extends Node2D
class_name PrimaseBlip

# ==========================================
# primase_blip.gd — Primase (RNA primer persistence pass)
#
# No longer a purely decorative blip — primase now does REAL per-slot
# synthesis: each ribonucleotide in a primer span is actually captured
# (via its own PolymeraseHalo, same mechanic Pol III's own capture uses)
# and placed into the real lagging strand, RNA-colored, before Pol III ever
# reaches that territory. This node is the visible actor for that process;
# the placed bases themselves are owned/persisted by replication_manager.gd,
# not by this node.
#
# Position is driven externally, per placement step (replication_manager.gd
# tweens this node toward each slot's final resting position, mirroring how
# lagging_polymerase's own position is driven) — no more continuous live-Y-
# curve-following, which was needed for the old purely-decorative version
# that hovered over not-yet-settled template. That's obsolete now: this node
# tracks the position of the base it's actually placing, which only exists
# at its own final resting Y once placed.
#
# set_pulse(t): 0 = rest, 1 = fully popped. Unlike ligase.gd's pulse (which
# PINCHES/shrinks), this one GROWS — a deliberately different motion
# language so the two enzymes don't read as the same gesture despite
# sharing the octagon shape family.
#
# SCRUB: never shown during scrub — replication_manager.gd's
# _lagging_scrub_rebuild() never calls the trigger in the first place
# (bases get recolored directly, without replaying any enzyme animation),
# so this needs no scrub-awareness of its own beyond the in-flight-tween-
# kill every other transient animation in this project already gets.
# ==========================================

const ENZYME_LABEL_SCENE: PackedScene = preload("res://scenes/enzyme_label.tscn")

var _sim: Node = null
var _tm: Node = null
var _blob: Polygon2D = null
var _label: EnzymeLabel = null
var _pulse_t: float = 0.0

func setup(sim: Node) -> void:
	_sim = sim
	_tm = sim.get_node("%ThemeManager")
	_build()
	set_pulse(0.0)

func _build() -> void:
	_blob = Polygon2D.new()
	_blob.z_as_relative = false
	add_child(_blob)
	_label = ENZYME_LABEL_SCENE.instantiate()
	_label.z_as_relative = false
	add_child(_label)
	_label.set_key("ENZYME_PRIMASE")

## t = 0 rest, 1 = fully popped (grown + pulse-colored). No clock of its
## own — the caller (replication_manager.gd) drives this via a tween on the
## same node whose position it's also driving, same pattern ligase.gd uses.
func set_pulse(t: float) -> void:
	_pulse_t = clampf(t, 0.0, 1.0)
	_apply()

func _apply() -> void:
	if _blob == null or _tm == null:
		return
	var tm := _tm
	var t := _pulse_t

	var base_size: float = tm.primase_blip_size
	var grown_size: float = base_size * lerpf(1.0, tm.primase_pulse_scale_ratio, t)
	_blob.polygon = _round_corners(_octagon(grown_size, grown_size, tm.primase_blip_chamfer_ratio), tm.primase_blip_corner_radius_ratio, tm.primase_blip_corner_segments)
	_blob.color = tm.primase_blip_color.lerp(tm.primase_pulse_color, t)
	_blob.z_index = tm.primase_blip_z

	if _label:
		var label_enabled: bool = tm.enzyme_labels_enabled
		_label.visible = label_enabled
		if label_enabled:
			_label.set_style(null, tm.label_font_size, tm.label_color, tm.label_panel_color)
			_label.z_index = tm.label_z
			_label.set_anchor_pos(Vector2(0.0, -(base_size * 0.5 + tm.primase_blip_label_margin)))

# ---------- octagon building block ----------
# NOTE: duplicated from helicase_ring.gd / polymerase_clamp.gd / ligase.gd —
# same deferred shared-utility extraction all three already flag.

func _octagon(w: float, h: float, chamfer: float) -> PackedVector2Array:
	var hw = w * 0.5
	var hh = h * 0.5
	var cx = hw * chamfer
	var cy = hh * chamfer
	return PackedVector2Array([
		Vector2(-hw + cx, -hh),
		Vector2( hw - cx, -hh),
		Vector2( hw, -hh + cy),
		Vector2( hw,  hh - cy),
		Vector2( hw - cx,  hh),
		Vector2(-hw + cx,  hh),
		Vector2(-hw,  hh - cy),
		Vector2(-hw, -hh + cy),
	])

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
