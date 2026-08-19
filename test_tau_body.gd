extends Node2D

@onready var helicase_dummy = $HelicaseDummy
@onready var polymerase_dummy = $LaggingPolyDummy
@onready var tau_body = $TauBody

var dragging = null
var drag_offset = Vector2.ZERO

func _ready():
	# Initial positioning
	helicase_dummy.position = Vector2(200, 100)
	polymerase_dummy.position = Vector2(200, 300)
	
	# Connect the tau body
	tau_body.set_connections(helicase_dummy, polymerase_dummy)
	
	print("Test Scene Ready: Drag the colored squares to test Tau Body geometry.")

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check if clicking helicase
				if _is_point_in_rect(event.position, helicase_dummy):
					dragging = helicase_dummy
					drag_offset = helicase_dummy.position - event.position
				# Check if clicking polymerase
				elif _is_point_in_rect(event.position, polymerase_dummy):
					dragging = polymerase_dummy
					drag_offset = polymerase_dummy.position - event.position
				else:
					dragging = null
			else:
				dragging = null
				
	if event is InputEventMouseMotion and dragging != null:
		dragging.position = event.position + drag_offset
		# Update tau body connections dynamically
		tau_body.set_connections(helicase_dummy, polymerase_dummy)

func _is_point_in_rect(point: Vector2, node: Node2D) -> bool:
	var rect = Rect2(node.position - Vector2(20, 20), Vector2(40, 40))
	return rect.has_point(point)

func _process(_delta):
	# Optional: Continuous update if logic changes, but _input handles drag
	pass
