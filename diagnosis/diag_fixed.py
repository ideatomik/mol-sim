import math

def sub(a, b): return (a[0]-b[0], a[1]-b[1])
def add(a, b): return (a[0]+b[0], a[1]+b[1])
def scale(a, s): return (a[0]*s, a[1]*s)
def length(a): return math.hypot(a[0], a[1])
def normalized(a):
    l = length(a)
    return (0.0,0.0) if l == 0 else (a[0]/l, a[1]/l)
def orthogonal(a): return (a[1], -a[0])
def angle(a): return math.atan2(a[1], a[0])
def dot(a,b): return a[0]*b[0]+a[1]*b[1]
def wrapf(v, mn, mx):
    rng = mx-mn
    return v - rng*math.floor((v-mn)/rng)

TAU = 2*math.pi

def derive_regular_ring(role_suffixes, bond_length, start_angle=-math.pi/2.0):
    n = len(role_suffixes)
    R = bond_length/(2.0*math.sin(math.pi/n))
    step = TAU/n
    return {suf: (math.cos(start_angle+i*step)*R, math.sin(start_angle+i*step)*R) for i, suf in enumerate(role_suffixes)}

def derive_fused_ring(a_pt, b_pt, remaining, fold_away_from, FIX=False):
    edge_vec = sub(b_pt, a_pt)
    edge_len = length(edge_vec)
    n = len(remaining) + 2
    R = edge_len/(2.0*math.sin(math.pi/n))
    apothem = R*math.cos(math.pi/n)
    edge_mid = scale(add(a_pt,b_pt), 0.5)
    edge_normal = normalized(orthogonal(edge_vec))
    if dot(edge_normal, sub(edge_mid, fold_away_from)) < 0.0:
        edge_normal = scale(edge_normal, -1.0)
    center = add(edge_mid, scale(edge_normal, apothem))
    start_angle = angle(sub(a_pt, center))
    target_angle = angle(sub(b_pt, center))
    step = TAU/n
    close_if_minus = abs(wrapf(start_angle-step-target_angle,-math.pi,math.pi)) < abs(wrapf(start_angle+step-target_angle,-math.pi,math.pi))
    if not FIX:
        direction = -1.0 if close_if_minus else 1.0
    else:
        direction = 1.0 if close_if_minus else -1.0
    positions = {}
    a = start_angle
    for suf in remaining:
        a += direction*step
        positions[suf] = add(center, scale((math.cos(a), math.sin(a)), R))
    return positions

RING_ROLE_SUFFIXES = ["c1_prime","c2_prime","c3_prime","c4_prime","o4_prime"]
SIX = ["n1","c2","n3","c4","c5","c6"]
FIVE_REMAIN = ["n9","c8","n7"]

bond_length = 0.35*54.0

def apply_strand_direction(local, pivot, sign):
    if sign >= 0: return dict(local)
    return {k: sub(scale(pivot,2.0), v) for k,v in local.items()}

def derive_base_layout(base_letter, c1_position, pairing_direction, bond_length, FIX=False):
    is_purine = base_letter in ("A","G")
    attach = "n9" if is_purine else "n1"
    if is_purine:
        local = derive_regular_ring(SIX, bond_length)
        five = derive_fused_ring(local["c4"], local["c5"], FIVE_REMAIN, (0.0,0.0), FIX=FIX)
        local.update(five)
    else:
        local = derive_regular_ring(SIX, bond_length)
    dirn = normalized(pairing_direction) if length(pairing_direction) > 0 else (0.0,1.0)
    target = add(c1_position, scale(dirn, bond_length))
    translation = sub(target, local[attach])
    return {k: add(v, translation) for k,v in local.items()}

def pairing_anchor_suffix(b): return {"A":"n1","T":"n3","G":"n1","C":"n3"}[b]

dna_ribbons_gap = 90.0
template_strand_y = 45.0
top_bonded_y = -45.0
slot_x = 1000.0
STRAND_SIGN = {"template_bottom": -1.0, "template_top": 1.0}

def residue_world_pos(strand):
    return (slot_x, top_bonded_y) if strand=="template_top" else (slot_x, template_strand_y)

def compute_anchor_world(strand, base_letter, partner_world_pos, FIX=False):
    world_pos = residue_world_pos(strand)
    sign = STRAND_SIGN[strand]
    ring_l = derive_regular_ring(RING_ROLE_SUFFIXES, bond_length)
    c1_l = ring_l["c1_prime"]
    anchor_offset = c1_l
    pairing_direction = sub(partner_world_pos, world_pos)
    base_pos = derive_base_layout(base_letter, c1_l, pairing_direction, bond_length, FIX=FIX)
    anchor_local = base_pos[pairing_anchor_suffix(base_letter)]
    return add(world_pos, sub(anchor_local, anchor_offset))

for FIX, label in [(False, "ORIGINAL (as shipped)"), (True, "WITH direction FIXED")]:
    top_wp = residue_world_pos("template_top")
    bot_wp = residue_world_pos("template_bottom")
    g = compute_anchor_world("template_top", "G", bot_wp, FIX)
    c = compute_anchor_world("template_bottom", "C", top_wp, FIX)
    span1 = length(sub(g, c))
    c2 = compute_anchor_world("template_top", "C", bot_wp, FIX)
    g2 = compute_anchor_world("template_bottom", "G", top_wp, FIX)
    span2 = length(sub(c2, g2))
    print(f"-- {label} --")
    print(f"  span1 (G-top/C-bottom) = {span1:.4f}")
    print(f"  span2 (C-top/G-bottom) = {span2:.4f}")
    print(f"  diff = {span1-span2:.4f}\n")
