extends Node

# ==========================================
# THEME MANAGER
# Autoload (singleton) that centralises all visual styling for the
# simulation. Every color and thickness is an @export so the Inspector
# can be used to tweak values directly. Later these will be wired to a
# UI for runtime switching, including a light/dark theme toggle.
#
# Registration: Project Settings → Autoload → add this script as
# "ThemeManager" (no scene needed, plain script autoload).
# ==========================================

@export_group("Background")
@export var background_color: Color = Color(0.15377063, 0.22897473, 0.44707716, 1.0)

@export_group("Base Colors")
@export var base_color_a: Color = Color(0.8, 0.2, 0.2, 1.0)
@export var base_color_t: Color = Color(0.2, 0.2, 0.8, 1.0)
@export var base_color_c: Color = Color(0.85, 0.6, 0.1, 1.0)
@export var base_color_g: Color = Color(0.2, 0.8, 0.2, 1.0)
@export var base_label_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var base_label_font_size: int = 14
@export var base_label_font: Font = null  # Leave null to use Godot default

@export_group("Backbone")
@export var backbone_color: Color = Color(0.43137255, 0.72156864, 1.0, 1.0)
@export var backbone_line_width: float = 16.0
@export var backbone_offset_distance: float = 24.0
@export var backbone_offset_smoothing_speed: float = 10.0

@export_group("Bond Marks")
@export var bond_mark_width: float = 14.0
@export var bond_mark_back_inset: float = 6.3
@export var bond_mark_black_color: Color = Color(0.0, 0.0, 0.0, 1.0)

@export_group("Hydrogen Bonds")
@export var at_bond_color: Color = Color(1.0, 0.85, 0.3, 1.0)
@export var cg_bond_color: Color = Color(0.3, 0.85, 1.0, 1.0)
@export var hydrogen_bond_width: float = 1.5
@export var hydrogen_bond_spacing: float = 4.0

@export_group("Synthesis Circle")
@export var synthesis_circle_color: Color = Color(1.0, 0.0, 0.101960786, 1.0)

@export_group("Helicase")
@export var helicase_color: Color = Color(0.85, 0.85, 0.85, 1.0)
@export var helicase_thickness: float = 5.0
@export var helicase_half_width: float = 14.0
@export var helicase_height_margin: float = 4.0

@export_group("Markers")
@export var marker_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var marker_font_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var marker_font_size: int = 14
## Distance in pixels between the end markers and the terminal bases
## of their respective strands.
@export var marker_offset: float = 24.0

## Convenience lookup: pass a base type string to get its fill color.
func get_base_color(base_type: String) -> Color:
	match base_type:
		"A": return base_color_a
		"T": return base_color_t
		"C": return base_color_c
		"G": return base_color_g
	return Color.GRAY
