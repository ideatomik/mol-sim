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
# LABEL: a static "Helicase" name tag anchored above the ring's rotation
# band. Deliberately does NOT participate in the barrel-roll — it's a fixed
# offset in local space, recomputed from ring_radius/max_blob_height each
# _apply() so Inspector tuning of those still moves it correctly, but with
# no roll dependency it can never overlap a full-height blob at any rotation
# phase. Config lives directly on this node (own @export vars), matching
# this file's existing pattern of NOT reading ThemeManager — unlike
# polymerase_clamp.gd, which does. Fade rides this node's modulate for free,
# same as the blobs.
#
# SHIPPABLE AS-IS: reparent this under simulation.gd's helicase_node and feed
# set_roll() from the _process block that already computes `eased`. Fade rides
# helicase_node.modulate for free — modulate propagates down the tree
# regardless of z_index, and z_as_relative=false on the blobs keeps front/back
# absolute rather than inheriting the container's z.
#
# _octagon()/_round_corners() extracted to procedural_shape_utils.gd
# (ProceduralShapeUtils) — this was the first of what became five duplicated
# copies project-wide; see that file's own header for the full list.
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

# ---------- LABEL ----------
@export var label_enabled: bool = true
@export var label_key: String = "ENZYME_HELICASE"   # translation key, never display text
@export var label_margin: float = 12.0              # gap above the ring's tallest reach
@export var label_font_size: int = 16
@export var label_text_color: Color = Color(1, 1, 1, 1)
@export var label_panel_color: Color = Color(0, 0, 0, 0.5)
@export var label_z: int = 10                       # above front_z, always readable

const ENZYME_LABEL_SCENE: PackedScene = preload("res://scenes/enzyme_label.tscn")

# ---------- DRAG-TO-SCRUB ----------
# LongSequenceDesign.md follow-up: click-and-drag anywhere on the ring
# scrubs playback. This node stays exactly as simulation-agnostic as the
# rest of the file — it only reports raw SCREEN-space mouse movement while
# a drag is active. Converting that into a scrub index (which needs
# nucleotide_slot_spacing, current zoom, and simulation.gd itself) is
# entirely the owning script's job, not this one's.
#
# Manual hit-test via _unhandled_input() rather than Area2D/input_event —
# Area2D picking silently depends on Viewport.physics_object_picking being
# enabled project-wide, which is exactly the class of silent-failure trap
# this project has hit before (CSV registration, LocaleManager unique-name).
# A local-space point-in-rect check has no such hidden dependency.
## Glyph counter-rotation for vertical mode, PUSHED in by simulation.gd (which
## owns this node) rather than looked up. This file deliberately holds no
## reference to sim/ThemeManager/ZoomManager — see the label params above,
## which are local @exports for the same reason. Pass ZoomManager's
## get_label_counter_rotation() verbatim; EnzymeLabel owns the mirror sign.
var label_counter_rotation: float = 0.0:
	set(value):
		label_counter_rotation = value
		if _label != null:
			_label.set_counter_rotation(value)

signal scrub_drag_started()
## Vector2, not float: this node reports raw screen movement on BOTH axes and
## deliberately does not decide which one is meaningful. Which axis runs along
## the track depends on ZoomManager.vertical_mode — a simulation-level fact,
## and per the contract above, resolving those is the owning script's job. The
## owner picks the component at the same site where it already converts px to
## a slot index. See VerticalModeDesign.md Part 4.
signal scrub_drag_delta(cumulative_px: Vector2)  # screen-space, since drag start
signal scrub_drag_ended()

var _dragging: bool = false
var _drag_start_screen: Vector2 = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _dragging and _point_in_click_region(get_global_mouse_position()):
				_dragging = true
				_drag_start_screen = event.position
				scrub_drag_started.emit()
				get_viewport().set_input_as_handled()
		elif _dragging:
			_dragging = false
			scrub_drag_ended.emit()
	elif event is InputEventMouseMotion and _dragging:
		scrub_drag_delta.emit(event.position - _drag_start_screen)

## Click region reuses the same footprint formula simulation.gd already
## computes for this ring's label positioning (ring_radius + max_blob_height
## * 0.5) — no new geometry invented. Width is generous (1.5x max_blob_width)
## since blobs oscillate in width as they rotate.
func _point_in_click_region(global_point: Vector2) -> bool:
	var local_point = to_local(global_point)
	var half_width = max_blob_width * 1.5
	var half_height = ring_radius + max_blob_height * 0.5
	return abs(local_point.x) <= half_width and abs(local_point.y) <= half_height

var _blobs: Array[Polygon2D] = []
var _roll: float = 0.0
var _label: EnzymeLabel = null

func _ready() -> void:
	skew = deg_to_rad(ring_skew_deg)
	_rebuild_blobs()
	_setup_label()

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

func _setup_label() -> void:
	if not label_enabled:
		return
	_label = ENZYME_LABEL_SCENE.instantiate()
	_label.z_as_relative = false
	_label.z_index = label_z
	add_child(_label)
	_label.set_key(label_key)
	_label.set_style(null, label_font_size, label_text_color, label_panel_color)
	_label.set_counter_rotation(label_counter_rotation)
	_update_label()

func _update_label() -> void:
	if _label == null:
		return
	var offset_y := ring_radius + max_blob_height * 0.5 + label_margin
	_label.set_anchor_pos(Vector2(0.0, -offset_y))

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
		blob.polygon = ProceduralShapeUtils.round_corners(ProceduralShapeUtils.octagon(w, h, chamfer_ratio), corner_radius_ratio, corner_segments)
		blob.position = Vector2(0.0, ring_radius * sin(theta))
		var is_front = c >= 0.0
		blob.z_index = front_z if is_front else back_z
		blob.color = front_color if is_front else back_color
		blob.visible = h > 1.0   # drop the degenerate ~zero-height sliver right at the flip point
	_update_label()