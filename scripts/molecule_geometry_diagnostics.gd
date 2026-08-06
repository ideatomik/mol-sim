class_name MoleculeGeometryDiagnostics
extends RefCounted

# ==========================================
# MOLECULE GEOMETRY DIAGNOSTICS
# Extracted from molecule_structure_renderer.gd (docs/superpowers/plans/
# 2026-08-03-template-strand-self-paired-rendering.md, Task 1) — pure move,
# no behavior change. The F9 live geometry dump: pairing scan, same-letter
# scan, full-residue derivation for diagnostics, self-paired boundary
# rotation trace. See molecule_structure_renderer.gd's F9 key-listener
# (_process()) for the call site.
# ==========================================

const _DIAG_PAIR_COUNT: int = 10
const _DIAG_RING_ROLE_LABELS: Dictionary = {
	"c1_prime": "C1'", "c2_prime": "C2'", "c3_prime": "C3'",
	"c4_prime": "C4'", "o4_prime": "O4'",
}
## Ring-backbone suffixes plus every exocyclic substituent suffix
## _place_base_substituents() (nitrogen_base_deriver.gd) can place — o2/n4
## (C), o2/o4/c5_methyl (T), n6 (A), o6/n2 (G). Diagnostic-only: these
## atoms were already present in base_positions and already counted toward
## base_diameter (confirmed: thymine's printed diameter, 43.2, already
## reflects o4/c5_methyl even before this list named them) — this just
## makes them visible in the printed block. The existing per-suffix
## `if base_positions.has(id)` guard below already silently skips any
## suffix absent from a given base (same mechanism that already lets
## purine-only n7/c8/n9 coexist here with pyrimidine-only suffixes), so
## listing every base's substituents in one shared array is safe.
const _DIAG_BASE_ROLE_SUFFIXES: Array[String] = ["n1", "c2", "n3", "c4", "c5", "c6", "n7", "c8", "n9", "o2", "o4", "n4", "n6", "n2", "o6", "c5_methyl"]

const _DIAG_OUTPUT_PATH: String = "user://geometry_dump.txt"

## Writes (appends) to user://geometry_dump.txt instead of print() —
## deliberately NOT going through the remote debugger connection. Console
## only gets one short breadcrumb line per dump, never the full content.
static func dump(renderer: Node2D, replication_mgr: Node, template_sim: Node, fold_cache: Dictionary, operators: Array[ReactionOperator]) -> void:
	var out: Array = []
	var bond_length: float = renderer.tm.molecular_ring_bond_length_ratio * renderer._slot_spacing()
	out.append("=== GEOMETRY DIAGNOSTIC DUMP (%s) ===" % Time.get_datetime_string_from_system())
	out.append("nucleotide_slot_spacing = %s" % renderer._slot_spacing())
	out.append("dna_ribbons_gap = %s" % renderer._dna_ribbons_gap())
	out.append("molecular_extra_ribbons_gap = %s  (render-only push, added per strand — see MOLECULAR_ROW_PUSH)" % renderer.tm.molecular_extra_ribbons_gap)
	out.append("molecular_ring_bond_length_ratio = %s" % renderer.tm.molecular_ring_bond_length_ratio)
	out.append("bond_length = %s" % bond_length)
	out.append("LIFECYCLE: fold TOPOLOGY (atoms/bonds, MoleculeFoldEngine.fold) is cached forever per \"strand:slot\" key in _fold_cache once first built, for every strand including template — never invalidated. Ring/base LOCAL GEOMETRY (RiboseDeriver.derive_ring/apply_strand_direction, NitrogenBaseDeriver.derive_base_layout) is recomputed FRESH every _process()/_rebuild_layout() call, every frame, for every strand including template — never cached. Any template-vs-leading/lagging difference found below is therefore numerical (real sequence/position data), not a staleness artifact.")

	var template_entries: Array[Dictionary] = template_sim.get_template_nucleotides() if template_sim != null else []
	var synth_entries: Array[Dictionary] = replication_mgr.get_synthesized_nucleotides() if replication_mgr != null else []

	# Same-strand-neighbor position lookup (real same-strand-neighbor
	# direction fix, docs/MolecularStructureDesign.md's Layout rule + Open
	# Question 10) — mirrors _rebuild_layout()'s own position_by_key, built
	# once here from every entry across every strand so _derive_full_residue()
	# can look up a real previous/next same-strand neighbor exactly like the
	# live renderer does, not a diagnostic-only approximation.
	var diag_position_by_key: Dictionary = {}
	for e in template_entries:
		diag_position_by_key["%s:%d" % [e.strand, e.slot]] = renderer._molecular_render_pos(e.strand, e.world_position)
	for e in synth_entries:
		diag_position_by_key["%s:%d" % [e.strand, e.slot]] = renderer._molecular_render_pos(e.strand, e.world_position)

	_dump_pairing(renderer, replication_mgr, template_sim, out, "template_top", "template_bottom", template_entries, template_entries, bond_length, diag_position_by_key, synth_entries, fold_cache, operators)
	_dump_pairing(renderer, replication_mgr, template_sim, out, "leading", "template_top", synth_entries, template_entries, bond_length, diag_position_by_key, [], fold_cache, operators)
	_dump_pairing(renderer, replication_mgr, template_sim, out, "lagging", "template_bottom", synth_entries, template_entries, bond_length, diag_position_by_key, [], fold_cache, operators)

	# Full-sequence same-letter scan (docs/MolecularStructure_
	# BasePairExpansion.md, Bug E follow-up): the per-pairing dump above
	# only ever samples the first _DIAG_PAIR_COUNT slots. A same-letter
	# report at a slot outside that range would be invisible to it. This
	# scans EVERY slot present in each pairing and flags any where top and
	# bottom show the identical letter (never valid Watson-Crick), plus
	# prints the two full sequences so they can be eyeballed directly
	# against a screenshot.
	out.append("\n\n=== FULL-SEQUENCE SAME-LETTER SCAN (all slots, not just first 10) ===")
	_scan_pairing_for_same_letter(out, "template_top", "template_bottom", template_entries, template_entries)
	_scan_pairing_for_same_letter(out, "leading", "template_top", synth_entries, template_entries)
	_scan_pairing_for_same_letter(out, "lagging", "template_bottom", synth_entries, template_entries)

	out.append("=== END DUMP ===\n")

	var existing: String = ""
	if FileAccess.file_exists(_DIAG_OUTPUT_PATH):
		var read_f: FileAccess = FileAccess.open(_DIAG_OUTPUT_PATH, FileAccess.READ)
		if read_f != null:
			existing = read_f.get_as_text()
			read_f.close()
	var write_f: FileAccess = FileAccess.open(_DIAG_OUTPUT_PATH, FileAccess.WRITE)
	if write_f != null:
		write_f.store_string(existing + "\n".join(out) + "\n")
		write_f.close()
		print("[GEOMETRY DIAG] dump written to %s" % ProjectSettings.globalize_path(_DIAG_OUTPUT_PATH))
	else:
		print("[GEOMETRY DIAG] FAILED to open %s for writing" % _DIAG_OUTPUT_PATH)


## Scans EVERY slot present in this pairing (not just the first
## _DIAG_PAIR_COUNT) and reports any where top and bottom show the
## identical letter — never valid Watson-Crick, so any hit here is a real
## bug regardless of which slot range a screenshot happened to show.
## Also prints both full sequences (in slot order) so they can be
## eyeballed directly against a screenshot.
static func _scan_pairing_for_same_letter(out: Array, top_strand: String, bottom_strand: String, top_source: Array[Dictionary], bottom_source: Array[Dictionary]) -> void:
	var top_by_slot: Dictionary = {}
	for e in top_source:
		if e.strand == top_strand:
			top_by_slot[e.slot] = e.base_type
	var bottom_by_slot: Dictionary = {}
	for e in bottom_source:
		if e.strand == bottom_strand:
			bottom_by_slot[e.slot] = e.base_type

	out.append("\n--- %s (top) / %s (bottom) — %d top slots, %d bottom slots ---" % [top_strand, bottom_strand, top_by_slot.size(), bottom_by_slot.size()])
	if top_by_slot.is_empty() or bottom_by_slot.is_empty():
		out.append("  (nothing to scan yet)")
		return

	var max_slot: int = 0
	for s in top_by_slot.keys():
		max_slot = max(max_slot, s)
	for s in bottom_by_slot.keys():
		max_slot = max(max_slot, s)

	var top_seq: String = ""
	var bottom_seq: String = ""
	var violations: Array = []
	for slot in range(max_slot + 1):
		var t: String = top_by_slot.get(slot, "-")
		var b: String = bottom_by_slot.get(slot, "-")
		top_seq += t
		bottom_seq += b
		if t != "-" and b != "-" and t == b:
			violations.append(slot)

	out.append("  top    sequence (slot 0..%d): %s" % [max_slot, top_seq])
	out.append("  bottom sequence (slot 0..%d): %s" % [max_slot, bottom_seq])
	if violations.is_empty():
		out.append("  SAME-LETTER VIOLATIONS: none — every paired slot has two different letters.")
	else:
		out.append("  SAME-LETTER VIOLATIONS at %d slot(s): %s" % [violations.size(), str(violations)])


## unzip_check_entries, if non-empty: replicates _pair_for_slot()'s real
## unzip logic (docs/MolecularStructure_BasePairExpansion.md, Bug F
## unpaired-residue follow-up) — a template_top/template_bottom slot is
## ONLY really paired with its opposite template if NEITHER leading NOR
## lagging has a base at that slot yet; once either exists, the real
## renderer treats that template residue as UNPAIRED (pairing_direction =
## ZERO, triggering the chain-aware fallback), regardless of whether the
## opposite template residue still physically exists. The old version of
## this function ignored that and force-paired every slot where BOTH
## template entries existed, silently computing geometry from a fake
## pairing_direction the real renderer never uses once replication has
## started — confirmed to give misleading "closest approach" numbers, not
## just a misleading H-bond span (the previously-known issue). Slots that
## are really unpaired are now dumped through the SAME unpaired code path
## as leading/lagging's own unpaired case, so the numbers here always
## match what actually renders.
static func _dump_pairing(renderer: Node2D, replication_mgr: Node, template_sim: Node, out: Array, top_strand: String, bottom_strand: String, top_source: Array[Dictionary], bottom_source: Array[Dictionary], bond_length: float, position_by_key: Dictionary, unzip_check_entries: Array[Dictionary] = [], fold_cache: Dictionary = {}, operators: Array[ReactionOperator] = []) -> void:
	var top_by_slot: Dictionary = {}
	for e in top_source:
		if e.strand == top_strand:
			top_by_slot[e.slot] = e
	var bottom_by_slot: Dictionary = {}
	for e in bottom_source:
		if e.strand == bottom_strand:
			bottom_by_slot[e.slot] = e

	# Matches _pair_for_slot()'s corrected real condition (docs/
	# MolecularStructure_BasePairExpansion.md, "ghost H-bond past helicase"
	# fix): a slot is unzipped once the helicase has physically passed it,
	# not merely once leading/lagging synthesis has caught up — those are
	# different positions (polymerase_x_offset_slots keeps synthesis
	# several slots behind the helicase), and the old leading/lagging-
	# existence-only check here would under-report unzipped slots in that
	# gap, same as the renderer bug it was written to catch.
	var unzipped_slots: Dictionary = {}
	if not unzip_check_entries.is_empty():
		for e in unzip_check_entries:
			if e.strand == "leading" or e.strand == "lagging":
				unzipped_slots[e.slot] = true
	# Helicase-position check only applies to the genuine template_top-vs-
	# template_bottom self-pairing (mirrors _pair_for_slot()'s real branch
	# order: PARTNER_STRAND.has(strand) — leading/lagging — returns
	# unconditionally BEFORE ever reaching the helicase check, so it must
	# never run for a leading/template_top or lagging/template_bottom call).
	# Applying it there too force-marks every slot "unzipped" once the
	# helicase has passed the whole strand (e.g. a finished simulation),
	# corrupting those sections into all-UNPAIRED even though they're real,
	# synthesized Watson-Crick pairs the live renderer draws correctly.
	var is_template_self_pairing: bool = (top_strand == "template_top" and bottom_strand == "template_bottom") or (top_strand == "template_bottom" and bottom_strand == "template_top")
	if template_sim != null and is_template_self_pairing:
		for e in top_by_slot.values():
			if e.world_position.x < template_sim.helicase_x:
				unzipped_slots[e.slot] = true
		for e in bottom_by_slot.values():
			if e.world_position.x < template_sim.helicase_x:
				unzipped_slots[e.slot] = true

	out.append("\n--- PAIRING: %s (top) / %s (bottom) ---" % [top_strand, bottom_strand])
	if top_by_slot.is_empty() or bottom_by_slot.is_empty():
		out.append("  (no paired residues yet — %s has %d entries, %s has %d entries)" % [top_strand, top_by_slot.size(), bottom_strand, bottom_by_slot.size()])
		return

	var printed: int = 0
	var slot: int = 0
	var max_slot_scan: int = 5000
	while printed < _DIAG_PAIR_COUNT and slot < max_slot_scan:
		if top_by_slot.has(slot) and bottom_by_slot.has(slot):
			var top_entry: Dictionary = top_by_slot[slot]
			var bottom_entry: Dictionary = bottom_by_slot[slot]
			var really_paired: bool = not unzipped_slots.has(slot)

			if not really_paired:
				# Real renderer treats BOTH sides as unpaired here — dump each
				# independently through the unpaired (ZERO pairing_direction)
				# path, no fake partner.
				printed += 1
				var top_r_u: Dictionary = _derive_full_residue(renderer, top_entry, renderer._molecular_render_pos(top_entry.strand, top_entry.world_position), bond_length, position_by_key, false, fold_cache, operators)
				var bottom_r_u: Dictionary = _derive_full_residue(renderer, bottom_entry, renderer._molecular_render_pos(bottom_entry.strand, bottom_entry.world_position), bond_length, position_by_key, false, fold_cache, operators)
				out.append("\n[PAIR %d | sequence: %s%s | UNPAIRED — unzipped, real renderer uses fallback direction, not shown as a real pair]" % [printed, top_entry.base_type, bottom_entry.base_type])
				_write_residue_block(renderer, out, "TOP (unpaired)", top_r_u)
				_write_residue_block(renderer, out, "BOTTOM (unpaired)", bottom_r_u)
				out.append("OVERLAP CHECK (own-base only, no real cross-strand pairing to check):")
				out.append("  top    substituent chain closest approach to OWN base = %.4f  (chain reaches %.4f from C1')" % [top_r_u.chain_closest_to_own_base, top_r_u.chain_far_from_c1])
				out.append("  bottom substituent chain closest approach to OWN base = %.4f  (chain reaches %.4f from C1')" % [bottom_r_u.chain_closest_to_own_base, bottom_r_u.chain_far_from_c1])
				slot += 1
				continue

			printed += 1
			var top_r: Dictionary = _derive_full_residue(renderer, top_entry, renderer._molecular_render_pos(bottom_entry.strand, bottom_entry.world_position), bond_length, position_by_key, is_template_self_pairing, fold_cache, operators)
			var bottom_r: Dictionary = _derive_full_residue(renderer, bottom_entry, renderer._molecular_render_pos(top_entry.strand, top_entry.world_position), bond_length, position_by_key, is_template_self_pairing, fold_cache, operators)

			out.append("\n[PAIR %d | sequence: %s%s]" % [printed, top_entry.base_type, bottom_entry.base_type])
			_write_residue_block(renderer, out, "TOP", top_r)
			var span: float = top_r.anchor_world.distance_to(bottom_r.anchor_world)
			out.append("H-BOND:")
			out.append("  anchor-to-anchor world distance = %.4f" % span)
			out.append("  dna_ribbons_gap for reference    = %s" % renderer._dna_ribbons_gap())
			# STALE as of the real-atom-pair H-bond rewrite (docs/
			# MolecularStructure_BasePairExpansion.md): originally added for
			# Bug R verification, mirroring _draw()'s old perp/offset dash
			# spacing computation so the dump could confirm what actually
			# rendered. That mechanism no longer exists — _draw() now draws
			# real per-atom-pair segments (HBOND_OWN_TO_PARTNER_ROLES), no
			# spacing/offset math at all. Left in place (flagged, not
			# silently deleted) since the numbers are still mathematically
			# real, just no longer describing anything the renderer uses.
			var h_bond_count: int = NitrogenBaseDeriver.hydrogen_bond_count(top_entry.base_type)
			var h_bond_dash_spacing: float = renderer.tm.molecular_hydrogen_bond_spacing_ratio * bond_length
			var h_bond_outermost_offset: float = float(h_bond_count - 1) * h_bond_dash_spacing / 2.0
			out.append("  dash spacing (molecular_hydrogen_bond_spacing_ratio * bond_length) = %.4f  (ratio=%s, bond_length=%.4f)" % [h_bond_dash_spacing, renderer.tm.molecular_hydrogen_bond_spacing_ratio, bond_length])
			out.append("  outermost dash offset (%d-line pair) = %.4f" % [h_bond_count, h_bond_outermost_offset])
			_write_residue_block(renderer, out, "BOTTOM", bottom_r)

			var top_closest_to_bottom_center: float = _closest_world_distance(top_r.base_world_positions.values(), bottom_r.world_pos)
			var bottom_closest_to_top_center: float = _closest_world_distance(bottom_r.base_world_positions.values(), top_r.world_pos)
			out.append("OVERLAP CHECK:")
			out.append("  top base ring closest-atom -> bottom strand center    = %.4f" % top_closest_to_bottom_center)
			out.append("  bottom base ring closest-atom -> top strand center    = %.4f" % bottom_closest_to_top_center)
			out.append("  top    ribose-to-own-base (attachment -> ring center) = %.4f  (base ring diameter = %.4f)" % [top_r.attachment_to_ring_center, top_r.base_diameter])
			out.append("  bottom ribose-to-own-base (attachment -> ring center) = %.4f  (base ring diameter = %.4f)" % [bottom_r.attachment_to_ring_center, bottom_r.base_diameter])
			out.append("  top    substituent chain closest approach to OWN base = %.4f  (chain reaches %.4f from C1')" % [top_r.chain_closest_to_own_base, top_r.chain_far_from_c1])
			out.append("  bottom substituent chain closest approach to OWN base = %.4f  (chain reaches %.4f from C1')" % [bottom_r.chain_closest_to_own_base, bottom_r.chain_far_from_c1])
		slot += 1

## Rebuilds one residue's full local+world geometry directly (same calls
## _rebuild_layout() makes), independent of culling. Returns everything the
## dump format needs, keyed for direct printing.
static func _derive_full_residue(renderer: Node2D, entry: Dictionary, partner_world_pos: Vector2, bond_length: float, position_by_key: Dictionary = {}, is_self_paired_template: bool = false, fold_cache: Dictionary = {}, operators: Array[ReactionOperator] = []) -> Dictionary:
	var strand: String = entry.strand
	var slot: int = entry.slot
	var base_type: String = entry.base_type
	var world_pos: Vector2 = renderer._molecular_render_pos(strand, entry.world_position)

	var cache_key: String = "%s:%d" % [strand, slot]
	var topology: MoleculeTopology = fold_cache.get(cache_key)
	if topology == null:
		var seed: MoleculeTopology = RiboseDeriver.build_incoming_nucleotide_seed("incoming.", base_type)
		topology = MoleculeFoldEngine.fold(seed, operators, 0)
		fold_cache[cache_key] = topology

	var ring_positions: Dictionary = RiboseDeriver.derive_ring(topology, "incoming.", bond_length)
	var c1_id: int = topology.find_by_role("incoming.c1_prime")
	var c1_local: Vector2 = ring_positions.get(c1_id, Vector2.ZERO)

	var pairing_direction: Vector2 = partner_world_pos - world_pos

	# Real same-strand-neighbor direction — moved up ahead of the
	# ring-rotation decision below (mirrors _rebuild_layout()'s identical
	# reordering for Bug W: resolve_self_paired_ring_rotation() needs these
	# real vectors to run its own clearance search). See the full comment
	# on this block in _rebuild_layout().
	var neighbor_sign: float = renderer._strand_direction_sign(strand)
	var next_slot_key: String = "%s:%d" % [strand, slot + 1]
	var prev_slot_key: String = "%s:%d" % [strand, slot - 1]
	var more_3prime_key: String = next_slot_key if neighbor_sign >= 0.0 else prev_slot_key
	var more_5prime_key: String = prev_slot_key if neighbor_sign >= 0.0 else next_slot_key
	var toward_next: Vector2 = Vector2.ZERO
	if position_by_key.has(more_3prime_key):
		toward_next = position_by_key[more_3prime_key] - world_pos
	var toward_previous: Vector2 = Vector2.ZERO
	if position_by_key.has(more_5prime_key):
		toward_previous = position_by_key[more_5prime_key] - world_pos

	# Self-paired-template correction (docs/MolecularStructure_
	# BasePairExpansion.md, Bug V/Bug W) — mirrors _rebuild_layout()'s
	# identical logic exactly, so the diagnostic dump reports the same
	# geometry the live renderer actually draws. is_self_paired_template is
	# caller-supplied (_dump_pairing() already computes the equivalent
	# is_template_self_pairing for Bug P) rather than re-derived here,
	# since this function only receives a partner WORLD POSITION, not a
	# partner key it could classify itself.
	var substituent_positions: Dictionary = {}
	# STAGE 1 -- mirrors _rebuild_layout()'s identical bypass exactly (see
	# that block's own comment for the full rationale: both the mirror and
	# the bake were found to have real geometry bugs via this same dump,
	# so both are deliberately bypassed, not deleted, in favor of the
	# plain leading/lagging formula, to re-establish a known-clean
	# baseline). This dump must keep reporting the same geometry the live
	# renderer actually draws.
	ring_positions = RiboseDeriver.apply_strand_direction(ring_positions, c1_local, renderer._strand_direction_sign(strand))

	# Bug V verification (docs/MolecularStructure_BasePairExpansion.md):
	# unlike anchor_alignment_dot below (a DIFFERENT, pre-existing metric —
	# the BASE ring's own anchor-vs-partner check, from an independent
	# rotation search), this measures the RIBOSE ring's own bulge
	# direction against pairing_direction, using the FINAL post-rotation
	# ring_positions — i.e. whatever apply_strand_direction() actually
	# just decided, regardless of which branch (fixed sign vs. self-paired
	# override) produced it. Computed unconditionally (not just for the
	# self-paired-template case) so leading/lagging/synthesized-partner
	# residues are visible here too, for direct before/after comparison.
	var bulge_ring_ids: Array = [
		topology.find_by_role("incoming.c2_prime"), topology.find_by_role("incoming.c3_prime"),
		topology.find_by_role("incoming.c4_prime"), topology.find_by_role("incoming.o4_prime"),
	]
	var bulge_vs_pairing_dot: float = 0.0
	var bulge_sum2: Vector2 = Vector2.ZERO
	var bulge_count2: int = 0
	for bulge_id2 in bulge_ring_ids:
		if ring_positions.has(bulge_id2):
			bulge_sum2 += ring_positions[bulge_id2]
			bulge_count2 += 1
	if bulge_count2 > 0:
		var final_bulge: Vector2 = bulge_sum2 / float(bulge_count2) - c1_local
		if final_bulge.length() > 0.0 and pairing_direction.length() > 0.0:
			bulge_vs_pairing_dot = final_bulge.normalized().dot(pairing_direction.normalized())

	# toward_next/toward_previous (real same-strand-neighbor vectors) were
	# already computed above, ahead of the ring-rotation decision — reused
	# here unmodified.
	# STAGE 1: unconditional now, matching the ring derivation above — see
	# that block's comment. is_self_paired_template no longer changes this
	# call for this stage.
	substituent_positions = RiboseDeriver.derive_substituents(topology, "incoming.", ring_positions, bond_length, toward_next, toward_previous)

	var base_positions: Dictionary = NitrogenBaseDeriver.derive_base_layout(topology, "incoming.", base_type, c1_local, pairing_direction, bond_length, ring_positions.values() + substituent_positions.values())

	var ring_named: Dictionary = {}
	for suffix in _DIAG_RING_ROLE_LABELS:
		var id: int = topology.find_by_role("incoming." + suffix)
		if ring_positions.has(id):
			ring_named[_DIAG_RING_ROLE_LABELS[suffix]] = ring_positions[id]

	var base_named: Dictionary = {}
	for suffix in _DIAG_BASE_ROLE_SUFFIXES:
		var id: int = topology.find_by_role("incoming." + suffix)
		if base_positions.has(id):
			base_named[suffix.to_upper()] = base_positions[id]

	var is_purine: bool = base_type == "A" or base_type == "G"
	var attachment_suffix: String = "n9" if is_purine else "n1"
	var attachment_id: int = topology.find_by_role("incoming." + attachment_suffix)
	var attachment_local: Vector2 = base_positions.get(attachment_id, Vector2.ZERO)

	var anchor_suffix: String = NitrogenBaseDeriver.pairing_anchor_suffix(base_type)
	var anchor_id: int = topology.find_by_role("incoming." + anchor_suffix)
	var anchor_local: Vector2 = base_positions.get(anchor_id, Vector2.ZERO)
	var anchor_world: Vector2 = world_pos + (anchor_local - c1_local)

	var ring_centroid: Vector2 = _centroid(ring_positions.values())
	var base_world_positions: Dictionary = {}
	for id in base_positions:
		base_world_positions[id] = world_pos + (base_positions[id] - c1_local)

	# Substituent chain (docs/MolecularStructure_BasePairExpansion.md, Bug D
	# follow-up): O3'/C5'/O5'/alpha-phosphate — placed radially OUTWARD from
	# C4' by RiboseDeriver.derive_substituents(), chained (C5' = C4' +
	# outward*bond_length, O5' = C5' + outward*bond_length, alpha_phosphate
	# = O5' + outward*bond_length) — 3 full bond_lengths beyond the ring
	# itself, in the SAME "outward" direction every time. Not covered by
	# the earlier "ribose ring diameter" measurement (ring atoms only) —
	# this chain can reach much further than the bare ring, and its
	# direction is tied to ring rotation (sign) same as the ring itself,
	# independently of the base's own pairing-direction-based rotation.
	const CHAIN_ROLE_LABELS: Dictionary = {
		"o3_prime": "O3'", "c5_prime": "C5'", "o5_prime": "O5'", "alpha_phosphate": "alpha-P",
	}
	var chain_named: Dictionary = {}
	for suffix in CHAIN_ROLE_LABELS:
		var id: int = topology.find_by_role("incoming." + suffix)
		if substituent_positions.has(id):
			chain_named[CHAIN_ROLE_LABELS[suffix]] = substituent_positions[id]
	var chain_far_from_c1: float = 0.0
	for p in substituent_positions.values():
		chain_far_from_c1 = max(chain_far_from_c1, p.distance_to(c1_local))
	var chain_closest_to_own_base: float = INF
	for p in substituent_positions.values():
		for bp in base_positions.values():
			chain_closest_to_own_base = min(chain_closest_to_own_base, p.distance_to(bp))

	# Chain-vs-own-ribose overlap check (docs/MolecularStructure_
	# BasePairExpansion.md, slot-0-broken-render investigation) — same
	# closest-atom pattern as chain_closest_to_own_base above, but against
	# the ribose ring's own atoms (C1'/C2'/C3'/C4'/O4') instead of the
	# base. If the reported live-screenshot symptom (O3' sitting on top of
	# C4') is real, this reads near-zero specifically at the affected slot
	# and normal everywhere else — a real number instead of a screenshot
	# impression, and independent of whatever bulge_vs_pairing_dot reports
	# (a same-strand-neighbor/chain-construction issue would show up here
	# regardless of whether the ring-rotation choice itself is correct).
	var chain_closest_to_own_ribose: float = INF
	for p2 in substituent_positions.values():
		for rp in ring_positions.values():
			chain_closest_to_own_ribose = min(chain_closest_to_own_ribose, p2.distance_to(rp))

	# World-space per-group coordinates (CQA follow-up — user asked whether
	# the dump discriminates which molecule/group an atom belongs to: yes,
	# ring_named/base_named/chain_named already do — but only LOCAL coords
	# were ever printed, forcing a manual local->world conversion by hand
	# to see what's actually overlapping on screen. Added directly here so
	# "is X too close to Y" is readable off the dump without doing that
	# conversion yourself.
	var ring_world_named: Dictionary = {}
	for role_label in ring_named:
		ring_world_named[role_label] = world_pos + (ring_named[role_label] - c1_local)
	var base_world_named: Dictionary = {}
	for role_label in base_named:
		base_world_named[role_label] = world_pos + (base_named[role_label] - c1_local)
	var chain_world_named: Dictionary = {}
	for role_label in chain_named:
		chain_world_named[role_label] = world_pos + (chain_named[role_label] - c1_local)

	# Direction check (CQA follow-up, docs/MolecularStructure_
	# BasePairExpansion.md, Bug F re-opened): the anchor-fixed clearance
	# search (Bug F correction) pins the ATTACHMENT atom toward
	# pairing_direction but rotates the rest of the ring FREELY to
	# maximize clearance from the ribose's own substituent chain — nothing
	# constrains the ANCHOR atom (the one actually used to aim the H-bond
	# at the real partner) to stay anywhere near that direction. This dot
	# product is strictly diagnostic: >0 means the anchor is at least on
	# the correct side of C1' (facing the partner); <0 means the search
	# picked a rotation that points the anchor AWAY from the real partner
	# entirely — the base's own chain and the partner happen to sit on the
	# same general side often enough that this is not a rare edge case.
	var anchor_dir: Vector2 = anchor_local - c1_local
	var anchor_alignment_dot: float = anchor_dir.normalized().dot(pairing_direction.normalized()) if anchor_dir.length() > 0.0 and pairing_direction.length() > 0.0 else 0.0

	return {
		strand = strand, slot = slot, sign = renderer._strand_direction_sign(strand),
		base_type = base_type, world_pos = world_pos,
		ring_named = ring_named, ring_world_named = ring_world_named,
		ring_diameter = _max_pairwise_distance(ring_positions.values()),
		attachment_suffix = attachment_suffix.to_upper(), attachment_local = attachment_local,
		attachment_dist_from_c1 = attachment_local.distance_to(c1_local),
		attachment_to_ring_center = attachment_local.distance_to(ring_centroid),
		base_named = base_named, base_world_named = base_world_named,
		base_diameter = _max_pairwise_distance(base_positions.values()),
		anchor_suffix = anchor_suffix.to_upper(), anchor_world = anchor_world,
		base_world_positions = base_world_positions,
		chain_named = chain_named, chain_world_named = chain_world_named,
		chain_far_from_c1 = chain_far_from_c1,
		chain_closest_to_own_base = chain_closest_to_own_base,
		chain_closest_to_own_ribose = chain_closest_to_own_ribose,
		pairing_direction = pairing_direction,
		anchor_alignment_dot = anchor_alignment_dot,
		bulge_vs_pairing_dot = bulge_vs_pairing_dot,
	}


static func _write_residue_block(renderer: Node2D, out: Array, label: String, r: Dictionary) -> void:
	out.append("%s NUCLEOTIDE (strand=%s, slot=%d, sign=%s):" % [label, r.strand, r.slot, ("+1" if r.sign >= 0.0 else "-1")])
	out.append("  world_pos (residue anchor, = C1' world position) = (%.4f, %.4f)" % [r.world_pos.x, r.world_pos.y])
	out.append("  ribose ring [RIBOSE] — local / world coords:")
	for role_label in r.ring_named:
		var p: Vector2 = r.ring_named[role_label]
		var pw: Vector2 = r.ring_world_named[role_label]
		out.append("    %s: local=(%.4f, %.4f)  world=(%.4f, %.4f)" % [role_label, p.x, p.y, pw.x, pw.y])
	out.append("  ribose ring diameter (widest extent) = %.4f" % r.ring_diameter)
	out.append("  RIBOSE RING bulge_vs_pairing_dot (Bug V verification, post-rotation, actual rendered value) = %.4f  (%s)" % [
		r.bulge_vs_pairing_dot,
		"bulge faces AWAY from partner (self-paired-template goal)" if r.bulge_vs_pairing_dot < 0.0 else "bulge faces TOWARD partner" if r.bulge_vs_pairing_dot > 0.0 else "n/a, unpaired"
	])
	out.append("  substituent chain [CHAIN: O3'/C5'/O5'/alpha-P] — local / world coords:")
	for role_label in r.chain_named:
		var pc: Vector2 = r.chain_named[role_label]
		var pcw: Vector2 = r.chain_world_named[role_label]
		out.append("    %s: local=(%.4f, %.4f)  world=(%.4f, %.4f)" % [role_label, pc.x, pc.y, pcw.x, pcw.y])
	out.append("  substituent chain farthest point from C1' = %.4f" % r.chain_far_from_c1)
	out.append("  substituent chain closest approach to OWN ribose ring = %.4f  (slot-0-broken-render check: near-zero means a chain atom is sitting on a ring atom)" % r.chain_closest_to_own_ribose)
	out.append("  DIRECTION CHECK: pairing_direction (toward real partner) = (%.4f, %.4f)  anchor_alignment_dot = %.4f  (%s)" % [
		r.pairing_direction.x, r.pairing_direction.y, r.anchor_alignment_dot,
		"anchor faces partner" if r.anchor_alignment_dot > 0.0 else "anchor faces AWAY from partner" if r.pairing_direction.length() > 0.0 else "n/a, unpaired"
	])
	out.append("  attachment atom (%s): local=(%.4f, %.4f), distance from C1' = %.4f" % [r.attachment_suffix, r.attachment_local.x, r.attachment_local.y, r.attachment_dist_from_c1])
	out.append("  base ring [BASE] — local / world coords:")
	for role_label in r.base_named:
		var p2: Vector2 = r.base_named[role_label]
		var p2w: Vector2 = r.base_world_named[role_label]
		out.append("    %s: local=(%.4f, %.4f)  world=(%.4f, %.4f)" % [role_label, p2.x, p2.y, p2w.x, p2w.y])
	out.append("  base ring diameter (widest extent) = %.4f" % r.base_diameter)
	out.append("  anchor atom (%s): world=(%.4f, %.4f)" % [r.anchor_suffix, r.anchor_world.x, r.anchor_world.y])


static func _max_pairwise_distance(points) -> float:
	var pts: Array = Array(points)
	var best: float = 0.0
	for i in range(pts.size()):
		for j in range(i + 1, pts.size()):
			var d: float = pts[i].distance_to(pts[j])
			if d > best:
				best = d
	return best


static func _centroid(points) -> Vector2:
	var pts: Array = Array(points)
	if pts.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for p in pts:
		sum += p
	return sum / pts.size()


static func _closest_world_distance(points, target: Vector2) -> float:
	var pts: Array = Array(points)
	var best: float = INF
	for p in pts:
		var d: float = p.distance_to(target)
		if d < best:
			best = d
	return best
