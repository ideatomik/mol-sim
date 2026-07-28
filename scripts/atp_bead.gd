class_name AtpBead
extends Node2D

# ==========================================
# atp_bead.gd
# ONE bead of the ATP/ADP/AMP/Pi glyph family — an adenine head or a single
# phosphate. Pooled: `atp_cycle.gd` creates a fixed set at build time and
# reassigns each bead's ROLE every frame. A bead has no lifetime, no memory,
# and no idea which molecule it currently belongs to.
#
# DELIBERATELY NOT nitrogen_base.gd, and this is a recorded divergence rather
# than a silent one (ATPCycleDesign.md, Object lifecycle and pooling): that
# scene is a RigidBody2D, and inheriting physics-body overhead for purely
# decorative pooled glyphs contradicts the low-end-hardware constraint. What
# IS copied is its VISUAL vocabulary, which is the pedagogically load-bearing
# part:
#   - draw_circle(..., antialiased = true) rather than a fixed-vertex polygon
#     (STATUS.md: a fixed-vertex polygon stays faceted regardless of MSAA)
#   - the pivot_offset label-centering fix, verbatim — see _center_label()
#   - set_label_rotation() injected from outside for vertical mode
#
# THEMEMANAGER-FREE, like nitrogen_base.gd and helicase_ring.gd. Every value
# is pushed in by the owner (atp_cycle.gd, which is itself pushed by
# simulation.gd). This node never looks anything up.
# ==========================================

var radius: float = 7.0
var fill_color: Color = Color(0.95, 0.80, 0.25, 1.0)

var _label: Label = null
var _label_rotation: float = 0.0

func _ready() -> void:
	_label = Label.new()
	add_child(_label)
	_center_label.call_deferred()
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color, true, -1.0, true)

# ---------- PUBLIC (all pushed in; nothing is looked up) ----------

## Sets everything that defines this bead's current role in one call, so a
## per-frame role reassignment is a single line at the call site rather than
## four that could drift apart.
func configure(p_radius: float, p_fill: Color, p_text: String) -> void:
	radius = p_radius
	fill_color = p_fill
	if _label != null and _label.text != p_text:
		_label.text = p_text
		_center_label.call_deferred()
	queue_redraw()

func set_label_style(font_size: int, text_color: Color, font: Font = null) -> void:
	if _label == null:
		return
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", text_color)
	if font != null:
		_label.add_theme_font_override("font", font)
	_center_label.call_deferred()

## Counter-rotation cancelling the camera's rotation in vertical mode so the
## "A"/"P" glyphs stay upright. Injected from outside exactly like
## nitrogen_base.gd's own set_label_rotation(); pass ZoomManager's
## get_label_counter_rotation() verbatim.
##
## The ATP cycle's beads were NOT in ATPCycleDesign.md's vertical-mode
## accounting — the design records that the glyph text needs no CSV keys
## (true: "A" and "P" are identical in every language) and then never revisits
## the fact that it is still DRAWN TEXT. v77's nucleotide_field.gd near-miss
## was this exact omission, caught only because someone checked the repo
## rather than the uploaded sample.
func set_label_rotation(radians: float) -> void:
	_label_rotation = radians
	_center_label.call_deferred()

# ---------- INTERNAL ----------

## pivot_offset is the load-bearing line, not the rotation — verbatim from
## nitrogen_base.gd._center_label(). Godot rotates a Control around its pivot,
## which defaults to the TOP-LEFT corner; without this every glyph swings off
## centre by half its own diagonal the moment a non-zero rotation applies. In
## horizontal mode _label_rotation is 0.0 and this is a strict no-op.
func _center_label() -> void:
	if _label == null:
		return
	_label.pivot_offset = _label.size / 2.0
	_label.position = -_label.size / 2.0
	_label.rotation = _label_rotation
