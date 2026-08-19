class_name TauBody
extends Node2D

## Tau Body: Physical coupling structure between helicase and lagging polymerase
## Models the E. coli tau homodimer connecting Pol III cores to DnaB helicase
## Part of the trombone loop mechanism in the complexity model

@export var enabled: bool = true:
	set(value):
		enabled = value
		_update_visibility()

# References to connected components (set by parent Replisome)
var helicase: Node2D = null
var lagging_polymerase: Node2D = null

# Visual elements
var body_shape: Polygon2D
var connector_lines: Array[Line2D] = []
const CONNECTOR_COUNT_DEFAULT = 3

# Configuration from ThemeManager
var _theme_data: Dictionary = {}

func _ready():
	_setup_visuals()
	_apply_theme()
	_update_visibility()

func _setup_visuals():
	"""Initialize tau body visual elements"""
	# Main body shape (representing tau dimer complex)
	body_shape = Polygon2D.new()
	body_shape.name = "TauBodyShape"
	add_child(body_shape)
	
	# Initialize connector lines (visual links to helicase/polymerase)
	for i in range(CONNECTOR_COUNT_DEFAULT):
		var line = Line2D.new()
		line.name = "Connector_%d" % i
		line.width = 2.0
		add_child(line)
		connector_lines.append(line)

func _apply_theme():
	"""Apply theme settings from ThemeManager"""
	if not Engine.is_editor_hint():
		var tm = get_tree().get_first_node_in_group("theme_manager")
		if tm:
			_theme_data = tm.get_tau_body_theme()
	
	# Apply body color and shape
	if _theme_data.has("color"):
		body_shape.color = _theme_data["color"]
	if _theme_data.has("width"):
		var base_width = _theme_data["width"]
		body_shape.polygon = _calculate_body_polygon(base_width)
		for line in connector_lines:
			line.width = base_width * 0.5
	
	# Apply connector count if different from default
	if _theme_data.has("connector_count"):
		var count = _theme_data["connector_count"]
		_adjust_connector_count(count)

func _calculate_body_polygon(width: float) -> PackedVector2Array:
	"""Generate polygon vertices for tau body shape"""
	# Elongated oval/rectangle shape representing tau dimer
	var points = PackedVector2Array()
	var half_w = width * 0.8
	var half_h = width * 1.2
	
	# Simple rectangular shape with rounded corners approximation
	points.append(Vector2(-half_w, -half_h))
	points.append(Vector2(half_w, -half_h))
	points.append(Vector2(half_w, half_h))
	points.append(Vector2(-half_w, half_h))
	
	return points

func _adjust_connector_count(count: int):
	"""Adjust number of connector lines based on theme"""
	while connector_lines.size() < count:
		var line = Line2D.new()
		line.name = "Connector_%d" % connector_lines.size()
		line.width = 2.0
		add_child(line)
		connector_lines.append(line)
	
	while connector_lines.size() > count:
		var line = connector_lines.pop_back()
		line.queue_free()

func _process(_delta):
	if not enabled:
		return
	
	_update_position()
	_update_connectors()

func _update_position():
	"""Position tau body between helicase and lagging polymerase"""
	if not helicase or not lagging_polymerase:
		return
	
	# Position at midpoint between helicase and polymerase, 
	# offset slightly toward helicase
	var h_pos = helicase.global_position
	var p_pos = lagging_polymerase.global_position
	
	var midpoint = (h_pos + p_pos) * 0.5
	var offset_toward_helicase = (h_pos - p_pos).normalized() * 10.0
	
	global_position = midpoint + offset_toward_helicase

func _update_connectors():
	"""Update connector lines to link tau body with components"""
	if connector_lines.size() < 2:
		return
	
	# First connector: tau body to helicase
	if helicase:
		var start = global_position
		var end = helicase.global_position
		connector_lines[0].points = [start, end]
	
	# Second connector: tau body to lagging polymerase
	if lagging_polymerase:
		var start = global_position
		var end = lagging_polymerase.global_position
		connector_lines[1].points = [start, end]
	
	# Additional connectors for visual complexity (optional decorative lines)
	for i in range(2, connector_lines.size()):
		if helicase and lagging_polymerase:
			var h_pos = helicase.global_position
			var p_pos = lagging_polymerase.global_position
			# Create intermediate connection points for visual effect
			var t = float(i - 2) / float(connector_lines.size() - 3) if connector_lines.size() > 3 else 0.5
			var mid = h_pos.lerp(p_pos, t)
			var offset = Vector2(0, -15.0 * (1.0 - abs(t - 0.5) * 2.0))
			connector_lines[i].points = [global_position, mid + offset]

func _update_visibility():
	"""Show/hide tau body based on enabled state"""
	visible = enabled
	for child in get_children():
		child.visible = enabled

func set_connections(heli: Node2D, lag_poly: Node2D):
	"""Set references to connected components"""
	helicase = heli
	lagging_polymerase = lag_poly
	_update_position()
	_update_connectors()

func get_helicase() -> Node2D:
	return helicase

func get_lagging_polymerase() -> Node2D:
	return lagging_polymerase
