# Krebs Cycle Visual Design — initial proposal (pre-implementation)
_Design discussion, not yet implemented — a holding pen for the idea, not a
build spec. Companion to `COMPLEXITY_MODEL.md` and to the Krebs spike
already scoped in `TODO.md` / `Zymulador_Plano_de_Projeto.md` (citrate
synthase + malate dehydrogenase, wraparound-seam test)._

_Context worth keeping attached to this doc: this module's primary user is
Henrique himself — a second-year biology undergrad who, by his own account,
"barely remembers" the Krebs cycle. Zymulador's Krebs tier is first and
foremost a study tool for its own author. That's a feature for correctness
pressure (if a station feels confusing to build, it's probably wrong), not
just a funding narrative._

---

## Origin of the metaphor

Extends the train/track model already established for DNA replication
(helicase position as single source of truth, everything else derived —
same pattern this doc reuses). Improvised in conversation, not yet checked
against a real platform-by-platform mechanism map — treat the specific
platform contents below as placeholders for the shape of the idea, not a
verified station list.

---

## Core mechanic: gears, not just a track

Unlike DNA replication's single linear/circular track, Krebs is proposed as
a **big main gear driving smaller sub-gears**, one per enzymatic step
(station). This is real gear-ratio math, not decorative chrome — confirmed
in discussion.

**Proposed derivation rule, to avoid the "two independently-tuned numbers
coincidentally agree" trap:** a station's sub-gear tooth count should equal
its platform count, so one main-gear tooth engaging the sub-gear is *by
construction* one platform advance. Arc length, teeth count, and platform
count all fall out of the single number that actually matters (platform
count) instead of three separately-tuned values that happen to line up
today and drift out of sync later.

This also gives scrub-safety the same way the Okazaki maturation rule does:
molecular state only updates at platform boundaries (tooth-to-tooth), never
mid-tooth. Scrubbing mid-station should never render a half-attached
substrate.

**Open question, not yet resolved:** is the train (the acetyl-CoA-derived
carbon skeleton) the literal "same molecule" that gets relabeled at each
station boundary, or does the visual system need an explicit relabel/morph
event? Krebs is **not** a branching detour-and-return system like Okazaki
fragments — it's a single continuous one-way transformation chain. Nothing
should imply the train leaves the main line and comes back *unchanged*.

---

## Stations and platforms

- **Station** = one enzymatic step of the cycle (8 total in the full
  cycle — citrate synthase, aconitase, isocitrate dehydrogenase, α-KG
  dehydrogenase, succinyl-CoA synthetase, succinate dehydrogenase, fumarase,
  malate dehydrogenase).
- **Platform** = one discrete sub-step within a station, the same role a
  nucleotide slot plays for the helicase. Bigger/busier stations (more
  reactants/products entering or leaving) get more platforms and therefore a
  longer loop and a bigger sub-gear.
- Platforms are where atoms, electron carriers, or CoA groups are added to
  or removed from the train. The train's *visual identity* (its molecule
  label/shape) changes as it crosses platform boundaries within a station,
  and again when it exits onto the main line as the next named intermediate.

**Worked (draft, unverified) example — α-ketoglutarate dehydrogenase,**
correcting the initial improvised platform order against the real E1/E2/E3
mechanism:

1. α-ketoglutarate binds; TPP-mediated decarboxylation releases **CO₂**
   almost immediately — this happens *before* CoA is involved.
2. The remaining 4-carbon fragment is handed to lipoamide (E2), which also
   binds **CoA-SH**, releasing **succinyl-CoA**.
3. Reduced lipoamide is reoxidized by E3, passing electrons through FAD to
   **NAD⁺ → NADH + H⁺**, released last.

So platform order for this station is **CO₂ out → CoA in → NADH out**, not
CoA-first as originally improvised. Same three-subunit (E1/E2/E3) mechanism
as pyruvate dehydrogenase, which may be worth reusing visually once/if
glycolysis is ever built, given the shared TPP → lipoamide → FAD/NAD⁺ relay.

**Standing rule this station raised, not yet decided:** should platform
order always follow literal mechanism order, or is a pedagogically-clarified
order acceptable for stations where the real order is confusing to display?
This will recur at every multi-platform station and should be decided once,
not per-station.

---

## Geography: cytosol, mitochondrion, and sub-regions

Krebs introduces a compartment the DNA replication track never needed to
represent: the cycle runs in the **mitochondrial matrix**, but its substrate
(pyruvate, and by extension the acetyl-CoA that feeds the cycle) originates
in the **cytosol** via glycolysis. A geography layer is proposed to make that
crossing legible rather than implicit:

- **Cytosol region** — where pyruvate exists post-glycolysis (upstream of
  this module's current scope, but the geography should leave room for it
  as a future feeder, per the Plano's glycolysis-is-also-level-1-2 note).
- **Mitochondrion, outer membrane** — freely permeable; likely not worth a
  distinct visual gate.
- **Mitochondrion, inner membrane** — the real checkpoint. Pyruvate crosses
  via the mitochondrial pyruvate carrier; this is a legitimate place for a
  "crossing" visual beat (a gate/lock the train passes through), separate
  from the gear-track mechanic proper.
- **Matrix** — where the main gear and all eight stations physically live.
  This is the only region where the Krebs gear-track itself is drawn.

Proposed framing, consistent with the labeled-chimera principle already
governing DNA topology: the compartment boundary is not decorative set
dressing, it's the reason pyruvate dehydrogenase (the pyruvate → acetyl-CoA
link reaction, technically upstream of and distinct from the Krebs cycle
proper) exists as a separate gating step before the main gear can start
turning. Whether PDH gets its own small gear feeding into the main one, or
is treated as a simple "entry lock," is an open question below.

---

## Open questions

1. Is the main-gear/sub-gear ratio meant to be visually apparent (student
   can see "this station takes longer/does more") or normalized for even
   pacing? Ties directly to the teeth = platforms derivation above.
2. Relabeling mechanic: does the train sprite morph continuously across
   platforms, or snap-relabel at each platform boundary? Scrub-safety favors
   the latter (discrete states only), matching the Okazaki precedent.
3. Mechanism-order vs. pedagogical-order for platform sequencing within a
   station — needs a single standing rule, not a per-station judgment call.
4. Does pyruvate dehydrogenase (the link reaction) get modeled as its own
   station/gear, or folded into an "entry lock" at the inner membrane
   crossing? It's chemically a separate enzyme complex, not part of the
   cycle proper — mislabeling it as "station 1 of Krebs" would repeat the
   kind of conflation this project has caught before (SSB/shelterin).
5. CO₂ and GTP/ATP byproducts leaving the train at various stations — do
   they get their own small branch-off visual (consistent with "platforms
   remove atoms"), and if so, does that need its own scrub-safety rule the
   way Okazaki fragment completion does?

---

## Scope reminder

The only thing currently committed to a timeline is the two-enzyme spike
already scoped elsewhere (citrate synthase + malate dehydrogenase, testing
the fusion event and the wraparound/regeneration seam) — and that spike is
explicitly meant to stay a *teste preliminar*, not a fully worked-out
station model. This document is a holding pen for the fuller gear/station/
geography idea so it isn't lost before then, not a spec to build against.
