extends ColorRect

# ==========================================
# COMPLEXITY SETUP POPUP
# UI-only dialog for the Okazaki maturation toggles (OkazakiMaturationDesign.md).
# Shown once at startup (before SequenceLoaderPopup — see simulation.gd's
# _ready()) and reachable again mid-session via PlayerUI's Menu button.
# Toggles apply live to ComplexityManager as they're pressed, same immediate-
# apply pattern player_ui.gd already uses for WobbleToggle/NCloudToggle —
# there's no invalid state to validate, unlike SequenceLoaderPopup's sequence
# text, so no local-copy-plus-commit-on-OK step is needed here.
# ==========================================

## Emitted when the player presses Continue — simulation.gd's startup flow
## listens for this once, to know when to advance to SequenceLoaderPopup.
signal setup_confirmed

# --- DEBUG: Set to true to auto-show when running this scene alone (F6) ---
const DEBUG_AUTO_SHOW: bool = false

@onready var primase_toggle: CheckButton = $CenterContainer/DialogPanel/MarginContainer/MainLayout/PrimaseRow/PrimaseToggle
@onready var ligase_toggle: CheckButton = $CenterContainer/DialogPanel/MarginContainer/MainLayout/LigaseRow/LigaseToggle
@onready var pol1_toggle: CheckButton = $CenterContainer/DialogPanel/MarginContainer/MainLayout/Pol1Row/Pol1Toggle
@onready var continue_button: Button = $CenterContainer/DialogPanel/MarginContainer/MainLayout/ActionsRow/ContinueButton
@onready var cancel_button: Button = $CenterContainer/DialogPanel/MarginContainer/MainLayout/ActionsRow/CancelButton

var complexity_mgr: Node = null  # %ComplexityManager, resolved in _ready()

# Startup mode (set via show_dialog()'s is_startup param): there's no prior
# simulation state to cancel back to, so Cancel quits instead. Mid-session
# reopens (PlayerUI's Menu button) get the normal revert-and-close behavior.
var _is_startup_mode: bool = false

# Toggle values as of the moment this dialog was opened — since toggles
# apply LIVE to ComplexityManager as they're pressed (same immediate-apply
# pattern as WobbleToggle/NCloudToggle, not a stage-then-commit-on-OK
# pattern), "Cancel" means re-applying this snapshot through the same
# setters, not just hiding without acting.
var _snapshot_primase: bool = false
var _snapshot_ligase: bool = false
var _snapshot_pol1: bool = false

func _ready() -> void:
	complexity_mgr = get_node_or_null("%ComplexityManager")
	if complexity_mgr == null:
		push_error("ComplexitySetupPopup: %ComplexityManager not found!")
		return

	# Pol I's Complex tier isn't built yet (OkazakiMaturationDesign.md) —
	# shown disabled as a toggle-seam placeholder ahead of the feature, per
	# COMPLEXITY_MODEL.md's "gray out, don't hide" convention for a
	# dependent that can't yet be meaningfully turned on.
	pol1_toggle.disabled = true
	pol1_toggle.tooltip_text = tr("UI_POL1_COMING_SOON")

	primase_toggle.toggled.connect(_on_primase_toggled)
	ligase_toggle.toggled.connect(_on_ligase_toggled)
	continue_button.pressed.connect(_on_continue_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)

	# Keeps the checkboxes in sync if the bridge-toggle cascade force-flips a
	# sibling from elsewhere (e.g. once Pol I's Complex tier ships and gets
	# turned on from this same dialog) — see ComplexityManager.set_pol1_enabled().
	complexity_mgr.toggle_changed.connect(_on_complexity_toggle_changed)

	visible = false

	if DEBUG_AUTO_SHOW:
		show_dialog()

func show_dialog(is_startup: bool = false) -> void:
	_is_startup_mode = is_startup
	if complexity_mgr != null:
		_snapshot_primase = complexity_mgr.is_enabled("primase")
		_snapshot_ligase = complexity_mgr.is_enabled("ligase")
		_snapshot_pol1 = complexity_mgr.is_enabled("pol1")
		primase_toggle.set_pressed_no_signal(_snapshot_primase)
		ligase_toggle.set_pressed_no_signal(_snapshot_ligase)
		pol1_toggle.set_pressed_no_signal(_snapshot_pol1)
	# At startup there's no prior simulation state to cancel back to — Cancel
	# quits instead of reverting. Reused label per this project's stable-key
	# translation convention rather than a whole separate button.
	cancel_button.text = "UI_QUIT_BUTTON" if is_startup else "UI_CANCEL_BUTTON"
	visible = true

func hide_dialog() -> void:
	visible = false

# ----- SIGNAL HANDLERS -----

func _on_primase_toggled(pressed: bool) -> void:
	complexity_mgr.set_primase_enabled(pressed)

func _on_ligase_toggled(pressed: bool) -> void:
	complexity_mgr.set_ligase_enabled(pressed)

func _on_continue_pressed() -> void:
	setup_confirmed.emit()
	hide_dialog()

func _on_cancel_pressed() -> void:
	if _is_startup_mode:
		get_tree().quit()
		return
	# Revert any live-applied changes from this dialog session back to the
	# snapshot taken in show_dialog() — order matters: primase/ligase first,
	# pol1 last, so a snapshot with pol1_enabled == true (which implies both
	# siblings were already true when the snapshot was taken) restores
	# cleanly without set_pol1_enabled()'s own force-enable cascade
	# fighting the values being restored underneath it.
	if complexity_mgr != null:
		complexity_mgr.set_primase_enabled(_snapshot_primase)
		complexity_mgr.set_ligase_enabled(_snapshot_ligase)
		complexity_mgr.set_pol1_enabled(_snapshot_pol1)
	hide_dialog()

func _on_complexity_toggle_changed(feature: String, enabled: bool) -> void:
	match feature:
		"primase":
			primase_toggle.set_pressed_no_signal(enabled)
		"ligase":
			ligase_toggle.set_pressed_no_signal(enabled)
		"pol1":
			pol1_toggle.set_pressed_no_signal(enabled)
