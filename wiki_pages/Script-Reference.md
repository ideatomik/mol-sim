# Script Reference


### Core Scripts

#### `simulation.gd` — Main Coordinator
**Purpose**: Template manager and visual coordinator. Owns template strand geometry, wobble animation, and zoom highlighting.

**Key Variables**:
- `dna_sequence`: DnaSequenceResource — current DNA sequence
- `helicase_mgr`: Helicase instance
- `replication_mgr`: ReplicationManager instance
- `num_nucleotide_slots`: Total slots in simulation
- `okazaki_fragment_size`: Slots per Okazaki fragment
- `lagging_gap_enabled`: Show end-replication problem gap
- `ligase_enabled`: Show nicks between fragments

**Key Functions**:
- `initialize_simulation(sequence_string)`: Set up simulation with DNA sequence
- `teardown_simulation()`: Clean up all dynamic nodes
- `_process(delta)`: Update wobble, zoom highlights
- `set_player_ui_visible(visible)`: Toggle UI panel
- `set_enzyme_labels_enabled(enabled)`: Toggle enzyme labels

**Signals**:
- `progress_changed(new_progress)`: Simulation progress (0.0-1.0)
- `simulation_initialized(total_bases)`: Ready after initialization
- `drag_scrub_requested(index)`: User dragging timeline
- `player_ui_visibility_changed(visible)`: UI panel toggled
- `enzyme_labels_visibility_changed(enabled)`: Labels toggled

---

#### `helicase.gd` — Replication Fork Engine
**Purpose**: Owns replication phase state machine and slot-by-slot stepping logic.

**Key Variables**:
- `current_slot_index`: Current position (0 to num_slots-1)
- `step_t`: Progress through current inter-slot step (0.0-1.0)
- `phase`: INTRO, SWEEPING, FINISHING_LAST_PULSE, SETTLING, DONE
- `speed_multiplier`: Playback speed (1x, 2x, 4x, 8x)
- `base_step_duration`: Seconds per slot at 1x speed

**Key Functions**:
- `initialize(slot_count, settling_duration)`: Setup
- `_process(delta)`: State machine stepping
- `start_intro()`, `finish_intro()`: Animation control
- `pause()`, `resume()`: Playback control
- `start_finishing(remaining_leading_slots)`: Escort walk setup

**Signals**:
- `slot_reached(index)`: Fired when helicase arrives at new slot
- `phase_changed(new_phase)`: Fired on phase transitions
- `sprite_should_fade`: Fired at SWEEPING→FINISHING_LAST_PULSE

---

#### `replication_manager.gd` — Synthesis Coordinator
**Purpose**: Owns all synthesis state, spawning, rendering, and enzyme animation for both strands.

**Key Variables**:
- `leading_synthesized_bases[]`: Bases synthesized on leading strand
- `lagging_fragments[]`: Completed Okazaki fragments
- `lagging_current_fragment`: Fragment in progress
- `leading_polymerase`, `lagging_polymerase`: Visual nodes
- `primase_blip`, `pol1`, `ligase`: Enzyme instances
- `leading_faded`, `lagging_polymerase_faded`, `pol1_faded`, `ligase_faded`: Fade states

**Key Functions**:
- `initialize(sim_node, tm, zoom_mgr)`: Setup with parent references
- `reset()`: Clear synthesis state (keep enzymes)
- `update(delta, ctx)`: Per-frame update
- `render(ctx)`: Render synthesis visuals
- `scrub_rebuild(ctx)`: Rebuild state for scrub position
- `connect_helicase(helicase_mgr)`: Wire helicase signals

**Leading Strand Section** (`_leading_*`):
- `_leading_reset()`: Clear leading arrays
- `_leading_fire_step(slot)`: Spawn base at slot
- `_leading_render()`: Draw backbone line

**Lagging Strand Section** (`_lagging_*`):
- `_lagging_reset()`: Clear fragments array
- `_lagging_fire_step()`: Fire next slot in current fragment
- `_lagging_start_catchup()`: Post-helicase completion
- `_lagging_render()`: Draw fragment backbones

**Capture Section** (`_capture_*`):
- `_capture_on_leading_slot_reached(slot)`: Event-driven spawn trigger
- `_capture_begin_lagging(slot)`: Start capture animation
- `_capture_finish_lagging(slot)`: Complete base placement

---

### UI Scripts

#### `player_ui.gd` — Transport Controls
**Purpose**: Playback controls (play/pause, step, scrub, speed).

**Key Variables**:
- `simulation`: Parent simulation node
- `zoom_mgr`: Camera2D reference
- `_is_dragging`: Scrubber drag state
- `_hover_index`: Sequence label hover position

**Key Functions**:
- `_ready()`: Connect signals, initialize speed ladder
- `_input(event)`: Keyboard shortcuts (Space, ., ,, F2, F3)
- `_on_play_pause_pressed()`: Toggle playback
- `_on_scrubber_value_changed(value)`: Scrub to position
- `set_speed(multiplier)`: Apply speed to helicase

---

#### `complexity_manager.gd` — Feature Toggles
**Purpose**: Owns feature toggles with cascade logic. Implements three cascade patterns: parent/child (Pol I enables primase+ligase), bridge-toggle (primase/ligase independently enable their own pieces when Pol I is off), and mode-gate (topology gates end-game modules).

**Key Variables**:
- `topology_mode`: CIRCULAR or LINEAR (mode-gate, gates Tus-Ter vs. telomere gap)
- `primase_enabled`, `pol1_enabled`, `ligase_enabled`: Okazaki maturation tiers
- `trombone_loop_enabled`: Replisome coupling tier (NOT YET IMPLEMENTED — planned in TromboneLoopDesign.md)
- `cofactor_activation_enabled`: ATP/NAD+ visualization lens
- `ssb_enabled`: SSB/shelterin toggle (NOT YET IMPLEMENTED — planned in COMPLEXITY_MODEL.md)

**Key Functions**:
- `is_enabled(feature_name)`: Check if feature is active
- `set_primase_enabled(value)`: Toggle with Pol I cascade
- `set_ligase_enabled(value)`: Toggle with Pol I cascade
- `set_pol1_enabled(value)`: Bridge toggle (enables primase+ligase)
- `set_topology_mode(value)`: Switch CIRCULAR/LINEAR, triggers `topology_changed` signal
- `ligase_uses_nad()`: Bacterial vs eukaryotic mode (NAD+ for bacterial ligase, ATP for eukaryotic)

**Signals**:
- `toggle_changed(feature, enabled)`: Any toggle changed
- `topology_changed(mode)`: Topology switched (gates which end-game modules are coherent)

**Cascade Patterns** (see [Complexity Cascade Flowchart](#5-complexity-toggle-dependencies)):
1. **Parent/Child**: Pol I → Primase + Ligase (enabling Pol I auto-enables both)
2. **Bridge-toggle**: Primase or Ligase can be enabled independently when Pol I is OFF (Light tier)
3. **Mode-gate**: Topology (CIRCULAR/LINEAR) gates mutually-exclusive end-game modules (Tus-Ter vs. telomere gap)

---

#### `zoom_manager.gd` — Camera System
**Purpose**: Manages camera zoom levels, highlight/dim system, and vertical mode.

**Key Variables**:
- `vertical_mode`: Portrait layout for mobile/recording
- `current_zoom_level`: 0 (overview), 1, 2, 3 (deep zoom)
- `highlighted_target`: Currently focused enzyme/strand

**Key Functions**:
- `register_target(name, frame_providers, label_key, visible_check)`: Register zoom target
- `zoom_in()`, `zoom_out()`: Navigate zoom levels
- `get_enzyme_highlight_dim(target)`: Get dim factor for enzyme
- `get_strand_highlight_dim()`: Get dim factor for strands
- `get_along_extent()`, `get_cross_extent()`: Viewport dimensions

---

### Rendering Scripts

#### `molecule_structure_renderer.gd` — Deep Zoom Renderer
**Purpose**: Skeletal ribose/nitrogen base renderer for deep zoom levels.

**Key Variables**:
- `template_source`: simulation.gd reference
- `active_beads[]`: Currently rendered atoms

**Key Functions**:
- `set_template_source(source)`: Wire to simulation
- `_process(delta)`: Per-frame atom rendering
- `is_slot_active(slot)`: Check if slot has molecular detail

---

#### `procedural_shape_utils.gd` — Shape Generation
**Purpose**: Shared utilities for procedural blob/shape generation.

**Key Functions**:
- `create_procedural_blob(points, resolution, amplitude)`: Generate organic shapes
- `create_helix_axis(points, radius, pitch)`: Generate helix path

---

### Core Molecular Scripts

#### `nitrogen_base.gd` — Base Geometry
**Purpose**: Nitrogen base (A, T, C, G) scene controller.

**Key Variables**:
- `base_type`: "A", "T", "C", or "G"
- `complement`: Complementary base type
- `hydrogen_bonds`: Number of bonds (2 for A-T, 3 for C-G)

---

#### `ribose_deriver.gd` — Sugar Ring Generator
**Purpose**: Compute ribose/deoxyribose ring geometry.

**Key Functions**:
- `derive_ring_positions(base_position, orientation)`: Calculate ring vertices
- `get_phosphate_attachment_point()`: Where phosphate connects

---

