extends RigidBody2D
# class_name intentionally omitted -- adding a class_name here triggered
# Godot's project-wide class registry re-scan, which caused parse-order
# failures cascading through the production scripts. Since simulation.gd
# accesses this script's public methods directly via duck typing, the
# class_name isn't needed for correctness.

# ==========================================
# NITROGEN BASE v4
# Purely visual -- no ThemeManager dependency. Colors are passed in by
# the caller (simulation.gd) via set_colors() after instantiation.
# This avoids node path issues when the base is deep in the scene tree.
# ==========================================

@export_group("Base Identity")
## The nitrogen base type: "A", "T", "C", or "G" (or "5'" / "3'" for markers).
## Set via set_base_type() after instantiation.
@export var base_type: String = "A"

@export_group("Label")
@export var label_font_size: int = 14

@export_group("Body Visual")
@export var body_radius: float = 10.0

@export_group("Physics")
## If true (default), this RigidBody2D stays kinematically frozen.
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
	add_child(label)

	_center_label.call_deferred()

func _center_label():
	if label:
		label.position = -label.size / 2.0

## Set the base type and update the label text.
## Call set_colors() after this to apply the correct fill and font colors.
func set_base_type(new_type: String) -> void:
	base_type = new_type
	if label:
		label.text = new_type

## Apply fill and label colors. Called by simulation.gd after instantiation
## using values from %ThemeManager, keeping this node ThemeManager-free.
func set_colors(fill_color: Color, label_color: Color) -> void:
	if body_poly:
		body_poly.color = fill_color
	if label:
		label.add_theme_color_override("font_color", label_color)

## Apply font size and optional custom font from ThemeManager.
## Call after set_colors() during spawning.
func set_font(font_size: int, font: Font = null) -> void:
	if label:
		label.add_theme_font_size_override("font_size", font_size)
		if font:
			label.add_theme_font_override("font", font)
		_center_label.call_deferred()

## Override the fill color only (used for synthesis debug highlighting).
## Does not affect base_type or label color.
func set_body_color(new_color: Color) -> void:
	if body_poly:
		body_poly.color = new_color

## Kept for compatibility -- set_base_type() is preferred.
func set_label_text(new_text: String) -> void:
	if label:
		label.text = new_text
