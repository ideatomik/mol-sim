# DNA Unwind Intro — Current State

Briefing summary of the startup intro animation, written after the
Inspector-tunable-speed/duration + crossfade-dismiss pass (2026-08-09).
Grounded directly against `scripts/dna_unwind_intro.gd` as it stands today.

## What it is

A short, skippable animation that plays right after a sequence is loaded and
before the live rail view appears: a simplified twisted double helix spins
in, then settles bead-by-bead into the exact flat layout the live view is
about to show, so the handoff reads as one continuous motion rather than a
cut. It's a bead-tier abstraction — real per-base colors and hydrogen-bond
styling, but no base-letter labels, no 5'→3' arrows, no derived molecular
geometry.

## The files

| File | Role |
|---|---|
| `scripts/dna_unwind_intro.gd` | The entire animation — `extends ColorRect`, both draws itself (`_draw()`) and *is* the full-screen overlay (no separate overlay node). |
| `scenes/DnaUnwindIntro.tscn` | Trivial wrapper scene: a `ColorRect` root with the script attached, `z_index = 51`, full-rect anchors, `visible = false` by default, dark-navy fill. |
| `scenes/simulation.tscn` | Instances `DnaUnwindIntro.tscn` under `UI` as `%DnaUnwindIntro` (unique name). |
| `scripts/player_ui.gd` | Orchestrator/caller — see Data flow below. |

## Data flow

`player_ui.gd`'s `_on_sequence_loaded()` (:591) initializes the simulation,
then looks up `%DnaUnwindIntro` and calls `_play_dna_intro()` (:617). That
function gathers the *real* on-screen values the live rail view itself would
use — per-base colors via `ThemeManager.get_base_color()`, real pixel
spacing/gap/bead-size/bond metrics pre-multiplied by the real camera fit
zoom (reproducing `zoom_manager.gd`'s `_compute_track_fit_zoom()` formula
exactly) — and passes them into `dna_intro.play(...)` (:656). This is why
the intro's end state matches the live view's geometry by construction
rather than by separate tuning: the script does no `ThemeManager` or
simulation lookups of its own.

`player_ui.gd` connects `intro_finished` one-shot (:605) to
`_on_sequence_loaded_intro_done()`, which resumes the deferred post-load
flow (camera reframe, etc.) — the intro is a gate this flow waits behind.

## Motion model — two sequential phases

**1. Rotation.** Only `rotation_angle` moves; everything else (rotation
radius, strand gap, bead radius, bond bundle width/spacing) is a plain
constant throughout, matching the original p5.js reference sketch's fixed
`h`/`space`/`size`. Rotation runs at a constant angular rate through every
lap but the last, which eases out via a cubic Hermite curve
(`-u³+u²+u`, continuous-slope-in / zero-slope-out — see `_rotation_state()`,
:294) so freezing reads as a glide-to-a-stop, not a sudden wall.

Rotation doesn't freeze at a fixed clock time — `_process()` (:318) watches
the rightmost bead pair during the final lap for the natural instant its
rotating Y already coincides with its real resting Y (a zero-crossing check
on `diff`), and triggers settle right then, so the first bead to move needs
zero motion to "start." Falls back to triggering at `rotation_duration_seconds`
if that coincidence never occurs, so the animation can never get stuck.

**2. Settle.** Once triggered, each bead individually glides in Y from its
frozen rotating pose to its real resting row, staggered right-to-left
(`_draw()`'s per-slot loop, :519) so the strand appears to settle as a wave.
Backbone points ride the exact same `slot_t` lerp as their bead, so the
handoff to the live view's own backbone lines is seamless.

A small ambient wobble (`_wobble_y()`, :407 — same hash-seeded per-bead jitter
as `simulation.gd`'s real strand) layers on top of both phases throughout.

## Rotation math (depth/occlusion)

The two beads at a slot are a real rotating pair, not an ad hoc vertical
oscillation — reusing the same technique `docs/HelicaseDesign.md` shipped
for the helicase ring's barrel-roll: a body rotating in the Y-Z plane,
viewed edge-on. Screen Y comes from `cos(phase)` (one bead, its pair is the
exact negative); the unrendered depth axis is `sin(phase)`, and its **sign**
decides which bead draws in front this frame. That sign only flips at
phase extremes (0, π, ...) — exactly where the pair is at maximum Y
separation, so the flip is invisible — giving the barber-pole crossing look.

Backbone points are a second point on the same rotating rod as their bead
(same phase/`mean_cos`, radius `rotation_radius + backbone_offset_px`), and
reuse their bead's own `top_is_front` for z-order directly (real backbone
sits outside the helix, bases inside) — see
`docs/superpowers/specs/2026-08-08-dna-intro-backbones-design.md` for the
full derivation.

## Tunable knobs (`@export var`, Inspector-adjustable on the `DnaUnwindIntro` node)

| Var | Default | Controls |
|---|---|---|
| `rotation_duration_seconds` | 4.4 | Wall-clock length of the rotation phase (nominal — can end earlier via the natural-coincidence trigger). |
| `total_spin_turns` | 3.0 | Full rotations over the rotation phase; combined with the duration above, sets angular speed. |
| `settle_stagger_seconds` | 1.0 | Span across which per-bead settle *start* delays spread right-to-left. |
| `settle_lerp_seconds` | 0.4 | How long each individual bead's own settle glide takes once its turn arrives. |
| `crossfade_duration_seconds` | 0.5 | How long the overlay's fade-out takes once dismissed. |

`_total_duration_seconds()` (:124) sums the three duration/stagger/lerp
values as a worst-case ceiling (used to clamp `_elapsed` and by the debug
freeze) — not the real finish condition, which is the dynamic trigger above.

Non-exported `const`s that affect the visual but aren't speed/duration knobs:
`SPATIAL_TWIST_DENSITY` (visual twist density, decorative), `BP_PER_TURN`
(real biological base-pairs-per-turn), `ROTATION_RADIUS_RATIO` (ties the
twist's footprint to the real strand gap), `BOND_INSET_RATIO` (H-bond line
inset from bead center). `FREEZE_AT_TWISTED_STATE`/`FREEZE_T` are temporary
debug scaffolding for iterating on geometry in isolation — not shipped
behavior, meant to be removed once no longer needed.

## Dismiss / crossfade

`_input()` (:363) watches for any mouse-button or key press while playing,
consumes it (`set_input_as_handled()`), and calls `_finish()` — the same
endpoint `_process()` calls on natural completion (:349), so skip and
natural-finish behave identically.

`_finish()` (:374) sets `_playing = false` and emits `intro_finished`
**immediately** — this is what actually unblocks the simulation underneath,
since `_input()` gates on `_playing` — then starts a `create_tween()`
fading `modulate:a` to 0 over `crossfade_duration_seconds`. On tween
completion, `_on_crossfade_finished()` (:387) sets `visible = false` and
resets `modulate.a = 1.0` so the next `play()` call starts fully opaque.
Net effect: the simulation becomes interactive the instant you dismiss the
intro, while the overlay itself visually fades out on top rather than
snapping away.

## Related docs

- `docs/superpowers/specs/2026-08-08-dna-intro-backbones-design.md` / `docs/superpowers/plans/2026-08-08-dna-intro-backbones.md` — design + plan for the backbone-line addition (already shipped, matches current code).
- `docs/superpowers/specs/2026-08-07-dna-spiral-continuous-spin-design.md` — earlier design for the "physically correct rotation" model (the cos/sin depth trick above).
- `docs/HelicaseDesign.md` / `docs/Topoisomerase.md` — origin and naming ("z-order + periodic-crossing pattern") of the rotating-pair occlusion technique this script reuses.
