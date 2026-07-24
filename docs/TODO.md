# TODO — working list

_Session close: 17 July 2026. Companion to STATUS.md (engineering state) and
Zymosim_Plano_de_Projeto.md (funding/product plan). **Contains revenue targets
and funding strategy — same handling as the Plano: keep out of any public
repo.**_

---

## Tomorrow — MolSim

### The demo
- [ ] **PC build, as-is, off the thumb drive. Do not touch it beforehand.** It
      works, it's plug-and-play, and that's been landing well. The night before
      a demo is the worst possible time to improve it.
- [ ] Android prototype — **secondary and optional**. If it slips, it slips.

### Bugs
_None open — the vertical-camera bug that used to be here (ResetZoomButton)
was resolved and superseded by tonight's full camera pass; see STATUS.md's
"Follow Mode, Click-Drag Dead Zone & Related Camera Fixes" section._

### Features
- [x] ~~Follow mode~~ — shipped: fourth camera state in `zoom_manager.gd`
      (auto position from the entry-level frame provider, independently held
      manual zoom), double-click entry/exit/highlight-toggle, background
      press-hold-drag-resume state machine, resume eased via
      `tm.zoom_follow_resume_duration`. Scoped to helicase + lagging
      polymerase only (leading gets the signal for free via the shared
      `polymerase_clamp.gd` but nothing connects it). Full writeup in
      STATUS.md's new "Follow Mode, Click-Drag Dead Zone & Related Camera
      Fixes" section; As-Built addendum in ZoomDesign.md.
- [x] ~~Double-click-to-follow sometimes paused playback~~ — `helicase_ring.gd`/
      `polymerase_clamp.gd`'s drag-to-scrub had no pixel dead zone, so jitter
      between a double-click's two presses was committing to a drag and
      pausing unconditionally. Fixed with a 6px `DRAG_DEADZONE_PX` in both
      files (NOT YET TUNED). Same root cause on both enzymes — LP's smaller
      click region just hit it harder.
- [x] ~~EnzymeLabel panel stuck at old width after topology switch shrank the
      text~~ — `reset_size()` fix in `set_key()`/`refresh_translation()`,
      `enzyme_label.gd`. NOT the label-margin item below — that's too-narrow
      margin; this was stale-width panel not shrinking back down.
- [ ] Retune `polymerase_label_margin` in vertical. "Pol epsilon" is now the
      longest enzyme name in the project, in the axis with the least room
      (cross-axis = 1080px, not 1920). Two Inspector locations — `helicase_ring.gd`
      keeps local `@export`s, `polymerase_clamp.gd` reads ThemeManager.

### Housekeeping (cheap — do these while tired)
- [x] ~~`simulation.gd` version header: v76 → v77~~ — two blocks added
      ("v77 — Vertical mode", "v77 continued — Follow mode & camera fixes"),
      matching STATUS.md's own section titles for traceability.
- [x] ~~Delete SKILL.md from project knowledge.~~ Turned out not to be a
      version lag after all — both copies claim `77.0` in frontmatter, but
      diffing the bodies showed the project copy is missing "The Crystal
      Building Method" section (~117 lines) wholesale, nothing else differs.
      Same fix either way: pulled a fresh copy of the live skill for you to
      swap in.
- [x] ~~Run the git check~~ — repo confirmed at `mol-sim\` (same level as
      project.godot), branch `Refactor`, 2 commits ahead of origin.
      `Get-ChildItem -Filter ".git"` was a false negative (PowerShell's
      leading-dot filter quirk on Windows) — `git status` from inside the
      folder is the reliable check going forward. `docs/` exists, untracked
      — worth checking whether it actually has the design docs in it yet,
      or the move never got past creating the folder.
- [x] ~~Verification debt: grep for draw_string/EnzymeLabel/Label.new()~~ —
      clean. `nucleotide_field.gd`/`polymerase_halo.gd`'s `draw_string()` and
      `nitrogen_base.gd`'s `Label.new()` are all intentional (lightweight
      rendering for per-particle/per-base labels, not enzyme name tags —
      EnzymeLabel's panel overhead doesn't belong there). No stray leftovers.
      New finding instead: `loop_test.gd` uses pre-v70.6 names (`factory_x`,
      `straight_y`) in its own `draw_string()` calls — looks like dead test
      scaffolding, not a glyph-sweep miss. Added to the dead-code retirement
      item below.
- [ ] Tier 2 docs: `ZoomDesign.md` (partially addressed — Follow Mode As-Built
      addendum added, but the rest of the doc is still pre-implementation v72
      and needs its own full rewrite pass), `OkazakiMaturationDesign.md`,
      `PolymeraseDesign.md`. Real, but none costs an hour the way the `.tscn`
      traps would have.

---

## PIPE / Proposta Simplificada — ACTIVE (grant only, no personal stipend)

**Status changed 17 July**, reconciling the 16 July "deprioritized" call with
findings from the 17 July session. Both are true at once:

- **Bolsa PE** (personal stipend) — **dead.** FAPESP's written reply confirmed
  enrollment in a graduação course *"é considerada quebra desta dedicação."*
  Not "may be" — *is*. The *noturno* argument wasn't engaged with; the *bolsa
  parcial* question went unanswered. Not worth revisiting.
- **Auxílio PIPE** (project grant to Embaúba) — **looks viable**, confirmed
  directly against the call text on 17 July:
  - Inova Simples explicitly eligible — item 4.2(d).
  - You can serve as sole **Pesquisador Responsável** without a separate
    Pesquisador Principal — dispensed given you hold all critical technical
    competencies (simulation architecture, software engineering, pedagogical
    design).
  - 24h/week minimum + 40h/week total dedication cap — workable given stated
    availability.
  - Item 4.1 confirms the desafio tecnológico framing (interest to company/
    market) does **not** require a proprietary deliverable.

**Net effect:** PIPE is off the table as personal income, but back on as a
project-funding track for the 29/07 pré-proposta. This resolves the first of
the three questions pinned on 16 July (PP without Bolsa PE — yes, workable);
the other two (bolsa parcial modality; trancamento timing) are now moot, since
the plan no longer assumes you draw a stipend at all.

### The plan doc — still needs the same fix
`Zymosim_Plano_de_Projeto.md` §4 still frames the FAPESP email as *"a
enviar"* and asserts *"graduação não é mencionada como impeditivo."* Both are
now stale in a different way than the 16 July note assumed — rewrite to
reflect the two-track reality above, not just "PIPE is off."

### SAGe registration — CLOSED
Previously flagged as urgent (2-business-day lead time before 29/07 if
Embaúba wasn't yet cadastrada). **Resolved: registration was done last year.**
Worth a quick login to confirm the cadastro is still active before submission,
but no lead-time risk remains.

### Proposta Simplificada draft — status
`PIPE_ProstaSimplificada_Draft.md` has all 5 SAGe fields drafted in Portuguese,
character-limit verified. Krebs cycle wraparound seam is the desafio
tecnológico; DNA replication engine deliberately excluded (item 8.5(a) —
"conceito já demonstrado" disqualifies). Still pending:
- [ ] Fill in surname + curso placeholders (Field 5)
- [ ] Endorsement quote from the genetics-professor demo (Field 5) — demo
      confirmed to have gone well; capture a citable line if one exists
- [ ] Field 4 financing-model narrative — currently assumes Model A/Hybrid;
      needs rewrite if Model B is chosen before submission
- [ ] Súmula Curricular (model at fapesp.br/sumula)
- [ ] Orçamento (R$/US$ tab) — Bolsa de Treinamento Técnico from Field 5 needs
      to reappear here with justification + plano de atividades

### Krebs spike — unchanged, still a prerequisite
- Two enzymatic steps: citrate synthase (fusion), malate dehydrogenase
  (regeneration) — validating cycle wraparound + scrub-safety at that seam.
- **Must stay a *teste preliminar*, not a *conceito já demonstrado*.** Its job
  is to prove a real question exists, not answer it. Resist polishing it.
- The wraparound seam is the valuable part precisely because linear
  replication structurally cannot test it.

---

## PIPE — 29/07 deadline SKIPPED, decision made 22 July

**Status changed 22 July.** Does not overturn the 17 July finding (Auxílio
PIPE is genuinely viable as a grant track, Bolsa PE is genuinely dead) — both
still true. What changed is the decision to *not* submit into this specific
chamada's 29/07 pré-proposta deadline.

**Why:** budget reality check surfaced a near-zero orçamento for the
software-only Krebs spike — no support staff needed, current PC handles the
sim fine, no paid software beyond the Claude subscription. Against a R$500k
ceiling, that's an honest but weak Fase 1 pitch, and forcing a thin proposal
into a deadline that was actively causing stress wasn't the right trade.

**Confirmed this session: PIPE Fase 1 is not deadline-limited outside this
specific themed chamada.** Regular PIPE Fase 1 runs in **fluxo contínuo**
(submissions accepted anytime via SAGe, no fixed dates). A themed
**Jornada Tecnológica — Educação** chamada is also scheduled to launch
**13/10/2026** — a stronger thematic fit than the general-lot call this
deadline belonged to. Missing 29/07 costs nothing structurally; none of the
prep work (Súmula Curricular, CV, comparables research, desafio tecnológico
framing) is lost.

**New direction — physical Krebs model.** Instead of the software-only
spike, the desafio tecnológico is being reframed around a physical/
electromechanical tabletop translation of the gear/platform metaphor already
in `KrebsCycleDesign.md`: a real gear train (tooth count = platform count,
same derivation rule as the software version), ATP modeled as a powered
3-lobed "battery" object, LEDs/small screens for signals — mechanism still
being designed, not yet specced. The genuinely open technical question this
raises: can a physical mechanism honor the same scrub-safety discipline the
software enforces (jump to an arbitrary state, no passing through
intermediate frames)? Working answer: the software instance keeps the
jump-to-any-state property and *instructs* the physical rig into position —
the physical model behaves like a cyclical assembly line driven by the sim,
not an independent state machine solving scrub-safety on its own.

**This week's actual focus, instead of PIPE:** Embaúba website (design
language finished, built with Claude Design) and crowdfunding campaign
prep — vertical social video planning started.

**Still true, not lost:** the Proposta Simplificada draft, Súmula Curricular
work, and all 17 July eligibility findings carry forward unchanged whenever
a proposal is actually submitted — into fluxo contínuo, the Educação call,
or a later general-lot chamada.

---

## Next session — Embaúba revenue planning

Requested 16 July: a dedicated session on revenue sources + agentic skills for
running the company.

### Do the arithmetic first — it changes what gets built
Target: **R$5.000/month minimum, R$6.000 ideal.**

Against the tiers in the Plano:

| Route | Supporters needed for R$5k | Notes |
|---|---|---|
| Individual (~R$20 blended) | **~250 recurring** | apoia.se Contínua, minus 13% |
| Instituição/Professor (R$80-100) | **~55-60 recurring** | ~4x more efficient per relationship |

250 sustained recurring supporters, pre-launch, for a niche molecular-biology
simulator, would be exceptional — most campaigns plateau well below that. The
institutional tier reaches the number with roughly a fifth of the relationships.

**That reframes the professor demo**: it isn't only validation, it's a sales call
for the one tier that actually reaches R$5k. Different motion from crowdfunding
— B2E, not broadcast.

### Session agenda
- [ ] Which route is primary: volume (individual) or institutional? Decides the
      whole campaign shape.
- [ ] Buy Me a Coffee international track — **blocked**: confirm Stripe Connect
      payout support for Brazil before promoting widely (open pendência in the
      Plano).
- [ ] Cost the alternatives currently uncosted in the Plano: trancamento
      (restores Bolsa PE — price is a graduation delay; now lower priority
      since Auxílio PIPE doesn't require it), FAPESP Educação call
      (13/10/2026), **AUIN/NIT da Unesp — still marked *não explorado ainda***,
      IDB Lab, MIT Solve next cycle.
- [ ] Campaign copy PT-BR + EN.
- [ ] Agentic skills for running Embaúba — scope to be defined.
- [ ] Fun-mode / "Name an Enzyme" data structure (needs quiet name approval
      before shipping, given classroom use).

---

## Deferred (not urgent, don't lose)

- [ ] `_anchor_centered_frame()` byte-identical in `simulation.gd` and
      `replication_manager.gd` — the `_round_corners()` shape again. One
      duplicate, so not yet worth extracting.
- [ ] **Translation review — three items now, worth batching**: `_FULL`
      word-order inconsistency; "Pol épsilon" accent in pt_BR/es; "eucariota" vs
      "eucariótico" in the es `UI_TOPOLOGY_*` strings.
- [ ] Trademark clearance for Zymosim (INPI + WIPO/USPTO) — before any spend on
      logo/domain/campaign launch.
- [ ] `okazaki_manager.gd` extraction — still the one deferred extraction target.
- [x] ~~Retire `loop_test.gd`~~ — deleted.
- [ ] Retire SVG pipeline dead code (`polymerase_shape.gd`,
      `svg_to_polymerase_gd.py`).
- [ ] Remove the `L` locale-cycling debug keybind once locale switching has been
      exercised across a full session.
