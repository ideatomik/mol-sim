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

## code is a Godot locale string matching a column header in the imported
## translation CSV — "en", "pt_BR", "es" for the current enzyme_labels.csv.
func set_locale(code: String) -> void:
	TranslationServer.set_locale(code)
	locale_changed.emit(code)

func get_locale() -> String:
	return TranslationServer.get_locale()
