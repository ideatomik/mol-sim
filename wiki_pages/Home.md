# Zymulador Wiki — Comprehensive Architecture Guide

**Last Updated**: Based on codebase v85 (August 2026)

**Companion Documents**: This wiki summarizes *implemented* architecture. For full design rationale, planned features, and biological model, see the links below.

---

## ⚠️ Implemented vs. Planned Features

**This wiki distinguishes between what is built now vs. what is designed but not yet implemented.** Many features documented in `/docs` are *planned* but not yet coded.

---

## Quick Navigation

- [[Project Structure & File Organization]]
- [[Core Architecture & Manager Hierarchy]]
- [[Script Reference]]
- [[Data Flow & Relationships]]
- [[Flowcharts & Diagrams]]
- [[Key Parameters & Configuration]]
- [[Signal Communication Map]]
- [[Planned Features Roadmap]]

---

# Overview


**Zymulador** is a molecular biology education platform built in Godot 4.x (GDScript). It simulates DNA replication as Phase 1 of a broader central dogma simulation (**DNA replication → Transcription → Translation**). The core design principle is **modular complexity** — a single simulator where educators set the complexity level to match their audience.

### Key Implemented Features
- ✅ DNA replication simulation with leading/lagging strand synthesis
- ✅ Okazaki fragment maturation (primase → Pol I → ligase relay)
- ✅ Interactive playback controls with drag-to-scrub timeline
- ✅ Multi-language support (English, Spanish, Portuguese-Brazil)
- ✅ Complexity toggles (primase, Pol I, ligase, topology mode)
- ✅ Procedural enzyme visuals (helicase ring, polymerase clamp/halo, primase blip, Pol I, ligase)
- ✅ End-replication problem (telomere gap) in linear mode

### Key Planned Features (NOT YET IMPLEMENTED)
- ❌ Trombone loop model (lagging polymerase coupled to replisome) — *designed in TromboneLoopDesign.md*
- ❌ Full replisome (clamp loader, β-clamps as distinct enzymes) — *partial: clamp visuals exist but not as separate toggles*
- ❌ Telomerase enzyme visual (extends template strand) — *designed in TelomeraseDesign.md*
- ❌ SSB/shelterin (single-strand binding proteins) — *designed in COMPLEXITY_MODEL.md*
- ❌ Tus-Ter termination (circular mode fork trap) — *designed in TusTerDesign.md*
- ❌ Topoisomerase (torsional strain relief ahead of fork) — *designed in Topoisomerase.md*
- ❌ Bidirectional replication (two replisomes from single origin) — *sketched in TusTerDesign.md*
- ❌ Transcription and Translation phases — *mentioned in DESIGN.md as future scope*

See [Feature Status Matrix](#feature-status-matrix) and [`docs/architecture/STATUS.md`](architecture/STATUS.md) for detailed implementation status.

---

# Feature Status Matrix


| Feature | Status | Complexity Tier | Design Doc | Notes |
|---------|--------|-----------------|------------|-------|
| **Leading strand synthesis** | ✅ Implemented | Base | — | Continuous 5'→3' synthesis, helicase-anchored positioning |
| **Lagging strand synthesis (base)** | ✅ Implemented | Base | OkazakiMaturationDesign.md | Independent polymerase, fixed-size tiles, right-to-left firing |
| **Helicase visual (ring)** | ✅ Implemented | Base | HelicaseDesign.md | Procedural octagon subunits, rotation animation |
| **Polymerase visual (clamp/halo)** | ✅ Implemented | Base | — | Clamp: octagon primitive; Halo: traveling particle |
| **Primase (blip)** | ✅ Implemented | Light | OkazakiMaturationDesign.md | Transient blip at fragment start, RNA primer persistence |
| **Ligase (traveling enzyme)** | ✅ Implemented | Light/Complex | OkazakiMaturationDesign.md | Seals nicks between fragments; Light: gated by Pol III completion; Complex: gated by Pol I completion |
| **Pol I (nick translation)** | ✅ Implemented | Complex | OkazakiMaturationDesign.md | Removes RNA primers, fills DNA behind |
| **Topology mode (CIRCULAR/LINEAR)** | ✅ Implemented | Mode-gate | COMPLEXITY_MODEL.md | Gates end-game modules (telomere gap vs. future Tus-Ter) |
| **Telomere gap (end-replication problem)** | ✅ Implemented | Linear-only | TelomeraseDesign.md | Shows consequence (gap), not yet the actor (telomerase enzyme) |
| **Trombone loop model** | ❌ Planned | High | TromboneLoopDesign.md | Lagging polymerase coupled to replisome via τ body |
| **Full replisome (clamp loader, β-clamps)** | ⚠️ Partial | High | COMPLEXITY_MODEL.md | Clamp visuals exist but not as separate toggles |
| **Telomerase enzyme visual** | ❌ Planned | Eukaryotic-only | TelomeraseDesign.md | Extends template strand, requires dynamic sequence growth |
| **SSB/shelterin** | ❌ Planned | Stage 2 elongation | COMPLEXITY_MODEL.md | Coats ssDNA behind helicase |
| **Tus-Ter termination** | ❌ Planned | Circular-only | TusTerDesign.md | Fork trap for circular chromosomes |
| **Topoisomerase** | ❌ Planned | Advanced | Topoisomerase.md | Relieves torsional strain ahead of fork |
| **Bidirectional replication** | ❌ Planned | Circular | TusTerDesign.md | Two replisomes from single origin |
| **Transcription phase** | ❌ Future scope | — | DESIGN.md | Post-replication central dogma phase |
| **Translation phase** | ❌ Future scope | — | DESIGN.md | Final central dogma phase |

**Legend**: ✅ Implemented | ⚠️ Partial | ❌ Not yet implemented

---


---

## About This Wiki

This wiki documents the **implemented** features of Zymulador as of August 2026. For detailed design documents, roadmap, and planned features, visit the [`docs/`](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/tree/main/docs) folder in the main repository.

### Key Design Documents
- [DESIGN.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/DESIGN.md) — Stable philosophy and biological model
- [STATUS.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/STATUS.md) — Current implementation state and roadmap
- [COMPLEXITY_MODEL.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/COMPLEXITY_MODEL.md) — Complexity toggle system
- [TODO.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/TODO.md) — Working list of bugs and features

---

*Generated automatically from docs/WIKI.md*
