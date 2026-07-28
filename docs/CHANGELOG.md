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
