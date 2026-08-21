# Core Architecture & Manager Hierarchy


### Architectural Principles

1. **Modular Complexity**: Every feature is toggle-aware from the start
2. **Single Source of Truth**: Each property has exactly one writer
3. **Manager Pattern**: Subsystems are encapsulated in manager nodes
4. **Event-Driven**: Signals coordinate cross-script communication
5. **Helicase-Anchored Positioning**: Replisome positioning derives from helicase state

### Manager Hierarchy

```
simulation.gd (Root Coordinator)
├── helicase_mgr (helicase.gd)
├── replication_mgr (replication_manager.gd)
│   ├── leading_polymerase
│   ├── lagging_polymerase
│   ├── leading_clamp / lagging_clamp
│   ├── primase_blip
│   ├── pol1
│   └── ligase
├── %ZoomManager (zoom_manager.gd)
├── %ThemeManager (theme_manager.gd)
├── %LocaleManager (locale_manager.gd)
├── %ComplexityManager (complexity_manager.gd)
└── %CursorAffordanceManager (cursor_affordance_manager.gd)
```

---

