# Zymulador — The Shared Base Layer Seam

_Design contract. Companion to DESIGN.md and COMPLEXITY_MODEL.md. Articulates
the boundaries between what is **universal** across every Zymulador
simulation, what is **shared within the nucleotide-family** siblings
specifically, and what is **specific to DNA replication alone** — so that
any future extraction of a common base layer has a target to honor. This is
a contract, not a refactor plan._

---

## Why this exists

Zymulador is not one simulation, and it is no longer even one *family* of
simulations. Two substrate families exist today:

- **Nucleotide-family** — processes that share a free-monomer solution,
  sequence data, and template-directed synthesis: **Replication** (built),
  **Transcription** (planned), **Translation** (planned), **PCR**
  (deferred).
- **Non-nucleotide** — processes that share none of that substrate, but
  share the same underlying regent-driven derivation discipline:
  **Na⁺/K⁺ pump** (spike, proof-of-concept for exactly this generalization
  question), **Krebs cycle** (flagship, software spike + physical model
  both in design).

The Na⁺/K⁺ pump spike exists specifically to answer the question this seam
raises: does the "one monotonic regent counter, everything else derived"
pattern hold outside DNA/RNA at all, on a domain with zero sequence
machinery? It does — `pump_step % NUM_PHASES` derives an arbitrary scrub
target instantly, the same invariant `helicase_mgr.current_slot_index`
already guarantees, on a substrate that has no slots, no bases, no
free-monomer solution. That result is why the tier structure below has a
universal layer above the nucleotide-specific one, not just a wider list of
siblings under the same shared layer.

DESIGN.md already frames the nucleotide-family siblings as coordinators
under `simulation.gd`'s Template Manager role. Krebs and the pump don't fit
that role — there's no template to manage — so they sit beside it as
independent regent-driven simulations that happen to obey the same
top-tier contract, not children of `simulation.gd`.

Today the nucleotide-family line is still blurred the way this doc
originally described: `simulation.gd` mixes genuinely universal primitives
with replication-specific machinery. That extraction is still deferred
until transcription/translation design begins. What's new is that the
*universal* primitives are no longer fully described by "what
`simulation.gd` currently does" — some of them (the regent-derivation rule
itself, the scrub-is-instant invariant, the toggle-cascade conventions)
live correctly today in places `simulation.gd` never touches, like
`helicase_atp_cycle.gd` and the pump spike's own `pump_step` logic.

---

## PCR is a parallel simulation, not a mode

Worth recording the distinction that motivated this doc, because it is easy
to get wrong:

- A **mode** (e.g. prokaryotic vs. eukaryotic) reconfigures the *same*
  simulation — same fork, same timeline, same scrubber, different enzyme
  identities.
- A **parallel simulation** (transcription, translation, PCR, Krebs, the
  pump) is its own process with its own timeline, end state, and visual
  grammar.

PCR fails the mode test on nearly every axis: no replication fork, no
single linear progression (it loops), no lagging strand, and its "done"
state is an exponential *population* rather than one finished daughter
molecule. You cannot reach PCR by re-skinning the replication fork — the
tell that it is a sibling process, not a variant.

What makes PCR fit the nucleotide-family bucket specifically (unlike Krebs
or the pump) is that it draws on the *same shared substrate layer*
transcription and translation will: the concentration-rich region of
free-floating monomers, template-directed 5'→3' synthesis by
complementarity, the global temperature dial, and the playback machinery.
PCR is therefore a fourth nucleotide-family sibling coordinator
(`pcr_manager.gd` or similar), deferred until after transcription and
translation are built.

---

## The Seam — three tiers

### Tier 1 — Universal (every Zymulador simulation, any substrate)

Owned by no single process; every sibling, nucleotide-family or not, is
expected to obey this tier's contract even though nothing here is
necessarily one shared codebase yet.

- **The regent-derivation rule.** One monotonically increasing counter is
  the sole source of truth; everything else is a pure function of it,
  computed live, never stored or accumulated imperatively. Proven across
  three genuinely different regent shapes now: a clamped spatial position
  (`helicase_mgr.current_slot_index`), a finite externally-reset state
  machine (`ligase.gd`'s IDLE→TRAVELING→HOLDING→SEALING), and an unclamped
  self-sustaining cycle requiring modulo arithmetic
  (`pump_step % NUM_PHASES`). Krebs's `station_index`/`platform_index` is
  the same shape as the pump's, one level up.
- **Scrub-is-always-instant.** Jump to any regent value; the rendered state
  snaps immediately and correctly with zero dependence on animation
  history. This is the specific invariant the pump spike's `pump_step = 47`
  test case exists to prove holds outside DNA.
- **Trigger philosophy follows from the scrub contract, not from the
  enzyme.** Found while building the ATP cofactor lens across helicase and
  ligase (STATUS.md, ATPCycleDesign.md): helicase's cycle is clock-driven
  because it's never hidden during scrub and must reconstruct instantly;
  ligase's is event-count-gated because it's fully hidden during scrub and
  inherits no reconstruct-instantly contract. The two enzymes share a
  glyph vocabulary and a toggle but zero timing machinery — they did NOT
  want to be unified into one mechanism once actually built. The
  generalizable rule: ask what scrub requires of a given piece of state
  first, and the correct trigger mechanism falls out. This applies as much
  to Krebs's stations and the pump's phases as it did to the two enzymes
  that surfaced it.
- **Complexity-toggle conventions.** `ComplexityManager`'s bridge-toggle
  cascade pattern, `is_enabled()`/`set_X_enabled()` shape, and the
  default-follows-parent/override-persists cascade rule (COMPLEXITY_MODEL.md)
  apply to any process with tiered complexity, not just replication's.
- **Enzyme/object-spawning conventions.** `add_child()` before
  `set_colors()`/`set_font()`/`set_radius()`; guard signal connections with
  `is_connected()` on re-init. Substrate-agnostic Godot lifecycle discipline.
- **"Never let two independently-tuned numbers coincidentally agree."**
  Any value derivable from the regent must be derived, not paralleled by a
  second hand-tuned value that merely happens to match today.

### Tier 2 — Nucleotide-family shared (replication / transcription / translation / PCR only)

Owned by the common parent (`simulation.gd`'s Template Manager role, or its
eventual extraction); every nucleotide-family sibling may read/use it.
**Does not apply to Krebs or the pump** — there is no template, no sequence,
no free-monomer solution on either of those substrates.

- **Free-monomer solution** — the concentration-rich region, Brownian
  motion, and the free-floating-monomer mechanic currently in
  `nitrogen_base.gd`. Reused by every nucleotide-family process (free
  dNTPs, free rNTPs, tRNAs/amino acids, PCR primers + dNTPs).
- **Sequence data + accessors** — per-slot base data and the
  `get_base()` / `get_complement()` / `get_slot_count()` interface.
- **Geometry primitives** — slot-position math (`get_slot_position()`),
  spacing, and layout constants that are not replication-fork-specific.
- **Playback** — scrub, timeline, play/stop, speed multiplier. (The
  scrub-is-always-instant *invariant* itself is Tier 1; this is the
  nucleotide-family-specific playback plumbing that implements it.)
- **Global dials/lenses** — `wobble_enabled`, `temperature`,
  `atp_activation_enabled`. These already cut across the nucleotide family
  by design; whether any of them also make sense for Krebs (temperature,
  plausibly) or the pump is an open question, not yet decided either way.

### Tier 3 — Replication-specific — must NOT leak into Tier 1 or Tier 2

Owned by `replication_manager.gd` / `helicase.gd`, never a shared parent.

- **Fork geometry** — the two-template unzipping model and the
  `center_y`-anchored replisome positioning.
- **Helicase-as-source-of-truth positioning** — the helicase is a
  *replication* enzyme; its role as the positioning anchor is a
  replication concern, not evidence that Tier 1's regent-derivation rule
  requires a spatial anchor (the pump spike is the proof it doesn't).
- **All synthesis-coordination logic** in `replication_manager.gd` and the
  phase state machine in `helicase.gd`.
- **Leading/lagging asymmetry** — Okazaki tiling, catch-up, the lagging
  polymerase's independent positioning. (Notably, PCR has *no* lagging
  strand and transcription/translation have no strand asymmetry at all —
  this is squarely replication's, within the nucleotide family too.)

---

## The Fork Test — and its generalization

The original sharpest check for whether the nucleotide-family seam is drawn
correctly:

> **No replication-fork logic may live in Tier 2.**

PCR has no fork, so if fork logic sits in Tier 2, the seam is wrong. But
PCR is not needed to run this test — **transcription also has no
replication fork** (it has a transcription *bubble*, a different
structure), so transcription alone exposes any fork logic that has leaked
into Tier 2.

**The generalized version, for Tier 1:** no nucleotide-family assumption
(sequence, template, free-monomer solution) may live in Tier 1. The Na⁺/K⁺
pump is this test's non-nucleotide equivalent of what transcription is for
Tier 2 — it has no sequence, no template, no bases, and the regent pattern
held anyway. Krebs will run the same test again on a third substrate
(carbon-skeleton transformation) once its spike ships.

---

## Design Principles for the Eventual Refactor

- **The Tier 2 refactor is driven by transcription and translation, not by
  PCR.** Unchanged from the original reasoning: PCR is the eventual stress
  test for Tier 2, not the design input.
- **Krebs and the pump do not wait on the Tier 2 refactor.** They never
  touch Tier 2 at all — nothing about `simulation.gd`'s eventual
  decomposition blocks or is blocked by either of them. Their only
  dependency is Tier 1, which already exists in practice (helicase, ligase,
  the pump spike) even though it has never been extracted into a literal
  shared file.
- **Extract Tier 1 to serve the process that needs it named, not
  speculatively.** The pump spike already validated Tier 1's shape without
  requiring a real extraction — `pump_step`'s logic lives entirely in the
  pump's own script today, obeying the contract by discipline, not by
  inheritance. Whether Tier 1 ever becomes a literal shared file/autoload,
  versus staying a convention every new sibling is written to follow, is
  an open question — not yet decided, and not urgent while the sibling
  count is small enough that drift would be easy to spot.
- **Build order** (nucleotide-family, unchanged): transcription →
  translation → PCR. **Krebs is the flagship non-nucleotide build**,
  already underway (software spike scoped, physical model in Lattice
  phase) — it does not sit in this ordered list because it isn't
  competing for the same Tier 2 seam transcription/translation/PCR are.

---

## What NOT to do yet

- Do **not** draft a detailed decomposition of `simulation.gd` now.
  Transcription and translation are still long-term roadmap items with no
  design behind them; planning the parent's exact structure against them
  would be premature.
- Do **not** move any code on the basis of this document alone. It is the
  contract the extraction must honor when it happens — the articulation of
  the boundary, not the instruction to cross it.
- Do **not** assume Tier 1 needs a literal shared file before a third
  non-nucleotide sibling (Krebs) has actually tested it. Two data points
  (helicase/ligase's ATP lens, the pump spike) support the tier existing
  conceptually; whether it needs code of its own is still open.

---

## Open questions carried forward by this revision

- Does `temperature` (currently Tier 2) actually belong in Tier 1? Krebs
  enzyme kinetics are temperature-sensitive in the same real sense
  replication's are — this may be a Tier 2 dial that's actually universal
  and was only ever tested against nucleotide-family processes so far.
- Does Tier 1 ever get a literal home (an autoload, a base scene, a
  documented-but-uninherited convention file), or does it stay a discipline
  every new sibling's design doc is individually checked against, the way
  this document already does for the pump and will for Krebs?
- `PhysicalKrebsDesign.md`'s scrub-safety answer (software stays
  instant-authoritative, the physical rig visibly travels without ever
  rendering a mislabeled mid-state) is a genuine *weakening* of the Tier 1
  scrub-is-instant invariant for one output channel (the physical rig)
  while the software regent itself keeps the invariant unweakened. Worth
  deciding whether that's a Tier 1 amendment (a hardware-output exception,
  named explicitly) or stays scoped as PhysicalKrebsDesign.md's own
  concern, since it's the first sibling to touch a non-software output at
  all.

---

## Cross-references

- `DESIGN.md` — nucleotide-family process-manager architecture, current
  `simulation.gd` responsibilities, helicase-anchored positioning.
- `COMPLEXITY_MODEL.md` — the universal-core-vs-divergent-specifics
  principle (the biological analogue of this code seam), the global dials,
  and the PCR/in-vitro framing in fuller biological context.
- `NaKPumpSpikeDesign.md` — the spike that motivated Tier 1's existence as
  a distinct layer from Tier 2.
- `ATPCycleDesign.md` / `STATUS.md` — source of the trigger-philosophy
  principle folded into Tier 1.
- `KrebsCycleDesign.md` / `PhysicalKrebsDesign.md` — the flagship
  non-nucleotide sibling this tier structure is written to support.
