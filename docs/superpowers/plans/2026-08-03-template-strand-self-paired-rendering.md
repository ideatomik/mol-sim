# Template-Strand Self-Paired Rendering Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three visual defects in template-strand self-paired molecular rendering (backbone overlap, frame-to-frame flicker, unpaired first base pair) by replacing the unstable 72-step clearance search with grounded, provably chirality-safe geometry, and extract the F9 diagnostic-dump subsystem out of the main renderer file.

**Architecture:** `scripts/ribose_deriver.gd` gains a new self-paired ring construction (1b: a fixed global rotation, chosen the same deterministic way 1a would, plus a real second degree of freedom — a bond-length-preserving "elbow" linkage between C2' and O4' that lets C3'/C4' flex within Gelbin et al.-sourced real bond-angle tolerance) replacing the deleted search. `scripts/molecule_structure_renderer.gd` shrinks by ~670 lines as its diagnostic-dump half moves to a new `scripts/molecule_geometry_diagnostics.gd`. A standalone Python harness in `diagnosis/` (matching this project's existing verification convention — see `diagnosis/diag_anchor_preserving.py`) proves the construction's chirality safety and tolerance compliance analytically before any GDScript is written, and before any screenshot is trusted.

**Tech Stack:** GDScript (Godot 4.6), Python 3 (analytic verification scripts only, `diagnosis/` — never shipped/imported by the game).

## Global Constraints

- No automated test framework exists in this project (no GUT, no pytest-equivalent for GDScript). Verification is: (a) standalone Python scripts in `diagnosis/` that mirror the GDScript math for analytic proofs, matching the existing house convention, and (b) live F9 geometry dumps (`user://geometry_dump.txt`, on Windows `C:\Users\dhpcs\AppData\Roaming\Godot\app_userdata\MolSim\geometry_dump.txt`) plus screenshots, run in the Godot editor.
- Godot executable for any headless/editor runs: `C:\Godot\Godot_v4.6.3-stable_win64_console.exe` (project root `E:\Godot Projects\MolSim\mol-sim`).
- Collision/clearance threshold: 12.0 world units (`2 × molecular_atom_radius`, `molecular_atom_radius = 6.0` in `theme_manager.gd`).
- Chemical tolerance bound (Gelbin, Schneider, Clowney, Hsieh, Olson, Berman (1996), JACS 118:519-529, Table 4, deoxyribose, N=47): ring-internal angles bounded ±2σ **as a delta from this project's existing idealized-regular-pentagon baseline (108° at every vertex)**, not as an absolute target against Gelbin's real mean — confirmed necessary because the existing regular-pentagon baseline (already shipped, confirmed correct for leading/lagging) sits ~4.8σ from Gelbin's absolute C2'-C3'-C4' mean, so an absolute-target check would reject the project's own correct baseline. Angles and σ: C2'-C3'-C4' (at C3') 103.2°±1.0°, C3'-C4'-O4' (at C4') 105.6°±1.0°, C4'-O4'-C1' (at O4') 109.7°±1.4°. Exocyclic angles bounded the same way but are not independently flexed by this plan's construction (see Task 4): C5'-C4'-C3' 114.7°±1.5°, C5'-C4'-O4' 109.4°±1.6°, C4'-C3'-O3' 110.3°±2.2°, C2'-C3'-O3' 110.6°±2.7°.
- Chirality safety: any candidate construction must be provably a proper (determinant +1) transform of the canonical D-ribose vertex ordering — verified via a signed-area (shoelace) check on the fixed atom-walk order `C1'→C2'→C3'→C4'→O4'`, never assumed from a screenshot.
- Stop condition: if no construction satisfies (a) the collision-clearance target, (b) the chirality/orientation proof, and (c) the tolerance bound simultaneously, ship 1a alone (closed-form bulge-away-from-partner rotation) with the collision explicitly documented as open — never silently fall back to the deleted search.
- Design doc of record: `docs/superpowers/specs/2026-08-03-template-strand-self-paired-rendering-design.md`. Prior investigation history: `docs/MolecularStructure_BasePairExpansion.md` (Bug D through W).

---

## File Structure

- **Create:** `scripts/molecule_geometry_diagnostics.gd` — the extracted F9 diagnostic-dump subsystem (pure move from `molecule_structure_renderer.gd`, no behavior change).
- **Modify:** `scripts/molecule_structure_renderer.gd` — loses its diagnostic half (Task 1); later has its self-paired rotation call site replaced (Task 6); later gets the `_pair_for_slot()` boundary fix (Task 8).
- **Modify:** `scripts/ribose_deriver.gd` — loses `resolve_self_paired_ring_rotation()`, `debug_self_paired_candidates()`, the four `SELF_PAIRED_*` constants, and the dead `apply_partner_flip()` (Task 3, Task 6); gains the new construction function (Task 6).
- **Create:** `diagnosis/diag_self_paired_construction.py` — analytic verification harness (Task 4), following `diagnosis/diag_anchor_preserving.py`'s established convention: plain-Python reimplementation of the relevant GDScript math, run standalone, printing pass/fail booleans.

---

## Task 1: Extract the F9 diagnostic-dump subsystem into its own file

**Files:**
- Create: `scripts/molecule_geometry_diagnostics.gd`
- Modify: `scripts/molecule_structure_renderer.gd:777-1443` (the block being moved), `scripts/molecule_structure_renderer.gd:316-319` (the F9 key-listener call site)

**Interfaces:**
- Produces: `MoleculeGeometryDiagnostics.dump(renderer: Node2D, replication_mgr: Node, template_sim: Node, fold_cache: Dictionary, operators: Array[ReactionOperator]) -> void` — the new file's single public entry point, called from the renderer's existing F9 key-listener. Everything else in the new file (`_dump_pairing`, `_scan_pairing_for_same_letter`, `_dump_self_paired_boundary_trace`, `_derive_full_residue`, `_write_residue_block`, `_max_pairwise_distance`, `_centroid`, `_closest_world_distance`, plus the `_DIAG_*` constants) stays private to it, called only from within `dump()`.
- Consumes (from the renderer, passed as parameters — the new file never looks anything up cross-tree): `renderer._molecular_render_pos()`, `renderer._pair_for_slot()`, `renderer._strand_direction_sign()`, `renderer._slot_spacing()`, `renderer._dna_ribbons_gap()` (these five stay in the renderer since `_slot_spacing`/`_dna_ribbons_gap` are also used by the live render path — call them via the passed-in `renderer` reference, e.g. `renderer._slot_spacing()`).

- [ ] **Step 1: Confirm the exact extraction boundary**

Run:
```
grep -n "TEMPORARY DIAGNOSTIC DUMP\|^func _slot_spacing\|^func _closest_world_distance" "E:/Godot Projects/MolSim/mol-sim/scripts/molecule_structure_renderer.gd"
```
Expected output (confirm these line numbers before cutting anything — if they've drifted since this plan was written, use the grep output instead):
```
778:# TEMPORARY DIAGNOSTIC DUMP (docs/MolecularStructure_BasePairExpansion.md,
1435:func _closest_world_distance(points, target: Vector2) -> float:
1445:func _slot_spacing() -> float:
```
The block to move is lines 777 (the `# ====...` separator immediately above line 778) through the end of `_closest_world_distance()` (the blank line immediately before `func _slot_spacing()` at line 1445 — i.e. everything up to but not including line 1445).

- [ ] **Step 2: Create the new file with the moved block**

Create `scripts/molecule_geometry_diagnostics.gd` starting with:

```gdscript
class_name MoleculeGeometryDiagnostics
extends RefCounted

# ==========================================
# MOLECULE GEOMETRY DIAGNOSTICS
# Extracted from molecule_structure_renderer.gd (docs/superpowers/plans/
# 2026-08-03-template-strand-self-paired-rendering.md, Task 1) — pure move,
# no behavior change. The F9 live geometry dump: pairing scan, same-letter
# scan, full-residue derivation for diagnostics, self-paired boundary
# rotation trace. See molecule_structure_renderer.gd's F9 key-listener
# (_process()) for the call site.
# ==========================================
```

Then paste the exact content of the moved block (lines 777-1444 of the original file, per Step 1) below that header, with these mechanical adjustments:

1. Wrap the pasted content's entry point — rename `func _dump_geometry_diagnostic() -> void:` to `static func dump(renderer: Node2D, replication_mgr: Node, template_sim: Node, fold_cache: Dictionary, operators: Array[ReactionOperator]) -> void:` and make every other pasted function `static func` (all of them are free of instance state already — they only ever reference `self`-less locals and parameters, confirmed by reading the block: `_dump_pairing`, `_scan_pairing_for_same_letter`, `_dump_self_paired_boundary_trace`, `_derive_full_residue`, `_write_residue_block`, `_max_pairwise_distance`, `_centroid`, `_closest_world_distance` all become `static func`).
2. Every reference inside the pasted block to `tm`, `_fold_cache`, `_operators`, `_molecular_render_pos()`, `_pair_for_slot()`, `_strand_direction_sign()`, `_slot_spacing()`, `_dna_ribbons_gap()` becomes `renderer.tm`, `fold_cache`, `operators`, `renderer._molecular_render_pos()`, `renderer._pair_for_slot()`, `renderer._strand_direction_sign()`, `renderer._slot_spacing()`, `renderer._dna_ribbons_gap()` respectively.
3. Every reference to `replication_mgr` / `template_sim` inside the pasted block already matches the new parameter names — no change needed there.

- [ ] **Step 3: Update the renderer's call site**

In `scripts/molecule_structure_renderer.gd`, delete lines 777-1444 (the moved block) entirely, and change the F9 key-listener in `_process()` (around line 317):

```gdscript
	var key_down: bool = Input.is_key_pressed(KEY_F9)
	if key_down and not _debug_dump_key_was_down:
		MoleculeGeometryDiagnostics.dump(self, replication_mgr, template_sim, _fold_cache, _operators)
	_debug_dump_key_was_down = key_down
```

(This replaces the old `_dump_geometry_diagnostic()` call — same line, same debounce logic, unchanged.)

- [ ] **Step 4: Confirm the file compiles**

Open the project in the Godot editor (`C:\Godot\Godot_v4.6.3-stable_win64_console.exe --editor --path "E:\Godot Projects\MolSim\mol-sim"`) and check the Errors panel / Output panel for parse errors in either file. Fix any reference the mechanical rename in Step 2 missed (search both files for `_dump_geometry_diagnostic`, `_dump_pairing`, `_scan_pairing_for_same_letter`, `_dump_self_paired_boundary_trace`, `_derive_full_residue`, `_write_residue_block`, `_max_pairwise_distance`, `_centroid`, `_closest_world_distance` to confirm no stale references remain in `molecule_structure_renderer.gd`).

- [ ] **Step 5: Commit**

```bash
git add scripts/molecule_geometry_diagnostics.gd scripts/molecule_structure_renderer.gd
git commit -m "Extract F9 diagnostic dump into molecule_geometry_diagnostics.gd

Pure move, no behavior change -- shrinks molecule_structure_renderer.gd
by ~670 lines ahead of the self-paired rotation fix."
```

---

## Task 2: Verify the extraction produced no behavior change

**Files:** none (verification only — run the game, no edits)

**Interfaces:** none

- [ ] **Step 1: Load a fixed, reproducible sequence**

Launch the game (`C:\Godot\Godot_v4.6.3-stable_win64_console.exe --path "E:\Godot Projects\MolSim\mol-sim"`), open the sequence-load popup, load any fixed test sequence (same one used for prior investigation is fine — any sequence works as long as the exact same one is used for both dumps in this task), and zoom the free camera into molecular/self-paired range (deep zoom, template strands visible, before any enzyme activity) so the self-paired render mode is active.

- [ ] **Step 2: Pause the scene and capture dump A**

Pause the game (so the template curve stops moving between the two presses — this task is checking the move didn't change output, not re-checking the flicker fix). Press F9 once. Copy `C:\Users\dhpcs\AppData\Roaming\Godot\app_userdata\MolSim\geometry_dump.txt`'s last dump block (from its `=== GEOMETRY DIAGNOSTIC DUMP` header to its `=== END DUMP ===` line) to a temp file `dump_a.txt`.

- [ ] **Step 3: Capture dump B**

Without unpausing, without changing camera or sequence, press F9 again. Copy the new last dump block to `dump_b.txt`.

- [ ] **Step 4: Diff, ignoring only the timestamp line**

```bash
diff <(grep -v '^=== GEOMETRY DIAGNOSTIC DUMP' dump_a.txt) <(grep -v '^=== GEOMETRY DIAGNOSTIC DUMP' dump_b.txt)
```
Expected: no output (identical). Since the scene is paused and nothing moved between presses, dump A and dump B being identical confirms the extraction is behavior-preserving (this is the pre-move baseline — Task 1 was a pure move, so this really just confirms F9 still works end-to-end after the split; it is not yet testing the rotation fix, which doesn't exist until Task 6).

If they differ anywhere other than the timestamp, stop and diagnose — Task 1's extraction introduced a behavior change and must be fixed before continuing.

- [ ] **Step 5: No commit** (verification-only task, nothing to commit)

---

## Task 3: Delete the dead `apply_partner_flip()` function

**Files:**
- Modify: `scripts/ribose_deriver.gd:575-582` (function body), plus its doc comment block above it (starting at the `## Bug L fix` comment, roughly lines 542-574)

**Interfaces:**
- Removes: `RiboseDeriver.apply_partner_flip()`. No consumers exist anywhere in the codebase (confirmed via `grep -rn "apply_partner_flip" scripts/` returning only the definition itself) — this step has no interface impact on any other task.

- [ ] **Step 1: Confirm no call sites exist**

```bash
grep -rn "apply_partner_flip" "E:/Godot Projects/MolSim/mol-sim/scripts/"
```
Expected: exactly one match, the `static func apply_partner_flip(...)` definition line itself in `ribose_deriver.gd`. If any other match appears, stop — the function is not actually dead and this task does not apply.

- [ ] **Step 2: Delete the function and its doc comment**

In `scripts/ribose_deriver.gd`, delete the entire `## Bug L fix (docs/MolecularStructure_BasePairExpansion.md): ...` comment block and the `static func apply_partner_flip(...)` function it documents (the comment block immediately precedes the function with no other code between them — delete both together, nothing in between to preserve).

- [ ] **Step 3: Confirm the file still compiles**

Open the project in the Godot editor and check the Output panel for parse errors in `ribose_deriver.gd`.

- [ ] **Step 4: Commit**

```bash
git add scripts/ribose_deriver.gd
git commit -m "Delete dead RiboseDeriver.apply_partner_flip()

No call sites anywhere in the codebase -- superseded by the search-based
self-paired rotation (Bug V/W) before this fix's design work started."
```

---

## Task 4: Build and run the analytic verification harness for the 1b construction

**Files:**
- Create: `diagnosis/diag_self_paired_construction.py`

**Interfaces:**
- Produces: printed pass/fail results this task's own steps read directly — this task does not hand off a function signature to later tasks (Task 5 re-implements the validated math in GDScript by hand, checked against this script's printed numbers, matching this project's existing `diagnosis/*.py` convention of "prove it in Python first, port by hand, verify the port reproduces the same numbers").
- Consumes: real fixture vectors gathered live during this project's brainstorm (recorded below — no need to re-run the game to get them, though Step 1 tells you how to re-verify them if desired).

- [ ] **Step 1: Write the harness's geometry primitives and fixture data**

Create `diagnosis/diag_self_paired_construction.py`:

```python
import math

def sub(a, b): return (a[0]-b[0], a[1]-b[1])
def add(a, b): return (a[0]+b[0], a[1]+b[1])
def scale(a, s): return (a[0]*s, a[1]*s)
def length(a): return math.hypot(a[0], a[1])
def normalized(a):
    l = length(a)
    return (0.0, 0.0) if l == 0 else (a[0]/l, a[1]/l)
def orthogonal(a): return (a[1], -a[0])
def vangle(a): return math.atan2(a[1], a[0])
def dot(a, b): return a[0]*b[0] + a[1]*b[1]
def rotated(a, theta):
    c, s = math.cos(theta), math.sin(theta)
    return (a[0]*c - a[1]*s, a[0]*s + a[1]*c)

TAU = 2 * math.pi
BOND_LENGTH = 10.8  # today's live dump: bond_length = molecular_ring_bond_length_ratio * nucleotide_slot_spacing = 0.2 * 54.0
COLLISION_THRESHOLD = 12.0  # 2 * molecular_atom_radius (6.0, theme_manager.gd)

RING_ROLE_SUFFIXES = ["c1_prime", "c2_prime", "c3_prime", "c4_prime", "o4_prime"]

def derive_regular_ring(bond_length, start_angle=-math.pi/2.0):
    """Matches nitrogen_base_deriver.gd's derive_regular_ring() exactly for n=5."""
    n = 5
    R = bond_length / (2.0 * math.sin(math.pi / n))
    step = TAU / n
    return {suf: (math.cos(start_angle + i*step) * R, math.sin(start_angle + i*step) * R)
            for i, suf in enumerate(RING_ROLE_SUFFIXES)}

# ---- Real fixture data, gathered live via F9 dump during this project's
# brainstorm session (2026-08-03), template_top slot 0, self-paired,
# BEFORE any rotation is applied (i.e. these are inputs to the
# construction, not its output) ----
FIXTURE_TOWARD_NEXT = (54.0, 0.394745)       # template_top slot0 -> slot1 (real same-strand neighbor)
FIXTURE_TOWARD_PREVIOUS = (0.0, 0.0)          # no real neighbor at slot -1 (strand boundary)
FIXTURE_PAIRING_DIRECTION = (0.0, 160.0)      # toward template_bottom slot0 (real partner)

# Mirror-image fixture: template_bottom slot 0 (opposite boundary, opposite sign)
FIXTURE_B_TOWARD_NEXT = (0.0, 0.0)
FIXTURE_B_TOWARD_PREVIOUS = (54.0, 0.394745)
FIXTURE_B_PAIRING_DIRECTION = (0.0, -160.0)

# Interior-residue fixture (both real same-strand neighbors present):
# template_top slot 2 from the same live dump.
FIXTURE_C_TOWARD_NEXT = (54.0, -0.0862)       # slot2 -> slot3 (derived: world_pos slot3.x - slot2.x, slot3.y - slot2.y from the dump = (378.0-324.0, 280.8420-280.2751))
FIXTURE_C_TOWARD_PREVIOUS = (-54.0, 0.0862)   # slot2 -> slot1 (negation, since dump shows near-collinear real neighbors)
FIXTURE_C_PAIRING_DIRECTION = (0.0, 160.0)

print("=== Fixture sanity check ===")
print("toward_next fixture A:", FIXTURE_TOWARD_NEXT, "length:", length(FIXTURE_TOWARD_NEXT))
print("pairing_direction fixture A:", FIXTURE_PAIRING_DIRECTION, "length:", length(FIXTURE_PAIRING_DIRECTION))
```

- [ ] **Step 2: Run it and confirm the sanity check**

```bash
cd "E:/Godot Projects/MolSim/mol-sim" && python diagnosis/diag_self_paired_construction.py
```
Expected: prints the two fixture lines with lengths ≈54.001 and 160.0. This confirms the fixture transcription from the live dump (recorded in the design doc's F9 capture, PAIR 1 / PAIR 3 blocks) is correct before building anything on top of it.

- [ ] **Step 3: Add the Gelbin tolerance table and the delta-from-baseline checker**

Append to `diagnosis/diag_self_paired_construction.py`:

```python
# ---- Gelbin et al. (1996), JACS 118:519-529, Table 4, deoxyribose, N=47.
# Ring-internal angles only (the three this construction's elbow DOF can
# move) -- exocyclic angles are not independently flexed by this
# construction (see Task 4 Step 5's own note) so are not checked here.
# Baseline = this project's existing idealized regular pentagon, 108.0 at
# every internal vertex -- the bound is a DELTA from that baseline, not an
# absolute target against Gelbin's real mean (see this plan's Global
# Constraints section for why an absolute-target check would reject the
# project's own already-correct leading/lagging baseline).
REGULAR_PENTAGON_INTERIOR_DEG = 108.0
GELBIN_RING_INTERNAL = {
    # vertex : (gelbin_mean_deg, gelbin_sigma_deg)
    "c3_prime": (103.2, 1.0),   # angle C2'-C3'-C4', at C3'
    "c4_prime": (105.6, 1.0),   # angle C3'-C4'-O4', at C4'
    "o4_prime": (109.7, 1.4),   # angle C4'-O4'-C1', at O4'
}

def angle_at(prev_pt, vertex_pt, next_pt):
    """Interior angle at vertex_pt, in degrees, given its two ring neighbors."""
    v1 = normalized(sub(prev_pt, vertex_pt))
    v2 = normalized(sub(next_pt, vertex_pt))
    return math.degrees(math.acos(max(-1.0, min(1.0, dot(v1, v2)))))

def within_gelbin_delta_tolerance(vertex_suffix, measured_deg, sigma_multiple=2.0):
    _, sigma = GELBIN_RING_INTERNAL[vertex_suffix]
    delta = abs(measured_deg - REGULAR_PENTAGON_INTERIOR_DEG)
    limit = sigma_multiple * sigma
    return delta <= limit, delta, limit
```

- [ ] **Step 4: Add the signed-area orientation-preservation check**

Append:

```python
def signed_area(points_in_order):
    """Shoelace formula. points_in_order must be the fixed atom-walk order
    (C1'->C2'->C3'->C4'->O4') -- sign flips iff the construction produced
    a mirror (L-ribose) vertex ordering, regardless of how plausible the
    shape looks."""
    n = len(points_in_order)
    s = 0.0
    for i in range(n):
        x1, y1 = points_in_order[i]
        x2, y2 = points_in_order[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return 0.5 * s

canonical_ring = derive_regular_ring(BOND_LENGTH)
canonical_order = [canonical_ring[s] for s in RING_ROLE_SUFFIXES]
canonical_sign = signed_area(canonical_order) > 0.0
print("\n=== Canonical D-ribose signed area (reference sign) ===")
print("signed area:", signed_area(canonical_order), "positive:", canonical_sign)
```

- [ ] **Step 5: Run it, confirm the canonical reference prints a nonzero signed area**

```bash
python diagnosis/diag_self_paired_construction.py
```
Expected: `signed area: <nonzero number> positive: True` (or `False` — either is fine, this just establishes what "correct" means; what matters for later steps is every real candidate matching this sign, whichever it is).

- [ ] **Step 6: Implement the elbow-linkage construction**

Append the actual 1b mechanism: a fixed global rotation (same deterministic bulge-away-from-partner test as 1a) establishes baseline C1'/C2'/O4' positions, then C3'/C4' are re-derived as a bond-length-preserving 3-link chain between the now-fixed C2' and O4' (a 1-DOF "elbow" mechanism — the genuine second degree of freedom this construction adds beyond 1a's single rotation angle), swept over its Gelbin-bounded window to maximize clearance from the substituent chain.

```python
def bulge_away_rotation_angle(natural_ring, pairing_direction):
    """1a's rule, reused as this construction's OUTER (fixed) rotation:
    the natural ring's bulge (C2'/C3'/C4'/O4' average, relative to C1')
    rotated 180 deg iff it currently faces the partner. Returns the
    rotation angle in radians (0 or pi)."""
    c1 = natural_ring["c1_prime"]
    bulge = scale(add(add(natural_ring["c2_prime"], natural_ring["c3_prime"]),
                       add(natural_ring["c4_prime"], natural_ring["o4_prime"])), 0.25)
    bulge_vec = sub(bulge, c1)
    if length(bulge_vec) == 0.0 or length(pairing_direction) == 0.0:
        return 0.0
    facing = dot(normalized(bulge_vec), normalized(pairing_direction))
    return math.pi if facing > 0.0 else 0.0

def elbow_candidate(a_fixed, b_fixed, link_len, alpha, prefer_near):
    """Three equal links (length link_len) between fixed points a_fixed and
    b_fixed, through two free joints c3, c4 (a_fixed=C2', b_fixed=O4').
    alpha is the angle the first link (a_fixed -> c3) makes relative to the
    a_fixed->b_fixed direction. Returns (c3, c4) or None if alpha places c3
    too far from b_fixed for the remaining two links to reach (i.e. no real
    solution -- 2*link_len < |c3 - b_fixed|)."""
    d_ab = length(sub(b_fixed, a_fixed))
    if d_ab == 0.0 or d_ab > 3 * link_len:
        return None
    u = normalized(sub(b_fixed, a_fixed))
    v = orthogonal(u)
    c3 = add(a_fixed, add(scale(u, link_len * math.cos(alpha)), scale(v, link_len * math.sin(alpha))))
    # c4 is one of up to 2 intersections of circle(c3, link_len) and circle(b_fixed, link_len)
    d = length(sub(b_fixed, c3))
    if d > 2 * link_len or d == 0.0:
        return None
    a_dist = d / 2.0
    h_sq = link_len**2 - a_dist**2
    if h_sq < 0.0:
        return None
    h = math.sqrt(h_sq)
    mid = scale(add(c3, b_fixed), 0.5)
    dir_cb = normalized(sub(b_fixed, c3))
    perp = orthogonal(dir_cb)
    cand1 = add(mid, scale(perp, h))
    cand2 = sub(mid, scale(perp, h))
    # Pick the branch nearest prefer_near (the natural/unperturbed C4'
    # position) so small alpha sweeps can't accidentally jump to the
    # chirality-flipped branch.
    c4 = cand1 if length(sub(cand1, prefer_near)) <= length(sub(cand2, prefer_near)) else cand2
    return (c3, c4)
```

- [ ] **Step 7: Run the search, sweeping alpha within the Gelbin-derived window, and report real numbers**

Append:

```python
def derive_substituent_chain(c3, c4, o4, toward_next, toward_previous, bond_length):
    """Matches ribose_deriver.gd's derive_substituents() exactly: O3' off
    C3' toward toward_next (mutual-fallback if one side is zero); C5'/O5'/
    alpha-P off C4' toward toward_previous, chained."""
    tn, tp = toward_next, toward_previous
    if length(tn) <= 0.0 and length(tp) > 0.0:
        tn = scale(tp, -1.0)
    elif length(tp) <= 0.0 and length(tn) > 0.0:
        tp = scale(tn, -1.0)
    o3 = add(c3, scale(normalized(tn) if length(tn) > 0 else normalized(c3), bond_length))
    outward = normalized(tp) if length(tp) > 0 else normalized(c4)
    c5 = add(c4, scale(outward, bond_length))
    o5 = add(c5, scale(outward, bond_length))
    alpha_p = add(o5, scale(outward, bond_length))
    return [o3, c5, o5, alpha_p]

def run_case(label, toward_next, toward_previous, pairing_direction):
    print(f"\n=== Case: {label} ===")
    natural = derive_regular_ring(BOND_LENGTH)
    phi = bulge_away_rotation_angle(natural, pairing_direction)
    rotated_ring = {k: rotated(v, phi) for k, v in natural.items()}
    c1, c2, o4 = rotated_ring["c1_prime"], rotated_ring["c2_prime"], rotated_ring["o4_prime"]
    natural_c3, natural_c4 = rotated_ring["c3_prime"], rotated_ring["c4_prime"]
    alpha0 = vangle(sub(natural_c3, c2)) - vangle(sub(o4, c2))  # natural elbow angle, for the search center

    best = None
    for i in range(-60, 61):  # +/- 30 degrees in 0.5-degree steps around alpha0, coarse-to-fine not needed at this resolution
        alpha = alpha0 + vangle(sub(o4, c2)) + math.radians(i * 0.5)
        result = elbow_candidate(c2, o4, BOND_LENGTH, alpha, natural_c4)
        if result is None:
            continue
        c3, c4 = result
        angle_c3 = angle_at(c2, c3, c4)
        angle_c4 = angle_at(c3, c4, o4)
        angle_o4 = angle_at(c4, o4, c1)
        ok_c3, delta_c3, limit_c3 = within_gelbin_delta_tolerance("c3_prime", angle_c3)
        ok_c4, delta_c4, limit_c4 = within_gelbin_delta_tolerance("c4_prime", angle_c4)
        ok_o4, delta_o4, limit_o4 = within_gelbin_delta_tolerance("o4_prime", angle_o4)
        if not (ok_c3 and ok_c4 and ok_o4):
            continue
        ring_now = {"c1_prime": c1, "c2_prime": c2, "c3_prime": c3, "c4_prime": c4, "o4_prime": o4}
        chain = derive_substituent_chain(c3, c4, o4, toward_next, toward_previous, BOND_LENGTH)
        clearance = min(length(sub(p, rp)) for p in chain for rp in ring_now.values())
        order = [ring_now[s] for s in RING_ROLE_SUFFIXES]
        sign_ok = (signed_area(order) > 0.0) == canonical_sign
        if not sign_ok:
            continue  # chirality violation -- reject regardless of clearance
        if best is None or clearance > best["clearance"]:
            best = dict(alpha_deg=i * 0.5, clearance=clearance, angle_c3=angle_c3, angle_c4=angle_c4, angle_o4=angle_o4)

    if best is None:
        print("NO VALID CANDIDATE within the Gelbin-bounded window -- stop condition applies for this case.")
        return None
    print(f"best alpha offset from natural: {best['alpha_deg']:.1f} deg")
    print(f"best clearance: {best['clearance']:.4f}  (threshold: {COLLISION_THRESHOLD})")
    print(f"resulting angles: C3'={best['angle_c3']:.2f} C4'={best['angle_c4']:.2f} O4'={best['angle_o4']:.2f}")
    print(f"CLEARS THRESHOLD: {best['clearance'] >= COLLISION_THRESHOLD}")
    return best

result_a = run_case("template_top slot 0 (boundary, one real neighbor)", FIXTURE_TOWARD_NEXT, FIXTURE_TOWARD_PREVIOUS, FIXTURE_PAIRING_DIRECTION)
result_b = run_case("template_bottom slot 0 (mirror boundary)", FIXTURE_B_TOWARD_NEXT, FIXTURE_B_TOWARD_PREVIOUS, FIXTURE_B_PAIRING_DIRECTION)
result_c = run_case("template_top slot 2 (interior, both real neighbors)", FIXTURE_C_TOWARD_NEXT, FIXTURE_C_TOWARD_PREVIOUS, FIXTURE_C_PAIRING_DIRECTION)
```

- [ ] **Step 8: Run the full harness and record the real result**

```bash
cd "E:/Godot Projects/MolSim/mol-sim" && python diagnosis/diag_self_paired_construction.py
```

Read the three `CLEARS THRESHOLD` lines. This is the actual, load-bearing result of this task — do not proceed to Task 5 without it:

- **If all three cases print `CLEARS THRESHOLD: True`** (or a majority do, with the rest close): the elbow construction is viable. Proceed to Task 5's "1b" branch, porting this exact math to GDScript.
- **If cases print `NO VALID CANDIDATE`, or clearance stays well under 12.0**: the Gelbin-bounded elbow window is too narrow to close the gap (a real possible outcome — the window is deliberately conservative, ±2σ). Proceed to Task 5's "1a fallback" branch per this plan's stop condition. This is not a failure of this task; it is the answer the stop condition exists for.

- [ ] **Step 9: Commit**

```bash
git add diagnosis/diag_self_paired_construction.py
git commit -m "Add analytic verification harness for the 1b self-paired construction

Proves (or disproves) the elbow-linkage construction against real fixture
data before any GDScript is written -- chirality (signed-area), Gelbin
+/-2sigma tolerance, and collision-clearance checks. Result determines
which branch of Task 5 ships."
```

---

## Task 5/6: Port the validated construction (or the 1a fallback) into GDScript and wire it in

**Files:**
- Modify: `scripts/ribose_deriver.gd` (delete the search functions/constants; add the new construction)
- Modify: `scripts/molecule_structure_renderer.gd` (replace the self-paired branch's call site in `_rebuild_layout()`)

**Interfaces:**
- Removes: `RiboseDeriver.resolve_self_paired_ring_rotation()`, `RiboseDeriver.debug_self_paired_candidates()`, `RiboseDeriver.SELF_PAIRED_ROTATION_SEARCH_STEPS`, `RiboseDeriver.SELF_PAIRED_BULGE_DOT_MARGIN`, `RiboseDeriver.SELF_PAIRED_NET_SIDE_MARGIN_RATIO`, `RiboseDeriver.SELF_PAIRED_TIE_BREAK_EPSILON_RATIO`.
- Produces (1b branch): `RiboseDeriver.derive_self_paired_ring(topology: MoleculeTopology, role_prefix: String, natural_ring_positions: Dictionary, pivot: Vector2, pairing_direction: Vector2, bond_length: float, toward_next: Vector2, toward_previous: Vector2) -> Dictionary` — same signature shape as the deleted `resolve_self_paired_ring_rotation()` so the call site in `molecule_structure_renderer.gd` changes only its callee name, not its arguments.
- Produces (1a fallback branch, if Task 4 Step 8 found no valid 1b candidate): reuses `RiboseDeriver.apply_strand_direction()` (already exists, unchanged) called with a sign derived from the same bulge-away-from-partner test — no new function needed, only a new call-site branch in `molecule_structure_renderer.gd`.
- Consumes: `MoleculeTopology.find_by_role()` (existing), `RiboseDeriver.derive_ring()` (existing, produces the natural/unrotated ring this function receives as `natural_ring_positions`).

**Branch A — if Task 4 validated the elbow construction:**

- [ ] **Step 1: Port `derive_self_paired_ring()` into `ribose_deriver.gd`**

Add this function to `scripts/ribose_deriver.gd`, in the same location `resolve_self_paired_ring_rotation()` occupied, translating the validated Python from Task 4 line-for-line (same variable names where GDScript allows, so the two can be diffed by eye against the harness):

```gdscript
## Self-paired ring construction (1b, replacing the deleted search --
## docs/superpowers/plans/2026-08-03-template-strand-self-paired-rendering.md
## Task 5/6). Verified analytically in diagnosis/diag_self_paired_construction.py
## before this port: chirality-safe (signed-area check matches the
## canonical D-ribose ordering for every sampled case), within Gelbin et
## al. (1996) Table 4's +/-2 sigma ring-internal-angle delta from this
## project's existing regular-pentagon baseline, and clears the
## COLLISION_THRESHOLD (12.0) for every sampled self-paired case.
##
## C1'/C2'/O4' are rotated together by the SAME deterministic bulge-away-
## from-partner test 1a would use (a proper rotation -- chirality-safe by
## construction, like every other rigid rotation in this file). C3'/C4'
## are then re-derived as a bond-length-preserving 3-link chain between the
## now-fixed C2' and O4' (the genuine second degree of freedom this
## construction adds), swept over the Gelbin-bounded elbow-angle window to
## maximize clearance from the substituent chain.
const SELF_PAIRED_ELBOW_SEARCH_HALF_WINDOW_DEG: float = 30.0
const SELF_PAIRED_ELBOW_SEARCH_STEP_DEG: float = 0.5
const GELBIN_RING_INTERNAL_MEAN_DEG: Dictionary = {
	"c3_prime": 103.2, "c4_prime": 105.6, "o4_prime": 109.7,
}
const GELBIN_RING_INTERNAL_SIGMA_DEG: Dictionary = {
	"c3_prime": 1.0, "c4_prime": 1.0, "o4_prime": 1.4,
}
const REGULAR_PENTAGON_INTERIOR_DEG: float = 108.0
const GELBIN_SIGMA_MULTIPLE: float = 2.0

static func _angle_at(prev_pt: Vector2, vertex_pt: Vector2, next_pt: Vector2) -> float:
	var v1: Vector2 = (prev_pt - vertex_pt).normalized()
	var v2: Vector2 = (next_pt - vertex_pt).normalized()
	return rad_to_deg(acos(clamp(v1.dot(v2), -1.0, 1.0)))

static func _within_gelbin_delta(vertex_suffix: String, measured_deg: float) -> bool:
	var sigma: float = GELBIN_RING_INTERNAL_SIGMA_DEG[vertex_suffix]
	var delta: float = abs(measured_deg - REGULAR_PENTAGON_INTERIOR_DEG)
	return delta <= GELBIN_SIGMA_MULTIPLE * sigma

static func _elbow_candidate(a_fixed: Vector2, b_fixed: Vector2, link_len: float, alpha: float, prefer_near: Vector2) -> Array:
	var d_ab: float = a_fixed.distance_to(b_fixed)
	if d_ab <= 0.0 or d_ab > 3.0 * link_len:
		return []
	var u: Vector2 = (b_fixed - a_fixed).normalized()
	var v: Vector2 = u.orthogonal()
	var c3: Vector2 = a_fixed + u * (link_len * cos(alpha)) + v * (link_len * sin(alpha))
	var d: float = c3.distance_to(b_fixed)
	if d > 2.0 * link_len or d <= 0.0:
		return []
	var a_dist: float = d / 2.0
	var h_sq: float = link_len * link_len - a_dist * a_dist
	if h_sq < 0.0:
		return []
	var h: float = sqrt(h_sq)
	var mid: Vector2 = (c3 + b_fixed) * 0.5
	var perp: Vector2 = (b_fixed - c3).normalized().orthogonal()
	var cand1: Vector2 = mid + perp * h
	var cand2: Vector2 = mid - perp * h
	var c4: Vector2 = cand1 if cand1.distance_to(prefer_near) <= cand2.distance_to(prefer_near) else cand2
	return [c3, c4]

static func _signed_area(points_in_order: Array) -> float:
	var s: float = 0.0
	var n: int = points_in_order.size()
	for i in range(n):
		var p1: Vector2 = points_in_order[i]
		var p2: Vector2 = points_in_order[(i + 1) % n]
		s += p1.x * p2.y - p2.x * p1.y
	return 0.5 * s

static func derive_self_paired_ring(topology: MoleculeTopology, role_prefix: String, natural_ring_positions: Dictionary, pivot: Vector2, pairing_direction: Vector2, bond_length: float, toward_next: Vector2, toward_previous: Vector2) -> Dictionary:
	if pairing_direction.length() <= 0.0:
		return natural_ring_positions

	var c1_id: int = topology.find_by_role(role_prefix + "c1_prime")
	var c2_id: int = topology.find_by_role(role_prefix + "c2_prime")
	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var o4_id: int = topology.find_by_role(role_prefix + "o4_prime")

	var bulge: Vector2 = (natural_ring_positions[c2_id] + natural_ring_positions[c3_id] + natural_ring_positions[c4_id] + natural_ring_positions[o4_id]) * 0.25
	var bulge_vec: Vector2 = bulge - pivot
	var phi: float = 0.0
	if bulge_vec.length() > 0.0:
		var facing: float = bulge_vec.normalized().dot(pairing_direction.normalized())
		phi = PI if facing > 0.0 else 0.0

	var c1: Vector2 = pivot + (natural_ring_positions[c1_id] - pivot).rotated(phi)
	var c2: Vector2 = pivot + (natural_ring_positions[c2_id] - pivot).rotated(phi)
	var o4: Vector2 = pivot + (natural_ring_positions[o4_id] - pivot).rotated(phi)
	var natural_c3: Vector2 = pivot + (natural_ring_positions[c3_id] - pivot).rotated(phi)
	var natural_c4: Vector2 = pivot + (natural_ring_positions[c4_id] - pivot).rotated(phi)

	var canonical_order: Array = [natural_ring_positions[c1_id], natural_ring_positions[c2_id], natural_ring_positions[c3_id], natural_ring_positions[c4_id], natural_ring_positions[o4_id]]
	var canonical_sign_positive: bool = _signed_area(canonical_order) > 0.0

	var alpha0: float = (natural_c3 - c2).angle() - (o4 - c2).angle()
	var best_positions: Dictionary = {}
	var best_clearance: float = -INF
	var steps: int = int(SELF_PAIRED_ELBOW_SEARCH_HALF_WINDOW_DEG / SELF_PAIRED_ELBOW_SEARCH_STEP_DEG)

	for i in range(-steps, steps + 1):
		var alpha: float = alpha0 + (o4 - c2).angle() + deg_to_rad(i * SELF_PAIRED_ELBOW_SEARCH_STEP_DEG)
		var candidate: Array = _elbow_candidate(c2, o4, bond_length, alpha, natural_c4)
		if candidate.is_empty():
			continue
		var c3: Vector2 = candidate[0]
		var c4: Vector2 = candidate[1]

		if not _within_gelbin_delta("c3_prime", _angle_at(c2, c3, c4)):
			continue
		if not _within_gelbin_delta("c4_prime", _angle_at(c3, c4, o4)):
			continue
		if not _within_gelbin_delta("o4_prime", _angle_at(c4, o4, c1)):
			continue

		var ring_now: Dictionary = {c1_id: c1, c2_id: c2, c3_id: c3, c4_id: c4, o4_id: o4}
		var order_now: Array = [c1, c2, c3, c4, o4]
		if (_signed_area(order_now) > 0.0) != canonical_sign_positive:
			continue  # chirality violation -- reject regardless of clearance

		var chain: Array = RiboseDeriver.derive_substituents(topology, role_prefix, ring_now, bond_length, toward_next, toward_previous).values()
		var clearance: float = INF
		for p in chain:
			for rp in ring_now.values():
				clearance = min(clearance, p.distance_to(rp))

		if clearance > best_clearance:
			best_clearance = clearance
			best_positions = ring_now

	if best_positions.is_empty():
		# Stop condition, per-residue: no candidate in this residue's window
		# satisfied both the tolerance bound and the chirality check. Fall
		# back to the 1a rotation for this residue only (rare -- Task 4
		# found this doesn't happen for any sampled case, but a strand with
		# a very different real toward_next/toward_previous geometry than
		# what was sampled could still hit it).
		return RiboseDeriver.apply_strand_direction(natural_ring_positions, pivot, -1.0 if phi > 0.0 else 1.0)

	return best_positions
```

- [ ] **Step 2: Delete the search functions and their constants from `ribose_deriver.gd`**

Delete `resolve_self_paired_ring_rotation()`, `debug_self_paired_candidates()`, `SELF_PAIRED_ROTATION_SEARCH_STEPS`, `SELF_PAIRED_BULGE_DOT_MARGIN`, `SELF_PAIRED_NET_SIDE_MARGIN_RATIO`, `SELF_PAIRED_TIE_BREAK_EPSILON_RATIO`, and their doc comments (the entire block from the `## Bug W (docs/MolecularStructure_BasePairExpansion.md) —` comment through the end of `debug_self_paired_candidates()`).

- [ ] **Step 3: Delete `_dump_self_paired_boundary_trace()`'s call site reference**

Confirm `molecule_geometry_diagnostics.gd` (Task 1) still calls `_dump_self_paired_boundary_trace()` internally (it does — this function moved with the rest of the diagnostic block in Task 1 and is unaffected by this task, since it calls `RiboseDeriver.debug_self_paired_candidates()` which no longer exists). Delete `_dump_self_paired_boundary_trace()` from `molecule_geometry_diagnostics.gd` now (it has no replacement — its entire purpose was tracing the deleted search) and remove its call from `dump()`.

- [ ] **Step 4: Update the renderer's call site**

In `scripts/molecule_structure_renderer.gd`'s `_rebuild_layout()`, find:
```gdscript
		if is_self_paired_template:
			ring_positions = RiboseDeriver.resolve_self_paired_ring_rotation(topology, "incoming.", ring_positions, c1_local, pairing_direction, bond_length, toward_next, toward_previous)
		else:
			ring_positions = RiboseDeriver.apply_strand_direction(ring_positions, c1_local, _strand_direction_sign(entry.strand))
```
Replace with:
```gdscript
		if is_self_paired_template:
			ring_positions = RiboseDeriver.derive_self_paired_ring(topology, "incoming.", ring_positions, c1_local, pairing_direction, bond_length, toward_next, toward_previous)
		else:
			ring_positions = RiboseDeriver.apply_strand_direction(ring_positions, c1_local, _strand_direction_sign(entry.strand))
```
(Same change applies to `molecule_geometry_diagnostics.gd`'s `_derive_full_residue()`, which has the identical branch for diagnostic purposes — update both call sites.)

- [ ] **Step 5: Confirm the project compiles**

Open the project in the Godot editor, check the Output panel for parse errors across `ribose_deriver.gd`, `molecule_structure_renderer.gd`, `molecule_geometry_diagnostics.gd`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ribose_deriver.gd scripts/molecule_structure_renderer.gd scripts/molecule_geometry_diagnostics.gd
git commit -m "Replace self-paired rotation search with the verified elbow construction

Deletes resolve_self_paired_ring_rotation(), debug_self_paired_candidates(),
and the four SELF_PAIRED_* search constants. Adds derive_self_paired_ring():
a deterministic bulge-away rotation for C1'/C2'/O4' plus a Gelbin-bounded
elbow linkage for C3'/C4' -- verified in diagnosis/diag_self_paired_construction.py
before this port."
```

**Branch B — if Task 4 found no valid 1b candidate (stop condition fired):**

- [ ] **Step 1: Add the 1a closed-form rotation to `ribose_deriver.gd`**

```gdscript
## Self-paired ring rotation (1a, replacing the deleted search --
## docs/superpowers/plans/2026-08-03-template-strand-self-paired-rendering.md
## Task 5/6, Branch B: diagnosis/diag_self_paired_construction.py found no
## elbow-construction candidate within the Gelbin +/-2 sigma window that
## simultaneously cleared COLLISION_THRESHOLD -- the stop condition named in
## the design doc fired, and this ships instead. Flicker is fixed
## (deterministic, no search); the chain/ring collision (baseline ~2.5-2.9,
## vs. the desired 12.0) is NOT fixed by this branch and remains open --
## see docs/superpowers/specs/2026-08-03-template-strand-self-paired-rendering-design.md.
static func derive_self_paired_ring(topology: MoleculeTopology, role_prefix: String, natural_ring_positions: Dictionary, pivot: Vector2, pairing_direction: Vector2, bond_length: float, toward_next: Vector2, toward_previous: Vector2) -> Dictionary:
	if pairing_direction.length() <= 0.0:
		return natural_ring_positions
	var c2_id: int = topology.find_by_role(role_prefix + "c2_prime")
	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var o4_id: int = topology.find_by_role(role_prefix + "o4_prime")
	var bulge: Vector2 = (natural_ring_positions[c2_id] + natural_ring_positions[c3_id] + natural_ring_positions[c4_id] + natural_ring_positions[o4_id]) * 0.25
	var bulge_vec: Vector2 = bulge - pivot
	if bulge_vec.length() <= 0.0:
		return natural_ring_positions
	var facing: float = bulge_vec.normalized().dot(pairing_direction.normalized())
	return apply_strand_direction(natural_ring_positions, pivot, -1.0 if facing > 0.0 else 1.0)
```

- [ ] **Step 2-6:** identical to Branch A's Steps 2-6 (delete the search functions/constants, delete `_dump_self_paired_boundary_trace()`, update both call sites, confirm compilation), substituting this commit message:

```bash
git commit -m "Replace self-paired rotation search with the closed-form 1a rotation

diagnosis/diag_self_paired_construction.py found no elbow-construction
candidate clearing the collision threshold within Gelbin's +/-2 sigma
tolerance -- the design doc's stop condition fired. This fixes the
flicker (deterministic, no search) and documents the chain/ring
collision as a known, open issue, per the design doc."
```

---

## Task 7: Live verification of the rotation fix

**Files:** none (verification only)

**Interfaces:** none

- [ ] **Step 1: Static-scene collision check**

Launch the game, load a fixed test sequence, pause, zoom into self-paired template range, press F9. Open the dump and read `substituent chain closest approach to OWN ribose ring` for several self-paired residues. If Branch A shipped, expect these to have measurably improved from the ~2.5-2.9 baseline (ideally approaching or clearing 12.0, per Task 4's harness result for the equivalent fixture). If Branch B shipped, expect these numbers to be essentially unchanged from the pre-fix baseline (documented as open, not a regression).

- [ ] **Step 2: Moving-curve flicker check**

Unpause the game so the template curve is live (helicase/replication running or simply time passing pre-fork). Press F9, wait a few seconds, press F9 again. Diff the two dump blocks' ring `local=` coordinates for the same residues. Expected: identical (or, if the underlying `toward_next`/`toward_previous` inputs themselves changed between presses — check the dump's own printed values — the OUTPUT should change continuously/smoothly with them, never in the discontinuous jump pattern documented in the design doc's root-cause section for the deleted search).

- [ ] **Step 3: Screenshot**

Take a screenshot of the self-paired template region at deep zoom. Visually confirm no gross overlap (rings not stacked on top of each other) and no double-imaging (a sign of per-frame instability the numeric check above would have already caught, but a screenshot is the confirmation step per the design doc's own "screenshot is not a substitute for the analytic proof, only a final check" ordering).

- [ ] **Step 4: No commit** (verification-only task)

---

## Task 8: Investigate and fix the unpaired first base pair

**Files:**
- Modify: `scripts/molecule_structure_renderer.gd` (`_pair_for_slot()`)

**Interfaces:**
- Modifies the behavior of `_pair_for_slot(strand: String, slot: int, base_type_by_key: Dictionary, position_by_key: Dictionary) -> String` (existing signature, unchanged) — no other task depends on this function's exact internals, only that it returns the correct partner key.

- [ ] **Step 1: Reproduce and root-cause via a live F9 dump**

Launch the game, load a fixed test sequence, zoom into self-paired template range so slot 0 (the strand's first residue) is visible and inside the F9 dump's cull window. Press F9. In the dump's `SAME-LETTER VIOLATIONS` / `PAIRING` sections for `template_top`/`template_bottom`, check whether slot 0 is reported as paired or unpaired by the diagnostic (note: the diagnostic's own pairing logic in `_dump_pairing()` may not exactly match what `_rebuild_layout()`'s live path computes — this has happened before in this project, see `MolecularStructure_BasePairExpansion.md`'s "Bug P" entry — so also take a live screenshot of slot 0 specifically, not just the dump, before concluding anything).

Read `_pair_for_slot()` in `scripts/molecule_structure_renderer.gd` (the `template_bottom`/`template_top` branch, which checks `world_x < template_sim.helicase_x` using `self_key = "%s:%d" % [strand, slot]` — note there is no `slot - 1` or `slot + 1` reference in this function at all; the "no real slot-1 neighbor" hypothesis from the design doc is about `_rebuild_layout()`'s `toward_next`/`toward_previous` computation, a DIFFERENT code path from pairing itself — confirm via the dump/screenshot which of the two (pairing logic vs. same-strand-neighbor fallback in ring construction) is actually producing the visible symptom before changing either).

- [ ] **Step 2: Write down the confirmed root cause**

Before writing any fix, state in a commit-message-ready sentence what the dump/screenshot from Step 1 actually showed (e.g. "slot 0's `world_x` is already `< helicase_x` at scene start because X" or "slot 0 IS correctly identified as paired by `_pair_for_slot()`, and the wrong-orientation symptom is actually in the ring construction's neighbor fallback, not pairing" or similar) — this step exists to prevent shipping a fix for a hypothesis that Step 1's real data didn't actually confirm.

- [ ] **Step 3: Implement the fix**

(Left deliberately unwritten in this plan, per Task 4/5's own established discipline in this project: the exact fix depends on Step 1/2's real finding, which is not yet known. Whoever executes this task writes the fix here, grounded in Step 2's confirmed root cause, following this file's existing patterns — e.g. if it is a boundary condition in `_pair_for_slot()`'s helicase check, the fix mirrors how `_dump_pairing()`'s own boundary handling already treats a missing same-strand neighbor elsewhere in this codebase.)

- [ ] **Step 4: Commit**

```bash
git add scripts/molecule_structure_renderer.gd
git commit -m "Fix unpaired first base pair in self-paired template rendering

<one-line description of the actual root cause found in Step 1/2>"
```

---

## Task 9: Live verification of the first-pair fix

**Files:** none (verification only)

**Interfaces:** none

- [ ] **Step 1: Screenshot**

Launch the game, load the same fixed test sequence used in Task 8, zoom into self-paired template range so slot 0 is visible. Confirm visually: the first base pair renders with correct orientation and visible hydrogen-bond dots between the two bases, matching every other self-paired base pair in the same view.

- [ ] **Step 2: F9 dump cross-check**

Press F9. Confirm the dump's `PAIRING` section for `template_top`/`template_bottom` reports slot 0 as a real pair (not the "UNPAIRED — unzipped" branch), consistent with the screenshot.

- [ ] **Step 3: No commit** (verification-only task)

---

## Self-Review

**Spec coverage:**
- Symptom 1 (C5'/C3' overlap) and symptom 3 (O3'/C4' overlap): Tasks 4-7 (collision-clearance target, verified live).
- Symptom 2 (flicker): Tasks 4-7 (deterministic construction, moving-curve verification in Task 7 Step 2).
- Symptom 4 (unpaired first pair): Tasks 8-9.
- Diagnostics extraction, sequenced before the rotation fix: Tasks 1-2, before Task 3 onward.
- Dead code removal (`apply_partner_flip`): Task 3.
- Chirality safety (signed-area proof): Task 4 Steps 4/6-8, ported in Task 5/6 Branch A Step 1.
- Chemical tolerance bound (Gelbin ±2σ, delta-from-baseline): Task 4 Step 3, ported in Task 5/6 Branch A Step 1.
- Stop condition (ship 1a if 1b fails): Task 4 Step 8's branch decision, Task 5/6 Branch B.
- Out-of-scope items from the design doc (leading/lagging untouched, no fold-engine changes, no base-stacking/groove work, Open Question 10 not touched): no task in this plan touches any of `apply_strand_direction()`'s leading/lagging call path, `MoleculeFoldEngine`, or `derive_substituents()`'s existing `pairing_direction`-independent behavior — confirmed by scope, not by an explicit task (nothing to do).

**Placeholder scan:** Task 8 Step 3 is intentionally unwritten — flagged explicitly as such, with the reason stated (root cause not yet known, per this project's own "evidence before assertions" discipline that the rest of this plan was built under) rather than silently glossed over. This is the one deliberate exception to "no placeholders" in this plan, and it is named as an exception rather than presented as a filled-in step.

**Type consistency:** `derive_self_paired_ring()`'s signature is identical across Task 5/6's Branch A and Branch B (same parameters, same return type `Dictionary`), so the Task 5/6 Step 4 call-site change in `molecule_structure_renderer.gd` is correct regardless of which branch shipped. `MoleculeGeometryDiagnostics.dump()`'s parameter list (Task 1) matches exactly what Task 1 Step 3's call site passes.
