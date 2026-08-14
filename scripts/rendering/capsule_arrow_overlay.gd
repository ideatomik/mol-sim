class_name CapsuleArrowOverlay
extends Node2D

# ==========================================
# capsule_arrow_overlay.gd
# ONE-OFF promo-video recording overlay — NOT a permanent feature, NOT an
# extension of the shipped intra-residue directional capsule (see
# MolecularIdentityHierarchy_Design.md's "Resolution — intra-residue
# directional capsule"). The capsule already shows 5'->3' direction as a
# static shape; this arrow reinforces the same direction via motion, for
# exactly one recording take.
#
# PLACEMENT: NOT added to simulation.tscn (matching trailer.gd's own
# precedent of staying out of the permanent scene). A future camera-
# choreography script add_child()s this node when the shot starts and
# queue_free()s it when done — presence in the tree IS the activation
# surface, no separate enabled flag. This guarantees it can never render
# during normal play/scrub/any other state, since nothing outside an
# explicit add_child() call can make it exist at all.
#
# Both MoleculeStructureRenderer and this node sit at identity transform
# as direct children of the same scene root (scenes/simulation.tscn), so
# raw Vector2 world positions from molecule_structure_renderer.gd's
# _capsule_layout (c5/c3 per residue) are usable here directly — no
# transform/offset compensation needed.
#
# Scrub-safety note: per-frame _process(delta) state (not a pure function
# of simulation state, this project's usual rule for anything drawn
# during normal play) is fine here specifically because this node is
# never part of the permanent scene tree — there's no "user drags the
# timeline mid-shot" scenario to protect against for a node that only
# exists for the duration of one scripted recording take.
# ==========================================

## Residue reference — the same {c5, c3} Vector2 pair shape
## molecule_structure_renderer.gd's _capsule_layout already uses
## internally. No new identifier scheme invented: there is no existing
## "look up residue X's world position" API anywhere in this codebase
## (_capsule_layout carries no slot/strand key, and zoom_manager.gd's
## target system is a camera-framing abstraction, unrelated). Settable
## from the Inspector for isolated static-position testing now, and as
## plain property assignment from the future camera-choreography script.
@export var c5_position: Vector2 = Vector2.ZERO
@export var c3_position: Vector2 = Vector2.ZERO

@export_group("Timing")
## Duration of the left-to-right sweep across the capsule's own
## horizontal span (c5.x -> c3.x). Tuned live via the Remote Inspector
## against a real capsule (F4 test harness) — see capsule's own
## molecular_debug_capsule_padding etc. for the project's established
## "tune live, then lock the default in" workflow this followed.
@export var arrow_lerp_seconds: float = 1.0
## Used for BOTH the fade-out (at the rightmost/3' position) and the
## fade-in (at the leftmost/5' position, immediately after the snap) —
## one shared value, not two. Tuned live, see arrow_lerp_seconds.
@export var arrow_fade_seconds: float = 0.1

@export_group("Geometry")
## Gap (world units) between the capsule's own top edge (atom radius +
## capsule padding above the c5/c3 line) and this arrow's fixed Y
## position. Tuned live, see arrow_lerp_seconds.
@export var vertical_gap: float = 8.0
## Arrowhead length/half-width, world units — deliberately this script's
## OWN tunables, not tm.molecular_backbone_arrow_*, which belong to the
## separate permanent backbone-arrow feature. Tuned live (unchanged from
## the starting guess), see arrow_lerp_seconds.
@export var arrow_length: float = 6.0
@export var arrow_half_width: float = 3.0
## Tuned live to #f4e100 — see arrow_lerp_seconds. Near-identical to the
## capsule's own tuned yellow (theme_manager.gd's
## molecular_debug_capsule_border_color scene override, ~#f4e100 as well)
## rather than the deliberately-distinct cyan this started at — a
## considered choice made live against the real shot, not an oversight.
@export var arrow_color: Color = Color(0.95686275, 0.88235294, 0.0)

## ThemeManager reference, injected by whoever creates this node (see
## molecule_structure_renderer.gd's temp verification wiring) rather than
## resolved here via get_node("%ThemeManager") — that lookup is unreliable
## for a node instantiated purely at runtime (.new() + add_child(), never
## part of the edited scene, no owner set), and silently returning null
## from _draw() below made a real failure here look identical to "nothing
## wrong, just not visible yet." Caught live: the node existed in the
## remote tree the whole time, sitting at its untransformed local (0,0)
## origin, because _draw() was returning before ever drawing anything.
var tm: Node = null

enum _Phase { MOVING, FADE_OUT, FADE_IN }

var _phase: _Phase = _Phase.MOVING
var _phase_elapsed: float = 0.0


func _process(delta: float) -> void:
	_phase_elapsed += delta
	var duration: float = arrow_lerp_seconds if _phase == _Phase.MOVING else arrow_fade_seconds
	if _phase_elapsed >= duration:
		_phase_elapsed = 0.0
		# MOVING -> FADE_OUT -> FADE_IN -> MOVING. FADE_IN always starts
		# at t=0 (leftmost/5') by construction below, which IS the
		# required snap — no separate snap step needed.
		_phase = _Phase.values()[(_phase + 1) % 3]
	queue_redraw()


func _draw() -> void:
	var t: float = 0.0
	var alpha: float = 1.0
	match _phase:
		_Phase.MOVING:
			t = clamp(_phase_elapsed / arrow_lerp_seconds, 0.0, 1.0)
		_Phase.FADE_OUT:
			t = 1.0
			alpha = 1.0 - clamp(_phase_elapsed / arrow_fade_seconds, 0.0, 1.0)
		_Phase.FADE_IN:
			t = 0.0
			alpha = clamp(_phase_elapsed / arrow_fade_seconds, 0.0, 1.0)

	if tm == null:
		return
	# Matches the REAL capsule's actual rendered size (see
	# molecule_structure_renderer.gd's _draw_c5_c3_capsule()) so this
	# arrow sits accurately above whatever the capsule is currently tuned
	# to, rather than a guessed/hardcoded offset.
	var capsule_radius: float = tm.molecular_atom_radius + tm.molecular_debug_capsule_padding
	var arrow_y: float = min(c5_position.y, c3_position.y) - capsule_radius - vertical_gap
	var arrow_x: float = lerp(c5_position.x, c3_position.x, t)
	var tip: Vector2 = Vector2(arrow_x + arrow_length * 0.5, arrow_y)
	var base_a: Vector2 = Vector2(arrow_x - arrow_length * 0.5, arrow_y - arrow_half_width)
	var base_b: Vector2 = Vector2(arrow_x - arrow_length * 0.5, arrow_y + arrow_half_width)

	var color: Color = arrow_color
	color.a *= alpha
	draw_polygon(PackedVector2Array([tip, base_a, base_b]), PackedColorArray([color]))
