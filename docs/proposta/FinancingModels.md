# MolSim / Zymosim — Two Financing Models (proposal)

_Design proposal, not yet decided. Companion to `RepoSplitDesign.md` (the
repo architecture both models below share) and to
`Zymosim_Plano_de_Projeto.md` (existing crowdfunding tiers, revenue
arithmetic, and international funding survey this document builds on)._

---

## Why this exists

Crowdfunding an educational tool where access is gated behind donations
sits uneasily with the mission — a school that can't donate shouldn't get
a worse (or absent) product than one that can. Both models below solve
that the same way: **the core educational function is never paywalled.**
They differ in what, if anything, Embaúba sells on top of it, and that
difference changes the funding-pathway math, the PIPE narrative, and the
team's build scope.

Both models share the repo split in `RepoSplitDesign.md`. Model A uses
both repos; Model B never builds the private one.

---

## Model A — Hybrid (open core + commercial platform layer)

**Free forever, unrestricted:** the complete simulator, `mol-sim-engine` —
every complexity tier, every enzyme, self-hostable by anyone.

**Sold, `mol-sim-platform`:** zero-setup hosting, teacher dashboards,
class rosters, LMS integration, institutional content-authoring tools,
priority support, PD workshops.

### Revenue sources
- Institutional subscriptions — the Plano's existing "Instituição/Professor"
  tier (R$80-100/mês), now selling *real product* (dashboard, rostering)
  rather than functioning mostly as a moral ask
- FAPESP PIPE — fits cleanly; PIPE funds product development toward a
  sellable outcome, and the platform layer *is* that sellable outcome
- Future B2G sales via BrazilLAB, bridging to public school networks
- os4science / DPG credibility (earned via the engine repo) strengthening
  IDB Lab and MIT Solve applications, which favor ventures with a
  sustainability story, not just impact
- Crowdfunding becomes a **small, optional patronage tier** — apoia.se
  individual supporters get credits/Discord/early builds, same as today's
  draft, but the business no longer depends on hitting the Plano's own
  flagged "~250 recurring supporters" number. It's supplementary, not load-bearing.

### Trade-offs
- **More to build and maintain**: two repos, billing infrastructure, a
  dashboard product, ongoing platform support — real scope beyond the
  simulator itself
- **Slower path to revenue-positive**: B2B/B2G sales cycles are slower
  than launching a Patreon-equivalent page
- **Risk of mission drift**: institutional feature requests (more
  dashboard, more admin tooling) competing for time against pedagogy work
  (Krebs cycle, transcription/translation)
- **Cleanest fit for PIPE as currently scoped** — a concrete, sellable
  product is the easiest story to tell a PIPE reviewer

---

## Model B — Full open source, Kurzgesagt-style

Reference: [kurzgesagt.org](https://kurzgesagt.org/) — free educational
content, funded by Patreon plus a merch store, no paywalled content
anywhere. Patron perks are additive (behind-the-scenes access, early
previews, community input) and never gate the actual educational output.

**Everything is open source and free — engine and any platform features
both.** No `mol-sim-platform` repo is ever built as a separate paid
product; if institutional tooling is needed later, it ships in the open
engine too.

### Revenue sources
- **Monthly patronage** — apoia.se Contínua (or equivalent), same
  mechanism as today's Plano, but reframed: supporters are funding open
  development, not buying access
- **Merch** — MolSim's existing rounded-octagon enzyme vocabulary
  (`HelicaseDesign.md`, `PolymeraseDesign.md`) is genuinely merch-ready:
  enamel pins or stickers of the helicase ring / polymerase clamp,
  replisome poster prints. This is a real, if modest, second revenue leg —
  exactly Kurzgesagt's model — and it doesn't exist at all in Model A's plan
- **"Name an Enzyme," done transparently** — already designed as additive,
  never substituting the real scientific label
  (`Zymosim_Plano_de_Projeto.md`: *"Rótulos científicos continuam sendo
  o padrão real sempre"*). Buying a name slot funds development; it never
  buys biological accuracy. This framing is what makes it ethically sound
  under this model specifically — worth keeping front and center in any
  public description of the tier
- One-off grants/sponsorships (os4science, possibly UNESCO-adjacent
  programs given DPG registration)

### The institutional tier's perk, reframed
Per your instruction: instead of buying dashboard features (there are
none — everything ships in the open engine), the Instituição/Professor
tier buys **priority on the development queue** — a formalized version of
the "Colaborador" tier's existing draft perk (*"voto no próximo processo
biológico da fila"*). Concretely: paying institutions get a heavier vote
or a guaranteed say in whether the next sprint targets, say, transcription
vs. a requested localization vs. a specific complexity-tier polish pass.

This is low-risk ethically in a way dashboard-gating isn't: **nobody is
denied anything, they only gain influence over sequencing.** The output
they're prioritizing ships free to everyone, including non-supporters,
the moment it's done — supporters just get to help decide what's next.

### Trade-offs
- **Cleanest ethical story available** — zero access friction, ever. Best
  fit for DPG registration, os4science, UNESCO Open Solutions adjacency,
  and B2G outreach to public school networks with no budget line at all
- **Revenue depends entirely on sustained voluntary giving.** The Plano's
  own arithmetic is the relevant caution here: ~250 recurring individual
  supporters for R$5k/month is explicitly flagged there as "exceptional
  for a niche molecular-biology simulator," and the institutional tier
  (~55-60 supporters) is efficient only if you can actually land that many
  paying-for-priority institutions — a real sales motion even without a
  product to demo beyond the queue itself
- **No contractual revenue floor** — patron churn is normal and
  unpredictable in a way institutional contracts aren't
- **PIPE narrative needs adaptation.** PIPE typically funds development
  toward a commercializable product; "everything is free forever, funded
  by patronage" is a different sustainability story, not necessarily a
  disqualifying one, but not the default PIPE reviewer expects either.
  This is the same kind of eligibility ambiguity already being checked
  for the Pesquisador Principal question — worth a similarly direct
  question to **pipe-jornada@fapesp.br**: *does PIPE fund open-source,
  patronage-sustained software, or does it require a proprietary/sellable
  deliverable?* Get this answered before committing to Model B if the
  July 29 pré-proposta is meant to reflect it.

---

## Funding-pathway fit, side by side

| Pathway | Model A (Hybrid) | Model B (Full OSS) |
|---|---|---|
| FAPESP PIPE | Strong — straightforward product narrative | Needs verification (see above) |
| Open Source for Science Fund | Yes — engine repo alone qualifies | Yes — whole product qualifies |
| Digital Public Goods Alliance | Yes — engine repo | Yes — whole product |
| IDB Lab / MIT Solve | Strong — impact + sustainable-business narrative | Strong — pure impact narrative |
| BrazilLAB / B2G | Good — sells dashboard to networks | Better — zero budget-line friction |
| Prototype Fund (Germany) | Ineligible (residency) — unaffected by model choice | Ineligible (residency) — unaffected by model choice |
| apoia.se / Buy Me a Coffee | Supplementary income | **Primary** income |

---

## Open questions to settle with Henrique

1. Does PIPE's Chamada 33/2026 require a proprietary/commercializable
   deliverable, or does open-source, patronage-funded software satisfy
   its criteria? (Same email channel as the Pesquisador Principal
   question — `pipe-jornada@fapesp.br`.)
2. Team capacity: does building and maintaining `mol-sim-platform`
   (Model A) fit alongside continued biology-content development, or does
   it compete for the same limited hours?
3. Time horizon: is Embaúba's runway (CNPJ overhead, near-term cash needs)
   compatible with Model B's dependency on patron growth reaching
   sustainable scale, or does Model A's institutional-contract stability
   matter more in the near term?
4. Is a hybrid-of-hybrids viable — start on Model B's fully-open path now
   (cheapest to build, cleanest grant story, matches the July 29
   pré-proposta timeline) with an explicit option to add a Model A
   platform layer later once/if institutional demand for dashboards
   actually materializes, rather than building it speculatively upfront?

---

## Cross-references

- `RepoSplitDesign.md` — the `mol-sim-engine` / `mol-sim-platform` repo
  architecture both models share
- `Zymosim_Plano_de_Projeto.md` — existing crowdfunding tiers, the
  individual-vs-institutional supporter math both models reuse, and the
  international funding survey
- `TODO.md` — the pré-proposta eligibility question this document's
  Question 1 parallels
