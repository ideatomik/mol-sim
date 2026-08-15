# Physical Krebs Cycle Model — initial proposal (pre-implementation)
_Design discussion, not yet approved. Lattice-phase doc per the Crystal
Building Method — written to be discussed and explicitly approved before
any physical build or new software work begins. Companion to
`KrebsCycleDesign.md` (the software gear-track proposal this doc extends
into hardware) and to the PIPE pivot decided 22 July: the physical model is
now the candidate *desafio tecnológico* for a future submission (fluxo
contínuo or the Educação call, 13/10/2026), not the 29/07 chamada, which was
skipped._

_Context worth keeping attached to this doc: the reason this exists at all
is that the software-only Krebs spike priced too close to zero — no staff,
no equipment, no paid licenses beyond a Claude subscription — to make a
credible pitch against PIPE's ceiling. A physical tabletop model gives the
proposal real Material Permanente and fabrication cost, which is also
genuinely useful pedagogically: something a professor can put on a table in
a classroom is a different object than a laptop demo._

---

## Origin of the idea

Software Krebs (`KrebsCycleDesign.md`) already proposes a gear-and-train
metaphor: a main gear driving one sub-gear per station, tooth count derived
from platform count so the two numbers can't drift apart. This doc asks
whether that metaphor can be built as an actual mechanism — real gears, real
motion — rather than only drawn as one.

Two things carry over unchanged from the software doc and from the DNA
replication engine before it:

- **The regent is still the carbon skeleton's transformation.** Nothing
  about going physical changes what a teacher would point at.
- **The derivation rule still applies.** Tooth count = platform count, same
  reasoning as the software version: one main-gear tooth engaging a
  sub-gear is, by construction, one platform advance. No independently-tuned
  number gets to disagree with the platform count.

What's new is a second regent-adjacent object: **ATP as a powered,
3-lobed "battery"** — a physical object with its own state (charged/
discharged, or a partial-charge tier) that the mechanism consumes or
produces at the relevant stations (substrate-level phosphorylation at
succinyl-CoA synthetase; the electron-carrier stations feeding oxidative
phosphorylation conceptually, even though that's downstream of Krebs
proper). Exact scope of what the battery object represents — GTP/ATP only,
or a stand-in for the electron carriers too — is an open question below.

---

## The central open question: does scrub-safety survive going physical?

This is the question the whole doc exists to answer, and it doesn't yet
have a settled answer.

Software scrub-safety means: jump to any `pump_step` / platform index, and
the rendered state snaps instantly and correctly, with no dependence on
animation history. A physical gear train has inertia, motor ramp time, and
a real position it has to travel *through* to get anywhere — it cannot
teleport the way a `Polygon2D` can.

**Working answer, not yet built or tested:** don't ask the physical rig to
be its own state machine. Keep the jump-to-any-state property entirely in
software, exactly as it already exists for DNA replication and the pump
spike. The physical model is a **cyclical assembly line driven by the sim**,
not an independent source of truth:

- Software owns `station_index` / `platform_index` as the single regent
  counter, same as `pump_step` or `nucleotide_index` elsewhere in the
  codebase.
- Scrubbing in the software view is instant, as always.
- The physical rig receives a target position (not a stream of intermediate
  steps) and **moves to it** — visibly, with real motor travel time, the way
  a real machine would. The rig's motion during a jump is allowed to be
  "slow honest travel," not fake instant teleport, because it's a physical
  object and everyone in the room already knows physical objects take time
  to move.
- Crucially: the rig is never asked to *render* an intermediate state as if
  it were correct. It is either at the commanded position, or visibly
  travelling toward it. There is no equivalent of a tweened lobe position
  presented as truth — travel is allowed to look like travel.

This preserves the actual invariant (state is never ambiguous or wrong,
even mid-motion) without pretending a stepper motor can match a redraw
call's speed. Worth stating plainly because it's a real weakening of the
software rule, not a free pass: DNA replication and the pump spike both
guarantee *zero* mid-state frames. This model can only guarantee *no
mislabeled* mid-state frames — the rig is allowed to be seen moving, it's
just never allowed to be seen sitting in the wrong place and calling it
right.

**Open sub-question:** does the software view stay authoritative during a
physical jump (i.e., can a student scrub the screen freely while the
physical rig visibly catches up a beat behind), or does the UI need to gate
scrubbing to the physical rig's actual travel time once a physical unit is
attached? Leaning toward the former — decoupled, rig catches up — since
gating the software UI's responsiveness to hardware latency would be a
regression against everything the engine already does well. Not yet
decided.

---

## Signals: LEDs and small screens

Byproducts and electron carriers (CO₂ out, CoA in, NADH out, GTP/ATP out)
are proposed as **LED indicators** at the relevant station, lighting on
platform-boundary events — the same "platforms remove/add atoms" idea as
the software doc, made physically visible without needing a moving part for
every single byproduct.

Small screens (station-local, not a single shared display) are proposed for
anything that needs a label or a molecule name rather than a binary
on/off — e.g. which named intermediate the train currently is. This keeps
the mechanical gear train doing the *motion* storytelling and the
screens/LEDs doing the *labeling* storytelling, rather than trying to make
the gears themselves carry text.

Both LEDs and screens are downstream outputs driven by the same software
regent counter — never an independent thing that could disagree with it.
Same "inject, don't let two numbers coincidentally agree" discipline as
everywhere else in this project.

---

## Scope questions, not yet resolved

1. **Battery object scope.** Does the ATP/GTP battery represent only
   substrate-level phosphorylation (succinyl-CoA synthetase), or does it
   also stand in for the electron carriers (NADH, FADH₂) as a pedagogical
   simplification, given oxidative phosphorylation is out of scope for
   Krebs proper? Risk of the same kind of conflation `KrebsCycleDesign.md`
   already flagged for PDH/"station 1" — needs a decision, not a default.
2. **Which stations get real mechanical motion vs. LED-only.** Building all
   eight stations as full gear-driven sub-mechanisms is a large fabrication
   scope. Does the physical model cover all eight, or a representative
   subset (mirroring the software spike's citrate synthase + malate
   dehydrogenase pair) with the rest LED/screen-only for v1?
3. **Fabrication path.** 3D-printed gears vs. off-the-shelf gear sets vs.
   laser-cut — not yet costed. Affects the Material Permanente budget
   narrative directly, so this needs an answer before any proposal draft
   quotes a number.
4. **Motor/control hardware.** Stepper vs. servo per station, and whether
   one controller drives the whole assembly (matching "one main gear
   drives sub-gears" mechanically) or each station has its own controller
   taking commands from the software regent counter over serial/USB.
   Undecided, and it materially changes both the parts list and the
   software-to-hardware interface shape.
5. **Failure/reset behavior.** If a motor stalls or the rig desyncs from
   the software counter, what's the recovery path? Needs at least a rough
   answer before this goes in front of anyone who'd ask "what happens when
   it breaks in the classroom."

---

## Relationship to existing work

- Does not replace or compete with the software Krebs spike
  (citrate synthase + malate dehydrogenase, wraparound-seam test) — that
  stays the *teste preliminar* proving the software regent generalizes.
  The physical model is a second, later question: can the same regent
  drive a real mechanism, not just a screen.
- Carries forward the same derivation-rule discipline as the pump spike and
  DNA replication: one number (platform count) is the source of truth;
  everything else — tooth count, LED trigger points, motor target
  positions — is derived from it, never independently tuned.
- Nothing here is committed to a timeline. This is a holding pen for the
  idea, written so it can be picked up cleanly whenever a submission
  window (fluxo contínuo or the 13/10/2026 Educação call) is actually being
  prepared.
