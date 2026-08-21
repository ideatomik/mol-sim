# Data Flow & Relationships


### Initialization Flow

```
User opens simulation
    ↓
ComplexitySetupPopup.show_dialog(true)
    ↓
User confirms complexity settings
    ↓
_on_startup_complexity_confirmed()
    ↓
SequenceLoaderPopup.show_dialog(true)
    ↓
User selects/enters sequence
    ↓
sequence_loaded signal fires
    ↓
simulation.initialize_simulation(dna_sequence_string)
    ↓
1. teardown_simulation() — clean old state
2. dna_sequence.from_string(seq) — parse sequence
3. _setup_template_strand() — create PathFollow2D slots
4. _setup_helicase() — instantiate helicase_mgr
5. _setup_replication_manager() — instantiate replication_mgr
6. replication_mgr.connect_helicase(helicase_mgr)
7. emit simulation_initialized
    ↓
PlayerUI._on_simulation_initialized()
    ↓
Scrubber.max_value = get_max_scrub_index()
Playback ready
```

### Playback Loop

```
_user presses Play_
    ↓
player_ui._on_play_pause_pressed()
    ↓
helicase_mgr.resume()
replication_mgr.manual_override = false
    ↓
_PROCESS LOOP (every frame):
    ↓
helicase_mgr._process(delta):
    - step_t += delta / step_duration
    - if step_t >= 1.0: current_slot_index++, emit slot_reached
    ↓
simulation._process(delta):
    - helicase_x = lerp(prev_x, curr_x, step_t)
    - polymerase_x = helicase_x - offset
    - apply_zoom_highlight()
    ↓
replication_mgr.update(delta, ctx):
    - _leading_update(): check proximity, fire bases
    - _lagging_update(): check fragment timing, fire slots
    - _primase_update(): place RNA primers
    - _pol1_update(): remove primers, fill DNA
    - _ligase_update(): seal nicks
    ↓
replication_mgr.render(ctx):
    - _leading_render(): draw backbone line
    - _lagging_render(): draw fragment backbones
    ↓
Visual update complete
```

### Scrubbing Flow

```
_user drags scrubber_
    ↓
player_ui._on_scrubber_value_changed(value)
    ↓
simulation.manual_override = true
helicase_mgr.pause()
    ↓
scrub_index = floor(value)
    ↓
replication_mgr.scrub_rebuild(ctx):
    1. reset() — clear all synthesis arrays
    2. Determine phase from scrub_index:
       - Index < num_slots: SWEEPING phase
       - Index < catchup_end: Lagging catchup
       - Index < settle_end: Enzyme settle
    3. Rebuild leading strand up to scrub_index
    4. Rebuild lagging fragments fully completed before scrub_index
    5. Hide enzymes mid-travel (show only finished states)
    ↓
helicase_mgr.current_slot_index = scrub_index
helicase_mgr.step_t = 0.0
    ↓
Visual rebuild complete (frozen at scrub position)
```

### Complexity Cascade

```
User enables "Pol I" checkbox
    ↓
complexity_manager.set_pol1_enabled(true)
    ↓
Cascade logic:
    - set_primase_enabled(true)  // Pol I needs primers
    - set_ligase_enabled(true)   // Pol I leaves nicks
    - pol1_enabled = true
    ↓
emit toggle_changed("primase", true)
emit toggle_changed("ligase", true)
emit toggle_changed("pol1", true)
    ↓
ComplexitySetupPopup updates checkboxes
    ↓
replication_mgr uses complexity_mgr.is_enabled("pol1"):
    - Primase blip spawns per fragment
    - Pol I travels behind Pol III
    - Ligase seals after Pol I completes
```

---

