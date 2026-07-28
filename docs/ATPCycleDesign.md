# ATP Cycle Design — the cofactor-activation lens
_**STATUS: BOTH halves shipped — helicase in v78, ligase in v79.** The body
of this document below is preserved as written at Lattice time and is wrong
in fifteen places — see **As-Built (v78)** and **As-Built (v79)** at the end
rather than trusting the body where the two disagree. This status line is
the only edit made to the original text; everything else was appended._

_Design document. Companion to
COMPLEXITY_MODEL.md (Cross-Cutting Lenses & Dials —
`atp_activation_enabled`), HelicaseDesign.md (barrel-roll math this hooks
into), and OkazakiMaturationDesign.md (ligase's state machine and timing).
Written per the Crystal Building Method's Lattice phase — to be discussed
and explicitly approved before any code is written._

_Grounded against real source read this session: `helicase.gd`,
`helicase_ring.gd`, `ligase.gd`, `replication_manager.gd`,
`theme_manager.gd`, `nitrogen_base.gd`, `procedural_shape_utils.gd`,
`complexity_manager.gd`, `simulation.gd`. Eight assumptions were corrected
against the files — see **Ground-truth corrections** below._

---

## Scope

Exactly two enzymes: **helicase** and **eukaryotic-mode ligase**. Both
already exist as shipped, working nodes; both are named in
COMPLEXITY_MODEL.md's ATP lens tree as the cleanest cases.

Explicitly NOT in this pass — each is blocked behind an enzyme that doesn't
exist yet, and pulling any of them in would mean building that enzyme
first:

| Enzyme | Blocked on |
| --- | --- |
| Clamp loader | clamp loader / sliding clamp not built |
| Topoisomerase / gyrase | topoisomerase not built |
| Pol V mutasome | TLS tier not built |
| DnaA | initiation stage not built |
| **Bacterial ligase (NAD⁺)** | **deliberately deferred — see below** |

**Bacterial ligase / NAD⁺ is deferred on its own merits, not blocked.**
NAD⁺ is not "ATP with a different name": it's nicotinamide mononucleotide
joined to an adenosine monophosphate through a pyrophosphate bridge — only
*one* half is adenine-based — and its byproduct is NMN, structurally
unrelated to any phosphate-chain shape. Reusing the A-P-P-P bead chain for
it would actively teach something false. It gets its own design pass.

This pass is therefore **eukaryotic-mode only** for ligase, consistent with
COMPLEXITY_MODEL.md's existing scoping of ligase's cofactor as a labeled
divergent-specific.

### Why these two together
They are the two trigger philosophies already proven separately in this
codebase — helicase is **clock-driven** (autonomous, per-step), ligase is
**event-count-gated** (fires on fragment seal). NaKPumpSpikeDesign.md
already flagged unifying those two under one pattern as an open question
worth answering. Building both under one lens tests whether a single lens
architecture genuinely covers both, or whether it secretly wants to be two
things. That's the architectural payoff beyond the pedagogical one.

### Why this is the right prerequisite for Krebs
The cofactor-activation mechanic (pick up ATP, spend it, discard the
byproducts, visually distinct from substrate incorporation) is exactly what
the Krebs spike will need for succinyl-CoA synthetase's GTP/ATP output, and
what `PhysicalKrebsDesign.md` assumes for its powered "battery" object.
Building it here, on enzymes that already work, means Krebs inherits a
proven mechanic instead of inventing one mid-spike.

---

## The two fuel mechanics must never be visually conflated

COMPLEXITY_MODEL.md states this already; restating because it is the whole
reason this lens is a separate thing rather than a decoration on existing
nucleotide capture:

1. **Substrate incorporation** (already built, `nitrogen_base.gd` +
   `polymerase_halo.gd`) — Pol III / primase pick a free nucleotide from
   solution and it *becomes part of the product*. Consumption.
2. **Cofactor activation** (this lens) — the enzyme picks up ATP, spends it,
   and *discards* it. The ATP becomes part of nothing.

A student watching both at once must be able to tell which is which.

**One deliberate exception to "keep them distinct": the adenine head is
shared on purpose.** ATP's A *is* the same adenine as the DNA base, and
showing that is the pedagogical payoff — biochemistry coming together
rather than two unrelated systems. So the glyph reuses the base's visual
language deliberately; the distinction is carried by the phosphate tail
(which no free nucleotide glyph has) and by the discard behavior, not by
making the adenine look different.

---

## The glyph family

Bead-chain, differing only by phosphate count — one shape vocabulary, no
new geometry per molecule:

```
ATP:  [A]─(P)─(P)─(P)      3 beads — whole cofactor, pre-cleave
ADP:  [A]─(P)─(P)          2 beads — helicase's discarded byproduct
AMP:  [A]─(P)              1 bead  — ligase's carried intermediate
```

A student who watches helicase first can read ligase's AMP instantly:
shorter tail = more spent. No new shape to learn.

**Pᵢ vs. PPᵢ — the one genuinely new shape:**

```
Pᵢ  (helicase):   (P)          single bead, floats alone
PPᵢ (ligase):     (P)══(P)      two beads FUSED to each other,
                                 drifting as ONE rigid unit
```

The fused connector is the disambiguating cue — a visibly thicker/distinct
joint than the adenine-to-phosphate links — per this project's existing
"shape and thickness first, never color alone" accessibility rule. PPᵢ must
never read as two loose phosphates that happen to be adjacent.

### Biological grounding for the shapes
- **Helicase**: hydrolysis cleaves the **β–γ** phosphoanhydride bond,
  releasing the terminal γ phosphate as free Pᵢ. ADP genuinely *is* ATP
  minus the last bead — the model is chemically correct, not just a
  convenient abstraction.
- **Ligase**: cleaves between **α and β**, releasing PPᵢ (two phosphates,
  fused) and leaving **AMP covalently bound to the enzyme itself**. The AMP
  then transfers onto the nick's 5' end (adenylylation), and only releases
  as free AMP once the 3'-OH attacks and the bond seals. This is why ligase
  *carries* its byproduct and helicase discards both immediately — a real
  mechanistic difference, not variety for its own sake.

---

## Helicase — timeline anchored to the step boundary

The constraint that shaped this: **the helicase's existing pace does not
change.** No compression of the glide, no delay to the barrel roll. ATP's
timeline is offset to sit *ahead of* the step it fuels, the same way
primase pre-places a primer ahead of where Pol III will need it.

```
Step i-1's step_t:  ... 0.7 ──────────── 1.0 │ Step i's step_t: 0 ──────────────► 1.0
                         │                    │                   │                  │
ATP:                  spawns,            docked,  ● SPARK      ADP recedes,      both gone
                      approaches         whole      (β-γ)       Pᵢ escapes         by 0.9
                                                                                        │
Helicase glide:                                    (UNCHANGED — starts here, exactly
                                                    as it does today, raw step_t)
```

The spark is pinned to the step boundary itself — which is simply "every
time the helicase arrives at a new slot."

**Nothing here is signal-triggered.** The entire cycle — approach, dock,
spark, drift, fade — is a **pure function of `(current_slot_index, step_t)`**,
with no state, no memory, and no event subscriptions. A boundary crossing
does not need to be announced, because "am I just past a boundary" is
answerable from `step_t` alone:

| Element | Derivation | Reads |
| --- | --- | --- |
| Approach visible | `step_t >= atp_spawn_lead_ratio` | **raw** |
| Docked (whole ATP) | `step_t >= atp_spawn_lead_ratio`, position lerps toward dock | **raw** |
| Spark visible | `step_t < atp_spark_window` (window sits just past the boundary) | **raw** |
| ADP / Pᵢ position | `f(eased)` — see Byproduct fates below | **eased** |
| ADP / Pᵢ alpha | ramps to 0 by `eased` ≈ 0.9 | **eased** |

This is deliberately the `helicase_ring.gd` model: that node has no "begin
rotating" event either, because every blob's pose is `f(roll)`. Pooled nodes
are assigned a **role per frame**, not a lifetime — so there is no "which
ATP is which" bookkeeping to reconstruct.

**An earlier draft of this document proposed firing the spark from
`helicase.gd`'s `slot_reached(index)` signal. That was wrong and is recorded
here so it is not re-proposed:** `scrub_to_slot()` sets `current_slot_index`
directly and **never emits `slot_reached`**, so a signal-driven spark cannot
be reconstructed by scrub at all. The same draft also claimed the cycle was
a pure function elsewhere in the document — two incompatible architectures
asserted in one design. Deriving everything resolves it.

A second reason the signal model failed: there are really **two** moments
needing a trigger, not one. The spark is at the boundary, but the approach
begins at 70% of the *prior* step — and `helicase.gd` emits nothing at 70%.
The event model would have needed a signal for one and a threshold test for
the other. The derived model needs neither.

### Why the spark precedes the motion — the biology
Hydrolysis and force-generation are separable events. The general power
stroke is: ATP binds → enzyme resets → hydrolysis occurs *on* the enzyme
(primed, nothing has moved yet) → **Pᵢ release** is what triggers the
force-generating conformational change → ADP releases. For hexameric
helicases (DnaB/CMG) the literature broadly ties hydrolysis-and-Pᵢ-release
around the ring to stepwise translocation, though the exact choreography is
still actively studied — worth not over-asserting in any label text.

Showing spark-then-motion (rather than spark-equals-motion) is an honest
dramatization of a real subtlety, in the same spirit as the barrel-roll
blob masking the exact instant a hydrogen bond breaks.

### Byproduct fates — three simultaneous, opposite-reading motions
All derived from `eased_step_t`, all pure lookups, no tweens:

```gdscript
var eased = helicase_mgr.get_eased_step_t()

# The cleave happened at the slot the helicase is currently AT.
# MUST use the same last_valid branch helicase_x itself uses. During
# FINISHING_LAST_PULSE the helicase steps PAST the last slot, so
# nucleotide_original_x[idx] would be out of range — but CLAMPING with
# min(idx, last_valid) is also wrong: it makes every finishing-phase cleave
# report the same origin, so ADP piles up repeatedly at the last slot while
# the helicase walks away from it. Extrapolate, exactly as helicase_x does,
# just evaluated at step start rather than mid-step.
var last_valid = num_nucleotide_slots - 1
var discard_origin_x: float
if idx >= last_valid:
    discard_origin_x = nucleotide_original_x[last_valid] + (idx - last_valid) * nucleotide_slot_spacing
else:
    discard_origin_x = nucleotide_original_x[idx]

# helicase glides FORWARD, level        (existing, unchanged)
# ADP recedes BACKWARD, level           — "discarded"
adp_x = discard_origin_x - nucleotide_slot_spacing * eased

# Pᵢ escapes FORWARD and UP (2 o'clock) — "spent to drive the motion"
pi_x  = discard_origin_x + (nucleotide_slot_spacing * pi_x_ratio) * eased
pi_y  = enzyme_y - pi_rise_distance * eased
```

**ADP and Pᵢ share one fade curve** (`atp_fade_duration`), both reaching
alpha 0 by `eased` ≈ 0.9.

*Deferred polish, recorded so the reasoning is not lost:* biology argues for
staggering them — Pᵢ release precedes ADP release, which is the same
ordering this design already dramatizes (Pᵢ leaving is what drives the
motion). It was not built because the entire drift window is 0→0.9, which at
1× is roughly 0.45 s; splitting that into staggered fades is likely
imperceptible and costs a second tunable for no legibility gain. Revisit if
the shared fade reads as two objects behaving identically when they
shouldn't.

ADP reuses `nucleotide_slot_spacing` directly (equal and opposite to the
helicase's own advance — the visual point). Pᵢ gets its own independent
`pi_x_ratio` / `pi_rise_distance`, because "2 o'clock" is an angle to be
eyeballed and tuned, not something that should be locked to a value that is
really about slot geometry.

Both byproducts **alpha-ramp to fully gone by `step_t` 0.9**, deliberately
clearing the site before the next spark fires at 1.0.

### Dock position
The θ=0 blob sits at the ring's own local origin
(`Vector2(0.0, ring_radius * sin(0))`), and `helicase_node.position` is
`Vector2(helicase_x, center_y)`. So the dock point is just the helicase
node's position — no blob math needed at all.

---

## Ligase — timeline anchored to existing state transitions

`replication_manager.gd`'s real tween chain, with hook points marked:

```
_ligase_kick():
  state = TRAVELING
  tween_property(position → target, ligase_travel_duration)     0.4s
  tween_callback(state = HOLDING)          ◄── ● SPARK fires here
  tween_interval(ligase_hold_duration)                          0.5s
                                           ◄── AMP carried (attached to blob)
                                           ◄── PPᵢ splits off, drifts, fades
  tween_callback(_ligase_seal)

_ligase_seal():
  state = SEALING
  tween_method(set_pulse, 0.0 → 1.0, seal_duration * 0.5)       0.15s  (pinch closes)
                                           ◄── NEW callback: AMP hop begins
  tween_method(set_pulse, 1.0 → 0.0, seal_duration * 0.5)       0.15s  (pinch releases)
  tween_callback(_ligase_finish_seal)      ◄── AMP detaches / fades, state = IDLE
```

**Why the spark sits at TRAVELING→HOLDING:** the cofactor only activates
once the enzyme has actually engaged the nick. Firing it mid-travel would
misrepresent what triggers cleavage. Mirrors helicase's "cleave at arrival."

**HOLDING has room.** At 0.5s it is the longest of the three phases (travel
0.4s, seal 0.3s), and it exists *specifically* for visibility — it was added
because the seal happened too fast to see the nick. Hosting
spark → AMP-carry → PPᵢ-drift-and-fade inside it fits the phase's original
design intent rather than fighting it.

**The AMP hop** — the adenylylation step — runs as its own brief tween in
parallel with the pulse's *second* half (the release). Reads as: pinch
clamps tight, then the enzyme visibly hands off what it was carrying as it
lets go. Duration is its own ThemeManager field, sized shorter than the
0.15s release half so it lands with a beat to spare rather than racing the
pulse.

### Ligase inherits a different scrub contract — and that's fine
`ligase.gd`'s header is explicit: the node is **hidden entirely during
scrub**, because "there is no 'the enzyme is mid-travel' state to reproduce
for an arbitrary scrub target." Its ATP visual inherits that exemption, so
real tween-driven timing is legitimate here — unlike helicase's, which must
be a pure function. Worth recording as a deliberate asymmetry, not an
inconsistency.

---

## Scrub-safety and phase coverage

**The ATP cycle is a pure function of `(current_slot_index, step_t)`** — the
same two values `helicase_x` and the barrel roll already derive from, both of
which scrub sets directly and instantly. It therefore snaps to the correct
state for free, with zero rebuild logic, exactly as `helicase_ring.gd` does.

### The cycle stays VISIBLE on pause and on scrub

An earlier draft proposed hiding the ATP visual whenever
`helicase_ring.rotation_frozen` is true. **That was wrong, and the reason
matters.** `manual_override` is not a scrub-specific flag — it is the
**pause flag**, set directly by `toggle_play()`. Hiding on it would mean the
ATP visual disappears every time a user pauses.

For a classroom tool that is backwards. Pausing to say *"the ATP just cleaved
here, now watch the phosphate leave"* is precisely the moment the object
needs to be on screen. The rule would have deleted the thing being discussed.

Because the cycle is fully derived, no hiding rule is needed at all:

- **Paused** — `step_t` stops advancing, so the cycle freezes mid-state,
  visible and correct. This is the teacher case, and it works by default.
- **Scrubbed** — `step_t` is set directly; the cycle snaps to the state that
  belongs at that position. Also visible, also correct.

This differs from `helicase_ring.gd`'s own `rotation_frozen` treatment, and
the divergence is deliberate: the ring collapses to a static symmetric pose
on pause because a *rotation phase* has no meaningful frozen value to show.
An ATP cycle does — "half-drifted, post-spark" is a real, informative state.
Freezing it is the point.

### Phase coverage — the cycle runs in two phases only

`helicase.gd` has five phases. The cycle is gated to the two where the
helicase is actually stepping:

| Phase | ATP cycle | Why |
| --- | --- | --- |
| `INTRO` | **Hidden** | `is_running` is false and `step_t` is 0 — which would sit inside the spark window and fire a spark before replication has begun. |
| `SWEEPING` | **Full cycle** | The normal case. |
| `FINISHING_LAST_PULSE` | **Full cycle, compressed — RESOLVED, stays on** | Still stepping. `step_duration` shrinks by `finishing_acceleration` (0.85) each step, floor 0.05. |
| `SETTLING` | **Hidden** | No stepping; `step_t` is stale. |
| `DONE` | **Hidden** | `is_running` is false; the scene fades out here anyway. |

The `INTRO` case is the load-bearing one: without an explicit gate, a
derived spark window keyed to low `step_t` values would fire at scene load,
before the helicase has moved at all.

**Why `FINISHING_LAST_PULSE` keeps the lens on.** The cycle lives entirely in
`step_t` space, so acceleration compresses it proportionally rather than
breaking it — it simply plays faster, exactly as the barrel roll already
does under the same acceleration. Four finishing steps at 1× reach
`0.5 × 0.85⁴ ≈ 0.26 s` per step: quicker, still legible. Switching the lens
off here would be the *more* jarring choice, since the helicase visibly
continues translocating and would appear to do so without fuel.

Note this phase is also the reason `discard_origin_x` must extrapolate
rather than clamp — see Byproduct fates above.

---

## Object lifecycle and pooling

Pooled, never instantiated or freed during play — same discipline as
`polymerase_halo.gd`'s particle pool.

**Cleave spawns nothing.** ATP-whole is 4 nodes (adenine head + 3 phosphate
beads). At cleave those same 4 nodes regroup into two independently-moving
clusters — helicase: ADP (head + 2) and Pᵢ (1); ligase: AMP (head + 1) and
PPᵢ (2, fused). No destroy-and-recreate.

**Peak concurrent load.** Helicase's cycle is bounded by the 0.7→0.9 overlap
window, where one generation's fading remnants coexist with the next
generation's approaching ATP: 2 generations × 4 nodes = **8 nodes**. Ligase
runs its own cycle concurrently and independently, adding **4 more** (ligase
fires once per fragment, so it has no self-overlap). **Peak is ~12 pooled
nodes**, not 8 — an earlier draft counted helicase only. Still cheap enough
for low-end hardware, which was an explicit design constraint, but the bound
should be stated correctly.

Each enzyme owns its own pool rather than sharing one. Two separate pools of
4 and 8 are simpler than one shared pool of 12 with contention rules, and
they match the project's existing per-enzyme `PolymeraseHalo` pattern (one
instance per polymerase, not one shared halo).

**Spawn model: just-in-time.** No ambient ATP field. An ambient population
would compete with the dNTP cloud for the same screen real estate at exactly
the moment the two fuel mechanics most need to read as distinct, and would
serve scattered enzymes (helicase at the fork, ligase trailing) poorly.

**Glyph implementation — deliberately NOT reusing `nitrogen_base.gd`
wholesale.** That scene is a `RigidBody2D` (frozen, plus a deferred-centered
`Label` child); inheriting physics-body overhead for 8 purely decorative
pooled nodes contradicts the low-end-hardware constraint. The ATP glyph
should be a lightweight `Node2D` that copies `nitrogen_base.gd`'s *visual*
conventions — same radius source, same `draw_circle(..., antialiased=true)`
approach (STATUS.md: a fixed-vertex polygon stays faceted regardless of
MSAA), same `pivot_offset` label-centering fix — without inheriting the
class. Recorded as a deliberate divergence, not a silent one; the visual
match is what's pedagogically load-bearing, not the class.

**No existing circle primitive.** `procedural_shape_utils.gd` provides only
`octagon()` and `round_corners()`. Phosphate beads use `draw_circle`
directly, as `nitrogen_base.gd` does. PPᵢ's fused connector is genuinely new
geometry with no existing primitive to build on.

---

## Toggles — a fourth cascade pattern

`complexity_manager.gd` currently implements three named patterns:
**standard** (parent off → child off), **bridge** (child on → parents on),
**mode-gate** (topology gates coherence). `atp_byproducts_visible` is none
of them:

> **Default-follows-parent, override-persists**: enabling
> `atp_activation_enabled` sets `atp_byproducts_visible = true` every time it
> is re-enabled. The user may turn `atp_byproducts_visible` off freely at any
> point, including mid-playback, without affecting the parent. Toggling the
> parent off and on again re-asserts the default.

The "re-assert on every parent enable" behavior was chosen deliberately over
"set once, remember user override forever" — it matches "turns on
automatically as ATP Cycle is toggled on" as a live rule rather than a
first-run default.

### What the toggle covers — mechanism vs. waste

The toggle was originally conceived as `adp_pi_visible`, named before
ligase's AMP and PPᵢ existed. That name is helicase-centric for what is
actually a cross-enzyme lens, and it does not answer what PPᵢ should do.
Renamed, with an explicit boundary:

| Object | Under the toggle? | Why |
| --- | --- | --- |
| ADP (helicase) | **Yes** | Discarded byproduct. |
| Pᵢ (helicase) | **Yes** | Discarded byproduct. |
| PPᵢ (ligase) | **Yes** | Discarded byproduct — exactly analogous to ADP + Pᵢ. |
| AMP released at `_ligase_finish_seal()` | **Yes** | Becomes waste at this moment. |
| AMP carried through `HOLDING` | **No — always visible** | Mechanism, not waste. |
| The AMP hop onto the nick | **No — always visible** | Mechanism, not waste. |

**The principle: AMP is mechanism until release, then waste.** Hiding the
carried AMP or the hop would hide *how ligase seals*, not merely tidy away
a discarded molecule — which is the opposite of what a decluttering toggle
should do. The whole ATP cycle can still be switched off wholesale via
`atp_activation_enabled` for users who want none of it.

`complexity_manager.gd`'s own comments ask that new cascade patterns be
named explicitly in COMPLEXITY_MODEL.md rather than each one being
re-derived ad hoc. This pattern should be added there when built.

---

## ThemeManager fields — split by concern, not lumped

Following the `EnzymeLabelsDesign.md` precedent (shared label fields in one
group; each enzyme's own margin in its own group), and the "never let two
independently-tuned numbers coincidentally agree" rule.

**New `@export_group("ATP Cycle")`** — the cofactor's own identity, shared
so that ATP looks like the *same molecule* wherever it appears:

```
atp_activation_enabled: bool
atp_byproducts_visible: bool   # renamed from adp_pi_visible — see Toggles
atp_bead_size: float           # phosphate bead radius
atp_adenine_scale: float       # relative to the base glyph's own size
atp_spark_duration: float
atp_spark_radius: float
atp_fade_duration: float       # shared by ADP and Pᵢ; see Byproduct fates
```

### Glyph text — no localization scope

Beads carry chemical symbols only: the adenine hexagon shows **"A"**, each
phosphate circle shows **"P"**. Both are identical in every language, so
**no CSV keys are required** — this lens adds nothing to the localization
surface, unlike the enzyme labels.

Molecule-level name tags ("ATP", "ADP", "AMP") are **deliberately not
added**. The bead count already is the label — a 3-bead chain next to the
text "ATP" is redundant, and the whole pedagogical point is that a student
reads spent-ness off the tail length rather than off a caption. Revisit only
if playtesting shows the bead count alone does not land.

**Existing `"Helicase Ring"` group gains:**
```
atp_spawn_lead_ratio: float    # 0.7 — RAW step_t threshold, not eased
atp_spark_window: float        # 0.10 — RAW step_t width of the spark's visible band
pi_x_ratio: float
pi_rise_distance: float
```

`atp_spark_window` default **0.10**: at 1× (`base_step_duration` 0.5 s) that
is roughly 0.05 s, about three frames at 60 fps — a classic arcade-flash
length. Tune by eye from there.

Note `atp_spark_window` is a **raw `step_t` width**, not a duration in
seconds. It therefore scales with the speed multiplier: at 8× the spark
occupies the same fraction of a much shorter step and may fall below one
frame. That is accepted, not a defect — at 8× the barrel roll and nucleotide
capture are equally illegible, and a spark that stayed prominent while
everything around it blurred would look wrong. The speed control is the
mechanism for observing detail.

**Existing `"Ligase"` group gains:**
```
ligase_amp_hop_duration: float
```

Note the forwarding requirement: `helicase_ring.gd` deliberately holds no
reference to ThemeManager (all config is local `@export`s pushed in by
`simulation.gd`, which duplicates each field as `helicase_ring_*`). The ATP
visual therefore **cannot be a child of the ring reading ThemeManager
itself**. This keeps the ring a pure function of one float, as its own
header insists.

**Parenting — a child of `helicase_node`, a sibling of the ring.** Same
relationship the ring itself has. This inherits `helicase_node.modulate` for
free, which matters at end-of-run: `_lagging_fade_enzyme_scene()` fades the
whole enzyme scene, and an ATP visual parented at the scene root would need
its own fade handling to avoid being the one object left behind.

Byproduct positions should be written via `global_position` rather than
local `position`, so the drift math stays in world space. ADP recedes while
its parent advances; expressing that as a local offset would mean carrying
the parent's own motion in every term — exactly the kind of derived value
this project keeps getting wrong when two things move at once.

---

## Ground-truth corrections made during this design

Recorded because each one was a wrong assumption caught only by reading the
actual file — the pattern this project's ground-truth discipline exists for:

1. **`ligase.gd` has no state machine.** It is a dumb view owning only its
   shape and `set_pulse(t)`. `LigaseState` (IDLE/TRAVELING/HOLDING/SEALING)
   lives in `replication_manager.gd`. Hook points are tween callbacks
   there, not states here.
2. **`helicase_ring.gd` reads no ThemeManager, by design.** Forced the ATP
   visual to be a sibling rather than a child (above).
3. **The θ=0 dock needs no blob math** — it is the ring node's own origin,
   which is `helicase_node.position`.
4. **`nitrogen_base.gd` is a `RigidBody2D`**, too heavy to reuse wholesale
   for pooled decorative glyphs (above).
5. **`procedural_shape_utils.gd` has no circle primitive** — only
   `octagon()` and `round_corners()`.
6. **`ligase_hold_duration` is 0.5s** — confirmed roomy enough for the
   sub-sequence, and confirmed to exist specifically for visibility.
7. **`manual_override` is the PAUSE flag, not a scrub flag.** Set by
   `toggle_play()`. An earlier draft's `frozen → hidden` rule would have
   hidden the ATP visual on every pause — the opposite of what a classroom
   tool needs. See Scrub-safety and phase coverage.
8. **`helicase.gd` does not emit `slot_reached` during scrub.**
   `scrub_to_slot()` sets `current_slot_index` directly. Any signal-driven
   trigger is therefore unreconstructible by scrub — which killed the
   event-driven model for this cycle.

---

## The easing trap — RESOLVED

`get_eased_step_t()` returns a **cubic ease-out**:
`1.0 - pow(1.0 - t, 3.0)`. Fast start, slow settle.

The ADP/Pᵢ drift is specified as eased, which is correct — it matches the
helicase's own feel. But **the ATP spawn threshold ("70% of the prior
step") is a raw `step_t` quantity, not an eased one**, and the two diverge
sharply:

| raw `step_t` | `eased_step_t` |
| --- | --- |
| 0.5 | 0.875 |
| 0.7 | 0.973 |
| 0.9 | 0.999 |

Testing the spawn threshold against the eased value would fire it at what
is effectively 97% of the step, leaving almost no visible approach.
**Spawn threshold reads raw `step_t` (`get_step_t()`, which exists); drift
positions read `get_eased_step_t()`.** This is precisely the "two similar
values are not interchangeable" trap STATUS.md documents repeatedly
(wobble-gating mismatch, camera `straight_y`, scrub tiling formula).

### Resolution: `simulation.gd` resolves both values at the boundary

The ATP node **never receives a value it could ease incorrectly**. Both
arrive already in their final space, named for that space:

```gdscript
# simulation.gd _process(), alongside the existing set_roll() call —
# both values are already in scope there (idx, get_step_t(), get_eased_step_t())
atp_cycle.update(
    spawn_progress_raw,      # helicase_mgr.get_step_t()
    drift_progress_eased     # helicase_mgr.get_eased_step_t()
)
```

The `_raw` / `_eased` suffixes are load-bearing, not decoration: a swapped
assignment reads as visibly incoherent rather than plausible. And because
resolution happens at the boundary, there is no downstream choice left to
get wrong — the ATP node holds no easing logic at all.

This matches the established pattern exactly. `simulation.gd` is already
the single funnel that resolves values and pushes them into
ThemeManager-free nodes: it does this for `helicase_ring`'s entire config,
for `label_counter_rotation`, and for `rotation_frozen`.

**Cost, stated honestly:** two parameters instead of the ring's single-float
contract. Accepted as the cheaper of the two prices available.

### Rejected alternative: extract the cubic into a shared helper

Extracting `1.0 - pow(1.0 - t, 3.0)` into a static utility both
`helicase.gd` and the ATP node call. Rejected for three reasons:

1. **It solves the wrong half.** A shared helper guarantees the *curve*
   matches, but the ATP node would still receive raw `step_t` and have to
   remember to ease it for drift and not for spawn. The original trap
   survives, relocated somewhere harder to see.
2. **The classification does not point to extraction here.** An easing curve
   IS a behavioral constant — SKILL.md's "Extract shared code by what
   divergence costs" entry says extract those on the second copy, and by
   that rule a shared helper would be defensible. But the same entry names
   an alternative that is strictly better when available: **eliminate the
   second consumer**. Boundary resolution does exactly that. Sharing a
   definition and removing the second consumer both prevent divergence;
   this one leaves fewer places able to get it wrong.
   *(An earlier draft argued this as "a fifth-copy extraction performed at
   copy two," reasoning from `procedural_shape_utils.gd`'s copy count. That
   was a heuristic mistaken for a principle, and SKILL.md now explicitly
   warns against reading it that way. The conclusion was right; the
   reasoning was not.)*
3. **It makes the ATP node less like `helicase_ring.gd`, not more.** The
   ring receives `roll` with the easing already baked in and never computes
   a curve. Teaching ATP to compute one moves it away from the purity model
   we're copying.

If a third consumer ever needs the curve, extract then.

---

## Open questions

All five questions carried by the previous draft are now resolved — see
`atp_spark_window`'s default (ThemeManager fields), the shared fade curve
(Byproduct fates), the mechanism-vs-waste boundary (Toggles), glyph text
scope (ThemeManager fields), and the `FINISHING_LAST_PULSE` decision (Phase
coverage).

What genuinely remains is tuning-by-eye rather than architecture:

- **`pi_x_ratio` and `pi_rise_distance`** — the "2 o'clock" angle exists to
  be eyeballed against the real scene. No sensible default can be derived on
  paper.
- **`atp_bead_size` / `atp_adenine_scale`** — must read as related to the
  DNA base glyph without competing with it for attention. Needs the two on
  screen together to judge.
- **PPᵢ's fused connector** — the one genuinely new piece of geometry in
  this design, with no existing primitive to build on. Its thickness has to
  clear the adenine-to-phosphate link thickness by enough that "one rigid
  unit" is unmistakable. A drawing problem, not a design one.

### Deferred, with reasoning recorded

- **Pᵢ-before-ADP fade stagger** — biologically correct, probably
  imperceptible at current window lengths. See Byproduct fates.
- **Molecule-level name tags** ("ATP"/"ADP"/"AMP") — redundant against bead
  count. See ThemeManager fields.
- **Bacterial ligase / NAD⁺** — a structurally different molecule needing
  its own design pass, not a recolor of this one. See Scope.

---

# As-Built (v78) — the helicase pass

_Written at Anneal. Records where Growth invalidated the Lattice, per
SKILL.md's rule that the divergence is recorded rather than the design being
silently patched to match. Eleven entries; the design was structurally
wrong, not sloppily wrong, and the reading that produced each correction is
noted so the next person learns where this codebase's intuitions mislead._

**Scope shipped:** helicase only. `atp_bead.gd` and `atp_cycle.gd` are new;
`simulation.gd`, `theme_manager.gd`, `complexity_manager.gd`,
`complexity_setup_popup.gd` and `ComplexitySetupPopup.tscn` were modified.
Nothing in `ligase.gd` or `replication_manager.gd` was touched — the ligase
half remains as designed, unbuilt, and its section below still stands.

---

## What held

Worth stating first, because most of the lattice did survive contact:

- **The derived model.** No signals, no state, no memory. `update()` is a
  pure function and scrub-safety came for free with zero rebuild logic,
  exactly as predicted.
- **Boundary resolution of the easing.** `simulation.gd` resolves both
  values and passes them pre-named; `atp_cycle.gd` contains no easing call.
  The rejected-alternative reasoning holds up in the built code.
- **Sibling-of-the-ring parenting.** Inheriting `helicase_node.modulate`
  meant end-of-run fade needed no handling at all.
- **The `discard_origin_x` extrapolation branch.** Built verbatim from the
  design's pseudo-code, including the warning against `min(idx, last_valid)`.
- **The fourth cascade pattern**, implemented as specified.

---

## 1. Toggle ownership moved to `complexity_manager.gd`

**Design said:** both bools live in ThemeManager's `ATP Cycle` group,
following `wobble_enabled`'s precedent as the other shipped cross-cutting
lens.

**As built:** `atp_activation_enabled` and `atp_byproducts_visible` are real
`@export var`s on `complexity_manager.gd`, alongside `primase_enabled` and
`pol1_enabled`. Only the tuning values stayed in ThemeManager.

**Why the precedent didn't survive.** `wobble_enabled` predates
ComplexityManager and has no cascade, so it was never a model for a toggle
that does. Reading `complexity_setup_popup.gd` settled it in one pass: that
dialog keeps its checkboxes in sync **only** through `toggle_changed`, and
reverts on Cancel **only** by replaying setters that live in
ComplexityManager. A ThemeManager-owned pair would have shown a stale
checkbox the first time the parent re-asserted the child — visibly wrong on
the first click, not a purity concern — and would have silently failed to
revert on Cancel.

The cost of implementing was also mis-estimated as new responsibility. It
isn't: `set_ligase_enabled()` and `set_lagging_gap_enabled()` already proxy
to properties that live on `simulation.gd`. The proxy-setter shape was
already in the file twice. ATP needed no proxy at all, making it the
*simplest* of the three.

## 2. The pool is eight beads, in two independent clusters

**Design said:** "Cleave spawns nothing… those same 4 nodes regroup into two
independently-moving clusters." Peak stated as 8 for helicase (two
generations × 4).

**As built:** `SPENT_BEADS` 0–3 and `WHOLE_BEADS` 4–7 are permanently
separate. Regrouping happens *within* a generation only.

**Why.** Sharing one cluster of 4 across generations requires a precedence
rule for the overlap window, and any tuning that widened the overlap would
then silently delete the byproducts. Eight pooled `Node2D`s is cheap even
under the low-end-hardware constraint; a tuning trap is not.

## 3. The "0.7 → 0.9 overlap window" does not exist at default tuning

This is the arithmetic the design didn't do, and it is the same raw/eased
conflation the document elsewhere goes to some length to warn about —
committed inside the warning's own section.

The byproducts fade out at **eased 0.9**. The approach begins at **raw
0.7**. Those are different spaces:

| quantity | raw `step_t` | `eased_step_t` |
| --- | --- | --- |
| byproducts gone | **0.536** | 0.9 |
| approach begins | **0.7** | 0.973 |

So at shipped defaults the two never coexist. There is instead a **dead band
of roughly raw 0.536 → 0.7** — about 0.08 s at 1× — where the helicase glides
with nothing else on screen. Peak concurrent bead count at default tuning is
therefore **4, not 8**; the pool of 8 exists so that tuning *into* an overlap
stays safe (entry 2), not because the default needs it.

The document's "Peak is ~12 pooled nodes" line, which corrected an earlier
draft's count, was itself corrected by arithmetic neither draft performed.

## 4. Local space, not `global_position`

**Design said:** write byproduct positions via `global_position`, because
ADP recedes while its parent advances and a local offset "would mean
carrying the parent's own motion in every term."

**As built:** `simulation.gd` subtracts `helicase_x` once and passes
`discard_origin_local`. `atp_cycle.gd` is entirely local-space.

**Why.** The premise is right about the general case but `simulation.gd`
already owns `helicase_x`, so the parent's motion is carried in exactly one
term, in the file that owns it — which is the same boundary-resolution move
the document itself adopted for the easing, applied one step further. The
payoff is that connector links draw directly from bead `position` without a
`to_local()` round-trip per bead per frame.

## 5. `atp_fade_duration` → `atp_byproduct_fade_end_eased`

The design names it a duration and then specifies it as "alpha 0 by `eased`
≈ 0.9" — a **position on the cubic curve**, not a number of seconds. The
name invites passing it 0.45. Renamed on that basis, and moved into the
Helicase Ring group with the other `step_t`-space quantities rather than the
shared identity group. A genuinely seconds-based fade belongs to the ligase
pass, whose cycle really is tween-driven.

## 6. The adenine is a circle

The doc contradicts itself: **Glyph text** says "the adenine hexagon shows
'A'", while **Object lifecycle and pooling** says to copy `nitrogen_base.gd`'s
"same radius source, same `draw_circle(..., antialiased=true)` approach."

The pooling section wins. The whole pedagogical payoff is that ATP's A *is*
the DNA base's A; a different silhouette would undercut the one thing the
shared head exists to say. Distinction is carried by the phosphate tail and
the discard behaviour, exactly as the doc's own **One deliberate exception**
paragraph argues.

Corollary: **the adenine has no colour field of its own.** `simulation.gd`
pushes `%ThemeManager.base_color_a` verbatim. Two independently-tuned colours
that are only ever supposed to agree is precisely the coincidence this
project's rule forbids — the fix is one authoritative source, not a second
tunable defaulted to match.

## 7. `atp_approach_offset` — a design gap, not a divergence

The timeline diagram says "spawns, approaches" and never says **from where**.
Added as `Vector2(150, -130)` in the Helicase Ring group: ahead of and above
the fork, so the cofactor reads as arriving from solution rather than being
emitted by the DNA. Pure tune-by-eye, same category as `pi_x_ratio`.

## 8. Vertical mode — the second design gap, and the more dangerous one

The doc's **Glyph text** section correctly concludes that "A" and "P" need no
CSV keys, being identical in every language — and then stops, never
revisiting the fact that they are still **drawn text**. Every glyph with text
in this project takes
`set_label_rotation(zoom_mgr.get_label_counter_rotation())`.

Without it the beads ship sideways in vertical mode. This is v77's
`nucleotide_field.gd` near-miss repeating exactly: a correct-sounding
completeness claim ("this lens adds nothing to the localization surface")
standing in for a check that was never run. Caught at Lattice review, before
code — the cheap place. `atp_bead.gd` implements it; `atp_cycle.gd` forwards
it to every bead via the same pushed-property contract `helicase_ring.gd`
uses for its own label.

## 9. `atp_spark_duration` not added

The design lists both `atp_spark_duration` (seconds, `ATP Cycle` group) and
`atp_spark_window` (raw `step_t` width, Helicase Ring group). For the
helicase these are two numbers meaning one thing, and the derived cycle can
only use the width. Deferred to the ligase pass, where seconds are the
natural unit because that cycle is genuinely tween-driven.

## 10. `update()` takes four parameters, not two

The doc's snippet shows two. The built signature is
`update(spawn_progress_raw, drift_progress_eased, discard_origin_local, active)`,
plus `byproducts_visible` written as a property each frame — the same idiom
`simulation.gd` already uses for `helicase_ring.rotation_frozen`.

The doc's own **Cost, stated honestly** paragraph accepted two parameters
against the ring's single-float contract. The real price was four. Still the
cheaper of the options available, but the number should be recorded
accurately rather than inherited from the draft that under-counted it.

Two further fields also had no design entry: **`atp_bead_spacing`**
(centre-to-centre along the chain) and **`atp_z`**, which must clear
`helicase_ring_front_z` (4) or the docked ATP disappears behind whichever
blob is front-centre at the boundary — the exact moment it must be visible.

## 11. Ground-truth correction #9 — scrub always lands inside the spark window

The design's **Scrub-safety** section states: "Scrubbed — `step_t` is set
directly; the cycle snaps to the state that belongs at that position."

`helicase.gd`'s `scrub_to_slot()` sets `step_t = 0.0` **unconditionally**. It
does not set an arbitrary value. So every scrub target renders the identical
state: spark on, byproducts at their origin un-drifted, no approaching ATP
(0 < 0.7). The entire drift range is unreachable by scrub.

Kept deliberately. Landing on a slot *is* landing on a cleave boundary, so
"the cleave at this slot" is the honest state, and it marks where the
hydrolysis happened at the position being examined. But two consequences
follow and both belong in the record:

- The arcade-flash reading of the spark exists **only during live play**. On
  scrub it is a static ring.
- **Pause is unaffected** — it holds whatever `step_t` was — so the classroom
  case the design fought for ("pause and say *the ATP just cleaved here, now
  watch the phosphate leave*") works exactly as intended. It is scrub, not
  pause, that collapses to one state.

This is the ninth entry in the document's **Ground-truth corrections** list
and belongs with correction #8, which caught the neighbouring fact that
`scrub_to_slot()` emits no `slot_reached`. Both come from the same three
lines of `helicase.gd`; the first reading found one and stopped.

---

## Open questions after v78

The three tune-by-eye items from the original **Open questions** are now
answerable against a running scene rather than on paper — `pi_x_ratio` /
`pi_rise_distance`, `atp_bead_size` / `atp_adenine_scale`. Add
`atp_approach_offset` and `atp_bead_spacing` to that list.

One new question, which only a running scene can settle: **does the frozen
scrub spark (entry 11) read as informative or as a rendering artifact?**
If artifact, the cheapest honest fix is to suppress the spark specifically
when `helicase_mgr` is not running *and* `step_t` is exactly 0 — narrow
enough not to disturb the pause case, which never lands on exactly 0.

Unchanged and still open: **PPᵢ's fused connector**, the only genuinely new
geometry left in this design, deferred with the rest of the ligase pass.

---

# As-Built (v79) — the ligase pass

_Four further entries, plus the answer to the question this whole design
existed to ask. New file: `ligase_atp.gd`. Modified:
`replication_manager.gd`, `theme_manager.gd`, `complexity_manager.gd`,
`simulation.gd` (version header only)._

## 12. The architectural question, answered: one lens, TWO mechanisms

**The design's stated payoff** (Why these two together) was that helicase is
clock-driven and ligase is event-count-gated, that NaKPumpSpikeDesign.md had
flagged unifying those two triggers as an open question, and that building
both under one lens would "test whether a single lens architecture genuinely
covers both, or whether it secretly wants to be two things."

**It wants to be two things, and that is the right outcome.** What the two
halves share:

- the glyph vocabulary (`atp_bead.gd`, reused verbatim by both)
- the ThemeManager `ATP Cycle` identity group
- the toggle and the mechanism-vs-waste boundary
- the biology being taught

What they share **nothing** of: timing, triggering, state, or space.
`atp_cycle.gd` is a pure function of two floats with no clock; `ligase_atp.gd`
is five tween-driven calls hung off an existing chain. Neither imports the
other's ideas.

The reason is not stylistic, and it is worth carrying to the pump and to
Krebs: **the trigger philosophy follows from the SCRUB CONTRACT, not from the
enzyme.** The helicase must reconstruct instantly for an arbitrary scrub
target, so it cannot own timing. Ligase is hidden entirely during scrub
(`ligase.gd`'s own header), so it may. Any future enzyme's ATP visual should
be decided the same way — ask what scrub does to that enzyme first, and the
mechanism falls out. Attempting to unify these two under one timing model
would have forced the derived half to carry machinery it must not have.

## 13. Eukaryotic-mode gating is `topology_mode`, and the pattern already existed

The design says this pass is "eukaryotic-mode only" for ligase without saying
what a eukaryotic mode *is* in the shipped code. It is `topology_mode`:
COMPLEXITY_MODEL.md's own table reads **Circular (bacterial) / Linear
(eukaryotic)**, and `complexity_manager.gd` already had the machinery, since
`is_enabled("lagging_gap")` folds exactly this check in.

So `is_enabled("atp_ligase")` returns
`atp_activation_enabled and topology_mode == LINEAR`, and
`replication_manager.gd` never learns topology exists. **Second registered use
of the mode-gate pattern**, not a new one.

Note the deliberate asymmetry: `is_enabled("atp")`, which drives the helicase,
is **not** topology-gated. Helicase runs on ATP in both domains. Two keys, two
gates, because the biology differs — the labeled-chimera principle applied to
a toggle rather than to a visual.

## 14. `atp_spark_duration` and `atp_fade_duration` return, correctly, as seconds

Entry 5 renamed the design's `atp_fade_duration` away, and entry 9 declined to
add `atp_spark_duration`, both on the grounds that the helicase's cycle lives
in `step_t` space where seconds are the wrong unit. The ligase pass is where
both fields become meaningful **under their original names**, because this
half really is tween-driven.

The lens therefore ends up with two fade parameters that sound alike and are
not interchangeable:

| Field | Space | Consumer |
| --- | --- | --- |
| `atp_byproduct_fade_end_eased` | position on the eased curve | helicase |
| `atp_fade_duration` | seconds | ligase |

This is the "never let two independently-tuned numbers coincidentally agree"
rule inverted — here two numbers must NOT agree and must not be mistaken for
each other, so they are named for their spaces. The design was right that the
fields belonged in the shared identity group; it was wrong only about which
half could use them.

## 15. Two tweens, not one — and a shared drift vector that is deliberate

Two smaller decisions, recorded because each was a near-miss:

**`_ppi_tween` and `_amp_tween` are separate.** A single shared tween meant
`hop()` would kill the PPi fade mid-flight whenever `atp_fade_duration` was
tuned longer than `ligase_hold_duration`, freezing PPi half-transparent until
the next reset. Independent motions of independent objects get independent
tweens; the default timings hide the bug, which is what makes it a trap.

**`atp_discard_drift` (renamed from the draft's `atp_ppi_drift`) serves both
PPi at cleave and the released AMP at seal completion.** One field, two
consumers, on purpose: they are the same event — *this molecule is now waste,
watch it leave* — so a single authoritative source is correct, and two
independently-tuned vectors would only ever be tuned to agree. Renamed away
from `ppi` so the shared use reads as intended rather than as a leftover.

Also: named callbacks (`_ligase_enter_holding`, `_ligase_atp_hop`) rather
than multi-line lambdas at the two new hook points. The one pre-existing
lambda in that chain was a single expression; GDScript's multi-line lambda
parsing is fragile enough not to introduce more.

---

## Still open after v79

- **The frozen scrub spark** (entry 11) — unchanged, still needs eyes on a
  running scene. Helicase only; ligase is hidden on scrub so the question
  does not arise there.
- **PPi's fused connector thickness** — `atp_fused_link_width` defaults to
  9.0 against `atp_link_width` 4.0. Whether that clears the "one rigid unit"
  bar is a drawing judgement, not a design one.
- **`ligase_atp_carry_offset` / `ligase_atp_nick_offset`** — pure eyeball,
  same category as `pi_x_ratio`. The carry point must read as *on* the blob
  and the nick point as *on the strand*, and neither can be derived on paper.
- **Bacterial ligase / NAD+** — scoped below, not yet built.

---

# The NAD+ pass — scoped (post-v79)

_Written down so the finding does not have to be re-derived. The drawing work
is genuinely small; the naming decision is the real content._

## The two cofactors are structurally parallel

Checked against the chemistry rather than assumed. NAD+ is a **dinucleotide**:
nicotinamide mononucleotide joined to adenosine monophosphate through a
phosphoanhydride (pyrophosphate) bond. Bacterial LigA cleaves that bond,
transferring the adenylyl group to an enzyme lysine and releasing NMN.

| | donor chain | carried | released |
| --- | --- | --- | --- |
| Eukaryotic (ATP) | `[A]-(P)-(P)-(P)` | AMP `[A]-(P)` | PPi `(P)=(P)` |
| Bacterial (NAD+) | `[A]-(P)-(P)-[N]` | AMP `[A]-(P)` | NMN `(P)-[N]` |

**Same four-bead chain, cleaved at the same relative position.** Only the
terminal bead differs — nicotinamide instead of a third phosphate. Both
models collapse the riboses, exactly as the shipped ATP glyph already does.

Consequence: **the entire adenylylation half is domain-independent and
already shipped.** Carry, hop onto the nick, release — `_amp_group` needs no
changes whatsoever. Bacterial and eukaryotic ligase genuinely share that
mechanism; the visual sharing it is not a shortcut.

## Drawing work

Small. Rename `_ppi_group` to something domain-neutral (`_leaving_group`),
swap bead 3's glyph and colour by donor mode, and **drop the fused-connector
treatment for NMN**. That last one is not an omission: `atp_fused_link_width`
exists because PPi's two phosphates are identical beads that must not read as
two loose Pi. NMN's two beads are already visually distinct, so an ordinary
link carries the meaning and a thick one would falsely imply the same
"rigid fused unit" claim.

## The actual cost: the toggle stops meaning "ATP"

`is_enabled("atp_ligase")` currently returns
`atp_activation_enabled and topology_mode == LINEAR` — a mode GATE. Ship NAD+
and ligase has a cofactor in both modes, so the check becomes a mode
PARAMETER instead. That ripples:

- **Key rename** — `atp_ligase` becomes something like `ligase_cofactor`.
  Touches `complexity_manager.gd`, `replication_manager.gd`'s
  `_ligase_atp_enabled()`, and COMPLEXITY_MODEL.md's Toggle Registry.
- **`UI_ATP_TOGGLE_LABEL`** — "ATP (energy cofactor)" is wrong once the lens
  shows NAD+ in bacterial mode. Wants a domain-neutral label.
- **`UI_ATP_BACTERIAL_LIGASE_NAD_TOOLTIP`** — becomes obsolete outright. It
  exists to explain an ABSENCE; filling the absence removes its reason to
  exist. Delete it in the same pass rather than leaving a string that
  describes a state the build no longer has.
- **The lens name itself** — the whole feature is called "ATP activation"
  throughout this document, `atp_cycle.gd`, `ligase_atp.gd` and the
  ThemeManager group. Helicase genuinely does run on ATP in both domains, so
  those names stay honest for that half. Whether the SHARED identity group
  should be renamed (cofactor rather than ATP) is the one real open question,
  and it is a naming decision with a file-rename cost, not a drawing one.

## Recommendation

Do not start the drawing before settling the naming. The thirty lines are
not where this pass can go wrong; a half-renamed toggle registry is.
