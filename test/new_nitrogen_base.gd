extends RigidBody2D
class_name NewNitrogenBase

# ==========================================
# NEW_NITROGEN_BASE v1
# A fresh, standalone script -- does NOT touch or derive from the real
# production nitrogen_base.gd. Meant to be the child RigidBody2D of each
# nucleotide_slot in rail_train_test.gd, per the structural refactor
# discussed: the slot (PathFollow2D) handles POSITIONAL mechanics (riding
# the curve, the trombone motion, the pulse), while this node will
# eventually carry BIOLOGICAL identity/behavior (base type, label,
# binding, target-pulse highlighting), matching the two-layer structure
# already used in the real simulation (nitrogen_base.gd + polymerase.gd).
#
# CURRENT SCOPE (v1): structure only, no behavior yet.
# - freeze = true, FreezeMode left at its default (STATIC) -- per Godot's
#   own docs, a STATIC-frozen RigidBody2D "is not affected by gravity and
#   forces; it can only be moved by user code" -- exactly the kinematic-
#   passenger behavior wanted here: this node rides wherever its parent
#   nucleotide_slot places it, with zero physics influence, until we
#   deliberately turn physics on in a later step.
# - A plain Label child, defaulting to "X" (placeholder for the eventual
#   real base-type system: A/T/C/G), with EXPORTED font size and color so
#   both are tunable directly from the Inspector.
# - A simple visual body (Polygon2D circle) so the base is visible on
#   screen even before any real sprite/art exists -- separate from, and
#   independent of, the nucleotide_slot's own ColorRect visual.
# ==========================================

@export_group("Label")
## Default placeholder text shown on every base until the real base-type (A/T/C/G) system is wired in.
@export var label_text: String = "X"
## Font size of the label, in pixels.
@export var label_font_size: int = 14
## Color of the label text.
@export var label_color: Color = Color(1.0, 1.0, 1.0, 1.0)

@export_group("Body Visual")
## Radius of the base's own circular visual body (independent of the parent nucleotide_slot's ColorRect).
@export var body_radius: float = 10.0
## Fill color of the base's circular visual body.
@export var body_color: Color = Color(0.8, 0.8, 0.8, 1.0)

@export_group("Physics")
## If true (default), this RigidBody2D stays kinematically frozen -- positioned entirely by its parent nucleotide_slot, with zero physics influence (no gravity, no forces, immune to collisions pushing it around). Set false only once real Brownian-motion/binding behavior is deliberately wired in -- not yet implemented in this v1 script.
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
	body_poly.color = body_color
	add_child(body_poly)

	label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", label_font_size)
	label.add_theme_color_override("font_color", label_color)
	add_child(label)

	# Center the label on the base's own origin using its ACTUAL measured
	# size (label.size, only correctly populated after one layout pass --
	# call_deferred runs this after the node has entered the tree and been
	# laid out, rather than guessing the offset from font_size alone).
	_center_label.call_deferred()

func _center_label():
	if label:
		label.position = -label.size / 2.0

func set_label_text(new_text: String):
	# Public setter for when the real base-type system replaces the "X"
	# placeholder -- kept simple and explicit rather than exposing `label`
	# directly, so callers don't need to know about the Label child node.
	label_text = new_text
	if label:
		label.text = new_text

func set_body_color(new_color: Color):
	# Public setter, same pattern as set_label_text() -- lets external
	# callers (e.g. rail_train_test.gd's synthesis-completion color
	# trigger) change the visible body color without needing to know
	# about the Polygon2D child node directly.
	body_color = new_color
	if body_poly:
		body_poly.color = new_color
