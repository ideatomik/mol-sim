# Na⁺/K⁺ Pump Spike — Design (pre-implementation)

_Design document. Companion to SHARED_BASE_SEAM.md, COMPLEXITY_MODEL.md, and
SKILL.md's Crystal Building method. No As-Built section yet — nothing here
has shipped._

---

## Purpose

PIPE Jornada Tecnológica Fase 1 desafio tecnológico. DNA replication is a
demonstrated concept (disqualifying under item 8.5a) — this spike exists to
prove a genuinely open technical question elsewhere in the architecture:
**does the regent-driven, derive-everything-from-one-counter pattern
generalize beyond a spatial position (helicase's x-coordinate) or a finite,
externally-reset state machine (ligase's IDLE→TRAVELING→HOLDING→SEALING)?**

The Na⁺/K⁺ pump's conformational cycle is the test case: a **self-sustaining,
non-spatial regent that cycles indefinitely on its own**, requiring modulo
arithmetic to derive an arbitrary scrub target instantly — the same
wraparound math the Krebs cycle would eventually need, tested here on a
domain with zero DNA/sequence machinery at all.

**Explicitly not this spike's job:** proving Krebs cycle itself works. Krebs
remains the product's flagship/roadmap target — the thing this spike's
result argues *for*, not what it builds. A passive ion channel (ligand-gated
gate, contrasted against the pump's active cycle) was considered and cut for
scope — see "Deferred" below.

---

## Biological reference — Post-Albers cycle (6 phases)

1. **E1·3Na** — cytoplasm-facing, high Na⁺ affinity, 3 Na⁺ bound
2. **E1P** — ATP hydrolyzed, phosphorylated, conformational shift begins
3. **E2P** — extracellular-facing, low Na⁺ affinity → releases 3 Na⁺
4. **E2P·2K** — high K⁺ affinity, binds 2 K⁺ extracellularly
5. **E2** — dephosphorylated
6. **E1** — shifts back to cytoplasm-facing, releases 2 K⁺, high Na⁺
   affinity restored → phase 1 of next cycle

Didactic accuracy over exhaustive precision, same standard as the
replication model — ATP-binding detail and the phosphorylation mechanism
itself are not separately animated (see Out of Scope).

---

## Regent

`pump_step: int` — monotonically increasing, never clamped (unlike
`helicase_mgr.current_slot_index`, which halts at sequence end — this one
doesn't, since the cycle has no terminus). Everything else is derived, same
discipline as helicase and the "never let two independently-tuned numbers
coincidentally agree" rule:

```gdscript
const NUM_PHASES := 6
var cycle_phase: int = pump_step % NUM_PHASES
var cycles_completed: int = pump_step / NUM_PHASES  # integer division
```

No other stored state. Ion tallies are computed from `pump_step`, never
accumulated imperatively:

```gdscript
total_na_released = cycles_completed * 3 + (3 if cycle_phase >= 2 else 0)
total_k_released  = cycles_completed * 2 + (2 if cycle_phase >= 5 else 0)
```

### Scrub-safety test case — the actual deliverable

Jump directly to `pump_step = 47`. Must instantly render: `cycle_phase = 5`
(E1, post-K-release), `cycles_completed = 7`, ion tallies consistent with 7
full cycles + partial phase 5 — zero animation replay, matching the
project's existing instant-snap invariant (`SKILL.md`'s "scrub is always an
instant snap" rule).

---

## Playback controls

Three interaction modes, all reading/writing `pump_step`:

- **Autoplay** — mirrors `helicase_mgr`'s play/pause/`step_duration`/
  `speed_multiplier` pattern. No finishing-phase machinery (`FINISHING_LAST_
  PULSE`/`SETTLING`) — those exist because a DNA sequence terminates; the
  pump cycle doesn't, so there's no "last slot" to special-case. Simpler
  than helicase, not a port of it.
- **Manual step, forward and backward** — the strongest argument for the
  scrub mechanic generally: a professor can pause and narrate phase-by-phase
  live, in either direction, which a continuously-running pump can't
  support. `pump_step += 1` / `pump_step -= 1` (never below 0), each
  triggering the same instant-derive path as scrub.
- **Scrub slider** — jump to an arbitrary `pump_step` directly. This is the
  actual architectural proof point; autoplay and manual-step are UX on top
  of the same underlying derivation.

---

## Visual design

**6 fully distinct poses**, one per phase — chosen over the cheaper
2-base-shape + overlay-boolean approach for visual variety, at the cost of
more asset-authoring time. **Flagged as the first thing to cut back to the
overlay approach if the 11-day budget gets tight** — the regent/scrub
architecture is identical either way, so downgrading pose count later costs
nothing else in the design.

- **Pose swap**: `PumpProtein` node swaps its rendered shape based on
  `cycle_phase`, built from `ProceduralShapeUtils.round_corners()`/
  `octagon()` primitives rather than a 6th independent copy-paste (per
  SKILL.md's "Keep together" guidance on `procedural_shape_utils.gd`).
- **Ion binding/release**: reuses the `PolymeraseHalo` particle-pool pattern
  from nucleotide capture — a small fixed-size pool of particles resolving
  into Na⁺ or K⁺ at the specific phase transitions (bind at phase 1,
  release at phase 3; bind at phase 4, release at phase 6), rather than a
  new particle system.
- **Membrane**: implied by a static horizontal line the protein sits on —
  no lipid bilayer rendering.

---

## Scene structure

New scene, sibling to `simulation.tscn`, not a child of it:

```
pump_spike.tscn / pump_spike.gd  (thin coordinator, mirrors simulation.gd's role)
├── ThemeManager (%ThemeManager)      — new export group, reused node pattern
│                                       (not autoload, matching the rest of
│                                       the project)
├── PumpProtein (Node2D)              — 6-pose swap, procedural shapes
├── IonHalo                           — reused PolymeraseHalo pattern,
│                                       restocked from cytoplasm/
│                                       extracellular sides
└── UI
    ├── Phase label / cycle counter
    ├── Play/pause + speed control
    ├── Step forward / step backward buttons
    └── Scrub slider
```

---

## Out of scope for this spike

- ATP molecule visual / phosphorylation mechanism detail — phase transition
  1→2 just fires, no ATP-binding animation
- Any tie-in to `ComplexityManager` tiers — single complexity level only
- Membrane/lipid bilayer rendering beyond the implying line
- Localization — English labels only

## Deferred (not urgent, don't lose)

- **Passive ion channel** (ligand-gated gate, contrasted against the pump's
  active cycle) — considered during design. Would have unified two trigger
  philosophies already proven separately in the codebase (helicase =
  autonomous clock-driven, ligase = event-count-gated) under one
  `state = f(counter)` pattern, on `channel_trigger_count` instead of a
  clock. Cut for scope given the 11-day PIPE timeline — a real second
  mechanism, not a cheap add. Worth revisiting post-proposta-simplificada if
  the "one derivation pattern, two trigger philosophies" argument turns out
  to matter for the fuller proposal.

---

## Open questions (unresolved — this is a first-pass design)

- Exact phase-boundary timing for ion bind/release relative to pose swap —
  simultaneous, or does the ion animation lead/lag the shape transition?
  (Compare: nucleotide capture's arrival syncs to `get_eased_step_t()`, not
  simultaneous with slot arrival.)
- Whether `pump_step` starts at 0 (E1·3Na, empty) or some mid-cycle default
  that reads better on scene load.
