extends Resource
class_name SimulationRules

# Presets for the UI (Mapped to PT-BR labels later)
enum ComplexityLevel {
	STATIC_DNA,       # Estático
	UNZIPPING,        # Desenrolamento
	LEADING_STRAND,   # Fita Líder
	FULL_REPLICATION  # Replicação Completa
}

@export var complexity: ComplexityLevel = ComplexityLevel.FULL_REPLICATION

@export_group("Feature Toggles")
@export var enable_helicase: bool = true
@export var enable_leading_polymerase: bool = true
@export var enable_lagging_polymerase: bool = true
@export var enable_ligase: bool = false
@export var spawn_free_bases: bool = true
@export var show_all_free_bases: bool = false # NEW: Toggle for constant free base visibility

@export_group("Environment")
@export var temperature: float = 37.0 # Celsius
@export var free_nucleotide_count: int = 320
@export var binding_distance: float = 80.0 # FIX: Restored so nitrogen_base.gd can check proximity

@export_group("Screen Shake")
@export var shake_reject_strength: float = 0.5
@export var shake_reject_decay: float = 15.0
@export var shake_approve_strength: float = 0.25
@export var shake_approve_decay: float = 10.0

@export var enable_screen_shake: bool = true

var is_running: bool = false
var mode: String = "DNA Repl" # Kept for backward compatibility

# Call this whenever the complexity preset changes in the UI
func apply_preset():
	match complexity:
		ComplexityLevel.STATIC_DNA:
			enable_helicase = false
			enable_leading_polymerase = false
			enable_lagging_polymerase = false
			enable_ligase = false
			spawn_free_bases = false
			
		ComplexityLevel.UNZIPPING:
			enable_helicase = true
			enable_leading_polymerase = false
			enable_lagging_polymerase = false
			enable_ligase = false
			spawn_free_bases = false
			
		ComplexityLevel.LEADING_STRAND:
			enable_helicase = true
			enable_leading_polymerase = true
			enable_lagging_polymerase = false
			enable_ligase = false
			spawn_free_bases = true
			
		ComplexityLevel.FULL_REPLICATION:
			enable_helicase = true
			enable_leading_polymerase = true
			enable_lagging_polymerase = true
			enable_ligase = false #upalala
			spawn_free_bases = true

# Helper to convert Celsius to simulation speed using an exponential curve
# 10°C = ~1.4 speed (Very cold, sluggish motion)
# 37°C = 150.0 speed (Normal Body Temp)
# 45°C = 600.0 speed (Hyper-fast, 20% faster than before, approaching denaturation)
func get_speed_from_temperature() -> float:
	var base_speed = 150.0
	var temp_diff = temperature - 37.0
	
	# Adjusted exponential multiplier to hit exactly 600.0 at 45°C
	var multiplier = exp(0.1733 * temp_diff)
	
	return base_speed * multiplier
