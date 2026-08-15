# Azteca — Concept Note (Nucleation)

_Synthesized 7 August 2026 from a single working conversation, building on
`LessonPrepCompanion_ConceptNote.md`. Earliest possible stage — a named
seed with a scoped Phase 1, not a Lattice doc. Several open questions
remain genuinely open; this note tracks what's decided versus what isn't._

---

## What it is

**Azteca** — named for the ant genus that commonly inhabits embaúba trees
in a mutualist relationship, mirroring the Embaúba/Sementes naming
convention. A companion product that removes the class-prep bottleneck
teachers face, without touching Zymulador's freeware promise.

**The core split (decided):**
- **Zymulador** stays fully free, open source, every complexity tier,
  forever — no change to the existing public commitment.
- **Azteca** is the commercial product. Payment buys prep-time saved, not
  simulator access or simulator depth. A non-paying teacher's students
  still get the exact same simulator a paying teacher's students get.

This distinction is what keeps Azteca consistent with Embaúba's existing
ethical commitment (a school that can't pay shouldn't get a worse tool) —
the *equipment* never depends on payment, only the labor-saving layer on
top of it does, and that layer didn't exist before, so nothing is being
taken away from the non-paying case.

---

## What it produces (decided)

Two deliverables, deliberately split, because a single artifact trying to
serve both jobs is why slides currently underperform at both:

1. **Class-facing material** — a lean, paced slide deck built around live
   Zymulador instances embedded at the moments that need real-time
   manipulation. Replaces what used to be board-drawing or static images.
2. **Study-facing material** — a study guide, dense enough to stand alone
   after class without a teacher's narration filling the gaps.

Brazilian classroom practice has shifted heavily toward slide-based
teaching (the board now reserved for specific data points or live
demonstration), which is what makes Zymulador's live-manipulation strength
so relevant here — Azteca's job is producing the deck that strength lives
inside of, not just the simulator states themselves.

---

## How it works (decided — mechanism)

**Not open generation.** Procedural composition of **human-authored,
human-reviewed content blocks and multimedia resources** — closer to how
a textbook is actually built than to a chatbot generating explanatory
prose from scratch. A "source of scientific truth" weaving skill
sequences and arranges these blocks into a coherent lesson, rather than
inventing content.

This has two compounding effects:
- **Cost**: generation cost is dominated by composition (connective
  tissue, sequencing, level-fitting) rather than large-scale text
  invention, which is materially cheaper and more predictable than open
  generation would have been.
- **Grant/accuracy narrative**: the technical risk becomes "does the
  composition logic correctly sequence and level-fit vetted material,"
  not "does the model hallucinate facts." A more defensible boundary for
  both a PIPE reviewer and Embaúba's own accuracy standards.

**New scope this implies, not yet designed**: an authoring/review
workflow for blocks themselves — who authors them, how they're vetted,
what makes a block eligible to be drawn from. This is separate work from
the composition/weaving logic.

---

## Phase 1 scope (decided this session)

Phase 1 Azteca is built **around Zymulador specifically** — molecular
biology class material spanning school years through college and
graduate level. Modularity (an existing Embaúba value) is the explicit
justification for scoping this way: prove the mechanism narrowly and
deeply in one domain before generalizing.

**Why molecular biology specifically, beyond Zymulador already existing:**
it's a subject with unusual longevity across a student's entire education
— early-school introductions to nutrition and genetics, through to
graduate-level topics like mitochondrial DNA and its connection back to
the Krebs cycle. Few subjects span that full range as one continuous
thread. That makes it a genuine proof of concept for level-modularity
specifically, not just a convenient starting domain — Azteca has to prove
it can serve a school-years lesson and a grad-school lesson from the same
mechanism, and molecular biology is one of the few subjects where that
full range exists to test against.

**Worth flagging explicitly**: this is a narrower Phase 1 than the "every
teacher, any subject" ambition named earlier in the same conversation.
That ambition isn't abandoned — it's the reason Azteca is its own Sementes
entry rather than a Zymulador feature — but Phase 1 concretely ships
against Zymulador's existing domain and level range, not a general
subject-agnostic tool. The gap between "own semente, every teacher" and
"Phase 1 is Zymulador-scoped" is intentional, not an inconsistency, as
long as it's named — subject-generality is a later-phase expansion, not
a Phase 1 claim.

---

## Explicitly tabled — Phase 2

**Student access.** Right now Azteca is designed around a single user
(the teacher). Whether students get direct access — to the study guide,
to Zymulador itself via Azteca's nudging, or to some self-directed middle
ground — is a real fork with real consequences (pricing shape, the
free-forever ethic, three different levels of exposure risk depending on
what "access" means) and is deliberately not being resolved in Phase 1.

---

## Explicitly tabled — further horizon, outside current PIPE timeline

**Physical-model integration (MOO, Krebs Cycle Train).** Raised as worth
recording now, not scoped or timelined. Azteca's relationship to a
physical didactic model could sit at three distinct levels, each a real
scope jump from the last:

1. **Instructions only** — Azteca tells the teacher what to do with the
   model by hand. No hardware dependency, works today.
2. **Blind connection** — Azteca can trigger the model (send a command to
   an actuator) but has no sense of its actual state — commanding a
   machine rather than perceiving and reacting to it.
3. **Full interaction** — Azteca reads sensor state and drives actuators
   the way it directly manipulates Zymulador's state today. A real
   two-way loop between software and physical model.

Level 3 is a materially different kind of work than anything else in this
note — hardware/mechatronics, not composition or generation — and would
mean **revisiting MOO's and Krebs Cycle Train's physical designs at the
design stage**, not extending them after the fact, since actuators and
sensors need to be designed in from the start. Not part of Phase 1; noted
here because it directly touches Azteca's scope and shouldn't be
rediscovered later without this context.

---

## Still genuinely open (not yet decided)

1. **Free tier or not.** Does a non-paying teacher get anything from
   Azteca at all (limited generations, lower priority), or is it a paid
   tool from day one with no free tier, justified by real per-use running
   cost that Zymulador itself doesn't have?
2. **Pricing shape**, once (1) is settled — needs its own arithmetic,
   separate from the existing Zymulador patronage tiers, and should
   account for the (favorable, per this session) generation cost
   structure once real output-length estimates exist.

---

## Team capacity (worth naming plainly)

Everything Embaúba has built up to and including Zymulador has been
solo-founder viable. Azteca changes that, even at the Phase 1 molecular-
biology proof of concept — the authoring/review workflow alone implies
more hands than one person running product, biology content, and business
simultaneously. Phase 2 (more subjects) and full physical-model
integration are, honestly, a fully matured company's scope, not an
extension of what one founder can carry solo.

This isn't a reason to not pursue Azteca — it's a reason to be explicit
that Azteca's roadmap is also, implicitly, a hiring/team-growth roadmap,
and Phase 1 scoping should account for that rather than assume the same
solo-capacity constraints that shaped everything before it.

---

## Financing / PIPE relevance

Azteca is the current leading candidate for the **Chamada Educação**
(opens 13 Oct 2026) technical narrative — see
`Embauba_Grants_Deadlines_Tracker.md`. The applied-research question
(constrained composition of vetted blocks, scientific-accuracy weaving,
reliable handoff into an existing simulator) is a stronger PIPE story than
the Krebs-cycle spike alone, without requiring any compromise to
Zymulador's freeware commitment. Still unscoped enough that this should
be treated as a candidate narrative, not a settled one, until Phase 1
design work is further along.

---

## Next steps

- Settle the free-tier question (open item 1 above) — it gates pricing
  design and touches the same ethical pattern already established for
  Zymulador.
- Design the block-authoring/review workflow implied by the procedural
  composition mechanism — separate scope from the weaving/generation
  logic itself.
- Revisit Phase 2 (student access) once Phase 1 has real usage to learn
  from, rather than speculatively designing it now.
- Update `LessonPrepCompanion_ConceptNote.md`'s standing next-steps (the
  individual-nucleotide-rendering thread, the teacher-conversation
  grounding pass) — this note supersedes it as the working seed, but
  doesn't yet incorporate the fuller teacher-conversation detail that
  original note flagged as still needed.
