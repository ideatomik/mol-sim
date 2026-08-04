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
            theta = theta_ideal if abs(delta) <= half else theta_center + (half if delta > 0.0 else -half)

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
                o3_clear=o3_clear, c5_clear=c5_clear)

result_a = run_case("template_top slot 0 (boundary)", FIXTURE_A_TOWARD_NEXT, FIXTURE_A_TOWARD_PREVIOUS, FIXTURE_A_PAIRING_DIRECTION)
result_b = run_case("template_bottom slot 0 (mirror boundary)", FIXTURE_B_TOWARD_NEXT, FIXTURE_B_TOWARD_PREVIOUS, FIXTURE_B_PAIRING_DIRECTION)
result_c = run_case("template_top slot 2 (interior)", FIXTURE_C_TOWARD_NEXT, FIXTURE_C_TOWARD_PREVIOUS, FIXTURE_C_PAIRING_DIRECTION)

CHAIN_EXTENSION_STRETCH_CAP_RATIO = 2.7  # confirmed/adjusted against real fixture data

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
