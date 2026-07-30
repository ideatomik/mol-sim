class_name LigaseCofactor
extends Node2D

# ==========================================
# ligase_cofactor.gd — the ligase half of the cofactor-activation lens
# (ATPCycleDesign.md). Companion to helicase_atp_cycle.gd, which does the helicase.
#
# DELIBERATELY TWEEN-DRIVEN, AND THAT IS NOT AN INCONSISTENCY.
# helicase_atp_cycle.gd is a pure function of (slot_index, step_t) because the helicase
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
# READS THEMEMANAGER, unlike helicase_atp_cycle.gd. Epitaxial: this node's substrate is
# ligase.gd, which reaches for %ThemeManager through _sim. helicase_atp_cycle.gd's
# substrate is helicase_ring.gd, which holds no external references at all.
# Same value, two delivery mechanisms, each matching its own substrate.
#
# BIOLOGY. Ligase cleaves between the ALPHA and BETA phosphates (or the
# alpha-P-nicotinamide bond, for NAD+), releasing a two-bead leaving group and
# leaving AMP covalently bound to the enzyme. The AMP then transfers onto the
# nick's 5' end (adenylylation), and only releases once the 3'-OH attacks and
# the bond seals. That is why ligase CARRIES its byproduct while helicase
# discards both immediately — a real mechanistic difference, not variety for
# its own sake.
#
# BOTH DONORS, SINCE THE NAD+ PASS. Bacterial ligase runs on NAD+, eukaryotic
# on ATP — NAD+ is not "ATP with a different name" (only one half is
# adenine-based) but the two ARE structurally parallel: same four-bead chain,
# cleaved at the same relative position, only the terminal bead differs
# (nicotinamide instead of a third phosphate). See ATPCycleDesign.md's NAD+
# pass for the full table. Consequence: the AMP half below is entirely
# donor-independent and untouched by this pass; only the leaving group's
# SECOND bead and its link (_apply_donor(), below) depend on donor_is_nad,
# which replication_manager.gd sets from ComplexityManager.ligase_uses_nad()
# before every begin_carry(). is_enabled("ligase_cofactor") itself no longer
# gates on topology at all — see complexity_manager.gd's own note on why a
# mode PARAMETER doesn't belong inside that boolean.
# ==========================================

# Bead roles are fixed for the lifetime of the node — unlike helicase_atp_cycle.gd's
# per-frame reassignment, because here the clusters are real sub-nodes that
# tween independently rather than pooled slots. "Fixed" means fixed WITHIN a
# run; the leaving group's second bead is re-styled by _apply_donor() at each
# begin_carry(), since the topology toggle can change between runs.
#   AMP group:     adenine + alpha phosphate   (carried, then hopped, then waste)
#   Leaving group: beta phosphate + [beta phosphate | nicotinamide]
#                  ATP  -> PPi, fused, discarded at cleave
#                  NAD+ -> NMN, ordinary link, discarded at cleave
var _sim: Node = null
var _tm: Node = null

var _amp_group: Node2D = null
var _leaving_group: Node2D = null
## The SECOND leaving-group bead and its connecting link are the only two
## nodes whose identity depends on the donor (ATP -> phosphate + PPi's thick
## fused link; NAD+ -> nicotinamide + an ordinary link). Kept as direct
## references, reconfigured once per begin_carry() rather than rebuilt, since
## "bead roles are fixed for the lifetime of the node" (this file's own
## header) only ever meant fixed WITHIN a run — donor mode can still change
## between runs via the topology toggle.
var _leaving_bead_b: CofactorBead = null
var _leaving_link: Line2D = null
var _bridge_link: Line2D = null   # the alpha-beta bond: the one that breaks
## TWO tweens, not one. The PPi drift and the AMP hop overlap whenever
## cofactor_fade_duration is tuned longer than ligase_hold_duration — and a single
## shared tween would mean hop() kills the PPi fade mid-flight, freezing it
## half-transparent on screen until the next reset. A tuning trap, not a
## saving. They are independent motions of independent objects; they get
## independent tweens.
var _ppi_tween: Tween = null
var _amp_tween: Tween = null

var _spark_t: float = 0.0
var _spark_active: bool = false

## Written by replication_manager.gd at each kick, from
## is_enabled("cofactor_byproducts"). Mechanism-vs-waste boundary: this hides PPi
## and the RELEASED AMP. The CARRIED AMP and the hop itself are mechanism —
## hiding those would hide HOW ligase seals rather than tidying away a
## discarded molecule, which is the opposite of what a decluttering toggle is
## for.
var byproducts_visible: bool = true

## Which donor to draw — read from ComplexityManager.ligase_uses_nad() by
## replication_manager.gd and written here BEFORE begin_carry() is called
## each kick, since the topology toggle can change between one seal and the
## next. A mode parameter, not a toggle of this node's own: see
## complexity_manager.gd's ligase_uses_nad() for why it lives outside
## is_enabled() entirely.
var donor_is_nad: bool = false

## Reconfigures the leaving-group's second bead and its connecting link for
## the current donor_is_nad. Idempotent — safe to call every begin_carry()
## even when the mode hasn't changed since the last one; CofactorBead.configure()
## and Line2D property writes are both cheap no-ops when the values already
## match.
##
##   ATP  -> second bead "P" (cofactor_bead_color), thick FUSED link (PPi:
##           two phosphates that must never read as two loose Pi).
##   NAD+ -> second bead "N" (cofactor_nicotinamide_color), ordinary link
##           (NMN: already two DIFFERENT beads by colour — ordinary width
##           carries the meaning; thick width would falsely claim a "rigid
##           fused unit" NMN doesn't have).
func _apply_donor() -> void:
	if _leaving_bead_b == null or _leaving_link == null or _tm == null:
		return
	var tm := _tm
	var bead_r: float = tm.cofactor_bead_size
	if donor_is_nad:
		_leaving_bead_b.configure(bead_r, tm.cofactor_nicotinamide_color, "N")
		_leaving_link.width = tm.cofactor_link_width
		_leaving_link.default_color = tm.cofactor_link_color
	else:
		_leaving_bead_b.configure(bead_r, tm.cofactor_bead_color, "P")
		_leaving_link.width = tm.cofactor_fused_link_width
		_leaving_link.default_color = tm.cofactor_fused_link_color

func setup(sim: Node) -> void:
	_sim = sim
	_tm = sim.get_node("%ThemeManager")
	_build()
	reset()

func _build() -> void:
	var tm := _tm
	var adenine_r: float = tm.base_radius * tm.cofactor_head_scale
	var bead_r: float = tm.cofactor_bead_size
	var spacing: float = tm.cofactor_bead_spacing

	_amp_group = Node2D.new()
	add_child(_amp_group)
	_leaving_group = Node2D.new()
	add_child(_leaving_group)

	# --- the alpha-beta bond, drawn by the PARENT because it is the one link
	# that spans the two clusters. Hiding it IS the cleave. Built here as an
	# empty Line2D — its points are set in begin_carry(), since it needs the
	# groups' CURRENT positions rather than their local layout, and it is
	# rebuilt (not just re-shown) every carry rather than being static.
	_bridge_link = Line2D.new()
	_bridge_link.width = tm.cofactor_link_width
	_bridge_link.default_color = tm.cofactor_link_color
	_bridge_link.antialiased = true
	_bridge_link.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_bridge_link.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_bridge_link)

	# --- AMP: adenine + alpha phosphate, joined by an ordinary link. Points
	# inset to bead EDGES (ProceduralShapeUtils.inset_segment) with rounded
	# caps, same treatment as helicase_atp_cycle.gd's bonds — set once here
	# and never touched again, since the two beads' LOCAL offsets within this
	# group never change; only the whole group's position (carry/hop/drift)
	# does, and Line2D points stay correct under a parent transform for free.
	var amp_link := Line2D.new()
	amp_link.width = tm.cofactor_link_width
	amp_link.default_color = tm.cofactor_link_color
	amp_link.antialiased = true
	amp_link.begin_cap_mode = Line2D.LINE_CAP_ROUND
	amp_link.end_cap_mode = Line2D.LINE_CAP_ROUND
	amp_link.points = ProceduralShapeUtils.inset_segment(Vector2.ZERO, Vector2(spacing, 0.0), adenine_r, bead_r)
	_amp_group.add_child(amp_link)
	_add_bead(_amp_group, Vector2.ZERO, adenine_r, tm.base_color_a, "A")
	_add_bead(_amp_group, Vector2(spacing, 0.0), bead_r, tm.cofactor_bead_color, "P")

	# --- The leaving group's SHARED bead (always a phosphate, both donors)
	# and its position-fixed link. Geometry (inset points, cap mode) never
	# changes by donor — only the SECOND bead's glyph and the link's
	# thickness/colour do, and those are set by _apply_donor() below, not
	# here. See that function's header for why: PPi (ATP's byproduct) is two
	# phosphates FUSED, needing a visibly thicker connector so it never reads
	# as two loose Pi; NMN (NAD+'s byproduct) is already two DIFFERENT beads
	# by colour, so the same thick treatment would falsely claim the same
	# "rigid fused unit" NMN doesn't have.
	_leaving_link = Line2D.new()
	_leaving_link.antialiased = true
	_leaving_link.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_leaving_link.end_cap_mode = Line2D.LINE_CAP_ROUND
	_leaving_link.points = ProceduralShapeUtils.inset_segment(Vector2.ZERO, Vector2(spacing, 0.0), bead_r, bead_r)
	_leaving_group.add_child(_leaving_link)
	_add_bead(_leaving_group, Vector2.ZERO, bead_r, tm.cofactor_bead_color, "P")
	_leaving_bead_b = _add_bead(_leaving_group, Vector2(spacing, 0.0), bead_r, tm.cofactor_bead_color, "P")

	_apply_donor()  # initial glyph — matches whatever topology_mode is at build time

func _add_bead(parent: Node2D, pos: Vector2, radius: float, fill: Color, text: String) -> CofactorBead:
	var bead := CofactorBead.new()
	parent.add_child(bead)
	bead.position = pos
	bead.set_label_style(_tm.cofactor_label_font_size, _tm.cofactor_label_color, _tm.cofactor_label_font)
	bead.set_label_rotation(_zoom_label_rotation())
	bead.configure(radius, fill, text)
	return bead

## Asked of ZoomManager through _sim — the same reach ligase.gd itself makes,
## rather than the pushed-property contract helicase_atp_cycle.gd uses. Epitaxial
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
	_apply_donor()
	var spacing: float = _tm.cofactor_bead_spacing
	var bead_r: float = _tm.cofactor_bead_size
	var carry: Vector2 = _tm.ligase_cofactor_carry_offset
	_amp_group.position = carry
	_amp_group.modulate.a = 1.0
	_amp_group.visible = true
	_leaving_group.position = carry + Vector2(spacing * 2.0, 0.0)
	_leaving_group.modulate.a = 1.0
	_leaving_group.visible = true
	# Inset to bead edges like every other bond in this glyph — the bridge is
	# the one bond spanning two independently-moving groups, but the endpoints
	# are still just two bead centers with bead_r radii, same helper call.
	_bridge_link.points = ProceduralShapeUtils.inset_segment(
		carry + Vector2(spacing, 0.0),
		carry + Vector2(spacing * 2.0, 0.0),
		bead_r, bead_r
	)
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
	_leaving_group.visible = byproducts_visible
	_spark_active = true
	_spark_t = 0.0

	_ppi_tween = create_tween()
	_ppi_tween.set_parallel(true)
	_ppi_tween.tween_method(_set_spark_t, 0.0, 1.0, _tm.cofactor_spark_duration)
	if byproducts_visible:
		_ppi_tween.tween_property(_leaving_group, "position",
			_leaving_group.position + _tm.cofactor_discard_drift, _tm.cofactor_fade_duration)
		_ppi_tween.tween_property(_leaving_group, "modulate:a", 0.0, _tm.cofactor_fade_duration)

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
	_amp_tween.tween_property(_amp_group, "position", _tm.ligase_cofactor_nick_offset, _tm.ligase_amp_hop_duration)
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
		_amp_group.position + _tm.cofactor_discard_drift, _tm.cofactor_fade_duration)
	_amp_tween.tween_property(_amp_group, "modulate:a", 0.0, _tm.cofactor_fade_duration)

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
	if _leaving_group != null:
		_leaving_group.visible = false
		_leaving_group.modulate.a = 1.0
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
	var c: Color = _tm.cofactor_spark_color
	c.a = c.a * (1.0 - _spark_t)
	# Expanding ring, not a filled disc — a disc would occlude the AMP it is
	# meant to be cleaving away from. Same treatment as helicase_atp_cycle.gd's spark,
	# centred on the carry point rather than on the enzyme origin.
	var centre: Vector2 = _tm.ligase_cofactor_carry_offset + Vector2(_tm.cofactor_bead_spacing * 1.5, 0.0)
	draw_circle(centre, lerp(_tm.cofactor_spark_radius * 0.35, _tm.cofactor_spark_radius, _spark_t), c, false, _tm.cofactor_spark_width, true)
