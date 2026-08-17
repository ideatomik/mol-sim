# Zymulador — Brief

- **Phase:** Active development.
- **Last milestone:** Molecular Structure design's Lattice phase (Crystal
  Building Method) closed out — docs-only, no code changed. All six
  originally-flagged design files ground-truthed, every open question
  bearing on the DNA-first milestone decided. See
  `docs/architecture/CHANGELOG.md` (top entry) and `MolecularStructureDesign.md`.
  This sits on top of the lagging-strand Okazaki maturation relay (primase →
  Pol I → ligase) and the topology-mode/telomere-gap mechanic, both already
  implemented, animated, and QA'd — see `docs/architecture/STATUS.md`.
- **Current focus:** Growth phase — implementing the Molecular Structure
  work against its scope fence (ribose ring deriver, phosphodiester
  operator, skeletal rendering gated to free-camera deep zoom). No
  implementation code exists yet as of the last changelog entry.
- **Also open, per `docs/architecture/TODO.md`:** a future Settings/Setup
  menu split — `ComplexitySetupPopup` currently mixes general app settings
  (language) with per-simulation setup (topology, Okazaki toggles), which
  won't scale once simulation types beyond DNA replication exist; needs its
  own brainstorm pass — the Krebs physical/electromechanical tabletop model
  (design doc exists, not yet approved or built), and trademark/domain
  clearance for "Zymulador" (INPI + WIPO/USPTO) before any spend on
  logo/domain/campaign.
- **Blockers:** none open.
- **Next deadline:** none specified in source docs.
- **Last updated:** 2026-08-17

## Location note

This is the real project folder (git repo root: `project.godot`, `.git`,
`scenes/`, `scripts/`, `docs/`, etc.). `e:\Embauba\Zymulador` is an NTFS
junction pointing here — not a copy. Edit files here or through the
junction; both paths resolve to the same files on disk. The parent folder,
`E:\Godot Projects\MolSim\`, also holds a pile of loose pre-split assets
(font packages, a "backing up original scripts and scenes" folder, stray
`.gd`/`.tscn` files) predating this repo's cleanup — none of that is part
of the live project.
