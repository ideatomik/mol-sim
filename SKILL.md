---
name: MolSim GDScript
description: >
  Read this skill before writing, editing, or reviewing any GDScript code for
  the MolSim project (Godot 4.x, E:/Godot Projects/MolSim/mol-sim/).
  Covers GDScript hard rules, edit protocol, architecture patterns, polarity
  marker logic, scrub rebuild rules, and biological model reference.
version: "70.3"
---

# MolSim GDScript Skill

## When to use this skill
Read this file before writing, editing, or reviewing any GDScript code for the
MolSim project (Godot 4.x, located at `E:/Godot Projects/MolSim/mol-sim/`).
Main scene: `res://scenes/simulation.tscn`.
Main script: `res://scripts/simulation.gd`.
Helicase sub-manager: `res://scripts/helicase.gd`.

---

## GDScript Hard Rules

- **No multiline `or` expressions.** A GDScript parser bug causes indentation
  errors when `or` spans multiple lines. Always write on a single line:
  ```gdscript
  # WRONG
  if condition_a \
  or condition_b:

  # CORRECT
  if condition_a or condition_b:
  ```

- **`add_child()` before `set_colors()` / `set_font()`.**
  NitrogenBase nodes need to be in the scene tree before receiving color/font
  calls, so `_ready()` fires first:
  ```gdscript
  # CORRECT
  add_child(base)
  base.set_colors(fill_color, label_color)
  ```

- **ThemeManager is a scene node, not an autoload.**
  Always access it via `%ThemeManager`, never via a global singleton.
  Plan: convert to autoload once export values are settled.

- **`nitrogen_base.gd` is ThemeManager-free.**
  Colors and fonts are injected externally via `set_colors()` and `set_font()`.
  Never reference ThemeManager from inside nitrogen_base.gd.

- **Guard signal connections against double-connect.**
  Any signal connected in a function called on re-initialization must be guarded:
  ```gdscript
  if not synthesis_area.area_entered.is_connected(_on_synthesis_area_entered):
      synthesis_area.area_entered.connect(_on_synthesis_area_entered)
  ```

---

## Edit Protocol

### Architecture first
Discuss the design approach before writing any code. Do not produce code until
the approach is agreed upon. If only one thing needs fixing, touch only that thing.

### Use the uploaded file as ground truth
The file the user uploads is always the authoritative current version — not what
was pasted earlier in a session, and not a previous output file. Always reference
the uploaded file when diagnosing issues.

### When combining fixes across versions
Always diff the two versions first to identify exactly what changed. Apply only
the additive fix to the known-good base. Never rewrite from memory.

### Location anchors over line numbers
Line numbers shift as code changes. When giving edit instructions, always anchor
to surrounding code snippets.

### Strict scope discipline
Do not make unrequested changes. Scope creep has caused reverts in this project.

### Debug prints stay
Leave debug prints in place until the feature they guard is explicitly confirmed
stable by the user.

### Version comments
Update the version header at the top of `simulation.gd` when delivering a new
version:
```gdscript
# ==========================================
# v 70.x
# - Change one
# - Change two
# ==========================================
```

---

## Target Architecture

MolSim is a molecular biology education platform covering the central dogma:
replication → transcription → translation. The script structure follows biological
boundaries, not technical convenience.

### Full target structure
```
ComplexityManager (Node → autoload later)
│   @export toggles per feature (okazaki_fragments, sliding_clamps, etc.)
│   is_enabled("feature_name") -> bool
│   Node first for Inspector tweaking; convert to autoload once values settle.
│
ThemeManager (Node → autoload later)
│   @export visual parameters
│   Same pattern as ComplexityManager.
│
simulation.gd  — Template Manager (thin scene coordinator)
│   Owns the source material each biological process reads from:
│   original DNA strands, rails, sequence resource, geometry constants.
│   Exposes slot positions, bases, and geometry to process managers.
│   Does NOT own any synthesized products.
│
├── replication_manager.gd  — thin coordinator for replication
│   Owns shared per-slot state arrays.
│   Delegates to sub-managers. Asks ComplexityManager what's enabled.
│   │
│   ├── helicase.gd  ✓ EXTRACTED
│   │   Discrete slot-by-slot stepping (replaces continuous sweep_speed).
│   │   Owns: current_slot_index, step_t, step_duration, speed_multiplier.
│   │   Owns: extra_steps_total, extra_steps_done (finishing phase).
│   │   Emits: slot_reached(index), phase_changed(new_phase).
│   │   helicase_x is a DERIVED visual value in simulation.gd.
│   │
│   ├── okazaki_manager.gd  (next extraction target)
│   │   Fragment tracking, assignment, open/close logic, sliding clamps (future).
│   │   Emits: fragment_completed(frag_index).
│   │
│   ├── primase.gd  (future)
│   └── ligase.gd  (future)
│
├── transcription_manager.gd  (future)
└── translation_manager.gd    (future)
```

### What simulation.gd exposes to process managers
```gdscript
get_slot_position(index: int) -> Vector2   # world position of template slot
get_base(index: int) -> String             # sequence data
get_complement(index: int) -> String
get_slot_count() -> int
get_geometry() -> Dictionary              # straight_y, dna_ribbons_gap, etc.
```

### Discrete helicase motion (replaces continuous sweep_speed)
```gdscript
# helicase.gd owns:
current_slot_index: int     # which slot the helicase is at
step_t: float               # 0.0→1.0, progress through current inter-slot step
step_duration: float        # seconds per step (derived from speed_multiplier)
speed_multiplier: float     # 1x, 2x, 4x, 8x — player-controlled
extra_steps_total: int      # finishing phase: extra steps past last slot
extra_steps_done: int       # finishing phase: steps taken so far
finishing_acceleration: float  # each finishing step multiplies step_duration by this

# helicase_x is derived in simulation.gd for rendering only:
var last_valid = num_nucleotide_slots - 1
if idx >= last_valid:
    # Extrapolate past last slot during finishing phase
    var overshoot = (idx - last_valid + eased) * nucleotide_slot_spacing
    helicase_x = nucleotide_original_x[last_valid] + overshoot
else:
    helicase_x = lerp(nucleotide_original_x[idx], nucleotide_original_x[idx + 1], eased)
```

### helicase.gd public API
```gdscript
initialize(slot_count, settling_duration)   # called by simulation.gd on init
finish_intro()                              # called when intro tween completes
pause() / resume()
start_finishing(remaining_leading_slots)    # called at FINISHING_LAST_PULSE
notify_settling_ready()                     # called by simulation.gd if needed
scrub_to_slot(index)                        # called by scrub_to()
set_phase(new_phase)                        # force phase (scrub)
set_speed(multiplier)
get_slot_index() -> int
get_eased_step_t() -> float                 # cubic ease-out for visual smoothness
get_settling_blend() -> float
get_phase() -> int
is_done() -> bool
```

### Natural seams — what to split vs keep together
**Extract as separate scripts (clean boundaries):**
- `helicase.gd` ✓ — pure state machine, minimal dependencies
- `okazaki_manager.gd` — fragment lifecycle, self-contained given synthesis events
- `primase.gd`, `ligase.gd` — future, self-contained once fragment structure exists

**Keep together in replication_manager.gd (messy seams):**
- Leading and lagging synthesis logic — share per-slot state arrays constantly
- Sliding clamps — tightly coupled to fragment lifecycle, lives in okazaki_manager

---

## Architecture Patterns

### Spawning nodes
Always follow this order:
1. Instantiate or create the node
2. Configure non-tree properties (z_index, color, etc.)
3. `add_child(node)` — puts it in the scene tree, fires `_ready()`
4. Call `set_colors()`, `set_font()`, or other injection methods

### Okazaki fragment data structure
```gdscript
{
  slots: Array[int],        # slot indices in this fragment
  backbone: Line2D,         # fragment's own backbone line
  bond_marks: Array[Node2D],
  marker_5p: Node2D,        # null until fragment complete
  marker_3p: Node2D,        # null until fragment complete; null for single-slot
  complete: bool
}
```
Fragment boundary = pulse cycle:
`int((nucleotide_original_x[i] - nucleotide_original_x[0]) / pulse_width)`
Same formula used in normal play, end-of-run sweep, and scrub rebuild.

### Polarity marker logic
- **Bottom template**: 3' left, 5' right
- **Top template**: 5' left, 3' right
- **Leading strand**: 3' left, 5' right
- **Lagging strand (whole)**: 5' left, 3' right (hidden until ligase)
- **Okazaki fragments**: 5' left, 3' right per fragment
- **Single-slot Okazaki**: combined "5'-3'" centered marker

### Scrub rebuild — synthesis eligibility
```gdscript
var is_done_phase = helicase_mgr.get_phase() == helicase_mgr.Phase.DONE

# Lagging slots:
if is_done_phase:
    lagging_synth_count += 1  # all slots done
elif nucleotide_original_x[i] < population_left_edge:
    if nucleotide_original_x[i] <= target_factory_x:
        lagging_synth_count += 1

# Leading slots:
if is_done_phase or nucleotide_original_x[i] <= leading_polymerase_x:
    leading_synth_count += 1
```
When scrubbing to DONE, push helicase_x past last slot:
```gdscript
var last_x = nucleotide_original_x[num_nucleotide_slots - 1]
helicase_x = last_x + gap_width
factory_x = last_x
```

### FINISHING_LAST_PULSE pattern
When the helicase reaches the last slot, simulation.gd:
1. Sweeps any remaining lagging slots (proximity detection can't catch them)
2. Closes the last Okazaki fragment
3. Counts leading slots still ahead of factory_x
4. Calls `helicase_mgr.start_finishing(remaining_leading)`

helicase.gd then takes `remaining_leading` extra steps (minimum 1), emitting
`slot_reached` each time so leading bases spawn naturally via position check.
Each step is faster than the last (finishing_acceleration multiplier).
After all steps, helicase self-transitions to SETTLING.

### Hiding markers until a later enzyme
```gdscript
marker_new_5p = _spawn_marker("5'", position)
marker_new_5p.modulate.a = 0.0  # Hidden until ligase joins fragments
```

---

## Key Computed Values

```gdscript
new_bottom_template_y = straight_y + new_bottom_template_offset
new_top_template_y    = straight_y - dna_ribbons_gap - new_bottom_template_offset
helicase_center_y     = straight_y - dna_ribbons_gap / 2.0
lagging_strand_base_y = new_bottom_template_y + dna_ribbons_gap
leading_strand_y      = straight_y - dna_ribbons_gap - new_bottom_template_offset - dna_ribbons_gap
population_left_edge  = factory_x - pulse_offset
pulse_width           = pulse_nucleotide_count * nucleotide_slot_spacing  # Okazaki boundary only
```

---

## Pinned Issues

### Scrub edge case
Occasional escaped synthesized base just left of the lagging polymerase during
scrub. Significantly improved in v70.2–v70.3 but not fully closed. Do not attempt
a partial fix — diagnose fully first. Likely disappears after replication_manager
discrete stepping refactor.

---

## ThemeManager Export Groups (reference)

Background, Base Colors (A/T/C/G, label_color, label_font_size, label_font),
Backbone (color/width/offset/smoothing), Bond Marks, Hydrogen Bonds (AT/CG
color/width/spacing), Synthesis Circle, Helicase (color/thickness/half_width/
height_margin), Markers (color/font_color/font_size/offset),
Okazaki Fragments (okazaki_marker_y_offset: float = 28.0)

---

## Biological Model Reference

MolSim follows the E. coli replication model. Didactic accuracy over exhaustive
precision — short sequences, simplified geometry.

- DNA Pol III synthesizes only 5'→3'
- Leading strand: continuous, follows fork direction (left→right)
- Lagging strand: discontinuous Okazaki fragments via trombone loop model
- Each Okazaki fragment requires an RNA primer (primase)
- β-clamp (sliding clamp) increases polymerase processivity
- τ (tau) body connects helicase + both polymerases + clamp loader in replisome
- Transcription errors: RNA Pol has no proofreading (~1 error per 10⁴ bases)
- Redundancy of transcription buffers errors — many mRNA copies per gene
