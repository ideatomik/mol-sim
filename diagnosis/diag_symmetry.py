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

def derive_base_layout(base_letter, c1_position, pairing_direction, bond_length):
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

dna_ribbons_gap = 90.0
template_strand_y = 45.0
top_bonded_y = -45.0
slot_x = 1000.0

def residue_world_pos(strand):
    return (slot_x, top_bonded_y) if strand == "template_top" else (slot_x, template_strand_y)

def full_base_world(strand, base_letter, partner_world_pos):
    world_pos = residue_world_pos(strand)
    ring_l = derive_regular_ring(RING_ROLE_SUFFIXES, bond_length)
    c1_l = ring_l["c1_prime"]
    anchor_offset = c1_l
    pairing_direction = sub(partner_world_pos, world_pos)
    base_pos = derive_base_layout(base_letter, c1_l, pairing_direction, bond_length)
    out = {}
    for k, v in base_pos.items():
        out[k] = add(world_pos, sub(v, anchor_offset))
    return out

top_wp = residue_world_pos("template_top")
bot_wp = residue_world_pos("template_bottom")
g_top = full_base_world("template_top", "G", bot_wp)
g_bot = full_base_world("template_bottom", "G", top_wp)

# The correct symmetry check here is a 180-degree POINT ROTATION about the
# shared center point (slot_x, 0) -- template_top and template_bottom sit at
# equal-and-opposite y, so a base rendered on one strand should be an exact
# rotation of the same base rendered on the other, never an axis mirror (a
# mirror would silently flip the ring's chirality, same no-reflection
# constraint as the ribose fix in RiboseDeriver.apply_strand_direction). An
# axis-mirror check (x same, y negated) was tried first and gave misleading
# nonzero errors for every atom off the center line -- it was checking the
# wrong operation, not finding a real bug. Point-rotation is: (x, y) ->
# (2*cx - x, -y).
cx = slot_x
print("atom      point-rotation-through-(%.1f,0) check" % cx)
max_err = 0.0
for k in g_top:
    t = g_top[k]
    b = g_bot[k]
    rotated_t = (2 * cx - t[0], -t[1])
    err = length(sub(rotated_t, b))
    max_err = max(max_err, err)
    print(f"  {k:8s} top=({t[0]:9.4f},{t[1]:9.4f})  bottom=({b[0]:9.4f},{b[1]:9.4f})  rotation_err={err:.2e}")
print(f"\nmax rotation error across all atoms = {max_err:.2e} (0 => bottom is an exact 180-degree rotation of top, i.e. consistent facing, no mirroring)")
