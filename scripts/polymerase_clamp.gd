extends Node2D
class_name PolymeraseClamp
# ==========================================
# polymerase_clamp.gd  —  runtime 3-piece polymerase clamp (v71)
#
# Builds the authored clamp (from PolymeraseShape's normalized polygons) as
# three child draw-nodes, scaled to the live duplex span and z-threaded so the
# DNA renders BETWEEN the back pieces and the front cap — the clamp reads as
# encircling the strand.
#
# Meant to be added as a CHILD of the existing polymerase node (leading_polymerase
# / the SynthesisCircle "lagging_polymerase"). That parent is already parked on
# the template-backbone row by replication_manager; this node self-offsets to the
# duplex CENTRE (where the art is registered) and self-scales, so NO existing
# positioning code has to change. modulate.a on the parent still fades it (CanvasItem
# modulate propagates to children).
#
# Static by default (DOWN / clamped). set_pump(t) lifts the jaw for live play;
# scrub just leaves it at 0 (DOWN), matching the "scrub only shows finished slots"
# rule — no pump-phase rebuild needed.
# ==========================================

# Absolute z-indices (z_as_relative disabled per piece) so the pieces straddle
# the DNA no matter what z_index the parent polymerase node carries.
# DNA reference: backbone -1, hydrogen bonds 0, bases 2, markers 3.
const Z_BACK_BODY := -3   # z-11  static back body — behind the strand
const Z_JAW_BACK  := -2   # z-10  jaw body        — behind the strand
const Z_JAW_FRONT := 4    # z+10  jaw cap         — in front of the strand

var _mirror: bool = false
var _jaw: Node2D = null
var jaw_cap_piece: Node2D = null   # the JAW_ZP10 _PolyPiece — capture's leg-1 live-follow anchor

func setup(sim: Node, mirror: bool, body_color: Color, cap_color: Color) -> void:
	_mirror = mirror
	var tm = sim.get_node("%ThemeManager")

	# Live duplex span: the art's DNA rect == backbone-to-backbone plus the
	# backbone_offset_distance + backbone_line_width/2 margin on each side.
	var span_px: float = sim.dna_ribbons_gap + 2.0 * (tm.backbone_offset_distance + tm.backbone_line_width / 2.0)

	# Offset from the parent (template-backbone row) to the duplex CENTRE, toward
	# the new strand: down for lagging, up for leading.
	var center_offset: float = sim.dna_ribbons_gap / 2.0
	position.y = -center_offset if mirror else center_offset

	# Scale normalized art -> pixels; y-flip mirrors the whole clamp for leading.
	scale = Vector2(span_px, -span_px if mirror else span_px)

	_build(body_color, cap_color)

func _build(body_color: Color, cap_color: Color) -> void:
	# Static back body (does not pump).
	_add_piece(PolymeraseShape.BACK_Z11, Z_BACK_BODY, body_color, self)

	# Jaw = the two pieces that pump together; parented under _jaw so a single
	# _jaw.position.y drives the lift.
	_jaw = Node2D.new()
	add_child(_jaw)
	_add_piece(PolymeraseShape.JAW_Z10, Z_JAW_BACK, body_color, _jaw)
	jaw_cap_piece = _add_piece(PolymeraseShape.JAW_ZP10, Z_JAW_FRONT, cap_color, _jaw)

func _add_piece(poly: PackedVector2Array, z: int, col: Color, parent: Node2D) -> _PolyPiece:
	var piece := _PolyPiece.new()
	piece.poly = poly
	piece.color = col
	piece.z_index = z
	piece.z_as_relative = false   # absolute z so it straddles the DNA layer
	parent.add_child(piece)
	return piece

## Local-space anchor inside JAW_ZP10 — the "inner tip," the end closest to the
## duplex center (bbox y-min; JAW_ZP10 spans y:[+0.044,+0.686] in normalized
## duplex-span units, x centered at 0). Derived from polymerase_shape.gd's
## JAW_ZP10 data (session notes carry the extraction script) — this piece was
## never touched by the later BACK_Z11/JAW_Z10 swap, so these numbers are
## still accurate to what's currently in that const.
const _JAW_ZP10_INNER := Vector2(0.0, 0.0443)

## Live world-space position of the jaw cap's inner tip, right now — walks the
## piece's real transform chain (its own local point -> _jaw's pump offset ->
## this clamp's scale/mirror/position -> the polymerase's world position) via
## to_global(), so it automatically tracks the pump animation and works
## identically for both strands with no strand-specific math needed here.
func get_jaw_cap_inner_anchor() -> Vector2:
	if jaw_cap_piece == null:
		return global_position
	return jaw_cap_piece.to_global(_JAW_ZP10_INNER)

## Lift the jaw. t = 0 -> DOWN (clamped), t = 1 -> UP (open). Expressed in
## normalized (duplex-span) units; the node scale converts to px and the
## leading mirror flips direction automatically.
## Sign confirmed at runtime (session, v71 pump wiring) — do not re-flip
## without checking the lift direction on screen first.
func set_pump(t: float) -> void:
	if _jaw != null:
		_jaw.position.y = PolymeraseShape.PUMP_OFFSET * t

# --- inner draw node: one polygon each ---
class _PolyPiece extends Node2D:
	var poly: PackedVector2Array
	var color: Color = Color.WHITE
	func _draw() -> void:
		if poly.size() >= 3:
			draw_colored_polygon(poly, color)
