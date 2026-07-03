extends Node2D
# ==========================================
# polymerase_clamp_test.gd  —  STANDALONE test harness (v71 clamp redesign)
#
# Validates the TWO-PIECE procedural clamp concept before any live-scene work,
# same isolate-then-integrate pattern the helicase ring used.
#
# FRAME (from the LAGGING polymerase's point of view):
#   INSIDE  = toward the screen's vertical center / the template DNA  = local -y (up)
#   OUTSIDE = toward the screen edge, away from the template          = local +y (down)
#   Leading strand is the single `_root.scale.y = -1` mirror of this — no separate math.
#
# BACK BODY  (behind the strand, back_z):
#   DOWN pose: height = duplex_span + 2*margin, vertically CENTERED on the
#   template midline (leaves `margin` past each duplex edge). Its OUTER edge
#   (outside / screen-edge side) is PINNED; pump grows its height INWARD
#   (toward center), so only the inner edge advances. Deforms per frame.
#
# JAW  (in front of the strand, front_z):
#   FIXED height = 0.25 * back's DOWN height. Its INSIDE edge is shared with
#   the back's inner edge, and it extends OUTWARD from there, OVERLAPPING the
#   back. Translates inward with the growing edge; its bounding box never
#   deforms (only its inner corners restyle — see corners).
#
# CAPTURE ANCHOR (#3): the jaw's OUTER edge (jaw_outer_y). As the jaw rides
#   back down it sweeps this point outward, pushing the captured nucleotide
#   toward the outer strand. Shown live as the yellow ring marker.
#
# CORNERS (two chamfer ratios, replacing the old single one):
#   At DOWN, every corner = outside_chamfer_ratio * half_height_at_DOWN — one
#   crisp, symmetric value. During pump:
#     - OUTSIDE corners stay pinned at that base value (crisp throughout).
#     - INSIDE corners blend toward inside_chamfer_ratio * half_height(t) as
#       t rises, so the flat vertical sides absorb the growth and the inner
#       end reads as STRETCHING to reach a nucleotide.
#   The jaw stretches alike, driven by the same t against its own half-height.
#
# SETUP: new scene, root Node2D, attach this script, run. On-screen controls
#   drive the pump (drag = scrub test), auto-pump, and the leading mirror.
#   Everything else is @export — tune live in the Inspector while it runs.
# ==========================================

# ---------- DUPLEX / LAYOUT ----------
@export var duplex_span: float = 100.0   # full vertical extent of strands + backbones
@export var margin: float = 30.0         # extra space the back adds past each duplex edge (DOWN pose)

# ---------- BACK BODY ----------
@export var back_width: float = 90.0
@export var back_grow: float = 40.0      # extra height added at UP (t = 1). Negative to retract.

# ---------- JAW ----------
@export var jaw_width: float = 90.0
@export_range(0.05, 1.0) var jaw_height_ratio: float = 0.35   # * back's DOWN height, computed once

# ---------- CORNERS (two chamfer ratios + generic rounding) ----------
@export_range(0.0, 1.0) var outside_chamfer_ratio: float = 0.35   # crisp baseline; owns the DOWN pose + outer corners
@export_range(0.0, 1.0) var inside_chamfer_ratio: float = 0.6     # UP-state stretch of the inner corners
@export_range(0.0, 1.0) var corner_radius_ratio: float = 0.6
@export_range(2, 8) var corner_segments: int = 4

# ---------- COLORS ----------
@export var back_color: Color = Color(0.18, 0.55, 0.32)    # back body — behind the strand (eyeballed from your swatch)
@export var front_color: Color = Color(0.30, 0.92, 0.55)   # jaw       — in front of the strand (eyeballed from your swatch)

# ---------- Z-STRADDLE (absolute, so the DNA renders between the pieces) ----------
@export var back_z: int = -1
@export var front_z: int = 1

# ---------- PUMP ----------
@export_range(0.0, 1.0) var pump_t: float = 0.0   # 0 = DOWN/clamped (scrub rests here), 1 = UP/open
@export var auto_pump: bool = false
@export var pump_speed: float = 10.0              # radians/sec for the auto sine (harness only — real pump derives from step timing)

var _root: Node2D = null
var _back: Polygon2D = null
var _jaw: Polygon2D = null
var _anchor: Node2D = null
var _dna: Node2D = null

var _pump_slider: HSlider = null
var _readout: Label = null
var _phase: float = 0.0
var _mirror: bool = false

func _ready() -> void:
	position = get_viewport_rect().size * 0.5   # center the rig in the viewport

	# Reference duplex — NOT under _root, so the mirror never flips it.
	_dna = _DnaRef.new()
	_dna.span = duplex_span
	_dna.z_index = 0
	_dna.z_as_relative = false
	add_child(_dna)

	_root = Node2D.new()
	add_child(_root)

	_back = _make_piece(back_z)
	_jaw = _make_piece(front_z)

	_anchor = _AnchorMark.new()
	_anchor.z_index = front_z + 1
	_anchor.z_as_relative = false
	_root.add_child(_anchor)

	_build_ui()
	_apply()

func _make_piece(z: int) -> Polygon2D:
	var p := Polygon2D.new()
	p.z_index = z
	p.z_as_relative = false   # absolute z so the pieces straddle the DNA layer
	_root.add_child(p)
	return p

func _process(delta: float) -> void:
	if auto_pump:
		_phase += delta * pump_speed
		pump_t = 0.5 - 0.5 * cos(_phase)
		if _pump_slider != null:
			_pump_slider.set_value_no_signal(pump_t)
	if _dna != null:
		_dna.span = duplex_span   # keep the reference in sync if tuned live
		_dna.queue_redraw()
	_apply()

# ---------- the concept ----------

func _apply() -> void:
	var t: float = clampf(pump_t, 0.0, 1.0)

	# Derived geometry (from duplex_span + margin — no longer free params).
	var back_base_height: float = duplex_span + 2.0 * margin
	var outer_edge_y: float = back_base_height * 0.5          # DOWN pose is centered, so |outer| = half
	var jaw_h: float = back_base_height * jaw_height_ratio    # fixed, computed once per frame from base

	var half_down: float = back_base_height * 0.5

	# BACK BODY: outer edge pinned at +outer_edge_y; grows inward (-y).
	var h_back: float = back_base_height + back_grow * t
	var half_cur: float = h_back * 0.5
	var back_inner_y: float = outer_edge_y - h_back           # advancing inner edge (up / inside)

	var cx_back: float = outside_chamfer_ratio * (back_width * 0.5)
	var cy_out_back: float = outside_chamfer_ratio * half_down                                    # crisp, pinned to base
	var cy_in_back: float = lerpf(outside_chamfer_ratio * half_down, inside_chamfer_ratio * half_cur, t)  # stretches with t
	_back.polygon = _round_corners(_octagon(back_width, h_back, cx_back, cy_in_back, cy_out_back), corner_radius_ratio, corner_segments)
	_back.position = Vector2(0.0, outer_edge_y - h_back * 0.5)
	_back.color = back_color

	# JAW: fixed height, inside edge glued to the back's inner edge, extends
	# outward (overlapping the back). Bounding box translates only; inner
	# corners restyle with the same t against the jaw's own half-height.
	var half_jaw: float = jaw_h * 0.5
	# Jaw copies the BACK's absolute cap sizes (px) so the diagonals read
	# identical despite the jaw being shorter — proportional ratios alone made
	# the shorter piece's corners look smaller. Reined in proportionally only if
	# two full caps would overrun the jaw's height (can't fit caps taller than
	# the piece); with a tall-enough jaw this guard never trips.
	var cy_in_jaw: float = cy_in_back
	var cy_out_jaw: float = cy_out_back
	var cap_sum: float = cy_in_jaw + cy_out_jaw
	if cap_sum > jaw_h:
		var k: float = jaw_h / cap_sum
		cy_in_jaw *= k
		cy_out_jaw *= k
	var cx_jaw: float = minf(cx_back, jaw_width * 0.5)   # copy absolute; guard only if jaw is narrower
	_jaw.polygon = _round_corners(_octagon(jaw_width, jaw_h, cx_jaw, cy_in_jaw, cy_out_jaw), corner_radius_ratio, corner_segments)
	_jaw.position = Vector2(0.0, back_inner_y + half_jaw)     # inside edge sits on back_inner_y
	_jaw.color = front_color

	# CAPTURE ANCHOR: jaw's OUTER edge — sweeps outward on the down-stroke to
	# push the nucleotide toward the outer strand.
	var anchor_y: float = back_inner_y + jaw_h
	_anchor.position = Vector2(0.0, anchor_y)

	if _readout != null:
		var side := "LEADING (mirrored)" if _mirror else "LAGGING"
		_readout.text = "%s   t=%.2f   h_back=%.0f   jaw_h=%.0f   anchor_y=%.0f" % [side, t, h_back, jaw_h, anchor_y]

# ---------- octagon building block (asymmetric caps: inside vs outside) ----------

func _octagon(w: float, h: float, cx: float, cy_top: float, cy_bottom: float) -> PackedVector2Array:
	# Vertically-stretchable octagon. TOP (-hh) = INSIDE (up) -> cy_top;
	# BOTTOM (+hh) = OUTSIDE (down) -> cy_bottom. Flat vertical sides absorb
	# the growth between the caps.
	var hw := w * 0.5
	var hh := h * 0.5
	return PackedVector2Array([
		Vector2(-hw + cx, -hh),        # top edge, left        (inside)
		Vector2( hw - cx, -hh),        # top edge, right       (inside)
		Vector2( hw, -hh + cy_top),    # upper-right shoulder  (inside)
		Vector2( hw,  hh - cy_bottom), # lower-right shoulder  (outside)
		Vector2( hw - cx,  hh),        # bottom edge, right    (outside)
		Vector2(-hw + cx,  hh),        # bottom edge, left     (outside)
		Vector2(-hw,  hh - cy_bottom), # lower-left shoulder   (outside)
		Vector2(-hw, -hh + cy_top),    # upper-left shoulder   (inside)
	])

func _round_corners(pts: PackedVector2Array, radius_ratio: float, segments: int) -> PackedVector2Array:
	# NOTE: at integration time this and _octagon become the shared utility
	# briefing item #7 calls for — copied here only to keep the harness standalone.
	var n := pts.size()
	if n < 3 or radius_ratio <= 0.0:
		return pts
	var out := PackedVector2Array()
	for i in range(n):
		var prev := pts[(i - 1 + n) % n]
		var cur := pts[i]
		var next := pts[(i + 1) % n]
		var to_prev := prev - cur
		var to_next := next - cur
		var len_prev := to_prev.length()
		var len_next := to_next.length()
		if len_prev < 0.0001 or len_next < 0.0001:
			out.append(cur)
			continue
		var r := radius_ratio * minf(len_prev, len_next) * 0.5
		var p1 := cur + to_prev.normalized() * r
		var p2 := cur + to_next.normalized() * r
		for s in range(segments + 1):
			var st := float(s) / float(segments)
			var a := p1.lerp(cur, st)
			var b := cur.lerp(p2, st)
			out.append(a.lerp(b, st))
	return out

# ---------- on-screen controls ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	box.custom_minimum_size = Vector2(360, 0)
	layer.add_child(box)

	_readout = Label.new()
	box.add_child(_readout)

	var pump_label := Label.new()
	pump_label.text = "Pump t  (drag = scrub test)"
	box.add_child(pump_label)

	_pump_slider = HSlider.new()
	_pump_slider.min_value = 0.0
	_pump_slider.max_value = 1.0
	_pump_slider.step = 0.001
	_pump_slider.custom_minimum_size = Vector2(320, 0)
	box.add_child(_pump_slider)
	_pump_slider.value_changed.connect(_on_pump_changed)

	var auto_btn := CheckButton.new()
	auto_btn.text = "Auto pump"
	box.add_child(auto_btn)
	auto_btn.toggled.connect(_on_auto_toggled)

	var mirror_btn := CheckButton.new()
	mirror_btn.text = "Mirror (leading strand)"
	box.add_child(mirror_btn)
	mirror_btn.toggled.connect(_on_mirror_toggled)

	var hint := Label.new()
	hint.text = "margin / grow / chamfer ratios / colors: live in the Inspector."
	box.add_child(hint)

func _on_pump_changed(v: float) -> void:
	if not auto_pump:
		pump_t = v

func _on_auto_toggled(on: bool) -> void:
	auto_pump = on
	if on:
		_phase = acos(clampf(1.0 - 2.0 * pump_t, -1.0, 1.0))   # resume from current t, no jump

func _on_mirror_toggled(on: bool) -> void:
	_mirror = on
	_root.scale.y = -1.0 if on else 1.0

# ==========================================
# reference duplex — full span (strands + backbones). Test scaffold only.
# ==========================================
class _DnaRef extends Node2D:
	var span: float = 100.0
	func _draw() -> void:
		var half := span * 0.5
		var w := 260.0
		var bb := Color(0.55, 0.75, 0.55, 0.9)      # backbones at the outer edges of the span
		draw_rect(Rect2(-w * 0.5, -half - 2.0, w, 4.0), bb)
		draw_rect(Rect2(-w * 0.5,  half - 2.0, w, 4.0), bb)
		# two template strands, set in a bit from the backbones
		var inner := half * 0.45
		var st := Color(0.45, 0.65, 0.85, 0.8)
		draw_rect(Rect2(-w * 0.5, -inner - 1.5, w, 3.0), st)
		draw_rect(Rect2(-w * 0.5,  inner - 1.5, w, 3.0), st)
		draw_rect(Rect2(-w * 0.5, -half, w, span), Color(0.55, 0.75, 0.55, 0.10))

# ==========================================
# capture-anchor marker — the jaw's OUTER edge, drawn so its motion is visible.
# ==========================================
class _AnchorMark extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.9, 0.2, 0.9))
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.2, 0.7), 2.0)
