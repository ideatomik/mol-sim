extends Node2D
# ==========================================
# nucleotide_field.gd  —  Environmental free-nucleotide field
# v71 (slice: environmental particle field)
#
# Purely decorative ambient layer: labeled A/T/C/G nucleotides drifting
# through the "solution" behind the DNA, representing the free dNTP pool the
# polymerases will later draw from. It is NOT the polymerase halo (that is a
# separate, functional capture pool designed in PolymeraseDesign.md) — this
# field is cosmetic only and never interacts with synthesis.
#
# Self-contained SHARED base-layer primitive (see SHARED_BASE_SEAM.md): the
# free-monomer solution belongs to the common parent, not to
# replication_manager.gd. This node touches no synthesis, scrub, or polymerase
# state and is intended for reuse by transcription / translation / PCR later.
#
# Lifecycle: a REAL persisted scene node (child of root, Inspector-editable —
# matches the ThemeManager convention), not code-instantiated. Particle count
# is derived from the sequence length (particles_per_slot * num_slots) and
# rebuilt on every on_sequence_changed() call from simulation.gd, including
# the first load.
#
# Rendering: a single node draws every particle in its own _draw() — a cached
# soft-edge texture (draw_texture_rect) or a hard draw_circle depending on
# blur_enabled, plus draw_string for the label — no per-particle nodes and no
# physics (unlike nitrogen_base.gd, which is a RigidBody2D we deliberately do
# not reuse here).
#
# Scrub note: drift is deliberately driven by this node's own _process, NOT by
# helicase step_t. It carries zero state that scrub must reproduce, so a
# free-running clock is safe here — this is the intentional exception to the
# "no independent-clock visuals" rule, which exists to protect SYNCHRONIZED
# visuals (polymerase position, bond breaking), none of which this touches.
# It keeps drifting while paused/scrubbing so the solution never looks frozen.
# ==========================================

@export_group("Field")
## Master on/off. Folds into a low-info theme preset later.
@export var enabled: bool = true : set = set_enabled
## Particles per slot in the current sequence. Actual count = round(this *
## num_nucleotide_slots), recomputed on every on_sequence_changed() call —
## so the field scales with sequence length rather than being a fixed number.
@export var particles_per_slot: float = 4.0
## Hard ceiling on particle_count regardless of sequence length — this is a
## purely decorative layer, and at the new 300-base ceiling (LongSequenceDesign.md),
## particles_per_slot * num_slots would otherwise scale to 1200 particles,
## which is what caused the FPS drop on large sequences. 200 is comfortably
## above what a short sequence ever produces (4 * 57 = 228 is the closest
## case, so this only actually clamps once sequences get meaningfully long).
@export var max_particles: int = 200
## Circle radius of each drifting nucleotide. 0.0 = auto-match the real
## synthesized bases' radius (tm.base_radius), resolved in _ready().
## Set a positive value here to override with a fixed size instead.
@export var particle_radius: float = 0.0
## Draw order — kept behind the DNA (the backbone sits at z_index -1).
@export var field_z_index: int = -10 : set = set_field_z_index

@export_group("Motion")
## Peak drift speed (px/sec).
@export var max_speed: float = 18.0
## Strength of the random Brownian nudge applied each frame (px/sec^2).
@export var jitter_accel: float = 40.0
## Extra world-space margin around the visible rect before a particle wraps,
## so wrap-around happens just off-screen instead of popping at the edge.
@export var edge_margin: float = 40.0

@export_group("Separation")
## Soft push-apart so particles don't visually overlap. Positional correction,
## not real physics (no RigidBody2D/CollisionShape2D) — keeps the field on its
## single-_draw()-call, no-per-particle-node design.
@export var separation_enabled: bool = true
## Extra gap kept beyond just touching (particle_radius * 2), so they read as
## distinct circles rather than glued together.
@export var separation_padding: float = 2.0
## Relaxation passes per frame. 1 is enough at this field's density; raise
## only if particles still visibly overlap in dense clusters.
@export var separation_iterations: int = 1

@export_group("Blur")
## Soft-particle look: draws a cached soft-edged circle texture (radial alpha
## falloff, baked once) instead of a hard draw_circle. No shader, no
## SubViewport — a shared texture tinted per-particle via draw_texture_rect's
## modulate, same single-_draw()-call architecture as everything else here.
@export var blur_enabled: bool = true
## Fraction of the drawn radius that stays fully opaque before the falloff
## begins. 0 = soft all the way to the center (very hazy); 1 = hard edge (no
## visible blur). Rebuilds the cached texture when changed.
@export_range(0.0, 1.0) var blur_softness: float = 0.45 : set = set_blur_softness
## How far the soft falloff extends past particle_radius (as a multiplier).
## Larger = bigger, hazier halo. Purely a draw-size scale — no texture rebuild
## needed when this changes.
@export_range(1.0, 2.5) var blur_extent: float = 1.4

@export_group("Label")
## Manual nudge for label centering, in case font metrics need a tweak beyond
## the ascent/descent-based centering already applied in _draw().
@export var label_offset: Vector2 = Vector2.ZERO

# ---------- REFERENCES ----------
var sim: Node = null
var tm: Node = null
## ZoomManager — glyph counter-rotation only. The REFERENCE is cached in
## _ready(), but the VALUE is read live in _draw(), exactly like tm's
## base_label_color already is. That sidesteps a real _ready()-order hazard:
## ZoomManager is a SIBLING, and sibling _ready() order follows scene-tree
## order, so caching its rotation here could capture a pre-orientation zero.
## Reading live cannot.
var zoom_mgr: Node = null
var _font: Font = null
var _font_size: int = 14
var particle_count: int = 0  # computed from particles_per_slot * num_slots — not exported, see on_sequence_changed()
var _rebuild_generation: int = 0  # guards against a stale deferred rebuild firing after a newer sequence load
var _soft_circle_tex: ImageTexture = null  # cached soft-edge alpha mask, shared by every particle

# ---------- PARTICLE STATE (parallel arrays; one entry per particle) ----------
var _pos: Array[Vector2] = []
var _vel: Array[Vector2] = []
var _type: Array[String] = []
var _fill: Array[Color] = []

const BASES := ["A", "T", "C", "G"]

# ==========================================
# LIFECYCLE
# ==========================================

func _ready() -> void:
	# Runs before the parent (root simulation.gd) node's own _ready() body,
	# since Godot readies children before parents — so sim/tm/font are
	# guaranteed valid by the time simulation.gd's first initialize_simulation()
	# call reaches out to this node.
	sim = get_parent()
	tm = get_node("%ThemeManager")
	zoom_mgr = get_node_or_null("%ZoomManager")
	z_index = field_z_index
	modulate.a = tm.nucleotide_field_alpha
	visible = enabled
	set_process(enabled)
	_font = tm.base_label_font if tm.base_label_font != null else ThemeDB.fallback_font
	_font_size = tm.base_label_font_size
	if particle_radius <= 0.0:
		particle_radius = tm.base_radius
	_build_soft_circle_texture()
	print("[FIELD] ready — awaiting first on_sequence_changed()")

## Called by simulation.gd's initialize_simulation() every time a sequence
## loads (including the very first load). Recomputes particle_count from the
## new slot count, then rebuilds — but the rebuild itself is deferred two
## process frames so it captures the camera's post-framing canvas transform
## rather than the stale pre-framing one. (Camera framing lives in a separate
## controller script outside this node's visibility, so rather than guessing
## its exact timing, we just wait a couple of frames — cheap, and the field
## is purely decorative so a two-frame-late rebuild is invisible in practice.)
func on_sequence_changed(num_slots: int) -> void:
	particle_count = min(max(0, roundi(particles_per_slot * num_slots)), max_particles)
	_request_rebuild()

func _request_rebuild() -> void:
	_rebuild_generation += 1
	var gen = _rebuild_generation
	await get_tree().process_frame
	await get_tree().process_frame
	if gen != _rebuild_generation:
		return  # a newer sequence load superseded this rebuild — let it win
	_build_particles()
	print("[FIELD] rebuilt — %d particles, rect=%s" % [_pos.size(), str(_visible_world_rect())])

func _build_particles() -> void:
	_pos.clear(); _vel.clear(); _type.clear(); _fill.clear()
	var rect = _visible_world_rect()
	for i in range(max(0, particle_count)):
		var bt = BASES[randi() % BASES.size()]
		_type.append(bt)
		_fill.append(_fill_for(bt))
		_pos.append(Vector2(
			randf_range(rect.position.x, rect.position.x + rect.size.x),
			randf_range(rect.position.y, rect.position.y + rect.size.y)
		))
		_vel.append(Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * max_speed * 0.5)
	queue_redraw()

func _fill_for(bt: String) -> Color:
	# Reuse sim's single source of truth for base fill, so the field always
	# matches the real bases' palette (opacity is applied via modulate.a).
	if sim != null and sim.has_method("_get_base_fill"):
		return sim._get_base_fill(bt)
	return Color.WHITE

# ==========================================
# DRIFT
# ==========================================

func _process(delta: float) -> void:
	modulate.a = tm.nucleotide_field_alpha
	if not enabled or _pos.is_empty():
		return
	var rect = _visible_world_rect()
	var minx = rect.position.x - edge_margin
	var maxx = rect.position.x + rect.size.x + edge_margin
	var miny = rect.position.y - edge_margin
	var maxy = rect.position.y + rect.size.y + edge_margin
	var span_x = maxx - minx
	var span_y = maxy - miny
	for i in range(_pos.size()):
		# Brownian nudge: perturb velocity, clamp to max_speed, integrate.
		_vel[i] += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * jitter_accel * delta
		_vel[i] = _vel[i].limit_length(max_speed)
		var p = _pos[i] + _vel[i] * delta
		# Wrap around the (margin-expanded) visible rect.
		if span_x > 0.0:
			if p.x < minx: p.x += span_x
			elif p.x > maxx: p.x -= span_x
		if span_y > 0.0:
			if p.y < miny: p.y += span_y
			elif p.y > maxy: p.y -= span_y
		_pos[i] = p
	_resolve_separation()
	queue_redraw()

func _resolve_separation() -> void:
	# Cheap positional push-apart (Verlet-style constraint satisfaction), not
	# force/velocity-based — stays numerically stable with no risk of
	# oscillation or energy build-up, which matters more than physical realism
	# for a decorative field. O(n^2) pair checks are fine at this field's
	# particle counts (low hundreds at most); revisit with a spatial grid only
	# if particles_per_slot is pushed much higher than the current default.
	if not separation_enabled or particle_radius <= 0.0 or _pos.size() < 2:
		return
	# Use the visually-apparent radius (bigger than particle_radius once blur
	# is drawing a wider halo), so particles don't look like they're
	# overlapping even though their nominal circles technically aren't.
	var effective_radius = particle_radius * blur_extent if blur_enabled else particle_radius
	var min_dist = effective_radius * 2.0 + separation_padding
	var min_dist_sq = min_dist * min_dist
	for _iter in range(max(1, separation_iterations)):
		for i in range(_pos.size()):
			for j in range(i + 1, _pos.size()):
				var delta_pos = _pos[j] - _pos[i]
				var dist_sq = delta_pos.length_squared()
				if dist_sq >= min_dist_sq:
					continue
				if dist_sq > 0.0001:
					var dist = sqrt(dist_sq)
					var push = delta_pos * ((min_dist - dist) * 0.5 / dist)
					_pos[i] -= push
					_pos[j] += push
				else:
					# Exactly coincident (rare) — nudge apart along an arbitrary axis.
					var push = Vector2(min_dist * 0.5, 0.0)
					_pos[i] -= push
					_pos[j] += push

# ==========================================
# RENDER
# ==========================================

func _draw() -> void:
	if not enabled:
		return
	var label_color: Color = tm.base_label_color if tm != null else Color.BLACK
	var label_rotation: float = zoom_mgr.get_label_counter_rotation() if zoom_mgr != null else 0.0
	var ascent = _font.get_ascent(_font_size) if _font != null else 0.0
	var descent = _font.get_descent(_font_size) if _font != null else 0.0
	for i in range(_pos.size()):
		var c = _pos[i]
		if blur_enabled and _soft_circle_tex != null:
			var draw_radius = particle_radius * blur_extent
			var rect = Rect2(c - Vector2(draw_radius, draw_radius), Vector2(draw_radius, draw_radius) * 2.0)
			draw_texture_rect(_soft_circle_tex, rect, false, _fill[i])
		else:
			draw_circle(c, particle_radius, _fill[i], true, -1.0, true)
		if _font != null:
			var txt = _type[i]
			var ssize = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
			# draw_string's y is the baseline; centre the text on the circle by
			# putting the ascent/descent midline on c.y.
			# Both coords are now LOCAL TO c, not absolute — the transform
			# below makes c the origin.
			var baseline_y = (ascent - descent) * 0.5
			var draw_pos = Vector2(-ssize.x / 2.0, baseline_y) + label_offset
			# Rotate each glyph around ITS OWN centre. Unlike polymerase_halo.gd
			# — which has a real Node2D per particle and so can rotate about
			# Vector2.ZERO — this file draws EVERY particle in ONE _draw() on a
			# single node. Rotating about the origin would swing the whole cloud
			# around the field's origin instead of spinning letters in place.
			# Passing c as the transform origin is what makes it a per-glyph spin.
			draw_set_transform(c, label_rotation, Vector2.ONE)
			draw_string(_font, draw_pos, txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, label_color)
			# MANDATORY reset — the loop continues and the NEXT particle's
			# draw_circle()/draw_texture_rect() use ABSOLUTE c. Leaving this set
			# would draw every subsequent body in this glyph's rotated frame.
			# (polymerase_halo.gd needs no reset: draw_string is the last call
			# in its _draw().)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==========================================
# VISIBLE-RECT HELPER
# ==========================================

func _visible_world_rect() -> Rect2:
	# v72 fix (zoom system integration): this used to derive the rect live
	# from the viewport's canvas transform every frame — correct in spirit
	# (zoom-aware), but it meant the WRAP boundary itself shrank to whatever
	# tiny region was on-screen while zoomed into a single enzyme (level
	# 3/4). Since the per-frame wrap in _process() only pulls a particle
	# inward by one span-width when it crosses the CURRENT rect's edge,
	# zooming in effectively compressed the whole field into that small
	# area; zooming back out then revealed a cluster that took a long time
	# to re-disperse via the slow Brownian drift.
	#
	# Fix: always wrap within the full "overworld" extent — mirrors
	# zoom_manager.gd's level-1 fit-to-track math (90% width) — regardless
	# of the camera's CURRENT zoom level. Godot already culls anything
	# off-screen, so the field doesn't need to track the live view; it only
	# needs a stable region to roam so it's evenly distributed whenever the
	# player zooms back out to level 1.
	var vp = get_viewport()
	var viewport_size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1152, 648)
	if sim == null or not ("track_length" in sim) or sim.track_length <= 0.0:
		return Rect2(Vector2.ZERO, viewport_size)  # fallback before the first sequence load
	var track_length: float = sim.track_length
	var mid_y: float = sim.center_y if ("center_y" in sim) else viewport_size.y * 0.5
	# Mirrors zoom_manager.gd's _compute_strand_fit() exactly: track_length
	# only fills 90% of the screen width at level 1's zoom, so the actual
	# visible world rect (what this field should roam within) is wider than
	# track_length itself, centered the same way the level-1 camera is.
	# edge_margin is intentionally NOT added here — _process() already adds
	# it on top of whatever this returns, same as before this fix.
	var overworld_zoom: float = (viewport_size.x * 0.90) / track_length
	var world_width: float = viewport_size.x / overworld_zoom
	var world_height: float = viewport_size.y / overworld_zoom
	return Rect2(
		Vector2(track_length * 0.5 - world_width * 0.5, mid_y - world_height * 0.5),
		Vector2(world_width, world_height)
	)

# ==========================================
# SETTERS (Inspector-live)
# ==========================================

func set_enabled(v: bool) -> void:
	enabled = v
	visible = v
	set_process(v)

func set_field_z_index(v: int) -> void:
	field_z_index = v
	z_index = v

func set_blur_softness(v: float) -> void:
	blur_softness = clamp(v, 0.0, 1.0)
	if is_inside_tree():
		_build_soft_circle_texture()
		queue_redraw()

## Bakes a small radial alpha-gradient texture once: fully opaque out to
## blur_softness * radius, then a smoothstep falloff to fully transparent at
## the edge. Resolution-independent of particle_radius/blur_extent — those
## only affect how large the texture is DRAWN each frame (_draw()), not the
## gradient baked into it, so this only needs rebuilding when blur_softness
## itself changes.
func _build_soft_circle_texture() -> void:
	const RES := 64
	var img := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	var center := Vector2(RES, RES) * 0.5
	var tex_radius := RES * 0.5
	var core := clamp(blur_softness, 0.0, 1.0)
	for y in range(RES):
		for x in range(RES):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / tex_radius
			var a := 1.0
			if d > core:
				a = 1.0 - smoothstep(core, 1.0, d)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clamp(a, 0.0, 1.0)))
	_soft_circle_tex = ImageTexture.create_from_image(img)