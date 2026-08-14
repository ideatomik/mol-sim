class_name PrimerCapsuleOverlay
extends Node2D

# ==========================================
# primer_capsule_overlay.gd
# Highlight for the RNA primer's own start-to-end extent (shot C,
# camera_regent.gd, Rilare 17's line). Same shape tool as the shipped
# atom-tier direction capsule and the bead-tier pair-capsule
# (ProceduralShapeUtils.capsule_outline()), new caller, own semantics —
# spans the primer's span, not a base pair or backbone direction. Own
# tunables (theme_manager.gd's primer_highlight_*), not shared with
# either prior capsule's fields.
#
# Same runtime-only instantiation convention as CapsuleArrowOverlay /
# PairCapsuleOverlay — presence in the tree IS the activation surface,
# tm injected by the caller (not self-resolved).
# ==========================================

@export var start_position: Vector2 = Vector2.ZERO
@export var end_position: Vector2 = Vector2.ZERO

var tm: Node = null

func _draw() -> void:
	if tm == null:
		return
	var radius: float = tm.base_radius + tm.primer_highlight_padding
	var outline: PackedVector2Array = ProceduralShapeUtils.capsule_outline(start_position, end_position, radius, 12)
	draw_polyline(outline, tm.primer_highlight_border_color, tm.primer_highlight_border_width, false)
