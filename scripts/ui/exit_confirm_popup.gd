extends ColorRect

# ==========================================
# EXIT CONFIRM POPUP
# PlaybackShortcutsDesign.md — a one-click, no-undo quit was flagged as a
# real risk given the classroom/demo deployment context (an accidental
# click during a live professor demo ends the session with no way back).
# Same popup shape as ComplexitySetupPopup/SequenceLoaderPopup (ColorRect
# dim overlay, CenterContainer > DialogPanel > MarginContainer >
# MainLayout, ActionsRow with two buttons), but lives inside
# WindowChromeOverlay's own CanvasLayer (layer = 100) rather than nested
# under UI like those two — WindowChromeOverlay's own buttons already
# render above everything at that layer; a popup under UI's default layer
# would render BEHIND them, leaving the always-on-top Exit/Toggle icons
# visually floating over the dimmed dialog.
#
# BodyLabel ("Any unsaved progress will be lost.", UI_CONFIRM_EXIT_BODY) is
# set invisible in the scene for now — there's no save/progress system yet,
# so the warning isn't true. Key + node both kept in place; flip
# BodyLabel.visible back to true once there's real progress to lose.
# ==========================================

@export var simulation: Node2D  # injected by window_chrome_overlay.gd at _ready()

@onready var confirm_button: Button = $CenterContainer/DialogPanel/MarginContainer/MainLayout/ActionsRow/ConfirmButton
@onready var cancel_button: Button = $CenterContainer/DialogPanel/MarginContainer/MainLayout/ActionsRow/CancelButton

## Whether the sim was actively playing before show_dialog() paused it —
## Cancel restores this exactly, rather than unconditionally toggling
## back (which would incorrectly resume an already-paused sim).
var _was_playing: bool = false

func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	visible = false

func show_dialog() -> void:
	if simulation != null:
		_was_playing = not simulation.manual_override
		if not simulation.manual_override:
			simulation.toggle_play()
	visible = true

func hide_dialog() -> void:
	visible = false

func _on_confirm_pressed() -> void:
	get_tree().quit()

func _on_cancel_pressed() -> void:
	if simulation != null and _was_playing and simulation.manual_override:
		simulation.toggle_play()
	hide_dialog()

## First real use of Esc anywhere in this project (confirmed no existing
## binding conflicts) — scoped narrowly to this popup's own cancel action,
## same as Enter mirrors Confirm. Doesn't preclude a future broader
## fullscreen-Esc rework; this is local to the popup's own input handling.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			_on_confirm_pressed()
			get_viewport().set_input_as_handled()
