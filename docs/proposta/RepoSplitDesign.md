# MolSim — Open-Core Repo Split Design (proposal)

_Design proposal, not yet implemented. Companion to `SHARED_BASE_SEAM.md`,
which already draws most of the boundary this document turns into a license
and repository boundary. Written alongside `FinancingModels.md`, which covers
the business-model question this architecture is meant to serve either
version of._

---

## Why the seam already exists

`SHARED_BASE_SEAM.md` separates the **shared base layer** (free-monomer
engine, playback/scrub, geometry primitives, ThemeManager, enzyme-spawning
conventions) from **process-specific logic** (fork geometry, replisome
positioning). That boundary was drawn for code-cleanliness reasons ahead of
the transcription/translation build. It turns out to be almost exactly the
right boundary for an open-core license split too — which is a good sign,
since a license boundary that fights the code architecture is a maintenance
tax forever.

The one place this document diverges from `SHARED_BASE_SEAM.md`: that doc
draws the seam between "shared substrate" and "replication-specific." This
document draws a **second, orthogonal seam** — between "the simulator" (all
of it, including replication-specific logic) and "the commercial platform
around the simulator." Both seams coexist; they answer different questions.

---

## Two repos

### `mol-sim-engine` (public, open source)

Everything needed for a complete, runnable, self-hostable educational tool:

- The full Godot project as it exists today: `simulation.gd`,
  `replication_manager.gd`, `helicase.gd`, `ligase.gd`, `primase_blip.gd`,
  `pol1.gd`, `procedural_shape_utils.gd`
- `ThemeManager`, `ComplexityManager`, `LocaleManager` and their CSVs
- All enzyme visuals: `helicase_ring.gd`, `polymerase_clamp.gd`
- `zoom_manager.gd`, `DnaSequenceResource`, base `PlayerUI` scenes
- **Every complexity tier, unrestricted** — base replication through the
  Complex-tier Okazaki maturation relay, telomerase, vertical mode. No
  tier is held back for a paid version. (See `FinancingModels.md` for why
  this matters ethically and for grant eligibility — os4science and DPG
  both require the actual educational function to be unrestricted.)
- Every design doc (`HelicaseDesign.md`, `PolymeraseDesign.md`,
  `OkazakiMaturationDesign.md`, etc.) — these are documentation of the
  open engine and belong with it
- Future siblings: `transcription_manager.gd`, `translation_manager.gd`,
  `pcr_manager.gd` when built

**Anyone can clone it, build it in Godot, run it in a classroom with zero
Embaúba involvement, fork it, or contribute back.**

### `mol-sim-platform` (private, commercial — exists only under the Hybrid model)

Everything that makes MolSim easy to deploy and manage at institutional
scale, but that a self-hosting teacher doesn't need:

- Zero-setup hosted/web build pipeline, signed builds for school
  Chromebook fleets, update management
- Teacher dashboard: class rosters, assignment tracking, LMS integration
- Institutional content-authoring tools (custom sequence sets, curricula)
- Billing/subscription infrastructure (Stripe/apoia.se integration)
- "Name an Enzyme" sponsor-name data pipeline and the quiet-approval
  workflow already described in `Zymosim_Plano_de_Projeto.md`
- Any telemetry/usage analytics offered to institutional customers

---

## Integration pattern

`mol-sim-platform` depends on `mol-sim-engine` as a pinned dependency (Godot
addon / git submodule / release-tag pin — pick during implementation), and
only ever touches the engine through its **already-exposed public surface**:
`ComplexityManager`'s toggle API, `DnaSequenceResource`, `simulation.gd`'s
accessors, the signals process managers already emit
(`slot_reached`, `phase_changed`, `fragment_completed`, etc.).

This is the same discipline `STATUS.md`'s architectural rules already
enforce internally — *"No script reaches into another script's owned visual
nodes"* — just applied one layer up, across a repo boundary instead of a
script boundary. If `mol-sim-platform` ever needs something from the engine
that isn't exposed as a method or signal, that's the same diagnostic signal
as a script reaching into another script's internals: the seam is leaking,
and the fix is to expose the thing properly in the engine repo, not to fork
around it in the platform repo.

**Versioning**: `mol-sim-engine` tags releases normally. `mol-sim-platform`
pins to a known-good tag and upgrades deliberately — this protects
institutional customers from community-driven engine churn breaking a
deployed product mid-semester, and protects the open engine from being
slowed down by platform-side release caution.

---

## License choice for `mol-sim-engine`

Two real options, worth deciding deliberately rather than defaulting:

| | MIT | AGPL-3.0 |
|---|---|---|
| Adoption friction | Lowest — no obligations on forks | Higher — network-use copyleft scares some integrators |
| DPG Standard / os4science fit | Both qualify (open licensing is the requirement, not a specific license) | Both qualify |
| Protects against a competitor forking the engine, adding a dashboard, and selling it without contributing back | No | Yes — AGPL's network clause specifically closes the "SaaS wrapper" loophole MIT leaves open |
| Relevant here because... | — | You are *building exactly that SaaS wrapper yourself* (the platform repo). AGPL means anyone else who wants to compete with the hosted/institutional product has to open-source their wrapper too, or negotiate a separate commercial license with you — the classic open-core pattern (GitLab, Mattermost, etc.) |

**Recommendation to discuss with Henrique**: AGPL-3.0 for `mol-sim-engine`
if the Hybrid model (see `FinancingModels.md`) is the direction — it's the
license that actually makes open-core sustainable rather than just
generous. If the Full Open Source model is chosen instead, the AGPL vs MIT
choice matters less (there's no competing wrapper to protect against), and
MIT's lower friction may better serve the DPG/os4science/adoption goals.

---

## What this split does *not* require deciding yet

- Whether `mol-sim-platform` is ever actually built. The engine repo split
  is worth doing regardless — it's what unlocks os4science eligibility and
  DPG registration either way (see `FinancingModels.md`). The decision to
  build a commercial platform layer on top of it can come later.
- Exact license text / CLA questions — worth a real legal pass before
  publishing, not a first-draft decision.

---

## Cross-references

- `SHARED_BASE_SEAM.md` — the code-architecture seam this license seam
  builds on
- `FinancingModels.md` — the Hybrid vs. Full Open Source business models
  this repo split is designed to support either of
- `Zymosim_Plano_de_Projeto.md` — crowdfunding tiers, existing revenue math
- `STATUS.md` — the "no script reaches into another script's owned nodes"
  rule this document extends across the repo boundary
