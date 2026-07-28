# MolSim — Implementation Status
_Current architecture state, roadmap, pinned issues, and scene structure —
the volatile counterpart to DESIGN.md's stable philosophy and biological
model. Split out of DESIGN.md in this pass, after its Roadmap section had
drifted out of sync with reality across several sessions' worth of shipped
features (ComplexityManager, primase, ligase, Pol I) that never got checked
off here even though their own companion docs (OkazakiMaturationDesign.md,
COMPLEXITY_MODEL.md, EnzymeLabelsDesign.md) were kept current throughout.
The split exists specifically so that drift, when it happens again, only
affects this file — DESIGN.md's philosophy and biological-model content
doesn't change when a feature ships, and shouldn't be expected to.

**Update this file at the end of any pass that ships, fixes, or extracts
something** — that's the actual habit this split is meant to make easier to
keep. Companion to SKILL.md (Claude-facing quick reference, covers some of
the same architecture patterns at a terser grain) and to the per-feature
design docs this file summarizes at a glance without duplicating.

**What does NOT belong here: the version log.** That is `CHANGELOG.md`'s
job, added after this file was written. The boundary:

| File | Owns |
| --- | --- |
| `simulation.gd` header | The **current version only**. Nothing older. |
| `CHANGELOG.md` | **All version history**, newest first. Terse — what changed. |
| `STATUS.md` (this file) | **Current state and why.** Architecture, roadmap, pinned issues, scene structure, and the root-cause narratives behind how the current state came to be. |

Version numbers in this file's section headings are **provenance markers,
not log entries** — they record when a piece of the current architecture
landed, which is why "Helicase-anchored positioning (v70.6 refactor, still
current...)" earns its place while a bare list of what changed in v70.6 does
not. When a section here and a `CHANGELOG.md` entry cover the same pass, the
changelog stays terse and points here for the full writeup; do not copy the
narrative into both._

---

## Current Architecture State

`helicase.gd`, `replication_manager.gd`, `ComplexityManager`, `ligase.gd`,
`primase_blip.gd`, and `pol1.gd` are all extracted/built and stable.
`simulation.gd` is a thin template manager + visual coordinator that owns
no synthesis state. `procedural_shape_utils.gd` is a shared utility, not a
manager — see SKILL.md's Target Architecture for the full script
dependency tree, kept there rather than duplicated here so there's only one
copy to keep current.

**The lagging strand — base complexity through the Complex-tier Okazaki
maturation relay (primase → Pol I → ligase) — is fully implemented,
animated, and QA'd.** Leading strand synthesis and intro/resume animation
remain unchanged from v70.6.

**Topology mode + the telomere-gap mechanic have since shipped** on top of
that: `ComplexityManager.topology_mode` (CIRCULAR/LINEAR, a third gating
pattern — a *mode-gate*, distinct from the parent/child and bridge-toggle
cascades), and the Linear-only `lagging_gap_enabled` telomerase tier, which
produces the biologically-correct end-replication gap (one terminal primer's
footprint, removed by Pol I without refill — NOT the pacing-lag-sized discard
originally sketched; see the Telomerase Tier section and TelomeraseDesign.md).
The telomerase *enzyme visual* (extending the template) is designed but not
yet built — TelomeraseDesign.md holds the pre-implementation design, gated
behind an SSB toggle that ships first.

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
  completely. Only once this finishes does the enzyme fade sequence run —
  and, as of the Pol I pass, only once ligase and (if `pol1_enabled`) Pol I
  have ALSO drained their own trailing queues (`_lagging_enzymes_settled()`/
  `_lagging_try_deferred_fade()` — see OkazakiMaturationDesign.md's Pol I
  Implementation Status for the bug this fixed: the fade used to hide a
  trailing seal before it had actually happened).
- **Enzyme fade sequencing**: `_lagging_fade_enzyme_scene()` (helicase,
  leading polymerase, lagging polymerase, ligase, Pol I) fires only *after*
  the lagging strand's own end-state has fully settled, including trailing
  enzyme work as of the Pol I pass (see above). It is no longer tied
  directly to `helicase.Phase.DONE`, since that no longer means "everything
  is finished" once lagging synthesis is decoupled from the helicase's own
  timeline.

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

The Okazaki maturation relay (primase, Pol I, ligase) each get their own
per-slot/per-job pacing derived from this same `helicase_mgr.step_duration`
value rather than independent constants — see OkazakiMaturationDesign.md's
Pol I Implementation Status for why an independent pacing constant
specifically broke scrub-safety for a real-time-gated trigger, and SKILL.md's
"Scrub-safety demands event-count gating" entry for the general principle
that came out of it.

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

This same lesson resurfaced once more during the Pol I pass, in a different
shape: scrub had never modeled primase's own ahead-of-Pol-III placement
window at all (harmless while conversion was instant; a real bug once Pol I
made primer *timing* load-bearing) — see OkazakiMaturationDesign.md's Pol I
Implementation Status, bug #1, for the fix.

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

See SKILL.md's "Target Architecture" section for the full script dependency
tree — kept there rather than duplicated here, specifically so there's only
one copy of it to keep in sync (this doc used to carry its own near-identical
copy, which is exactly the kind of duplication that caused the drift this
split is meant to prevent).

### Key architectural rules
- **ThemeManager / ComplexityManager**: scene nodes, Inspector-editable, no
  autoload yet. Convert to autoload once export values settle.
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
  has shipped multiple times (`lagging_total_consumed`, `lagging_batch_cursor`,
  and again with primase's ahead-of-Pol-III window once Pol I made it matter).
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
- **Scrub-safety demands event-count gating, not real-time pacing, for
  anything that decides WHEN a trigger fires** (as opposed to how fast its
  own animation plays once it has). Added during the Pol I pass after an
  early trigger proposal paced removal off Pol III's own real-time fire-step
  — see SKILL.md's own entry on this for the general statement, and
  OkazakiMaturationDesign.md's Pol I Implementation Status for the specific
  story.

---

## Long-Sequence Support (v74)

Companion doc: `LongSequenceDesign.md` (implementation-level detail — exact
edit anchors, function names, and the handful of items still needing
in-engine tuning). This section is the summary of what shipped.

### Sequence length ceiling
`DnaSequenceResource.MAX_LENGTH` raised from 57 to **300** — the single
source of truth for validation (`is_valid_sequence()`) and random-length
generation (`randomize_sequence()`). `simulation.gd`'s truncation logic and
`SequenceLoaderPopup.tscn`'s `SequenceInput.max_length` both reference this
constant now instead of independent hardcoded `57`s — three previously-
separate enforcement points collapsed into one (see the architectural rule
above).

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
length ceiling fix addressed, applied here as well.

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

**The key design decision, worth recording explicitly**: dragging never
reads an enzyme's *current on-screen position* — only how far the mouse has
moved, in screen pixels, since the drag began, applied to whatever the
scrub index was at that moment. This is what makes the lagging polymerase
draggable at all despite its non-monotonic position — the math simply never
touches that position, so the sawtooth is irrelevant to it. Confirmed
working in practice: dragging smoothly moved the scrub index back and forth
across a real fragment-boundary jump with no special-casing needed.

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

## Complexity Toggle Status — Backbone Color (v73)

`template_backbone_color` (ThemeManager) was added in v73 to visually
distinguish the original template DNA backbone from newly-synthesized strand
backbone (`backbone_color`, unchanged) — a classroom aid for "which strand is
the original" that a single shared backbone color couldn't convey. Applied to
`backbone_line` and `top_strand_backbone_line` in `simulation.gd` only;
`replication_manager.gd`'s `leading_backbone_line`, `lagging_backbone_line`,
and per-fragment Okazaki lines are untouched and keep reading `backbone_color`.

---

## Telomerase Tier — Gap Mechanic + Topology Mode (shipped)

Companion docs: `TelomeraseDesign.md` (the enzyme visual — designed, NOT yet
built) and `TusTerDesign.md` (circular-termination sketch). This section
covers what actually shipped: topology mode, the telomere gap, and the batch
of end-of-strand fixes that came with it.

### Topology mode — the third gating pattern
`ComplexityManager.topology_mode` (enum `CIRCULAR` / `LINEAR`, default
`CIRCULAR` = the non-breaking E. coli model). It's a **mode-gate**, distinct
from the two cascades already in COMPLEXITY_MODEL.md: switching to CIRCULAR
force-disables `lagging_gap_enabled`; switching to LINEAR does *not*
auto-enable it. `is_enabled("lagging_gap")` folds the mode check in, so no
caller needs to know topology exists. `topology_changed` signal mirrors
`toggle_changed`. UI: dropdown + greyed-out telomerase checkbox in
`ComplexitySetupPopup` (five new `UI_TOPOLOGY_*`/`UI_TELOMERASE_*` CSV keys).

### The telomere gap — corrected model
The gap is **one terminal RNA primer's footprint** (`_primase_primer_length()`
slots), sized by primer length — deliberately NOT by the helicase↔Pol III
pacing lag. The original "discard the unfinished fragment" sketch was
biologically wrong (synthesised DNA doesn't dissolve; the gap it produced was
~2 fragments, lag-sized) and was **removed entirely**, not toggled off. In its
place: catch-up finishes the whole strand, then the terminal primer is removed
via a `remove_only` Pol I job (`_lagging_finalize_terminal_gap()`) — the same
enzyme that removes every other primer, visibly failing to refill this one.
Light tier (no Pol I) does a quiet fade instead; same end state. **Requires
primase** — with no primer there is no gap (flagged; whether this becomes a
hard `requires` edge in the UI is an open decision, deferred to the UI pass).

### End-of-strand fixes that shipped alongside
- **Last-fragment nick (any topology, Pol I on, telomerase off)**: the last
  fragment's own primer is never removed (nothing closes after it), which had
  deadlocked ligase's eligibility gate forever. Ligase now seals the last
  fragment's 5' nick anyway once the strand is complete — its DNA joins the
  strand, the un-removed 3' primer stays a distinct RNA segment. Both the
  sealed (ligase-on) and continuous (ligase-off) render merges gained
  retained-primer handling (`_lagging_fragment_retains_primer()` /
  `_lagging_render_retained_primer()`).
- **Ligase spawn/reset**: `_ligase_reset_visual()` now also resets *position*
  (create-once-hide lifecycle seam — it used to keep last-seal position across
  reloads, sliding in from mid-strand). New `_ligase_park_offstage()` parks it
  below the strand near the start so its first seal rises into place instead of
  dropping from local origin. `ligase_offstage_drop` ThemeManager field.
- **Polymerase end-of-run rest slide**: `_polymerases_move_to_rest()` — the
  lagging polymerase slides up to meet the leading one at catch-up completion,
  both nudged past the strand's end so they clear Pol I/ligase's catch-up work.
  `polymerase_rest_nudge_slots` / `polymerase_rest_move_duration` fields.
  Live-only polish (both are alpha-0 in scrub at DONE); the `_polymerases_at_rest`
  guard is synced in `_lagging_scrub_rebuild()` so a mid-run-scrub-then-replay
  re-fires it.
- **3' marker on the gapped fragment**: `_lagging_fragment_last_rendered_slot()`
  walks back past null gap slots so the marker lands on the last DNA base, not
  inside the empty gap.

All of the above route through the shared render-merge paths, so each got a
QCA scrub pass across the catch-up→fade window in both topologies.

---

## Vertical Mode (v77)

Companion doc: `VerticalModeDesign.md` (design + the five places the design was
wrong once real files were read). Motivated by a product need, not the roadmap:
the Instagram vertical teaser drew interest but viewers reported not
understanding what they were looking at. Vertical mode exists so the simulation
reads natively in 1080x1920 instead of being a letterboxed crop of a landscape
scene.

### The approach: rotate the CAMERA, not the simulation

`ZoomManager.vertical_mode` (`@export`, explicit toggle — not aspect-derived,
because predictability while recording beats auto-detection). Sets
`rotation_degrees = -90` so world +x — which is the track's axis in BOTH modes —
runs top-to-bottom on screen.

Every world quantity is untouched: `center_y`, `helicase_x`,
`nucleotide_original_x[]`, `track_length`, slot positions, every frame
provider's return value. Only the view transform changes. Rotating a simulation
root instead would have dragged `Camera2D.global_position` into rotated space,
forcing every fit formula that returns a world position to be transformed on
the way out.

**`Camera2D.ignore_rotation` defaults to TRUE in Godot 4** — without clearing
it, `rotation` is silently ignored and vertical mode does nothing, with no
error. `_apply_orientation()` clears it unconditionally so no state exists where
it's true. Same silent-failure shape as the CSV-registration and `mouse_filter`
traps below.

**Zero new scrub-safety surface.** `vertical_mode` is set at load and never
animated, so the rotation is a constant, not a tween. Nothing in `scrub_snap()`
/ `_transition_to_level()` / `_apply_live_frame()` gained a timing dependency.
This is why the pass was small.

### The axis mapping: ONE file knows which way is up

`ZoomManager.get_along_extent()` / `get_cross_extent()` are **public** — the
single source of truth for which viewport dimension corresponds to which world
axis. Along-axis = the track's direction (world x); cross-axis = across it
(world y — strand thickness, replisome height, perpendicular in both modes).

They're public because the frame providers in `simulation.gd` /
`replication_manager.gd` compute their OWN zoom and previously read
`get_viewport()` directly, pre-judging an axis. **Eight viewport-reading fit
sites across three files** now route through these two helpers. The only raw
`get_viewport_rect()` reads left in `zoom_manager.gd` are the two helpers
themselves plus the free-camera SCREEN centre (genuinely screen-space, correctly
not swapped).

Because the rotation is exactly 90 degrees, world-axis-aligned bounding boxes
stay axis-aligned in camera space — no point transformation anywhere, just a
swap of which viewport dimension each world axis is fitted against.

### Findings that contradicted the design doc

- **`_fit_points()` is dead code.** Every registered target returns a
  `Dictionary {zoom, position}`; nothing returns an `Array`. The design's claim
  that "bounding-box targets survive rotation for free" described a path with no
  callers. Kept axis-correct anyway so it isn't a trap for the next provider.
- **`_polymerase_footprint_frame()` is a cross-axis-only fit** serving leading
  L3, lagging L2/L3, and leading L2's fallback — so the polymerase targets were
  never bounding-box targets either.
- **`_anchor_centered_frame()` is byte-identical in `simulation.gd` and
  `replication_manager.gd`** — the same shape as `_round_corners()` before
  `procedural_shape_utils.gd`. One duplicate, not five, so not extracted yet.
  See Medium term.

### Glyph counter-rotation — three different fixes

World-space text doesn't rotate for free. Everything else does: enzyme
silhouettes, the helicase barrel-roll, bond marks (perpendicular to the strand,
stays perpendicular), halo particles (a rounded square rotated 90 degrees is the
same rounded square, so the RNA/DNA shape distinction survives), draw order.

1. **`nitrogen_base.gd`** — the glyph is a real `Label` node, so
   `set_label_rotation()` (injected by the spawner, per this file's
   ThemeManager-free contract). **The load-bearing line is `pivot_offset`, not
   the rotation**: Godot rotates a Control around its pivot, which defaults to
   the TOP-LEFT corner, so without `label.pivot_offset = label.size / 2.0` every
   glyph swings off-centre by half its own diagonal. On 300 bases that reads as
   "the letters fell over and scattered" rather than as its one-line cause.
   Covers 5'/3' markers too — same scene, `base_type` of `"5'"`/`"3'"`.
2. **`polymerase_halo.gd`** — raw `draw_string()`, no Label. Rotates the GLYPH
   only via `draw_set_transform(Vector2.ZERO, label_rotation, Vector2.ONE)`, not
   the whole `_HaloDot` node. Rotating the node would work today purely because
   a circle is rotation-invariant and a rounded square is invariant at exactly
   90 degrees — i.e. it would rely on the camera angle and the particle shape
   coincidentally agreeing.
3. **`nucleotide_field.gd`** — the OPPOSITE fix. It draws every particle in ONE
   `_draw()` on a single node, so `Vector2.ZERO` would swing the whole cloud
   around the field's origin instead of spinning letters in place. Passes each
   particle's own centre `c` as the transform origin, and **must reset the
   transform afterward** (the loop continues; the next body uses absolute `c`).
   It also reads the rotation LIVE in `_draw()`, like it already reads
   `tm.base_label_color` — ZoomManager is a SIBLING, and sibling `_ready()` order
   follows scene-tree order, so caching there could capture a pre-orientation
   zero.

`draw_string` appears exactly twice in the project. Both are handled.

### EnzymeLabel: the mirror inverts the sign, and EnzymeLabel owns that

`set_counter_rotation(radians)` — sibling to the existing `set_mirror()`. Both
compose around `pivot_offset`, so the anchor never moves.

The leading clamp carries `scale.y = -1`, and reflection conjugates rotation
(`S * R(t) * S = R(-t)`), so a local `t` under a mirrored parent renders as world
`-t`. **The sign lives in `EnzymeLabel._apply_rotation()`, not in the five
callers** — every enzyme passes `get_label_counter_rotation()` verbatim and none
of them knows the mirror interaction exists. Order-independent: `set_mirror()`
and `set_counter_rotation()` compose either way.

Wired into `helicase_ring.gd`, `polymerase_clamp.gd`, `primase_blip.gd`,
`ligase.gd`, `pol1.gd`. Each follows its own file's existing convention —
`helicase_ring.gd` gets it PUSHED by `simulation.gd` (it holds no external
references at all, which is why its label params are local `@export`s); the
others reach through their existing `_sim` for `%ZoomManager`, as they already do
for `%ThemeManager`.

### `scrub_drag_delta`: float -> Vector2

The enzyme hit-tests needed **no change** — `to_local(get_global_mouse_position())`
is world-space and already accounts for camera rotation. Only
`event.position.x` (raw viewport) was wrong.

The fix deliberately does NOT go in the enzyme scripts.
`helicase_ring.gd`'s own banner states the contract: it reports raw SCREEN-space
movement, and converting that into a scrub index is the owner's job. It also
holds **zero** external references — no `_sim`, no `_tm`, nothing. So the signal
widened to `Vector2` and the owning scripts pick the component where they already
convert px to slots:

```gdscript
var along_px: float = cumulative_px.y if zoom_mgr.vertical_mode else cumulative_px.x
```

**The enzyme now knows strictly less than before** — it no longer pre-judges
which screen axis is meaningful. `_request_clamp_drag_scrub()` already funnelled
both clamps, so there are only two decision points, not three.

**No sign flip needed**: horizontally, drag right (+screen x) is world +x is
forward; vertically, world +x maps to screen +y which is DOWN, so drag down is
forward. Positive is forward in both. `zoom` is uniform, so px-per-slot is
axis-independent.

### Arrow-key pan: an input swap, not a vector rotation

`pan_offset_x` is applied as `Vector2(pan_offset_x, 0.0)` in world space, and
world x is along-track in BOTH modes — so it needed no change at all. Only the
binding swaps (`_pan_action_negative/positive()`). Pleasingly, that's the same
pair `_input()` must consume to keep the Scrubber from seeing them: an `HSlider`
reacts to ui_left/ui_right, a `VSlider` to ui_up/ui_down.

### Free camera: the one place that needed real rotation

`_unhandled_input()`'s drag and `_free_camera_scroll_zoom()`'s cursor anchor are
the ONLY screen->world conversions in the file, and both were identity. Unrotated
in vertical, dragging right pans along world x — the canvas slides *vertically*
while the mouse moves horizontally. One helper, `_screen_to_world_offset()`,
applies `.rotated(rotation)`; identity in horizontal, so no branch.

### ThemeManager: the cross-axis rename

"Height" meant cross-axis, which in vertical mode is horizontal. Shipped as a
**pure rename** — comments stripped and identifiers normalised, both files were
byte-identical to their originals, so it changed no behavior by construction.

| Old | New |
| --- | --- |
| `zoom_strand_width_percentage` | `zoom_along_axis_percentage` |
| `zoom_height_fit_percentage` | `zoom_cross_axis_fit_percentage` |
| `zoom_vertical_content_span` | `zoom_cross_axis_content_span` |
| `_compute_height_fit()` | `_compute_cross_axis_fit()` |
| `viewport_width` (2 params + 1 local) | `along_extent` |
| `NEW_STRAND_LEVEL{2,3}_VERTICAL_FIT` | `..._CROSS_AXIS_FIT` |

**The rule applied: rename what names a SCREEN axis; leave what names a WORLD
span.** `_polymerase_footprint_height()` is a world-y span and kept its name.

### PlayerUI: one script, two scenes

`PlayerUI.tscn` had **zero** `unique_name_in_owner` flags — all 25 `@onready`
references were hardcoded deep paths, which a different container structure
breaks. Converted to `%Name` (25 nodes flagged, 25 references rewritten;
verified by rebuilding the path->name map from the scene and confirming every
`%Name` resolves to the exact node its old path did).

`VerticalPlayerUI.tscn` shares `player_ui.gd` and satisfies the same contract:
**17 required names present, 8 optional absent.** The optional eight
(`SequenceLabel`, `ZoomControls` + its children) use `get_node_or_null()`.

**Nothing was retired.** The enzyme dropdown's code is intact for the planned
voice-command interface; the vertical scene simply has no widget for it.

**Guards are function-level, not per-line**, because three of the consumers are
driven by ZoomManager signals rather than by the widgets:
`_update_enzyme_dropdown_availability()` runs EVERY FRAME from `_process`;
`_populate_enzyme_dropdown()` fires on `targets_changed`; `_on_zoom_target_changed()`
on `target_changed`. All three would have hit a null dropdown on frame one.

`ResetZoomButton` is deliberately KEPT in vertical (moved into the transport
row): with no pinch gesture on mobile and no zoom buttons, zooming in would
otherwise be a one-way trip.

Scene selection is **deliberately asymmetric** — `simulation.gd`'s
`_swap_in_vertical_player_ui()` leaves the horizontal path completely untouched
(zero risk to the working PC build) and only the vertical branch is new code. It
must assign `vertical.simulation = self` by hand before `add_child()`, because
`PlayerUI.tscn`'s instance has that `@export` editor-wired via
`node_paths=PackedStringArray("simulation")`, which a runtime instantiation
can't inherit.

### Topology-conditional polymerase labels

See `EnzymeLabelsDesign.md`'s Topology addendum. In LINEAR topology the
polymerase clamps are genuinely different enzymes (Pol epsilon leading, Pol delta
lagging), not one enzyme mirrored — so the shared `ENZYME_POLYMERASE` key splits.

`_polymerase_label_key()` collapses 8 cells to 4 keys, and **each topology
ignores exactly one of its two other inputs — a different one**: CIRCULAR ignores
strand (E. coli: same protein both strands) and honours `pol1_enabled`; LINEAR
ignores `pol1_enabled` (the spelled names are already unambiguous) and honours
strand.

**`polymerase_clamp.gd`'s `_mirror` became `_is_leading`.** It was already doing
double duty as strand identity (`_apply()` reads it for
`clamp_leading_back_color`), but those are colours — wrong there is cosmetic;
wrong about which enzyme this IS teaches biology. Renamed rather than adding a
second bool: two flags that must always agree is the same trap in a worse form,
since then they CAN disagree. Zero behavior change — both call sites already
passed the right value. **The file header's "no leading/lagging distinction" is
now a CIRCULAR-only claim.**

Names are spelled in Latin ("Pol epsilon"/"Pol delta"), not Greek glyphs — at
label size on a moving clamp, a one-glyph difference between the two most
important enzymes in the eukaryotic fork is the same failure this project's
RNA/DNA rule already forbids ("shape AND thickness, never colour alone").

---

## Follow Mode, Click-Drag Dead Zone & Related Camera Fixes (v77 continued)

Companion doc: `ZoomDesign.md`'s As-Built addendum at the bottom (the rest of
that file is pre-implementation and stale — flagged there, not rewritten).
This section covers a same-day cluster of camera work, starting from the
ResetZoomButton bug below and expanding once its root cause turned out to be
one instance of a more general gap.

### RESOLVED — ResetZoomButton did nothing in vertical mode (v77)
Root cause was two-layered:
1. **`%ZoomManager` lookup crosses a scene-ownership boundary.** Horizontal
   `PlayerUI` is placed in the editor inside `simulation.tscn`, so its `owner`
   is wired automatically and `%ZoomManager` resolves. `VerticalPlayerUI` is
   instantiated at runtime (`_swap_in_vertical_player_ui()`), so its root's
   `owner` is never set to the outer scene — `%ZoomManager` silently returned
   null, `player_ui.gd` hit its own `if zoom_mgr:` guard, and
   `reset_zoom_button.pressed.connect(...)` never ran. Same class of fix as
   the pre-existing `vertical.simulation = self` injection one line above it
   — `zoom_mgr` needed the identical manual injection.
2. **Broader bug surfaced during the fix**: `_process()`'s per-frame live-
   tracking (`_apply_live_frame()`/`_frame_strand()`) directly writes
   `zoom`/`global_position` every frame with no guard against an in-flight
   `_transition_to_level()` tween — so the tween's own cubic-ease was being
   stomped one frame after starting, on every level/target transition, not
   just Reset. `tm.zoom_level_transition_duration` was doing nothing
   visible project-wide. Fixed by having `_process()` return early while
   `_transition_tween` is valid.

### SHIPPED — Follow mode (double-click an enzyme)
Fourth mutually-exclusive camera state in `zoom_manager.gd`, alongside free
camera and the level-based target system — not a variant of either. Position
auto-derived every frame from the target's own entry-level frame provider
(ignoring the provider's zoom half entirely); zoom held independently in
`_follow_zoom`, changed only by scroll. Scoped to **helicase and lagging
polymerase only** (leading polymerase's `polymerase_clamp.gd` gets the same
`follow_requested` signal for free since the script is shared, but nothing
connects to it — scoped at the call site in `replication_manager.gd`, not the
shared file).

Entry/exit, all via double-click (Godot's own `event.double_click`, no manual
timing):
- Double-click an enzyme → follow it (or switch directly if already
  following a different one).
- Double-click the ALREADY-followed enzyme → toggles highlight instead
  (`request_follow()`'s own branch) — the second trigger for what
  HighlightButton does.
- Double-click empty background → `reset_zoom()`, back to level 1.

Background press-and-hold while following: freezes the camera in place
immediately (`_follow_paused`), then resolves on release — a quick tap (no
movement, <250ms) drops follow and enters free camera; a hold or hold+drag
resumes follow, eased back over `tm.zoom_follow_resume_duration` (cubic
ease-out, recomputed against the LIVE target position every frame rather
than a frozen snapshot, since the followed enzyme keeps moving during the
ease). `scrub_snap()` bypasses this ease entirely and jumps straight to the
live target, matching `ZoomDesign.md`'s "clamps are live-play-only" note.

New ThemeManager exports (`Follow Mode` subgroup): `zoom_follow_min_zoom`,
`zoom_follow_resume_duration`. Both NOT YET TUNED.

### RESOLVED — double-click on an enzyme sometimes paused playback
`helicase_ring.gd` / `polymerase_clamp.gd`'s drag-to-scrub committed to a
drag on the very first pixel of motion after a press — no dead zone. Any
incidental mouse jitter between a double-click's two presses (confirmed via
`[FOLLOWCLICK]` prints — LP's smaller click region made it near-guaranteed,
helicase's larger one made it intermittent) fired `scrub_drag_delta`, which
pauses playback unconditionally via `_scrub_to_index()` regardless of
whether the resulting index actually changed. Fixed with a 6px
`DRAG_DEADZONE_PX` (NOT YET TUNED, plain local const — deliberately not
routed through ThemeManager, respecting `helicase_ring.gd`'s existing
"no ThemeManager reference" contract) before a press commits to a drag at
all; below it, release is treated as a plain click. Independent of Follow
Mode — benefits ordinary single-click-drag scrubbing too.

### RESOLVED — EnzymeLabel panel kept old (wider) width after text shrank
`enzyme_label.gd`'s `set_key()` set `_rich_text.text` and trusted the
`resized` signal alone to re-center — works growing short→long, but Godot's
Control/Container sizing reliably grows to fit a child's minimum size and
doesn't reliably shrink back down on its own. Repro: switching topology
mid-simulation (LINEAR → CIRCULAR) left "Pol III"'s label at "Pol epsilon"'s
width, dead space in front of the shorter text. Fixed with `reset_size()`
(forces an immediate recompute from the child's current minimum size) in
both `set_key()` and `refresh_translation()` — the latter had the identical
latent bug for a locale switch to a shorter word, just not yet surfaced.
Distinct from the still-open `polymerase_label_margin` vertical-mode overflow
item on TODO.md — that one's too-narrow margin; this was stale-width panel.

---

## Roadmap

### v71 — Visual polish + localization — DONE
- [x] Polymerase vector graphics (leading + lagging). Procedural two-piece
      clamp (`polymerase_clamp.gd`), pump animation synced to the helicase's
      own `step_t`. Shared shape, mirrored/recolored per strand. See
      PolymeraseDesign.md.
- [x] Nucleotide capture + placement animation. `polymerase_halo.gd`: a
      small typed-particle pool per polymerase. `_capture_*` functions in
      `replication_manager.gd`: search-first/fallback-relabel matching,
      two-leg animation.
- [x] Helicase vector graphics: six-blob barrel-roll ring. See
      HelicaseDesign.md.
- [x] Text labels on enzymes. See EnzymeLabelsDesign.md.
- [x] Localization hook: Godot's built-in `TranslationServer` + CSV. Live
      switching (not restart-to-apply) — confirmed working with zero extra
      plumbing beyond what `Control.text` already provides.

### v74 — Long-sequence support — DONE
See Long-Sequence Support section above for full detail.

### v75 — Zoom system extensions + free camera — DONE
See Zoom System Extensions & Free Camera section above for full detail.

### Okazaki maturation relay — DONE
- [x] **Primase tier**: RNA primers as explicit, visible objects preceding
      each fragment, both Light tier (transient blip) and Complex tier
      (real persisted RNA state, ahead-of-Pol-III placement). See
      OkazakiMaturationDesign.md.
- [x] **Ligase tier**: real traveling enzyme (not just a static toggle),
      LigaseState state machine, dual trigger call sites at Complex tier.
      See OkazakiMaturationDesign.md.
- [x] **Pol I (primer removal)**: nick-translation enzyme, one-fragment-lag
      trigger, true-absence lifecycle, two-lobe (EXO/POL) visual. The
      "bridge toggle" that couples primase + ligase into the full Complex
      tier. See OkazakiMaturationDesign.md.
- [x] **ComplexityManager node**: real toggles (`primase_enabled`,
      `pol1_enabled`; `ligase_enabled` stays on `sim` — see its own
      migration note), `is_enabled()`/`set_X_enabled()` API, bridge-toggle
      cascade, `ComplexitySetupPopup` UI. See SKILL.md's ComplexityManager
      access entry and COMPLEXITY_MODEL.md's Cascading UI behavior.
- [x] `procedural_shape_utils.gd` extraction — `_round_corners()` had ended
      up duplicated five times (helicase_ring/ligase/primase_blip/pol1/
      polymerase_clamp) by the time Pol I shipped; extracted once that fifth
      copy made it worth doing.

### Telomerase tier — gap mechanic DONE, enzyme visual PENDING
- [x] Topology mode (`CIRCULAR`/`LINEAR`) + `lagging_gap_enabled` gating —
      shipped. See Telomerase Tier section above.
- [x] Telomere gap mechanic — shipped, but NOT via the originally-sketched
      "discard the unfinished fragment" path. That model was biologically
      wrong and removed entirely; the gap is now one terminal primer's
      footprint, removed by a `remove_only` Pol I job. This also resolved the
      old open question about the discarded-fragment/Pol I-queue interaction —
      there is no discarded fragment anymore.
- [ ] **Telomerase enzyme visual** — designed (`TelomeraseDesign.md`), not
      built. The hard architectural fork to settle first: whether
      `nucleotide_original_x[]` actually grows (template lengthens mid-run) or
      telomerase-added bases are represented some cheaper way. Comparable in
      scope to the whole Okazaki relay, not a single enzyme pass.
- [ ] Decide whether telomerase should hard-require primase (grey out the
      checkbox unless primase is on) — deferred to the UI pass.

### v77 — Vertical mode — DONE
See Vertical Mode section above for full detail.
- [x] `vertical_mode` + camera rotation; `get_along_extent()`/`get_cross_extent()`
      as the single source of truth for the axis mapping (8 fit sites, 3 files).
- [x] Glyph counter-rotation: bases, 5'/3' markers, RNA primers, Okazaki
      markers, both halo pools, the ambient nucleotide field.
- [x] `EnzymeLabel.set_counter_rotation()` + all five enzymes.
- [x] `scrub_drag_delta` widened to `Vector2`; drag-scrub works in both modes.
- [x] ThemeManager cross-axis rename (pure rename, verified no-op).
- [x] Topology-conditional polymerase labels + `_is_leading`.
- [x] PlayerUI unique-name refactor (25 nodes) + `VerticalPlayerUI.tscn`.
- [ ] **Vertical camera setup for recording** — designed, not built. Three
      pieces, and they're one feature: double-click an enzyme to follow it;
      lock the camera's world-y to `center_y` so the strand stays centred and
      only scrolls vertically; keep the wheel-set zoom while following.
      **This is a THIRD camera mode** — free camera is manual zoom/manual
      position, target mode is auto/auto, and this is manual zoom + auto
      position. The frame providers already return `{zoom, position}`, so
      follow mode just ignores the zoom half and overrides `position.y`.
      Scrub-safe by construction (position derives per-frame from the provider;
      zoom is a constant). Double-click deliberately sidesteps the
      tap-vs-drag conflict — it's a distinct gesture from press-and-drag, so
      drag-to-scrub needs no movement threshold and no deferred pause.
      Not vertical-gated: `select_target()`/`target_changed` is already the API
      and the dropdown is already just one input path that listens and syncs
      (see `_on_zoom_target_changed()`'s own comment anticipating
      "keyboard/click/voice, later"), so this is the first step of the enzyme
      zoom dropdown rework rather than a vertical-only detour.

### Near term — SSB tier (prerequisite for telomerase visual)
- [ ] SSB (single-strand binding protein) as its own general Stage 2
      elongation toggle — coats exposed ssDNA behind the helicase; independent
      of telomerase. Ships FIRST, on its own. (Shelterin — the actual
      telomere-specific overhang protector telomerase force-enables — is a
      later, separate addition; see TelomeraseDesign.md's "Overhang
      protection" for the SSB-first/shelterin-later decision.)

### Near term — Tus–Ter termination (circular)
- [ ] Sketched only (`TusTerDesign.md`): two replisomes meeting from opposite
      directions, resolving circular topology's own "last primer never
      removed" case via the real mechanism (the second replisome supplies the
      missing "next fragment closes" trigger). The full bidirectional
      replication bubble is explicitly deferred post-proposta-simplificada.

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
- [ ] `okazaki_manager.gd` extraction — lagging-strand logic still lives
      inline in `replication_manager.gd`. Deferred through the entire
      Okazaki maturation relay shipping (primase/ligase/Pol I all landed
      without needing it pulled out) — still the one deferred extraction
      target, per SKILL.md's Natural Seams section.
- [ ] Player UI: slider widget extended to reach catch-up scrub territory
      (currently only arrow-key stepping reaches it)
- [ ] Themes: Dark, Light, Dark Low-Info, Light Low-Info (wobble already has
      a `wobble_enabled` ThemeManager toggle ready for this)
- [ ] `_anchor_centered_frame()` is byte-identical in `simulation.gd` and
      `replication_manager.gd` (v77) — the same shape `_round_corners()` had
      before `procedural_shape_utils.gd`. Only one duplicate so far, so not yet
      worth extracting; note it here so the second copy triggers the same
      treatment rather than a rediscovery.
- [ ] **Verification debt (v77)**: grep the REAL project directory for
      `draw_string`, `EnzymeLabel`, and `Label.new()` to confirm the glyph
      counter-rotation inventory is complete. The v77 sweep only covered files
      uploaded to chat, which is how `nucleotide_field.gd` was initially missed —
      it has a `draw_string` and would have shipped with sideways letters.
- [ ] **Translation review** now has three items pending a native-speaker pass,
      not one: the `_FULL` word-order inconsistency (see EnzymeLabelsDesign.md),
      "Pol épsilon"'s accent in pt_BR/es, and "eucariota" vs "eucariótico" in the
      es topology strings. Worth batching into one pass.

### Long term
- [ ] Transcription phase
- [ ] Error mechanics (proofreading on replication, error rates on transcription)
- [ ] Translation phase
- [ ] DNA sequence input UI

---

## Pinned Issues

### RESOLVED — ResetZoomButton does nothing in vertical mode (v77)
See "Follow Mode, Click-Drag Dead Zone & Related Camera Fixes" above for the
full root-cause writeup (`%ZoomManager` injection + the transition-tween race
it surfaced). Kept here as a heading, matching this section's own convention
below of recording resolved traps for future reference.

---

Otherwise none open for the replication simulator's base complexity tier —
all scrub/live-trigger desync bugs found during QA are resolved (see Scrub
determinism above). Kept here as a heading rather than removed, since this
project's history shows pinned issues are a useful place to record resolved
traps for future reference, not just active blockers.

**Resolved, worth remembering (recurring "two similar values aren't
interchangeable" trap):**
- **Wobble-gating value mismatch (v70.7)**: bottom template's wobble gating
  compared against `polymerase_y_lagging` instead of the value it actually
  settles to, `new_bottom_template_y` — differ by `dna_ribbons_gap / 2.0`.
- **Camera centering (early v70.x)**: camera controller read a stale
  `straight_y` export that had been renamed to `template_strand_y`, silently
  falling back to a hardcoded default instead of erroring.
- **Scrub tiling formula (v70)**: the in-progress fragment's slot range
  formula assumed every tile was full `okazaki_fragment_size` wide,
  producing out-of-range indices whenever the *final* tile was genuinely
  short — fixed by deriving the tile's true end
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
- **`sim.pol1_enabled` doesn't exist (Pol I pass)**: `pol1_enabled` lives on
  `ComplexityManager` itself, not proxied onto `sim` the way `ligase_enabled`
  is (which predates `ComplexityManager` — see its own migration note).
  Reading `sim.pol1_enabled` crashes at runtime (`Invalid access to property
  or key`) rather than failing a lookup — caught immediately on first real
  playtest. See SKILL.md's ComplexityManager access entry.
- **Scrub never modeled primase's ahead-of-Pol-III placement window (Pol I
  pass)**: harmless while primer conversion was instant (anything Pol III
  would eventually touch became DNA regardless of what sat there first); a
  real bug once Pol I made primer *timing* load-bearing — scrubbing to a
  point where primase would have already placed a primer, then resuming
  play, made Pol III find nothing there and write fresh DNA straight
  through. See OkazakiMaturationDesign.md's Pol I Implementation Status,
  bug #1.
- **Scene-wide fade could hide a trailing seal before it happened (Pol I
  pass)**: the fade-out fired the instant Pol III's own synthesis finished,
  without checking whether ligase/Pol I still had trailing work queued —
  functionally correct, invisibly so. See OkazakiMaturationDesign.md's Pol I
  Implementation Status, bug #2.
- **`tween_callback` used where `tween_method` was needed (Pol I pass)**: a
  callback is an instant snap with no visible duration; two of them
  back-to-back produced a pulse that was technically animating 0→1→0 but
  invisibly. See OkazakiMaturationDesign.md's Pol I Implementation Status,
  bug #3.

**Resolved during the Telomerase gap / topology pass:**
- **Gap sized by the pacing lag, not primer length**: the original discard
  model left a ~2-fragment gap because it threw away whatever the lagging
  polymerase hadn't finished at helicase DONE — and how far behind it was is
  set by `okazaki_fragment_size + pll_slot_count` (a visual-pacing number),
  not by anything biological. Same "two independently-tuned numbers standing
  in for each other" trap as the others here. Fixed by sizing the gap from
  `_primase_primer_length()` and removing the discard model outright.
- **Ligase deadlocked on the last fragment's un-removable primer**: its
  eligibility gate (`not primer_removed → break`) is really a render-merge
  guard (don't merge a fragment whose own primer is still RNA), which happens
  to be a safe proxy for every fragment *except* the last, whose primer is
  permanent — so ligase parked forever. Diagnosed only after adding `[LIGASE]`
  prints (ligase was the one enzyme with zero console visibility). Fixed by
  sealing the last fragment's 5' nick anyway once the strand's complete.
- **Backbone merge treated intentional null slots as "not ready"**: the
  `frag_ready` guard blocked merging any fragment with a null slot — correct
  for a mid-flight base, wrong for an intentionally-empty telomere-gap slot,
  so a logically-sealed terminal fragment kept rendering its nick.
  `_is_telomere_gap_slot()` distinguishes the two.
- **Ligase kept its last-seal position across reloads (create-once-hide
  seam)**: `_ligase_reset_visual()` reset visibility/alpha/pulse but not
  position, so the next run's first seal slid in from mid-strand; and with no
  offstage rest spot its first-ever spawn dropped from the node's local
  origin. Same lifecycle-seam class as primase's own reset. Fixed with
  `_ligase_park_offstage()`.
- **`_terminal_removal_started` / `_polymerases_at_rest` not synced on
  scrub**: both once-per-run guards, set true on the first play and never
  cleared by scrub (which doesn't call `_lagging_reset()`), so a
  scrub-then-replay skipped the terminal removal / the rest slide. Same class
  as the `lagging_total_consumed` / `lagging_batch_cursor` scrub desyncs
  above — fixed by syncing both flags to the reconstructed phase in
  `_lagging_scrub_rebuild()`.
- **`PackedVector2Array` mutated through a parameter**: it's copy-on-write in
  Godot 4, so appending inside a helper mutated a local copy and the caller's
  line array never saw the bridge point — the retained-primer segment didn't
  connect. Fixed by returning the points and appending in the caller.

---

## Scene Structure

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
├── ComplexityManager (Node, %ComplexityManager)
├── LocaleManager (Node, %LocaleManager)
└── UI (CanvasLayer)
    ├── ComplexitySetupPopup           — shown at startup, before SequenceLoaderPopup
    ├── SequenceLoaderPopup
    └── PlayerUI                       — PlayerUI.tscn instance; `simulation`
                                         @export is editor-wired here via
                                         node_paths. REPLACED AT RUNTIME by a
                                         VerticalPlayerUI.tscn instance (renamed
                                         to "PlayerUI" to keep the path stable)
                                         when ZoomManager.vertical_mode is on —
                                         see simulation.gd's
                                         _swap_in_vertical_player_ui()

helicase.gd — added as child of simulation.gd at runtime via initialize_simulation()
replication_manager.gd — added as child of simulation.gd at runtime via initialize_simulation()
lagging_catchup_timer (Timer) — added as child of simulation.gd at runtime by
  replication_manager.gd, lazily on first use, on the base-complexity catch-up path
ligase (Ligase) — added as child of sim by replication_manager.gd's initialize(),
  created once, persists across sequence loads (visible toggled, not freed)
primase_blip (PrimaseBlip) — same lifecycle as ligase above
pol1 (Pol1Enzyme) — the one exception: NOT created in initialize() — true
  absence until its first job, instantiated on demand by
  replication_manager.gd's _pol1_kick(), persists once created. See SKILL.md's
  True-absence lifecycle entry.
```

`leading_polymerase` is not a scene node — it's created procedurally by
`replication_manager.gd` in `setup_backbones()`, same as before v70.6.
`lagging_polymerase_tween` is transient script state (not a scene node),
created/killed by `_lagging_fire_step()` and the scrub/reset paths.
