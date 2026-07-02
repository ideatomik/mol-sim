# MolSim — Design Document
_Last updated: v70.7 session_

---

## What MolSim Is

MolSim is a molecular biology education platform built in Godot 4.x (GDScript).
It is not just a DNA replication simulator — replication is Phase 1 of a broader
simulation covering the central dogma: **DNA replication → Transcription → Translation**.

The core design principle is **modular complexity**: a single simulator, one codebase,
where educators set the complexity dial to match their audience. High school, undergraduate,
or general public — same product, different feature toggles.

---

## Complexity System

Complexity toggles are **first-class citizens** in the architecture, not afterthoughts.
Every new feature must be built toggle-aware from the start, even before the toggle UI exists.
A feature that can't be hidden is technical debt.

### Replication complexity layers (in order)
1. Leading strand only — core concept of semiconservative replication (DONE ✓)
2. + Lagging strand, base level: an independent polymerase (not attached to the
   replisome at this tier) synthesizes Okazaki fragments as fixed-size tiles —
   `[0, F)`, `[F, 2F)`, `[2F, 3F)`, … where `F = okazaki_fragment_size` — firing
   right-to-left *within* each tile (newest slot first, oldest last), one slot
   per helicase step once a one-time startup backlog (`okazaki_fragment_size +
   pll_slot_count` exposed slots) has built up. After startup, firing is fully
   continuous — no idle gaps between fragments (**DONE ✓ as of v70.7**, see
   Architecture below for the implementation).
3. + Trombone loop model: the lagging polymerase stays physically coupled to
   the replisome via the tau (τ) body, looping the template strand through
   itself so both polymerases can move in the same direction together.
4. + Full replisome (clamp loader, β-clamps on both strands, primase as a
   distinct visual/enzyme rather than implicit)
5. + RNA primers and primer removal as explicit steps
6. + Proofreading (DNA Pol III 3'→5' exonuclease)
7. + Mismatch Repair (MutS/MutL/MutH complex, post-replication)

The trombone loop (old layer 3 in earlier drafts of this document) is now
understood as the **maximum complexity tier currently in scope** for the
replication simulator, not a prerequisite for showing Okazaki fragments at
all — the base-level back-and-forth model is biologically valid on its own
and is the right starting point before adding replisome coupling.

### The telomere gap is a toggle, not a fixed behavior

At **base complexity**, the lagging polymerase is deliberately *not* shown as
attached to the replisome, so there's no in-simulation reason for it to stop
short of the strand's end — once the helicase finishes, the lagging polymerase
independently keeps firing (on its own clock, no longer helicase-driven) until
every slot is synthesized, including a genuinely short final fragment sized to
whatever remains. **No gap is shown at base complexity.**

The gap itself — the real end-replication problem — is reserved behind
`lagging_gap_enabled` (export, `replication_manager.gd`, default `false`),
switched on when the **telomerase tier** is introduced. With it enabled, an
incomplete trailing fragment at `DONE` is discarded rather than caught up,
and the leftover stretch is recorded as `lagging_telomere_gap`. Both code
paths already exist side by side (see Architecture below) — enabling
telomerase complexity is a toggle flip, not new plumbing.

The **primase tier**, still ahead, will further tune this gap mechanic (e.g.
primer placement/removal governing exactly where and how the gap forms) —
`lagging_gap_enabled` and the discard/catch-up split are built with this in
mind, so that tuning should land as refinement on top of the existing toggle
rather than a rework.

---

## Biological Model

MolSim follows the **E. coli replication model** for accuracy and visual clarity.

### Key biological facts encoded in the simulation
- DNA Pol III can only synthesize 5'→3'
- The two template strands are antiparallel
- Leading strand: continuous synthesis in the direction of the fork
- Lagging strand: discontinuous synthesis (Okazaki fragments). At base
  complexity, the lagging polymerase is independent of the replisome — it
  fires fixed-size fragments right-to-left as backlog builds up, then
  independently finishes the strand once the fork itself is done. This is
  the base-complexity model (layer 2 above) before replisome coupling is
  introduced.
- With a single replisome, the lagging strand template loops back on itself
  so its polymerase can travel in the same direction as the fork while still
  synthesizing 5'→3' — this is the trombone loop model (layer 3), the
  highest complexity tier currently planned for the replication simulator
- Each Okazaki fragment requires an RNA primer (primase) — not yet modeled;
  the real end-replication gap this produces is deferred to the telomerase
  tier (see Complexity System above)
- Fragments are joined by DNA ligase after primer removal
- In the full replisome, both polymerases are held together via the tau (τ) body
- β-clamp (sliding clamp) on each strand increases polymerase processivity

### Didactic simplifications (intentional)
- Sequences are short (≤57 bases) for visual clarity, with a computed minimum
  floor (see Architecture) ensuring at least one full Okazaki fragment can fire
- Single-slot Okazaki fragments use a combined "5'-3'" marker
- Biological accuracy is didactic, not exhaustive
- The base-complexity lagging strand model (independent polymerase,
  fixed-tile fragments, no telomere gap) is presented as a real, simplified
  picture of discontinuous synthesis, not as a placeholder or approximation
  to be apologized for — multiple educational sources describe lagging-strand
  synthesis this way before introducing replisome coupling and the
  end-replication problem

---

## Architecture

### Current state (v70.7)
`helicase.gd` and `replication_manager.gd` are extracted and stable. `simulation.gd` is
a thin template manager + visual coordinator that owns no synthesis state.

**The lagging strand — base complexity — is fully implemented**, rebuilt from a
clean slate after the earlier loop-mechanics attempt was removed. Leading
strand synthesis, enzyme visuals, and intro/resume animation remain unchanged
from v70.6.

```
simulation.gd  — Template Manager + visual coordinator
├── helicase.gd  — discrete slot stepping, phase state machine, signals (DONE ✓)
└── replication_manager.gd
    ├── leading strand synthesis — unchanged from v70.6 (DONE ✓)
    └── lagging strand synthesis — base complexity (DONE ✓ as of v70.7)
```

### Lagging strand mechanism (v70.7)

- **Trigger**: driven by `helicase.slot_reached`, same deterministic pattern
  the leading strand already proved out — no proximity detection, no replay
  dependency. `connect_helicase()` wires `slot_reached` and `phase_changed`
  from `replication_manager.gd` directly.
- **Startup delay**: firing begins once `okazaki_fragment_size + pll_slot_count`
  slots have been exposed (raw helicase step count — the lagging polymerase is
  *not* replisome-attached at this tier, so there's no positional offset to
  subtract, unlike the leading strand's `polymerase_x_offset_slots`-based
  positioning).
- **Fragment tiling**: fixed, deterministic tiles `[0,F), [F,2F), …` where
  `F = okazaki_fragment_size`. Independent of `pll_slot_count`, which only
  governs the one-time startup delay — not fragment boundaries.
- **Firing order**: within each tile, right-to-left (highest index first),
  matching 5'→3' synthesis direction on the bottom template. Stored via
  `slots.push_front()` so the array stays ascending for existing
  backbone/marker/rendering code, which assumes low-to-high order.
- **Position**: `lagging_polymerase` (the renamed `synthesis_circle` scene
  node) is positioned independently — snapped to each newly-fired slot's x —
  *not* derived from `helicase_x` like `leading_polymerase` still is. This is
  a deliberate, currently-accepted exception to the "helicase is the single
  source of truth for replisome positioning" rule below, justified by the
  lagging polymerase not being shown as replisome-attached until the
  trombone-loop tier.
- **Post-helicase catch-up (base complexity only)**: once the helicase reaches
  `DONE`, a dedicated `Timer` (`lagging_catchup_timer`, paced by
  `lagging_catchup_step_duration`) takes over firing — finishing whatever
  fragment was in progress, then opening one final, genuinely short fragment
  (`min(okazaki_fragment_size, remaining)`) to close out the strand
  completely. Only once this finishes does the enzyme fade sequence run.
- **Enzyme fade sequencing**: `_lagging_fade_enzyme_scene()` (helicase,
  leading polymerase, lagging polymerase) fires only *after* the lagging
  strand's own end-state — catch-up completion, or the telomerase-tier
  discard-fade — has fully settled. It is no longer tied directly to
  `helicase.Phase.DONE`, since that no longer means "everything is finished"
  once lagging synthesis is decoupled from the helicase's own timeline.
- **Scrub determinism**: `_lagging_scrub_rebuild()` reproduces both branches
  deterministically for an arbitrary scrub target — the fixed-tile math for
  mid-run scrubbing, and either full catch-up (`lagging_gap_enabled = false`)
  or the discard-to-last-fragment-boundary (`lagging_gap_enabled = true`) for
  scrubbing to `DONE` — so scrubbing to any point always matches what a live
  play-through would have produced at that point.

### Minimum sequence length

`min_sequence_length = polymerase_x_offset_slots + okazaki_fragment_size +
pll_slot_count + 1` (export, `simulation.gd`) — ensures every sequence has
room for the leading strand's own offset plus at least one full Okazaki
fragment plus the lagging startup buffer. Sequences shorter than this are
padded with random bases at load time. `telomere_primer_footprint`, an
earlier fixed-floor approach to guaranteeing a visible gap, was removed once
the gap became a toggle (`lagging_gap_enabled`) rather than an always-on
minimum.

### Helicase-anchored positioning (v70.6 refactor, still current for leading strand + helicase)

The replisome's positioning model was restructured so the **helicase is the
single source of truth** for where everything sits, rather than deriving
positions from the bottom template strand's literal resting y:

- `center_y` (export, `simulation.gd`, default `360.0`) — the vertical
  screen-center anchor. Purely a layout constant; does not literally
  correspond to any strand's position.
- `template_strand_y` (derived, `simulation.gd`) — `center_y + dna_ribbons_gap / 2.0`.
  The bottom template strand's resting y. The top template strand's bonded y
  is the mirror, `center_y - dna_ribbons_gap / 2.0`.
- `helicase_node.position` — sits at `(helicase_x, center_y)`, vertically
  centered between the two template strands by construction.
- `polymerase_x` (derived, `simulation.gd`) — `helicase_x -
  polymerase_x_offset_slots * nucleotide_slot_spacing`. Used by the **leading**
  polymerase and by the lagging strand's *exposure* math (how far behind the
  helicase a slot becomes eligible for synthesis at all) — but, as of v70.7,
  no longer used to position the **lagging** polymerase visual itself (see
  Lagging strand mechanism above).
- `polymerase_y_lagging` / `polymerase_y_leading` (derived, `simulation.gd`) —
  `center_y + polymerase_y_offset` and `center_y - polymerase_y_offset`
  respectively.
- `new_bottom_template_y` / `new_top_template_y` (derived, `simulation.gd`) —
  each template strand's fully-unzipped resting y, mirrored. Note these are
  *not* identical to `polymerase_y_lagging`/`polymerase_y_leading` (they
  include an additional `dna_ribbons_gap / 2.0` term) — a past source of a
  wobble-gating bug (see Pinned Issues history) worth remembering when
  touching either value.

### Target architecture
```
ComplexityManager (Node → autoload later)
│   @export toggles per feature (lagging_gap_enabled, sliding_clamps, etc.)
│   is_enabled("feature_name") -> bool
│
ThemeManager (Node → autoload later)
│   @export visual parameters. Same pattern as ComplexityManager.
│
simulation.gd  — Template Manager (thin scene coordinator)
│   Owns original DNA strands, rails, sequence resource, geometry constants.
│   Exposes slot positions, bases, and geometry to process managers.
│   Does NOT own any synthesized products.
│
├── replication_manager.gd  — thin coordinator for replication
│   Owns shared per-slot state arrays. Delegates to sub-managers.
│   │
│   ├── helicase.gd  ✓ DONE
│   │   Discrete slot-by-slot stepping. Owns phase state machine.
│   │   Emits: slot_reached(index), phase_changed(new_phase).
│   │
│   ├── lagging strand (base complexity)  ✓ DONE (v70.7, inline in
│   │   replication_manager.gd — not yet extracted to okazaki_manager.gd)
│   │   Fragment tiling, right-to-left firing, catch-up mechanism, scrub
│   │   determinism, gap toggle reserved for telomerase.
│   │
│   ├── primase.gd  (future — will tune gap mechanics further)
│   └── ligase.gd  (future)
│
├── transcription_manager.gd  (future)
└── translation_manager.gd    (future)
```

### Key architectural rules
- **ThemeManager / ComplexityManager**: scene nodes, Inspector-editable, no autoload yet.
  Convert to autoload once export values settle.
- **nitrogen_base.gd**: ThemeManager-free, colors/font/radius injected via
  `set_colors()` / `set_font()` / `set_radius()`
- `add_child()` before `set_colors()` / `set_font()` / `set_radius()` (so `_ready()` fires first)
- GDScript: no multiline `or` expressions (put on one line — parser bug)
- Every new enzyme/visual designed with an on/off switch, even before toggle UI exists
- **Signal connections**: always guard with `if not signal.is_connected(callable)`
  before connecting in functions called on re-initialization
- **No script reaches into another script's owned visual nodes.** `simulation.gd`
  never positions, fades, or queries `replication_mgr`'s enzymes directly — it calls
  methods on `replication_mgr` instead.
- **The helicase is the single source of truth for replisome positioning** —
  with one deliberate, currently-accepted exception: the **lagging polymerase
  at base complexity**, which is independently positioned rather than
  helicase-relative, because it isn't shown as replisome-attached until the
  trombone-loop tier. When that tier lands, the lagging polymerase should
  return to helicase-relative positioning (mirroring the leading polymerase),
  and this exception should be removed from this rule rather than expanded.
- **Complexity layers build upward, not sideways.** Each layer should be a
  clean, working, toggle-able state on its own before the next layer is added
  on top.
- **Toggle-gate new mechanics instead of replacing old ones.** The telomere
  gap mechanic (discard-at-DONE, `lagging_telomere_gap`) was fully built,
  then gated behind `lagging_gap_enabled` rather than deleted when base
  complexity turned out not to need it — it's reserved for the telomerase
  tier. This is the intended pattern for future complexity-tier work: build
  the toggle seam, don't throw away validated code paths.

---

## Development Conventions

- **Architecture-first**: discuss design before writing any code
- **Strict scope discipline**: do not make unrequested changes
- **Version discipline**: commit stable versions before major changes; revert when regressions appear
- **Location anchors over line numbers**: use surrounding code snippets as edit anchors
- **Debug prints stay** until the feature they guard is confirmed stable
- **True current version**: the uploaded file is always ground truth, not earlier pastes
- **When combining fixes**: always diff the two versions, identify what changed,
  apply only the additive fix to the known-good base — never rewrite from memory
- **When rebuilding a subsystem from scratch**: remove the old implementation
  completely first and confirm a clean, regression-free baseline before writing
  new logic on top.
- **Debug/diagnostic visuals are temporary by design** — remove once they've
  served their purpose validating a piece of math.
- **Trace the exact math with small numbers before trusting an assumption**
  about emergent behavior (e.g. "does a gap form," "does firing ever idle") —
  several v70.7 design decisions (removing `telomere_primer_footprint`, the
  fixed-tile fragment model, the catch-up mechanism) only became clear after
  hand-tracing concrete step-by-step examples, not from reasoning about the
  formulas alone.

---

## Roadmap

### Immediate — Lagging polymerase animation
- [ ] Tween the lagging polymerase's movement between fired slots (currently
      an instant snap per slot) — snap-first was intentional as a working
      baseline; smoothing it out is the next visual pass
- [ ] Investigate remaining minor scrub-related issues (not yet fully
      diagnosed — flagged during v70.7 testing, not blocking)

### Near term — Telomerase tier
- [ ] Flip `lagging_gap_enabled` on for this tier; verify the
      already-built discard/gap-recording path (validated during v70.7
      development before catch-up became the base-complexity default)
- [ ] Design telomerase's own visual (extends the gap, doesn't just leave it)

### Near term — Primase tier
- [ ] RNA primers as explicit, visible objects preceding each fragment
- [ ] Primer removal step, tying into (and likely refining) the gap mechanic
      established at the telomerase tier

### Near term — Trombone loop complexity
- [ ] Design the trombone loop curve and PLL (Pre-Loop Length) geometry as
      first-class `replication_manager.gd` logic
- [ ] Return the lagging polymerase to helicase-relative positioning
      (mirroring the leading polymerase), removing the base-complexity
      exception noted in Key Architectural Rules above
- [ ] Loop slot queue tied to helicase steps, sized by `pll_slot_count`
- [ ] Ligase joining Okazaki fragments + reveal whole-strand lagging markers

### Replisome visual
- [ ] Unified replisome structure (E. coli model): τ (tau) body connecting
      helicase, leading polymerase, lagging polymerase, clamp loader.
      Only meaningful once the trombone loop complexity layer exists.
- [ ] Sliding clamps (β-clamp): one per Okazaki fragment + one on leading strand

### Medium term
- [ ] `okazaki_manager.gd` extraction — lagging-strand logic currently lives
      inline in `replication_manager.gd`; extraction was deferred until the
      base-complexity model was proven stable, which it now is (v70.7)
- [ ] ComplexityManager node (toggles per feature, Inspector-editable first)
- [ ] UI controller rebuild
- [ ] Themes: Dark, Light, Dark Low-Info, Light Low-Info (wobble already has
      a `wobble_enabled` ThemeManager toggle ready for this)

### Long term
- [ ] Transcription phase
- [ ] Error mechanics (proofreading on replication, error rates on transcription)
- [ ] Translation phase
- [ ] DNA sequence input UI

---

## Pinned Issues

- **Minor scrub issues (v70.7, unconfirmed specifics)**: flagged during
  testing after the lagging strand's scrub-rebuild fixes landed; not yet
  diagnosed in detail. Not blocking further work, but should be revisited
  before the trombone-loop tier adds more scrub complexity on top.
- **Wobble-gating value mismatch (v70.7, resolved)**: the bottom template's
  wobble gating compared its settled position against `polymerase_y_lagging`
  instead of the value it actually settles to, `new_bottom_template_y` — the
  two differ by `dna_ribbons_gap / 2.0`. Fixed; noted here since the two
  "lagging y" values look interchangeable but aren't, and the same confusion
  could recur when touching related geometry.
- **Scrub edge case (lagging strand, historical, pre-v70.7 rebuild)**:
  occasional escaped synthesized base during scrub, present in the old
  proximity/transfer state machine. Moot — that state machine no longer
  exists; the v70.7 deterministic rebuild was designed specifically to avoid
  this class of bug structurally rather than "improve" on it.

---

## Scene Structure (v70.7)

```
root (Node2D, simulation.gd)
├── Camera2D
├── CanvasLayer → ColorRect
├── RailPath (Path2D)                    — bottom template strand
├── TopRailPath (Path2D)                 — top template strand
├── TemplateStrandOriginalTrack (Line2D)
├── SynthesisCircle (Node2D)             — lagging polymerase visual,
│                                           driven entirely by replication_mgr
│                                           (referenced internally as
│                                           lagging_polymerase)
├── BackboneLine (Line2D)
├── HydrogenBondsContainer (Node2D)
├── TemplateHydrogenBondsContainer (Node2D)
├── ThemeManager (Node, %ThemeManager)
└── UI (CanvasLayer)
    ├── SequenceLoaderPopup
    └── PlayerUI

helicase.gd — added as child of simulation.gd at runtime via initialize_simulation()
replication_manager.gd — added as child of simulation.gd at runtime via initialize_simulation()
lagging_catchup_timer (Timer) — added as child of simulation.gd at runtime by
  replication_manager.gd, lazily on first use, on the base-complexity catch-up path
```

`leading_polymerase` is not a scene node — it's created procedurally by
`replication_manager.gd` in `setup_backbones()`, same as before v70.7.
