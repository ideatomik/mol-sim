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
MOLECULAR_ATOM_RADIUS = 4.0  # scenes/simulation.tscn's real override of theme_manager.gd's molecular_atom_radius (script default is 6.0, but the real scene overrides it -- confirmed via the .tscn directly, not the script default, after live testing caught this mismatch)
COLLISION_CLEARANCE_RATIO = 2.0  # no overlap between two full-radius atom circles -- the real invariant behind the old flat 12.0
COLLISION_THRESHOLD = COLLISION_CLEARANCE_RATIO * MOLECULAR_ATOM_RADIUS  # = 8.0 with the real scene's radius
BULGE_DOT_MARGIN_DEG = 5.0  # keeps bulge_vs_pairing_dot comfortably negative (~-0.087) instead of landing exactly on the 0.0 knife-edge; introduced here after Task 1's initial run showed every fixture saturating the clamp exactly at the arc boundary

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
    fixed_tiebreak_sign = 1.0 if (bulge_vec[0] * ring_bond_dir0[1] - bulge_vec[1] * ring_bond_dir0[0]) >= 0.0 else -1.0

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
            half = math.pi / 2.0 - math.radians(BULGE_DOT_MARGIN_DEG)
            delta = wrap_pi(theta_ideal - theta_center)
            theta = theta_ideal if abs(delta) <= half else theta_center + fixed_tiebreak_sign * half

    result = {k: add(pivot, rotated(sub(v, pivot), theta)) for k, v in natural_ring.items()}
    return result, theta

print("=== Fixture sanity check ===")
print("Fixture A toward_next:", FIXTURE_A_TOWARD_NEXT, "length:", length(FIXTURE_A_TOWARD_NEXT))
print("Fixture A pairing_direction:", FIXTURE_A_PAIRING_DIRECTION, "length:", length(FIXTURE_A_PAIRING_DIRECTION))

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
                o3_clear=o3_clear, c5_clear=c5_clear, toward_next=toward_next, toward_previous=toward_previous)

result_a = run_case("template_top slot 0 (boundary)", FIXTURE_A_TOWARD_NEXT, FIXTURE_A_TOWARD_PREVIOUS, FIXTURE_A_PAIRING_DIRECTION)
result_b = run_case("template_bottom slot 0 (mirror boundary)", FIXTURE_B_TOWARD_NEXT, FIXTURE_B_TOWARD_PREVIOUS, FIXTURE_B_PAIRING_DIRECTION)
result_c = run_case("template_top slot 2 (interior)", FIXTURE_C_TOWARD_NEXT, FIXTURE_C_TOWARD_PREVIOUS, FIXTURE_C_PAIRING_DIRECTION)

# Verification: demonstrate the old (jittering) formula vs new (stable) formula
print("\n=== OSCILLATION BUG VERIFICATION ===")
print("Testing whether tiny input perturbation (0.394745 vs 0.394746) causes theta to flip:")

def derive_self_paired_ring_old_formula(natural_ring, pairing_direction, toward_next, toward_previous):
    """OLD formula with sign-based tie-break (jitters at ±π boundary)."""
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
            half = math.pi / 2.0 - math.radians(BULGE_DOT_MARGIN_DEG)
            delta = wrap_pi(theta_ideal - theta_center)
            # OLD: sign-based tie-break (JITTERS)
            theta = theta_ideal if abs(delta) <= half else theta_center + (half if delta > 0.0 else -half)

    result = {k: add(pivot, rotated(sub(v, pivot), theta)) for k, v in natural_ring.items()}
    return result, theta

natural = derive_regular_ring(BOND_LENGTH)

# Test Case A with unperturbed input
_, theta_old_unperturbed = derive_self_paired_ring_old_formula(natural, FIXTURE_A_PAIRING_DIRECTION, FIXTURE_A_TOWARD_NEXT, FIXTURE_A_TOWARD_PREVIOUS)
# Test Case A with perturbation in the sign-flipping range
toward_next_perturbed_pos = (54.0, 0.5)  # slightly higher Y
toward_next_perturbed_neg = (54.0, 0.3)  # slightly lower Y
_, theta_old_perturbed_pos = derive_self_paired_ring_old_formula(natural, FIXTURE_A_PAIRING_DIRECTION, toward_next_perturbed_pos, FIXTURE_A_TOWARD_PREVIOUS)
_, theta_old_perturbed_neg = derive_self_paired_ring_old_formula(natural, FIXTURE_A_PAIRING_DIRECTION, toward_next_perturbed_neg, FIXTURE_A_TOWARD_PREVIOUS)

# New formula (with fixed tie-break) should be stable
_, theta_new_unperturbed = derive_self_paired_ring(natural, FIXTURE_A_PAIRING_DIRECTION, FIXTURE_A_TOWARD_NEXT, FIXTURE_A_TOWARD_PREVIOUS)
_, theta_new_perturbed_pos = derive_self_paired_ring(natural, FIXTURE_A_PAIRING_DIRECTION, toward_next_perturbed_pos, FIXTURE_A_TOWARD_PREVIOUS)
_, theta_new_perturbed_neg = derive_self_paired_ring(natural, FIXTURE_A_PAIRING_DIRECTION, toward_next_perturbed_neg, FIXTURE_A_TOWARD_PREVIOUS)

old_delta_pos = abs(math.degrees(theta_old_perturbed_pos) - math.degrees(theta_old_unperturbed))
old_delta_neg = abs(math.degrees(theta_old_perturbed_neg) - math.degrees(theta_old_unperturbed))
new_delta_pos = abs(math.degrees(theta_new_perturbed_pos) - math.degrees(theta_new_unperturbed))
new_delta_neg = abs(math.degrees(theta_new_perturbed_neg) - math.degrees(theta_new_unperturbed))
old_flips_either = old_delta_pos > 90.0 or old_delta_neg > 90.0
new_stable = new_delta_pos < 0.1 and new_delta_neg < 0.1

print(f"OLD formula (sign-based tie-break, wraparound knife-edge sensitive):")
print(f"  toward_next (Y+0.1): theta changes by {old_delta_pos:.2f} deg")
print(f"  toward_next (Y-0.1): theta changes by {old_delta_neg:.2f} deg")
print(f"  -> Shows large flips: {old_flips_either}")
print(f"NEW formula (fixed deterministic tie-break):")
print(f"  toward_next (Y+0.1): theta changes by {new_delta_pos:.2f} deg")
print(f"  toward_next (Y-0.1): theta changes by {new_delta_neg:.2f} deg")
print(f"  -> Stable: {new_stable}")
print(f"Bug mechanism confirmed (old flips, new stable): {old_flips_either and new_stable}")

def required_chain_reach(start_pos, dir_hat, ring, bond_length, real_neighbor_distance, threshold=COLLISION_THRESHOLD):
    """Smallest distance >= bond_length along the UNCHANGED real direction
    dir_hat that clears every ring atom by `threshold`, capped so it can
    never reach past roughly the halfway point to the real same-strand
    neighbor (real_neighbor_distance = length of the real, UNnormalized
    toward_next/toward_previous vector) minus a `threshold`-sized safety
    margin -- grounded in the real live neighbor distance, not an
    arbitrary bond-length multiplier, so this scales correctly regardless
    of what slot spacing / bond_length ratio a given scene uses (found via
    live testing: the old flat 2.7x-bond_length cap let the chain reach
    55.1 units when the real neighbor was only 54.0 units away -- an
    inter-residue collision the old same-residue-only cap had no way to
    prevent)."""
    best = bond_length
    threshold_sq = threshold * threshold
    for p in ring.values():
        rel = sub(p, start_pos)
        a = dot(rel, dir_hat)
        h_sq = max(0.0, length_sq(rel) - a * a)
        if h_sq >= threshold_sq:
            continue
        current_dist_sq = (bond_length - a) ** 2 + h_sq
        if current_dist_sq >= threshold_sq:
            continue
        reach = math.sqrt(threshold_sq - h_sq)
        best = max(best, a + reach)
    max_safe_reach = max(bond_length, real_neighbor_distance * 0.5 - threshold)
    return min(best, max_safe_reach)

def run_case_with_tier2(label, result):
    ring = result["ring"]
    toward_next = result["toward_next"]
    toward_previous = result["toward_previous"]

    # Compute the effective real neighbor distances, accounting for mutual fallback:
    # if one direction has no real neighbor (0,0), the other side's vector is used as fallback
    tn_dist = length(toward_next) if length(toward_next) > 0.0 else length(toward_previous)
    tp_dist = length(toward_previous) if length(toward_previous) > 0.0 else length(toward_next)

    o3_reach = required_chain_reach(ring["c3_prime"], result["o3_dir"], ring, BOND_LENGTH, tn_dist)
    c5_reach = required_chain_reach(ring["c4_prime"], result["c5_dir"], ring, BOND_LENGTH, tp_dist)
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
