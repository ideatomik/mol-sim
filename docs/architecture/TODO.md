# TODO — working list

_Session close: 15 August 2026. Companion to STATUS.md (engineering state).
Funding/revenue tracking has moved to the Embaúba project — this file no
longer carries PIPE or crowdfunding items. **Contains no revenue targets as
of this pass; if that changes, restore the "keep out of any public repo"
handling note.**_

---

### Bugs
_None open._

### Features
- [ ] **Localization UI.** Replace the `L` debug locale-cycling keybind with
      a real user-facing language switcher. (Supersedes the old "remove the
      `L` keybind" housekeeping item — the debug mechanism was standing in
      for a UI that was never built.)

---

### Krebs — physical model (still open)
- [ ] Physical/electromechanical tabletop Krebs model. Design doc
      (`PhysicalKrebsDesign.md`) already exists — Lattice-phase, not yet
      approved or built — covering the gear train (tooth count = platform
      count, same derivation rule as the software version), the ATP
      3-lobed "battery" object, and LED/small-screen signaling. The
      scrub-safety-under-physical-motion question is worked through and has
      a working answer there (software keeps jump-to-any-state and
      instructs the rig; the rig is a cyclical assembly line that visibly
      travels to its commanded position, never rendering a mislabeled
      mid-state — a real weakening of the zero-mid-frame software rule,
      not a free pass). Remaining open items are the doc's own unresolved
      scope questions: battery-object scope, which stations get real
      mechanical motion vs. LED-only, fabrication path, and motor/control
      hardware — none decided yet.

---

### To verify (may already be done — confirm before acting)
- [ ] **Translation review batch**: `_FULL` key word-order inconsistency;
      "Pol épsilon" accent in pt_BR/es; "eucariota" vs "eucariótico" in the
      es `UI_TOPOLOGY_*` strings. Flagged as possibly already resolved —
      confirm against the current localization CSVs before treating as open.

---

### Deferred (cheap to keep, not urgent)
- [ ] `_anchor_centered_frame()` byte-identical in `simulation.gd` and
      `replication_manager.gd` — one duplicate, not yet worth extracting.
      Extract on the second copy per SKILL.md's "extract by what divergence
      costs" rule. Parked here rather than deleted since it's a one-line
      note to lose and a real debugging session to rediscover.

---

### Trademark
- [ ] Trademark/domain clearance for **Zymulador** (INPI + WIPO/USPTO) —
      before any spend on logo/domain/campaign launch. Supersedes the old
      "Zymosim" clearance item: every current doc, the skill file, and the
      repo naming convention have moved to Zymulador; `Zymulador_Plano_de_Projeto.md`
      (renamed from `Zymosim_Plano_de_Projeto.md`) still frames "Zymosim" as the
      evaluated candidate name in its trademark-analysis section, which is
      accurate as history, not a staleness gap. Worth a final confirm with
      wetware that Zymulador is the settled public-facing name before filing
      anything.

---

## Removed this pass (resolved, superseded, or relocated)

- ~~Retune `polymerase_label_margin` in vertical~~ — fixed.
- ~~Vertical mode~~ — feature itself is in cold storage; no open items
  tracked here until it's picked back up.
- ~~`okazaki_manager.gd` extraction~~ — predates Zymulador's expansion
  beyond a DNA/RNA-centered simulator; dropped rather than carried forward
  into the multi-process architecture.
- ~~PIPE / Embaúba revenue planning session agenda~~ (Stripe Connect
  confirmation, route prioritization, campaign copy, AUIN/NIT contact,
  etc.) — now tracked in the Embaúba project, not here.
- ~~Retire SVG pipeline dead code~~ (`polymerase_shape.gd`,
  `svg_to_polymerase_gd.py`) — confirmed gone.
- ~~"PC build, as-is, off the thumb drive" demo note~~ — tied to one past
  demo night, not a standing task.
