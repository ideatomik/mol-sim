# Topoisomerase Visual Design — future complexity tier (pre-implementation)
_Design discussion, not yet implemented. Speculative future tier, well above
base complexity. Companion to DESIGN.md's Complexity System and to
HelicaseDesign.md, which established the z-order + periodic-crossing pattern
this reuses._

---

## Context

Real DNA is a double helix. MolSim's established didactic convention is to
render it as flat, parallel ribbons instead — deliberately, so viewers can
track base-pairing and synthesis without the visual noise of a twisting
strand. This convention applies to both the replicated region (behind the
fork) and, currently, the unreplicated region ahead of the fork, which is
rendered as a single flat `TemplateStrandOriginalTrack` line — not yet two
strands at all.

Topoisomerase's biological role is relieving torsional strain **ahead of the
fork**, caused by the helicase's own unwinding motion. Depicting that strain
means depicting a twisting double helix in the pre-fork region specifically
— which is the one part of the scene where the flat-ribbon convention would
need to be broken.

---

## Why this is gated behind a future toggle, not built now

A twisting pre-fork region directly fights the flat-ribbon model's own
purpose: reducing visual complexity so replication mechanics stay legible.
Adding torsional twist at base complexity would be adding visual noise to
solve a problem base complexity doesn't have yet — torsional strain isn't a
concept the base tier is trying to teach.

This is the same reasoning already applied to `lagging_gap_enabled` and
`ligase_enabled`: build (or in this case, design) the concept, but gate it
behind a toggle reserved for a tier sophisticated enough to need it, rather
than force it into the base didactic view. Proposed toggle name:
`topoisomerase_enabled`, default `false`, expected to sit at or above the
full replisome tier in the complexity ladder — torsional strain is a more
advanced concept than "DNA unzips and copies itself."

At base complexity (and for the foreseeable near-term tiers), the pre-fork
region stays exactly as it is today: a single flat line.

---

## Visual mechanic (proposed, once the tier is reached)

Reuses the periodic z-order swap pattern already established for the
helicase ring's blob rotation (see HelicaseDesign.md) — same illusion
family, applied along a strand's length instead of around a rotating ring:

- **Two strands, not one**: the pre-fork region would need to become a
  genuine twisted pair rather than the current single flat line — a bigger
  structural change than just adding a visual effect on top of what exists.
- **Periodic z-order swap**: at fixed intervals along the pre-fork strand
  (either a fixed slot count or fixed pixel distance), flip which of the two
  strands draws on top — the same "barber pole" crossing illusion used for
  any twisted-pair visual.
- **Convergence at the crossing**: strand separation (vertical gap between
  the two pre-fork strands) oscillates via something like `abs(cos(θ))`
  along the strand's horizontal length, with z-order flipping exactly at
  the zero-crossings. Without the convergence, a hard z-flip with no
  positional easing would look like the strands teleporting past each other
  rather than twisting — this is the same principle that made the helicase
  blob's width/height breathing necessary rather than a plain z-flip alone.
- **Resolution at the fork**: the twist needs to visually untwist into the
  flat, separated ribbons right at the unzipping point, where the pre-fork
  twisted region meets the post-fork flat region. Post-fork rendering is
  unchanged.

---

## Open items (not yet resolved)

- **Simpler alternative not yet ruled out**: instead of a fully twisting
  two-strand pre-fork region, periodic crossing hatch-marks drawn *on* the
  existing single flat line, implying "this part is still wound" without
  structurally changing the pre-fork region into two strands. Lighter-weight,
  worth weighing against the full twist once this tier is actually reached.
- **Enzyme depiction**: whether topoisomerase itself is shown as a distinct
  enzyme object (visually consistent with the helicase ring / polymerase
  treatment) acting at specific crossing points as the fork advances, or
  rendered as more of an ambient effect on the pre-fork region with the
  enzyme implied rather than explicitly drawn.
- **Exact tier placement**: confirmed to be "well above base complexity,"
  but not yet pinned to a specific rung on the complexity ladder relative to
  the full replisome, primase, or ligase tiers.
- **Structural cost**: pre-fork region currently has no concept of "two
  strands" at all in the data model, unlike the post-fork region — this
  tier would need that structural addition before any twist rendering could
  sit on top of it, independent of which visual mechanic (full twist vs.
  hatch-marks) is chosen.
