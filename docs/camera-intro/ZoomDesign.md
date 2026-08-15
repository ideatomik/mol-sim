# Zoom / Camera Design — v72 (pre-implementation)
_Design discussion, not yet implemented. Companion to DESIGN.md, SHARED_BASE_SEAM.md,
COMPLEXITY_MODEL.md, HelicaseDesign.md, and PolymeraseDesign.md. Written for a
demo build that diverges from the current roadmap order — this is a genuinely
new cross-cutting system, not an enzyme visual pass._

---

## Ground truth as of this pass

Read directly from `simulation.tscn`, `camera_controller.gd`, `simulation.gd`
(uploaded this session — supersedes any earlier assumption in this doc or
prior conversation):

- `Camera2D` is a **direct child of the scene root**, with `camera_controller.gd`
  attached to it directly — there is no separate camera-manager node today.
  `ThemeManager` and `LocaleManager` are sibling `Node`s at that same level;
  any new manager should sit alongside them, not under `replication_manager.gd`.
- `camera_controller.gd` does exactly one job: fit the **entire** `track_length`
  to 90% of viewport width, centered on `center_y` (the helicase's y — already
  documented as replisome-positioning's single source of truth), re-fitting on
  resize. This is, functionally, all of **level 1** as it exists today. There
  is no multi-level, multi-target, or follow logic to extend — it's a clean
  slate above level 1.
- `helicase_x` / `polymerase_x` are derived fresh every frame from
  `helicase_mgr`'s discrete slot state (`current_slot_index`, `get_eased_step_t()`),
  in both `_process()` (live play) and `scrub_to()` / `scrub_to_lagging_catchup()`
  (scrub) — never tweened, never independently clocked. Any camera-follow logic
  should read positions the same way: recomputed, not cached.
- **Leading/lagging polymerase nodes are owned inside `replication_mgr`**, not
  exposed on `simulation.gd` directly. `simulation.gd` only knows `polymerase_x`
  (a shared x-coordinate) and the two `polymerase_y_*` constants — it does not
  hold references to the clamp nodes themselves. Any zoom target registration
  for the polymerases has to come from `replication_manager.gd` (or the clamp
  scripts themselves), not from `simulation.gd`.
- **The lagging polymerase's per-fragment "jump back" is real, confirmed in
  code** (`scrub_rebuild`'s fragment-boundary handling, and the "jump back"
  language already in `PolymeraseDesign.md`'s open/close design) — not just a
  documented intention. Camera design for the lagging strand must treat this
  discontinuity as a first-class case.
- No `ComplexityManager` node exists yet — today's complexity toggles
  (`lagging_gap_enabled`, `ligase_enabled`) are plain `@export bool` fields on
  `simulation.gd` itself. Any complexity-tier branching this design needs (e.g.
  trombone loop on/off) will read those same flat exports for now, the same
  way `replication_manager.gd` already does — not a `ComplexityManager` API
  that doesn't exist yet.

---

## Where this system lives

**Extend `camera_controller.gd` in place, rather than adding a parallel node.**
It's already the script attached to the one `Camera2D`, it already has the
"recompute framing, apply to `zoom`/`global_position`" shape, and level 1 is
already exactly what it does — there's no reason to introduce a second node
that also has to reach into the `Camera2D` to move it. Level 1's current
behavior becomes one branch of a larger `match zoom_level:`; nothing about it
changes.

This still satisfies "architected as shared from day one" (your answer):
sharing doesn't require a *separate* node, it requires that the **registration
API** not be replication-specific. `camera_controller.gd` (candidate rename:
`zoom_manager.gd`, since it stops being just "the camera's controller" and
becomes the thing other systems register with — naming TBD, not load-bearing)
exposes a target-registry that any process manager can call into —
`replication_manager.gd` today, `transcription_manager.gd` /
`translation_manager.gd` later — without this file knowing anything about
replication internals.

---

## The core design problem: framing changes shape with complexity tier

Your framing example is the crux of this whole design:

> lagging polymerase at the current level would have the camera follow it
> back and forth as it works. With a trombone loop enabled, it would have to
> track it moving forward while also keeping the loop in view.

This rules out the design I'd sketched before seeing the files — a static
`level3_points: Array[Node2D]` handed to the camera once at registration time.
That works for "polymerase + helicase, both fixed node references," but it
silently breaks the moment a complexity toggle changes *what geometry needs to
be in frame* without changing *which enzyme* is focused. Same target, same
enzyme, different frame shape depending on `trombone_loop` on/off.

**Resolution: targets register a frame-provider `Callable`, not a static point
list.** Each frame, the camera calls it and gets back whatever points currently
need to be in view — the provider itself is where complexity-tier branching
lives, right next to the code that already knows the current tier (the same
place `lagging_gap_enabled`/`ligase_enabled` checks already live today):

```gdscript
# Conceptual shape — not final signatures
register_target(id: String,
                level3_frame_fn: Callable,   # () -> Array[Vector2]
                level4_frame_fn: Callable)   # () -> Array[Vector2]
```

For the lagging polymerase specifically, `level3_frame_fn` today (no trombone
loop) returns `[lagging_clamp.global_position, helicase_node.global_position]`.
Once trombone loop ships, that same function's body grows an
`if trombone_loop_enabled:` branch that also includes the loop's current
extent — the camera code itself never has to know trombone loop exists. This
is the same "gate behind toggles, preserve the old path" discipline SKILL.md
already mandates for enzyme visuals, just applied to camera framing.

This also cleanly answers the ownership question from `SHARED_BASE_SEAM.md`:
the *camera* (fit points to viewport, tween between states, handle scrub) is
shared; *which points matter and why* is supplied by whoever owns that biology,
exactly matching the seam already drawn for enzyme-spawning conventions.

---

## Zoom levels — what each one shows, and how it changes per enzyme/tier

### Level 1 — Overworld (existing, untouched)
Exactly today's `camera_controller.gd` behavior. No changes.

### Level 2 — The two new DNA molecules
Not enzyme-keyed, not player-cyclable. A single frame-provider (owned by
`replication_manager.gd`, since it owns both new-strand backbones) returning
the bounding extent of the leading + lagging synthesized-strand geometry so
far. Grows as synthesis progresses — recomputed live each frame, same as
everything else, so it's scrub-safe for free.

### Level 3 — Enzyme in context
Three player-cyclable targets at minimum, confirmed this session:

- **Leading polymerase** — context = itself + the helicase (per your original
  example: "shows its work on the new DNA and also the helicase unzipping the
  template"). Motion is continuous, monotonic — the easy case.
- **Lagging polymerase** — context = itself + the helicase. Motion is
  **discontinuous**: it advances with synthesis, then jumps back to the start
  of the next Okazaki fragment. The camera should not treat this jump as an
  error to smooth away — per PolymeraseDesign.md's own philosophy ("this
  asymmetry is itself a quiet teaching moment"), a visible pan-back on fragment
  boundary is arguably the *point*, not a bug to hide. Proposed: a bounded-speed
  tween (not instant, not floaty) on the frame update, so the back-jump reads
  as "the polymerase let go and restarted," not a camera glitch. **With
  trombone loop enabled** (future tier): the frame-provider must also include
  the loop's geometry, per the discussion above — net motion is forward with
  the fork while the visible loop content still cycles backward. This needs
  its own pass once trombone loop's actual visual shape is designed; flagging
  it here only as the reason the frame-provider pattern was chosen.
- **Helicase** — its own standalone target (confirmed this session). No
  natural "partner" the way each polymerase has one; context is most likely
  itself plus the immediate pre-fork bond it's about to break, so the
  bond-breaking moment (already timed to land exactly at `step_t == 1.0` per
  HelicaseDesign.md) is visible in frame. Open question below.

### Level 4 — Enzyme detail
Same target id as level 3 (focus persists), tighter fixed-radius frame instead
of a bounding box:

- **Leading/lagging polymerase** — the capture system (halo + two-leg capture
  animation from PolymeraseDesign.md), centered on the clamp's jaw.
- **Helicase** — the barrel-roll ring mechanics up close (the six-blob
  rotation and front/back z-swap from HelicaseDesign.md).

---

## Input: one API, many triggers (per your answer — keyboard + UI + click, voice later)

Every input method converges on the same handful of calls; no input method
computes camera math itself:

```
set_zoom_level(level: int)
select_target(id: String)     # direct selection — used by click-on-enzyme and (later) voice
cycle_target(direction: int)  # used by keyboard, and optionally UI prev/next buttons
```

- **Keyboard**: `_unhandled_input()` block mapping to the three calls above.
- **UI buttons**: PlayerUI (already in the scene tree) gets buttons per
  enzyme, each calling `select_target(id)` directly.
- **Click on enzyme**: needs a small `Area2D`/click-region per enzyme node
  (helicase, each clamp) that calls `select_target(id)` on input — not
  designed yet, needs its own pass once we know click targets are in scope
  for this demo vs. a later polish item.
- **Voice (later)**: a command dispatcher that resolves parsed intent to the
  same `select_target`/`set_zoom_level` calls. Nothing about this design
  should need to change when voice lands — that's the point of routing
  everything through this narrow API now.

---

## Scrub-safety — the split that makes this tractable

Two genuinely different motions, matching your answer ("instant for scrub,
animated for live play"):

1. **Live tracking within a level/target** — every frame, camera
   position/zoom is *recomputed* from the current frame-provider's live
   output. No tween, ever, regardless of play/scrub state — this is a derived
   value exactly like `helicase_x`, not an animation. This is what makes the
   lagging polymerase's back-and-forth safe to follow during scrubbing: scrub
   already sets `helicase_x`/fragment state instantly and synchronously
   (confirmed in `scrub_to()`), so a camera that just reads current positions
   each frame inherits that instantness for free.
2. **Level/target *changes*** — triggered only by discrete player input
   (never by playback or scrub). These get an animated tween during live play.
   If a scrub event fires mid-tween, the tween must be force-cancelled and the
   camera snapped straight to the end state — same pattern `helicase.gd`
   already uses (`set_phase()` forces state during scrub rather than tweening
   through it). Concretely: `scrub_to()`/`scrub_to_lagging_catchup()` in
   `simulation.gd` will need one added call into the zoom system's
   `scrub_snap()` so an in-flight level-change tween can't be caught
   mid-flight by a scrub.

The lagging-polymerase fragment-boundary pan (item 1, "bounded-speed tween")
sits in a gray zone worth flagging now: it's technically a tween, but it's
tracking within a level, not a level-change. Under the letter of the rule
above it would need to also snap instantly during scrub. Practically, this
probably just means: the pan is a *visual smoothing* clamp on the camera's
follow speed (a max-pixels-per-frame or critically-damped-spring clamp) rather
than a scheduled `Tween` object — so during scrub, the same clamp logic simply
lets the camera catch up over a couple of frames of *live play only*, and
`scrub_snap()` bypasses the clamp entirely and jumps straight to the target
position. Needs to be pinned down precisely during implementation, per the
same caution COMPLEXITY_MODEL.md gave the temperature/helicase interaction.

---

## Sequence length & viewport cropping (added this session)

New requirement: sequences in the hundreds of nucleotides, needed in
particular for PCR later. This breaks an assumption baked into level 1 today,
not just a scaling tweak.

### Why this isn't just "zoom out further"

`simulation.gd` currently hard-caps sequences at 57 bases
(`if sequence.length() > 57: truncate`), and `camera_controller.gd`'s entire
job is fitting the **whole** `track_length` into 90% of viewport width. That
cap almost certainly exists *because* "fit everything" stops being legible
well before 57 bases at any reasonable screen size — individual bases and
enzymes would shrink to unreadable size on a hundreds-long sequence. So this
isn't "raise the cap and let level 1 zoom out more" — level 1's fundamental
model (fit-the-whole-track) has to change for long sequences. Level 1 becomes
a **windowed/cropped camera at a fixed, readable zoom**, showing a scrolling
slice of the sequence rather than all of it at once.

### This reuses the level 3/4 machinery, not a new system

A windowed level-1 camera is, structurally, the same problem levels 3/4
already solve: "follow a focus point/region at a fixed zoom, recomputed live
each frame." The natural fit is to make level 1's long-sequence behavior use
the same follow/frame-provider pattern already designed above, just with:
- a wider, level-1-appropriate frame radius (enough slots to be useful context,
  not the tight enzyme-detail radius of level 4)
- a **manual pan/scroll override** layered on top, since "and/or follow the
  helicase or something else" implies the player needs to be able to look
  somewhere the auto-follow isn't currently pointing (e.g. checking on the
  lagging strand's completed region while the helicase is still working
  further along)

### Manual pan vs. auto-follow — needs a defined interaction, not just both existing

Both auto-follow and manual scroll can't be simultaneously "in control" of the
same camera position without a defined precedence rule. The common pattern
(RTS/MOBA cameras) is: manual input immediately takes precedence and disengages
auto-follow; something explicit (a "recenter on helicase" button/key, or an
inactivity timeout) re-engages follow. This needs a decision, not just an
assumption — see open questions below.

### Threshold: nucleotide count or viewport math?

Rather than a hardcoded "cropping kicks in above N bases" constant, this
should probably be computed the same way `_frame_strand()` already computes
its zoom — i.e. "does fitting the whole track at the minimum readable zoom
still exceed the viewport" — so short sequences keep today's exact
fit-to-whole behavior with zero behavior change, and the windowed mode only
engages once the sequence genuinely doesn't fit. Avoids a magic number that
has to be hand-tuned again if `nucleotide_slot_spacing` or the minimum
readable zoom ever changes.

### Confirmed level-1 follow behavior (this session)

- **Auto-follow is on by default** at level 1 for long sequences — resolves
  the open question above.
- **Asymmetric margin, not centered framing.** Today's fit-to-whole-track
  centers content with an even margin on both sides. The windowed mode
  instead keeps a fixed **10% of viewport width as a left margin only** — the
  focus point sits near the left edge of the screen, and the remaining 90%
  of the viewport shows track ahead of it. Content beyond the viewport's
  right edge is simply not drawn (clipped), which is the natural consequence
  of a fixed-zoom window rather than a special case to build.
  In coordinates: with `viewport_width_world = viewport_width_px / zoom`,
  `camera.global_position.x = focus_x + 0.40 * viewport_width_world` places
  `focus_x` at the 10%-from-left mark instead of screen-center.
- **The follow anchor, during play or forward-scrub**: the x midpoint between
  `helicase_x` and `polymerase_x` (leading polymerase) — `(helicase_x +
  polymerase_x) / 2.0`. Notably **not** the lagging polymerase. Both
  `helicase_x`/`polymerase_x` are monotonic forward movers (unlike the
  lagging polymerase's per-fragment jump-back), so this anchor is guaranteed
  smooth by construction — the lagging polymerase's jank simply never reaches
  the level-1 camera. Worth confirming this exclusion is deliberate rather
  than incidental, since it's the reason this anchor works cleanly.

### PCR flag (not designed here)

You noted this is particularly needed for PCR. Per `SHARED_BASE_SEAM.md`'s
build order (transcription → translation → PCR), PCR's camera is out of scope
for this pass — and it's a harder problem than windowing (PCR has *many*
molecules, an exponentially growing population, not one long strand), so it
likely needs its own design pass rather than inheriting this one directly.
Flagging only so the windowing model above isn't accidentally built in a way
that assumes "exactly one strand" and has to be re-architected later.

### Open questions this section adds

- ~~Is auto-follow on by default at level 1 for long sequences?~~ **Resolved:
  yes.**
- ~~What does level-1 auto-follow lock onto?~~ **Resolved: midpoint of
  `helicase_x` and `polymerase_x` (leading), not the helicase alone.**
- **Scrub *backward*, and paused state**: **deferred — decide once visible
  in-engine.** The anchor formula would technically keep working unchanged in
  either direction (it's just a live recompute), so this is purely a framing
  taste call, not a technical blocker. Flagging as the one item in this
  section to revisit visually before considering the windowed camera done,
  rather than something to pre-decide on paper.
- **Fixed zoom value**: **resolved — reuses whatever `_frame_strand()`
  computed at the old 57-base cap.** This preserves today's exact per-base
  pixel scale; nothing about how a base/enzyme *looks* changes the moment a
  sequence crosses into windowed territory, only the framing/margin behavior
  does. Concretely, this is a value to capture once (e.g. by calling the
  existing fit-to-width formula with a fixed reference length of 57 rather
  than the live `track_length`), not something the windowed mode recomputes
  per sequence.
- **Boundary conditions at the ends of the sequence**: **resolved — no
  clamping.** The `(helicase_x + polymerase_x) / 2.0` anchor and the
  10%-left-margin rule apply uniformly all the way through, including the
  finishing/DONE phases where `helicase_x` overshoots past `track_length`
  and the very start of an intro. This means the window *will* show empty
  space past the actual track's end during finishing/DONE and at the very
  start of a run — an accepted tradeoff for keeping one uniform rule rather
  than special-casing the edges.
- Does manual pan release back to auto-follow via an explicit action
  (button/key) or an inactivity timeout — or both?
- Does the windowed camera apply only to level 1, or does level 2 ("the two
  new DNA molecules") also need windowing once the synthesized region itself
  exceeds a viewport's worth of width on a long sequence? Seems likely, not
  yet confirmed.

---

## Open questions before implementation

- **Helicase's level-3 context**: itself alone, or itself + something ahead
  (upcoming hydrogen bond, template strand)? Not yet decided.
- **Complexity-tier gating of the zoom system itself**: does level 3/4 exist
  at all complexity tiers, or is it reserved for tiers sophisticated enough
  to have distinct enzymes worth zooming into (mirrors the gating logic
  already used for `topoisomerase_enabled`)? Probably moot for the near-term
  demo (base tier only) but worth naming now.
- **Exact framing math** (padding, min/max zoom per level, aspect-ratio
  handling) — deferred until we're looking at real numbers in-engine.
- **Click-region hitboxes per enzyme** — in scope for this demo pass, or a
  later polish item? Affects whether it's designed now or stubbed.
- **Naming**: `camera_controller.gd` extended in place vs. renamed to
  `zoom_manager.gd`. Cosmetic, but touches the `ext_resource` path in
  `simulation.tscn` if renamed — flagging so it's a deliberate choice, not an
  accidental rename mid-diff.
- **Level 2 → level 3 target memory**: if the player was on "leading
  polymerase" at level 3/4, zooms out to level 2, then back to level 3/4 —
  does it resume the same target, or reset to a default (e.g. always leading
  polymerase first)? Not yet decided.

---

## Suggested next step

Once you're back at this: confirm the open questions above (especially
helicase's level-3 context and the click-region scope), then I can draft the
actual `register_target`/`select_target` signatures and the frame-provider
function bodies for each of the three level-3/4 targets against the real
`replication_manager.gd` (not yet uploaded — needed before any code, since
that's where the polymerase clamp node references actually live).

---

## ⚠️ EVERYTHING ABOVE THIS LINE IS STALE (pre-implementation, v72)

The document above predates the actual build in ways that no longer match
what's running: single `camera_controller.gd` directly on the scene root (now
`zoom_manager.gd`, its own node), a Level 1-4 scheme (Level 4 was later
removed entirely — entry_level is 2 for every registered target now, not 3),
no `ZoomManager`, no `ComplexityManager` (both exist now). This needs its own
full rewrite pass — same size job as the other Tier 2 docs on TODO.md
(`OkazakiMaturationDesign.md`, `PolymeraseDesign.md`) — not attempted here.
The addendum below covers Follow Mode specifically, as actually shipped, and
should be treated as the only currently-accurate section in this file.

---

## Follow Mode — As-Built (shipped this session)

Anticipated in this doc's own "Manual pan vs. auto-follow" and scrub-safety
sections (the "critically-damped-spring clamp… during scrub, same clamp
logic simply lets the camera catch up over a couple of frames of live play
only" note) — implemented as a genuinely fourth mutually-exclusive camera
state in `zoom_manager.gd`, alongside free camera and the level-based target
system (not a variant of either):

- **Entry point**: `request_follow(id)` — the single funnel point for
  "double-click an enzyme," mirroring `select_target()`'s own role for other
  input methods. Double-clicking the already-followed enzyme instead toggles
  highlight (second trigger for HighlightButton); double-clicking a
  *different* enzyme switches directly; double-clicking empty background
  routes through `reset_zoom()`.
- **Position**: derived every frame from the target's own entry-level frame
  provider, position only — the provider's zoom half is ignored entirely.
- **Zoom**: held independently in `_follow_zoom`, seeded from whatever zoom
  was already showing on entry ("keep the wheel-set zoom"), changed only by
  scroll, clamped to a dedicated `tm.zoom_follow_min_zoom` floor — tighter
  than free camera's whole-track-fit floor by design, not reused from it.
- **Scope**: helicase and lagging polymerase only. `polymerase_clamp.gd` is
  shared by both leading and lagging, so it emits `follow_requested`
  unconditionally, but only `replication_manager.gd`'s lagging-clamp
  connection actually wires it to `request_follow()` — leading stays
  follow-inert at the connection site, not in the shared script.
- **Background press-and-hold while following** (the part this doc didn't
  anticipate — no click-region-vs-background distinction existed yet when
  this was written): freezes the camera in place immediately on press
  (`_follow_paused`), then resolves on release — a quick tap (<250ms, no
  movement) drops follow and enters free camera from wherever the camera
  already was; a hold or hold-then-drag resumes follow, eased back over
  `tm.zoom_follow_resume_duration` via cubic ease-out. The ease recomputes
  its target from the LIVE frame provider every frame rather than a frozen
  snapshot — the followed enzyme keeps moving during the ease (it doesn't
  pause with the camera), so a fixed-endpoint tween would produce a visible
  second jump right as it finished.
- **Scrub-safety**: confirms this doc's own prediction almost exactly.
  `scrub_snap()` bypasses the resume-ease entirely and jumps straight to the
  live target — same "clamps are live-play-only" split already anticipated
  above for the lagging-polymerase fragment-boundary pan.
- **Click detection**: same manual `_point_in_click_region()` hit-test
  drag-to-scrub already used (Area2D picking still avoided for the same
  silent-failure reasons), gated on Godot's own `event.double_click` flag —
  no manual timing needed. Surfaced a real, unrelated bug in the process: the
  drag-to-scrub gesture had no pixel dead zone, so the incidental jitter
  between a double-click's two presses was committing to a drag and pausing
  playback. Fixed with a `DRAG_DEADZONE_PX` (6px, NOT YET TUNED) in both
  `helicase_ring.gd` and `polymerase_clamp.gd` before a press commits to
  dragging at all — same fix, independent of Follow Mode, benefits ordinary
  single-click-drag scrubbing too.

New ThemeManager exports (`Follow Mode` subgroup): `zoom_follow_min_zoom`,
`zoom_follow_resume_duration`. Both NOT YET TUNED — placeholders pending real
numbers in-engine, same convention as this file's other zoom constants.
