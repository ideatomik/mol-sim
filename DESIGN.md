# MolSim — Design Document
_Last updated: v75 — zoom system extensions: per-enzyme drag-to-scrub, free camera mode (mouse pan/zoom), nucleotide field/halo tuning_

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
   continuous — no idle gaps between fragments. **Fully DONE ✓ as of the v70
   wrap** — mechanism, scrub determinism, and a real slot-by-slot animated
   polymerase are all complete and QA'd (see Architecture below).
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
`lagging_gap_enabled` (export, `simulation.gd`, default `false`), switched on
when the **telomerase tier** is introduced. With it enabled, an incomplete
trailing fragment at `DONE` is discarded rather than caught up, and the
leftover stretch is recorded as `lagging_telomere_gap`. Both code paths
already exist side by side (see Architecture below) — enabling telomerase
complexity is a toggle flip, not new plumbing.

The **primase tier**, still ahead, will further tune this gap mechanic (e.g.
primer placement/removal governing exactly where and how the gap forms) —
`lagging_gap_enabled` and the discard/catch-up split are built with this in
mind, so that tuning should land as refinement on top of the existing toggle
rather than a rework.

### Backbone continuity (nicks) is a toggle too

At **base complexity**, no ligase is modeled, so there's no in-simulation
reason for a nick to remain visible between two adjacent, already-synthesized
Okazaki fragments — the backbone should read as one continuous line, exactly
like the leading strand's. Once a fragment completes, it merges into that
continuous line; only the very first fragment's 5' end and the current
last-complete fragment's 3' end keep markers, since an internal boundary
between two already-joined fragments isn't meaningful anymore.

This is governed by `ligase_enabled` (export, `simulation.gd`, default
`false`), mirroring `lagging_gap_enabled`'s pattern exactly. When `true`
(reserved for the **ligase tier**), rendering reverts to per-fragment
backbones with visibly separate segments and nicks at every boundary —
because at that tier, a fragment genuinely *should* stay visually distinct
until the ligase enzyme visits and seals it. Both rendering paths already
exist side by side in `replication_manager.gd`'s `_lagging_render()` — this
is another toggle flip, not new plumbing, when the ligase tier lands.

### Backbone color as a teaching signal (v73)

`template_backbone_color` (ThemeManager) was added in v73 to visually
distinguish the original template DNA backbone from newly-synthesized strand
backbone (`backbone_color`, unchanged) — a classroom aid for "which strand is
the original" that a single shared backbone color couldn't convey. Applied to
`backbone_line` and `top_strand_backbone_line` in `simulation.gd` only;
`replication_manager.gd`'s `leading_backbone_line`, `lagging_backbone_line`,
and per-fragment Okazaki lines are untouched and keep reading `backbone_color`.

**The reusable part for transcription is the *pattern*, not the *color*:**
one dedicated ThemeManager color field per distinct strand role, applied at
the `Line2D` level. RNA-vs-DNA (a backbone chemistry distinction) is not the
same axis as replication's template-vs-new-strand distinction, so
transcription's future mRNA strand should get its own field rather than
inherit `template_backbone_color` — not designed further until
transcription's own design pass begins, per SHARED_BASE_SEAM.md's caution
against front-loading sibling-process detail.

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
- Fragments are joined by DNA ligase after primer removal — until modeled,
  the backbone is shown continuous (see Backbone continuity toggle above)
- In the full replisome, both polymerases are held together via the tau (τ) body
- β-clamp (sliding clamp) on each strand increases polymerase processivity

### Didactic simplifications (intentional)
- Sequences can be up to 300 bases (`DnaSequenceResource.MAX_LENGTH`, raised
  from 57 in v74 — see Long-Sequence Support below), with a computed minimum
  floor (see Architecture) ensuring at least one full Okazaki fragment can
  fire. 57 is no longer a hard ceiling — it's now the shared "legible
  reference length" the zoom system and SequenceLabel both key off of (see
  Long-Sequence Support)
- Single-slot Okazaki fragments use a combined "5'-3'" marker
- Biological accuracy is didactic, not exhaustive
- The base-complexity lagging strand model (independent polymerase,
  fixed-tile fragments, no telomere gap, continuous joined-looking backbone)
  is presented as a real, simplified picture of discontinuous synthesis, not
  as a placeholder or approximation to be apologized for — multiple
  educational sources describe lagging-strand synthesis this way before
  introducing replisome coupling, primase, and the end-replication problem

---

## Architecture

### Current state (v70 wrap)
`helicase.gd` and `replication_manager.gd` are extracted and stable. `simulation.gd` is
a thin template manager + visual coordinator that owns no synthesis state.

**The lagging strand — base complexity — is fully implemented, animated, and QA'd**,
rebuilt from a clean slate after the earlier loop-mechanics attempt was removed.
Leading strand synthesis and intro/resume animation remain unchanged from v70.6.

```
simulation.gd  — Template Manager + visual coordinator
├── helicase.gd  — discrete slot stepping, phase state machine, signals (DONE ✓)
└── replication_manager.gd
    ├── leading strand synthesis — unchanged from v70.6 (DONE ✓)
    └── lagging strand synthesis — base complexity, animated, QA'd (DONE ✓)
```

### Lagging strand mechanism

- **Trigger**: driven by `helicase.slot_reached`, same deterministic pattern
  the leading strand already proved out — no proximity detection, no replay
  dependency. `connect_helicase()` wires `slot_reached` and `phase_changed`
  from `replication_manager.gd` directly.
- **Startup delay**: firing begins once `okazaki_fragment_size + pll_slot_count`
  raw helicase steps have occurred — the lagging polymerase is *not*
  replisome-attached at this tier, so there's no positional offset to subtract,
  unlike the leading strand's `polymerase_x_offset_slots`-based positioning.
- **Fragment tiling**: fixed, deterministic tiles `[0,F), [F,2F), …` where
  `F = okazaki_fragment_size`. Independent of `pll_slot_count`, which only
  governs the one-time startup delay — not fragment boundaries. The *final*
  tile may be genuinely shorter than `F` slots if `num_slots` isn't an exact
  multiple of `F` — this must be accounted for in **every** place that
  computes a tile's slot range, not just the "fully done" case (see Pinned
  Issues history: a real bug shipped once from a formula that assumed every
  tile was full-size).
- **Firing order**: within each tile, right-to-left (highest index first),
  matching 5'→3' synthesis direction on the bottom template. Stored via
  `slots.push_front()` so the array stays ascending for backbone/marker/
  rendering code, which assumes low-to-high order.
- **Position**: `lagging_polymerase` is positioned independently — snapped to
  each newly-fired slot's x — *not* derived from `helicase_x` like
  `leading_polymerase` still is. This is a deliberate, currently-accepted
  exception to the "helicase is the single source of truth for replisome
  positioning" rule below, justified by the lagging polymerase not being
  shown as replisome-attached until the trombone-loop tier.
- **Post-helicase catch-up (base complexity only)**: once the helicase reaches
  `DONE`, a dedicated `Timer` (`lagging_catchup_timer`, paced by
  `lagging_catchup_step_duration`) takes over firing — finishing whatever
  fragment was in progress, then opening one final, genuinely short fragment
  (`min(okazaki_fragment_size, remaining)`) to close out the strand
  completely. Only once this finishes does the enzyme fade sequence run.
- **Enzyme fade sequencing**: `_lagging_fade_enzyme_scene()` (helicase,
  leading polymerase, lagging polymerase) fires only *after* the lagging
  strand's own end-state — catch-up completion, or the telomerase-tier
  discard-fade — has fully settled, including animating the discarded
  fragment's bases/bonds out rather than freeing them instantly. It is no
  longer tied directly to `helicase.Phase.DONE`, since that no longer means
  "everything is finished" once lagging synthesis is decoupled from the
  helicase's own timeline.

### Lagging polymerase animation

The leading polymerase's smooth slot-to-slot motion isn't its own animation
system — it's a side effect of always being defined as
`helicase_x - constant_offset`, and `helicase_x` is already smoothly eased
between slots by `helicase.gd`'s own `step_t`/`get_eased_step_t()` (cubic
ease-out). The lagging polymerase, being deliberately decoupled from the
helicase at base complexity, doesn't get this for free and needs its own
tween.

`_lagging_fire_step(duration: float)` — the single call site for every slot
fired, whether live or during catch-up — tweens `lagging_polymerase.position`
to the new slot's x over `duration`, using `Tween.TRANS_CUBIC` /
`Tween.EASE_OUT` to deliberately match the helicase's own easing curve.
`duration` is supplied by the caller: `helicase_mgr.step_duration` (already
dynamic — reflects speed multiplier and finishing acceleration) for live
firing, `lagging_catchup_step_duration` for catch-up firing. Because
`_lagging_fire_step()` is the *only* place position changes during live/
catch-up play, a fragment's first slot (the "jump back" to start the next
fragment) goes through the identical code path as any other slot — same
duration, just a bigger `x` delta — so no special-casing was needed for the
fragment-boundary jump.

Scrub is always an instant snap, never animated, matching how every other
scrub-driven value in the simulation behaves. Any in-flight
`lagging_polymerase_tween` is explicitly `.kill()`ed immediately before a
scrub-driven position snap (both in `scrub_rebuild()`'s dispatcher and in
`_lagging_reset()`), so a leftover animation from an interrupted live/catch-up
glide can never silently overwrite a scrub jump a frame later.

### Scrub determinism — hard-won lessons

`_lagging_scrub_rebuild()` reproduces the *visual* fragment/base state
deterministically for an arbitrary scrub target. But base complexity's live
trigger (`_on_helicase_slot_reached()` → `_lagging_fire_step()`) depends on
its **own** separate counters — `lagging_total_consumed` (gates whether
firing continues at all) and `lagging_batch_cursor` (which exact slot fires
next). Early versions of the scrub rebuild only synced the *visual* fragment
data and left these two counters stale — which worked fine as long as you
never scrubbed and then resumed live play, but silently broke resuming after
any stop/scrub: `lagging_total_consumed` stuck at a prior run's final value
made the live trigger's own `>= num_slots` guard permanently short-circuit
(no lagging synthesis ever happened again), and a stale `lagging_batch_cursor`
caused a *reopened* fragment to graft an old run's leftover slot onto the
newly-rebuilt one (`slots=[28, 29, 2, 3, 4, 5]` — two unrelated ranges
stitched together). **Both are now fixed**: `_lagging_scrub_rebuild()`
explicitly resyncs `lagging_total_consumed = total_consumed`, and derives
`lagging_batch_cursor = lagging_current_fragment.slots[0] - 1` whenever a
partial fragment exists. The general lesson, worth remembering for any future
live-trigger state: **scrub must resync every variable the live trigger
reads, not just the ones driving what's on screen** — visual correctness and
live-trigger correctness are two different invariants that can silently
diverge.

**Catch-up-during-scrub**: since catch-up is deterministic (fires exactly one
slot per known interval, in a fixed order), the scrub *index* space itself
was extended rather than inventing a parallel wall-clock-based rebuild path.
`simulation.gd`'s `get_max_scrub_index()` returns `num_slots - 1 +
catchup_needed` (`catchup_needed` from
`replication_manager.get_lagging_catchup_steps_needed()`), and
`scrub_to_nucleotide_index()` routes any index past `num_slots - 1` to a new
`scrub_to_lagging_catchup(catchup_step)`, which threads `catchup_step` through
`scrub_rebuild()`'s `ctx` as `lagging_catchup_step`. `_lagging_scrub_rebuild()`
treats catch-up steps as strictly additive on top of the "natural" tiling
point (`attempted_consumed`) computed at the helicase's own final position —
reaching `DONE` no longer *implies* full completion for either live play or
scrub; both require the explicit extra steps. This currently only extends
arrow-key stepping (`scrub_to_nucleotide_index()`) — the slider widget's own
`max_value` is intentionally left at the old ceiling (`total_bases`) until a
future UI pass; dragging the slider to its current max still lands on the
"natural" point, not full catch-up.

### Minimum sequence length

`min_sequence_length = polymerase_x_offset_slots + okazaki_fragment_size +
pll_slot_count + 1` (export, `simulation.gd`) — ensures every sequence has
room for the leading strand's own offset plus at least one full Okazaki
fragment plus the lagging startup buffer. Sequences shorter than this are
padded with random bases at load time.

### Nitrogen base rendering

`nitrogen_base.gd`'s circle is drawn via `_draw()` + `draw_circle(...,
antialiased=true)` rather than a manually-constructed low-segment `Polygon2D`
fan. A fixed-vertex polygon stays visibly faceted regardless of project-wide
MSAA settings — anti-aliasing smooths *pixel edges* of whatever shape exists,
it doesn't make a 24-gon rounder. Godot's `draw_circle` antialiased flag uses
a dedicated smoothing technique instead, giving genuinely round circles at
any radius with no extra assets. `body_fill_color` (plain `Color` var) plus
`queue_redraw()` replace the old `Polygon2D`-mutation pattern in
`set_colors()` / `set_radius()` / `set_body_color()` — same call signatures,
so no call site elsewhere needed to change.

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
  polymerase and by the lagging strand's *exposure* math — but not used to
  position the **lagging** polymerase visual itself (see Lagging strand
  mechanism above).
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
│   @export toggles per feature (lagging_gap_enabled, ligase_enabled, etc.)
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
│   ├── lagging strand (base complexity)  ✓ DONE — mechanism, scrub
│   │   determinism, animation, all QA'd (inline in replication_manager.gd —
│   │   not yet extracted to okazaki_manager.gd)
│   │
│   ├── primase.gd  (future — will tune gap mechanics further)
│   └── ligase.gd  (future — will flip ligase_enabled on)
│
├── transcription_manager.gd  (future)
└── translation_manager.gd    (future)
```

### Key architectural rules
- **ThemeManager / ComplexityManager**: scene nodes, Inspector-editable, no autoload yet.
  Convert to autoload once export values settle.
- **nitrogen_base.gd**: ThemeManager-free, colors/font/radius injected via
  `set_colors()` / `set_font()` / `set_radius()`; circle drawn via
  `draw_circle(antialiased=true)`, not a manual `Polygon2D` fan.
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
- **Scrub is always instant; live/catch-up firing is always animated.** Any
  code path that can run during a scrub must snap, and must kill any
  in-flight tween first — animation only belongs to the live trigger and the
  catch-up timer.
- **Scrub must resync every variable the live trigger depends on, not just
  what's rendered.** A rebuild that only fixes the visuals but leaves a
  live-trigger counter stale will look correct immediately after scrubbing
  and then fail silently the next time play resumes — this exact class of bug
  has shipped twice (`lagging_total_consumed`, `lagging_batch_cursor`).
- **Complexity layers build upward, not sideways.** Each layer should be a
  clean, working, toggle-able state on its own before the next layer is added
  on top.
- **Toggle-gate new mechanics instead of replacing old ones.** The telomere
  gap mechanic and the per-fragment nicked-backbone rendering were both fully
  built, then gated behind toggles (`lagging_gap_enabled`, `ligase_enabled`)
  rather than deleted when base complexity turned out not to need them —
  they're reserved for the telomerase and ligase tiers respectively. This is
  the intended pattern for future complexity-tier work: build the toggle
  seam, don't throw away validated code paths.
- **Don't let two independently-tuned numbers just happen to agree.** The
  old sequence-length cap (three separate hardcoded `57`s across
  `dna_sequence_resource.gd`, `simulation.gd`, and `SequenceLoaderPopup.tscn`)
  and, later, the zoom threshold / SequenceLabel window width (two more
  independent `57`s) were both fixed this way in v74 — centralize into one
  shared source (a constant or ThemeManager field) rather than trusting
  coincidental agreement to hold as the codebase evolves. See Long-Sequence
  Support below for both fixes.
- **Prefer relative deltas over absolute position when driving an
  interaction from something whose position isn't stable.** The enzyme
  drag-to-scrub feature (v75) needed to work identically for the lagging
  polymerase, whose own on-screen position is deliberately non-monotonic
  (Okazaki jump-back — a sawtooth, not a line). Tracking cumulative
  screen-space mouse movement since the drag began, and never reading the
  dragged node's current position, sidesteps the instability entirely: the
  same math works for all three enzymes with no special-casing. See Zoom
  System Extensions below.

---

## Long-Sequence Support (v74)

Companion doc: `LongSequenceDesign.md` (implementation-level detail — exact
edit anchors, function names, and the handful of items still needing
in-engine tuning). This section is the DESIGN.md-level summary of what
shipped.

### Sequence length ceiling
`DnaSequenceResource.MAX_LENGTH` raised from 57 to **300** — the single
source of truth for validation (`is_valid_sequence()`) and random-length
generation (`randomize_sequence()`). `simulation.gd`'s truncation logic and
`SequenceLoaderPopup.tscn`'s `SequenceInput.max_length` both reference this
constant now instead of independent hardcoded `57`s — three previously-
separate enforcement points collapsed into one (see the new architectural
rule above).

### Preset catalogue rewrite
`Aleatória`, `Telômeros`, and `Promotores` removed. Replaced with:
- `PRESET_RICA_CG` / `PRESET_RICA_AT` — unchanged fixed-content presets,
  renamed to stable translation keys (never shown to the user directly,
  same split `EnzymeLabelsDesign.md` established for enzyme labels)
- `PRESET_PCR_TEMPLATE` — new, 90 bases fixed content (forward anchor +
  middle stretch + reverse anchor). A forward-reservation for the not-yet-
  built PCR sibling simulation (`SHARED_BASE_SEAM.md`'s build order:
  transcription → translation → PCR) — inert in replication today, same as
  the old `Telômeros`/`Promotores` reservations were
- `PRESET_CURTA` / `PRESET_MEDIA` / `PRESET_LONGA` / `PRESET_GRANDE` — new,
  random content at pinned lengths (34 / 57 / 90 / 200), re-rolled on every
  selection — replacing `Aleatória`'s fully-random-length behavior with four
  reproducible size tiers

`dna_sequence_resource.gd` now has two preset dictionaries — `PRESETS`
(fixed content) and `RANDOM_LENGTH_PRESETS` (pinned-length random) — plus an
explicit `PRESET_ORDER` array, since dropdown display order can't be relied
on from two separate dictionaries' own key order.

### Localization: presets + one UI string
New `presets.csv` (7 keys) and `ui_strings.csv` (`UI_CHAR_COUNT`), following
the same stable-key/CSV pattern `EnzymeLabelsDesign.md` established —
**must be registered under Project Settings → Localization → Translations**,
not just imported (the same silent-failure trap documented there).
`sequence_loader_popup.gd`'s preset dropdown now uses the `tr()` +
`set_item_metadata()` split already proven for the enzyme dropdown in
`player_ui.gd`, since `OptionButton` items don't auto-translate the way
`RichTextLabel`/`Label` text does.

### Zoom: fit-to-height windowed mode (level 1)
`zoom_manager.gd`'s `_compute_strand_fit()` now branches: below a live
threshold, level 1 behaves exactly as before (fit the whole track to 90% of
viewport width). Above it, level 1 switches to **fit-to-height** — zoom
derived from a fixed vertical content span instead of the (now arbitrarily
long) track width, with the camera's x-position following
`(helicase_x + polymerase_x) / 2.0` (leading polymerase, not lagging — per
`ZoomDesign.md`'s original reasoning: the lagging polymerase's per-fragment
jump-back would make the anchor itself jump) instead of centering the whole
track.

The threshold is **not** a hardcoded nucleotide count — it's "would the
whole track still fit legibly at the current viewport," computed live
against the shared `legible_reference_length` (see below), so it stays
correct if `nucleotide_slot_spacing` or viewport size ever change.

**Pan auto-release**, scoped to level-1 fit-to-height mode only (levels 2/3
keep their existing "sticky until deliberate change" pan behavior
unchanged): an inactivity timeout, and an explicit `recenter_pan()` action
wired to a new `RecenterPanButton` in `PlayerUI.tscn`'s `ZoomControls` row.
Both tween `pan_offset_x` back to zero rather than snapping, except during
scrub, which force-cancels any in-flight release tween and snaps instantly —
this project's existing scrub-is-always-instant rule, extended to cover the
new mechanism.

**New-strand targets excluded above the threshold**: `new_leading_strand` /
`new_lagging_strand`'s `is_visible_fn` callables now also return `false`
whenever `zoom_mgr.is_windowed_mode()` is true — a whole-strand bounding box
doesn't make sense to zoom into while it's sprawled off-screen; best
highlighted once fully visible at the normal fit-to-track zoom. This reuses
the existing visibility-gating plumbing (dropdown item disabling, auto-drop-
to-level-1 if already focused on a target that becomes invisible) with no
new mechanism needed.

### SequenceLabel: windowed display + click/drag-to-scrub
`replication_manager.gd`'s `get_sequence_rich_text()` no longer renders the
whole sequence — it shows a fixed-width window (the same shared reference
length as the zoom threshold) centered on the helicase's current progress,
following the fork rather than growing unboundedly wide with sequence
length. This incidentally also fixed `PlayerUI.tscn`'s `SequenceLabel`/
scrubber-width-matching overflow problem with no additional code — since the
label now always shows a bounded number of characters, the existing
width-matching logic in `player_ui.gd`'s `_update_ui()` just works.

Each visible character is wrapped in `[url=ABSOLUTE_SLOT_INDEX]` (the
absolute slot index, not its position within the window), enabling:
- **Click** → scrub to that slot (`meta_clicked`)
- **Hover** → highlight + pointer cursor (`meta_hover_started`/`_ended`)
- **Click-and-drag across letters** → continuous scrub, mirroring the
  scrubber slider's own drag behavior — synthesized from raw mouse-button
  state via `gui_input`, since `RichTextLabel` has no built-in drag concept
  the way `HSlider` does

`player_ui.gd`'s scrubber-drag handler and the label's click handler now
share one `_scrub_to_index()` helper instead of duplicating the pause/
scrub/update sequence.

**Visual grouping now marks real Okazaki fragment boundaries**
(`i % okazaki_fragment_size == 0`) instead of an arbitrary fixed
every-10-characters interval that predated this pass and was never actually
tied to fragment size. Same deterministic tiling formula (`[0,F), [F,2F),
…`) this file's own fragment logic already relies on elsewhere, so the two
can't drift out of sync.

### Shared reference length: one number, not two
`legible_reference_length` (ThemeManager, default `57`) is read by both the
zoom threshold above and the SequenceLabel window width — the same
"two independently-tuned numbers that happen to agree" trap the sequence-
length ceiling fix addressed, applied here as well (see the new
architectural rule above).

### ThemeManager: new "Zoom & Long-Sequence Display" group
All of `zoom_manager.gd`'s previously-local tuning constants —
`zoom_strand_width_percentage`, `zoom_height_fit_percentage`,
`zoom_vertical_content_span`, `zoom_level34_padding`,
`zoom_level_transition_duration`, `zoom_pan_screen_speed`,
`zoom_pan_release_inactivity_seconds`, `zoom_pan_release_tween_duration` —
plus `legible_reference_length` now live in ThemeManager, Inspector-editable.
Not because they're colors — because a broader zoom-tuning pass benefits
from one place to iterate rather than values split across files.
`zoom_manager.gd` caches a `tm` reference the same way `replication_manager.gd`
already did (`get_node("%ThemeManager")`).

The SequenceLabel hover highlight colors (`sequence_text_hover_bg_color` /
`sequence_text_hover_text_color`) moved to ThemeManager's existing
"Sequence Text" group too, alongside the synthesized/unsynthesized colors
they work with — so future theme variants can vary the hover look, same as
every other color in the project.

---

## Zoom System Extensions & Free Camera (v75)

Companion doc: `LongSequenceDesign.md` covers the pass that motivated this
one (windowed zoom, SequenceLabel). This section covers everything built on
top of it once the zoom system was actually implemented and put through
real use.

### Per-enzyme Level 2/3 fit percentages restored, centralized correctly
`HELICASE_LEVEL2_FIT`/`LEVEL3_FIT` (`simulation.gd`) and
`LEADING_LEVEL2_FIT`/`LAGGING_LEVEL2_FIT`/`POLYMERASE_LEVEL3_FIT`
(`replication_manager.gd`) moved to ThemeManager's new "Enzyme Level 2/3
Fit" subgroup — `zoom_helicase_level2_fit` (0.6), `zoom_helicase_level3_fit`
(0.8), `zoom_leading_level2_fit` (0.35), `zoom_lagging_level2_fit` (0.35),
`zoom_polymerase_level3_fit` (0.6, shared by leading+lagging Level 3 only —
not further split, matching the original single constant). Each stays
independently tunable — an earlier centralization pass had accidentally
merged these into one shared value; corrected once the regression was
reported.

### Nucleotide field & polymerase halo — alpha decoupled, particle count capped
`nucleotide_field.gd`'s free-floating particle count
(`particles_per_slot * num_slots`) was scaling to over 1000 particles on
long sequences, causing a measurable FPS drop — capped with a new
`max_particles` export (default 200). Separately, `polymerase_halo.gd` used
to read its own opacity live from `nucleotide_field.gd`'s alpha every
frame, forcing the two to always match — decoupled into ThemeManager's new
"Nucleotide Field & Halo" group (`nucleotide_field_alpha` /
`polymerase_halo_alpha`), so the functional capture-pool halo can be tuned
independently from the purely decorative background field.

### Click/drag-to-scrub on the enzymes themselves
`helicase_ring.gd` and `polymerase_clamp.gd` (covering both leading and
lagging) each got a manual `_unhandled_input()` hit-test — deliberately not
`Area2D`/`input_event`, which silently depends on
`Viewport.physics_object_picking` being enabled project-wide, exactly the
class of trap this project has hit before (CSV registration,
`LocaleManager` unique-name). Both emit sim-agnostic drag signals
(`scrub_drag_started`/`scrub_drag_delta`/`scrub_drag_ended`, screen-space
only, no simulation/zoom knowledge); `simulation.gd` (owns the ring) and
`replication_manager.gd` (owns both clamps) convert the delta into a scrub
index and funnel it through `simulation.gd`'s new `request_drag_scrub()`,
which `player_ui.gd` already listens to and routes into the same
`_scrub_to_index()` helper the slider and `SequenceLabel` already share.

**The key design decision, worth recording explicitly** (see the new
architectural rule above): dragging never reads an enzyme's *current
on-screen position* — only how far the mouse has moved, in screen pixels,
since the drag began, applied to whatever the scrub index was at that
moment. This is what makes the lagging polymerase draggable at all despite
its non-monotonic position — the math simply never touches that position,
so the sawtooth is irrelevant to it. Confirmed working in practice:
dragging smoothly moved the scrub index back and forth across a real
fragment-boundary jump with no special-casing needed.

### Free camera mode (mouse pan/zoom)
A new camera state, orthogonal to the discrete `zoom_level` system —
`zoom_manager.gd`'s `_free_camera_mode`. While active, neither
`_apply_live_frame()` (target-driven) nor `_compute_strand_fit()` (level-1
auto-fit) touch the camera; `_process()` early-returns and a new
`_unhandled_input()` drives everything directly:

- **Left-click-drag anywhere not already claimed by an enzyme's own
  drag-scrub** (checked via `is_input_handled()`, not any collision
  detection of `zoom_manager.gd`'s own) pans the camera in full 2D — the
  standard "grab canvas" convention, content follows the mouse.
- **Scroll wheel** zooms continuously, toward the cursor (the
  Illustrator/Photoshop convention), bounded between a new zoom-out floor
  (see below) and `zoom_free_camera_max_zoom_in` (ThemeManager, new "Free
  Camera Mode" subgroup, alongside `zoom_free_camera_scroll_step`).
- **Either gesture clears the currently selected target** (dropdown resets
  to the "Enzymes" placeholder) but does **not** reset the camera itself —
  entry seeds free-camera state from wherever the camera already was, so
  the transition is seamless.
- **Exit is only via two explicit player actions**: picking a target again
  (`select_target()`), or `ResetZoomButton` (`reset_zoom()`) — no automatic
  snap-back on its own.

**"Level 0" needed no new fit formula.** The zoom-out floor is literally
`_compute_strand_fit()`'s own whole-track-fit value, computed *before* its
windowed-mode legibility check — extracted into a shared
`_compute_track_fit_zoom()` helper both now call. For short sequences this
is identical to what level 1 already shows (nothing new); for long ones
it's smaller than the windowed level-1 zoom, letting the player scroll out
far enough to see the entire track at once — exactly the requested
behavior, and only for the sequences where it actually matters (>57 bases),
with no explicit length check required anywhere.

**`RecenterPanButton` pulls double duty.** In level-1 fit-to-height mode it
still tweens `pan_offset_x` back to zero (unchanged from v74). In free
camera mode, it instead centers the whole track (both axes) on screen
*without touching zoom* — same position `ResetZoomButton`'s level-1 snap
would use, just without the zoom part. Implemented via `tween_method()`
against a dedicated `_free_camera_position` var rather than tweening
`global_position` directly — tweening the Camera2D property alone would
leave the authoritative `_free_camera_position` state stale, so the very
next drag/scroll would read the old value and yank the view back. Same
class of bug as the missing `lagging_polymerase_tween.kill()` below, just
caught before it shipped this time.

### UI additions
- **Enzyme dropdown default**: no longer auto-selects Helicase on load —
  shows a disabled "Enzymes" placeholder (`UI_ENZYME_DROPDOWN_PLACEHOLDER`)
  until the player actually picks something.
- **`WobbleToggle`** wired to ThemeManager's existing `wobble_enabled`.
- **`NCloudToggle`** wired to `nucleotide_field.gd`'s `enabled` export.
- **`SequenceLabel`**: the automatic `[url]`-meta underline (a Godot
  default behavior, not something this project deliberately set) turned
  off via `meta_underlined = false`. Its visual grouping (already tied to
  real Okazaki fragment boundaries as of v74) needed no further change —
  it was never actually tied to fragment size before v74 despite briefly
  appearing to be.

### Bugs found and fixed this pass
- **`scrub_rebuild()` never killed `lagging_polymerase_tween`** — only
  `lagging_pump_tween`. Since the lagging polymerase's position tween is
  essentially always in flight during live play, any scrub landing
  mid-tween would snap correctly for one frame, then the stale tween's own
  next update would silently drag it right back toward its pre-scrub
  target — "everything paused except the lagging polymerase." This bug
  predates v75; the new drag-to-scrub paths just made it far more likely to
  actually trigger (many more scrub events per second than the slider ever
  produced), which is how it surfaced.
- **A full-screen background `ColorRect`'s `mouse_filter` was left at its
  Godot default (`Stop`)**, silently absorbing every mouse click at the GUI
  stage before it could ever reach the new enzyme-drag/free-camera
  `_unhandled_input()` handlers — zero clicks, zero errors, nothing to go on
  except a diagnostic print that should have fired but never did. Same
  silent-failure shape as the CSV-registration and `LocaleManager`
  unique-name traps already documented in this project. Fixed by setting it
  to `Ignore`.

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
  about emergent behavior — several v70.7 design decisions only became clear
  after hand-tracing concrete step-by-step examples, not from reasoning about
  the formulas alone.
- **Chaotic manual QA finds real bugs straight-line testing won't.**
  Scrubbing back and forth arbitrarily, then resuming play, surfaced two
  separate live-trigger desync bugs that a clean forward playtest never would
  have hit. Worth deliberately doing before calling any interactive feature done.

---

## Roadmap

### v71 — Visual polish + localization
- [x] Polymerase vector graphics (leading + lagging) — DONE. Authored 3-piece
      clamp (back body + jaw back + jaw front cap), ported from hand-drawn SVG
      via a python converter (`svg_to_polymerase_gd.py` → generated
      `polymerase_shape.gd` normalized polygon consts) into a runtime node
      (`polymerase_clamp.gd`) that z-threads the DNA between the clamp's back
      pieces and front cap, with a pump animation synced to the helicase's own
      `step_t`. Shared shape, mirrored/recolored per strand. See
      PolymeraseDesign.md (status updated) for full design history.
- [x] Nucleotide capture + placement animation — DONE, extending beyond the
      original roadmap scope. `polymerase_halo.gd`: a small typed-particle
      pool per polymerase (a bounded "tiny nucleotide_field," same soft-blur
      visual language, live-synced size/physics/alpha from
      `nucleotide_field.gd`). `_capture_*` functions in `replication_manager.gd`:
      search-first/fallback-relabel matching, two-leg animation (live follow
      of the jaw's inner anchor while the clamp is still gliding, then a tween
      to the base's final resting spot once it's arrived). Leading strand's
      spawn trigger was converted from per-frame position-polling to
      event-driven (off `helicase.slot_reached`), matching the trigger model
      lagging already used — `_leading_update()`'s old polling loop is now a
      no-op, safe to delete once this is confirmed stable across more QA.
      Scrub unaffected — never runs capture, same "instant, finished slots
      only" rule the pump already followed.
- [ ] Helicase vector graphics: six-blob barrel-roll ring, driven by
      `get_eased_step_t()`. See HelicaseDesign.md. **Next up.**
- [ ] Add text labels to enzymes for visual polish and learning support
- [ ] Localization hook: Godot's built-in `TranslationServer` + CSV
      (`tr("KEY")`), set up once enzyme labels exist so their text is written
      through translation keys from day one rather than retrofitted. Base
      letters (A/T/C/G) and polarity markers (`5'`/`3'`) are NOT translated —
      standard notation, not natural-language text.
      - [ ] Open decision: live in-game language switching (needs every
        translated-text call site to be re-runnable on a locale-changed
        signal) vs. restart-to-apply (simpler, no extra plumbing) — decide
        before building the hook, since it changes the hook's shape

### v74 — Long-sequence support
- [x] Sequence length ceiling raised 57 → 300 (`DnaSequenceResource.MAX_LENGTH`),
      unifying three previously-independent hardcoded enforcement points
- [x] Preset catalogue rewrite: removed `Aleatória`/`Telômeros`/`Promotores`;
      added `PRESET_PCR_TEMPLATE` (90 bases, fixed, PCR-tier reservation) and
      four pinned-length random tiers (`PRESET_CURTA`/`MEDIA`/`LONGA`/`GRANDE`
      at 34/57/90/200); all preset names moved to stable translation keys
      (`presets.csv`)
- [x] Zoom: level 1 fit-to-height windowed mode for sequences past a live,
      viewport-computed legibility threshold, with pan auto-release
      (inactivity timeout + explicit recenter button), and the two
      new-strand zoom targets excluded from the dropdown while windowed
- [x] SequenceLabel: windowed live-follow display (fixes the unbounded-width
      overflow at long sequences), click/drag-to-scrub via `[url]` meta +
      hover/RichText signals, and real Okazaki-fragment-aligned visual
      grouping (replacing an old arbitrary every-10-characters interval)
- [x] `legible_reference_length` and all zoom-tuning floats centralized on
      ThemeManager's new "Zoom & Long-Sequence Display" group; SequenceLabel
      hover colors moved to the existing "Sequence Text" group
- See `LongSequenceDesign.md` for full implementation detail

### v75 — Zoom system extensions + free camera
- [x] Per-enzyme Level 2/3 zoom fit percentages restored to independent,
      correctly-scoped ThemeManager fields after an earlier centralization
      pass had accidentally merged them
- [x] Nucleotide field particle count capped (`max_particles`, fixes a real
      FPS drop on long sequences); polymerase halo alpha decoupled from the
      field's own alpha into its own ThemeManager field
- [x] Click/drag-to-scrub on the helicase ring and both polymerase clamps —
      relative screen-space delta, not absolute position, which is what
      makes it work for the lagging polymerase's non-monotonic motion with
      no special-casing
- [x] Free camera mode: click-drag pan (2D) + scroll-wheel zoom-toward-
      cursor, clears the selected target without resetting the camera,
      exits only via picking a target again or `ResetZoomButton`; zoom-out
      floor doubles as "Level 0" with no new fit formula needed
      (`_compute_track_fit_zoom()`, shared with level 1's own fit)
- [x] `RecenterPanButton` double-duty: centers the track (no zoom change)
      while in free camera mode
- [x] UI: "Enzymes" placeholder default (no more auto-selecting Helicase),
      `WobbleToggle`, `NCloudToggle`
- [x] Two real bugs found and fixed: `scrub_rebuild()`'s missing
      `lagging_polymerase_tween.kill()`, and a background `ColorRect` left
      at Godot's default `mouse_filter = Stop` silently swallowing all
      clicks

### Near term — Telomerase tier
- [ ] Flip `lagging_gap_enabled` on for this tier; verify the
      already-built discard/gap-recording path
- [ ] Design telomerase's own visual (extends the gap, doesn't just leave it)

### Near term — Primase tier
- [ ] RNA primers as explicit, visible objects preceding each fragment
- [ ] Primer removal step, tying into (and likely refining) the gap mechanic
      established at the telomerase tier

### Near term — Ligase tier
- [ ] Flip `ligase_enabled` on for this tier; verify the already-built
      per-fragment nicked-backbone rendering path
- [ ] Animate the actual joining moment (nick sealing) rather than just
      toggling between the two static rendering modes

### Near term — Trombone loop complexity
- [ ] Design the trombone loop curve and PLL (Pre-Loop Length) geometry as
      first-class `replication_manager.gd` logic
- [ ] Return the lagging polymerase to helicase-relative positioning
      (mirroring the leading polymerase), removing the base-complexity
      exception noted in Key Architectural Rules above
- [ ] Loop slot queue tied to helicase steps, sized by `pll_slot_count`

### Replisome visual
- [ ] Unified replisome structure (E. coli model): τ (tau) body connecting
      helicase, leading polymerase, lagging polymerase, clamp loader.
      Only meaningful once the trombone loop complexity layer exists.
- [ ] Sliding clamps (β-clamp): one per Okazaki fragment + one on leading strand

### Medium term
- [ ] `okazaki_manager.gd` extraction — lagging-strand logic currently lives
      inline in `replication_manager.gd`; extraction was deferred until the
      base-complexity model was proven stable, which it now is
- [ ] ComplexityManager node (toggles per feature, Inspector-editable first)
- [ ] Player UI: slider widget extended to reach catch-up scrub territory
      (currently only arrow-key stepping reaches it)
- [ ] Themes: Dark, Light, Dark Low-Info, Light Low-Info (wobble already has
      a `wobble_enabled` ThemeManager toggle ready for this)

### Long term
- [ ] Transcription phase
- [ ] Error mechanics (proofreading on replication, error rates on transcription)
- [ ] Translation phase
- [ ] DNA sequence input UI

---

## Pinned Issues

None currently open for the replication simulator's base complexity tier —
all scrub/live-trigger desync bugs found during v70 QA are resolved (see
Scrub determinism above for the two that shipped and were fixed:
`lagging_total_consumed` and `lagging_batch_cursor` never resyncing on
scrub). Kept here as a heading rather than removed, since this project's
history shows pinned issues are a useful place to record resolved traps for
future reference, not just active blockers.

**Resolved, worth remembering (recurring "two similar values aren't
interchangeable" trap):**
- **Wobble-gating value mismatch (v70.7)**: bottom template's wobble gating
  compared against `polymerase_y_lagging` instead of the value it actually
  settles to, `new_bottom_template_y` — differ by `dna_ribbons_gap / 2.0`.
- **Camera centering (early v70.x)**: camera controller read a stale
  `straight_y` export that had been renamed to `template_strand_y`, silently
  falling back to a hardcoded default instead of erroring.
- **Scrub tiling formula (v70, this session)**: the in-progress fragment's
  slot range formula assumed every tile was full `okazaki_fragment_size`
  wide, producing out-of-range indices whenever the *final* tile was
  genuinely short — fixed by deriving the tile's true end
  (`min(tile_start + F, num_slots)`) instead of assuming `tile_start + F`.
- **Missing tween kill in `scrub_rebuild()` (v75)**: the dispatcher killed
  `lagging_pump_tween` on every scrub but never `lagging_polymerase_tween` —
  the tween that actually moves the lagging polymerase's *position*, and is
  essentially always in flight during live play. Any scrub landing
  mid-tween would snap correctly for one frame, then the stale tween's own
  next update silently dragged it back toward its pre-scrub target —
  "everything paused except the lagging polymerase." Predates v75; the new
  enzyme drag-to-scrub paths just made it far more likely to trigger.
- **Background `ColorRect` left at default `mouse_filter = Stop` (v75)**:
  silently absorbed every mouse click at the GUI stage before the new
  enzyme-drag/free-camera `_unhandled_input()` handlers could ever see
  them — zero clicks, zero errors. Same silent-failure shape as the CSV
  registration and `LocaleManager` unique-name traps. Fixed by setting it
  to `Ignore`.

---

## Scene Structure (v70 wrap)

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
`replication_manager.gd` in `setup_backbones()`, same as before v70.6.
`lagging_polymerase_tween` is transient script state (not a scene node),
created/killed by `_lagging_fire_step()` and the scrub/reset paths.
