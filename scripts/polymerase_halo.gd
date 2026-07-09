extends Node2D
class_name PolymeraseHalo
# ==========================================
# polymerase_halo.gd  —  idle nucleotide pool orbiting one polymerase (v71)
#
# The FUNCTIONAL counterpart to nucleotide_field.gd's decorative environmental
# field (see PolymeraseDesign.md's "two separate particle systems" split):
#   - nucleotide_field.gd = ambient background dNTPs, cosmetic, whole viewport.
#   - PolymeraseHalo (this file) = a small, fixed pool staying close to ONE
#     polymerase — the pool replication_manager.gd's _capture_* functions
#     draw from via capture_particle() (search-first-then-fallback matching,
#     see its doc comment).
#
# Motion: same Brownian-jitter physics as nucleotide_field.gd (matching
# max_speed/jitter_accel defaults), bounded by a circular velocity-reflecting
# boundary (halo_radius) around the clamp instead of the field's viewport-edge
# wrap — a "living chaos" cloud that stays close to the polymerase.
#
# SOURCE OF TRUTH: size and drift physics are read LIVE from
# sim.nucleotide_field each frame — not duplicated as separate exports here.
# Alpha is the one exception (see _current_halo_alpha()): it used to be read
# live from the field too, but was decoupled onto its own ThemeManager field
# (polymerase_halo_alpha) so the functional capture pool can be tuned
# independently from the purely-decorative background field's opacity.
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

const Z_IDLE := 3   # in front of backbone(-1)/bonds(0)/clamp-back(-3,-2), behind bases(2)/markers(3)/clamp-front(4)

@export_group("Halo")
@export var particle_count: int = 5 : set = set_particle_count
## How far the cloud is allowed to wander from the clamp center, in pixels.
@export var halo_radius: float = 60.0
## Which letters this halo's particles can show. Default matches DNA
## nucleotides (Pol III's own halo); set to ["A","U","C","G"] for an RNA
## pool (primase's halo — see replication_manager.gd's initialize()) BEFORE
## calling setup(), since _build_particles() reads this during initial fill.
@export var base_letters: PackedStringArray = ["A", "T", "C", "G"]
## Optional per-letter color overrides, checked before falling back to
## sim._get_base_fill() — needed for any letter that function doesn't know
## (e.g. "U", which has no DNA equivalent) and to make an RNA halo's whole
## ambient cloud read as RNA-tinted rather than only the captured/placed
## base. Set BEFORE calling setup(), same reason as base_letters above.
var color_overrides: Dictionary = {}

var _tex: ImageTexture = null
var _pos: Array = []
var _vel: Array = []
var _nodes: Array = []
var _sim: Node = null
var _field: Node = null    # nucleotide_field.gd instance — live source for size/physics/alpha
var _tm: Node = null       # ThemeManager — font/label + fallback source if _field is missing
var _last_radius: float = -1.0
var _last_softness: float = -1.0
# Cached appearance state, refreshed in _build_particles()/_process() — lets
# capture_particle()'s single-particle replenish reuse the same values
# without re-deriving them from _tm/_field each time.
var _cached_font: Font = null
var _cached_font_size: int = 14
var _cached_label_color: Color = Color.BLACK
var _cached_blur_on: bool = true
var _cached_extent: float = 1.4

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
	# color_overrides first (needed for any letter sim._get_base_fill()
	# doesn't know, e.g. "U" — and to make an RNA halo's whole ambient cloud
	# read as RNA-tinted, not just the captured/placed base).
	if color_overrides.has(bt):
		return color_overrides[bt]
	# Same single source of truth nucleotide_field.gd uses otherwise, so
	# halo particles match the real bases' and field's DNA palette.
	if _sim != null and _sim.has_method("_get_base_fill"):
		return _sim._get_base_fill(bt)
	return Color.WHITE

## Returns the first halo particle currently showing the given base type, or
## null if none match right now. Used by capture_particle()'s search step.
func find_particle_of_type(letter: String) -> Node:
	for n in _nodes:
		if n.base_type == letter:
			return n
	return null

## Called once when a polymerase step BEGINS (not on arrival). Search-first,
## fallback-relabel: if a particle of `letter` exists, use it; otherwise
## relabel whichever particle sits closest to the clamp center. Either way,
## that particle is removed from the idle pool and its GLOBAL position
## returned (the caller spawns the real base there and animates it in), and
## one fresh random replacement is spawned to keep the ambient pool at
## particle_count — capture should never visibly deplete the halo.
func capture_particle(letter: String) -> Vector2:
	if _nodes.is_empty():
		return global_position

	var idx = -1
	for i in range(_nodes.size()):
		if _nodes[i].base_type == letter:
			idx = i
			break
	if idx == -1:
		idx = 0
		var best_dist = _pos[0].length()
		for i in range(1, _nodes.size()):
			if _pos[i].length() < best_dist:
				best_dist = _pos[i].length()
				idx = i

	var dot = _nodes[idx]
	var world_pos: Vector2 = dot.global_position
	_nodes.remove_at(idx)
	_pos.remove_at(idx)
	_vel.remove_at(idx)
	dot.queue_free()

	_spawn_into_pool(base_letters[randi() % base_letters.size()])
	return world_pos

func _current_radius() -> float:
	return _field.particle_radius if _field != null else (_tm.base_radius if _tm != null else 10.0)

func _current_max_speed() -> float:
	return _field.max_speed if _field != null else 18.0

func _current_jitter_accel() -> float:
	return _field.jitter_accel if _field != null else 40.0

## Own opacity, previously read live from nucleotide_field.gd's field_alpha
## (forcing both to match) — now its own independent ThemeManager field, so
## the functional capture pool can be tuned separately from the purely
## decorative background field.
func _current_halo_alpha() -> float:
	return _tm.polymerase_halo_alpha if _tm != null else 0.35

func _current_blur_enabled() -> bool:
	return _field.blur_enabled if _field != null else true

func _current_blur_extent() -> float:
	return _field.blur_extent if _field != null else 1.4

func _current_blur_softness() -> float:
	return _field.blur_softness if _field != null else 0.45

## Guarantees at least min(count, base_letters.size()) distinct types are represented
## — plain independent-random draws don't, and with a small pool (~5 across 4
## types) that was leaving types missing entirely. Any slots beyond the
## guaranteed set are free-random. Shuffled so the guaranteed types aren't
## always in the same particle indices.
func _assign_types(count: int) -> Array:
	var result: Array = []
	var guaranteed: Array = base_letters.duplicate()
	guaranteed.shuffle()
	for i in range(min(count, guaranteed.size())):
		result.append(guaranteed[i])
	for i in range(guaranteed.size(), count):
		result.append(base_letters[randi() % base_letters.size()])
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
	_refresh_cached_appearance()
	var types := _assign_types(max(0, particle_count))
	for i in range(types.size()):
		_spawn_into_pool(types[i])

func _refresh_cached_appearance() -> void:
	_last_radius = _current_radius()
	_cached_blur_on = _current_blur_enabled()
	_cached_extent = _current_blur_extent()
	_cached_label_color = _tm.base_label_color if _tm != null else Color.BLACK
	_cached_font = (_tm.base_label_font if (_tm != null and _tm.base_label_font != null) else ThemeDB.fallback_font)
	_cached_font_size = _tm.base_label_font_size if _tm != null else 14

## Builds one particle of the given type using the current cached appearance
## state, places it at a random spot within halo_radius, and appends it to
## the live pool arrays. Shared by _build_particles() (initial fill) and
## capture_particle() (single-particle replenish after a capture).
func _spawn_into_pool(bt: String) -> Node:
	var dot := _HaloDot.new()
	dot.tex = _tex
	dot.base_type = bt
	dot.color = _fill_for(bt)
	dot.font = _cached_font
	dot.font_size = _cached_font_size
	dot.label_color = _cached_label_color
	dot.radius_px = _last_radius
	dot.blur_enabled = _cached_blur_on
	dot.blur_draw_size = _last_radius * 2.0 * _cached_extent
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
	return dot

func _process(delta: float) -> void:
	modulate.a = _current_halo_alpha()

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
		_cached_blur_on = blur_on
		_cached_extent = extent
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