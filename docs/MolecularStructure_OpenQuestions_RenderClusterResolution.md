Zymulador — Molecular Structure Design: Open Questions
Resolution pass — render-mode / zoom / culling cluster (Q4, Q7, Q8, Q9)
=====================================================================
This resolves the render-mode cluster only. Q1 (aconitase), Q3 (stereo),
Q5 (operator format), and Q6 (ATP bead migration) are untouched by this
pass and remain exactly as in the source doc.

One general caveat applied to every decision below when this pass was
first drafted: reasoned from ZoomDesign.md (v72, pre-implementation) and
the corrections already logged in MolecularStructureDesign.md — NOT from
a fresh read of zoom_manager.gd. That gap is now closed.

**VERIFIED against zoom_manager.gd (full read, 1,017 lines) — the zoom-
scalar direction convention:** zooming IN increases the numeric `zoom`
value; zooming OUT decreases it toward a floor. Confirmed three
independent ways in the live code: `_compute_free_camera_min_zoom()` is
explicitly commented "the zoom-out FLOOR" and shrinks as track length
grows (more world to fit -> smaller number); the free-camera clamp's
upper bound is literally named `tm.zoom_free_camera_max_zoom_in` (large
number = deepest zoom-in); and `MOUSE_BUTTON_WHEEL_UP` (conventional
zoom-in gesture) multiplies (increases) `_free_camera_zoom` in
`_free_camera_scroll_zoom()`. `ZoomDesign.md`'s Follow Mode section
independently uses the same min-is-out/max-is-in language for
`zoom_follow_min_zoom`, confirming this isn't free-camera-specific.

This resolves the "min"/"max" naming question below: the two hysteresis
thresholds are an ENTER threshold (higher zoom value, crossed going up ->
activates skeletal rendering) and an EXIT threshold (lower zoom value,
crossed going down -> deactivates), with enter > exit — a standard
Schmitt trigger, checked as `zoom >= enter_threshold` /
`zoom < exit_threshold`. No longer a placeholder pending verification.


4. WHERE DOES RENDER-MODE SELECTION LIVE?  [DECIDED]
---------------------------------------------------------
Decision: a continuous zoom-scalar threshold inside free-camera mode.
Not an explicit user toggle. Not a new (fifth) camera state.

Reasoning: level-based zoom tops out at level 3 (enzyme-in-context) —
there is no level 4, by deliberate prior decision. Anything deeper than
that has to come from free camera, which is already continuous (pan +
zoom, unconstrained by the level system) — that IS what free camera is
for. A toggle would work mechanically but fights the pedagogy this
subsystem exists for: the seed problem is specifically about what
changes as a student leans in, and a manual switch turns that into a
mode a student has to know exists rather than something that just
happens as they get closer, the way a real microscope does.

Concrete shape — hysteresis band, mandatory, now confirmed against
zoom_manager.gd (see the top-of-file verification note): zooming in
INCREASES the numeric `zoom` scalar, zooming out decreases it toward a
floor. Two threshold values are needed, not one:
  - `molecular_zoom_enter_threshold` (higher zoom value) — crossing it
    while zoom is INCREASING (zooming closer) activates skeletal
    rendering: `zoom >= molecular_zoom_enter_threshold`.
  - `molecular_zoom_exit_threshold` (lower zoom value, strictly less
    than the enter threshold) — crossing it while zoom is DECREASING
    (pulling back) deactivates skeletal rendering:
    `zoom < molecular_zoom_exit_threshold`.
A single shared threshold would flap the instant scroll direction
reverses by one tick at the boundary — this is not optional polish, it's
required for the feature to be usable at all. Both values should be
Inspector-tunable, per existing project convention (ThemeManager,
alongside the other zoom-tuning floats).


7. DOES MOLECULAR ZOOM BELONG INSIDE FREE-CAMERA MODE AT ALL?  [DECIDED]
-----------------------------------------------------------------------------
Decision: yes. See question 4 — this is the same decision from the other
angle, not a separate one to re-derive.

current_target_id: free camera already clears it today (kills highlight
dimming). Decision: do NOT special-case molecular render-mode to
preserve or restore it. Free camera already accepts this cost for
everything else; carving an exception out specifically for the render
swap would introduce a new coupling between render-mode and
target-tracking that nothing currently justifies, and it sits outside
this milestone's scope fence regardless. If this turns out to matter
once it's visible on screen, that is a future, explicit, separately-
scoped decision — not something to build speculatively now.


8. IMMEDIATE-MODE RENDERING VS. ATOM PICKING  [DECIDED for the DNA milestone]
------------------------------------------------------------------------------------
Decision: immediate-mode rendering, per the design doc's existing lean
(nucleotide_field.gd's pattern — large-count case). Atom picking
(hover/click at the per-atom level) is explicitly OUT OF SCOPE for this
milestone. Nothing in the scope fence (ribose + phosphodiester operator
+ skeletal rendering) requires it.

Cheap-insurance requirement, not scope creep: whatever function computes
per-atom layout positions each frame must write them into a STORED
structure — an array of {position, element, atom_id} per atom — that
_draw() then iterates, rather than positions living only as local
variables inside the draw call that vanish afterward. This costs a few
lines now and means a future atom-picking pass is "iterate the same
array with a hit-test," not a rebuild of the layout code. Same
discipline already used for helicase_x: computed once, read by more
than one consumer, never duplicated.


9. WHAT IS THE CULLING UNIT?  [DECIDED for the DNA milestone]
--------------------------------------------------------------------
Decision: per-molecule bounding-box culling ONLY. Do not build the
per-atom fallback for this milestone.

Reasoning: the doc's own estimate puts the DNA milestone's working set
at a handful of nucleotides (~30 atoms each) visible at once at
molecular zoom — nowhere near the measured ~1,200-glyph ceiling that
per-atom culling exists to protect against. Building the fallback tier
now would be complexity added against a bottleneck that hasn't been
demonstrated to exist at this milestone's scale — the same violation
"complexity layers build upward, not sideways" already warns against
elsewhere in this project.

Required alongside shipping the bbox-only version: leave an explicit,
named comment at the cull site citing the 1,200-glyph ceiling and this
deferred fallback — same treatment as the aconitase exception (question
1): a flagged gap, not a silent one. The actual profiling pass belongs
with Krebs (more stations, more atoms, more likely to approach the
ceiling), not here.


10. RENDER-MODE TRANSITION MECHANICS  [DECIDED — new, addendum to Q4/Q7]
-------------------------------------------------------------------------------
Not in the source doc's original numbering; added because it surfaced
while resolving Q4/Q7 and needs to ship correctly the first time, not be
retrofitted after a hard cut is already built and found wanting.

Two SEPARATE failure modes exist at the threshold crossing — treat them
separately, do not assume solving one solves the other:

  (a) A one-time HITCH exactly at the crossing (cost).
  (b) A visual "pop" from the hard cut (appearance).

Decision on (a) — hitch: layout computation runs EVERY frame regardless
of which render mode is currently active; only the draw calls are gated
behind the render-mode check. Do not compute the skeletal layout lazily
on first crossing — that guarantees paying for the fold-and-position
pass exactly on the frame a low-spec machine can least afford it. The
doc's own numbers make always-computing cheap: ~30 atoms, microseconds,
smaller still at this milestone's one-operator scope. If atom labels
need their own font/size, prefer reusing a size already drawn elsewhere
on screen, to avoid a first-crossing glyph-atlas-build stall; if a
dedicated size turns out to be needed, that is a specific thing to watch
for in CQA, not something to assume away.

Decision on (b) — hard cut ships first, as the buildable baseline. No
crossfade or blur in the first implementation. This is deliberate, not
a placeholder to feel bad about: a video-game-style "objective lens
refocus" treatment (crossfade or short defocus) is a reasonable next
layer, but whether it's actually needed can only be judged by CQA on
low-spec hardware — it may turn out the hitch in (a), once fixed, is
the whole problem and the cut itself never reads as a pop worth masking.

IF a transition treatment is added later, these constraints are not
optional:

  - It must be a PURE FUNCTION of the live zoom scalar, recomputed every
    frame — never a triggered or timed animation. A "loading screen"-
    style state machine (enter/wait/exit, timed) is the one framing to
    avoid literally: it would let a scrub jump past the threshold with
    no cover (state desync), or replay repeatedly on a scrub oscillating
    near the boundary — the exact real-time-pacing failure mode this
    project has already hit and fixed once elsewhere (see SKILL.md on
    event-count gating vs. real-time pacing). Scrubbing to any zoom
    value, from anywhere, must show the correct blend amount instantly.
  - It must reuse the SAME TWO hysteresis thresholds from question 4 as
    its start/end points — not a separate pair of blur-specific
    tunables. Two thresholds meant to describe the same crossing, tuned
    independently, is the exact "never let two independently-tuned
    numbers coincidentally agree" trap this project already has a name
    for (see ATPCycleDesign.md's As-Built note on the raw/eased dead-
    band mismatch).
  - Default treatment if/when added: a CROSSFADE (draw both renderers,
    modulate alpha across the band) — reuses the ghosting/fade idiom
    already used elsewhere in this codebase (near-zero additional cost,
    no shader). Reach for an actual blur shader only if CQA shows the
    crossfade doesn't sell "refocusing" convincingly — and if so, scope
    it tightly: only the molecule's own on-screen region, only within
    the narrow zoom band around the threshold, never full-screen, never
    always-on.
  - Category of state: camera/view state, same bucket as layer/
    occlusion visibility — lives with zoom_manager.gd's zoom scalar,
    NEVER regent-derived, NEVER touched or reset by scrub_rebuild().
    Read the live zoom scalar fresh each frame (same live-read pattern
    already used for rotation in nucleotide_field.gd) — do not cache it
    at _ready() and risk a stale pre-orientation value from sibling
    _ready() ordering.

Explicitly deferred to CQA, not designed further here:
  - Whether the hard cut needs a transition treatment at all.
  - Whether a defocus effect specifically reads as "the instrument
    refocusing" rather than "something dissolving" — one glance worth
    checking given this project's standing caution against visual
    metaphors that could teach something false, but very likely a
    non-issue given how conventional a focus-pull read is.

=====================================================================
Status after this pass: questions 4, 7, 8, and 9 are DECIDED and
buildable. Question 10 (new) is DECIDED for the hard-cut baseline, with
its future-layer constraints specified in advance so a later addition
doesn't have to be re-derived. Nothing in this cluster blocks starting
implementation of the DNA milestone's scope fence (ribose +
phosphodiester operator + skeletal rendering).
