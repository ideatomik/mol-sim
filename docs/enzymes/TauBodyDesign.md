# Tau Body Design — E. coli Replisome Coupling
_Design document for the tau body (`tau_body.gd`), the physical coupling point
between helicase and lagging polymerase in the E. coli trombone-loop replisome
model. Companion to COMPLEXITY_MODEL.md's `trombone_loop` toggle registry entry,
HelicaseDesign.md's ring animation pattern, and PolymeraseDesign.md's clamp
architecture. Implements the structural core that makes the trombone loop
geometrically coherent._

---

## Biological Context

In _E. coli_, the replicative polymerase (Pol III) exists as a **tau homodimer**
(τ₂) that physically links multiple components of the replisome:

- **Two Pol III core enzymes** (one for leading, one for lagging strand)
- **DnaB helicase** (the hexameric ring that unwinds DNA)
- **DnaG primase** (transiently associates for primer synthesis on lagging strand)

This physical coupling is what creates the famous **"trombone loop"** geometry:
the lagging strand template must loop back on itself so that both polymerases
can move in the same physical direction (with the helicase) even though they
are synthesizing DNA in opposite directions relative to the template strands.

The tau body is the **structural hub** that makes this possible — it is not
itself catalytic, but it is the scaffold that holds the catalytic components
in the correct spatial relationship.

---

## Visual Concept

The tau body is rendered as a **small procedural shape** positioned between
the helicase ring and the lagging polymerase clamp, visually representing the
tau dimer's role as a connector. Unlike the helicase (rotating ring) or
polymerase (two-piece clamp with pump animation), the tau body has **no
intrinsic animation** — its motion is entirely derived from the helicase
position, with the lagging polymerase attached to it.

### Shape proposal

A **rounded rectangle** or **capsule shape**, wider than tall, suggesting a
bridge or connector rather than a ring or clamp. Drawn procedurally using
the shared `procedural_shape_utils.gd` primitives (same building block as
helicase_ring.gd, polymerase_clamp.gd, ligase.gd).

```
     ┌─────────────┐
     │  TAU BODY   │  ← connects helicase (left) to lagging Pol (right)
     └─────────────┘
```

Positioned at:
- **X**: helicase X position + small offset (sits just behind helicase)
- **Y**: centered on the lagging strand template ribbon
- **Z**: between DNA ribbon and polymerase clamp layers

---

## Architecture — Division of Labor

### What tau_body.gd owns

1. **Procedural shape rendering** — draws the tau body blob via `_apply()`
2. **ThemeManager integration** — reads tau body visual parameters live each frame
3. **Label support** — optional enzyme label via EnzymeLabel scene (following
   EnzymeLabelsDesign.md pattern)
4. **Setup/initialization** — `setup(sim)` method matching other enzyme scripts

### What tau_body.gd does NOT own

1. **Position** — driven externally by replication_manager.gd or helicase.gd
   (same pattern as polymerase_clamp.gd's position driven by its parent node)
2. **Trombone loop geometry** — handled by a separate `trombone_loop.gd` script
   (see TromboneLoopDesign.md)
3. **Lagging polymerase repositioning logic** — replication_manager.gd decides
   when lagging Pol is helicase-relative vs. absolute; tau_body just provides
   the anchor point

This follows the established pattern: enzyme visuals own their shape and
internal animation; the replication manager owns positioning and lifecycle.

---

## Integration with Complexity System

### Toggle dependency

The tau body is gated by the `trombone_loop_enabled` toggle in ComplexityManager:

```gdscript
# In complexity_manager.gd or replication_manager.gd
if complexity_manager.is_enabled("trombone_loop"):
    tau_body.visible = true
    # Lagging polymerase becomes helicase-relative
else:
    tau_body.visible = false
    # Lagging polymerase uses legacy absolute positioning
```

### Backward compatibility

When `trombone_loop_enabled` is OFF:
- Tau body is hidden
- Lagging polymerase uses existing absolute positioning (current behavior)
- No trombone loop line is drawn
- The simulation remains functionally identical to pre-tau implementation

When `trombone_loop_enabled` is ON:
- Tau body appears at helicase position
- Lagging polymerase repositions to be tau-body-relative
- Trombone loop line appears connecting lagging Pol to fork
- Loop geometry updates dynamically as fragment grows

This is a **purely additive** complexity layer — no existing functionality
changes, only the visual model becomes more biologically accurate.

---

## ThemeManager Exports

Following the pattern established by HelicaseDesign.md ("Helicase Ring" group)
and PolymeraseDesign.md ("Polymerase Clamp" group), a new **"Tau Body"**
export group is required:

| Export Key | Type | Suggested Default | Purpose |
| --- | --- | --- | --- |
| `tau_body_color` | Color | distinct from Pol III | Base color for tau body shape |
| `tau_body_width` | float | ~1.2x polymerase clamp width | Horizontal extent |
| `tau_body_height` | float | ~0.8x polymerase clamp height | Vertical extent |
| `tau_body_chamfer_ratio` | float | 0.2 | Chamfer ratio for octagon primitive |
| `tau_body_corner_radius_ratio` | float | 0.15 | Corner rounding |
| `tau_body_corner_segments` | int | 4 | Smoothness of rounded corners |
| `tau_body_z_index` | int | between DNA and polymerase | Layer ordering |
| `tau_body_label_margin` | float | 12.0 | Distance from shape to label |
| `tau_body_enabled` | bool | true (when trombone_loop enabled) | Master toggle for visibility |

These exports live in ThemeManager alongside the existing "Helicase Ring" and
"Polymerase Clamp" groups, maintaining the project's theming architecture.

---

## Positioning Model

### Coordinate system

The tau body's position is **helicase-relative**:

```gdscript
# Conceptual (actual implementation in replication_manager.gd or helicase.gd)
tau_body.position.x = helicase.position.x - tau_body_offset_x
tau_body.position.y = lagging_strand_ribbon_y
```

Where `tau_body_offset_x` is a small constant (e.g., 10–20 pixels) placing
the tau body just **behind** (to the left of) the helicase ring, representing
the physical linkage without overlapping the ring visual.

### Lagging polymerase attachment

When trombone loop mode is active, the lagging polymerase position becomes:

```gdscript
# Lagging Pol is now tau-body-relative, not absolute
lagging_pol.position.x = tau_body.position.x + polymerase_offset_from_tau
lagging_pol.position.y = lagging_strand_ribbon_y
```

This is the key change: instead of the lagging polymerase having an absolute
position based on fragment progress alone, it now maintains a fixed offset
from the tau body (which moves with the helicase). The trombone loop then
accounts for the difference between this position and where the polymerase
would need to be if it were following the template absolutely.

---

## Animation Strategy

### No intrinsic animation

Unlike the helicase (barrel-roll rotation) or polymerase (synthesis pulse,
clamp open/close), the tau body has **no internal animation clock**. Its
visual state is static except for:

1. **Position updates** — moves with helicase every frame
2. **Visibility toggles** — fades in/out when trombone_loop changes
3. **Optional pulse** — could synchronize with helicase step for visual
   cohesion (deferred until base implementation validated)

### Scrub safety

Following the project's scrub-safety rule (no independent clocks), the tau
body position snaps instantly to the correct location during scrub, derived
from `helicase.current_slot_index` and `helicase.step_t`. No tweening or
time-based motion — pure positional derivation.

---

## Relationship to Trombone Loop Geometry

The tau body and trombone loop are **separate concerns**:

| Tau Body | Trombone Loop |
| --- | --- |
| Physical coupling structure | Dynamic DNA loop geometry |
| Single procedural shape | Line2D or Curve2D |
| Moves with helicase | Updates based on loop length |
| Represents protein complex | Represents ssDNA template |
| Always present when enabled | Changes shape continuously |

See TromboneLoopDesign.md for the loop geometry specification. The tau body
provides the **anchor point** from which the loop is measured — the loop
connects the lagging polymerase (attached to tau body) back to the fork
junction.

---

## Implementation Phases

### Phase 1: Infrastructure
- [ ] Create `tau_body.gd` script following ligase.gd/pol1.gd patterns
- [ ] Add "Tau Body" export group to ThemeManager
- [ ] Implement basic procedural shape (rounded rectangle/capsule)
- [ ] Add EnzymeLabel support (key: `"ENZYME_TAU_BODY"` or `"REPLISOME_TAU"`)
- [ ] Add `trombone_loop_enabled` toggle to ComplexityManager if not present

### Phase 2: Repositioning
- [ ] Modify replication_manager.gd to make lagging Pol helicase-relative
- [ ] Establish tau body position as helicase-offset
- [ ] Test backward compatibility (toggle off = legacy behavior)
- [ ] Verify scrub behavior (instant snap, no drift)

### Phase 3: Integration with Loop
- [ ] Coordinate with TromboneLoopDesign.md implementation
- [ ] Ensure tau body provides correct anchor for loop geometry
- [ ] Tune visual spacing (offset constants, z-ordering)
- [ ] Add optional synchronized pulse (matches helicase step timing)

### Phase 4: Polish
- [ ] ThemeManager tuning pass (colors, sizes accessible and distinct)
- [ ] Label positioning refinement
- [ ] Documentation update (COMPLEXITY_MODEL.md dependencies)
- [ ] QA matrix testing (all toggle combinations with trombone_loop)

---

## Open Questions (Not Yet Resolved)

- **Exact shape choice**: capsule vs. rounded rectangle vs. custom polygon?
  (Capsule is simplest; custom shape may better suggest dimer structure.)
- **Color strategy**: should tau body match Pol III (same complex) or contrast
  (distinct structural role)?
- **Label text**: "Tau", "τ", "Tau Body", or "Replisome Hub"?
- **Pulse animation**: worth adding a subtle helicase-synced pulse, or keep
  purely static to emphasize structural (non-catalytic) role?
- **Primase association**: should primase_blip.gd visually attach to tau body
  when trombone_loop enabled (reflecting DnaG–tau interaction), or remain
  independent?

---

## References

- COMPLEXITY_MODEL.md — `trombone_loop` toggle registry, biological context
- HelicaseDesign.md — procedural shape pattern, step-driven animation model
- PolymeraseDesign.md — two-piece clamp architecture, ThemeManager integration
- OkazakiMaturationDesign.md — trailing enzyme pattern, complexity tier gating
- EnzymeLabelsDesign.md — label scene instantiation, zoom counter-rotation
- `procedural_shape_utils.gd` — shared octagon/round_corners utilities
