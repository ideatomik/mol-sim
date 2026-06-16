extends Node

# ==========================================
# CENTRALIZED ALPHA SETTINGS
# ==========================================
const DIMMED_ALPHA: float = 0.025   # Alpha for non-highlighted elements
const HIGHLIGHT_ALPHA: float = 1.0 # Alpha for highlighted elements

# Stores the currently active highlight groups so other scripts (like hydrogen bonds) can read them
var current_active_groups: Array = [] 

# ==========================================
# MULTI-GROUP HIGHLIGHTING
# ==========================================
func highlight_groups(group_names: Array):
	# FIX: Do NOT call clear_highlight() here! 
	# clear_highlight() wipes current_active_groups, which breaks the hydrogen bonds.
	# Instead, we manually dim everything first.
	var all_highlightable = get_tree().get_nodes_in_group("highlightable")
	for node in all_highlightable:
		if node is CanvasItem:
			node.modulate.a = DIMMED_ALPHA

	# NOW we set the active groups for other scripts to read
	current_active_groups = group_names

	# STEP 2: Loop through requested groups and brighten matches
	for group_name in group_names:
		# Handle dynamic base pair highlighting (A-T or C-G)
		if group_name == "pair_AT" or group_name == "pair_CG":
			for node in all_highlightable:
				if node is NitrogenBase and node.partner_base != null:
					var b1 = node
					var b2 = node.partner_base
					
					# Only highlight if bases are physically close (< 200px)
					if b1.position.distance_to(b2.position) < 200.0:
						var is_AT = (b1.base_type == "A" and b2.base_type == "T") or (b1.base_type == "T" and b2.base_type == "A")
						var is_CG = (b1.base_type == "C" and b2.base_type == "G") or (b1.base_type == "G" and b2.base_type == "C")
						
						if (group_name == "pair_AT" and is_AT) or (group_name == "pair_CG" and is_CG):
							b1.modulate.a = HIGHLIGHT_ALPHA
							b2.modulate.a = HIGHLIGHT_ALPHA
		else:
			# Standard group highlighting (bases, enzymes, etc.)
			var targets = get_tree().get_nodes_in_group(group_name)
			for node in targets:
				if node is CanvasItem:
					node.modulate.a = HIGHLIGHT_ALPHA

# ==========================================
# CLEAR ALL HIGHLIGHTS
# ==========================================
func clear_highlight():
	# This is ONLY called when the user clicks "Limpar Destaque"
	current_active_groups = []
	
	var all_highlightable = get_tree().get_nodes_in_group("highlightable")
	for node in all_highlightable:
		if node is CanvasItem:
			node.modulate.a = HIGHLIGHT_ALPHA
