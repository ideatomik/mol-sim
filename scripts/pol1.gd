extends Node2D
class_name Pol1Enzyme

# ==========================================
# pol1.gd — Complex-tier trailing enzyme (nick translation), see
# OkazakiMaturationDesign.md.
#
# Two connected lobes along the TRAVEL axis — same "two procedural pieces,
# one shared shape family" precedent polymerase_clamp.gd already set with
# its back/jaw split, but split along local X (direction of travel) instead
# of the duplex's inside/outside axis. Pol I's two simultaneous activities
# (5'->3' exonuclease chewing the RNA primer ahead of it, 5'->3' polymerase
# filling DNA in behind it) are sequential ALONG the strand, not front/back
# relative to it — hence a different axis than the clamp's split.
#
# EXO lobe = local -x (leading edge). Primer removal sweeps right-to-left
#   (high-to-low index) across a fragment's primer span — the same chained
#   order Pol III itself already used to originally write those slots, so
#   the leading edge points toward lower x.
# POL lobe = local +x (trailing edge). Sits over already-converted DNA.
# A fixed lobe_gap holds both a constant distance apart — matched exo/pol
# rates, so the nick slides forward without growing or shrinking, which is
# the real biological behavior this enzyme models (not an approximation of
# convenience).
#
# POSITIONING is driven entirely EXTERNALLY, same division of labor
# ligase.gd/primase_blip.gd already use — replication_manager.gd tweens this
# node's own `position` one converted slot at a time as Pol I sweeps across
# a primer span. This file owns only its own two-lobe shape and the
# per-slot pulse.
#
# set_pulse(t): 0 = rest (between bites), 1 = mid-bite (both lobes pulsed
# together — "matched rates" means synchronized, not offset-phase). Driven
# by chained tweens (0->1->0) per converted slot, same pattern ligase's seal
# pulse and primase's pop pulse already use — no clock of its own.
#
# SCRUB: hidden during scrub, same rule every enzyme visual in this project
# follows — scrub shows only finished states, and there is no "mid-bite"
# state to reproduce for an arbitrary scrub target.
#
# LIFECYCLE — the one enzyme that breaks from "created once at initialize(),
# persists hidden until needed": this node is TRUE ABSENCE until its first
# job, instantiated on demand by replication_manager.gd rather than created
# up front. Real Pol I has no fixed position in the replisome — it's a
# freely diffusing enzyme, not a tethered structural component the way
# helicase/Pol III/the clamp are — so there's no idle "waiting spot" for it
# to occupy before it has work. Once instantiated it persists for the rest
# of the run; see replication_manager.gd's POL1 section for the
# leave-the-strand motion it plays between jobs instead of parking in place.
# ==========================================

const ENZYME_LABEL_SCENE: PackedScene = preload("res://scenes/enzyme_label.tscn")

var _sim: Node = null
var _tm: Node = null
var _exo_lobe: Polygon2D = null
var _pol_lobe: Polygon2D = null
var _label: EnzymeLabel = null
var _pulse_t: float = 0.0

func setup(sim: Node) -> void:
	_sim = sim
	_tm = sim.get_node("%ThemeManager")
	_build()
	set_pulse(0.0)

func _build() -> void:
	_exo_lobe = Polygon2D.new()
	_exo_lobe.z_as_relative = false
	add_child(_exo_lobe)
	_pol_lobe = Polygon2D.new()
	_pol_lobe.z_as_relative = false
	add_child(_pol_lobe)
	_label = ENZYME_LABEL_SCENE.instantiate()
	_label.z_as_relative = false
	add_child(_label)
	_label.set_key("ENZYME_POL1")

## t = 0 rest, 1 = mid-bite (both lobes pulsed). No clock of its own — the
## caller (replication_manager.gd) drives this via a tween on the same node
## whose position it's also driving, once per converted slot.
func set_pulse(t: float) -> void:
	_pulse_t = clampf(t, 0.0, 1.0)
	_apply()

func _apply() -> void:
	if _exo_lobe == null or _tm == null:
		return
	var tm := _tm
	var t := _pulse_t

	var lobe_size: float = tm.pol1_lobe_size
	var lobe_gap: float = tm.pol1_lobe_gap
	var pulse_scale_ratio: float = tm.pol1_pulse_scale_ratio
	var chamfer: float = tm.pol1_chamfer_ratio
	var corner_ratio: float = tm.pol1_corner_radius_ratio
	var corner_segs: int = tm.pol1_corner_segments
	var exo_color: Color = tm.pol1_exo_color
	var exo_pulse_color: Color = tm.pol1_exo_pulse_color
	var pol_color: Color = tm.pol1_pol_color
	var pol_pulse_color: Color = tm.pol1_pol_pulse_color
	var z: int = tm.pol1_z

	var grown: float = lobe_size * lerpf(1.0, pulse_scale_ratio, t)
	var half_gap: float = lobe_gap * 0.5
	var shape: PackedVector2Array = _round_corners(_octagon(grown, grown, chamfer), corner_ratio, corner_segs)

	_exo_lobe.polygon = shape
	_exo_lobe.position = Vector2(-half_gap, 0.0)
	_exo_lobe.color = exo_color.lerp(exo_pulse_color, t)
	_exo_lobe.z_index = z

	_pol_lobe.polygon = shape
	_pol_lobe.position = Vector2(half_gap, 0.0)
	_pol_lobe.color = pol_color.lerp(pol_pulse_color, t)
	_pol_lobe.z_index = z

	if _label:
		var label_enabled: bool = tm.enzyme_labels_enabled
		_label.visible = label_enabled
		if label_enabled:
			_label.set_style(null, tm.label_font_size, tm.label_color, tm.label_panel_color)
			_label.z_index = tm.label_z
			_label.set_anchor_pos(Vector2(0.0, -(lobe_size * 0.5 + tm.pol1_label_margin)))

# ---------- octagon building block ----------
# NOTE: duplicated from helicase_ring.gd / polymerase_clamp.gd / ligase.gd /
# primase_blip.gd — same deferred shared-utility extraction all four already
# flag; a fifth copy here rather than resolving that now.

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
		var r = radius_ratio * minf(len_prev, len_next) * 0.5
		var p1 = cur + to_prev.normalized() * r
		var p2 = cur + to_next.normalized() * r
		for s in range(segments + 1):
			var t = float(s) / float(segments)
			var a = p1.lerp(cur, t)
			var b = cur.lerp(p2, t)
			out.append(a.lerp(b, t))
	return out
