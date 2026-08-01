extends Node

# ==========================================
# THEME MANAGER
# Autoload (singleton) that centralises all visual styling for the
# simulation. Every color and thickness is an @export so the Inspector
# can be used to tweak values directly. Later these will be wired to a
# UI for runtime switching, including a light/dark theme toggle.
#
# Registration: Project Settings → Autoload → add this script as
# "ThemeManager" (no scene needed, plain script autoload).
# ==========================================

@export_group("Background")
@export var background_color: Color = Color(0.15377063, 0.22897473, 0.44707716, 1.0)

@export_group("Wobble")
@export var wobble_enabled: bool = true

@export_group("Nitrogen Base Settings")
@export var base_color_a: Color = Color(0.8, 0.2, 0.2, 1.0)
@export var base_color_t: Color = Color(0.2, 0.2, 0.8, 1.0)
@export var base_color_c: Color = Color(0.85, 0.6, 0.1, 1.0)
@export var base_color_g: Color = Color(0.2, 0.8, 0.2, 1.0)
@export var base_label_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var base_label_font_size: int = 14
@export var base_label_font: Font = null
@export var base_radius: float = 15.0

@export_group("Backbone")
@export var backbone_color: Color = Color(0.43137255, 0.72156864, 1.0, 1.0)
@export var template_backbone_color: Color = Color(0.6, 0.6, 0.6)  # placeholder — tune in Inspector
@export var backbone_line_width: float = 16.0
@export var backbone_offset_distance: float = 24.0
@export var backbone_offset_smoothing_speed: float = 10.0

@export_group("Bond Marks")
@export var bond_mark_width: float = 14.0
@export var bond_mark_color: Color = Color(0.0, 0.0, 0.0, 1.0)

@export_group("Hydrogen Bonds")
@export var at_bond_color: Color = Color(1.0, 0.85, 0.3, 1.0)
@export var cg_bond_color: Color = Color(0.3, 0.85, 1.0, 1.0)
@export var hydrogen_bond_width: float = 1.5
@export var hydrogen_bond_spacing: float = 4.0

@export_group("Synthesis Circle")
@export var synthesis_circle_color: Color = Color(1.0, 0.0, 0.101960786, 1.0)

@export_group("Helicase Ring")
## Standalone toggle, same relationship to a future low-info theme that
## wobble_enabled already has: a low-info preset will simply set this false.
## Independent of scrub — scrub freezes the ring regardless of this value.
@export var helicase_ring_rotation_enabled: bool = true
@export var helicase_ring_blob_count: int = 6
@export var helicase_ring_ring_radius: float = 80.0
@export var helicase_ring_max_blob_height: float = 90.0
@export var helicase_ring_max_blob_width: float = 50.0
@export_range(0.0, 1.0) var helicase_ring_min_width_ratio: float = 0.6
@export_range(0.0, 1.0) var helicase_ring_chamfer_ratio: float = 0.35
@export_range(0.0, 1.0) var helicase_ring_corner_radius_ratio: float = 0.6
@export_range(2, 8) var helicase_ring_corner_segments: int = 4
## Degrees rotated per unit roll during live play. Frozen (scrub / rotation
## disabled) ignores this and holds the static symmetric pose.
@export var helicase_ring_step_angle_deg: float = 60.0
@export var helicase_ring_front_color: Color = Color(0.22, 0.45, 0.85, 1.0)
@export var helicase_ring_back_color: Color = Color(0.14, 0.28, 0.55, 1.0)
@export var helicase_ring_front_z: int = 4
@export var helicase_ring_back_z: int = -1
@export_range(-45.0, 45.0, 0.1) var helicase_ring_skew_deg: float = 3.0

# ---------- ATP cycle: helicase-specific timeline (ATPCycleDesign.md) ----------
# These live in the Helicase Ring group rather than the shared "Cofactor"
# group below because every one of them is a quantity in HELICASE step_t
# space, and because they are genuinely ATP-SPECIFIC: helicase runs on ATP in
# bacteria and eukaryotes alike, so the atp_ prefix stays honest here. The
# shared group holds whatever the cofactor of the moment looks like. Two
# prefixes coexisting is the labeled-chimera principle applied to field names
# — shared thing shared, divergent thing labeled.
## RAW step_t at which the whole ATP begins drifting in, measured in the
## PRIOR step. The approach sits AHEAD of the step it fuels so the helicase's
## own pace never changes — nothing here compresses the glide or delays the
## barrel roll.
@export_range(0.0, 1.0) var atp_spawn_lead_ratio: float = 0.7
## RAW step_t WIDTH of the spark's visible band, not a duration in seconds.
## At 1x (base_step_duration 0.5) 0.10 is roughly 0.05s — about three frames
## at 60fps, a classic arcade-flash length. Because it is a width it scales
## with the speed multiplier and may drop below one frame at 8x; accepted,
## since the barrel roll and nucleotide capture are equally illegible there.
@export_range(0.0, 1.0) var atp_spark_window: float = 0.10
## EASED step_t at which ADP and Pi have fully faded — a position on the
## cubic ease-out curve, NOT a number of seconds. Clears the site before the
## next spark fires at the following boundary.
@export_range(0.0, 1.0) var atp_byproduct_fade_end_eased: float = 0.9
## Pi escapes forward and UP ("2 o'clock") while ADP recedes level and
## backward — spent-to-drive-the-motion against discarded. Independent of
## slot geometry on purpose: the angle is a thing to eyeball against the real
## scene, and ADP already reuses nucleotide_slot_spacing for its own recede.
@export var atp_pi_x_ratio: float = 0.6
@export var atp_pi_rise_distance: float = 90.0
## Where the whole ATP drifts in from, in the helicase node's local space.
## Ahead of and above the fork, so it reads as arriving from solution rather
## than being emitted by the DNA.
@export var atp_approach_offset: Vector2 = Vector2(150.0, -130.0)

@export_group("Cofactor")
# The cofactor's own identity, shared so a cofactor looks like the SAME
# molecule wherever it appears — helicase and eukaryotic ligase (both ATP)
# today, bacterial ligase (NAD+) next, and whatever Krebs brings after that.
#
# Renamed from "ATP Cycle" once it was clear the group would outlive ATP:
# NAD+, FAD, CoA and GTP are all coming, and a group named for one of its
# members ages badly. cofactor_head_scale carries the same lesson — it was
# atp_adenine_scale, which holds for ATP/NAD+/FAD/CoA and then breaks on GTP,
# whose head is guanine. Named for the ROLE, not the molecule.
#
# The head bead deliberately reuses the DNA base's visual language: ATP's A
# IS the same adenine as the base, and showing that is the pedagogical
# payoff. It gets no color field of its own — simulation.gd pushes
# base_color_a verbatim, so the two can never drift apart. A future guanine-
# headed cofactor (GTP) will need that push to become mode-dependent. The distinction
# between substrate incorporation and cofactor activation is carried by the
# phosphate tail (no free nucleotide glyph has one) and by the discard
# behavior, not by making the adenine look different.
@export var cofactor_bead_size: float = 7.0                 # phosphate bead radius
@export_range(0.1, 2.0) var cofactor_head_scale: float = 0.75   # multiplies base_radius
@export var cofactor_bead_spacing: float = 20.0             # centre-to-centre along the chain
@export var cofactor_bead_color: Color = Color(0.95, 0.80, 0.25, 1.0)
## The one bead that differs by donor (NAD+ pass, ATPCycleDesign.md).
## Deliberately a different hue from cofactor_bead_color rather than a
## shape change: NMN's two beads (P + nicotinamide) are already visually
## DISTINCT from each other by colour alone, which is exactly why the fused-
## connector treatment PPi needs is correctly dropped for NMN — two
## differently-coloured beads read as "a pair," not "one ambiguous unit,"
## without needing a thick link to say so.
@export var cofactor_nicotinamide_color: Color = Color(0.55, 0.35, 0.85, 1.0)
@export var cofactor_link_color: Color = Color(0.95, 0.80, 0.25, 1.0)
@export var cofactor_link_width: float = 4.0
@export var cofactor_label_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var cofactor_label_font_size: int = 10
## Beads carry chemical symbols only — "A" on the adenine, "P" on each
## phosphate. Identical in every language, so this lens adds NOTHING to the
## localization surface. Molecule-level name tags ("ATP"/"ADP"/"AMP") are
## deliberately absent: the bead count already is the label, and the whole
## point is that a student reads spent-ness off the tail length.
@export var cofactor_label_font: Font = null
@export var cofactor_spark_color: Color = Color(1.0, 0.95, 0.6, 1.0)
@export var cofactor_spark_radius: float = 34.0
@export var cofactor_spark_width: float = 3.0
## Absolute z. Must clear helicase_ring_front_z (4) or the docked ATP vanishes
## behind whichever blob is front-centre at the boundary — which is exactly
## the moment it needs to be visible.
@export var cofactor_z: int = 6

# ---------- Ligase-pass additions (v79) ----------
## PPi's fused connector — the one genuinely new piece of geometry in this
## design, with no primitive in procedural_shape_utils.gd to build on. Its
## thickness must clear cofactor_link_width by enough that "one rigid unit" is
## unmistakable: PPi must never read as two loose phosphates that happen to
## be adjacent, which is exactly what distinguishes it from helicase's single
## free Pi. Shape and thickness first, never colour alone.
@export var cofactor_fused_link_width: float = 9.0
@export var cofactor_fused_link_color: Color = Color(0.95, 0.80, 0.25, 1.0)
## Where a DISCARDED cluster drifts to before vanishing — PPi at cleave, and
## the released AMP at seal completion. Deliberately one field serving both:
## they are the same event ("this molecule is now waste, see it leave"), so a
## single authoritative source is correct here rather than two numbers that
## would only ever be tuned to agree. Named for the event, not for PPi, so the
## shared use reads as intended rather than as a leftover.
@export var cofactor_discard_drift: Vector2 = Vector2(70.0, -60.0)
## SECONDS, unlike the helicase's atp_spark_window (a raw step_t width) and
## atp_byproduct_fade_end_eased (a position on the eased curve). The ligase
## cycle is genuinely tween-driven — ligase.gd is hidden entirely during
## scrub, so it inherits no reconstruct-instantly contract — which is why
## seconds are the honest unit HERE and were the wrong unit there. The design
## doc listed cofactor_spark_duration in this group from the start; it only became
## meaningful once the tween-driven half was built.
@export var cofactor_spark_duration: float = 0.12
@export var cofactor_fade_duration: float = 0.35

@export_group("Polymerase Clamp")
## Two-piece procedural clamp (polymerase_clamp.gd). Geometry is in pixels;
## the vertical span is derived from dna_ribbons_gap + backbone margins at
## runtime, so these tune the shape ON TOP of the live duplex height.
## Colours are per-strand: leading = the mirrored clamp, lagging = the
## non-mirrored one.
@export var clamp_margin: float = 30.0             # extra height past each duplex edge at DOWN
@export var clamp_back_grow: float = 40.0          # extra back height at UP (t=1); negative retracts
@export var clamp_back_width: float = 90.0
@export var clamp_jaw_width: float = 90.0
@export_range(0.05, 1.0) var clamp_jaw_height_ratio: float = 0.35   # * back's DOWN height
## Lower jaw (pincer partner, mirrors the jaw about the duplex midline).
## Kept deliberately short by default — didactically it must stay clear of
## the lagging strand's nitrogen base so the base pairing stays visible.
@export var clamp_lower_jaw_width: float = 90.0
@export_range(0.05, 1.0) var clamp_lower_jaw_height_ratio: float = 0.15   # * back's DOWN height
@export_range(0.0, 1.0) var clamp_outside_chamfer_ratio: float = 0.35  # crisp baseline + outer corners
@export_range(0.0, 1.0) var clamp_inside_chamfer_ratio: float = 0.6    # UP-state inner-corner stretch
@export_range(0.0, 1.0) var clamp_corner_radius_ratio: float = 0.6
@export_range(2, 8) var clamp_corner_segments: int = 4
## Absolute z so the DNA renders BETWEEN the pieces (DNA: backbone -1, bonds 0,
## bases 2, markers 3). Back must sit below the backbone, front above the markers.
@export var clamp_back_z: int = -3
@export var clamp_front_z: int = 4
@export var clamp_leading_back_color: Color = Color(0.22, 0.42, 1.0, 1.0)
@export var clamp_leading_front_color: Color = Color(0.45, 0.60, 1.0, 1.0)
@export var clamp_lagging_back_color: Color = Color(0.80, 0.32, 0.32, 1.0)
@export var clamp_lagging_front_color: Color = Color(0.95, 0.52, 0.52, 1.0)
## End-of-run resting position. Once the lagging polymerase finishes its last
## fragment it would otherwise sit frozen on top of Pol I / ligase as they
## finish their catch-up queue — so both polymerases slide to a shared rest
## spot: the lagging one travels up to meet the leading one, and both nudge
## `rest_nudge_slots` slot-spacings past the strand's end so they clear the DNA
## rather than resting over it. Duration is the slide; nudge is how far past
## the end. Tunable independently — this is pure end-state framing, unrelated
## to any mid-run pacing number.
@export var polymerase_rest_nudge_slots: float = 2.0
@export var polymerase_rest_move_duration: float = 0.5

@export_group("Ligase")
## Single procedural blob (ligase.gd) — Complex-tier trailing enzyme, see
## OkazakiMaturationDesign.md. Position is driven externally (replication_
## manager.gd tweens this node's own position); these params tune only its
## shape/color/pulse.
@export var ligase_base_size: float = 36.0
@export_range(0.1, 1.0) var ligase_pinch_ratio: float = 0.55   # width at full pulse, relative to base_size
@export_range(0.0, 1.0) var ligase_chamfer_ratio: float = 0.35
@export_range(0.0, 1.0) var ligase_corner_radius_ratio: float = 0.6
@export_range(2, 8) var ligase_corner_segments: int = 4
@export var ligase_rest_color: Color = Color(0.85, 0.65, 0.13, 1.0)
@export var ligase_pulse_color: Color = Color(1.0, 0.85, 0.3, 1.0)
@export var ligase_z: int = 5
@export var ligase_label_margin: float = 12.0
## Time to travel to the next pending fragment boundary, and total pulse
## duration once there (split 50/50 between the pinch-in and pinch-out
## halves) — independently tunable, per this project's "never let two
## numbers coincidentally agree" rule.
@export var ligase_travel_duration: float = 0.4
## How long ligase sits parked at the nick, fully visible, before it starts
## pulsing/sealing — decoupled from travel speed so the gap stays legible
## regardless of how snappy ligase's own movement is (feedback: the seal was
## too fast to actually see the nick before it closed).
@export var ligase_hold_duration: float = 0.5
@export var ligase_seal_duration: float = 0.3
## Vertical distance ligase parks BELOW the strand at its offstage rest spot,
## so its first seal rises up into place rather than dropping in from the
## node's local origin. Defaults to Pol I's own offstage drop (40.0) so the two
## enzymes enter/leave at a matching depth, but split out as its own field so
## ligase's spawn depth can be tuned independently later without disturbing
## Pol I — per this project's "never let two numbers coincidentally agree" rule.
@export var ligase_offstage_drop: float = 40.0
## ATP cycle, ligase half (ATPCycleDesign.md). Offsets are local to the
## ligase node, which is legitimate because ligase is STATIONARY for the whole
## cofactor sequence — it only moves during TRAVELING, and every step of the
## cycle happens at or after the TRAVELING->HOLDING boundary.
## Carry: where the cofactor rides on the blob. Nick: where the AMP lands when
## it transfers onto the nick's 5' end (adenylylation).
@export var ligase_cofactor_carry_offset: Vector2 = Vector2(-46.0, -34.0)
@export var ligase_cofactor_nick_offset: Vector2 = Vector2(-6.0, 14.0)
## The adenylylation hop, run in parallel with the seal pulse's RELEASE half
## (0.15s at default ligase_seal_duration). Deliberately shorter than that
## half so it lands with a beat to spare rather than racing the pulse — do not
## let this creep up to 0.15 and coincidentally agree with it.
@export var ligase_amp_hop_duration: float = 0.10

@export_group("Primase")
## Now does REAL per-slot placement (RNA primer persistence pass) — no longer
## a purely decorative blip. Fires once per slot within a fragment's primer
## span, driven by the SAME helicase-passage event as everything else (see
## replication_manager.gd's _primase_check_slot()) — no independent pacing
## constant needed, its cadence already IS the helicase's cadence.
@export var primase_blip_size: float = 30.0
@export_range(0.0, 1.0) var primase_blip_chamfer_ratio: float = 0.35
@export_range(0.0, 1.0) var primase_blip_corner_radius_ratio: float = 0.6
@export_range(2, 8) var primase_blip_corner_segments: int = 4
@export var primase_blip_color: Color = Color(0.6, 0.25, 0.75, 1.0)  # also reused as the primer backbone color
@export var primase_pulse_color: Color = Color(0.85, 0.55, 1.0, 1.0)
## Primase's pulse GROWS (unlike ligase's pinch/shrink) — a distinct enough
## motion language that the two enzymes don't read as the same gesture.
@export_range(1.0, 2.0) var primase_pulse_scale_ratio: float = 1.3
@export var primase_blip_z: int = 5
@export var primase_blip_label_margin: float = 12.0
@export var primase_blip_fade_in_duration: float = 0.15
## Held fixed again (not fragment-duration-tied, per the earlier scrapped
## approach) — the PLACED BASES are the real persisted state now, RNA-colored
## until Pol I exists; the enzyme itself just needs a brief settle before
## leaving, not to stay parked for a whole fragment's duration.
@export var primase_blip_hold_duration: float = 0.2
@export var primase_blip_fade_out_duration: float = 0.2
## Single-leg flight duration for each captured ribonucleotide, halo capture
## point -> final resting position (Pol III's own capture routes through the
## clamp's jaw as an extra leg — primase has no clamp, so one leg is the
## honest version, not a shortcut).
@export var primase_capture_duration: float = 0.15

@export_group("Pol I")
## Shape/color, read by pol1.gd's _apply().
@export_range(0.1, 2.0) var pol1_lobe_size_ratio: float = 0.5   # relative to clamp_back_width — see polymerase_clamp.gd's "Polymerase Clamp" group
@export var pol1_lobe_gap: float = 24.0
@export_range(1.0, 2.0) var pol1_pulse_scale_ratio: float = 1.3
@export_range(0.0, 1.0) var pol1_chamfer_ratio: float = 0.35
@export_range(0.0, 1.0) var pol1_corner_radius_ratio: float = 0.6
@export_range(2, 8) var pol1_corner_segments: int = 4
@export var pol1_exo_color: Color = Color(0.75, 0.30, 0.30, 1.0)
@export var pol1_exo_pulse_color: Color = Color(0.95, 0.45, 0.45, 1.0)
@export var pol1_pol_color: Color = Color(0.30, 0.55, 0.75, 1.0)
@export var pol1_pol_pulse_color: Color = Color(0.45, 0.75, 0.95, 1.0)
@export var pol1_z: int = 5
@export var pol1_label_margin: float = 12.0
@export_range(0.1, 1.0) var pol1_pol_lobe_height_ratio: float = 0.5   # relative to the exo lobe's own height

## Motion timing, read by replication_manager.gd's POL I section.
@export var pol1_offstage_drop: float = 40.0
@export var pol1_travel_duration: float = 0.35
@export var pol1_leave_duration: float = 0.35

@export_group("RNA Primer")
## Ratio of okazaki_fragment_size, not a fixed slot count — scales if fragment
## size is tuned per-domain (see COMPLEXITY_MODEL.md's Okazaki fragment size
## note). 0.25 against the current default of 12 yields a clean 3-slot primer.
@export_range(0.05, 0.5) var primer_length_ratio: float = 0.25
@export var rna_base_color_a: Color = Color(0.85, 0.55, 0.85, 1.0)
@export var rna_base_color_u: Color = Color(0.55, 0.55, 0.9, 1.0)  # uracil, not thymine — RNA has no T
@export var rna_base_color_c: Color = Color(0.9, 0.7, 0.5, 1.0)
@export var rna_base_color_g: Color = Color(0.6, 0.85, 0.6, 1.0)
## Accessibility: RNA is distinguished from DNA by SHAPE and THICKNESS, not
## color alone — the primer segment's backbone reuses backbone_color, not
## its own hue. Values pushed for strong contrast, not a subtle nudge: a
## 16px vs 10px width step plus filled-vs-open on two same-colored green
## shapes proved genuinely unreadable even paused and zoomed in — this
## needs to look unmistakably like a different material at a glance, not
## a difference you have to go looking for.
## rna_backbone_line_width: the segment's own thickness (much thinner than
## backbone_line_width). rna_bond_mark_width: the chevron's own horizontal
## span — wider than bond_mark_width, so it reads as a distinctly wide open
## "V" rather than a smaller/fainter version of the DNA triangle.
## rna_bond_mark_line_width: the chevron's stroke thickness — needs to be
## thick enough to read as a real line, not a hairline that blends into
## the ribbon underneath.
@export var rna_backbone_line_width: float = 5.0
@export var rna_bond_mark_width: float = 22.0
@export var rna_bond_mark_line_width: float = 3.0
@export var rna_backbone_color: Color = Color(0.6, 0.25, 0.75, 1.0)  # matches primase_blip_color by default — tune independently
@export var rna_bond_mark_color: Color = Color(0.0, 0.0, 0.0, 1.0)
## RNA nitrogen bases' own label/font color — independent from
## base_label_color (DNA's), same reason the RNA fill colors above got their
## own a/u/c/g set instead of reusing base_color_a/t/c/g. Applied by whoever
## spawns/colors an RNA-shaped nitrogen_base.gd instance (rounded_square
## shape) and by PolymeraseHalo when its is_rna flag is set.
@export var rna_base_label_color: Color = Color(1.0, 1.0, 1.0, 1.0)


@export_group("Markers")
@export var marker_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var marker_font_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var marker_font_size: int = 14
@export var marker_font: Font = null
## Distance in pixels between the end markers and the terminal bases
## of their respective strands.
@export var marker_offset: float = 24.0

@export_group("Okazaki Fragments")
## Y offset below the backbone tip where 5'/3' markers appear on completed fragments.
@export var okazaki_marker_y_offset: float = 28.0

@export_group("Sequence Text")
## Used by get_sequence_rich_text() for the BBCode-colored base sequence display.
@export var sequence_text_synthesized_color: Color = Color(0.2980392, 0.6862745, 0.3137255, 1.0)   # was #4CAF50
@export var sequence_text_unsynthesized_color: Color = Color(1.0, 1.0, 1.0, 1.0)                    # was #FFFFFF
## SequenceLabel click/drag-to-scrub hover highlight (LongSequenceDesign.md
## Part 4) — moved here from local consts in replication_manager.gd so
## themes can vary the hover treatment too, same as every other color here.
@export var sequence_text_hover_bg_color: Color = Color(0.227, 0.373, 0.541, 1.0)     # was #3a5f8a
@export var sequence_text_hover_text_color: Color = Color(1.0, 1.0, 1.0, 1.0)          # was #ffffff

@export_group("Enzyme Labels")
@export var enzyme_labels_enabled: bool = true
@export var polymerase_label_margin: float = 16.0
@export var label_font_size: int = 16
@export var label_color: Color = Color(1, 1, 1, 1)
@export var label_panel_color: Color = Color(0, 0, 0, 0.5)
@export var label_z: int = 10

@export_group("Nucleotide Field & Halo")
## Ambient environmental field's opacity (nucleotide_field.gd) — moved here
## from that file's own local field_alpha export. Purely decorative
## background layer; kept dim by default.
@export_range(0.0, 1.0) var nucleotide_field_alpha: float = 0.05
## PolymeraseHalo's own opacity — previously read LIVE from the field above
## (polymerase_halo.gd's _current_field_alpha()), meaning both were forced
## to match. Decoupled into its own field so the functional capture pool can
## be tuned independently from the purely-decorative background field.
## Default matches the halo's own prior null-fallback constant (0.35),
## which was the closest thing to an "intended" halo-specific value already
## in the code before this pass.
@export_range(0.0, 1.0) var polymerase_halo_alpha: float = 0.35

@export_group("Zoom & Long-Sequence Display")
## Shared by zoom_manager.gd's level-1 windowed-mode threshold AND
## replication_manager.gd's SequenceLabel window width (LongSequenceDesign.md
## Part 3/4) — one number instead of two independently-tuned constants that
## used to just happen to agree (57), the same class of drift Part 1 fixed
## for the sequence-length ceiling.
@export var legible_reference_length: int = 57

## Level 1, short sequences: % of the ALONG-AXIS viewport extent the whole
## track fills. The track always runs along world x; along-axis is viewport
## WIDTH in horizontal mode and viewport HEIGHT in vertical mode — only which
## screen axis world x maps to changes. See VerticalModeDesign.md Part 1a.
@export_range(0.0, 1.0) var zoom_along_axis_percentage: float = 0.90
## Level 1, long sequences (windowed mode): % of the CROSS-AXIS viewport
## extent the fixed cross-axis content span below fills. NOT YET TUNED.
@export_range(0.0, 1.0) var zoom_cross_axis_fit_percentage: float = 0.70
## World-space extent ACROSS the track (both template strands + enzyme
## geometry — i.e. the world-y span) that windowed mode frames against.
## Perpendicular to the strand in both orientations. NOT YET TUNED.
@export var zoom_cross_axis_content_span: float = 400.0
## World-space padding around framed points at levels 2/3.
@export var zoom_level34_padding: float = 160.0
## Seconds for an animated level/target transition tween.
@export var zoom_level_transition_duration: float = 0.5
## Screen-space pan speed (px/sec) for arrow-key panning, divided by zoom
## each frame so it feels the same regardless of zoom level.
@export var zoom_pan_screen_speed: float = 400.0
## Seconds of pan inactivity before level-1 fit-to-height mode auto-releases
## back to the follow anchor. NOT YET TUNED.
@export var zoom_pan_release_inactivity_seconds: float = 3.0
## Duration of the tween back to center when panning releases (either via
## the inactivity timeout above, or the explicit recenter button).
@export var zoom_pan_release_tween_duration: float = 0.6

@export_subgroup("Enzyme Level 2/3 Fit")
## Multi-level zoom system — per-enzyme Level 2 ("regional context") / Level
## 3 ("exclusively focused") fit percentages. Previously local consts in
## simulation.gd (helicase) and replication_manager.gd (leading/lagging
## polymerase) — moved here so they're Inspector-editable, but each one
## stays its own independently-tuned value, exactly as tuned before. Not
## merged into a single shared number; helicase, leading, and lagging each
## keep their own fields, matching how leading/lagging's own Level 2 fits
## already diverged into two values (different framing MECHANISMS, not just
## different numbers — see _zoom_frame_leading_level2()/_zoom_frame_lagging_
## level2() in replication_manager.gd).
@export_range(0.0, 1.0) var zoom_helicase_level2_fit: float = 0.6
@export_range(0.0, 1.0) var zoom_helicase_level3_fit: float = 0.8
@export_range(0.0, 1.0) var zoom_leading_level2_fit: float = 0.35
@export_range(0.0, 1.0) var zoom_lagging_level2_fit: float = 0.35
## Shared by leading + lagging Level 3 only (same clamp geometry either way,
## unlike Level 2 which needed to split) — matches the original single
## POLYMERASE_LEVEL3_FIT constant exactly, not further split.
@export_range(0.0, 1.0) var zoom_polymerase_level3_fit: float = 0.6

@export_subgroup("Free Camera Mode")
## Max zoom-in ceiling for free-camera mode (mouse drag-pan + scroll-zoom,
## no target selected). There's no enzyme footprint to size against once no
## target is selected, so this is a flat number rather than a per-target
## Level 3 fit. NOT YET TUNED — placeholder pending real numbers in-engine.
##
## Raised 4.0 -> 8.0 (Growth Session 2 CQA follow-up, see
## docs/MolecularStructure_BasePairExpansion.md's culling note): this value
## also doubles as the ceiling molecule_structure_renderer.gd's per-molecule
## cull window narrows toward (cull window = viewport_size / zoom.x). At
## 4.0 the window stayed wide enough (~320px raw at a 1280px viewport) to
## keep 10+ nucleotides simultaneously in skeletal mode at once, each now
## carrying a full base + backbone + H-bond lines across up to 4 strands —
## a real perf drop. 8.0 narrows that to ~160px (~3 nucleotides), back in
## range of the "a handful" working-set assumption Q9's per-molecule-only
## culling decision was built on. Still empirically tunable, not final.
@export var zoom_free_camera_max_zoom_in: float = 8.0
## Multiplier applied per scroll-wheel tick, or per Zoom In/Out button press
## while already in free-camera mode (zoom *= this per step in, /= this per
## step out). NOT YET TUNED.
@export var zoom_free_camera_scroll_step: float = 1.15

@export_subgroup("Follow Mode")
## Zoom-out floor while following (double-click an enzyme). Deliberately its
## own raw tunable rather than reusing free camera's whole-track-fit floor —
## a follow shot should stay reasonably tight even at its most zoomed-out,
## not fall back to seeing the entire track. NOT YET TUNED — placeholder
## pending real numbers in-engine.
@export var zoom_follow_min_zoom: float = 1.5
## Seconds for the cubic-ease-out catch-up after a background pause/drag
## releases back into follow mode — see ZoomDesign.md's "critically-damped-
## spring clamp" note on follow speed. Deliberately short; this is closing a
## small hand-off gap, not a deliberate camera move like
## zoom_level_transition_duration. NOT YET TUNED.
@export var zoom_follow_resume_duration: float = 0.35

@export_group("Molecular Structure")
## Zoom scalar (free-camera zoom.x — CONFIRMED against zoom_manager.gd:
## zooming IN increases this value, zooming OUT decreases it toward a
## floor) crossed GOING UP that activates skeletal rendering. Must be
## strictly greater than molecular_zoom_exit_threshold — this is a
## hysteresis band, not a single toggle point, or scroll-wheel jitter at
## one shared threshold would flap the render mode every tick reversed.
## See MolecularStructure_OpenQuestions_RenderClusterResolution.md
## (question 4). NOT YET TUNED.
##
## Raised 3.0 -> 6.5 (Growth Session 2 CQA follow-up, see
## docs/MolecularStructure_BasePairExpansion.md's culling note): raising
## zoom_free_camera_max_zoom_in alone only narrowed the per-molecule cull
## window (viewport_size / zoom.x) once actually zoomed to near that
## ceiling — for most of the active range, the window was still sized by
## THIS threshold, which stayed wide enough (~427px at a 1280px viewport,
## ~8 nucleotides) to keep the same perf problem for anywhere but the
## extreme max zoom. At 6.5 the window is already ~197px (~3.6
## nucleotides) at the moment skeletal mode activates.
@export var molecular_zoom_enter_threshold: float = 6.5
## Zoom scalar crossed GOING DOWN that deactivates skeletal rendering.
## Strictly less than molecular_zoom_enter_threshold. Raised 2.2 -> 5.5
## alongside the enter threshold, keeping a comparable hysteresis gap.
## NOT YET TUNED.
@export var molecular_zoom_exit_threshold: float = 5.5
## World-space bond length for one ribose-ring edge, expressed as a
## fraction of nucleotide_slot_spacing (sim.gd) rather than a literal
## Ångström constant — relative bond-length ratios only, per
## MolecularStructureDesign.md Open Question 2's resolution (derived
## geometry, not real-world scale). Tuned (docs/MolecularStructure_
## BasePairExpansion.md): 0.35 (bond_length=18.9) put the H-bond anchor
## span at 36.96 with the purine ring's own widest extent (62.54) actually
## EXCEEDING nucleotide_slot_spacing (54.0) — confirmed cause of the
## screenshot-reported same-strand purine overlap. 0.287 (bond_length=15.5)
## was picked from a fine sweep (diagnosis/diag_retarget.py) as the point
## where the H-bond span first clears 2 full dash+gap cycles of
## molecular_h_bond_dash_length/gap_length (14.0 units) while the purine
## extent (51.29) still keeps a real, if thin (~5%), margin under
## nucleotide_slot_spacing — the two constraints trade off against each
## other across the whole sweep, so this is a balance point, not a value
## that clears both with room to spare.
@export var molecular_ring_bond_length_ratio: float = 0.287
## Line width for skeletal bonds, world units (scales with zoom like
## everything else drawn in world space). NOT YET TUNED.
@export var molecular_bond_width: float = 2.5
## Atom circle radius, world units. NOT YET TUNED.
@export var molecular_atom_radius: float = 6.0
## Font size (px) for skeletal atom element-symbol labels. Deliberately its
## OWN field, not a reuse of base_label_font_size — that value (14) is
## proportioned for the bead-glyph mode's base_radius (15 world units,
## ratio ~0.93). Reused directly against molecular_atom_radius (6.0), the
## ratio becomes ~2.33 — ~2.5x too large relative to its own atom circle,
## independent of zoom (both circle and label are magnified equally by the
## same camera transform, so this was a proportion bug, not a zoom-level
## one) — the root cause of the label/atom overlap CQA found. Default here
## (6) matches the bead-glyph mode's own ratio applied to this circle's
## actual radius. NOT YET TUNED — a reasoned starting point, not a final
## answer; residual overlap after this is the signal to tune
## molecular_atom_radius/molecular_ring_bond_length_ratio next.
@export var molecular_atom_label_font_size: int = 6
## Option C fix (docs/MolecularStructure_BasePairExpansion.md): number of
## points sampled along the actual template rail curve for an
## inter-residue bond whose straight-chord length exceeds
## nucleotide_slot_spacing (only possible on template_bottom/template_top,
## the only strands with a curve to bend around — leading/lagging use flat
## algebraic Y, never trigger this). A covalent phosphodiester bond does
## not stretch; drawing a curve-following polyline through the fork's
## steep bonded->unzipped transition is chemically honest where a straight
## chord was a rendering approximation, not a data problem. "A handful" —
## 5 segments. NOT YET TUNED.
@export var molecular_curve_sample_count: int = 6
## Fill color for skeletal bonds and any atom with no per-element color
## defined below (the element color table itself lives in
## molecule_structure_renderer.gd, matching simulation.gd's
## _get_base_fill() pattern rather than duplicating a color table here).
@export var molecular_bond_color: Color = Color(0.6, 0.6, 0.65)
## World-space padding added to a nucleotide's derived ring/substituent
## extent when building its per-molecule culling bounding box. NOT YET
## TUNED.
@export var molecular_cull_bbox_padding: float = 20.0
## Growth Session 2 (base-pair expansion): CPK color for nitrogen atoms —
## carbon/oxygen/phosphorus already have dedicated cases in
## molecule_structure_renderer.gd's _element_color(); nitrogen previously
## fell through to molecular_bond_color, which stopped being distinct once
## real base topology (with several N atoms per residue) started rendering.
## Standard CPK convention: blue. NOT YET TUNED.
@export var molecular_nitrogen_color: Color = Color(0.25, 0.35, 0.95)
## Growth Session 2: additional cull-bbox padding accounting for a base
## pair's real extent now spanning BOTH strands (the hydrogen-bond span),
## not just one ribose ring. Sized off the same live gap
## _update_hydrogen_bond_height() already reads (dna_ribbons_gap), not an
## independently-tuned constant — see
## docs/MolecularStructure_BasePairExpansion.md's culling note. NOT YET
## TUNED (defaults to sim.dna_ribbons_gap at the renderer call site if left
## at 0.0).
@export var molecular_pair_span_padding: float = 0.0
## Dot radius for the dotted hydrogen-bond lines drawn between paired
## bases' named pairing-anchor atoms (Tier 2 per the addendum doc — one
## anchor atom per base, existing AT=2/CG=3 line count reused from
## replication_manager.gd, not recomputed). Was rendered as dashes
## (draw_line segments) through Growth Session 2 despite this field
## already being named/commented as "dotted" — switched to actual dots
## (docs/MolecularStructure_BasePairExpansion.md) once the ratio-shrink
## fix (Bug H) pushed the real post-fork H-bond span down near a single
## dash+gap cycle, where a dashed line reads as one short blur; dots don't
## have that failure mode since each one is a fixed-size mark regardless
## of how many fit along the span. Center-to-center pitch (2*radius + gap)
## kept equal to the old dash+gap total (7.0) so this rename doesn't
## silently change the constraint used when tuning molecular_ring_bond_
## length_ratio. NOT YET TUNED beyond that.
@export var molecular_h_bond_dot_radius: float = 2.0
## Gap between dots (edge to edge) for the same hydrogen-bond lines.
## NOT YET TUNED beyond preserving the old dash+gap pitch — see
## molecular_h_bond_dot_radius's comment.
@export var molecular_h_bond_dot_gap: float = 3.0

## Extra vertical separation (Bug I decoupling, docs/MolecularStructure_
## BasePairExpansion.md), added ONLY inside the molecular renderer's own
## row placement — never touches sim.dna_ribbons_gap, the value shared
## with the normal-zoom bead-glyph ribbon spacing and several other
## systems (polymerase clamp, ligase drop, etc.). Confirmed empirically
## (live F9 dumps + live screenshots): raising sim.dna_ribbons_gap to 100
## gave every base ring comfortable clearance from its paired partner's
## ring (~85 was still short; base rings up to 46.4 in diameter need real
## room), i.e. 100-60 = 40 as a starting point for this same fix applied
## only to this renderer's own per-strand offset
## (molecule_structure_renderer.gd's MOLECULAR_ROW_PUSH table). Live-tuned
## up from there to 80 for full legibility at atom zoom (every ring/base/
## H-bond distinguishable, not just non-overlapping) — the bead-glyph
## ribbon gap stays at its own tuned value (60) throughout, unaffected.
@export var molecular_extra_ribbons_gap: float = 80.0

## Convenience lookup: pass a base type string to get its fill color.
func get_base_color(base_type: String) -> Color:
	match base_type:
		"A": return base_color_a
		"T": return base_color_t
		"C": return base_color_c
		"G": return base_color_g
	return Color.GRAY