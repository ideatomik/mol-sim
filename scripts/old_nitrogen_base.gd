extends RigidBody2D
class_name NitrogenBase

enum State { TEMPLATE, FREE, BOUND }

@export var base_type: String = "A"
@export var state: State = State.FREE

var is_unzipped: bool = false
var is_bound: bool = false
var is_target: bool = false
var is_on_loop: bool = false # True while positioned along the trombone loop curve (see dna_strand.gd update_peel)
var loop_normal_angle: float = 0.0 # Outward-normal direction while is_on_loop, used by new_strand_backbone.gd to offset the paired new-strand base
var was_on_loop: bool = false # Previous-frame is_on_loop, used to detect the loop->finished "push" transition
var push_tween: Tween = null # Active "push" release tween, if this base just transitioned from loop to finished
var original_pos: Vector2
var wobble_speed: float = randf_range(2.0, 4.0)
var wobble_phase: float = randf() * TAU

var partner_base: NitrogenBase = null
# REDIRECT MECHANIC: when a polymerase needs this base type and none are
# organically nearby, it can redirect an existing free base toward itself
# rather than spawning a new one (cheaper, and avoids unbounded node growth
# on weak hardware). This biases the Brownian kick direction in
# _integrate_forces toward redirect_target_pos while active, rather than
# overriding velocity outright -- so it still looks like normal jittery
# motion, just nudged toward a destination.
var is_redirecting: bool = false
var redirect_target_pos: Vector2 = Vector2.ZERO

const BROWNIAN_STRENGTH: float = 1000.0

const BASE_COLORS = {
	"A": Color.WHITE, 
	"T": Color.WHITE, 
	"C": Color.WHITE, 
	"G": Color.WHITE
}

const BASE_FILL = {
	"A": Color(0.8, 0.2, 0.2), 
	"T": Color(0.2, 0.2, 0.8), 
	"C": Color(0.85, 0.6, 0.1),
	"G": Color(0.2, 0.8, 0.2)
}

func _ready():
	original_pos = position
	is_target = false
	scale = Vector2.ONE
	_apply_appearance()
	add_to_group("nitrogen_bases")
	
	# Highlight system registration
	add_to_group("highlightable")
	add_to_group("all_bases")
	add_to_group("base_" + base_type)
	
	if state == State.FREE:
		add_to_group("free_nucleotides")
		var rules = SimulationManager.current_rules
		var current_speed = rules.get_speed_from_temperature() if rules else 150.0
		linear_velocity = Vector2.RIGHT.rotated(randf() * TAU) * current_speed

	# Listen for theme changes to update marker colors instantly
	if ThemeManager:
		ThemeManager.theme_changed.connect(_on_theme_changed)

func _on_theme_changed():
	# Only markers need to update their colors when the theme changes
	if base_type == "5'" or base_type == "3'":
		_apply_appearance()
		queue_redraw()

func _draw():
	# Default base colors
	var fill = BASE_FILL.get(base_type, Color.GRAY)
	
	# FIX: Override color if this is a 5' or 3' marker
	if base_type == "5'" or base_type == "3'":
		fill = ThemeManager.marker_circle_color if ThemeManager else Color.DARK_GRAY
		
	draw_circle(Vector2.ZERO, 15, fill)

func _apply_appearance():
	var label = get_node_or_null("Label")
	if label:
		label.text = base_type
		if not label.label_settings:
			label.label_settings = LabelSettings.new()
			
		# FIX: Use ThemeManager colors for markers, keep white for bases
		if base_type == "5'" or base_type == "3'":
			label.label_settings.font_color = ThemeManager.marker_font_color if ThemeManager else Color.WHITE
		else:
			label.label_settings.font_color = Color.WHITE

func make_template():
	set("mode", 3)
	collision_layer = 0
	collision_mask = 0

func make_bound():
	set("mode", 3)
	collision_layer = 0
	collision_mask = 0

# ==========================================
# MAIN PROCESS LOOP
# Handles wobble, target pulsing, and dynamic visibility
# ==========================================
func _process(delta):
	# 1. Handle wobble for template bases, and for BOUND bases EXCEPT
	# bottom/lagging-strand ones.
	# POSITION-OWNERSHIP FIX: bound lagging-strand bases have their position
	# actively driven every frame by new_strand_backbone.gd's
	# _update_active_fragment_positions() (follows the template partner along
	# the trombone loop curve). Both scripts writing to `position` in the
	# same frame caused this wobble write to silently clobber the
	# curve-follow write, depending on Godot's node processing order -- the
	# new strand looked flat even though the loop-follow logic was computing
	# correct curve positions every frame. Bound leading-strand bases aren't
	# driven by anything else, so they keep their wobble as before.
	var is_lagging_bound = false
	if state == State.BOUND and partner_base != null:
		var parent_strand = partner_base.get_parent()
		if parent_strand is DnaStrand and not parent_strand.is_top_strand:
			is_lagging_bound = true

	if (state == State.TEMPLATE and not is_unzipped) or (state == State.BOUND and not is_lagging_bound):
		var t = Time.get_ticks_msec() / 1000.0
		var wobble_x = sin(t * wobble_speed + wobble_phase) * 1.5
		var wobble_y = cos(t * wobble_speed * 0.7 + wobble_phase) * 1.5
		position = original_pos + Vector2(wobble_x, wobble_y)
			
	# 2. Handle target pulsing (when enzyme is about to bind)
	if is_target:
		var t = Time.get_ticks_msec() / 1000.0
		var pulse_factor = (sin(t * 8.0) + 1.0) * 0.5 
		var scale_multiplier = 1.0 + (pulse_factor * 0.1)
		scale = Vector2(scale_multiplier, scale_multiplier)
	else:
		scale = Vector2.ONE

	# 3. Dynamic visibility for FREE bases
	if state == State.FREE:
		var rules = SimulationManager.current_rules
		var target_alpha = HighlightManager.HIGHLIGHT_ALPHA # Default: fully visible
		
		if rules:
			var is_near_enzyme = false
			
			# Check distance to active polymerases
			var polymerases = get_tree().get_nodes_in_group("polymerases")
			for pol in polymerases:
				if not pol.is_detaching and position.distance_to(pol.position) < rules.binding_distance:
					is_near_enzyme = true
					break
			
			# Check distance to active primases (if they exist)
			if not is_near_enzyme:
				var primases = get_tree().get_nodes_in_group("primases")
				for prim in primases:
					if not prim.is_detaching and position.distance_to(prim.position) < rules.binding_distance:
						is_near_enzyme = true
						break
			
			# Determine target alpha based on TWO factors:
			# 1. Is "Show All Bases" enabled?
			# 2. Is the base near an enzyme?
			if not rules.show_all_free_bases and not is_near_enzyme:
				# "Show All Bases" is OFF and base is NOT near enzyme → fade to dimmed
				target_alpha = HighlightManager.DIMMED_ALPHA
			else:
				# Either "Show All Bases" is ON OR base is near enzyme → stay bright
				target_alpha = HighlightManager.HIGHLIGHT_ALPHA
		
		# Fast, smooth alpha tweening
		modulate.a = lerp(modulate.a, target_alpha, delta * 10.0)
		
		# Force labels to always stay horizontal
		rotation = 0

func _integrate_forces(physics_state):
	if self.state != State.FREE: 
		return
	var rules = SimulationManager.current_rules
	if not rules or rules.mode != "DNA Repl": 
		return
	if not rules.is_running:
		physics_state.linear_velocity = Vector2.ZERO
		physics_state.angular_velocity = 0.0
		return

	var brownian_kick = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * BROWNIAN_STRENGTH * physics_state.step
	
	# REDIRECT MECHANIC: bias the kick toward the redirect target instead of
	# pure random direction, so this base drifts toward the polymerase that
	# requested it -- still jittery (random kick still applied, just blended
	# with a directional pull), not a hard velocity override.
	if is_redirecting:
		var to_target = (redirect_target_pos - global_position)
		if to_target.length() > 4.0:
			var pull = to_target.normalized() * BROWNIAN_STRENGTH * physics_state.step
			# Raised lerp weight from 0.7 to 0.85 for a more direct approach
			# now that we're relying on this path more (faster throttle).
			brownian_kick = brownian_kick.lerp(pull, 0.85)
		else:
			is_redirecting = false
	
	physics_state.linear_velocity += brownian_kick
	
	var max_speed = rules.get_speed_from_temperature() if rules else 150.0
	if physics_state.linear_velocity.length() > max_speed:
		physics_state.linear_velocity = physics_state.linear_velocity.normalized() * max_speed

func _physics_process(delta):
	if self.state != State.FREE: 
		return
	var rules = SimulationManager.current_rules
	if not rules or rules.mode != "DNA Repl": 
		return

	var polymerases = get_tree().get_nodes_in_group("polymerases")
	for pol in polymerases:
		if pol.is_waiting_for_binding and position.distance_to(pol.position) < rules.binding_distance:
			pol.request_binding(self)
			return

func start_redirect(target_pos: Vector2):
	# REDIRECT MECHANIC: called by a polymerase that needs this base type and
	# found none nearby organically. This base will drift (biased Brownian
	# motion, see _integrate_forces) toward target_pos instead of pure
	# random wander, until close enough or it gets consumed/redirected
	# elsewhere.
	is_redirecting = true
	redirect_target_pos = target_pos

func reject():
	var rules = SimulationManager.current_rules
	var base_speed = rules.get_speed_from_temperature() if rules else 150.0
	var bounce_speed = base_speed * 2.0
	
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.RED, 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)
	
	linear_velocity = linear_velocity.normalized() * bounce_speed

func finalize_bind(final_pos: Vector2):
	var rules = SimulationManager.current_rules
	self.state = State.BOUND
	make_bound()
	is_target = false
	scale = Vector2.ONE
	remove_from_group("free_nucleotides")
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	freeze = true 
	
	var tween = create_tween()
	tween.tween_property(self, "rotation", 0.0, 0.15).set_ease(Tween.EASE_OUT)
	original_pos = final_pos 
	tween.parallel().tween_property(self, "modulate", Color(0.8, 1.0, 0.4), 0.15)
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)
	
	queue_redraw()

func fade_and_free():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.finished.connect(queue_free)
