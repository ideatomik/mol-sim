# Atom-Tier Structural Work — Design (pre-implementation)

_Lattice-phase doc per the Crystal Building Method. Written the evening of
the template-DNA self-pairing fix (see `MolecularStructureDesign.md`'s
"How self-paired rendering was reconstructed" entry, 2026-08-06), as a
same-session handoff — **not grounded against source**. Nothing in
`molecule_structure_renderer.gd`, `replication_manager.gd`,
`nitrogen_base_deriver.gd`, `ribose_deriver.gd`, `simulation.gd`, or any
Okazaki-maturation enzyme file (`ligase.gd`, `primase_blip.gd`, `pol1.gd`)
was read while drafting this. Treat every claim below about "what exists"
as inherited from prior design docs and session summaries, not verified.
**First task in tomorrow's session is grounding this doc, not implementing
off it.**_

---

## Nucleation — two related problems, one shared root

1. **A boundary bug**: the first (leftmost) base pair on the template DNA
   strand was observed unpaired in the main project — not misrendered, not
   overlapping, simply not participating in pairing at all.
2. **A missing tier**: Okazaki fragment maturation (the nick/primer/Pol I/
   ligase relay) is fully built and shipped at the bead-glyph tier
   (`OkazakiMaturationDesign.md`, "DONE" per `STATUS.md`'s roadmap) but was
   never extended to the atom-level (molecular) renderer. That renderer was
   built and bug-fixed entirely against a simpler mental model: leading/
   lagging/template strands with continuous backbones, no fragment
   boundaries, no nicks, and no ribonucleotide/deoxyribonucleotide
   distinction.

These are scoped together (not as two separate docs) because (2) cannot be
built without solving a piece of (3)-adjacent territory first: Pol I's
atom-level identity (per `OkazakiMaturationDesign.md`) is specifically
"primer-colored bases disappearing, DNA-colored bases appearing" — the
renderer needs a real ribonucleotide topology to animate that transition
at all, not just a differently-colored DNA base standing in for one.

Item (1) is scoped as a standalone bug-fix task, not a Lattice item — it's
a boundary-condition defect, not new design surface. It's listed first
because it's likely fast to diagnose and should not block on the design
work below.

---

## Task A — first-pair boundary bug (diagnostic, not design)

**Not the same bug as the recently-fixed self-paired reference-frame
issue.** That fix governed *how already-paired residues get their
geometry* (rotation/reflection). This is a *pairing-decision* boundary
condition — the leftmost residue apparently never gets paired at all,
which is upstream of any geometry code.

Candidate root-cause territory, ranked by how directly the prior session's
bug list (`MolecularStructure_BasePairExpansion.md`, Bugs P/Q) points at
it — **all three below already have a documented history of exactly this
kind of off-by-one/boundary failure in this file**, so start here before
looking elsewhere:

- `_pair_for_slot()` (`molecule_structure_renderer.gd:~625`) — Bug Q's fix
  made this check the synthesized complementary strand before falling back
  to template-template pairing. Worth checking whether slot index 0
  specifically hits an edge case in that lookup (e.g. a `-1`/`i-1` neighbor
  reference that's valid for every slot except the first).
- `_rebuild_layout()`'s `pairing_direction` computation
  (`molecule_structure_renderer.gd:~407-409`) — feeds directly off
  `_pair_for_slot()`'s result; confirm the boundary residue is reaching
  this function with a real (non-empty) partner string at all, or whether
  it's arriving pre-failed.
- `PARTNER_STRAND` (`molecule_structure_renderer.gd:123-126`) — a static
  lookup table with no notion of sequence position; unlikely culprit on
  its own, but worth ruling out if the first two don't explain it.

**Diagnostic protocol** (per this project's ground-truth discipline — dump
must exercise the actual boundary, not just confirm the table above):

1. Fresh F9 dump, pre-play, sequence loaded, before any scrub — capture
   slot 0's `PAIR`/`pairing_direction`/`anchor_alignment_dot` entries
   specifically (not just the aggregate "N paired" count, which the Bug Q
   verification used and could hide a single-slot exception).
2. Confirm whether the same defect exists at the *rightmost* slot
   (`num_slots - 1`) or is genuinely left-only — this determines whether
   the fix is a general "any missing neighbor" fallback (matching the
   direction-aware fix already used for Bug T's chain-direction fallback)
   or something specific to index 0.
3. Screenshot cross-check at atom zoom, same load state as the dump, to
   confirm the dump is reading what's actually on screen (per the Bug
   G/Q "diagnostic silently drifts from the renderer's real behavior"
   trap this project has hit twice already).

---

## Task B — atom-level Okazaki maturation + RNA primer rendering (design)

### Scope fence

In scope: giving the molecular renderer enough topology and layout
awareness to render (a) a real nick/gap in the phosphodiester backbone
between adjacent Okazaki fragments, (b) a ribonucleotide primer residue
that is visually and topologically distinct from a DNA residue, and (c)
some atom-tier treatment of Pol I and ligase passing over that region —
even if the treatment is "these enzymes don't get bespoke atom-tier
visuals; the molecular renderer just reflects the bead-glyph-tier state
change (primer→DNA, nick→sealed) with a beat of delay/transition."

Out of scope for this pass: primase's own atom-tier enzyme visual (the
molecular renderer doesn't render enzymes at all today, per
`MolecularStructureDesign.md`'s three-layer model — enzymes are a
different rendering problem, procedural silhouettes, not derived
topology). Extending enzyme rendering itself into the molecular tier is a
separate, larger doc if it's ever wanted.

### Sub-problem 1 — ribonucleotide topology (uracil, 2'-OH)

Per `OkazakiMaturationDesign.md`, RNA/DNA distinction today is a
**rendering-layer substitution only** at the bead-glyph tier —
`dna_sequence.get_base()` never actually emits uracil; primase's halo
swaps in `A/U/C/G` display letters and RNA tinting purely for the bead
glyph. The molecular renderer, which derives real atom-level topology per
residue, has no equivalent hook — it doesn't know a slot's "real" base
identity is thymine-shaped-as-uracil versus deoxyribose-versus-ribose.

Two real geometry differences, not just a color swap, need actual
representation if the molecular tier is going to show a primer honestly:

- **Uracil vs. thymine**: uracil lacks thymine's C5 methyl group. This is
  a `nitrogen_base_deriver.gd` topology change (one fewer exocyclic atom
  on the pyrimidine ring for primer residues), not a layout/rendering
  change.
- **Ribose vs. deoxyribose**: primer residues need a real 2'-OH on the
  ribose ring; DNA residues correctly have none today. This is a
  `ribose_deriver.gd` topology change — an added exocyclic oxygen at C2',
  with its own derived direction (per the Layout rule already codified in
  `MolecularStructureDesign.md`: "each branch's direction must be derived
  independently... never a single shared direction... applied to more
  than one substituent"). The 2'-OH must not reuse the 3'-OH's or the
  base-attachment substituent's direction-derivation logic wholesale — new
  branch, grounded in its own real reference geometry (Gelbin et al. 1996
  again likely the right source for the bond angle).

**Open question, not decided**: does topology carry an explicit
`is_rna: bool` (or `sugar_type` / `base_is_uracil` flags) per residue at
the point where the molecular renderer requests a residue's topology, or
does it derive RNA-ness live from the same per-slot state the bead-glyph
tier already reads (`_is_still_primer()`, keyed off shape/color of
`lagging_synthesized_bases[i]`, per `MolecularStructure_BasePairExpansion.md`'s
correction to the original four-flag primer-state proposal)? The latter
keeps a single source of truth and matches this project's "derive, don't
store" principle; the former is more explicit but risks the two tiers'
primer-identity logic silently diverging the way `_pair_for_slot()` and
`_dump_pairing()` already have once (Bug Q). **Recommend deriving live
from the same per-slot state, not a new stored flag**, pending
confirmation this doesn't hit a real performance or architecture wall once
someone's actually looking at the code.

### Sub-problem 2 — the nick itself (backbone gap rendering)

At the bead-glyph tier, an unsealed nick is governed by `ligase_enabled`
and rendered as a literal line-break in the backbone `Line2D`, with 5'/3'
end markers. The molecular renderer's equivalent would be: no bond drawn
between one residue's O3' and the next fragment's alpha-phosphate, until
`sealed` flips true for that boundary.

This is likely the cheapest part of this whole task — if the molecular
renderer already derives bonds by walking `chain.<suffix>` roles per
residue (per `molecule_topology.gd`'s existing role convention), a nick is
just "don't draw the inter-residue bond for this specific pair, and don't
let `derive_substituents()`'s clearance search treat the next residue as a
same-strand neighbor for direction purposes" — the same kind of
real-vs-fallback distinction already established for strand-boundary
residues (Bug T).

**Open question**: does the *visual gap* (empty space) need to be wider
than the normal inter-residue spacing to read clearly as a break at atom
zoom, or does simply omitting the bond line read clearly enough on its
own given the atoms are already discrete circles? Recommend deciding this
with a live screenshot rather than guessing — cheap to try both.

### Sub-problem 3 — Pol I / ligase atom-tier treatment

Given the out-of-scope note above (no enzyme silhouettes at molecular
zoom), the realistic options are:

- **(a) State-reflection only.** The molecular renderer just reads
  `primer_removed` / `sealed` per fragment (already-shipped fragment-dict
  fields, per `OkazakiMaturationDesign.md`'s data model) and shows the
  post-state instantly once the bead-glyph tier's enzyme has finished —
  no atom-tier animation of the transition itself.
- **(b) A minimal transition cue.** Base color/label briefly flags
  "was primer, now DNA" for one beat when scrubbing/playing past the
  transition point, without a full enzyme visual — closer in spirit to
  how the molecular tier already treats other state changes.

**Recommend (a) for the first pass** — matches the stated out-of-scope
boundary, and the project's existing pattern of shipping a toggle-gated
minimal version before a richer one (per "toggle-gate new mechanics
instead of deleting them"). (b) can be added later without restructuring
anything in (a).

---

## Suggested session order for tomorrow

1. Ground this doc — read `molecule_structure_renderer.gd`,
   `replication_manager.gd`'s Okazaki-relevant sections, and
   `nitrogen_base_deriver.gd`/`ribose_deriver.gd` before touching either
   task.
2. Task A (bug) first — likely fast, unblocks nothing else but is cheap
   to close out.
3. Task B, sub-problem 1 (ribonucleotide topology) before sub-problems 2/3
   — the nick and enzyme-state questions are much easier to reason about
   once a primer residue is a real, distinct topology rather than a
   DNA residue in RNA's clothing.
