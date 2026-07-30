# Handout — Molecular Structure Subsystem, DNA-first Milestone

_For Claude Code. This is a Growth-phase kickoff on a Lattice-approved design
— see the Crystal Building Method in `SKILL.md`. The design has been
discussed and the direction + first milestone's shape are approved. Nothing
below authorizes drifting past the scope fence without stopping to check
back in._

---

## Read first, in this order

1. `SKILL.md` — GDScript hard rules, engine traps, edit protocol, ground-truth
   discipline. Non-negotiable baseline for touching this codebase at all.
2. `MolecularStructureDesign.md` — the full design. **Read it whole, not the
   summary below.** This handout is a pointer into it, not a replacement for
   it.
3. `COMPLEXITY_MODEL.md` and `SHARED_BASE_SEAM.md` — `MolecularStructureDesign.md`
   is a cross-cutting subsystem doc and a peer of both, not a companion to
   one module.

## Before writing any code: extend the corrections section, don't edit the body

`MolecularStructureDesign.md` is explicit that it is **partially grounded**.
`nitrogen_base.gd` and `zoom_manager.gd` have been read; the corrections from
that pass are already in the doc's "Ground-truth corrections" section (12
entries). Six files are still unread and still assumption:

- `procedural_shape_utils.gd`
- `cofactor_bead.gd`
- `nucleotide_field.gd`
- `polymerase_halo.gd`
- `theme_manager.gd`
- `replication_manager.gd`

**Read all six before writing implementation code.** Where they contradict
the doc's body, add a numbered entry to the corrections section (continuing
from #12) rather than silently editing the body — same discipline as the
first pass. Two things the doc already flags as likely to bite here:

- `ProceduralShapeUtils.inset_segment()` + `Line2D.LINE_CAP_ROUND` already
  solve bond rendering (built for the ATP cofactor beads). Inherit it
  wholesale for skeletal bonds — collinear labeled atoms have the exact
  same "line shows through at partial alpha / crosses labels / reads as one
  rod" failure mode it was built to fix. Do not reinvent it.
- The live-read/cached-reference pattern in `nucleotide_field.gd`: cache the
  `zoom_mgr` reference in `_ready()`, but read anything per-frame
  (rotation, etc.) live in `_draw()`. Sibling `_ready()` order means a
  cached live value can capture a pre-orientation zero. Copy this pattern
  exactly for the molecule renderer.

## The task — scope fence

**Build:** ribose (the furanose ring) + the phosphodiester-bond operator +
skeletal rendering, at the deepest zoom level only, inside DNA replication.

**Stop there.** Do not drift into base stacking, major/minor groove, or sugar
pucker variants — that would silently convert this into a DNA polish pass,
which invalidates the doc's own sequencing argument for doing DNA before
Krebs (see "First milestone: DNA, not Krebs" in the design doc). If you
notice the work pulling in that direction, stop and flag it rather than
finishing it.

Out of scope, unconditionally, per the design doc's "Hard scope boundary":
SMILES/InChI parsing, general valence solving or aromaticity perception, 3D
coordinates/conformers/energy minimization, reaction prediction, any
molecule not on the authored cast list.

## Architecture rules that apply (see the design doc for the reasoning)

- **Three-layer separation is the whole architecture**: Topology (atoms,
  bonds, identity — no coordinates, ever) / Layout (a deterministic function
  from topology to 2D positions — force-directed layout is disqualified
  outright, it breaks scrub) / Render mode (bead-glyph, skeletal,
  ball-and-stick — same topology, different renderer). Keep these three
  genuinely separate; do not let render-mode logic leak into topology.
- **Derived, not stored (Model B).** The molecule at any step is computed by
  folding reaction operators over a seed topology, replayed from scratch on
  every scrub — not authored per-intermediate. This is the regent pattern
  applied to chemistry.
- **Stability, not just determinism.** The furanose ring carries canonical
  vertex positions; 5'-CH₂-phosphate and 3'-OH hang off it as substituents at
  known ring positions. The backbone must not visibly shift when something
  attached to it changes — that's what makes 5'→3' directionality fall out
  of the geometry instead of being an arrow drawn on top.
- **Hydrogens: deepest zoom level only**, per the design doc's decision.
- **Immediate-mode rendering, not per-atom nodes**, for the molecule layer —
  this is a large-count case (`nucleotide_field.gd`'s pattern), not a small
  fixed pool (`polymerase_halo.gd`'s pattern). See the design doc's
  correction #7 for the criterion.
- **Manual culling is mandatory**, not optional — Godot culls whole canvas
  items by rect, but every draw call inside one `_draw()` fires regardless
  of on-screen visibility. See correction #6 for the specifics and the trap
  `nucleotide_field.gd` already hit and fixed once.
- **Layer/occlusion state (if you touch it at this milestone) is VIEW state,
  not MODEL state.** The regent must never write it; `scrub_rebuild()` must
  never reset it. This may not be load-bearing for the DNA milestone
  specifically — flag if you think it becomes relevant.

## What you cannot verify from here — hand back for these

- **CQA (aggressive scrub testing).** The Godot MCP tools can't simulate
  input. Every scrub-safety claim — the derived layout snapping correctly
  under scrub, no flicker, no drift — is unverified until scrubbed by hand
  in the running editor.
- **Anything the design doc marks "must see on screen"** — bead scale,
  spacing, whether a rendered bond genuinely reads as terminating at the
  atom it meets rather than overshooting. Pick a reasonable starting value,
  note it as untuned, move on. Don't guess repeatedly trying to land it
  blind.

## Done means

Mechanically correct and scrub-safe, not visually tuned. When you stop —
whether at the scope fence or because something needs a decision — write an
As-Built addendum to `MolecularStructureDesign.md` recording what actually
got built and where it diverged from the plan, appended rather than
overwriting the Lattice-phase body (same convention as `ATPCycleDesign.md`'s
As-Built sections). Update `STATUS.md` and `CHANGELOG.md` per their existing
ownership split (`CHANGELOG.md` = version history, `STATUS.md` = current
state and why).

---

## One thing to confirm before this handout is used

This assumes `SKILL.md` (current version, with the Crystal Building Method
section — check the frontmatter version matches what's live, not the one
that was once found missing that section) and `MolecularStructureDesign.md`
are actually on disk in the repo Claude Code will read from, not just in
this chat's project knowledge. Land both there first.
