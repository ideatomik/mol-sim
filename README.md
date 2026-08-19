# Zymulador

**Zymulador** is a molecular biology education platform built in Godot 4.x (GDScript). It is not just a DNA replication simulator — replication is Phase 1 of a broader simulation covering the central dogma: **DNA replication → Transcription → Translation**.

The core design principle is **modular complexity**: a single simulator, one codebase, where educators set the complexity dial to match their audience. High school, undergraduate, or general public — same product, different feature toggles.

![License](https://img.shields.io/badge/license-proprietary-blue.svg)
![Godot Version](https://img.shields.io/badge/Godot-4.6-%23478cbf?logo=godot-engine&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)

---

## Table of Contents

- [Features](#features)
- [Complexity System](#complexity-system)
- [Installation](#installation)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Documentation](#documentation)
- [Localization](#localization)
- [Current Status](#current-status)
- [Roadmap](#roadmap)
- [Credits](#credits)

---

## Features

### DNA Replication Simulation
- **Leading strand synthesis** with continuous polymerase activity
- **Lagging strand synthesis** with Okazaki fragments
- **Trombone loop model** showing physical coupling of polymerases
- **Full replisome visualization** including helicase, primase, clamp loader, and β-clamps
- **RNA primer placement and removal** as explicit enzymatic steps
- **Proofreading mechanisms** (3'→5' exonuclease activity)
- **Mismatch repair complex** visualization

### Interactive Controls
- **Playback controls**: Play, pause, step forward/backward, fast forward/rewind
- **Drag-to-scrub**: Direct manipulation of the replication timeline
- **Free camera mode**: Deep zoom into molecular structures
- **Sequence loader**: Load custom DNA sequences with configurable parameters
- **Language switcher**: Real-time localization between English, Spanish, and Portuguese (Brazilian)

### Visual Enhancements
- **DNA helix unwinding intro**: Startup animation showing twisted double-helix settling into flat rail view
- **Per-base wobble**: Realistic thermal motion of nucleotides
- **Backbone line rendering**: Continuous or segmented based on complexity tier
- **Hydrogen bond visualization**: 2 bonds for A-T pairs, 3 for C-G pairs
- **Enzyme affordance cursors**: Context-aware cursor changes for interactive elements

---

## Complexity System

Complexity toggles are **first-class citizens** in the architecture. Every feature is built toggle-aware from the start.

### Replication Complexity Layers

| Tier | Features |
|------|----------|
| 1 | Leading strand only — core concept of semiconservative replication |
| 2 | + Lagging strand with fixed-size Okazaki fragments |
| 3 | + Trombone loop model — lagging polymerase coupled to replisome |
| 4 | + Full replisome (clamp loader, β-clamps, primase) |
| 5 | + RNA primers and primer removal |
| 6 | + Proofreading (DNA Pol III 3'→5' exonuclease) |
| 7 | + Mismatch Repair (MutS/MutL/MutH complex) |

Additional toggles control:
- **Telomere gap visibility** (end-replication problem)
- **Backbone continuity** (nicks between Okazaki fragments)
- **Enzyme labels** (on-demand annotation overlay)

---

## Installation

### Prerequisites
- **Godot Engine 4.6** or later (GL Compatibility renderer)
- Windows 10/11 (primary export target)

### Setup
1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd Zymulador
   ```

2. Open the project in Godot:
   - Launch Godot Engine
   - Click "Import" and navigate to `project.godot`
   - The project will appear in your project list

3. Run the simulation:
   - Press F5 or click the Play button in Godot
   - The main scene (`simulation.tscn`) will load automatically

### Export
Export presets are configured in `export_presets.cfg`. Current configuration:
- Windows Desktop (DirectX 12, GL Compatibility)
- Embedded PCK for single-file distribution
- Optimized font inclusion (~108MB final size)

---

## Usage

### Basic Controls
| Key | Action |
|-----|--------|
| `Space` | Play/Pause simulation |
| `.` | Step forward |
| `,` | Step backward |
| `Shift + .` | Fast forward |
| `Shift + ,` | Fast rewind |
| `F2` | Toggle player UI visibility |
| `F3` | Toggle enzyme labels |
| `L` | Cycle language (deprecated — use dropdown) |

### Mouse Interaction
- **Click and drag** on helicase ring or polymerase clamps to scrub timeline
- **Scroll wheel** to zoom in/out (gated to free-camera mode at deep zoom levels)
- **Right-click and drag** to pan camera (free-camera mode)

### Sequence Loading
1. Click the "Load Sequence" button
2. Select a preset sequence or enter custom DNA
3. Adjust Okazaki fragment size (for lagging strand tiers)
4. Configure topology and complexity toggles
5. Click "Load" to initialize the simulation

---

## Project Structure

```
Zymulador/
├── scenes/                     # Godot scene files (.tscn)
│   ├── simulation.tscn         # Main simulation scene
│   ├── PlayerUI.tscn           # Horizontal playback controls
│   ├── VerticalPlayerUI.tscn   # Vertical playback controls
│   ├── ComplexitySetupPopup.tscn  # Settings dialog
│   ├── SequenceLoaderPopup.tscn   # Sequence selection
│   ├── DnaUnwindIntro.tscn     # Helix unwinding animation
│   └── enzyme_label.tscn       # Enzyme annotation labels
├── scripts/                    # GDScript source files
│   ├── simulation.gd           # Main coordinator (template manager)
│   ├── core/                   # Core systems (camera, locale, complexity)
│   ├── replication/            # Enzyme logic (helicase, polymerases, etc.)
│   ├── rendering/              # Visual rendering utilities
│   └── ui/                     # UI controllers
├── docs/                       # Documentation
│   ├── architecture/           # Design docs, changelog, status
│   ├── enzymes/                # Enzyme-specific design documents
│   ├── molecular-structure/    # Krebs cycle & structure planning
│   └── superpowers/            # Feature specifications
├── localization/               # Translation files
│   ├── enzyme_labels.*.translation
│   ├── presets.*.translation
│   └── ui_strings.*.translation
├── fonts/                      # Font assets (Noto Sans family)
├── icons/                      # UI iconography
├── cursors/                    # Cursor pack (Kenney's CC0)
├── resources/                  # Shared resources
├── button_styles/              # Button theme resources
├── project.godot               # Project configuration
├── export_presets.cfg          # Export configuration
└── BRIEF.md                    # Quick project overview
```

---

## Documentation

Comprehensive documentation is maintained in the `docs/` directory:

| Document | Purpose |
|----------|---------|
| `docs/architecture/DESIGN.md` | Stable design philosophy and biological model |
| `docs/architecture/STATUS.md` | Current implementation state and roadmap |
| `docs/architecture/CHANGELOG.md` | Version history (all versions) |
| `docs/architecture/TODO.md` | Working task list and known issues |
| `docs/architecture/COMPLEXITY_MODEL.md` | Complexity system specification |
| `BRIEF.md` | Quick project overview and current phase |

### Key Design Documents
- **Enzyme designs**: `docs/enzymes/` — individual enzyme behavior specs
- **Molecular structure**: `docs/molecular-structure/` — Krebs cycle planning
- **Superpowers**: `docs/superpowers/` — feature specifications

---

## Localization

Zymulador supports three languages out of the box:

| Language | Code | Endonym |
|----------|------|---------|
| English | `en` | English |
| Spanish | `es` | Español |
| Portuguese (Brazil) | `pt_BR` | Português (Brasil) |

### Adding a New Language
1. Create translation files in `localization/`:
   - `enzyme_labels.<code>.translation`
   - `presets.<code>.translation`
   - `ui_strings.<code>.translation`

2. Add translations to `project.godot`:
   ```ini
   [internationalization]
   locale/translations=PackedStringArray(..., "res://localization/<file>.<code>.translation")
   ```

3. The language switcher in `ComplexitySetupPopup` will automatically detect new locales.

---

## Current Status

**Phase:** Active development (v85 — Alpha-ship UI/localization pass)

### Completed
- ✅ Leading strand synthesis
- ✅ Lagging strand with Okazaki fragments (base complexity)
- ✅ Primase, Pol I, and Ligase enzymes
- ✅ Trombone loop model
- ✅ Full replisome visualization
- ✅ Language switcher (EN/ES/PT-BR)
- ✅ Localized tooltips across all 17 PlayerUI buttons
- ✅ DNA helix unwinding intro animation
- ✅ Free camera mode with deep zoom
- ✅ Cursor affordance system

### In Progress
- 🔄 Molecular Structure Lattice (ribose ring deriver, phosphodiester operator)
- 🔄 Settings/Setup menu split (general settings vs. per-simulation setup)

### Planned
- ⏳ Transcription simulation
- ⏳ Translation simulation
- ⏳ Krebs Cycle physical/electromechanical model
- ⏳ Telomerase and end-replication problem visualization
- ⏳ Proofreading and mismatch repair tiers

---

## Roadmap

### Near-term (Post-Alpha)
1. **Export size optimization** — Custom-compiled Godot templates, UPX packing
2. **Menu restructuring** — Separate general settings from simulation setup
3. **Molecular Structure implementation** — DNA-first milestone completion

### Mid-term
1. **Transcription module** — RNA polymerase, promoter regions, splicing
2. **Translation module** — Ribosome, tRNA, codon table
3. **Trademark clearance** — INPI + WIPO/USPTO filing for "Zymulador"

### Long-term
1. **Krebs Cycle physical model** — Electromechanical tabletop installation
2. **Full central dogma coverage** — All three processes in one platform
3. **Educational curriculum integration** — Lesson plans, assessments

---

## Credits

### Development
- Built with **Godot Engine** 4.x (GDScript)
- Jolt Physics integration for 3D physics

### Assets
- **Kenney's Cursor Pack** (CC0) — Interactive cursor affordances
- **Noto Sans font family** — Localization typography
- Custom SVG icons and button styles

### Biological Accuracy
Design informed by standard molecular biology textbooks and peer-reviewed literature on DNA replication mechanisms.

---

## License

Proprietary educational software. All rights reserved.

---

## Contact

For questions, contributions, or licensing inquiries, please refer to the project documentation or contact the development team.

**Last updated:** August 2026
