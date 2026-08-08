# DNA spiral intro: continuous-spin rework

## Context

`scripts/dna_unwind_intro.gd` (+ `scenes/DnaUnwindIntro.tscn`) plays a startup
animation when a sequence loads: a simplified twisted double helix that
unfurls into the flat, parallel-ribbon convention the rest of the app uses.
It's driven entirely by real on-screen values passed in from
`player_ui.gd`'s `_play_dna_intro()` (colors, spacing, gap, backbone/rung
widths), so its end state is an exact match for the live rail view.

The reference the twisted-pose geometry was originally built against is a
p5.js sketch (a classic rotating-DNA-ladder effect):

```js
angle = angle + frequency;
for (i = 0; i < length; i += space) {
  let radian = radians(angle + i);
  line(i, h*sin(radian), i, h*cos(radian));
  ellipse(i, h*sin(radian), size, size);
  ellipse(i, h*cos(radian), size, size);
}
```

The key thing this reference does that the current script doesn't: `angle`
increments every frame, forever, with nothing that ever holds it in place.
The current script instead splits into two sequential phases — phase 1
spins a frozen twisted pose in place for `ROTATE_DURATION_SECONDS`, then
*stops* rotating and phase 2 unfurls that held pose flat over
`UNFURL_DURATION_SECONDS`. That stop-then-unfurl seam is the specific
mismatch driving this rework.

## Goal

Replace the two-phase (rotate-in-place, then unfurl) structure with one
continuous animation: rotation spins at a constant angular speed for the
entire duration, while the unfurl easing (amplitude shrinking to 0, slot
spacing spreading out to final positions, strand gap growing to its real
value) runs *concurrently* over that same window instead of being sequenced
after rotation stops.

Everything else about the current script is kept:
- Per-base rung colors (`_top_colors`/`_bottom_colors`), not the reference's
  uniform stroke/fill.
- The backbone polylines connecting rung-tops and rung-bottoms into two
  continuous curves (the reference has no such curves — bare rungs only —
  but they're being kept here).
- The sin(phase)/cos(phase) quarter-turn relative offset between top and
  bottom strands (confirmed live to be what reads as an organic twist
  rather than flat crossing sine waves).
- The mean-offset correction (`mean_sin`/`mean_cos`) that keeps each strand
  averaging out to its true baseline regardless of turn count or rotation
  angle — its closed form already takes an arbitrary `rotation_angle`, so it
  needs no changes for continuous rotation.
- Masking-circle rung end caps, gap-from-zero (so strands actually cross
  during the twisted phase), ease-out cubic easing curve, skip-on-any-input.

## Design

### Timing model

- Collapse `ROTATE_DURATION_SECONDS` + `UNFURL_DURATION_SECONDS` into a
  single `TOTAL_DURATION_SECONDS` (start from the current sum, 4.4s, as the
  live-tuning baseline).
- `unfurl_progress = clamp(_elapsed / TOTAL_DURATION_SECONDS, 0, 1)`,
  eased with the existing ease-out cubic, driving amplitude/spacing/gap
  exactly as today — except `eased_t` now starts from literal 0 instead of
  the frozen `ROTATE_PHASE_T`. The degenerate zero-spread instant at t=0 is
  no longer *held* (that was only a problem because phase 1 held it for
  2.2s), so it's a non-issue for a continuously-easing single phase.
- `rotation_angle = _elapsed * angular_speed`, running for the whole
  duration at a constant rate — no hold, no phase boundary. `angular_speed`
  replaces `ROTATION_TURNS` (e.g. `TOTAL_SPIN_TURNS * TAU / TOTAL_DURATION_SECONDS`,
  keeping a "turns" constant as the tunable knob rather than raw
  radians/sec). Since amplitude eases to 0 by the end, continued rotation
  after the strand is visually flat is harmless (sin/cos terms vanish) —
  no need to stop it early.
- `ROTATE_PHASE_T`, `ROTATE_DURATION_SECONDS`, `UNFURL_DURATION_SECONDS`,
  `ROTATION_TURNS` are removed; `TOTAL_DURATION_SECONDS` and
  `TOTAL_SPIN_TURNS` replace them.

### Debug freeze scaffolding

`FREEZE_AT_TWISTED_STATE`/`FREEZE_T` exist to inspect the twisted-pose
geometry in isolation while iterating. With no more distinct "held twisted
phase," freezing now just means pinning `_elapsed` at an arbitrary point
within the single continuous timeline (still dismissible via click/keypress
like today). Same mechanism, adjusted for the new timeline — kept, since
live-tuning the new geometry is exactly what it's for.

### Tightness

"Denser/tighter twist" is a tuning target, not a derived value — same as
`ROTATION_TURNS` already was ("decorative only — no real quantity to derive
this from — live-tune by eye"). `TOTAL_SPIN_TURNS` (temporal density) and
the existing `BP_PER_TURN`-derived spatial winding are both candidates to
adjust; exact values get tuned live in the running app against the real
strand data, not pinned in this spec.

### Out of scope

- No change to `player_ui.gd`'s `_play_dna_intro()` or the data it passes
  in — this is a pure `dna_unwind_intro.gd` geometry/timing rework.
- No change to per-base coloring, backbone curves, or masking-circle caps.

## Testing

Visual only — run the app, load a sequence, watch the intro play, iterate
on `TOTAL_SPIN_TURNS`/`TOTAL_DURATION_SECONDS`/spatial turn density by eye.
No automated test coverage exists for this script today and none is being
added (pure `_draw()`-driven visual animation).
