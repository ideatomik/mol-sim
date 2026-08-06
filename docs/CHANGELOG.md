# MolSim — Changelog

Version history for the MolSim project. This file is the **single owner of
version history**. Nothing else in the project keeps a running version log.

**Ownership boundary** (see SKILL.md's "Version comments" section):

| Location | Owns |
| --- | --- |
| `simulation.gd` header | The **current version only**. What changed in this version, nothing older. |
| `CHANGELOG.md` (this file) | **All version history**, newest first. |
| `STATUS.md` | **Current state and why** — architecture, scene structure, pinned issues, resolved-bug lessons. Not a version log. |

When delivering a new version: move the outgoing version's block from
`simulation.gd`'s header into this file, then write the new version's block
in the header. The header never accumulates more than one version.

Entries below were seeded from `simulation.gd`'s accumulated header blocks
at the time this file was created. That header had retained v77, v76, v71.x,
and v70.6 while v72–v75 had been pruned at some point without record — those
four versions are genuinely absent from this log and are recoverable only
from git history and STATUS.md's narrative sections.

---

## [docs-only, not a version] Molecular Structure — Lattice phase complete (DNA-first milestone)

No code touched — recorded here anyway per explicit instruction, since this
closes a real planning phase worth having in the version history even
though the "version bump" rule (`SKILL.md`: "A documentation-only restructure
is not itself a version bump") correctly keeps it out of `simulation.gd`'s
header.

- `MolecularStructureDesign.md`'s Lattice phase (Crystal Building Method) is
  now fully grounded and resolved for the DNA-first milestone: all six
  originally-flagged files read across three ground-truth-correction passes
  (13 corrections total, `replication_manager.gd` — 3,144 lines — the last),
  and every open question that bears on the milestone is decided.
- Two new companion resolution docs: `MolecularStructure_OpenQuestions_RenderClusterResolution.md`
  (questions 4/7/8/9, plus new question 10 — render-mode selection inside
  free-camera mode, hysteresis band verified against `zoom_manager.gd`,
  atom-picking and culling scoped out for this milestone) and
  `MolecularStructure_OpenQuestions_Q3Q5Resolution.md` (question 5 —
  operator-authoring format, fixed four-array diff interface; question 3's
  milestone slice — ribose handedness as a hardcoded deriver constant).
- Questions 1 (aconitase) and 6 (ATP bead-chain migration) parked
  indefinitely, correctly out of scope until the full Krebs build.
- `ClaudeCode_Handout_MolecularStructure.md` (the Growth-phase kickoff brief)
  updated to match — the stale "six files unread" framing is gone.
- The stale root-level `SKILL.md` duplicate (v70.3) was also removed this
  pass; `docs/SKILL.md` (v77.0) is the sole current copy.
- **Next**: Growth phase — implement against the scope fence (ribose ring
  deriver, phosphodiester operator, skeletal rendering gated to free-camera
  deep zoom). No implementation code exists yet as of this entry.

---

# ==========================================
# v 82 — self-paired reflect fix + atom-tier label zoom tiers
# - Self-paired residues (template_top/template_bottom pairing with
#   themselves at the fork) now render via RiboseDeriver.
#   reflect_about_backbone_axis() — both residues reflected about their
#   own POST-rotation C3'-C4' line, not the pre-rotation natural ring
#   (the actual bug: the old mirror reflected one frame while the
#   substituent chain was built from the other, producing an exact
#   O3'=C4'/C5'=C3' coordinate collision). The old bake system
#   (bake_self_paired_geometry(), the bounded rotation-angle search) is
#   bypassed, not deleted, in case it's needed again.
# - Carries an on-screen hover disclaimer while the reflect transform is
#   active — "in 2D molecular representations this rotation doesn't
#   really exist, but for didactic reasons, we're showing you this way."
#   (docs/superpowers/specs/2026-08-04-fork-flip-disclaimer-design.md)
# - Fixed an unrelated spacing bug found along the way: self-paired
#   strands' render-only MOLECULAR_ROW_PUSH was 50 units wider than
#   leading/lagging's own spacing; halved to match exactly.
# - New docs/MolecularStructureDesign.md correction: the chirality-safety
#   shoelace check is a flat 2D proxy for a 3D property, correctly scoped
#   to catch only in-page rotations — an out-of-page rotation (this fix's
#   own reflect) is physically chirality-preserving but indistinguishable
#   from a mirror on this renderer's flat projection, hence the
#   disclaimer rather than pretending it's chirality-neutral.
# - Diagnostics extracted out of molecule_structure_renderer.gd into a
#   new scripts/molecule_geometry_diagnostics.gd (F9 dump, unchanged
#   behavior, just relocated).
# - Atom-tier skeletal labels (docs/atomtier/AtomTier_VisualDesign.md
#   Part 1): a second, nested zoom threshold inside skeletal mode
#   (molecular_label_zoom_enter_threshold / _exit_threshold, its own
#   hysteresis pair, independent of the skeletal on/off pair) now
#   switches atom labels between two fixed bands — element-only (C, O,
#   P, N) further out, full chemistry notation (C3', Pα, ...) once
#   zoomed in past the new threshold — each with its own ThemeManager
#   font-size field, no continuous interpolation.
#
# CURRENT VERSION ONLY. Prior versions live in CHANGELOG.md — when
# delivering a new version, move this block there first, then write the new
# one here. This header never accumulates more than one version.
# ==========================================

# ==========================================
# v 81 — NAD+ pass (bacterial ligase gets its cofactor)
# - is_enabled("ligase_cofactor") stopped being a topology GATE and became a
#   plain proxy for cofactor_activation_enabled — ligase has a cofactor in
#   BOTH modes now. WHICH one is a separate question, answered by the new
#   ComplexityManager.ligase_uses_nad() (true in Circular/bacterial mode),
#   deliberately kept out of is_enabled() itself: mixing a mode PARAMETER
#   into that boolean would make "false" ambiguous between "lens off" and
#   "wrong donor for this mode."
# - ligase_cofactor.gd: _ppi_group -> _leaving_group. New donor_is_nad flag,
#   set by replication_manager.gd from ligase_uses_nad() before every
#   begin_carry() (topology can change between one seal and the next). New
#   _apply_donor(): ATP -> second bead "P" + thick fused link (PPi, must not
#   read as two loose Pi); NAD+ -> second bead "N" + ordinary link (NMN's two
#   beads are already visually distinct by colour, so the fused treatment
#   would falsely claim a "rigid unit" NMN doesn't have). The AMP half is
#   entirely untouched — adenylylation is chemically identical for both
#   donors, so nothing there needed to change.
# - New ThemeManager field: cofactor_nicotinamide_color.
# - complexity_setup_popup.gd: _update_cofactor_mode_note() REMOVED — it
#   explained an absence ("ligase has no cofactor here"), and the absence is
#   filled. Left as a comment rather than silently deleted.
# - ui_strings.csv: UI_ATP_TOGGLE_LABEL / UI_ATP_BYPRODUCTS_TOGGLE_LABEL /
#   UI_ATP_BYPRODUCTS_REQUIRES_ATP_TOOLTIP -> UI_COFACTOR_* (copy updated:
#   byproducts list now includes NMN). UI_ATP_BACTERIAL_LIGASE_NAD_TOOLTIP
#   deleted outright, not carried forward.
# - Zero helicase changes. Its bonds and byproducts are still pure ATP
#   (helicase runs on ATP in every domain — see v80's header on why atp_*
#   stayed atp_* there).
#
# CURRENT VERSION ONLY. Prior versions live in CHANGELOG.md — when
# delivering a new version, move this block there first, then write the new
# one here. This header never accumulates more than one version.
# ==========================================

# ==========================================
# v 80 — cofactor rename (no behavior change)
# - The ATP lens outgrew its name before shipping a second cofactor. NAD+ is
#   next, and FAD / CoA / GTP arrive with Krebs; a namespace called after one
#   of its members ages badly. Shared identity is now cofactor_*.
# - Renamed here: atp_cycle -> helicase_atp_cycle (MORE specific, not less —
#   it was always helicase-only and the bare name implied otherwise), and the
#   ThemeManager pushes now read cofactor_* / cofactor_head_scale.
# - DELIBERATELY NOT renamed: this file's helicase timeline fields
#   (atp_spawn_lead_ratio, atp_spark_window, atp_byproduct_fade_end_eased,
#   atp_pi_*, atp_approach_offset). Helicase runs on ATP in every domain, so
#   atp_ is honest there and generalizing it would make the code LESS precise.
#   Two prefixes coexisting is the labeled-chimera principle applied to field
#   names — shared thing shared, divergent thing labeled.
# - atp_adenine_scale -> cofactor_head_scale: adenine holds for ATP, NAD+,
#   FAD and CoA, then breaks on GTP. Named for the role, not the molecule.
# - CSV keys stay UI_ATP_* this pass; they get fixed with the copy in the
#   NAD+ pass, when the copy actually needs to change.
# - Zero behavior change. simulation.tscn needed no edits: it had no
#   serialized atp_* overrides, so nothing had to be migrated.
#
# CURRENT VERSION ONLY. Prior versions live in CHANGELOG.md — when
# delivering a new version, move this block there first, then write the new
# one here. This header never accumulates more than one version.
# ==========================================

## v79 — ATP cycle (ligase pass)

- New `ligase_atp.gd` (**renamed to `ligase_cofactor.gd` in v80**) — the
  ligase half of the cofactor-activation lens. A child of the ligase node,
  which inherits hide-on-scrub, the end-of-run `modulate` fade, and offstage
  parking for free, since all three already act on `ligase` itself.
- **Deliberately tween-driven, unlike the helicase half.** `ligase.gd` is
  hidden entirely during scrub, so it inherits no reconstruct-instantly
  contract and real tween timing is legitimate. Recorded as a deliberate
  asymmetry between the two halves of one lens, not an oversight.
- Hooked into `replication_manager.gd`'s existing seal chain at four points:
  carry begins with the travel tween; the spark fires at the
  `TRAVELING` → `HOLDING` boundary (never mid-travel — the cofactor activates
  only once the enzyme has engaged the nick); the AMP hop runs between the
  seal pulse's two halves, so it parallels the RELEASE half rather than the
  pinch; AMP release fires at `_ligase_finish_seal()`.
- New named callbacks `_ligase_enter_holding()` and `_ligase_atp_hop()`
  rather than multi-line lambdas at the two new hook points — GDScript's
  multi-line lambda parsing is fragile, and the one pre-existing lambda in
  that chain was a single expression.
- **Answers the question `ATPCycleDesign.md` was built to ask.** Helicase
  (clock-driven) and ligase (event-count-gated) share the glyph vocabulary,
  the ThemeManager identity group and the toggle — and share **no** timing
  machinery. The trigger philosophy follows from the SCRUB CONTRACT, not from
  the enzyme. Carry this to the pump and to Krebs: ask what scrub does to an
  enzyme first, and the mechanism falls out.
- Eukaryotic-mode gating via `is_enabled("atp_ligase")` (**renamed to
  `"ligase_cofactor"` in v80**), folding the topology check in so
  `replication_manager.gd` never learns topology exists — second registered
  use of the mode-gate pattern `set_topology_mode()` introduced for
  `lagging_gap`. Bacterial ligase runs on NAD⁺, whose byproduct NMN shares no
  shape with a phosphate chain, so reusing the ATP glyph in circular mode
  would actively teach something false.
- `is_enabled("atp")` is deliberately **not** topology-gated: helicase runs
  on ATP in both domains.
- ThemeManager gains `atp_fused_link_width` / `atp_fused_link_color` (PPᵢ's
  fused connector — the only genuinely new geometry in the design, and it
  must never read as two loose phosphates), `atp_discard_drift`,
  `atp_spark_duration` and `atp_fade_duration` (both **seconds** here, unlike
  the helicase half's `step_t`-space equivalents), plus
  `ligase_atp_carry_offset`, `ligase_atp_nick_offset` and
  `ligase_amp_hop_duration`. All renamed in v80 except
  `ligase_amp_hop_duration`, which was already domain-neutral — AMP is the
  carried intermediate for both donors.
- Two independent tweens (`_ppi_tween`, `_amp_tween`) rather than one: a
  shared tween meant `hop()` would kill the PPᵢ fade mid-flight whenever
  `atp_fade_duration` was tuned longer than `ligase_hold_duration`, freezing
  it half-transparent until the next reset. Default timings hide it, which is
  what made it a trap rather than a saving.
- `simulation.gd` unchanged apart from its version header.

## v78 — ATP cycle (helicase pass)

- New `atp_cycle.gd` (**renamed to `helicase_atp_cycle.gd` in v80**), built
  in `_setup_helicase()` as a SIBLING of `helicase_ring` under
  `helicase_node`. Inherits the node's position and `modulate` for free;
  ThemeManager-free like the ring, so its whole config is pushed from
  `simulation.gd`.
- New `atp_bead.gd` (**renamed to `cofactor_bead.gd` in v80**) — a pooled
  glyph bead. Copies `nitrogen_base.gd`'s visual vocabulary (`draw_circle`
  antialiased, the `pivot_offset` label-centering fix) without inheriting its
  `RigidBody2D` overhead.
- **Derived, not event-driven.** `helicase.gd`'s `scrub_to_slot()` never
  emits `slot_reached`, so any signal-triggered spark would be
  unreconstructible by scrub. Deriving everything from
  (`slot_index`, `step_t`) removes the problem rather than working around it,
  and scrub-safety comes for free with zero rebuild logic.
- `_process()` section 1 resolves **both** progress values at the boundary —
  `get_step_t()` raw for the spawn threshold, `get_eased_step_t()` for drift
  — and passes them pre-named. The cubic ease-out maps raw 0.7 to eased
  0.973, so testing the spawn threshold against the eased value would have
  fired the approach at 97% of the step with nothing visible. The cycle file
  holds no easing logic at all and therefore has nothing to get wrong.
- Also resolves `discard_origin` using the same `last_valid` extrapolation
  branch `helicase_x` uses, and subtracts `helicase_x` once so the cycle
  stays in pure local space.
- Runs in section 1 (always, even paused and scrubbed) deliberately: pausing
  to say "the ATP just cleaved here" is the classroom case, so the cycle
  freezes visible and correct rather than hiding.
- Toggles added to `complexity_manager.gd` — `atp_activation_enabled`,
  `atp_byproducts_visible` (both **renamed to `cofactor_*` in v80**) — with a
  **fourth named cascade pattern**, "default-follows-parent,
  override-persists": enabling the parent re-asserts the child true every
  time; the user may override freely; the parent going off does not clear the
  override. Placed here rather than in ThemeManager (where the older
  `wobble_enabled` lens lives) because `complexity_setup_popup.gd` syncs its
  checkboxes only through `toggle_changed` and reverts on Cancel only by
  replaying setters that live in ComplexityManager.
- ThemeManager gains an `ATP Cycle` group (**renamed `Cofactor` in v80**) for
  the cofactor's shared identity, plus helicase-specific timeline fields in
  the Helicase Ring group: `atp_spawn_lead_ratio`, `atp_spark_window`,
  `atp_byproduct_fade_end_eased`, `atp_pi_x_ratio`, `atp_pi_rise_distance`,
  `atp_approach_offset`. **These six survive v80's rename** — helicase runs
  on ATP in every domain, so the prefix is honest there.
- The head bead pushes `base_color_a` verbatim with no colour field of its
  own: ATP's adenine IS the DNA base's adenine, and two independently-tuned
  colours that are only supposed to agree is exactly the coincidence this
  project's rule forbids.
- Bead labels get `_zoom_label_rotation()` pushed, same as the ring's — the
  "A"/"P" glyphs are drawn text and would have shipped sideways in vertical
  mode. Not in the design doc; caught at Lattice review.
- Two new rows in `ComplexitySetupPopup.tscn` and three new `ui_strings.csv`
  keys (`UI_ATP_TOGGLE_LABEL`, `UI_ATP_BYPRODUCTS_TOGGLE_LABEL`,
  `UI_ATP_BYPRODUCTS_REQUIRES_ATP_TOOLTIP`); a fourth,
  `UI_ATP_BACTERIAL_LIGASE_NAD_TOOLTIP`, was added afterwards to label the
  bacterial-ligase divergence rather than leave it silent.


## v77 — Vertical mode

- New `_swap_in_vertical_player_ui(zoom_mgr)`, called from `_ready()`: when
  `ZoomManager.vertical_mode` is on, replaces the editor-wired PlayerUI
  instance with a runtime-instantiated `VerticalPlayerUI.tscn` (same script,
  `player_ui.gd`, renamed "PlayerUI" to keep the node path stable). Falls
  back to the horizontal UI with a `push_error()` if the swap can't find what
  it needs, rather than soft-locking — same degrade-gracefully shape as
  v76's popup fallback.
- `_zoom_label_rotation()` pushes `ZoomManager.get_label_counter_rotation()`
  into helicase_ring/polymerase clamps' labels — `simulation.gd` stays the
  single place that asks, rather than five enzyme scripts each reading
  `get_viewport()` and pre-judging an axis. See `VerticalModeDesign.md`.
- `request_drag_scrub()`'s axis pick (`zoom_mgr.vertical_mode`) is the only
  place drag-to-scrub itself needed to change — screen-space delta in,
  world-x-equivalent slot delta out, same either way.

### v77 continued — Follow mode & camera fixes

- New `_on_helicase_ring_follow_requested()`, connected alongside the
  existing `scrub_drag_started`/`scrub_drag_delta` wiring: routes
  `helicase_ring.gd`'s `follow_requested` signal (double-click) into
  `zoom_mgr.request_follow("helicase")`. Lagging polymerase's own connection
  lives in `replication_manager.gd`, which owns that clamp directly — leading
  polymerase gets the same signal for free (shared `polymerase_clamp.gd`) but
  nothing connects it, by product decision.
- `_swap_in_vertical_player_ui()` now also injects
  `vertical.zoom_mgr = zoom_mgr` by hand, same treatment as the pre-existing
  `vertical.simulation = self` one line above it — `%ZoomManager`'s own lookup
  in `player_ui.gd`'s `_ready()` can't cross the scene-ownership boundary a
  runtime-instantiated child scene sits behind, which is what silently broke
  `ResetZoomButton` in vertical mode until this pass. See STATUS.md's "Follow
  Mode, Click-Drag Dead Zone & Related Camera Fixes" for the full writeup,
  and `ZoomDesign.md`'s As-Built addendum for Follow Mode's own design.

---

## v76 — Complexity setup startup gate

- `_ready()` no longer auto-generates a random default sequence and calls
  `initialize_simulation()` directly. Instead it shows `ComplexitySetupPopup`
  (Pol I / Ligase / Primase toggles, backed by the new `ComplexityManager`
  node) first, then `SequenceLoaderPopup` — reusing PlayerUI's existing
  `sequence_loaded -> initialize_simulation()` wiring for the actual load
  rather than adding a second listener on the same signal.
- New `_on_startup_complexity_confirmed()` bridges the two popups. Falls back
  to the old random-sequence boot if either popup node is missing, so a
  broken scene reference degrades gracefully instead of soft-locking at a
  popup that will never show.
- See `OkazakiMaturationDesign.md` for the toggle set and cascade logic.

---

## v72–v75 — not recorded here

These four versions were pruned from `simulation.gd`'s header before this
changelog existed. Their content is recoverable from git history, and
STATUS.md carries narrative accounts of several passes from this range
(notably the v75 drag-to-scrub bug set: the missing
`lagging_polymerase_tween.kill()` in `scrub_rebuild()`, and the background
`ColorRect` left at `mouse_filter = Stop`).

---

## v71.x — Helicase ring

- Placeholder capsule in `_setup_helicase()` replaced by `HelicaseRing`
  (`helicase_ring.gd`): six see-through octagonal blobs in a barrel-roll,
  parented under `helicase_node`, rides its position/modulate/fade for free.
- `_process()` now feeds `helicase_ring.set_roll(idx + eased)`
  unconditionally (same block that already derives `helicase_x` every frame
  regardless of `manual_override`) and sets
  `rotation_frozen = manual_override or !ThemeManager.helicase_ring_rotation_enabled`
  — freezes to a static symmetric pose on scrub/pause, same treatment the
  polymerase clamp's DOWN-state-on-scrub already gets. No changes needed in
  `scrub_to()` / `scrub_to_lagging_catchup()` — they set `step_t` via
  `scrub_to_slot()`, which this block picks up on the next frame regardless.
- ThemeManager: new "Helicase Ring" export group. Old "Helicase" group left
  in place (unused fields, cheap to leave; retire in a later cleanup pass
  once the ring is confirmed stable).

---

## v70.6 — Helicase-anchored positioning

- Debug visuals removed (`debug_gap_line`, `debug_top_rail_line`, PLL
  zigzag) — they served their purpose validating the PLL geometry math.
- `gap_width` replaced by `polymerase_x_offset_slots` (float multiplier on
  `nucleotide_slot_spacing`, default 4.0) — `polymerase_x` is now computed
  directly off `helicase_x` rather than via a separate fixed pixel constant.
- `new_bottom_template_offset` renamed to `polymerase_y_offset` — the
  vertical distance each polymerase sits from `center_y` (the helicase's y).
- `factory_x`/`factory_y` renamed to
  `polymerase_x`/`polymerase_y_lagging`; the leading polymerase's y is
  `polymerase_y_leading`. Both are computed directly from
  `helicase_node.position`, which is now the single source of truth for
  replisome positioning.
- `replication_manager.gd` Phase 1 + Phase 2 complete; `simulation.gd` is
  purely template manager + visual coordinator.
