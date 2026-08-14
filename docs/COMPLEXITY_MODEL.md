# Zymulador — Complexity Model & The Chimera Decision
_Design document. Companion to DESIGN.md. Maps the full palette of DNA
replication components Zymulador could model, the organizing principle for
choosing among them, and how the complexity toggles relate to one another._

---

## The Core Decision: A Labeled Chimera

Zymulador originally adopted the **E. coli** model for its clean, well-characterized
replisome body. For a didactic tool, though, the most useful model is not any
single organism but a deliberate **chimera** — one that pulls the clearest
illustration of each concept from whichever domain of life shows it best.

The hazard of a chimera is teaching a "Frankenstein organism" that a student
walks away believing is real — over-generalizing a domain-specific detail as
universal. The mitigation is not to avoid mixing; it is to **label the seams**.

This produces the organizing principle for the entire complexity system:

### Two layers, only one of which mixes freely

**Universal core (the shared trunk).** True across all cellular life. Can be
shown organism-agnostically with no label, because nothing false is absorbed:

- Unwinding of the duplex into a replication fork
- Antiparallel template strands
- Synthesis only ever 5'→3'
- Leading strand continuous, lagging strand discontinuous
- Okazaki fragments on the lagging strand
- RNA primers preceding synthesis
- Ligation of fragments
- Proofreading (3'→5' exonuclease)
- Mismatch repair

**Divergent specifics (labeled branches).** Domains genuinely differ here.
Showing these *unlabeled* is itself teaching a falsehood, so each must carry a
"this is how [bacteria / eukaryotes] do it" tag when displayed:

- Chromosome topology (circular vs. linear)
- Number of origins
- Exact enzyme identities
- Which strand the helicase encircles
- Ligase cofactor (NAD⁺ vs. ATP)
- End-of-chromosome behavior (fork fusion vs. telomeres)
- Chromatin / nucleosome packaging

### Topology is the spine — it gates coherence

The single most important structural constraint: **chromosome topology is not
free to mix.** A molecule cannot be simultaneously circular (forks meet, no
ends) and linear (has ends requiring telomere maintenance).

This matters because Zymulador's *current* roadmap is already chimeric in a way
that quietly conflicts:

- The **telomere gap / telomerase tier** (`lagging_gap_enabled`) is a
  **linear-chromosome, eukaryotic** concept. The end-replication problem only
  exists because a linear chromosome has ends the lagging strand cannot finish
  after the terminal primer is removed.
- **Tus–Ter termination** and the **single-origin trombone-loop replisome**
  (both pulled from E. coli) are **circular-chromosome** mechanics — two forks
  leaving one origin and meeting in the middle of a loop.

These cannot describe the same molecule. Topology therefore sits **above** the
enzyme graph and gates which end-game modules are even coherent:

| Aspect | Circular (bacterial) | Linear (eukaryotic) |
| --- | --- | --- |
| Origins | one (oriC) | many |
| End behavior | forks meet at Tus–Ter trap | telomere gap → telomerase |
| Telomere tier | **incoherent** | **required** |
| Tus–Ter tier | required | **incoherent** |

**Recommendation — now shipped:** topology / domain is an explicit top-level
mode (`topology_mode`, CIRCULAR/LINEAR), gating the end-game modules, with the
universal core as the shared trunk both modes draw from. Embrace the chimera
for the universal core; never silently blend circular and linear mechanics.
See the Mode-gate pattern under Cascading UI behavior for the shipped cascade
mechanics.

This retroactively resolves two earlier open questions:

- **Ligase cofactor** stops being an awkward exception. Bacterial ligase runs
  on NAD⁺; eukaryotic ligase runs on ATP. It becomes a labeled divergent-
  specific, and the ATP-activation lens (below) correctly lights up ligase
  *only in eukaryotic mode*.
- **Chromatin** becomes the signature eukaryotic-mode visual with no bacterial
  counterpart to reconcile.

---

## The Full Component Palette

Everything Zymulador could model, by replication stage. `[✓]` already in DESIGN.md,
`[~]` planned/mentioned, `[NEW]` surfaced during this mapping and not previously
scoped.

### Stage 1 — Initiation `[NEW — absent from DESIGN.md]`
DESIGN.md currently starts mid-elongation with the fork already open.

- **Origin (oriC)** — a defined origin; cooperative binding of the initiator
  melts an A:T-rich stretch open. Bacterial: single origin. Eukaryotic: many.
- **Initiator protein** — bacterial **DnaA** (ATP-bound form fires the origin;
  ADP-bound is inactive); eukaryotic **ORC + Cdc6 + Cdt1**.
- **Helicase loading** — bacterial DnaB loaded as a DnaB₆–DnaC₆ complex;
  eukaryotic MCM2-7 loaded as an inactive double hexamer, later activated into
  CMG (Cdc45 + MCM2-7 + GINS).
- **Bidirectionality** — two replisomes leave the origin in opposite directions.

### Stage 2 — Elongation `[the heart of the current sim]`

- **Helicase** `[✓]` — bacterial DnaB (encircles the *lagging* template);
  eukaryotic CMG (encircles the *leading* template). A labeled divergence.
- **SSB / single-strand binding protein** `[NEW]` — coats exposed ssDNA,
  protecting it and blocking spurious re-priming. Decorates the unzipped-but-
  not-yet-copied stretch. Bacterial SSB; eukaryotic RPA.
- **Primase** `[~]` — bacterial DnaG (associates transiently); eukaryotic
  Pol α-primase (integral to the replisome). Fueled by ribonucleotide substrate,
  not ATP-as-cofactor.
- **Leading + lagging replicative polymerase** `[✓]` — bacterial Pol III (both
  strands); eukaryotic Pol ε (leading) + Pol δ (lagging). Fueled by incoming
  dNTP substrate (each dNTP is itself a triphosphate; pyrophosphate released on
  incorporation), *not* by ATP pickup.
- **Sliding clamp + clamp loader** `[~]` — bacterial β-clamp + τ/γ complex;
  eukaryotic PCNA + RFC. The clamp loader is ATP-driven.
- **Topoisomerase / gyrase** `[NEW]` — relaxes supercoiling ahead of the fork.
  Works at its own distinct location (ahead of the fork, not at it). Gyrase is
  ATP-driven. Sibling to the polymerases; depends only on the fork existing.

### Stage 3 — Okazaki Maturation `[Built — see OkazakiMaturationDesign.md]`

- **Primer removal** `[✓ — bridges the primase and ligase tiers, the first
  shipped "bridge toggle" cascade — see Cascading UI behavior below]` —
  bacterial Pol I performs nick-translation (5'→3' exonuclease removes RNA
  primer while the polymerase fills DNA behind it), assisted by RNase H
  (not separately modeled — see OkazakiMaturationDesign.md). A distinct
  enzyme visit between primase and ligase, one fragment behind Pol III's
  own progress.
- **Ligase** `[✓]` — seals the nick. **Bacterial ligase uses NAD⁺; eukaryotic
  ligase uses ATP** — a labeled divergent-specific, not a bug in the ATP lens.

### Stage 4 — Termination `[NEW — absent from DESIGN.md]` (circular mode only)

- **Tus–Ter replication fork trap** — polar Tus–Ter blocks let replisomes enter
  but not leave a termination region, so the two forks meet at a defined spot.
  Tus acts as a "contrahelicase," impeding unwinding in one orientation only.
  A satisfying visual payoff: a stop-sign the helicase runs into.
  **Coherent only in circular topology.**

### Stage 5 — Fidelity & Damage Tolerance

- **Proofreading (3'→5' exonuclease)** `[~ layer 6]` — richer than "catches
  errors": a misincorporated base fails the pairing check, the polymerase
  backtracks, the primer end unwinds a few bases and shuttles to a separate
  exonuclease site for removal, then returns. The pol-site → exo-site shuttle
  is animatable.
- **Mismatch repair (MMR)** `[~ layer 7]` — full cast: MutS (recognizes
  mismatch), MutL, MutH (nicks the strand), UvrD helicase, exonucleases, SSB,
  ligase, Pol III. Strand discrimination is the clever, teachable part:
  newly-made DNA is transiently unmethylated, so MutH nicks the unmethylated
  (presumed-incorrect) strand at hemimethylated GATC sites. Needs only "errors
  exist."
- **Translesion synthesis (TLS)** `[NEW — a whole damage-response branch]` — see
  the dedicated section below. Needs the stronger precondition "unreadable
  damage exists."

---

## The Polymerase Zoo & Translesion Synthesis

E. coli alone has **five** DNA polymerases. Zymulador currently models Pol III
(as leading/lagging polymerase) and Pol I (primer removal, as a real
Complex-tier node — see OkazakiMaturationDesign.md). The other three are not
backup replicases — they are a **DNA-damage rescue crew** and constitute a
complexity branch Zymulador has no representation of at all.

| Polymerase | Role | Fidelity | In Zymulador |
| --- | --- | --- | --- |
| Pol I | Primer removal, gap fill (nick translation) | High | `[✓]` built — see OkazakiMaturationDesign.md |
| Pol II | SOS-induced fork rescue | — | `[NEW]` |
| Pol III | The chromosomal replicase | High (proofreads) | `[✓]` |
| Pol IV (DinB) | Translesion; restarts stalled forks | Low (no proofreading); ~5–10× more accurate than Pol V | `[NEW]` |
| Pol V (UmuD'₂C) | Translesion specialist | Very low; error rate ~10⁻³–10⁻⁴ | `[NEW]` |

When Pol III hits a lesion it cannot read through, it stalls and the fork risks
collapse. The SOS response induces Pol II/IV/V to push through the damage,
trading fidelity for continuity. Pol V is notably regulated: it cannot bind DNA
until it forms a "mutasome" with a RecA filament and ATP.

**Why this is a distinct branch, not more polymerase toggles.** It introduces a
prerequisite chain Zymulador does not yet have:

```
DNA Damage / Lesion  [NEW mechanic — a base Pol III literally cannot read past]
└─ SOS Response      [NEW mechanic — the trigger that makes Pol IV/V available]
   └─ Pol III stalls at the lesion
      └─ Pol IV / Pol V swaps in for that stretch
         └─ Lesion bypassed (correctly or mutated, per the error mechanic)
         └─ Pol III resumes
```

This differs from Proofreading/MMR, which both need only "errors exist." TLS
needs "unreadable *damage* exists" — a stronger, rarer condition. It is a
**damage-tolerance** system, not a repair system, and sits as a sibling branch
after MMR in complexity.

**Toolbelt visual hook.** The sliding clamp can hold multiple polymerases at
once — when Pol III stalls, Pol IV takes control of the clamp and the template;
when the block clears, Pol III regains it. A literal polymerase hand-off on the
same clamp, which maps cleanly onto the sliding-clamp visual once built.

---

## Cross-Cutting Lenses & Dials

These are **not nodes in the enzyme dependency tree.** They cut across it, like
the existing `wobble_enabled` toggle. Two kinds:

### Visual lenses (on/off, no simulation-logic change)

**`atp_activation_enabled`** — shows the little ATP blob (three-phosphate tail,
visually distinct from a single-phosphate free nucleotide) docking onto and
fueling the enzymes that actually run on ATP, releasing ADP + Pᵢ as a byproduct.

Crucially, this is a *second, distinct fuel mechanic* from the substrate-
incorporation already in `nitrogen_base.gd`. Two different models that must not
be visually conflated:

1. **Substrate incorporation** (already built) — Pol III / primase pick free
   nucleotides from solution and the nucleotide *becomes part of the product*.
   A consumption mechanic.
2. **Cofactor activation** (this lens) — the enzyme picks up ATP, spends it on a
   conformational change, and *discards* it as ADP + Pᵢ. The ATP becomes part of
   nothing.

Who lights up under this lens:

```
atp_activation_enabled (sibling to the whole enzyme tree)
├─ Helicase             → consumes ATP → ADP+Pᵢ per step (cleanest case)
├─ Clamp loader         → consumes ATP per clamp load   (needs clamp toggle)
├─ Topoisomerase/gyrase → consumes ATP                  (needs topo toggle)
├─ Pol V mutasome       → requires ATP + RecA to activate (needs TLS toggle)
├─ DnaA                 → requires ATP-bound state to fire origin (needs init toggle)
└─ Ligase               → ATP ONLY in eukaryotic mode (bacterial ligase = NAD⁺)

Explicitly NOT ATP-fueled: Pol III, primase (substrate-fueled),
                           bacterial ligase (NAD⁺).
```

### Continuous drivers (read/modify state other systems own)

**`temperature`** — a global dial, alongside `wobble_enabled`. Unlike ATP (a
pure visual lens), temperature actively reads and modifies simulation state.
Two regimes:

- **Too cold** — kinetic slowdown: Brownian motion of free nucleotides/ATP
  slows, enzyme step-rate slows (ties into existing `speed_multiplier` and
  wobble amplitude), approaching a frozen floor.
- **Too hot** — thermal denaturation: hydrogen bonds spontaneously break,
  **starting at AT-rich slots first** (2 H-bonds) before GC (3 H-bonds),
  independent of helicase position. This is real and teachable — it is the
  first step of PCR — and reuses data the sim already has (the per-slot base
  identity). Melting temperature rises ~0.4 °C per 1% increase in GC content.
  (Optional deeper layer: at extreme heat the *enzymes* denature too — the real
  reason PCR needs a heat-stable polymerase, a possible future "thermostable
  polymerase" aside.)

**Architectural note — the one conflict to resolve at implementation.** Even as
a global dial, temperature can open a base pair the helicase has not reached.
This brushes against the "helicase is the single source of truth for replisome
positioning" invariant. Resolution: temperature does **not** reposition the
helicase; it adds a **second, independent gate** on per-slot hydrogen-bond /
wobble state — a slot reads as *bonded* unless (helicase has passed) **or**
(thermally melted). The positioning rule stays intact; the helicase simply is
no longer the *only* thing that can open a pair. Pin this down precisely when
temperature is implemented.

---

## The Enzyme Dependency Tree

Relationship types:

- **Hard requires** — child is meaningless if parent is off; must auto-disable.
- **Soft recommends** — works alone but loses explanatory point without the other.
- **Shares a mechanic** — both read/write the same underlying state; not parent/child.
- **Sibling** — freely combinable, no relation.
- **Bridge toggle** — couples two siblings that are each independently
  meaningful alone but jointly required for the bridge itself to make
  sense; cascades both directions (on force-enables both sides, either
  side off force-disables the bridge) — see Cascading UI behavior below.
- **Mode-gate** — not a parent/child at all, but a top-level *mode* (topology)
  whose value determines which end-game modules are even coherent. Switching
  to a mode force-disables the module the other mode owns; switching *into* a
  mode does not auto-enable that mode's module (the choice stays deliberate).
  The shipped case is `topology_mode` gating Telomerase (linear) vs. Tus–Ter
  (circular) — see Cascading UI behavior below.

```
[MODE: Chromosome topology / domain]  — top-level context, gates the branches
│
Helicase (root — off = fully static DNA)
├─ SSB                         (needs Helicase; sibling to polymerases)
├─ Topoisomerase / gyrase      (needs Helicase; sibling to polymerases)
├─ Leading Polymerase          (needs Helicase)
│    └─ Leading Proofreading   (needs Leading Polymerase)
├─ Lagging Polymerase          (needs Helicase)
│    ├─ Ligase                 (needs Lagging Polymerase; BRIDGED by Primer removal)
│    ├─ Telomerase / gap       (needs Lagging Polymerase + LINEAR mode;
│    │                          gap mechanic BUILT, enzyme visual designed-not-built;
│    │                          force-enables Shelterin once built)
│    │    └─ Shelterin         (telomere-end protection; force-enabled by
│    │                          Telomerase — NEW, not built. NOT the same as SSB,
│    │                          which is general and a sibling above)
│    ├─ Primase                (needs Lagging Polymerase; soft-recommends Telomerase
│    │                          for the end-of-strand story; BRIDGED by Primer removal)
│    ├─ Primer removal (Pol I) (BRIDGE TOGGLE — turning ON force-enables Primase
│    │                          AND Ligase; either one turning OFF force-disables
│    │                          this. Built — see OkazakiMaturationDesign.md)
│    ├─ Lagging Proofreading   (needs Lagging Polymerase)
│    └─ Trombone loop          (needs Lagging Polymerase)
│         └─ Full replisome / clamps / τ body (needs Trombone loop)
├─ Termination (Tus–Ter)       (needs Helicase + CIRCULAR mode)
│
└─ Fidelity branch
     ├─ Error generation       (shared substrate — no toggle of its own yet)
     │    ├─ Proofreading      (reads Error generation)
     │    └─ Mismatch repair   (reads Error generation)
     └─ Damage tolerance
          ├─ Lesion + SOS      (NEW mechanics — "unreadable damage exists")
          └─ Translesion (Pol IV/V)  (needs Lesion + SOS)

Cross-cutting (NOT in the tree): wobble_enabled, atp_activation_enabled, temperature
```

### Cascading UI behavior

- Turning a parent **off** auto-disables and grays out all dependents.
- Turning a child **on** does **not** silently auto-enable its parent — gray out
  disabled children with a tooltip explaining the prerequisite, so the parent
  choice stays deliberate.
- **Bridge toggle** (third pattern, alongside the two above) — a toggle whose
  entire reason to exist is *coupling* two siblings that are each
  independently meaningful alone, but jointly required for the toggle
  itself to make sense. Cascades in **both** directions, asymmetrically:
  turning the bridge **on** force-enables both siblings (a deliberate
  exception to the "child doesn't auto-enable parent" rule above — there is
  no valid intermediate state where the bridge is on but a sibling isn't);
  turning **either sibling off** force-disables the bridge (the standard
  rule, applied normally). First shipped case: `pol1_enabled` bridges
  `primase_enabled` and `ligase_enabled` — nothing for Pol I to remove
  without a primer existing, nothing for ligase to seal without Pol I
  finishing (see `OkazakiMaturationDesign.md`'s Cascade logic section for
  the full account, and `complexity_manager.gd`'s `set_pol1_enabled()` for
  the shipped implementation). Anticipated second case: the clamp
  loader / sliding clamps pairing, once built — clamp loader is meaningless
  without clamps to load, and clamps at that tier are meaningless without a
  loader putting them there.
- **Mode-gate** (fourth pattern, alongside the three above) — a top-level
  *mode* rather than an enzyme toggle, whose value gates which end-game
  modules are coherent at all. Cascades asymmetrically, mirroring the two
  hierarchy rules above but applied to a mode: switching to a mode
  force-disables the module the *other* mode owns (like "parent off disables
  dependents"); switching *into* a mode does **not** auto-enable that mode's
  own module (like "child on doesn't auto-enable parent" — the module choice
  stays deliberate). **Shipped:** `topology_mode` (CIRCULAR/LINEAR, default
  CIRCULAR). Switching to CIRCULAR force-disables `lagging_gap_enabled`;
  switching to LINEAR only *ungrays* the telomerase checkbox, it doesn't flip
  it on. `is_enabled("lagging_gap")` folds the mode check in so no downstream
  caller needs to know topology exists, and a `topology_changed` signal keeps
  the UI in sync — see `complexity_manager.gd`'s `set_topology_mode()` and
  STATUS.md's Telomerase Tier section for the shipped implementation. The
  mirror case (Tus–Ter grayed out in linear) applies once Tus–Ter is built.
- With ~18 possible toggles the raw 2ⁿ combination space is not QA-able. Pair
  the open matrix with a small set of tested **named presets**, e.g.
  "Leading-only," "Base replisome," "With repair," "Full trombone replisome,"
  "Eukaryotic fork," which are the guaranteed-tested paths.

---

## Toggle Registry

Flat registry of every candidate toggle. `requires` / `conflicts` capture the
sparse relationships; a full N×N matrix would be mostly empty.

| Toggle | Category | Requires | Conflicts / mode-gate | Status |
| --- | --- | --- | --- | --- |
| topology_mode | Top-level mode | — | — | ✓ (shipped — mode-gate pattern) |
| helicase | Enzyme (root) | — | — | ✓ (implicit always-on today) |
| ssb | Enzyme | helicase | — | NEW (next up — prerequisite for telomerase visual) |
| topoisomerase | Enzyme | helicase | — | NEW |
| leading_polymerase | Enzyme | helicase | — | ✓ |
| lagging_polymerase | Enzyme | helicase | — | ✓ |
| ligase_enabled | Enzyme | lagging_polymerase | — | Built (Light + Complex tier) |
| lagging_gap_enabled | Enzyme | lagging_polymerase; primase (soft, hard-gate TBD) | linear mode only | Built (gap mechanic shipped; enzyme visual pending) |
| primase | Enzyme | lagging_polymerase | soft: telomerase | Built (Light + Complex tier) |
| primer_removal (pol1_enabled) | Enzyme — bridge toggle | primase, ligase_enabled | — | Built (Complex tier) |
| telomerase_visual | Enzyme | lagging_gap_enabled | linear mode only | NEW (designed — TelomeraseDesign.md) |
| shelterin | Enzyme | telomerase (force-enabled by it) | linear mode only | NEW (telomere-end protection — see TelomeraseDesign.md) |
| trombone_loop | Structural | lagging_polymerase | — | Planned |
| full_replisome | Structural | trombone_loop | — | Planned |
| termination_tus_ter | Enzyme | helicase | circular mode only | NEW (sketched — TusTerDesign.md) |
| leading_proofreading | Fidelity | leading_polymerase | — | Planned (layer 6) |
| lagging_proofreading | Fidelity | lagging_polymerase | — | Planned (layer 6) |
| error_generation | Shared mechanic | ≥1 polymerase | — | NEW (prereq for below) |
| mismatch_repair | Fidelity | error_generation | — | Planned (layer 7) |
| lesion_sos | Damage mechanic | ≥1 polymerase | — | NEW |
| translesion_pol45 | Damage tolerance | lesion_sos | — | NEW |
| wobble_enabled | Cross-cutting lens | — | — | ✓ |
| atp_activation_enabled | Cross-cutting lens | — | — | NEW |
| temperature | Cross-cutting dial | — | — | NEW (existed in old Zymulador) |

---

## Open Questions Carried Forward

- **Proofreading granularity** — one unified toggle applying to whichever
  polymerase(s) are active, or split leading/lagging (finer pedagogical control,
  more buttons)?
- **Primase scope** — lagging-only (matches current docs) or also spawn the
  single leading-strand origin primer for completeness?
- **Eukaryotic mode depth** — full parallel machinery (ORC/MCM/CMG/Pol ε/δ/α,
  PCNA/RFC, chromatin) or a lighter "relabel + linear topology + telomeres"
  pass first?
- **Error vs. lesion mechanics** — are these one underlying "bad base" system
  with two severities (mismatch = proofreadable, lesion = requires TLS), or two
  independent mechanics?
