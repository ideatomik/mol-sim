extends ColorRect

# ==========================================
# COMPLEXITY SETUP POPUP
# UI-only dialog for the Okazaki maturation toggles (OkazakiMaturationDesign.md),
# the topology mode, and the ATP activation lens (ATPCycleDesign.md).
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
@onready var cofactor_toggle: CheckButton = $CenterContainer/DialogPanel/MarginContainer/MainLayout/CofactorRow/CofactorToggle
@onready var cofactor_byproducts_toggle: CheckButton = $CenterContainer/DialogPanel/MarginContainer/MainLayout/CofactorByproductsRow/CofactorByproductsToggle
@onready var continue_button: Button = $CenterContainer/DialogPanel/MarginContainer/MainLayout/ActionsRow/ContinueButton
@onready var cancel_button: Button = $CenterContainer/DialogPanel/MarginContainer/MainLayout/ActionsRow/CancelButton

var complexity_mgr: Node = null  # %ComplexityManager, resolved in _ready()

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
var _snapshot_cofactor: bool = false
var _snapshot_cofactor_byproducts: bool = true

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
	cofactor_toggle.toggled.connect(_on_cofactor_toggled)
	cofactor_byproducts_toggle.toggled.connect(_on_cofactor_byproducts_toggled)
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
		# Read the RAW property, not is_enabled("cofactor_byproducts") — that call
		# folds the parent check in for consumers, so with the lens off it
		# would report false and this dialog would silently overwrite the
		# user's real byproducts setting on the next Cancel.
		_snapshot_cofactor = complexity_mgr.is_enabled("cofactor")
		_snapshot_cofactor_byproducts = complexity_mgr.cofactor_byproducts_visible
		cofactor_toggle.set_pressed_no_signal(_snapshot_cofactor)
		cofactor_byproducts_toggle.set_pressed_no_signal(_snapshot_cofactor_byproducts)
		_update_telomerase_gate(_snapshot_topology_mode)
		_update_cofactor_byproducts_gate(_snapshot_cofactor)
	# At startup there's no prior simulation state to cancel back to, and
	# nothing loaded yet for Cancel to close down to — same reasoning as
	# SequenceLoaderPopup's own is_startup param, hide it entirely rather
	# than repurpose it.
	cancel_button.visible = not is_startup
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

func _on_cofactor_toggled(pressed: bool) -> void:
	complexity_mgr.set_cofactor_activation_enabled(pressed)

func _on_cofactor_byproducts_toggled(pressed: bool) -> void:
	complexity_mgr.set_cofactor_byproducts_visible(pressed)

## Grey-out for the child of the "default-follows-parent, override-persists"
## cascade. Deliberately does NOT touch the checkbox's pressed state: the
## parent's own setter re-asserts true for real when the lens is enabled, and
## that arrives here through _on_complexity_toggle_changed() like every other
## cascade in this dialog. Same division of labour as _update_telomerase_gate().
func _update_cofactor_byproducts_gate(cofactor_on: bool) -> void:
	cofactor_byproducts_toggle.disabled = not cofactor_on
	# CSV keys renamed in the NAD+ pass (ATPCycleDesign.md) — the lens now
	# shows ATP in one mode and NAD+ in the other, so "ATP (energy cofactor)"
	# was no longer accurate copy in the mode it doesn't show ATP. See
	# ui_strings.csv: UI_COFACTOR_* replaces UI_ATP_* throughout this dialog.
	cofactor_byproducts_toggle.tooltip_text = "" if cofactor_on else "UI_COFACTOR_BYPRODUCTS_REQUIRES_COFACTOR_TOOLTIP"

## Grey-out + tooltip for the mode-gated telomerase checkbox — same treatment
## COMPLEXITY_MODEL.md calls for any child control under an incoherent mode
## (Telomerase in Circular, Tus–Ter in Linear once that tier exists).
## Doesn't touch the checkbox's pressed state — set_topology_mode()'s own
## cascade already handles that side by calling set_lagging_gap_enabled(false)
## for real, which arrives here via _on_complexity_toggle_changed().
# _update_cofactor_mode_note() and UI_ATP_BACTERIAL_LIGASE_NAD_TOOLTIP were
# REMOVED in the NAD+ pass (ATPCycleDesign.md). That tooltip existed to
# explain an ABSENCE — "ligase has no cofactor here" — and filling the
# absence with an actual NAD+ visual removed its reason to exist. Left as a
# comment rather than silently deleted, per this project's convention of
# recording divergences instead of letting them vanish without a trace.

func _update_telomerase_gate(mode: int) -> void:
	var linear: bool = mode == 1  # ComplexityManager.Topology.LINEAR
	telomerase_toggle.disabled = not linear
	telomerase_toggle.tooltip_text = "" if linear else "UI_TELOMERASE_REQUIRES_LINEAR_TOOLTIP"

func _on_continue_pressed() -> void:
	setup_confirmed.emit()
	hide_dialog()

func _on_cancel_pressed() -> void:
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
		# ATP restores parent-then-child for the same reason pol1 restores
		# last and topology restores before telomerase: the parent's cascade
		# force-sets the child true on every enable, so restoring the child
		# first would let set_cofactor_activation_enabled() stomp a value already
		# put back underneath it. Third instance of the same ordering trap in
		# this one function — the shape is now familiar enough that any future
		# toggle with a cascade should be added here parent-first by default.
		complexity_mgr.set_cofactor_activation_enabled(_snapshot_cofactor)
		complexity_mgr.set_cofactor_byproducts_visible(_snapshot_cofactor_byproducts)
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
		"cofactor":
			cofactor_toggle.set_pressed_no_signal(enabled)
			_update_cofactor_byproducts_gate(enabled)
		"cofactor_byproducts":
			cofactor_byproducts_toggle.set_pressed_no_signal(enabled)

func _on_topology_changed(mode: int) -> void:
	topology_option.select(mode)
	_update_telomerase_gate(mode)
