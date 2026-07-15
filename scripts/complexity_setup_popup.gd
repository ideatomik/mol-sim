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
@onready var topology_option: OptionButton = $CenterContainer/DialogPanel/MarginContainer/MainLayout/TopologyRow/TopologyOption
@onready var telomerase_toggle: CheckButton = $CenterContainer/DialogPanel/MarginContainer/MainLayout/TelomeraseRow/TelomeraseToggle
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
var _snapshot_topology_mode: int = 0  # ComplexityManager.Topology.CIRCULAR
var _snapshot_lagging_gap: bool = false

func _ready() -> void:
	complexity_mgr = get_node_or_null("%ComplexityManager")
	if complexity_mgr == null:
		push_error("ComplexitySetupPopup: %ComplexityManager not found!")
		return

	# Item order must match ComplexityManager.Topology enum order exactly
	# (CIRCULAR = 0, LINEAR = 1) — OptionButton.selected is used directly as
	# the enum value in _on_topology_selected() rather than through a lookup
	# table, so this ordering is load-bearing, not cosmetic.
	topology_option.clear()
	topology_option.add_item("UI_TOPOLOGY_CIRCULAR")  # Topology.CIRCULAR = 0
	topology_option.add_item("UI_TOPOLOGY_LINEAR")    # Topology.LINEAR = 1

	primase_toggle.toggled.connect(_on_primase_toggled)
	ligase_toggle.toggled.connect(_on_ligase_toggled)
	pol1_toggle.toggled.connect(_on_pol1_toggled)
	topology_option.item_selected.connect(_on_topology_selected)
	telomerase_toggle.toggled.connect(_on_telomerase_toggled)
	continue_button.pressed.connect(_on_continue_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)

	# Keeps the checkboxes in sync if the bridge-toggle cascade force-flips a
	# sibling from elsewhere (e.g. once Pol I's Complex tier ships and gets
	# turned on from this same dialog) — see ComplexityManager.set_pol1_enabled().
	complexity_mgr.toggle_changed.connect(_on_complexity_toggle_changed)
	# Mirrors toggle_changed above, for the mode-gate cascade specifically —
	# keeps telomerase_toggle's grey-out state in sync if topology_mode ever
	# changes from somewhere other than this dropdown.
	complexity_mgr.topology_changed.connect(_on_topology_changed)

	visible = false

	if DEBUG_AUTO_SHOW:
		show_dialog()

func show_dialog(is_startup: bool = false) -> void:
	_is_startup_mode = is_startup
	if complexity_mgr != null:
		_snapshot_primase = complexity_mgr.is_enabled("primase")
		_snapshot_ligase = complexity_mgr.is_enabled("ligase")
		_snapshot_pol1 = complexity_mgr.is_enabled("pol1")
		_snapshot_topology_mode = complexity_mgr.topology_mode
		_snapshot_lagging_gap = complexity_mgr.is_enabled("lagging_gap")
		primase_toggle.set_pressed_no_signal(_snapshot_primase)
		ligase_toggle.set_pressed_no_signal(_snapshot_ligase)
		pol1_toggle.set_pressed_no_signal(_snapshot_pol1)
		topology_option.select(_snapshot_topology_mode)
		telomerase_toggle.set_pressed_no_signal(_snapshot_lagging_gap)
		_update_telomerase_gate(_snapshot_topology_mode)
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

func _on_pol1_toggled(pressed: bool) -> void:
	complexity_mgr.set_pol1_enabled(pressed)

func _on_topology_selected(index: int) -> void:
	complexity_mgr.set_topology_mode(index)

func _on_telomerase_toggled(pressed: bool) -> void:
	complexity_mgr.set_lagging_gap_enabled(pressed)

## Grey-out + tooltip for the mode-gated telomerase checkbox — same treatment
## COMPLEXITY_MODEL.md calls for any child control under an incoherent mode
## (Telomerase in Circular, Tus–Ter in Linear once that tier exists).
## Doesn't touch the checkbox's pressed state — set_topology_mode()'s own
## cascade already handles that side by calling set_lagging_gap_enabled(false)
## for real, which arrives here via _on_complexity_toggle_changed().
func _update_telomerase_gate(mode: int) -> void:
	var linear: bool = mode == 1  # ComplexityManager.Topology.LINEAR
	telomerase_toggle.disabled = not linear
	telomerase_toggle.tooltip_text = "" if linear else "UI_TELOMERASE_REQUIRES_LINEAR_TOOLTIP"

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
	#
	# Same reasoning extends to topology: set_topology_mode() restores FIRST,
	# then set_lagging_gap_enabled() — so a snapshot of {Linear, telomerase
	# on} restores by first (re)entering Linear (a no-op if already there,
	# or a real switch if the session had flipped to Circular and silently
	# force-cleared telomerase along the way), THEN re-applying telomerase's
	# snapshot value on top. Restoring in the opposite order would let
	# set_topology_mode(CIRCULAR)'s own auto-disable cascade stomp a
	# telomerase value already restored underneath it, exactly the failure
	# mode the pol1 comment above already warns about for its own pair.
	if complexity_mgr != null:
		complexity_mgr.set_primase_enabled(_snapshot_primase)
		complexity_mgr.set_ligase_enabled(_snapshot_ligase)
		complexity_mgr.set_pol1_enabled(_snapshot_pol1)
		complexity_mgr.set_topology_mode(_snapshot_topology_mode)
		complexity_mgr.set_lagging_gap_enabled(_snapshot_lagging_gap)
	hide_dialog()

func _on_complexity_toggle_changed(feature: String, enabled: bool) -> void:
	match feature:
		"primase":
			primase_toggle.set_pressed_no_signal(enabled)
		"ligase":
			ligase_toggle.set_pressed_no_signal(enabled)
		"pol1":
			pol1_toggle.set_pressed_no_signal(enabled)
		"lagging_gap":
			telomerase_toggle.set_pressed_no_signal(enabled)

func _on_topology_changed(mode: int) -> void:
	topology_option.select(mode)
	_update_telomerase_gate(mode)
