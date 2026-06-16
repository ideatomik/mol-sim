extends CharacterBody2D

@export var pol_lagging: CharacterBody2D
@export var backbone: Node2D

var current_target_gap_pos: Vector2 = Vector2.ZERO
var current_target_gap_index: int = -1
var is_sealing: bool = false
var is_detaching: bool = false
var move_tween: Tween
var seal_tween: Tween

const WIDTH: float = 50.0
const HEIGHT: float = 25.0
const RADIUS: float = 12.5

func _ready():
	add_to_group("ligases")
	add_to_group("highlightable") # Allows it to be dimmed
	add_to_group("ligase_highlight") # Allows it to be specifically highlighted
	
	_update_enzyme_color()	
	# Listen for theme changes
	if ThemeManager:
		ThemeManager.theme_changed.connect(_update_enzyme_color)

func _update_enzyme_color():
	var new_color = ThemeManager.enzyme_ligase_color

func _physics_process(delta):
	var rules = SimulationManager.current_rules
	
	# CASCADE EFFECT: If Ligase is disabled, detach immediately
	if rules and not rules.enable_ligase and not is_detaching:
		_trigger_detachment()
		return

	if is_sealing or is_detaching:
		return

	var unsealed_gaps = backbone.get_unsealed_gaps() if backbone else []
	# CASCADE EFFECT: If lagging polymerase is gone/disabled, consider the job done and detach
	var pol_is_done = (pol_lagging == null) or pol_lagging.is_detaching

	if unsealed_gaps.size() > 0:
		var target_data = unsealed_gaps[0]
		current_target_gap_pos = target_data["position"]
		current_target_gap_index = target_data["index"]
		
		if position.distance_to(current_target_gap_pos) < 5.0:
			_trigger_seal()
		else:
			_move_to(current_target_gap_pos, delta)
			
	elif pol_is_done:
		_trigger_detachment()
	else:
		if pol_lagging:
			var hover_pos = Vector2(pol_lagging.position.x - 80.0, pol_lagging.position.y)
			_move_to(hover_pos, delta)

func _move_to(target: Vector2, delta: float):
	if move_tween:
		move_tween.kill()
	move_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	move_tween.tween_property(self, "position", target, 0.4)

func _trigger_seal():
	is_sealing = true
	
	seal_tween = create_tween().set_parallel(true)
	seal_tween.tween_property(self, "modulate", Color.WHITE, 0.1)
	seal_tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	seal_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.3).set_delay(0.1)
	seal_tween.tween_property(self, "scale", Vector2.ONE, 0.2).set_delay(0.1)
	
	seal_tween.finished.connect(func():
		if backbone and current_target_gap_index != -1:
			backbone.seal_gap(current_target_gap_index)
		is_sealing = false
		modulate = Color.WHITE
	)

func _trigger_detachment():
	is_detaching = true
	
	var detach_pos = Vector2(position.x, position.y + 50.0)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position", detach_pos, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 1.2)

func _draw():
	draw_rect(Rect2(-WIDTH/2, -HEIGHT/2, WIDTH, HEIGHT), ThemeManager.enzyme_ligase_color)
	draw_circle(Vector2(-WIDTH/2, 0), RADIUS, ThemeManager.enzyme_ligase_color)
	draw_circle(Vector2(WIDTH/2, 0), RADIUS, ThemeManager.enzyme_ligase_color)
