# Tus–Ter Termination — sketch
_Quick sketch, not a full design pass (compare TelomeraseDesign.md's depth —
this is intentionally lighter). Companion to COMPLEXITY_MODEL.md's Toggle
Registry (`termination_tus_ter`, circular-mode-only, currently `NEW`) and
STATUS.md's "Near term — Trombone loop complexity" roadmap entry. Captures
Henrique's concept, sourced from an earlier side-scrolling game project of
his, for how the two replisomes' meeting could read visually._

---

## Core idea

Circular bacterial DNA, still viewed from the side (same flat/side-view
convention as the rest of the scene — no face-on circular rendering, per
HelicaseDesign.md's already-settled rejection of that approach). The
"circularity" is implied, not drawn as a literal loop.

Two replisomes travel the strand from opposite directions — one left-to-
right (the one that exists today), one right-to-left (new). As the
existing left-to-right replisome approaches the point where, today, it
would just leave a dangling last RNA primer and stop, it instead **meets
the second replisome** coming from the other side. That meeting point is
where termination actually happens — Tus–Ter, in the real biology, is what
traps the forks at a defined spot rather than letting them collide
anywhere.

This directly resolves the "last primer never removed" question for
circular topology, but not via a stand-in hack — via the actual mechanism:
the fragment that today has no "next fragment" to trigger its primer
removal instead meets fragments arriving from the *other* replisome, which
supplies that missing "next fragment closes" event for real.

---

## Explicitly deferred (post-proposta-simplificada)

The full **bidirectional-replication-bubble** picture — a single origin
opening into two forks that travel in opposite directions from the same
starting point, each with its own leading/lagging strand — is **not** part
of this sketch's scope. That's the complete, biologically accurate version
of how bacterial replication actually starts, but it's a substantially
larger feature (a second full replisome, mirrored strand roles, origin
visual, bubble geometry) than what's needed to resolve the immediate
termination question. Flagged explicitly as future work, after the
upcoming FAPESP proposta simplificada.

For Tus–Ter's own sake, the two replisomes meeting don't need to have
started from a shared visible origin in this pass — they can simply be
posed as already-approaching from both ends of the visible sequence,
independent of how they got there.

---

## Open questions (unresolved — this is a sketch)

- Does the second (right-to-left) replisome mirror the existing one's
  leading/lagging strand assignment, or is the geometry different for a
  fork traveling the opposite direction along the same template
  orientation?
- What does "meeting" actually trigger, mechanically? A literal fragment
  closing from the second replisome's side, satisfying the first
  replisome's terminal fragment's `_lagging_close_fragment()`-style
  trigger — or a distinct Tus–Ter-specific event?
- Visual treatment of the Tus protein / Ter sites themselves — real Tus–Ter
  is a directional trap (forks can enter but not exit past a Ter site
  going the wrong way), not just "two replisomes happen to collide." Worth
  deciding whether that directionality is shown explicitly or simplified
  away for this tier.
- Where the meeting point sits relative to the loaded sequence — fixed
  Ter-site position, sequence midpoint, or wherever the two replisomes
  happen to meet based on independent pacing?
- Relationship to the trombone loop tier (STATUS.md's next roadmap item
  after telomerase) — Tus–Ter and the trombone loop are both circular-
  topology, single-origin mechanics per COMPLEXITY_MODEL.md; likely share
  underlying replisome-coupling architecture, not yet mapped out here.

---

## Gating

Per COMPLEXITY_MODEL.md's existing registry entry: `termination_tus_ter`,
requires `helicase`, **circular mode only** — mirrors `lagging_gap_enabled`'s
linear-only gating exactly, just the opposite topology.
