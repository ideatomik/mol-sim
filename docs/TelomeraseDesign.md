# Telomerase Visual Design — pre-implementation
_Design document. Companion to DESIGN.md, COMPLEXITY_MODEL.md, and
OkazakiMaturationDesign.md. Addresses STATUS.md's Near-term Telomerase tier
checklist item: "Design telomerase's own visual (extends the gap, doesn't
just leave it)." No As-Built section yet — nothing here has shipped. One
sequencing decision IS locked in: SSB ships first as its own general-purpose
toggle, shelterin later specifically for telomerase — see "Overhang
protection" below._

---

## Context

The **telomere gap** is already fully implemented: `lagging_gap_enabled`
(gated behind `topology_mode == LINEAR`) makes catch-up finish the whole
lagging strand, then removes the terminal RNA primer via the normal Pol I
sweep (or a quiet fade at Light tier), leaving its footprint as
`lagging_telomere_gap`. That is the **consequence** of the end-replication
problem — biologically accurate, scrub-safe, and correctly sized to one
primer's length, not a pacing artifact.

What doesn't exist yet is the **actor**: the enzyme that, in a real cell,
would extend the telomere and prevent that gap from compounding generation
after generation. Right now the "telomerase tier" toggle only ever shows the
problem, never the mitigation. This document designs that missing half.

**Explicitly not in scope for THIS pass:** SSB (`ssb` in COMPLEXITY_MODEL.md's
Toggle Registry) is a separate, still-`NEW`, general Stage 2 elongation
toggle — it belongs to its own design/implementation pass, independent of
telomerase, since it coats ssDNA everywhere behind the helicase during
ordinary fork progression, not just at telomeres. **Decision (this session):**
SSB ships first, on its own, as general-purpose replisome furniture.
Shelterin — the actual telomere-specific overhang protector — is a later,
separate addition scoped specifically for telomerase; see "Overhang
protection" below for how the two relate once both exist.

---

## Biological mechanism

Telomerase does not fill the lagging-strand gap directly. It extends the
**template** strand's 3' end, giving the lagging-strand machinery more room
to work with — then that machinery (primase → Pol III → Pol I → ligase,
already fully built) gets a second, genuinely new invocation over the newly
lengthened region.

1. Telomerase is a ribonucleoprotein: protein (**TERT**, a reverse
   transcriptase) plus a short **RNA template** built into the enzyme
   itself — not read from the chromosome.
2. It binds the 3' overhang of the template strand and base-pairs part of
   its own internal RNA against the existing DNA end.
3. Using that RNA as template, it reverse-transcribes new DNA repeats onto
   the template strand's 3' end. This is synthesis in the **template**
   direction — the strand MolSim currently treats as fixed and read-only.
4. It **translocates**: releases, repositions further out along its own
   just-synthesized repeat, and repeats the cycle. Real telomerase does this
   several times per telomere-maintenance event, not once.
5. Only after the template is longer can the normal lagging-strand
   machinery place one more primer out there and fill in some of what would
   otherwise have been lost.
6. Even then, the tip always ends up as a single-stranded 3' overhang —
   telomerase **tops up** the loss, it does not erase it. That overhang is
   itself a real, protected structure (shelterin-bound in vivo), not a
   simulation shortfall to hide.

Point 6 is the pedagogically load-bearing part: a correct telomerase pass
must still end in an unresolved 3' overhang, or it teaches that telomerase
solves shortening outright, which is false and is exactly the kind of
unlabeled-chimera error COMPLEXITY_MODEL.md's whole framework exists to
prevent.

---

## Why this is architecture, not a new enzyme sprite

Every other enzyme added so far — primase, Pol I, ligase — operates within a
strand whose length is fixed at load time. `sim.num_nucleotide_slots` and
`sim.nucleotide_original_x[]` are set once in `simulation.gd` on sequence
load and never grow afterward. Telomerase's actual mechanism requires the
**template strand to lengthen mid-run**, which no existing system supports:

- New template bases must appear, visually growing rightward past where the
  original sequence ended.
- `nucleotide_original_x[]` (and anything indexed by it — helicase
  positioning, zoom frame-providers, the SequenceLabel window) needs either
  a genuine append path or a documented reason it can stay fixed while
  telomerase's added bases render some other way.
- Telomerase needs its own visual with a visible internal RNA template loop,
  distinguished from primase's primers the same way RNA is already
  distinguished from DNA elsewhere in the scene — shape/thickness first,
  color second (accessibility rule, already established for primase).
- A translocation/repeat animation: bind → extend → release → hop → repeat,
  not a single extend-and-leave.
- Once telomerase finishes extending, the **existing** primase → Pol III →
  Pol I → ligase pipeline needs a second, genuinely new invocation over the
  newly-lengthened region — reopening after the scene had already started
  its end-of-run fade, not a one-off tacked onto the first pass.
- That second pass must still end in an overhang (see mechanism point 6) —
  the extension shortens the gap, it must not close it to zero.

This is comparable in scope to the Okazaki maturation relay (primase + Pol I
+ ligase together), not to a single enzyme visual pass like helicase or the
polymerase clamps.

---

## Visual concept (proposed, unresolved)

Not yet designed in detail — flagged here as the shape of the open work,
not a decision:

- Telomerase's own body: likely a rounded-octagon family member (matches
  the established visual vocabulary — see DESIGN.md/PolymeraseDesign.md's
  "rounded octagons are the established shape language across all
  enzymes"), sized and posed to visibly carry an internal RNA loop.
- The RNA template loop itself: rounded-square RNA styling (existing
  primase convention), arranged as a visible loop rather than a linear
  strand, since real telomerase RNA is base-paired back on itself as part
  of the enzyme, not lying flat like a primer.
- Translocation: a hop/reposition animation along the template's 3' end,
  repeating a small, fixed number of times per telomere-maintenance event
  (exact repeat count TBD — probably ThemeManager-tunable, not hardcoded).
- Newly-synthesized template repeats: need their own base-appearance
  animation, analogous to `_capture_begin_lagging`'s halo-to-backbone
  travel, but on the template strand and in the template's own growth
  direction (rightward, past the original sequence end) rather than
  lagging-strand-relative.
- Occurs at scene-fade time, after helicase/Pol III/Pol I/ligase have
  already done their first-pass work and the enzyme scene would otherwise
  already be fading — telomerase's own activity needs to defer or briefly
  reverse that fade, not race it.

---

## Scrub-safety implications

This is the part most likely to break the project's non-negotiable
constraint if under-designed, so flagging it explicitly rather than leaving
it implicit:

- Scrub shows only finished states. A telomerase pass has multiple
  translocation cycles, each itself a bind → extend → release sequence —
  scrubbing to any point mid-run must show a **fully resolved** state of
  however many translocation cycles have "completed" by that scrub
  position, never a mid-bind or mid-extension frame. This mirrors how the
  terminal-primer-removal gap state was made scrub-safe (reconstruct the
  finished state directly, don't replay the animation) — the same pattern
  should extend to each translocation cycle, not just the final one.
- `_lagging_scrub_rebuild()`'s DONE-phase branch will need to know how many
  template repeats (if any) existed at the scrubbed-to point, and
  reconstruct the second-pass primase/Pol III/Pol I/ligase state for that
  extended region the same structural way it already reconstructs the
  first pass — no tween, no replay, position-derived only.
- If `nucleotide_original_x[]` grows, every existing consumer that assumes
  a fixed array length at scrub time needs an explicit audit — this is
  exactly the "scrub must resync every variable the live trigger depends
  on, not just what's rendered" trap STATUS.md already warns about, and a
  growing array is a new, larger version of that same trap.

---

## Gating

Builds on the existing mode-gate/toggle-gate machinery rather than
introducing a new pattern:

- Requires `topology_mode == LINEAR` (already enforced for
  `lagging_gap_enabled` via `ComplexityManager.is_enabled()`).
- Requires `lagging_gap_enabled` — telomerase only makes sense once there's
  a gap to mitigate.
- Should probably **require `primase_enabled`** as a hard dependency, not
  just the current soft relationship — per the primase-off limitation
  already flagged when the gap itself shipped: with no primer, there is no
  gap, and with no gap, telomerase extending the template has nothing to
  visibly shorten. Whether this becomes an actual `requires` edge in
  `ComplexityManager` (greying out the telomerase checkbox until primase is
  on, same treatment topology_mode already gives it) is an open decision
  for the UI pass, not resolved here.
- **Force-enables `shelterin_enabled`** once shelterin exists — see
  "Overhang protection" below. Same bridge-toggle direction as
  `set_pol1_enabled()`'s existing force-enable of `primase_enabled`/
  `ligase_enabled`: telomerase turns shelterin on, shelterin turning off
  does not turn telomerase off.

---

## Overhang protection: SSB and shelterin, built separately

**Decision:** these are not the same toggle wearing two names — they're two
different proteins, built in two separate passes, for two different reasons.

- **SSB ships first, entirely on its own**, scoped as general Stage 2
  elongation furniture per COMPLEXITY_MODEL.md's existing registry entry
  (`requires: helicase`, no telomere involvement at all). It coats whatever
  ssDNA is exposed behind the helicase during ordinary fork progression,
  the same everywhere along the strand. This is its own design/
  implementation session, independent of telomerase, and should land (or at
  least be scoped) before telomerase's own work resumes.
- **Shelterin ships later, specifically for telomerase.** Not yet in
  COMPLEXITY_MODEL.md's Toggle Registry at all — will need to be added
  there (Stage 2 or a new "Stage 4 — Telomere maintenance" grouping, TBD)
  as part of that future pass, alongside its own visual (a capping
  structure at the 3' overhang, distinct from both SSB's coating and
  primase's primers).
- **The cascade telomerase actually drives is shelterin, not SSB** — once
  shelterin exists, `ComplexityManager` gets a new bridge-toggle case
  mirroring `set_pol1_enabled()`'s existing pattern exactly: turning
  telomerase on force-enables `shelterin_enabled`, the same direction-only
  dependency `pol1_enabled` already has on `primase_enabled`/
  `ligase_enabled` today.
- Until shelterin exists, telomerase's overhang simply renders unprotected
  (no cap, matching what the sim shows today) — not a regression, just the
  honest state of "the dependency isn't built yet," same as any other
  toggle-gated feature waiting on a prerequisite.

---

## Integration points (files likely touched)

- `replication_manager.gd` — by far the largest share of the work: new
  telomerase state machine, template-strand growth, second-pass
  primase/Pol III/Pol I/ligase invocation, scrub reconstruction.
- `simulation.gd` — `num_nucleotide_slots` / `nucleotide_original_x[]`
  growth (or a documented alternative), if the template-growth approach
  requires it.
- `ThemeManager` (`theme_manager.gd`) — new export group for telomerase's
  body/RNA-loop visuals, translocation timing, repeat count.
- `ZoomDesign.md`'s frame-provider system — any zoom target keyed to
  original sequence length needs to know about telomerase-added bases if
  the strand visually extends past its original bounds.
- `PlayerUI`/`SequenceLabel` — same concern as above, windowed sequence
  label may need to account for a strand that grew after load.
- `ComplexitySetupPopup` — the primase-hard-dependency gating decision
  above, if adopted.

---

## Open items (not yet resolved)

- Exact telomerase body shape and RNA-loop visual treatment.
- Whether `nucleotide_original_x[]` actually grows, or whether
  telomerase-added bases are represented some other way that avoids
  touching every fixed-length-array consumer in the codebase — this is the
  single biggest architectural fork in this whole design and should be
  settled first, before any visual work starts.
- Number of translocation cycles per telomere-maintenance event, and
  whether it's fixed or tunable.
- How much of the newly-extended template the second-pass lagging-strand
  machinery actually fills back in — full minus one primer's worth (mirrors
  the original gap exactly), or a smaller demonstrative amount.
- Whether the primase-hard-dependency gating change happens now or is
  deferred to the already-planned UI pass.
- **SSB (prerequisite, own session):** general Stage 2 elongation toggle,
  scope/build independent of telomerase — should land or at least be
  scoped before telomerase work resumes. See "Overhang protection" above.
- **Shelterin (telomerase-specific, later):** not yet in COMPLEXITY_MODEL.md's
  registry at all. Still open once its own pass starts: exact visual (capping
  structure vs. a coating treatment like SSB's), where it sits in the Toggle
  Registry's staging, and the precise moment in telomerase's own sequence
  (before/after/during translocation) it appears and binds.
