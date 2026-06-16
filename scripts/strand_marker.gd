extends RigidBody2D

@export var marker_text: String = "5'"
@export var marker_color: Color = Color.WHITE

func _ready():
	var label = get_node_or_null("Label")
	if label:
		label.text = marker_text
		label.label_settings.font_color = marker_color

func _draw():
	draw_circle(Vector2.ZERO, 15, Color(0.3, 0.3, 0.3))
	draw_arc(Vector2.ZERO, 15, 0, TAU, 32, marker_color, 2.0, true)
