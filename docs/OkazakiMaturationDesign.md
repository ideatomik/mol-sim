# Okazaki Maturation Design — Primase, Ligase, Pol I
_All three enzymes are implemented — primase, ligase, and Pol I, across both
Light and Complex tiers. See Implementation Status below for what shipped and
where it diverged from this doc's design record. Companion to
COMPLEXITY_MODEL.md (Stage 3 — Okazaki Maturation), DESIGN.md's Complexity
System and roadmap, and SKILL.md's target architecture (`primase.gd`,
`ligase.gd` listed as future, self-contained once fragment structure exists —
all three now exist as `ligase.gd`/`primase_blip.gd`/`pol1.gd`). Supersedes
the original single-relay framing of this doc — see Revision History._

---

## Revision History

- **v1 (original)**: proposed primase/Pol I/ligase as one always-together relay of
  three trailing enzyme nodes.
- **v2**: split into two tiers — a **Light tier** (primase + ligase,
  fully independent, no Pol I) and a **Complex tier** (Pol I bridges the two into
  the full relay). Ligase's already-shipped toggle-flip behavior becomes the Light
  tier's ligase implementation rather than a separate thing; primase gets an
  equivalent Light-tier implementation (a transient blip, no persistent node).
- **v3**: Light-tier ligase and primase are now both implemented
  — see **Implementation Status** below for where the shipped versions diverged
  from this doc's original design. Implementation order revised: an **RNA primer
  persistence** pass now sits between primase and Pol I (was: primase → Pol I
  directly) — Pol I's whole visual identity is nick-translating a persisted
  primer, and the current blip leaves nothing behind for it to consume yet.
- **v4**: RNA primer persistence has shipped — real pre-
  synthesis (primase places actual bases ahead of Pol III, not a preview),
  shape+thickness accessibility distinction (no color-only cue), primase's
  own direction corrected to match Pol III's, and Pol III now converts
  primer to DNA as it passes (absorbing "Pol I's job" per the original
  Light-tier design, now actually possible since primer state persists).
  Both open questions this pass was blocked on (primer flip trigger,
  RNA/DNA color distinction) are resolved — see Implementation Status.
- **v5 (this version)**: Pol I has shipped, and Complex tier is fully built —
  see Implementation Status below for the full account. Highlights: the
  real trigger diverged from this doc's own v4 proposal (a biology check
  mid-build found the anchor-slot idea was geometrically wrong — see
  Implementation Status for the corrected fragment-lag model); a two-lobe
  procedural visual (exo/pol) rather than the single-blob shape ligase and
  primase use; a true-absence lifecycle unique among the three enzymes; and
  three real bugs a chaotic-QA pass surfaced once primer timing actually
  mattered for the first time (scrub never modeled primase's own
  ahead-of-Pol-III window; the scene-wide fade could hide a trailing seal
  before it happened; Pol I's own pulse animation was silently instant).
  All three are fixed — see Implementation Status.

---

## The three toggles

| Toggle | Light behavior (`pol1_enabled` off) | Complex behavior (`pol1_enabled` on) |
| --- | --- | --- |
| `primase_enabled` | Transient blip at each fragment's start slot (same visual language as the polymerase halo's traveling particle — appears, does its thing, disappears). Primer color-flip is passive, riding on Polymerase's own existing synthesis pulse. No persisted RNA state, no queue. | Primer bases **persist** as a real RNA-colored segment after the blip fades — becomes actual per-fragment state that Pol I's queue reads from. |
| `ligase_enabled` | Today's already-built static toggle, unchanged: nicked vs. continuous backbone rendering, keyed directly off Pol III fragment completion. No primer awareness. | Real trailing enzyme, gated by `frag.primer_removed` (Pol I's completion) IN ADDITION TO Pol III's own `_lagging_close_fragment()` trigger, not instead of it — see Implementation Status for why both call sites stayed. |
| `pol1_enabled` (primer removal) | Doesn't exist in this state — no node, no queue. | Shipped. The nick-translation enzyme: a trailing node, true-absence until its first job, consuming `primase_enabled`'s persisted primer state, removing it one fragment-lag behind Pol III's own progress, setting `frag.primer_removed`. |

**Implementation order**: all three pieces are now built (see Implementation
Status below) — Light-tier ligase, Light-tier primase, RNA primer
persistence, and Pol I's Complex tier. This doc's own v4 prediction for Pol
I's trigger (reuse `_pol3_convert_primer_if_needed()`'s call site directly)
turned out to be wrong — see Implementation Status for the corrected
fragment-lag model and why.

---

## Implementation Status (As-Built)

What actually shipped for the two Light-tier pieces, and where it diverged
from this doc's original design. Kept separate from the sections below
(which remain the design record) — this is the source of truth for current
behavior.

### Ligase — shipped as the Complex-tier version, not the Light-tier toggle
The original v1/v2 framing had ligase's *Light* tier stay the existing static
toggle (nicked vs. continuous, keyed off Pol III completion) until `pol1_enabled`
existed. In practice, once `polymerase_clamp.gd`/`helicase_ring.gd` were in hand
as reference, building the real traveling enzyme directly turned out to be no
harder than the static version — so ligase shipped as a genuine node
(`ligase.gd`) now, ahead of schedule relative to this doc's original staging:

- **Stand-in trigger**: queue is fed by Pol III's own `_lagging_close_fragment()`
  event (fragment completion) rather than Pol I's not-yet-built `primer_removed`.
  Nothing about ligase's own motion/render/scrub logic depends on which trigger
  is driving it — swapping to `primer_removed` later only changes the call site.
- **Catch-up via a real event, not a poll**: `ComplexityManager.toggle_changed`
  is consumed directly — turning ligase on mid-run (after fragments already
  piled up while it was off) kicks the queue immediately, rather than needing a
  per-frame check.
- **Merge algorithm unified**: `_lagging_render()`'s two branches (ligase on/off)
  now share the same contiguous-prefix merge logic, gated on `frag.sealed`
  (on) vs. `frag_ready` (off) — not two separately-maintained algorithms.
- **Position**: sits at the fragment boundary, offset by half a slot spacing
  (visually centered in the gap between slots) and by `backbone_offset_distance`
  (sits on the drawn backbone row, not the base row).
- **Fully scrub-safe**: `_lagging_scrub_rebuild()` marks every synthesized
  fragment `sealed = true` directly — scrub shows only the fully-sealed state,
  never a mid-travel/mid-seal enzyme, exactly as originally designed.

### Primase — shipped as designed, with one real trigger correction
- **Trigger moved off Pol III entirely**: the original design fired the blip
  from the same fragment-boundary event Pol III's own tiling uses
  (`_lagging_open_next_fragment()`). In practice this fired far too late —
  Pol III's own backlog/startup delay means it can reach a slot many steps
  after the helicase already exposed it, which read as the primer marking
  "something that happened a while ago" rather than the spot itself. Shipped
  trigger instead: `_on_helicase_slot_reached()`, gated by a purely geometric
  tiling check (`_primase_check_slot()` — is this slot a fragment's starting
  slot, independent of Pol III's own progress) that fires the instant the
  helicase passes it.
- **Position is live-followed, not fixed**: the bottom template row is still
  visually transitioning (bonded → unzipped) for several slots after the
  helicase passes them — a fixed target Y (even the eventual resting Y) made
  the blip look disconnected from the strand. Shipped version samples the same
  rail curve the template row's own rendering uses, every frame the blip is
  visible, so it always sits exactly on the row as currently drawn.
- **Hold duration tied to Okazaki fragment size, not a fixed constant**: the
  blip's on-screen hold is computed at trigger time as
  `okazaki_fragment_size * helicase_mgr.step_duration` — the exact time Pol
  III is committed to that fragment (build every slot, then slide back to
  open the next one). The blip fades out right as that slide-back happens,
  so the primer visually persists for precisely as long as the fragment it
  marks is under active construction, rather than a short flash disconnected
  from Pol III's own pace. `ThemeManager`'s fixed `primase_blip_hold_duration`
  field was removed as dead once this landed — only the (short, still fixed)
  fade-in/fade-out edges remain as tunable constants.
- **No persisted RNA state yet** (unchanged from the original design) — see
  Implementation order above for why this is next, not a rejected idea.

### RNA Primer Persistence — shipped, with several real divergences

The largest pass since this doc's v3. High-level shape matches the design
(real per-slot RNA state, primer/DNA visually distinguished, Pol III
eventually "absorbs Pol I's job") but almost every specific decision landed
differently than first proposed, usually after finding a real bug the
original framing didn't anticipate.

**Real pre-synthesis, not a preview.** The open fork from v3 (does primase
place real state ahead of Pol III, or a decorative preview that hands off
when Pol III actually arrives) resolved toward real pre-synthesis — primase
places actual bases into `lagging_synthesized_bases` directly, ahead of
wherever the lagging polymerase enzyme currently is. This does mean primers
now appear scattered ahead of the visible polymerase, a real departure from
this project's "synthesis = wherever the enzyme is" visual convention — but
that's the more biologically honest picture (primase genuinely works ahead
of the replisome), and it reuses the existing `_capture_begin_lagging()`
guard for free: Pol III's own fire-step already silently skips an
already-placed slot, so nothing needed to change there to make Pol III
correctly *not* re-place a primer base.

**Primer length**: `primer_length_ratio = 0.25` against `okazaki_fragment_size`
(bumped from 6 to 12 specifically so this yields a clean 3-slot primer)
rather than a fixed absolute count — scales if fragment size is ever tuned
per-domain (see COMPLEXITY_MODEL.md's Okazaki fragment size note).

**Primase's own halo, not a color relabel.** Once primase does real
synthesis, it needed the same "pick from a pool, fly it in" mechanic Pol
III's `PolymeraseHalo` already has — reused directly rather than duplicated,
but `polymerase_halo.gd` needed two small additions to support a second
instance meaningfully: a configurable `base_letters` (RNA's `A/U/C/G`
instead of DNA's `A/T/C/G` — real RNA has no thymine, substituted at the
rendering layer only, `sim.dna_sequence.get_base()` itself stays untouched)
and a `color_overrides` map (RNA-tinted, not the shared DNA palette). One
honest limitation left as-is: the ambient *floating* particles in primase's
halo read DNA-colored until the moment of capture, since fully re-tinting
the whole cloud would need forking more of the shared class than this pass's
scope justified.

**Shape, not just color — accessibility, not decoration.** A late but
important correction: primer bases needed to be distinguishable by *shape*
(rounded square vs. circle) as well as color, and the primer backbone
segment needed to drop its own hue entirely, distinguished instead by
thickness and marker shape (an open chevron vs. the DNA triangle) — never
color alone. `nitrogen_base.gd` gained a `shape` property and `set_shape()`;
`simulation.gd` gained `_create_bond_mark_sprite_rna_reversed()` (literally
the DNA triangle's same corner geometry, drawn as an open 3-point `Line2D`
instead of a filled `Polygon2D` — "an equilateral triangle without one of
its sides"). **First contrast pass was nowhere near enough** — a modest
width step (16px→10px) plus filled-vs-open at the *same* size proved
genuinely unreadable even paused and zoomed in, confirmed by a user
screenshot after I'd (wrongly) assumed it was a motion-blur perception
issue rather than an actual legibility failure. Landed values: RNA backbone
5px (under a third of DNA's 16px), and the chevron got its **own** width
field (`rna_bond_mark_width = 22`, wider than DNA's `bond_mark_width = 14`)
instead of sharing DNA's — the two shapes needed different proportions, not
just a hollow/filled variant of the same silhouette.

**The pending-backbone registry — the real architectural addition.**
Backbone rendering was entirely fragment-scoped, and a fragment doesn't
exist until Pol III opens it — but primase (firing off the helicase, not
Pol III) can place real bases long before that happens. Without a fix, those
bases sat with no connecting backbone for the entire gap between placement
and Pol III's eventual arrival. Fix: `primase_pending_backbones`, a
tile-keyed registry primase builds into immediately, rendered fresh every
frame in `_lagging_render()`, then **adopted** (not recreated) by
`_lagging_open_next_fragment()` the instant Pol III opens that same tile —
ownership handoff, not a rebuild.

**A second, subtler bug the adoption handoff itself created**: right after
adoption, `_lagging_render_fragment_backbone()` was recomputing the primer
segment's points by walking `frag.slots` — but `frag.slots` lags reality
here. Pol III still bookkeeps its way through already-primase-placed primer
slots one fire-step at a time (it only *skips the spawn*, not the
bookkeeping), so for a couple of fire-steps right after adoption, an
already-fully-placed 3-slot primer would visibly *shrink* back down to 1
point before growing back — read as "Pol III building the primer with its
own (wrong) specs," which is what several rounds of screenshots were
actually showing. Fix: primer points are now derived from the same
deterministic tile math the pending-backbone pass already trusted
(`_primase_tile_end()`/`_primase_primer_length()`), not from `frag.slots`
membership. DNA points still come from `frag.slots`, since that portion
*does* genuinely depend on Pol III's own progress.

**Direction correction.** Primase originally placed its 3 bases one at a
time, in the order the helicase exposed them (low-to-high) — but Pol III's
own firing is high-to-low, so a single fragment would read as being
synthesized in two opposite directions (primer one way, DNA extension the
other). Fixed by waiting: the trigger now only fires once, on the anchor
slot (the *last* of the 3 to become available, since the helicase sweeps
low-to-high) — by which point the whole span is already exposed, and
primase plays all 3 placements as a chained sequence in Pol III's own
high-to-low order. No new pacing constant needed; the existing per-placement
tween duration already sequences it correctly.

**Pol III converts the primer — the "Pol I's job, absorbed" idea, now
actually built.** `_capture_begin_lagging()`'s existing skip-guard (hit when
a slot is already placed) now calls `_pol3_convert_primer_if_needed()`
instead of just returning: recolors, reshapes (rounded-square → circle),
relabels (U → T) the base in place. Instant, not animated — shape can't
smoothly interpolate between the two custom-drawn primitives without real
polygon morphing, and animating color alone while shape snaps would look
mismatched. This made "primer-or-not" stop being pure geometry (a slot can
be *in* the primer span but already converted), so a new `_is_still_primer()`
(geometry + the base's actual current shape) supersedes plain
`_is_primer_slot()` everywhere rendering needs to know the difference —
`_is_primer_slot()` itself stays pure geometry, since the placement trigger
still needs it before any base exists to have a shape at all.
_Correction as of Pol I's Implementation Status below: this instant
conversion is now Light-tier only — `_capture_begin_lagging()` skips this
call entirely when `pol1_enabled`, and the actual conversion moment becomes
Pol I's own animated sweep instead._

**Scrub simplified, not extended** — _true only for the Light tier, and
only until Pol I existed._ Once Pol III converts every primer slot it
passes, anything scrub shows as "consumed" is — by definition, in the real
timeline — already converted, since scrub never shows content beyond Pol
III's own progress. Scrub's primer-coloring/shaping branch was removed
entirely rather than taught to replicate the conversion logic; this also
means scrub never needs to model primase's own ahead-of-Pol-III pending
placements, a real simplification rather than a corner cut. _This stopped
being true the moment Pol I's removal timing became load-bearing — see
Pol I's Implementation Status below (bug #1) for the scrub fix this
actually needed once conversion was no longer instant._

**Ligase's hold phase**, added in the same pass on unrelated feedback (the
seal happened too fast to see the nick): a new `LigaseState.HOLDING`
between arrival and sealing, with its own `ligase_hold_duration` — decouples
"how fast ligase travels" from "how long the gap stays visible," rather than
just slowing travel down and making the enzyme itself feel sluggish.

**Both v3 open questions resolved**: primer flip trigger → Pol III converts
it (not a passive Polymerase-pulse flip, not held indefinitely for a
not-yet-built Pol I). RNA/DNA base color distinction → shipped, four
`rna_base_color_*` fields plus the shape/thickness accessibility layer.

### Pol I — shipped, with the trigger model corrected mid-build

The largest divergence of any piece in this doc from its own design record.
The high-level shape survived (a trailing enzyme, gated behind a persisted
primer, handing off to ligase) but the *trigger* — the single most
important architectural decision — turned out wrong on first proposal, and
a live biology check during the build caught it before it shipped.

**The anchor-slot trigger (this doc's own v4 proposal) was geometrically
wrong.** The plan was to reuse `_pol3_convert_primer_if_needed()`'s call
site directly — the moment Pol III's fire-step first touches an
already-primase-placed slot. Walking the actual slot numbers: a fragment's
primer occupies *its own* highest-index slots, touched during *that same
fragment's* first few fire-steps, right as it opens — not when Pol III's
growing edge later reaches the *previous* fragment's primer, which is what
real nick-translation timing actually depends on (Pol I needs freshly-made
DNA immediately adjacent to extend into as it displaces the old primer).
Confirmed with concrete tile numbers before building on it: with
`okazaki_fragment_size = 12`, `primer_length = 3`, fragment 1's own close
(reaching slot 12) lands exactly adjacent to fragment 0's primer (slots
9-11) — fragment 1 closing is what delivers Pol III next to fragment 0's
primer, not fragment 0's own opening.

**Shipped trigger: one-fragment lag, gated on fragment CLOSE, not primer
placement.** `_lagging_close_fragment()` — already ligase's own trigger
call site — now *also* enqueues a Pol I job for `lagging_fragments[-2]`
once at least two fragments exist. Fragment *k*'s primer becomes eligible
for removal the instant fragment *k+1* closes, never before. This has three
consequences the anchor-slot version wouldn't have had:

- **Fully event-count-gated, no independent clock.** Pol I's own per-slot
  sweep is paced by `sim.helicase_mgr.step_duration` (see QCA fixes below),
  but *when a job starts* depends only on fragment-close events — a pure
  function of `lagging_fragments.size()`, reconstructable instantly for any
  scrub target with zero animation-history dependency. This was the actual
  reason the anchor-slot version got rejected: pacing a removal off
  Pol III's own real-time fire-step made "has this primer been removed yet"
  depend on wall-clock animation progress, which no scrub rebuild in this
  project has ever needed to replay.
- **The last fragment in any sequence never gets its own primer removed.**
  There's no "next fragment closes" event for it. This is not a bug — see
  the sanity check below, this is the real end-replication problem/telomere
  gap, arrived at from Pol I's side rather than telomerase's. Left alone
  entirely until the telomerase tier exists (`OkazakiMaturationDesign.md`'s
  own open question on this, now partially answered — see Open Questions).
- **Ligase's trigger stays exactly where it was, plus one more call site.**
  Contrary to this doc's v1-v4 framing ("ligase's real trigger should
  become `primer_removed`"), the shipped version did NOT swap ligase's
  trigger away from `_lagging_close_fragment()`. Instead, `_ligase_kick()`'s
  own eligibility check grew one line — `if pol1_enabled and not
  frag.primer_removed: break` — and `_pol1_finish_job()` calls
  `_ligase_kick()` too, as a second trigger. Both call sites are idempotent
  and safe to double-fire; whichever one satisfies the (now two-part)
  eligibility check first is the one that actually kicks ligase into
  motion. Simpler than a trigger swap, and it meant zero changes to
  ligase's own motion/render/scrub logic — exactly the kind of
  "swapping the trigger only changes the call site" outcome the original
  Ligase Implementation Status entry predicted, just via addition rather
  than replacement.

**True-absence lifecycle — the one enzyme that breaks the create-once-hide
pattern.** Ligase and primase are both instantiated once at `initialize()`
and toggle visibility/alpha thereafter. Pol I is not instantiated until its
first job exists, and stays instantiated (never freed again) after that —
real Pol I has no fixed position in the replisome to occupy while idle,
unlike helicase/Pol III/the clamp, which are physically tethered together.
Between jobs it plays a leave-the-strand motion (drop + fade at wherever
the last job ended) rather than parking visibly, and reappears near
wherever its *next* job is rather than traveling cross-screen to get
there — matches "freely diffuses, doesn't migrate visibly" better than a
long travel tween would. One real consequence this simplified rather than
complicated: because the *gating* state (`frag.primer_removed`) lives on
the fragment dict, resolved structurally, scrub never needs to
lazy-instantiate the node at all — it stays fully offstage during scrub
exactly like ligase and primase, regardless of whether it exists yet.

**Two-lobe visual, not the single-blob shape ligase/primase share.** Real
Pol I does two simultaneous things (5'→3' exonuclease chewing the primer,
5'→3' polymerase filling DNA behind it) — represented as two connected
lobes rather than one pulsing blob, the one enzyme in this relay whose
whole biological identity is "two activities at once." Landed shape,
after two live QOL passes:

- **EXO lobe is the fixed reference point**, sitting at local origin — which
  is the node's own position, itself pinned to the lagging strand's actual
  base row (no `backbone_offset_distance`, unlike ligase, which sits on the
  backbone line instead — Pol I is working the bases directly, not sealing
  a backbone junction). POL lobe is offset from EXO by a tunable
  `pol1_lobe_gap`, not a symmetric split around a shared center.
  Originally split along the travel axis (mirroring the clamp's back/jaw
  split) — moved to a vertical stack instead after both lobes read as a
  blur along the strand line, especially the RNA-removal side.
- **POL lobe is shorter than EXO** (`pol1_pol_lobe_height_ratio`, default
  0.5) — same width, same color family, deliberately not a twin shape.
- **Sized off Pol III's own clamp width** (`clamp_back_width *
  pol1_lobe_size_ratio`), not an independently-tuned flat constant — Pol I
  reads larger than ligase on purpose; ligase stays small by design.

**Three real bugs a chaotic-QA pass found, once primer timing started to
matter for the first time:**

1. **Scrub silently erased primers that would exist in a live run.**
   `_lagging_scrub_rebuild()` only ever reconstructed *Pol III's own*
   threshold-lagged progress — it never modeled primase's ahead-of-Pol-III
   placement window at all. Harmless under the old instant-conversion
   model (anything Pol III would eventually touch became DNA regardless of
   whether a primer sat there first), but a real bug once removal timing
   became load-bearing: scrubbing to a point where primase would have
   already placed a primer, then resuming play, made Pol III find nothing
   there and write fresh DNA straight through — Pol I never got a primer to
   remove in the first place. Fixed with a second reconstruction pass in
   `_lagging_scrub_rebuild()`, keyed off raw helicase exposure the same way
   primase's own live trigger is. The connecting *backbone line* for this
   ahead-of-Pol-III window still isn't reconstructed during scrub (that's
   primase's separate pending-backbone mechanism, which scrub still
   bypasses entirely) — a known minor cosmetic gap, not a data-model bug,
   left as a flagged follow-up.
2. **The scene-wide fade could hide a trailing seal before it happened.**
   `_lagging_start_catchup()`/`_lagging_catchup_tick()` fired the
   whole-scene fade-out (helicase, both polymerases, ligase, Pol I) the
   instant `lagging_total_consumed` reached `num_nucleotide_slots` —
   with no regard for whether ligase or Pol I still had trailing work
   queued. In practice this meant the *second-to-last* fragment's own
   seal — fully reachable, since it only needs the (always-happens) last
   fragment to close, not that fragment's own primer removal — routinely
   completed *after* the fade had already hidden everything. Functionally
   correct, invisibly so; read as "ligase doesn't seal the last valid
   fragment." Fixed with `_lagging_enzymes_settled()` (true once ligase and,
   if `pol1_enabled`, Pol I have both drained their queues) gating the
   fade, and a deferred-fade retry hooked into both enzymes' own completion
   handlers.
3. **Pol I's pulse was two `tween_callback`s with nothing between them.**
   `tween_callback` is an instant snap with no visible duration — two of
   them back-to-back (`set_pulse(1.0)` then `set_pulse(0.0)`) landed within
   the same frame or two, technically animating 0→1→0 but invisibly.
   Should have been `tween_method` (real interpolation over real time) from
   the start — the same pattern ligase's own seal pulse already used
   correctly. Fixed; the bite is now actually visible.

**Two QOL passes, both about pacing and legibility:**

- **Both Pol I's per-slot sweep and primase's own 3-base placement now
  pace off `sim.helicase_mgr.step_duration`**, not their own independent
  flat constants (`pol1_step_duration`, `primase_capture_duration` — both
  now dead fields, safe to remove from ThemeManager). Previously both
  animated at a fixed real-world speed regardless of simulation speed,
  which read as "too fast to grasp what's happening" at anything above the
  slowest speed setting. Tying to the helicase's own step pacing means both
  now move at the sim's actual speed automatically.
- **Primer backbone gets its own color** (`rna_backbone_color`, new field),
  at both of its creation sites (the pending-backbone mechanism and the
  render-time fallback path). Worth noting explicitly: this doesn't
  override the project's existing accessibility principle for this
  segment ("distinguished from the DNA segment by THICKNESS and MARKER
  SHAPE first — never rely on color alone") — color is now an *added*
  redundant cue on top of that, not a replacement for it.

### Sanity check: the telomere-adjacent trailing primer

Confirmed correct, not a bug, during the same QCA pass that found the three
above: Pol III still fully synthesizes the very last fragment (including
building all the way through/past where its own primer sits) — the trailing
RNA bases visible at a linear sequence's end are that last fragment's own
never-removed primer, exactly per the one-fragment-lag design. The one
*actual* bug in the same screenshot was a separate, earlier nick (the
second-to-last fragment failing to seal) — bug #2 above, not this.

---

## Cascade logic

Two directions, and they are **not symmetric**:

- **Turning `pol1_enabled` ON** force-enables `primase_enabled` and `ligase_enabled`
  if either was off, and both simultaneously switch from their Light behavior to
  their Complex behavior. This is a deliberate exception to COMPLEXITY_MODEL.md's
  usual cascading rule ("turning a child on does not silently auto-enable its
  parent") — justified because Pol I is structurally meaningless without both
  siblings active at once: nothing to remove without a primer existing, nothing
  for ligase to seal without Pol I finishing. There's no valid intermediate state
  where Pol I is on but one sibling isn't.
- **Turning `primase_enabled` or `ligase_enabled` OFF while `pol1_enabled` is on**
  force-disables Pol I too. This direction *is* the standard rule — a required
  dependency disappearing disables the dependent. Primase/ligase then simply fall
  back to their own Light behavior rather than vanishing entirely.
- **With `pol1_enabled` off**, `primase_enabled` and `ligase_enabled` stay fully
  independent toggles, no awareness of each other — exactly today's shipped
  ligase behavior, plus the new Light-tier primase blip alongside it.

**This is not a one-off exception unique to Pol I** — it's the general pattern for
any enzyme whose entire reason to exist is bridging/coupling two siblings that are
each independently meaningful alone but jointly required for the bridge to make
sense. The clamp loader + sliding clamps (both on the toggle roadmap, per
COMPLEXITY_MODEL.md's Full replisome / clamps tier) will very likely need the same
"activating the bridge force-enables both sides, deactivating either side
force-disables the bridge" cascade — clamp loader is meaningless without clamps to
load, and clamps at that tier are meaningless without a loader putting them there.
**Recommendation**: name this cascade shape explicitly in COMPLEXITY_MODEL.md's
Cascading UI behavior section as a recognized second pattern (call it a
"bridge toggle") alongside the existing "hard requires" / "soft recommends" /
"shares a mechanic" / "sibling" relationship types, rather than re-deriving it
ad hoc each time a new bridging enzyme comes up. Not resolved in this doc —
flagged here since Pol I is the first concrete case, but the naming/registry
update belongs in COMPLEXITY_MODEL.md itself.

---

## What each enzyme actually does (biological recap)

- **Primase (DnaG)** — synthesizes a short RNA primer at the *start* of a new
  Okazaki fragment, giving Pol III the free 3'-OH it needs (DNA polymerases can't
  initiate a strand from nothing). Acts once per fragment, *ahead of* Pol III —
  the primer must exist before synthesis of that fragment can begin.
- **Pol I (primer removal)** — nick translation: simultaneous 5'→3' exonuclease
  (chews the RNA primer off the front) and 5'→3' polymerase (fills DNA in behind
  it) at matched rates, so the nick slides forward without growing or shrinking
  until the primer is fully replaced with DNA. Trails *behind* Pol III, visiting
  each fragment only after Pol III has finished it.
- **Ligase** — seals the final DNA-DNA phosphodiester bond. Cannot act until the
  primer is fully gone (Pol I's job) — ligase joins DNA to DNA, not RNA to DNA.
  Trails behind Pol I.

Real cells often use RNase H to remove most of the RNA primer first, with Pol I
mopping up the last ribonucleotide. Zymulador doesn't model RNase H as a separate
step — Pol I alone is capable of the whole removal, and RNase H would add a fourth
enzyme for a distinction beyond this project's didactic scope. Worth a one-line
mention in `_FULL` label text later, not a modeled mechanic.

---

## Light tier

### Primase (transient blip)
- **Spawn**: on the same fragment-boundary event Pol III's own tile jump already
  fires off — no new trigger needed.
- **Position**: the fragment's starting slot, lagging-strand y — a single
  coordinate, not a continuously-tracked position.
- **Lifecycle**: fade/scale in → brief hold → fade out, timed to its own short
  duration constant (same pattern as the polymerase's synthesis pulse, just its
  own object instead of riding the clamp's pulse).
- **Scrub**: never rendered during scrub — same "instant, finished slots only"
  rule the nucleotide capture animation already follows. Scrub only needs to know
  whether the primer *state* exists (RNA-colored bases present or already
  flipped), not replay the blip.
- **No queue, no lag distance, no travel** — doesn't need any relay-node
  machinery, because it's not tracking "how far behind Pol III am I," it's just
  "did this fragment's boundary event fire."
- **Label**: can carry the already-reserved `ENZYME_PRIMASE` key, shown only
  while the blip is visible.

### Pol I's job, absorbed into Polymerase (no separate node)
When Polymerase finishes fragment *k* and moves on to fragment *k+1*, fragment
*k*'s primer bases flip from RNA-color to DNA-color, riding on Polymerase's own
existing synthesis pulse — no new animation, no new node, one enzyme doing double
duty on the primer bases nearby.

### Ligase (already built)
Unchanged from today: `ligase_enabled`, static per-fragment nicked-backbone vs.
continuous rendering, keyed directly off Pol III fragment completion.

---

## Complex tier (`pol1_enabled`)

Three trailing nodes, each following the pattern already established by
`helicase_ring.gd`/`polymerase_clamp.gd`: procedural visual (shared rounded-octagon
primitive), own ThemeManager export group, event-driven only (no independent
clock), scrub-safe by construction.

```
Helicase (unzips)
  → Polymerase (Pol III — synthesizes DNA for each fragment, right-to-left)
      → Primase — visits a fragment's start slot BEFORE Pol III reaches it,
          places a PERSISTED RNA primer (not a blip) that Pol I's queue reads
      → Pol I — visits a fragment AFTER Pol III completes it,
          nick-translates the primer out, DNA in, sets primer_removed
          → Ligase — visits a fragment AFTER Pol I completes it, seals the nick
```

Each of the three is a **distinct node with its own monotonic position** — unlike
Polymerase's lagging-strand instance, none of them jump back and forth; each only
ever moves forward to its next pending target, at its own pace, independently
lagging behind the stage before it by some tunable number of fragments/slots
(`primase_lead_slots`, `pol1_lag_fragments`, `ligase_lag_fragments` — naming TBD,
each its own ThemeManager value, not a shared constant, per this project's "never
let two independently-tuned numbers coincidentally agree" rule).

_Correction, as shipped: none of these three lag constants exist._ Primase's
lead is unchanged from Light tier (fires the instant its own anchor slot is
exposed — no lead distance to tune at all). Pol I's lag is exactly one
fragment, expressed structurally (`lagging_fragments[-2]`, gated on the next
fragment's own close event) rather than as a tunable float — see Pol I's
Implementation Status above for why a *tunable* lag specifically would have
broken scrub-safety (real-time pacing, not event-count pacing). Ligase's lag
is effectively zero beyond what it already had: no new call site swap, just
one added condition on its existing eligibility check.

### Visual concept per Complex-tier enzyme
- **Primase**: same small blip visual as the Light tier, but the primer it leaves
  behind now persists as real state instead of fading with the blip.
- **Pol I**: the most visually distinct moment available — nick translation reads
  naturally as a *sliding gap*: primer-colored bases disappearing at the leading
  edge while DNA-colored bases appear at the trailing edge of the same small
  window, moving together. Distinct from Polymerase's "grow the strand outward"
  animation — worth leaning into as a deliberate visual contrast.
  _As shipped: two connected lobes (EXO/POL) rather than a single window with
  two edges, but the same core idea — one moving unit doing two visually
  distinct things at once. See Pol I's Implementation Status above._
- **Ligase**: brief pulse/pinch at the junction once Pol I hands it off, closing
  the last visible gap in the backbone line.

---

## Data model

Light tier only needs a lightweight primer-state pair riding on the existing
fragment structure; Complex tier needs the full four-flag version:

```gdscript
{
  slots: Array[int],
  backbone: Line2D,
  bond_marks: Array[Node2D],
  marker_5p: Node2D,
  marker_3p: Node2D,
  primer_placed: bool,      # Light: set true then irrelevant after color-flip.
                             # Complex: gates Pol I's queue.
  synthesis_complete: bool, # renamed from `complete` — Pol III done
  primer_removed: bool,     # Light: flips passively on Polymerase's pulse.
                             # Complex: set by Pol I specifically.
  sealed: bool,              # replaces binary ligase_enabled read in both tiers
}
```

_Correction, as shipped: no `primer_placed` field exists, and `complete`
was never renamed to `synthesis_complete`._ "Is a slot's primer placed"
turned out not to need fragment-level state at all — it's answered
per-slot, by whether `lagging_synthesized_bases[i]` is non-null with
`shape == "rounded_square"` (`_is_still_primer()`, already existed pre-Pol
I). The fragment dict only gained the one field this doc's original
four-flag proposal got right: `primer_removed: bool`, defaulting `false`,
flipped by `_pol1_finish_job()`. `complete` stayed `complete` — no rename,
since nothing about Pol I needed to distinguish it from a hypothetical
different "complete" meaning.

Rendering (`_lagging_render()`) already branches on complexity toggles for backbone
continuity — this extends that branch to read `sealed` per-boundary rather than a
single global toggle state, so partially-matured strands render correctly mid-run
in both tiers.

---

## Scrub-safety

Same discipline as the existing lagging-strand scrub math (per DESIGN.md's
"scrub must resync every variable the live trigger depends on" rule): each
enzyme's position (Complex tier) and every fragment-state flag (both tiers) must
be derived instantly and correctly for an arbitrary scrub target, the same way
`_lagging_scrub_rebuild()` already derives `lagging_total_consumed`/
`lagging_batch_cursor`. Worth building the Light-tier flag resync and the
Complex-tier three-enzyme resync as one consistent pass rather than
rediscovering the pattern per enzyme.

---

## Domain mode interaction (eukaryote vs. prokaryote)

Per COMPLEXITY_MODEL.md's chimera framing, the three enzymes in this relay diverge
across domains at genuinely different depths:

| Stage | Divergence depth | Real difference |
| --- | --- | --- |
| Primase | Mechanism | DnaG (pure-RNA primer) vs. Pol α-primase (RNA-DNA hybrid primer + a Pol α → Pol δ handoff step bacteria don't have) |
| Primer removal | Mechanism | Pol I nick-translation (one enzyme) vs. FEN1 + RNase H2 (+ Dna2 for long flaps) flap-cutting (a multi-protein team, different visual entirely) |
| Ligase | Cofactor only | NAD⁺ (bacterial) vs. ATP (eukaryotic) — already correctly scoped as a divergent-specific under `atp_activation_enabled` in COMPLEXITY_MODEL.md |

**Decision for this pass: label-only for primase and primer removal.** Both keep
their bacterial mechanics (the transient blip / Pol I nick-translation sliding-gap
animation) under either domain setting — only the enzyme name/label swaps, the same
way `EnzymeLabelsDesign.md` already branches `_FULL` label keys per enzyme. Ligase
needs no change here; its existing cofactor-lens handling already covers the real
divergence correctly.

**Explicitly deferred, not designed here**: the accurate eukaryotic mechanic —
hybrid-primer visual, the Pol α → Pol δ handoff moment, and FEN1/RNase H2/Dna2
flap-cutting in place of nick-translation. This is real future scope, not a
rejected idea — flagged so it isn't silently forgotten once a `topology_mode`/domain
toggle actually exists and someone asks why eukaryotic mode still shows a bacterial
mechanic under the hood.

---

## Open questions

- ~~**Pol I's real trigger**~~ — **RESOLVED.** Not the anchor-slot
  `_pol3_convert_primer_if_needed()` call site this doc originally
  proposed — see Pol I's Implementation Status above for why that was
  geometrically wrong, and the fragment-lag model (`_lagging_close_fragment()`
  gates removal of `lagging_fragments[-2]`) that shipped instead. Answers
  the "replace vs. layered fallback" framing too: the instant conversion is
  now Light-tier only, fully bypassed (not layered under) when
  `pol1_enabled`.
- **Primase halo's ambient cloud stays DNA-colored** — only the captured/
  placed base reads as RNA; the floating particles before capture don't.
  Flagged as a deliberate scope boundary when built, not revisited since.
- ~~**Primase's exact timing (Complex tier)**~~ — **RESOLVED, mostly.**
  Primase's placement trigger itself didn't change for Complex tier — same
  raw-helicase-exposure anchor trigger as Light tier, unchanged. What DID
  need resolving once Pol I shipped: scrub never modeled this ahead-of-
  Pol-III window at all, which was harmless before Pol I existed and a real
  bug once primer removal timing became load-bearing — see Pol I's
  Implementation Status, bug #1. Primase's own per-slot pacing also now
  ties to `sim.helicase_mgr.step_duration` (a QOL fix, not a Complex-tier-
  specific one — applies at both tiers).
- **Interaction with `lagging_gap_enabled` (telomerase tier)** — partially
  answered from Pol I's side: the very last fragment in any sequence
  naturally never gets its own primer removed under the shipped fragment-lag
  model (no "next fragment closes" event exists for it) — confirmed correct
  behavior, not a bug, during QCA (see Pol I's Implementation Status,
  Sanity check). What's still undesigned is telomerase's OWN side: how a
  `lagging_gap_enabled` run should handle the DISCARDED trailing fragment
  (`_lagging_discard_incomplete_at_end()`, reserved, not yet built) —
  whether it should even reach `_lagging_close_fragment()` at all, or get
  dropped before that point in a way Pol I's queue needs to explicitly
  ignore.
- **The "bridge toggle" cascade pattern** — being resolved in the same pass
  as this update; see COMPLEXITY_MODEL.md's Cascading UI behavior section.
- **ATP/NAD⁺ cofactor lens** — per COMPLEXITY_MODEL.md, ligase's
  `atp_activation_enabled` hookup is eukaryotic-mode-only (bacterial ligase runs
  on NAD⁺). Not blocking for either tier, but the lens should read the same
  per-fragment `sealed` event both tiers produce, once topology mode exists.
- **Pol I's ahead-of-Pol-III scrub reconstruction spawns bases but not
  backbone geometry.** Flagged as a known minor gap in Pol I's
  Implementation Status (bug #1) — the primer bases render correctly on
  scrub now, but the connecting backbone line for that same ahead window
  doesn't appear until Pol III's own live progress later reaches that tile.
  Not resolved here; worth a small follow-up pass if it turns out to be
  more visible in practice than it sounds on paper.
