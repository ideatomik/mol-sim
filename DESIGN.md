# MolSim — Design Document
_Last updated: v70.2 session_

---

## What MolSim Is

MolSim is a molecular biology education platform built in Godot 4.x (GDScript).
It is not just a DNA replication simulator — replication is Phase 1 of a broader
simulation covering the central dogma: **DNA replication → Transcription → Translation**.

The core design principle is **modular complexity**: a single simulator, one codebase,
where educators set the complexity dial to match their audience. High school, undergraduate,
or general public — same product, different feature toggles.

---

## Complexity System

Complexity toggles are **first-class citizens** in the architecture, not afterthoughts.
Every new feature must be built toggle-aware from the start, even before the toggle UI exists.
A feature that can't be hidden is technical debt.

### Replication complexity layers (in order)
1. Leading strand only — core concept of semiconservative replication
2. + Lagging strand and Okazaki fragments
3. + Full replisome (tau body, sliding clamps, clamp loader, primase)
4. + RNA primers and primer removal
5. + Proofreading (DNA Pol III 3'→5' exonuclease)
6. + Mismatch Repair (MutS/MutL/MutH complex, post-replication)

### Transcription complexity layers
- RNA Polymerase, promoter recognition, mRNA strand synthesis
- Transcription errors (RNA Pol has no proofreading; ~1 error per 10⁴ bases)
- Redundancy concept: many mRNA copies buffer transcription errors

### Translation complexity layers
- Ribosome, tRNA, codons, polypeptide chain synthesis
- Error mechanics layered on top

---

## Biological Model

MolSim follows the **E. coli replication model** for accuracy and visual clarity.

### Key biological facts encoded in the simulation
- DNA Pol III can only synthesize 5'→3'
- The two template strands are antiparallel
- Leading strand: continuous synthesis in the direction of the fork
- Lagging strand: discontinuous synthesis (Okazaki fragments) via trombone loop model
- Each Okazaki fragment requires an RNA primer (primase)
- Fragments are joined by DNA ligase after primer removal
- The replisome holds both polymerases together via the tau (τ) body
- β-clamp (sliding clamp) on each strand increases polymerase processivity

### Didactic simplifications (intentional)
- Sequences are short (≤57 bases) for visual clarity
- Single-slot Okazaki fragments use a combined "5'-3'" marker
- Biological accuracy is didactic, not exhaustive

---

## Architecture

### Current state (v70.2)
Everything lives in `simulation.gd`. This is intentional for now — premature
modularization before the feature set is stable adds overhead without benefit.

### Target architecture (SimulationManager refactor)
The refactor should be driven by the complexity system design first — toggles before
anything else. Proposed module boundaries follow biological boundaries:

```
simulation.gd (thin coordinator)
├── SimulationManager         — owns sequence resource, complexity toggles, phase flow
├── replication_manager.gd    — helicase, polymerases, Okazaki logic, synthesis states
├── replisome_visual.gd       — tau body, clamps, enzyme geometry (toggle-aware)
├── transcription_manager.gd  — RNA Pol, promoter, mRNA strand
├── translation_manager.gd    — ribosome, tRNA, polypeptide
└── error_mechanics.gd        — proofreading, MMR; shared by replication + transcription
```

### Key architectural rules
- **ThemeManager**: scene node on root, Inspector-editable, no autoload
- **DnaSequenceResource**: will move into SimulationManager
- **nitrogen_base.gd**: ThemeManager-free, colors injected via `set_colors()` / `set_font()`
- `add_child()` before `set_colors()` / `set_font()` (so `_ready()` fires first)
- GDScript: no multiline `or` expressions (put on one line — parser bug)
- Every new enzyme/visual designed with an on/off switch, even before toggle UI exists

---

## Development Conventions

- **Architecture-first**: discuss design before writing any code
- **Strict scope discipline**: do not make unrequested changes
- **Version discipline**: commit stable versions before major changes; revert when regressions appear
- **Location anchors over line numbers**: use surrounding code snippets as edit anchors
- **Debug prints stay** until the feature they guard is confirmed stable
- **True current version**: the uploaded file is always ground truth, not earlier pastes

---

## Roadmap

### Immediate (v70.x)
- [ ] Remove debug prints (`[OKAZAKI]`, baseline switch) — scrub now confirmed stable
- [ ] Ligase joining Okazaki fragments into `new_strand_backbone_line` + reveal whole-strand lagging markers
- [ ] RNA primers and primase enzyme

### Replisome visual
- [ ] Unified replisome structure (E. coli model):
  - τ (tau) body connecting helicase, leading polymerase, lagging polymerase, clamp loader
  - Replaces current separate synthesis circles
  - Designed as a single visual node, toggle-aware
- [ ] Sliding clamps (β-clamp):
  - One per Okazaki fragment on lagging strand
  - One on leading strand

### Medium term
- [ ] SimulationManager refactor — complexity toggle system designed first
- [ ] Modular script breakdown (see architecture above)
- [ ] UI controller rebuild
- [ ] Themes: Dark, Light, Dark Low-Info, Light Low-Info
  - Low-Info variants: reduced visual complexity for autistic users
  - Fewer simultaneous animated elements
  - Muted palette, no high-contrast flashing
  - Wobble disabled or greatly reduced

### Long term
- [ ] Transcription phase
- [ ] Error mechanics (proofreading on replication, error rates on transcription)
- [ ] Translation phase
- [ ] DNA sequence input UI (wire to `dna_sequence.set_from_string()`)

---

## Pinned Issues

- **Scrub edge case**: occasional escaped synthesized base just left of lagging
  polymerase during scrub. Harder to reproduce after v70.2 fix but not fully closed.
  May need a stricter boundary condition or a different synthesis eligibility approach.

---

## Scene Structure (v70.2)

```
root (Node2D, simulation.gd)
├── Camera2D
├── CanvasLayer → ColorRect
├── RailPath (Path2D)                    — bottom template strand
├── TopRailPath (Path2D)                 — top template strand
├── TemplateStrandOriginalTrack (Line2D)
├── NewStrandLine (Line2D)
├── SynthesisCircle (Node2D) → SynthesisArea (Area2D)
├── TemplateStrandNewTrack (Line2D)
├── TopTemplateStrandNewTrack (Line2D)
├── BackboneLine (Line2D)
├── HydrogenBondsContainer (Node2D)
├── TemplateHydrogenBondsContainer (Node2D)
├── ThemeManager (Node, %ThemeManager)
└── UI (CanvasLayer)
    ├── SequenceLoaderPopup
    └── PlayerUI
```
