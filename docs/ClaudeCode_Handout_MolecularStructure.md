# Handout — Molecular Structure Subsystem, DNA-first Milestone

_For Claude Code. This is a Growth-phase kickoff on a Lattice-approved design
— see the Crystal Building Method in `docs/SKILL.md` (the only current copy;
a stale root-level `SKILL.md` duplicate has since been removed). The design
has been discussed and the direction + first milestone's shape are approved.
Nothing below authorizes drifting past the scope fence without stopping to
check back in._

_**Updated**: the Lattice phase is now fully closed for this milestone. All
six files originally flagged as unread have been read (see
`MolecularStructureDesign.md`'s ground-truth corrections, three passes,
#1–13), and every open question that bears on the DNA-first milestone has
been resolved — see "Open questions, resolved" below. This is a
documentation-only update; no implementation code has been written yet._

---

## Read first, in this order

1. `docs/SKILL.md` — GDScript hard rules, engine traps, edit protocol,
   ground-truth discipline, the Crystal Building Method itself. Non-
   negotiable baseline for touching this codebase at all.
2. `MolecularStructureDesign.md` — the full design. **Read it whole, not the
   summary below.** This handout is a pointer into it, not a replacement for
   it. Includes three ground-truth-correction passes and a fully resolved
   Open Questions section.
3. `COMPLEXITY_MODEL.md` and `SHARED_BASE_SEAM.md` — `MolecularStructureDesign.md`
   is a cross-cutting subsystem doc and a peer of both, not a companion to
   one module.
4. The three resolution docs, all folded into `MolecularStructureDesign.md`'s
   Open Questions section but worth reading directly for full reasoning:
   - `MolecularStructure_OpenQuestions_RenderClusterResolution.md` —
     render-mode selection, free-camera integration, atom-picking scope,
     culling unit, and transition mechanics (questions 4, 7, 8, 9, plus new
     question 10).
   - `MolecularStructure_OpenQuestions_Q3Q5Resolution.md` — the
     milestone-relevant slice of stereo-in-topology (question 3) and the
     full operator-authoring format decision (question 5).

## Ground-truth grounding: complete, not partial

All six files originally flagged as unread are now read and reconciled —
`procedural_shape_utils.gd`, `cofactor_bead.gd`, `nucleotide_field.gd`,
`polymerase_halo.gd`, `theme_manager.gd`, and `replication_manager.gd`
(3,144 lines, read in full). No further ground-truth reading is required
before starting implementation. If something in the actual code still
contradicts the design doc once you're writing against it, the discipline
is unchanged: **add a new numbered correction, don't silently edit the
body.**

Two things the doc already flags as likely to bite when building the
renderer:

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

## Open questions, resolved

Everything below is DECIDED (or decided at the milestone-relevant slice) —
see `MolecularStructureDesign.md`'s Open Questions section for the status
tags and the two resolution docs for full reasoning. Build against these,
don't re-derive them:

- **Ring geometry (Q2)**: derived from published bond geometry (idealized
  bond lengths/angles), not hand-authored, not via Inkscape (that pipeline
  is retired-in-place project-wide, superseded by `procedural_shape_utils.gd`).
- **Ribose handedness (Q3, milestone slice)**: a hardcoded constant in the
  ribose deriver's own vertex-walk order — not topology-schema data, no
  `chirality` parameter. Requires a flagged code comment stating it's
  D-ribose-only. The general schema-wide stereo question stays open,
  correctly, pending aconitase — not this milestone's problem.
- **Operator authoring format (Q5)**: a fixed four-array diff —
  `bonds_broken`, `bonds_formed`, `atoms_leaving`, `atoms_arriving` — plus
  `teaching_text`, consumed by one shared fold-engine function. Atom
  references **must use role tags**, never raw indices. Author the
  phosphodiester operator as **Option A**: static `Resource`/dictionary
  data, Inspector-editable, no code — precedented by `dna_sequence_resource.gd`,
  the only `Resource` subclass in `scripts/`.
- **Render-mode selection (Q4/Q7)**: a continuous zoom-scalar threshold
  inside free-camera mode (not a manual toggle, not a new camera state).
  Requires a verified hysteresis band — `molecular_zoom_enter_threshold` >
  `molecular_zoom_exit_threshold`, both Inspector-tunable — confirmed
  against `zoom_manager.gd`: zooming in **increases** the numeric `zoom`
  scalar, zooming out decreases it toward a floor.
- **Atom picking (Q8)**: out of scope for this milestone. Cheap-insurance
  requirement: per-atom layout positions must be written into a stored
  array (`{position, element, atom_id}`) that `_draw()` iterates, not left
  as local draw-call variables — so a future picking pass is "hit-test the
  same array," not a rebuild.
- **Culling unit (Q9)**: per-molecule bounding-box only for this milestone;
  no per-atom fallback. Leave a flagged comment at the cull site citing the
  ~1,200-glyph ceiling and the deferred fallback tier.
- **Render-mode transition (Q10, new)**: layout computation runs every
  frame regardless of active render mode (only draw calls are gated) to
  avoid a first-crossing hitch. Ship a hard cut first, no crossfade/blur —
  defer that to CQA. If added later, it must be a pure function of the live
  zoom scalar (never a timed state machine) and must reuse Q4's same two
  hysteresis thresholds.

## The task — scope fence

**Build:** ribose (the furanose ring) + the phosphodiester-bond operator +
skeletal rendering, at the deepest zoom level only (per Q4/Q7 above: inside
free-camera mode, past the enter threshold), inside DNA replication.

**Stop there.** Do not drift into base stacking, major/minor groove, or sugar
pucker variants — that would silently convert this into a DNA polish pass,
which invalidates the doc's own sequencing argument for doing DNA before
Krebs (see "First milestone: DNA, not Krebs" in the design doc). If you
notice the work pulling in that direction, stop and flag it rather than
finishing it.

Out of scope, unconditionally, per the design doc's "Hard scope boundary":
SMILES/InChI parsing, general valence solving or aromaticity perception, 3D
coordinates/conformers/energy minimization, reaction prediction, any
molecule not on the authored cast list. Also out of scope for this
milestone specifically (per the resolved questions above): atom picking/
hit-testing, per-atom culling, any render-mode transition treatment beyond
a hard cut.

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
  applied to chemistry. Reinforced, not just precedented, by
  `replication_manager.gd`'s own scrub-rebuild discipline (correction #13).
- **Stability, not just determinism.** The furanose ring carries canonical
  vertex positions; 5'-CH₂-phosphate and 3'-OH hang off it as substituents at
  known ring positions. The backbone must not visibly shift when something
  attached to it changes — that's what makes 5'→3' directionality fall out
  of the geometry instead of being an arrow drawn on top.
- **Hydrogens: deepest zoom level only**, per the design doc's decision.
- **Immediate-mode rendering, not per-atom nodes**, for the molecule layer —
  this is a large-count case (`nucleotide_field.gd`'s pattern), not a small
  fixed pool (`polymerase_halo.gd`'s pattern). See the design doc's
  correction #7 for the criterion, and correction #13 for confirmation from
  `replication_manager.gd`'s side of the boundary (zero `_draw()` calls
  there — it's wholly node-per-object).
- **Manual culling is mandatory**, not optional — Godot culls whole canvas
  items by rect, but every draw call inside one `_draw()` fires regardless
  of on-screen visibility. See correction #6 for the specifics and the trap
  `nucleotide_field.gd` already hit and fixed once. Per-molecule bounding-box
  only for this milestone (Q9, above).
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
  blind. Same applies to the two hysteresis thresholds (Q4) — Inspector-
  tunable placeholders, not final numbers.

## Done means

Mechanically correct and scrub-safe, not visually tuned. When you stop —
whether at the scope fence or because something needs a decision — write an
As-Built addendum to `MolecularStructureDesign.md` recording what actually
got built and where it diverged from the plan, appended rather than
overwriting the Lattice-phase body (same convention as `ATPCycleDesign.md`'s
As-Built sections). Update `STATUS.md` and `CHANGELOG.md` per their existing
ownership split (`CHANGELOG.md` = version history, `STATUS.md` = current
state and why).
