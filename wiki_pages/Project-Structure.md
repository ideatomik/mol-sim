# Project Structure & File Organization


```
Zymulador/
├── scenes/                     # Godot scene files (.tscn)
│   ├── simulation.tscn         # Main simulation scene
│   ├── PlayerUI.tscn           # Horizontal playback controls
│   ├── VerticalPlayerUI.tscn   # Vertical playback controls
│   ├── ComplexitySetupPopup.tscn
│   ├── SequenceLoaderPopup.tscn
│   └── enzyme_label.tscn
├── scripts/
│   ├── simulation.gd           # Main coordinator (template manager)
│   ├── core/                   # Core systems
│   │   ├── nitrogen_base.gd
│   │   ├── ribose_deriver.gd
│   │   ├── molecule_fold_engine.gd
│   │   ├── molecule_topology.gd
│   │   └── reaction_operator.gd
│   ├── replication/            # Enzyme logic
│   │   ├── helicase.gd
│   │   ├── helicase_ring.gd
│   │   ├── helicase_atp_cycle.gd
│   │   ├── replication_manager.gd
│   │   ├── polymerase_clamp.gd
│   │   ├── polymerase_halo.gd
│   │   ├── polymerase_shape.gd
│   │   ├── primase_blip.gd
│   │   ├── pol1.gd
│   │   ├── ligase.gd
│   │   ├── ligase_cofactor.gd
│   │   └── dna_sequence_resource.gd
│   ├── ui/                     # UI controllers
│   │   ├── player_ui.gd
│   │   ├── complexity_manager.gd
│   │   ├── complexity_setup_popup.gd
│   │   ├── sequence_loader_popup.gd
│   │   ├── zoom_manager.gd
│   │   ├── camera_regent.gd
│   │   ├── theme_manager.gd
│   │   ├── locale_manager.gd
│   │   └── cursor_affordance_manager.gd
│   └── rendering/              # Visual rendering
│       ├── molecule_structure_renderer.gd
│       ├── procedural_shape_utils.gd
│       └── pair_capsule_overlay.gd
├── docs/                       # Documentation
├── localization/               # Translation files
└── resources/                  # Shared resources
```

---

