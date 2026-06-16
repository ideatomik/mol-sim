extends Node

# This will hold the active rules
var current_rules: SimulationRules

func set_rules(new_rules: SimulationRules):
	current_rules = new_rules
