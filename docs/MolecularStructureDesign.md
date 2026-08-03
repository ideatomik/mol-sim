# Molecular Structure — Design (pre-implementation)

_Lattice-phase doc per the Crystal Building Method. **This is a
cross-cutting subsystem doc, a peer of `COMPLEXITY_MODEL.md` and
`SHARED_BASE_SEAM.md` — not a companion to any single module.** It is
foundational to both DNA replication's deep zoom and to Krebs, which is
why it belongs to neither. See the status note below on what has and has
not shipped — this is no longer accurate as a blanket "nothing has
shipped" statement for the DNA slice specifically._

_**Partially grounded.** `nitrogen_base.gd` and `zoom_manager.gd` were read
after the first draft; five assumptions died on contact and are recorded in
**Ground-truth corrections** below — including one that materially weakens
this doc's own sequencing argument. The body above that section is preserved
as written at Lattice time; where the two disagree, the corrections section
wins._

_**Fully grounded as of the third pass.** All six files flagged after the
first draft — `procedural_shape_utils.gd`, `cofactor_bead.gd`,
`nucleotide_field.gd`, `polymerase_halo.gd`, `theme_manager.gd`, and
`replication_manager.gd` — have now been read. See **Ground-truth
corrections** below for all three passes; the third found no new
contradictions, only confirmation of corrections #3, #6, and #7. Nothing
left unread does not mean nothing left unresolved — see **Open questions**
below for what's still undecided regardless of file-reading status._

_**"Nothing here has shipped" is now stale for the DNA slice.** The DNA
milestone's scope fence (ribose + phosphodiester operator + skeletal
rendering, see "First milestone" below) has substantially built and
shipped, across Growth Session 1 and the base-pair expansion pass —
`MolecularStructure_BasePairExpansion.md` is the As-Built-style record of
that work (bugs A through M, all root-caused via code trace or live
diagnostic dump, not guessed). This doc's own Lattice-phase status
survives for what it actually governs — the cross-cutting layer Krebs will
also depend on — but should no longer be read as describing unbuilt DNA
work. See the new Layout-rule subsection below and Open Question 2's
update for two places the growth session fed real findings back up into
this cross-cutting doc, per the project's own Annealing discipline._

---

## Nucleation — the seed problem

Two observed facts, from different directions, that turn out to be the same
problem:

1. **Enzyme silhouette authoring is a blind loop.** Procedural shape work
   is currently iterated by describing vertex geometry in prose to an
   assistant that cannot see the result. It is the only part of this
   project with that property — architecture, state derivation, and bug
   hunting are all text-native. Dozens of round-trips per shape.
2. **At the zoom level where molecular structure matters, shape stops
   being a matter of taste.** "What 5'→3' actually means" is a question
   about the geometric arrangement of specific carbons. The ribose ring,
   the exocyclic 5' carbon, the 3' hydroxyl, and the phosphodiester bridge
   have canonical connectivity and published geometry. Hand-placing those
   vertices would be *worse* than deriving them: it puts eyeballing where
   there is a right answer.

The seed is therefore **not** "build a shape editor." A vertex editor
serves (1) badly and (2) not at all. The seed is: **below a certain zoom
level, molecular structure is data, and the project currently has no
representation for it.**

### What this doc is not

It is not the answer to problem (1). That has its own, much cheaper answer
recorded in `NaKPumpSpikeDesign.md`'s territory rather than here:
`@tool` annotations plus parametric poses, giving live editor-viewport
redraw as Inspector values change. Enzyme silhouettes are parametric
functions of a driving scalar (`set_pump(t)`, the ring's `|cos θ|`
breathing, `set_pulse(t)`) and are a different kind of object from a
molecule. **The two must not be unified.**

---

## The three-layer model

Keeping these separate is the whole architecture. Everything else in this
doc follows from it.

| Layer | Owns | Does not own |
| --- | --- | --- |
| **Topology** | Atoms, bonds, identity | Any coordinate |
| **Layout** | Positions, per named projection | What is connected to what |
| **Render mode** | How it is drawn | Position or connectivity |

**Topology.** An atom is an element, a formal charge, and a persistent
**identity**. A bond is two atom IDs, an order, and stereo flags where they
matter. No coordinates at this layer, ever.

**Layout.** A function from topology to 2D positions. **Must be
deterministic.** Force-directed layout is disqualified outright — it is
iterative and seed-dependent, so it would render a different picture on
each scrub. That is a direct violation of the instant-snap invariant at the
most fundamental level available, and no amount of caching rescues it.

### Layout rule: substituent direction must be grounded, not shared

A layout function is deterministic by construction the moment it is a pure
function of topology — but determinism alone does not make it *correct*.
A layout can compute the same wrong answer every time, reproducibly, and
pass every scrub-safety check while still not describing the molecule it
claims to.

**The failure mode, found repeatedly enough in the DNA milestone to name
as a rule rather than a one-off:** when an atom has more than one
substituent branching off it toward different real neighbors, each
branch's direction must be derived independently — grounded in either (a)
real reference geometry for that specific bond, or (b) real position data
for whatever it actually connects to. **Never a single shared direction,
sign, or flag applied to more than one substituent on the assumption that
ring symmetry, or a nearby real constraint, makes them equivalent.**

This is not a hypothetical risk. `MolecularStructure_BasePairExpansion.md`
records the same underlying failure surfacing at least twice under
different names, at different layers of the same nucleotide, across a
single growth session:

- **Bug D/F** (base ring placement): `NitrogenBaseDeriver`'s rotation was
  fully consumed aligning the attachment atom toward the real partner,
  leaving the anchor atom's own facing an unconstrained side effect —
  correct for some strand/pairing sign combinations, wrong for others,
  purely because two chemically distinct atoms (attachment, anchor) were
  governed by one shared rotation decision.
- **Bug J/L** (ribose ring and substituent chain): `RiboseDeriver`'s ring
  rotation is correctly tied to a *fixed* per-strand sign (the
  antiparallel-orientation fix, confirmed correct and never touched by
  the bugs below it); the substituent chain was originally derived from
  that same ring-local frame with no awareness of the real partner
  direction, then patched (Bug J) to flip based on
  `pairing_direction`, which broke the ring/chain's own mutual
  consistency for exactly the two strands the patch touched (Bug L) —
  two independently-oriented parts of one residue disagreeing with each
  other, the identical shape of bug as Bug D/F one layer up.

**Verified against real measured geometry, not assumed to be true:**
Gelbin, A.; Schneider, B.; Clowney, L.; Hsieh, S.-H.; Olson, W. K.; Berman,
H. M. *Geometric Parameters in Nucleic Acids: Sugar and Phosphate
Constituents.* J. Am. Chem. Soc. **1996**, 118, 519–529 — the standard
statistical survey (~127 high-resolution crystal structures) for this
geometry. In deoxyribose, the bond angle at C4' (C5'-C4'-C3') averages
114.7°; the bond angle at C3' (C4'-C3'-O3') averages 110.3°. These are two
separately measured quantities, not one value read from two symmetric
ring positions — external confirmation that C5' and O3' are governed by
independent torsion angles in the real molecule (γ for C5'-C4', ε for
C3'-O3'), never a mirrored or shared pair. This also supersedes this
doc's own Open Question 2 placeholder of "~109.5° tetrahedral angles" with
real per-bond values; see that question's update below.

**Named exception, not silently resolved:** the shipped Bug J/L fix
derives substituent direction from `pairing_direction` — the vector
toward the real H-bond partner on the *other* strand — and verifies
itself by checking whether the result faces the partner correctly. That
is a real, working, screenshot-and-diagnostic-confirmed fix for the
symptoms it targeted, and it is **confirmed chemically inaccurate**, not
merely unconfirmed: Gelbin's data says C5'/O3' are governed by the real
*same-strand* neighbor (the previous/next residue along the backbone),
independent of which base is paired to what, and `pairing_direction` is
not that reference. The two only produce the same answer by coincidence
of this milestone's specific antiparallel duplex topology, not by
construction. Carried forward as a named exception (same treatment as
the aconitase exception below) rather than a silent one — see Open
Question 10. Whether to spend the effort re-deriving C5'/O3' from real
same-strand neighbor positions now, given the shipped version already
passes its own verification and nothing currently visible depends on the
difference, is the only part left open; Krebs will need its own answer
regardless, since it has no "previous/next residue" to borrow this exact
mechanism from. Bug M attempted a related direction change (deriving
outward directly from `-pairing_direction` rather than ring-vertex
position) and was tested live and reverted — the crossing it targeted
turned out not to be a neighbor-collision at all, per
`MolecularStructure_BasePairExpansion.md`'s own concluding investigation,
which is a useful caution against assuming a direction fix is required
before checking what the symptom actually is.

**Practical check before shipping any future substituent-direction
derivation:** ask whether two or more branches share a computed direction,
sign, or boolean flag. If yes, ask whether that sharing is justified by
the branches actually being the same thing chemically (rare) or is a
convenience inherited from a nearby but different constraint (the failure
mode above, twice). When in doubt, verify against a cited source or real
position data before trusting the geometry to look right — this class of
bug can render as plausible-looking crowding for a long time before
anyone traces it back to the actual direction math, which is exactly what
happened across Bugs D through M.

**Render mode.** Bead-glyph (what the ATP cofactor beads already do),
skeletal / line-angle (the organic-chemistry standard), ball-and-stick.
Same topology, different renderer. **This is what makes zoom tractable:
zooming in does not load new art, it swaps renderer on data that was
already there.**

---

## The central decision: derived, not stored

Two models were considered. This section records why the losing one lost,
because it is the more obvious one and will be proposed again.

### Model A — author each intermediate (REJECTED)

Citrate, isocitrate, α-ketoglutarate… eight molecule literals, and
`molecule_at(platform)` is an array lookup. Trivially scrub-safe, easy to
build, easy to explain.

Rejected because it is the "never let two independently-tuned numbers
coincidentally agree" rule violated in visual form. Citrate and isocitrate
differ by one hydroxyl moving between adjacent carbons. Authored
independently, **nothing structurally enforces that everything else stayed
the same** — and "everything else stayed the same" is precisely what the
student is there to learn. Eight molecules that are all supposed to agree
about being the same carbon backbone is eight chances to silently disagree.

### Model B — seed plus reaction operators (ADOPTED)

Author the seed once. Every step is an operator: *this bond breaks, this
group leaves as CO₂, this hydride goes to NAD⁺*. Then:

```
molecule_at(step_n) = fold(reactions[0..n], seed)
```

Replay from the seed on every scrub. On the order of 30 atoms across 8
operators — pure computation, no animation, microseconds. **This is the
regent pattern applied to chemistry: the molecule is derived from the
counter, never stored.**

Three payoffs beyond the principle:

**The operator is the pedagogy.** "Isocitrate dehydrogenase decarboxylates
and reduces NAD⁺" is not a caption written next to the animation — it is
the literal content of the operator. Teaching text and code become one
artifact, which is the same collapse the derivation rule buys everywhere
else in this project.

**Atom identity becomes visible.** If atoms persist across transformations,
the simulation can show something almost universally taught wrong: **the
two carbons entering as acetyl-CoA are not the two released as CO₂ on that
same turn.** They leave on later turns. This is the isotope-labeling
result; it is genuinely counterintuitive; and essentially no textbook
diagram can show it, because textbook diagrams have no atom identity. This
is a claim about mechanism that static media cannot make — the strongest
single argument this subsystem produces.

**The wraparound seam becomes falsifiable.** `KrebsCycleDesign.md`
currently treats it as "will the loop close cleanly." Under Model B it is a
hard assertion: replay all eight operators and the result must be
**graph-isomorphic to the seed**. Not "looks the same" — provably the same
molecule, testable in code, pass/fail. That is a considerably stronger
*desafio tecnológico* than the software-only Krebs spike that priced near
zero (see `TODO.md`, PIPE pivot of 22 July).

---

## Layout: deterministic is not enough — it must be stable

If forming a bond at carbon 4 shifts carbon 1, the student's eye loses the
backbone and the transformation becomes unreadable. Determinism prevents
scrub flicker; **stability** is what makes the thing teach.

**The rule: the carbon skeleton carries canonical positions, and
substituents hang off it at derived angles.** The backbone stays anchored
across the whole cycle; only what is attached to it changes. This is the
correct pedagogy anyway — a student tracking Krebs should be tracking a
backbone that stays put while groups come and go.

Same principle for the nucleotide: the furanose ring has canonical vertex
positions, and 5'-CH₂-phosphate and 3'-OH are substituents at known ring
positions. **The 5'→3' directionality then falls out of the geometry
rather than being an arrow that was drawn on.** That is the version of
"what 5'→3' actually means" worth building; an annotated arrow is not.

### UNRESOLVED — aconitase breaks the anchored backbone

Citrate is prochiral and aconitase acts on it asymmetrically. The backbone
arguably *reorients* at that station, which is the one place the
skeleton-stays-put rule may not hold.

**Decision for now: carry it as a named exception, not a silent one.** This
is explicitly flagged as unresolved and will have to be addressed properly
before the full eight-station Krebs model is built — a named exception is a
holding position, not an answer. When it is addressed, ask whether the rule
needs weakening globally or whether aconitase genuinely is singular.

---

## Layers: presence, occlusion, and the third state

2D representations of overlapping structure are the recurring failure of
printed molecular illustration. The GPCR snake diagram is the worst
offender and the clearest case: it is an *accurate drawing of the wrong
thing* — faithful about connectivity (which residues sit in which helix,
which loops are extracellular) and destructive of spatial adjacency. TM3,
TM5, TM6 and TM7 form the orthosteric pocket; in the snake diagram TM3 and
TM6 are nowhere near each other. The one relationship the student needs is
the one the projection guarantees to hide. The G-protein docking site fails
the same way on the opposite face: the diagram has no cytoplasmic
*surface*, only a row of loop-ends.

Print must choose one occlusion order and live with it forever. **This
project can make occlusion a variable.** That is a structural advantage,
not an incremental one — but it needs a rule, or layers become a dumping
ground.

### Presence and occlusion are different axes

- **Complexity toggles change what is *modeled*.** Turning off Pol I means
  Pol I is not part of the simulation.
- **Layer visibility changes what is *drawn* of something that remains
  fully present.** Ghosting TM1–TM2 does not remove them; they are still
  in the topology, still conceptually occluding.

The codebase has already brushed against this: `byproducts_visible` hides
discarded ADP (tidying), and `ATPCycleDesign.md` explicitly refused to let
the carried AMP be hidden because that would hide *mechanism*. Same
boundary, one level up. Promote it from a one-off judgment to a stated
rule, because at molecular zoom it will recur constantly.

### Three states that must never be conflated

| State | Meaning | Drawn |
| --- | --- | --- |
| **Absent** | Not in the model | Nothing |
| **Hidden** | In the model, suppressed deliberately | Nothing, but *indicated* |
| **Ghosted** | In the model, reduced alpha | Yes, still conceptually occluding |

A student who cannot tell "I turned this off" from "this is not there"
learns something false about the biology. Decided once, consistent across
all modules.

### Layer state is VIEW state, not MODEL state

**The regent must never write it, and `scrub_rebuild()` must never reset
it.** If a student ghosts two helices and then scrubs, the ghosting
survives.

This is a genuinely new category in this codebase — everything to date is
either regent-derived or a complexity toggle. Stated here explicitly
*before* the first implementation, because the default instinct will be to
make layer state a function of the step counter, and that would be wrong.

---

## Plural layouts, and the unfurling transition

The snake diagram is **a layout, not a truth**. The helical wheel is a
different layout of the same topology. The side-on bundle is a third. Same
elements, same identities, three projections.

This means the project does not have to pick a winner. **The projection
change itself becomes a teaching beat that nobody teaches.** Courses show
the snake diagram, separately show a ribbon structure, and leave the
student to reconcile them privately — most never do. Watching the row fold
into a barrel, with helix 3 keeping its identity and colour the whole way,
*is* the missing explanation.

Scrub-safety survives cleanly: `projection_t` is another derived scalar,
every intermediate is a deterministic interpolation between two layouts
over an identical element set, no accumulated state anywhere.

**Three cautions, all real:**

1. **The morph teaches a lie if unlabeled.** A student who watches a
   receptor unfurl will believe receptors unfurl. It must read as *the
   diagram rearranging*, not the protein moving — different easing, a
   frame or grid that visibly reorganizes, an explicit label. This is the
   labeled-chimera principle applied to projection rather than to
   organism: the representational move is declared, never smuggled.
2. **Naive interpolation passes helices through each other.** Lerping
   seven positions from row to ring produces crossings. Fixable — an
   intermediate keyframe, or interpolation in polar coordinates around the
   eventual bundle axis — but it is real work, to be costed before the
   animation is promised to anyone.
3. **Layers can become an excuse not to solve layout.** "The student can
   toggle it" moves the work from the author to the student, and a student
   who does not yet know what they are looking at does not know what to
   toggle. **The default state, before anyone touches anything, still has
   to teach.** Layers are for genuine either/or occlusion where no single
   view can serve both purposes — not a substitute for choosing well.

### The capability worth chasing: superposition

Not ghosting. **Overlay of two states of the same object**, aligned on
shared elements — inactive receptor against active, with TM6's outward
swing visible as one image and a slider between them. Structural
biologists do exactly this with aligned structures; it is how the field
thinks, and it is impossible in print.

It works *only* because element identity persists: helix 6 in state A and
helix 6 in state B are the same entity, so the alignment is computed, not
eyeballed. This is the third distinct payoff falling out of persistent
identity — a strong sign the abstraction is load-bearing rather than
merely elegant.

Composes with the unfurl: keep the snake diagram as a ghosted underlay
while the bundle folds, so the student watches the familiar
representation register onto the spatial one rather than being replaced
by it.

---

## Scale boundary — this does NOT extend to membrane proteins

Atoms-and-bonds does not describe a GPCR. At that scale an element is a
**helix**, and the relations are spatial-and-topological, not covalent.
Forcing one schema across both scales would produce something serving
neither.

**What generalizes is the principle, not the schema:** topology separate
from layout, layout plural and named, identity persistent, view state
distinct from model state.

The membrane-protein layer therefore gets its own future design doc. It is
named here so the boundary is deliberate rather than discovered later.

There is also a cheaper answer to the specific GPCR question worth trying
*first*, before any projection-morphing is committed to: **a side-on bundle
with the two front helices ghosted** — a cutaway. Ghosted rather than
deleted, so nothing is silently claimed absent. The ligand descends into a
pocket whose walls are visible; the G-protein docks on a cytoplasmic face
that exists as a surface. One well-chosen projection plus transparency may
deliver most of the pedagogy for a fraction of the cost, and building it
first is how you find out whether the morph is needed at all.

**A related standing risk, flagged not decided:** a fixed oblique / 2.5D
projection with real per-element depth ordering is technically easy in
Godot 2D. The cost is not technical — the entire visual language is
currently flat orthographic side-view, and introducing a second projection
convention across modules is a consistency debt carried forever. To be
decided deliberately, never drifted into.

---

## Hard scope boundary

This must not become a chemistry engine. Explicitly **out of scope**:

- SMILES / InChI parsing
- General valence solving, aromaticity perception
- 3D coordinates, conformers, energy minimization
- Reaction prediction of any kind
- Any molecule not on the authored cast list

**In scope:** a fixed, hand-authored cast — on the order of 40 molecules
and 20 operators total across DNA and Krebs combined.

RDKit exists and does all of the above properly, but it is Python/C++ and
integrating it into a Godot export targeting an offline thumb-drive demo
would be its own project with its own failure modes. Hand-rolling a
deliberately tiny version is correct here **provided the tininess is
defended in writing**, which is what this section is for.

---

## First milestone: DNA, not Krebs

**Decided.** The first working version of this subsystem is built into DNA
replication.

**Why:**
- DNA replication already ships and the zoom system already exists, so
  this adds a layer to working infrastructure rather than building two
  unproven things simultaneously.
- The chemistry is minimal: one repeating unit (nucleotide), one reaction
  operator (phosphodiester bond formation), one ring to lay out (ribose).
  That is the smallest honest test of the two load-bearing claims —
  deterministic stable layout, and one topology rendering at multiple zoom
  levels.
- Krebs then inherits a proven subsystem instead of inventing one
  mid-spike, exactly as the ATP cofactor pass did for the glyph vocabulary.
- Side effect worth having: it deepens the already-shipped module, which
  is a better demo and crowdfunding asset than a half-built Krebs.

**The cost, recorded honestly:** Krebs is the flagship and the PIPE
narrative; DNA replication is already demonstrated. And the
graph-isomorphism wraparound test — the strongest technical claim this doc
produces — is a *Krebs* question that DNA structurally cannot test, the
same way linear replication cannot test the cycle seam.

### Scope fence on the milestone

Build ribose + the phosphodiester operator + skeletal rendering at deep
zoom. Stop. Take the result to Krebs.

**If it drifts into base stacking, major/minor groove, or sugar pucker
variants, it has become a DNA polish pass and the sequencing argument no
longer holds.** That drift is the specific failure mode to watch for, and
noticing it is a reason to stop, not to renegotiate.

---

## Hydrogens

**Decided: deepest zoom level only.** Skeletal notation omits them;
ball-and-stick does not. Including them roughly doubles atom count, and it
determines whether "reduction" is visible as an actual hydride moving or
only as a label change on NAD⁺ — which is the reason to show them at all,
at the one zoom level where the mechanism is the subject.

---

## Ground-truth corrections — `nitrogen_base.gd`, `zoom_manager.gd`

Read after the first draft. Each entry is an assumption in the body above
that the real file contradicted.

### 1. There is no zoom level 4, and its absence was a decision

`zoom_manager.gd`'s banner: level 1 (whole strand) plus levels 2 and 3, and
**"Level 4 was removed entirely (design decision: two zoom-in steps plus
level 1 is enough; no target needs a fourth level)."**

This doc's "First milestone" section leans on "the zoom system already
exists" as a reason DNA-first is cheap. That is now qualified. What exists
is a three-level **target-framing** system whose deepest level is
"exclusively focused" on an enzyme — not a magnification ladder that
molecular structure can simply extend. Deep molecular zoom either reverses
a deliberate design decision, or does not live in the level system at all.

**The DNA-first argument survives but is weaker than written.** It still
holds on chemistry simplicity, on deepening a shipped module, and on
Krebs inheriting a proven subsystem. It no longer holds on "the zoom
infrastructure is already there."

### 2. Free camera mode is the likelier home for molecular zoom

`_free_camera_mode` is a fully independent camera state: while active,
neither `_apply_live_frame()` nor `_frame_strand()` touch the camera at
all, `_process()` early-returns, and zoom is continuous — bounded below by
`_compute_free_camera_min_zoom()` (the whole-track fit, doubling as
"Level 0") and above by `tm.zoom_free_camera_max_zoom_in`.

Continuous scroll-zoom past a threshold is a much better fit for
"structure resolves as you get closer" than a discrete fourth level would
be, and it requires reversing no prior decision. **Provisional position:
molecular render-mode switching keys off continuous zoom in free-camera
mode, not off `zoom_level`.** This also reframes open question 4 below —
the real risk is mode flapping at a continuous threshold, which needs
hysteresis, not a discrete-vs-manual choice.

### 3. `nitrogen_base.gd` is a `RigidBody2D` — the renderer must not extend it

One `RigidBody2D` per base, each with a `Label` child, permanently frozen
(`stay_frozen` defaults true and nothing sets it false). On a 300-base
sequence that is already 300 rigid bodies and 300 Controls.

If molecular zoom expanded each nucleotide into ~20 atoms by the same
pattern, that is 6,000 rigid bodies and 6,000 Labels. **Not viable.**

`ATPCycleDesign.md` already hit this and already answered it: `nitrogen_base.gd`
was judged too heavy to reuse for pooled glyphs, and `cofactor_bead.gd`
shipped as a lightweight `Node2D` copying only its visual conventions. The
molecule renderer must follow that precedent, or go further — **one
`_draw()` per molecule** rather than one node per atom, matching
`nucleotide_field.gd`'s single-node particle drawing.

This is a genuine architectural constraint the body above missed entirely.
The three-layer model survives it fine (topology has no nodes), but it
means **the render layer is immediate-mode, not a node tree** — which
should be stated as a commitment, not discovered during Growth.

### 4. Glyph counter-rotation is a real inherited obligation

Vertical mode rotates the camera −90°, and text does not rotate for free.
`get_label_counter_rotation()` is **pushed** into nodes, never read by them
— `nitrogen_base.gd` is ThemeManager-free by contract and takes it via
`set_label_rotation()`, whose load-bearing line is `pivot_offset`, not the
rotation itself.

Any atom labels inherit this. And because correction 3 pushes the renderer
toward a single `_draw()` per molecule, it inherits `nucleotide_field.gd`'s
variant specifically — per-atom transform origin, reset after each — **not**
`nitrogen_base.gd`'s. STATUS.md records these as three different fixes for
what looks like one problem; picking the wrong one produces a molecule that
spins around its own origin instead of upright labels.

Also inherited: `EnzymeLabel` under the leading clamp carries `scale.y = -1`,
and reflection conjugates rotation, so mirrored parents must pass the
negated value. Any mirrored molecular rendering has the same trap.

### 5. Two stale claims found in passing (not blocking, worth logging)

- **`_round_corners()` is still duplicated in `nitrogen_base.gd`.** Its own
  comment says so, naming four other copies. `SKILL.md` and `STATUS.md`
  describe the `procedural_shape_utils.gd` extraction as having resolved
  the five-copy duplication; this file was evidently not migrated. Since
  `round_corners()` is a pure utility rather than a behavioral constant,
  the cost is tedium, not drift — but the docs currently overstate the
  extraction's completeness.
- **`register_target()`'s doc comment still describes the `_fit_points()`
  Array path** as a live option, while `STATUS.md` records `_fit_points()`
  as dead code with no callers. One of the two is wrong; the comment is the
  likelier stale one, but this was not verified.

### What was confirmed, not contradicted

- Live tracking is recomputed fresh every frame and **never tweened** —
  explicitly called scrub-safe by construction in `_process()`, same
  principle as `helicase_x`. The claim that layout must be deterministic
  rather than iterative fits this codebase's existing discipline exactly.
- `nitrogen_base.gd` already carries `set_shape("circle" / "rounded_square")`
  as an accessibility distinction (RNA must differ from DNA by shape, not
  colour alone). A string-keyed shape swap with a real pedagogical
  justification is established precedent for render-mode selection.

---

## Ground-truth corrections — second pass

`procedural_shape_utils.gd`, `cofactor_bead.gd`, `nucleotide_field.gd`,
`polymerase_halo.gd`, `theme_manager.gd` read. `replication_manager.gd`
(3,144 lines) opened only far enough to confirm file size — still unread,
still assumption.

### 6. There is a hard rendering ceiling, and it is lower than this doc assumed

`nucleotide_field.gd` caps at `max_particles = 200`, and the comment says
why: at the 300-base ceiling, `particles_per_slot * num_slots` reached
**1,200 particles, which caused an FPS drop.** That is single-node
immediate-mode drawing — a `draw_texture_rect` plus a `draw_string` per
particle, no nodes, no physics. The cheapest rendering this project has.

So correction 3's conclusion was right and its reasoning was incomplete.
Immediate-mode is not merely *better* than per-atom nodes; **immediate-mode
itself tops out around a thousand glyphs on target hardware.** A 300-base
strand at ~20 atoms per nucleotide is ~6,000 atoms. Whole-strand atomic
rendering is not achievable by any route.

**This is fine, and it is also a design commitment.** At molecular zoom
only a few nucleotides are on screen, so the working set is naturally
small — but the cull must be **explicit and manual**. Godot culls whole
canvas items by their rect; every draw call issued inside a single
`_draw()` is issued regardless of whether it lands on screen. A molecule
renderer that draws the full strand and lets the engine sort it out will
be issuing thousands of dead draw calls per frame.

`nucleotide_field.gd` also documents the trap in the other direction: its
`_visible_world_rect()` used to derive from the live canvas transform and
had to be changed *away* from that, because a zoom-dependent boundary
compressed the field. A per-atom cull must therefore be a genuine
visibility test, not a reused roaming-bounds rect — those are two different
quantities that would look interchangeable.

### 7. The per-particle-node vs. immediate-mode choice is decided by count

The codebase already runs both, deliberately:

| File | Pattern | Count |
| --- | --- | --- |
| `polymerase_halo.gd` | `_HaloDot extends Node2D`, one node per particle | ~5, fixed pool |
| `nucleotide_field.gd` | one `_draw()`, parallel arrays | up to 200 |

Small fixed pools get real nodes; large counts get immediate mode. The
molecule layer is a large count, so immediate mode — but the criterion is
worth stating as the criterion, since a *single* molecule at deep zoom
might legitimately want nodes.

### 8. Bond rendering already exists and should be inherited wholesale

`ProceduralShapeUtils.inset_segment()` shortens a bond to run edge-to-edge
rather than centre-to-centre, paired with `Line2D.LINE_CAP_ROUND`. Its doc
comment gives the reasoning: a centre-to-centre line shows through beads at
partial alpha, crosses labels, and reads as one continuous rod across
several collinear beads rather than as distinct bonds.

**That reasoning applies verbatim to skeletal molecular structure**, which
is nothing but collinear atoms with labels. This doc's body treats bond
rendering as unbuilt; it is built, tested, and its failure mode already
documented. Inherit it, do not reinvent it.

`octagon()` is symmetric-only, and `polymerase_clamp.gd`'s asymmetric
variant was deliberately left local as "a genuinely different shape, not
more duplication to extract" — a useful precedent against this doc's
instinct toward one universal shape vocabulary.

### 9. Live-read, cached-reference: the pattern the renderer must copy

`nucleotide_field.gd` caches the `zoom_mgr` **reference** in `_ready()` but
reads `get_label_counter_rotation()` **live in `_draw()`** — because
ZoomManager is a sibling, sibling `_ready()` order follows scene-tree
order, and caching the rotation could capture a pre-orientation zero.

This is the concrete form of the "inject, don't lookup" rule for a node
that needs a per-frame value from a sibling. The molecule renderer has
exactly this shape and should copy it exactly.

`cofactor_bead.gd` also records that the ATP beads were missed in
`ATPCycleDesign.md`'s vertical-mode accounting — the design noted the glyph
text needs no translation keys ("A" and "P" are language-independent) and
then never revisited that it is still *drawn text*. **Same near-miss shape
to watch for here:** atom labels are element symbols, identical in every
language, which makes it easy to conclude they need no localization work
and thereby skip the rotation question too.

### 10. Amendment to correction 5 — the extraction did complete

More precisely than logged in the first pass: `procedural_shape_utils.gd`'s
header names its five consumers — `helicase_ring.gd`, `polymerase_clamp.gd`,
`ligase.gd`, `primase_blip.gd`, `pol1.gd`. `nitrogen_base.gd` is not among
them, and its own comment claims duplication from only four of those.

So the extraction was completed for the files it targeted; `nitrogen_base.gd`
is an **uncounted sixth copy** that both sides' comments miss. Since
`round_corners()` is a pure utility rather than a behavioral constant, the
cost is tedium, not drift — but the miss is real, and it is exactly the
"before asserting completeness, check the territory" failure the skill
records from v77.

### 11. A second stale level-4 reference

`nucleotide_field.gd`'s `_visible_world_rect()` comment refers to "level
3/4." Level 4 was removed. Two independent stale references now (this and
`register_target()`'s `_fit_points()` comment), which suggests the comment
layer generally lags the code by about one zoom-system revision — worth
distrusting comments about the zoom system specifically.

### 12. ThemeManager has room, and a naming precedent

Twenty-three groups, feature-named, with subgroups used for the zoom
system's internal divisions. "Nucleotide Field & Halo" is precedent for one
group serving two related nodes — so a single "Molecular Structure" group
covering topology-agnostic render settings is consistent with house style.
No structural obstacle here; noted only because the body assumed it
without checking.

---

## Ground-truth corrections — third pass

`replication_manager.gd` (3,144 lines) read in full — the one file the
second pass had only opened far enough to confirm size. No contradictions
found; this pass only confirms prior corrections from the other side of the
file boundary they describe.

### 13. `replication_manager.gd` confirms the node-per-object / immediate-mode split, and reinforces Model B

Every synthesized nucleotide in this file is spawned via
`_spawn_leading_base()` / `_spawn_lagging_base()`, both of which call
`sim.NewNitrogenBaseScene.instantiate()` — one full scene node per base, no
exceptions, across leading strand, lagging strand, primer placement, and
scrub rebuild alike. This is the exact call pattern correction #3 inferred
from `nitrogen_base.gd`'s own definition; reading the consumer side confirms
it rather than merely assuming it.

Conversely, the file contains **zero** `_draw()` calls, zero manual culling,
and zero particle-pool logic anywhere in its 3,144 lines — immediate-mode
rendering is entirely absent here and lives exclusively in
`nucleotide_field.gd` / `polymerase_halo.gd`. Corrections #6 and #7's
node-vs-immediate-mode boundary is drawn in exactly the right place: this
file is wholly on the node-per-object side of it.

**Model B reinforced, not just precedented.** `_leading_scrub_rebuild()` and
`_lagging_scrub_rebuild()` reconstruct fragment structure, primer-removed
state, and the telomere gap entirely fresh from `ctx` on every scrub call —
nothing here is patched incrementally or replayed from tween history. The
"derived, not stored" regent pattern this doc proposes for molecule state
(`molecule_at(step_n) = fold(reactions[0..n], seed)`) is not a novel
import — it is already this project's load-bearing scrub discipline,
applied here to fragments/primers instead of atoms/bonds.

**Data point for open question 8 (atom picking / hit-testing).** The
CAPTURE section's two-leg animation (`_capture_update_leading()` /
`_capture_update_lagging()`) — a live per-frame follow of a moving anchor
while the enzyme is still mid-glide, switching to a fixed-endpoint tween
once it arrives — is the established visual language for "this thing is
being placed into the structure." Worth reusing verbatim if a future
phosphodiester-bond-formation operator ever animates its own placement step,
though it does not resolve the open question itself (no per-atom nodes
means no free per-atom input routing either way).

---

## Open questions

_Triage status as of the render-cluster and Q3/Q5 resolution passes.
Render-cluster (`MolecularStructure_OpenQuestions_RenderClusterResolution.md`):
questions 4, 7, 8, 9 (plus new question 10, added there) are DECIDED — see
that file for the full resolution and the zoom_manager.gd-verified
hysteresis mechanics. Q3/Q5 (`MolecularStructure_OpenQuestions_Q3Q5Resolution.md`):
question 5 (operator authoring format) is fully DECIDED; question 3
(stereo from day one) is PARTIALLY DECIDED — only the DNA-milestone slice
(ribose's handedness), with the general schema-wide question still open.
Question 2 is DECIDED below. Questions 1 and 6 are **parked
indefinitely — no action needed**, not merely unresolved: 1 is explicitly
gated on the full eight-station Krebs model, which is not scheduled, and
6 is a low-value optional refactor with no user-visible gain. Nothing
remains in "standing by for resolution" as of this pass — every question
that bears on the DNA-first milestone is now decided at least at the
milestone-relevant slice._

1. **Aconitase and the anchored backbone** (above) — PARKED INDEFINITELY,
   no action needed. Carried as a named exception; only becomes relevant
   at the full eight-station Krebs model, which is not scheduled. Not a
   blocker for anything currently planned.
2. **Layout authoring format — DECIDED.** Canonical vertex positions for
   each template ring (starting with the furanose/ribose ring) are
   **derived from published bond geometry** — idealized bond
   lengths/angles computed programmatically, not hand-placed in an editor.
   This is the doc's own Nucleation-section argument applied to itself:
   "hand-placing those vertices would be *worse* than deriving them"
   (problem 2) rules out hand-authoring for the same reason it motivated
   this whole subsystem. Substituents (5'-CH₂-phosphate, 3'-OH) then hang
   off the derived ring at known positions/angles, per the existing Layout
   section's stability rule. Scale is relative (bond-length *ratios*
   preserved), not literal Ångströms — the absolute unit matches whatever
   visual scale `nucleotide_slot_spacing` already establishes.

   **Superseded, real numbers now in hand — no longer a generic
   placeholder.** The earlier version of this question estimated "~109.5°
   tetrahedral angles" as a stand-in. Verified against Gelbin et al.
   (1996), *Geometric Parameters in Nucleic Acids: Sugar and Phosphate
   Constituents*, J. Am. Chem. Soc. 118, 519–529 (statistical survey,
   ~127 crystal structures) — the standard reference for this geometry,
   not a generic chemistry approximation. Real deoxyribose values used:
   C5'-C4'-C3' bond angle averages 114.7°; C4'-C3'-O3' averages 110.3°.
   These two angles are measurably different from each other (not a
   symmetric pair), which is the direct evidence behind the new Layout
   rule subsection above.

   **The "Inkscape in the pipeline" framing was moot, not decided against.**
   The SVG-authoring pipeline (`polymerase_shape.gd`,
   `svg_to_polymerase_gd.py`) is already retired-in-place project-wide, per
   `PolymeraseDesign.md`'s As-Built note — superseded by
   `procedural_shape_utils.gd`'s shared procedural primitives
   (octagon/round_corners/inset_segment) for enzyme silhouettes. A
   bond-angle deriver for molecule rings is the same
   "procedural-over-authored" precedent this project already completed,
   applied to a different geometry domain (idealized chemistry instead of
   idealized enzyme shape) — not a fresh decision to keep or drop Inkscape,
   which was never actually a live option here.

   **Still genuinely open:** whether the ring template carries stereo
   information from the start (see question 3 below) — flat bond-angle
   derivation in 2D doesn't by itself answer that, and it's exactly where
   aconitase's prochiral case (question 1) may force the issue.
3. **Does the topology layer need stereo from day one** — PARTIALLY
   DECIDED, see `MolecularStructure_OpenQuestions_Q3Q5Resolution.md`
   (question 3 there). Milestone slice: D-ribose's handedness is a
   **hardcoded constant baked into the ribose deriver's own vertex-walk
   order**, not a topology-schema data field — no R/S flag, no
   `chirality` parameter. Every nucleotide is derived by the same
   convention, which is what guarantees consistent 5'→3' directionality
   across a whole strand (a parameter could desync per-call; a hardcoded
   constant can't). Requires a flagged code comment at the hardcoded spot
   stating it's D-ribose-only, same treatment as the aconitase exception.

   **The GENERAL question stays open, deliberately** — does the topology
   schema need a stereo field across the whole ~40-molecule cast? Still
   gated on aconitase (question 1, parked). Sharper trigger condition than
   before: not "is a molecule chiral" (most of Krebs is chiral-but-
   consistently-drawn, same hardcoded pattern as ribose) but "does an
   operator need to treat two topologically-identical atoms as different"
   — which is what aconitase's citrate arms actually require. Fumarase's
   fumarate→L-malate hydration is flagged as a *predicted* (unconfirmed)
   second consumer of whatever schema aconitase eventually forces.
4. **Where does render-mode selection live** — DECIDED, see
   `MolecularStructure_OpenQuestions_RenderClusterResolution.md`
   (question 4 there): a continuous zoom-scalar threshold inside
   free-camera mode, with a verified-against-`zoom_manager.gd` hysteresis
   band (enter/exit thresholds).
7. **Does molecular zoom belong inside free-camera mode at all?** —
   DECIDED, see `MolecularStructure_OpenQuestions_RenderClusterResolution.md`
   (question 7 there): yes, no special-casing of `current_target_id`.
8. **Immediate-mode rendering vs. atom picking.** — DECIDED for this
   milestone, see `MolecularStructure_OpenQuestions_RenderClusterResolution.md`
   (question 8 there): immediate-mode, atom picking out of scope, but
   per-atom layout positions must be written to a stored array as
   cheap insurance for a future picking pass.
9. **What is the culling unit?** — DECIDED for this milestone, see
   `MolecularStructure_OpenQuestions_RenderClusterResolution.md`
   (question 9 there): per-molecule bounding-box only, per-atom fallback
   explicitly deferred (flagged at the cull site, not silently dropped).
5. **How is an operator authored?** — DECIDED, see
   `MolecularStructure_OpenQuestions_Q3Q5Resolution.md` (question 5
   there). Fixed interface regardless of authoring method: a diff of four
   arrays — `bonds_broken`, `bonds_formed`, `atoms_leaving`,
   `atoms_arriving` — plus a `teaching_text` gloss, consumed by one shared
   fold-engine function. Atom references **must use role tags**
   ("the growing chain's 3'-oxygen"), never raw indices, since topology is
   derived fresh every fold (Model B — nothing cached across steps).

   **Option A ships now**: each operator authored as a small `Resource`
   or dictionary — static data, Inspector-editable, no code. Correct fit
   for the DNA milestone's one operator (phosphodiester bond formation),
   which has no conditional logic. Verified precedent in this codebase:
   `dna_sequence_resource.gd` is the **only** `class_name ... extends
   Resource` anywhere in `scripts/` — "single source of truth for all
   sequence data," `@export var sequence: Array[String]` — exactly the
   Inspector-editable, no-logic-beyond-accessors shape Option A proposes,
   confirmed rather than assumed.

   **Option B held in reserve, not built**: same four-array output, but
   from a per-operator GDScript function instead of static data — the
   escape hatch for when aconitase (question 1) forces an operator to
   choose between two topologically-identical atoms, which static data
   can't express. A generic SMARTS-like pattern-matching DSL is ruled out
   outright — same category the doc's Hard Scope Boundary already
   excludes (general valence solving / aromaticity perception).
6. **Does the ATP bead-chain glyph family migrate onto this layer, or stay
   as-is?** — PARKED INDEFINITELY, no action needed. The `[A]─(P)─(P)─(P)`
   vocabulary is already a hand-rolled bond table with the abstraction not
   pulled out. Migrating it would validate the model against shipped code;
   it would also be a refactor of working visuals for no user-visible
   gain. Not obviously worth it, and nothing depends on it.
10. **`pairing_direction`-based substituent flipping (Bug J/L, in
    `MolecularStructure_BasePairExpansion.md`) is confirmed NOT chemically
    accurate — carried as a named exception, not an open toss-up.** Real
    measured geometry (Gelbin et al., 1996, cited above) ties C5'/O3''s
    direction to the real previous/next residue on the *same* strand,
    governed by independent bond angles (114.7° / 110.3°) with no
    relationship to which base is paired across the helix. The shipped
    fix derives direction from `pairing_direction` — the cross-strand
    H-bond vector — which is the wrong reference by construction, not an
    approximation of the right one. The two only agree visually for this
    milestone's specific antiparallel-duplex topology, coincidentally, not
    because the code is built to reflect real same-strand connectivity.

    **What's actually open is narrower: whether to spend the effort
    replacing it now.** The shipped heuristic passes its own verification
    (screenshots, dot products) for every symptom it was built against,
    and nothing currently visible depends on the difference. Not fixing
    it yet is a legitimate call — but only if this exception stays named
    and visible, the same treatment as the aconitase exception, rather
    than being quietly assumed correct because it looks right on screen.
    Krebs will need its own literature-grounded direction derivation
    regardless (it has no "previous/next residue" to borrow this
    mechanism from), so revisiting this is not purely a DNA cleanup item
    whenever it does happen.

---

## Scope reminder

Nothing in this document is committed to a timeline. The only thing
approved is the *direction* and the first milestone's shape. This is a
Lattice doc: it exists to be discussed and explicitly approved before any
code is written, and to be contradicted in writing by an As-Built section
once real files are read.

---

## Self-paired template state is a first-class render state, not a transient one

**Correction, added after this framing crept into conversation and needed to
be stopped rather than left implicit.** The self-paired template case (both
template strands still hydrogen-bonded to each other, before the polymerase
has caught up and built either strand's real copy) has repeatedly been
described in discussion as "temporary," "transient," or "a brief pre-fork
window" — language used to justify deprioritizing its correctness relative
to leading/lagging's fully-synthesized geometry. That framing is wrong and
is retired as of this entry.

**Why it's wrong, on the record:** this is the state a teacher or student
sees when panning the fully-assembled DNA with no enzyme active — no
helicase, no polymerase, nothing moving to compete for attention. That is
not an edge case to be tolerated until something better replaces it; it is
the cleanest available teaching view of what antiparallel structure and
5'→3' directionality actually mean at the atom level, precisely because
nothing else is happening on screen. A rendering defect here is not lower
priority than the same defect on leading/lagging — if anything it is
encountered MORE, since a student is free to sit in this state indefinitely,
while the fork keeps moving past any given leading/lagging residue.

**What follows from this:** self-paired template geometry (ring rotation,
chain placement, O4' proximity, H-bond rendering) must be held to the same
correctness bar as leading/lagging's fixed-sign path — chemically accurate
distances and directions, not merely "passes its own clearance metric" or
"good enough for a state nobody lingers on." Every open item in
`MolecularStructure_BasePairExpansion.md`'s Bug V/W thread (the rotation
search's constraint conflicts, the O4'-proximity failure, the
determinism/flicker bug) is evaluated against that bar, not against a
lower one implied by "it resolves once the fork arrives." It does resolve —
but that is not a reason to under-invest in it now.

**Naming going forward:** refer to this as "the self-paired template state"
or "the pre-fork state" when precision about *when* it occurs is useful —
those are neutral, descriptive terms. Do not use "temporary," "transient,"
or language implying it is lower-priority than any other named render
state in this document.
