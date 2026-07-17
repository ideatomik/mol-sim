# MolSim — The Shared Base Layer Seam

_Design contract. Companion to DESIGN.md and COMPLEXITY_MODEL.md. Articulates
the boundary between what is **shared** across all MolSim simulations and what
is **specific** to DNA replication, so that any future extraction of a common
base layer has a target to honor. This is a contract, not a refactor plan — the
refactor itself is deferred until transcription/translation design begins._

---

## Why this exists

MolSim is not one simulation. It is a family of processes that share a
substrate but differ in mechanism:

- **Replication** (built)
- **Transcription** (planned — central dogma)
- **Translation** (planned — central dogma)
- **PCR** (deferred — see below)

DESIGN.md already frames these as siblings: `simulation.gd` as the "Template
Manager" owning source material, with `replication_manager.gd` /
`transcription_manager.gd` / `translation_manager.gd` as sibling process
coordinators. This document pins down **what the shared parent actually owns**
versus what belongs to replication alone — the seam those siblings sit on.

Today that line is blurred: `simulation.gd` mixes genuinely universal
primitives (free-monomer solution, per-slot data, playback) with
replication-specific machinery (fork geometry, the two-template unzipping
model). The extraction cannot happen cleanly until this seam is explicit.

---

## PCR is a parallel simulation, not a mode

Worth recording the distinction that motivated this doc, because it is easy to
get wrong:

- A **mode** (e.g. prokaryotic vs. eukaryotic) reconfigures the *same*
  simulation — same fork, same timeline, same scrubber, different enzyme
  identities.
- A **parallel simulation** (transcription, translation, PCR) is its own
  process with its own timeline, end state, and visual grammar.

PCR fails the mode test on nearly every axis: no replication fork, no single
linear progression (it loops), no lagging strand, and its "done" state is an
exponential *population* rather than one finished daughter molecule. You cannot
reach PCR by re-skinning the replication fork — the tell that it is a sibling
process, not a variant.

What makes PCR fit the parallel-sim bucket is that it draws on the *same shared
substrate layer* transcription and translation will: the concentration-rich
region of free-floating monomers, template-directed 5'→3' synthesis by
complementarity, the global temperature dial, and the playback machinery. PCR
is therefore a fourth sibling process coordinator (`pcr_manager.gd` or similar),
deferred until after transcription and translation are built.

---

## The Seam

### Shared — belongs in the base layer

Owned by the common parent; every sibling process may read/use it.

- **Free-monomer solution** — the concentration-rich region, Brownian motion,
  and the free-floating-monomer mechanic currently in `nitrogen_base.gd`.
  Reused by every process (free dNTPs, free rNTPs, tRNAs/amino acids, PCR
  primers + dNTPs).
- **Sequence data + accessors** — per-slot base data and the
  `get_base()` / `get_complement()` / `get_slot_count()` interface.
- **Geometry primitives** — slot-position math (`get_slot_position()`),
  spacing, and layout constants that are not replication-fork-specific.
- **Playback** — scrub, timeline, play/stop, speed multiplier, and the
  scrub-is-always-instant invariant.
- **Global dials/lenses** — `wobble_enabled`, `temperature`,
  `atp_activation_enabled`. These already cut across everything by design.
- **Enzyme-spawning conventions** — `add_child()` before
  `set_colors()`/`set_font()`/`set_radius()`; guard signal connections with
  `is_connected()` on re-init.

### Replication-specific — must NOT leak into the base

Owned by `replication_manager.gd` / `helicase.gd`, never the shared parent.

- **Fork geometry** — the two-template unzipping model and the
  `center_y`-anchored replisome positioning.
- **Helicase-as-source-of-truth positioning** — the helicase is a *replication*
  enzyme; its role as the positioning anchor is a replication concern.
- **All synthesis-coordination logic** in `replication_manager.gd` and the
  phase state machine in `helicase.gd`.
- **Leading/lagging asymmetry** — Okazaki tiling, catch-up, the lagging
  polymerase's independent positioning. (Notably, PCR has *no* lagging strand
  and transcription/translation have no strand asymmetry at all — this is
  squarely replication's.)

---

## The Fork Test

The single sharpest check for whether the seam is drawn correctly:

> **No replication-fork logic may live in the shared base layer.**

PCR has no fork, so if fork logic sits in the shared layer, the seam is wrong.
But PCR is not needed to run this test — **transcription also has no
replication fork** (it has a transcription *bubble*, a different structure), so
transcription alone exposes any fork logic that has leaked into the shared
layer. This is why the build order works (see below): transcription tests the
seam early; PCR merely confirms it later.

---

## Design Principles for the Eventual Refactor

- **The refactor is driven by transcription and translation, not by PCR.** PCR
  is the eventual stress test, not the design input. Designing the shared base
  "for PCR" now risks over-abstracting toward a deferred process based on a
  conceptual sketch rather than real implementation friction.
- **PCR's only claim on the seam today** is a sanity check: does this boundary
  *allow* a fork-less, looping, exponential process later? It must not *require*
  anything for PCR yet.
- **Extract to serve the process being built.** When transcription design
  begins, pull shared primitives out to serve it — guided by this contract —
  rather than attempting a big-bang decomposition up front.
- **Build order** (decided): transcription → translation → PCR. Each new
  sibling validates the seam against a process that does not share replication's
  fork, tightening the shared layer before PCR has to fit it.

---

## What NOT to do yet

- Do **not** draft a detailed decomposition of `simulation.gd` now.
  Transcription and translation are still long-term roadmap items with no design
  behind them; planning the parent's exact structure against them would be
  premature.
- Do **not** move any code on the basis of this document alone. It is the
  contract the extraction must honor when it happens — the articulation of the
  boundary, not the instruction to cross it.

---

## Cross-references

- `DESIGN.md` — sibling process-manager architecture, current `simulation.gd`
  responsibilities, helicase-anchored positioning.
- `COMPLEXITY_MODEL.md` — the universal-core-vs-divergent-specifics principle
  (the biological analogue of this code seam), the global dials, and the
  PCR/in-vitro framing in fuller biological context.
