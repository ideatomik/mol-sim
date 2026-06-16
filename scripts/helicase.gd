extends CharacterBody2D

const BASE_SPEED: float = 35.0

var top_strand: DnaStrand
var bottom_strand: DnaStrand
var end_x: float = 0.0
var is_detaching: bool = false

const WIDTH: float = 90.0
const HEIGHT: float = 30.0
const RADIUS: float = 15.0
const FILL_COLOR: Color = Color(0.6, 0.2, 0.8)

func _ready():
	add_to_group("helicases")
	add_to_group("highlightable") # Allows it to be dimmed
	add_to_group("helicase_highlight") # Allows it to be specifically highlighted

func _physics_process(delta):
	var rules = SimulationManager.current_rules
	if not rules or rules.mode != "DNA Repl":
		return
		
	# CASCADE EFFECT: If Helicase is disabled via UI, detach immediately
	if not rules.enable_helicase and not is_detaching:
		_trigger_detachment()
		return
		
	if is_detaching:
		return
		
	if rules.is_running and position.x < end_x:
		var current_temp_speed = rules.get_speed_from_temperature() if rules else 150.0
		var current_speed = BASE_SPEED * (current_temp_speed / 150.0)
		position.x += current_speed * delta
		
		if position.x > end_x:
			position.x = end_x
	
	if top_strand:
		top_strand.update_peel(position.x)
	if bottom_strand:
		bottom_strand.update_peel(position.x)
		
	if position.x >= end_x:
		_trigger_detachment()

func _trigger_detachment():
	is_detaching = true
	var detach_pos = Vector2(position.x, position.y - 50.0)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position", detach_pos, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 1.2)

func _draw():
	var w = WIDTH
	var h = HEIGHT
	var r = RADIUS
	
	draw_rect(Rect2(-w/2 + r, -h/2, w - 2*r, h), FILL_COLOR)
	draw_circle(Vector2(-w/2 + r, 0), r, FILL_COLOR)
	draw_circle(Vector2(w/2 - r, 0), r, FILL_COLOR)
	
	draw_arc(Vector2(-w/2 + r, 0), r, PI/2, 3*PI/2, 32, Color.WHITE, 2.0, true)
	draw_arc(Vector2(w/2 - r, 0), r, -PI/2, PI/2, 32, Color.WHITE, 2.0, true)
	draw_line(Vector2(-w/2 + r, -h/2), Vector2(w/2 - r, -h/2), Color.WHITE, 2.0, true)
	draw_line(Vector2(-w/2 + r, h/2), Vector2(w/2 - r, h/2), Color.WHITE, 2.0, true)
