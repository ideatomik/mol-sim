extends Node2D
class_name PolymeraseHalo
# ==========================================
# polymerase_halo.gd  —  idle nucleotide pool orbiting one polymerase (v71)
#
# The FUNCTIONAL counterpart to nucleotide_field.gd's decorative environmental
# field (see PolymeraseDesign.md's "two separate particle systems" split):
#   - nucleotide_field.gd = ambient background dNTPs, cosmetic, whole viewport.
#   - PolymeraseHalo (this file) = a small, fixed pool staying close to ONE
#     polymerase — the pool the capture mechanic will later draw from
#     ("nearest halo particle is selected... resolves into the specific
#     required nucleotide type... travels to the clamp").
#
# THIS FILE IS IDLE-ONLY (first pass). No capture/resolve/travel logic yet —
# deliberately deferred so the idle motion can be seen and used to reason
# about the capture animation before that riskier piece (which touches the
# base-spawn trigger) gets designed.
#
# Motion: same Brownian-jitter physics as nucleotide_field.gd (matching
# max_speed/jitter_accel defaults), bounded by a circular velocity-reflecting
# boundary (halo_radius) around the clamp instead of the field's viewport-edge
# wrap — a "living chaos" cloud that stays close to the polymerase.
#
# SOURCE OF TRUTH: size, drift physics, and alpha are read LIVE from
# sim.nucleotide_field each frame — not duplicated as separate exports here.
# Particles are now REAL typed bases (letter + per-type color via
# sim._get_base_fill()), same visual language as the field — this genuinely
# is "a tiny nucleotide_field around the polymerase," just bounded to
# halo_radius instead of the viewport and with a smaller, fixed pool.
#
# Z-layering: sits IN FRONT of the clamp's back pieces and the backbone/bonds,
# but still BEHIND the actual bases/markers and the clamp's front cap. The
# original placement (behind the clamp's entire back body) put most of the
# halo's small radius directly under a large opaque shape, making it read as
# "hiding" rather than a visible cloud.
# ==========================================

const Z_IDLE := 1   # in front of backbone(-1)/bonds(0)/clamp-back(-3,-2), behind bases(2)/markers(3)/clamp-front(4)
const BASES := ["A", "T", "C", "G"]

@export_group("Halo")
@export var particle_count: int = 5 : set = set_particle_count
## How far the cloud is allowed to wander from the clamp center, in pixels.
@export var halo_radius: float = 60.0

var _tex: ImageTexture = null
var _pos: Array = []
var _vel: Array = []
var _nodes: Array = []
var _sim: Node = null
var _field: Node = null    # nucleotide_field.gd instance — live source for size/physics/alpha
var _tm: Node = null       # ThemeManager — font/label + fallback source if _field is missing
var _last_radius: float = -1.0
var _last_softness: float = -1.0

func setup(sim: Node, mirror: bool) -> void:
	_sim = sim
	_tm = sim.get_node("%ThemeManager")
	_field = sim.nucleotide_field
	var center_offset: float = sim.dna_ribbons_gap / 2.0
	position.y = -center_offset if mirror else center_offset
	_build_texture(_current_blur_softness())
	_build_particles()
	set_process(true)

func _fill_for(bt: String) -> Color:
	# Same single source of truth nucleotide_field.gd uses, so halo particles
	# always match the real bases' and field's palette.
	if _sim != null and _sim.has_method("_get_base_fill"):
		return _sim._get_base_fill(bt)
	return Color.WHITE

## Returns the first halo particle currently showing the given base type, or
## null if none match right now. Not called from anywhere yet — this is what
## a future capture step would use to grab a matching particle instead of an
## arbitrary one. See the matching-strategy discussion (session notes) before
## wiring it in: with a small pool (~5) across 4 types, an exact match isn't
## guaranteed at every capture moment.
func find_particle_of_type(letter: String) -> Node:
	for n in _nodes:
		if n.base_type == letter:
			return n
	return null

func _current_radius() -> float:
	return _field.particle_radius if _field != null else (_tm.base_radius if _tm != null else 10.0)

func _current_max_speed() -> float:
	return _field.max_speed if _field != null else 18.0

func _current_jitter_accel() -> float:
	return _field.jitter_accel if _field != null else 40.0

func _current_field_alpha() -> float:
	return _field.field_alpha if _field != null else 0.35

func _current_blur_enabled() -> bool:
	return _field.blur_enabled if _field != null else true

func _current_blur_extent() -> float:
	return _field.blur_extent if _field != null else 1.4

func _current_blur_softness() -> float:
	return _field.blur_softness if _field != null else 0.45

## Guarantees at least min(count, BASES.size()) distinct types are represented
## — plain independent-random draws don't, and with a small pool (~5 across 4
## types) that was leaving types missing entirely. Any slots beyond the
## guaranteed set are free-random. Shuffled so the guaranteed types aren't
## always in the same particle indices.
func _assign_types(count: int) -> Array:
	var result: Array = []
	var guaranteed: Array = BASES.duplicate()
	guaranteed.shuffle()
	for i in range(min(count, guaranteed.size())):
		result.append(guaranteed[i])
	for i in range(guaranteed.size(), count):
		result.append(BASES[randi() % BASES.size()])
	result.shuffle()
	return result

func _build_texture(softness: float) -> void:
	const RES := 32
	var img := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	var c := Vector2(RES, RES) * 0.5
	var core := clamp(softness, 0.0, 1.0)
	for y in range(RES):
		for x in range(RES):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (RES * 0.5)
			var a := 1.0
			if d > core:
				a = 1.0 - smoothstep(core, 1.0, d)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clamp(a, 0.0, 1.0)))
	_tex = ImageTexture.create_from_image(img)
	_last_softness = softness

func _build_particles() -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear(); _pos.clear(); _vel.clear()
	_last_radius = _current_radius()
	var blur_on = _current_blur_enabled()
	var extent = _current_blur_extent()
	var label_color: Color = _tm.base_label_color if _tm != null else Color.BLACK
	var font: Font = (_tm.base_label_font if (_tm != null and _tm.base_label_font != null) else ThemeDB.fallback_font)
	var font_size: int = _tm.base_label_font_size if _tm != null else 14
	var types := _assign_types(max(0, particle_count))
	for i in range(types.size()):
		var dot := _HaloDot.new()
		dot.tex = _tex
		dot.base_type = types[i]
		dot.color = _fill_for(types[i])
		dot.font = font
		dot.font_size = font_size
		dot.label_color = label_color
		dot.radius_px = _last_radius
		dot.blur_enabled = blur_on
		dot.blur_draw_size = _last_radius * 2.0 * extent
		dot.z_index = Z_IDLE
		dot.z_as_relative = false
		add_child(dot)
		_nodes.append(dot)
		var ang = randf() * TAU
		var r = randf() * halo_radius
		var p = Vector2(cos(ang), sin(ang)) * r
		_pos.append(p)
		_vel.append(Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _current_max_speed() * 0.5)
		dot.position = p
		dot.queue_redraw()

func _process(delta: float) -> void:
	modulate.a = _current_field_alpha()

	var softness_now = _current_blur_softness()
	var softness_changed = abs(softness_now - _last_softness) > 0.005
	if softness_changed:
		_build_texture(softness_now)   # updates _last_softness internally
		for n in _nodes:
			n.tex = _tex

	var r_now = _current_radius()
	var blur_on = _current_blur_enabled()
	var extent = _current_blur_extent()
	if abs(r_now - _last_radius) > 0.01 or softness_changed:
		_last_radius = r_now
		for n in _nodes:
			n.radius_px = r_now
			n.blur_enabled = blur_on
			n.blur_draw_size = r_now * 2.0 * extent
			n.queue_redraw()

	var spd = _current_max_speed()
	var jit = _current_jitter_accel()
	for i in range(_nodes.size()):
		# Same Brownian nudge + speed clamp as nucleotide_field.gd, read live
		# so tuning the field's physics tunes this too.
		_vel[i] += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * jit * delta
		_vel[i] = _vel[i].limit_length(spd)
		var p = _pos[i] + _vel[i] * delta
		# Bounded, not wrapped: reflect the velocity off halo_radius so the
		# cloud stays close to the clamp but keeps wandering/filling its
		# interior, rather than piling up at a hard rim.
		if p.length() > halo_radius:
			var n = p.normalized()
			_vel[i] = _vel[i] - 2.0 * _vel[i].dot(n) * n
			p = n * halo_radius
		_pos[i] = p
		_nodes[i].position = p

# ---------- SETTERS (Inspector-live) ----------

func set_particle_count(v: int) -> void:
	particle_count = max(0, v)
	if is_inside_tree() and _tex != null:
		_build_particles()

# --- inner draw node: soft-textured or hard circle + centered label ---
class _HaloDot extends Node2D:
	var tex: ImageTexture
	var color: Color = Color.WHITE
	var radius_px: float = 10.0        # true particle radius — used for the hard-circle fallback
	var blur_enabled: bool = true
	var blur_draw_size: float = 20.0   # radius_px * blur_extent * 2 — only used when blur_enabled
	var base_type: String = ""
	var font: Font = null
	var font_size: int = 14
	var label_color: Color = Color.BLACK
	func _draw() -> void:
		if blur_enabled and tex != null:
			var r = blur_draw_size * 0.5
			draw_texture_rect(tex, Rect2(-r, -r, blur_draw_size, blur_draw_size), false, color)
		else:
			draw_circle(Vector2.ZERO, radius_px, color, true, -1.0, true)
		if font != null and base_type != "":
			var ascent = font.get_ascent(font_size)
			var descent = font.get_descent(font_size)
			var ssize = font.get_string_size(base_type, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var baseline_y = (ascent - descent) * 0.5
			draw_string(font, Vector2(-ssize.x / 2.0, baseline_y), base_type,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
