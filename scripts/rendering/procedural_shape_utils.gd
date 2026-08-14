class_name ProceduralShapeUtils
extends RefCounted

# ==========================================
# procedural_shape_utils.gd
# Shared building blocks for every procedural enzyme visual in this project
# (helicase_ring.gd, polymerase_clamp.gd, ligase.gd, primase_blip.gd,
# pol1.gd) — extracted after `_round_corners()` ended up duplicated five
# times over, the shared-utility item every one of those files' own header
# comments had been individually flagging and deferring since
# helicase_ring.gd first shipped it.
#
# `class_name` makes this globally accessible with no preload — call
# ProceduralShapeUtils.octagon(...) / ProceduralShapeUtils.round_corners(...)
# directly. Static methods only; this is never instantiated.
#
# octagon() covers the SYMMETRIC case only (same chamfer on every corner) —
# helicase_ring.gd, ligase.gd, primase_blip.gd, and pol1.gd all only ever
# needed this variant. polymerase_clamp.gd's own asymmetric octagon (separate
# inside/outside chamfer per its back/jaw pieces) stays local to that file —
# a genuinely different shape, not more duplication to extract; it was never
# copied anywhere else.
#
# round_corners() was the one truly identical across all five files
# (including polymerase_clamp.gd) — the actual target of this extraction.
#
# capsule_outline() (molecule_structure_renderer.gd's provisional intra-
# residue directional-highlight mockup) is a different kind of extraction —
# not deduplication of five near-identical call sites like the two above,
# just the natural home for a generic "line segment + radius -> outline"
# shape once one existed, rather than leaving arc/line math local to a
# single caller. round_corners() rounds a PRE-BUILT polygon's sharp
# vertices via a sampled bezier pullback; it doesn't synthesize a true
# semicircular cap from two bare endpoints + a radius, so it isn't a fit
# for a capsule despite the superficial "rounding" similarity — this is
# genuinely new geometry, not a reuse of that function under the hood.
# ==========================================

## Symmetric octagon — flat vertical sides, chamfered top/bottom caps. Same
## shape all four single-piece procedural blobs in this project use.
static func octagon(w: float, h: float, chamfer: float) -> PackedVector2Array:
	var hw = w * 0.5
	var hh = h * 0.5
	var cx = hw * chamfer
	var cy = hh * chamfer
	return PackedVector2Array([
		Vector2(-hw + cx, -hh),
		Vector2( hw - cx, -hh),
		Vector2( hw, -hh + cy),
		Vector2( hw,  hh - cy),
		Vector2( hw - cx,  hh),
		Vector2(-hw + cx,  hh),
		Vector2(-hw,  hh - cy),
		Vector2(-hw, -hh + cy),
	])

## Generic rounding for any convex polygon: at each vertex, pull back along
## both adjacent edges by a radius relative to that edge's own length, then
## bridge the gap with a sampled quadratic bezier instead of a sharp point.
## Edge-relative radius is what keeps this collapse-safe — as a shape
## squashes and edges shrink, the rounding shrinks with them.
static func round_corners(pts: PackedVector2Array, radius_ratio: float, segments: int) -> PackedVector2Array:
	var n = pts.size()
	if n < 3 or radius_ratio <= 0.0:
		return pts
	var out = PackedVector2Array()
	for i in range(n):
		var prev = pts[(i - 1 + n) % n]
		var cur = pts[i]
		var next = pts[(i + 1) % n]
		var to_prev = prev - cur
		var to_next = next - cur
		var len_prev = to_prev.length()
		var len_next = to_next.length()
		if len_prev < 0.0001 or len_next < 0.0001:
			out.append(cur)
			continue
		var r = radius_ratio * minf(len_prev, len_next) * 0.5
		var p1 = cur + to_prev.normalized() * r
		var p2 = cur + to_next.normalized() * r
		for s in range(segments + 1):
			var t = float(s) / float(segments)
			var a = p1.lerp(cur, t)
			var b = cur.lerp(p2, t)
			out.append(a.lerp(b, t))
	return out

## Shortens a bead-to-bead bond so it runs edge-to-edge instead of
## center-to-center — used by both cofactor files (helicase_atp_cycle.gd,
## ligase_cofactor.gd) for the ATP/NAD+ glyph's connecting bonds. Paired with
## Line2D.LINE_CAP_ROUND, this is what makes a bond read as a short rounded
## connector between two circles rather than a rod passing through their
## centers — which, at partial alpha during a fade, is exactly what let the
## old center-to-center line show through several collinear beads as one
## continuous "backbone," crossing straight over each label in the process.
##
## Clamped rather than allowed to invert: if the two radii already meet or
## overlap (from_r + to_r >= dist), the usable span is zero and both points
## collapse to the same location on the line between the centers — the bond
## simply disappears under the beads rather than drawing backwards.
static func inset_segment(from: Vector2, to: Vector2, from_r: float, to_r: float) -> PackedVector2Array:
	var delta: Vector2 = to - from
	var dist: float = delta.length()
	if dist < 0.0001:
		return PackedVector2Array([from, to])
	var dir: Vector2 = delta / dist
	var usable: float = maxf(dist - from_r - to_r, 0.0)
	var a: Vector2 = from + dir * from_r
	var b: Vector2 = a + dir * usable
	return PackedVector2Array([a, b])

## Border-only padded capsule around a line segment: two straight sides
## offset ±radius perpendicular to `from`->`to`, closed off by a true
## semicircular arc at each end (radius `radius`, centered at `from` and
## `to` respectively) — NOT a filled shape; the caller draws the returned
## outline with draw_polyline()/draw_polygon(..., filled=false), never
## draw_polygon(..., filled=true). Returns a CLOSED loop (the last point
## coincides with the first) sampled at `segments` points per semicircle,
## walking: from+perp -> to+perp -> [arc around `to`, exits toward +dir] ->
## from-perp -> [arc around `from`, exits toward -dir] -> back to
## from+perp. Degenerate-safe: if `from` == `to`, Vector2.normalized() on
## the zero-length direction returns Vector2.ZERO (Godot behavior, not an
## error) — every point collapses to `from`, a zero-area loop rather than a
## crash.
static func capsule_outline(from: Vector2, to: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var dir: Vector2 = (to - from).normalized()
	var perp: Vector2 = dir.rotated(PI / 2.0)
	var perp_angle: float = perp.angle()
	var pts := PackedVector2Array()
	pts.append(from + perp * radius)
	pts.append(to + perp * radius)
	# DECREASING angle for both arcs (not `perp_angle + PI * s/segments`,
	# which sweeps both caps through the SAME side — verified against
	# concrete numbers, dir=(1,0)/perp_angle=90deg: increasing from
	# perp_angle would pass through 180deg = -dir for BOTH caps, i.e. both
	# bulging back toward the segment's own interior instead of away from
	# it, self-intersecting into a bowtie/pointed-petal shape rather than a
	# smooth capsule). Decreasing from perp_angle correctly sweeps this
	# `to`-cap through +dir (away from `from`).
	for s in range(1, segments + 1):
		var a: float = perp_angle - PI * float(s) / float(segments)
		pts.append(to + Vector2(cos(a), sin(a)) * radius)
	pts.append(from - perp * radius)
	# Decreasing from perp_angle+PI correctly sweeps the `from`-cap through
	# -dir (away from `to`) — same rotational sense as the `to`-cap above,
	# which is what keeps the whole boundary a single non-self-intersecting
	# loop rather than two arcs bulging the same way.
	for s in range(1, segments + 1):
		var a: float = perp_angle + PI - PI * float(s) / float(segments)
		pts.append(from + Vector2(cos(a), sin(a)) * radius)
	return pts
