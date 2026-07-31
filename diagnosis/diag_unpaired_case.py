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
def dot(a, b): return a[0]*b[0]+a[1]*b[1]
def rotated(a, theta):
    c, s = math.cos(theta), math.sin(theta)
    return (a[0]*c - a[1]*s, a[0]*s + a[1]*c)
def wrapf(v, mn, mx):
    rng = mx-mn
    return v - rng*math.floor((v-mn)/rng)

TAU = 2*math.pi
BASE_ROTATION_SEARCH_STEPS = 72

def derive_regular_ring(role_suffixes, bond_length, start_angle=-math.pi/2.0):
    n = len(role_suffixes)
    R = bond_length/(2.0*math.sin(math.pi/n))
    step = TAU/n
    return {suf: (math.cos(start_angle+i*step)*R, math.sin(start_angle+i*step)*R) for i, suf in enumerate(role_suffixes)}

def derive_fused_ring(a_pt, b_pt, remaining, fold_away_from):
    edge_vec = sub(b_pt, a_pt)
    edge_len = length(edge_vec)
    n = len(remaining) + 2
    R = edge_len/(2.0*math.sin(math.pi/n))
    apothem = R*math.cos(math.pi/n)
    edge_mid = scale(add(a_pt, b_pt), 0.5)
    edge_normal = normalized(orthogonal(edge_vec))
    if dot(edge_normal, sub(edge_mid, fold_away_from)) < 0.0:
        edge_normal = scale(edge_normal, -1.0)
    center = add(edge_mid, scale(edge_normal, apothem))
    start_angle = vangle(sub(a_pt, center))
    target_angle = vangle(sub(b_pt, center))
    step = TAU/n
    direction = -1.0
    if abs(wrapf(start_angle-step-target_angle, -math.pi, math.pi)) < abs(wrapf(start_angle+step-target_angle, -math.pi, math.pi)):
        direction = 1.0
    positions = {}
    a = start_angle
    for suf in remaining:
        a += direction*step
        positions[suf] = add(center, scale((math.cos(a), math.sin(a)), R))
    return positions

RING_ROLE_SUFFIXES = ["c1_prime", "c2_prime", "c3_prime", "c4_prime", "o4_prime"]
SIX = ["n1", "c2", "n3", "c4", "c5", "c6"]
FIVE_REMAIN = ["n9", "c8", "n7"]

def pairing_anchor_suffix(b): return {"A": "n1", "T": "n3", "G": "n1", "C": "n3"}[b]

def apply_strand_direction(local, pivot, sign):
    if sign >= 0: return dict(local)
    return {k: sub(scale(pivot, 2.0), v) for k, v in local.items()}

def build_base_local(base_letter, bond_length):
    is_purine = base_letter in ("A", "G")
    attach = "n9" if is_purine else "n1"
    anchor = pairing_anchor_suffix(base_letter)
    if is_purine:
        local = derive_regular_ring(SIX, bond_length)
        five = derive_fused_ring(local["c4"], local["c5"], FIVE_REMAIN, (0.0, 0.0))
        local.update(five)
    else:
        local = derive_regular_ring(SIX, bond_length)
    return local, attach, anchor

def derive_base_layout_SHIPPED(base_letter, c1_position, pairing_direction, bond_length, avoid_points):
    """Matches nitrogen_base_deriver.gd's derive_base_layout() exactly,
    INCLUDING the fallback-direction fix: when pairing_direction is zero
    (unpaired residue) and avoid_points is available, the fallback points
    away from the chain's own centroid instead of a fixed Vector2.DOWN."""
    local, attach, anchor = build_base_local(base_letter, bond_length)

    if length(pairing_direction) > 0:
        dirn = normalized(pairing_direction)
    elif avoid_points:
        cx = sum(p[0] for p in avoid_points) / len(avoid_points)
        cy = sum(p[1] for p in avoid_points) / len(avoid_points)
        centroid = (cx, cy)
        dirn = normalized(scale(centroid, -1.0)) if length(centroid) > 0 else (0.0, -1.0)
    else:
        dirn = (0.0, -1.0)

    local_anchor = local[anchor]
    local_reach = sub(local[anchor], local[attach])
    reach_len = length(local_reach)
    anchor_target = add(c1_position, scale(dirn, bond_length + reach_len))

    if not avoid_points:
        local_dir = normalized(local_reach) if reach_len > 0 else (0.0, -1.0)
        best_angle = vangle(dirn) - vangle(local_dir)
    else:
        best_angle = 0.0
        best_clearance = -math.inf
        for i in range(BASE_ROTATION_SEARCH_STEPS):
            angle = TAU * i / BASE_ROTATION_SEARCH_STEPS
            candidate_anchor = rotated(local_anchor, angle)
            candidate_translation = sub(anchor_target, candidate_anchor)
            clearance = math.inf
            for k, v in local.items():
                world = add(rotated(v, angle), candidate_translation)
                for ap in avoid_points:
                    clearance = min(clearance, length(sub(world, ap)))
            if clearance > best_clearance:
                best_clearance = clearance
                best_angle = angle

    rotated_local = {k: rotated(v, best_angle) for k, v in local.items()}
    translation = sub(anchor_target, rotated_local[anchor])
    return {k: add(v, translation) for k, v in rotated_local.items()}, attach, anchor

def chain_points(ring_local, bl):
    outward_c3 = normalized(ring_local["c3_prime"])
    o3 = add(ring_local["c3_prime"], scale(outward_c3, bl))
    outward_c4 = normalized(ring_local["c4_prime"])
    c5 = add(ring_local["c4_prime"], scale(outward_c4, bl))
    o5 = add(c5, scale(outward_c4, bl))
    alpha = add(o5, scale(outward_c4, bl))
    return [o3, c5, o5, alpha]

def point_segment_distance(p, a, b):
    ab = sub(b, a)
    ab_len2 = ab[0]**2 + ab[1]**2
    if ab_len2 == 0:
        return length(sub(p, a))
    t = max(0.0, min(1.0, dot(sub(p, a), ab) / ab_len2))
    proj = add(a, scale(ab, t))
    return length(sub(p, proj))

def seg_check(pos, a, b):
    return min(point_segment_distance(bp, a, b) for bp in pos.values())


bond_length = 10.8  # live confirmed value (molecular_ring_bond_length_ratio=0.2)

ring_plus1 = derive_regular_ring(RING_ROLE_SUFFIXES, bond_length)
c1_local = ring_plus1["c1_prime"]
ring_minus1 = apply_strand_direction(ring_plus1, c1_local, -1.0)

for sign, ring_local, label in [(1, ring_plus1, "sign=+1 (lagging/template_top)"), (-1, ring_minus1, "sign=-1 (leading/template_bottom)")]:
    chain = chain_points(ring_local, bond_length)
    c4 = ring_local["c4_prime"]
    c3 = ring_local["c3_prime"]
    print(f"=== {label}, UNPAIRED (pairing_direction=(0,0)) ===")
    for base in ["A", "T", "G", "C"]:
        pos, attach, anchor = derive_base_layout_SHIPPED(base, c1_local, (0.0, 0.0), bond_length, chain)
        d_c4_c5 = seg_check(pos, c4, chain[1])
        d_c5_o5 = seg_check(pos, chain[1], chain[2])
        d_o5_ap = seg_check(pos, chain[2], chain[3])
        d_c3_o3 = seg_check(pos, c3, chain[0])
        worst = min(d_c4_c5, d_c5_o5, d_o5_ap, d_c3_o3)
        print(f"  base={base}: C4-C5={d_c4_c5:.4f}  C5-O5={d_c5_o5:.4f}  O5-alphaP={d_o5_ap:.4f}  C3-O3={d_c3_o3:.4f}  (worst={worst:.4f})")
    print()
