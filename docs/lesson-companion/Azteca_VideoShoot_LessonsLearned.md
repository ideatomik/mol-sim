# Video Shoot Lessons & Pain Points — Field Input for Azteca (Lesson-Prep Companion)

_Companion to `LessonPrepCompanion_ConceptNote.md`. That note flagged its
one-line teacher-conversation summary as a placeholder for "a real
Nucleation pass grounded in the actual teacher conversations." This isn't
that — it's a different kind of grounding: producing the "O Sentido da
Vida" promo video required doing, by hand, almost exactly what Azteca is
meant to automate — picking a sequence, choosing an enzyme configuration,
choosing a zoom tier, and staging what's revealed and when to tell a
specific story. Every friction point below is a friction point a teacher
would also hit, just compressed into one all-nighter instead of spread
across a term's worth of lesson prep._

---

## Context

Four camera shots (A–D) needed to demonstrate specific replication
concepts on a tight schedule, each requiring a hand-picked sequence,
complexity configuration, zoom tier, and label state, choreographed
against independently-recorded voice-over whose exact timing wasn't known
until the audio was trimmed. This is the same shape as "describe your
lesson, get a ready Zymulador scene" — just with a camera script standing
in for a lesson plan.

---

## Pain points

### 1. Configuration knowledge lives in Claude/Claude Code's heads, not in the tool

Every shot needed a specific combination of toggles to read clearly:
Okazaki Fragment Size manually tuned down to 6 (from its normal default)
specifically so the lagging strand's back-and-forth motion would be
visible in an ~11s window; a 57-nt sequence chosen because it's long
enough to show real structure but short enough to stay legible at
level-2 zoom; `complexity_mgr.set_pol1_enabled(true)` chosen knowing (not
discoverable in-tool) that it cascades primase and ligase along with it.
None of this is written down anywhere a teacher — or a non-expert
producer — could find it. **Azteca's core job is exactly this: encoding
"which configuration reads well for which concept" as reusable,
inspectable knowledge, not tribal knowledge held by whoever built the
sim.**

### 2. No way to preview or query timing before recording

Predicting when the lagging polymerase would first fire required manual
arithmetic — `(fragment_size + pll_slot_count) × base_step_duration` —
worked out by hand each time, not something the tool could answer
directly. A teacher planning a class around a specific moment ("I want
this to happen right as I finish explaining primers") has no way to ask
the sim "when does X happen given this config" without either running it
live or doing the same manual math. **A companion that generates lesson
material needs a query/preview path for "at what point does event X
occur," not just the ability to set up a config and press play.**

### 3. Label/reveal staging is coarser than the storytelling needs

`enzyme_labels_enabled` is a single shared flag — there's no way to
reveal helicase's label now and polymerase's label two beats later
without either accepting a blanket "everything labeled at once" (what
Shot C ended up doing, under time pressure) or hand-building a one-off
workaround (what Shot A did, relying on the fact that only two labels
existed yet at that point in the sequence, which only worked by
coincidence of ordering). **A lesson author — human or Azteca — routinely
wants staged reveal ("show this, then that"), and today that requires
either a lucky ordering or a visible compromise in the final material.**
This is very close to the individual-nucleotide-label filter already
built for LessonPrepCompanion's first candidate feature — it's the same
underlying need (selective, staged visibility) recurring in a second
context.

### 4. Highlighting "the nearest relevant thing" isn't a first-class capability

Shot A needed to find and highlight the nearest upcoming A-T pair, then
the nearest C-G pair, relative to wherever the fork currently was — a
capability built one-off for this shot (`find_nearest_matching_pair`)
rather than something already available. This is a generically useful
teaching gesture ("show me an example of X near where we're looking"),
not a video-specific one — a lesson author will want it just as often as
a video producer does.

### 5. Two independent clocks had to be reconciled by hand

Narration pacing (voice-over clip durations, only known after audio was
recorded and trimmed) and simulation pacing (step durations, helicase
speed, fragment size) are unrelated numbers that had to be manually
matched shot-by-shot — hold here until Gisele finishes talking, resume
there. Any tool that pairs generated narration/talking-points with a
Zymulador scene will hit this same coupling problem in miniature: **the
scene's internal timing and the lesson's spoken/written pacing are two
different clocks that don't know about each other by default.**

### 6. General-purpose primitives get built, then mis-scoped in their own docs

The directional capsule (`capsule_outline()`) was built for one demo
purpose and initially documented as if exclusive to it, even though a
second, unrelated caller (bead-tier pair highlighting) was already using
it — the design doc had to be corrected after the fact. Worth naming as
a pattern: **when building reusable highlight/annotation primitives for
Azteca, document them as general-purpose from the first caller**, not
after a second caller forces the correction.

### 7. "Prompted" isn't the same as "confirmed working"

Shots B and C were scripted and handed off but their recorded status was
never independently confirmed in this session — only Shot D was verified
against a screenshot. Any generative pipeline (Azteca producing a scene
config, then trusting it renders as intended) needs a cheap, built-in
verification step — not just "the instructions were sent" — or it will
silently ship material that doesn't actually match what was asked for.

### 8. Time pressure pushes toward the coarsest available option, not the best one

Shot C's blanket label reveal wasn't chosen because it was the right
pedagogical choice — it was chosen because there wasn't time to build the
staged version. **If Azteca is meant to remove the prep-time bottleneck,
it has to default to the well-staged version cheaply, not just make the
crude version faster to reach** — otherwise it reproduces the same
under-time-pressure compromises it's meant to eliminate, just faster.

---

## What worked well

Worth recording alongside the friction — not everything was a workaround,
and some of this is exactly the pattern Azteca should lean into rather
than reinvent.

### 1. A general-purpose primitive, reused cleanly on the second call

`capsule_outline()` was built once for the directional 5'→3' indicator
and then reused, with zero modification, for the completely unrelated
bead-tier pair-highlight (A-T/C-G capsules). The only failure was in the
*documentation* scoping it too narrowly (item 6 above) — the code itself
generalized for free the moment a second caller needed it. That's the
right outcome, and the lesson isn't "stop building single-purpose things
fast," it's "write the doc as if the second caller already exists."

### 2. A hard geometry problem got a real fix, not a patch

Camera-independent capsule positioning (needed because `_molecular_render_pos()`
shifts x by up to ±150 units depending on live camera position) was
solved with fixed-point iteration on the cluster center rather than a
tuned correction offset — converges in ~16 iterations, and Shot D's
successful recording confirmed it works end to end. This is the "derive,
don't tune" principle paying off directly under a real deadline, not just
in the abstract — a plausible easier route (approximate + hand-tuned
correction) was replaced with a derived one before it shipped, and it
held up on the first take that mattered.

### 3. A previously-solved problem got reused instead of re-solved

The DnaUnwindIntro dismiss-conflict fix (any-key dismiss firing
accidentally alongside a deliberate trigger key) was solved once and then
reused as-is for Shot A's choreography, with no rework. Small, but it's
the pattern Azteca depends on at scale: solved interaction problems
staying solved across new contexts instead of resurfacing per shot.

### 4. A refactor done as a verified no-op held up under real use

Splitting `_rebuild_layout()`'s per-residue loop into geometry-derivation
vs. consumption phases was explicitly checked to be behavior-preserving
before anything was built on top of it — and it then correctly supported
two new features (residue-position lookup, camera-independent centering)
without a single regression traced back to it. Front-loading the "did
this change anything" check paid for itself by removing that refactor
entirely as a suspect during later debugging.

### 5. Right-sized tooling for right-sized problems

When local ffmpeg noise-reduction attempts on Gisele's audio made things
worse (comb-filtering artifacts, louder pops), the fix wasn't more
ffmpeg tuning — it was recognizing the problem called for a different
tool (Adobe Podcast Enhance) and switching to it, plus separately
deciding that heavy processing wasn't worth it at all for lossy
room-playback audio and simple loudness-matching would do. Two good
calls in the same thread: escalate to a better tool when the cheap one
is fighting the problem, and de-escalate the target quality when the
delivery context doesn't need more.

### 6. Estimation without the ideal tool still landed usably

With no ASR available in the sandbox, cue timing for Rilare_08a (the
A/T/C/G mention moments) was estimated from silence-gap alignment against
the known script text instead — and Henrique confirmed on listening that
it was close enough. A reasonable proxy, checked against ground truth
before being trusted, substituted for a missing capability without
blocking progress.

### 7. Wrong scoping got caught and corrected in the doc itself, not just noted

When the capsule primitive was mis-documented as demo-exclusive, the
correction went into `MolecularIdentityHierarchy_Design.md` directly —
the doc now states the general-purpose framing plainly, rather than
carrying a footnote or an open question about it. Errors caught mid-project
were fixed at the source rather than logged as debt.

---

## Implications for Azteca (carried forward, not yet decided)

- The companion's output probably needs to include not just a static
  config/preset, but a **small timeline** — configuration changes and
  reveal/highlight events pinned to either wall-clock cues or sim-internal
  events (fragment N complete, fork reaches slot M) — since almost every
  pain point above is really "the current tool has states but no
  choreography between them."
- A query interface ("when does X happen under this config," "what's the
  nearest Y to position Z") looks like a real, separable technical
  requirement, not just a nice-to-have — items 2 and 4 are both instances
  of the same missing capability.
- Label/highlight granularity (item 3) should probably be designed once,
  generally, rather than solved per-feature each time it comes up — this
  is the second time (after the atom-tier selective-label filter) that
  the same underlying need has surfaced.

---

## What this doesn't cover

This is producer-side friction from building one specific video, not
teacher-side friction from lesson planning — the two days of teacher
conversations that motivated the original concept note are still the
primary source that should ground Azteca's actual Nucleation pass. This
document is supporting evidence that the same class of problem shows up
even in an adjacent, non-classroom context — not a replacement for
talking to teachers.
