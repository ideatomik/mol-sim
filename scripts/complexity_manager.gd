extends Node

# ==========================================
# COMPLEXITY MANAGER — v1
# Owns feature toggles per SKILL.md's target architecture:
#   is_enabled("feature_name") -> bool
# Scene Node, Inspector-editable, NOT an autoload yet — same pattern as
# ThemeManager/LocaleManager. Access via %ComplexityManager.
#
# Scope of this pass: the three Okazaki maturation toggles from
# OkazakiMaturationDesign.md (primase, ligase, pol1) and the "bridge toggle"
# cascade Pol I needs. Not a general ComplexityManager for every toggle in
# COMPLEXITY_MODEL.md's registry yet — grow this file as more toggles need
# the same Inspector-editable-Node treatment.
#
# ligase_enabled migration note: `simulation.gd` already owns a working
# `ligase_enabled` @export, read directly by replication_manager.gd's
# _lagging_render(). Rather than duplicate that as a second source of truth
# here (the exact "two independently-tuned numbers" trap DESIGN.md warns
# against), this manager proxies get/set to simulation.gd's existing
# property via get_parent() — ComplexityManager is instanced as a direct
# child of the simulation root, same as ThemeManager/LocaleManager. A real
# migration (moving the property here outright and updating
# replication_manager.gd's read site) is a follow-up once that file is
# next touched, not done blind in this pass.
# ==========================================

## Emitted whenever any toggle changes — including cascade-driven changes,
## so UI (ComplexitySetupPopup) can stay in sync without polling.
signal toggle_changed(feature: String, enabled: bool)

@export var primase_enabled: bool = false
@export var pol1_enabled: bool = false  # Complex tier — no implementation exists yet (see OkazakiMaturationDesign.md). Toggle-seam placeholder, shown disabled in the UI ahead of the feature.

var _sim: Node = null  # simulation.gd instance — see ligase_enabled migration note above

func _ready() -> void:
	_sim = get_parent()

func is_enabled(feature: String) -> bool:
	match feature:
		"primase":
			return primase_enabled
		"ligase":
			return _sim.ligase_enabled if _sim != null else false
		"pol1":
			return pol1_enabled
		_:
			push_warning("ComplexityManager.is_enabled(): unknown feature '%s'" % feature)
			return false

## Standard cascade direction (COMPLEXITY_MODEL.md's usual rule): a required
## dependency going away disables the dependent. Turning Primase off while
## Pol I is on force-disables Pol I too, since Pol I is structurally
## meaningless without a primer to remove (OkazakiMaturationDesign.md).
func set_primase_enabled(value: bool) -> void:
	if primase_enabled == value:
		return
	primase_enabled = value
	print("[COMPLEXITY] primase_enabled = %s" % value)
	toggle_changed.emit("primase", value)
	if not value and pol1_enabled:
		set_pol1_enabled(false)

## Same standard direction as primase above, for the ligase side of the pair.
func set_ligase_enabled(value: bool) -> void:
	if _sim == null or _sim.ligase_enabled == value:
		return
	_sim.ligase_enabled = value
	print("[COMPLEXITY] ligase_enabled = %s" % value)
	toggle_changed.emit("ligase", value)
	if not value and pol1_enabled:
		set_pol1_enabled(false)

## "Bridge toggle" cascade (OkazakiMaturationDesign.md's Cascade logic — a
## deliberate exception to the usual "child doesn't auto-enable parent"
## rule): Pol I is meaningless without both siblings active at once, so
## turning it ON force-enables Primase and Ligase rather than requiring
## them first. This is the FIRST concrete case of this pattern in the
## project — COMPLEXITY_MODEL.md's Cascading UI behavior section should
## eventually name it explicitly (see the design doc's open questions)
## rather than each future bridge toggle (e.g. clamp loader / clamps)
## re-deriving the shape ad hoc.
func set_pol1_enabled(value: bool) -> void:
	if pol1_enabled == value:
		return
	pol1_enabled = value
	print("[COMPLEXITY] pol1_enabled = %s" % value)
	if value:
		if not primase_enabled:
			set_primase_enabled(true)
		if _sim != null and not _sim.ligase_enabled:
			set_ligase_enabled(true)
	toggle_changed.emit("pol1", value)
