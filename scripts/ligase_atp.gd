class_name LigaseAtp
extends Node2D

# ==========================================
# ligase_atp.gd — the ligase half of the cofactor-activation lens
# (ATPCycleDesign.md). Companion to atp_cycle.gd, which does the helicase.
#
# DELIBERATELY TWEEN-DRIVEN, AND THAT IS NOT AN INCONSISTENCY.
# atp_cycle.gd is a pure function of (slot_index, step_t) because the helicase
# must reconstruct instantly for an arbitrary scrub target. Ligase inherits a
# different contract: ligase.gd's own header states the node is HIDDEN
# ENTIRELY during scrub, because there is no "the enzyme is mid-travel" state
# to reproduce. Its ATP visual inherits that exemption, so real tween timing
# is legitimate here. Recorded as a deliberate asymmetry between the two
# halves of one lens, not an oversight.
#
# THIS ANSWERS THE QUESTION THE LENS WAS BUILT TO ASK. The design chose these
# two enzymes together because helicase is CLOCK-DRIVEN (autonomous, per-step)
# and ligase is EVENT-COUNT-GATED (fires on fragment seal), and
# NaKPumpSpikeDesign.md had flagged unifying those two triggers as an open
# question. Built out, they did NOT want to be one thing: the two halves share
# the glyph vocabulary, the ThemeManager identity group and the toggle, and
# share no timing machinery whatsoever. See this file's As-Built note in
# ATPCycleDesign.md — "one lens, two mechanisms" is the answer, and it is a
# better one than forcing a single mechanism would have been.
#
# CHILD OF THE LIGASE NODE, which buys three behaviors for free and is the
# reason no lifecycle code appears in this file:
#   - ligase.visible = false in _ligase_reset_visual() hides this too
#   - _lagging_fade_enzyme_scene()'s modulate fade reaches these beads
#   - _ligase_park_offstage() carries them along
# All local space. Legitimate here, unlike the helicase case, because ligase
# is STATIONARY for the entire ATP sequence — it only moves during TRAVELING,
# and every step below happens at or after the TRAVELING->HOLDING boundary.
#
# READS THEMEMANAGER, unlike atp_cycle.gd. Epitaxial: this node's substrate is
# ligase.gd, which reaches for %ThemeManager through _sim. atp_cycle.gd's
# substrate is helicase_ring.gd, which holds no external references at all.
# Same value, two delivery mechanisms, each matching its own substrate.
#
# BIOLOGY. Ligase cleaves between the ALPHA and BETA phosphates, releasing
# PPi (two phosphates, fused) and leaving AMP covalently bound to the enzyme.
# The AMP then transfers onto the nick's 5' end (adenylylation), and only
# releases once the 3'-OH attacks and the bond seals. That is why ligase
# CARRIES its byproduct while helicase discards both immediately — a real
# mechanistic difference, not variety for its own sake.
#
# EUKARYOTIC MODE ONLY. Bacterial ligase runs on NAD+, which is not "ATP with
# a different name": only one half is adenine-based, and its byproduct NMN is
# structurally unrelated to any phosphate-chain shape. Reusing this glyph for
# it would actively teach something false. The gate lives in
# complexity_manager.gd's is_enabled("atp_ligase"), folded in with the
# topology check so no caller here needs to know topology exists.
# ==========================================

# Bead roles are fixed for the lifetime of the node — unlike atp_cycle.gd's
# per-frame reassignment, because here the clusters are real sub-nodes that
# tween independently rather than pooled slots.
#   AMP group: adenine + alpha phosphate   (carried, then hopped, then waste)
#   PPi group: beta + gamma phosphates     (fused, discarded at cleave)
var _sim: Node = null
var _tm: Node = null

var _amp_group: Node2D = null
var _ppi_group: Node2D = null
var _bridge_link: Line2D = null   # the alpha-beta bond: the one that breaks
## TWO tweens, not one. The PPi drift and the AMP hop overlap whenever
## atp_fade_duration is tuned longer than ligase_hold_duration — and a single
## shared tween would mean hop() kills the PPi fade mid-flight, freezing it
## half-transparent on screen until the next reset. A tuning trap, not a
## saving. They are independent motions of independent objects; they get
## independent tweens.
var _ppi_tween: Tween = null
var _amp_tween: Tween = null

var _spark_t: float = 0.0
var _spark_active: bool = false

## Written by replication_manager.gd at each kick, from
## is_enabled("atp_byproducts"). Mechanism-vs-waste boundary: this hides PPi
## and the RELEASED AMP. The CARRIED AMP and the hop itself are mechanism —
## hiding those would hide HOW ligase seals rather than tidying away a
## discarded molecule, which is the opposite of what a decluttering toggle is
## for.
var byproducts_visible: bool = true

func setup(sim: Node) -> void:
	_sim = sim
	_tm = sim.get_node("%ThemeManager")
	_build()
	reset()

func _build() -> void:
	var tm := _tm
	var adenine_r: float = tm.base_radius * tm.atp_adenine_scale
	var bead_r: float = tm.atp_bead_size
	var spacing: float = tm.atp_bead_spacing

	_amp_group = Node2D.new()
	add_child(_amp_group)
	_ppi_group = Node2D.new()
	add_child(_ppi_group)

	# --- the alpha-beta bond, drawn by the PARENT because it is the one link
	# that spans the two clusters. Hiding it IS the cleave.
	_bridge_link = Line2D.new()
	_bridge_link.width = tm.atp_link_width
	_bridge_link.default_color = tm.atp_link_color
	_bridge_link.antialiased = true
	add_child(_bridge_link)

	# --- AMP: adenine + alpha phosphate, joined by an ordinary link
	var amp_link := Line2D.new()
	amp_link.width = tm.atp_link_width
	amp_link.default_color = tm.atp_link_color
	amp_link.antialiased = true
	amp_link.points = PackedVector2Array([Vector2.ZERO, Vector2(spacing, 0.0)])
	_amp_group.add_child(amp_link)
	_add_bead(_amp_group, Vector2.ZERO, adenine_r, tm.base_color_a, "A")
	_add_bead(_amp_group, Vector2(spacing, 0.0), bead_r, tm.atp_bead_color, "P")

	# --- PPi: two phosphates FUSED, drifting as ONE rigid unit. The connector
	# is visibly thicker than the ordinary links above, per this project's
	# "shape and thickness first, never colour alone" accessibility rule. PPi
	# must never read as two loose phosphates that happen to be adjacent —
	# that ambiguity is exactly what separates it from helicase's single Pi.
	# This is the only genuinely new geometry in the whole design, and it has
	# no primitive to build on: procedural_shape_utils.gd provides octagon()
	# and round_corners() only.
	var ppi_link := Line2D.new()
	ppi_link.width = tm.atp_fused_link_width
	ppi_link.default_color = tm.atp_fused_link_color
	ppi_link.antialiased = true
	ppi_link.points = PackedVector2Array([Vector2.ZERO, Vector2(spacing, 0.0)])
	_ppi_group.add_child(ppi_link)
	_add_bead(_ppi_group, Vector2.ZERO, bead_r, tm.atp_bead_color, "P")
	_add_bead(_ppi_group, Vector2(spacing, 0.0), bead_r, tm.atp_bead_color, "P")

func _add_bead(parent: Node2D, pos: Vector2, radius: float, fill: Color, text: String) -> void:
	var bead := AtpBead.new()
	parent.add_child(bead)
	bead.position = pos
	bead.set_label_style(_tm.atp_label_font_size, _tm.atp_label_color, _tm.atp_label_font)
	bead.set_label_rotation(_zoom_label_rotation())
	bead.configure(radius, fill, text)

## Asked of ZoomManager through _sim — the same reach ligase.gd itself makes,
## rather than the pushed-property contract atp_cycle.gd uses. Epitaxial
## again: each file inherits its own substrate's convention. The "A"/"P" bead
## glyphs are drawn text and ship sideways in vertical mode without this.
func _zoom_label_rotation() -> float:
	if _sim == null:
		return 0.0
	var zm = _sim.get_node_or_null("%ZoomManager")
	return zm.get_label_counter_rotation() if zm != null else 0.0

# ==========================================
# PUBLIC — one call per hook point in replication_manager.gd's tween chain
# ==========================================

## Called from _ligase_kick(), as the travel tween starts. The whole,
## uncleaved ATP rides in with the enzyme.
func begin_carry() -> void:
	_kill_tweens()
	_spark_active = false
	var spacing: float = _tm.atp_bead_spacing
	var carry: Vector2 = _tm.ligase_atp_carry_offset
	_amp_group.position = carry
	_amp_group.modulate.a = 1.0
	_amp_group.visible = true
	_ppi_group.position = carry + Vector2(spacing * 2.0, 0.0)
	_ppi_group.modulate.a = 1.0
	_ppi_group.visible = true
	_bridge_link.points = PackedVector2Array([
		carry + Vector2(spacing, 0.0),
		carry + Vector2(spacing * 2.0, 0.0),
	])
	_bridge_link.visible = true
	visible = true
	queue_redraw()

## Called at the TRAVELING -> HOLDING boundary. The cofactor activates only
## once the enzyme has actually engaged the nick; firing mid-travel would
## misrepresent what triggers cleavage. Mirrors helicase's "cleave at arrival."
##
## HOLDING has room for this: at 0.5s it is the longest of the three phases
## (travel 0.4, seal 0.3) and it exists SPECIFICALLY for visibility — it was
## added because the seal happened too fast to see the nick. Hosting
## spark -> PPi-drift-and-fade inside it fits that original intent rather than
## fighting it.
func cleave() -> void:
	_kill_ppi_tween()
	_bridge_link.visible = false
	_ppi_group.visible = byproducts_visible
	_spark_active = true
	_spark_t = 0.0

	_ppi_tween = create_tween()
	_ppi_tween.set_parallel(true)
	_ppi_tween.tween_method(_set_spark_t, 0.0, 1.0, _tm.atp_spark_duration)
	if byproducts_visible:
		_ppi_tween.tween_property(_ppi_group, "position",
			_ppi_group.position + _tm.atp_discard_drift, _tm.atp_fade_duration)
		_ppi_tween.tween_property(_ppi_group, "modulate:a", 0.0, _tm.atp_fade_duration)

## Called between the seal pulse's two halves — so it runs in parallel with
## the RELEASE half, not the pinch. Reads as: the pinch clamps tight, then the
## enzyme visibly hands off what it was carrying as it lets go. Duration is
## its own field, sized shorter than the 0.15s release half so it lands with a
## beat to spare rather than racing the pulse.
##
## Always visible regardless of byproducts_visible: adenylylation is
## MECHANISM. AMP only becomes waste at release.
func hop() -> void:
	_kill_amp_tween()
	_amp_group.visible = true
	_amp_group.modulate.a = 1.0
	_amp_tween = create_tween()
	_amp_tween.tween_property(_amp_group, "position", _tm.ligase_atp_nick_offset, _tm.ligase_amp_hop_duration)
	queue_redraw()

## Called from _ligase_finish_seal(). The 3'-OH has attacked, the bond is
## sealed, and the AMP that was mechanism a moment ago is now waste — which is
## the exact moment it comes under the byproducts toggle.
func release() -> void:
	_kill_amp_tween()
	if not byproducts_visible:
		_amp_group.visible = false
		queue_redraw()
		return
	_amp_tween = create_tween()
	_amp_tween.set_parallel(true)
	_amp_tween.tween_property(_amp_group, "position",
		_amp_group.position + _tm.atp_discard_drift, _tm.atp_fade_duration)
	_amp_tween.tween_property(_amp_group, "modulate:a", 0.0, _tm.atp_fade_duration)

## Called from _ligase_reset_visual(), which already fires on scrub, on the
## ligase toggle going off mid-travel, and on reload. Everything hard-resets;
## nothing here needs to reconstruct a partial state, because scrub never
## shows one.
func reset() -> void:
	_kill_tweens()
	_spark_active = false
	_spark_t = 0.0
	if _amp_group != null:
		_amp_group.visible = false
		_amp_group.modulate.a = 1.0
	if _ppi_group != null:
		_ppi_group.visible = false
		_ppi_group.modulate.a = 1.0
	if _bridge_link != null:
		_bridge_link.visible = false
	queue_redraw()

# ==========================================
# INTERNAL
# ==========================================

func _kill_ppi_tween() -> void:
	if _ppi_tween != null and _ppi_tween.is_valid():
		_ppi_tween.kill()
	_ppi_tween = null

func _kill_amp_tween() -> void:
	if _amp_tween != null and _amp_tween.is_valid():
		_amp_tween.kill()
	_amp_tween = null

func _kill_tweens() -> void:
	_kill_ppi_tween()
	_kill_amp_tween()

func _set_spark_t(t: float) -> void:
	_spark_t = t
	if t >= 1.0:
		_spark_active = false
	queue_redraw()

func _draw() -> void:
	if not _spark_active or _tm == null:
		return
	var c: Color = _tm.atp_spark_color
	c.a = c.a * (1.0 - _spark_t)
	# Expanding ring, not a filled disc — a disc would occlude the AMP it is
	# meant to be cleaving away from. Same treatment as atp_cycle.gd's spark,
	# centred on the carry point rather than on the enzyme origin.
	var centre: Vector2 = _tm.ligase_atp_carry_offset + Vector2(_tm.atp_bead_spacing * 1.5, 0.0)
	draw_circle(centre, lerp(_tm.atp_spark_radius * 0.35, _tm.atp_spark_radius, _spark_t), c, false, _tm.atp_spark_width, true)
