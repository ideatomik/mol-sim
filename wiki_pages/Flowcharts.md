# Flowcharts & Diagrams


### 1. Overall System Architecture

```mermaid
graph TB
    subgraph "Main Scene (simulation.tscn)"
        Sim[simulation.gd<br/>Template Manager]
        HelicaseMgr[helicase.gd<br/>Phase State Machine]
        ReplMgr[replication_manager.gd<br/>Synthesis Coordinator]
    end
    
    subgraph "UI Layer"
        PlayerUI[player_ui.gd<br/>Transport Controls]
        ComplexityMgr[complexity_manager.gd<br/>Feature Toggles]
        ZoomMgr[zoom_manager.gd<br/>Camera System]
        ThemeMgr[theme_manager.gd<br/>Visual Constants]
        LocaleMgr[locale_manager.gd<br/>Localization]
    end
    
    subgraph "Enzymes (children of ReplMgr)"
        LeadingPoly[Leading Polymerase]
        LaggingPoly[Lagging Polymerase]
        Primase[primase_blip.gd]
        Pol1[pol1.gd]
        Ligase[ligase.gd]
    end
    
    subgraph "Rendering"
        MolRenderer[molecule_structure_renderer.gd]
        ProcUtils[procedural_shape_utils.gd]
    end
    
    PlayerUI -->|signals| Sim
    Sim -->|instantiates| HelicaseMgr
    Sim -->|instantiates| ReplMgr
    HelicaseMgr -->|slot_reached| ReplMgr
    ReplMgr -->|manages| LeadingPoly
    ReplMgr -->|manages| LaggingPoly
    ReplMgr -->|manages| Primase
    ReplMgr -->|manages| Pol1
    ReplMgr -->|manages| Ligase
    ComplexityMgr -->|is_enabled| ReplMgr
    ZoomMgr -->|highlight_dim| Sim
    ZoomMgr -->|highlight_dim| ReplMgr
    ThemeMgr -->|colors| Sim
    ThemeMgr -->|colors| ReplMgr
    MolRenderer -->|template_source| Sim
```

### 2. Helicase Phase State Machine

```mermaid
stateDiagram-v2
    [*] --> INTRO: start_intro()
    INTRO --> SWEEPING: finish_intro()
    SWEEPING --> FINISHING_LAST_PULSE: current_slot >= last_slot
    FINISHING_LAST_PULSE --> SETTLING: extra_steps_done >= extra_steps_total
    SETTLING --> DONE: settling_t >= settling_duration
    DONE --> [*]: is_running = false
    
    note right of FINISHING_LAST_PULSE
        Sprite fades here
        (sprite_should_fade)
        State machine continues
        escorting leading polymerase
    end note
    
    SWEEPING --> SWEEPING: slot_reached(index)
    FINISHING_LAST_PULSE --> FINISHING_LAST_PULSE: slot_reached(index)
```

### 3. Lagging Strand Okazaki Fragment Lifecycle

```mermaid
sequenceDiagram
    participant H as Helicase
    participant RM as ReplicationManager
    participant P as Primase
    participant LP as Lagging Polymerase
    participant Pol1 as Pol I
    participant L as Ligase
    
    H->>RM: slot_reached(start_delay + n*fragment_size)
    RM->>P: _primase_kick(fragment_start)
    P-->>RM: RNA primer placed (3 bases)
    
    loop For each slot in fragment (right-to-left)
        H->>RM: slot_reached(index)
        RM->>LP: _lagging_fire_step()
        LP-->>RM: Base spawned, captured
    end
    
    RM->>RM: _lagging_close_fragment()
    alt ligase_enabled
        RM->>L: _ligase_kick(gap_slot)
    end
    
    alt pol1_enabled
        RM->>Pol1: _pol1_kick(primer_start)
        Pol1-->>RM: Primer removed, DNA filled
        RM->>L: _ligase_kick(gap_slot)
        L-->>RM: Nick sealed
    end
```

### 4. Independent End-of-Run Fade Cascade

```mermaid
graph LR
    A[Helicase reaches<br/>last_slot_index] --> B[Phase:<br/>FINISHING_LAST_PULSE]
    B --> C[emit sprite_should_fade]
    C --> D[Helicase sprite fades]
    
    D --> E[Helicase takes<br/>extra_steps_total<br/>invisible steps]
    E --> F[Leading polymerase<br/>reaches true end]
    F --> G[Leading polymerase fades]
    
    H[Lagging catchup<br/>completes] --> I[_lagging_finish_pending<br/>armed]
    I --> J{Position tween<br/>AND capture<br/>both finished?}
    J -->|No| K[Wait in update()]
    K --> J
    J -->|Yes| L[Lagging polymerase fades]
    
    M[Pol I queue drains] --> N[Pol I fades]
    O[Ligase queue drains] --> P[Ligase fades]
    
    G & L & N & P --> Q[All enzymes faded]
    Q --> R[scene_fully_faded = true]
    R --> S[is_fully_complete() returns true]
```

### 5. Complexity Toggle Dependencies

```mermaid
graph TB
    subgraph "Base Tier (Always On)"
        Leading[Leading Strand]
        Lagging[Lagging Strand<br/>Okazaki Fragments]
    end
    
    subgraph "Light Tier"
        Primase[Primase<br/>RNA Primers]
    end
    
    subgraph "Complex Tier"
        Pol1[Pol I<br/>Primer Removal]
        Ligase[Ligase<br/>Nick Sealing]
    end
    
    subgraph "Trombone Tier"
        Trombone[Trombone Loop<br/>Tau Body Coupling]
    end
    
    subgraph "Telomerase Tier"
        Telomere[End-Replication Gap<br/>Telomerase Extension]
    end
    
    Lagging --> Primase
    Primase --> Pol1
    Pol1 --> Ligase
    Lagging --> Trombone
    Telomere -.->|LINEAR mode only| Lagging
    
    style Primase fill:#ff9
    style Pol1 fill:#fc9
    style Ligase fill:#fc9
    style Trombone fill:#c9f
    style Telomere fill:#f9c
```

### 6. Zoom Level Hierarchy

```mermaid
graph TD
    L0[Level 0: Overview<br/>Full sequence visible] -->|zoom in| L1
    L0 -->|zoom out| L0
    
    L1[Level 1: Regional<br/>~10-15 bases] -->|zoom in| L2
    L1 -->|zoom out| L0
    
    L2[Level 2: Enzyme Detail<br/>Single enzyme + context] -->|zoom in| L3
    L2 -->|zoom out| L1
    
    L3[Level 3: Molecular<br/>Individual atoms/bonds] -->|zoom out| L2
    
    L2 -->|targets| Helicase[Helicase Ring]
    L2 -->|targets| LeadingPoly[Leading Polymerase]
    L2 -->|targets| LaggingPoly[Lagging Polymerase]
    
    L3 -->|renders| MolRenderer[Molecular Structure Renderer<br/>Ribose rings, nitrogen bases]
```

### 7. Signal Communication Map

```mermaid
graph TB
    subgraph "Helicase Signals"
        H1[slot_reached index]
        H2[phase_changed new_phase]
        H3[sprite_should_fade]
    end
    
    subgraph "Simulation Signals"
        S1[progress_changed value]
        S2[simulation_initialized total_bases]
        S3[drag_scrub_requested index]
        S4[player_ui_visibility_changed visible]
        S5[enzyme_labels_visibility_changed enabled]
    end
    
    subgraph "Complexity Signals"
        C1[toggle_changed feature, enabled]
        C2[topology_changed mode]
    end
    
    subgraph "Receivers"
        RM[ReplicationManager]
        PU[PlayerUI]
        CSP[ComplexitySetupPopup]
        EL[EnzymeLabel instances]
    end
    
    H1 --> RM
    H2 --> RM
    H3 --> RM
    S1 --> PU
    S2 --> PU
    S3 --> PU
    S4 --> PU
    S5 --> EL
    C1 --> CSP
    C2 --> CSP
```

---

