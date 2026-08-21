# Key Parameters & Configuration


### Simulation Exports (simulation.gd)

| Parameter | Type | Default | Purpose |
|-----------|------|---------|---------|
| `nucleotide_slot_spacing` | float | 54.0 | Pixels between adjacent nucleotides |
| `num_nucleotide_slots` | int | 30 | Default sequence length |
| `center_y` | float | 360.0 | Screen-center Y anchor |
| `polymerase_y_offset` | float | 120.0 | Vertical distance from center to polymerases |
| `dna_ribbons_gap` | float | 90.0 | Gap between template strands |
| `polymerase_x_offset_slots` | float | 4.0 | Slots between helicase and polymerase |
| `okazaki_fragment_size` | int | 12 | Slots per Okazaki fragment |
| `telomere_primer_footprint` | int | 2 | Terminal gap size (end-replication problem) |
| `fade_duration` | float | 0.6 | Enzyme fade animation duration |
| `settling_duration` | float | 0.5 | Post-replication settling time |
| `wobble_amplitude` | float | 2.0 | Thermal motion amplitude |
| `wobble_speed` | float | 1.5 | Thermal motion frequency |
| `lagging_gap_enabled` | bool | false | Show telomere gap (Linear mode) |
| `ligase_enabled` | bool | false | Show nicks between fragments |

### Helicase Exports (helicase.gd)

| Parameter | Type | Default | Purpose |
|-----------|------|---------|---------|
| `base_step_duration` | float | 0.5 | Seconds per slot at 1x speed |
| `settling_duration` | float | 0.5 | Settling phase duration |

### Speed Options

```gdscript
const SPEED_OPTIONS = [1, 2, 4, 8]  # Multiplier options in dropdown
const SPEED_VALUES = [1/16, 1/8, 1/4, 0.5, 1, 1.5, 2, 4, 8, 16]  # Fine-grained ladder
```

### Complexity Toggles (complexity_manager.gd)

| Feature | Tier | Status | Description |
|---------|------|--------|-------------|
| `primase_enabled` | Light | ✅ Implemented | RNA primers per Okazaki fragment |
| `pol1_enabled` | Complex | ✅ Implemented | Pol I removes primers, fills DNA |
| `ligase_enabled` | Light/Complex | ✅ Implemented | Ligase seals nicks (Light: gated by Pol III; Complex: gated by Pol I) |
| `trombone_loop_enabled` | Trombone | ❌ Planned | Tau body couples polymerases (TromboneLoopDesign.md) |
| `cofactor_activation_enabled` | Cross-cutting | ⚠️ Partial | Show ATP/NAD+ cofactors (helicase_atp_cycle.gd, ligase_cofactor.gd implemented) |
| `topology_mode` | Mode-gate | ✅ Implemented | CIRCULAR (default) or LINEAR — gates Tus-Ter vs. telomere gap |
| `ssb_enabled` | Stage 2 elongation | ❌ Planned | SSB/shelterin coating ssDNA (COMPLEXITY_MODEL.md) |

### Phase Enum (helicase.gd)

```gdscript
enum Phase {
    INTRO,              # Initial positioning (animated)
    SWEEPING,           # Active replication (slot 0 → last_slot)
    FINISHING_LAST_PULSE,  # Escort walk (invisible sprite)
    SETTLING,           # Post-replication settling
    DONE                # Simulation complete
}
```

---

