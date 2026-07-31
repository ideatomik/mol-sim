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
BASE_ROTATION_SEARCH_STEPS = 72  # matches nitrogen_base_deriver.gd's constant

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

def derive_base_layout_OLD(base_letter, c1_position, pairing_direction, bond_length):
    """Pre-Bug-F algorithm: aligns local attachment->anchor with pairing_direction."""
    local, attach, anchor = build_base_local(base_letter, bond_length)
    dirn = normalized(pairing_direction) if length(pairing_direction) > 0 else (0.0, -1.0)
    local_reach = sub(local[anchor], local[attach])
    local_dir = normalized(local_reach) if length(local_reach) > 0 else (0.0, -1.0)
    rotation_angle = vangle(dirn) - vangle(local_dir)
    rotated_local = {k: rotated(v, rotation_angle) for k, v in local.items()}
    target = add(c1_position, scale(dirn, bond_length))
    translation = sub(target, rotated_local[attach])
    return {k: add(v, translation) for k, v in rotated_local.items()}, attach, anchor

def derive_base_layout_SHIPPED(base_letter, c1_position, pairing_direction, bond_length, avoid_points):
    """Bug F fix, matches nitrogen_base_deriver.gd's derive_base_layout()
    exactly: anchor target computed directly (algebraically identical to
    the OLD algorithm's own anchor position -- verified below), rotation
    angle searched to maximize clearance from avoid_points."""
    local, attach, anchor = build_base_local(base_letter, bond_length)
    dirn = normalized(pairing_direction) if length(pairing_direction) > 0 else (0.0, -1.0)
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


# ---- Setup: template-template pairing, straight vertical, real numbers
# from the live F9 dump (bond_length=10.8, dna_ribbons_gap=60) ----
dna_ribbons_gap = 60.0
template_strand_y = 30.0
top_bonded_y = -30.0
slot_x = 1000.0
bond_length = 10.8

def residue_world_pos(strand):
    return (slot_x, top_bonded_y) if strand == "template_top" else (slot_x, template_strand_y)

ring_plus1 = derive_regular_ring(RING_ROLE_SUFFIXES, bond_length)
c1_local = ring_plus1["c1_prime"]
ring_minus1 = apply_strand_direction(ring_plus1, c1_local, -1.0)

def chain_points(ring_local, bl):
    outward_c3 = normalized(ring_local["c3_prime"])
    o3 = add(ring_local["c3_prime"], scale(outward_c3, bl))
    outward_c4 = normalized(ring_local["c4_prime"])
    c5 = add(ring_local["c4_prime"], scale(outward_c4, bl))
    o5 = add(c5, scale(outward_c4, bl))
    alpha = add(o5, scale(outward_c4, bl))
    return [o3, c5, o5, alpha]

chain_plus1 = chain_points(ring_plus1, bond_length)
chain_minus1 = chain_points(ring_minus1, bond_length)

def chain_closest_to_own_base(base_pos, chain_pts):
    best = math.inf
    for cp in chain_pts:
        for bp in base_pos.values():
            best = min(best, length(sub(cp, bp)))
    return best

top_wp = residue_world_pos("template_top")
bot_wp = residue_world_pos("template_bottom")
pd_top = sub(bot_wp, top_wp)
pd_bot = sub(top_wp, bot_wp)

print("=== OLD algorithm (pre-Bug-F) ===")
old_top, _, top_anchor_role = derive_base_layout_OLD("C", c1_local, pd_top, bond_length)
old_bot, _, bot_anchor_role = derive_base_layout_OLD("G", c1_local, pd_bot, bond_length)
old_top_anchor_world = add(top_wp, sub(old_top[top_anchor_role], c1_local))
old_bot_anchor_world = add(bot_wp, sub(old_bot[bot_anchor_role], c1_local))
old_span = length(sub(old_top_anchor_world, old_bot_anchor_world))
print("anchor span =", old_span)
print("top clearance    =", chain_closest_to_own_base(old_top, chain_plus1))
print("bottom clearance =", chain_closest_to_own_base(old_bot, chain_minus1))

print("\n=== SHIPPED algorithm (Bug F fix) ===")
new_top, _, _ = derive_base_layout_SHIPPED("C", c1_local, pd_top, bond_length, chain_plus1)
new_bot, _, _ = derive_base_layout_SHIPPED("G", c1_local, pd_bot, bond_length, chain_minus1)
new_top_anchor_world = add(top_wp, sub(new_top[top_anchor_role], c1_local))
new_bot_anchor_world = add(bot_wp, sub(new_bot[bot_anchor_role], c1_local))
new_span = length(sub(new_top_anchor_world, new_bot_anchor_world))
print("anchor span =", new_span)
print("top clearance    =", chain_closest_to_own_base(new_top, chain_plus1))
print("bottom clearance =", chain_closest_to_own_base(new_bot, chain_minus1))

print("\n=== Verification ===")
print("anchor world MATCH (top)    =", length(sub(old_top_anchor_world, new_top_anchor_world)) < 1e-9)
print("anchor world MATCH (bottom) =", length(sub(old_bot_anchor_world, new_bot_anchor_world)) < 1e-9)
print("span unchanged =", abs(old_span - new_span) < 1e-9)
