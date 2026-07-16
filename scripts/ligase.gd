extends Node2D
class_name Ligase

# ==========================================
# ligase.gd — Complex-tier trailing enzyme (OkazakiMaturationDesign.md)
#
# A single small procedural blob — same rounded-corner octagon primitive as
# helicase_ring.gd / polymerase_clamp.gd, used here at its simplest: no
# rotation, no asymmetric inside/outside caps, just a shape that can rest,
# travel, and briefly pinch when sealing a junction.
#
# POSITIONING is driven entirely EXTERNALLY, by replication_manager.gd's
# _ligase_kick()/_ligase_seal() (a Tween on this node's own `position`) —
# same division of labor polymerase_clamp.gd's own parent/child split
# already uses (the polymerase node owns position, the clamp owns its own
# shape/pump). This node owns only its own shape and the seal-pulse
# animation, via set_pulse(t).
#
# set_pulse(t): 0 = rest (idle), 1 = fully pinched (mid-seal). Driven by two
# chained tweens (0->1, then 1->0) from replication_manager.gd — no clock of
# its own, same discipline every other enzyme visual in this project follows.
#
# SCRUB: replication_manager.gd hides this node during scrub (scrub shows
# only finished states — there is no "the enzyme is mid-travel" state to
# reproduce for an arbitrary scrub target, matching the rule the nucleotide
# capture animation and the primase blip already follow).
#
# STAND-IN TRIGGER: ligase's queue is fed by _lagging_close_fragment() at
# Light tier, and ALSO by _pol1_finish_job() at Complex tier (an added
# condition on _ligase_kick()'s own eligibility check, not a trigger swap —
# see OkazakiMaturationDesign.md's Pol I Implementation Status). Nothing in
# this file knows or cares which trigger fired.
#
# _octagon()/_round_corners() extracted to procedural_shape_utils.gd
# (ProceduralShapeUtils) — this was the third of five duplicated copies
# project-wide; see that file's own header for the full list.
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
	_label.set_key("ENZYME_LIGASE")

## t = 0 rest, 1 = fully pinched mid-seal. No clock of its own — the caller
## (replication_manager.gd) drives this via a tween on the same node whose
## position it's also driving.
func set_pulse(t: float) -> void:
	_pulse_t = clampf(t, 0.0, 1.0)
	_apply()

func _apply() -> void:
	if _blob == null or _tm == null:
		return
	var tm := _tm

	var base_size: float = tm.ligase_base_size
	var pinch_ratio: float = tm.ligase_pinch_ratio
	var chamfer: float = tm.ligase_chamfer_ratio
	var corner_ratio: float = tm.ligase_corner_radius_ratio
	var corner_segs: int = tm.ligase_corner_segments
	var rest_color: Color = tm.ligase_rest_color
	var pulse_color: Color = tm.ligase_pulse_color
	var z: int = tm.ligase_z

	var t := _pulse_t
	var w: float = base_size * lerpf(1.0, pinch_ratio, t)
	var h: float = base_size
	_blob.polygon = ProceduralShapeUtils.round_corners(ProceduralShapeUtils.octagon(w, h, chamfer), corner_ratio, corner_segs)
	_blob.color = rest_color.lerp(pulse_color, t)
	_blob.z_index = z

	if _label:
		var label_enabled: bool = tm.enzyme_labels_enabled
		_label.visible = label_enabled
		if label_enabled:
			_label.set_style(null, tm.label_font_size, tm.label_color, tm.label_panel_color)
			_label.z_index = tm.label_z
			_label.set_anchor_pos(Vector2(0.0, base_size * 0.5 + tm.ligase_label_margin))
