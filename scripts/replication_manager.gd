extends Node

# ==========================================
# replication_manager.gd
# v70.5.6: synthesis_circle -> lagging_polymerase, top_polymerase -> leading_polymerase
# (naming clarity pass). Polymerase y-positions now sit exactly on their
# template strand's bonded row (template_strand_y for lagging,
# template_strand_y - dna_ribbons_gap for leading) instead of the
# polymerase_y_lagging/polymerase_y_leading offsets, so each polymerase visually
# aligns with the row of bases it's synthesizing alongside.
#
# v70.5.5: Self-containment refactor (no behavior change). All leading-strand
# logic is grouped into clearly-named _leading_* functions
# (_leading_reset, _leading_setup_backbones, _leading_teardown,
# _leading_scrub_rebuild, _leading_render), called from the public lifecycle/
# update/render/scrub functions, which are thin dispatchers. This mirrors
# the structure the lagging strand will use, so future Okazaki-fragment work
# only touches _lagging_* functions without threading more conditionals into
# leading-strand code. Public API (initialize, reset, setup_backbones,
# teardown, update, render, scrub_rebuild, resume_enzymes, run_intro,
# get_sequence_rich_text, manual_override) is unchanged.
#
# v71: added a third self-contained section, _capture_* — the same pattern
# extended to the nucleotide-capture animation, which neither the leading nor
# lagging section owns on its own. _leading_update() (the old per-frame
# position-poll spawn trigger) was removed in this pass; leading spawning is
# now event-driven via _capture_on_leading_slot_reached(), same trigger model
# lagging's _lagging_fire_step() already used. See the CAPTURE section banner
# comment further down for the full design rationale.
#
# Also removed in v70.5.5: a dead `lagging_synth_count` computation in the
# old scrub_rebuild() that was computed but never used (leftover from the
# pre-removal lagging strand).
#
# Phase 1 + Phase 2 complete: owns all synthesis state, spawning, synthesis
# rendering, and enzyme animation. simulation.gd calls update(delta, ctx) each
# frame and scrub_rebuild(ctx) on scrub. Nodes are added as children of sim
# (simulation.gd) so the scene tree shape is unchanged.
# v70.6: factory_x/factory_y renamed to polymerase_x/polymerase_y_lagging;
# new_bottom_template_offset renamed to polymerase_y_offset; gap_width replaced
# by polymerase_x_offset_slots * nucleotide_slot_spacing. Both polymerases are
# now positioned purely as offsets from helicase_node.position (single source
# of truth for replisome positioning), owned in simulation.gd.
# Lagging strand (Okazaki fragments, trombone loop) removed; clean slate for rebuild.
# ==========================================

# ---------- PARENT REFERENCE ----------
var sim: Node = null  # Set by initialize(). Used for add_child(), geometry, etc.
var tm: Node = null   # ThemeManager reference, cached in initialize()
var zoom_mgr: Node = null  # ZoomManager reference, cached in initialize()
## MoleculeStructureRenderer reference (Growth Session 2), pushed in by
## simulation.gd — used only to poll is_slot_active() live each frame for
## bug-A occlusion suppression. Never reached into for anything else,
## preserving "no script reaches into another script's owned visual nodes."
var molecule_renderer: Node = null

func set_molecule_renderer(renderer: Node) -> void:
	molecule_renderer = renderer
# LongSequenceDesign.md follow-up — scrub index when each clamp's current
# drag gesture began. Kept separate per clamp (only one is realistically
# ever mid-drag at once, but no reason to share state that doesn't need to be).
var _leading_drag_start_index: int = 0
var _lagging_drag_start_index: int = 0

# ---------- PER-SLOT STATE ARRAYS ----------
var nucleotide_backbone_delta: Array[float] = []

# ---------- SYNTHESIS STATE ----------
var manual_override: bool = true

# ---------- SYNTHESIZED DATA (Lagging Strand) ----------
var lagging_fragments: Array = []          # completed fragments
var lagging_current_fragment = null        # Dictionary or null — fragment in progress
var lagging_telomere_gap = null      # {start, end, length} of unsynthesized real slots at the strand's end, or null
var lagging_backbone_line: Line2D = null
var lagging_bond_marks: Array[Node2D] = []
var lagging_synthesized_bases: Array = []
var lagging_hydrogen_bonds: Array = []
var connected_helicase_mgr: Node = null  # cached for Phase enum access in the phase_changed handler

var lagging_total_fragments: int = 0     # floor(num_slots / okazaki_fragment_size) — hard safety cap, prevents ever firing an out-of-range slot
var lagging_firing_started: bool = false # true once the one-time startup delay has passed
var lagging_fade_in_started: bool = false # true once the proximity-based fade-in has been triggered (see update())
var lagging_total_consumed: int = 0      # total slots actually fired so far
var lagging_batch_cursor: int = 0        # next slot index to fire within the currently-open fragment (counts down)
var lagging_polymerase_x: float = 0.0    # independent position of the lagging polymerase visual — no longer helicase-relative
var lagging_catchup_timer: Timer = null


# ---------- CACHED CONTEXT (updated each frame in update()) ----------
var ctx_polymerase_x: float = 0.0
var ctx_helicase_x: float = 0.0
var ctx_center_y: float = 0.0
var ctx_template_strand_y: float = 0.0
var ctx_polymerase_y_lagging: float = 0.0
var ctx_polymerase_y_leading: float = 0.0
var ctx_dna_ribbons_gap: float = 0.0
var ctx_polymerase_y_offset: float = 0.0
var ctx_wobble_t: float = 0.0
var ctx_phase: int = 0
var ctx_num_slots: int = 0
var ctx_nucleotide_original_x: Array = []


# ---------- SYNTHESIZED DATA (Leading Strand) ----------
var leading_synthesized_bases: Array = []
var leading_hydrogen_bonds: Array = []
var leading_backbone_line: Line2D = null
var leading_strand_bond_marks: Array[Node2D] = []
var leading_polymerase: Node2D = null  # renamed from top_polymerase
var leading_fade_in_started: bool = false # true once the proximity-based fade-in has been triggered (see update())
var lagging_polymerase: Node2D = null  # renamed from synthesis_circle — reference to scene node, set in initialize()
var lagging_polymerase_faded: bool = false  # renamed from synthesis_circle_faded
# Set when the strand itself is fully consumed but ligase/Pol I still have
# pending trailing work (a queued job, or mid-travel/seal) — the scene-wide
# fade used to fire the instant total_consumed reached num_slots regardless
# of whether trailing enzymes had caught up, which meant the LAST valid
# fragment's own seal (gated behind Pol I's fragment-lag removal, itself
# gated behind the very last fragment closing) routinely happened AFTER the
# fade had already hidden everything — functionally correct, invisibly so.
# See _lagging_enzymes_settled()/_lagging_try_deferred_fade().
var _lagging_fade_pending: bool = false
## Gap mode only — set once when the terminal primer removal is kicked off at
## strand completion, so the removal (and gap recording) fires exactly once
## even though catch-up completion can be re-entered via the deferred-fade path.
var _terminal_removal_started: bool = false
## Set once when both polymerases start their end-of-run slide to the shared
## rest spot, so the move fires exactly once per run (catch-up completion can
## be reached more than once via the settle/deferred-fade paths).
var _polymerases_at_rest: bool = false
const LEADING_POLYMERASE_RADIUS: float = 24.0  # renamed from TOP_POLYMERASE_RADIUS
# ---------- MARKERS ----------
var marker_leading_5p: Node2D = null
var marker_leading_3p: Node2D = null


var lagging_polymerase_tween: Tween = null
var leading_clamp: PolymeraseClamp = null
var lagging_clamp: PolymeraseClamp = null
var leading_halo: PolymeraseHalo = null
var lagging_halo: PolymeraseHalo = null
var lagging_pump_tween: Tween = null

# ---------- LIGASE (Complex tier — OkazakiMaturationDesign.md) ----------
# Light tier: fed purely by Pol III's own _lagging_close_fragment() event.
# Complex tier (pol1_enabled): _lagging_close_fragment() still calls
# _ligase_kick() unconditionally (same call site, untouched), but the
# eligibility check inside _ligase_kick() itself now additionally requires
# frag.primer_removed — see POL I section. _pol1_finish_job() adds a SECOND
# call site once a primer actually clears, since that's frequently the real
# unblocking event at this tier. Ligase's own motion/render/scrub logic is
# unchanged either way — only the gating changed, not the call site itself.
var ligase: Ligase = null
## ATP cofactor visual, a CHILD of the ligase node — which buys hide-on-scrub,
## the end-of-run modulate fade, and offstage parking for free, since all three
## already act on ligase itself. See ligase_cofactor.gd's header.
var ligase_cofactor: LigaseCofactor = null
var _ligase_tween: Tween = null
enum LigaseState { IDLE, TRAVELING, HOLDING, SEALING }
var _ligase_state: int = LigaseState.IDLE
## The lagging slot just BEFORE the fragment ligase is currently
## traveling to / holding at / sealing — i.e. next_frag.slots[0] - 1, the
## exact boundary is_lagging_bond_sealed()/get_lagging_gap_atom_position()
## key off. -2 whenever ligase isn't parked at any specific gap (IDLE,
## offstage) — a DISTINCT sentinel from the real, valid value -1 (the very
## first Okazaki fragment's own seal, which has no predecessor slot but is
## still a real gap _ligase_apply_atom_tier_position_swap() must handle,
## not skip). Cleared to -2 in _ligase_finish_seal() and
## _ligase_reset_visual() so a scrub or a completed seal can never leave a
## stale slot index behind for _ligase_apply_atom_tier_position_swap() to
## read.
var _ligase_active_gap_slot: int = -2

# ---------- PRIMASE (Light tier — OkazakiMaturationDesign.md) ----------
# Transient blip only — no queue, no persisted RNA state, no travel. Fires
# once per fragment, at the moment that fragment OPENS (mirror image of
# ligase's trigger, which fires on fragment CLOSE).
var primase_blip: PrimaseBlip = null
var primase_halo: PolymeraseHalo = null
var _primase_tween: Tween = null
## tile_end (int) -> {backbone: Line2D, bond_marks: Array} — primer backbone
## geometry for a tile whose bases primase has placed but whose fragment
## Pol III hasn't opened yet. Adopted (not recreated) by
## _lagging_open_next_fragment() the moment it opens that same tile.
var primase_pending_backbones: Dictionary = {}

# ---------- POL I (Complex tier — OkazakiMaturationDesign.md) ----------
# True-absence lifecycle (unlike ligase/primase): not instantiated until its
# first job, persists after that. Trigger: _lagging_close_fragment() enqueues
# a job for the SECOND-TO-LAST fragment (lagging_fragments[-2]) once at least
# two fragments exist. The fragment that just closed is what brings Pol
# III's growing edge geometrically adjacent to the PREVIOUS fragment's own
# primer (that primer sits at its own tile_end, exactly where the
# just-closed fragment's tile_start begins) — one fragment of lag,
# deterministic (event-count-gated, not real-time-paced), not the primer of
# the fragment that just closed itself. The very last fragment in a
# sequence never gets a "next fragment closes" event, so its primer is
# never removed and ligase never seals it — the real end-replication
# problem, not a bug; left alone until the telomerase tier exists to handle
# it (OkazakiMaturationDesign.md's open questions already flag this).
var pol1: Pol1Enzyme = null
var _pol1_tween: Tween = null
enum Pol1Phase { OFFSTAGE, ARRIVING, WORKING, LEAVING }
var _pol1_state: int = Pol1Phase.OFFSTAGE
var _pol1_queue: Array = []  # Array[Dictionary] — {frag: Dictionary, seq: Array[int]}, seq high-to-low

# ---------- COMPLEXITY MANAGER ----------
var complexity_mgr: Node = null  # %ComplexityManager, cached in initialize()

# ---------- CAPTURE STATE ----------
# The traveling nucleotide during a step: leg 1 is a live per-frame follow of
# the jaw cap's inner anchor (not a tween — the clamp is still mid-glide, so
# there is no fixed destination to tween to), leg 2 is a genuine tween to the
# base's final resting spot once the clamp itself has arrived. See the
# _capture_* section below. At most one capture is in flight per strand at a
# time (same one-step-at-a-time discipline the position/pump tweens follow).
var leading_capture_node: Node2D = null
var leading_capture_tween: Tween = null
var leading_capture_target_slot: int = -1
var leading_capture_leg2_started: bool = false

var lagging_capture_node: Node2D = null
var lagging_capture_tween: Tween = null
var lagging_capture_target_slot: int = -1
var lagging_capture_leg2_started: bool = false
var lagging_capture_leg2_duration: float = 0.0  # stored at _capture_begin_lagging() time; _set_lagging_pump_phase's callback only carries phase, not duration
# ==========================================
# LIFECYCLE — public dispatchers
# ==========================================

func initialize(p_sim: Node) -> void:
	# Called once when simulation.gd first creates this node.
	sim = p_sim
	tm = p_sim.get_node("%ThemeManager")
	zoom_mgr = p_sim.get_node_or_null("%ZoomManager")
	if zoom_mgr != null:
		# Registered once, here — NOT re-registered in _leading_setup_backbones(),
		# even though that function recreates leading_polymerase on every
		# sequence load. The Callables close over `self` (replication_mgr,
		# which persists across sequences) and look up leading_polymerase /
		# lagging_polymerase fresh each call, so they stay valid across
		# reloads without re-registration. Level 4 has been removed entirely
		# (design decision) — enzymes now register level 3 only... and as of
		# this pass, level 2 too, now that it has real "regional context"
		# framing instead of the old placeholder. entry_level is therefore 2
		# for both polymerases now (was 3) — selecting one from the dropdown
		# jumps straight to level 2, same as the new-strand targets.
		zoom_mgr.register_target("leading_polymerase", {2: _zoom_frame_leading_level2, 3: _zoom_frame_leading_level3}, "ZOOM_LEADING_POLYMERASE", _zoom_leading_visible)
		zoom_mgr.register_target("lagging_polymerase", {2: _zoom_frame_lagging_level2, 3: _zoom_frame_lagging_level3}, "ZOOM_LAGGING_POLYMERASE", _zoom_lagging_visible)
		# The two new DNA strands themselves, not enzymes. Unlike the enzymes
		# above, these have entry_level 2 (the lowest key below) — select_target()
		# jumps straight to level 2, and + walks 2 -> 3. No level 4 for these
		# either. See the two frame-provider functions below for what each
		# level shows.
		zoom_mgr.register_target("new_leading_strand", {
			2: _zoom_frame_new_leading_level2,
			3: _zoom_frame_new_leading_level3,
		}, "ZOOM_NEW_LEADING_STRAND", _zoom_new_leading_visible)
		zoom_mgr.register_target("new_lagging_strand", {
			2: _zoom_frame_new_lagging_level2,
			3: _zoom_frame_new_lagging_level3,
		}, "ZOOM_NEW_LAGGING_STRAND", _zoom_new_lagging_visible)
	lagging_polymerase = p_sim.synthesis_circle
	lagging_polymerase.z_index = 10
	lagging_polymerase_faded = false
	_lagging_fade_pending = false
	lagging_polymerase.modulate.a = 0.0  # start invisible

	# Build the 3-piece lagging clamp as a child of the SynthesisCircle node.
	# It self-offsets to the duplex centre and z-threads the strand between its
	# back pieces and front cap — no positioning code here changes.
	lagging_clamp = PolymeraseClamp.new()
	lagging_polymerase.add_child(lagging_clamp)
	lagging_clamp.setup(sim, false)
	lagging_clamp.scrub_drag_started.connect(_on_lagging_clamp_drag_started)
	lagging_clamp.scrub_drag_delta.connect(_on_lagging_clamp_drag_delta)
	lagging_clamp.follow_requested.connect(_on_lagging_clamp_follow_requested)
	lagging_halo = PolymeraseHalo.new()
	lagging_polymerase.add_child(lagging_halo)
	lagging_halo.setup(sim, false)

	# Ligase (Complex tier) — created once, persists across sequence loads,
	# same lifecycle as leading_clamp/lagging_clamp above. Added directly
	# under sim rather than under a polymerase node, since it travels
	# independently along the backbone rather than riding either polymerase's
	# position.
	ligase = Ligase.new()
	sim.add_child(ligase)
	ligase.setup(sim)
	ligase_cofactor = LigaseCofactor.new()
	ligase.add_child(ligase_cofactor)
	ligase_cofactor.setup(sim)
	ligase.visible = false
	_ligase_park_offstage()  # start at the offstage rest spot, not local origin (up-left of the strand)

	# Primase (Light tier) — same "created once, persists across sequence
	# loads" lifecycle. Alpha-driven rather than visible-driven (matches
	# helicase_node's own fade convention) since it's purely an appear/hold/
	# fade blip with no travel.
	primase_blip = PrimaseBlip.new()
	sim.add_child(primase_blip)
	primase_blip.setup(sim)
	primase_blip.modulate.a = 0.0

	# Same halo mechanic Pol III's own capture already uses — a distinct
	# instance, child of primase_blip so it automatically follows the blip's
	# own position (mirrors how lagging_halo is a child of lagging_polymerase).
	# Reused unmodified: it's already generically written, reads its physics/
	# size live from sim.nucleotide_field, needs no primase-specific changes.
	primase_halo = PolymeraseHalo.new()
	primase_blip.add_child(primase_halo)
	# RNA pool, not DNA: real primase draws from a chemically distinct
	# rNTP pool (ribose, not deoxyribose — same base letters as DNA except
	# uracil replacing thymine). base_letters/color_overrides must be set
	# BEFORE setup(), which builds the initial particle fill from them.
	primase_halo.base_letters = PackedStringArray(["A", "U", "C", "G"])
	primase_halo.color_overrides = {
		"A": tm.rna_base_color_a,
		"U": tm.rna_base_color_u,
		"C": tm.rna_base_color_c,
		"G": tm.rna_base_color_g,
	}
	primase_halo.is_rna = true
	primase_halo.setup(sim, false)

	# Fed by ComplexityManager.toggle_changed rather than polled — covers the
	# "ligase toggled ON mid-run, after fragments already completed while it
	# was off" catch-up case with a real event instead of a per-frame check.
	# Toggling OFF resets the visual instead of leaving it frozen mid-travel.
	complexity_mgr = p_sim.get_node_or_null("%ComplexityManager")
	if complexity_mgr != null:
		complexity_mgr.toggle_changed.connect(_on_complexity_toggle_changed)

func reset(num_slots: int) -> void:
	# Called by simulation.gd after teardown, before spawning new slots.
	manual_override = true
	_leading_reset(num_slots)
	_lagging_reset(num_slots)
	_capture_reset()

func setup_backbones() -> void:
	# Called after reset() during initialize_simulation().
	_leading_setup_backbones()
	_lagging_setup_backbones()

func teardown() -> void:
	# Free all owned nodes. Called by simulation.gd teardown_simulation().
	_leading_teardown()
	_lagging_teardown()
	_capture_teardown()

# ==========================================
# UPDATE — called from simulation.gd _process
# ==========================================

func update(delta: float, ctx: Dictionary) -> void:
	# ctx keys provided by simulation.gd:
	#   helicase_x, polymerase_x, center_y, template_strand_y,
	#   polymerase_y_lagging, polymerase_y_leading, dna_ribbons_gap,
	#   polymerase_y_offset, wobble_t, phase, helicase_mgr, num_slots
	var phase = ctx.phase
	var helicase_mgr = ctx.helicase_mgr

	# Cache context for use in signal handlers
	ctx_polymerase_x = ctx.polymerase_x
	ctx_helicase_x = ctx.helicase_x
	ctx_center_y = ctx.center_y
	ctx_template_strand_y = ctx.template_strand_y
	ctx_polymerase_y_lagging = ctx.polymerase_y_lagging
	ctx_polymerase_y_leading = ctx.polymerase_y_leading
	ctx_dna_ribbons_gap = ctx.dna_ribbons_gap
	ctx_polymerase_y_offset = ctx.polymerase_y_offset
	ctx_wobble_t = ctx.wobble_t
	ctx_phase = ctx.phase
	ctx_num_slots = ctx.num_slots
	ctx_nucleotide_original_x = sim.nucleotide_original_x



	# ---- Enzyme positions: each polymerase sits on its own template strand's row ----
	if leading_polymerase and phase != helicase_mgr.Phase.DONE:
		leading_polymerase.position = Vector2(ctx.polymerase_x, ctx.new_top_template_y)
		if leading_clamp != null:
			var reached_first_slot = ctx.num_slots > 0 and ctx.polymerase_x >= sim.nucleotide_original_x[0]
			leading_clamp.set_pump(sin(helicase_mgr.step_t * PI) if reached_first_slot else 0.0)
	elif leading_clamp != null:
		leading_clamp.set_pump(0.0)

	# Deliberately OUTSIDE the phase check above: if phase flips to DONE while
	# a capture is still mid-flight (last slot's animation still running when
	# FINISHING wraps up), it must still get to finish — otherwise the
	# traveling base freezes forever and never graduates into the strand.
	# _capture_update_leading() already no-ops when nothing is in flight.
	_capture_update_leading(helicase_mgr.step_t, helicase_mgr.step_duration)

	# ---- Helicase finishing trigger (driven by leading strand's remaining slots) ----
	if phase == helicase_mgr.Phase.FINISHING_LAST_PULSE and helicase_mgr.extra_steps_total == 0:
		var remaining_leading = 0
		for i in range(ctx.num_slots):
			if sim.nucleotide_original_x[i] > ctx.polymerase_x:
				remaining_leading += 1
		helicase_mgr.start_finishing(remaining_leading)

	# ---- Proximity-based fade-in: each polymerase becomes visible shortly
	# before it actually starts working, rather than popping in with the
	# helicase at the very start of the run. Trigger is spatial (3 slot
	# spacings of fork progress before the first slot it will work on); the
	# fade itself takes exactly one helicase step_duration, so it reads as a
	# quick "arrival" rather than a slow ambient fade.
	#
	# Uses ctx.polymerase_x (fork/leading-polymerase progress) as the
	# distance reference for BOTH strands, not each polymerase's own
	# position — the lagging polymerase in particular stays parked
	# (invisible) until its own first _lagging_fire_step() call, so its own
	# position never changes during the wait and can't serve as a "getting
	# closer" signal. Naturally fires later for lagging than leading, since
	# its first slot sits farther down the strand.
	if not leading_fade_in_started and leading_polymerase != null and ctx.num_slots > 0:
		if sim.nucleotide_original_x[0] - ctx.polymerase_x <= 3.0 * sim.nucleotide_slot_spacing:
			leading_fade_in_started = true
			var leading_fade_tween = sim.create_tween()
			leading_fade_tween.tween_property(leading_polymerase, "modulate:a", 1.0, helicase_mgr.step_duration)

	if not lagging_fade_in_started and lagging_polymerase != null and ctx.num_slots > 0:
		var lagging_first_slot = min(sim.okazaki_fragment_size, ctx.num_slots) - 1
		if sim.nucleotide_original_x[lagging_first_slot] - ctx.polymerase_x <= 3.0 * sim.nucleotide_slot_spacing:
			lagging_fade_in_started = true
			var lagging_fade_tween = sim.create_tween()
			lagging_fade_tween.tween_property(lagging_polymerase, "modulate:a", 1.0, helicase_mgr.step_duration)

	# Leading strand spawning now happens via _capture_on_leading_slot_reached()
	# (event-driven, off helicase.slot_reached) — see the _capture_* section.
	# The old per-frame position-polling spawn here was removed: it would have
	# kept re-checking leading_synthesized_bases[i] == null and instantly
	# double-spawning while a capture is deliberately still in flight for that
	# slot (capture keeps the array entry null until its animation completes).

# ==========================================
# SCRUB REBUILD — called from simulation.gd scrub_to()
# ==========================================

func scrub_rebuild(ctx: Dictionary) -> void:
	# ctx keys: target_polymerase_x, helicase_x, is_done_phase, num_slots,
	#           nucleotide_original_x, template_strand_y, helicase_mgr
	# Capture never runs during scrub — scrub always shows finished slots
	# only, same rule the pump already follows. Any in-flight traveling
	# nucleotide (and its node — not yet in the synthesized-bases arrays, so
	# the strand rebuilds below won't free it) must be killed here or it leaks.
	_capture_reset()

	var target_polymerase_x: float = ctx.target_polymerase_x
	var nucleotide_original_x = ctx.nucleotide_original_x
	_leading_scrub_rebuild(ctx)
	_lagging_scrub_rebuild(ctx)

	# ---- Enzyme visibility/position on scrub: each polymerase sits on its own template strand's row ----
	# Fade-in state must resync here too, not just alpha — scrubbing backward
	# past the proximity trigger point must reset leading_fade_in_started /
	# lagging_fade_in_started, or resuming live play afterward would think
	# the fade already happened and skip it (same class of bug as the
	# lagging_total_consumed / lagging_batch_cursor scrub desyncs documented
	# elsewhere in this file).
	var leading_near = ctx.num_slots > 0 and (sim.nucleotide_original_x[0] - target_polymerase_x) <= 3.0 * sim.nucleotide_slot_spacing
	leading_fade_in_started = leading_near
	if leading_polymerase:
		leading_polymerase.modulate.a = 0.0 if ctx.is_done_phase else (1.0 if leading_near else 0.0)
		leading_polymerase.position = Vector2(target_polymerase_x, ctx.new_top_template_y)
		if leading_clamp != null: leading_clamp.set_pump(0.0)

	var lagging_first_slot = (min(sim.okazaki_fragment_size, ctx.num_slots) - 1) if ctx.num_slots > 0 else -1
	var lagging_near = lagging_first_slot >= 0 and (sim.nucleotide_original_x[lagging_first_slot] - target_polymerase_x) <= 3.0 * sim.nucleotide_slot_spacing
	lagging_fade_in_started = lagging_near
	if lagging_polymerase:
		lagging_polymerase_faded = ctx.is_done_phase
		lagging_polymerase.modulate.a = 0.0 if ctx.is_done_phase else (1.0 if lagging_near else 0.0)
		if lagging_pump_tween != null and lagging_pump_tween.is_valid():
			lagging_pump_tween.kill()
		# Any in-flight lagging_polymerase_tween must die here too, or it
		# keeps animating toward its pre-scrub target and overwrites the
		# snap below on its next update — every OTHER scrub path already
		# instant-snaps correctly; this was the one gap, only visible when
		# a scrub landed mid-tween (which live play's constant lagging-
		# polymerase animation makes fairly likely, not a rare edge case).
		if lagging_polymerase_tween != null and lagging_polymerase_tween.is_valid():
			lagging_polymerase_tween.kill()
		if lagging_clamp != null:
			lagging_clamp.set_pump(0.0)

		lagging_polymerase.position = Vector2(lagging_polymerase_x, ctx.new_bottom_template_y)

	# Ligase (Complex tier): scrub shows only finished states — there is no
	# "mid-travel"/"mid-seal" to reproduce for an arbitrary scrub target, so
	# any in-flight tween is killed and the enzyme hidden, same as every
	# other scrub-must-be-instant rule in this file. _lagging_scrub_rebuild()
	# (already called above) marks every synthesized fragment sealed
	# directly, independent of this.
	_ligase_reset_visual()
	# Primase (Light tier): never fires during scrub in the first place (see
	# the PRIMASE section banner), but an in-flight blip from right before
	# the scrub started still needs killing, same as any other tween here.
	_primase_blip_reset_visual()
	# Pol I (Complex tier): same rule — scrub shows only finished states, and
	# the gating state (frag.primer_removed) is resolved structurally below
	# by _lagging_scrub_rebuild() regardless of whether this node even
	# exists, so it always just goes fully offstage here.
	_pol1_reset_visual()
	_primase_clear_pending_backbones()

# ==========================================
# ENZYME ANIMATION — called from simulation.gd toggle_play() / _run_intro()
# ==========================================

func resume_enzymes() -> void:
	if leading_polymerase and leading_fade_in_started:
		leading_polymerase.modulate.a = 1.0
	if lagging_polymerase and lagging_fade_in_started:
		lagging_polymerase.modulate.a = 1.0
	lagging_polymerase_faded = false
	_lagging_fade_pending = false

func run_intro(intro_x: float, fade_time: float, slide_time: float, tween: Tween) -> void:
	var polymerase_x_offset = sim.polymerase_x_offset_slots * sim.nucleotide_slot_spacing
	#lagging_polymerase.position = Vector2(intro_x - polymerase_x_offset, sim.template_strand_y)
	lagging_polymerase.position = Vector2(intro_x - polymerase_x_offset, sim.new_bottom_template_y)
	tween.tween_property(lagging_polymerase, "position",
		Vector2(sim.polymerase_x, sim.new_bottom_template_y), slide_time).set_delay(fade_time)

	if leading_polymerase:
		leading_polymerase.position = Vector2(intro_x - polymerase_x_offset, sim.new_top_template_y)
		tween.tween_property(leading_polymerase, "position",
			Vector2(sim.polymerase_x, sim.new_top_template_y), slide_time).set_delay(fade_time)

# ==========================================
# RENDER — called from simulation.gd _process visual section
# ==========================================

func render(delta: float, ctx: Dictionary) -> void:
	# Updates positions and backbones for all synthesized nodes.
	# ctx keys: wobble_t, polymerase_y_lagging, dna_ribbons_gap,
	#           polymerase_y_offset, center_y, template_strand_y,
	#           new_top_template_y, num_slots,
	#           nucleotide_original_x, template_strand_bottom,
	#           nucleotide_bases, top_strand_slots
	_leading_render(ctx)
	_lagging_render(ctx)
	_leading_apply_atom_tier_position_swap(ctx)
	_lagging_apply_atom_tier_position_swap()
	_ligase_apply_atom_tier_position_swap()
	_debug_dump_polymerase_atom_tier_state(ctx)
	_apply_highlight()

# ==========================================
# ZOOM / HIGHLIGHT — frame-providers registered with ZoomManager, and the
# per-frame highlight-dim application for this file's owned visuals. See
# ZoomDesign.md and zoom_manager.gd's file banner for the ownership contract.
# ==========================================

## Fit percentages, same tunable-by-eye pattern that worked for the
## new-strand targets — nudge these directly if the framing needs
## adjustment once tested in-engine.

## Shared by both clamps — same clamp geometry either way. Reuses the EXACT
## formula polymerase_clamp.gd itself uses for its own label placement
## (half_down = back_base_height * 0.5, doubled here for full height), so
## this tracks any ThemeManager "Polymerase Clamp" tuning automatically
## rather than duplicating a guessed constant.
## See the matching pair in simulation.gd. zoom_mgr is already cached in
## initialize(), so no lookup needed here.
## See the matching helper in simulation.gd.
func _zoom_label_rotation() -> float:
	return zoom_mgr.get_label_counter_rotation() if zoom_mgr != null else 0.0

func _zoom_along_extent() -> float:
	return zoom_mgr.get_along_extent() if zoom_mgr != null else 1152.0

func _zoom_cross_extent() -> float:
	return zoom_mgr.get_cross_extent() if zoom_mgr != null else 648.0

func _polymerase_footprint_height() -> float:
	var span: float = sim.dna_ribbons_gap + 2.0 * (float(tm.backbone_offset_distance) + float(tm.backbone_line_width) * 0.5)
	return span + 2.0 * tm.clamp_margin

## Level 2 fit percentages. Leading and lagging now use genuinely different
## MECHANISMS, not just different numbers — see the two functions below for
## why — so each gets its own named field even though both still land in
## replication_manager.gd's shared "tune by eye" style.

## Level 2 — "regional context": camera CENTERS ON leading polymerase
## itself, sized just wide/tall enough that the helicase also fits in frame.
## Anchor-centering (not a bounding-box midpoint) is safe here because
## leading stays close to the helicase at all times — unlike lagging (see
## _zoom_frame_lagging_level2() below), there's no risk of this swinging the
## zoom out wildly.
func _zoom_frame_leading_level2() -> Dictionary:
	if leading_polymerase == null or not is_instance_valid(leading_polymerase):
		return {}
	if sim.helicase_node == null or not is_instance_valid(sim.helicase_node):
		return _polymerase_footprint_frame(leading_polymerase, tm.zoom_leading_level2_fit)
	var context: Array = [sim.helicase_node.global_position]
	return _anchor_centered_frame(leading_polymerase.global_position, context, tm.zoom_leading_level2_fit)

func _zoom_frame_leading_level3() -> Dictionary:
	return _polymerase_footprint_frame(leading_polymerase, tm.zoom_polymerase_level3_fit)

## Level 2 — deliberately does NOT include the helicase in frame, unlike
## leading's version above. Lagging periodically jumps back to the start of
## a new Okazaki fragment then creeps forward again as it fires — tracking
## it alone (fixed zoom, panning position) means the camera's own motion
## against the static DNA background *is* that back-and-forth, which is the
## whole pedagogical point (per this session's discussion): you watch it
## catch up toward where the helicase/leading currently are, then fall
## behind again as the next fragment opens — without needing the helicase
## literally boxed into frame for that to read.
func _zoom_frame_lagging_level2() -> Dictionary:
	return _polymerase_footprint_frame(lagging_polymerase, tm.zoom_lagging_level2_fit)

func _zoom_frame_lagging_level3() -> Dictionary:
	return _polymerase_footprint_frame(lagging_polymerase, tm.zoom_polymerase_level3_fit)

## Centers the camera ON `anchor` (the highlighted object) rather than on
## the bounding-box midpoint of anchor+context — sizes the frame
## symmetrically around the anchor just far enough to include every context
## point, so the anchor is guaranteed to land dead-center on screen. Only
## used where the context point stays reasonably close to the anchor
## (leading+helicase); lagging deliberately avoids this (see above).
func _anchor_centered_frame(anchor: Vector2, context: Array, fit_pct: float) -> Dictionary:
	var max_dx: float = 0.0
	var max_dy: float = 0.0
	for p in context:
		max_dx = max(max_dx, abs(p.x - anchor.x))
		max_dy = max(max_dy, abs(p.y - anchor.y))
	var size: Vector2 = Vector2(max(max_dx * 2.0, 1.0), max(max_dy * 2.0, 1.0))
	# size.x is a world-x span, size.y a world-y span. The extent helpers supply
	# whichever viewport dimension each currently maps to — the rotation is
	# exactly 90 degrees, so the box stays axis-aligned and needs no transform.
	var target_zoom: float = minf((_zoom_along_extent() * fit_pct) / size.x, (_zoom_cross_extent() * fit_pct) / size.y)
	return {zoom = target_zoom, position = anchor}

func _polymerase_footprint_frame(clamp_node: Node2D, fit_pct: float) -> Dictionary:
	if clamp_node == null or not is_instance_valid(clamp_node):
		return {}
	var footprint_height: float = _polymerase_footprint_height()
	if footprint_height <= 0.0:
		return {}
	# footprint_height is a world-y span — ACROSS the track — so it fits against
	# the cross-axis viewport extent in both orientations.
	var target_zoom: float = (_zoom_cross_extent() * fit_pct) / footprint_height
	return {zoom = target_zoom, position = clamp_node.global_position}

## Reuses leading_polymerase/lagging_polymerase's own modulate.a — the exact
## signal the proximity fade-in logic (_leading_render/_lagging_render) is
## already setting to 0.0 before it's near enough to be relevant, rather than
## introducing a second, possibly-out-of-sync notion of "visible."
func _zoom_leading_visible() -> bool:
	return leading_polymerase != null and is_instance_valid(leading_polymerase) and leading_polymerase.modulate.a > 0.01

func _zoom_lagging_visible() -> bool:
	return lagging_polymerase != null and is_instance_valid(lagging_polymerase) and lagging_polymerase.modulate.a > 0.01

## Cross-axis fit percentages for the new-strand targets. "Cross-axis" is the
## world-y span (ACROSS the track) — viewport HEIGHT in horizontal mode,
## viewport WIDTH in vertical mode. See VerticalModeDesign.md.
##  - Level 2 shows all four rows around the fork's cross-axis spread (new
##    strand, template's unzipped row, template's bonded/pre-fork row, other
##    template's row) at 80% of the cross-axis extent.
##  - Level 3 shows just the new strand + its paired template's unzipped
##    row, tighter, at 70% of the cross-axis extent (15% padding —
##    deliberately more than level 2's 10%, so it reads as visibly different
##    from level 2 rather than landing on the same effective zoom).
## Both are cross-axis-ONLY fits (return a Dictionary, not points) — the
## along-axis isn't a constraint here; along-track position stays centered on
## the track (same as level 1) at both levels.
const NEW_STRAND_LEVEL2_CROSS_AXIS_FIT: float = 0.6
const NEW_STRAND_LEVEL3_CROSS_AXIS_FIT: float = 0.2

# --- New Leading Strand (pairs with the ORIGINAL TOP template) ---
#
# Four rows, top to bottom (confirmed against _rebuild_top_rail() and the
# actual leading-base positioning in _leading_render()):
#   new_top_template_y - dna_ribbons_gap   <- new leading strand's own row
#   new_top_template_y                     <- top template, UNZIPPED (post-fork) row
#   template_strand_y - dna_ribbons_gap    <- top template, BONDED (pre-fork) row
#   template_strand_y                      <- bottom template's row
# The gap between rows 1-2 and between rows 3-4 are both exactly
# dna_ribbons_gap, symmetric around the polymerase_y_offset zone (rows 2-3)
# — so centering on the full four-row span and centering on just the
# polymerase_y_offset zone land on the exact same point algebraically.

func _zoom_frame_new_leading_level2() -> Dictionary:
	if sim == null or not ("track_length" in sim) or sim.track_length <= 0.0:
		return {}
	var new_strand_y: float = sim.new_top_template_y - sim.dna_ribbons_gap
	var bottom_template_y: float = sim.template_strand_y
	var mid_y: float = (new_strand_y + bottom_template_y) * 0.5
	# base_radius on each end: span between row CENTERLINES isn't the same
	# as the span of actual rendered content — the nucleotide circles extend
	# base_radius beyond their own centerline in each direction, and it's
	# THAT outer edge that needs to fit within the padding, not the bare
	# centerline distance (confirmed via debug screenshots: without this,
	# the circles themselves overflow the intended padding at high zoom).
	var content_span: float = (bottom_template_y - new_strand_y)# + 2.0 * tm.base_radius
	if content_span <= 0.0:
		return {}
	var target_zoom: float = (_zoom_cross_extent() * NEW_STRAND_LEVEL2_CROSS_AXIS_FIT) / content_span
	return {zoom = target_zoom, position = Vector2(sim.track_length * 0.5, mid_y)}

func _zoom_frame_new_leading_level3() -> Dictionary:
	if sim == null or not ("track_length" in sim) or sim.track_length <= 0.0:
		return {}
	var new_strand_y: float = sim.new_top_template_y - sim.dna_ribbons_gap
	var unzipped_template_y: float = sim.new_top_template_y
	var mid_y: float = (new_strand_y + unzipped_template_y) * 0.5
	var content_span: float = abs(unzipped_template_y - new_strand_y)# + 2.0 * tm.base_radius
	if content_span <= 0.0:
		return {}
	var target_zoom: float = (_zoom_cross_extent() * NEW_STRAND_LEVEL3_CROSS_AXIS_FIT) / content_span
	return {zoom = target_zoom, position = Vector2(sim.track_length * 0.5, mid_y)}

func _zoom_new_leading_visible() -> bool:
	# LongSequenceDesign.md follow-up: doesn't make sense to zoom into a
	# whole-strand bounding box while level 1 itself is in windowed
	# (cross-axis-fit) mode (long sequence) — the strand sprawls far past
	# what's on screen at once. Best highlighted once it's fully visible at
	# the normal fit-to-track zoom.
	if zoom_mgr != null and zoom_mgr.is_windowed_mode():
		return false
	return leading_backbone_line != null and is_instance_valid(leading_backbone_line) and leading_backbone_line.points.size() > 0

# --- New Lagging Strand (pairs with the ORIGINAL BOTTOM template) ---
#
# Mirrors the leading strand's structure exactly, flipped: leading's level 2
# used [new leading strand, top unzipped, top bonded, bottom bonded] with
# the OTHER template's bonded row as the far boundary. Lagging's mirrors
# that with top/bottom swapped: [top bonded, bottom bonded, bottom unzipped,
# new lagging strand] — the far boundary here is the TOP template's bonded
# row (template_strand_y - dna_ribbons_gap), NOT anything from the leading
# strand's own rows.
#   template_strand_y - dna_ribbons_gap     <- top template, BONDED row (far boundary)
#   template_strand_y                       <- bottom template, BONDED row
#   new_bottom_template_y                   <- bottom template, UNZIPPED row
#   new_bottom_template_y + dna_ribbons_gap <- new lagging strand's own row

func _zoom_frame_new_lagging_level2() -> Dictionary:
	if sim == null or not ("track_length" in sim) or sim.track_length <= 0.0:
		return {}
	var top_boundary_y: float = sim.template_strand_y - sim.dna_ribbons_gap
	var new_strand_y: float = sim.new_bottom_template_y + sim.dna_ribbons_gap
	var mid_y: float = (top_boundary_y + new_strand_y) * 0.5
	# base_radius on each end — see the matching comment in
	# _zoom_frame_new_leading_level2() for why this is needed.
	var content_span: float = (new_strand_y - top_boundary_y)# + 2.0 * tm.base_radius
	if content_span <= 0.0:
		return {}
	var target_zoom: float = (_zoom_cross_extent() * NEW_STRAND_LEVEL2_CROSS_AXIS_FIT) / content_span
	return {zoom = target_zoom, position = Vector2(sim.track_length * 0.5, mid_y)}

func _zoom_frame_new_lagging_level3() -> Dictionary:
	if sim == null or not ("track_length" in sim) or sim.track_length <= 0.0:
		return {}
	var unzipped_template_y: float = sim.new_bottom_template_y
	var new_strand_y: float = sim.new_bottom_template_y + sim.dna_ribbons_gap
	var mid_y: float = (unzipped_template_y + new_strand_y) * 0.5
	var content_span: float = abs(new_strand_y - unzipped_template_y)# + 2.0 * tm.base_radius
	if content_span <= 0.0:
		return {}
	var target_zoom: float = (_zoom_cross_extent() * NEW_STRAND_LEVEL3_CROSS_AXIS_FIT) / content_span
	return {zoom = target_zoom, position = Vector2(sim.track_length * 0.5, mid_y)}

func _zoom_new_lagging_visible() -> bool:
	# Checks actual synthesis state rather than a rendering object's
	# contents. lagging_backbone_line.points.size() > 0 used to be the check
	# here (mirroring _zoom_new_leading_visible() above, where it's still
	# correct — the leading strand has no equivalent branching). That broke
	# once ligase.gd landed: with ligase_enabled, a completed-but-unsealed
	# fragment renders through its own separate frag.backbone, not this
	# shared line, so lagging_backbone_line can be legitimately empty while
	# real lagging-strand content already exists on screen.
	if zoom_mgr != null and zoom_mgr.is_windowed_mode():
		return false
	return lagging_total_consumed > 0


func _apply_highlight() -> void:
	if zoom_mgr == null:
		return

	# Enzymes: writes the CLAMP/HALO's own `modulate` — NOT self_modulate,
	# and NOT the parent leading_polymerase/lagging_polymerase container's
	# modulate. self_modulate was a real bug (confirmed via screenshots):
	# leading_clamp/lagging_clamp are themselves just Node2D containers with
	# no drawing of their own — the actual shapes are _back/_jaw/_lowerjaw,
	# their own children — so self_modulate on the clamp had literally no
	# visible effect. Regular `modulate` DOES propagate to children, and
	# writing it here (one level below the fade-owning container) is still
	# conflict-free: the proximity fade-in system only ever writes
	# leading_polymerase/lagging_polymerase's OWN modulate (the parent),
	# never leading_clamp/lagging_clamp's — still exactly one writer per
	# property, just one level down from where this used to sit. This also
	# fixes the enzyme labels not dimming (they're children too, and
	# modulate reaches them where self_modulate never did).
	var leading_dim = zoom_mgr.get_enzyme_highlight_dim("leading_polymerase")
	if leading_clamp != null: leading_clamp.modulate.a = leading_dim
	if leading_halo != null: leading_halo.modulate.a = leading_dim

	var lagging_dim = zoom_mgr.get_enzyme_highlight_dim("lagging_polymerase")
	if lagging_clamp != null: lagging_clamp.modulate.a = lagging_dim
	if lagging_halo != null: lagging_halo.modulate.a = lagging_dim

	# Strand visuals: plain modulate.a is safe here — nothing else writes it,
	# EXCEPT the molecular-structure occlusion suppression (bug A,
	# MolecularStructure_BasePairExpansion.md), which is folded in directly
	# below rather than living as a second writer in _leading_render()/
	# _lagging_render() — two writers on the same modulate.a property is
	# exactly the bug class this file's own "one writer per property" rule
	# (see the enzyme comment above) already warns against, and a real
	# instance of it shipped here once: this function runs AFTER
	# _leading_render()/_lagging_render() inside render(), so an earlier
	# occlusion write here would have silently clobbered strand_dim right
	# back to ~1.0 every frame. molecular_active(...) suppression always
	# wins over strand_dim (0.0, not multiplied) — a residue being shown
	# skeletally should read as fully hidden in bead mode regardless of
	# whatever the zoom-highlight dim would otherwise have been.
	var strand_dim = zoom_mgr.get_strand_highlight_dim()
	# Continuous replacements (bead<->molecular crossfade, Open Question 10)
	# for the old is_strand_active()/is_slot_bead_suppressed() bools — 0.0
	# at t=0 and 1.0 at t=1 reproduce the exact old binary boundaries,
	# ramping smoothly between. strand_dim * (1.0 - fade) preserves "atom-
	# tier suppression always wins over strand_dim" exactly: fade=1.0 drives
	# alpha to 0.0 regardless of strand_dim's own value.
	var leading_strand_fade: float = molecule_renderer.get_strand_fade_amount("leading") if molecule_renderer != null else 0.0
	var lagging_strand_fade: float = molecule_renderer.get_strand_fade_amount("lagging") if molecule_renderer != null else 0.0

	if leading_backbone_line != null: leading_backbone_line.modulate.a = strand_dim * (1.0 - leading_strand_fade)
	for mark in leading_strand_bond_marks:
		if mark != null and is_instance_valid(mark): mark.modulate.a = strand_dim * (1.0 - leading_strand_fade)
	for i in range(leading_hydrogen_bonds.size()):
		var bond = leading_hydrogen_bonds[i]
		if bond == null or not is_instance_valid(bond): continue
		# max()s the partner template strand too (PARTNER_STRAND["leading"] =
		# "template_top", molecule_structure_renderer.gd:175-177) — matching
		# simulation.gd's already-correct template_hydrogen_bonds pattern.
		# _active_slots is populated independently per "strand:slot" from two
		# separate sources (get_synthesized_nucleotides() vs.
		# get_template_nucleotides()), so leading:i and template_top:i can
		# disagree on atom-tier activity; checking only "leading" left the
		# bead-level pair line fully opaque whenever the TEMPLATE half of the
		# pair was the one actually rendered at atom scale — the reported bug.
		# max(), not OR-of-bools anymore: either side alone should be able to
		# drive the fade fully, same semantics as the old OR.
		var bond_fade: float = 0.0
		if molecule_renderer != null:
			bond_fade = max(molecule_renderer.get_bead_fade_amount("leading", i), molecule_renderer.get_bead_fade_amount("template_top", i))
		bond.modulate.a = strand_dim * (1.0 - bond_fade)

	if lagging_backbone_line != null: lagging_backbone_line.modulate.a = strand_dim * (1.0 - lagging_strand_fade)
	for mark in lagging_bond_marks:
		if mark != null and is_instance_valid(mark): mark.modulate.a = strand_dim * (1.0 - lagging_strand_fade)
	for i in range(lagging_hydrogen_bonds.size()):
		var bond = lagging_hydrogen_bonds[i]
		if bond == null or not is_instance_valid(bond): continue
		# max()s the partner template strand too — same fix as leading's bond
		# above (PARTNER_STRAND["lagging"] = "template_bottom"). _is_still_primer()
		# gating stays leading-side-only (a primer slot has no synthesized
		# lagging base yet to occlude), but the template partner can still be
		# atom-tier-active independently, so it's still checked unconditionally.
		var bond_fade: float = 0.0
		if molecule_renderer != null:
			var lagging_fade: float = 0.0 if _is_still_primer(i) else molecule_renderer.get_bead_fade_amount("lagging", i)
			bond_fade = max(lagging_fade, molecule_renderer.get_bead_fade_amount("template_bottom", i))
		bond.modulate.a = strand_dim * (1.0 - bond_fade)
	for frag in lagging_fragments:
		if frag.backbone != null and is_instance_valid(frag.backbone):
			frag.backbone.modulate.a = strand_dim * (1.0 - lagging_strand_fade)
		# primer_backbone (RNA segment) wasn't covered by this function
		# before the molecular-occlusion fix — adding it here rather than
		# losing that coverage when the per-fragment writer that used to
		# handle it (in _lagging_render_fragment_backbone()) is removed.
		if frag.get("primer_backbone", null) != null and is_instance_valid(frag.primer_backbone):
			frag.primer_backbone.modulate.a = strand_dim * (1.0 - lagging_strand_fade)
		for mark in frag.bond_marks:
			if mark != null and is_instance_valid(mark): mark.modulate.a = strand_dim * (1.0 - lagging_strand_fade)
		for mark in frag.get("primer_bond_marks", []):
			if mark != null and is_instance_valid(mark): mark.modulate.a = strand_dim * (1.0 - lagging_strand_fade)
	if lagging_current_fragment != null:
		if lagging_current_fragment.backbone != null and is_instance_valid(lagging_current_fragment.backbone):
			lagging_current_fragment.backbone.modulate.a = strand_dim * (1.0 - lagging_strand_fade)
		if lagging_current_fragment.get("primer_backbone", null) != null and is_instance_valid(lagging_current_fragment.primer_backbone):
			lagging_current_fragment.primer_backbone.modulate.a = strand_dim * (1.0 - lagging_strand_fade)
		for mark in lagging_current_fragment.bond_marks:
			if mark != null and is_instance_valid(mark): mark.modulate.a = strand_dim * (1.0 - lagging_strand_fade)
		for mark in lagging_current_fragment.get("primer_bond_marks", []):
			if mark != null and is_instance_valid(mark): mark.modulate.a = strand_dim * (1.0 - lagging_strand_fade)

# ==========================================
# QUERY FUNCTIONS
# ==========================================

# LongSequenceDesign.md follow-up — drag-to-scrub handlers for both
# polymerase clamps. Both funnel through the same _request_clamp_drag_scrub()
# conversion, which is why the lagging polymerase's non-monotonic (fragment-
# boundary jump-back) on-screen position is a non-issue here: the math never
# reads the clamp's current position, only how far the mouse has moved
# since the drag began, applied to wherever the scrub index was at that
# moment. Same conversion simulation.gd uses for the helicase ring, so drag
# feel is identical across all three enzymes.
func _on_leading_clamp_drag_started() -> void:
	_leading_drag_start_index = sim.get_synthesized_count()

func _on_leading_clamp_drag_delta(cumulative_px: Vector2) -> void:
	_request_clamp_drag_scrub(_leading_drag_start_index, cumulative_px)

func _on_lagging_clamp_drag_started() -> void:
	_lagging_drag_start_index = sim.get_synthesized_count()

func _on_lagging_clamp_drag_delta(cumulative_px: Vector2) -> void:
	_request_clamp_drag_scrub(_lagging_drag_start_index, cumulative_px)

func _on_lagging_clamp_follow_requested() -> void:
	if zoom_mgr != null:
		zoom_mgr.request_follow("lagging_polymerase")

func _request_clamp_drag_scrub(start_index: int, cumulative_px: Vector2) -> void:
	if zoom_mgr == null or sim.nucleotide_slot_spacing <= 0.0:
		return
	var zoom_x: float = zoom_mgr.zoom.x
	if zoom_x <= 0.0:
		return
	print("[FOLLOWCLICK] LP request_clamp_drag_scrub, cumulative_px=", cumulative_px)
	# See the matching comment in simulation.gd's _on_helicase_ring_drag_delta()
	# for why no sign flip is needed. Both clamps funnel through here, so the
	# axis choice is made once for the pair.
	var along_px: float = cumulative_px.y if zoom_mgr.vertical_mode else cumulative_px.x
	var px_per_slot: float = sim.nucleotide_slot_spacing * zoom_x
	var slot_delta: int = int(round(along_px / px_per_slot))
	sim.request_drag_scrub(start_index + slot_delta)

## Windowed slice, NOT the whole sequence — tm.legible_reference_length (57)
## characters centered on the helicase's current progress, following the
## fork rather than growing unboundedly wide with total sequence length (the
## PlayerUI.tscn SequenceLabel overflow problem this replaces). Same shared
## ThemeManager constant zoom_manager.gd's fit-to-height threshold uses, so
## both subsystems agree on what "legible" means from one number rather than
## two independently-tuned ones (this file used to have its own local copy —
## folded into ThemeManager to remove that duplication). Each character is
## wrapped in [url=ABSOLUTE_INDEX] — the absolute slot index, NOT its
## position within the window — so PlayerUI's click/drag-to-scrub always
## reads back a stable reference regardless of what's currently visible.
## hover_index (-1 = none) gets a bgcolor + color treatment (colors also on
## ThemeManager now, so themes can vary the hover look) layered on top of
## its normal synthesized/unsynthesized color. Visual grouping marks real
## Okazaki fragment boundaries (every okazaki_fragment_size slots) rather
## than an arbitrary fixed interval.
func get_sequence_rich_text(helicase_x: float, nucleotide_original_x: Array, hover_index: int = -1) -> String:
	var seq_string = sim.dna_sequence._to_string()
	if seq_string.is_empty():
		return "5' [empty] 3'"
	var n = seq_string.length()

	# Progress index: how many slots the helicase has already passed — the
	# same boundary test already driving synthesized/unsynthesized coloring
	# below, reused here as the window's center of attention, so the window
	# naturally follows the fork as helicase_x advances each frame.
	var progress_index = 0
	for i in range(n):
		if i < nucleotide_original_x.size() and nucleotide_original_x[i] <= helicase_x:
			progress_index = i
		else:
			break

	var window_size = min(tm.legible_reference_length, n)
	var window_half = window_size / 2
	var window_start = clamp(progress_index - window_half, 0, max(0, n - window_size))
	var window_end = window_start + window_size  # exclusive

	var text = "5' " if window_start == 0 else "… "
	for i in range(window_start, window_end):
		# Real fragment boundary, not the old arbitrary every-10-characters
		# grouping — DESIGN.md's fixed, deterministic tiling ([0,F), [F,2F),
		# … where F = okazaki_fragment_size) is the same formula this file's
		# own tile math already relies on elsewhere, so this can't drift out
		# of sync with the actual fragment logic.
		if i > window_start and i % sim.okazaki_fragment_size == 0:
			text += " "
		var base = seq_string[i]
		var synthesized = i < nucleotide_original_x.size() and nucleotide_original_x[i] <= helicase_x
		var base_color = tm.sequence_text_synthesized_color if synthesized else tm.sequence_text_unsynthesized_color
		var char_markup: String
		if i == hover_index:
			char_markup = "[bgcolor=#" + tm.sequence_text_hover_bg_color.to_html(false) + "][color=#" + tm.sequence_text_hover_text_color.to_html(false) + "]" + base + "[/color][/bgcolor]"
		else:
			char_markup = "[color=#" + base_color.to_html(false) + "]" + base + "[/color]"
		text += "[url=" + str(i) + "]" + char_markup + "[/url] "
	text += "3'" if window_end >= n else "…"
	return text

## Read-only view over leading_synthesized_bases / lagging_synthesized_bases
## for molecule_structure_renderer.gd — introduced for the Molecular
## Structure DNA-first milestone (MolecularStructureDesign.md). No new
## state: world_position is read straight off each already-spawned base
## node's own .position (already kept current every frame by
## _leading_render()/_lagging_render()), not recomputed independently, so
## this can never drift from what's actually on screen. Respects "no script
## reaches into another script's owned visual nodes" — callers get this
## array, never the underlying node arrays themselves.
func get_synthesized_nucleotides() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(leading_synthesized_bases.size()):
		var base = leading_synthesized_bases[i]
		if base != null and is_instance_valid(base):
			result.append({
				slot = i,
				strand = "leading",
				# Watson-Crick fix REVERTED (docs/MolecularStructure_
				# BasePairExpansion.md, Bug E follow-up): the original
				# get_complement(i) here was correct all along. The earlier
				# "fix" (get_base(i)) was based on get_template_nucleotides()'s
				# reported template_top formula, which turned out to NOT match
				# what simulation.gd's real _spawn_top_strand() bead-spawn
				# actually displays for template_top (get_base(i), not
				# get_complement(i) as get_template_nucleotides() claimed) — a
				# separate, older, pre-existing inconsistency between those two
				# functions. Leading's real template is template_top (still
				# confirmed via docs/SKILL.md's polarity table); template_top's
				# REAL displayed letter is get_base(i), so leading (its
				# complement) must be get_complement(i). Fixed at the other end
				# instead: see get_template_nucleotides() in simulation.gd.
				base_type = sim.dna_sequence.get_complement(i),
				world_position = base.position,
			})
	for i in range(lagging_synthesized_bases.size()):
		var base = lagging_synthesized_bases[i]
		if base != null and is_instance_valid(base) and not _is_still_primer(i):
			result.append({
				slot = i,
				strand = "lagging",
				# Reverted, symmetric to leading's above — see that comment.
				base_type = sim.dna_sequence.get_base(i),
				world_position = base.position,
			})
	return result

# ==========================================
# LEADING STRAND — self-contained section
# ==========================================
# Owns: leading_synthesized_bases, leading_hydrogen_bonds, leading_backbone_line,
# leading_strand_bond_marks, leading_polymerase, marker_leading_5p/3p.
# Synthesis trigger: simple position check, nucleotide_original_x[i] <= polymerase_x.
# No queue, no fragment boundaries — continuous synthesis, same as a real leading strand.

func _leading_reset(num_slots: int) -> void:
	leading_fade_in_started = false
	# Clear before appending — matches _lagging_reset()'s pattern. Without
	# this, a reload left the array holding whatever _leading_teardown()
	# had queue_free()'d (see that function's own fix comment): the fresh
	# num_slots nulls landed AFTER the stale entries instead of replacing
	# them, so leading_synthesized_bases[i] for a freshly loaded sequence
	# actually read a leftover reference from the PREVIOUS sequence.
	leading_synthesized_bases.clear()
	leading_hydrogen_bonds.clear()
	for i in range(num_slots):
		leading_synthesized_bases.append(null)
		leading_hydrogen_bonds.append(null)

func _leading_setup_backbones() -> void:
	leading_backbone_line = Line2D.new()
	leading_backbone_line.default_color = tm.backbone_color
	leading_backbone_line.width = tm.backbone_line_width
	leading_backbone_line.z_index = -1
	leading_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	leading_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	leading_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	sim.add_child(leading_backbone_line)

	# Leading polymerase visual
	if leading_polymerase and is_instance_valid(leading_polymerase):
		leading_polymerase.queue_free()
	leading_polymerase = Node2D.new()
	leading_polymerase.z_index = 10
	leading_clamp = PolymeraseClamp.new()
	leading_polymerase.add_child(leading_clamp)
	leading_clamp.setup(sim, true)
	leading_clamp.scrub_drag_started.connect(_on_leading_clamp_drag_started)
	leading_clamp.scrub_drag_delta.connect(_on_leading_clamp_drag_delta)
	leading_halo = PolymeraseHalo.new()
	leading_polymerase.add_child(leading_halo)
	leading_halo.setup(sim, true)
	leading_polymerase.position = Vector2(sim.polymerase_x, sim.new_top_template_y)
	leading_polymerase.modulate.a = 0.0
	sim.add_child(leading_polymerase)

func _leading_teardown() -> void:
	for base in leading_synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in leading_hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	for mark in leading_strand_bond_marks:
		if mark != null and is_instance_valid(mark): mark.queue_free()
	# Crash fix (queue_free on 'previously freed' instance, reported during
	# reload/scrub): _lagging_teardown() already clears its equivalent three
	# arrays right after freeing them; this function never did. Without this,
	# the array kept holding references to the nodes just freed above —
	# on the next sequence load, _leading_reset() only APPENDED new nulls
	# (see its own fix) rather than replacing them, so a later render() call
	# could pop and re-queue_free() a reference that had already been fully
	# deallocated by the end of THIS frame — Godot's "previously freed" error.
	leading_synthesized_bases.clear()
	leading_hydrogen_bonds.clear()
	leading_strand_bond_marks.clear()

	if leading_backbone_line and is_instance_valid(leading_backbone_line):
		leading_backbone_line.queue_free()
	if leading_polymerase and is_instance_valid(leading_polymerase):
		leading_polymerase.queue_free()
		leading_polymerase = null

	if marker_leading_5p and is_instance_valid(marker_leading_5p): marker_leading_5p.queue_free()
	if marker_leading_3p and is_instance_valid(marker_leading_3p): marker_leading_3p.queue_free()

	leading_backbone_line = null
	marker_leading_5p = null
	marker_leading_3p = null

func _leading_update(polymerase_x: float, num_slots: int, nucleotide_original_x: Array) -> void:
	# Removed (v71 capture wiring): this used to be the leading strand's ONLY
	# spawn trigger, a per-frame position-threshold poll. Spawning is now
	# event-driven via _capture_on_leading_slot_reached() (see _capture_*
	# section) so capture can begin at STEP START, not on arrival. Left as a
	# named no-op (rather than deleting the function outright) since removing
	# it entirely would leave the old call site's removal comment above
	# pointing at nothing — kept for traceability; safe to delete outright
	# once this is confirmed stable.
	pass

func _leading_scrub_rebuild(ctx: Dictionary) -> void:
	var target_polymerase_x: float = ctx.target_polymerase_x
	var is_done_phase: bool = ctx.is_done_phase
	var num_slots: int = ctx.num_slots
	var target_slot: int = ctx.target_slot
	var nucleotide_original_x = ctx.nucleotide_original_x

	# ---- Free leading markers when before first base ----
	if target_polymerase_x < nucleotide_original_x[0]:
		if marker_leading_5p and is_instance_valid(marker_leading_5p):
			marker_leading_5p.queue_free()
			marker_leading_5p = null
		if marker_leading_3p and is_instance_valid(marker_leading_3p):
			marker_leading_3p.queue_free()
			marker_leading_3p = null

	# ---- Rebuild leading strand ----
	for base in leading_synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in leading_hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	leading_synthesized_bases.clear()
	leading_hydrogen_bonds.clear()
	leading_synthesized_bases.resize(num_slots)
	leading_hydrogen_bonds.resize(num_slots)

	for mark in leading_strand_bond_marks:
		if mark != null and is_instance_valid(mark): mark.queue_free()
	leading_strand_bond_marks.clear()

	# leading_synth_count mirrors _capture_on_leading_slot_reached()'s own
	# formula (target = index + 1 - polymerase_x_offset_slots) directly, off
	# target_slot, rather than re-deriving it independently via an x-position
	# threshold — the two had silently drifted apart before. This count is
	# exactly what's complete at this instant (matches where the polymerase
	# clamp itself is rendered); the scrub/resume gap this used to cause is
	# now closed on the live-trigger side instead (see the catch-up check in
	# _capture_on_leading_slot_reached()), so this stays physically accurate
	# rather than over-filling by a slot to paper over it.
	var leading_synth_count: int
	if is_done_phase:
		leading_synth_count = num_slots
	else:
		leading_synth_count = int(clamp(float(target_slot) + 1.0 - sim.polymerase_x_offset_slots, 0.0, float(num_slots)))

	for i in range(leading_synth_count):
		if leading_synthesized_bases[i] == null:
			# Reverted — see get_synthesized_nucleotides()'s matching comment.
			leading_synthesized_bases[i] = _spawn_leading_base(i, sim.dna_sequence.get_complement(i))
			leading_hydrogen_bonds[i] = _spawn_leading_hydrogen_bonds(i)

func _leading_render(ctx: Dictionary) -> void:
	var wobble_t: float = ctx.wobble_t
	var dna_ribbons_gap: float = ctx.dna_ribbons_gap
	var new_top_template_y: float = ctx.new_top_template_y
	var nucleotide_original_x = ctx.nucleotide_original_x

	# ---- Leading strand backbone ----
	var leading_points = PackedVector2Array()
	for i in range(leading_synthesized_bases.size()):
		if leading_synthesized_bases[i] != null:
			var wobble_y = sim.get_wobble_y(i, wobble_t)
			var world_x = nucleotide_original_x[i]
			var leading_y = new_top_template_y - dna_ribbons_gap + wobble_y
			leading_synthesized_bases[i].position = Vector2(world_x, leading_y)
			# Bug A fix (MolecularStructure_BasePairExpansion.md): per-slot,
			# live occlusion of the bead circle whenever the molecule
			# renderer is drawing this residue in skeletal mode. Backbone
			# line/marks/hydrogen-bond suppression is now handled in
			# _apply_highlight() instead (single-writer fix — this file used
			# to also write those same properties here, racing against
			# _apply_highlight()'s own strand_dim write later in the same
			# render() call and losing).
			if molecule_renderer != null:
				var bead_fade: float = molecule_renderer.get_bead_fade_amount("leading", i)
				leading_synthesized_bases[i].modulate.a = 1.0 - bead_fade
				leading_synthesized_bases[i].set_desaturation_amount(molecule_renderer.get_transition_desaturation_amount())
			else:
				leading_synthesized_bases[i].modulate.a = 1.0
			if leading_hydrogen_bonds[i] != null:
				var top_template_y = new_top_template_y + wobble_y
				leading_hydrogen_bonds[i].position = Vector2(world_x, top_template_y)
				sim._update_hydrogen_bond_height(leading_hydrogen_bonds[i], leading_y - top_template_y)
			leading_points.append(Vector2(world_x, leading_y - tm.backbone_offset_distance))
	leading_backbone_line.points = leading_points
	leading_backbone_line.width = tm.backbone_line_width
	_update_bond_marks_leading(leading_points)

	# ---- Leading strand markers ----
	# Hidden while atom-tier skeletal rendering is active — see the matching
	# comment in simulation.gd's marker block for the full rationale.
	var atom_tier_active: bool = molecule_renderer != null and molecule_renderer.is_molecular_mode_active()
	if marker_leading_5p == null and leading_synthesized_bases[0] != null:
		var wobble_first = sim.get_wobble_y(0, wobble_t)
		var leading_y = new_top_template_y - dna_ribbons_gap + wobble_first
		marker_leading_5p = _spawn_marker("3'", Vector2(
			nucleotide_original_x[0] - tm.marker_offset,
			leading_y - tm.backbone_offset_distance
		))
	if marker_leading_5p:
		var wobble_first = sim.get_wobble_y(0, wobble_t)
		var leading_y = new_top_template_y - dna_ribbons_gap + wobble_first
		marker_leading_5p.position = Vector2(
			nucleotide_original_x[0] - tm.marker_offset,
			leading_y - tm.backbone_offset_distance
		)
		marker_leading_5p.visible = not atom_tier_active
	if marker_leading_3p == null and leading_synthesized_bases[0] != null:
		var last_synth = -1
		for i in range(leading_synthesized_bases.size()):
			if leading_synthesized_bases[i] != null: last_synth = i
		if last_synth >= 0:
			var wobble_last = sim.get_wobble_y(last_synth, wobble_t)
			var leading_y = new_top_template_y - dna_ribbons_gap + wobble_last
			marker_leading_3p = _spawn_marker("5'", Vector2(
				nucleotide_original_x[last_synth] + tm.marker_offset,
				leading_y - tm.backbone_offset_distance
			))
	if marker_leading_3p:
		var last_synth = -1
		for i in range(leading_synthesized_bases.size()):
			if leading_synthesized_bases[i] != null: last_synth = i
		if last_synth >= 0:
			var wobble_last = sim.get_wobble_y(last_synth, wobble_t)
			var leading_y = new_top_template_y - dna_ribbons_gap + wobble_last
			marker_leading_3p.position = Vector2(
				nucleotide_original_x[last_synth] + tm.marker_offset,
				leading_y - tm.backbone_offset_distance
			)
		marker_leading_3p.visible = not atom_tier_active

## Backward scan for the last synthesized leading slot — same shape as the
## leading-marker code's own last_synth scan above, kept as a separate
## small helper here (not factored together) so this function's only job
## is answering the question, not also owning marker positioning.
func _leading_latest_synthesized_slot() -> int:
	for i in range(leading_synthesized_bases.size() - 1, -1, -1):
		if leading_synthesized_bases[i] != null:
			return i
	return -1

## Zoom-derived (never time-based) fade + position swap for the leading Pol
## III clamp container, mirroring _ligase_apply_atom_tier_position_swap()'s
## pattern. Simpler gating than ligase's: leading_polymerase.position is
## already rewritten fresh every frame with no tween (see the "if
## leading_polymerase and phase != DONE" write in update()), so there's no
## discrete state machine to key off — this just needs synthesis to have
## actually started (a slot exists to query).
func _leading_apply_atom_tier_position_swap(ctx: Dictionary) -> void:
	if leading_polymerase == null or molecule_renderer == null:
		return
	# Unlike _lagging_apply_atom_tier_position_swap()'s own gate (which
	# naturally goes -1 once no fragment is open) and
	# _ligase_apply_atom_tier_position_swap()'s _ligase_state gate,
	# _leading_latest_synthesized_slot() stays >= 0 forever once synthesis
	# has started — so this needs its own explicit "run is over" check, or
	# it fights both _polymerases_move_to_rest()'s slide-to-rest tween
	# (while ligase/Pol I are still catching up on the lagging tail) and
	# _lagging_fade_enzyme_scene()'s later fade-out tween, snapping
	# leading_polymerase back to the last synthesized slot's position each
	# frame. _polymerases_at_rest goes true first (at _polymerases_move_to_
	# rest()) and stays true through the later fade, so gating on it alone
	# covers both.
	if _polymerases_at_rest:
		return
	var latest_slot: int = _leading_latest_synthesized_slot()
	if latest_slot < 0:
		return

	var t: float = molecule_renderer.get_transition_fraction()
	var active: bool = molecule_renderer.is_molecular_mode_active()
	var edge: float = 0.0 if active else 1.0
	var half_width: float = max(tm.polymerase_atom_swap_dip_half_width, 0.001)
	var dip_shape: float = clamp(1.0 - abs(t - edge) / half_width, 0.0, 1.0)
	leading_polymerase.modulate.a = 1.0 - dip_shape * tm.polymerase_atom_swap_dip_peak_amount

	# leading_clamp/leading_halo self-offset by a bead-scale
	# ±dna_ribbons_gap/2 local Y every frame (duplex-centre registration) —
	# that offset must be suppressed while this container sits at an
	# atom-tier anchor, or the child silently re-introduces a bead-scale
	# displacement on top of the swap above.
	var atom_positioned: bool = active and molecule_renderer.has_slot_o3_position("leading", latest_slot)
	if leading_clamp != null:
		leading_clamp.set_atom_tier_offset_suppressed(atom_positioned)
	if leading_halo != null:
		leading_halo.set_atom_tier_offset_suppressed(atom_positioned)

	if atom_positioned:
		leading_polymerase.position = molecule_renderer.get_slot_o3_position("leading", latest_slot)
	else:
		# Bead-tier fallback: render()'s own ctx has no polymerase_x key
		# (that's only in update()'s separate ctx dict) — ctx_polymerase_x
		# is the instance field update() already caches from it each frame,
		# and update() runs before render() every _process() tick, so it's
		# always fresh here.
		leading_polymerase.position = Vector2(ctx_polymerase_x, ctx.new_top_template_y)

func _spawn_leading_base(index: int, base_type: String, start_pos = null) -> Node2D:
	var base = sim.NewNitrogenBaseScene.instantiate()
	var world_x = sim.nucleotide_original_x[index]
	var leading_y = sim.new_top_template_y - sim.dna_ribbons_gap
	base.position = start_pos if start_pos != null else Vector2(world_x, leading_y)
	base.z_index = 2
	sim.add_child(base)
	base.set_base_type(base_type)
	base.set_radius(tm.base_radius)
	base.set_colors(sim._get_base_fill(base_type), tm.base_label_color)
	base.set_font(tm.base_label_font_size, tm.base_label_font)
	base.set_label_rotation(_zoom_label_rotation())
	base.desaturation_gray_target = tm.molecular_bead_desaturation_gray_target
	return base

func _spawn_leading_hydrogen_bonds(index: int) -> Node2D:
	# Reverted — leading's real template is template_top, whose REAL
	# displayed letter (simulation.gd's _spawn_top_strand()) is
	# get_base(index), not get_complement(index). Functionally invisible
	# either way since hydrogen_bond_count()/bond color only depend on
	# AT-vs-GC family, which a base and its complement always share — kept
	# consistent with the real formula anyway, not left mismatched.
	var template_base = sim.dna_sequence.get_base(index)
	var bond_count = NitrogenBaseDeriver.hydrogen_bond_count(template_base)
	var bond_color = tm.cg_bond_color if (template_base == "C" or template_base == "G") else tm.at_bond_color
	var container = Node2D.new()
	container.position = Vector2(sim.nucleotide_original_x[index], sim.new_top_template_y)
	var total_width = (bond_count - 1) * tm.hydrogen_bond_spacing
	var start_x = -total_width / 2.0
	var inset = tm.base_radius - 3.0
	for b in range(bond_count):
		var line = Line2D.new()
		var lx = start_x + b * tm.hydrogen_bond_spacing
		line.add_point(Vector2(lx, -inset))
		line.add_point(Vector2(lx, -(sim.dna_ribbons_gap - inset)))
		line.default_color = bond_color
		line.width = tm.hydrogen_bond_width
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		container.add_child(line)
	sim.hydrogen_bonds_container.add_child(container)
	return container

func _update_bond_marks_leading(points: PackedVector2Array) -> void:
	var needed = max(0, points.size() - 1)
	while leading_strand_bond_marks.size() < needed:
		leading_strand_bond_marks.append(_create_bond_mark_sprite())
	while leading_strand_bond_marks.size() > needed:
		var extra = leading_strand_bond_marks.pop_back()
		if extra != null and is_instance_valid(extra): extra.queue_free()
	for i in range(needed):
		var a = points[i]
		var b = points[i + 1]
		var mid = (a + b) / 2.0
		var segment = b - a
		var mark = leading_strand_bond_marks[i]
		mark.position = mid
		mark.visible = segment.length() > 0.0
		if mark.visible:
			mark.rotation = segment.angle()

# ==========================================
# LAGGING STRAND — self-contained section
# ==========================================
# Owns: lagging_fragments, lagging_current_fragment.
# Synthesis trigger: helicase.slot_reached signal (not position-based, since
# fragments need discrete boundaries at okazaki_fragment_size).
# Slot mapping: when helicase reaches `index`, the lagging polymerase's
# trailing position corresponds to slot (index - polymerase_x_offset_slots),
# matching the polymerase_x formula in simulation.gd exactly.

func connect_helicase(helicase_mgr: Node) -> void:
	connected_helicase_mgr = helicase_mgr
	if not helicase_mgr.slot_reached.is_connected(_on_helicase_slot_reached):
		helicase_mgr.slot_reached.connect(_on_helicase_slot_reached)
	if not helicase_mgr.slot_reached.is_connected(_capture_on_leading_slot_reached):
		helicase_mgr.slot_reached.connect(_capture_on_leading_slot_reached)
	if not helicase_mgr.phase_changed.is_connected(_on_helicase_phase_changed):
		helicase_mgr.phase_changed.connect(_on_helicase_phase_changed)

func _lagging_reset(num_slots: int) -> void:
	lagging_fragments.clear()
	lagging_current_fragment = null
	lagging_telomere_gap = null
	lagging_synthesized_bases.clear()
	lagging_hydrogen_bonds.clear()
	for i in range(num_slots):
		lagging_synthesized_bases.append(null)
		lagging_hydrogen_bonds.append(null)
	lagging_total_fragments = num_slots / sim.okazaki_fragment_size
	lagging_firing_started = false
	lagging_fade_in_started = false
	lagging_total_consumed = 0
	lagging_batch_cursor = 0
	lagging_polymerase_x = 0.0
	_lagging_fade_pending = false
	_terminal_removal_started = false
	_polymerases_at_rest = false
	if lagging_catchup_timer != null:
		lagging_catchup_timer.stop()
	if lagging_polymerase_tween != null and lagging_polymerase_tween.is_valid():
		lagging_polymerase_tween.kill()
	_ligase_reset_visual()
	_primase_blip_reset_visual()
	_primase_clear_pending_backbones()
	_pol1_reset_visual()

func _lagging_setup_backbones() -> void:
	if lagging_backbone_line != null and is_instance_valid(lagging_backbone_line):
		lagging_backbone_line.queue_free()
	lagging_backbone_line = Line2D.new()
	lagging_backbone_line.default_color = tm.backbone_color
	lagging_backbone_line.width = tm.backbone_line_width
	lagging_backbone_line.z_index = -1
	lagging_backbone_line.joint_mode = Line2D.LINE_JOINT_ROUND
	lagging_backbone_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	lagging_backbone_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	sim.add_child(lagging_backbone_line)

func _lagging_teardown() -> void:
	for base in lagging_synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in lagging_hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	lagging_synthesized_bases.clear()
	lagging_hydrogen_bonds.clear()

	var all_fragments = lagging_fragments.duplicate()
	if lagging_current_fragment != null:
		all_fragments.append(lagging_current_fragment)
	for frag in all_fragments:
		if frag.backbone != null and is_instance_valid(frag.backbone):
			frag.backbone.queue_free()
		if frag.get("primer_backbone", null) != null and is_instance_valid(frag.primer_backbone):
			frag.primer_backbone.queue_free()
		for mark in frag.bond_marks:
			if mark != null and is_instance_valid(mark): mark.queue_free()
		for mark in frag.get("primer_bond_marks", []):
			if mark != null and is_instance_valid(mark): mark.queue_free()
		if frag.marker_5p != null and is_instance_valid(frag.marker_5p):
			frag.marker_5p.queue_free()
		if frag.marker_3p != null and is_instance_valid(frag.marker_3p):
			frag.marker_3p.queue_free()

	if lagging_backbone_line != null and is_instance_valid(lagging_backbone_line):
		lagging_backbone_line.queue_free()
	for mark in lagging_bond_marks:
		if mark != null and is_instance_valid(mark): mark.queue_free()
	lagging_bond_marks.clear()

	lagging_fragments.clear()
	lagging_current_fragment = null

func _on_helicase_slot_reached(index: int) -> void:
	# Fires ahead of every early-return below — primase acts on newly-
	# exposed template as soon as the helicase passes it, independent of
	# Pol III's own backlog/startup delay (which can lag many steps behind).
	# See _primase_check_slot() for why this is safe to compute purely from
	# tiling geometry, with no dependency on lagging_current_fragment/
	# lagging_total_consumed at all.
	_primase_check_slot(index)

	if lagging_total_consumed >= sim.num_nucleotide_slots:
		return

	if not lagging_firing_started:
		if index < sim.okazaki_fragment_size + sim.pll_slot_count:
			return
		lagging_firing_started = true
		lagging_fade_in_started = true
		if lagging_polymerase != null:
			lagging_polymerase.modulate.a = 1.0

	if lagging_current_fragment == null:
		_lagging_open_next_fragment()

	_lagging_fire_step(sim.helicase_mgr.step_duration)

func _lagging_fire_step(duration: float) -> void:
	var slot_index = lagging_batch_cursor
	lagging_current_fragment.slots.push_front(slot_index)  # push_front: firing goes right-to-left, so this keeps the array ascending
	_capture_begin_lagging(slot_index, duration)

	lagging_polymerase_x = sim.nucleotide_original_x[slot_index]
	if lagging_polymerase:
		if lagging_polymerase_tween != null and lagging_polymerase_tween.is_valid():
			lagging_polymerase_tween.kill()
		lagging_polymerase_tween = sim.create_tween()
		lagging_polymerase_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		lagging_polymerase_tween.tween_property(lagging_polymerase, "position", Vector2(lagging_polymerase_x, sim.new_bottom_template_y), duration)

	# Pump the lagging clamp 0->1->0 over the same duration, matching the
	# leading strand's sin(step_t*PI) shape — opens mid-move, clamps on arrival.
	# Same call site for live and catch-up firing, so both are covered.
	if lagging_clamp != null:
		if lagging_pump_tween != null and lagging_pump_tween.is_valid():
			lagging_pump_tween.kill()
		lagging_pump_tween = sim.create_tween()
		lagging_pump_tween.tween_method(_set_lagging_pump_phase, 0.0, 1.0, duration)

	lagging_total_consumed += 1
	lagging_batch_cursor -= 1

	if lagging_current_fragment.slots.size() >= sim.okazaki_fragment_size or lagging_total_consumed >= sim.num_nucleotide_slots:
		_lagging_close_fragment()

## Zoom-derived (never time-based) fade + position swap for the lagging Pol
## III clamp container. Structurally different from the leading version:
## lagging_polymerase.position is driven by a per-fire-step Tween
## (_lagging_fire_step() above), with no tween-free discrete state to key
## off the way ligase has HOLDING/SEALING — so this gates on the tween
## itself being inactive, never touching position while it's mid-travel
## (the same "never race a tween" discipline the ligase swap's own
## HOLDING/SEALING gate exists for).
##
## Known, accepted limitation: because lagging fires frequently (once per
## synthesized base) and each fire-step re-triggers the tween, this swap
## visibly toggles off (bead position, mid-tween) then on (atom position,
## once settled) every fire cycle while at atom zoom. Shipped scoped like
## this first, per CQA to judge whether the flicker is distracting enough
## to warrant smoothing out.
func _lagging_apply_atom_tier_position_swap() -> void:
	if lagging_polymerase == null or molecule_renderer == null:
		return
	if lagging_polymerase_tween != null and lagging_polymerase_tween.is_valid():
		return  # tween owns position mid-travel -- never race it
	var latest_slot: int = _lagging_latest_fired_slot()
	if latest_slot < 0:
		return

	var t: float = molecule_renderer.get_transition_fraction()
	var active: bool = molecule_renderer.is_molecular_mode_active()
	var edge: float = 0.0 if active else 1.0
	var half_width: float = max(tm.polymerase_atom_swap_dip_half_width, 0.001)
	var dip_shape: float = clamp(1.0 - abs(t - edge) / half_width, 0.0, 1.0)
	lagging_polymerase.modulate.a = 1.0 - dip_shape * tm.polymerase_atom_swap_dip_peak_amount

	# See the matching comment in _leading_apply_atom_tier_position_swap()
	# for why lagging_clamp/lagging_halo's own bead-scale duplex-centre
	# offset must be suppressed while this container sits at an atom-tier
	# anchor.
	var atom_positioned: bool = active and molecule_renderer.has_slot_o3_position("lagging", latest_slot)
	if lagging_clamp != null:
		lagging_clamp.set_atom_tier_offset_suppressed(atom_positioned)
	if lagging_halo != null:
		lagging_halo.set_atom_tier_offset_suppressed(atom_positioned)

	if atom_positioned:
		lagging_polymerase.position = molecule_renderer.get_slot_o3_position("lagging", latest_slot)
	else:
		lagging_polymerase.position = Vector2(lagging_polymerase_x, sim.new_bottom_template_y)

## The most-recently-fired lagging slot: lagging_current_fragment.slots[0]
## (the front of the ascending array, per push_front's own "firing goes
## right-to-left" ordering — see _lagging_fire_step()), or -1 if no
## fragment is currently open (a brief window between a fragment closing
## and the next one opening).
func _lagging_latest_fired_slot() -> int:
	if lagging_current_fragment == null or lagging_current_fragment.slots.size() == 0:
		return -1
	return lagging_current_fragment.slots[0]

## This project keeps exactly one active debug-log investigation at a
## time, always bound to F1 — press F1 while the scene is running to fire
## it. Currently wired to the "both polymerases render on the top strand
## row" bug report: prints each strand's atom-tier slot/position data
## alongside its bead-tier fallback, so the actual runtime numbers can
## pinpoint the mechanism instead of further static-analysis guessing.
## Raw-keypress-with-edge-detection, print() only — nothing that stresses
## the remote debugger connection. When this investigation wraps, the next
## one repurposes this same block/comment rather than leaving a stale
## F-key dump behind.
var _polymerase_debug_key_was_down: bool = false

func _debug_dump_polymerase_atom_tier_state(ctx: Dictionary) -> void:
	var key_down: bool = Input.is_key_pressed(KEY_F1)
	if not key_down or _polymerase_debug_key_was_down:
		_polymerase_debug_key_was_down = key_down
		return
	_polymerase_debug_key_was_down = key_down
	if molecule_renderer == null:
		print("[POLY DEBUG] molecule_renderer is null")
		return

	var t: float = molecule_renderer.get_transition_fraction()
	var active: bool = molecule_renderer.is_molecular_mode_active()
	print("[POLY DEBUG] transition_fraction=%s active=%s" % [t, active])

	var leading_slot: int = _leading_latest_synthesized_slot()
	var leading_has: bool = leading_slot >= 0 and molecule_renderer.has_slot_o3_position("leading", leading_slot)
	print("[POLY DEBUG] leading: slot=%d has_atom=%s atom_pos=%s container_pos=%s bead_fallback=%s" % [
		leading_slot, leading_has,
		molecule_renderer.get_slot_o3_position("leading", leading_slot) if leading_has else "n/a",
		leading_polymerase.position if leading_polymerase != null else "n/a",
		Vector2(ctx_polymerase_x, ctx.new_top_template_y),
	])

	var lagging_slot: int = _lagging_latest_fired_slot()
	var lagging_has: bool = lagging_slot >= 0 and molecule_renderer.has_slot_o3_position("lagging", lagging_slot)
	var lagging_tween_active: bool = lagging_polymerase_tween != null and lagging_polymerase_tween.is_valid()
	print("[POLY DEBUG] lagging: slot=%d has_atom=%s atom_pos=%s container_pos=%s bead_fallback=%s tween_active=%s" % [
		lagging_slot, lagging_has,
		molecule_renderer.get_slot_o3_position("lagging", lagging_slot) if lagging_has else "n/a",
		lagging_polymerase.position if lagging_polymerase != null else "n/a",
		Vector2(lagging_polymerase_x, sim.new_bottom_template_y),
		lagging_tween_active,
	])

func _lagging_open_fragment() -> void:
	lagging_current_fragment = {
		slots = [],
		loop_queue = [],
		backbone = null,
		primer_backbone = null,
		bond_marks = [],
		primer_bond_marks = [],
		marker_5p = null,
		marker_3p = null,
		complete = false,
		sealed = false,
		primer_removed = false,   # see POL I section
	}

func _lagging_open_next_fragment() -> void:
	_lagging_open_fragment()
	var remaining = sim.num_nucleotide_slots - lagging_total_consumed
	var this_fragment_size = min(sim.okazaki_fragment_size, remaining)
	lagging_batch_cursor = lagging_total_consumed + this_fragment_size - 1

	# Adopt (not recreate) any pending primer backbone primase already built
	# for this tile — see _primase_ensure_pending_backbone()/_lagging_render()'s
	# pending-backbone pass. tile_end here is always lagging_batch_cursor + 1,
	# same formula _primase_tile_end() uses (verified equal for both full and
	# short-final tiles).
	var tile_end = lagging_batch_cursor + 1
	if primase_pending_backbones.has(tile_end):
		var entry = primase_pending_backbones[tile_end]
		lagging_current_fragment.primer_backbone = entry.backbone
		lagging_current_fragment.primer_bond_marks = entry.bond_marks
		primase_pending_backbones.erase(tile_end)

func _lagging_close_fragment() -> void:
	lagging_current_fragment.complete = true
	lagging_fragments.append(lagging_current_fragment)
	lagging_current_fragment = null
	if _pol1_enabled() and lagging_fragments.size() >= 2:
		_pol1_enqueue_job(lagging_fragments[-2])
	_ligase_kick()

# ==========================================
# LIGASE — Complex tier (OkazakiMaturationDesign.md)
# Self-contained section, same _lagging_*-style isolation this file already
# uses for its other sub-systems. Two triggers funnel into the same
# idempotent _ligase_kick(): _lagging_close_fragment() above (event-driven,
# fires the instant Pol III finishes a fragment) and
# _on_complexity_toggle_changed() below (fires once, if ligase is switched
# on after fragments already piled up while it was off — the "catch-up"
# case). Neither needs to know about the other.
# ==========================================

# ==========================================
# PRIMASE — RNA primer persistence pass
# No longer a purely decorative blip. Trigger is still
# _on_helicase_slot_reached() above, but _is_primer_slot()'s tiling-geometry
# math now covers every slot in a fragment's primer span (not just its
# single anchor slot), and each one gets a REAL ribonucleotide placed —
# captured from primase's own PolymeraseHalo (same mechanic Pol III's own
# capture uses, just a single-leg flight since primase has no clamp to
# route through), spawned RNA-colored, persisted into
# lagging_synthesized_bases directly. No independent pacing constant: each
# placement is driven by its own helicase-passage event, so primase's
# cadence already IS the helicase's cadence.
#
# The span's anchor slot (tile_end - 1, highest index) is unchanged from the
# original single-slot design — same already-correct, already-tested
# position. The span extends DOWNWARD in index from there across
# primer_length_slots() slots. Since the helicase sweeps low-to-high,
# chronologically primase actually visits the span's LOW end first and the
# anchor slot last — this has no bearing on which end is 5'/3' for marker
# purposes (that's governed entirely by Pol III's own separate firing order
# when it later tiles frag.slots — see the Revision History note in
# OkazakiMaturationDesign.md about the marker investigation this pass
# prompted, which turned out not to be a bug).
#
# The blob's own appear/pulse/hold/fade lifecycle is now spread across
# MULTIPLE calls instead of built as one tween chain in a single call:
# fade-in fires on the span's first slot, fade-out (after a short hold) on
# its last — same shape as before, just driven by repeated events rather
# than one.
#
# The PLACED BASES never fade — real persisted state, RNA-colored until
# Pol I exists to flip them (per the "held" decision). Only the enzyme
# itself has a lifecycle.
#
# Never fires during scrub: _lagging_scrub_rebuild() colors primer-span
# bases directly via _is_primer_slot(), without replaying any placement
# animation — so this needs no scrub-specific guard beyond the in-flight-
# tween-kill every other transient animation here already gets.
# ==========================================

## Live-samples the SAME bottom-template rail curve the template row's own
## rendering uses (simulation.gd's _process()) — needed because a slot's row
## is still transitioning (bonded -> unzipped) for several slots after the
## helicase passes it, and primase places real bases there well before that
## transition completes. Converges to new_bottom_template_y automatically
## once a slot's row has settled, so this is safe to use unconditionally.
func _lagging_template_y_at(world_x: float) -> float:
	var curve = sim.rail_path.curve if sim.rail_path else null
	if curve == null:
		return sim.new_bottom_template_y
	return sim._sample_curve_y_at_x(curve.get_baked_points(), world_x, sim.template_strand_y)

## Which tile does `index` belong to, and where does that tile actually end
## (one past its highest slot) — accounting for a short final tile the same
## way _lagging_scrub_rebuild() already does (true_tile_end = min(tile_start+F, num_slots)).
func _primase_tile_end(index: int) -> int:
	var f = sim.okazaki_fragment_size
	var tile_start = (index / f) * f
	return min(tile_start + f, sim.num_nucleotide_slots)

## Ratio of okazaki_fragment_size (tm.primer_length_ratio), clamped so a
## primer never consumes an entire fragment (always leaves at least one slot
## for Pol III to actually extend) and is never zero.
func _primase_primer_length() -> int:
	var f = sim.okazaki_fragment_size
	return clampi(int(round(f * tm.primer_length_ratio)), 1, f - 1)

## Purely geometric — true if `index` falls within its tile's primer span
## (the top primer_length() slots of that tile, ending at the same
## fragment-start position primase already anchored on before this pass).
## No dependency on Pol III's own progress.
func _is_primer_slot(index: int) -> bool:
	var num_slots = sim.num_nucleotide_slots
	if index < 0 or index >= num_slots:
		return false
	var tile_end = _primase_tile_end(index)
	var span = _primase_primer_length()
	return (tile_end - index) <= span

## Expects an RNA letter (post T->U substitution) — see _primase_place_primer_base().
## Pol III "absorbing Pol I's job" at Light-tier complexity (per
## OkazakiMaturationDesign.md's original proposal, now unblocked now that
## primer state actually persists): converts an already-placed primer base
## to DNA in place the instant Pol III's fire-step passes over it, instead
## of just skipping it silently. Recolor + reshape only — instant, not
## animated (shape can't smoothly interpolate between a custom-drawn circle
## and rounded-square without real polygon morphing, so animating color
## alone while shape snaps would look like a mismatch; simplicity matches
## this feature's own Light-tier spirit).
## Recolor + reshape an already-placed primer base to DNA in place — shared
## by both tiers' conversion moment (Light tier's instant stand-in below,
## and Complex tier's Pol I animated sweep, see POL I section). Assumes the
## caller has already confirmed this is a primer slot with a not-yet-
## converted base present.
func _convert_primer_base_to_dna(index: int) -> void:
	var node = lagging_synthesized_bases[index]
	if node == null or node.shape != "rounded_square":
		return  # already converted, or nothing there yet
	# Reverted (docs/MolecularStructure_BasePairExpansion.md, Bug E
	# follow-up): lagging's real template is template_bottom, whose REAL
	# displayed letter (simulation.gd's _spawn_bottom_strand()) is
	# get_complement(i), not get_base(i) as get_template_nucleotides()
	# claimed — see get_synthesized_nucleotides()'s comment in this file
	# for the full account. Lagging (template_bottom's complement) must be
	# get_base(i).
	var base_type = sim.dna_sequence.get_base(index)  # real letter — converting back to DNA, T not U
	node.set_base_type(base_type)
	node.set_shape("circle")
	node.set_colors(sim._get_base_fill(base_type), tm.base_label_color)

## Pol III "absorbing Pol I's job" at Light-tier complexity — unchanged
## behavior, now just delegating the actual conversion work.
func _pol3_convert_primer_if_needed(index: int) -> void:
	if complexity_mgr == null or not complexity_mgr.is_enabled("primase"):
		return
	if not _is_primer_slot(index):
		return
	# Gap mode: the terminal primer footprint is the telomere gap. Pol III
	# must NOT absorb it into DNA (as it does at Light tier), or there'd be
	# nothing left to remove and no gap. Left as RNA, it's faded out by the
	# terminal-removal step at strand completion instead.
	if complexity_mgr.is_enabled("lagging_gap") and index >= sim.num_nucleotide_slots - _primase_primer_length():
		return
	_convert_primer_base_to_dna(index)

## Supersedes pure-geometry _is_primer_slot() for RENDERING purposes (backbone
## split) once conversion exists — a slot can be geometrically within the
## primer span but already converted, so geometry alone isn't enough anymore.
## _is_primer_slot() itself stays pure geometry — still needed as-is for the
## placement TRIGGER, which only ever asks "is this slot part of a primer
## span" before the base exists to have a shape at all.
func _is_still_primer(index: int) -> bool:
	if not _is_primer_slot(index):
		return false
	var node = lagging_synthesized_bases[index]
	return node != null and node.shape == "rounded_square"

func _primer_rna_color_for(base_type: String) -> Color:
	match base_type:
		"A": return tm.rna_base_color_a
		"U": return tm.rna_base_color_u
		"C": return tm.rna_base_color_c
		"G": return tm.rna_base_color_g
		_: return tm.rna_base_color_a

func _primase_check_slot(index: int) -> void:
	if primase_blip == null or complexity_mgr == null or not complexity_mgr.is_enabled("primase"):
		return
	var tile_end = _primase_tile_end(index)
	# Only the anchor (highest index in the span) kicks off the sequence.
	# The helicase sweeps low-to-high, so the anchor is always the LAST
	# slot of the span to become available — waiting for it guarantees the
	# whole span is already exposed before primase places anything. This
	# lets the 3 placements play in Pol III's own high-to-low order, so the
	# whole fragment (primer + DNA) reads as one consistent synthesis
	# direction instead of two opposing ones (previously: primer placed
	# low-to-high as each slot was individually exposed, then Pol III
	# continuing high-to-low into the DNA portion — two strands built in
	# opposite directions within what's meant to read as one fragment).
	if index != tile_end - 1:
		return

	var span = _primase_primer_length()
	var seq: Array = []
	for slot_index in range(tile_end - 1, tile_end - span - 1, -1):
		seq.append(slot_index)
	print("[PRIMASE] placing primer — tile anchor=%d span=%s" % [index, str(seq)])
	_primase_place_sequence(seq, 0)

## Chains through `seq` (already ordered high-to-low) one slot at a time —
## each placement's own tween triggers the next once its pulse completes.
## Stops naturally once seq_pos runs past the end.
func _primase_place_sequence(seq: Array, seq_pos: int) -> void:
	if seq_pos >= seq.size():
		return
	var index = seq[seq_pos]
	var is_first = (seq_pos == 0)
	var is_last = (seq_pos == seq.size() - 1)
	_primase_place_primer_base(index, is_first, is_last, seq, seq_pos)

## Creates the tile's pending backbone Line2D if it doesn't exist yet.
## Points are NOT computed here — _lagging_render()'s own pending-backbone
## pass recomputes them fresh every frame, same "derive don't patch"
## approach as everything else in this file.
func _primase_ensure_pending_backbone(tile_end: int) -> void:
	if primase_pending_backbones.has(tile_end):
		return
	var line = Line2D.new()
	line.default_color = tm.rna_backbone_color
	line.width = tm.rna_backbone_line_width
	line.z_index = -1
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	sim.add_child(line)
	primase_pending_backbones[tile_end] = { backbone = line, bond_marks = [] }

## Frees every pending backbone — used on a fresh sequence load and during
## scrub (any scrub invalidates live-play pending state; scrub reconstructs
## fragments directly via the tile rebuild, never through this mechanism).
func _primase_clear_pending_backbones() -> void:
	for tile_end in primase_pending_backbones.keys():
		var entry = primase_pending_backbones[tile_end]
		if entry.backbone != null and is_instance_valid(entry.backbone):
			entry.backbone.queue_free()
		for mark in entry.bond_marks:
			if mark != null and is_instance_valid(mark): mark.queue_free()
	primase_pending_backbones.clear()

## Places one real, RNA-colored ribonucleotide at `index` and drives the
## blob's own appear/pulse/[hold/fade] lifecycle for this step, chaining to
## the next step in `seq` once this one's pulse completes.
func _primase_place_primer_base(index: int, is_first: bool, is_last: bool, seq: Array, seq_pos: int) -> void:
	if lagging_synthesized_bases[index] != null:
		# Shouldn't normally happen (the anchor trigger guarantees a fresh
		# sequence each time) — but stay idempotent and advance the chain
		# rather than silently stalling on a stray already-placed slot.
		_primase_place_sequence(seq, seq_pos + 1)
		return
	_primase_ensure_pending_backbone(_primase_tile_end(index))
	# Reverted — see _convert_primer_base_to_dna()'s comment.
	var base_type = sim.dna_sequence.get_base(index)
	if base_type == "T":
		base_type = "U"  # rendering-layer only — real RNA has no thymine. The
		# underlying sequence data (re-read via get_base() by anything else,
		# e.g. Pol III's own skipped capture attempt) is untouched.
	var target_x = sim.nucleotide_original_x[index]
	var target_y = _lagging_template_y_at(target_x) + sim.dna_ribbons_gap
	# Paced by the helicase's own step_duration, same fix Pol I's own
	# per-slot sweep got — previously used the flat primase_capture_duration
	# constant, so all 3 primer bases chained through in real time far
	# faster than 3 actual helicase steps would take. fade_in/hold/fade_out
	# stay their own separate constants — those are visual flourish (appear/
	# settle/disappear feel), not stepping pace.
	var step_duration: float = sim.helicase_mgr.step_duration

	if _primase_tween != null and _primase_tween.is_valid():
		_primase_tween.kill()
	_primase_tween = sim.create_tween()

	if is_first:
		primase_blip.position = Vector2(target_x, target_y)
		primase_blip.modulate.a = 0.0
		_primase_tween.tween_property(primase_blip, "modulate:a", 1.0, tm.primase_blip_fade_in_duration)
	else:
		_primase_tween.tween_property(primase_blip, "position", Vector2(target_x, target_y), step_duration)

	_primase_tween.tween_method(primase_blip.set_pulse, 0.0, 1.0, step_duration * 0.25)
	_primase_tween.tween_method(primase_blip.set_pulse, 1.0, 0.0, step_duration * 0.25)

	if is_last:
		_primase_tween.tween_interval(tm.primase_blip_hold_duration)
		_primase_tween.tween_property(primase_blip, "modulate:a", 0.0, tm.primase_blip_fade_out_duration)
	else:
		_primase_tween.tween_callback(_primase_place_sequence.bind(seq, seq_pos + 1))

	# The placed base is its own separate node/tween/lifecycle — same
	# separation Pol III's own capture keeps between the polymerase's
	# position tween and the captured base's own flight.
	var start_pos = primase_halo.capture_particle(base_type) if primase_halo != null else Vector2(target_x, target_y)
	var color = _primer_rna_color_for(base_type)
	var node = _spawn_lagging_base(index, base_type, start_pos, color, "rounded_square")
	var base_tween = sim.create_tween()
	base_tween.tween_property(node, "position", Vector2(target_x, target_y), step_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	base_tween.tween_callback(_primase_finish_base.bind(index, node))

func _primase_finish_base(index: int, node: Node2D) -> void:
	var world_x = sim.nucleotide_original_x[index]
	node.position = Vector2(world_x, _lagging_template_y_at(world_x) + sim.dna_ribbons_gap)
	lagging_synthesized_bases[index] = node
	lagging_hydrogen_bonds[index] = _spawn_lagging_hydrogen_bonds(index)

## Kills any in-flight blip animation and snaps to invisible/rest. Used
## during scrub and on a fresh sequence load — mirrors
## _ligase_reset_visual()'s shape. Does NOT touch already-placed primer
## bases — those are real persisted state now, untouched by this reset.
func _primase_blip_reset_visual() -> void:
	if _primase_tween != null and _primase_tween.is_valid():
		_primase_tween.kill()
	if primase_blip != null:
		primase_blip.modulate.a = 0.0
		primase_blip.set_pulse(0.0)

func _on_complexity_toggle_changed(feature: String, enabled: bool) -> void:
	if feature == "ligase":
		if enabled:
			_ligase_kick()
		else:
			_ligase_reset_visual()
	elif feature == "pol1":
		if not enabled:
			_pol1_reset_visual()
		# Turning ON mid-run needs no catch-up sweep here: any fragment pair
		# that already closed while pol1 was off was already instant-
		# converted by the Light-tier stand-in — nothing to retroactively
		# undo or reprocess. Going forward, new _lagging_close_fragment()
		# calls pick up the real Pol I path automatically.

# ==========================================
# POL I — Complex tier (OkazakiMaturationDesign.md)
# Real nick-translation, replacing the Light-tier instant stand-in
# entirely when pol1_enabled. Trigger is _lagging_close_fragment() above —
# fully event-count-gated, no independent clock, no real-time backlog risk.
# Queue is pull-model, same idempotent-kick shape ligase already uses.
# ==========================================

## Convenience read — pol1_enabled lives on ComplexityManager itself, unlike
## ligase_enabled (which predates ComplexityManager and still lives directly
## on sim per complexity_manager.gd's migration note). Guards against
## complexity_mgr not being resolved yet.
func _pol1_enabled() -> bool:
	return complexity_mgr != null and complexity_mgr.is_enabled("pol1")

## Builds this fragment's own primer slot sequence (its own top `span`
## slots, high-to-low — same chained order primase itself placed them in)
## and queues it for Pol I.
func _pol1_enqueue_job(frag: Dictionary, remove_only: bool = false) -> void:
	var tile_end = _primase_tile_end(frag.slots[-1])
	var span = _primase_primer_length()
	var seq: Array = []
	for slot_index in range(tile_end - 1, tile_end - span - 1, -1):
		seq.append(slot_index)
	_pol1_queue.append({frag = frag, seq = seq, remove_only = remove_only})
	print("[POL1] job queued — primer span=%s remove_only=%s (queue depth now %d)" % [str(seq), remove_only, _pol1_queue.size()])
	_pol1_kick()

## Idempotent: no-ops if pol1 is off, already busy, or nothing queued.
## Instantiates the node lazily on first-ever call — see pol1.gd's header
## for why this node breaks from ligase/primase's create-once-hide
## lifecycle (real Pol I has no fixed replisome position to occupy before
## it has work).
func _pol1_kick() -> void:
	if not _pol1_enabled() or _pol1_state != Pol1Phase.OFFSTAGE or _pol1_queue.is_empty():
		return
	if pol1 == null:
		print("[POL1] first job ever — instantiating node (true-absence lifecycle)")
		pol1 = Pol1Enzyme.new()
		sim.add_child(pol1)
		pol1.setup(sim)
		pol1.modulate.a = 0.0
	var job: Dictionary = _pol1_queue.pop_front()
	_pol1_state = Pol1Phase.ARRIVING
	var anchor: int = job.seq[0]
	print("[POL1] kick — traveling to anchor slot=%d (queue depth now %d)" % [anchor, _pol1_queue.size()])
	var target_x = sim.nucleotide_original_x[anchor]
	# Sits directly on the lagging strand's own base row, not the backbone
	# line's offset row like ligase — Pol I is working the bases themselves
	# (converting RNA to DNA in place), not sealing a backbone junction, so
	# lining up with the slots it's actually touching reads more clearly.
	var target_y = sim.new_bottom_template_y + sim.dna_ribbons_gap
	pol1.position = Vector2(target_x, target_y + tm.pol1_offstage_drop)
	if _pol1_tween != null and _pol1_tween.is_valid():
		_pol1_tween.kill()
	_pol1_tween = sim.create_tween()
	_pol1_tween.tween_property(pol1, "modulate:a", 1.0, tm.pol1_travel_duration)
	_pol1_tween.parallel().tween_property(pol1, "position", Vector2(target_x, target_y), tm.pol1_travel_duration)
	_pol1_tween.tween_callback(_pol1_work.bind(job, 0))

## Sweeps one primer slot at a time, high-to-low, converting + pulsing each
## in turn before advancing — same chained-tween shape
## _primase_place_sequence() already uses. Paced by the helicase's own
## step_duration (same value _lagging_fire_step() itself uses), not an
## independent constant — keeps Pol I's own bite-rate visually legible and
## in sync with the sim's speed control, rather than racing ahead of it.
func _pol1_work(job: Dictionary, seq_pos: int) -> void:
	var seq: Array = job.seq
	if seq_pos >= seq.size():
		_pol1_finish_job(job)
		return
	_pol1_state = Pol1Phase.WORKING
	var index: int = seq[seq_pos]
	var target_x = sim.nucleotide_original_x[index]
	var step_duration: float = sim.helicase_mgr.step_duration
	var remove_only: bool = job.get("remove_only", false)
	_pol1_tween = sim.create_tween()
	_pol1_tween.tween_property(pol1, "position:x", target_x, step_duration)
	_pol1_tween.tween_callback(func():
		if remove_only:
			_remove_terminal_primer_base(index)
			print("[POL1] removing terminal primer slot %d (%d/%d) — no refill, this is the gap" % [index, seq_pos + 1, seq.size()])
		else:
			_convert_primer_base_to_dna(index)
			print("[POL1] converting slot %d (%d/%d)" % [index, seq_pos + 1, seq.size()])
	)
	# tween_method, not tween_callback — a callback is an instant snap with
	# no visible duration; two of them back-to-back (the original bug here)
	# produce a pulse that's technically 0->1->0 but invisible, since both
	# steps land within the same frame or two. tween_method actually
	# interpolates over real time, same pattern ligase's own seal pulse uses.
	_pol1_tween.tween_method(pol1.set_pulse, 0.0, 1.0, step_duration * 0.25)
	_pol1_tween.tween_method(pol1.set_pulse, 1.0, 0.0, step_duration * 0.25)
	_pol1_tween.tween_callback(_pol1_work.bind(job, seq_pos + 1))

## Marks the fragment's primer removed (the only thing _ligase_kick()'s
## eligibility check actually needs), then leaves the strand — drops +
## fades at wherever this job ended, rather than parking visibly. Kicks
## both ligase (its real Complex-tier trigger now) and its own queue for
## the next pending job.
func _pol1_finish_job(job: Dictionary) -> void:
	if job.get("remove_only", false):
		print("[POL1] terminal removal complete — recording gap, primer will not be refilled")
		_lagging_finalize_terminal_gap(job.frag, job.seq)
	else:
		job.frag.primer_removed = true
		print("[POL1] job complete — primer removed, frag now sealable, leaving strand")
	_pol1_state = Pol1Phase.LEAVING
	_pol1_tween = sim.create_tween()
	_pol1_tween.tween_property(pol1, "position:y", pol1.position.y + tm.pol1_offstage_drop, tm.pol1_leave_duration)
	_pol1_tween.parallel().tween_property(pol1, "modulate:a", 0.0, tm.pol1_leave_duration)
	_pol1_tween.tween_callback(func():
		_pol1_state = Pol1Phase.OFFSTAGE
		_ligase_kick()
		_pol1_kick()
		_lagging_try_deferred_fade()
	)

## The remove-only counterpart to _convert_primer_base_to_dna(): fades one
## terminal primer base + its bond out over a single sweep step, matching the
## bite cadence of a normal conversion. Bases are only alpha-faded here (not
## freed) so the primer backbone keeps drawing through the sweep; the actual
## free + null + gap recording happens once in _lagging_finalize_terminal_gap()
## when the job finishes.
func _remove_terminal_primer_base(index: int) -> void:
	var step_duration: float = sim.helicase_mgr.step_duration
	var base = lagging_synthesized_bases[index]
	var bond = lagging_hydrogen_bonds[index]
	var t = sim.create_tween()
	if base != null and is_instance_valid(base):
		t.parallel().tween_property(base, "modulate:a", 0.0, step_duration)
	if bond != null and is_instance_valid(bond):
		t.parallel().tween_property(bond, "modulate:a", 0.0, step_duration)

## Kills any in-flight travel/sweep/leave tween and drops back to fully
## offstage (faded, idle). Does NOT touch already-converted primer bases —
## same rule _ligase_reset_visual()/_primase_blip_reset_visual() already
## follow. No-ops entirely if pol1 was never instantiated (true absence —
## nothing to reset). Used on scrub, toggle-off mid-run, and sequence reload.
func _pol1_reset_visual() -> void:
	var had_work: bool = _pol1_state != Pol1Phase.OFFSTAGE or not _pol1_queue.is_empty()
	if had_work:
		print("[POL1] reset — was in state %d with %d queued, dropping to OFFSTAGE" % [_pol1_state, _pol1_queue.size()])
	if _pol1_tween != null and _pol1_tween.is_valid():
		_pol1_tween.kill()
	_pol1_state = Pol1Phase.OFFSTAGE
	_pol1_queue.clear()
	if pol1 != null:
		pol1.modulate.a = 0.0
		pol1.set_pulse(0.0)

## Bead-space gap target for the ligase glyph: half a slot spacing before
## `frag_first_slot` (the fragment about to be sealed's first slot) — i.e.
## the boundary between frag_first_slot-1 and frag_first_slot. Extracted out
## of _ligase_kick() so _ligase_apply_atom_tier_position_swap()'s bead-tier
## fallback (when the atom-tier gap position isn't available this frame —
## e.g. off-screen) can share the exact same formula rather than risk the
## two silently drifting apart.
func _ligase_gap_bead_position(frag_first_slot: int) -> Vector2:
	var target_x = sim.nucleotide_original_x[frag_first_slot] - sim.nucleotide_slot_spacing / 2.0
	var target_y = sim.new_bottom_template_y + sim.dna_ribbons_gap + tm.backbone_offset_distance
	return Vector2(target_x, target_y)

## Idempotent: no-ops if ligase is off, already busy, or nothing is pending.
## Finds the EARLIEST unsealed-but-complete fragment — since ligase only ever
## moves forward and never revisits, this is always correct regardless of
## which trigger called it.
func _ligase_kick() -> void:
	if not sim.ligase_enabled or _ligase_state != LigaseState.IDLE or ligase == null:
		return
	var next_frag = null
	for frag in lagging_fragments:
		if frag.sealed:
			continue
		if _pol1_enabled() and not frag.get("primer_removed", false):
			# The last fragment's OWN primer is never removed (no fragment
			# closes after it to trigger removal) — but its 5' nick to the
			# previous fragment IS sealable, since that junction is all DNA.
			# So once the strand is complete, seal it anyway: its DNA joins the
			# strand and only the un-removed 3' primer stays distinct. Every
			# OTHER unsealed fragment still waits for its own primer. Gap mode
			# is excluded — it removes the terminal primer outright, so
			# primer_removed goes true there and this branch never applies.
			var is_last = frag == lagging_fragments[-1]
			var strand_complete = lagging_current_fragment == null and lagging_total_consumed >= sim.num_nucleotide_slots
			var gap_mode = complexity_mgr != null and complexity_mgr.is_enabled("lagging_gap")
			if not (is_last and strand_complete and not gap_mode):
				print("[LIGASE] kick — earliest unsealed fragment (slot %d) isn't primer-clean yet, waiting" % frag.slots[0])
				break  # earliest unsealed fragment isn't primer-clean yet — nothing later can be either
			print("[LIGASE] sealing final fragment (slot %d) — 5' nick joins strand, 3' primer stays (never removed)" % frag.slots[0])
		next_frag = frag
		break
	if next_frag == null:
		return

	_ligase_active_gap_slot = next_frag.slots[0] - 1
	_ligase_state = LigaseState.TRAVELING
	ligase.visible = true
	_ligase_cofactor_begin()
	print("[LIGASE] traveling to seal fragment starting at slot %d" % next_frag.slots[0])
	if _ligase_tween != null and _ligase_tween.is_valid():
		_ligase_tween.kill()
	_ligase_tween = sim.create_tween()
	_ligase_tween.tween_property(ligase, "position", _ligase_gap_bead_position(next_frag.slots[0]), tm.ligase_travel_duration)
	# Spark fires at TRAVELING -> HOLDING, never mid-travel: the cofactor only
	# activates once the enzyme has actually engaged the nick. Mirrors
	# helicase's "cleave at arrival." The PPi drift and fade then run inside
	# the hold interval below, which exists specifically for visibility.
	_ligase_tween.tween_callback(_ligase_enter_holding)
	_ligase_tween.tween_interval(tm.ligase_hold_duration)
	_ligase_tween.tween_callback(_ligase_seal.bind(next_frag))

func _ligase_seal(frag: Dictionary) -> void:
	_ligase_state = LigaseState.SEALING
	print("[LIGASE] sealing — pinch starting")
	_ligase_tween = sim.create_tween()
	_ligase_tween.tween_method(ligase.set_pulse, 0.0, 1.0, tm.ligase_seal_duration * 0.5)
	# Adenylylation runs in parallel with the RELEASE half, not the pinch:
	# the pinch clamps tight, THEN the enzyme visibly hands off what it was
	# carrying as it lets go. Sequenced between the two tween_methods so it
	# starts exactly at the halfway point without a second tween to keep in
	# sync with this one.
	_ligase_tween.tween_callback(_ligase_cofactor_hop)
	_ligase_tween.tween_method(ligase.set_pulse, 1.0, 0.0, tm.ligase_seal_duration * 0.5)
	_ligase_tween.tween_callback(_ligase_finish_seal.bind(frag))

func _ligase_finish_seal(frag: Dictionary) -> void:
	frag.sealed = true
	# AMP was MECHANISM up to this instant and becomes WASTE at it — which is
	# the exact moment it comes under the byproducts toggle. See
	# ATPCycleDesign.md's mechanism-vs-waste table.
	if ligase_cofactor != null and _ligase_cofactor_enabled():
		ligase_cofactor.release()
	print("[LIGASE] seal complete — frag.sealed=true, merging into continuous line")
	_ligase_state = LigaseState.IDLE
	_ligase_active_gap_slot = -2
	_ligase_kick()  # pick up the next pending fragment, if any -- overwrites _ligase_active_gap_slot above if so
	_lagging_try_deferred_fade()

## Kills any in-flight travel/pulse, hides the node, and drops back to rest.
## Used when ligase is toggled off mid-travel (so it doesn't sit frozen
## mid-air) and during scrub (see scrub_rebuild()'s dispatcher) — scrub shows
## only finished states, never an in-progress travel/seal.
func _ligase_reset_visual() -> void:
	if _ligase_tween != null and _ligase_tween.is_valid():
		_ligase_tween.kill()
	_ligase_state = LigaseState.IDLE
	_ligase_active_gap_slot = -2
	if ligase != null:
		ligase.visible = false
		ligase.modulate.a = 1.0  # undoes _lagging_fade_enzyme_scene()'s end-of-run fade — otherwise the NEXT run's first seal sets visible=true while alpha is still 0 from the last one
		ligase.set_pulse(0.0)
		if ligase_cofactor != null:
			ligase_cofactor.reset()
		_ligase_park_offstage()  # snap back to the offstage rest spot — otherwise it stays at wherever its last seal ended, so the next run's first seal tween starts mid-strand and slides in from there (create-once-hide lifecycle seam, same as primase/Pol I)

## Parks ligase at its offstage rest position: below the strand, near the
## start (where its first seal always lands), so the first seal rises up into
## place instead of dropping in from the node's local origin up-and-left of the
## strand. Below-the-strand matches Pol I's own downward-offstage convention.
func _ligase_park_offstage() -> void:
	if ligase == null:
		return
	var park_y = sim.new_bottom_template_y + sim.dna_ribbons_gap + tm.backbone_offset_distance + tm.ligase_offstage_drop
	var park_x = 0.0
	if sim.nucleotide_original_x.size() > 0:
		park_x = sim.nucleotide_original_x[0]
	ligase.position = Vector2(park_x, park_y)

## Zoom-derived (never tweened/time-based) fade + position swap for the
## bead-tier ligase glyph, so it relocates to the atom-tier gap position
## while the camera is in molecular zoom, instead of always sitting at its
## bead-space position. Gated to HOLDING/SEALING only: those are the two
## LigaseState values where ligase.position is a static "parked at this
## gap" value with no tween currently writing it — TRAVELING owns position
## via its own tween in _ligase_kick(), and this function must never touch
## it then, or the two writers would race. Pure function of the live zoom
## scalar (molecule_renderer.get_transition_fraction()/
## is_molecular_mode_active()) — no clock of its own, same scrub-safety
## discipline the bead<->molecular crossfade itself follows: scrubbing to
## any zoom value must show the correct blend instantly, never replay or
## get stuck mid-fade.
func _ligase_apply_atom_tier_position_swap() -> void:
	if ligase == null or molecule_renderer == null:
		return
	if _ligase_state != LigaseState.HOLDING and _ligase_state != LigaseState.SEALING:
		return
	if _ligase_active_gap_slot < -1:
		return  # -2 sentinel: genuinely unset, no active gap at all

	var t: float = molecule_renderer.get_transition_fraction()
	var active: bool = molecule_renderer.is_molecular_mode_active()
	# The swap point is wherever is_molecular_mode_active() actually flips
	# for the CURRENT active state -- t=1.0 while inactive (rising toward
	# atom mode flips it true there), t=0.0 while active (falling toward
	# bead mode flips it false there), per molecule_structure_renderer.gd's
	# own _compute_active() Schmitt-trigger logic against the identical two
	# thresholds get_transition_fraction() ramps between. NOT the band
	# midpoint, and NOT a fixed point independent of current state.
	var edge: float = 0.0 if active else 1.0
	var t_dist: float = abs(t - edge)
	var half_width: float = max(tm.ligase_atom_swap_dip_half_width, 0.001)
	var dip_shape: float = clamp(1.0 - t_dist / half_width, 0.0, 1.0)
	ligase.modulate.a = 1.0 - dip_shape * tm.ligase_atom_swap_dip_peak_amount

	# _ligase_active_gap_slot == -1 is the very first Okazaki fragment's own
	# seal (next_frag.slots[0] == 0, no real predecessor slot exists) --
	# fall back to the SINGLE atom position of the fragment's own first slot
	# (its alpha-phosphate) rather than the usual two-atom gap midpoint,
	# since there's nothing on the other side to average with.
	var has_atom_pos: bool
	var atom_pos: Vector2
	if _ligase_active_gap_slot < 0:
		has_atom_pos = molecule_renderer.has_slot_alpha_position("lagging", _ligase_active_gap_slot + 1)
		atom_pos = molecule_renderer.get_slot_alpha_position("lagging", _ligase_active_gap_slot + 1)
	else:
		has_atom_pos = molecule_renderer.has_lagging_gap_atom_position(_ligase_active_gap_slot)
		atom_pos = molecule_renderer.get_lagging_gap_atom_position(_ligase_active_gap_slot) if has_atom_pos else Vector2.ZERO

	if active and has_atom_pos:
		ligase.position = atom_pos
	else:
		# Bead-tier fallback: ALWAYS freshly recomputed via the shared
		# helper, never read back from ligase.position (which a prior
		# frame's atom-tier branch may have overwritten) -- so there's a
		# defined answer even off-screen, never a crash or a snap-to-zero.
		ligase.position = _ligase_gap_bead_position(_ligase_active_gap_slot + 1)

## Eukaryotic mode only — bacterial ligase runs on NAD+, a structurally
## different molecule that this glyph would misrepresent. The topology check
## is folded into is_enabled("ligase_cofactor") itself, so this file never has to
## know topology exists, exactly as is_enabled("lagging_gap") already does for
## the gap mechanic.
## Named methods rather than multi-line lambdas at the two new hook points.
## GDScript's multi-line lambda parsing is fragile enough that this project
## already avoids it — the one pre-existing lambda in this chain was a single
## expression. A named callback also keeps the tween chain readable as a list
## of steps rather than a wall of inline bodies.
func _ligase_enter_holding() -> void:
	_ligase_state = LigaseState.HOLDING
	if ligase_cofactor != null and _ligase_cofactor_enabled():
		ligase_cofactor.cleave()

func _ligase_cofactor_hop() -> void:
	if ligase_cofactor != null and _ligase_cofactor_enabled():
		ligase_cofactor.hop()

func _ligase_cofactor_enabled() -> bool:
	return complexity_mgr != null and complexity_mgr.is_enabled("ligase_cofactor")

## Called as the travel tween starts. The whole uncleaved ATP rides in with
## the enzyme; nothing cleaves until arrival. Also re-reads the byproducts
## toggle AND the donor (NAD+ pass) per kick rather than caching either, so
## flipping the checkbox — or the topology mode — mid-run takes effect on the
## very next fragment.
func _ligase_cofactor_begin() -> void:
	if ligase_cofactor == null:
		return
	if not _ligase_cofactor_enabled():
		ligase_cofactor.reset()
		return
	ligase_cofactor.byproducts_visible = complexity_mgr.is_enabled("cofactor_byproducts")
	ligase_cofactor.donor_is_nad = complexity_mgr.ligase_uses_nad()
	ligase_cofactor.begin_carry()

func _lagging_scrub_rebuild(ctx: Dictionary) -> void:
	var is_done_phase: bool = ctx.is_done_phase
	var num_slots: int = ctx.num_slots
	var nucleotide_original_x = ctx.nucleotide_original_x
	var threshold = sim.okazaki_fragment_size + sim.pll_slot_count

	var attempted_consumed = 0
	var exposed_count = num_slots if is_done_phase else max(0, ctx.target_slot)
	if is_done_phase:
		attempted_consumed = _lagging_natural_done_consumed(num_slots, nucleotide_original_x)
	else:
		if exposed_count >= threshold:
			attempted_consumed = exposed_count - threshold + 1
		attempted_consumed = clamp(attempted_consumed, 0, num_slots)

	var lagging_gap_on = complexity_mgr != null and complexity_mgr.is_enabled("lagging_gap")
	var total_consumed = attempted_consumed
	if is_done_phase and lagging_gap_on:
		# Corrected gap model: Pol III finishes the WHOLE strand — nothing is
		# discarded. The telomere gap is only the terminal primer footprint,
		# removed after the strand is otherwise complete, and reconstructed as
		# empty further down. So the built length is the full strand.
		total_consumed = num_slots
	elif is_done_phase:
		# DONE alone doesn't finish lagging — it reaches the natural tiling
		# point, same as live play. Further completion comes from explicit
		# catch-up steps, supplied via ctx.lagging_catchup_step by
		# scrub_to_lagging_catchup() for arrow-key stepping. Defaults to 0
		# (natural state) for ordinary scrub_to() calls — slider-drag or the
		# exact boundary arrow-key step.
		var catchup_step = ctx.get("lagging_catchup_step", 0)
		total_consumed = clamp(attempted_consumed + catchup_step, attempted_consumed, num_slots)
	if is_done_phase and lagging_gap_on:
		var last_slot = num_slots - 1
		var gap_start = num_slots - _primase_primer_length()
		lagging_telomere_gap = { start = gap_start, end = last_slot, length = last_slot - gap_start + 1 }
	else:
		lagging_telomere_gap = null

	# ---- Free old visuals, rebuild from scratch ----
	var old_fragments = lagging_fragments.duplicate()
	if lagging_current_fragment != null:
		old_fragments.append(lagging_current_fragment)
	for frag in old_fragments:
		if frag.backbone != null and is_instance_valid(frag.backbone): frag.backbone.queue_free()
		if frag.get("primer_backbone", null) != null and is_instance_valid(frag.primer_backbone): frag.primer_backbone.queue_free()
		for mark in frag.bond_marks:
			if mark != null and is_instance_valid(mark): mark.queue_free()
		for mark in frag.get("primer_bond_marks", []):
			if mark != null and is_instance_valid(mark): mark.queue_free()
		if frag.marker_5p != null and is_instance_valid(frag.marker_5p): frag.marker_5p.queue_free()
		if frag.marker_3p != null and is_instance_valid(frag.marker_3p): frag.marker_3p.queue_free()
	lagging_fragments.clear()
	lagging_current_fragment = null

	for base in lagging_synthesized_bases:
		if base != null and is_instance_valid(base): base.queue_free()
	for bond in lagging_hydrogen_bonds:
		if bond != null and is_instance_valid(bond): bond.queue_free()
	lagging_synthesized_bases.clear()
	lagging_hydrogen_bonds.clear()
	lagging_synthesized_bases.resize(num_slots)
	lagging_hydrogen_bonds.resize(num_slots)

	# ---- Tile [0, total_consumed) into fragments ----
	# Every full-size tile is complete. If total_consumed reaches num_slots and
	# the final tile is short, that short tile is ALSO complete — it's the
	# catch-up mechanism's genuinely-short final fragment (left-anchored), not
	# a partial fill. Only when total_consumed stops mid-tile *before* reaching
	# num_slots is the trailing portion still open — firing sweeps right-to-left
	# within a tile, so only its rightmost `remainder` slots have fired so far.
	var full_tiles = total_consumed / sim.okazaki_fragment_size
	var remainder = total_consumed - full_tiles * sim.okazaki_fragment_size

	for k in range(full_tiles):
		var frag = { slots = range(k * sim.okazaki_fragment_size, (k + 1) * sim.okazaki_fragment_size),
			loop_queue = [], backbone = null, primer_backbone = null, bond_marks = [], primer_bond_marks = [], marker_5p = null, marker_3p = null, complete = true, sealed = true, primer_removed = false }
		lagging_fragments.append(frag)

	if remainder > 0:
		var tile_start = full_tiles * sim.okazaki_fragment_size
		var true_tile_end = min(tile_start + sim.okazaki_fragment_size, num_slots)
		var frag_slots = range(true_tile_end - remainder, true_tile_end)
		if total_consumed >= num_slots:
			var frag = { slots = frag_slots,
				loop_queue = [], backbone = null, primer_backbone = null, bond_marks = [], primer_bond_marks = [], marker_5p = null, marker_3p = null, complete = true, sealed = true, primer_removed = false }
			lagging_fragments.append(frag)
		else:
			lagging_current_fragment = { slots = frag_slots,
				loop_queue = [], backbone = null, primer_backbone = null, bond_marks = [], primer_bond_marks = [], marker_5p = null, marker_3p = null, complete = false, sealed = false, primer_removed = false }

	# Pol I fragment-lag resolution (Complex tier): fragment m's primer reads
	# as removed iff a LATER fragment has also closed — the actual trigger
	# is "the next fragment closes", never "opens", so an open-but-not-closed
	# lagging_current_fragment (if any) never satisfies this for the last
	# entry in lagging_fragments. Every entry except the last closed one
	# qualifies; a single-fragment run has nothing to flip.
	for idx in range(lagging_fragments.size() - 1):
		lagging_fragments[idx].primer_removed = true

	# Per-fragment spawn: at Light tier (pol1 off) every consumed slot still
	# renders as DNA, same simplification as before (conversion is instant,
	# so nothing scrub ever shows can still be primer). At Complex tier,
	# frag.primer_removed (resolved structurally just above, purely from
	# fragment position — no animation/tween history involved) determines
	# whether that fragment's own primer span still renders RNA-styled.
	for frag in lagging_fragments:
		_lagging_scrub_spawn_fragment(frag)
	if lagging_current_fragment != null:
		_lagging_scrub_spawn_fragment(lagging_current_fragment)

	# ---- Primase's own ahead-of-Pol-III placements ----
	# Primase's real trigger fires off raw helicase exposure, not Pol III's
	# own threshold-lagged progress — see the reconstruction above, which
	# only covers up to `total_consumed`. Any tile whose ANCHOR slot has
	# already been exposed by the helicase (exposed_count), but which Pol
	# III hasn't opened yet, would already have its primer placed in a live
	# run. Only the primer span itself gets spawned — the rest of that
	# tile awaits Pol III's own future synthesis and stays unspawned, same
	# as live play.
	#
	# Backbone geometry: reuses _primase_ensure_pending_backbone() directly
	# rather than reconstructing the Line2D by hand — that function only
	# creates the entry (empty points/bond_marks); _lagging_render()'s own
	# per-frame pass over primase_pending_backbones.keys() already redraws
	# geometry fresh every frame from whatever's in lagging_synthesized_bases,
	# so populating the bases above is all that's actually needed here.
	# Safe to call unconditionally: scrub_rebuild()'s dispatcher already ran
	# _primase_clear_pending_backbones() before this function, so there's
	# nothing stale to collide with.
	if complexity_mgr != null and complexity_mgr.is_enabled("primase"):
		var ahead_tile_start = full_tiles * sim.okazaki_fragment_size
		if remainder > 0:
			ahead_tile_start += sim.okazaki_fragment_size  # the open tile is already covered above
		var span = _primase_primer_length()
		# Mirrors _primase_check_slot()'s live-play gap-avoidance boundary —
		# scrubbing into this range must show exactly what a live run would
		# have shown, i.e. nothing, since these tiles are structurally
		# unreachable by the polymerase before the strand ends (see the
		# comment at _primase_check_slot() for the derivation).
		var k = ahead_tile_start
		while k < num_slots:
			var this_tile_end = min(k + sim.okazaki_fragment_size, num_slots)
			if this_tile_end - 1 > exposed_count - 1:
				break  # this tile's anchor isn't exposed yet — neither is any later tile's
			var primer_start = max(k, this_tile_end - span)
			for i in range(primer_start, this_tile_end):
				# Reverted — see _convert_primer_base_to_dna()'s comment.
				var base_type = sim.dna_sequence.get_base(i)
				var rna_letter = base_type
				if rna_letter == "T":
					rna_letter = "U"
				var color = _primer_rna_color_for(rna_letter)
				lagging_synthesized_bases[i] = _spawn_lagging_base(i, rna_letter, null, color, "rounded_square")
				lagging_hydrogen_bonds[i] = _spawn_lagging_hydrogen_bonds(i)
			_primase_ensure_pending_backbone(this_tile_end)
			k = this_tile_end

	# ---- Terminal telomere gap reconstruction (gap mode, DONE only) ----
	# The finished state has the terminal primer already removed — an empty
	# gap, never RNA and never DNA. Everything above rebuilt the strand as if
	# complete (terminal primer spawned RNA-styled via the last fragment); now
	# clear that footprint back out so scrub shows exactly the post-removal
	# end state live play lands on. Purely structural — no tween, no replay.
	if is_done_phase and lagging_gap_on and lagging_fragments.size() > 0:
		var span_t = _primase_primer_length()
		var terminal_frag = lagging_fragments[-1]
		for i in range(num_slots - span_t, num_slots):
			if i >= 0 and lagging_synthesized_bases[i] != null and is_instance_valid(lagging_synthesized_bases[i]):
				lagging_synthesized_bases[i].queue_free()
			lagging_synthesized_bases[i] = null
			if i >= 0 and lagging_hydrogen_bonds[i] != null and is_instance_valid(lagging_hydrogen_bonds[i]):
				lagging_hydrogen_bonds[i].queue_free()
			lagging_hydrogen_bonds[i] = null
		if terminal_frag.get("primer_backbone", null) != null and is_instance_valid(terminal_frag.primer_backbone):
			terminal_frag.primer_backbone.queue_free()
			terminal_frag.primer_backbone = null
		# Primer gone → fragment is primer-clean and sealed in the end state.
		terminal_frag.primer_removed = true
		terminal_frag.sealed = true

	# ---- Polymerase position + visibility ----
	lagging_total_consumed = total_consumed
	lagging_firing_started = total_consumed > 0
	# Keep the once-only terminal-removal guard consistent with what THIS scrub
	# reconstructed. At the DONE gap state the removal is already baked in
	# (footprint cleared above), so mark it done; anywhere earlier it hasn't
	# happened yet, so clear it — otherwise a stale `true` from a prior full
	# play would make a subsequent play-forward skip the removal and leave the
	# terminal primer standing.
	_terminal_removal_started = is_done_phase and lagging_gap_on
	# Same reasoning for the polymerase rest-slide guard: at DONE the slide has
	# conceptually already happened (and both polymerases are alpha-0 here
	# anyway); anywhere earlier it hasn't, so clear it or a play-forward from a
	# mid-run scrub would skip the slide.
	_polymerases_at_rest = is_done_phase
	if total_consumed > 0:
		if lagging_current_fragment != null:
			lagging_polymerase_x = sim.nucleotide_original_x[lagging_current_fragment.slots[0]]
			lagging_batch_cursor = lagging_current_fragment.slots[0] - 1
		elif lagging_fragments.size() > 0:
			lagging_polymerase_x = sim.nucleotide_original_x[lagging_fragments[-1].slots[0]]
	else:
		lagging_polymerase_x = sim.nucleotide_original_x[0] - sim.polymerase_x_offset_slots * sim.nucleotide_slot_spacing

## Spawns every slot in `frag`, RNA-styled for any slot still within its
## primer span AND not yet removed (pol1_enabled and frag.primer_removed ==
## false), DNA-styled otherwise. Replaces the old "everything renders as
## DNA" simplification, which only held while conversion was instant. Still
## fully deterministic and animation-free — frag.primer_removed was already
## resolved structurally in _lagging_scrub_rebuild(), purely from fragment
## position, never from replayed tween state.
func _lagging_scrub_spawn_fragment(frag: Dictionary) -> void:
	var primer_still_present: bool = _pol1_enabled() and not frag.get("primer_removed", false)
	for i in frag.slots:
		# Reverted — see _convert_primer_base_to_dna()'s comment.
		var base_type = sim.dna_sequence.get_base(i)
		if primer_still_present and _is_primer_slot(i):
			var rna_letter = base_type
			if rna_letter == "T":
				rna_letter = "U"  # rendering-layer only, matches _primase_place_primer_base()
			var color = _primer_rna_color_for(rna_letter)
			lagging_synthesized_bases[i] = _spawn_lagging_base(i, rna_letter, null, color, "rounded_square")
		else:
			lagging_synthesized_bases[i] = _spawn_lagging_base(i, base_type)
		lagging_hydrogen_bonds[i] = _spawn_lagging_hydrogen_bonds(i)

func _on_helicase_phase_changed(new_phase: int) -> void:
	if new_phase == connected_helicase_mgr.Phase.DONE and not sim.manual_override:
		# Both modes run the same catch-up now — Pol III finishes the strand.
		# In gap mode the difference is deferred to catch-up completion, where
		# the terminal primer is removed (leaving its footprint as the gap)
		# instead of the strand simply ending. Synthesized DNA is never
		# discarded — the old discard-the-open-fragment model is gone.
		_lagging_start_catchup()

func _lagging_start_catchup() -> void:
	if lagging_polymerase_faded:
		return
	if lagging_total_consumed >= sim.num_nucleotide_slots:
		_lagging_finish_or_remove_terminal()
		return
	if lagging_catchup_timer == null:
		lagging_catchup_timer = Timer.new()
		lagging_catchup_timer.one_shot = false
		sim.add_child(lagging_catchup_timer)
		lagging_catchup_timer.timeout.connect(_lagging_catchup_tick)
	lagging_catchup_timer.wait_time = sim.lagging_catchup_step_duration
	lagging_catchup_timer.start()

func _lagging_catchup_tick() -> void:
	if lagging_current_fragment == null:
		_lagging_open_next_fragment()
	_lagging_fire_step(sim.lagging_catchup_step_duration)
	if lagging_total_consumed >= sim.num_nucleotide_slots:
		lagging_catchup_timer.stop()
		_lagging_finish_or_remove_terminal()

## True once ligase and (if pol1_enabled) Pol I have both fully drained their
## queues and returned to idle — the gate the scene-wide fade waits on so it
## never hides a trailing seal/removal that's still genuinely in flight.
func _lagging_enzymes_settled() -> bool:
	if _ligase_state != LigaseState.IDLE:
		return false
	if _pol1_enabled() and (_pol1_state != Pol1Phase.OFFSTAGE or not _pol1_queue.is_empty()):
		return false
	return true

## Called from the tail of ligase's and Pol I's own completion handlers —
## picks up wherever _lagging_start_catchup()/_lagging_catchup_tick() left
## off if the strand itself was already done but trailing work wasn't.
## No-ops silently in every other case (nothing pending, or not settled yet).
func _lagging_try_deferred_fade() -> void:
	if not _lagging_fade_pending or lagging_polymerase_faded:
		return
	if lagging_total_consumed < sim.num_nucleotide_slots:
		return  # shouldn't normally happen, but stay safe
	if not _lagging_enzymes_settled():
		return
	_lagging_fade_pending = false
	lagging_polymerase_faded = true
	_lagging_fade_enzyme_scene()

## Catch-up has reached the strand's end. In gap mode, remove the terminal
## primer (leaving its footprint as the telomere gap) BEFORE the scene fades;
## otherwise fall straight through to the normal settle-gated fade. Guarded to
## fire the removal exactly once — the deferred-fade path can re-enter here.
func _lagging_finish_or_remove_terminal() -> void:
	# The lagging polymerase has finished its last fragment. Slide both
	# polymerases to their shared rest spot NOW (not at fade time) — this is
	# exactly when Pol I / ligase are still working the tail of their queues,
	# and a stationary lagging polymerase would sit on top of them.
	_polymerases_move_to_rest()
	if complexity_mgr != null and complexity_mgr.is_enabled("lagging_gap") and not _terminal_removal_started:
		_terminal_removal_started = true
		_lagging_start_terminal_removal()
		return
	if not _lagging_enzymes_settled():
		_lagging_fade_pending = true
		return
	lagging_polymerase_faded = true
	_lagging_fade_enzyme_scene()

## Slides both polymerases to a shared end-of-run rest spot: the lagging one
## travels up to meet the leading one, and both nudge a couple slot-spacings
## past the strand's end so they clear the DNA (and Pol I / ligase's catch-up
## work). Live-only polish — at DONE both are alpha-0 in scrub, and scrub
## recomputes their positions anyway, so this never needs reconstructing and
## can't desync scrub. Fires once per run.
func _polymerases_move_to_rest() -> void:
	if _polymerases_at_rest or leading_polymerase == null or lagging_polymerase == null:
		return
	_polymerases_at_rest = true
	var nudge = tm.clamp_rest_nudge_slots * sim.nucleotide_slot_spacing
	var rest_x = leading_polymerase.position.x + nudge
	var dur = tm.clamp_rest_move_duration
	var lt = sim.create_tween()
	lt.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	lt.tween_property(leading_polymerase, "position:x", rest_x, dur)
	# Reuses lagging_polymerase_tween so a scrub mid-slide kills it cleanly
	# (scrub_rebuild already kills this tween and snaps to the scrub position).
	if lagging_polymerase_tween != null and lagging_polymerase_tween.is_valid():
		lagging_polymerase_tween.kill()
	lagging_polymerase_tween = sim.create_tween()
	lagging_polymerase_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	lagging_polymerase_tween.tween_property(lagging_polymerase, "position:x", rest_x, dur)
	lagging_polymerase_x = rest_x  # keep the tracking var in sync so no later read snaps it back mid-slide
	print("[LAGGING] polymerases sliding to rest x=%.1f (leading end + %d slots)" % [rest_x, int(tm.clamp_rest_nudge_slots)])

## The top `primer_length` slots of the strand — the terminal primer's
## footprint, i.e. the telomere gap. This is the ONE primer that, once removed,
## can never be refilled (no upstream 3'-OH beyond the chromosome end), so its
## span is the shortening. Sized by primer length, deliberately NOT by the
## helicase↔Pol III pacing lag.
func _lagging_terminal_gap_span() -> int:
	return _primase_primer_length()

## Kicks off the terminal-primer removal at strand completion (gap mode).
## The footprint is only ever removed if it's actually RNA primer — i.e.
## primase placed it. If there's no terminal primer present (e.g. primase off),
## there's nothing to remove and no gap forms; we fall through to the fade.
## Whether the removal is shown by Pol I (Complex tier) or done as a quiet fade
## (Pol I not on-screen) is the only tier-dependent branch — the end state is
## identical either way.
func _lagging_start_terminal_removal() -> void:
	var span = _lagging_terminal_gap_span()
	var terminal_frag = lagging_fragments[-1] if lagging_fragments.size() > 0 else null

	# Collect terminal slots that are actually RNA primer right now. DNA slots
	# are never touched — synthesized DNA does not dissolve. So if primase is
	# off (terminal footprint is DNA or empty), rna_slots is empty and no gap
	# forms — the gap is exactly, and only, a removed RNA primer.
	var rna_slots: Array = []
	for i in range(sim.num_nucleotide_slots - span, sim.num_nucleotide_slots):
		if i >= 0 and lagging_synthesized_bases[i] != null and is_instance_valid(lagging_synthesized_bases[i]) and lagging_synthesized_bases[i].shape == "rounded_square":
			rna_slots.append(i)

	if rna_slots.is_empty():
		print("[LAGGING] terminal removal — no RNA primer present, no gap (primase off?)")
		_lagging_fade_pending = true
		_lagging_try_deferred_fade()
		return

	rna_slots.sort()
	rna_slots.reverse()  # high-to-low, Pol I's own sweep order

	if _pol1_enabled():
		print("[LAGGING] terminal primer removal via Pol I — slots=%s" % [str(rna_slots)])
		_lagging_fade_pending = true
		_pol1_enqueue_job(terminal_frag, true)
	else:
		print("[LAGGING] terminal primer removal via quiet fade — slots=%s" % [str(rna_slots)])
		_lagging_quiet_terminal_fade(terminal_frag, rna_slots)

## No-Pol-I tiers: fade the terminal RNA primer out with no enzyme on screen,
## then record the gap and let the strand seal + scene fade proceed. Same end
## state as the Pol I path.
func _lagging_quiet_terminal_fade(terminal_frag, rna_slots: Array) -> void:
	var t = sim.create_tween()
	for i in rna_slots:
		if lagging_synthesized_bases[i] != null and is_instance_valid(lagging_synthesized_bases[i]):
			t.parallel().tween_property(lagging_synthesized_bases[i], "modulate:a", 0.0, sim.fade_duration)
		if lagging_hydrogen_bonds[i] != null and is_instance_valid(lagging_hydrogen_bonds[i]):
			t.parallel().tween_property(lagging_hydrogen_bonds[i], "modulate:a", 0.0, sim.fade_duration)
	t.chain().tween_callback(func():
		_lagging_finalize_terminal_gap(terminal_frag, rna_slots)
	)

## Frees the removed terminal primer nodes, records the gap, marks the terminal
## fragment primer-removed (so ligase will seal its 5' nick to the previous
## fragment — the nick that otherwise stayed open), and lets the deferred fade
## fire. Shared by both the Pol I and quiet-fade paths.
func _lagging_finalize_terminal_gap(terminal_frag, rna_slots: Array) -> void:
	for i in rna_slots:
		if lagging_synthesized_bases[i] != null and is_instance_valid(lagging_synthesized_bases[i]):
			lagging_synthesized_bases[i].queue_free()
		lagging_synthesized_bases[i] = null
		if lagging_hydrogen_bonds[i] != null and is_instance_valid(lagging_hydrogen_bonds[i]):
			lagging_hydrogen_bonds[i].queue_free()
		lagging_hydrogen_bonds[i] = null

	# The removed primer's own RNA backbone/bond-marks go too — otherwise they
	# leak the same way the old discard path leaked (QCA would surface them).
	if terminal_frag != null:
		if terminal_frag.get("primer_backbone", null) != null and is_instance_valid(terminal_frag.primer_backbone):
			terminal_frag.primer_backbone.queue_free()
			terminal_frag.primer_backbone = null
		for mark in terminal_frag.get("primer_bond_marks", []):
			if mark != null and is_instance_valid(mark): mark.queue_free()
		terminal_frag.primer_bond_marks = []
		# Primer is gone → the fragment IS primer-clean now, so ligase can seal
		# its 5' nick to the previous fragment on the normal path.
		terminal_frag.primer_removed = true

	var span = _lagging_terminal_gap_span()
	var gap_start = sim.num_nucleotide_slots - span
	var last_slot = sim.num_nucleotide_slots - 1
	lagging_telomere_gap = { start = gap_start, end = last_slot, length = last_slot - gap_start + 1 }
	print("[LAGGING] telomere gap recorded: slots %d-%d (length %d)" % [gap_start, last_slot, lagging_telomere_gap.length])

	_ligase_kick()  # seal the now-clean terminal fragment's 5' nick
	_lagging_fade_pending = true
	_lagging_try_deferred_fade()

func _lagging_fade_enzyme_scene() -> void:
	var fade_tween = sim.create_tween()
	if lagging_polymerase != null:
		fade_tween.tween_property(lagging_polymerase, "modulate:a", 0.0, sim.fade_duration)
	if leading_polymerase:
		fade_tween.parallel().tween_property(leading_polymerase, "modulate:a", 0.0, sim.fade_duration)
	if sim.helicase_node:
		fade_tween.parallel().tween_property(sim.helicase_node, "modulate:a", 0.0, sim.fade_duration)
	if ligase != null:
		fade_tween.parallel().tween_property(ligase, "modulate:a", 0.0, sim.fade_duration)
	if pol1 != null:
		fade_tween.parallel().tween_property(pol1, "modulate:a", 0.0, sim.fade_duration)

func _spawn_lagging_base(index: int, base_type: String, start_pos = null, color_override = null, shape_override = null) -> Node2D:
	var base = sim.NewNitrogenBaseScene.instantiate()
	var world_x = sim.nucleotide_original_x[index]
	var lagging_y = sim.new_bottom_template_y + sim.dna_ribbons_gap
	base.position = start_pos if start_pos != null else Vector2(world_x, lagging_y)
	base.z_index = 2
	sim.add_child(base)
	base.set_base_type(base_type)
	base.set_radius(tm.base_radius)
	var fill_color = color_override if color_override != null else sim._get_base_fill(base_type)
	# RNA (rounded_square) gets its own font color — bug fix: this used to
	# pass tm.base_label_color unconditionally, so rna_base_label_color had
	# no effect on the three call sites that route through here (live
	# placement in _primase_place_primer_base(), and both scrub-rebuild
	# paths in _lagging_scrub_rebuild()/_lagging_scrub_spawn_fragment()).
	# _convert_primer_base_to_dna() is unaffected — it calls set_colors()
	# directly with base_label_color, correctly, since it's converting TO DNA.
	var label_color = tm.rna_base_label_color if shape_override == "rounded_square" else tm.base_label_color
	base.set_colors(fill_color, label_color)
	base.set_font(tm.base_label_font_size, tm.base_label_font)
	base.set_label_rotation(_zoom_label_rotation())
	base.desaturation_gray_target = tm.molecular_bead_desaturation_gray_target
	if shape_override != null:
		base.set_shape(shape_override)
	return base

func _spawn_lagging_hydrogen_bonds(index: int) -> Node2D:
	# Reverted — lagging's real template is template_bottom, whose REAL
	# displayed letter (simulation.gd's _spawn_bottom_strand()) is
	# get_complement(index). See _spawn_leading_hydrogen_bonds()'s matching
	# comment.
	var template_base = sim.dna_sequence.get_complement(index)
	var bond_count = NitrogenBaseDeriver.hydrogen_bond_count(template_base)
	var bond_color = tm.cg_bond_color if (template_base == "C" or template_base == "G") else tm.at_bond_color
	var container = Node2D.new()
	container.position = Vector2(sim.nucleotide_original_x[index], sim.new_bottom_template_y)
	var total_width = (bond_count - 1) * tm.hydrogen_bond_spacing
	var start_x = -total_width / 2.0
	var inset = tm.base_radius - 3.0
	for b in range(bond_count):
		var line = Line2D.new()
		var lx = start_x + b * tm.hydrogen_bond_spacing
		line.add_point(Vector2(lx, inset))
		line.add_point(Vector2(lx, sim.dna_ribbons_gap - inset))
		line.default_color = bond_color
		line.width = tm.hydrogen_bond_width
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		container.add_child(line)
	sim.hydrogen_bonds_container.add_child(container)
	return container

## True if `index` falls inside the recorded telomere gap — i.e. it's an
## intentionally-empty slot (removed terminal primer), not a base that simply
## hasn't landed yet. The backbone render uses this to distinguish "gap, stop
## the line here" from "mid-flight, wait before merging".
func _is_telomere_gap_slot(index: int) -> bool:
	return lagging_telomere_gap != null and index >= lagging_telomere_gap.start and index <= lagging_telomere_gap.end

## Atom-tier equivalent of the bead tier's own "unsealed fragment gets its
## own separate Line2D" rule (_lagging_render()'s merge-prefix scan) — true
## if the phosphodiester bond between lagging slot `slot` (the lower/5'-er
## index) and slot+1 should render as an unbroken backbone bond. False
## exactly when `slot + 1` is the FIRST slot of a completed-but-unsealed
## Okazaki fragment (a real, still-open nick); true for every other slot,
## including ordinary intra-fragment bonds and any slot that isn't a
## fragment boundary at all (e.g. one still inside lagging_current_fragment,
## which never appears in lagging_fragments and so falls through to the
## default). Reads lagging_fragments live every call — no cached seal
## state, so a mid-session seal (camera parked at atom zoom) is picked up
## on the very next rebuild. No underscore prefix:
## molecule_structure_renderer.gd calls this externally, the same "read
## lagging_fragments directly, don't derive a second answer" discipline the
## bead tier's own gap logic already follows.
##
## Gated on frag.slots[0] (the fragment STARTING at slot+1), NOT
## frag.slots[-1] (the fragment ENDING at slot) — this was gated backwards
## in an earlier pass and shipped a real bug: fragment N's own closure
## seals FAST (nothing else competes for ligase right after it closes),
## while fragment N+1 takes many more fire-steps to complete, so gating on
## fragment N's seal let the N/N+1 junction bond render the instant
## fragment N+1's first slot landed, with no ligase visit at that junction
## at all. The bead tier's own PROVEN merge-prefix scan
## (_lagging_render()'s `last_sealed_idx`) requires fragment N+1 ITSELF to
## be sealed before the merge advances past it — confirming the junction is
## gated by the fragment ligase actually travels to and pinches AT that
## exact spot (_ligase_kick()'s own target formula uses next_frag.slots[0],
## the same slot+1 this function now keys off).
##
## Telomere-gap/terminal-fragment removal (Pol I territory) is out of scope
## at this complexity tier — frag.slots[0] is used directly, unlike the
## defensive backward-scan _lagging_fragment_last_rendered_slot() needs.
func is_lagging_bond_sealed(slot: int) -> bool:
	# Base complexity tier (ligase_enabled == false, per simulation.gd's own
	# doc comment on that export var): "continuous lagging backbone (no
	# ligase modeled)" -- fragments still get created/tracked internally
	# (_lagging_open_fragment() doesn't gate on this flag, by design, since
	# fragment bookkeeping also drives other tier-independent logic), but
	# they can never actually seal at this tier -- _ligase_kick() itself
	# gates on sim.ligase_enabled, so frag.sealed would sit false forever
	# and every fragment boundary would render as a permanent phantom nick.
	# Short-circuiting here (rather than gating the renderer's call site)
	# keeps this function's contract -- "should this bond render intact" --
	# tier-aware on its own, matching OkazakiMaturationDesign.md's own note
	# that `sealed` was meant to replace a binary ligase_enabled read.
	if sim != null and not sim.ligase_enabled:
		return true
	for frag in lagging_fragments:
		if frag.slots.size() > 0 and frag.slots[0] == slot + 1:
			return frag.sealed
	return true  # not a fragment boundary -- ordinary bond, always drawn

## The fragment's own 3' end for MARKER purposes — frag.slots[-1] is the
## fragment's highest slot index, which for the terminal fragment after
## telomerase removal is inside the now-empty gap (that slot was fired by
## Pol III during catch-up, so it's still in .slots, but its base no longer
## exists). The growing strand's actual 3'-most synthesized nucleotide is the
## last DNA base BEFORE the gap — walks backward from frag.slots[-1] to find
## it. Ordinary fragments (not the terminal one, or gap mode off) hit the
## first slot checked and return immediately, so this is a no-op cost-wise
## for the overwhelming majority of fragments.
func _lagging_fragment_last_rendered_slot(frag: Dictionary) -> int:
	for i in range(frag.slots.size() - 1, -1, -1):
		var slot_index = frag.slots[i]
		if lagging_synthesized_bases[slot_index] != null:
			return slot_index
	return frag.slots[-1]  # defensive fallback — shouldn't be reachable for a fragment with want_3p

## True if this fragment still carries an un-removed RNA primer. Only ever the
## case for the LAST fragment in a non-gap Pol I run — every other fragment's
## primer is removed (by Pol I) before it merges, and gap mode removes the
## terminal one outright. Used by the merge path to keep that primer as its own
## RNA segment instead of freeing it / drawing DNA straight through it.
func _lagging_fragment_retains_primer(frag: Dictionary) -> bool:
	for slot_index in frag.slots:
		if _is_still_primer(slot_index):
			return true
	return false

## Renders a merged fragment's retained RNA primer as its own segment (created
## if needed) and returns its points, so the caller can bridge its merged DNA
## line to the primer's first point (a PackedVector2Array is copy-on-write, so
## the bridge append has to happen on the caller's own local array, not here).
func _lagging_render_retained_primer(frag: Dictionary, wobble_t: float, dna_ribbons_gap: float, new_bottom_template_y: float, nucleotide_original_x: Array) -> PackedVector2Array:
	if frag.get("primer_backbone", null) == null:
		var pline = Line2D.new()
		pline.default_color = tm.rna_backbone_color
		pline.width = tm.rna_backbone_line_width
		pline.z_index = -2
		pline.joint_mode = Line2D.LINE_JOINT_ROUND
		pline.begin_cap_mode = Line2D.LINE_CAP_ROUND
		pline.end_cap_mode = Line2D.LINE_CAP_ROUND
		sim.add_child(pline)
		frag.primer_backbone = pline
	var tile_end = _primase_tile_end(frag.slots[-1])
	var span = _primase_primer_length()
	var primer_points = PackedVector2Array()
	for slot_index in range(max(0, tile_end - span), tile_end):
		if _is_still_primer(slot_index):
			var wobble_y = sim.get_wobble_y(slot_index, wobble_t)
			var lagging_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
			primer_points.append(Vector2(nucleotide_original_x[slot_index], lagging_y + tm.backbone_offset_distance))
	frag.primer_backbone.points = primer_points
	frag.primer_backbone.width = tm.rna_backbone_line_width
	frag.primer_backbone.z_index = -2
	frag.primer_bond_marks = _update_bond_marks_generic(frag.get("primer_bond_marks", []), primer_points, sim._create_bond_mark_sprite_rna_reversed)
	return primer_points

func _lagging_render(ctx: Dictionary) -> void:
	var wobble_t: float = ctx.wobble_t
	var dna_ribbons_gap: float = ctx.dna_ribbons_gap
	var new_bottom_template_y: float = ctx.new_bottom_template_y
	var nucleotide_original_x = ctx.nucleotide_original_x

	# Live-sampled per-slot template Y, NOT the fixed new_bottom_template_y —
	# needed because a base can be registered here well before its row has
	# visually finished the bonded->unzipped transition (primase places
	# bases the instant the helicase passes their slot, long before
	# polymerase_x — which anchors where the curve settles — reaches them).
	# Safe to apply unconditionally to every base, not just primase's: the
	# curve sample converges to new_bottom_template_y automatically once a
	# slot's row has settled, so this changes nothing for Pol III's own
	# already-settled bases, only fixes the ones placed ahead of that.
	for i in range(lagging_synthesized_bases.size()):
		if lagging_synthesized_bases[i] != null:
			var wobble_y = sim.get_wobble_y(i, wobble_t)
			var world_x = nucleotide_original_x[i]
			var template_y = _lagging_template_y_at(world_x)
			var lagging_y = template_y + dna_ribbons_gap + wobble_y
			lagging_synthesized_bases[i].position = Vector2(world_x, lagging_y)
			# Bug A fix — see the matching comment in _leading_render().
			# Primer (RNA) slots are excluded: get_synthesized_nucleotides()
			# never reports them (molecule renderer models DNA incorporation
			# only, per that method's own comment), so they can never be
			# molecular-active and should stay fully opaque in bead mode.
			if molecule_renderer != null and not _is_still_primer(i):
				var bead_fade: float = molecule_renderer.get_bead_fade_amount("lagging", i)
				lagging_synthesized_bases[i].modulate.a = 1.0 - bead_fade
				lagging_synthesized_bases[i].set_desaturation_amount(molecule_renderer.get_transition_desaturation_amount())
			else:
				lagging_synthesized_bases[i].modulate.a = 1.0
			if lagging_hydrogen_bonds[i] != null:
				var bottom_template_y = template_y + wobble_y
				lagging_hydrogen_bonds[i].position = Vector2(world_x, bottom_template_y)
				sim._update_hydrogen_bond_height(lagging_hydrogen_bonds[i], lagging_y - bottom_template_y)
				# H-bond suppression now handled in _apply_highlight()
				# (single-writer fix) — see the matching comment in
				# _leading_render().

	# Primase-placed bases can exist for a tile BEFORE Pol III has opened
	# that fragment at all — primase fires the instant the helicase passes
	# a slot, well ahead of Pol III's own backlog-delayed arrival at the
	# same tile. Without this, those bases would sit with no connecting
	# backbone until Pol III's own (much later) bookkeeping happened to
	# reach them. Rendered fresh every frame like everything else here;
	# ADOPTED (not recreated) by the real fragment the moment
	# _lagging_open_next_fragment() opens that same tile — see there for
	# the handoff.
	for tile_end in primase_pending_backbones.keys():
		var entry = primase_pending_backbones[tile_end]
		var span = _primase_primer_length()
		var pending_points = PackedVector2Array()
		for slot_index in range(max(0, tile_end - span), tile_end):
			if lagging_synthesized_bases[slot_index] != null:
				var wobble_y = sim.get_wobble_y(slot_index, wobble_t)
				var world_x = nucleotide_original_x[slot_index]
				var template_y = _lagging_template_y_at(world_x)
				pending_points.append(Vector2(world_x, template_y + dna_ribbons_gap + wobble_y + tm.backbone_offset_distance))
		entry.backbone.points = pending_points
		entry.backbone.width = tm.rna_backbone_line_width
		entry.bond_marks = _update_bond_marks_generic(entry.bond_marks, pending_points, sim._create_bond_mark_sprite_rna_reversed)

	if sim.ligase_enabled:
		# Fragments merge into the one continuous backbone line once ligase
		# has actually SEALED them — not merely once Pol III completed them.
		# A completed-but-unsealed fragment keeps its own separate, nicked
		# backbone (same path an in-progress fragment already uses) until
		# ligase catches up to it. Sealed fragments are always a contiguous
		# PREFIX of lagging_fragments — ligase only ever moves forward,
		# never revisits (same invariant the old static toggle relied on,
		# just earned by the enzyme's own motion now instead of assumed) —
		# so "how far the merge extends" is one scan, not a per-fragment check.
		var last_sealed_idx := -1
		for idx in range(lagging_fragments.size()):
			var frag = lagging_fragments[idx]
			if not frag.sealed:
				break
			# Same defensive re-check the off-branch below relies on: a
			# fragment's capture animation can still be mid-flight for a
			# frame or two after it's logically closed. Sealing takes long
			# enough in practice that this should never actually trip, but
			# the guard costs nothing and keeps the same safety margin.
			var frag_ready = true
			for slot_index in frag.slots:
				if lagging_synthesized_bases[slot_index] == null and not _is_telomere_gap_slot(slot_index):
					frag_ready = false
					break
			if not frag_ready:
				break
			last_sealed_idx = idx

		var sealed_points = PackedVector2Array()
		for idx in range(lagging_fragments.size()):
			var frag = lagging_fragments[idx]
			if idx <= last_sealed_idx:
				# Only ever true for the last fragment in a non-gap Pol I run:
				# its own primer is never removed, so keep it as its own RNA
				# segment rather than freeing it or drawing the DNA line
				# straight through the RNA.
				var retains_primer = _lagging_fragment_retains_primer(frag)
				if frag.backbone != null and is_instance_valid(frag.backbone):
					frag.backbone.queue_free()
					frag.backbone = null
				if not retains_primer and frag.get("primer_backbone", null) != null and is_instance_valid(frag.primer_backbone):
					frag.primer_backbone.queue_free()
					frag.primer_backbone = null
				# Pre-existing gap, fixed alongside the primer_bond_marks
				# addition below: bond_marks were never freed when a
				# fragment merges into the sealed continuous line, so they
				# were left dangling (this branch stops calling
				# _lagging_render_fragment_backbone() for merged fragments,
				# so nothing else was going to shrink these back to 0 either).
				for mark in frag.bond_marks:
					if mark != null and is_instance_valid(mark): mark.queue_free()
				frag.bond_marks = []
				if not retains_primer:
					for mark in frag.get("primer_bond_marks", []):
						if mark != null and is_instance_valid(mark): mark.queue_free()
					frag.primer_bond_marks = []
				for slot_index in frag.slots:
					if lagging_synthesized_bases[slot_index] == null or _is_still_primer(slot_index):
						continue  # telomere gap slot (null) or retained RNA primer — merged DNA line stops here
					var wobble_y = sim.get_wobble_y(slot_index, wobble_t)
					var lagging_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
					sealed_points.append(Vector2(nucleotide_original_x[slot_index], lagging_y + tm.backbone_offset_distance))
				# Retained primer renders as its own RNA segment, bridged to the
				# merged DNA line so the join has no visible gap.
				if retains_primer:
					var pp = _lagging_render_retained_primer(frag, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)
					if sealed_points.size() > 0 and pp.size() > 0:
						sealed_points.append(pp[0])
				# Merged fragments never keep their own internal 5'/3' —
				# same reasoning DESIGN.md already gives for the no-ligase
				# continuous mode: an internal boundary inside a joined
				# stretch isn't meaningful anymore.
				_lagging_set_fragment_markers(frag, idx == 0, idx == last_sealed_idx, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)
			else:
				_lagging_render_fragment_backbone(frag, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)
				_lagging_render_fragment_markers(frag, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)

		lagging_backbone_line.points = sealed_points
		lagging_backbone_line.width = tm.backbone_line_width
		_update_bond_marks_lagging(sealed_points)

		if lagging_current_fragment != null:
			_lagging_render_fragment_backbone(lagging_current_fragment, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)
			_lagging_render_fragment_markers(lagging_current_fragment, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)
		return

	# ---- Continuous mode (no ligase modeled): backbone spans only COMPLETE
	# fragments, merged into one line. A fragment still being built keeps its
	# own separate backbone until it completes and joins the continuous line.
	#
	# "Complete" here means every slot's base has actually landed — NOT
	# merely that the fragment has been logically closed. Fragments fire
	# highest-index-first (right-to-left), so a fragment's LOWEST slot is
	# fired last, closing the fragment the instant it's fired — its capture
	# animation can still be mid-flight for a frame or two afterward. Merging
	# such a fragment into the continuous line before that slot lands would
	# skip the missing point and let Line2D draw straight through the gap,
	# bridging to the previous fragment before this one's final base has
	# actually appeared. So an incomplete-but-closed fragment keeps rendering
	# through its own separate backbone (same path the in-progress fragment
	# uses) until every slot is genuinely there.
	var continuous_points = PackedVector2Array()
	for frag in lagging_fragments:
		var frag_ready = true
		for slot_index in frag.slots:
			if lagging_synthesized_bases[slot_index] == null and not _is_telomere_gap_slot(slot_index):
				frag_ready = false
				break
		if not frag_ready:
			_lagging_render_fragment_backbone(frag, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)
			continue
		var retains_primer = _lagging_fragment_retains_primer(frag)
		if frag.backbone != null and is_instance_valid(frag.backbone):
			frag.backbone.queue_free()
			frag.backbone = null
		if not retains_primer and frag.get("primer_backbone", null) != null and is_instance_valid(frag.primer_backbone):
			frag.primer_backbone.queue_free()
			frag.primer_backbone = null
		for mark in frag.bond_marks:
			if mark != null and is_instance_valid(mark): mark.queue_free()
		frag.bond_marks = []
		if not retains_primer:
			for mark in frag.get("primer_bond_marks", []):
				if mark != null and is_instance_valid(mark): mark.queue_free()
			frag.primer_bond_marks = []
		for slot_index in frag.slots:
			if lagging_synthesized_bases[slot_index] == null or _is_still_primer(slot_index):
				continue  # telomere gap slot (null) or retained RNA primer — continuous DNA line stops here
			var wobble_y = sim.get_wobble_y(slot_index, wobble_t)
			var lagging_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
			continuous_points.append(Vector2(nucleotide_original_x[slot_index], lagging_y + tm.backbone_offset_distance))
		if retains_primer:
			var pp = _lagging_render_retained_primer(frag, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)
			if continuous_points.size() > 0 and pp.size() > 0:
				continuous_points.append(pp[0])

	lagging_backbone_line.points = continuous_points
	lagging_backbone_line.width = tm.backbone_line_width
	_update_bond_marks_lagging(continuous_points)

	if lagging_current_fragment != null:
		_lagging_render_fragment_backbone(lagging_current_fragment, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)

	# Only the very first fragment's 5' and the current last-complete
	# fragment's 3' survive — an internal boundary stops being meaningful
	# once the backbone actually connects through it. The highest index of
	# any fragment is always its FIRST-fired, long-settled slot, so there's
	# no same-frame race to worry about here — BUT it can still be a
	# telomere-gap slot with no base at all (terminal fragment after
	# telomerase removal), which is why _lagging_set_fragment_markers() uses
	# _lagging_fragment_last_rendered_slot() rather than frag.slots[-1]
	# directly for the 3' position.
	for idx in range(lagging_fragments.size()):
		var frag = lagging_fragments[idx]
		var want_5p = (idx == 0)
		var want_3p = (idx == lagging_fragments.size() - 1)
		_lagging_set_fragment_markers(frag, want_5p, want_3p, wobble_t, dna_ribbons_gap, new_bottom_template_y, nucleotide_original_x)

func _lagging_set_fragment_markers(frag: Dictionary, want_5p: bool, want_3p: bool, wobble_t: float, dna_ribbons_gap: float, new_bottom_template_y: float, nucleotide_original_x: Array) -> void:
	if frag.slots.size() == 0:
		return
	var first_slot = frag.slots[0]
	var last_slot = _lagging_fragment_last_rendered_slot(frag)
	var first_y = new_bottom_template_y + dna_ribbons_gap + sim.get_wobble_y(first_slot, wobble_t) + tm.backbone_offset_distance
	var last_y = new_bottom_template_y + dna_ribbons_gap + sim.get_wobble_y(last_slot, wobble_t) + tm.backbone_offset_distance
	# Hidden while atom-tier skeletal rendering is active — see the matching
	# comment in simulation.gd's marker block for the full rationale.
	var atom_tier_active: bool = molecule_renderer != null and molecule_renderer.is_molecular_mode_active()

	if want_5p and want_3p and frag.slots.size() == 1:
		if frag.marker_5p == null:
			frag.marker_5p = _spawn_marker("5'-3'", Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset))
		frag.marker_5p.position = Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset)
		frag.marker_5p.visible = not atom_tier_active
		if frag.marker_3p != null:
			frag.marker_3p.queue_free()
			frag.marker_3p = null
		return

	if want_5p:
		if frag.marker_5p == null:
			frag.marker_5p = _spawn_marker("5'", Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset))
		frag.marker_5p.position = Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset)
		frag.marker_5p.visible = not atom_tier_active
	elif frag.marker_5p != null:
		frag.marker_5p.queue_free()
		frag.marker_5p = null

	if want_3p:
		if frag.marker_3p == null:
			frag.marker_3p = _spawn_marker("3'", Vector2(nucleotide_original_x[last_slot], last_y + tm.marker_offset))
		frag.marker_3p.position = Vector2(nucleotide_original_x[last_slot], last_y + tm.marker_offset)
		frag.marker_3p.visible = not atom_tier_active
	elif frag.marker_3p != null:
		frag.marker_3p.queue_free()
		frag.marker_3p = null

func _lagging_render_fragment_backbone(frag: Dictionary, wobble_t: float, dna_ribbons_gap: float, new_bottom_template_y: float, nucleotide_original_x: Array) -> void:
	if frag.slots.size() == 0:
		return

	if frag.backbone == null:
		var line = Line2D.new()
		line.default_color = tm.backbone_color
		line.width = tm.backbone_line_width
		line.z_index = -1
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		sim.add_child(line)
		frag.backbone = line

	# Primer segment (RNA primer persistence pass): distinguished from the
	# DNA segment by THICKNESS and MARKER SHAPE first — accessibility: never
	# rely on color ALONE to depict a difference. rna_backbone_color is an
	# ADDED cue on top of that, not a replacement for it — thickness/shape
	# stay the primary distinguishing signal, color is redundant reinforcement.
	# Splits for as long as any of this fragment's slots fall in a primer
	# span — only relevant while primase is on. Never un-splits at Light
	# tier, same "held until Pol I" rule the base colors/shapes themselves
	# follow.
	var primase_on = complexity_mgr != null and complexity_mgr.is_enabled("primase")
	if primase_on and frag.get("primer_backbone", null) == null:
		var pline = Line2D.new()
		pline.default_color = tm.rna_backbone_color
		pline.width = tm.rna_backbone_line_width
		pline.z_index = -1
		pline.joint_mode = Line2D.LINE_JOINT_ROUND
		pline.begin_cap_mode = Line2D.LINE_CAP_ROUND
		pline.end_cap_mode = Line2D.LINE_CAP_ROUND
		sim.add_child(pline)
		frag.primer_backbone = pline

	var points = PackedVector2Array()
	for slot_index in frag.slots:
		if lagging_synthesized_bases[slot_index] != null:
			var wobble_y = sim.get_wobble_y(slot_index, wobble_t)
			var world_x = nucleotide_original_x[slot_index]
			var lagging_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
			points.append(Vector2(world_x, lagging_y + tm.backbone_offset_distance))

	# Primer segment computed from the DETERMINISTIC primer span (same math
	# _lagging_render()'s pending-backbone pass already uses), NOT from
	# frag.slots membership. frag.slots lags behind reality here: Pol III
	# still walks through already-primase-placed primer slots one
	# bookkeeping entry per fire-step even though it skips re-spawning them
	# (_capture_begin_lagging()'s guard) — so right after adoption,
	# frag.slots can briefly contain only 1 of the primer's 3 slots even
	# though all 3 are already placed. Deriving primer_points from
	# frag.slots instead of the deterministic span made an already-fully-
	# placed primer visibly SHRINK for a couple of fire-steps right after
	# Pol III opened the fragment, before catching back up — this is what
	# was actually behind the "stuck with RNA specs" reports. The DNA
	# portion still genuinely depends on frag.slots/Pol III's own progress
	# (those slots aren't placed until Pol III gets there), so that part is
	# unchanged.
	var dna_points = points
	var primer_points = PackedVector2Array()
	if primase_on and frag.slots.size() > 0:
		var tile_end = _primase_tile_end(frag.slots[-1])
		var span = _primase_primer_length()
		for slot_index in range(max(0, tile_end - span), tile_end):
			if lagging_synthesized_bases[slot_index] != null and _is_still_primer(slot_index):
				var wobble_y = sim.get_wobble_y(slot_index, wobble_t)
				var world_x = nucleotide_original_x[slot_index]
				var lagging_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
				primer_points.append(Vector2(world_x, lagging_y + tm.backbone_offset_distance))

		# DNA points: everything in frag.slots that ISN'T still primer-styled
		# (includes both slots that were never primer, and primer slots Pol
		# III has already converted).
		dna_points = PackedVector2Array()
		for slot_index in frag.slots:
			if lagging_synthesized_bases[slot_index] != null and not _is_still_primer(slot_index):
				var wobble_y = sim.get_wobble_y(slot_index, wobble_t)
				var world_x = nucleotide_original_x[slot_index]
				var lagging_y = new_bottom_template_y + dna_ribbons_gap + wobble_y
				dna_points.append(Vector2(world_x, lagging_y + tm.backbone_offset_distance))

		# Shared boundary point so the two segments join with no visual gap
		# — previously free (a shared array slice), now explicit since the
		# two point sets are built independently.
		if dna_points.size() > 0 and primer_points.size() > 0:
			dna_points.append(primer_points[0])

	frag.backbone.points = dna_points
	frag.backbone.width = tm.backbone_line_width
	frag.backbone.z_index = -1
	if frag.get("primer_backbone", null) != null:
		frag.primer_backbone.points = primer_points
		frag.primer_backbone.width = tm.rna_backbone_line_width
		# Draws BEHIND the DNA segment at their shared boundary point —
		# previously both sat at the same z_index, so draw order came down
		# to child-add order (primer_backbone created second, drawing on
		# top). Not confirmed as the root cause of the reported bug, but a
		# real ordering issue worth fixing regardless.
		frag.primer_backbone.z_index = -2

	frag.bond_marks = _update_bond_marks_generic(frag.bond_marks, dna_points, sim._create_bond_mark_sprite_reversed)
	if frag.get("primer_backbone", null) != null:
		frag.primer_bond_marks = _update_bond_marks_generic(frag.get("primer_bond_marks", []), primer_points, sim._create_bond_mark_sprite_rna_reversed)

	# Bug A suppression for this fragment's visuals now lives in
	# _apply_highlight() (single-writer fix) instead of here — this
	# function runs before render()'s own _apply_highlight() call, so a
	# write here would have been clobbered by strand_dim just like the
	# other cases this fix addresses.

## Shared grow/shrink/position loop for a fragment's bond-mark holders —
## `sprite_fn` is whichever mark shape this segment needs (filled triangle
## for DNA, open chevron for RNA), so the same loop serves both without
## duplicating it.
func _update_bond_marks_generic(marks: Array, points: PackedVector2Array, sprite_fn: Callable) -> Array:
	var needed = max(0, points.size() - 1)
	while marks.size() < needed:
		marks.append(sprite_fn.call())
	while marks.size() > needed:
		var extra = marks.pop_back()
		extra.queue_free()
	for i in range(needed):
		var a = points[i]
		var b = points[i + 1]
		var mid = (a + b) / 2.0
		var segment = b - a
		var mark = marks[i]
		mark.position = mid
		mark.visible = segment.length() > 0.0
	return marks

func _lagging_natural_done_consumed(num_slots: int, nucleotide_original_x: Array) -> int:
	# How many lagging slots would be consumed by pure position-based tiling
	# the instant the helicase reaches its own final position — before any
	# catch-up steps are applied. Shared by _lagging_scrub_rebuild() and
	# get_lagging_catchup_steps_needed() so both use the identical formula.
	var last_slot_index = num_slots - 1
	var offset_px = sim.polymerase_x_offset_slots * sim.nucleotide_slot_spacing
	var polymerase_x_at_last_slot = nucleotide_original_x[last_slot_index] - offset_px
	var remaining_leading = 0
	for i in range(num_slots):
		if nucleotide_original_x[i] > polymerase_x_at_last_slot:
			remaining_leading += 1
	var effective_index = last_slot_index + max(1, remaining_leading)

	var threshold = sim.okazaki_fragment_size + sim.pll_slot_count
	var exposed_count = max(0, effective_index)
	var attempted = 0
	if exposed_count >= threshold:
		attempted = exposed_count - threshold + 1
	return clamp(attempted, 0, num_slots)

## Public: how many extra arrow-key steps past the helicase's own last slot
## are needed for the lagging strand to fully catch up, at base complexity
## (lagging_gap_enabled = false). Used by simulation.gd to extend the
## scrubbable range for scrub_to_nucleotide_index().
func get_lagging_catchup_steps_needed(num_slots: int, nucleotide_original_x: Array) -> int:
	return num_slots - _lagging_natural_done_consumed(num_slots, nucleotide_original_x)

func is_fully_complete() -> bool:
	# True only once the whole replisome has visually faded out — i.e. after
	# lagging catch-up finishes (or, under lagging_gap_enabled, after the
	# telomere-gap discard settles). helicase_mgr reaching Phase.DONE is NOT
	# this: the lagging strand keeps synthesizing on its own independent
	# lagging_catchup_timer for a while after the helicase itself finishes
	# (see _on_helicase_phase_changed() / _lagging_start_catchup()). Callers
	# that want "is there still anything moving on screen" should use this,
	# not helicase_mgr.get_phase() == Phase.DONE.
	return lagging_polymerase_faded

func _lagging_render_fragment_markers(frag: Dictionary, wobble_t: float, dna_ribbons_gap: float, new_bottom_template_y: float, nucleotide_original_x: Array) -> void:
	if frag.slots.size() == 0 or not frag.complete:
		return

	var first_slot = frag.slots[0]
	var last_slot = _lagging_fragment_last_rendered_slot(frag)
	var first_y = new_bottom_template_y + dna_ribbons_gap + sim.get_wobble_y(first_slot, wobble_t) + tm.backbone_offset_distance
	var last_y = new_bottom_template_y + dna_ribbons_gap + sim.get_wobble_y(last_slot, wobble_t) + tm.backbone_offset_distance
	# Hidden while atom-tier skeletal rendering is active — see the matching
	# comment in simulation.gd's marker block for the full rationale.
	var atom_tier_active: bool = molecule_renderer != null and molecule_renderer.is_molecular_mode_active()

	if frag.slots.size() == 1:
		if frag.marker_5p == null:
			frag.marker_5p = _spawn_marker("5'-3'", Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset))
		frag.marker_5p.position = Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset)
		frag.marker_5p.visible = not atom_tier_active
	else:
		if frag.marker_5p == null:
			frag.marker_5p = _spawn_marker("5'", Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset))
		frag.marker_5p.position = Vector2(nucleotide_original_x[first_slot], first_y + tm.marker_offset)
		frag.marker_5p.visible = not atom_tier_active
		if frag.marker_3p == null:
			frag.marker_3p = _spawn_marker("3'", Vector2(nucleotide_original_x[last_slot], last_y + tm.marker_offset))
		frag.marker_3p.position = Vector2(nucleotide_original_x[last_slot], last_y + tm.marker_offset)
		frag.marker_3p.visible = not atom_tier_active

func _update_bond_marks_lagging(points: PackedVector2Array) -> void:
	var needed = max(0, points.size() - 1)
	while lagging_bond_marks.size() < needed:
		lagging_bond_marks.append(sim._create_bond_mark_sprite_reversed())
	while lagging_bond_marks.size() > needed:
		var extra = lagging_bond_marks.pop_back()
		if extra != null and is_instance_valid(extra): extra.queue_free()
	for i in range(needed):
		var a = points[i]
		var b = points[i + 1]
		var mid = (a + b) / 2.0
		var segment = b - a
		var mark = lagging_bond_marks[i]
		mark.position = mid
		mark.visible = segment.length() > 0.0
		if mark.visible:
			mark.rotation = segment.angle()

func _set_lagging_pump_phase(phase: float) -> void:
	if lagging_clamp != null:
		lagging_clamp.set_pump(sin(phase * PI))
	_capture_update_lagging(phase)

# ==========================================
# CAPTURE — self-contained section
# ==========================================
# Owns: the traveling nucleotide during a step. Triggered once per step, at
# step START (not arrival) — _capture_on_leading_slot_reached() for leading
# (off helicase.slot_reached directly, since leading has no other per-step
# event), _capture_begin_lagging() called from _lagging_fire_step() for
# lagging (which already has a clean step-start call site).
#
# The node created here IS the permanent synthesized base — there is no
# placeholder swap. It is deliberately kept OUT of leading_synthesized_bases /
# lagging_synthesized_bases until leg 2 completes, so the existing render()
# functions (which position every non-null array entry to its final row every
# frame) never fight the traveling node. This is also why no changes were
# needed anywhere in _leading_render()/_lagging_render()/backbone/hydrogen-bond
# code: the traveling node is invisible to all of that machinery until it
# "graduates" into the array at the exact moment it settles into place.
#
# Two legs per step, split at the pump's own halfway point:
#   Leg 1 (step_t/phase 0 -> 0.5): a LIVE FOLLOW, not a tween — the clamp
#     itself is still mid-glide toward the slot during this half, so there is
#     no fixed destination yet. Every frame, position is set directly to
#     get_jaw_cap_inner_anchor(), which already accounts for the clamp's
#     glide + pump animation via to_global(). Chosen over a tween specifically
#     because a fixed-endpoint tween started at leg-1's beginning would target
#     where the jaw WILL be, not where it IS — looking disconnected while the
#     clamp is still moving.
#   Leg 2 (step_t/phase 0.5 -> 1): a genuine tween, from wherever leg 1 left
#     off to the base's true final resting position — valid as a fixed-point
#     tween because by this half, the clamp itself has arrived and stopped.
#     Reads as the jaw depositing the nucleotide into place.
#
# Scrub never runs any of this — scrub_rebuild() calls _capture_reset() up
# front and places finished bases instantly via the untouched
# _spawn_leading_base()/_spawn_lagging_base() call sites, same as before.

func _capture_reset() -> void:
	if leading_capture_node != null and is_instance_valid(leading_capture_node):
		leading_capture_node.queue_free()
	leading_capture_node = null
	if leading_capture_tween != null and leading_capture_tween.is_valid():
		leading_capture_tween.kill()
	leading_capture_tween = null
	leading_capture_target_slot = -1
	leading_capture_leg2_started = false

	if lagging_capture_node != null and is_instance_valid(lagging_capture_node):
		lagging_capture_node.queue_free()
	lagging_capture_node = null
	if lagging_capture_tween != null and lagging_capture_tween.is_valid():
		lagging_capture_tween.kill()
	lagging_capture_tween = null
	lagging_capture_target_slot = -1
	lagging_capture_leg2_started = false

func _capture_teardown() -> void:
	_capture_reset()

# ---------- LEADING ----------

func _capture_on_leading_slot_reached(index: int) -> void:
	# Slot mapping mirrors the lagging strand's own documented relationship:
	# when the helicase reaches `index`, the leading polymerase's position
	# corresponds to slot (index - polymerase_x_offset_slots) — same formula
	# polymerase_x itself is built from. Holds during FINISHING's extra steps
	# too (index just keeps climbing past num_slots-1; the old position-poll
	# this replaces relied on the same incidental correctness).
	var target = index + 1 - sim.polymerase_x_offset_slots
	if target < 0 or target >= sim.num_nucleotide_slots:
		return

	# Catch-up: if the immediately-preceding slot is ALSO missing and has no
	# capture in flight for it at all (not merely still animating — that case
	# is already handled by _capture_begin_leading()'s own
	# force-finish-previous-capture logic below), its trigger never fired in
	# the first place. This only happens right after a scrub:
	# helicase_mgr.scrub_to_slot() sets current_slot_index directly without
	# emitting slot_reached, so the capture that "belongs" to that slot never
	# began. Place it instantly here — no animation, matching how scrub
	# itself places finished bases — so it isn't permanently skipped. This
	# keeps _leading_scrub_rebuild()'s own fill count exact (matching where
	# the polymerase clamp actually renders) instead of over-filling ahead of
	# it to paper over the same gap.
	var prev = target - 1
	if prev >= 0 and leading_synthesized_bases[prev] == null and leading_capture_target_slot != prev:
		# Reverted — see get_synthesized_nucleotides()'s comment.
		leading_synthesized_bases[prev] = _spawn_leading_base(prev, sim.dna_sequence.get_complement(prev))
		leading_hydrogen_bonds[prev] = _spawn_leading_hydrogen_bonds(prev)

	if leading_synthesized_bases[target] != null:
		return
	_capture_begin_leading(target, connected_helicase_mgr.step_duration)

func _capture_begin_leading(index: int, duration: float) -> void:
	if leading_synthesized_bases[index] != null:
		return
	if leading_capture_node != null:
		_capture_finish_leading(leading_capture_target_slot, leading_capture_node)
	# Reverted — see get_synthesized_nucleotides()'s comment.
	var base_type = sim.dna_sequence.get_complement(index)
	var fallback_pos = Vector2(sim.nucleotide_original_x[index], sim.new_top_template_y - sim.dna_ribbons_gap)
	var start_pos = leading_halo.capture_particle(base_type) if leading_halo != null else fallback_pos
	leading_capture_node = _spawn_leading_base(index, base_type, start_pos)
	leading_capture_target_slot = index
	leading_capture_leg2_started = false

## Called every frame from update()'s leading block. step_t/duration are the
## SAME values already driving the clamp's glide and pump — capture rides
## those, not an independent clock.
func _capture_update_leading(step_t: float, duration: float) -> void:
	if leading_capture_node == null:
		return
	if step_t < 0.5:
		if leading_clamp != null:
			leading_capture_node.position = leading_clamp.get_jaw_cap_inner_anchor()
	elif not leading_capture_leg2_started:
		leading_capture_leg2_started = true
		var index = leading_capture_target_slot
		var node = leading_capture_node
		var final_pos = Vector2(sim.nucleotide_original_x[index], sim.new_top_template_y - sim.dna_ribbons_gap)
		var tween = sim.create_tween()
		tween.tween_property(node, "position", final_pos, duration / 2.0)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_callback(_capture_finish_leading.bind(index, node))
		leading_capture_tween = tween

func _capture_finish_leading(index: int, node: Node2D) -> void:
	leading_synthesized_bases[index] = node
	leading_hydrogen_bonds[index] = _spawn_leading_hydrogen_bonds(index)
	node.position = Vector2(sim.nucleotide_original_x[index], sim.new_top_template_y - sim.dna_ribbons_gap)
	if leading_capture_node == node:
		leading_capture_node = null
		leading_capture_target_slot = -1
		if leading_capture_tween != null and leading_capture_tween.is_valid():
			leading_capture_tween.kill()
		leading_capture_tween = null

# ---------- LAGGING ----------

func _capture_begin_lagging(index: int, duration: float) -> void:
	if lagging_synthesized_bases[index] != null:
		if not _pol1_enabled():
			_pol3_convert_primer_if_needed(index)
		return
	if lagging_capture_node != null:
		_capture_finish_lagging(lagging_capture_target_slot, lagging_capture_node)
	# Reverted — see _convert_primer_base_to_dna()'s comment.
	var base_type = sim.dna_sequence.get_base(index)
	var fallback_pos = Vector2(sim.nucleotide_original_x[index], sim.new_bottom_template_y + sim.dna_ribbons_gap)
	var start_pos = lagging_halo.capture_particle(base_type) if lagging_halo != null else fallback_pos
	lagging_capture_node = _spawn_lagging_base(index, base_type, start_pos)
	lagging_capture_target_slot = index
	lagging_capture_leg2_started = false
	lagging_capture_leg2_duration = duration / 2.0

## Called from _set_lagging_pump_phase(), which already runs every frame of
## the pump tween (live or catch-up) — reused as capture's per-frame hook
## rather than adding a second timing source for the same step.
func _capture_update_lagging(phase: float) -> void:
	if lagging_capture_node == null:
		return
	if phase < 0.5:
		if lagging_clamp != null:
			lagging_capture_node.position = lagging_clamp.get_jaw_cap_inner_anchor()
	elif not lagging_capture_leg2_started:
		lagging_capture_leg2_started = true
		var index = lagging_capture_target_slot
		var node = lagging_capture_node
		var final_pos = Vector2(sim.nucleotide_original_x[index], sim.new_bottom_template_y + sim.dna_ribbons_gap)
		var tween = sim.create_tween()
		tween.tween_property(node, "position", final_pos, lagging_capture_leg2_duration)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_callback(_capture_finish_lagging.bind(index, node))
		lagging_capture_tween = tween

func _capture_finish_lagging(index: int, node: Node2D) -> void:
	lagging_synthesized_bases[index] = node
	lagging_hydrogen_bonds[index] = _spawn_lagging_hydrogen_bonds(index)
	node.position = Vector2(sim.nucleotide_original_x[index], sim.new_bottom_template_y + sim.dna_ribbons_gap)
	if lagging_capture_node == node:
		lagging_capture_node = null
		lagging_capture_target_slot = -1
		if lagging_capture_tween != null and lagging_capture_tween.is_valid():
			lagging_capture_tween.kill()
		lagging_capture_tween = null

# ==========================================
# SHARED SPAWNING HELPERS
# ==========================================

func _spawn_marker(marker_type: String, world_pos: Vector2) -> Node2D:
	var marker = sim.NewNitrogenBaseScene.instantiate()
	marker.position = world_pos
	marker.z_index = 3
	sim.add_child(marker)
	marker.set_base_type(marker_type)
	marker.set_radius(tm.base_radius)
	marker.set_colors(tm.marker_color, tm.marker_font_color)
	marker.set_font(tm.marker_font_size, tm.marker_font)
	marker.set_label_rotation(_zoom_label_rotation())
	return marker

func _create_bond_mark_sprite() -> Node2D:
	# Single triangle, tip pointing LEFT — see the matching function in
	# simulation.gd for the full rationale (replaces a two-diamond masking
	# trick that broke visibly during alpha fades).
	var holder = Node2D.new()
	var h = tm.backbone_line_width / 2.0
	var w = tm.bond_mark_width
	var triangle = Polygon2D.new()
	triangle.polygon = PackedVector2Array([
		Vector2(-w / 2.0, 0),
		Vector2(0, -h),
		Vector2(0, h),
	])
	triangle.color = tm.bond_mark_color
	holder.add_child(triangle)
	holder.z_index = 1
	sim.add_child(holder)
	return holder
