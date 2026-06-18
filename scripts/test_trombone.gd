extends Node2D

var loop_curve: Curve2D = Curve2D.new()
var base_spacing: float = 35.0
var time: float = 0.0

func _ready():
	# CRITICAL: Lower the bake interval for smoother rotation sampling!
	# If it's too high, the rotation will look "blocky" at the bottom of the loop.
	loop_curve.bake_interval = 2.0 

func _process(delta):
	time += delta
	queue_redraw()

func _draw():
	var stretch_factor = (sin(time * 1.5) + 1.0) * 50.0
	
	var helicase_pos = Vector2(200, 200)
	var polymerase_pos = Vector2(350 + stretch_factor, 350 + stretch_factor)
	var rejoin_pos = Vector2(500 + (stretch_factor * 2), 200)

	loop_curve.clear_points()
	
	# Add points with handles for smooth transitions
	loop_curve.add_point(helicase_pos, Vector2(-50, 0), Vector2(50, 0))
	loop_curve.add_point(polymerase_pos, Vector2(-40, 0), Vector2(40, 0))
	loop_curve.add_point(rejoin_pos, Vector2(-50, 0), Vector2(50, 0))

	# Draw straight DNA context
	draw_line(Vector2(0, 200), helicase_pos, Color.GRAY, 4.0)
	draw_line(rejoin_pos, Vector2(1000, 200), Color.GRAY, 4.0)

	# Draw the loop backbone using baked points
	var points = loop_curve.get_baked_points()
	for i in range(points.size() - 1):
		draw_line(points[i], points[i+1], Color.WHITE, 4.0)

	# ==========================================
	# PLACE BASES USING sample_baked_with_rotation
	# ==========================================
	var current_distance = 0.0
	var total_length = loop_curve.get_baked_length()
	
	while current_distance <= total_length:
		# This returns a Transform2D, which contains BOTH position and rotation!
		var t = loop_curve.sample_baked_with_rotation(current_distance)
		var pos = t.origin
		var rot = t.get_rotation()
		
		# 1. Draw the base (Orange Circle)
		draw_circle(pos, 12.0, Color.ORANGE)
		
		# 2. Draw a directional arrow (Red Triangle) to prove rotation works
		var arrow_size = 10.0
		# Create a triangle pointing right (0 radians), then rotate it by the curve's angle
		var p1 = pos + Vector2(arrow_size, 0).rotated(rot)
		var p2 = pos + Vector2(-arrow_size, -arrow_size).rotated(rot)
		var p3 = pos + Vector2(-arrow_size, arrow_size).rotated(rot)
		
		var arrow_points = PackedVector2Array([p1, p2, p3])
		draw_colored_polygon(arrow_points, Color.RED)
		
		# Move to next base
		current_distance += base_spacing
