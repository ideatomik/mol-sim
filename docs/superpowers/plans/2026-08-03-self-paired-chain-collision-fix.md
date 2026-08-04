# Self-Paired Template Chain/Ring Collision Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the O3'/C4' and C5'/C3' backbone collision in self-paired template molecular rendering (left explicitly open by the prior template-strand-self-paired-rendering fix) by replacing the current binary 0°/180° ring rotation with a closed-form continuous rotation (Tier 1), plus a per-substituent real-direction-preserving distance extension for whichever residues Tier 1 alone can't clear (Tier 2).

**Architecture:** `RiboseDeriver.derive_self_paired_ring()` gains a closed-form continuous rotation angle (Tier 1), replacing its current 0°/180° choice, still a rigid rotation (chirality-safe by construction, same proof as today's shipped version). `RiboseDeriver.derive_substituents()` gains an opt-in, per-substituent distance extension (Tier 2) used only when `is_self_paired_template = true` AND Tier 1 alone didn't clear the collision threshold for that specific substituent — the real placement *direction* is never touched, only how far along it the atom sits. A standalone Python harness in `diagnosis/` proves both tiers against real fixture data before any GDScript is written, matching this project's established convention.

**Tech Stack:** GDScript (Godot 4.6), Python 3 (analytic verification only, `diagnosis/` — never shipped/imported by the game).

## Global Constraints

- No automated test framework exists in this project. Verification is: (a) a standalone Python script in `diagnosis/` mirroring the GDScript math for an analytic proof (this project's established convention), and (b) live F9 geometry dumps (`user://geometry_dump.txt`, on Windows `C:\Users\dhpcs\AppData\Roaming\Godot\app_userdata\MolSim\geometry_dump.txt`) plus screenshots, run in the Godot editor.
- Godot executable for any headless/editor runs: `C:\Godot\Godot_v4.6.3-stable_win64_console.exe` (project root `E:\Godot Projects\MolSim\mol-sim`).
- Collision/clearance threshold: 12.0 world units (`2 × molecular_atom_radius`, `molecular_atom_radius = 6.0` in `theme_manager.gd`).
- `bond_length` in the live scene = `molecular_ring_bond_length_ratio (0.2) × nucleotide_slot_spacing (54.0)` = `10.8`.
- **Rollback constraint (hard requirement from the design doc):** the entire behavior change (Tier 1 + Tier 2, both inside `ribose_deriver.gd`, plus the two call-site updates) ships as **one commit**. The Python harness commits (non-behavioral) land separately, before it.
- **Leading/lagging safety (hard requirement from the design doc):** no line in `apply_strand_direction()`, `STRAND_DIRECTION_SIGN`, or the `else` branch of either call site (leading/lagging's path, `is_self_paired_template = false`) may change.
- O3'/C5' must always extend in exactly the real `toward_next`/`toward_previous` direction — never redirected, angle-substituted, or role-swapped. This project has independently falsified four prior attempts that violated this, all for the same reason (it desyncs from `_build_backbone_bonds()`'s real inter-residue bond target). Tier 2 only ever changes *distance* along that unchanged direction.
- Design doc of record: `docs/superpowers/specs/2026-08-03-self-paired-chain-collision-fix-design.md`. Prior investigation history: `docs/MolecularStructure_BasePairExpansion.md` (Bug D through W), `docs/superpowers/specs/2026-08-03-template-strand-self-paired-rendering-design.md`.

---

## File Structure

- **Create:** `diagnosis/diag_chain_ring_clearance_fix.py` — analytic verification harness (Tasks 1-2), self-contained (this project's convention: each `diagnosis/diag_*.py` stands alone, no cross-imports between them).
- **Modify:** `scripts/ribose_deriver.gd` — `derive_self_paired_ring()`'s body replaced (Tier 1); `derive_substituents()` gains an `is_self_paired_template` parameter and Tier 2 logic (Task 3).
- **Modify:** `scripts/molecule_structure_renderer.gd` — `_rebuild_layout()`'s `derive_substituents()` call site passes `is_self_paired_template` (Task 3).
- **Modify:** `scripts/molecule_geometry_diagnostics.gd` — `_derive_full_residue()`'s `derive_substituents()` call site passes `is_self_paired_template` (Task 3).

---

## Task 1: Python harness — Tier 1 closed-form rotation

**Files:**
- Create: `diagnosis/diag_chain_ring_clearance_fix.py`

**Interfaces:**
- Produces: printed values this task's own steps read directly (matching this project's existing `diagnosis/*.py` convention — no function handed to a later task; Task 3 re-implements the validated math in GDScript by hand, checked against this script's printed numbers).
- Consumes: the same three real fixtures already recorded in `diagnosis/diag_self_paired_construction.py` (boundary top, boundary bottom, interior) — copied here rather than imported, matching this project's "each diag script stands alone" convention.

- [ ] **Step 1: Write the geometry primitives, fixtures, and Tier 1 rotation function**

Create `diagnosis/diag_chain_ring_clearance_fix.py`:

```python
import math

def sub(a, b): return (a[0]-b[0], a[1]-b[1])
def add(a, b): return (a[0]+b[0], a[1]+b[1])
def scale(a, s): return (a[0]*s, a[1]*s)
def length(a): return math.hypot(a[0], a[1])
def length_sq(a): return a[0]*a[0] + a[1]*a[1]
def normalized(a):
    l = length(a)
    return (0.0, 0.0) if l == 0 else (a[0]/l, a[1]/l)
def dot(a, b): return a[0]*b[0] + a[1]*b[1]
def rotated(a, theta):
    c, s = math.cos(theta), math.sin(theta)
    return (a[0]*c - a[1]*s, a[0]*s + a[1]*c)
def angle_to(a, b):
    """Signed angle FROM a TO b, radians, range (-pi, pi] -- matches
    Godot's Vector2.angle_to()."""
    return math.atan2(a[0]*b[1] - a[1]*b[0], dot(a, b))
def wrap_pi(x):
    """Wrap x into (-pi, pi] -- matches Godot's wrapf(x, -PI, PI)."""
    return (x + math.pi) % (2 * math.pi) - math.pi

TAU = 2 * math.pi
BOND_LENGTH = 10.8  # molecular_ring_bond_length_ratio (0.2) * nucleotide_slot_spacing (54.0)
COLLISION_THRESHOLD = 12.0  # 2 * molecular_atom_radius (6.0, theme_manager.gd)

RING_ROLE_SUFFIXES = ["c1_prime", "c2_prime", "c3_prime", "c4_prime", "o4_prime"]

def derive_regular_ring(bond_length, start_angle=-math.pi/2.0):
    """Matches nitrogen_base_deriver.gd's derive_regular_ring() exactly for n=5."""
    n = 5
    R = bond_length / (2.0 * math.sin(math.pi / n))
    step = TAU / n
    return {suf: (math.cos(start_angle + i*step) * R, math.sin(start_angle + i*step) * R)
            for i, suf in enumerate(RING_ROLE_SUFFIXES)}

# ---- Real fixture data (same three cases as diag_self_paired_construction.py,
# copied rather than imported -- this project's diag scripts each stand alone) ----
FIXTURE_A_TOWARD_NEXT = (54.0, 0.394745)       # template_top slot0 -> slot1
FIXTURE_A_TOWARD_PREVIOUS = (0.0, 0.0)          # boundary: no real slot -1
FIXTURE_A_PAIRING_DIRECTION = (0.0, 160.0)

FIXTURE_B_TOWARD_NEXT = (0.0, 0.0)              # boundary: no real neighbor past strand end
FIXTURE_B_TOWARD_PREVIOUS = (54.0, 0.394745)
FIXTURE_B_PAIRING_DIRECTION = (0.0, -160.0)

FIXTURE_C_TOWARD_NEXT = (54.0, -0.0862)         # interior: both real neighbors present
FIXTURE_C_TOWARD_PREVIOUS = (-54.0, 0.0862)
FIXTURE_C_PAIRING_DIRECTION = (0.0, 160.0)

def derive_self_paired_ring(natural_ring, pairing_direction, toward_next, toward_previous):
    """Tier 1: closed-form continuous rotation. Mirrors what Task 3 ports
    into RiboseDeriver.derive_self_paired_ring()."""
    pivot = natural_ring["c1_prime"]
    if length(pairing_direction) <= 0.0:
        return dict(natural_ring), 0.0

    bulge = scale(add(add(natural_ring["c2_prime"], natural_ring["c3_prime"]),
                       add(natural_ring["c4_prime"], natural_ring["o4_prime"])), 0.25)
    bulge_vec = sub(bulge, pivot)
    pairing_hat = normalized(pairing_direction)
    arc_target = scale(pairing_hat, -1.0)
    theta_center = angle_to(bulge_vec, arc_target)

    ring_bond_dir0 = normalized(sub(natural_ring["c4_prime"], natural_ring["c3_prime"]))

    tn, tp = toward_next, toward_previous
    if length(tn) <= 0.0 and length(tp) > 0.0:
        tn = scale(tp, -1.0)
    elif length(tp) <= 0.0 and length(tn) > 0.0:
        tp = scale(tn, -1.0)

    theta = theta_center
    if length(tn) > 0.0 or length(tp) > 0.0:
        tn_hat = normalized(tn) if length(tn) > 0.0 else (0.0, 0.0)
        tp_hat = normalized(tp) if length(tp) > 0.0 else (0.0, 0.0)
        forward = sub(tn_hat, tp_hat)
        if length(forward) > 0.0:
            target_ring_bond_dir = scale(normalized(forward), -1.0)
            theta_ideal = angle_to(ring_bond_dir0, target_ring_bond_dir)
            half = math.pi / 2.0
            delta = wrap_pi(theta_ideal - theta_center)
            theta = theta_ideal if abs(delta) <= half else theta_center + (half if delta > 0.0 else -half)

    result = {k: add(pivot, rotated(sub(v, pivot), theta)) for k, v in natural_ring.items()}
    return result, theta

print("=== Fixture sanity check ===")
print("Fixture A toward_next:", FIXTURE_A_TOWARD_NEXT, "length:", length(FIXTURE_A_TOWARD_NEXT))
print("Fixture A pairing_direction:", FIXTURE_A_PAIRING_DIRECTION, "length:", length(FIXTURE_A_PAIRING_DIRECTION))
```

- [ ] **Step 2: Run it and confirm the fixture sanity check**

```bash
cd "E:/Godot Projects/MolSim/mol-sim" && python diagnosis/diag_chain_ring_clearance_fix.py
```
Expected: prints the two fixture lines with lengths ≈54.001 and 160.0 (same fixtures already validated in `diag_self_paired_construction.py` — this just confirms the copy is faithful).

- [ ] **Step 3: Add the bulge-away and chain-clearance measurement, run against all three fixtures**

Append to `diagnosis/diag_chain_ring_clearance_fix.py`:

```python
def bulge_vs_pairing_dot(ring, pairing_direction):
    pivot = ring["c1_prime"]
    bulge = scale(add(add(ring["c2_prime"], ring["c3_prime"]), add(ring["c4_prime"], ring["o4_prime"])), 0.25)
    bulge_vec = sub(bulge, pivot)
    if length(bulge_vec) == 0.0 or length(pairing_direction) == 0.0:
        return 0.0
    return dot(normalized(bulge_vec), normalized(pairing_direction))

def derive_substituent_first_hops(ring, toward_next, toward_previous, bond_length):
    """Tier-1-only chain placement (no Tier 2 yet) -- same rule as today's
    shipped derive_substituents(): one bond_length along the real direction."""
    tn, tp = toward_next, toward_previous
    if length(tn) <= 0.0 and length(tp) > 0.0:
        tn = scale(tp, -1.0)
    elif length(tp) <= 0.0 and length(tn) > 0.0:
        tp = scale(tn, -1.0)
    o3_dir = normalized(tn) if length(tn) > 0.0 else normalized(ring["c3_prime"])
    c5_dir = normalized(tp) if length(tp) > 0.0 else normalized(ring["c4_prime"])
    o3 = add(ring["c3_prime"], scale(o3_dir, bond_length))
    c5 = add(ring["c4_prime"], scale(c5_dir, bond_length))
    return o3, c5, o3_dir, c5_dir

def min_clearance_to_ring(point, ring):
    return min(length(sub(point, p)) for p in ring.values())

def run_case(label, toward_next, toward_previous, pairing_direction):
    print(f"\n=== Case: {label} ===")
    natural = derive_regular_ring(BOND_LENGTH)
    ring, theta = derive_self_paired_ring(natural, pairing_direction, toward_next, toward_previous)
    bvd = bulge_vs_pairing_dot(ring, pairing_direction)
    print(f"theta: {math.degrees(theta):.2f} deg")
    print(f"bulge_vs_pairing_dot: {bvd:.4f}  (must be <= 0, ideally close to -1)")
    o3, c5, o3_dir, c5_dir = derive_substituent_first_hops(ring, toward_next, toward_previous, BOND_LENGTH)
    o3_clear = min_clearance_to_ring(o3, ring)
    c5_clear = min_clearance_to_ring(c5, ring)
    print(f"O3' clearance to ring (Tier 1 only): {o3_clear:.4f}  (target: {COLLISION_THRESHOLD})")
    print(f"C5' clearance to ring (Tier 1 only): {c5_clear:.4f}  (target: {COLLISION_THRESHOLD})")
    return dict(ring=ring, theta=theta, bvd=bvd, o3=o3, c5=c5, o3_dir=o3_dir, c5_dir=c5_dir,
                o3_clear=o3_clear, c5_clear=c5_clear)

result_a = run_case("template_top slot 0 (boundary)", FIXTURE_A_TOWARD_NEXT, FIXTURE_A_TOWARD_PREVIOUS, FIXTURE_A_PAIRING_DIRECTION)
result_b = run_case("template_bottom slot 0 (mirror boundary)", FIXTURE_B_TOWARD_NEXT, FIXTURE_B_TOWARD_PREVIOUS, FIXTURE_B_PAIRING_DIRECTION)
result_c = run_case("template_top slot 2 (interior)", FIXTURE_C_TOWARD_NEXT, FIXTURE_C_TOWARD_PREVIOUS, FIXTURE_C_PAIRING_DIRECTION)
```

- [ ] **Step 4: Run it and record the real result**

```bash
cd "E:/Godot Projects/MolSim/mol-sim" && python diagnosis/diag_chain_ring_clearance_fix.py
```

Read all three cases' `bulge_vs_pairing_dot` and clearance lines. This is the real, load-bearing result of this task:
- `bulge_vs_pairing_dot` must read ≤ 0 for all three cases (confirms Tier 1 never reopens the original Bug V ring-vs-partner overlap). If any case reads > 0, stop and re-derive the rotation formula — do not proceed to Task 2 with a broken bulge constraint.
- Record each case's O3'/C5' clearance number honestly, whatever it is. Cases already at or above 12.0 need no Tier 2 help; cases below 12.0 are exactly what Task 2 targets.

- [ ] **Step 5: Commit**

```bash
git add diagnosis/diag_chain_ring_clearance_fix.py
git commit -m "$(cat <<'EOF'
Add Tier 1 analytic harness for the self-paired chain/ring collision fix

Proves the closed-form continuous rotation against the same three real
fixtures used for the earlier (abandoned) elbow-flex construction:
confirms bulge-away-from-partner never regresses, and records real
same-residue chain clearance before any GDScript is written.
EOF
)"
```

---

## Task 2: Python harness — Tier 2 per-substituent reach extension

**Files:**
- Modify: `diagnosis/diag_chain_ring_clearance_fix.py`

**Interfaces:**
- Produces: printed values this task's steps read directly, same convention as Task 1.
- Consumes: `derive_self_paired_ring()`, `run_case()`'s per-case results from Task 1 (same file, already defined above).

- [ ] **Step 1: Add the Tier 2 reach solve and stretch cap**

Append to `diagnosis/diag_chain_ring_clearance_fix.py`:

```python
CHAIN_EXTENSION_STRETCH_CAP_RATIO = 2.5  # starting value -- confirmed/adjusted below against real fixture data

def required_chain_reach(start_pos, dir_hat, ring, bond_length, threshold=COLLISION_THRESHOLD):
    """Smallest distance >= bond_length along the UNCHANGED real direction
    dir_hat that clears every ring atom by `threshold`. Never changes
    direction -- only how far along it the atom sits."""
    best = bond_length
    threshold_sq = threshold * threshold
    for p in ring.values():
        rel = sub(p, start_pos)
        a = dot(rel, dir_hat)
        h_sq = max(0.0, length_sq(rel) - a * a)
        if h_sq >= threshold_sq:
            continue  # this ring atom can never collide regardless of reach
        current_dist_sq = (bond_length - a) ** 2 + h_sq
        if current_dist_sq >= threshold_sq:
            continue  # already clear at the default bond length
        reach = math.sqrt(threshold_sq - h_sq)
        best = max(best, a + reach)
    return min(best, bond_length * CHAIN_EXTENSION_STRETCH_CAP_RATIO)

def run_case_with_tier2(label, result):
    ring = result["ring"]
    o3_reach = required_chain_reach(ring["c3_prime"], result["o3_dir"], ring, BOND_LENGTH)
    c5_reach = required_chain_reach(ring["c4_prime"], result["c5_dir"], ring, BOND_LENGTH)
    o3_final = add(ring["c3_prime"], scale(result["o3_dir"], o3_reach))
    c5_final = add(ring["c4_prime"], scale(result["c5_dir"], c5_reach))
    o3_clear = min_clearance_to_ring(o3_final, ring)
    c5_clear = min_clearance_to_ring(c5_final, ring)
    print(f"\n=== Tier 2: {label} ===")
    print(f"O3' reach: {o3_reach:.4f}  ({o3_reach/BOND_LENGTH:.2f}x bond_length)  clearance now: {o3_clear:.4f}")
    print(f"C5' reach: {c5_reach:.4f}  ({c5_reach/BOND_LENGTH:.2f}x bond_length)  clearance now: {c5_clear:.4f}")
    print(f"O3' CLEARS THRESHOLD: {o3_clear >= COLLISION_THRESHOLD - 1e-6}")
    print(f"C5' CLEARS THRESHOLD: {c5_clear >= COLLISION_THRESHOLD - 1e-6}")

run_case_with_tier2("template_top slot 0 (boundary)", result_a)
run_case_with_tier2("template_bottom slot 0 (mirror boundary)", result_b)
run_case_with_tier2("template_top slot 2 (interior)", result_c)
```

- [ ] **Step 2: Run it and record the real result**

```bash
cd "E:/Godot Projects/MolSim/mol-sim" && python diagnosis/diag_chain_ring_clearance_fix.py
```

Read every `CLEARS THRESHOLD` line. This is the real, load-bearing result of this task:
- If every case reads `True`: Tier 2 as specified is sufficient at the default 2.5× cap. Proceed to Task 3 as written.
- If any case reads `False`: the required reach hit the cap without clearing. Report the actual `x bond_length` multiplier needed (uncapped — temporarily raise `CHAIN_EXTENSION_STRETCH_CAP_RATIO` and re-run to find it) and use that real number, not a guess, when porting `CHAIN_EXTENSION_STRETCH_CAP_RATIO` to GDScript in Task 3. If the true required multiplier is implausibly large (e.g. >4x, visibly absurd for a bond), stop and flag this in the commit message for Task 3 as a known, documented, per-residue-open case — same "stop condition" discipline as the rest of this project's self-paired work, not silently accepted.

- [ ] **Step 3: Commit**

```bash
git add diagnosis/diag_chain_ring_clearance_fix.py
git commit -m "$(cat <<'EOF'
Add Tier 2 analytic harness: per-substituent real-direction reach extension

Solves, closed-form, the smallest distance along the UNCHANGED real
toward_next/toward_previous direction that clears the self-paired ring's
own atoms by the 12.0 threshold. Confirms (or adjusts) the stretch cap
against real fixture data before this port into GDScript.
EOF
)"
```

---

## Task 3: Port both tiers into GDScript and wire them in (single commit)

**Files:**
- Modify: `scripts/ribose_deriver.gd`
- Modify: `scripts/molecule_structure_renderer.gd:511`
- Modify: `scripts/molecule_geometry_diagnostics.gd:348`

**Interfaces:**
- Modifies: `RiboseDeriver.derive_self_paired_ring(topology, role_prefix, natural_ring_positions, pivot, pairing_direction, bond_length, toward_next, toward_previous) -> Dictionary` — **signature unchanged** from today's shipped version, only the body changes.
- Modifies: `RiboseDeriver.derive_substituents(topology, role_prefix, ring_positions, bond_length, toward_next = Vector2.ZERO, toward_previous = Vector2.ZERO, is_self_paired_template: bool = false) -> Dictionary` — adds one new parameter, defaulting to today's exact behavior, so every caller that doesn't pass it explicitly is unaffected.
- Consumes: `MoleculeTopology.find_by_role()` (existing), `Vector2.angle_to()`, `Vector2.rotated()`, `wrapf()` (Godot 4 built-ins).

**This entire task is ONE commit (Step 6) — the Rollback constraint from the design doc.** Steps 1-5 make all the edits; nothing is committed until Step 6.

- [ ] **Step 1: Replace `derive_self_paired_ring()`'s body in `ribose_deriver.gd`**

Find the current `derive_self_paired_ring()` (the shipped Branch B / 1a version — its doc comment starts `## Self-paired ring rotation (1a, replacing the deleted search --`). Replace the entire function (keep the function signature line, replace everything inside) with:

```gdscript
## Self-paired ring construction, Tier 1 (docs/superpowers/plans/
## 2026-08-03-self-paired-chain-collision-fix.md, Task 3) -- replaces the
## binary 0/180-degree choice (Branch B / 1a) with a closed-form continuous
## rotation angle. Still a RIGID rotation of the whole natural ring (never
## flexes C3'/C4' individually), so it is chirality-safe by construction,
## same proof as the version it replaces -- no new tolerance/signed-area
## check needed. Verified against real fixture data in
## diagnosis/diag_chain_ring_clearance_fix.py before this port.
##
## Two real constraints, both derived from the SAME rotation angle:
## 1. Bulge-away-from-partner (existing goal, unchanged): the ring's own
##    bulge (a fixed direction in its unrotated frame) must face away from
##    the real partner (pairing_direction) -- a ~180-degree-wide feasible
##    arc, centered on theta_center below.
## 2. Chain-clearance (new): the ring's own C3'-C4' bond should point away
##    from the strand's real forward direction (blended from toward_next
##    and -toward_previous -- these agree in the common straight-strand
##    case, so a single angle can satisfy both O3' and C5' at once there).
## If the ideal chain-clearance angle falls inside the bulge-away arc, use
## it exactly. If not, clamp to the nearest arc edge -- continuous in the
## real inputs, so this does not reproduce the discrete-candidate-jump
## flicker that got the old 72-step search reverted.
static func derive_self_paired_ring(topology: MoleculeTopology, role_prefix: String, natural_ring_positions: Dictionary, pivot: Vector2, pairing_direction: Vector2, bond_length: float, toward_next: Vector2, toward_previous: Vector2) -> Dictionary:
	if pairing_direction.length() <= 0.0:
		return natural_ring_positions

	var c2_id: int = topology.find_by_role(role_prefix + "c2_prime")
	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var o4_id: int = topology.find_by_role(role_prefix + "o4_prime")

	var bulge: Vector2 = (natural_ring_positions[c2_id] + natural_ring_positions[c3_id] + natural_ring_positions[c4_id] + natural_ring_positions[o4_id]) * 0.25
	var bulge_vec: Vector2 = bulge - pivot
	var pairing_hat: Vector2 = pairing_direction.normalized()
	var arc_target: Vector2 = -pairing_hat
	var theta_center: float = bulge_vec.angle_to(arc_target)

	var ring_bond_dir0: Vector2 = (natural_ring_positions[c4_id] - natural_ring_positions[c3_id]).normalized()

	var tn: Vector2 = toward_next
	var tp: Vector2 = toward_previous
	if tn.length() <= 0.0 and tp.length() > 0.0:
		tn = -tp
	elif tp.length() <= 0.0 and tn.length() > 0.0:
		tp = -tn

	var theta: float = theta_center
	if tn.length() > 0.0 or tp.length() > 0.0:
		var tn_hat: Vector2 = tn.normalized() if tn.length() > 0.0 else Vector2.ZERO
		var tp_hat: Vector2 = tp.normalized() if tp.length() > 0.0 else Vector2.ZERO
		var forward: Vector2 = tn_hat - tp_hat
		if forward.length() > 0.0:
			var target_ring_bond_dir: Vector2 = -forward.normalized()
			var theta_ideal: float = ring_bond_dir0.angle_to(target_ring_bond_dir)
			var half: float = PI / 2.0
			var delta: float = wrapf(theta_ideal - theta_center, -PI, PI)
			theta = theta_ideal if abs(delta) <= half else theta_center + (half if delta > 0.0 else -half)

	var result: Dictionary = {}
	for id in natural_ring_positions:
		result[id] = pivot + (natural_ring_positions[id] - pivot).rotated(theta)
	return result
```

- [ ] **Step 2: Add the Tier 2 constants and reach-solve helper to `ribose_deriver.gd`**

Add near the top of the file, alongside the other named constants (e.g. `TETRAHEDRAL_ANGLE_DEG`):

```gdscript
## 2 * molecular_atom_radius (6.0, theme_manager.gd) -- the same
## collision-clearance target used throughout this project's self-paired-
## template work (docs/superpowers/specs/2026-08-03-self-paired-chain-
## collision-fix-design.md).
const COLLISION_CLEARANCE_THRESHOLD: float = 12.0
## Confirmed against real fixture data in
## diagnosis/diag_chain_ring_clearance_fix.py's Task 2 (update this value
## here if that harness found a different real multiplier is needed).
const CHAIN_EXTENSION_STRETCH_CAP_RATIO: float = 2.5
```

Add this helper function near `derive_substituents()`:

```gdscript
## Tier 2 (docs/superpowers/plans/2026-08-03-self-paired-chain-collision-fix.md,
## Task 3): smallest distance >= bond_length along the UNCHANGED real
## direction `dir_hat` that clears every atom in `ring_positions` by
## COLLISION_CLEARANCE_THRESHOLD, capped at CHAIN_EXTENSION_STRETCH_CAP_RATIO
## * bond_length. Never changes direction -- only how far along the already-
## correct real direction the substituent sits, so this cannot desync from
## the real inter-residue backbone bond the way every previously-attempted
## fix for this same collision did (docs/MolecularStructure_BasePairExpansion.md,
## Bug V/W's four independently-failed attempts, plus this project's own
## angle-substitution attempt, all reverted for exactly that reason).
static func _required_chain_reach(start_pos: Vector2, dir_hat: Vector2, ring_positions: Dictionary, bond_length: float) -> float:
	var best: float = bond_length
	var threshold_sq: float = COLLISION_CLEARANCE_THRESHOLD * COLLISION_CLEARANCE_THRESHOLD
	for p in ring_positions.values():
		var rel: Vector2 = p - start_pos
		var a: float = rel.dot(dir_hat)
		var h_sq: float = max(0.0, rel.length_squared() - a * a)
		if h_sq >= threshold_sq:
			continue
		var current_dist_sq: float = (bond_length - a) * (bond_length - a) + h_sq
		if current_dist_sq >= threshold_sq:
			continue
		var reach: float = sqrt(threshold_sq - h_sq)
		best = max(best, a + reach)
	return min(best, bond_length * CHAIN_EXTENSION_STRETCH_CAP_RATIO)
```

- [ ] **Step 3: Wire Tier 2 into `derive_substituents()`**

Change the function signature and the O3'/C5' placement blocks. Find:

```gdscript
static func derive_substituents(topology: MoleculeTopology, role_prefix: String, ring_positions: Dictionary, bond_length: float, toward_next: Vector2 = Vector2.ZERO, toward_previous: Vector2 = Vector2.ZERO) -> Dictionary:
	var positions: Dictionary = {}

	if toward_next.length() <= 0.0 and toward_previous.length() > 0.0:
		toward_next = -toward_previous
	elif toward_previous.length() <= 0.0 and toward_next.length() > 0.0:
		toward_previous = -toward_next

	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var o3_id: int = topology.find_by_role(role_prefix + "o3_prime")
	if c3_id != -1 and o3_id != -1 and ring_positions.has(c3_id):
		var c3_pos: Vector2 = ring_positions[c3_id]
		var outward: Vector2 = toward_next.normalized() if toward_next.length() > 0.0 else c3_pos.normalized()
		positions[o3_id] = c3_pos + outward * bond_length

	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var c5_id: int = topology.find_by_role(role_prefix + "c5_prime")
	if c4_id != -1 and c5_id != -1 and ring_positions.has(c4_id):
		var c4_pos: Vector2 = ring_positions[c4_id]
		var outward: Vector2 = toward_previous.normalized() if toward_previous.length() > 0.0 else c4_pos.normalized()
		var c5_pos: Vector2 = c4_pos + outward * bond_length
		positions[c5_id] = c5_pos
```

Replace with:

```gdscript
static func derive_substituents(topology: MoleculeTopology, role_prefix: String, ring_positions: Dictionary, bond_length: float, toward_next: Vector2 = Vector2.ZERO, toward_previous: Vector2 = Vector2.ZERO, is_self_paired_template: bool = false) -> Dictionary:
	var positions: Dictionary = {}

	if toward_next.length() <= 0.0 and toward_previous.length() > 0.0:
		toward_next = -toward_previous
	elif toward_previous.length() <= 0.0 and toward_next.length() > 0.0:
		toward_previous = -toward_next

	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var o3_id: int = topology.find_by_role(role_prefix + "o3_prime")
	if c3_id != -1 and o3_id != -1 and ring_positions.has(c3_id):
		var c3_pos: Vector2 = ring_positions[c3_id]
		var outward: Vector2 = toward_next.normalized() if toward_next.length() > 0.0 else c3_pos.normalized()
		var reach: float = bond_length
		if is_self_paired_template and toward_next.length() > 0.0:
			reach = _required_chain_reach(c3_pos, outward, ring_positions, bond_length)
		positions[o3_id] = c3_pos + outward * reach

	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var c5_id: int = topology.find_by_role(role_prefix + "c5_prime")
	if c4_id != -1 and c5_id != -1 and ring_positions.has(c4_id):
		var c4_pos: Vector2 = ring_positions[c4_id]
		var outward: Vector2 = toward_previous.normalized() if toward_previous.length() > 0.0 else c4_pos.normalized()
		var reach: float = bond_length
		if is_self_paired_template and toward_previous.length() > 0.0:
			reach = _required_chain_reach(c4_pos, outward, ring_positions, bond_length)
		var c5_pos: Vector2 = c4_pos + outward * reach
		positions[c5_id] = c5_pos
```

(Leave the rest of the function — the O5'/alpha-phosphate block below `c5_pos` — exactly as it is; it already continues from `c5_pos` in the same `outward` direction at normal `bond_length` increments, which is correct and unchanged: only the *first* hop, O3' and C5' themselves, ever stretches.)

- [ ] **Step 4: Update the renderer's call site**

In `scripts/molecule_structure_renderer.gd`, find (around line 511):

```gdscript
		var substituent_positions: Dictionary = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous)
```

Replace with:

```gdscript
		var substituent_positions: Dictionary = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous, is_self_paired_template)
```

(`is_self_paired_template` is already computed a few lines above this call site for the ring-rotation branch — confirm it's in scope before this line; it is, per the existing `_rebuild_layout()` structure.)

- [ ] **Step 5: Update the diagnostics call site**

In `scripts/molecule_geometry_diagnostics.gd`, find (around line 348):

```gdscript
	var substituent_positions: Dictionary = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous)
```

Replace with:

```gdscript
	var substituent_positions: Dictionary = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous, is_self_paired_template)
```

(`is_self_paired_template` is already a parameter of `_derive_full_residue()`, the enclosing function — confirm it's in scope; it is.)

- [ ] **Step 6: Confirm the project compiles**

Open the project in the Godot editor (`C:\Godot\Godot_v4.6.3-stable_win64_console.exe --editor --path "E:\Godot Projects\MolSim\mol-sim"`) and check the Output panel for parse errors across `ribose_deriver.gd`, `molecule_structure_renderer.gd`, `molecule_geometry_diagnostics.gd`.

- [ ] **Step 7: Diff-review the leading/lagging safety constraint before committing**

```bash
cd "E:/Godot Projects/MolSim/mol-sim" && git diff scripts/ribose_deriver.gd scripts/molecule_structure_renderer.gd scripts/molecule_geometry_diagnostics.gd
```
Confirm by reading the diff: no line inside `apply_strand_direction()` or the `STRAND_DIRECTION_SIGN` dictionary changed, and both call-site diffs are exactly the one-argument addition from Steps 4-5 (nothing else on those lines changed). If anything else shows up in the diff, stop and investigate before committing — this is the mechanical check the design doc's Leading/Lagging Safety section requires.

- [ ] **Step 8: Commit (the single behavior-change commit)**

```bash
git add scripts/ribose_deriver.gd scripts/molecule_structure_renderer.gd scripts/molecule_geometry_diagnostics.gd
git commit -m "$(cat <<'EOF'
Fix self-paired template chain/ring collision (Tier 1 + Tier 2)

Replaces derive_self_paired_ring()'s binary 0/180-degree choice with a
closed-form continuous rotation that targets both the existing
bulge-away-from-partner constraint and (new) chain-clearance from the
ring, verified in diagnosis/diag_chain_ring_clearance_fix.py before this
port. Where that rotation alone still leaves O3'/C5' under the 12.0
collision threshold, derive_substituents() now extends that one
substituent further along its UNCHANGED real toward_next/toward_previous
direction (never redirected) until it clears, capped at
CHAIN_EXTENSION_STRETCH_CAP_RATIO.

Leading/lagging is untouched: apply_strand_direction(),
STRAND_DIRECTION_SIGN, and every is_self_paired_template=false code path
are unmodified (confirmed via diff review before this commit). This is a
single, self-contained commit for the entire behavior change, per this
fix's design doc, so it can be reverted with one `git revert` if needed.
EOF
)"
```

---

## Task 4: Live verification

**Files:** none (verification only — no commit)

**Interfaces:** none

- [ ] **Step 1: Static-scene collision check**

Launch the game, load a fixed test sequence, pause, zoom into self-paired template range, press F9. Open the dump and read `substituent chain closest approach to OWN ribose ring` for several self-paired residues on both strands. Expected: at or above 12.0 for most/all residues (matching whatever Task 2's harness run found achievable), a large improvement over the pre-fix baseline of 0.008-0.2. For any residue that hits the Tier 2 stretch cap without clearing, this is expected to be documented, not silently wrong — cross-check against what Task 2's harness run recorded for that same fixture case.

- [ ] **Step 2: Moving-curve flicker check**

Unpause the game so the template curve is live. Press F9, wait a few seconds, press F9 again. Diff the two dump blocks' ring `local=` coordinates for the same residues. Expected: either identical (if the real `toward_next`/`toward_previous`/`pairing_direction` inputs didn't change between presses) or changing smoothly/continuously with them — never the discontinuous jump pattern documented for the old reverted search.

- [ ] **Step 3: Leading/lagging regression check**

With leading/lagging strands populated (unpause until synthesis has started), press F9. Confirm `chain_closest_to_own_ribose` for leading/lagging residues still reads the same clean value as before this fix (10.8, or whatever the pre-fix baseline for those strands was) — confirms the `is_self_paired_template = false` path is genuinely untouched, not just by code review but by live behavior.

- [ ] **Step 4: Revert dry-run (Rollback constraint verification)**

```bash
cd "E:/Godot Projects/MolSim/mol-sim" && git revert --no-commit HEAD && git diff --cached --stat
```
Expected: only `scripts/ribose_deriver.gd`, `scripts/molecule_structure_renderer.gd`, `scripts/molecule_geometry_diagnostics.gd` appear in the diff, cleanly reverting Task 3's commit with no conflicts. Then restore the fix (undo the dry-run without committing it):
```bash
git revert --abort
```

- [ ] **Step 5: Screenshot**

Take a screenshot of the self-paired template region at deep zoom. Visually confirm no gross overlap remains (or, for any residue documented as still-open in Step 1, that it reads as a visibly stretched-but-connected bond rather than a broken/overlapping one).

- [ ] **Step 6: No commit** (verification-only task)

---

## Self-Review

**Spec coverage:**
- Tier 1 (refined closed-form rotation): Task 1 (Python proof), Task 3 Steps 1 (GDScript port).
- Tier 2 (per-substituent real-direction extension): Task 2 (Python proof), Task 3 Steps 2-3 (GDScript port).
- Rollback constraint (single commit, revertible): Task 3's explicit single-commit structure (Steps 1-7 stage everything, Step 8 is the only commit) plus Task 4 Step 4's dry-run verification.
- Leading/lagging safety constraint: Task 3 Step 7 (diff review before commit) plus Task 4 Step 3 (live behavior check).
- Bulge-away-from-partner must never regress (no reopening Bug V): Task 1 Step 4's explicit check.
- Stretch cap sourced from real data, not guessed: Task 2 Step 2's explicit instruction to use the harness's real found multiplier.
- Out-of-scope items from the design doc (Gelbin ring-tolerance checking, base rotation, leading/lagging, unpaired-first-pair symptom): no task touches any of `NitrogenBaseDeriver`, `apply_strand_direction()`, or `_pair_for_slot()` — confirmed by scope, not by an explicit task (nothing to do).

**Placeholder scan:** none — every step has runnable code or a concrete, checkable expectation. Task 2 Step 2 and Task 4 Step 1 both explicitly instruct recording the *real* result rather than assuming a predicted number, matching this project's own established convention for harness-discovery steps (not a placeholder — an intentional "read reality" instruction, same as the prior plan's Task 4 Step 8).

**Type consistency:** `derive_self_paired_ring()`'s signature is unchanged from the version it replaces. `derive_substituents()`'s new `is_self_paired_template: bool = false` parameter matches exactly what both call sites (Task 3 Steps 4-5) pass, and matches the same parameter name/type already used by `derive_self_paired_ring()`'s callers for the ring-rotation branch (`is_self_paired_template`, computed once per residue in `_rebuild_layout()`/`_derive_full_residue()`).
