# Trombone Loop Design — Dynamic Lagging Strand Geometry
_Design document for the trombone loop visualization (`trombone_loop.gd`), the
dynamic DNA loop that forms on the lagging strand template in the E. coli
replisome model. Companion to TauBodyDesign.md (structural coupling point),
COMPLEXITY_MODEL.md's `trombone_loop` toggle, and the existing polymerase/helicase
architecture. Implements the iconic "trombone" geometry that gives the
replisome its name._

---

## Biological Context

The **trombone loop** is a direct consequence of two constraints:

1. **DNA polymerase only synthesizes 5'→3'**
2. **Both polymerases move physically with the helicase** (due to tau body coupling)

Since the lagging strand template runs 3'→5' toward the fork (opposite the
leading strand), the lagging polymerase must synthesize DNA by moving _away_
from the fork along the template. But because it's physically tethered to the
helicase via the tau body, it can't actually move away — instead, the
template DNA itself forms a **loop** that grows as synthesis proceeds.

When the loop reaches a critical length (one Okazaki fragment ~1000–2000 nt
in E. coli), the polymerase releases, the loop collapses, and a new cycle
begins at the next primase site.

This dynamic loop structure resembles a **trombone slide** extending and
retracting — hence the name.

---

## Visual Concept

The trombone loop is rendered as a **dynamic curved line** connecting:

- **Anchor point**: the lagging polymerase (attached to tau body)
- **Fork junction**: where the lagging template emerges from the helicase

The loop should appear as a smooth **bezier curve** or series of connected
segments that:

1. Starts near the polymerase clamp
2. Extends backward (leftward) as the fragment grows
3. Forms a U-shaped or teardrop-shaped loop
4. Suddenly collapses when the fragment completes
5. Repeats for each Okazaki fragment

### Style options

| Approach | Pros | Cons |
| --- | --- | --- |
| **Line2D with points** | Simple, performant, easy to update | Less organic curve control |
| **Curve2D + baked mesh** | Smooth bezier curves, adjustable tension | More complex setup, may need rebaking |
| **Custom polygon** | Full control over loop thickness/taper | Most complex, requires geometry math |

**Recommendation**: Start with **Curve2D** for smooth, adjustable curves.
Can always simplify to Line2D if performance becomes an issue.

---

## Geometry Model

### Key parameters

The loop shape is determined by these variables:

```gdscript
# Fixed anchors
var polymerase_pos: Vector2  # Current lagging Pol position (tau-relative)
var fork_pos: Vector2        # Helicase/fork junction position

# Dynamic state
var fragment_progress: float  # 0.0 → 1.0 through current Okazaki fragment
var max_loop_length: float    # Pixels at full fragment length (~1000–2000 nt equivalent)
var current_loop_length: float = fragment_progress * max_loop_length

# Shape tuning
var loop_tightness: float     # How sharply the curve bends (adjustable via ThemeManager)
var loop_sag: float           # Vertical droop (makes loop more U-shaped vs. circular)
```

### Curve construction

Using Godot's Curve2D system:

```gdscript
# Point 0: starts at polymerase
curve.add_point(polymerase_pos)

# Point 1: control point pulling backward/left
var control_back = polymerase_pos + Vector2(-current_loop_length * 0.5, 0)
curve.add_point(control_back)

# Point 2: control point pushing forward/right toward fork
var control_forward = fork_pos + Vector2(-current_loop_length * 0.5, 0)
curve.add_point(control_forward)

# Point 3: ends at fork junction
curve.add_point(fork_pos)
```

This creates a smooth S-curve or U-curve depending on the control point
placement. Adjusting the control point offsets changes the loop's apparent
"tightness" and how much it sags vertically.

### Pre-loop minimum

Biologically, there's a small amount of ssDNA between the polymerase and
fork even at the start of a fragment (the "pre-loop"). This should be
represented as a **minimum loop length** that never goes to zero:

```gdscript
const PRE_LOOP_MIN_PIXELS = 15.0  # Never fully collapse visually
var actual_loop_length = max(current_loop_length, PRE_LOOP_MIN_PIXELS)
```

---

## Architecture — Division of Labor

### What trombone_loop.gd owns

1. **Curve2D or Line2D node management** — creates/updates the visual curve
2. **Geometry calculation** — computes control points based on anchor positions
3. **ThemeManager integration** — reads loop visual parameters (color, width, etc.)
4. **Fragment lifecycle** — responds to fragment start/completion events
5. **Animation of growth/collapse** — smooth interpolation between states

### What trombone_loop.gd does NOT own

1. **Polymerase or helicase positioning** — reads positions, doesn't set them
2. **Fragment timing logic** — replication_manager.gd decides when fragments
   start/end; trombone_loop just responds
3. **Tau body rendering** — separate concern (see TauBodyDesign.md)

This follows the established pattern: the loop is a **reactive visual element**
that depends on state owned elsewhere.

---

## Integration with Complexity System

### Toggle dependency

The trombone loop is gated by the same `trombone_loop_enabled` toggle as the
tau body:

```gdscript
if complexity_manager.is_enabled("trombone_loop"):
    trombone_loop.visible = true
    trombone_loop.update_loop()  # Start updating each frame
else:
    trombone_loop.visible = false
    # Lagging template renders as straight line (legacy behavior)
```

### Interaction with primer removal / Pol I

When `pol1_enabled` (Complex tier):
- Loop still forms during fragment synthesis
- Loop collapse timing unchanged
- No direct interaction with Pol I's nick-translation

The trombone loop represents **physical template geometry**, not enzymatic
processing — it's independent of what happens to the RNA primer afterward.

---

## ThemeManager Exports

A new **"Trombone Loop"** export group is required:

| Export Key | Type | Suggested Default | Purpose |
| --- | --- | --- | --- |
| `trombone_loop_color` | Color | matches template strand | Line color for loop |
| `trombone_loop_width` | float | 3.0 | Stroke width of loop line |
| `trombone_loop_tightness` | float | 0.6 | Bezier control point spacing |
| `trombone_loop_sag` | float | 0.3 | Vertical droop factor |
| `trombone_loop_pre_loop_min` | float | 15.0 | Minimum visible loop size |
| `trombone_loop_max_pixels` | float | 200.0 | Max loop extent at full fragment |
| `trombone_loop_z_index` | int | below enzymes, above DNA | Layer ordering |
| `trombone_loop_gradient` | bool | false | Optional gradient along loop length |
| `trombone_loop_animated` | bool | true | Enable/disable growth animation |

These exports allow fine-tuning the loop's appearance without code changes,
matching the project's theming philosophy.

---

## Animation Strategy

### Growth phase

As the lagging polymerase synthesizes the fragment:

```gdscript
# In _process or via explicit update call
func update_loop(fragment_progress: float) -> void:
    var progress = clampf(fragment_progress, 0.0, 1.0)
    current_loop_length = lerpf(PRE_LOOP_MIN, max_loop_length, progress)
    _update_curve_points()
```

The loop grows smoothly from minimum to maximum length over the fragment
synthesis duration (~2–5 seconds depending on speed multiplier).

### Collapse event

At fragment completion, the loop must **rapidly collapse**:

```gdscript
# Called by replication_manager.gd at fragment boundary
func collapse_loop() -> void:
    # Option 1: Instant snap (scrub-safe, simplest)
    current_loop_length = PRE_LOOP_MIN
    _update_curve_points()
    
    # Option 2: Fast tween (more dramatic, needs scrub handling)
    var tween = create_tween()
    tween.tween_property(self, "current_loop_length", PRE_LOOP_MIN, 0.1)
```

**Recommendation**: Use **instant snap** for initial implementation.
Matches the project's scrub-safety discipline and reflects the biological
reality (loop release is very fast once polymerase disengages).

### Scrub safety

During scrub operations:
- Loop instantly snaps to correct length for current fragment progress
- No tweens or time-based animations active
- Same geometric calculation as real-time, just applied instantly

---

## Coordinate System & Positioning

### Anchor points

```gdscript
# Polymerase anchor: read from lagging polymerase node
var pol_anchor = lagging_polymerase.global_position

# Fork anchor: derived from helicase position
var fork_anchor = helicase.global_position + Vector2(helicase_half_width, 0)

# Both anchors are in global coordinates; curve points computed accordingly
```

### Template strand alignment

The loop should appear to emerge from the **lagging strand template ribbon**,
not float arbitrarily. This means:

- Y-position of both anchors should align with lagging template Y
- Loop should not cross into leading strand space
- Z-index should place loop behind enzyme bodies but in front of DNA ribbon

---

## Relationship to Tau Body

The tau body and trombone loop work together but are **separate nodes**:

```
Helicase ring
    └─ Tau body (offset slightly left)
        └─ Lagging polymerase (fixed offset right from tau)
            └─ [Trombone loop connects Pol back to fork]
```

The tau body provides the **structural anchor**; the trombone loop provides
the **geometric visualization** of the template DNA path.

See TauBodyDesign.md for the tau body specification.

---

## Implementation Phases

### Phase 1: Basic Infrastructure
- [ ] Create `trombone_loop.gd` script (extends Node2D)
- [ ] Add Curve2D child node programmatically
- [ ] Add "Trombone Loop" export group to ThemeManager
- [ ] Implement basic `_update_curve_points()` method
- [ ] Test visibility toggle (on/off with `trombone_loop_enabled`)

### Phase 2: Geometry Tuning
- [ ] Connect to lagging polymerase position (read-only)
- [ ] Connect to helicase/fork position (read-only)
- [ ] Tune bezier control points for natural-looking loop
- [ ] Implement pre-loop minimum constant
- [ ] Test loop growth across fragment synthesis

### Phase 3: Lifecycle Integration
- [ ] Hook into fragment start/completion signals
- [ ] Implement instant collapse at fragment boundary
- [ ] Verify scrub behavior (instant snap, no drift)
- [ ] Test with varying fragment lengths (if applicable)

### Phase 4: Polish & Optimization
- [ ] ThemeManager tuning pass (colors, widths, tightness)
- [ ] Performance check (Curve2D update cost per frame)
- [ ] Optional: add subtle gradient or taper effect
- [ ] QA testing with all complexity tier combinations
- [ ] Documentation cross-reference updates

---

## Open Questions (Not Yet Resolved)

- **Curve style**: Should loop be a simple line, or should it have thickness
  that tapers (thicker near polymerase, thinner at fork)?
- **Color strategy**: Match template strand color exactly, or use a distinct
  highlight color to make loop more visible?
- **Loop direction**: Should the curve always sag downward, or should it
  alternate (some up, some down) to suggest 3D randomness?
- **Maximum length capping**: If fragment length exceeds visual bounds, should
  loop scale down proportionally or clip at a maximum pixel length?
- **Primase blip interaction**: When primase places a new primer, should the
  loop briefly show a "kink" or marker at the primer site?

---

## Biological Accuracy Notes

### Loop length scaling

Real E. coli Okazaki fragments are ~1000–2000 nucleotides. The visual loop
length should be **proportional** to this:

```gdscript
# If 1 slot = 1 base pair visually
const OKAZAKI_FRAGMENT_SLOTS = 1500  # E. coli average
var max_loop_length = OKAZAKI_FRAGMENT_SLOTS * slot_spacing_pixels
```

However, this may need adjustment for visual clarity — a literal 1500-slot
loop might be too large for the viewport. Consider:

- Scaling factor (e.g., 0.5x for visual fit)
- Capping at reasonable pixel maximum
- Making max length tunable via ThemeManager export

### Single-strand vs. double-strand representation

The trombone loop represents **single-stranded DNA template** (the lagging
strand before synthesis). Visually, this could be distinguished from the
double-stranded regions by:

- Thinner line weight than duplex DNA
- Different color (perhaps matching single-strand regions elsewhere)
- Slight waviness or reduced rigidity in the curve

This distinction is optional but adds biological fidelity.

---

## References

- COMPLEXITY_MODEL.md — `trombone_loop` toggle registry, Stage 2 elongation context
- TauBodyDesign.md — structural coupling point, tau dimer architecture
- OkazakiMaturationDesign.md — fragment lifecycle, primase/ligase/Pol I timing
- PolymeraseDesign.md — lagging polymerase positioning, clamp architecture
- Godot Curve2D documentation — bezier curve API reference
