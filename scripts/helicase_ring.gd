class_name HelicaseRing
extends Node2D

# ==========================================
# helicase_ring.gd
# Side-view barrel-roll helicase ring. N blobs ("subunits") cycle vertically
# like a slot-machine reel, selling a ring rotating around the unzipping point.
#
# PURE FUNCTION OF ONE FLOAT `roll` (plus the rotation_frozen flag, below).
#   In the sim:  roll = helicase_mgr.current_slot_index + helicase_mgr.get_eased_step_t()
#   In the test harness: the slider value (raw scrub) or the eased play value.
# There is NO independent clock in here — set_roll() alone fully determines
# every blob's pose when not frozen. That is what makes it scrub-safe for
# free: scrub already sets slot_index + step_t directly, so feeding roll
# snaps the ring to the geometrically correct pose with zero rebuild logic.
#
# SEE-THROUGH MODEL. N blobs spaced 360/N apart, each doing a full revolution.
# A blob's z_index flips between front_z and back_z with sign(cos theta). The
# flip lands at theta = 90/270, where blob_height is 0 (invisible) — so the
# z-swap never pops. Blobs pass BEHIND the DNA (back_z) on the far half and IN
# FRONT (front_z) on the near half, which is the whole depth cue.
#
# ROTATION_FROZEN — static-pose mode, mirroring the polymerase clamp always
# showing its DOWN state on scrub. When true, `theta` drops the roll term
# entirely (theta = i * spacing only) — a fixed, symmetric arrangement with
# NO dependency on slot position. Two independent callers are expected to
# set this: simulation.gd during scrub (matching "scrub is always instant,
# never animated"), and the low-info theme (reduced-motion accessibility).
# The ring doesn't need to know which reason applies — whoever's asking just
# sets the flag.
#
# SHIPPABLE AS-IS: reparent this under simulation.gd's helicase_node and feed
# set_roll() from the _process block that already computes `eased`. Fade rides
# helicase_node.modulate for free — modulate propagates down the tree
# regardless of z_index, and z_as_relative=false on the blobs keeps front/back
# absolute rather than inheriting the container's z.
# ==========================================

# ---------- GEOMETRY ----------
@export var blob_count: int = 6
@export var ring_radius: float = 80.0        # vertical travel amplitude of each blob center (~ dna_ribbons_gap/2)
@export var max_blob_height: float = 90.0    # full height at theta=0 (face-on)
@export var max_blob_width: float = 50.0     # full width at theta=0. With 6 blobs the front-center blob is joined by its two ±60° neighbors at half-strength, so occlusion is a cluster effect, not a single-blob >= dna_ribbons_gap requirement — tune against the real gap once integrated
@export_range(0.0, 1.0) var min_width_ratio: float = 0.6   # width floor at theta=90 (edge-on sliver) so it never collapses to a zero-width line
@export_range(0.0, 1.0) var chamfer_ratio: float = 0.35        # octagon's base shape: how much of each corner is cut to form the flat diagonal shoulders (0 = plain rect, 1 = diamond)
@export_range(0.0, 1.0) var corner_radius_ratio: float = 0.6   # additional rounding on top of the chamfer, smoothing all 8 vertices. Radius is relative to the LOCAL edge length at each vertex, so it shrinks with the squash and can't self-intersect
@export_range(2, 8) var corner_segments: int = 4               # arc smoothness per corner; blobs are tiny, cheap to raise

# ---------- ROTATION ----------
@export var step_angle_deg: float = 60.0     # degrees the ring rotates per unit roll, when NOT frozen.
                                             # 60 (with blob_count 6) lands a FULL-SIZE blob dead-center-FRONT
                                             # at every whole step — the moment a blob should cover the fork.
                                             # This is the live/theme value; poke to compare rotation speed feel.
@export var rotation_frozen: bool = false    # true = static symmetric pose (theta = i*spacing only, no roll dependency).
                                             # Set by simulation.gd during scrub, and by the low-info theme toggle.

@export_range(-45.0, 45.0, 0.1) var ring_skew_deg: float = 3.0:
	set(value):
		ring_skew_deg = value
		skew = deg_to_rad(value)

# ---------- COLOR / DEPTH ----------
@export var front_color: Color = Color(0.22, 0.45, 0.85)
@export var back_color: Color = Color(0.14, 0.28, 0.55)
@export var front_z: int = 4                 # above the DNA bases (sim bases are z=2)
@export var back_z: int = -1                 # below the backbone

var _blobs: Array[Polygon2D] = []
var _roll: float = 0.0

func _ready() -> void:
	skew = deg_to_rad(ring_skew_deg)
	_rebuild_blobs()

# ---------- PUBLIC ----------

func set_roll(roll: float) -> void:
	_roll = roll
	_apply()

# ---------- INTERNAL ----------

func _rebuild_blobs() -> void:
	for b in _blobs:
		if is_instance_valid(b):
			b.queue_free()
	_blobs.clear()
	for i in range(max(1, blob_count)):
		var b = Polygon2D.new()
		b.z_as_relative = false   # front_z / back_z are absolute, not offset from this node's z
		add_child(b)
		_blobs.append(b)
	_apply()

func _apply() -> void:
	if _blobs.size() != max(1, blob_count):
		_rebuild_blobs()
		return
	var spacing = TAU / float(_blobs.size())
	var step = 0.0 if rotation_frozen else deg_to_rad(step_angle_deg)
	var roll = 0.0 if rotation_frozen else _roll
	for i in range(_blobs.size()):
		var theta = roll * step + i * spacing
		var c = cos(theta)
		var abs_c = abs(c)
		var h = max_blob_height * abs_c
		var w = max_blob_width * (min_width_ratio + (1.0 - min_width_ratio) * abs_c)
		var blob = _blobs[i]
		blob.polygon = _round_corners(_octagon(w, h, chamfer_ratio), corner_radius_ratio, corner_segments)
		blob.position = Vector2(0.0, ring_radius * sin(theta))
		var is_front = c >= 0.0
		blob.z_index = front_z if is_front else back_z
		blob.color = front_color if is_front else back_color
		blob.visible = h > 1.0   # drop the degenerate ~zero-height sliver right at the flip point

func _octagon(w: float, h: float, chamfer: float) -> PackedVector2Array:
	# Vertically-stretchable octagon: flat vertical sides, chamfered top/bottom
	# caps. Flat sides collapse cleanly to a sliver as w -> min; this is the
	# shape, before corner rounding is applied.
	var hw = w * 0.5
	var hh = h * 0.5
	var cx = hw * chamfer
	var cy = hh * chamfer
	return PackedVector2Array([
		Vector2(-hw + cx, -hh),   # top edge, left
		Vector2( hw - cx, -hh),   # top edge, right
		Vector2( hw, -hh + cy),   # upper-right shoulder
		Vector2( hw,  hh - cy),   # lower-right shoulder
		Vector2( hw - cx,  hh),   # bottom edge, right
		Vector2(-hw + cx,  hh),   # bottom edge, left
		Vector2(-hw,  hh - cy),   # lower-left shoulder
		Vector2(-hw, -hh + cy),   # upper-left shoulder
	])

func _round_corners(pts: PackedVector2Array, radius_ratio: float, segments: int) -> PackedVector2Array:
	# Generic rounding for any convex polygon: at each vertex, pull back along
	# both adjacent edges by a radius relative to that edge's own length, then
	# bridge the gap with a sampled quadratic bezier instead of a sharp point.
	# Edge-relative radius is what keeps this collapse-safe — as the blob
	# squashes and edges shrink, the rounding shrinks with them.
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
