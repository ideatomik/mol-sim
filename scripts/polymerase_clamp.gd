extends Node2D
class_name PolymeraseClamp
# ==========================================
# polymerase_clamp.gd  —  runtime TWO-PIECE procedural polymerase clamp (v71)
#
# Replaces the SVG-authored 3-piece clamp (polymerase_shape.gd) with the
# procedural octagon approach validated in polymerase_clamp_test.gd — same
# building block as helicase_ring.gd (rounded-corner octagon), same
# scrub-is-a-pure-function-of-one-scalar discipline.
#
# Added as a CHILD of the polymerase node (leading_polymerase / the
# SynthesisCircle "lagging_polymerase"). That parent rides the template-backbone
# row; this node self-offsets to the duplex CENTRE and mirrors for the leading
# strand, so NO existing positioning code changes. Fade rides the parent's
# modulate.a for free (CanvasItem modulate propagates to children).
#
# FRAME (lagging POV): INSIDE = toward the template/centre = local -y;
#   OUTSIDE = toward the screen edge = local +y. Leading strand is the single
#   scale.y = -1 mirror of this.
#
# BACK BODY (behind the strand): DOWN height = span + 2*margin, centred on the
#   duplex midline; OUTER edge pinned, grows INWARD with pump t. Deforms/frame.
# JAW (in front of the strand): fixed height = jaw_height_ratio * back's DOWN
#   height; inside edge glued to the back's inner edge, extends outward,
#   translates inward as the back grows. Copies the back's absolute corner
#   sizes so the diagonals read identical despite being shorter.
#
# CAPTURE ANCHOR: the jaw's OUTER edge — swept outward on the down-stroke to
#   push the captured nucleotide toward the outer strand. Exposed via
#   get_jaw_cap_inner_anchor() (name kept for the _capture_* call sites), which
#   walks the real transform chain so it tracks pump + mirror automatically.
#
# LABEL: a static "DNA Polymerase III" name tag anchored outside the back
# body (the far side from the duplex), independent of the pump — it does NOT
# breathe with set_pump(t), so it stays put while the clamp animates. Same
# key ("ENZYME_POLYMERASE") for both strands, matching PolymeraseDesign.md's
# "same enzyme, mirrored/recolored per strand" treatment — no leading/lagging
# text split. Config is read live from ThemeManager's "Polymerase Clamp"
# group each frame, same as every other geometry/colour param here (unlike
# helicase_ring.gd, which keeps its own local @export vars instead).
# Mirroring is handled by the label itself (set_mirror), so its glyphs stay
# upright on the leading strand despite this node's own scale.y = -1.
#
# LABEL KEY is tier-conditional (Pol I pass, OkazakiMaturationDesign.md):
# plain "ENZYME_POLYMERASE" ("Polymerase") at every tier except Complex,
# where it switches to "ENZYME_POL3" ("Pol III") — the only tier where Pol I
# and Pol III are both visible at once, so it's the only tier where the
# generic name would actually be ambiguous. Read live in _apply() (moved out
# of the one-time _build()) via %ComplexityManager.is_enabled("pol1") —
# pol1_enabled lives on ComplexityManager itself, unlike ligase_enabled
# (which predates ComplexityManager and still lives directly on sim).
#
# All geometry/colour params live in ThemeManager's "Polymerase Clamp" group and
# are read live each frame, so Inspector tuning works while running. Colours are
# per-strand (leading = mirror; lagging = non-mirror). No pump clock in here —
# set_pump(t) alone determines the pose; scrub rests at t = 0 (DOWN).
#
# TOPOLOGY-LABEL ADDENDUM: _is_leading (was _mirror) is now read for two
# purposes, not one — the leading/lagging COLOR split it always drove, and
# now which polymerase this IS in LINEAR topology (Pol epsilon vs Pol delta;
# see EnzymeLabelsDesign.md's Topology-conditional polymerase labels
# addendum). Renamed rather than adding a second bool: two flags that must
# always agree is the same trap in a worse form, since then they CAN
# disagree. Zero behavior change — both call sites already pass the value
# this needed (leading_clamp.setup(sim, true) / lagging_clamp.setup(sim,
# false)); only the name changed to match what it now means.
# ==========================================

const ENZYME_LABEL_SCENE: PackedScene = preload("res://scenes/enzyme_label.tscn")

var _is_leading: bool = false
var _sim: Node = null
var _tm: Node = null
var _complexity_mgr: Node = null
var _back: Polygon2D = null
var _jaw: Polygon2D = null
var _lowerjaw: Polygon2D = null
var _label: EnzymeLabel = null
var _pump_t: float = 0.0
var _anchor_local_y: float = 0.0
## True while the atom-tier position swap (replication_manager.gd) has
## repositioned this clamp's own PARENT container to an atom-tier anchor —
## zeroes the duplex-centre local offset _apply() would otherwise
## unconditionally re-apply on top of that every frame, silently undoing
## the swap. See set_atom_tier_offset_suppressed().
var _atom_tier_offset_suppressed: bool = false

# ---------- DRAG-TO-SCRUB ----------
# LongSequenceDesign.md follow-up: click-and-drag anywhere on the clamp
# scrubs playback — same mechanism as helicase_ring.gd (see that file for
# the fuller rationale on manual hit-testing over Area2D). Click-region
# half-extents are cached from _apply()'s own already-computed geometry
# each frame, rather than recomputing the whole pipeline in the hit-test.
signal scrub_drag_started()
## Vector2, not float: this node reports raw screen movement on BOTH axes and
## deliberately does not decide which one is meaningful. Which axis runs along
## the track depends on ZoomManager.vertical_mode — a simulation-level fact,
## and per the contract above, resolving those is the owning script's job. The
## owner picks the component at the same site where it already converts px to
## a slot index. See VerticalModeDesign.md Part 4.
signal scrub_drag_delta(cumulative_px: Vector2)  # screen-space, since drag start
signal scrub_drag_ended()
## FollowModeDesign — double-click within the same click region drag-to-scrub
## already uses. Emitted for BOTH leading and lagging (this file is shared,
## _is_leading-agnostic like the rest of its click handling) — follow mode is
## currently lagging-only by product decision, scoped at the connection site
## in replication_manager.gd, not here.
signal follow_requested()

var _dragging: bool = false
## Same dead-zone fix as helicase_ring.gd — see its var block for the full
## rationale (found via [FOLLOWCLICK] prints: LP's smaller click region made
## the spurious-pause bug near-guaranteed, vs. intermittent on helicase).
var _pending: bool = false
var _drag_start_screen: Vector2 = Vector2.ZERO
const DRAG_DEADZONE_PX: float = 6.0  # NOT YET TUNED
var _click_half_width: float = 0.0
var _click_half_height: float = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _dragging and not _pending and _point_in_click_region(get_global_mouse_position()):
				if event.double_click:
					follow_requested.emit()
					get_viewport().set_input_as_handled()
					return
				_pending = true
				_drag_start_screen = event.position
				get_viewport().set_input_as_handled()
		elif _dragging:
			_dragging = false
			scrub_drag_ended.emit()
		elif _pending:
			_pending = false
	elif event is InputEventMouseMotion and (_dragging or _pending):
		if _pending:
			if (event.position - _drag_start_screen).length() < DRAG_DEADZONE_PX:
				return
			_pending = false
			_dragging = true
			scrub_drag_started.emit()
		scrub_drag_delta.emit(event.position - _drag_start_screen)

## Asked of ZoomManager through _sim — the same reach this file already makes
## for %ThemeManager and %ComplexityManager in setup(). 0.0 horizontally.
## Topology-conditional polymerase name. See EnzymeLabelsDesign.md's
## "Topology-conditional polymerase labels" addendum for the full matrix and
## reasoning — summary: each topology ignores exactly one of its two inputs.
## CIRCULAR ignores strand (E. coli: same enzyme, both strands) and honors
## pol1_enabled (disambiguates a generic name once Pol I shares the screen).
## LINEAR ignores pol1_enabled (Pol epsilon/delta are already unambiguous) and
## honors strand (genuinely different enzymes: Pol epsilon leading, Pol delta
## lagging).
##
## Confirmed against complexity_manager.gd: the enum is `Topology`
## (CIRCULAR/LINEAR), not the guessed `TopologyMode`, declared with no
## class_name. Accessed dynamically through the Node-typed _complexity_mgr
## reference below — same mechanism that already lets is_enabled() work on
## this same untyped reference elsewhere in this file, so no static type
## needed on this side.
func _polymerase_label_key() -> String:
	var is_linear: bool = false
	if _complexity_mgr != null:
		is_linear = _complexity_mgr.topology_mode == _complexity_mgr.Topology.LINEAR
	if is_linear:
		return "ENZYME_POL_EPSILON" if _is_leading else "ENZYME_POL_DELTA"
	# CIRCULAR (or complexity manager missing): existing tier-conditional
	# behavior, unchanged. pol1_enabled lives on ComplexityManager itself,
	# not on sim (unlike ligase_enabled, which predates ComplexityManager) —
	# see complexity_manager.gd's migration note.
	var complex_tier: bool = _complexity_mgr.is_enabled("pol1") if _complexity_mgr != null else false
	return "ENZYME_POL3" if complex_tier else "ENZYME_POLYMERASE"

func _zoom_label_rotation() -> float:
	if _sim == null:
		return 0.0
	var zm = _sim.get_node_or_null("%ZoomManager")
	return zm.get_label_counter_rotation() if zm != null else 0.0

func _point_in_click_region(global_point: Vector2) -> bool:
	var local_point = to_local(global_point)
	return abs(local_point.x) <= _click_half_width and abs(local_point.y) <= _click_half_height

func setup(sim: Node, is_leading: bool) -> void:
	_sim = sim
	_is_leading = is_leading
	_tm = sim.get_node("%ThemeManager")
	_complexity_mgr = sim.get_node_or_null("%ComplexityManager")
	_build()
	set_pump(0.0)

func _build() -> void:
	_back = Polygon2D.new()
	_back.z_as_relative = false   # absolute z so the DNA renders between the pieces
	add_child(_back)
	_jaw = Polygon2D.new()
	_jaw.z_as_relative = false
	add_child(_jaw)
	_lowerjaw = Polygon2D.new()
	_lowerjaw.z_as_relative = false
	add_child(_lowerjaw)
	_label = ENZYME_LABEL_SCENE.instantiate()
	_label.z_as_relative = false
	add_child(_label)
	_label.set_mirror(_is_leading)   # leading -> therefore mirrored
	# NOTE: set_key() no longer called here — the key is tier-conditional
	# now (see _apply()), so it has to be read live rather than fixed once
	# at build time.

## Lift the jaw. t = 0 -> DOWN (clamped, scrub rests here), t = 1 -> UP (open).
## Fed the already-shaped step value by replication_manager (sin(step_t*PI) /
## sin(phase*PI)), so the pump rate is inherited from the helicase step timing.
func set_pump(t: float) -> void:
	_pump_t = clampf(t, 0.0, 1.0)
	_apply()

## Zeroes (or restores) the duplex-centre local offset — see
## _atom_tier_offset_suppressed's own doc comment. Forces an immediate
## _apply() so the change takes effect the same frame, not next time
## set_pump() happens to fire.
func set_atom_tier_offset_suppressed(suppressed: bool) -> void:
	if suppressed == _atom_tier_offset_suppressed:
		return
	_atom_tier_offset_suppressed = suppressed
	_apply()

func _apply() -> void:
	if _back == null or _tm == null or _sim == null:
		return
	var tm := _tm

	# --- typed pulls from ThemeManager (tm.* is Variant; annotate to keep := clean downstream) ---
	var margin: float = tm.clamp_margin
	var grow: float = tm.clamp_back_grow
	var back_width: float = tm.clamp_back_width
	var jaw_width: float = tm.clamp_jaw_width
	var jaw_ratio: float = tm.clamp_jaw_height_ratio
	var lower_jaw_ratio: float = tm.clamp_lower_jaw_height_ratio
	var lower_jaw_width: float = tm.clamp_lower_jaw_width
	var out_ratio: float = tm.clamp_outside_chamfer_ratio
	var in_ratio: float = tm.clamp_inside_chamfer_ratio
	var corner_ratio: float = tm.clamp_corner_radius_ratio
	var corner_segs: int = tm.clamp_corner_segments
	var back_z: int = tm.clamp_back_z
	var front_z: int = tm.clamp_front_z
	var back_col: Color = tm.clamp_leading_back_color if _is_leading else tm.clamp_lagging_back_color
	var front_col: Color = tm.clamp_leading_front_color if _is_leading else tm.clamp_lagging_front_color

	# --- registration: origin -> duplex centre, mirror flips inside/outside ---
	# span = full vertical extent of the duplex (strands + backbones) = the DOWN
	# duplex_span from the harness. Recomputed each frame so it tracks any gap change.
	var gap: float = _sim.dna_ribbons_gap
	var span: float = gap + 2.0 * (float(_tm.backbone_offset_distance) + float(_tm.backbone_line_width) / 2.0)
	var center_offset: float = gap / 2.0
	position.y = 0.0 if _atom_tier_offset_suppressed else (-center_offset if _is_leading else center_offset)
	scale = Vector2(1.0, -1.0) if _is_leading else Vector2(1.0, 1.0)

	var t: float = _pump_t

	# Derived geometry (from span + margin).
	var back_base_height: float = span + 2.0 * margin
	var jaw_h: float = back_base_height * jaw_ratio
	var half_down: float = back_base_height * 0.5

	# BACK BODY: now grows symmetrically in BOTH directions, since the lower
	# jaw mirrors the jaw and needs backing on its side too. Inner edge keeps
	# the exact same formula as before (jaw/lower-jaw math is untouched);
	# outer edge now extends by the same amount instead of staying pinned.
	# Total extra height is therefore 2x what a single-sided grow gave.
	# (outer edge = +half_down + extra_back; not stored, since _back.position
	# = ZERO and h_back already encode the symmetric span)
	var extra_back: float = grow * t
	var h_back: float = back_base_height + 2.0 * extra_back
	var back_inner_y: float = -half_down - extra_back
	var cx_back: float = out_ratio * (back_width * 0.5)
	var cy_out_back: float = out_ratio * half_down                                        # crisp, sized off the rest-state half height
	var cy_in_back: float = lerpf(out_ratio * half_down, in_ratio * (h_back * 0.5), t)    # stretches with t
	_back.polygon = ProceduralShapeUtils.round_corners(_octagon(back_width, h_back, cx_back, cy_in_back, cy_out_back), corner_ratio, corner_segs)
	_back.position = Vector2.ZERO   # symmetric growth keeps it centred on the duplex midline
	_back.color = back_col
	_back.z_index = back_z

	# JAW: fixed height, inside edge glued to the back's inner edge, extends
	# outward (overlaps the back). Copies the back's absolute cap sizes; reined
	# in proportionally only if two caps would overrun the jaw's own height.
	var half_jaw: float = jaw_h * 0.5
	var cy_in_jaw: float = cy_in_back
	var cy_out_jaw: float = cy_out_back
	var cap_sum: float = cy_in_jaw + cy_out_jaw
	if cap_sum > jaw_h:
		var k: float = jaw_h / cap_sum
		cy_in_jaw *= k
		cy_out_jaw *= k
	var cx_jaw: float = minf(cx_back, jaw_width * 0.5)
	_jaw.polygon = ProceduralShapeUtils.round_corners(_octagon(jaw_width, jaw_h, cx_jaw, cy_in_jaw, cy_out_jaw), corner_ratio, corner_segs)
	_jaw.position = Vector2(0.0, back_inner_y + half_jaw)
	_jaw.color = front_col
	_jaw.z_index = front_z

	# LOWER JAW: exact mirror of the jaw about the duplex midline (clamp-local
	# y = 0, where _back sits centred at rest). Glued edge tracks -back_inner_y
	# (mirror of the back's growing edge); free edge points toward the DNA.
	# Same crisp/stretchy chamfer split as the jaw, reusing the back's own
	# cap values, just assigned to the opposite octagon side since this piece
	# is flipped. Own height/width ratios so it can be tuned independently.
	# Pump is shared (_pump_t) with no separate phase, so at t=0 (DOWN/clamped)
	# both prongs sit together at rest, and at t=1 (UP/open) they swing apart
	# in sync — a true pincer open/close, not two independently-timed pieces.
	var lower_jaw_h: float = back_base_height * lower_jaw_ratio
	var half_lower_jaw: float = lower_jaw_h * 0.5
	var cy_in_lower: float = cy_in_back      # stretchy cap -> glued (far) edge
	var cy_out_lower: float = cy_out_back    # crisp cap -> free (near-DNA) edge
	var cap_sum_lower: float = cy_in_lower + cy_out_lower
	if cap_sum_lower > lower_jaw_h:
		var k_lower: float = lower_jaw_h / cap_sum_lower
		cy_in_lower *= k_lower
		cy_out_lower *= k_lower
	var cx_lower: float = minf(cx_back, lower_jaw_width * 0.5)
	# top(-hh)=free/near-DNA edge -> crisp; bottom(+hh)=glued/far edge -> stretchy
	_lowerjaw.polygon = ProceduralShapeUtils.round_corners(_octagon(lower_jaw_width, lower_jaw_h, cx_lower, cy_out_lower, cy_in_lower), corner_ratio, corner_segs)
	_lowerjaw.position = Vector2(0.0, -back_inner_y - half_lower_jaw)
	_lowerjaw.color = front_col
	_lowerjaw.z_index = front_z

	# CAPTURE ANCHOR: jaw's OUTER edge (local), cached for get_jaw_cap_inner_anchor().
	_anchor_local_y = back_inner_y + jaw_h

	# LABEL: static offset outward from the duplex (+y, pre-mirror), independent
	# of pump t so it doesn't breathe with the clamp. tm.enzyme_labels_enabled /
	# tm.polymerase_label_margin / tm.label_font_size / tm.label_color /
	# tm.label_z are new fields — see chat for the exact ThemeManager export
	# block to add.
	if _label:
		var label_enabled: bool = tm.enzyme_labels_enabled
		_label.visible = label_enabled
		if label_enabled:
			_label.set_key(_polymerase_label_key())
			var label_margin_out: float = tm.polymerase_label_margin
			var label_font_size: int = tm.label_font_size
			var label_text_color: Color = tm.label_color
			var label_z: int = tm.label_z
			_label.set_style(null, label_font_size, label_text_color)
			# Read live, like every other label param in this block. EnzymeLabel
			# negates this internally for the mirrored (leading) clamp — see
			# _apply_rotation() there; nothing here needs to know the sign.
			_label.set_counter_rotation(_zoom_label_rotation())
			_label.z_index = label_z
			_label.set_anchor_pos(Vector2(0.0, half_down + label_margin_out))

	# Click region for drag-to-scrub — widest of the back/jaw pieces, full
	# vertical reach of the back body. Recomputed here (not cached across
	# frames) so it stays correct as the clamp animates/tunes live.
	_click_half_width = max(back_width, jaw_width) * 0.5
	_click_half_height = half_down

## Live label toggle — this clamp's own _apply() already re-runs every
## frame via set_pump(), so this is redundant for it specifically, but kept
## for API parity with ligase.gd/pol1.gd/primase_blip.gd, whose _apply()
## doesn't run every frame.
func refresh_label_visibility() -> void:
	if _label != null and _tm != null:
		_label.visible = _tm.enzyme_labels_enabled

## Live world-space position of the jaw's outer edge, right now. Walks the real
## transform chain (local point -> this clamp's scale/mirror/position -> the
## polymerase's world position) via to_global(), so it tracks the pump and works
## identically for both strands with no strand-specific math here. Name kept from
## the SVG version so replication_manager's _capture_* call sites are unchanged.
func get_jaw_cap_inner_anchor() -> Vector2:
	if _jaw == null:
		return global_position
	return to_global(Vector2(0.0, _anchor_local_y))

# ---------- octagon building block (asymmetric caps: inside vs outside) ----------
# NOTE: this asymmetric _octagon() (separate inside/outside chamfer per
# top/bottom) is genuinely unique to this file's back/jaw pieces — never
# duplicated elsewhere, so nothing to extract here. round_corners() WAS
# duplicated (identically) across all five procedural enzyme files —
# extracted to procedural_shape_utils.gd (ProceduralShapeUtils); see that
# file's own header for the full list.

func _octagon(w: float, h: float, cx: float, cy_top: float, cy_bottom: float) -> PackedVector2Array:
	# TOP (-hh) = INSIDE (up) -> cy_top; BOTTOM (+hh) = OUTSIDE (down) -> cy_bottom.
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
