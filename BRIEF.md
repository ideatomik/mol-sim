# Zymulador — Brief

- **Phase:** Active development.
- **Last milestone:** v85 — alpha-ship UI/localization pass: language
  switcher, export size cut (~26MB unused fonts removed), a new
  `CursorAffordanceManager` (hover/drag cursor swaps), a per-sequence
  Okazaki fragment-size control, localized tooltips across all 17
  `PlayerUI` buttons, and three real replication-visual bugs traced to
  root cause (primase's untracked placement tween, a missing
  scrub-retrigger idempotency guard, and `resume_enzymes()` not checking
  each enzyme's actual state before forcing it visible). See
  `docs/architecture/CHANGELOG.md` (top entry) and `docs/architecture/STATUS.md`
  ("Alpha-Ship Pass — UI/Localization + Replication Bug Fixes (v85)").
  Sits on top of the still-more-fundamental Molecular Structure Lattice
  closeout (Crystal Building Method, docs-only) from the prior milestone —
  see `MolecularStructureDesign.md`.
- **Current focus:** Growth phase — implementing the Molecular Structure
  work against its scope fence (ribose ring deriver, phosphodiester
  operator, skeletal rendering gated to free-camera deep zoom). No
  implementation code exists yet as of this entry; v85 was a parallel
  alpha-ship-prep detour, not part of this work.
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
