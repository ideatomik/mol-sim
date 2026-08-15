class_name ZoomFrameUtils
extends RefCounted

# ==========================================
# zoom_frame_utils.gd
# Shared zoom-frame math for simulation.gd and replication_manager.gd —
# extracted after `anchor_centered_frame()` turned up byte-identical in both,
# per the "extract shared code by what divergence costs" rule.
#
# `along_extent`/`cross_extent` are plain parameters rather than this
# function calling instance methods itself: simulation.gd's
# `_zoom_along_extent()`/`_zoom_cross_extent()` do a fresh
# `get_node_or_null("%ZoomManager")` lookup per call, while
# replication_manager.gd's use a cached `zoom_mgr` member — genuinely
# different implementations behind matching signatures, not duplication to
# extract. Keeping this function pure avoids coupling it to either style.
#
# `class_name` makes this globally accessible with no preload — call
# ZoomFrameUtils.anchor_centered_frame(...) directly. Static methods only;
# this is never instantiated.
# ==========================================

## Smallest zoom that keeps every point in `context` within `fit_pct` of the
## viewport, centered on `anchor`. `along_extent`/`cross_extent` are the
## caller's current along-track/cross-track viewport extents.
static func anchor_centered_frame(anchor: Vector2, context: Array, fit_pct: float, along_extent: float, cross_extent: float) -> Dictionary:
	var max_dx: float = 0.0
	var max_dy: float = 0.0
	for p in context:
		max_dx = max(max_dx, abs(p.x - anchor.x))
		max_dy = max(max_dy, abs(p.y - anchor.y))
	var size: Vector2 = Vector2(max(max_dx * 2.0, 1.0), max(max_dy * 2.0, 1.0))
	# size.x is a world-x span, size.y a world-y span. The extent helpers supply
	# whichever viewport dimension each currently maps to — the rotation is
	# exactly 90 degrees, so the box stays axis-aligned and needs no transform.
	var target_zoom: float = minf((along_extent * fit_pct) / size.x, (cross_extent * fit_pct) / size.y)
	return {zoom = target_zoom, position = anchor}
