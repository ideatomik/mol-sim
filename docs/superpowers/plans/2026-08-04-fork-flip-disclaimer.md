# Fork-Flip Hover Disclaimer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hover-triggered on-screen disclaimer to every self-paired residue currently rendered via the fork-flip mirror (`RiboseDeriver.reflect_about_backbone_axis()`), closing the "MUST pair this with the on-screen didactic disclaimer" requirement its own doc comment states and the design doc's fork-flip entry requires before this can ship.

**Architecture:** `molecule_structure_renderer.gd` gains a `_mirrored_residue_layout` array, populated inline at the exact call site of the existing mirror branch in `_rebuild_layout()` (so a residue cannot be mirrored without becoming hoverable), a per-frame hover check in `_process()`, and a drawn tooltip in `_draw()` — following this file's existing immediate-mode `draw_string()` convention for atom labels, no new nodes, no picking framework.

**Tech Stack:** GDScript (Godot 4.6). No Python harness — this is interaction/rendering, not geometry math (this project's `diagnosis/*.py` convention is for the latter only).

## Global Constraints

- Godot executable: `C:\Godot\Godot_v4.6.3-stable_win64_console.exe` (project root for this work: `E:\Godot Projects\MolSim\mol-sim\.claude\worktrees\self-paired-chain-fix`).
- No automated test framework exists in this project. Verification is live: F9 geometry dumps (`user://geometry_dump.txt`, on Windows `C:\Users\dhpcs\AppData\Roaming\Godot\app_userdata\MolSim\geometry_dump.txt`) plus manual interaction in the test chamber (`scenes/test_chamber.tscn`, this worktree only) or the real game, run in the Godot editor.
- Disclaimer text, verbatim, from `docs/MolecularStructureDesign.md`'s already-recorded framing: `in 2D molecular representations this rotation doesn't really exist, but for didactic reasons, we're showing you this way.`
- Trigger is hover-only (not click, not a persistent banner) — decided in `docs/superpowers/specs/2026-08-04-fork-flip-disclaimer-design.md`.
- Animation (the alternative to today's instant flip) is explicitly out of scope for this plan — a separate, independently-schedulable follow-up per the design doc.
- Registration into the new hover-tracking array MUST happen at the same call site as the mirror transform itself (`molecule_structure_renderer.gd`'s `self_paired_sign < 0` branch, currently around line 534), not as a separate opt-in step — this is what makes it structurally impossible to mirror a residue without it becoming hoverable.
- `_rebuild_layout()` already early-returns before touching any layout array when `not _active` (skeletal zoom tier gate) — the new array inherits this for free; do not add separate zoom gating.
- Design doc of record: `docs/superpowers/specs/2026-08-04-fork-flip-disclaimer-design.md`. Parent design-intent entry: `docs/MolecularStructureDesign.md`, "Self-paired fork-flip as a deliberate, labeled 2D mirror" (2026-08-04).

---

## File Structure

- **Modify:** `scripts/molecule_structure_renderer.gd` — new `_mirrored_residue_layout: Array[Dictionary]` member and `MIRRORED_RESIDUE_TOOLTIP_TEXT` constant (Task 1); populated in `_rebuild_layout()` (Task 1); new `_hovered_mirrored_key: String` member, computed in `_process()` (Task 2); tooltip drawn in `_draw()` (Task 3).

---

## Task 1: Track mirrored residues during layout

**Files:**
- Modify: `scripts/molecule_structure_renderer.gd`

**Interfaces:**
- Produces: `_mirrored_residue_layout: Array[Dictionary]`, each entry `{world_pos: Vector2, radius: float, key: String}` — consumed by Task 2's hover check.
- Produces: `const MIRRORED_RESIDUE_TOOLTIP_TEXT: String` — consumed by Task 3's draw call.

- [ ] **Step 1: Add the tooltip text constant and the new layout array**

In `scripts/molecule_structure_renderer.gd`, near the other `Array[Dictionary]` layout members (right after `_h_bond_layout` at line 55), add:

```gdscript
## {world_pos: Vector2, radius: float, key: String} — one entry per
## residue currently rendered via RiboseDeriver.reflect_about_backbone_axis()
## (the fork-flip mirror) this frame. Populated inline at the exact call
## site of that mirror in _rebuild_layout() — never a separate opt-in step
## — so a residue cannot be mirrored without becoming hoverable, closing
## the disclaimer requirement in reflect_about_backbone_axis()'s own doc
## comment. Read by _process() to compute _hovered_mirrored_key, and
## indirectly by _draw() through that. Inherits the _active zoom-tier gate
## for free: _rebuild_layout() early-returns before this is ever touched
## while inactive.
var _mirrored_residue_layout: Array[Dictionary] = []
```

Near the top of the file, after the `class_name`/`extends` lines and before the first `var` block (or alongside other `const` declarations such as `OPERATOR_PATH` at line 130), add:

```gdscript
## Verbatim project framing (docs/MolecularStructureDesign.md, "Self-paired
## fork-flip as a deliberate, labeled 2D mirror") for the hover disclaimer
## shown while a residue is rendered via RiboseDeriver.
## reflect_about_backbone_axis(). Never paraphrase this string — it's the
## project's own already-agreed wording.
const MIRRORED_RESIDUE_TOOLTIP_TEXT: String = "in 2D molecular representations this rotation doesn't really exist, but for didactic reasons, we're showing you this way."
```

- [ ] **Step 2: Clear the array each frame**

In `_rebuild_layout()`, find the existing array-clear block (`scripts/molecule_structure_renderer.gd:371-374`):

```gdscript
	_atom_layout.clear()
	_bond_layout.clear()
	_h_bond_layout.clear()
	_active_slots.clear()
	if not _active:
		return
```

Change to:

```gdscript
	_atom_layout.clear()
	_bond_layout.clear()
	_h_bond_layout.clear()
	_active_slots.clear()
	_mirrored_residue_layout.clear()
	if not _active:
		return
```

- [ ] **Step 3: Track each residue's max atom extent from its anchor**

In `_rebuild_layout()`'s per-entry loop, find the atom-building loop (`scripts/molecule_structure_renderer.gd:581-591`):

```gdscript
		for atom in topology.atoms:
			if not local_positions.has(atom.id):
				continue
			var world: Vector2 = world_pos + (local_positions[atom.id] - anchor_offset)
			_atom_layout.append({
				position = world,
				element = atom.element,
				label = _atom_display_label(atom.role, atom.element),
				atom_id = atom.id,
				nucleotide_slot = entry.slot,
			})
```

Change to:

```gdscript
		var residue_max_extent: float = 0.0
		for atom in topology.atoms:
			if not local_positions.has(atom.id):
				continue
			var local_offset: Vector2 = local_positions[atom.id] - anchor_offset
			residue_max_extent = max(residue_max_extent, local_offset.length())
			var world: Vector2 = world_pos + local_offset
			_atom_layout.append({
				position = world,
				element = atom.element,
				label = _atom_display_label(atom.role, atom.element),
				atom_id = atom.id,
				nucleotide_slot = entry.slot,
			})
```

- [ ] **Step 4: Register mirrored residues right after the extent is known**

Immediately after the atom-building loop from Step 3 (right after its closing, before the bond-building loop that starts `for bond in topology.bonds:` at `scripts/molecule_structure_renderer.gd:593`), add:

```gdscript
		if is_self_paired_template and self_paired_sign < 0.0:
			_mirrored_residue_layout.append({
				world_pos = world_pos,
				radius = residue_max_extent + tm.molecular_atom_radius,
				key = key,
			})
```

This reuses `is_self_paired_template` and `self_paired_sign`, both already in scope from the mirror branch earlier in the same loop iteration (`scripts/molecule_structure_renderer.gd:522,533-539`), and `key`, already in scope from line 432.

- [ ] **Step 5: Confirm the file compiles**

Open the project in the Godot editor (`C:\Godot\Godot_v4.6.3-stable_win64_console.exe --path "E:\Godot Projects\MolSim\mol-sim\.claude\worktrees\self-paired-chain-fix"`) and check the Output/Errors panel for `molecule_structure_renderer.gd` parse errors. Expected: none.

- [ ] **Step 6: Commit**

```bash
git add scripts/molecule_structure_renderer.gd
git commit -m "$(cat <<'EOF'
Track mirrored residues for the fork-flip hover disclaimer

Registers into _mirrored_residue_layout at the exact call site of
reflect_about_backbone_axis(), so a residue cannot be rendered via the
fork-flip mirror without becoming hoverable in the next task.
EOF
)"
```

---

## Task 2: Compute hover state each frame

**Files:**
- Modify: `scripts/molecule_structure_renderer.gd`

**Interfaces:**
- Consumes: `_mirrored_residue_layout: Array[Dictionary]` from Task 1.
- Produces: `_hovered_mirrored_key: String` (empty when nothing is hovered) — consumed by Task 3's `_draw()`.

- [ ] **Step 1: Add the hover-state member**

Next to `_mirrored_residue_layout` (added in Task 1, Step 1), add:

```gdscript
## Key ("strand:slot") of the mirrored residue currently under the mouse,
## or "" if none. Recomputed once per frame in _process(), read by _draw()
## to decide whether to draw the fork-flip disclaimer tooltip.
var _hovered_mirrored_key: String = ""
```

- [ ] **Step 2: Compute it in `_process()`**

Find `_process()` (`scripts/molecule_structure_renderer.gd:326-331`):

```gdscript
func _process(_delta: float) -> void:
	if replication_mgr == null or zoom_mgr == null or tm == null:
		return
	_active = _compute_active()
	_rebuild_layout()
	queue_redraw()
```

Change to:

```gdscript
func _process(_delta: float) -> void:
	if replication_mgr == null or zoom_mgr == null or tm == null:
		return
	_active = _compute_active()
	_rebuild_layout()
	_hovered_mirrored_key = _compute_hovered_mirrored_key()
	queue_redraw()
```

- [ ] **Step 3: Add the helper function**

Add this new function near `_compute_active()` (`scripts/molecule_structure_renderer.gd:344-350`):

```gdscript
## Nearest mirrored residue whose radius contains the mouse, or "" if none
## qualify. _mirrored_residue_layout is already empty whenever _active is
## false (Task 1) or no residue is currently fork-flip-mirrored, so no
## extra gating is needed here.
func _compute_hovered_mirrored_key() -> String:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var best_key: String = ""
	var best_dist: float = INF
	for m in _mirrored_residue_layout:
		var dist: float = mouse_pos.distance_to(m.world_pos)
		if dist <= m.radius and dist < best_dist:
			best_dist = dist
			best_key = m.key
	return best_key
```

- [ ] **Step 4: Confirm the file compiles**

Same check as Task 1 Step 5. Expected: no parse errors.

- [ ] **Step 5: Commit**

```bash
git add scripts/molecule_structure_renderer.gd
git commit -m "$(cat <<'EOF'
Compute per-frame hover state for mirrored residues

Nearest-within-radius mirrored residue under the mouse each frame, or
empty when none qualify. Feeds the tooltip draw in the next task.
EOF
)"
```

---

## Task 3: Draw the disclaimer tooltip

**Files:**
- Modify: `scripts/molecule_structure_renderer.gd`

**Interfaces:**
- Consumes: `_hovered_mirrored_key: String` and `_mirrored_residue_layout: Array[Dictionary]` from Task 2/1; `MIRRORED_RESIDUE_TOOLTIP_TEXT` from Task 1.

- [ ] **Step 1: Add the draw call**

At the end of `_draw()` (`scripts/molecule_structure_renderer.gd:871-940`), after the atom-drawing loop (after line 940, the final `draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)`), add:

```gdscript

	# Fork-flip hover disclaimer (docs/superpowers/specs/
	# 2026-08-04-fork-flip-disclaimer-design.md): drawn last so it renders
	# on top of atoms/bonds/labels. Hardcoded background/text colors —
	# no established draw_rect() convention or theme fields exist in this
	# file to reuse, and this is a small, self-contained overlay, not
	# something worth a new theme_manager.gd surface for.
	if _hovered_mirrored_key != "":
		var hovered_world_pos: Vector2 = Vector2.ZERO
		for m in _mirrored_residue_layout:
			if m.key == _hovered_mirrored_key:
				hovered_world_pos = m.world_pos
				break
		var tooltip_font: Font = tm.base_label_font if tm.base_label_font != null else ThemeDB.fallback_font
		if tooltip_font != null:
			var tooltip_font_size: int = tm.molecular_atom_label_font_size
			var text_size: Vector2 = tooltip_font.get_string_size(MIRRORED_RESIDUE_TOOLTIP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size)
			var padding: Vector2 = Vector2(6.0, 4.0)
			var tooltip_offset: Vector2 = Vector2(-text_size.x / 2.0, -tm.molecular_atom_radius * 4.0)
			var box_pos: Vector2 = hovered_world_pos + tooltip_offset - padding
			var box_size: Vector2 = text_size + padding * 2.0
			draw_rect(Rect2(box_pos, box_size), Color(0.0, 0.0, 0.0, 0.75), true)
			var text_pos: Vector2 = hovered_world_pos + tooltip_offset + Vector2(0.0, tooltip_font.get_ascent(tooltip_font_size))
			draw_string(tooltip_font, text_pos, MIRRORED_RESIDUE_TOOLTIP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size, Color.WHITE)
```

- [ ] **Step 2: Confirm the file compiles**

Same check as Task 1 Step 5. Expected: no parse errors.

- [ ] **Step 3: Live check — tooltip appears and disappears correctly**

Open the test chamber (`scenes/test_chamber.tscn`) in the Godot editor and run it (F6, or F5 if it's the configured main scene). Zoom into free-camera skeletal mode over a self-paired region until template residues render as ribose rings (past `molecular_zoom_enter_threshold`).

- Hover the mouse over a `template_bottom` residue in a self-paired stretch (the `direction_sign < 0` fork-flip residue). Expected: a dark tooltip box appears above it reading exactly `in 2D molecular representations this rotation doesn't really exist, but for didactic reasons, we're showing you this way.`
- Move the mouse away. Expected: tooltip disappears.
- Hover a `template_top` residue in the same self-paired region (still bake-path, not mirrored). Expected: no tooltip.
- Hover a leading/lagging residue. Expected: no tooltip.

- [ ] **Step 4: Live check — F9 dump unaffected**

Press F9 while the scene is running. Expected: `user://geometry_dump.txt` (`C:\Users\dhpcs\AppData\Roaming\Godot\app_userdata\MolSim\geometry_dump.txt` on Windows) still reflects the mirrored geometry correctly — this task only adds a draw-time overlay, it does not touch `molecule_geometry_diagnostics.gd` or any geometry computation.

- [ ] **Step 5: Commit**

```bash
git add scripts/molecule_structure_renderer.gd
git commit -m "$(cat <<'EOF'
Draw the fork-flip hover disclaimer tooltip

Closes the on-screen disclaimer requirement from RiboseDeriver.
reflect_about_backbone_axis()'s doc comment and the design doc's
fork-flip entry: a residue rendered via the mirror now always shows
the project's stated didactic framing on hover.
EOF
)"
```
