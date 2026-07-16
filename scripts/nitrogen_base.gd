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
## The nitrogen base type: "A", "T"/"U", "C", or "G" (or "5'" / "3'" for markers).
## Set via set_base_type() after instantiation.
@export var base_type: String = "A"
## "circle" (default, DNA) or "rounded_square" (RNA) — accessibility: RNA
## primer bases must be distinguishable by shape, not color alone. Set via
## set_shape() after instantiation.
@export var shape: String = "circle"

@export_group("Label")
@export var label_font_size: int = 14

@export_group("Body Visual")
@export var body_radius: float = 10.0
## Hardcoded, not ThemeManager-driven — this node is deliberately
## ThemeManager-free (see the header comment); a rounding ratio is a shape
## constant, not something that needs per-project Inspector tuning the way
## colors/sizes do.
const ROUNDED_SQUARE_CORNER_RATIO: float = 0.35
const ROUNDED_SQUARE_CORNER_SEGMENTS: int = 4

@export_group("Physics")
## If true (default), this RigidBody2D stays kinematically frozen.
@export var stay_frozen: bool = true

var label: Label
var body_fill_color: Color = Color.WHITE

func _ready():
	freeze = stay_frozen

	queue_redraw()

	label = Label.new()
	label.add_theme_font_size_override("font_size", label_font_size)
	add_child(label)

	_center_label.call_deferred()

func _draw():
	if shape == "rounded_square":
		var half = body_radius
		var square = PackedVector2Array([
			Vector2(-half, -half), Vector2(half, -half),
			Vector2(half, half), Vector2(-half, half),
		])
		draw_polygon(_round_corners(square, ROUNDED_SQUARE_CORNER_RATIO, ROUNDED_SQUARE_CORNER_SEGMENTS), PackedColorArray([body_fill_color]))
	else:
		draw_circle(Vector2.ZERO, body_radius, body_fill_color, true, -1.0, true)

## NOTE: duplicated from helicase_ring.gd / polymerase_clamp.gd / ligase.gd /
## primase_blip.gd — same deferred shared-utility extraction all of those
## already flag.
func _round_corners(pts: PackedVector2Array, radius_ratio: float, segments: int) -> PackedVector2Array:
	var n = pts.size()
	if n < 3 or radius_ratio <= 0.0:
		return pts
	var out = PackedVector2Array()
	for i in range(n):
		var prev = pts[(i - 1 + n) % n]
		var cur = pts[i]
		var next = pts[(i + 1) % n]
		var to_prev = prev - cur
		var to_next = next - cur
		var len_prev = to_prev.length()
		var len_next = to_next.length()
		if len_prev < 0.0001 or len_next < 0.0001:
			out.append(cur)
			continue
		var r = radius_ratio * min(len_prev, len_next) * 0.5
		var p1 = cur + to_prev.normalized() * r
		var p2 = cur + to_next.normalized() * r
		for s in range(segments + 1):
			var t = float(s) / float(segments)
			var a = p1.lerp(cur, t)
			var b = cur.lerp(p2, t)
			out.append(a.lerp(b, t))
	return out

func _center_label():
	if label:
		label.position = -label.size / 2.0

## Set the base type and update the label text.
## Call set_colors() after this to apply the correct fill and font colors.
func set_base_type(new_type: String) -> void:
	base_type = new_type
	if label:
		label.text = new_type

## Set the body shape ("circle" or "rounded_square") and redraw.
func set_shape(new_shape: String) -> void:
	shape = new_shape
	queue_redraw()

## Apply fill and label colors. Called by simulation.gd after instantiation
## using values from %ThemeManager, keeping this node ThemeManager-free.
func set_colors(fill_color: Color, label_color: Color) -> void:
	body_fill_color = fill_color
	queue_redraw()
	if label:
		label.add_theme_color_override("font_color", label_color)

## Apply a new body radius, rebuilding the circular polygon.
## Called by the spawner using %ThemeManager.base_radius, keeping this
## node ThemeManager-free.
func set_radius(radius: float) -> void:
	body_radius = radius
	queue_redraw()

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
	body_fill_color = new_color
	queue_redraw()

## Kept for compatibility -- set_base_type() is preferred.
func set_label_text(new_text: String) -> void:
	if label:
		label.text = new_text
