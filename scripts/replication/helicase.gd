extends Node

# ==========================================
# helicase.gd
# Discrete slot-by-slot helicase motion.
# Owns the replication phase state machine and stepping logic.
# helicase_x is a DERIVED visual value — computed by simulation.gd from
# current_slot_index and step_t, not owned here.
# ==========================================

# ---------- SIGNALS ----------
signal slot_reached(index: int)       # Fired once per step when helicase arrives at a new slot
signal phase_changed(new_phase: int)  # Fired on every phase transition (passes Phase enum value)
signal sprite_should_fade             # Fired once, at SWEEPING -> FINISHING_LAST_PULSE — the
                                       # helicase's own unwinding job is done and its sprite
                                       # should fade, even though the state machine keeps
                                       # quietly running to finish escorting the leading
                                       # polymerase's derived position to the true end.

# ---------- SPEED ----------
# step_duration is seconds per slot at 1x. Speed multiplier divides it.
@export var base_step_duration: float = 0.5  # Seconds per slot at 1x — tweak in Inspector
const SPEED_OPTIONS: Array = [1, 2, 4, 8]

var speed_multiplier: float = 1.0
var step_duration: float = 0.5

# ---------- DISCRETE MOTION ----------
var current_slot_index: int = 0    # Which slot the helicase is currently AT
var step_t: float = 0.0            # 0.0→1.0 progress through the current inter-slot step
var is_running: bool = false        # True when actively stepping (not paused)

# ---------- PHASE ----------
# Mirrors the Phase enum in simulation.gd. Passed as int via signal to avoid
# cross-script enum dependency.
enum Phase { INTRO, SWEEPING, FINISHING_LAST_PULSE, SETTLING, DONE }
var phase: int = Phase.INTRO

# ---------- SETTLING ----------
var settling_t: float = 0.0
var settling_duration: float = 0.5   # Should match simulation.gd export

# ---------- FINISHING ----------
# Extra steps taken after last_slot_index, one per leading slot still ahead of factory_x.
# Set by simulation.gd via start_finishing(count) when FINISHING_LAST_PULSE begins.
# Runs at the same flat step_duration as normal SWEEPING — no acceleration. The helicase
# sprite itself has already faded by this point (see sprite_should_fade); these steps only
# exist to keep escorting the leading polymerase's helicase-derived position to the true end.
var extra_steps_total: int = 0
var extra_steps_done: int = 0

# ---------- CONTEXT (set by simulation.gd after _ready) ----------
var slot_count: int = 0             # Total number of slots — set by simulation.gd
var last_slot_index: int = 0        # slot_count - 1

# ==========================================
# LIFECYCLE
# ==========================================

func initialize(p_slot_count: int, p_settling_duration: float) -> void:
	slot_count = p_slot_count
	last_slot_index = slot_count - 1
	settling_duration = p_settling_duration
	step_duration = base_step_duration  # Sync from Inspector export
	current_slot_index = 0
	step_t = 0.0
	settling_t = 0.0
	extra_steps_total = 0
	extra_steps_done = 0
	phase = Phase.INTRO
	is_running = false

func _process(delta: float) -> void:
	if not is_running:
		return

	match phase:
		Phase.INTRO:
			pass  # Controlled externally via start_intro() / finish_intro()

		Phase.SWEEPING:
			step_t += delta / step_duration
			if step_t >= 1.0:
				step_t -= 1.0
				current_slot_index += 1
				emit_signal("slot_reached", current_slot_index)
				if current_slot_index >= last_slot_index:
					_set_phase(Phase.FINISHING_LAST_PULSE)

		Phase.FINISHING_LAST_PULSE:
			# Step past the last slot, emitting slot_reached so leading bases
			# spawn naturally via the position-based synthesis path.
			# Flat pace (same step_duration as SWEEPING) — the helicase sprite
			# already faded on entering this phase; this just finishes escorting
			# the leading polymerase's derived position. Self-transitions to
			# SETTLING when done.
			step_t += delta / step_duration
			if step_t >= 1.0:
				step_t -= 1.0
				current_slot_index += 1
				emit_signal("slot_reached", current_slot_index)
				extra_steps_done += 1
				if extra_steps_done >= extra_steps_total:
					settling_t = 0.0
					_set_phase(Phase.SETTLING)

		Phase.SETTLING:
			settling_t += delta
			var t = clamp(settling_t / settling_duration, 0.0, 1.0)
			if t >= 1.0:
				_set_phase(Phase.DONE)

		Phase.DONE:
			is_running = false

# ==========================================
# PUBLIC API
# ==========================================

func start_intro() -> void:
	phase = Phase.INTRO
	is_running = false  # Intro is driven by tween in simulation.gd
	extra_steps_total = 0
	extra_steps_done = 0
	step_duration = base_step_duration / speed_multiplier

func finish_intro() -> void:
	# Called by simulation.gd when the intro tween completes
	_set_phase(Phase.SWEEPING)
	is_running = true

func pause() -> void:
	is_running = false

func resume() -> void:
	if phase != Phase.DONE:
		is_running = true

func notify_settling_ready() -> void:
	# Called by simulation.gd when all slots have settled to new_bottom_template_y
	if phase == Phase.FINISHING_LAST_PULSE:
		settling_t = 0.0
		_set_phase(Phase.SETTLING)

func start_finishing(remaining_leading_slots: int) -> void:
	# Called by simulation.gd when FINISHING_LAST_PULSE begins.
	# Takes one extra step per leading slot still ahead of factory_x.
	# Minimum 1 so helicase always exits visually.
	extra_steps_total = max(1, remaining_leading_slots)
	extra_steps_done = 0
	step_duration = base_step_duration / speed_multiplier

func scrub_to_slot(index: int) -> void:
	current_slot_index = clamp(index, 0, last_slot_index)
	step_t = 0.0
	is_running = false
	extra_steps_total = 0  # clear stale finishing state from a previous run
	extra_steps_done = 0
	step_duration = base_step_duration / speed_multiplier
	# Phase is set by simulation.gd's scrub_to() after calling this

func set_phase(new_phase: int) -> void:
	# Allow simulation.gd to force a phase (e.g. during scrub)
	_set_phase(new_phase)

func set_speed(multiplier: float) -> void:
	speed_multiplier = multiplier
	step_duration = base_step_duration / speed_multiplier

# ---------- DERIVED VALUES (for simulation.gd rendering) ----------

func get_eased_step_t() -> float:
	# Ease-out curve: fast start, settles into position — ratchet feel
	var t = step_t
	return 1.0 - pow(1.0 - t, 3.0)  # Cubic ease-out

func get_slot_index() -> int:
	return current_slot_index

func get_step_t() -> float:
	return step_t

func get_settling_blend() -> float:
	# 0.0 at start of settling, 1.0 when done — used by simulation.gd for
	# settle_blend visual blending in _rebuild_rail
	if phase == Phase.DONE:
		return 1.0
	if phase != Phase.SETTLING:
		return 0.0
	return clamp(settling_t / settling_duration, 0.0, 1.0)

func get_phase() -> int:
	return phase

func is_done() -> bool:
	return phase == Phase.DONE

# ==========================================
# PRIVATE
# ==========================================

func _set_phase(new_phase: int) -> void:
	if new_phase == phase:
		return
	phase = new_phase
	emit_signal("phase_changed", new_phase)
	if new_phase == Phase.FINISHING_LAST_PULSE:
		emit_signal("sprite_should_fade")
