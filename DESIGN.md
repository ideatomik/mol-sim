# MolSim — Design Document
_Last updated: v70.6 session_

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
2. + Lagging strand, base level: a single untethered polymerase synthesizes
   Okazaki fragments moving forward (same direction as the fork), then snaps
   back to meet the helicase and start the next fragment. No trombone loop,
   no replisome coupling. This is the simpler, commonly-taught first picture
   of discontinuous synthesis — confirmed against multiple educational
   sources (see Biological Model below) — and the layer immediately ahead
   on the roadmap.
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

### Transcription complexity layers
- RNA Polymerase, promoter recognition, mRNA strand synthesis
- Transcription errors (RNA Pol has no proofreading; ~1 error per 10⁴ bases)
- Redundancy concept: many mRNA copies buffer transcription errors

### Translation complexity layers
- Ribosome, tRNA, codons, polypeptide chain synthesis
- Error mechanics layered on top

---

## Biological Model

MolSim follows the **E. coli replication model** for accuracy and visual clarity.

### Key biological facts encoded in the simulation
- DNA Pol III can only synthesize 5'→3'
- The two template strands are antiparallel
- Leading strand: continuous synthesis in the direction of the fork
- Lagging strand: discontinuous synthesis (Okazaki fragments). DNA polymerase
  must move backward relative to the replication fork to synthesize each
  fragment, then return to start the next one closer to the fork — this is
  the base-complexity model (layer 2 above) before replisome coupling is
  introduced.
- With a single replisome, the lagging strand template loops back on itself
  so its polymerase can travel in the same direction as the fork while still
  synthesizing 5'→3' — this is the trombone loop model (layer 3), the
  highest complexity tier currently planned for the replication simulator
- Each Okazaki fragment requires an RNA primer (primase)
- Fragments are joined by DNA ligase after primer removal
- In the full replisome, both polymerases are held together via the tau (τ) body
- β-clamp (sliding clamp) on each strand increases polymerase processivity

### Didactic simplifications (intentional)
- Sequences are short (≤57 bases) for visual clarity
- Single-slot Okazaki fragments use a combined "5'-3'" marker
- Biological accuracy is didactic, not exhaustive
- The base-complexity lagging strand model (independent polymerase,
  back-and-forth motion) is presented as a real, simplified picture of
  discontinuous synthesis, not as a placeholder or approximation to be
  apologized for — multiple educational sources describe lagging-strand
  synthesis this way before introducing replisome coupling

---

## Architecture

### Current state (v70.6)
`helicase.gd` and `replication_manager.gd` are extracted and stable. `simulation.gd` is
a thin template manager + visual coordinator that owns no synthesis state.

**Phase 1 and Phase 2 are both complete** (see migration history below). The lagging
strand itself — Okazaki fragments, the trombone loop, primase, ligase — was fully
**removed** during a loop-mechanics rebuild attempt and is being rebuilt from a clean
slate, starting from the base complexity layer (independent polymerase, no loop) rather
than attempting the trombone loop directly.

```
simulation.gd  — Template Manager + visual coordinator
├── helicase.gd  — discrete slot stepping, phase state machine, signals (DONE ✓)
└── replication_manager.gd  — leading strand synthesis only; both polymerase
                               enzyme visuals; intro/resume animation API (DONE ✓)
                               Lagging strand: NOT YET BUILT (clean slate,
                               starting at base complexity)
```

### Helicase-anchored positioning (v70.6 refactor)

The replisome's positioning model was restructured so the **helicase is the
single source of truth** for where everything sits, rather than deriving
positions from the bottom template strand's literal resting y:

- `center_y` (export, `simulation.gd`, default `360.0`) — the vertical
  screen-center anchor. Replaces the old `straight_y`, which used to mean
  "the bottom template strand's y" and was overloaded as the layout anchor
  at the same time. `center_y` is now purely a layout constant; it does not
  literally correspond to any strand's position.
- `template_strand_y` (derived, `simulation.gd`) — `center_y + dna_ribbons_gap / 2.0`.
  This is what `straight_y` used to mean literally: the bottom template
  strand's resting y. The top template strand's bonded y is the mirror,
  `center_y - dna_ribbons_gap / 2.0`.
- `helicase_node.position` — the helicase sits at `(helicase_x, center_y)`,
  vertically centered between the two template strands by construction.
- `polymerase_x` (derived, `simulation.gd`) — both polymerases share this x:
  `helicase_x - polymerase_x_offset_slots * nucleotide_slot_spacing`.
  Replaces the old `factory_x` / fixed-pixel `gap_width`. The distance is now
  expressed in slot units (`polymerase_x_offset_slots`, export, default `4.0`)
  rather than an independent pixel constant, so it scales naturally with
  `nucleotide_slot_spacing`.
- `polymerase_y_lagging` / `polymerase_y_leading` (derived, `simulation.gd`) —
  `center_y + polymerase_y_offset` and `center_y - polymerase_y_offset`
  respectively. `polymerase_y_offset` (export, default `120.0`) replaces the
  old `new_bottom_template_offset` and is now understood as "the vertical
  distance each polymerase sits from the helicase's y (`center_y`)," not as
  an offset from the bottom template strand.
- Both `synthesis_circle` (lagging polymerase, scene node) and
  `top_polymerase` (leading polymerase, procedural node owned by
  `replication_manager.gd`) are positioned purely as
  `helicase_node.position + Vector2(∓polymerase_x_offset, ±polymerase_y_offset)`
  — there is no other source of truth for where they sit.
- The leading strand's render y was a known inconsistency, fixed in this
  session: it was sitting `dna_ribbons_gap / 2.0` from the top template's
  unzipped position (`new_top_template_y`) instead of a full `dna_ribbons_gap`,
  unlike every other paired-strand spacing in the simulation. `new_top_template_y`
  is now passed through `update(ctx)` / `render(ctx)` so `replication_manager.gd`
  computes the leading strand's y as `new_top_template_y - dna_ribbons_gap`,
  consistent with the bottom-template/lagging-strand spacing.
- All PLL diagonal/zigzag **debug visuals** (`debug_gap_line`,
  `debug_top_rail_line`, the yellow `PllDebugLines` zigzag, the
  `pll_slot_count` print diagnostics) were removed from `simulation.gd` —
  they served their purpose validating the PLL geometry math during the
  earlier loop-mechanics investigation and are no longer needed now that the
  rebuild is starting from base complexity rather than the loop directly.
  `pll_slot_count` itself remains as an export for when loop-complexity work
  resumes.

### replication_manager.gd migration — history

**Phase 1 ✓ DONE:** All synthesis state variables and spawning functions moved into
`replication_manager.gd`. simulation.gd calls `replication_manager.update(delta, ctx)`
and `scrub_rebuild(ctx)`, passing context. Data lives in the right place.

**Phase 2 ✓ DONE:** `helicase.gd` exposes real signals (`slot_reached`,
`phase_changed`) that `replication_manager.gd` connects to directly via
`connect_helicase()`/`_on_helicase_slot_reached()` (signal wiring exists in the
codebase already; currently unused while the lagging strand is being rebuilt, but the
pattern is proven and ready). Enzyme animation became method-based instead of
`simulation.gd` poking node properties: `replication_mgr.resume_enzymes()` and
`replication_mgr.run_intro(intro_x, fade_time, slide_time, tween)` are now the only
ways `simulation.gd` touches `synthesis_circle` / `top_polymerase`. `simulation.gd`
no longer references either enzyme node directly anywhere.

The originally-planned `okazaki_manager.gd` extraction did not happen as a literal
file move, because the Okazaki/lagging-strand logic it would have extracted was
removed entirely rather than carried forward. The signal-based, delegation-clean
architecture Phase 2 was meant to produce is in place regardless — `okazaki_manager.gd`
(or equivalent) will be designed fresh as lagging-strand complexity grows, using the
deterministic `slot_reached`-driven trigger pattern proven by the leading strand's own
position-based synthesis check as a reference for how clean a trigger can be.

### Target architecture
```
ComplexityManager (Node → autoload later)
│   @export toggles per feature (lagging_strand_loop, sliding_clamps, etc.)
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
│   ├── okazaki_manager.gd  (NEXT — base-complexity lagging strand:
│   │   independent polymerase, back-and-forth motion, no loop)
│   │   Fragment tracking, assignment, open/close logic.
│   │   Trombone loop geometry and slot positioning along the loop curve
│   │   is a LATER complexity tier, not part of the base build.
│   │
│   ├── primase.gd  (future)
│   └── ligase.gd  (future)
│
├── transcription_manager.gd  (future)
└── translation_manager.gd    (future)
```

### Key architectural rules
- **ThemeManager / ComplexityManager**: scene nodes, Inspector-editable, no autoload yet.
  Convert to autoload once export values settle.
- **nitrogen_base.gd**: ThemeManager-free, colors injected via `set_colors()` / `set_font()`
- `add_child()` before `set_colors()` / `set_font()` (so `_ready()` fires first)
- GDScript: no multiline `or` expressions (put on one line — parser bug)
- Every new enzyme/visual designed with an on/off switch, even before toggle UI exists
- **Signal connections**: always guard with `if not signal.is_connected(callable)`
  before connecting in functions called on re-initialization
- **No script reaches into another script's owned visual nodes.** `simulation.gd`
  never positions, fades, or queries `replication_mgr`'s enzymes directly — it calls
  methods on `replication_mgr` instead. This rule was tightened during the Phase 2
  cleanup after repeated regressions where `simulation.gd` quietly grew direct pokes
  into `replication_mgr.synthesis_circle` / `top_polymerase`.
- **The helicase is the single source of truth for replisome positioning.**
  Both polymerases derive their position purely from `helicase_node.position`
  plus a fixed offset (`polymerase_x_offset_slots`, `polymerase_y_offset`).
  No other script or formula should introduce an independent position source
  for either polymerase.
- **Complexity layers build upward, not sideways.** The lagging strand is
  being rebuilt starting from the simplest correct biological picture (base
  complexity, layer 2) rather than attempting the trombone loop (layer 3)
  directly. Each layer should be a clean, working, toggle-able state on its
  own before the next layer is added on top — this mirrors the project's
  core "modular complexity" principle and is meant to prevent the kind of
  repeated rebuild failures seen when loop mechanics were attempted before
  the deterministic foundation existed.

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
  completely first (state, render, scrub paths, signal connections) and confirm a
  clean, regression-free baseline before writing any new logic on top. Layering new
  logic over not-fully-removed old logic was the direct cause of the loop-mechanics
  rebuild's repeated failures.
- **Debug/diagnostic visuals are temporary by design.** Once a debug visual
  (e.g. the PLL diagonal/zigzag) has served its purpose validating a piece of
  math, remove it rather than leaving it in permanently — it isn't part of
  the simulation's didactic output and accumulates as clutter otherwise.

---

## Roadmap

### Immediate (v70.7) — Lagging strand, base complexity
- [ ] Independent lagging polymerase: synthesizes one slot per helicase step
      while moving forward (same direction as the fork), no loop, no replisome
      coupling
- [ ] When an Okazaki fragment reaches `pulse_nucleotide_count` slots, the
      polymerase "jumps" back to meet the helicase's current position and
      starts the next fragment
- [ ] Deterministic, helicase-step-driven slot queue and fragment
      assignment, following the same clean trigger pattern proven by the
      leading strand (position/step-based, no proximity detection)
- [ ] Boundary handling at the very start and end of the strand (fewer than
      a full fragment's worth of slots available)

### Near term — Lagging strand, trombone loop complexity
- [ ] Design the trombone loop curve and PLL (Pre-Loop Length) geometry as
      first-class `replication_manager.gd` logic (the PLL debug visuals
      removed this session validated the underlying math; the loop itself
      is a later complexity layer built on top of the base-level model above)
- [ ] Loop slot queue tied to helicase steps, sized by `pll_slot_count` +
      `pulse_nucleotide_count`
- [ ] Ligase joining Okazaki fragments + reveal whole-strand lagging markers
- [ ] RNA primers and primase enzyme

### Replisome visual
- [ ] Unified replisome structure (E. coli model):
  - τ (tau) body connecting helicase, leading polymerase, lagging polymerase, clamp loader
  - Replaces current separate synthesis circles
  - Designed as a single visual node, toggle-aware
  - Only meaningful once the trombone loop complexity layer exists, since the
    tau body's role is specifically to couple both polymerases together
- [ ] Sliding clamps (β-clamp): one per Okazaki fragment + one on leading strand

### Medium term
- [ ] `okazaki_manager.gd` extraction once the lagging strand above is stable
- [ ] ComplexityManager node (toggles per feature, Inspector-editable first)
- [ ] UI controller rebuild
- [ ] Themes: Dark, Light, Dark Low-Info, Light Low-Info

### Long term
- [ ] Transcription phase
- [ ] Error mechanics (proofreading on replication, error rates on transcription)
- [ ] Translation phase
- [ ] DNA sequence input UI

---

## Pinned Issues

- **Scrub edge case (lagging strand, historical)**: occasional escaped synthesized
  base just left of lagging polymerase, present in the old proximity/transfer state
  machine. Moot now that the lagging strand has been removed entirely; flagged here
  so the rebuilt version is designed to avoid the same class of bug (the deterministic
  step-count model should make this structurally impossible rather than "improved").

---

## Scene Structure (v70.6)

```
root (Node2D, simulation.gd)
├── Camera2D
├── CanvasLayer → ColorRect
├── RailPath (Path2D)                    — bottom template strand
├── TopRailPath (Path2D)                 — top template strand
├── TemplateStrandOriginalTrack (Line2D)
├── SynthesisCircle (Node2D)             — lagging-position polymerase visual,
│                                           driven entirely by replication_mgr
├── BackboneLine (Line2D)
├── HydrogenBondsContainer (Node2D)
├── TemplateHydrogenBondsContainer (Node2D)
├── ThemeManager (Node, %ThemeManager)
└── UI (CanvasLayer)
    ├── SequenceLoaderPopup
    └── PlayerUI

helicase.gd — added as child of simulation.gd at runtime via initialize_simulation()
replication_manager.gd — added as child of simulation.gd at runtime via initialize_simulation()
```

Removed from the scene during the lagging-strand cleanup (dead proximity-detection
and unused debug/baseline nodes): `NewStrandLine`, `SynthesisArea` +
`SynthesisCollisionShape` (children of `SynthesisCircle`), `TemplateStrandNewTrack`,
`TopTemplateStrandNewTrack`. `top_polymerase` is not a scene node — it's created
procedurally by `replication_manager.gd` in `setup_backbones()`.

No further scene node removals in this session — the PLL debug visuals removed
were runtime-created `Line2D`/`Node2D` instances in `simulation.gd`, not scene
nodes in `simulation.tscn`.
