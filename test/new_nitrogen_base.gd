extends RigidBody2D
# class_name intentionally omitted -- adding a class_name here triggered
# Godot's project-wide class registry re-scan, which caused parse-order
# failures cascading through the production scripts (DnaStrand not found,
# NitrogenBase not found, etc.). Since rail_train_test.gd accesses this
# script's public methods directly via duck typing, the class_name isn't
# needed for correctness.

# ==========================================
# NEW_NITROGEN_BASE v2
# Added base type identity (A/T/C/G) and per-type fill colors matching
# the production nitrogen_base.gd palette. The body circle color is now
# driven by base_type via BASE_FILL rather than the generic body_color
# export. set_base_type() is the public setter -- call it after
# instantiation to assign the base and update visuals.
#
# set_body_color() is kept for the synthesis-completion magenta override
# (called by rail_train_test.gd when a slot turns magenta), but it now
# only overrides the Polygon2D fill directly -- it does not change
# base_type.
# ==========================================

const BASE_FILL: Dictionary = {
	"A": Color(0.8, 0.2, 0.2),   # red
	"T": Color(0.2, 0.2, 0.8),   # blue
	"C": Color(0.85, 0.6, 0.1),  # amber
	"G": Color(0.2, 0.8, 0.2),   # green
}

const BASE_LABEL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0) # white for all bases

@export_group("Base Identity")
## The nitrogen base type: "A", "T", "C", or "G".
## Set via set_base_type() after instantiation; do not set directly in
## the Inspector unless you also call _apply_base_appearance() manually.
@export var base_type: String = "A"

@export_group("Label")
## Font size of the label, in pixels.
@export var label_font_size: int = 14

@export_group("Body Visual")
## Radius of the base's circular visual body.
@export var body_radius: float = 10.0

@export_group("Physics")
## If true (default), this RigidBody2D stays kinematically frozen --
## positioned entirely by its parent nucleotide_slot, with zero physics
## influence. Set false only once real binding behavior is wired in.
@export var stay_frozen: bool = true

var label: Label
var body_poly: Polygon2D

func _ready():
	freeze = stay_frozen

	body_poly = Polygon2D.new()
	var points = PackedVector2Array()
	const SEGMENTS = 24
	for i in range(SEGMENTS):
		var angle = (float(i) / SEGMENTS) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * body_radius)
	body_poly.polygon = points
	add_child(body_poly)

	label = Label.new()
	label.add_theme_font_size_override("font_size", label_font_size)
	label.add_theme_color_override("font_color", BASE_LABEL_COLOR)
	add_child(label)

	_center_label.call_deferred()
	_apply_base_appearance()

func _center_label():
	if label:
		label.position = -label.size / 2.0

## Apply the fill color and label text for the current base_type.
func _apply_base_appearance():
	if body_poly:
		body_poly.color = BASE_FILL.get(base_type, Color(0.5, 0.5, 0.5))
	if label:
		label.text = base_type

## Public setter: assign a base type and update visuals immediately.
## This is the intended way to set the base after instantiation.
func set_base_type(new_type: String) -> void:
	base_type = new_type
	_apply_base_appearance()

## Public setter for the synthesis-completion color override (magenta).
## Only changes the visual fill -- does not affect base_type.
func set_body_color(new_color: Color) -> void:
	if body_poly:
		body_poly.color = new_color

## Public setter for the label text -- kept for compatibility but
## set_base_type() is preferred since it updates both label and color.
func set_label_text(new_text: String) -> void:
	if label:
		label.text = new_text
