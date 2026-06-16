extends Node2D

@export var boid_scene: PackedScene
@export var nitrogen_base_scene: PackedScene
@export var dna_strand_scene: PackedScene
@export var helicase_scene: PackedScene
@export var polymerase_scene: PackedScene
@export var ligase_scene: PackedScene
@export var hydrogen_bonds_scene: PackedScene
@export var new_strand_backbone_scene: PackedScene

@onready var camera = $Camera2D

var screen_width: float = 1280.0
var screen_height: float = 720.0
var screen_center: Vector2 = Vector2(640, 360)

const BASE_SPACING: float = 35.0
const STRAND_OFFSET_Y: float = 80.0
var strand_y_top: float = 320.0
var strand_y_bottom: float = 400.0
var start_x: float = 280.0

const WALL_MARGIN: float = 50.0

var shake_strength: float = 0.0
var shake_decay: float = 10.0
var is_sim_running: bool = false

const DNA_SEQUENCE = ["A", "T", "G", "C", "G", "A", "T", "A", "C", "G", "C", "T", "A", "G", "C", "T", "G", "A", "T", "T", "T", "G", "G", "C"]

func _ready():
	get_window().mode = Window.MODE_FULLSCREEN
	
	screen_width = get_viewport_rect().size.x
	screen_height = get_viewport_rect().size.y
	screen_center = Vector2(screen_width / 2, screen_height / 2)
	
	_update_layout_positions()
	
	if camera:
		camera.make_current()
		camera.position = screen_center
		
	_build_walls()
		
	if not SimulationManager.current_rules:
		SimulationManager.set_rules(SimulationRules.new())
		
	_build_simulation()
	
	#Start in a paused state
	is_sim_running = false
	var rules = SimulationManager.current_rules
	if rules:
		rules.is_running = false

func _update_layout_positions():
	var dna_width = DNA_SEQUENCE.size() * BASE_SPACING
	start_x = (screen_width - dna_width) / 2
	strand_y_top = (screen_height / 2) - (STRAND_OFFSET_Y / 2)
	strand_y_bottom = (screen_height / 2) + (STRAND_OFFSET_Y / 2)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		_toggle_fullscreen()

func _toggle_fullscreen():
	var window = get_window()
	if window.mode == Window.MODE_WINDOWED:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
	
	await get_tree().process_frame
	_on_window_resized()

func _on_window_resized():
	screen_width = get_viewport_rect().size.x
	screen_height = get_viewport_rect().size.y
	screen_center = Vector2(screen_width / 2, screen_height / 2)
	
	_update_layout_positions()
	
	if camera:
		camera.position = screen_center
	
	_build_walls()
	_build_simulation()

func _build_walls():
	var old_walls = get_node_or_null("Walls")
	if old_walls:
		old_walls.queue_free()
		
	var walls_node = Node2D.new()
	walls_node.name = "Walls"
	add_child(walls_node)
	
	_create_wall(walls_node, Vector2(screen_width / 2, WALL_MARGIN / 2), Vector2(screen_width + (WALL_MARGIN * 2), WALL_MARGIN))
	_create_wall(walls_node, Vector2(screen_width / 2, screen_height - (WALL_MARGIN / 2)), Vector2(screen_width + (WALL_MARGIN * 2), WALL_MARGIN))
	_create_wall(walls_node, Vector2(WALL_MARGIN / 2, screen_height / 2), Vector2(WALL_MARGIN, screen_height + (WALL_MARGIN * 2)))
	_create_wall(walls_node, Vector2(screen_width - (WALL_MARGIN / 2), screen_height / 2), Vector2(WALL_MARGIN, screen_height + (WALL_MARGIN * 2)))

func _create_wall(parent: Node2D, pos: Vector2, size: Vector2):
	var wall = StaticBody2D.new()
	wall.position = pos
	parent.add_child(wall)
	
	var shape_node = CollisionShape2D.new()
	var rect_shape = RectangleShape2D.new()
	rect_shape.size = size
	shape_node.shape = rect_shape
	wall.add_child(shape_node)

func _process(delta):
	if shake_strength > 0.0:
		camera.offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))
		shake_strength = move_toward(shake_strength, 0.0, shake_decay * delta)
	else:
		camera.offset = Vector2.ZERO

func trigger_shake(strength: float, decay: float = 10.0):
	shake_strength = max(shake_strength, strength)
	shake_decay = decay

func _build_simulation():
	print("MAIN: _build_simulation() called!")
	
	# FOOLPROOF CLEANUP: Delete everything tagged as a simulation object
	print("MAIN: Clearing old simulation objects...")
	var objects_to_clear = get_tree().get_nodes_in_group("sim_objects")
	for obj in objects_to_clear:
		print("  -> Freeing: ", obj.name)
		obj.queue_free()
	
	var rules = SimulationManager.current_rules
	
	if rules.mode == "DNA Repl":
		_spawn_dna(rules)
	else:
		_spawn_boids(rules)

func _spawn_boids(rules):
	for i in range(100):
		var boid = boid_scene.instantiate()
		boid.position = Vector2(randf_range(WALL_MARGIN + 10, screen_width - WALL_MARGIN - 10), randf_range(WALL_MARGIN + 10, screen_height - WALL_MARGIN - 10))
		add_child(boid)

func _spawn_dna(rules):
	print("--- STARTING _spawn_dna ---")
	
	# 1 & 2. DNA Strands
	var top_strand: DnaStrand = dna_strand_scene.instantiate()
	top_strand.add_to_group("sim_objects") # NEW
	top_strand.is_top_strand = true
	top_strand.build_sequence(DNA_SEQUENCE, nitrogen_base_scene, BASE_SPACING, start_x, strand_y_top)
	
	var bottom_strand: DnaStrand = dna_strand_scene.instantiate()
	bottom_strand.add_to_group("sim_objects") # NEW
	bottom_strand.is_top_strand = false
	var bottom_seq = []
	for base in DNA_SEQUENCE:
		bottom_seq.append(_get_complement(base))
	bottom_strand.build_sequence(bottom_seq, nitrogen_base_scene, BASE_SPACING, start_x, strand_y_bottom)

	var h_bonds = hydrogen_bonds_scene.instantiate()
	h_bonds.add_to_group("sim_objects") # NEW
	h_bonds.top_strand = top_strand
	h_bonds.bottom_strand = bottom_strand

	add_child(h_bonds)
	add_child(top_strand)
	add_child(bottom_strand)

	for i in range(top_strand.bases.size()):
		var b1 = top_strand.bases[i]
		var b2 = bottom_strand.bases[i]
		b1.partner_base = b2
		b2.partner_base = b1
		var pair_type = "pair_AT" if (b1.base_type == "A" or b1.base_type == "T") else "pair_CG"
		b1.add_to_group(pair_type)
		b2.add_to_group(pair_type)

	var dna_end_x = start_x + (DNA_SEQUENCE.size() * BASE_SPACING) + 100.0
	var pol_lagging_ref = null
	var new_backbone_ref = null

	# 3. CONDITIONAL: Helicase
	if rules.enable_helicase:
		print("  -> SPAWNING HELICASE")
		var helicase = helicase_scene.instantiate()
		helicase.add_to_group("sim_objects") # NEW
		helicase.position = Vector2(start_x - 20, (strand_y_top + strand_y_bottom) / 2)
		helicase.end_x = dna_end_x
		helicase.top_strand = top_strand
		helicase.bottom_strand = bottom_strand
		add_child(helicase)
	else:
		print("  -> SKIPPING HELICASE (Disabled in rules)")
	
	# 4. CONDITIONAL: Leading Strand Polymerase
	if rules.enable_leading_polymerase:
		print("  -> SPAWNING LEADING POLYMERASE")
		var pol_leading = polymerase_scene.instantiate()
		pol_leading.add_to_group("sim_objects") # NEW
		pol_leading.is_leading = true
		pol_leading.nitrogen_base_scene = nitrogen_base_scene
		pol_leading.position = Vector2(start_x - BASE_SPACING, strand_y_top - 120.0)
		pol_leading.template_strand = top_strand
		add_child(pol_leading)
	
	# 5. CONDITIONAL: Lagging Strand Polymerase
	if rules.enable_lagging_polymerase:
		print("  -> SPAWNING LAGGING POLYMERASE")
		pol_lagging_ref = polymerase_scene.instantiate()
		pol_lagging_ref.add_to_group("sim_objects") # NEW
		pol_lagging_ref.is_leading = false
		pol_lagging_ref.nitrogen_base_scene = nitrogen_base_scene
		pol_lagging_ref.position = Vector2(start_x - BASE_SPACING, strand_y_bottom + 120.0)
		pol_lagging_ref.template_strand = bottom_strand
		add_child(pol_lagging_ref)

	# 6. CONDITIONAL: New strand backbone renderer
	if rules.enable_leading_polymerase or rules.enable_lagging_polymerase:
		print("  -> SPAWNING NEW BACKBONE RENDERER")
		new_backbone_ref = new_strand_backbone_scene.instantiate()
		new_backbone_ref.add_to_group("sim_objects") # NEW
		add_child(new_backbone_ref)

	# 7. CONDITIONAL: Ligase enzyme
	if rules.enable_ligase and ligase_scene:
		print("  -> SPAWNING LIGASE")
		var ligase = ligase_scene.instantiate()
		ligase.add_to_group("sim_objects") # NEW
		ligase.position = Vector2(start_x - BASE_SPACING - 80.0, strand_y_bottom + 120.0)
		ligase.pol_lagging = pol_lagging_ref
		ligase.backbone = new_backbone_ref
		add_child(ligase)

	# 8. CONDITIONAL: Free nucleotides
	if rules.spawn_free_bases:
		print("  -> SPAWNING FREE BASES: ", rules.free_nucleotide_count)
		for i in range(rules.free_nucleotide_count):
			var free_base: NitrogenBase = nitrogen_base_scene.instantiate()
			free_base.add_to_group("sim_objects") # NEW
			free_base.base_type = ["A", "T", "C", "G"][randi() % 4]
			free_base.state = NitrogenBase.State.FREE
			free_base.position = Vector2(
				randf_range(WALL_MARGIN + 20, screen_width - WALL_MARGIN - 20), 
				randf_range(WALL_MARGIN + 20, screen_height - WALL_MARGIN - 20)
			)
			add_child(free_base)
	else:
		print("  -> SKIPPING FREE BASES (Disabled in rules)")
		
	print("--- FINISHED _spawn_dna ---")

func _get_complement(base: String) -> String:
	match base:
		"A": return "T"
		"T": return "A"
		"C": return "G"
		"G": return "C"
	return "A"

# ==========================================
# SIMULATION STATE CONTROL
# ==========================================

func is_simulation_running() -> bool:
	return is_sim_running

func start_simulation():
	is_sim_running = true
	var rules = SimulationManager.current_rules
	if rules:
		rules.is_running = true

func pause_simulation():
	is_sim_running = false
	var rules = SimulationManager.current_rules
	if rules:
		rules.is_running = false

func reset_simulation():
	# 1. Stop the simulation
	is_sim_running = false
	var rules = SimulationManager.current_rules
	if rules:
		rules.is_running = false
		
	# 2. Clear any active highlights
	HighlightManager.clear_highlight()
	
	# 3. Rebuild the scene based on current rules
	_build_simulation()
