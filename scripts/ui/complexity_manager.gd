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

## Emitted whenever topology_mode changes. Separate from toggle_changed
## since this is a mode, not a bool feature — COMPLEXITY_MODEL.md's "topology
## is the spine" principle gets its own signal rather than being shoehorned
## into the String-keyed toggle channel.
signal topology_changed(mode: int)

## COMPLEXITY_MODEL.md's topology spine: a molecule can't be simultaneously
## circular (forks meet, no ends) and linear (has ends requiring telomere
## maintenance). CIRCULAR is the default — matches the E. coli model the sim
## already runs today, so nothing changes for existing scenes until someone
## actively switches modes.
enum Topology { CIRCULAR, LINEAR }

@export var topology_mode: Topology = Topology.CIRCULAR
@export var primase_enabled: bool = false
## Cross-cutting lens (ATPCycleDesign.md), NOT a node in the enzyme tree —
## it lights up whichever enzymes actually run on ATP, wherever they are.
##
## Deliberately a real @export here rather than a ThemeManager field, which
## is where wobble_enabled (the other shipped cross-cutting lens) lives. That
## precedent predates this file, and ATPCycleDesign.md followed it out of
## habit. It does not survive contact with the cascade below: the popup keeps
## its checkboxes in sync ONLY through toggle_changed, and reverts on Cancel
## ONLY by replaying setters that live here. A toggle outside this file would
## show a stale checkbox the first time its parent re-asserted it, and would
## silently fail to revert. The tuning VALUES (bead size, spark radius, fade)
## stay in ThemeManager's "ATP Cycle" group, where visual constants belong.
@export var cofactor_activation_enabled: bool = false
@export var cofactor_byproducts_visible: bool = true
@export var pol1_enabled: bool = false  # Complex tier — implemented (pol1.gd, wired into replication_manager.gd's bridge-toggle cascade). Comment was stale; correcting per ground-truth read during the topology_mode pass.

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
		"lagging_gap":
			# Mode-gate, not a plain proxy: lagging_gap_enabled is only ever
			# meaningful in Linear mode (COMPLEXITY_MODEL.md's topology
			# spine — a circular chromosome has no ends for the
			# end-replication problem to apply to). Folding the mode check
			# in here means every caller (replication_manager.gd's discard
			# trigger, primase's gap-avoidance check, scrub_rebuild) only
			# ever needs is_enabled("lagging_gap") and never has to know
			# topology_mode exists at all.
			return topology_mode == Topology.LINEAR and (_sim.lagging_gap_enabled if _sim != null else false)
		"cofactor":
			return cofactor_activation_enabled
		"ligase_cofactor":
			# NO LONGER MODE-GATED (was, through v79). Ligase has a cofactor
			# in EVERY mode now — ATP in eukaryotic, NAD+ in bacterial — so
			# this collapses to the same one-liner as helicase's own
			# is_enabled("cofactor") above. WHICH donor to draw is a
			# separate question, answered by ligase_uses_nad() below, and
			# deliberately NOT folded in here: is_enabled() answers "is the
			# lens on," and mixing a mode PARAMETER into that boolean would
			# make "false" ambiguous between "lens off" and "wrong donor for
			# this mode," which it can never be.
			return cofactor_activation_enabled
		"cofactor_byproducts":
			# Parent check folded in, same reasoning as lagging_gap's mode
			# check above: every caller asks one question and never has to
			# know the parent lens exists. Byproducts are meaningless with
			# the whole cycle switched off.
			return cofactor_activation_enabled and cofactor_byproducts_visible
		_:
			push_warning("ComplexityManager.is_enabled(): unknown feature '%s'" % feature)
			return false

## Which donor ligase reaches for — a MODE PARAMETER, not a toggle, so it
## lives outside is_enabled() entirely rather than as a third string key.
## Bacterial ligase runs on NAD+; eukaryotic ligase runs on ATP — see
## ATPCycleDesign.md's NAD+ pass. Callers ask this only once they already
## know is_enabled("ligase_cofactor") is true; it says nothing about whether
## the lens is on, only which molecule to draw if it is.
func ligase_uses_nad() -> bool:
	return topology_mode == Topology.CIRCULAR

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

## Mode-gate cascade — COMPLEXITY_MODEL.md's topology spine, applied as a
## THIRD gating pattern distinct from the parent/child and bridge-toggle
## cascades above. Switching to Circular force-disables lagging_gap_enabled,
## same "parent going away disables the dependent" direction used
## everywhere else in this file, just applied to a mode instead of a bool.
## Switching to Linear deliberately does NOT auto-enable lagging_gap_enabled
## in return — mirrors the equally-deliberate restraint in set_pol1_enabled()
## style cascades where a child never auto-enables its own parent, applied
## here as "the dependent doesn't get to ride along with the mode." Linear
## only unlocks the checkbox; turning telomerase on stays a separate,
## conscious choice.
func set_topology_mode(value: Topology) -> void:
	if topology_mode == value:
		return
	topology_mode = value
	print("[COMPLEXITY] topology_mode = %s" % Topology.keys()[value])
	topology_changed.emit(value)
	if value == Topology.CIRCULAR and _sim != null and _sim.lagging_gap_enabled:
		set_lagging_gap_enabled(false)

## Proxy setter mirroring set_ligase_enabled()'s pattern exactly —
## lagging_gap_enabled lives on simulation.gd (same "avoid two
## independently-tuned numbers" reasoning as the ligase_enabled migration
## note at the top of this file), not duplicated here as a second source
## of truth.
func set_lagging_gap_enabled(value: bool) -> void:
	if _sim == null or _sim.lagging_gap_enabled == value:
		return
	_sim.lagging_gap_enabled = value
	print("[COMPLEXITY] lagging_gap_enabled = %s" % value)
	toggle_changed.emit("lagging_gap", value)

## "Default-follows-parent, override-persists" cascade — the FOURTH named
## pattern in this file, alongside standard (parent off disables dependents),
## bridge (child on force-enables parents), and mode-gate (a mode gates which
## dependents are coherent). None of those three fits, which is why it is
## named here rather than re-derived ad hoc at the UI layer:
##
##   Enabling the parent sets cofactor_byproducts_visible true EVERY time it is
##   re-enabled. The user may then turn byproducts off freely at any point,
##   including mid-playback, without affecting the parent. Toggling the
##   parent off and on again re-asserts the default.
##
## "Re-assert on every parent enable" was chosen over "set once, remember the
## user's override forever" deliberately — the byproducts default is a live
## rule about what turning the lens on should show you, not a first-run
## convenience. Add this to COMPLEXITY_MODEL.md's Cascading UI behavior
## section as a registered pattern.
##
## Note the parent going OFF does NOT force the child false. There is nothing
## to hide once the whole cycle is invisible, and clearing it would destroy
## the override the user just expressed — the "override-persists" half.
func set_cofactor_activation_enabled(value: bool) -> void:
	if cofactor_activation_enabled == value:
		return
	cofactor_activation_enabled = value
	print("[COMPLEXITY] cofactor_activation_enabled = %s" % value)
	toggle_changed.emit("cofactor", value)
	if value and not cofactor_byproducts_visible:
		set_cofactor_byproducts_visible(true)

func set_cofactor_byproducts_visible(value: bool) -> void:
	if cofactor_byproducts_visible == value:
		return
	cofactor_byproducts_visible = value
	print("[COMPLEXITY] cofactor_byproducts_visible = %s" % value)
	toggle_changed.emit("cofactor_byproducts", value)
