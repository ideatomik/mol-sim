extends Node

# ==========================================
# trailer.gd
# Scripted camera director for teaser/trailer capture.
#
# PLACEMENT: add as a child node anywhere inside simulation.tscn's tree
# (e.g. directly under "root", as a sibling of ZoomManager). It resolves
# %ZoomManager the same way replication_manager.gd / zoom_manager.gd itself
# do (unique-name lookup, works from anywhere in the owning scene), and
# resolves the simulation root via `simulation_path` (defaults to "..").
#
# DESIGN: rides the existing ZoomManager target system (register_target /
# select_target / is_target_visible) rather than hand-rolling camera framing
# — those frame-provider Callables already recompute live against the
# current viewport size each call, so running the project at 1080x1920 for
# a capture session reframes every shot correctly with zero extra work here.
#
# Everything below is @export-tunable from the Inspector — no code edits
# needed between takes. With autostart on, just hit Play on this scene.
# ==========================================

@export_group("Window")
@export var force_vertical_window: bool = true
@export var window_size: Vector2i = Vector2i(1080, 1920)

@export_group("Sequence")
@export var simulation_path: NodePath = NodePath("..")
@export var sequence_length: int = 34
@export var fixed_sequence: String = ""  # leave empty to randomize a fresh one each take

@export_group("Playback Speed")
@export var helicase_speed_multiplier: float = 1.0  # forwarded to helicase_mgr.set_speed()

@export_group("Shot List — Enzyme Follow")
@export var enzyme_targets: Array[String] = ["helicase", "leading_polymerase", "lagging_polymerase"]
@export var level2_hold: float = 1.5       # regional-context hold, per target
@export var push_to_level3: bool = true    # brief tight close-in after level2_hold
@export var level3_hold: float = 1.0
@export var visibility_timeout: float = 6.0  # give up waiting on a target after this long

@export_group("Shot List — Wide + Scrub")
@export var wide_shot_hold: float = 1.5
@export var scrub_pass_count: int = 2
@export var scrub_pass_duration: float = 2.0
@export var scrub_range: Vector2 = Vector2(0.0, 1.0)

@export_group("Control")
@export var autostart: bool = true
@export var trigger_key: Key = KEY_P  # press this key in-game to start the sequence on demand
@export var loop: bool = false

var _sim: Node = null
var _zoom_mgr: Node = null
var _running: bool = false
var _sim_ready: bool = false  # true once simulation_initialized has fired at least once

func _ready() -> void:
	if force_vertical_window:
		get_window().mode = Window.MODE_WINDOWED  # Maximized/Fullscreen would otherwise override .size below
		get_window().size = window_size

	_sim = get_node_or_null(simulation_path)
	if _sim == null or not ("initialize_simulation" in _sim):
		push_error("trailer.gd: simulation_path (%s) doesn't point at simulation.gd — check node placement." % simulation_path)
		return

	_zoom_mgr = get_node_or_null("%ZoomManager")
	if _zoom_mgr == null:
		push_error("trailer.gd: %ZoomManager not found in this scene.")
		return

	# One-shot: simulation_initialized fires at the end of the FIRST
	# initialize_simulation() call (in simulation.gd's own _ready()), which
	# runs after this node's _ready() since children ready before parents —
	# guarantees register_target() has already happened before _sim_ready
	# flips true, whether the sequence starts via autostart or the trigger key.
	if not _sim.simulation_initialized.is_connected(_on_first_sim_ready):
		_sim.simulation_initialized.connect(_on_first_sim_ready, CONNECT_ONE_SHOT)

func _on_first_sim_ready(_total_bases: int) -> void:
	_sim_ready = true
	if autostart:
		call_deferred("run")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == trigger_key:
		if _sim_ready and not _running:
			run()

func run() -> void:
	if _running:
		return
	_running = true
	_play_sequence()

func _play_sequence() -> void:
	while true:
		await _run_one_take()
		if not loop:
			break
	_running = false

func _run_one_take() -> void:
	# 1. Load a fresh sequence for this take.
	if fixed_sequence != "":
		_sim.initialize_simulation(fixed_sequence)
	else:
		_sim.dna_sequence.randomize_sequence(sequence_length)
		_sim.initialize_simulation(_sim.dna_sequence._to_string())

	_zoom_mgr.reset_zoom_instant()

	if _sim.helicase_mgr != null:
		_sim.helicase_mgr.set_speed(helicase_speed_multiplier)

	# 2. Start playback — toggle_play() handles the intro fade/slide and
	# kicks off SWEEPING once the intro tween completes.
	_sim.toggle_play()

	# 3. Follow each enzyme in turn.
	for target_id in enzyme_targets:
		await _hold_on_target(target_id)

	# 4. Zoom out to the wide shot.
	_zoom_mgr.reset_zoom()
	await get_tree().create_timer(wide_shot_hold).timeout

	# 5. Scrub back and forth across the finished strand.
	for i in range(scrub_pass_count):
		var from_p: float = scrub_range.x if i % 2 == 0 else scrub_range.y
		var to_p: float = scrub_range.y if i % 2 == 0 else scrub_range.x
		await _scrub_between(from_p, to_p, scrub_pass_duration)

func _hold_on_target(target_id: String) -> void:
	var waited := 0.0
	while not _zoom_mgr.is_target_visible(target_id) and waited < visibility_timeout:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if not _zoom_mgr.is_target_visible(target_id):
		return  # never showed up in time — skip rather than hang the take forever

	_zoom_mgr.select_target(target_id)  # jumps to the target's entry level (2)
	await get_tree().create_timer(level2_hold).timeout

	if push_to_level3:
		_zoom_mgr.set_zoom_level(3)
		await get_tree().create_timer(level3_hold).timeout

func _scrub_between(from_p: float, to_p: float, duration: float) -> void:
	# scrub_to() itself is instant/discrete — tween a progress float across
	# it via tween_method for a smooth scrub-back-and-forth read.
	if not _sim.manual_override:
		_sim.toggle_play()  # pause live playback so scrub takes full control
	var tw := create_tween()
	tw.tween_method(_sim.scrub_to, from_p, to_p, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished