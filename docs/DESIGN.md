# Zymulador — Design Document
_Stable design philosophy and biological model — what Zymulador is, why
modular complexity, and the biology it's teaching. This content doesn't
change when a feature ships, and isn't expected to. For current
implementation status, active roadmap, pinned issues, and scene structure,
see STATUS.md — that content used to live in this same file and repeatedly
drifted out of sync, since status changes far more often than the reasoning
behind it does. Split apart for exactly that reason; see STATUS.md's own
header for the fuller account of what prompted it._

---

## What Zymulador Is

Zymulador is a molecular biology education platform built in Godot 4.x (GDScript).
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
2. + Lagging strand, base level: an independent polymerase (not attached to the
   replisome at this tier) synthesizes Okazaki fragments as fixed-size tiles —
   `[0, F)`, `[F, 2F)`, `[2F, 3F)`, … where `F = okazaki_fragment_size` — firing
   right-to-left *within* each tile (newest slot first, oldest last), one slot
   per helicase step once a one-time startup backlog (`okazaki_fragment_size +
   pll_slot_count` exposed slots) has built up. After startup, firing is fully
   continuous — no idle gaps between fragments.
3. + Trombone loop model: the lagging polymerase stays physically coupled to
   the replisome via the tau (τ) body, looping the template strand through
   itself so both polymerases can move in the same direction together.
4. + Full replisome (clamp loader, β-clamps on both strands, primase as a
   distinct visual/enzyme rather than implicit)
5. + RNA primers and primer removal as explicit steps
6. + Proofreading (DNA Pol III 3'→5' exonuclease)
7. + Mismatch Repair (MutS/MutL/MutH complex, post-replication)

The trombone loop (old layer 3 in earlier drafts of this document) is now
understood as the **maximum complexity tier currently in scope** for the
replication simulator, not a prerequisite for showing Okazaki fragments at
all — the base-level back-and-forth model is biologically valid on its own
and is the right starting point before adding replisome coupling.

_See STATUS.md's Roadmap for which of these layers are actually built today._

### The telomere gap is a toggle, not a fixed behavior

At **base complexity**, the lagging polymerase is deliberately *not* shown as
attached to the replisome, so there's no in-simulation reason for it to stop
short of the strand's end — once the helicase finishes, the lagging polymerase
independently keeps firing (on its own clock, no longer helicase-driven) until
every slot is synthesized, including a genuinely short final fragment sized to
whatever remains. **No gap is shown at base complexity.**

The gap itself — the real end-replication problem — is reserved behind
`lagging_gap_enabled` (export, `simulation.gd`, default `false`), switched on
when the **telomerase tier** is introduced. With it enabled, an incomplete
trailing fragment at `DONE` is discarded rather than caught up, and the
leftover stretch is recorded as `lagging_telomere_gap`. Both code paths
already exist side by side — enabling telomerase complexity is a toggle
flip, not new plumbing.

The Pol I pass reached a version of this same gap from an entirely different
angle: under Pol I's own removal model, the very last fragment in any
sequence never gets a "next fragment closes" event to trigger its own primer
removal — the same end-replication problem, arrived at independently,
without `lagging_gap_enabled` even being involved. See
OkazakiMaturationDesign.md's Pol I Implementation Status for the fuller
account, and STATUS.md's Roadmap for the still-open question of how the two
should interact once telomerase itself is built.

### Backbone continuity (nicks) is a toggle too

At **base complexity**, no ligase is modeled, so there's no in-simulation
reason for a nick to remain visible between two adjacent, already-synthesized
Okazaki fragments — the backbone should read as one continuous line, exactly
like the leading strand's. Once a fragment completes, it merges into that
continuous line; only the very first fragment's 5' end and the current
last-complete fragment's 3' end keep markers, since an internal boundary
between two already-joined fragments isn't meaningful anymore.

This is governed by `ligase_enabled` (export, `simulation.gd`, default
`false`), mirroring `lagging_gap_enabled`'s pattern exactly. When `true`
(the ligase tier), rendering reverts to per-fragment backbones with visibly
separate segments and nicks at every boundary — because at that tier, a
fragment genuinely *should* stay visually distinct until the ligase enzyme
visits and seals it. Both rendering paths exist side by side in
`replication_manager.gd`'s `_lagging_render()` — a toggle flip, not new
plumbing, for whichever tier needs it. _See STATUS.md for current build
status of the ligase tier itself._

### Backbone color as a teaching signal

`template_backbone_color` (ThemeManager) visually distinguishes the original
template DNA backbone from newly-synthesized strand backbone
(`backbone_color`) — a classroom aid for "which strand is the original" that
a single shared backbone color couldn't convey.

**The reusable part for transcription is the *pattern*, not the *color*:**
one dedicated ThemeManager color field per distinct strand role, applied at
the `Line2D` level. RNA-vs-DNA (a backbone chemistry distinction) is not the
same axis as replication's template-vs-new-strand distinction, so
transcription's future mRNA strand should get its own field rather than
inherit `template_backbone_color` — not designed further until
transcription's own design pass begins, per SHARED_BASE_SEAM.md's caution
against front-loading sibling-process detail.

---

## Biological Model

Zymulador follows the **E. coli replication model** for accuracy and visual clarity.

### Key biological facts encoded in the simulation
- DNA Pol III can only synthesize 5'→3'
- The two template strands are antiparallel
- Leading strand: continuous synthesis in the direction of the fork
- Lagging strand: discontinuous synthesis (Okazaki fragments). At base
  complexity, the lagging polymerase is independent of the replisome — it
  fires fixed-size fragments right-to-left as backlog builds up, then
  independently finishes the strand once the fork itself is done. This is
  the base-complexity model (layer 2 above) before replisome coupling is
  introduced.
- With a single replisome, the lagging strand template loops back on itself
  so its polymerase can travel in the same direction as the fork while still
  synthesizing 5'→3' — this is the trombone loop model (layer 3), the
  highest complexity tier currently planned for the replication simulator
- Each Okazaki fragment requires an RNA primer (primase)
- Pol I performs nick-translation to remove each fragment's RNA primer —
  simultaneous 5'→3' exonuclease + 5'→3' polymerase at matched rates, one
  fragment behind Pol III's own progress (needs the NEXT fragment's worth
  of freshly-made DNA to extend into as it displaces the old primer)
- Fragments are joined by DNA ligase once their primer is fully replaced
  with DNA — ligase cannot act on an RNA-DNA junction, only DNA-DNA
- In the full replisome, both polymerases are held together via the tau (τ) body
- β-clamp (sliding clamp) on each strand increases polymerase processivity

### Didactic simplifications (intentional)
- Sequences can be up to 300 bases (`DnaSequenceResource.MAX_LENGTH`), with
  a computed minimum floor ensuring at least one full Okazaki fragment can
  fire.
- Single-slot Okazaki fragments use a combined "5'-3'" marker
- Biological accuracy is didactic, not exhaustive
- The base-complexity lagging strand model (independent polymerase,
  fixed-tile fragments, no telomere gap, continuous joined-looking backbone)
  is presented as a real, simplified picture of discontinuous synthesis, not
  as a placeholder or approximation to be apologized for — multiple
  educational sources describe lagging-strand synthesis this way before
  introducing replisome coupling, primase, and the end-replication problem
- RNase H's real assisting role in primer removal isn't separately modeled —
  Pol I alone stands in for the whole removal, didactic scope over
  exhaustive mechanism (same principle as the point above)

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
  completely first and confirm a clean, regression-free baseline before writing
  new logic on top.
- **Debug/diagnostic visuals are temporary by design** — remove once they've
  served their purpose validating a piece of math.
- **Trace the exact math with small numbers before trusting an assumption
  about emergent behavior.** Several early design decisions only became
  clear after hand-tracing concrete step-by-step examples, not from
  reasoning about the formulas alone — Pol I's own trigger design repeated
  this lesson: a proposed anchor-slot trigger looked right until concrete
  tile numbers (`okazaki_fragment_size=12`, `primer_length=3`) showed it
  wasn't, before it shipped. See OkazakiMaturationDesign.md's Pol I
  Implementation Status.
- **Chaotic manual QA finds real bugs straight-line testing won't.**
  Scrubbing back and forth arbitrarily, then resuming play, has surfaced
  multiple live-trigger desync bugs that a clean forward playtest never
  would have hit — worth deliberately doing before calling any interactive
  feature done. Confirmed again during the Pol I pass (see STATUS.md's
  Pinned Issues).

_Note: this list overlaps significantly with SKILL.md's own Edit Protocol
section, which covers much of the same ground at a terser, more
Claude-facing grain. Not yet unified — flagged here rather than resolved,
since reconciling them is its own small project, not a byproduct of this
split._
