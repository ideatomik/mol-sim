# Self-Paired Geometry Bake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the self-paired template's live, per-frame ring/chain geometry computation with a bake-once-cache-forever model, unlocking a real search budget (elbow-flex ring construction + free substituent placement) that a per-frame formula structurally cannot afford — resolving the chain/ring collision the live two-tier fix (Tier 1/Tier 2) could not.

**Architecture:** `RiboseDeriver` gains `bake_self_paired_geometry()` — a bake-time-only function combining Tier 1's proven rotation formula (unchanged), a revived elbow-flex construction for C3'/C4' (the abandoned "1b" idea, now searched without flicker risk since it never runs twice), and a free substituent-placement search for O3'/C5' (direction and distance, not locked to the live neighbor vector). `molecule_structure_renderer.gd` and `molecule_geometry_diagnostics.gd` gain a `"strand:slot"`-keyed cache — same convention `_fold_cache` already uses — computed once, translated to the residue's live world position every frame after. A Python harness proves the search against real fixtures before any GDScript is written, per this project's house convention.

**Tech Stack:** GDScript (Godot 4.6), Python 3 (analytic verification only, `diagnosis/`, never shipped/imported by the game).

## Global Constraints

- No automated test framework exists in this project. Verification is: (a) a standalone Python script in `diagnosis/` mirroring the GDScript math, (b) live F9 geometry dumps (`user://geometry_dump.txt`, on Windows `C:\Users\dhpcs\AppData\Roaming\Godot\app_userdata\MolSim\geometry_dump.txt`) plus screenshots, run in the Godot editor or the test chamber (`scenes/test_chamber.tscn`, this worktree only).
- Godot executable: `C:\Godot\Godot_v4.6.3-stable_win64_console.exe` (project root for this work: `E:\Godot Projects\MolSim\mol-sim\.claude\worktrees\self-paired-chain-fix`).
- `bond_length` in the real scene = 10.8 (`molecular_ring_bond_length_ratio` 0.2 × `nucleotide_slot_spacing` 54.0). Collision-clearance threshold = `COLLISION_CLEARANCE_RATIO` (2.0) × real `molecular_atom_radius` (4.0, the real scene's override — NOT the theme script's 6.0 default) = 8.0.
- Gelbin et al. (1996), JACS 118:519-529, Table 4, deoxyribose, N=47, ring-internal angles: C2'-C3'-C4' (at C3') 103.2°±1.0°, C3'-C4'-O4' (at C4') 105.6°±1.0°, C4'-O4'-C1' (at O4') 109.7°±1.4°. Tolerance bound is a DELTA from this project's regular-pentagon baseline (108.0° at every vertex), same convention the abandoned "1b" attempt established. Start the search at ±2σ; widen only as far as actually needed to find a working candidate, and report the real multiple needed — never assume ±2σ suffices without checking.
- Chirality safety: every candidate ring must match the canonical D-ribose vertex-order signed area (shoelace formula on `C1'→C2'→C3'→C4'→O4'`), verified directly, never assumed.
- **Rollback constraint (hard requirement, same as the superseded plan):** the entire GDScript behavior change (bake function + cache wiring + retiring Tier 1/2) ships as one commit. Python harness commits (non-behavioral) land separately, before it.
- **Leading/lagging safety (hard requirement, same as the superseded plan):** no line in `apply_strand_direction()`, `STRAND_DIRECTION_SIGN`, or the `is_self_paired_template = false` branch of either call site may change.
- O3'/C5' may now be searched over direction AND distance (a deliberate loosening from the superseded plan, justified in the Lattice doc: a self-paired residue's real same-strand-neighbor *side* never changes while self-paired, only its precise angle wobbles sub-degree with the template curve's physics — a one-time bake is insensitive to that by construction). What must NOT happen: pointing at the wrong neighbor entirely (previous vs. next) — the search window is centered on the real direction, not unbounded.
- Design doc of record: `docs/MolecularStructureDesign.md`, "Self-paired geometry is baked once per residue, not recomputed live" (2026-08-04). Superseded plan (As-Built amended, do not re-implement): `docs/superpowers/specs/2026-08-03-self-paired-chain-collision-fix-design.md`. Prior investigation history: `docs/MolecularStructure_BasePairExpansion.md` (Bug D through W), `docs/superpowers/specs/2026-08-03-template-strand-self-paired-rendering-design.md`.

---

## File Structure

- **Create:** `diagnosis/diag_self_paired_bake.py` — analytic verification harness (Tasks 1-2), self-contained per this project's `diagnosis/*.py` convention.
- **Modify:** `scripts/ribose_deriver.gd` — `derive_self_paired_ring()` and `_required_chain_reach()` (and the `is_self_paired_template` branches inside `derive_substituents()`) are deleted; a new `bake_self_paired_geometry()` is added (Task 3).
- **Modify:** `scripts/molecule_structure_renderer.gd` — adds `_self_paired_geometry_cache: Dictionary` and `invalidate_self_paired_geometry()`; `_rebuild_layout()`'s self-paired branch becomes a cache-or-bake lookup instead of a live formula call (Task 4).
- **Modify:** `scripts/molecule_geometry_diagnostics.gd` — `_derive_full_residue()` reads the SAME cache via the passed-in `renderer` reference (so a dump always reflects exactly what's rendered, never a second independent computation) (Task 4).

---

## Task 1: Python harness — ring construction (rotation + elbow-flex)

**Files:**
- Create: `diagnosis/diag_self_paired_bake.py`

**Interfaces:**
- Produces: printed values this task's steps read directly, matching this project's `diagnosis/*.py` convention.
- Consumes: the same three real fixtures already established (boundary top, boundary bottom, interior) — copied here, not imported, matching this project's "each diag script stands alone" convention.

- [ ] **Step 1: Geometry primitives, fixtures, and Tier 1's proven rotation (reused unchanged)**

Create `diagnosis/diag_self_paired_bake.py`:

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
    return math.atan2(a[0]*b[1] - a[1]*b[0], dot(a, b))
def wrap_pi(x):
    return (x + math.pi) % (2 * math.pi) - math.pi
def orthogonal(a): return (a[1], -a[0])

TAU = 2 * math.pi
BOND_LENGTH = 10.8
MOLECULAR_ATOM_RADIUS = 4.0  # real scene override, not theme script's 6.0 default
COLLISION_CLEARANCE_RATIO = 2.0
COLLISION_THRESHOLD = COLLISION_CLEARANCE_RATIO * MOLECULAR_ATOM_RADIUS  # 8.0
BULGE_DOT_MARGIN_DEG = 5.0

RING_ROLE_SUFFIXES = ["c1_prime", "c2_prime", "c3_prime", "c4_prime", "o4_prime"]

def derive_regular_ring(bond_length, start_angle=-math.pi/2.0):
    n = 5
    R = bond_length / (2.0 * math.sin(math.pi / n))
    step = TAU / n
    return {suf: (math.cos(start_angle + i*step) * R, math.sin(start_angle + i*step) * R)
            for i, suf in enumerate(RING_ROLE_SUFFIXES)}

# ---- Real fixture data (same three cases used throughout this project's
# self-paired investigation, copied rather than imported) ----
FIXTURE_A_TOWARD_NEXT = (54.0, 0.394745)
FIXTURE_A_TOWARD_PREVIOUS = (0.0, 0.0)
FIXTURE_A_PAIRING_DIRECTION = (0.0, 160.0)

FIXTURE_B_TOWARD_NEXT = (0.0, 0.0)
FIXTURE_B_TOWARD_PREVIOUS = (54.0, 0.394745)
FIXTURE_B_PAIRING_DIRECTION = (0.0, -160.0)

FIXTURE_C_TOWARD_NEXT = (54.0, -0.0862)
FIXTURE_C_TOWARD_PREVIOUS = (-54.0, 0.0862)
FIXTURE_C_PAIRING_DIRECTION = (0.0, 160.0)

def tier1_rotation(natural_ring, pairing_direction, toward_next, toward_previous):
    """Unchanged from the shipped fix (diagnosis/diag_chain_ring_clearance_fix.py)
    -- proven, not re-derived. Returns (rotated_ring, theta)."""
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
    fixed_tiebreak_sign = 1.0 if (bulge_vec[0]*ring_bond_dir0[1] - bulge_vec[1]*ring_bond_dir0[0]) >= 0.0 else -1.0
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
            half = math.pi/2.0 - math.radians(BULGE_DOT_MARGIN_DEG)
            delta = wrap_pi(theta_ideal - theta_center)
            theta = theta_ideal if abs(delta) <= half else theta_center + fixed_tiebreak_sign * half
    result = {k: add(pivot, rotated(sub(v, pivot), theta)) for k, v in natural_ring.items()}
    return result, theta

def bulge_vs_pairing_dot(ring, pairing_direction):
    pivot = ring["c1_prime"]
    bulge = scale(add(add(ring["c2_prime"], ring["c3_prime"]), add(ring["c4_prime"], ring["o4_prime"])), 0.25)
    bulge_vec = sub(bulge, pivot)
    if length(bulge_vec) == 0.0 or length(pairing_direction) == 0.0:
        return 0.0
    return dot(normalized(bulge_vec), normalized(pairing_direction))

print("=== Fixture sanity check ===")
print("Fixture A toward_next:", FIXTURE_A_TOWARD_NEXT, "length:", length(FIXTURE_A_TOWARD_NEXT))
print("Fixture A pairing_direction:", FIXTURE_A_PAIRING_DIRECTION, "length:", length(FIXTURE_A_PAIRING_DIRECTION))
```

- [ ] **Step 2: Run it, confirm the sanity check**

```bash
cd "E:/Godot Projects/MolSim/mol-sim/.claude/worktrees/self-paired-chain-fix" && python diagnosis/diag_self_paired_bake.py
```
Expected: the two fixture lines print with lengths ≈54.001 and 160.0.

- [ ] **Step 3: Add the Gelbin tolerance checker and the elbow-linkage construction**

Append:

```python
GELBIN_RING_INTERNAL_MEAN_DEG = {"c3_prime": 103.2, "c4_prime": 105.6, "o4_prime": 109.7}
GELBIN_RING_INTERNAL_SIGMA_DEG = {"c3_prime": 1.0, "c4_prime": 1.0, "o4_prime": 1.4}
REGULAR_PENTAGON_INTERIOR_DEG = 108.0

def angle_at(prev_pt, vertex_pt, next_pt):
    v1 = normalized(sub(prev_pt, vertex_pt))
    v2 = normalized(sub(next_pt, vertex_pt))
    return math.degrees(math.acos(max(-1.0, min(1.0, dot(v1, v2)))))

def within_gelbin_delta(vertex_suffix, measured_deg, sigma_multiple):
    sigma = GELBIN_RING_INTERNAL_SIGMA_DEG[vertex_suffix]
    delta = abs(measured_deg - REGULAR_PENTAGON_INTERIOR_DEG)
    return delta <= sigma_multiple * sigma

def signed_area(points_in_order):
    n = len(points_in_order)
    s = 0.0
    for i in range(n):
        x1, y1 = points_in_order[i]
        x2, y2 = points_in_order[(i + 1) % n]
        s += x1*y2 - x2*y1
    return 0.5 * s

def elbow_candidate(a_fixed, b_fixed, link_len, alpha, prefer_near):
    """Three equal links between fixed a_fixed (C2') and b_fixed (O4'),
    through two free joints c3, c4. Returns (c3, c4) or None if alpha
    places c3 unreachable from b_fixed by the remaining two links."""
    d_ab = length(sub(b_fixed, a_fixed))
    if d_ab == 0.0 or d_ab > 3 * link_len:
        return None
    u = normalized(sub(b_fixed, a_fixed))
    v = orthogonal(u)
    c3 = add(a_fixed, add(scale(u, link_len * math.cos(alpha)), scale(v, link_len * math.sin(alpha))))
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
    c4 = cand1 if length(sub(cand1, prefer_near)) <= length(sub(cand2, prefer_near)) else cand2
    return (c3, c4)
```

- [ ] **Step 4: Add the ring-search stage (rotation reused, elbow-flex swept, tolerance widened only if needed)**

Append:

```python
canonical_ring = derive_regular_ring(BOND_LENGTH)
canonical_order = [canonical_ring[s] for s in RING_ROLE_SUFFIXES]
canonical_sign_positive = signed_area(canonical_order) > 0.0

ELBOW_SEARCH_HALF_WINDOW_DEG = 40.0
ELBOW_SEARCH_STEP_DEG = 1.0
TOLERANCE_WIDEN_STEPS = [2.0, 3.0, 4.0, 6.0, 8.0]  # sigma multiples tried in order; report which one worked

def search_ring(natural, pairing_direction, toward_next, toward_previous):
    """Stage 1: reuse Tier 1's proven theta, then sweep the elbow angle
    around the natural (unflexed) joint angle, at progressively wider
    Gelbin tolerance only if nothing passes at the previous width.
    Re-checks bulge_vs_pairing_dot on the FLEXED ring at every candidate
    -- C3'/C4' contribute to the bulge average, so flexing them can shift
    it; this must be verified per-candidate; it cannot be assumed
    preserved from the unflexed rotation."""
    rotated_ring, theta = tier1_rotation(natural, pairing_direction, toward_next, toward_previous)
    c1, c2, o4 = rotated_ring["c1_prime"], rotated_ring["c2_prime"], rotated_ring["o4_prime"]
    natural_c3, natural_c4 = rotated_ring["c3_prime"], rotated_ring["c4_prime"]
    alpha0 = angle_to((1.0, 0.0), sub(natural_c3, c2)) if False else vangle(sub(natural_c3, c2))
    for sigma_mult in TOLERANCE_WIDEN_STEPS:
        best = None
        steps = int(ELBOW_SEARCH_HALF_WINDOW_DEG / ELBOW_SEARCH_STEP_DEG)
        for i in range(-steps, steps + 1):
            alpha = alpha0 + math.radians(i * ELBOW_SEARCH_STEP_DEG)
            cand = elbow_candidate(c2, o4, BOND_LENGTH, alpha, natural_c4)
            if cand is None:
                continue
            c3, c4 = cand
            if not within_gelbin_delta("c3_prime", angle_at(c2, c3, c4), sigma_mult):
                continue
            if not within_gelbin_delta("c4_prime", angle_at(c3, c4, o4), sigma_mult):
                continue
            if not within_gelbin_delta("o4_prime", angle_at(c4, o4, c1), sigma_mult):
                continue
            ring_now = {"c1_prime": c1, "c2_prime": c2, "c3_prime": c3, "c4_prime": c4, "o4_prime": o4}
            order_now = [ring_now[s] for s in RING_ROLE_SUFFIXES]
            if (signed_area(order_now) > 0.0) != canonical_sign_positive:
                continue
            bvd = bulge_vs_pairing_dot(ring_now, pairing_direction)
            if bvd > -0.05:
                continue
            spread = length(sub(c3, c1)) + length(sub(c4, c1))  # cheap proxy: more room for substituents later
            if best is None or spread > best["spread"]:
                best = dict(ring=ring_now, theta=theta, alpha_deg=i * ELBOW_SEARCH_STEP_DEG,
                            sigma_mult=sigma_mult, bulge_dot=bvd, spread=spread)
        if best is not None:
            return best
    return None  # stop condition: report this honestly, do not force a result

def vangle(a): return math.atan2(a[1], a[0])

result_a = search_ring(canonical_ring, FIXTURE_A_PAIRING_DIRECTION, FIXTURE_A_TOWARD_NEXT, FIXTURE_A_TOWARD_PREVIOUS)
result_b = search_ring(canonical_ring, FIXTURE_B_PAIRING_DIRECTION, FIXTURE_B_TOWARD_NEXT, FIXTURE_B_TOWARD_PREVIOUS)
result_c = search_ring(canonical_ring, FIXTURE_C_PAIRING_DIRECTION, FIXTURE_C_TOWARD_NEXT, FIXTURE_C_TOWARD_PREVIOUS)

for label, r in [("A (boundary top)", result_a), ("B (boundary bottom)", result_b), ("C (interior)", result_c)]:
    print(f"\n=== Ring search: {label} ===")
    if r is None:
        print("NO VALID RING CANDIDATE at any tolerance tried -- stop condition, report honestly.")
    else:
        print(f"theta={math.degrees(r['theta']):.2f} deg, elbow alpha offset={r['alpha_deg']:.1f} deg, "
              f"tolerance needed=+/-{r['sigma_mult']}sigma, bulge_dot={r['bulge_dot']:.4f}")
```

- [ ] **Step 5: Run it and record the real result**

```bash
cd "E:/Godot Projects/MolSim/mol-sim/.claude/worktrees/self-paired-chain-fix" && python diagnosis/diag_self_paired_bake.py
```

Read all three cases. This is the real, load-bearing result of this task:
- Record which tolerance width (`sigma_mult`) each fixture actually needed — honestly, even if it's wider than ±2σ. This is expected to potentially widen (the design doc's own framing: "widened only as far as actually needed") — do not treat anything short of the maximum tried (±8σ) as a failure requiring escalation; only a `None` result (no tolerance width worked at all) is a real stop-condition case worth flagging before proceeding to Task 2.
- Record `bulge_dot` for each — must read ≤ -0.05 (already enforced by the search, but confirm the printed values honestly reflect that, not a bug in the filter).

- [ ] **Step 6: Commit**

```bash
git add diagnosis/diag_self_paired_bake.py
git commit -m "$(cat <<'EOF'
Add Stage 1 (ring construction) harness for the self-paired geometry bake

Reuses the shipped Tier 1 rotation unchanged, adds the revived elbow-
flex construction (the abandoned "1b" idea) searched over a window
around the natural joint angle, widening Gelbin tolerance only as far as
real fixture data requires. Re-checks bulge_vs_pairing_dot on the FLEXED
ring per candidate, not assumed preserved from the unflexed rotation.
EOF
)"
```

---

## Task 2: Python harness — substituent placement search

**Files:**
- Modify: `diagnosis/diag_self_paired_bake.py`

**Interfaces:**
- Produces: printed values this task's steps read directly.
- Consumes: `search_ring()`'s results from Task 1 (same file).

- [ ] **Step 1: Add the substituent search**

Append:

```python
SUBSTITUENT_SEARCH_HALF_WINDOW_DEG = 90.0
SUBSTITUENT_SEARCH_ANGLE_STEP_DEG = 3.0
SUBSTITUENT_SEARCH_DIST_STEPS = 6  # bond_length up to 2x bond_length

def min_clearance_to_ring(point, ring):
    return min(length(sub(point, p)) for p in ring.values())

def search_substituent(start_pos, natural_dir, ring, real_neighbor_distance):
    """Direction AND distance searched jointly, centered on natural_dir
    (the real toward_next/toward_previous direction) -- window bounded so
    this can never point at the wrong neighbor entirely, per the Global
    Constraints. max_safe_reach mirrors the shipped Tier 2's real-
    neighbor-distance cap (never past half the real neighbor distance
    minus the collision threshold)."""
    if length(natural_dir) <= 0.0:
        return None
    natural_hat = normalized(natural_dir)
    natural_angle = vangle(natural_hat)
    max_safe_reach = max(BOND_LENGTH, real_neighbor_distance * 0.5 - COLLISION_THRESHOLD)
    best = None
    steps = int(SUBSTITUENT_SEARCH_HALF_WINDOW_DEG / SUBSTITUENT_SEARCH_ANGLE_STEP_DEG)
    for i in range(-steps, steps + 1):
        angle = natural_angle + math.radians(i * SUBSTITUENT_SEARCH_ANGLE_STEP_DEG)
        direction = (math.cos(angle), math.sin(angle))
        for j in range(SUBSTITUENT_SEARCH_DIST_STEPS + 1):
            dist = BOND_LENGTH + (max_safe_reach - BOND_LENGTH) * (j / SUBSTITUENT_SEARCH_DIST_STEPS)
            point = add(start_pos, scale(direction, dist))
            clearance = min_clearance_to_ring(point, ring)
            if best is None or clearance > best["clearance"]:
                best = dict(point=point, direction=direction, dist=dist, clearance=clearance,
                            angle_offset_deg=i * SUBSTITUENT_SEARCH_ANGLE_STEP_DEG)
    return best

def run_full_bake(label, ring_result, toward_next, toward_previous):
    print(f"\n=== Full bake: {label} ===")
    if ring_result is None:
        print("No ring candidate -- cannot search substituents.")
        return None
    ring = ring_result["ring"]
    tn, tp = toward_next, toward_previous
    if length(tn) <= 0.0 and length(tp) > 0.0:
        tn = scale(tp, -1.0)
    elif length(tp) <= 0.0 and length(tn) > 0.0:
        tp = scale(tn, -1.0)
    o3_result = search_substituent(ring["c3_prime"], tn, ring, length(tn))
    c5_result = search_substituent(ring["c4_prime"], tp, ring, length(tp))
    print(f"O3': angle offset={o3_result['angle_offset_deg']:.1f} deg, dist={o3_result['dist']:.4f} "
          f"({o3_result['dist']/BOND_LENGTH:.2f}x bond_length), clearance={o3_result['clearance']:.4f} "
          f"(target {COLLISION_THRESHOLD}) -- {'CLEARS' if o3_result['clearance'] >= COLLISION_THRESHOLD else 'DOES NOT CLEAR'}")
    print(f"C5': angle offset={c5_result['angle_offset_deg']:.1f} deg, dist={c5_result['dist']:.4f} "
          f"({c5_result['dist']/BOND_LENGTH:.2f}x bond_length), clearance={c5_result['clearance']:.4f} "
          f"(target {COLLISION_THRESHOLD}) -- {'CLEARS' if c5_result['clearance'] >= COLLISION_THRESHOLD else 'DOES NOT CLEAR'}")
    return dict(ring=ring_result, o3=o3_result, c5=c5_result)

full_a = run_full_bake("A (boundary top)", result_a, FIXTURE_A_TOWARD_NEXT, FIXTURE_A_TOWARD_PREVIOUS)
full_b = run_full_bake("B (boundary bottom)", result_b, FIXTURE_B_TOWARD_NEXT, FIXTURE_B_TOWARD_PREVIOUS)
full_c = run_full_bake("C (interior)", result_c, FIXTURE_C_TOWARD_NEXT, FIXTURE_C_TOWARD_PREVIOUS)
```

- [ ] **Step 2: Run it and record the real result**

```bash
cd "E:/Godot Projects/MolSim/mol-sim/.claude/worktrees/self-paired-chain-fix" && python diagnosis/diag_self_paired_bake.py
```

Read every `CLEARS`/`DOES NOT CLEAR` line. This is the real, load-bearing result of the whole bake design:
- If every case reads `CLEARS`: the bake fully resolves the collision the live fix couldn't. Proceed to Task 3.
- If some case reads `DOES NOT CLEAR`: record the real clearance achieved (still likely better than the live fix's 3.92-unit floor — compare honestly) and proceed to Task 3 regardless, documenting the specific residue/case as still-open, same "ship what works, document the rest" pattern this project has used throughout. Do not widen the substituent search window further without reporting why the current window (±90°, up to 2× bond_length) was insufficient first — this is meant to be a large search already; if it's not enough, that is itself information worth recording before trying a bigger one.

- [ ] **Step 3: Commit**

```bash
git add diagnosis/diag_self_paired_bake.py
git commit -m "$(cat <<'EOF'
Add Stage 2 (substituent placement) search to the self-paired geometry bake

Direction and distance searched jointly, centered on and bounded around
the real toward_next/toward_previous direction (never able to point at
the wrong neighbor). Confirms whether the combined ring + substituent
bake fully resolves the collision the live Tier 1/Tier 2 fix could not.
EOF
)"
```

---

## Task 3: Port the validated bake into GDScript

**Files:**
- Modify: `scripts/ribose_deriver.gd`

**Interfaces:**
- Removes: `derive_self_paired_ring()`, `_required_chain_reach()`, `CHAIN_EXTENSION_STRETCH_CAP_RATIO`, the `is_self_paired_template` branches inside `derive_substituents()` (that parameter is removed from `derive_substituents()`'s signature entirely — it no longer has a self-paired-specific behavior; the bake function owns that now).
- Produces: `RiboseDeriver.bake_self_paired_geometry(topology: MoleculeTopology, role_prefix: String, bond_length: float, pairing_direction: Vector2, toward_next: Vector2, toward_previous: Vector2, real_neighbor_distance_next: float, real_neighbor_distance_previous: float, molecular_atom_radius: float) -> Dictionary` — returns `{ring_positions: Dictionary, substituent_positions: Dictionary}`, both keyed by atom id exactly like `derive_ring()`/`derive_substituents()` already return, so the caller's existing downstream code (base layout, world-position translation) needs no changes beyond reading these two sub-dictionaries instead of calling the two separate functions.
- Consumes: `MoleculeTopology.find_by_role()`, `derive_regular_ring()` (unchanged), the validated Task 1/2 Python math, ported line-for-line per this project's established convention.

- [ ] **Step 1: Port Stage 1 (ring search) into `ribose_deriver.gd`**

Delete `derive_self_paired_ring()` and its doc comment entirely. In its place, add (translating Task 1's `search_ring()`, `elbow_candidate()`, `angle_at()`, `within_gelbin_delta()`, `signed_area()` line-for-line, GDScript syntax):

```gdscript
## Self-paired geometry bake, Stage 1: ring construction (docs/
## MolecularStructureDesign.md, "Self-paired geometry is baked once per
## residue, not recomputed live", 2026-08-04). Reuses the proven Tier 1
## rotation unchanged, then sweeps an elbow-flex angle (the revived
## abandoned "1b" idea) around the natural joint angle, widening Gelbin
## tolerance only as far as diagnosis/diag_self_paired_bake.py's real run
## found necessary. Bake-time only -- called at most once per residue,
## never per frame, so a real search budget is available here that was
## never available to the retired live formula.
const ELBOW_SEARCH_HALF_WINDOW_DEG: float = 40.0
const ELBOW_SEARCH_STEP_DEG: float = 1.0
const GELBIN_RING_INTERNAL_SIGMA_DEG: Dictionary = {"c3_prime": 1.0, "c4_prime": 1.0, "o4_prime": 1.4}
const REGULAR_PENTAGON_INTERIOR_DEG: float = 108.0
## Sigma multiples tried in order until one yields a valid candidate --
## confirmed against diagnosis/diag_self_paired_bake.py's real run before
## this port; update this list if that harness found different widths
## necessary.
const TOLERANCE_WIDEN_STEPS: Array[float] = [2.0, 3.0, 4.0, 6.0, 8.0]

static func _angle_at(prev_pt: Vector2, vertex_pt: Vector2, next_pt: Vector2) -> float:
	var v1: Vector2 = (prev_pt - vertex_pt).normalized()
	var v2: Vector2 = (next_pt - vertex_pt).normalized()
	return rad_to_deg(acos(clamp(v1.dot(v2), -1.0, 1.0)))

static func _within_gelbin_delta(vertex_suffix: String, measured_deg: float, sigma_multiple: float) -> bool:
	var sigma: float = GELBIN_RING_INTERNAL_SIGMA_DEG[vertex_suffix]
	return abs(measured_deg - REGULAR_PENTAGON_INTERIOR_DEG) <= sigma_multiple * sigma

static func _signed_area(points_in_order: Array) -> float:
	var s: float = 0.0
	var n: int = points_in_order.size()
	for i in range(n):
		var p1: Vector2 = points_in_order[i]
		var p2: Vector2 = points_in_order[(i + 1) % n]
		s += p1.x * p2.y - p2.x * p1.y
	return 0.5 * s

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

## Stage 1 result dictionary keys: "ring" (Dictionary, atom id -> Vector2),
## "theta" (float, radians). Returns {} (empty) if no candidate was found
## at any tolerance width tried -- the caller (Stage 2 / the bake
## orchestrator) must handle this as the documented stop-condition case,
## not assume a result.
static func _search_self_paired_ring(topology: MoleculeTopology, role_prefix: String, natural_ring_positions: Dictionary, pivot: Vector2, pairing_direction: Vector2, bond_length: float, toward_next: Vector2, toward_previous: Vector2) -> Dictionary:
	var rotated_ring: Dictionary = derive_self_paired_ring_rotation_only(topology, role_prefix, natural_ring_positions, pivot, pairing_direction, bond_length, toward_next, toward_previous)
	var c2_id: int = topology.find_by_role(role_prefix + "c2_prime")
	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var o4_id: int = topology.find_by_role(role_prefix + "o4_prime")
	var c1: Vector2 = rotated_ring[topology.find_by_role(role_prefix + "c1_prime")]
	var c2: Vector2 = rotated_ring[c2_id]
	var o4: Vector2 = rotated_ring[o4_id]
	var natural_c3: Vector2 = rotated_ring[c3_id]
	var natural_c4: Vector2 = rotated_ring[c4_id]
	var alpha0: float = (natural_c3 - c2).angle()

	var canonical_order: Array = [natural_ring_positions[topology.find_by_role(role_prefix + "c1_prime")], natural_ring_positions[c2_id], natural_ring_positions[c3_id], natural_ring_positions[c4_id], natural_ring_positions[o4_id]]
	var canonical_sign_positive: bool = _signed_area(canonical_order) > 0.0

	for sigma_mult in TOLERANCE_WIDEN_STEPS:
		var best: Dictionary = {}
		var best_spread: float = -INF
		var steps: int = int(ELBOW_SEARCH_HALF_WINDOW_DEG / ELBOW_SEARCH_STEP_DEG)
		for i in range(-steps, steps + 1):
			var alpha: float = alpha0 + deg_to_rad(i * ELBOW_SEARCH_STEP_DEG)
			var candidate: Array = _elbow_candidate(c2, o4, bond_length, alpha, natural_c4)
			if candidate.is_empty():
				continue
			var c3: Vector2 = candidate[0]
			var c4: Vector2 = candidate[1]
			if not _within_gelbin_delta("c3_prime", _angle_at(c2, c3, c4), sigma_mult):
				continue
			if not _within_gelbin_delta("c4_prime", _angle_at(c3, c4, o4), sigma_mult):
				continue
			if not _within_gelbin_delta("o4_prime", _angle_at(c4, o4, c1), sigma_mult):
				continue
			var ring_now: Dictionary = {topology.find_by_role(role_prefix + "c1_prime"): c1, c2_id: c2, c3_id: c3, c4_id: c4, o4_id: o4}
			var order_now: Array = [c1, c2, c3, c4, o4]
			if (_signed_area(order_now) > 0.0) != canonical_sign_positive:
				continue
			var bulge_dot: float = _bulge_vs_pairing_dot(ring_now, c1, c2_id, c3_id, c4_id, o4_id, pairing_direction)
			if bulge_dot > -0.05:
				continue
			var spread: float = c3.distance_to(c1) + c4.distance_to(c1)
			if spread > best_spread:
				best_spread = spread
				best = ring_now
		if not best.is_empty():
			return best
	return {}

static func _bulge_vs_pairing_dot(ring: Dictionary, c1: Vector2, c2_id: int, c3_id: int, c4_id: int, o4_id: int, pairing_direction: Vector2) -> float:
	var bulge: Vector2 = (ring[c2_id] + ring[c3_id] + ring[c4_id] + ring[o4_id]) * 0.25
	var bulge_vec: Vector2 = bulge - c1
	if bulge_vec.length() <= 0.0 or pairing_direction.length() <= 0.0:
		return 0.0
	return bulge_vec.normalized().dot(pairing_direction.normalized())
```

**Note on `derive_self_paired_ring_rotation_only`:** this is Tier 1's exact, already-shipped rotation formula, kept as a small private helper (rename the current `derive_self_paired_ring()` body to this name rather than deleting it outright) — Stage 1 calls it to get the rigid-rotated starting point before flexing. Confirm this rename compiles before continuing; nothing else should reference the old public name after this step.

- [ ] **Step 2: Port Stage 2 (substituent search) and the bake orchestrator**

Append:

```gdscript
## Self-paired geometry bake, Stage 2 (docs/MolecularStructureDesign.md,
## same entry as Stage 1 above): O3'/C5' direction AND distance searched
## jointly, centered on and bounded around the real toward_next/
## toward_previous direction -- never able to point at the wrong
## neighbor, per this project's hard-won constraint from four
## independently-failed prior attempts (docs/MolecularStructure_
## BasePairExpansion.md, Bug V/W). Bake-time only, same as Stage 1.
const SUBSTITUENT_SEARCH_HALF_WINDOW_DEG: float = 90.0
const SUBSTITUENT_SEARCH_ANGLE_STEP_DEG: float = 3.0
const SUBSTITUENT_SEARCH_DIST_STEPS: int = 6

static func _min_clearance_to_ring(point: Vector2, ring_positions: Dictionary) -> float:
	var best: float = INF
	for p in ring_positions.values():
		best = min(best, point.distance_to(p))
	return best

static func _search_substituent(start_pos: Vector2, natural_dir: Vector2, ring_positions: Dictionary, bond_length: float, real_neighbor_distance: float, collision_clearance_threshold: float) -> Dictionary:
	if natural_dir.length() <= 0.0:
		return {}
	var natural_angle: float = natural_dir.angle()
	var max_safe_reach: float = max(bond_length, real_neighbor_distance * 0.5 - collision_clearance_threshold)
	var best: Dictionary = {}
	var best_clearance: float = -INF
	var steps: int = int(SUBSTITUENT_SEARCH_HALF_WINDOW_DEG / SUBSTITUENT_SEARCH_ANGLE_STEP_DEG)
	for i in range(-steps, steps + 1):
		var angle: float = natural_angle + deg_to_rad(i * SUBSTITUENT_SEARCH_ANGLE_STEP_DEG)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		for j in range(SUBSTITUENT_SEARCH_DIST_STEPS + 1):
			var dist: float = bond_length + (max_safe_reach - bond_length) * (float(j) / float(SUBSTITUENT_SEARCH_DIST_STEPS))
			var point: Vector2 = start_pos + direction * dist
			var clearance: float = _min_clearance_to_ring(point, ring_positions)
			if clearance > best_clearance:
				best_clearance = clearance
				best = {point = point, direction = direction, dist = dist, clearance = clearance}
	return best

## The single public entry point for this whole bake (docs/
## MolecularStructureDesign.md, "Self-paired geometry is baked once per
## residue, not recomputed live"). Returns {} (empty) if Stage 1 found no
## ring candidate at any tolerance width -- the caller (the renderer's
## cache-or-bake lookup, Task 4) must handle this as the documented
## stop-condition case: fall back to the rigid rotation-only construction
## (derive_self_paired_ring_rotation_only) rather than crash or render
## nothing.
static func bake_self_paired_geometry(topology: MoleculeTopology, role_prefix: String, bond_length: float, pairing_direction: Vector2, toward_next: Vector2, toward_previous: Vector2, real_neighbor_distance_next: float, real_neighbor_distance_previous: float, molecular_atom_radius: float) -> Dictionary:
	var natural_ring: Dictionary = derive_ring(topology, role_prefix, bond_length)
	var pivot: Vector2 = natural_ring[topology.find_by_role(role_prefix + "c1_prime")]
	var ring_positions: Dictionary = _search_self_paired_ring(topology, role_prefix, natural_ring, pivot, pairing_direction, bond_length, toward_next, toward_previous)
	if ring_positions.is_empty():
		ring_positions = derive_self_paired_ring_rotation_only(topology, role_prefix, natural_ring, pivot, pairing_direction, bond_length, toward_next, toward_previous)

	var collision_clearance_threshold: float = COLLISION_CLEARANCE_RATIO * molecular_atom_radius

	var c3_id: int = topology.find_by_role(role_prefix + "c3_prime")
	var c4_id: int = topology.find_by_role(role_prefix + "c4_prime")
	var tn: Vector2 = toward_next
	var tp: Vector2 = toward_previous
	if tn.length() <= 0.0 and tp.length() > 0.0:
		tn = -tp
	elif tp.length() <= 0.0 and tn.length() > 0.0:
		tp = -tn

	var substituent_positions: Dictionary = derive_substituents(topology, role_prefix, ring_positions, bond_length, toward_next, toward_previous)
	if ring_positions.has(c3_id) and tn.length() > 0.0:
		var o3_id: int = topology.find_by_role(role_prefix + "o3_prime")
		var o3_result: Dictionary = _search_substituent(ring_positions[c3_id], tn, ring_positions, bond_length, real_neighbor_distance_next, collision_clearance_threshold)
		if not o3_result.is_empty():
			substituent_positions[o3_id] = o3_result.point
	if ring_positions.has(c4_id) and tp.length() > 0.0:
		var c5_id: int = topology.find_by_role(role_prefix + "c5_prime")
		var c5_result: Dictionary = _search_substituent(ring_positions[c4_id], tp, ring_positions, bond_length, real_neighbor_distance_previous, collision_clearance_threshold)
		if not c5_result.is_empty():
			# O5'/alpha-phosphate continue chained from the searched C5' in
			# its own found direction, same bond_length increments as
			# derive_substituents() already applies -- recomputed here since
			# C5' itself moved.
			var o5_id: int = topology.find_by_role(role_prefix + "o5_prime")
			var alpha_id: int = topology.find_by_role(role_prefix + "alpha_phosphate")
			substituent_positions[c5_id] = c5_result.point
			if o5_id != -1:
				var o5_pos: Vector2 = c5_result.point + c5_result.direction * bond_length
				substituent_positions[o5_id] = o5_pos
				if alpha_id != -1:
					substituent_positions[alpha_id] = o5_pos + c5_result.direction * bond_length

	return {ring_positions = ring_positions, substituent_positions = substituent_positions}
```

- [ ] **Step 3: Remove Tier 2's live logic and simplify `derive_substituents()`**

In `derive_substituents()`, delete the `is_self_paired_template` parameter entirely, and delete the `is_self_paired_template`-gated branches inside the O3'/C5' blocks (both `reach`/`if is_self_paired_template and ...` blocks) — restore those two blocks to their pre-Tier-2 form (always `outward * bond_length`, exactly as this function behaved before any of this session's self-paired work). Also delete `_required_chain_reach()` and `CHAIN_EXTENSION_STRETCH_CAP_RATIO` entirely — nothing calls them anymore (the bake's Stage 2 uses `_search_substituent()` instead, and applies its own result directly rather than through `derive_substituents()`'s reach logic). `COLLISION_CLEARANCE_RATIO` stays (still used by `bake_self_paired_geometry()`).

- [ ] **Step 4: Confirm the file compiles**

```bash
cd "E:/Godot Projects/MolSim/mol-sim/.claude/worktrees/self-paired-chain-fix" && "C:\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . --check-only --quit
```
(Or open in the editor and check the Output panel.) Fix any reference to the deleted `derive_self_paired_ring()`/`is_self_paired_template` parameter that Task 4 hasn't updated yet — expected at this point, since Task 4 updates the call sites; confirm the error is specifically about the two call sites, not a syntax error inside this file.

- [ ] **Step 5: No commit yet** (this task's changes are only valid once Task 4's call-site updates land — commit together at the end of Task 4, per the single-commit Rollback constraint)

---

## Task 4: Wire the cache into the renderer and diagnostics, retire the live path

**Files:**
- Modify: `scripts/molecule_structure_renderer.gd`
- Modify: `scripts/molecule_geometry_diagnostics.gd`

**Interfaces:**
- Produces: `MoleculeStructureRenderer._self_paired_geometry_cache: Dictionary` (keyed `"strand:slot"`), `MoleculeStructureRenderer.invalidate_self_paired_geometry(strand: String, slot: int) -> void` (public, named seam for future ligase/polymerase-interaction work — not called anywhere yet, per the design doc).
- Consumes: `RiboseDeriver.bake_self_paired_geometry()` (Task 3).

**This task's diff, together with Task 3's, is ONE commit — the Rollback constraint.**

- [ ] **Step 1: Add the cache and invalidation entry point**

In `scripts/molecule_structure_renderer.gd`, near `_fold_cache`'s declaration, add:

```gdscript
## "strand:slot" -> {ring_positions: Dictionary, substituent_positions: Dictionary}
## (RiboseDeriver.bake_self_paired_geometry()'s return shape). Computed
## once per residue, on first encounter while self-paired, never
## recomputed after -- same convention as _fold_cache, now extended to
## LOCAL GEOMETRY for this one render state (docs/MolecularStructureDesign.md,
## "Self-paired geometry is baked once per residue, not recomputed live").
var _self_paired_geometry_cache: Dictionary = {}

## Named, callable invalidation seam for future work this cache does not
## yet need to know about (an unbound/exposed phosphate at a ligase site,
## distinct polymerase-interaction geometry) -- decided at Nucleation,
## docs/MolecularStructureDesign.md's same entry. Nothing calls this yet;
## it exists so that future work has an obvious attachment point instead
## of forcing a redesign of this cache.
func invalidate_self_paired_geometry(strand: String, slot: int) -> void:
	_self_paired_geometry_cache.erase("%s:%d" % [strand, slot])
```

- [ ] **Step 2: Replace `_rebuild_layout()`'s self-paired branch with a cache-or-bake lookup**

Find (the block Task 3's Branch-B-era code left in place):
```gdscript
		if is_self_paired_template:
			ring_positions = RiboseDeriver.derive_self_paired_ring(topology, "incoming.", ring_positions, c1_local, pairing_direction, bond_length, toward_next, toward_previous)
		else:
			ring_positions = RiboseDeriver.apply_strand_direction(ring_positions, c1_local, _strand_direction_sign(entry.strand))
```
Replace with:
```gdscript
		var substituent_positions: Dictionary = {}
		if is_self_paired_template:
			var cache_key: String = "%s:%d" % [entry.strand, entry.slot]
			if not _self_paired_geometry_cache.has(cache_key):
				_self_paired_geometry_cache[cache_key] = RiboseDeriver.bake_self_paired_geometry(topology, "incoming.", bond_length, pairing_direction, toward_next, toward_previous, position_by_key.get(more_3prime_key, world_pos).distance_to(world_pos) if position_by_key.has(more_3prime_key) else 0.0, position_by_key.get(more_5prime_key, world_pos).distance_to(world_pos) if position_by_key.has(more_5prime_key) else 0.0, tm.molecular_atom_radius)
			var baked: Dictionary = _self_paired_geometry_cache[cache_key]
			ring_positions = baked.ring_positions
			substituent_positions = baked.substituent_positions
		else:
			ring_positions = RiboseDeriver.apply_strand_direction(ring_positions, c1_local, _strand_direction_sign(entry.strand))
```
(`more_3prime_key`/`more_5prime_key` are the same variables `_rebuild_layout()` already computes a few lines above this block for `toward_next`/`toward_previous` themselves — reuse them directly, do not recompute.)

Find the existing line just below (previously always run for every residue):
```gdscript
		var substituent_positions: Dictionary = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous, is_self_paired_template, tm.molecular_atom_radius)
```
Replace with:
```gdscript
		if not is_self_paired_template:
			substituent_positions = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous)
```
(The self-paired branch above already populated `substituent_positions` from the bake; this now only runs `derive_substituents()` for the non-self-paired — leading/lagging — path, with its original pre-Tier-2 signature.)

- [ ] **Step 3: Update `molecule_geometry_diagnostics.gd`'s `_derive_full_residue()` to read the SAME cache**

Find the equivalent block (the diagnostics file's own copy of the same logic) and apply the identical replacement, but read `renderer._self_paired_geometry_cache` directly (via the passed-in `renderer` reference, this file's established convention) rather than owning a second, independent cache — a dump must always reflect exactly what the live renderer would show, never a second independent computation that could silently drift from it.

- [ ] **Step 4: Confirm the project compiles**

```bash
cd "E:/Godot Projects/MolSim/mol-sim/.claude/worktrees/self-paired-chain-fix" && "C:\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . --check-only --quit
```

- [ ] **Step 5: Diff-review for the leading/lagging safety constraint**

```bash
cd "E:/Godot Projects/MolSim/mol-sim/.claude/worktrees/self-paired-chain-fix" && git diff scripts/ribose_deriver.gd scripts/molecule_structure_renderer.gd scripts/molecule_geometry_diagnostics.gd
```
Confirm: no line inside `apply_strand_direction()` or `STRAND_DIRECTION_SIGN` changed, and the `else` branches (leading/lagging's path) call `derive_substituents()` with its original, pre-Tier-2 argument list (no `is_self_paired_template`, no `molecular_atom_radius`) — confirming leading/lagging's behavior is provably identical to before this whole self-paired investigation began, not merely identical to the immediately-prior commit.

- [ ] **Step 6: Commit (Task 3 + Task 4 together, the single behavior-change commit)**

```bash
git add scripts/ribose_deriver.gd scripts/molecule_structure_renderer.gd scripts/molecule_geometry_diagnostics.gd
git commit -m "$(cat <<'EOF'
Replace live self-paired geometry with a bake-once-cache-forever model

Retires derive_self_paired_ring()'s live continuous rotation and
_required_chain_reach()'s live distance-cap logic -- both structurally
incapable of resolving the chain/ring collision, per the As-Built
amendment on the superseded design doc (a 3.92-unit geometric floor no
live reach-tuning could cross). Replaces them with
RiboseDeriver.bake_self_paired_geometry(): a ring construction search
(Tier 1's rotation plus a revived elbow-flex degree of freedom) and a
substituent placement search (direction and distance, bounded around the
real neighbor direction), both verified in diagnosis/diag_self_paired_bake.py
before this port, computed once per residue and cached forever via a new
_self_paired_geometry_cache -- same convention _fold_cache already
established for topology.

Leading/lagging is untouched: apply_strand_direction(),
STRAND_DIRECTION_SIGN, and derive_substituents()'s leading/lagging call
path are byte-identical to their pre-self-paired-investigation form
(confirmed via diff review before this commit). Single, self-contained
commit for the entire behavior change, per this project's established
Rollback discipline.
EOF
)"
```

---

## Task 5: Live verification

**Files:** none (verification only — no commit)

**Interfaces:** none

- [ ] **Step 1: Test chamber — static collision check**

Launch the test chamber (`scenes/test_chamber.tscn`, this worktree), press F9. Read `chain_closest_to_own_ribose` for every sampled residue. Expected: at or above 8.0 for residues where Task 2's harness run found `CLEARS`; for any residue Task 2 recorded as `DOES NOT CLEAR`, cross-check the live number against that harness's recorded value — it should match closely, not be worse.

- [ ] **Step 2: Cache stability check — the actual fix for the flicker/oscillation class of defect**

Unpause (or let the test chamber run, if it has live motion) and press F9 multiple times, seconds apart. For every self-paired residue, confirm the `local=` ring and chain coordinates are BYTE-IDENTICAL across every dump — not merely close, not merely stable in practice, but exactly unchanged, since the geometry is computed at most once and never touched again. Any difference at all is a real bug (the cache isn't actually caching) and must be root-caused before proceeding, not written off as noise.

- [ ] **Step 3: Real game — leading/lagging regression check**

Launch the real project (not the test chamber) with a fixed sequence, let synthesis begin, press F9. Confirm `chain_closest_to_own_ribose` for leading/lagging residues still reads the clean baseline value (10.8, matching every prior session in this investigation) — confirms the `is_self_paired_template = false` path is genuinely untouched by live behavior, not just code review.

- [ ] **Step 4: Real game — self-paired region screenshot**

Screenshot the self-paired template region at deep zoom. Visually confirm no gross overlap remains. For any residue Task 2 recorded as `DOES NOT CLEAR`, confirm it reads as a plausible, non-broken shape rather than a gross artifact — matching this project's own "a screenshot confirms, it does not substitute for the analytic proof" ordering.

- [ ] **Step 5: Revert dry-run (Rollback constraint verification)**

```bash
cd "E:/Godot Projects/MolSim/mol-sim/.claude/worktrees/self-paired-chain-fix" && git revert --no-commit HEAD && git diff --cached --stat
```
Expected: only `scripts/ribose_deriver.gd`, `scripts/molecule_structure_renderer.gd`, `scripts/molecule_geometry_diagnostics.gd` appear, cleanly reverting the Task 3+4 commit. Then:
```bash
git revert --abort
```

- [ ] **Step 6: No commit** (verification-only task)

---

## Self-Review

**Spec coverage:**
- Ring construction (rotation reused + elbow-flex, Gelbin tolerance widened only as needed): Task 1 (Python), Task 3 Step 1 (GDScript port).
- Substituent placement search (direction + distance, bounded around real neighbor direction): Task 2 (Python), Task 3 Step 2 (GDScript port).
- Cache design (`"strand:slot"` key, named invalidation seam for future ligase/polymerase work): Task 4 Step 1.
- Retiring the live Tier 1/Tier 2 path: Task 3 Step 3, Task 4 Step 2.
- Rollback constraint (single commit, revertible): Task 3 Step 5 (no commit until Task 4), Task 4 Step 6 (the one commit), Task 5 Step 5 (dry-run verification).
- Leading/lagging safety constraint: Task 4 Step 5 (diff review before commit), Task 5 Step 3 (live behavior check).
- Chirality safety (never assumed): Task 1 Step 3-4 (`_signed_area` check every candidate), ported unchanged in Task 3 Step 1.
- Stop condition (no ring candidate found at any tolerance): Task 1 Step 5's explicit instruction to report `None` honestly; Task 3 Step 2's `bake_self_paired_geometry()` falls back to the rotation-only construction rather than crashing, matching this project's "never silently degrade further without a documented path" pattern.
- Cache stability as the actual flicker/oscillation fix (not just claimed): Task 5 Step 2's byte-identical-across-presses check.
- Out-of-scope items from the Lattice decision (leading/lagging untouched, no ligase/polymerase state implementation, no cache variant key): no task touches `apply_strand_direction()`, `STRAND_DIRECTION_SIGN`, or adds a variant-keyed cache — confirmed by scope, not by an explicit task (nothing to do beyond the named seam Task 4 Step 1 adds).

**Placeholder scan:** none — every step has runnable code or a concrete, checkable expectation. Task 1 Step 5 and Task 2 Step 2 both explicitly instruct recording the *real* result rather than assuming success, matching this project's established harness-discovery convention (not a placeholder — the search's actual outcome is genuinely unknown until run, same discipline as every prior harness task in this investigation).

**Type consistency:** `bake_self_paired_geometry()`'s return shape (`{ring_positions: Dictionary, substituent_positions: Dictionary}`) is used identically in Task 3 Step 2 (where it's constructed) and Task 4 Step 2 (where it's consumed via `baked.ring_positions`/`baked.substituent_positions`). `derive_substituents()`'s signature reverts to its original pre-Tier-2 form (Task 3 Step 3) and is called that way in both remaining call sites (Task 4 Step 2's non-self-paired branch, and the bake orchestrator's own internal call in Task 3 Step 2 for the O3'/C5' *ids* it still needs before overwriting positions with the search results).
