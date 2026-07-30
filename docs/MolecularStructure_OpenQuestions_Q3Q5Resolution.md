MolSim — Molecular Structure Design: Open Questions
Resolution pass — Q3 (narrow slice) and Q5
=====================================================================
This resolves the milestone-blocking half of Q3 and the whole of Q5.
Q1 (aconitase) and Q6 (ATP bead migration) are untouched. The general
half of Q3 (does topology need a schema-wide stereo field across the
full ~40-molecule cast) is also untouched — still parked on Q1 forcing
the issue at the full Krebs build.


3. DOES THE TOPOLOGY LAYER NEED STEREO FROM DAY ONE?  [PARTIALLY DECIDED]
---------------------------------------------------------------------------------
Narrow slice decided: D-ribose's handedness is a hardcoded constant
baked into the ribose deriver's own vertex-walk order — not a data
field anywhere in the topology schema. No R/S flag, no `chirality`
parameter passed in. The deriver always produces the same enantiomer.

Reasoning: this is a purer form of "derived, not stored" than a passed
constant would be — a hardcoded convention inside the function body
can't desync or be silently overridden per-call the way a parameter
could. Every nucleotide, every fold, every scrub calls the same deriver
with the same fixed convention, which is what makes 5'->3'
directionality fall out of the geometry consistently across an entire
strand (the payoff Q2's "geometry, not an arrow drawn on top" decision
depends on) — that consistency only holds if every ring is drawn with
identical handedness, which a hardcoded constant guarantees by
construction and a parameter would only guarantee by discipline.

Does not interact with Q5: the phosphodiester operator's role-tagged
atom references are chirality-agnostic, so this decision and Q5's are
independent and don't need to agree with each other.

Required at the point of implementation: a code comment at the
hardcoded convention itself, stating plainly that it is D-ribose only,
deliberately fixed, and that any future need to mirror a different
handedness (a non-natural nucleotide analog, e.g.) means promoting this
from a constant to real topology data — pointing straight back at the
still-open general half of this question. Same treatment as the
aconitase exception and the culling ceiling comment: a flagged gap, not
a silent one.

Still fully open, deliberately: whether the topology schema needs a
GENERAL stereo field across the whole ~40-molecule/20-operator cast.
Trigger condition for when this actually gets forced (established in
discussion, worth recording here): not "is a molecule chiral" — most of
Krebs' chiral intermediates are chiral the same way ribose is, always
drawn the same handed way, and ride this same hardcoded-constant
pattern with zero schema change. The real trigger is "does an operator
need to treat two atoms as different when the flat topology says
they're identical" — which is what aconitase's citrate arms actually
require and a bond-graph literally cannot express without added data.
Predicted (NOT confirmed against the literature, verify when that
station is actually built) second consumer of whatever schema aconitase
forces: fumarase's stereospecific hydration of fumarate to L-malate
looks like the same class of problem. If confirmed, whatever gets built
for aconitase should be built expecting a second consumer, not shipped
as a one-off special case.


5. HOW IS AN OPERATOR AUTHORED?  [DECIDED]
------------------------------------------------
Decision: pure declarative data (Option A of three considered), with a
named escape hatch to a procedural variant (Option B) held in reserve,
not built yet.

Fixed interface, applies regardless of which option is producing it: a
reaction operator is a diff of exactly four arrays —
`bonds_broken`, `bonds_formed`, `atoms_leaving`, `atoms_arriving` —
plus a `teaching_text` field carrying the plain-English gloss. Atom
references inside the diff MUST use ROLE tags, never raw indices or
positions (e.g. "the growing chain's 3'-oxygen," "the incoming
nucleotide's alpha-phosphate") — this is non-negotiable regardless of
authoring option, because topology is derived fresh every fold (Model
B, nothing cached across steps) and an index-based reference would
silently break the moment the same operator is applied to a different
nucleotide than the one it was authored against. A single shared FOLD
ENGINE (one function, not per-operator code) consumes any operator's
four arrays and produces the next topology — same shared-seam pattern
already used for enzyme spawning, applied to chemistry instead of
geometry.

Option A (decided, ship now): each operator is a small Resource or
dictionary, static data, Inspector-editable, no code. Strongest version
of the doc's "the operator IS the pedagogy" claim — the Inspector view
of the resource literally is the reaction equation. Correct fit for the
DNA milestone's one operator (phosphodiester bond formation), which has
no conditional logic — role-tagged atoms in, role-tagged atoms out,
nothing to branch on.

Worked example (phosphodiester bond formation):
  bonds_broken:  [(incoming.alpha_P, incoming.beta_P)]
  bonds_formed:  [(chain.o3_prime, incoming.alpha_P)]
  atoms_leaving: [incoming.beta_P, incoming.gamma_P, ...]   (-> PPi)
  teaching_text: "The 3'-OH attacks the alpha-phosphate; pyrophosphate
                  leaves."

Option B (named, not built): same four-array output shape, but
generated by a per-operator GDScript function instead of static data —
`func phosphodiester_operator(topology) -> OperatorDiff`. The
authoring surface becomes procedural (so conditionals are trivial to
express) while the interface the fold engine consumes stays identical
to Option A's. This is the explicit escape hatch for when aconitase
(Q1) forces an operator to choose between two topologically-identical
atoms — something static data cannot express. Not needed before that.

Ruled out outright (not just deprioritized): a generic pattern-matching
DSL (SMARTS-like). Same category the doc's own Hard Scope Boundary
already excludes — general valence solving / aromaticity perception —
solving a much harder, more general problem than a ~20-operator
authored cast actually has.

Why Option A now rather than Option B now: building Option B's
flexibility before it's needed would be solving Q1's problem (Krebs-
only, explicitly out of scope for this milestone) ahead of the DNA
milestone that doesn't require it — same "complexity layers build
upward, not sideways" discipline already applied to the culling
decision. What's actually locked in now, regardless of which option is
active at a given moment, is the four-array shape itself — so Option B
arriving later is a new PRODUCER of an existing interface, not a second
incompatible operator system.

=====================================================================
Status after this pass: Q5 is fully decided and buildable — the DNA
milestone's one operator (phosphodiester bond formation) can be
authored as Option A data against the fixed four-array interface. Q3's
milestone-relevant slice (ribose's hardcoded handedness) is decided;
its general schema-wide question remains open, correctly, pending
aconitase.
