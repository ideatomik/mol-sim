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
## Shared by zoom_manager.gd's level-1 fit-to-height threshold AND
## replication_manager.gd's SequenceLabel window width (LongSequenceDesign.md
## Part 3/4) — one number instead of two independently-tuned constants that
## used to just happen to agree (57), the same class of drift Part 1 fixed
## for the sequence-length ceiling.
@export var legible_reference_length: int = 57

## Level 1, short sequences: % of viewport width the whole track fills.
@export_range(0.0, 1.0) var zoom_strand_width_percentage: float = 0.90
## Level 1, long sequences (fit-to-height mode): % of viewport height the
## fixed vertical content span fills. NOT YET TUNED.
@export_range(0.0, 1.0) var zoom_height_fit_percentage: float = 0.70
## World-space vertical extent (both template strands + enzyme geometry)
## fit-to-height frames against. NOT YET TUNED.
@export var zoom_vertical_content_span: float = 400.0
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
@export var zoom_free_camera_max_zoom_in: float = 4.0
## Multiplier applied per scroll-wheel tick, or per Zoom In/Out button press
## while already in free-camera mode (zoom *= this per step in, /= this per
## step out). NOT YET TUNED.
@export var zoom_free_camera_scroll_step: float = 1.15

## Convenience lookup: pass a base type string to get its fill color.
func get_base_color(base_type: String) -> Color:
	match base_type:
		"A": return base_color_a
		"T": return base_color_t
		"C": return base_color_c
		"G": return base_color_g
	return Color.GRAY