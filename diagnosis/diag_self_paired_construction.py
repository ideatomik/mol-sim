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
