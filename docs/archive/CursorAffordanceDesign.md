# Cursor Affordance System — Lattice Note

## Nucleation (seed problem)
Recording trial shots surfaced that the default OS cursor is too small to
track on video, especially during scrub interactions. Fixing that raised a
broader, genuinely reusable need: Zymulador has interactable objects with
different interaction types (drag helicase/polymerase, inspect a labeled
molecule to open an info panel), and point-and-click game conventions already
give players/users a vocabulary for this — grab hand for draggable, magnifying
lens for inspectable. This should be built as shared infrastructure, not
wired per-node, since info panels (upcoming) and Azteca's live-emphasis
tooling will need the same hover-affordance behavior.

## Lattice (design)

### Affordance types (generic, extensible)
```gdscript
enum CursorAffordance {
    DEFAULT,      # idle / non-interactable — fallback, not a placeholder
    DRAGGABLE,    # helicase, polymerase, any object the user can grab and move
    INSPECTABLE,  # labeled molecules with an info panel (uracil, etc.)
    SCRUB,        # PROPOSED, not decided — player UI progress bar / timeline
                  # handle. See "PROPOSAL for Claude Code review" below —
                  # this may end up folded into DRAGGABLE instead.
}
```
`DEFAULT` is the generic fallback for anything that doesn't register an
affordance — it is not a "temporary" state; per the self-paired-template
precedent, generic/default states are first-class, not lower-priority.
Future affordance types (e.g. a scrub-jump target, Azteca's selective-label
targets) extend this enum rather than bypassing the manager.

### CursorAffordanceManager (autoload/singleton)
Single scrub-safe, stateless-per-frame manager. Public API:

```gdscript
# Called once by an interactable node, typically in _ready()
func register(node: Node, affordance: CursorAffordance) -> void

# Optional, for nodes that are conditionally interactable
# (e.g. only draggable once a certain sim phase is reached)
func set_affordance(node: Node, affordance: CursorAffordance) -> void
func unregister(node: Node) -> void
```

Internally, the manager connects to each registered node's `mouse_entered` /
`mouse_exited` signals (nodes must be `Area2D`/`Control`-derived or expose
equivalent signals) and swaps the active cursor via
`Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, hotspot)`.

This follows "inject, don't lookup" — interactable nodes register themselves
with the manager (injected reference or autoload access), rather than the
manager scanning the scene tree for interactables.

### Cursor asset table — SUPERSEDED, now sourced from Kenney's Cursor Pack

Henrique sourced Kenney's free CC0 Cursor Pack (kenney.nl/assets/cursor-pack)
and selected the actual shipping assets from it, replacing the placeholder
SVGs drafted earlier in this note. All files are natively 64×64 PNG — no
rescaling needed. Hotspots below were measured directly from each asset's
non-transparent bounding box.

| Affordance                  | Asset                            | Hotspot (px, 64×64 native) | Notes |
|------------------------------|-----------------------------------|------------------------------|-------|
| DEFAULT                      | `pointer_c.png`                   | (4, 4) — top-left tip vertex | Straight left edge + flat top corner, standard arrow-style hotspot placement |
| DRAGGABLE (hover, not yet grabbed) | `hand_open.png`             | (31, 31) — center of palm    | |
| DRAGGABLE (actively dragging)      | `hand_closed.png`           | (31, 31) — center of palm    | New third sub-state — see below |
| SCRUB / TIMELINE (current horizontal timeline, today's shoot) | `tracking_horizontal.png` | (32, 32) — center | Only tracking asset wired today — see correction below |
| INSPECTABLE                  | *(none shipped yet)*              | —                             | Correctly deferred — no info panel feature to attach it to yet |

All Kenney assets share one flat black-outline-on-transparent style, which
is visually consistent enough to read as "one cursor system" across states
without needing the navy/orange accent treatment from the original draft
assets.

### Correction: `_up`/`_down`/`tracking_vertical*` are NOT for today's timeline
Original draft of this table guessed `tracking_horizontal_up`/`_down` were
directional feedback for the current horizontal scrub track. Henrique
clarified (2026-08-17) that's wrong — those, along with the entire
`tracking_vertical` family, were selected with the **future vertical
progress bar** in mind, for whenever vertical mode
(`VerticalModeDesign.md`) is taken seriously. None of them apply to today's
horizontal timeline.

**Reserved / sleeping assets — present in the folder, not wired to anything:**
- `tracking_horizontal_up.png`
- `tracking_horizontal_down.png`
- `tracking_vertical.png`
- `tracking_vertical_left.png`
- `tracking_vertical_right.png`

Decision: leave them sleeping rather than wiring or discarding them. They
cost nothing sitting unused in the asset folder, and pulling them back out
of Kenney's pack later would just be redoing work already done today. When
`VerticalModeDesign.md` is actually written, that doc should claim these
assets explicitly (with its own hotspot/affordance mapping) rather than this
note quietly deciding vertical-mode cursor behavior in passing. Only
`tracking_horizontal.png` (the plain, non-directional icon) is in scope for
today's SCRUB affordance.

### DRAGGABLE now has three sub-states, not two
The original Lattice draft only specified hover (open hand). Having both
`hand_open` and `hand_closed` available upgrades this to the three-state
pattern discussed but not yet designed:
- idle/DEFAULT → `pointer_c`
- hover over draggable, not yet grabbed → `hand_open`
- actively dragging (mouse button down, drag in progress) → `hand_closed`

This requires the manager to also listen for the drag-start/drag-end
input events on registered DRAGGABLE nodes (not just `mouse_entered` /
`mouse_exited`), since the closed-hand state is driven by button state, not
hover state alone.

### PROPOSAL for Claude Code review: SCRUB as a fourth affordance type

**This section is a proposal, not a decision.** Flagging for Claude Code's
implementation-level judgment before it's settled, since the tradeoff is
mostly about what's cheapest and cleanest against the actual codebase, which
Claude Code has more direct visibility into than this note does.

**The case for adding `CursorAffordance.SCRUB`:**
- The player UI progress bar isn't "grabbing an object and moving it" the
  way helicase/polymerase drag is — it's manipulating simulation time
  directly. Conceptually a different action, even if the input mechanics
  (mouse down, drag, mouse up) look similar at the code level.
- Reusing DRAGGABLE for both would mean the enum value stops describing
  "what kind of thing this is" and starts describing "what input pattern
  this uses" — those aren't guaranteed to stay aligned as more affordances
  get added later (e.g., Azteca's selective-label filtering might also be
  drag-shaped but conceptually distinct again).
- `tracking_horizontal.png` is a visually distinct asset from
  `hand_open`/`hand_closed` — the asset table already implies two different
  affordances even before the enum catches up.

**The case against (reasons to just reuse DRAGGABLE):**
- If the manager's registration API is generic enough (`register(node,
  affordance, cursor_texture_set)`), the enum value itself might not need
  to change — DRAGGABLE could just carry a different texture set per node
  without a new enum case, if that's a smaller diff against however the
  manager ends up structured.
- Fewer enum cases is fewer places for future affordances to need to decide
  "is this DRAGGABLE-shaped or its own thing," which is exactly the kind of
  judgment call that's easy to get inconsistent over time without a very
  clear rule.

**Ask for Claude Code:** given how the manager and interactable nodes are
actually structured today, does a fourth `SCRUB` enum case, or a
same-DRAGGABLE-different-texture-set approach, produce the cleaner diff?
Either is fine design-wise — this is an implementation call, not a
philosophical one.

### Third state note (per Henrique, 2026-08-17)
DEFAULT is intentionally generic now — expected to be reused across future
simulations (Krebs, translation, etc.) and higher-complexity DNA replication
views, not scoped narrowly to today's shoot.

## Growth (implementation) — NOT YET APPROVED
Do not implement until Henrique confirms:
1. Which nodes register as DRAGGABLE today (helicase, polymerase — confirm
   exact node paths/scripts)
2. Whether INSPECTABLE registration is scoped now (uracil etc.) or deferred
   until the info panel feature itself lands — currently deferred, no asset
   shipped yet
3. Final asset sizing after on-monitor test (Kenney assets are 64×64 native;
   confirm this reads at recording/projector distance before Growth)
4. **Claude Code's read on the SCRUB proposal above** — fourth enum case vs.
   folding into DRAGGABLE with a different texture set
5. `hand_closed` requires wiring drag-start/drag-end input state, not just
   hover — confirm this is in scope for today's pass or deferred alongside
   the rest of the drag-interaction implementation
6. `tracking_horizontal_up/down` and the whole `tracking_vertical` family
   stay unregistered — reserved for `VerticalModeDesign.md`, not today's scope

## As-Built / Open Questions
- Multi-touch/pen input handling not addressed — flagged as a future
  consideration for classroom/projector use, not blocking this pass.
- Whether `register()` takes an `Area2D` directly or a signal-emitting
  wrapper is left to Claude Code's judgment during Growth, consistent with
  existing scene architecture patterns — should be confirmed against
  `molsim-gdscript` SKILL.md conventions before implementation.
- **2026-08-17 revision**: original draft used custom-drawn SVG cursor
  assets (navy/orange, purpose-built for this doc). Henrique replaced these
  with selections from Kenney's free CC0 Cursor Pack
  (kenney.nl/assets/cursor-pack) before shipping. Rejected the custom set
  not for quality reasons but because Kenney's pack ships a matched hand
  open/closed pair and dedicated scrub-track icons the draft set didn't
  have — better affordance coverage for less effort. Custom SVGs are kept
  in the same output folder in case a branded cursor pass is wanted later,
  but they are not the shipping asset — Kenney filenames in the table above
  are authoritative.
