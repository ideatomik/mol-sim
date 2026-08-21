extends Node2D

@export_group("Tau Body Visuals")
@export var body_color: Color = Color(0.8, 0.6, 0.2, 0.9)
@export var connector_color: Color = Color(0.5, 0.5, 0.5, 0.7)
@export var body_size: float = 24.0
@export var connector_width: float = 4.0
@export var connector_count: int = 3
@export var pre_loop_min: float = 10.0
@export var loop_tightness: float = 0.5

var helicase_pos: Vector2 = Vector2.ZERO
var lagging_pos: Vector2 = Vector2.ZERO

func _ready():
	pass

func _process(_delta):
	queue_redraw()

func set_connections(h_pos: Vector2, l_pos: Vector2):
	helicase_pos = h_pos
	lagging_pos = l_pos
	queue_redraw()

func _draw():
	var local_h = to_local(helicase_pos)
	var local_l = to_local(lagging_pos)

	for i in range(connector_count):
		var offset = Vector2(randf() - 0.5, randf() - 0.5) * 10.0
		var start_point = local_h + offset
		var end_point = local_l + offset

		draw_line(start_point, end_point, connector_color, connector_width, true)

	var midpoint = (local_h + local_l) / 2.0
	draw_circle(midpoint, body_size / 2.0, body_color)

	draw_circle(local_h, 6.0, Color.GREEN, true)
	draw_circle(local_l, 6.0, Color.RED, true)
