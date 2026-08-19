extends CanvasLayer

# ==========================================
# WINDOW CHROME OVERLAY
# Screen-anchored overlay, independent of PlayerUI: a top-right close/exit
# button and a bottom-right Player UI visibility toggle (a resize-grip
# metaphor, deliberately sitting ON TOP of PlayerUI's own bottom bar).
#
# `simulation` is pushed in by simulation.tscn (node_paths-wired, same
# pattern PlayerUI.tscn's own `simulation` export uses) rather than looked
# up here, since this node has no scene-tree relationship to Simulation
# that would let %ZoomManager-style unique-name lookup reach it reliably.
#
# F2 and this overlay's own ToggleButton both funnel through
# simulation.gd's set_player_ui_visible() — the single source of truth —
# and this overlay stays in sync with EITHER trigger via
# player_ui_visibility_changed, not by tracking its own local state.
# ==========================================

const TEX_CROSS_SMALL: Texture2D = preload("res://icons/cross_small.png")
const TEX_CROSS_LARGE: Texture2D = preload("res://icons/cross_large.png")
const TEX_RESIZE_DIAGONAL: Texture2D = preload("res://icons/resize_c_cross_diagonal.png")
const TEX_RESIZE_PLAIN: Texture2D = preload("res://icons/resize_c_cross.png")

const PRESS_SCALE: float = 0.85
const DIMMED_ALPHA: float = 0.1

@export var simulation: Node2D

@onready var close_button: TextureButton = $CloseButton
@onready var toggle_button: TextureButton = $ToggleButton
@onready var exit_confirm_popup: ColorRect = $ExitConfirmPopup

var _toggle_hovering: bool = false

func _ready() -> void:
	close_button.texture_normal = TEX_CROSS_SMALL
	close_button.texture_hover = TEX_CROSS_LARGE
	close_button.texture_pressed = TEX_CROSS_SMALL
	close_button.tooltip_text = "UI_TOOLTIP_EXIT"
	close_button.button_down.connect(_on_close_button_down)
	close_button.button_up.connect(_on_close_button_up)
	close_button.pressed.connect(_on_close_pressed)

	toggle_button.tooltip_text = "UI_TOOLTIP_TOGGLE_PLAYER_UI"
	toggle_button.pressed.connect(_on_toggle_pressed)
	toggle_button.mouse_entered.connect(_on_toggle_hover.bind(true))
	toggle_button.mouse_exited.connect(_on_toggle_hover.bind(false))

	if simulation == null:
		push_error("WindowChromeOverlay: simulation node not assigned!")
		return
	exit_confirm_popup.simulation = simulation
	simulation.player_ui_visibility_changed.connect(_on_player_ui_visibility_changed)
	_sync_to_player_ui_visible(simulation.is_player_ui_visible())

## Press-squish feedback — texture_pressed alone only swaps the image, not
## the size; the "maybe at a smaller size" ask needs an actual scale change.
func _on_close_button_down() -> void:
	close_button.scale = Vector2.ONE * PRESS_SCALE

func _on_close_button_up() -> void:
	close_button.scale = Vector2.ONE

func _on_close_pressed() -> void:
	exit_confirm_popup.show_dialog()

func _on_toggle_pressed() -> void:
	if simulation != null:
		simulation.set_player_ui_visible(not simulation.is_player_ui_visible())

func _on_toggle_hover(hovering: bool) -> void:
	_toggle_hovering = hovering
	_update_toggle_alpha()

func _on_player_ui_visibility_changed(player_ui_visible: bool) -> void:
	_sync_to_player_ui_visible(player_ui_visible)

func _sync_to_player_ui_visible(player_ui_visible: bool) -> void:
	close_button.visible = player_ui_visible
	toggle_button.texture_normal = TEX_RESIZE_DIAGONAL if player_ui_visible else TEX_RESIZE_PLAIN
	_update_toggle_alpha()

func _update_toggle_alpha() -> void:
	if simulation != null and simulation.is_player_ui_visible():
		toggle_button.modulate.a = 1.0
	else:
		toggle_button.modulate.a = 1.0 if _toggle_hovering else DIMMED_ALPHA
