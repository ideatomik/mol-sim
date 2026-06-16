extends Control

# ==========================================
# UI REFERENCES (VERIFIED against your Scene Tree)
# ==========================================
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var mode_dropdown: OptionButton = $MarginContainer/VBoxContainer/ModeDropdown

@onready var start_button: Button = $MarginContainer/VBoxContainer/ControlButtonsHBox/StartButton
@onready var pause_button: Button = $MarginContainer/VBoxContainer/ControlButtonsHBox/PauseButton
@onready var reset_button: Button = $MarginContainer/VBoxContainer/ControlButtonsHBox/ResetButton

@onready var collapse_button: Button = $MarginContainer/VBoxContainer/CollapseButton
@onready var collapsible_content: VBoxContainer = $MarginContainer/VBoxContainer/CollapsibleContent

@onready var temp_slider: HSlider = $MarginContainer/VBoxContainer/CollapsibleContent/TemperatureSection/TempSlider
@onready var temp_label: Label = $MarginContainer/VBoxContainer/CollapsibleContent/TemperatureSection/TempLabel

# --- Ativar/Desativar Section ---
@onready var section_enzymes_button: Button = $MarginContainer/VBoxContainer/CollapsibleContent/SectionEnzymes/SectionEnzymesButton
@onready var enzymes_content: VBoxContainer = $MarginContainer/VBoxContainer/CollapsibleContent/SectionEnzymes/EnzymesContent
@onready var check_helicase: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionEnzymes/EnzymesContent/CheckHelicase
@onready var check_leading: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionEnzymes/EnzymesContent/CheckLeading
@onready var check_lagging: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionEnzymes/EnzymesContent/CheckLagging
@onready var check_ligase: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionEnzymes/EnzymesContent/CheckLigase
@onready var check_bases: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionEnzymes/EnzymesContent/CheckBases
@onready var apply_button: Button = $MarginContainer/VBoxContainer/CollapsibleContent/SectionEnzymes/EnzymesContent/EnzymesContentButtons/ApplyButton
@onready var restore_defaults_button: Button = $MarginContainer/VBoxContainer/CollapsibleContent/SectionEnzymes/EnzymesContent/EnzymesContentButtons/RestoreDefaultsButton

# --- Destacar Section ---
@onready var section_highlight_button: Button = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightButton
@onready var section_highlight_content: VBoxContainer = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent # NEW!

@onready var bases_highlight_button: Button = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/BasesHighlightButton
@onready var bases_highlight_content: VBoxContainer = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/BasesHighlightContent
@onready var enzimes_highlight_button: Button = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/EnzimesHighlightButton
@onready var enzimes_highlight_content: VBoxContainer = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/EnzimesHighlightContent

@onready var check_highlight_a: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/BasesHighlightContent/CheckHighlightA
@onready var check_highlight_t: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/BasesHighlightContent/CheckHighlightT
@onready var check_highlight_c: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/BasesHighlightContent/CheckHighlightC
@onready var check_highlight_g: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/BasesHighlightContent/CheckHighlightG
@onready var check_highlight_at: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/BasesHighlightContent/CheckHighlightAT
@onready var check_highlight_cg: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/BasesHighlightContent/CheckHighlightCG

@onready var check_highlight_helicase: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/EnzimesHighlightContent/CheckHighlightHelicase
@onready var check_highlight_leading: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/EnzimesHighlightContent/CheckHighlightLeading
@onready var check_highlight_lagging: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/EnzimesHighlightContent/CheckHighlightLagging
@onready var check_highlight_ligase: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/EnzimesHighlightContent/CheckHighlightLigase
@onready var check_highlight_primase: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/EnzimesHighlightContent/CheckHighlightPrimase
@onready var clear_highlight_button: Button = $MarginContainer/VBoxContainer/CollapsibleContent/SectionHighlight/SectionHighlightContent/ClearHighlightButton

# --- Aparência Section ---
@onready var section_appearance_button: Button = $MarginContainer/VBoxContainer/CollapsibleContent/SectionAppearance/SectionAppearanceButton
@onready var section_appearance_content: VBoxContainer = $MarginContainer/VBoxContainer/CollapsibleContent/SectionAppearance/SectionAppearanceContent
@onready var check_show_all_bases: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionAppearance/SectionAppearanceContent/CheckShowAllBases
@onready var light_mode_button: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionAppearance/SectionAppearanceContent/LightMode
@onready var dark_mode_button: CheckButton = $MarginContainer/VBoxContainer/CollapsibleContent/SectionAppearance/SectionAppearanceContent/DarkMode

# ==========================================
# COLLAPSE STATE VARIABLES (All start TRUE/FOLDED)
# ==========================================
var is_main_collapsed: bool = true
var is_enzymes_collapsed: bool = true
var is_highlight_collapsed: bool = true
var is_bases_highlight_collapsed: bool = true
var is_enzimes_highlight_collapsed: bool = true
var is_appearance_collapsed: bool = true

func _ready():
	print("UI Controller _ready() started...")
	
	# 1. Setup Dropdown
	mode_dropdown.clear()
	mode_dropdown.add_item("Replicação de DNA", SimulationRules.ComplexityLevel.FULL_REPLICATION)
	mode_dropdown.add_item("Transcrição de DNA", SimulationRules.ComplexityLevel.LEADING_STRAND)
	mode_dropdown.add_item("Tradução de RNA", SimulationRules.ComplexityLevel.STATIC_DNA)
	
	# 2. Connect Main Controls
	start_button.pressed.connect(_on_start_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	collapse_button.pressed.connect(_on_main_collapse_pressed)
	mode_dropdown.item_selected.connect(_on_mode_changed)
	temp_slider.value_changed.connect(_on_temp_changed)
	
	# 3. Connect Section Toggles
	section_enzymes_button.pressed.connect(_on_enzymes_collapse_pressed)
	section_highlight_button.pressed.connect(_on_highlight_collapse_pressed)
	bases_highlight_button.pressed.connect(_on_bases_highlight_collapse_pressed)
	enzimes_highlight_button.pressed.connect(_on_enzimes_highlight_collapse_pressed)
	section_appearance_button.pressed.connect(_on_appearance_collapse_pressed)
	
	# 4. Connect Enzyme Toggles
	apply_button.pressed.connect(_on_apply_pressed)
	restore_defaults_button.pressed.connect(_on_restore_defaults_pressed)
	
	# 5. Connect Highlight Toggles (Multi-select)
	var highlight_checks = [check_highlight_a, check_highlight_t, check_highlight_c, check_highlight_g, 
							check_highlight_at, check_highlight_cg, check_highlight_helicase, 
							check_highlight_leading, check_highlight_lagging, check_highlight_ligase, 
							check_highlight_primase]
	for check in highlight_checks:
		check.toggled.connect(_on_highlight_toggled)
	clear_highlight_button.pressed.connect(_on_clear_highlight_pressed)
	
	# 6. Connect Appearance Toggles
	check_show_all_bases.toggled.connect(_on_show_all_bases_toggled)
	light_mode_button.toggled.connect(_on_light_mode_toggled)
	dark_mode_button.toggled.connect(_on_dark_mode_toggled)
	
	# 7. Initial Sync & State
	_sync_ui_to_rules()
	_apply_initial_collapse_states()
	
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("is_simulation_running"):
		start_button.disabled = main_scene.is_simulation_running()
		pause_button.disabled = not main_scene.is_simulation_running()
		
	print("UI Controller _ready() finished.")

func _apply_initial_collapse_states():
	_update_section_visuals(collapse_button, collapsible_content, is_main_collapsed, "Opções")
	_update_section_visuals(section_enzymes_button, enzymes_content, is_enzymes_collapsed, "Ativar/Desativar")
	_update_section_visuals(section_highlight_button, section_highlight_content, is_highlight_collapsed, "Destacar") # NEW!
	_update_section_visuals(bases_highlight_button, bases_highlight_content, is_bases_highlight_collapsed, "Bases Nitrogenadas")
	_update_section_visuals(enzimes_highlight_button, enzimes_highlight_content, is_enzimes_highlight_collapsed, "Enzimas")
	_update_section_visuals(section_appearance_button, section_appearance_content, is_appearance_collapsed, "Aparência")

func _update_section_visuals(button: Button, content: Control, is_collapsed: bool, text_base: String):
	content.visible = not is_collapsed
	button.text = ("▶ " if is_collapsed else "▼ ") + text_base

# ==========================================
# COLLAPSE HANDLERS
# ==========================================
func _on_main_collapse_pressed():
	is_main_collapsed = !is_main_collapsed
	_update_section_visuals(collapse_button, collapsible_content, is_main_collapsed, "Opções")

func _on_enzymes_collapse_pressed():
	is_enzymes_collapsed = !is_enzymes_collapsed
	_update_section_visuals(section_enzymes_button, enzymes_content, is_enzymes_collapsed, "Ativar/Desativar")

func _on_bases_highlight_collapse_pressed():
	is_bases_highlight_collapsed = !is_bases_highlight_collapsed
	_update_section_visuals(bases_highlight_button, bases_highlight_content, is_bases_highlight_collapsed, "Bases Nitrogenadas")

func _on_enzimes_highlight_collapse_pressed():
	is_enzimes_highlight_collapsed = !is_enzimes_highlight_collapsed
	_update_section_visuals(enzimes_highlight_button, enzimes_highlight_content, is_enzimes_highlight_collapsed, "Enzimas")

func _on_appearance_collapse_pressed():
	is_appearance_collapsed = !is_appearance_collapsed
	_update_section_visuals(section_appearance_button, section_appearance_content, is_appearance_collapsed, "Aparência")
	
func _on_highlight_collapse_pressed():
	is_highlight_collapsed = !is_highlight_collapsed
	_update_section_visuals(section_highlight_button, section_highlight_content, is_highlight_collapsed, "Destacar")

# ==========================================
# SIMULATION CONTROLS
# ==========================================
func _on_start_pressed():
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("start_simulation"):
		main_scene.start_simulation()
		start_button.disabled = true
		pause_button.disabled = false

func _on_pause_pressed():
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("pause_simulation"):
		main_scene.pause_simulation()
		start_button.disabled = false
		pause_button.disabled = true

func _on_reset_pressed():
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("reset_simulation"):
		main_scene.reset_simulation()
		start_button.disabled = false
		pause_button.disabled = true
		_on_clear_highlight_pressed()

func _on_mode_changed(index: int):
	var rules = SimulationManager.current_rules
	if rules:
		rules.complexity = index
		rules.apply_preset()
		_sync_ui_to_rules()

func _on_temp_changed(value: float):
	temp_label.text = "Temperatura: %.1f °C" % value
	var rules = SimulationManager.current_rules
	if rules:
		rules.temperature = value

# ==========================================
# APPLY & RESTORE
# ==========================================
func _on_apply_pressed():
	print("--- APPLY BUTTON PRESSED (Real-time Cascade) ---")
	var rules = SimulationManager.current_rules
	if not rules:
		return
		
	rules.enable_helicase = check_helicase.button_pressed
	rules.enable_leading_polymerase = check_leading.button_pressed
	rules.enable_lagging_polymerase = check_lagging.button_pressed
	rules.enable_ligase = check_ligase.button_pressed
	rules.spawn_free_bases = check_bases.button_pressed
	
	if not rules.spawn_free_bases:
		var free_bases = get_tree().get_nodes_in_group("free_nucleotides")
		for base in free_bases:
			if base.has_method("fade_and_free"):
				base.fade_and_free()
			else:
				base.queue_free()

func _on_restore_defaults_pressed():
	check_helicase.button_pressed = true
	check_leading.button_pressed = true
	check_lagging.button_pressed = true
	check_ligase.button_pressed = true
	check_bases.button_pressed = true
	_on_apply_pressed()

func _sync_ui_to_rules():
	var rules = SimulationManager.current_rules
	if not rules:
		return
		
	temp_slider.value = rules.temperature
	temp_label.text = "Temperatura: %.1f °C" % rules.temperature
	mode_dropdown.select(rules.complexity)
	
	check_helicase.button_pressed = rules.enable_helicase
	check_leading.button_pressed = rules.enable_leading_polymerase
	check_lagging.button_pressed = rules.enable_lagging_polymerase
	check_ligase.button_pressed = rules.enable_ligase
	check_bases.button_pressed = rules.spawn_free_bases
	check_show_all_bases.button_pressed = rules.show_all_free_bases

# ==========================================
# HIGHLIGHTING (Multi-Select)
# ==========================================
func _on_highlight_toggled(_pressed: bool):
	var active_groups = []
	
	if check_highlight_a.button_pressed: active_groups.append("base_A")
	if check_highlight_t.button_pressed: active_groups.append("base_T")
	if check_highlight_c.button_pressed: active_groups.append("base_C")
	if check_highlight_g.button_pressed: active_groups.append("base_G")
	if check_highlight_at.button_pressed: active_groups.append("pair_AT")
	if check_highlight_cg.button_pressed: active_groups.append("pair_CG")
	
	if check_highlight_helicase.button_pressed: active_groups.append("helicase_highlight")
	if check_highlight_leading.button_pressed: active_groups.append("leading_poly_highlight")
	if check_highlight_lagging.button_pressed: active_groups.append("lagging_poly_highlight")
	if check_highlight_ligase.button_pressed: active_groups.append("ligase_highlight")
	if check_highlight_primase.button_pressed: active_groups.append("primase_highlight")
	
	if active_groups.size() == 0:
		HighlightManager.clear_highlight()
	else:
		HighlightManager.highlight_groups(active_groups)

func _on_clear_highlight_pressed():
	HighlightManager.clear_highlight()
	var checks = [check_highlight_a, check_highlight_t, check_highlight_c, check_highlight_g, 
				  check_highlight_at, check_highlight_cg, check_highlight_helicase, 
				  check_highlight_leading, check_highlight_lagging, check_highlight_ligase, 
				  check_highlight_primase]
	for check in checks:
		check.button_pressed = false

func _on_show_all_bases_toggled(toggled_on: bool):
	var rules = SimulationManager.current_rules
	if rules:
		rules.show_all_free_bases = toggled_on

# ==========================================
# APPEARANCE (Exclusive Toggles)
# ==========================================
func _on_light_mode_toggled(toggled_on: bool):
	if toggled_on:
		dark_mode_button.set_pressed_no_signal(false)
		if ThemeManager:
			ThemeManager.apply_light_mode()
		_apply_theme() # No more hardcoded colors!

func _on_dark_mode_toggled(toggled_on: bool):
	if toggled_on:
		light_mode_button.set_pressed_no_signal(false)
		if ThemeManager:
			ThemeManager.apply_dark_mode()
		_apply_theme() # No more hardcoded colors!

func _apply_theme():
	var bg = get_tree().get_first_node_in_group("background")
	if bg and ThemeManager:
		# Read the background color directly from the ThemeManager
		bg.color = ThemeManager.bg_color 
