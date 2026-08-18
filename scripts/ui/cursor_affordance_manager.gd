extends Node
class_name CursorAffordanceManager

# ==========================================
# CURSOR AFFORDANCE MANAGER
# Swaps the OS mouse cursor to signal what's under it — grab-hand over
# draggable enzymes, scrub-track icon over the timeline. Scene Node,
# Inspector-editable, NOT an autoload — same pattern as
# ComplexityManager/LocaleManager/ThemeManager (this project has zero
# [autoload] entries in project.godot; every manager is a plain Node
# instanced under the simulation root, reached via %UniqueName).
#
# See docs/CursorAffordanceDesign.md for the design rationale.
#
# WIRING: helicase_ring.gd and polymerase_clamp.gd deliberately hold no
# external references (their own header comments — pure, simulation-
# agnostic components) and can't call this manager directly. They emit
# hover_changed/scrub_drag_started/scrub_drag_ended; their OWNING scripts
# (simulation.gd for the ring, replication_manager.gd for both clamps —
# the same scripts that already connect those signals for scrub purposes)
# forward them here via set_hovering()/set_dragging(). The Scrubber
# (a Control) is registered directly by player_ui.gd instead, since
# Control's own mouse_entered/mouse_exited are reliable — unlike Area2D
# picking, which this project avoids project-wide (see helicase_ring.gd's
# "Manual hit-test" comment for why).
# ==========================================

enum CursorAffordance { DEFAULT, DRAGGABLE, INSPECTABLE, SCRUB }

# Hotspots measured directly from each asset's non-transparent bounding box
# — see docs/CursorAffordanceDesign.md's asset table. All assets are
# 64x64 PNGs from Kenney's free CC0 Cursor Pack (kenney.nl/assets/cursor-pack).
const _DEFAULT_TEXTURE: Texture2D = preload("res://cursors/pointer_c.png")
const _DEFAULT_HOTSPOT: Vector2 = Vector2(4, 4)

const _DRAGGABLE_HOVER_TEXTURE: Texture2D = preload("res://cursors/hand_open.png")
const _DRAGGABLE_DRAGGING_TEXTURE: Texture2D = preload("res://cursors/hand_closed.png")
const _DRAGGABLE_HOTSPOT: Vector2 = Vector2(31, 31)

## tracking_horizontal.png shelved for now — this project's horizontal
## timeline is the only one actually shipping; vertical_mode today is an
## ad hoc testing toggle, not a real second layout yet (see
## docs/camera-intro/VerticalModeDesign.md). Revisit once that's built out
## properly rather than branching on vertical_mode here in the meantime.
## Hotspot not separately measured in docs/CursorAffordanceDesign.md's
## asset table (only tracking_horizontal's is) — 64x64 native and visually
## center-symmetric, so the same center hotspot is used; revisit if that
## assumption is wrong once seen on screen.
const _SCRUB_TEXTURE: Texture2D = preload("res://cursors/tracking_vertical.png")
const _SCRUB_HOTSPOT: Vector2 = Vector2(32, 32)

## node -> CursorAffordance
var _registered: Dictionary = {}
var _hovered_node: Node = null
var _dragging_node: Node = null

func _ready() -> void:
	_apply()

func register(node: Node, affordance: CursorAffordance) -> void:
	_registered[node] = affordance
	if node is Control:
		if not node.mouse_entered.is_connected(set_hovering.bind(node, true)):
			node.mouse_entered.connect(set_hovering.bind(node, true))
		if not node.mouse_exited.is_connected(set_hovering.bind(node, false)):
			node.mouse_exited.connect(set_hovering.bind(node, false))

func unregister(node: Node) -> void:
	_registered.erase(node)
	if _hovered_node == node:
		_hovered_node = null
	if _dragging_node == node:
		_dragging_node = null
	_apply()

## Called by the owning script (simulation.gd, replication_manager.gd),
## never by the interactable node itself — see header. Also self-registered
## for Control nodes via register()'s own mouse_entered/mouse_exited hookup.
func set_hovering(node: Node, hovering: bool) -> void:
	if hovering:
		_hovered_node = node
	elif _hovered_node == node:
		_hovered_node = null
	_apply()

## Called by the owning script from its scrub_drag_started/scrub_drag_ended
## handlers — dragging always takes priority over hover in _apply() below.
func set_dragging(node: Node, dragging: bool) -> void:
	if dragging:
		_dragging_node = node
	elif _dragging_node == node:
		_dragging_node = null
	_apply()

## Only one node can plausibly be hovered/dragging at a time in practice —
## screen-space click regions for helicase/clamps/scrubber don't overlap —
## so no arbitration beyond "dragging wins over hover" is needed here.
func _apply() -> void:
	if _dragging_node != null and _registered.get(_dragging_node) == CursorAffordance.DRAGGABLE:
		Input.set_custom_mouse_cursor(_DRAGGABLE_DRAGGING_TEXTURE, Input.CURSOR_ARROW, _DRAGGABLE_HOTSPOT)
		return
	if _hovered_node != null and _registered.has(_hovered_node):
		match _registered[_hovered_node]:
			CursorAffordance.DRAGGABLE:
				Input.set_custom_mouse_cursor(_DRAGGABLE_HOVER_TEXTURE, Input.CURSOR_ARROW, _DRAGGABLE_HOTSPOT)
				return
			CursorAffordance.SCRUB:
				Input.set_custom_mouse_cursor(_SCRUB_TEXTURE, Input.CURSOR_ARROW, _SCRUB_HOTSPOT)
				return
			# INSPECTABLE: no asset shipped yet (docs/CursorAffordanceDesign.md) —
			# falls through to DEFAULT below until one lands.
	Input.set_custom_mouse_cursor(_DEFAULT_TEXTURE, Input.CURSOR_ARROW, _DEFAULT_HOTSPOT)
