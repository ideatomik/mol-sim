extends Node

# ==========================================
# SIGNALS
# ==========================================
signal theme_changed

# ==========================================
# UNIVERSAL COLORS (Stay the same in both modes)
# ==========================================
var base_A_color: Color = Color(0.8, 0.2, 0.2)
var base_T_color: Color = Color(0.2, 0.2, 0.8)
var base_C_color: Color = Color(0.85, 0.6, 0.1)
var base_G_color: Color = Color(0.2, 0.8, 0.2)
var base_U_color: Color = Color(0.701961, 0.192157, 0.945098)

var enzyme_helicase_color: Color = Color(1.0, 0.0, 0.321569)
var enzyme_polymerase_color: Color = Color(0.95, 0.6, 0.1)
var enzyme_ligase_color: Color = Color(0.0, 0.8, 0.8)
var enzyme_primase_color: Color = Color(0.2, 0.6, 0.9)

var nick_color: Color = Color(1.0, 0.3, 0.3, 0.9) #TODO: nick mechanics revamp. only show at beginning and end of the empty  space
var dimmed_alpha: float = 0.25
var highlight_alpha: float = 1.0

# ==========================================
# Marker (5'/3') Colors - Active State
# ==========================================
var marker_circle_color: Color
var marker_font_color: Color

# ==========================================
# DARK MODE PALETTE (Original/Default)
# ==========================================
var dark_backbone_color: Color = Color(0.6, 0.6, 0.6, 0.9)
var dark_arrow_color: Color = Color(0.9, 0.9, 0.9, 0.8)
var dark_bond_normal_color: Color = Color(1.0, 1.0, 1.0, 0.5)
var dark_bond_dimmed_color: Color = Color(1.0, 1.0, 1.0, 0.1)
var dark_bond_highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var dark_bg_color: Color = Color(0.1, 0.1, 0.15, 1.0)
var dark_marker_circle_color: Color = Color(0.2, 0.2, 0.3, 1.0) # Dark blue/gray
var dark_marker_font_color: Color = Color(1.0, 1.0, 1.0, 1.0)   # White

# ==========================================
# LIGHT MODE PALETTE (High Contrast)
# ==========================================
var light_backbone_color: Color = Color(0.2, 0.2, 0.3, 0.9)
var light_arrow_color: Color = Color(0.2, 0.2, 0.3, 0.8)
var light_bond_normal_color: Color = Color(0.2, 0.2, 0.3, 0.6)
var light_bond_dimmed_color: Color = Color(0.2, 0.2, 0.3, 0.1)
var light_bond_highlight_color: Color = Color(0.1, 0.1, 0.1, 1.0)
var light_bg_color: Color = Color(0.85, 0.85, 0.9, 1.0)
var light_marker_circle_color: Color = Color(0.8, 0.8, 0.9, 1.0) # Light blue/gray
var light_marker_font_color: Color = Color(0.1, 0.1, 0.2, 1.0)   # Dark blue/black

# ==========================================
# DIMENSIONS & SCALING
# ==========================================
var backbone_width: float = 8.0
var arrow_scale: float = 0.9
var bond_thickness: float = 1 # hydrogen bonds

# ==========================================
# SCREEN SHAKE
# ==========================================
var shake_strength_level_0: float = 0.00  # Very subtle shake in overview
var shake_strength_level_1: float = 0.25  # Moderate shake in context view
var shake_strength_level_2: float = 0.50  # Strong shake in action zone
var shake_strength_level_3: float = 1.00 # Violent shake in microscope view

# ==========================================
# ACTIVE THEME STATE (What the game actually reads)
# ==========================================
var backbone_color: Color
var arrow_color: Color
var bond_normal_color: Color
var bond_dimmed_color: Color
var bond_highlight_color: Color
var bg_color: Color

func _ready():
	# Start with Dark Mode by default
	apply_dark_mode()

func apply_dark_mode():
	backbone_color = dark_backbone_color
	arrow_color = dark_arrow_color
	bond_normal_color = dark_bond_normal_color
	bond_dimmed_color = dark_bond_dimmed_color
	bond_highlight_color = dark_bond_highlight_color
	bg_color = dark_bg_color
	marker_circle_color = dark_marker_circle_color
	marker_font_color = dark_marker_font_color
	theme_changed.emit()

func apply_light_mode():
	backbone_color = light_backbone_color
	arrow_color = light_arrow_color
	bond_normal_color = light_bond_normal_color
	bond_dimmed_color = light_bond_dimmed_color
	bond_highlight_color = light_bond_highlight_color
	bg_color = light_bg_color
	marker_circle_color = light_marker_circle_color
	marker_font_color = light_marker_font_color
	theme_changed.emit()
