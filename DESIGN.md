# MolSim — Design Document
_Last updated: v70.5 session_

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

### Current state (v70.5)
`helicase.gd` and `replication_manager.gd` are extracted and stable. `simulation.gd` is
a thin template manager + visual coordinator that owns no synthesis state.

**Phase 1 and Phase 2 are both complete** (see migration history below). The lagging
strand itself — Okazaki fragments, the trombone loop, primase, ligase — was fully
**removed** during a loop-mechanics rebuild attempt and needs to be designed and
implemented fresh. This is not a regression of the architecture; the architecture is
in its target shape. It's a clean slate for the one piece of biology that was never
successfully modeled in the old proximity/transfer state machine.

```
simulation.gd  — Template Manager + visual coordinator
├── helicase.gd  — discrete slot stepping, phase state machine, signals (DONE ✓)
└── replication_manager.gd  — leading strand synthesis only; both polymerase
                               enzyme visuals; intro/resume animation API (DONE ✓)
                               Lagging strand: NOT YET BUILT (clean slate)
```

### replication_manager.gd migration — history

**Phase 1 ✓ DONE:** All synthesis state variables and spawning functions moved into
`replication_manager.gd`. simulation.gd calls `replication_manager.update(delta, ctx)`
and `scrub_rebuild(ctx)`, passing context. Data lives in the right place.

**Phase 2 ✓ DONE:** `helicase.gd` exposes real signals (`slot_reached`,
`phase_changed`) that `replication_manager.gd` connects to directly via
`connect_helicase()`/`_on_helicase_slot_reached()` (signal wiring exists in the
codebase already; currently unused while the lagging strand is being rebuilt, but the
pattern is proven and ready). Enzyme animation became method-based instead of
`simulation.gd` poking node properties: `replication_mgr.resume_enzymes()` and
`replication_mgr.run_intro(intro_x, fade_time, slide_time, tween)` are now the only
ways `simulation.gd` touches `synthesis_circle` / `top_polymerase`. `simulation.gd`
no longer references either enzyme node directly anywhere.

The originally-planned `okazaki_manager.gd` extraction did not happen as a literal
file move, because the Okazaki/lagging-strand logic it would have extracted was
removed entirely rather than carried forward. The signal-based, delegation-clean
architecture Phase 2 was meant to produce is in place regardless — `okazaki_manager.gd`
(or equivalent) will be designed fresh when the lagging strand is rebuilt, using the
deterministic `slot_reached`-driven trigger pattern proven by the leading strand's own
position-based synthesis check as a reference for how clean a trigger can be.

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
│   ├── okazaki_manager.gd  (NEXT — lagging strand rebuild from scratch)
│   │   Fragment tracking, assignment, open/close logic, sliding clamps (future).
│   │   Trombone loop geometry and slot positioning along the loop curve.
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
- **No script reaches into another script's owned visual nodes.** `simulation.gd`
  never positions, fades, or queries `replication_mgr`'s enzymes directly — it calls
  methods on `replication_mgr` instead. This rule was tightened during the Phase 2
  cleanup after repeated regressions where `simulation.gd` quietly grew direct pokes
  into `replication_mgr.synthesis_circle` / `top_polymerase`.

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
- **When rebuilding a subsystem from scratch**: remove the old implementation
  completely first (state, render, scrub paths, signal connections) and confirm a
  clean, regression-free baseline before writing any new logic on top. Layering new
  logic over not-fully-removed old logic was the direct cause of the loop-mechanics
  rebuild's repeated failures.

---

## Roadmap

### Immediate (v70.6) — Lagging strand rebuild
- [ ] Design the trombone loop curve and PLL (Pre-Loop Length) geometry as
      first-class `replication_manager.gd` logic, not `simulation.gd` debug
      scaffolding (migrate the existing PLL diagonal/zigzag debug visuals into real
      geometry math owned by `replication_manager.gd`)
- [ ] Deterministic, helicase-step-driven loop slot queue and Okazaki fragment
      assignment (no proximity/transfer state machine — that pattern is retired)
- [ ] Re-implement lagging strand synthesis, rendering, and scrub rebuild against
      the clean Phase 2 architecture
- [ ] Ligase joining Okazaki fragments + reveal whole-strand lagging markers
- [ ] RNA primers and primase enzyme

### Replisome visual
- [ ] Unified replisome structure (E. coli model):
  - τ (tau) body connecting helicase, leading polymerase, lagging polymerase, clamp loader
  - Replaces current separate synthesis circles
  - Designed as a single visual node, toggle-aware
- [ ] Sliding clamps (β-clamp): one per Okazaki fragment + one on leading strand

### Medium term
- [ ] `okazaki_manager.gd` extraction once the lagging strand above is stable
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

- **Scrub edge case (lagging strand, historical)**: occasional escaped synthesized
  base just left of lagging polymerase, present in the old proximity/transfer state
  machine. Moot now that the lagging strand has been removed entirely; flagged here
  so the rebuilt version is designed to avoid the same class of bug (the deterministic
  step-count model should make this structurally impossible rather than "improved").

---

## Scene Structure (v70.5)

```
root (Node2D, simulation.gd)
├── Camera2D
├── CanvasLayer → ColorRect
├── RailPath (Path2D)                    — bottom template strand
├── TopRailPath (Path2D)                 — top template strand
├── TemplateStrandOriginalTrack (Line2D)
├── SynthesisCircle (Node2D)             — lagging-position polymerase visual,
│                                           driven entirely by replication_mgr
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

Removed from the scene during the lagging-strand cleanup (dead proximity-detection
and unused debug/baseline nodes): `NewStrandLine`, `SynthesisArea` +
`SynthesisCollisionShape` (children of `SynthesisCircle`), `TemplateStrandNewTrack`,
`TopTemplateStrandNewTrack`. `top_polymerase` is not a scene node — it's created
procedurally by `replication_manager.gd` in `setup_backbones()`.
