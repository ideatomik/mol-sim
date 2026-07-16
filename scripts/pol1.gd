extends Node2D
class_name Pol1Enzyme

# ==========================================
# pol1.gd — Complex-tier trailing enzyme (nick translation), see
# OkazakiMaturationDesign.md.
#
# Two connected lobes stacked VERTICALLY (local Y), not along the travel
# axis. Originally split along local X (leading/trailing, mirroring the
# clamp's back/jaw precedent) — moved to a vertical stack instead: at the
# in-scene scale, both activities happening at essentially the same nick
# point read as a blur when spread along the strand, especially the
# RNA-removal side, which got visually lost against the strand line itself.
# Stacking makes both lobes legible without slowing the sim down to see them.
#
# EXO lobe (RNA removal) = the reference point, sitting exactly at local
#   origin — which is the node's own position (the lagging strand's base
#   row, see replication_manager.gd's _pol1_kick()). Placed as the anchor
#   deliberately: it's the harder-to-read of the two activities and
#   benefits from being the fixed point everything else is measured from.
# POL lobe (DNA fill-in) = offset from EXO by pol1_lobe_gap (local +y,
#   visually below), not a symmetric split around a shared center — EXO's
#   own position never moves regardless of how pol1_lobe_gap is tuned.
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
#
# _octagon()/_round_corners() extracted to procedural_shape_utils.gd
# (ProceduralShapeUtils) — this was the fifth and last duplicated copy
# project-wide; see that file's own header for the full list.
# ==========================================

const ENZYME_LABEL_SCENE: PackedScene = preload("res://scenes/enzyme_label.tscn")

var _sim: Node = null
var _tm: Node = null
var _exo_lobe: Polygon2D = null
var _pol_lobe: Polygon2D = null
var _label: EnzymeLabel = null
var _pulse_t: float = 0.0

## Asked of ZoomManager through _sim — the same reach setup() already makes for
## %ThemeManager. 0.0 in horizontal mode. EnzymeLabel owns the mirror sign;
## Pol I is unmirrored anyway (single instance, lagging strand only).
func _zoom_label_rotation() -> float:
	if _sim == null:
		return 0.0
	var zm = _sim.get_node_or_null("%ZoomManager")
	return zm.get_label_counter_rotation() if zm != null else 0.0

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

	# Sized relative to Pol III's own clamp width — derived, not an
	# independently-tuned flat constant, per this project's "never let two
	# numbers coincidentally agree" rule. Ligase stays small on purpose;
	# Pol I reads better closer to Pol III's own footprint.
	var lobe_size: float = tm.clamp_back_width * tm.pol1_lobe_size_ratio
	var lobe_gap: float = tm.pol1_lobe_gap
	var pol_height_ratio: float = tm.pol1_pol_lobe_height_ratio
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
	# EXO is the reference point, sitting exactly at the node's own position
	# (the base row, per replication_manager.gd's _pol1_kick()) — not a
	# symmetric split around it. POL is offset from EXO by pol1_lobe_gap,
	# tunable independently of EXO's own size or position.
	_exo_lobe.polygon = ProceduralShapeUtils.round_corners(ProceduralShapeUtils.octagon(grown, grown, chamfer), corner_ratio, corner_segs)
	_exo_lobe.position = Vector2.ZERO
	_exo_lobe.color = exo_color.lerp(exo_pulse_color, t)
	_exo_lobe.z_index = z

	_pol_lobe.polygon = ProceduralShapeUtils.round_corners(ProceduralShapeUtils.octagon(grown, grown * pol_height_ratio, chamfer), corner_ratio, corner_segs)
	_pol_lobe.position = _exo_lobe.position + Vector2(0.0, lobe_gap)
	_pol_lobe.color = pol_color.lerp(pol_pulse_color, t)
	_pol_lobe.z_index = z

	if _label:
		var label_enabled: bool = tm.enzyme_labels_enabled
		_label.visible = label_enabled
		if label_enabled:
			_label.set_style(null, tm.label_font_size, tm.label_color, tm.label_panel_color)
			_label.set_counter_rotation(_zoom_label_rotation())
			_label.z_index = tm.label_z
			_label.set_anchor_pos(Vector2(0.0, -(lobe_size * 0.5 + tm.pol1_label_margin)))
