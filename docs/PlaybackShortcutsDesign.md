# Playback Shortcuts & Exit Confirmation — Design (Lattice)

Status: approved, ready for Growth phase. All open questions resolved.
Scope: `player_ui.gd` (`_unhandled_input()`), `window_chrome_overlay.gd`, `simulation.gd`.

## 1. Problem / Nucleation

`player_ui.gd` currently binds only what's needed for mouse/UI-driven playback
control. We're adding a full keyboard layer for transport, scrubbing, speed,
zoom, and enzyme-target navigation, so the player UI is usable without
reaching for the mouse — useful both for fast iteration during dev and for
smoother classroom demos.

Separately, `window_chrome_overlay.gd` (shipped today) added a top-right Exit
button that calls `get_tree().quit()` immediately, no confirmation. Given the
classroom/demo context this ships into, an accidental click during a live
professor demo is a real cost (lost session, no undo). This doc folds in a
confirmation popup for that action alongside the new keyboard bindings, since
both changes touch the same input-handling surface.

## 2. Key bindings (final list, confirmed this session)

| Key | Action | Existing API called |
|---|---|---|
| Space | Play/pause | existing toggle |
| ← / → | Step one base | new: `_step_base(direction)` |
| Shift+← / Shift+→ | Jump one Okazaki fragment | new: `_step_fragment(direction)`, reuses `replication_manager.gd`'s `i % okazaki_fragment_size == 0` boundary logic |
| [ / ] | Speed down/up | existing speed setter |
| = / - | Zoom in/out one level | `zoom_mgr.set_zoom_level()` |
| 1–4 | Jump to zoom tier | `zoom_mgr.set_zoom_level(n)` |
| Q / E | Cycle enzyme target back/forward | `zoom_mgr.cycle_target(-1)` / `cycle_target(1)` |
| F2 | Toggle player UI visibility | `simulation.set_player_ui_visible()` (already shipped, now also fires `player_ui_visibility_changed`) |
| F3 | Toggle enzyme labels | existing `tm.enzyme_labels_enabled` |

Deliberately **not bound**: Esc. No fullscreen mode exists — Zymulador
launches maximized-windowed by design, specifically because college projector
setups are frequently misconfigured in ways neither students nor faculty are
permitted to fix, and a hidden window title bar would otherwise strand the
user with no way to un-fullscreen. Esc can be introduced later alongside a
real UI rework, once there's an actual fullscreen state for it to exit.

Deliberately **not Tab**: reserved by Godot for `Control` focus navigation
and by Windows for Alt+Tab (OS-level, unreachable from inside Godot). Q/E
avoids both collisions outright rather than requiring a `focus_mode`
audit across every `Control` in the scene.

### No collision with existing mouse mechanics

Confirmed: mouse drag (enzyme drag / camera pan), mouse-wheel zoom, and
double-click select are `InputEventMouseMotion` / `InputEventMouseButton`;
all new bindings above are `InputEventKey`. Different event types, same
`_unhandled_input()` function, no interference. One QCA item: confirm
`=/-` (keyboard zoom) and mouse-wheel zoom both terminate at
`set_zoom_level()` so they can't disagree — expected to already hold, per
the "one API, many triggers" pattern this project already uses for
`select_target()`/`cycle_target()`.

## 3. Exit confirmation popup

### Current behavior (shipped today, this session)
`WindowChromeOverlay`'s Exit button (`cross_small.png`/`cross_large.png`,
hover-grow + press-squish feedback) calls `get_tree().quit()` directly on
click. No confirmation.

### Change
Exit button click opens a confirmation popup instead of quitting directly.
Popup confirms → `get_tree().quit()`. Popup cancels / clicks outside →
no-op, returns to whatever state the sim was already in (paused or playing,
unchanged — the popup does not force a pause; open question below).

### Why
Flagged as a real risk given deployment context: professor demos are
effectively sales calls (per current PIPE/crowdfunding institutional-tier
positioning), and the Exit button's own hover-grow animation is designed to
invite exactly the kind of curious click that would end a session
mid-pitch. A one-click no-undo quit is disproportionate to the
low-frequency, high-cost nature of this action.

### Implementation shape
- New popup scene, matching the project's existing popup pattern
  (`ComplexitySetupPopup`, `sequence_loader_popup.gd`) rather than a new
  one-off mechanism.
- Two buttons: confirm ("Exit Zymulador" / "Sair do Zymulador" /
  localized es) and cancel.
- Localization keys: `UI_CONFIRM_EXIT_TITLE`, `UI_CONFIRM_EXIT_BODY`,
  `UI_CONFIRM_EXIT_YES`, `UI_CONFIRM_EXIT_NO` — same raw-key
  auto-refresh-on-locale-change convention as `UI_TOOLTIP_EXIT` /
  `UI_TOOLTIP_TOGGLE_PLAYER_UI`.
- Popup is screen-anchored like `WindowChromeOverlay` itself (same
  `CanvasLayer`, or a sibling one drawn above it) — it must remain visible
  and clickable even if `PlayerUI` is currently hidden via F2, since the
  Exit button itself stays visible/reachable regardless of F2 state.

### Open questions — resolved

- **Does opening the popup pause the simulation? → Yes.** Pause on popup
  open; restore the prior play/pause state on cancel. No special handling
  needed on confirm (quitting either way). Free to implement — scrub-safe,
  no state loss.
- **Keyboard support inside the popup? → Esc = cancel, scoped narrowly.**
  This is Esc's *only* bound meaning anywhere in the project right now
  (Section 2 — no fullscreen state exists yet for a broader Esc binding).
  Enter = confirm is unaffected by this and stays in scope. This narrow
  binding does not preclude or complicate the future fullscreen-Esc rework;
  it's local to the popup's own input handling and can be folded into (or
  left alongside) that later work without conflict.
- **Does F2 (hide player UI) affect the popup once open? → No, popup is
  modal.** Once open, the popup owns input until dismissed — F2 does
  nothing while it's up, same as any other modal popup in the project
  (`ComplexitySetupPopup`, `sequence_loader_popup.gd`). Reduces state space:
  no need to reason about what "player UI hidden + exit popup open"
  visually looks like, since F2 simply can't fire in that window.

## 4. Out of scope for this pass

- Any change to `WindowChromeOverlay`'s player-UI-toggle button (bottom
  right) — unaffected by this doc.
- Esc-to-exit-fullscreen — deferred to the future UI rework mentioned this
  session, once Zymulador has more simulations and fullscreen becomes
  relevant.
- Gamepad/controller bindings — not discussed, not in scope.

## 5. Suggested implementation order

1. Keyboard block in `player_ui.gd` (`_unhandled_input()`), transport +
   scrub + speed + zoom + Q/E cycling. Independently QCA-able, no
   dependency on the popup.
2. Exit confirmation popup scene + `window_chrome_overlay.gd` wiring
   (Exit button → popup → confirm/cancel).
3. Localization keys for the popup, matching existing tooltip convention.

Each step ships and QCAs independently; no step blocks another.
