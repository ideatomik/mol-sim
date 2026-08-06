# Lesson-Prep Companion — Concept Note (Nucleation only)

_Earliest possible stage — a seed problem and rough shape, not a Lattice
doc. Written from a single conversational description after two days of
teacher conversations; nothing here has been scoped, validated against
teacher needs beyond that anecdotal round, or checked against what's
technically buildable. Purpose is purely to not lose the idea before next
week._

---

## Nucleation — the seed problem

Two days of conversations with Brazilian schoolteachers surfaced a
consistent demand, independent of anything Zymulador itself currently
does: **teachers have very little prep time relative to a large number of
classes, and they want ready-made class material, not a tool they have to
build material with from scratch.**

Zymulador today is the second half of that need — a renderer, a simulator
a teacher can point at and demonstrate with — but it assumes the teacher
already knows which sequence, which enzyme configuration, which zoom
level, and which talking points make a good lesson. That assumption is
exactly what teacher prep time doesn't allow for.

This is not a new problem invented from nothing — it's the same demand
that already motivated the didactic sequence preset catalogue (short
C-G/A-T-rich sequences sized to read clearly at level-2 zoom, the
PCR-flavored template, presets for promoters/exons/introns — discussed
2026-07-07). That catalogue is Embaúba authoring ready-made examples by
hand, one at a time. **The companion is the generalization of that same
instinct: instead of a fixed catalogue, a tool that generates
didactically-sound examples and lesson material on demand, scoped to
whatever a given teacher's class actually needs that week.**

The individual-nucleotide-rendering-for-didactic-purposes thread (raised
in passing, not sure yet whether that was discussed here or with Claude
Code — worth tracking down before next week) comes from this same root:
a teacher doesn't want "the simulator," they want "the thing that shows
my students exactly this concept, at exactly this level of detail,
today."

---

## Rough shape (unscoped, for discussion next week)

An AI-backed companion application whose output is class material —
sequences, configuration presets, suggested talking points, maybe
worksheets — that Zymulador can load and render directly. The pairing
matters: the companion doesn't replace Zymulador or compete with it, it
removes the prep-time bottleneck that currently sits in front of it.
Something closer to "describe your lesson, get a ready Zymulador scene
plus supporting material" than a general-purpose chatbot bolted on.

Genuinely open, not even provisionally decided:

- **What it actually outputs.** A loadable Zymulador preset/config file
  only? Full lesson-plan-style material (talking points, discussion
  questions) alongside the preset? Both, with the preset as the
  Zymulador-facing artifact and the rest as a companion document?
- **Where it lives.** A separate application, a mode inside Zymulador
  itself, or a web tool that produces files Zymulador then opens? Each has
  different implications for the incubation/CNPJ scope and for whether
  this is one product or two.
- **Content accuracy.** Zymulador's own biological-accuracy principle
  (claims checked against current authoritative sources, cited by name,
  never trained-in recall) presumably has to extend to whatever this
  companion generates — worth deciding early whether that's a hard
  requirement from day one or something to phase in, since it changes the
  technical approach significantly (constrained generation against a
  vetted source set vs. open generation with after-the-fact review).
- **Who it's actually for.** The same teacher already using Zymulador in
  class, or a broader population of teachers who might use the companion
  even without ever touching the simulator? This affects both the product
  boundary above and the business case below.

---

## Why this matters for financing, not just product

Flagged explicitly because it changes the PIPE conversation, not just the
roadmap: the financing notes already record that the pure-software Krebs
spike was judged too weak a pitch for the 29/07 PIPE chamada, and that
professor demos are effectively B2E sales calls for the institutional
crowdfunding tier. A prep-time companion is a sharper technological
challenge than "render molecules correctly" alone — it's a real applied-AI
product problem (constrained generation, didactic-accuracy validation,
integration with an existing simulator) — and it directly targets the
adoption bottleneck the institutional tier already depends on solving
(the 55-60 professor relationships needed at R$80-100/month each). Worth
weighing this specifically against **Jornada Tecnológica — Educação**
(13/10/2026) once it's scoped further, given that chamada's already-noted
stronger thematic fit versus the fluxo contínuo path.

Not claiming this settles anything about Model A vs. Model B (open-core+
SaaS vs. full open-source/patronage) — if anything it adds a new axis to
that decision, since a generative companion has a much more natural SaaS
shape than the renderer itself does. Worth raising next week rather than
assuming either.

---

## Next steps (for next week, not now)

- Track down whether the individual-nucleotide-rendering-for-didactic-
  purposes conversation happened here or with Claude Code, and pull it
  back into context.
- Talk through the "rough shape" open questions above until at least the
  output-boundary and where-it-lives questions have a provisional answer
  — those two gate almost everything else, including whether this is a
  Sementes Embaúba portfolio entry of its own or a Zymulador feature.
- Only after that: a real Nucleation pass grounded in the actual teacher
  conversations (what was said, not just the one-line summary above) —
  this note is a placeholder for that, not a substitute.
