extends Node2D
class_name DnaStrand

@export var is_top_strand: bool = true
@onready var backbone: Line2D = $Backbone

var bases: Array[NitrogenBase] = []
var left_marker: NitrogenBase
var right_marker: NitrogenBase
var current_helicase_x: float = 0.0

const PEEL_WIDTH: float = 60.0
const MAX_SEPARATION: float = 80.0
const BASE_RADIUS: float = 15.0


func _ready():
	if not backbone:
		push_warning("DnaStrand: 'Backbone' Line2D node not found! Check the scene hierarchy.")
	else:
		backbone.visible = true
		backbone.antialiased
		backbone.add_to_group("highlightable")
		backbone.z_index = -1
		backbone.z_as_relative = false
		
		# Apply initial theme values
		if ThemeManager:
			backbone.default_color = ThemeManager.backbone_color
			backbone.width = ThemeManager.backbone_width # <-- NEW
		
	# Listen for theme changes
	if ThemeManager:
		ThemeManager.theme_changed.connect(_on_theme_changed)

func _on_theme_changed():
	if backbone:
		backbone.default_color = ThemeManager.backbone_color
		backbone.width = ThemeManager.backbone_width # <-- NEW
	queue_redraw()

# Draws the 5'->3' directional arrows (< or >)
func _draw():
	if bases.size() < 2:
		return
		
	var arrow_right = PackedVector2Array([Vector2(-6, -5), Vector2(6, 0), Vector2(-6, 5)])
	var arrow_left = PackedVector2Array([Vector2(6, -5), Vector2(-6, 0), Vector2(6, 5)])
	var arrow_shape = arrow_left if is_top_strand else arrow_right
	
	var arrow_color = ThemeManager.arrow_color if ThemeManager else Color(0.9, 0.9, 0.9, 0.8)
	if backbone:
		arrow_color.a *= backbone.modulate.a 
	
	for i in range(bases.size() - 1):
		var b1 = bases[i]
		var b2 = bases[i+1]
		
		# Only draw if bases are close together
		if b1.position.distance_to(b2.position) < 100.0:
			
			# FIX: Calculate the dynamic offset for BOTH b1 and b2 individually!
			var dist1 = current_helicase_x - b1.original_pos.x
			var progress1 = clamp(dist1 / PEEL_WIDTH, 0.0, 1.0)
			var start_offset1 = -BASE_RADIUS if is_top_strand else BASE_RADIUS
			var end_offset1 = BASE_RADIUS if is_top_strand else -BASE_RADIUS
			var offset1 = lerp(start_offset1, end_offset1, progress1)
			
			var dist2 = current_helicase_x - b2.original_pos.x
			var progress2 = clamp(dist2 / PEEL_WIDTH, 0.0, 1.0)
			var start_offset2 = -BASE_RADIUS if is_top_strand else BASE_RADIUS
			var end_offset2 = BASE_RADIUS if is_top_strand else -BASE_RADIUS
			var offset2 = lerp(start_offset2, end_offset2, progress2)
			
			# Apply the specific offsets to each point
			var p1 = Vector2(b1.position.x, b1.position.y + offset1)
			var p2 = Vector2(b2.position.x, b2.position.y + offset2)
			
			# Calculate the angle and midpoint based on the correctly offset points
			var angle = (p2 - p1).angle()
			var mid_point = (p1 + p2) / 2.0
			
			var arrow_points = PackedVector2Array()
			for p in arrow_shape:
				arrow_points.append(mid_point + p.rotated(angle))
				
			draw_colored_polygon(arrow_points, arrow_color)

func build_sequence(sequence: Array, base_scene: PackedScene, spacing: float, start_x: float, start_y: float):
	left_marker = base_scene.instantiate()
	left_marker.base_type = "3'" if is_top_strand else "5'"
	left_marker.state = NitrogenBase.State.TEMPLATE
	left_marker.make_template()
	left_marker.original_pos = Vector2(start_x - spacing, start_y)
	left_marker.position = left_marker.original_pos
	add_child(left_marker)

	for i in range(sequence.size()):
		var base: NitrogenBase = base_scene.instantiate()
		base.base_type = sequence[i]
		base.state = NitrogenBase.State.TEMPLATE
		base.make_template()
		
		var pos = Vector2(start_x + (i * spacing), start_y)
		base.position = pos
		base.original_pos = pos
		
		add_child(base)
		bases.append(base)
		
	right_marker = base_scene.instantiate()
	right_marker.base_type = "5'" if is_top_strand else "3'"
	right_marker.state = NitrogenBase.State.TEMPLATE
	right_marker.make_template()
	right_marker.original_pos = Vector2(start_x + (sequence.size() * spacing), start_y)
	right_marker.position = right_marker.original_pos
	add_child(right_marker)

	_update_backbone()
	

# CALLED EVERY FRAME TO KEEP ARROWS VISIBLE
func _process(delta):
	# FIX: Removed the backbone.points update from here! 
	# It was overwriting the dynamic lerp calculated in update_peel() 
	# with a static offset every single frame.
	
	# We only need to redraw the directional arrows here.
	queue_redraw() 

# CALLED BY HELICASE EVERY FRAME FOR DYNAMIC UNZIPPING ANIMATION
func update_peel(helicase_x: float):
	current_helicase_x = helicase_x
	if not backbone:
		return

	# TROMBONE LOOP: only the bottom (lagging) template strand loops.
	# The top (leading) strand keeps the simple peel-up animation.
	if not is_top_strand:
		_update_peel_with_loop(helicase_x)
		return

	var points: PackedVector2Array = []
	
	# Helper function to calculate the new position of unzipped bases
	var apply_position = func(node: NitrogenBase, original_x: float, original_y: float):
		node.is_unzipped = true
		var t = Time.get_ticks_msec() / 1000.0
		var wobble_x = sin(t * node.wobble_speed + node.wobble_phase) * 1.5
		var wobble_y = cos(t * node.wobble_speed * 0.7 + node.wobble_phase) * 1.5
		
		var dist = helicase_x - original_x
		var progress = clamp(dist / PEEL_WIDTH, 0.0, 1.0)
		
		var y_offset = 0.0
		if dist > 0:
			var ease = smoothstep(0.0, 1.0, progress)
			var direction = -1.0 if is_top_strand else 1.0
			y_offset = ease * MAX_SEPARATION * direction
		
		node.position.x = original_x + wobble_x
		node.position.y = original_y + y_offset + wobble_y

	# 1. Update the 5'/3' markers
	if left_marker:
		apply_position.call(left_marker, left_marker.original_pos.x, left_marker.original_pos.y)

	# 2. Update the bases and calculate the backbone curve
	for base in bases:
		apply_position.call(base, base.original_pos.x, base.original_pos.y)
		
		var dist = helicase_x - base.original_pos.x
		var progress = clamp(dist / PEEL_WIDTH, 0.0, 1.0)
		
		# THE -15 TO +15 INTERPOLATION OFFSET
		# Top strand: starts at -15, shifts to +15
		# Bottom strand: starts at +15, shifts to -15
		var start_offset = -BASE_RADIUS if is_top_strand else BASE_RADIUS
		var end_offset = BASE_RADIUS if is_top_strand else -BASE_RADIUS
		var tangential_offset = lerp(start_offset, end_offset, progress)
		
		# Apply the dynamic offset to the base's current position
		var backbone_y = base.position.y + tangential_offset
		points.append(Vector2(base.position.x, backbone_y))
		
	# 3. Update the 5'/3' markers
	if right_marker:
		apply_position.call(right_marker, right_marker.original_pos.x, right_marker.original_pos.y)

	# Apply the new curve to the Line2D
	backbone.points = points
	
	# Redraw the directional arrows
	queue_redraw()

# ==========================================
# TROMBONE LOOP (bottom/lagging template strand only)
# Categorizes bases as zipped / loop / finished and routes the loop
# region through a Curve2D so it actually bulges into a U-shape,
# anchored at the lagging polymerase on one end and the helicase
# on the other.
# ==========================================
const LOOP_MIN_DEPTH: float = 250.0
const LOOP_WIDTH_FOR_DEPTH: float = 80.0 # Mirrors PEEL_WIDTH-ish horizontal span used in the depth formula
const BASE_SPACING: float = 35.0

func _update_peel_with_loop(helicase_x: float):
	var t = Time.get_ticks_msec() / 1000.0

	var wobble_for = func(node: NitrogenBase) -> Vector2:
		var wx = sin(t * node.wobble_speed + node.wobble_phase) * 1.5
		var wy = cos(t * node.wobble_speed * 0.7 + node.wobble_phase) * 1.5
		return Vector2(wx, wy)

	# Find the lagging polymerase to know where the loop should anchor.
	var lagging_poly = null
	for p in get_tree().get_nodes_in_group("polymerases"):
		if not p.is_leading:
			lagging_poly = p
			break

	# Fallback: if there's no lagging polymerase yet (e.g. detached/not spawned),
	# behave like a simple peel so we never leave bases unpositioned.
	if lagging_poly == null:
		_simple_peel_fallback(helicase_x, wobble_for)
		return

	var anchor_x: float = lagging_poly.factory_anchor_x if lagging_poly.factory_anchor_initialized else helicase_x

	# --- 1. Categorize bases ---
	var zipped: Array[NitrogenBase] = []
	var loop_bases: Array[NitrogenBase] = []
	var finished: Array[NitrogenBase] = []

	for base in bases:
		if base.original_pos.x > helicase_x:
			zipped.append(base)
		elif base.original_pos.x < anchor_x:
			finished.append(base)
		else:
			loop_bases.append(base)

# DIAGNOSTIC: throttled loop-health print, same 2s cadence as polymerase.gd's
	# POLY DEBUG. Reports category counts plus the loop's actual bounding box,
	# so we can tell from logs alone whether the loop is engaging at all and
	# whether it's actually spreading out into a curve vs collapsing flat.
	if Engine.get_physics_frames() % 120 == 0:
		var min_x = INF
		var max_x = -INF
		var min_y = INF
		var max_y = -INF
		for b in loop_bases:
			min_x = min(min_x, b.position.x)
			max_x = max(max_x, b.position.x)
			min_y = min(min_y, b.position.y)
			max_y = max(max_y, b.position.y)
		print("[%s] LOOP DEBUG | zipped:%d loop:%d finished:%d | anchor_x:%.1f helicase_x:%.1f | loop_bbox: x[%.1f,%.1f] y[%.1f,%.1f]" % [
			Time.get_ticks_msec(), zipped.size(), loop_bases.size(), finished.size(),
			anchor_x, helicase_x, min_x, max_x, min_y, max_y
		])

	# --- 2. Zipped bases: still inside the helix, no movement at all ---
	if left_marker and left_marker.original_pos.x > helicase_x:
		left_marker.is_unzipped = false
		left_marker.position = left_marker.original_pos
	for base in zipped:
		base.is_unzipped = false
		base.is_on_loop = false
		base.position = base.original_pos

	# --- 3. Finished bases: lie flat again, alongside the synthesized strand ---
	# PUSH MECHANIC: when a base transitions from the loop to finished for the
	# first time, animate it from its last loop position to its flat resting
	# spot instead of snapping instantly. This is the visible "push" half of
	# the trombone motion -- the loop releasing and the strand snapping taut
	# as the polymerase advances. Previously this was an instant position
	# assignment, which combined with the loop->finished move happening on
	# the same frame as the anchor jump, made the release invisible (the
	# base just silently teleported to a position that hadn't been drawn yet).
	for base in finished:
		var w = wobble_for.call(base)
		var target_pos = base.original_pos + w

		if not base.was_on_loop:
			# Already finished last frame (or always was) -- keep current
			# simple behavior, no need to re-trigger a tween every frame.
			base.is_unzipped = true
			base.is_on_loop = false
			base.position = target_pos
		else:
			# JUST transitioned from loop -> finished this frame: kick off
			# the push tween from wherever it currently is (its last loop
			# curve position) to its flat resting position.
			base.is_unzipped = true
			base.is_on_loop = false
			if base.push_tween:
				base.push_tween.kill()
			base.push_tween = base.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			base.push_tween.tween_property(base, "position", target_pos, 0.35)

		base.was_on_loop = false

	# --- 4. Loop bases: sampled along a Curve2D from anchor -> helicase ---
	var poly_y = lagging_poly.global_position.y
	var fork_point = Vector2(helicase_x, global_position.y if bases.is_empty() else bases[0].original_pos.y)
	var anchor_point = Vector2(anchor_x, poly_y)

	var n = loop_bases.size()
	if n > 0:
		# DEPTH FIX: previously depth was a rough guess that didn't account
		# for how far apart anchor_point and fork_point actually are, so the
		# curve's real arc length often didn't match n * BASE_SPACING at all
		# -- bases got stretched or bunched to fill whatever length the
		# curve happened to have. This solves depth analytically (treating
		# each side of the U as roughly a straight diagonal leg) so the
		# curve's arc length comes out close to the bases' natural spacing.
		# Cheap (closed-form), not exact (real Bezier arc length differs
		# slightly from the two-straight-legs approximation), but much
		# closer than before without repeatedly rebuilding the curve.
		var target_len = n * BASE_SPACING
		var half_width = abs(helicase_x - anchor_x) / 2.0
		var half_target = target_len / 2.0
		var depth = LOOP_MIN_DEPTH
		if half_target > half_width:
			depth = max(LOOP_MIN_DEPTH, sqrt(half_target * half_target - half_width * half_width))
		# Loop bulges downward for the bottom strand (direction = +1).
		var bulge_y = poly_y + depth

		var curve = Curve2D.new()
		# Point A: at the polymerase (loop "entry", where finished strand resumes)
		curve.add_point(anchor_point, Vector2.ZERO, Vector2(60, depth * 0.5))
		# Point B: bottom of the U
		var mid_x = (anchor_x + helicase_x) / 2.0
		curve.add_point(Vector2(mid_x, bulge_y), Vector2(-(helicase_x - anchor_x) * 0.25, 0), Vector2((helicase_x - anchor_x) * 0.25, 0))
		# Point C: at the helicase (loop "exit", freshly unzipped template)
		curve.add_point(fork_point, Vector2(-60, depth * 0.5), Vector2.ZERO)

# DIAGNOSTIC: same cadence, geometry inputs that fed the curve. If
		# anchor_point and fork_point are nearly identical, or depth stays
		# pinned at LOOP_MIN_DEPTH while n grows, that points at the curve
		# construction itself rather than how bases are sampled along it.
		if Engine.get_physics_frames() % 120 == 0:
			print("[%s] LOOP CURVE | n:%d depth:%.1f | anchor_pt:%s mid_pt:%s fork_pt:%s | curve_len:%.1f" % [
				Time.get_ticks_msec(), n, depth, anchor_point, Vector2(mid_x, bulge_y), fork_point, curve.get_baked_length()
			])

		var curve_len = curve.get_baked_length()
		# Loop bases are ordered left-to-right (anchor side -> helicase side) in `bases`,
		# since that's how build_sequence() populated the array.
		for i in range(n):
			var base = loop_bases[i]
			base.is_unzipped = true
			base.is_on_loop = true
			# SPACING FIX: previously this distributed bases evenly across
			# whatever the curve's actual baked length happened to be
			# ((i+0.5)/n * curve_len), which decoupled spacing entirely from
			# BASE_SPACING -- when the curve came out longer or shorter than
			# n * BASE_SPACING (which it always did, since depth was a rough
			# guess), bases stretched or bunched instead of keeping their
			# normal fixed spacing. Now we step at a fixed BASE_SPACING
			# distance from the anchor end instead, matching how spacing
			# works everywhere else on the strand. Clamped to curve_len so a
			# slightly-undersized curve (depth estimate is approximate, not
			# exact) doesn't sample past the end.
			var dist_along = clamp((float(i) + 0.5) * BASE_SPACING, 0.0, curve_len)
			var sample_t = curve.sample_baked_with_rotation(dist_along)
			var w = wobble_for.call(base)
			base.position = sample_t.origin + w
			# NORMAL DIRECTION FIX: rather than trusting a fixed +90deg
			# rotation of the tangent (which can point either toward or away
			# from the loop's interior depending on which way the tangent
			# happens to face at that point), explicitly pick whichever
			# perpendicular direction points further downward (+y). Our
			# bottom-strand loop only ever bulges downward (bulge_y = poly_y
			# + depth, never upward), so "away from the loop interior" is
			# unambiguous: it's always the candidate with the larger y
			# component. This was the source of the new strand drifting at
			# an inconsistent angle relative to its template partner --
			# get_rotation() + PI/2 sometimes pointed the wrong way as the
			# tangent direction varied along the curve.
			var tangent_angle = sample_t.get_rotation()
			var candidate_a = Vector2.RIGHT.rotated(tangent_angle + PI / 2.0)
			var candidate_b = Vector2.RIGHT.rotated(tangent_angle - PI / 2.0)
			base.loop_normal_angle = (tangent_angle + PI / 2.0) if candidate_a.y > candidate_b.y else (tangent_angle - PI / 2.0)

	# --- 5. Build backbone points in strand order: finished -> loop -> zipped ---
	var points: PackedVector2Array = []
	var tangential = BASE_RADIUS # bottom strand offset sign

	if left_marker:
		left_marker.is_on_loop = false
		if left_marker.original_pos.x < anchor_x:
			left_marker.is_unzipped = true
			var w = wobble_for.call(left_marker)
			left_marker.position = left_marker.original_pos + w
		points.append(Vector2(left_marker.position.x, left_marker.position.y + tangential))

	for base in finished:
		points.append(Vector2(base.position.x, base.position.y + tangential))
	for base in loop_bases:
		points.append(base.position) # already on the curve; no flat tangential offset inside the loop
	for base in zipped:
		points.append(Vector2(base.position.x, base.position.y + tangential))

	if right_marker:
		if right_marker.original_pos.x > helicase_x:
			right_marker.is_unzipped = false
			right_marker.position = right_marker.original_pos
			points.append(Vector2(right_marker.position.x, right_marker.position.y + tangential))
		else:
			right_marker.is_unzipped = true
			var w = wobble_for.call(right_marker)
			right_marker.position = right_marker.original_pos + w
			points.append(Vector2(right_marker.position.x, right_marker.position.y + tangential))

	backbone.points = points
	queue_redraw()

func _simple_peel_fallback(helicase_x: float, wobble_for: Callable):
	var points: PackedVector2Array = []
	var apply_position = func(node: NitrogenBase, original_x: float, original_y: float):
		node.is_unzipped = true
		node.is_on_loop = false
		var w = wobble_for.call(node)
		var dist = helicase_x - original_x
		var progress = clamp(dist / PEEL_WIDTH, 0.0, 1.0)
		var y_offset = 0.0
		if dist > 0:
			var ease = smoothstep(0.0, 1.0, progress)
			y_offset = ease * MAX_SEPARATION
		node.position.x = original_x + w.x
		node.position.y = original_y + y_offset + w.y

	if left_marker:
		apply_position.call(left_marker, left_marker.original_pos.x, left_marker.original_pos.y)
	for base in bases:
		apply_position.call(base, base.original_pos.x, base.original_pos.y)
		var backbone_y = base.position.y + BASE_RADIUS
		points.append(Vector2(base.position.x, backbone_y))
	if right_marker:
		apply_position.call(right_marker, right_marker.original_pos.x, right_marker.original_pos.y)

	backbone.points = points
	queue_redraw()

func get_exposed_bases(helicase_x: float) -> Array:
	var exposed: Array[NitrogenBase] = []
	for base in bases:
		if helicase_x - base.original_pos.x > 20.0:
			exposed.append(base)
	return exposed

func _update_backbone():
	if not backbone:
		return
	var points: PackedVector2Array = []
	var tangential_offset = -BASE_RADIUS if is_top_strand else BASE_RADIUS
	
	for base in bases:
		var point_y = base.position.y + tangential_offset
		points.append(Vector2(base.position.x, point_y))
		
	backbone.points = points
	queue_redraw()
