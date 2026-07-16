extends PanelContainer
class_name EnzymeLabel

# ==========================================
# enzyme_label.gd
# Reusable enzyme name tag: a half-opacity panel behind a BBCode RichTextLabel.
# A real scene/class object (not a bare Label spawned inline) so it can later
# host its own behavior — e.g. counter-scaling against camera zoom — without
# touching the enzyme scripts that spawn it.
#
# TRANSLATION: set_key() takes the raw translation KEY (e.g.
# "ENZYME_HELICASE"), never a display string. RichTextLabel.text auto-
# translates through Godot's built-in Control mechanism, and every Control
# re-applies its translation automatically on TranslationServer.set_locale()
# — so live language switching costs nothing extra here. refresh_translation()
# is kept as a manual escape hatch in case empirical testing (once
# LocaleManager exists) shows a gap in that auto-refresh for this node type.
#
# CENTERING: pivot_offset is kept at size * 0.5, and position is derived from
# set_anchor_pos()'s point minus that pivot — so the label's own CENTER, not
# its top-left, stays pinned to the anchor regardless of text length. This
# means a locale change that changes text length re-centers automatically via
# the resized signal, with no caller involvement.
#
# NOTE: named set_anchor_pos(), not set_anchor() — Control already defines a
# built-in set_anchor(side, anchor, keep_offset, push_opposite_anchor) with an
# incompatible signature; reusing that name would shadow it.
#
# MIRROR: set_mirror(true) sets local scale.y = -1, cancelling a mirrored
# parent's own scale.y = -1 (the leading polymerase clamp) so glyphs stay
# upright. Because scale is applied around pivot_offset (== the anchor point),
# the anchor itself never moves when mirroring toggles.
#
# VERTICAL MODE: set_counter_rotation() cancels the camera's -90 rotation so
# the tag stays readable. It composes with MIRROR — see _apply_rotation() for
# why the sign flips there, and why that sign lives in this file rather than
# in the five enzyme scripts that spawn these.
# ==========================================

var _rich_text: RichTextLabel = null
var _anchor: Vector2 = Vector2.ZERO
var _key: String = ""
var _mirror: bool = false
var _counter_rotation: float = 0.0

func _ready() -> void:
	_ensure_rich_text()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rich_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	_recenter()

# get_node() walks the local subtree that instantiate() already built, so this
# works immediately after instantiation — unlike @onready, which waits for
# _ready(), which itself waits for this node to enter a LIVE SceneTree. That
# assumption broke here: polymerase_clamp.gd calls set_key() on this node
# from _build(), which can run before PolymerClamp itself is in the live
# tree (still mid-assembly during simulation.gd's own _ready()) — so
# @onready's assignment hadn't happened yet. Every public method below calls
# this guard first instead of trusting _ready() to have already run.
func _ensure_rich_text() -> void:
	if _rich_text == null:
		_rich_text = get_node("RichTextLabel")

## Sets the raw translation key. Never pass a display string directly.
func set_key(key: String) -> void:
	_ensure_rich_text()
	_key = key
	_rich_text.text = key

## Manual re-translate, in case a future locale-change path needs it.
func refresh_translation() -> void:
	_ensure_rich_text()
	_rich_text.text = _key

## anchor_pos is in the PARENT's local space — the point the label's own
## center should stay pinned to, regardless of text length or mirroring.
func set_anchor_pos(anchor_pos: Vector2) -> void:
	_anchor = anchor_pos
	_recenter()

## true for the leading-strand clamp (whose parent already has scale.y = -1),
## so the label counter-flips and reads upright. No-op for anything unmirrored.
func set_mirror(mirror: bool) -> void:
	_mirror = mirror
	scale.y = -1.0 if mirror else 1.0
	_apply_rotation()

## Cancels the camera's rotation in vertical mode so the name tag stays
## upright. Pass ZoomManager.get_label_counter_rotation() verbatim — callers
## never need to know about the mirror interaction below.
func set_counter_rotation(radians: float) -> void:
	_counter_rotation = radians
	_apply_rotation()

## The mirror INVERTS the sense of rotation, so the sign is owned here rather
## than by the five enzyme scripts that spawn these. A mirrored parent applies
## S = scale.y(-1); this node's own transform is R(t) * S; composed, the total
## is S * R(t) * S = R(-t), because reflection conjugates rotation. So a local
## t under the leading clamp renders as world -t, and cancelling the camera's
## rotation there needs the negation.
##
## Keeping this here means every caller passes the same unmodified value and
## the sign can't be got wrong at one of five call sites. Order-independent:
## set_mirror() and set_counter_rotation() may be called in either order.
## Rotation applies around pivot_offset (== the anchor), so the anchor never
## moves — the same property that already made set_mirror() safe.
func _apply_rotation() -> void:
	rotation = -_counter_rotation if _mirror else _counter_rotation

func set_style(font: Font, font_size: int, text_color: Color, panel_bg_color: Color) -> void:
	_ensure_rich_text()
	if font:
		_rich_text.add_theme_font_override("normal_font", font)
	_rich_text.add_theme_font_size_override("normal_font_size", font_size)
	_rich_text.add_theme_color_override("default_color", text_color)
	var style := StyleBoxFlat.new()
	style.bg_color = panel_bg_color
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	add_theme_stylebox_override("panel", style)
	_recenter()

func _on_resized() -> void:
	_recenter()

func _recenter() -> void:
	pivot_offset = size * 0.5
	position = _anchor - pivot_offset
