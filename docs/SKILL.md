---
name: molsim-gdscript
description: >
  Read this skill before writing, editing, or reviewing any GDScript code OR
  .tscn scene files for the MolSim project (Godot 4.x,
  E:/Godot Projects/MolSim/mol-sim/). Covers the Crystal Building session
  method, GDScript hard rules, silent Godot engine traps (.tscn attribute
  placement, Camera2D.ignore_rotation, stale editor state), edit protocol,
  architecture patterns, polarity marker logic, scrub rebuild rules, and
  biological model reference.
version: "81.0"
---

# MolSim GDScript Skill

## When to use this skill
Read this file before writing, editing, or reviewing any GDScript code for the
MolSim project (Godot 4.x, located at `E:/Godot Projects/MolSim/mol-sim/`).
Main scene: `res://scenes/simulation.tscn`.
Main script: `res://scripts/simulation.gd`.
Helicase sub-manager: `res://scripts/helicase.gd`.

---

## The Crystal Building Method (session method)

How sessions run. Borrowed from the Double Diamond (Discover / Define / Develop
/ Deliver) and renamed, because the geology maps onto this project's real
failure modes and the diamonds don't.

### 1. Nucleation — find the seed

The seed is a **problem**, never a solution. v77's was "the vertical teaser drew
interest but viewers reported not understanding what they were looking at" — not
"build a vertical mode."

A seed's quality determines the whole crystal. State it as an observed fact
about the world, and resist letting a proposed solution stand in for it. When
the user arrives with a solution ("rotate the camera 90 degrees"), find the
problem underneath it first — then say whether the solution fits.

### 2. Lattice — define the structure

The design doc. The lattice determines what can attach later: once
frame-providers-return-world-points is the structure, every subsequent fix must
attach along it or the crystal fractures.

Architecture is discussed and approved before any code. This phase produces a
document, not an implementation.

### 3. Growth — accrete along the lattice

Implementation. Two rules, both load-bearing:

**A crystal only accretes what is actually in the solution.**
Never grow from inference. Every v77 failure was an attempt to accrete material
that wasn't there:
- Reasoned about `.tscn` attribute placement twice, having already flagged the
  format as unrecognized. One editor round-trip settled it in thirty seconds.
- Claimed "that closes the glyph inventory" from a sweep of *uploaded* files —
  `nucleotide_field.gd` hadn't been uploaded and had a `draw_string()`.
- Split a document on `"---"` without checking whether `---` appeared in the
  content. It did: a markdown table separator. Orphaned the table.
- Read a `[ ]` in a doc last touched six days earlier as a live task. It was
  done, and the reply changed the plan.

**Before asserting completeness, format, or status: check the territory.**
If verification is cheap and the claim is load-bearing, verification is not
optional. Flagging uncertainty out loud is not a substitute for resolving it.

**Growth is epitaxial** — new layers inherit the substrate's orientation. Each
file's existing convention governs what attaches to it. In v77:
`helicase_ring.gd` got the counter-rotation *pushed* (it holds zero external
references); `polymerase_clamp.gd` *reached* for it through its existing `_sim`
(it already does that for ThemeManager); `nitrogen_base.gd` got it *injected*
via a setter (ThemeManager-free by contract). Same value, three delivery
mechanisms, each matching its own substrate.

### 4. Annealing — the debrief

Defects don't leave a crystal by adding more layers. You revisit, and let them
migrate out. This is the document pass, and it is not optional bookkeeping — it
is the phase that keeps the lattice true.

**Growth is allowed to invalidate the Lattice, and the As-Built section is the
ritual for recording that.** This is the amendment the Double Diamond doesn't
make: it assumes Discover is *research*, so the brief can be trusted. Here,
discovery is mostly *reading the existing codebase* — the territory already
exists, it just isn't in anyone's head yet, and reading it costs enough that it
happens during Growth.

So the design doc will be wrong, structurally, not sloppily. Five of
`VerticalModeDesign.md`'s claims died on contact with real files: `_fit_points()`
was dead code; five viewport reads were eight across three files; the mirror sign
belonged in `EnzymeLabel`, not the callers; `polymerase_halo.gd`'s fix was the
*opposite* of what `nucleotide_field.gd` needed.

**Record the divergence; never silently patch the design to match reality.** An
As-Built section that says "the design claimed X, the code said Y, here's why"
is worth more than a design that was never wrong — because the next person
reading it learns where this codebase's intuitions mislead.

### Defects propagate

An error in an early lattice plane becomes a plane of weakness throughout.
`_mirror` doubling as strand identity was harmless while it only picked
`clamp_leading_back_color` — cosmetic. It became load-bearing the moment LINEAR
topology made leading and lagging genuinely different enzymes. When a defect is
found, ask what else grew on top of it.

Corollary: **prefer loud failure modes.** A missing `%Name` on a typed
`@onready` errors at startup naming the node; an unassigned `@export` is silently
null until first use. Choosing the loud one is what made a 25-node refactor safe
to do mechanically.

### Grain boundaries

A session is rarely one crystal. v77 was four nucleation sites — vertical mode,
topology labels, PlayerUI, and a strategic call about the zoom rework — growing
into separate domains that met at boundaries.

**Grain boundaries are where materials fail**, which this project already knows
under another name: `SHARED_BASE_SEAM.md`, and COMPLEXITY_MODEL.md's
labeled-chimera principle. The same discipline applies to session work. When two
crystals meet — a rename pass touching a feature pass, a UI change touching a
camera change — the boundary is the risk, and it gets labeled rather than
blended.

Practical consequence: keep the domains separable. v77's ThemeManager rename
shipped as a **provable no-op** (comments stripped and identifiers normalized,
the files were byte-identical) specifically so that "did the rename break
something" and "did vertical mode break something" never became one question.

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

## Godot Engine Traps (silent — no error, no crash, feature just absent)

Every entry here cost real debugging time. They share a shape: Godot accepts the
input, reports nothing, and does not do the thing.

### `unique_name_in_owner` is a PROPERTY LINE, not a header attribute
Cost roughly an hour in v77. Godot writes it BELOW the node header:

```
[node name="Scrubber" type="HSlider" parent="Panel/MarginContainer/VBoxContainer"]
unique_name_in_owner = true
layout_mode = 2
```

Putting it inside the brackets (`[node name="Scrubber" ... unique_name_in_owner=true]`)
parses without error and does NOTHING. Every `%Name` lookup then fails at startup
with `Node not found: "%Foo"` — all of them at once.

**The diagnostic tell**: if ALL unique names fail together while the scene itself
loads fine, it's the mechanism, not the names. A wrong name breaks one lookup; a
wrong mechanism breaks every one.

### Godot's `.tscn` parser silently ignores unknown `[node]` header keys
This is *why* the trap above is silent rather than an error. Never infer from
"the scene loaded" that an attribute you added was understood.

### `unique_id=` in MolSim's `.tscn` files is an unrecognized dialect — leave it alone
Every `[node]` header carries `unique_id=<int>`. It is **not**
`unique_name_in_owner` despite the resemblance, and its purpose is not documented
here. Don't touch it. When deriving a NEW scene from an existing one, strip it
(and the `gd_scene` `uid=`) so Godot regenerates rather than two scenes claiming
one identity.

### Godot will not reload an open scene from disk — and will overwrite it
If a `.tscn` is open in the editor and the file changes underneath, Godot keeps
its in-memory copy and writes it back on the next save, silently reverting the
change. **Close the tab before replacing a scene file.**

The flip side rescued v77: after the broken `.tscn` was reverted on disk, the
editor still held the good in-memory version, and Ctrl+S wrote Godot's own
canonical serialization out — which is what finally answered the format question.

**So: when unsure what Godot writes, tick the property in the editor, save, and
read the file.** That is ground truth. Reasoning about the format is not.

### `Camera2D.ignore_rotation` defaults to TRUE in Godot 4
Setting `rotation` on a Camera2D does nothing until `ignore_rotation = false`.
No error. `zoom_manager.gd`'s `_apply_orientation()` clears it unconditionally so
no state exists where it's true.

### Others already recorded (see STATUS.md's Pinned Issues for the full account)
- CSV localization must be registered in Project Settings — importing it in the
  FileSystem dock is not enough, and `tr()` silently echoes the raw key back.
- `LocaleManager`'s unique-name flag.
- `mouse_filter` defaults to `Stop` on `ColorRect` — a full-screen background
  absorbs every click at the GUI stage before `_unhandled_input()` ever sees it.
- Autoload dead entries in `project.godot`.
- `Area2D` physics picking; `unique_name_in_owner` on nodes reached via `%`.

---

## Edit Protocol

### Architecture first
Discuss the design approach before writing any code. Do not produce code until
the approach is agreed upon. If only one thing needs fixing, touch only that thing.

This is the **Lattice** phase of the Crystal Building Method above; everything
else in this Edit Protocol is **Growth**. If a session skips straight here from a
bare feature request, the seed hasn't been found yet — go back and find the
problem under the proposed solution.

### Use the uploaded file as ground truth
The file the user uploads is always the authoritative current version — not what
was pasted earlier in a session, and not a previous output file. Always reference
the uploaded file when diagnosing issues.

**This extends to file FORMATS, not just contents.** When a file uses a
convention you don't recognize, do not reason about it — have the editor produce
one example and read what it writes. v77 lost an hour to two confident guesses
about `.tscn` attribute placement that a single editor round-trip settled in
thirty seconds. Flagging the uncertainty out loud is not a substitute for
resolving it.

**And a sweep across uploaded files is a sample, not the population.** v77's
"that closes the glyph inventory" was wrong because `nucleotide_field.gd` hadn't
been uploaded yet and had a `draw_string()` — it would have shipped with sideways
letters. Any claim about ALL of the code must be checked against the repo, not
against what happens to be in the conversation.

### Verify biology against current sources, not memory
The same ground-truth discipline above applies to biological claims, not just
code. Before finalizing a design decision, a complexity-toggle behavior, or a
proposed option set that rests on a biological mechanism, check it against a
current authoritative source (a recent review, textbook, or primary paper) —
don't rely on trained-in recall. As zoom depth and mechanism count grow, the
risk of quietly conflating adjacent facts (wrong rate-limiting step, wrong
enzyme assignment, a detail that's true for one organism but not the one
MolSim models) grows with it, and errors like that are far more expensive to
catch after they're embedded in animation logic than before.

Cite what was checked: name the source and pull the specific supporting detail
in your own words, with a short (sub-sentence) excerpt only where the exact
wording matters — not a running paraphrase-quote of the source. If a source
can't be found or is ambiguous, say so explicitly rather than defaulting to
memory silently. This applies to Nucleation/Lattice-stage discussion as much
as to committed doc text — flag the unverified biological claim before it
becomes a premise the rest of the session builds on.

### When combining fixes across versions
Always diff the two versions first to identify exactly what changed. Apply only
the additive fix to the known-good base. Never rewrite from memory.

### Verify by cross-checking two sources, never by a replace count
A find-and-replace reporting "3 sites changed" says nothing about whether there
were 4. Pick an invariant the change must satisfy, then test the invariant.

Two v77 cases, both caught this way:
- **The `set_label_rotation()` push**: the anchor assumed `set_font(...)` was
  followed by `return base` — true for `_spawn_leading_base()` and
  `_spawn_marker()`, but NOT `_spawn_lagging_base()`, which has an
  `if shape_override != null:` tail. Caught by asserting that every `set_font(`
  in both files is followed by a `set_label_rotation(`. Missing it would have
  shipped every lagging-strand and RNA primer base sideways while leading bases
  stood upright.
- **The PlayerUI unique-name refactor**: verified by rebuilding the path->name
  map FROM the scene file and confirming each `%Name` resolves to the exact node
  its old `$`-path pointed at — not by trusting that a regex grabbed the right
  leaf.

Corollary: prefer failure modes that are loud. A missing `%Name` on a typed
`@onready` errors at startup naming the node and line; an unassigned `@export`
drag-target is silently null until first use. That difference is why the
25-node unique-name refactor was safe to do mechanically.

### Location anchors over line numbers
Line numbers shift as code changes. When giving edit instructions, always anchor
to surrounding code snippets.

### Strict scope discipline
Do not make unrequested changes. Scope creep has caused reverts in this project.

### Debug prints stay
Leave debug prints in place until the feature they guard is explicitly confirmed
stable by the user.

### Version comments — three files, one owner each
**Rule.** Each file owns exactly one thing. Do not duplicate between them.

| File | Owns |
| --- | --- |
| `simulation.gd` header | The **current version only**. Nothing older. |
| `CHANGELOG.md` | **All version history**, newest first. |
| `STATUS.md` | **Current state and why** — architecture, scene structure, pinned issues, resolved-bug lessons. Not a version log. |

**Procedure when delivering a new version.**
1. Move the outgoing version's block from `simulation.gd`'s header into
   `CHANGELOG.md`.
2. Write the new version's block in the header.
3. Do not leave two version blocks in the header.

```gdscript
# ==========================================
# v 70.x
# - Change one
# - Change two
#
# CURRENT VERSION ONLY. Prior versions live in CHANGELOG.md.
# ==========================================
```

*Rationale:* before this rule, the header had accumulated five blocks and
~87 lines before the first line of code — and the retention was arbitrary
rather than deliberate. v77, v76, v71.x and v70.6 survived while v72–v75 had
been pruned at some point with no record of the decision. Those four versions
are now recoverable only from git history. Meanwhile STATUS.md already
carried fuller accounts of several of the same passes, so the header was
partly duplicating it with no rule for which owned what — the same
divergence-by-duplication problem the extraction entry above describes,
applied to prose instead of code.

A documentation-only restructure is **not** itself a version bump. Bump the
version when behavior changes, not when comments move.

---

## Target Architecture

MolSim is a molecular biology education platform covering the central dogma:
replication → transcription → translation. The script structure follows biological
boundaries, not technical convenience.

### Full target structure
```
ComplexityManager (Node, %ComplexityManager, sibling of %ThemeManager)
│   Real toggles now: primase_enabled, pol1_enabled (own @export vars);
│   ligase_enabled stays on sim itself (predates this node — see its own
│   migration note, a deliberate "don't duplicate the source of truth" call,
│   not an oversight).
│   is_enabled("feature_name") -> bool — match on feature, proxy to sim for
│   ligase specifically.
│   set_X_enabled(value) per toggle — not a bare setter, drives cascades.
│   Bridge toggle cascade (pol1_enabled): turning ON force-enables primase +
│   ligase; either sibling turning OFF force-disables pol1. Asymmetric on
│   purpose — see OkazakiMaturationDesign.md's Cascade logic and
│   COMPLEXITY_MODEL.md's Cascading UI behavior (now a named, registered
│   pattern, not ad hoc).
│   emits toggle_changed(feature, enabled) — UI (ComplexitySetupPopup) and
│   replication_manager.gd both listen, no polling.
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
│   ├── okazaki_manager.gd  (still the one deferred extraction target —
│   │   fragment tracking/open/close logic all stayed inline in
│   │   replication_manager.gd even after primase/ligase/pol1 shipped;
│   │   none of the three needed it pulled out to land)
│   │   Fragment tracking, assignment, open/close logic, sliding clamps (future).
│   │   Emits: fragment_completed(frag_index).
│   │
│   ├── primase_blip.gd  ✓ BUILT — real per-slot RNA placement (not a
│   │   decorative blip despite the name), own PolymeraseHalo instance,
│   │   pending-backbone registry for its ahead-of-Pol-III window
│   │
│   ├── ligase.gd  ✓ BUILT — traveling enzyme, LigaseState state machine
│   │   (IDLE/TRAVELING/HOLDING/SEALING), dual trigger call sites
│   │   (_lagging_close_fragment() + _pol1_finish_job(), gated by
│   │   frag.primer_removed only at Complex tier)
│   │
│   └── pol1.gd  ✓ BUILT — two-lobe (EXO/POL) nick-translation enzyme,
│       the one enzyme with a TRUE-ABSENCE lifecycle (not instantiated
│       until its first job, unlike every other enzyme's create-once-hide
│       pattern — see Architecture Patterns below). Trigger is
│       event-count-gated (fragment CLOSE, one-fragment lag via
│       lagging_fragments[-2]), not real-time-paced — see Architecture
│       Patterns' "scrub-safety demands event-count gating" entry for why
│       that distinction mattered enough to redesign the trigger mid-build.
│
├── transcription_manager.gd  (future)
└── translation_manager.gd    (future)

procedural_shape_utils.gd (ProceduralShapeUtils, class_name — no preload
    needed) — shared octagon()/round_corners() building blocks, extracted
    after round_corners() ended up duplicated identically five times across
    helicase_ring.gd/ligase.gd/primase_blip.gd/pol1.gd/polymerase_clamp.gd.
    New procedural enzyme visuals should call this rather than adding a
    sixth copy.
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
- `okazaki_manager.gd` — fragment lifecycle, still not extracted; stayed
  inline in replication_manager.gd through primase/ligase/pol1 all
  shipping without it
- `primase_blip.gd`, `ligase.gd`, `pol1.gd` ✓ — all built, all
  self-contained per the original prediction here. `pol1.gd` needed one
  real deviation from the other two's lifecycle — see Architecture
  Patterns' true-absence entry.
- `procedural_shape_utils.gd` ✓ — not predicted here originally, but
  turned out to be the actual natural seam once a fifth enzyme visual
  needed the same octagon/rounding math the first four had each been
  copy-pasting

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
  slots: Array[int],          # slot indices in this fragment
  loop_queue: Array,
  backbone: Line2D,           # DNA-portion backbone line
  primer_backbone: Line2D,    # RNA-portion backbone line, null once no
                               # slots in this fragment are still primer —
                               # see _is_still_primer(), _primer_rna_color_for()
  bond_marks: Array[Node2D],
  primer_bond_marks: Array[Node2D],
  marker_5p: Node2D,          # null until fragment complete
  marker_3p: Node2D,          # null until fragment complete; null for single-slot
  complete: bool,
  sealed: bool,                # ligase-specific; true once _ligase_finish_seal() ran
  primer_removed: bool,        # pol1-specific; true once _pol1_finish_job() ran —
                                # gates _ligase_kick()'s eligibility check at Complex
                                # tier only, ignored entirely at Light tier
}
```
No `primer_placed` field — "is a slot's primer placed" is answered per-slot
(`lagging_synthesized_bases[i]` non-null + `shape == "rounded_square"`,
via `_is_still_primer()`), not tracked at the fragment level. See
OkazakiMaturationDesign.md's Data model section for the fuller account of
why the originally-proposed four-flag version didn't match what shipped.
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

### ComplexityManager access — same %-unique-name pattern as ThemeManager
```gdscript
complexity_mgr = p_sim.get_node_or_null("%ComplexityManager")  # cache once, in initialize()
if complexity_mgr != null and complexity_mgr.is_enabled("primase"):
    ...
```
One real asymmetry to know about: `ligase_enabled` lives directly on
`sim` (predates ComplexityManager), not on ComplexityManager itself — a
deliberate "don't create two sources of truth" call documented in
`complexity_manager.gd`'s own migration note, not an oversight to "fix" by
moving it. `ComplexityManager.is_enabled("ligase")` proxies to
`sim.ligase_enabled` under the hood; `primase_enabled`/`pol1_enabled` are
real `@export var`s on ComplexityManager itself. When adding code that
reads a toggle, check which one you're actually dealing with — `sim.pol1_enabled`
doesn't exist and will crash at runtime (`Invalid access to property or
key`), not fail a lookup.

### Bridge toggle — a recognized cascade pattern, not ad hoc per-enzyme logic
Some toggles exist purely to couple two independently-meaningful siblings
into something only makes sense together (Pol I bridging primase +
ligase is the first shipped case). Cascades both directions, asymmetrically:
```gdscript
func set_pol1_enabled(value: bool) -> void:
    ...
    if value:
        if not primase_enabled: set_primase_enabled(true)
        if not sim.ligase_enabled: set_ligase_enabled(true)
    toggle_changed.emit("pol1", value)
```
Turning the bridge ON force-enables both siblings (an explicit exception to
the usual "child doesn't auto-enable parent" rule). Turning EITHER sibling
OFF force-disables the bridge (the standard rule, unchanged). See
`COMPLEXITY_MODEL.md`'s Cascading UI behavior section — this is now a named,
registered pattern there, not something to re-derive per new bridging
enzyme (clamp loader/clamps is the anticipated next case).

### True-absence lifecycle — the exception to "create once, hide"
Every enzyme visual except `pol1.gd` is instantiated once at
`initialize()` and toggles `visible`/`modulate.a` thereafter. Pol I breaks
this: not instantiated until its first job exists (real Pol I has no fixed
replisome position to occupy while idle, unlike helicase/Pol III/the clamp,
which are physically tethered together), then persists once created rather
than being freed/reinstantiated again between jobs — it plays a
leave-the-strand motion (drop + fade) instead. Before defaulting a new
enzyme to the create-once-hide pattern, check whether it's actually a
tethered replisome component or a freely-diffusing one — that's the real
question, not "is it simpler to always create it upfront."

### Scrub-safety demands event-count gating, not real-time pacing
A trigger that fires off Pol III's own real-time animation progress (e.g.
"the instant this fire-step's tween completes") cannot be reconstructed
instantly for an arbitrary scrub target without replaying tween history —
which nothing in this project does. Pol I's own trigger got redesigned
mid-build for exactly this reason: an early proposal paced removal off
Pol III's real-time fire-step; the shipped version instead gates on
`lagging_fragments.size()` (a fragment CLOSE event count), fully
recomputable from scrub state alone. Per-slot animation speed (how fast
something visibly moves) is unrelated and fine to pace off
`helicase_mgr.step_duration` — the rule is specifically about *when a
job starts*, not how long its own animation takes once running. See
`OkazakiMaturationDesign.md`'s Pol I Implementation Status for the full
account, including the concrete tile-number check that caught the original
proposal being wrong before it shipped.

### Extract shared code by what divergence costs, not by copy count
**Rule.** Classify the duplicated code first. Then extract.

- **Pure utility** — geometric or mathematical code with no domain meaning
  and no tuned value. Copies cannot disagree about behavior. Extract when
  convenient.
- **Behavioral constant** — any value or function the simulation's motion is
  calibrated against. Examples: easing curves, pacing ratios, derived
  geometry offsets. Copies that drift produce no error and no crash. They
  produce motion that looks wrong. Extract on the second copy.

**Alternative to extraction.** Remove the second consumer instead. Resolve
the value at the boundary. Pass the result to the consumer. The consumer
then holds no logic that can drift.

*Rationale and history:* `procedural_shape_utils.gd` was extracted after
`round_corners()` reached five identical copies — but that number is not the
rule, and reading it as one gets the lesson backwards. All five of those
files' headers had been individually flagging and deferring the extraction
the whole time. It was a known debt carried four copies too long, not
patience vindicated. `round_corners()` happened to be a pure utility, so the
delay cost only tedium; the same delay on a behavioral constant would have
cost a debugging session instead.

This is the "never let two independently-tuned numbers coincidentally agree"
rule in function form rather than constant form. The constant form has
already bitten this project twice: the wobble-gating mismatch
(`polymerase_y_lagging` vs `new_bottom_template_y`, differing by
`dna_ribbons_gap / 2.0`), and the camera's stale `straight_y` read after the
rename to `template_strand_y`.

Do not over-apply this toward premature extraction. Two visuals that
superficially resemble each other are not automatically one shared thing —
ligase's pulse SHRINKS (pinch) while primase's GROWS, a deliberate
distinction ThemeManager's own comments flag. An "enzyme pulse" extraction
would have fought a divergence that turned out to be correct. The
classification step is the work; the copy count is only the trigger to
perform it.

The ATP cycle took the alternative route rather than extracting
(`ATPCycleDesign.md`). Instead of sharing `get_eased_step_t()`'s cubic with
a second caller, `simulation.gd` resolves both values at the boundary and
passes them pre-named — `spawn_progress_raw` and `drift_progress_eased` — so
the consuming node holds no easing logic at all. Sharing a definition and
eliminating the second consumer both prevent divergence; prefer whichever
leaves fewer places able to get it wrong.

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
Okazaki Fragments (okazaki_marker_y_offset: float = 28.0),
Polymerase Clamp (back/jaw/lower-jaw geometry, per-strand leading/lagging
colors, `clamp_back_width` — Pol I's own lobe sizing derives off this rather
than an independent constant), Ligase (base_size/pinch_ratio/rest+pulse
color/travel+hold+seal durations), Primase (blip_size/pulse/RNA halo colors/
fade+capture durations — note `primase_capture_duration` is DEAD, replaced
by pacing off `helicase_mgr.step_duration`), RNA Primer
(`primer_length_ratio`, `rna_base_color_*` ×4, `rna_backbone_color`,
`rna_backbone_line_width`, `rna_bond_mark_width`), Pol I (lobe_size_ratio/
lobe_gap/pol_lobe_height_ratio/pulse_scale_ratio/exo+pol colors/offstage_drop/
travel+leave durations — note `pol1_step_duration` is DEAD, same reason as
primase's dead field above; both fixed fields safe to remove if still present)

---

## Biological Model Reference

MolSim follows the E. coli replication model. Didactic accuracy over exhaustive
precision — short sequences, simplified geometry.

- DNA Pol III synthesizes only 5'→3'
- Leading strand: continuous, follows fork direction (left→right)
- Lagging strand: discontinuous Okazaki fragments via trombone loop model
- Each Okazaki fragment requires an RNA primer (primase)
- Pol I performs nick-translation to remove each fragment's RNA primer —
  simultaneous 5'→3' exonuclease + 5'→3' polymerase at matched rates, one
  fragment behind Pol III's own progress (needs the NEXT fragment's worth
  of freshly-made DNA to extend into as it displaces the old primer — see
  OkazakiMaturationDesign.md for why that specific lag, not primer
  placement time, is the real trigger). RNase H's real role in assisting
  this isn't separately modeled — didactic scope, Pol I alone stands in
  for the whole removal.
- Ligase seals the final phosphodiester bond once a fragment's primer is
  fully replaced with DNA — cannot act on RNA-DNA junctions, only DNA-DNA
- β-clamp (sliding clamp) increases polymerase processivity
- τ (tau) body connects helicase + both polymerases + clamp loader in replisome
- Transcription errors: RNA Pol has no proofreading (~1 error per 10⁴ bases)
- Redundancy of transcription buffers errors — many mRNA copies per gene
