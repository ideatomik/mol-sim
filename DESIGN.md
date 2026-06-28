# MolSim — Design Document
_Last updated: v70.4 session_

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

### Current state (v70.4)
`helicase.gd` and `replication_manager.gd` have been extracted. `simulation.gd` is now
a template manager + visual coordinator. Phase 1 migration is complete.

```
simulation.gd  — Template Manager + visual coordinator
├── helicase.gd  — discrete slot stepping, phase state machine (EXTRACTED ✓)
└── replication_manager.gd  — synthesis state, spawning, update(), scrub_rebuild(), render() (EXTRACTED ✓)
```

### replication_manager.gd migration — two-phase plan

**Phase 1 ✓ DONE (v70.4):** All synthesis state variables and spawning functions live in
`replication_manager.gd`. simulation.gd calls `replication_manager.update(delta)` from
its `_process`, passing context. Data lives in the right place.

**Phase 2 (medium term, with okazaki_manager):** Convert to proper signal-based
architecture. Extract Okazaki fragment logic into `okazaki_manager.gd`.
Signals replace the `update(delta)` calling pattern.

### Target architecture
```
ComplexityManager (Node → autoload later)
│   @export toggles per feature (okazaki_fragments, sliding_clamps, etc.)
│   is_enabled("feature_name") -> bool
│
ThemeManager (Node → autoload later)
│   @export visual parameters. Same pattern as ComplexityManager.
│
simulation.gd  — Template Manager (thin scene coordinator)
│   Owns original DNA strands, rails, sequence resource, geometry constants.
│   Exposes slot positions, bases, and geometry to process managers.
│   Does NOT own any synthesized products.
│
├── replication_manager.gd  — thin coordinator for replication
│   Owns shared per-slot state arrays. Delegates to sub-managers.
│   │
│   ├── helicase.gd  ✓ DONE
│   │   Discrete slot-by-slot stepping. Owns phase state machine.
│   │   Emits: slot_reached(index), phase_changed(new_phase).
│   │
│   ├── okazaki_manager.gd  (Phase 2)
│   │   Fragment tracking, assignment, open/close logic, sliding clamps (future).
│   │
│   ├── primase.gd  (future)
│   └── ligase.gd  (future)
│
├── transcription_manager.gd  (future)
└── translation_manager.gd    (future)
```

### Key architectural rules
- **ThemeManager / ComplexityManager**: scene nodes, Inspector-editable, no autoload yet.
  Convert to autoload once export values settle.
- **nitrogen_base.gd**: ThemeManager-free, colors injected via `set_colors()` / `set_font()`
- `add_child()` before `set_colors()` / `set_font()` (so `_ready()` fires first)
- GDScript: no multiline `or` expressions (put on one line — parser bug)
- Every new enzyme/visual designed with an on/off switch, even before toggle UI exists
- **Signal connections**: always guard with `if not signal.is_connected(callable)`
  before connecting in functions called on re-initialization

---

## Development Conventions

- **Architecture-first**: discuss design before writing any code
- **Strict scope discipline**: do not make unrequested changes
- **Version discipline**: commit stable versions before major changes; revert when regressions appear
- **Location anchors over line numbers**: use surrounding code snippets as edit anchors
- **Debug prints stay** until the feature they guard is confirmed stable
- **True current version**: the uploaded file is always ground truth, not earlier pastes
- **When combining fixes**: always diff the two versions, identify what changed,
  apply only the additive fix to the known-good base — never rewrite from memory

---

## Roadmap

### Immediate (v70.5)
- [ ] Ligase joining Okazaki fragments + reveal whole-strand lagging markers
- [ ] RNA primers and primase enzyme

### Replisome visual
- [ ] Unified replisome structure (E. coli model):
  - τ (tau) body connecting helicase, leading polymerase, lagging polymerase, clamp loader
  - Replaces current separate synthesis circles
  - Designed as a single visual node, toggle-aware
- [ ] Sliding clamps (β-clamp): one per Okazaki fragment + one on leading strand

### Medium term
- [ ] replication_manager.gd Phase 2 (signal-based, okazaki_manager.gd extraction)
- [ ] ComplexityManager node (toggles per feature, Inspector-editable first)
- [ ] UI controller rebuild
- [ ] Themes: Dark, Light, Dark Low-Info, Light Low-Info

### Long term
- [ ] Transcription phase
- [ ] Error mechanics (proofreading on replication, error rates on transcription)
- [ ] Translation phase
- [ ] DNA sequence input UI

---

## Pinned Issues

- **Scrub edge case**: occasional escaped synthesized base just left of lagging
  polymerase. Significantly improved in v70.2–v70.3 but not fully closed. Likely
  disappears after replication_manager discrete stepping refactor.

---

## Scene Structure (v70.4)

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

helicase.gd — added as child of simulation.gd at runtime via initialize_simulation()
replication_manager.gd — added as child of simulation.gd at runtime via initialize_simulation()
```
