class_name PairCapsuleOverlay
extends Node2D

# ==========================================
# pair_capsule_overlay.gd
# Bead-tier base-pair highlight — a capsule spanning two bead positions
# across strands (template_top + template_bottom, same slot, self-paired
# template state). NOT the shipped atom-tier intra-residue C5'->C3'
# direction capsule (molecule_structure_renderer.gd's
# _draw_c5_c3_capsule()) — a different semantic use of the same
# ProceduralShapeUtils.capsule_outline() shape tool: this highlights
# base-pair identity/connection, not backbone direction.
#
# Provisional/investigation — confirmed working in isolation only so far
# (see simulation.gd's TEMP F6 debug harness); NOT wired into
# camera_regent.gd or any real shot choreography yet. That's deliberately
# a separate follow-up once this piece and simulation.gd's
# has_slot_bead_position()/get_slot_bead_position() are both confirmed.
#
# PLACEMENT: instantiated purely at runtime (no scene presence), same
# convention as CapsuleArrowOverlay — presence in the tree IS the
# activation surface, no enabled bool needed.
#
# Scrub-safe: _draw() reads bead_a_position/bead_b_position fresh every
# call — no stored/animated geometry of its own. Whoever drives this
# (currently: the debug harness, once per spawn; eventually: a real
# choreography script, live every frame) is responsible for keeping those
# two fields current; this node itself never derives or caches a position.
# ==========================================

@export var bead_a_position: Vector2 = Vector2.ZERO
@export var bead_b_position: Vector2 = Vector2.ZERO

## ThemeManager reference, injected by whoever creates this node — NOT
## self-resolved via %ThemeManager, same reasoning as CapsuleArrowOverlay.tm:
## that lookup is unreliable for a node instantiated purely at runtime
## (.new() + add_child(), never part of the edited scene, no owner set).
var tm: Node = null

func _draw() -> void:
	if tm == null:
		return
	var radius: float = tm.base_radius + tm.pair_highlight_padding
	var outline: PackedVector2Array = ProceduralShapeUtils.capsule_outline(bead_a_position, bead_b_position, radius, 12)
	# antialiased=false, matching the shipped capsule's own
	# _draw_c5_c3_capsule() and every other line in that renderer.
	draw_polyline(outline, tm.pair_highlight_border_color, tm.pair_highlight_border_width, false)
