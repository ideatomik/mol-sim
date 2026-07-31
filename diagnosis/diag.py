import math

def vec(x, y):
    return (x, y)

def add(a, b):
    return (a[0] + b[0], a[1] + b[1])

def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])

def scale(a, s):
    return (a[0] * s, a[1] * s)

def length(a):
    return math.hypot(a[0], a[1])

def normalized(a):
    l = length(a)
    if l == 0:
        return (0.0, 0.0)
    return (a[0] / l, a[1] / l)

def orthogonal(a):
    # Godot Vector2.orthogonal(): Vector2(y, -x)
    return (a[1], -a[0])

def angle(a):
    return math.atan2(a[1], a[0])

def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]

def wrapf(value, mn, mx):
    rng = mx - mn
    if rng == 0:
        return mn
    result = value - (rng * math.floor((value - mn) / rng))
    return result

TAU = 2 * math.pi

def derive_regular_ring(role_suffixes, bond_length, start_angle=-math.pi / 2.0):
    n = len(role_suffixes)
    circumradius = bond_length / (2.0 * math.sin(math.pi / n))
    angle_step = TAU / n
    positions = {}
    for i, suf in enumerate(role_suffixes):
        a = start_angle + i * angle_step
        positions[suf] = (math.cos(a) * circumradius, math.sin(a) * circumradius)
    return positions

def derive_fused_ring(shared_edge_a, shared_edge_b, remaining_role_suffixes, fold_away_from):
    edge_vec = sub(shared_edge_b, shared_edge_a)
    edge_len = length(edge_vec)
    n = len(remaining_role_suffixes) + 2
    circumradius = edge_len / (2.0 * math.sin(math.pi / n))
    apothem = circumradius * math.cos(math.pi / n)
    edge_mid = scale(add(shared_edge_a, shared_edge_b), 0.5)
    edge_normal = normalized(orthogonal(edge_vec))
    if dot(edge_normal, sub(edge_mid, fold_away_from)) < 0.0:
        edge_normal = scale(edge_normal, -1.0)
    center = add(edge_mid, scale(edge_normal, apothem))

    start_angle = angle(sub(shared_edge_a, center))
    target_angle = angle(sub(shared_edge_b, center))
    step = TAU / n
    direction = 1.0
    if abs(wrapf(start_angle - step - target_angle, -math.pi, math.pi)) < abs(wrapf(start_angle + step - target_angle, -math.pi, math.pi)):
        direction = -1.0

    positions = {}
    a = start_angle
    for suf in remaining_role_suffixes:
        a += direction * step
        positions[suf] = add(center, scale((math.cos(a), math.sin(a)), circumradius))
    return positions, center, start_angle, target_angle, direction

# ---- Ribose ring (RiboseDeriver.derive_ring / RING_ROLE_SUFFIXES) ----
RING_ROLE_SUFFIXES = ["c1_prime", "c2_prime", "c3_prime", "c4_prime", "o4_prime"]
PURINE_SIX_RING_SUFFIXES = ["n1", "c2", "n3", "c4", "c5", "c6"]
PYRIMIDINE_RING_SUFFIXES = ["n1", "c2", "n3", "c4", "c5", "c6"]
PURINE_FIVE_RING_REMAINING_SUFFIXES = ["n9", "c8", "n7"]

nucleotide_slot_spacing = 54.0
molecular_ring_bond_length_ratio = 0.35
bond_length = molecular_ring_bond_length_ratio * nucleotide_slot_spacing
print(f"bond_length = {bond_length}")

ring = derive_regular_ring(RING_ROLE_SUFFIXES, bond_length)
print("\n-- Ribose ring local positions (identical for every base) --")
for k, v in ring.items():
    print(f"  {k}: ({v[0]:.4f}, {v[1]:.4f})")

def apply_strand_direction(local_positions, pivot, sign):
    if sign >= 0:
        return dict(local_positions)
    return {k: sub(scale(pivot, 2.0), v) for k, v in local_positions.items()}

c1_local = ring["c1_prime"]
for sign, label in [(1.0, "sign +1 (template_top/lagging)"), (-1.0, "sign -1 (template_bottom/leading)")]:
    rotated = apply_strand_direction(ring, c1_local, sign)
    print(f"\n-- Ribose ring, {label}, world offset from C1' (= local - c1_local) --")
    for k in RING_ROLE_SUFFIXES:
        off = sub(rotated[k], c1_local)
        print(f"  {k}: ({off[0]:.4f}, {off[1]:.4f})")

# ---- Base layout (NitrogenBaseDeriver.derive_base_layout) ----
def derive_base_layout(base_letter, c1_position, pairing_direction, bond_length):
    is_purine = base_letter in ("A", "G")
    attachment_suffix = "n9" if is_purine else "n1"
    if is_purine:
        local = derive_regular_ring(PURINE_SIX_RING_SUFFIXES, bond_length)
        five_ring, center, sa, ta, direction = derive_fused_ring(
            local["c4"], local["c5"], PURINE_FIVE_RING_REMAINING_SUFFIXES, (0.0, 0.0)
        )
        local.update(five_ring)
        print(f"    [purine fused-ring debug] center={center}, start_angle_deg={math.degrees(sa):.3f}, target_angle_deg={math.degrees(ta):.3f}, direction={direction}")
        for k in PURINE_FIVE_RING_REMAINING_SUFFIXES:
            print(f"    local[{k}] = ({local[k][0]:.4f}, {local[k][1]:.4f})")
        print(f"    local[c5] = ({local['c5'][0]:.4f}, {local['c5'][1]:.4f})  <-- compare to n9 above")
    else:
        local = derive_regular_ring(PYRIMIDINE_RING_SUFFIXES, bond_length)

    dirn = normalized(pairing_direction) if length(pairing_direction) > 0 else (0.0, 1.0)
    attachment_target = add(c1_position, scale(dirn, bond_length))
    translation = sub(attachment_target, local[attachment_suffix])
    positions = {k: add(v, translation) for k, v in local.items()}
    return positions

def pairing_anchor_suffix(base_letter):
    return {"A": "n1", "T": "n3", "G": "n1", "C": "n3"}[base_letter]

# ---- Set up the two pairs ----
dna_ribbons_gap = 90.0
center_y = 0.0
template_strand_y = center_y + dna_ribbons_gap / 2.0          # bottom rail resting y = 45
top_bonded_y = template_strand_y - dna_ribbons_gap             # top rail resting y = -45
slot_x = 1000.0  # arbitrary, same x for both strands at a given slot (paired directly across)

STRAND_SIGN = {"leading": -1.0, "lagging": 1.0, "template_bottom": -1.0, "template_top": 1.0}

def residue_world_pos(strand):
    return (slot_x, top_bonded_y) if strand == "template_top" else (slot_x, template_strand_y)

def compute_anchor_world(strand, base_letter, partner_world_pos):
    world_pos = residue_world_pos(strand)
    sign = STRAND_SIGN[strand]
    ring_l = derive_regular_ring(RING_ROLE_SUFFIXES, bond_length)
    c1_l = ring_l["c1_prime"]
    ring_l = apply_strand_direction(ring_l, c1_l, sign)
    anchor_offset = c1_l  # computed pre-rotation, but c1 is the fixed pivot so identical either way
    pairing_direction = sub(partner_world_pos, world_pos)
    print(f"  [{strand}:{base_letter}] world_pos={world_pos}, pairing_direction={pairing_direction}, sign={sign}")
    base_pos = derive_base_layout(base_letter, c1_l, pairing_direction, bond_length)
    anchor_suffix = pairing_anchor_suffix(base_letter)
    anchor_local = base_pos[anchor_suffix]
    anchor_world = add(world_pos, sub(anchor_local, anchor_offset))
    print(f"  [{strand}:{base_letter}] anchor='{anchor_suffix}' local={anchor_local}, world={anchor_world}")
    return anchor_world

print("\n\n==== PAIR 1: G on template_top, C on template_bottom (slot n) ====")
top_wp = residue_world_pos("template_top")
bot_wp = residue_world_pos("template_bottom")
g_anchor = compute_anchor_world("template_top", "G", bot_wp)
c_anchor = compute_anchor_world("template_bottom", "C", top_wp)
span1 = length(sub(g_anchor, c_anchor))
print(f"  H-bond span (G-top/C-bottom) = {span1:.4f}")

print("\n==== PAIR 2: C on template_top, G on template_bottom (slot m) ====")
c2_anchor = compute_anchor_world("template_top", "C", bot_wp)
g2_anchor = compute_anchor_world("template_bottom", "G", top_wp)
span2 = length(sub(c2_anchor, g2_anchor))
print(f"  H-bond span (C-top/G-bottom) = {span2:.4f}")

print(f"\nDIFFERENCE: span1 - span2 = {span1 - span2:.4f}")
