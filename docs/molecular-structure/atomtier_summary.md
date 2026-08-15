# Atom-Level Zoom / Molecular Structure Rendering — Current State

Briefing summary of the atom-tier rendering subsystem, written ahead of extending it to handle Okazaki fragments. Compiled by grounding directly against source (not the earlier atomtier design docs, which predate this pass and are self-flagged as ungrounded — see the Design doc map below).

## The subsystem's files

| File | Role |
|---|---|
| `scripts/molecule_structure_renderer.gd` (1219 lines) | Orchestrator — the only one with `_process()`/`_draw()`. Everything routes through here. |
| `scripts/molecule_topology.gd` | Pure chemistry identity: atoms `{id, element, formal_charge, role}` + bonds `{a, b, order}`. **No coordinates.** |
| `scripts/molecule_fold_engine.gd` | Stateless: `fold(seed, operators, step_n)` replays a diff-based operator list to build/mutate a topology. "Derived, not stored." |
| `scripts/molecule_geometry_diagnostics.gd` (564 lines) | Debug dump, triggered by F9 in-game. |
| `scripts/theme_manager.gd` | Visual tuning — the four zoom-hysteresis thresholds, plus `molecular_*` colors/sizes. |

## Data flow

`molecule_structure_renderer.gd` sits as a sibling `Node2D` to `$NucleotideField`. It gets pushed two references — `set_replication_manager()` and `set_template_source()` — never does tree lookups. Every frame, `_process()` (:450-462):

1. Recomputes `is_molecular_mode_active()` (:446) — hysteresis on `zoom_mgr.zoom.x` vs. `tm.molecular_zoom_enter/exit_threshold`, gated on free-camera mode.
2. Recomputes the nested label-detail flag (`_compute_label_full_geometry_active()`, :482-488) — element-only vs. full chemistry notation (`C3'`, `Pα`).
3. Calls `replication_mgr.get_synthesized_nucleotides()` and `template_sim.get_template_nucleotides()` — both return flat `Array[Dictionary]` of `{slot, strand, base_type, world_position}`. **No fragment or topology info in this data at all.**
4. `_rebuild_layout()` (:507) merges these into per-residue folded topologies (cached forever per `"strand:slot"` key in `_fold_cache`) and rebuilds three fresh layout arrays every frame: `_atom_layout`, `_bond_layout`, `_h_bond_layout`.
5. `_draw()` (:1095-1218) paints everything immediate-mode — `draw_circle()` per atom (element-colored), `draw_line()` per bond with inset endpoints, dotted segments for real per-atom-pair hydrogen bonds (actual WC donor/acceptor mapping, not approximated). **No per-atom Node2D instances** — same immediate-mode philosophy as `nucleotide_field.gd`.

Ownership split: **Topology** = atoms+bonds identity → **FoldEngine** = topology construction/mutation → (RiboseDeriver/NitrogenBaseDeriver) = 2D coordinates, recomputed fresh every frame, never cached → **Renderer** = orchestration, caching, culling, all drawing.

## Strand/slot addressing

Exact strand strings used everywhere: `"leading"`, `"lagging"`, `"template_top"`, `"template_bottom"`. Every internal key is `"%s:%d" % [strand, slot]`. `slot` is just an integer index into the strand's flat array — **there's no concept of a sub-range or fragment membership anywhere in this addressing scheme.** Backbone bonds (`_build_backbone_bonds()`, :838-881) connect slot N to slot N+1 purely by array adjacency, for every strand unconditionally.

## The Okazaki fragment gap (confirmed, zero hits)

Grepped `okazaki|fragment|frag\.` across all three core scripts — nothing. The renderer currently treats the lagging strand as one continuous, gap-free strand. Concretely:

- `_build_backbone_bonds()` will draw a covalent bond straight across a real nick between two unsealed Okazaki fragments — it has no idea fragments exist.
- No RNA-primer vs. DNA distinction in topology at all (no `is_rna`/sugar-type concept on any atom).
- `replication_manager.gd` already tracks everything needed — `lagging_fragments: Array` of dicts with `frag.slots`, `frag.primer_removed`, `frag.complete`, `frag.sealed` — but none of it is exposed through `get_synthesized_nucleotides()`, which is the only feed the molecular renderer consumes.

There's a design doc that already scoped this — `docs/atomtier/AtomTier_StructuralDesign.md` Task B — covering the same three sub-problems (ribonucleotide topology, the nick itself, Pol I/ligase state reflection). **Caveat: that doc is explicitly self-flagged as "not grounded against source"** — written without reading the actual renderer/replication_manager code — so treat it as a starting hypothesis, not verified fact.

## Design doc map

- **`docs/atomtier/AtomTier_StructuralDesign.md`** — Task A (first-pair boundary bug, diagnostic) + Task B (atom-level Okazaki maturation + RNA primer rendering design) — the most directly relevant doc for Okazaki work, but unverified against source.
- **`docs/atomtier/AtomTier_VisualDesign.md`** — label font scaling across zoom tiers (shipped) + "nested visual grouping" (base-pair→nucleotide→functional-group visual hierarchy, unscoped) — also unverified against source.
- **`docs/MolecularStructureDesign.md`** — the foundational cross-cutting design doc (three-layer Topology/Layout/Render model, "derived not stored" pattern, node-vs-immediate-mode boundary, self-paired fork-flip rationale); heavily ground-truthed with numbered corrections.
- **`docs/MolecularStructure_BasePairExpansion.md`** — Growth Session 2: full double-ribbon, both strands, hydrogen bonds — the bulk of the bug history (Bugs B/C/D/E/I/J/L/P/Q/T/V/W) referenced throughout the renderer's comments.
- **`docs/MolecularStructure_OpenQuestions_Q3Q5Resolution.md`** — resolves stereo-in-topology (Q3) and operator-format (Q5) questions; mostly Krebs-cycle-relevant, not DNA/Okazaki.
- **`docs/MolecularStructure_OpenQuestions_RenderClusterResolution.md`** — resolves render-mode/zoom/culling questions (Q4/Q7/Q8/Q9) — relevant background for how culling and zoom hysteresis were decided.
- **`docs/MolecularIdentityHierarchy_Design.md`** — Nucleation-phase, not yet grounded: how to visually distinguish "which molecule" at ball-and-stick tier when CPK coloring alone loses per-molecule identity; tangential to Okazaki work.
- **`docs/ClaudeCode_Handout_MolecularStructure.md`** — the original Growth-phase kickoff handout for the DNA-first milestone (Session 1); useful for historical context, less relevant now that the subsystem has shipped past it.
- **`docs/OkazakiMaturationDesign.md`** — the bead-glyph-tier fragment/primer/Pol I/ligase design that already shipped; this is what Task B's `frag.primer_removed`/`sealed` fields come from.

## Reading order (for extending this to Okazaki fragments)

1. `docs/MolecularStructureDesign.md` — the shared mental model (three-layer split, "derived not stored" pattern).
2. `scripts/molecule_topology.gd` + `scripts/molecule_fold_engine.gd` — small (86 + 79 lines), establishes the contract any Okazaki extension must fit into.
3. `scripts/molecule_structure_renderer.gd`, focused on `_rebuild_layout()` (:507-826) and `_build_backbone_bonds()` (:838-881) — where fragment-boundary awareness needs to go.
4. `docs/OkazakiMaturationDesign.md` + the `frag` lifecycle in `replication_manager.gd` (search `lagging_fragments`, `_lagging_open_next_fragment`, `_lagging_close_fragment`, `_pol1_finish_job`) — the bead-tier source of truth atom-tier needs to mirror.
5. `docs/atomtier/AtomTier_StructuralDesign.md` Task B — closest existing plan, read critically (see caveat above).
6. `docs/MolecularStructure_BasePairExpansion.md` — skim for "Bug T" (real-vs-fallback boundary residue handling) — structurally the same kind of boundary case as a fragment nick.
