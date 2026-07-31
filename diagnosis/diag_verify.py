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

def derive_regular_ring(role_suffixes, bond_length, start_angle=-math.pi/2.0):
    n = len(role_suffixes)
    R = bond_length/(2.0*math.sin(math.pi/n))
    step = TAU/n
    return {suf: (math.cos(start_angle+i*step)*R, math.sin(start_angle+i*step)*R) for i, suf in enumerate(role_suffixes)}

def derive_fused_ring(a_pt, b_pt, remaining, fold_away_from):
    """Matches the FIXED nitrogen_base_deriver.gd derive_fused_ring()."""
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

bond_length = 0.35 * 54.0

def apply_strand_direction(local, pivot, sign):
    if sign >= 0:
        return dict(local)
    return {k: sub(scale(pivot, 2.0), v) for k, v in local.items()}

def derive_base_layout(base_letter, c1_position, pairing_direction, bond_length):
    """Matches the FIXED nitrogen_base_deriver.gd derive_base_layout()."""
    is_purine = base_letter in ("A", "G")
    attach = "n9" if is_purine else "n1"
    if is_purine:
        local = derive_regular_ring(SIX, bond_length)
        five = derive_fused_ring(local["c4"], local["c5"], FIVE_REMAIN, (0.0, 0.0))
        local.update(five)
    else:
        local = derive_regular_ring(SIX, bond_length)

    dirn = normalized(pairing_direction) if length(pairing_direction) > 0 else (0.0, -1.0)
    local_attachment = local[attach]
    local_dir = normalized(local_attachment) if length(local_attachment) > 0 else (0.0, -1.0)
    rotation_angle = vangle(dirn) - vangle(local_dir)
    rotated_local = {k: rotated(v, rotation_angle) for k, v in local.items()}

    target = add(c1_position, scale(dirn, bond_length))
    translation = sub(target, rotated_local[attach])
    return {k: add(v, translation) for k, v in rotated_local.items()}

def pairing_anchor_suffix(b): return {"A": "n1", "T": "n3", "G": "n1", "C": "n3"}[b]

dna_ribbons_gap = 90.0
template_strand_y = 45.0
top_bonded_y = -45.0
slot_x = 1000.0
STRAND_SIGN = {"template_bottom": -1.0, "template_top": 1.0}

def residue_world_pos(strand):
    return (slot_x, top_bonded_y) if strand == "template_top" else (slot_x, template_strand_y)

def compute_anchor_world(strand, base_letter, partner_world_pos):
    world_pos = residue_world_pos(strand)
    ring_l = derive_regular_ring(RING_ROLE_SUFFIXES, bond_length)
    c1_l = ring_l["c1_prime"]
    anchor_offset = c1_l
    pairing_direction = sub(partner_world_pos, world_pos)
    base_pos = derive_base_layout(base_letter, c1_l, pairing_direction, bond_length)
    anchor_local = base_pos[pairing_anchor_suffix(base_letter)]
    return add(world_pos, sub(anchor_local, anchor_offset))

def check_fused_ring_no_overlap():
    local = derive_regular_ring(SIX, bond_length)
    five = derive_fused_ring(local["c4"], local["c5"], FIVE_REMAIN, (0.0, 0.0))
    d = length(sub(five["n9"], local["c5"]))
    print(f"-- Fused-ring check: |n9 - c5| = {d:.4f} (was 0.0000 before fix) --")
    for k in FIVE_REMAIN:
        print(f"   local[{k}] = ({five[k][0]:.4f}, {five[k][1]:.4f})")
    print(f"   local[c4]  = ({local['c4'][0]:.4f}, {local['c4'][1]:.4f})")
    print(f"   local[c5]  = ({local['c5'][0]:.4f}, {local['c5'][1]:.4f})\n")

def run_pair(base_top, base_bottom, label):
    top_wp = residue_world_pos("template_top")
    bot_wp = residue_world_pos("template_bottom")
    top_anchor = compute_anchor_world("template_top", base_top, bot_wp)
    bot_anchor = compute_anchor_world("template_bottom", base_bottom, top_wp)
    span = length(sub(top_anchor, bot_anchor))
    print(f"{label}: top({base_top})={tuple(round(x,4) for x in top_anchor)}  bottom({base_bottom})={tuple(round(x,4) for x in bot_anchor)}  span={span:.4f}")
    return span

check_fused_ring_no_overlap()

print("== G/C pair, both orientations ==")
s1 = run_pair("G", "C", "G-top/C-bottom")
s2 = run_pair("C", "G", "C-top/G-bottom")
print(f"  diff = {abs(s1-s2):.6f}\n")

print("== A/T pair, both orientations ==")
s3 = run_pair("A", "T", "A-top/T-bottom")
s4 = run_pair("T", "A", "T-top/A-bottom")
print(f"  diff = {abs(s3-s4):.6f}\n")
