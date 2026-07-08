extends Node
class_name LocaleManager

# ==========================================
# locale_manager.gd
# Thin wrapper around Godot's built-in TranslationServer. Follows the same
# pattern as ComplexityManager/ThemeManager: a plain Node, Inspector-editable,
# not yet an autoload.
#
# Live switching is almost entirely Godot's own doing: every Control already
# re-applies its own translation automatically when TranslationServer's
# locale changes (NOTIFICATION_TRANSLATION_CHANGED), as long as its text was
# set to a raw translation KEY (never a display string) — which is exactly
# what enzyme_label.gd's set_key() does. This script's only real job is
# exposing set_locale() as a clean call site and emitting locale_changed for
# any future non-Control listener (a language-picker widget highlighting the
# current selection, say) that isn't covered by that automatic mechanism.
#
# Add as a sibling of %ThemeManager under simulation.gd's root, with a
# unique name enabled (%LocaleManager), so it's reachable the same way.
# ==========================================

@export var default_locale: String = "pt_BR"

signal locale_changed(new_locale: String)

func _ready() -> void:
	set_locale(default_locale)
	print("[LOCALE] active='%s'  tr(ENZYME_HELICASE)='%s'" % [get_locale(), tr("ENZYME_HELICASE")])

# ---------- TEMPORARY DEBUG: remove once locale switching is confirmed stable ----------
# Press L to cycle en -> pt_BR -> es -> en... Lets you eyeball every locale in
# one run without editing code each time. Per this project's convention,
# debug scaffolding stays until explicitly confirmed working, then gets
# pulled — this one's a bigger candidate for removal than most, since it's
# not even print-only, it actually changes runtime state on a keypress.
const _DEBUG_LOCALES: Array[String] = ["en", "pt_BR", "es"]
var _debug_locale_index: int = 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		_debug_locale_index = (_debug_locale_index + 1) % _DEBUG_LOCALES.size()
		var code: String = _DEBUG_LOCALES[_debug_locale_index]
		set_locale(code)
		print("[LOCALE] debug-switched to '%s'  tr(ENZYME_HELICASE)='%s'  tr(ENZYME_POLYMERASE)='%s'" % [code, tr("ENZYME_HELICASE"), tr("ENZYME_POLYMERASE")])

## code is a Godot locale string matching a column header in the imported
## translation CSV — "en", "pt_BR", "es" for the current enzyme_labels.csv.
func set_locale(code: String) -> void:
	TranslationServer.set_locale(code)
	locale_changed.emit(code)

func get_locale() -> String:
	return TranslationServer.get_locale()
