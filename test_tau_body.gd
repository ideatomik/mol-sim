extends Node2D

@export var helicase_dummy: Node2D
@export var lagging_poly_dummy: Node2D
@export var tau_body: Node2D

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	if not helicase_dummy or not lagging_poly_dummy or not tau_body:
		return

	var h_pos = helicase_dummy.global_position
	var l_pos = lagging_poly_dummy.global_position
	var midpoint = (h_pos + l_pos) * 0.5

	tau_body.global_position = midpoint

	if tau_body.has_method("set_connections"):
		tau_body.set_connections(h_pos, l_pos)
