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
