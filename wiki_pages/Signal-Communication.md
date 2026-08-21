# Signal Communication Map


### Signal Producers

| Script | Signal | Parameters | Consumers |
|--------|--------|------------|-----------|
| `helicase.gd` | `slot_reached` | `index: int` | `replication_manager.gd` |
| `helicase.gd` | `phase_changed` | `new_phase: int` | `replication_manager.gd` |
| `helicase.gd` | `sprite_should_fade` | _(none)_ | `replication_manager.gd` |
| `simulation.gd` | `progress_changed` | `new_progress: float` | `player_ui.gd` |
| `simulation.gd` | `simulation_initialized` | `total_bases: int` | `player_ui.gd` |
| `simulation.gd` | `drag_scrub_requested` | `index: int` | `player_ui.gd` |
| `simulation.gd` | `player_ui_visibility_changed` | `visible: bool` | `player_ui.gd`, `camera_regent.gd` |
| `simulation.gd` | `enzyme_labels_visibility_changed` | `enabled: bool` | `enzyme_label.gd` instances |
| `complexity_manager.gd` | `toggle_changed` | `feature: String, enabled: bool` | `complexity_setup_popup.gd` |
| `complexity_manager.gd` | `topology_changed` | `mode: int` | `complexity_setup_popup.gd` |

### Signal Connection Pattern

```gdscript
# In replication_manager.gd's connect_helicase():
func connect_helicase(helicase_mgr: Node) -> void:
    connected_helicase_mgr = helicase_mgr
    helicase_mgr.slot_reached.connect(_on_helicase_slot_reached)
    helicase_mgr.phase_changed.connect(_on_helicase_phase_changed)
    
# In player_ui.gd's _ready():
func _ready():
    if simulation != null:
        simulation.simulation_initialized.connect(_on_simulation_initialized)
        simulation.progress_changed.connect(_on_progress_changed)
        simulation.drag_scrub_requested.connect(_on_drag_scrub_requested)
```

---

