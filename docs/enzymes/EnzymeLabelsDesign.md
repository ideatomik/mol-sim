# Enzyme Labels & Localization — Design (implemented)
_Implemented as part of v71: `EnzymeLabel.tscn`/`enzyme_label.gd`, `locale_manager.gd`,
and `enzyme_labels.csv`, wired into `helicase_ring.gd` and `polymerase_clamp.gd`.
Since extended to `ligase.gd`, `primase_blip.gd`, and `pol1.gd` as those
enzymes shipped — see the Complex-tier addendum immediately after the
original As-Built below. Retained as the design rationale and as a
reference pattern for future localized/labeled content — the body below is
the original pre-implementation discussion; see **As-Built** immediately
below for where the shipped version diverged. Companion to DESIGN.md's v71
roadmap item and to HelicaseDesign.md / PolymeraseDesign.md, whose As-Built
sections both listed "text labels" as their one remaining open item — this
closes that out for both._

---

## As-Built

What actually shipped, and where it diverged from the design below. The
design body is kept intact as reference; this note is the source of truth
for the current implementation.

- **A real scene object, not a bare `Label`.** The design below assumed a
  plain `Label` with styling injected via `set_style()`. Mid-implementation,
  Henrique proposed a stronger version instead: `EnzymeLabel.tscn` — a
  `PanelContainer` (flat rectangle, half-opacity `StyleBoxFlat` background)
  with a BBCode-enabled `RichTextLabel` child — instantiated as a real
  addressable node rather than assembled inline. Motivation: a future
  zoom-in/out mechanic will want to counter-scale these labels to hold
  constant screen size, and a self-contained scene/class object is the
  natural place to hang that behavior later without touching
  `helicase_ring.gd` or `polymerase_clamp.gd` again.
- **`set_anchor_pos()`, not `set_anchor()`.** `Control` already defines a
  built-in `set_anchor(side, anchor, keep_offset, push_opposite_anchor)` with
  an incompatible signature. The design below used `set_anchor()`; the
  shipped name avoids shadowing the engine method.
- **Centering via `pivot_offset`, exactly as designed, plus the mirror
  interaction worked out further than originally specified**: `pivot_offset`
  is kept at `size * 0.5` and `position = anchor - pivot_offset`, so the
  label's own center — not its top-left — stays pinned to the anchor
  regardless of text length (a locale change that changes string length
  re-centers for free via the `resized` signal). `set_mirror(mirror)` sets
  local `scale.y = -1` to cancel the parent clamp's own mirror; because scale
  is applied around `pivot_offset`, the anchor point never moves when
  mirroring toggles — this composition works cleanly and needed no
  special-casing beyond what was planned.
- **A real tree-lifecycle bug, not anticipated by the design**: `@onready var
  _rich_text: RichTextLabel = $RichTextLabel` broke in practice, because
  `PolymeraseClamp._build()` (which calls `EnzymeLabel.set_key()`
  immediately after instantiating it) can run before `PolymerClamp` itself
  is in a *live* `SceneTree` — it's still mid-assembly during
  `simulation.gd`'s own `_ready()`. `@onready`'s assignment waits for
  `_ready()`, which waits for live-tree entry, so `_rich_text` was still
  `null` when `set_key()` ran. Fixed by replacing `@onready` with a lazy
  `_ensure_rich_text()` guard (`get_node()`, which works on the local
  subtree immediately after `instantiate()` regardless of live-tree status)
  called at the top of every public method. Worth remembering for any future
  scene-based component spawned by a script that isn't itself live yet —
  the same class of "looks fine until the instantiation order changes" trap
  this project's Pinned Issues already tracks for other subsystems.
- **`helicase_ring.gd` keeps its own local `@export` label params
  (`label_enabled`, `label_key`, `label_margin`, `label_font_size`,
  `label_text_color`, `label_panel_color`, `label_z`), not a ThemeManager
  group.** The design below assumed a single unified ThemeManager "Enzyme
  Labels" group for both enzymes. Ground truth showed `helicase_ring.gd`
  already keeps all of its *other* params as local exports rather than
  reading ThemeManager — so the label config follows suit there, for
  consistency with that file's existing convention.
- **`polymerase_clamp.gd`, conversely, reads its label config live from
  ThemeManager every frame** (`enzyme_labels_enabled`,
  `polymerase_label_margin`, `label_font_size`, `label_color`,
  `label_panel_color`, `label_z`) — matching *that* file's existing
  ThemeManager-driven pattern for every other geometry/colour value. The
  result is a deliberate split, not an inconsistency: each enzyme's label
  config follows whichever pattern that enzyme's own script already used.
  `helicase_label_margin`, `primase_label_margin`, `ligase_label_margin` from
  the design below were **not** added to ThemeManager — the ring doesn't read
  ThemeManager at all, and primase/ligase don't have owning scripts yet to
  establish which pattern they'll follow.
- **Label position is static, independent of the enzyme's own motion, exactly
  as designed** — confirmed in practice, not just planned: the helicase
  label's offset depends on `ring_radius`/`max_blob_height` but not `roll`
  (recomputed every `_apply()` so Inspector tuning still moves it, but never
  breathes with the barrel-roll), and the polymerase label's offset uses the
  rest-state `half_down`, not the pump-grown value, so it doesn't breathe
  with `set_pump(t)` either.
- **Live language switching needed zero extra plumbing, as hoped** —
  confirmed empirically, not just theorized: `RichTextLabel.text` genuinely
  auto-translates and self-refreshes via Godot's own `Control` mechanism the
  moment `TranslationServer.set_locale()` is called. `refresh_translation()`
  was kept as a manual escape hatch but was never actually needed.
- **`LocaleManager` shipped close to spec**: `default_locale`, `set_locale()`,
  `get_locale()`, `locale_changed` signal, scene `Node` with `%LocaleManager`
  unique name — plus a `[LOCALE]` debug print (per this project's
  debug-prints-stay convention) and a **temporary** debug keybind (`L` cycles
  `en → pt_BR → es`) for manual QA, explicitly flagged for removal once
  switching is confirmed stable across a real play session.
- **Two real setup gotchas hit during bring-up, worth recording as pinned
  traps**:
  1. Importing the CSV in the FileSystem dock is **not** sufficient by
     itself — it must also be explicitly added under **Project Settings →
     Localization → Translations**, which is what actually writes
     `project.godot`'s `[internationalization]` section
     (`locale/translations=PackedStringArray(...)`). Without this step,
     everything runs clean with no errors, `TranslationServer.set_locale()`
     succeeds, and `tr()` just silently echoes the raw key back — a "looks
     correct, does nothing" failure mode with no error to point at it.
  2. `unique_name_in_owner = true` must be explicitly toggled for the
     `LocaleManager` node ("Access as Unique Name" in the Scene dock) — it
     is not implied by naming the node `LocaleManager`. Missing this
     produces the same silent-failure symptom as (1): no crash, no error,
     `%LocaleManager` just resolves to nothing anywhere in the project.
- **Complexity-tier hook for enzyme *naming*, not originally scoped in the
  design below at all**: base-tier labels now show the generic/simple name
  (`ENZYME_HELICASE` = "Helicase", `ENZYME_POLYMERASE` = "Polymerase"), with
  a `_FULL` variant reserved but unused (`ENZYME_HELICASE_FULL` = "DnaB
  Helicase", `ENZYME_POLYMERASE_FULL` = "DNA Polymerase III"). This is the
  same principle COMPLEXITY_MODEL.md already establishes for exact enzyme
  identity as a **divergent specific** — bacterial DnaB vs. eukaryotic CMG,
  Pol III vs. Pol ε/δ — just applied to naming instead of visuals.
  _Correction — `ComplexityManager` now exists, and the hook that landed
  wasn't quite this prediction: `polymerase_clamp.gd`'s label swaps to a
  DIFFERENT short key (`ENZYME_POL3`, "Pol III") when `pol1_enabled`, not to
  `ENZYME_POLYMERASE_FULL`. The `_FULL` keys themselves are still reserved
  and still unused by any code path — see the Complex-tier addendum below
  for what actually shipped and why a same-length swap turned out to fit
  the real need (disambiguating Pol I from Pol III) better than revealing
  a longer scientific name would have._
- **Word-order inconsistency between the two `_FULL` translations, flagged
  but not resolved**: `ENZYME_POLYMERASE_FULL` keeps English word order in
  pt_BR/es ("DNA Polimerase III" / "ADN Polimerasa III"), while
  `ENZYME_HELICASE_FULL` reorders to noun-first ("Helicase DnaB" / "Helicasa
  DnaB"). Both are defensible depending on how each term is actually written
  in Portuguese/Spanish biology texts; this hasn't had a native-speaker
  pass yet.
- **UI text localization (PlayerUI / SequenceLoaderPopup) is a separate,
  not-yet-finished thread**, despite living in the same CSV file format.
  `UI_CHAR_COUNT` (the `"%d / %d caracteres"` format string in
  `sequence_loader_popup.gd`) has been identified as needing a key, but the
  full string inventory is still blocked on `DnaSequenceResource.gd` (which
  defines the preset names shown in the sequence dropdown) and the two
  `.tscn` scene files (button labels, dialog titles) — none of which have
  been uploaded yet. **Not** part of what shipped in this pass.

---

## As-Built — Complex-tier addendum (ligase, primase, Pol I)

Everything above is the original v71 pass (helicase + polymerase clamp
only). This covers what shipped later, once `ligase.gd`, `primase_blip.gd`,
and `pol1.gd` existed and needed the same label treatment — see
OkazakiMaturationDesign.md for those enzymes' own build history; this
section is specifically about their *labeling*.

- **All three followed `polymerase_clamp.gd`'s pattern, not
  `helicase_ring.gd`'s.** The original As-Built above framed this as an
  open question each enzyme would resolve based on "whichever pattern that
  enzyme's own script already used" — in practice, all three (ligase,
  primase, Pol I) already read every other geometry/color parameter live
  from ThemeManager, so their labels followed suit with no real decision
  needed: `enzyme_labels_enabled`, `label_font_size`, `label_color`,
  `label_panel_color`, `label_z` are shared fields (still living in the
  "Polymerase Clamp" ThemeManager group, despite the name — see note below);
  each enzyme keeps only its own margin as a distinct field
  (`ligase_label_margin`, `primase_blip_label_margin`, `pol1_label_margin`),
  same shape `polymerase_label_margin` already established.
- **The tier-conditional key swap — a new pattern, not predicted by the
  original `_FULL`-key framing above.** `polymerase_clamp.gd`'s label key
  is now chosen live in `_apply()` (moved out of the one-time `_build()`,
  since it's no longer a fixed key): plain `"ENZYME_POLYMERASE"` at every
  tier except Complex, where it switches to `"ENZYME_POL3"` — a same-length
  scientific-vs-generic swap, not a reveal-the-longer-name swap. Reasoning:
  the ambiguity this needed to solve was specifically "which polymerase is
  this" once Pol I and Pol III share the screen for the first time — a
  short, precise name solves that; a longer name (`_FULL`) would have, but
  wasn't needed to. `ENZYME_POL1` needs no equivalent tiering — Pol I only
  exists at all when `pol1_enabled` is true (true-absence lifecycle, see
  SKILL.md), so there's no base-tier label to fall back to.
- **`pol1.gd`'s two-lobe shape needed one label-specific adjustment beyond
  the single-blob enzymes**: the anchor point for `set_anchor_pos()` had to
  account for the taller vertical extent of two stacked lobes rather than
  one, recomputed twice across two visual-tuning passes as the lobe
  layout itself changed (see OkazakiMaturationDesign.md's Pol I
  Implementation Status for the layout history) — a reminder that a
  multi-piece enzyme's label anchor needs revisiting any time its own
  silhouette changes, not just set once at spawn.

---

## As-Built — Vertical mode + topology-conditional labels (v77)

_Two unrelated passes that both landed on this file's components in v77: glyph
counter-rotation for vertical recording (see `VerticalModeDesign.md`), and the
topology-conditional polymerase name split. The latter **answers this document's
own open item** — "wait until `topology_mode` itself exists" — which expired when
topology_mode shipped with the telomerase tier._

### `set_counter_rotation()` — and why EnzymeLabel owns the mirror sign

Sibling to the existing `set_mirror()`. Both compose around `pivot_offset`,
already maintained at `size * 0.5`, so the anchor never moves — the same property
that made `set_mirror()` safe without special-casing.

The leading clamp carries `scale.y = -1`, and reflection conjugates rotation
(`S * R(t) * S = R(-t)`), so a local `t` under a mirrored parent renders as world
`-t`. **The sign lives in `_apply_rotation()` here, not in the five callers.**
Every enzyme passes `ZoomManager.get_label_counter_rotation()` verbatim and none
knows the mirror interaction exists — five call sites cannot disagree about a
sign none of them holds. Order-independent: `set_mirror()` and
`set_counter_rotation()` compose either way.

If the sign were ever wrong, the symptom is diagnostic: every enzyme label
upright EXCEPT the leading polymerase's, which reads upside down.

**Margins will need retuning per orientation.** In vertical, labels stick out
along the CROSS axis — the 1080px budget, not the 1920px one — and that retune
happens in two Inspector locations, per the deliberate split recorded above
(`helicase_ring.gd` keeps local `@export`s; `polymerase_clamp.gd` reads
ThemeManager). "Pol epsilon" (11 chars vs "Pol III"'s 7) is now the longest
enzyme name in the project, in the orientation with least room for it.

### Scope: which renames are honest

OkazakiMaturationDesign.md already decided **label-only for primase and primer
removal** — both keep bacterial mechanics under either domain, only the name
swaps. This addendum **narrows that decision**, on the strength of that doc's
own divergence-depth table.

The chimera principle says the label *is* the mitigation for a divergent
specific. That cuts both ways: renaming is truthful exactly where the mechanism
doesn't diverge, and actively teaches a falsehood where it does.

| Enzyme | Rename shape | Ship it? |
| --- | --- | --- |
| Pol III → **Pol ε / Pol δ** | one key splits into two | **Yes.** Processive, clamp-bound, template-directed synthesis is genuinely what both do. |
| Ligase → **Ligase I** | pure rename | **Yes.** The real divergence is cofactor (NAD⁺/ATP), already scoped to `atp_activation_enabled`. |
| Helicase → **CMG** | rename | **Deferred.** Same ring mechanism, but DnaB encircles the *lagging* template and CMG the *leading* one — COMPLEXITY_MODEL.md already lists "which strand the helicase encircles" as a divergent specific. Renaming without re-siting the ring asserts something false about CMG. |
| Primase → **Pol α-primase** | rename | **No.** Pol α makes an RNA–**DNA hybrid** primer and hands off to Pol δ. Labelling a pure-RNA blip "Pol α" teaches a falsehood about Pol α. |
| Pol I → **FEN1** | rename | **No.** FEN1 doesn't nick-translate; it cuts flaps. Different mechanism entirely. |

**The inversion worth naming**: for the bottom three rows, label-only mode is
*worse* than no rename. A student seeing "FEN1" perform nick translation learns
something false about FEN1, and the label is the thing doing the lying — the
exact failure the labeled-chimera principle exists to prevent, arrived at from
the opposite direction. A visible **bacterial Pol I sitting in a eukaryotic
fork is itself a labeled seam**; renaming it to FEN1 is what hides the seam.

So: ship the top two, leave Pol I / primase / helicase bacterial in eukaryotic
mode, and state the divergence in `ENZYME_POL1_FULL` — already reserved, still
unread by any code path, and exactly the right place for "eukaryotes do this
with FEN1 + RNase H2 instead."

---

### The key-selection matrix

Three inputs: `topology_mode` × `pol1_enabled` × leading/lagging. Eight cells,
**four keys**.

| topology | `pol1_enabled` | strand | key |
| --- | --- | --- | --- |
| CIRCULAR | false | leading | `ENZYME_POLYMERASE` |
| CIRCULAR | false | lagging | `ENZYME_POLYMERASE` |
| CIRCULAR | true | leading | `ENZYME_POL3` |
| CIRCULAR | true | lagging | `ENZYME_POL3` |
| LINEAR | false | leading | `ENZYME_POL_EPSILON` |
| LINEAR | false | lagging | `ENZYME_POL_DELTA` |
| LINEAR | true | leading | `ENZYME_POL_EPSILON` |
| LINEAR | true | lagging | `ENZYME_POL_DELTA` |

### Each mode ignores exactly one axis — and it's a different one

This is the structure that makes the implementation obviously correct rather
than merely tested:

- **CIRCULAR ignores strand, honours `pol1_enabled`.** In E. coli, leading and
  lagging are the same protein — there is nothing for strand to select between.
- **LINEAR ignores `pol1_enabled`, honours strand.** `ENZYME_POL3` exists for
  one reason: to disambiguate a *generic* name once Pol I shares the screen
  ("which polymerase is this?"). Pol ε and Pol δ are already specific. There is
  no ambiguity left for `pol1_enabled` to resolve.

The two axes swap roles across the mode boundary. Neither is redundant; each is
load-bearing in exactly one mode.

```gdscript
## CIRCULAR: strand is irrelevant (one enzyme, both strands), pol1_enabled
## disambiguates a generic name. LINEAR: pol1_enabled is irrelevant (the Greek
## names are already unambiguous), strand selects a genuinely different enzyme.
func _polymerase_label_key() -> String:
	if _topology_is_linear():
		return "ENZYME_POL_EPSILON" if _is_leading else "ENZYME_POL_DELTA"
	return "ENZYME_POL3" if _pol1_enabled() else "ENZYME_POLYMERASE"
```

Chosen live in `_apply()`, extending the existing tier-conditional swap rather
than adding a second mechanism — `polymerase_clamp.gd` already moved key
selection out of `_build()` for exactly this reason when `ENZYME_POL3` shipped.

---

### The prerequisite: `_mirror` is not strand identity

**This is the one real blocker, and it is not about labels.**

`polymerase_clamp.gd` today knows only `_mirror`. Its own header states the
design:

> Shared shape, "same enzyme, mirrored/recolored per strand" treatment — no
> leading/lagging distinction.

That is a **bacterial claim**, and it is load-bearing. Eukaryotic mode is
precisely the thing that expires it: leading and lagging stop being the same
enzyme.

`_mirror` is already doing double duty as strand identity — `_apply()` reads it
to pick `tm.clamp_leading_back_color` vs `tm.clamp_lagging_back_color`. So the
conflation is shipped, not new. But those are *colours*; being wrong there is a
cosmetic bug. Being wrong about which enzyme this **is** teaches biology.

**Do not add an `is_leading` parameter alongside `mirror`.** Two bools that must
always agree is the same trap in a worse form — it creates a state where they
*can* disagree, and nothing catches it.

**Recommendation: rename the concept, don't duplicate it.**

```gdscript
func setup(sim: Node, is_leading: bool) -> void:   # was: mirror: bool
	_is_leading = is_leading
	...
	_label.set_mirror(_is_leading)   # leading -> therefore mirrored
```

One source of truth, named for the causal fact (leading) rather than its visual
consequence (mirrored). Both call sites already pass the right values —
`leading_clamp.setup(sim, true)` / `lagging_clamp.setup(sim, false)` — so this
is a **zero-behaviour-change rename**. `set_mirror()` on `EnzymeLabel` keeps its
name; mirroring is genuinely what that node does.

Update the header comment when this lands: the "no leading/lagging distinction"
line becomes true-in-CIRCULAR-only.

---

### CSV rows

Two rows. Append to `res://localization/enzyme_labels.csv`:

```
ENZYME_POL_EPSILON,Pol epsilon,Pol épsilon,Pol épsilon
ENZYME_POL_DELTA,Pol delta,Pol delta,Pol delta
```

pt_BR/es accent on "épsilon" is a first-pass guess, not a confirmed
native-speaker call — flag it alongside the `_FULL` review rather than
treating it as settled.

**Spelled out in Latin script (Pol epsilon / Pol delta), not the Greek glyphs
(ε/δ) — decided after drafting this addendum, for a reason specific to the
project's own accessibility rule.** `ε` and `δ` are both small, round,
lowercase glyphs; at label size, on a moving clamp, in a vertical video, on a
phone, they are close to indistinguishable — a one-glyph distinction carrying
the entire pedagogical payload of splitting the key (Pol ε is leading, Pol δ
is lagging). This is the same failure shape `EnzymeLabelsDesign.md`'s own RNA/
DNA rule already guards against: shape AND thickness distinguish RNA from DNA,
never color alone. Spelled out, the two names differ from the first letter and
survive small type, motion, and compression; a real cost is accepted knowingly
— every textbook and paper writes Pol δ/Pol ε, so this is a one-time
recognition step away from the literature, best closed later via the `_FULL`
keys if anything ever reads them.

This also changes the CSV shape. Spelled-out names are ordinary words, so
unlike `ENZYME_POL3`/`ENZYME_POL1` (Roman numerals, identical in all three
columns) these are the **first genuinely translatable enzyme rows** in the
file — "delta" lands identical across en/pt_BR/es by coincidence, "epsilon"
does not (pt_BR/es both want the accent: épsilon). Native-speaker confirmation
of the pt_BR/es spelling belongs on the same pending review pass
`EnzymeLabelsDesign.md` already flags for the `_FULL` word-order issue.

This also retires the Greek-glyph-coverage pre-flight this addendum originally
carried (confirming the default font renders `ε`/`δ` without falling back to
`.notdef`/tofu boxes) — moot once the CSV holds only Latin characters.

### Deliberately NOT reserving `_FULL` variants

Deviating from the established pattern, for a stated reason: three `_FULL` rows
already exist (`ENZYME_HELICASE_FULL`, `ENZYME_POLYMERASE_FULL`,
`ENZYME_POL1_FULL`), **none has a reader**, and all three are pending the
native-speaker word-order review this doc already flags as unresolved. Adding
two more unread, unreviewed rows compounds that debt rather than paying it.
Reserve `_FULL` when something reads one.

### A length consequence worth flagging now

"Pol epsilon" (11 characters) is markedly longer than "Pol III" (7) — the
longest enzyme name in the project, on the polymerase clamp, which is the
label `polymerase_label_margin` was tuned against. In vertical mode, enzyme
labels stick out along the CROSS axis (VerticalModeDesign.md Part 2b) — the
1080px budget, not the 1920px one — so this lands as the longest name in the
tightest available space. Re-check `polymerase_label_margin` in-engine once
these ship, in both orientations; don't assume the horizontal tuning carries
over.

---

### Open items this addendum does NOT resolve

- **`EukaryoticModeDesign.md` is the real scope**, and it is Okazaki-relay-
  sized: the Pol α → Pol δ handoff, the hybrid-primer visual, and FEN1 /
  RNase H2 / Dna2 flap-cutting replacing nick translation. OkazakiMaturation
  Design.md already flagged all three as "real future scope, not a rejected
  idea." This addendum is the label layer only.
- **The Pol I visual is a hinge, and it opens along the domain boundary.**
  Worth recording before it's lost: in eukaryotes, Pol δ does the
  strand-displacement synthesis that *makes* the flap, and FEN1 only cuts it —
  so Pol I's two jobs split across two proteins, and the polymerase half
  returns to the lagging clamp, because **Pol δ is the lagging polymerase**.
  `pol1.gd`'s shipped visual is already two lobes: EXO and POL. Those are
  exactly the two functions that diverge. The two-lobe shape, built for a
  bacterial reason (nick translation reads as one unit doing two things at
  once), already encodes the eukaryotic seam: POL's job goes back to the
  lagging clamp, EXO becomes FEN1. Whoever writes `EukaryoticModeDesign.md`
  should start there.
- **Sliding clamp / clamp loader** (β-clamp → PCNA, γ complex → RFC) are the
  other named-in-COMPLEXITY_MODEL.md renames. Both are pure renames and both
  are honest — but neither enzyme is built, so no keys yet, same reasoning
  that holds for topoisomerase and SSB.

---

## Scope for this pass

_As of the original v71 pass. See the Complex-tier addendum above for
ligase/primase/Pol I, all fully wired since — that scope note below is
kept as historical record, not current status._

- **Labeled now (v71)**: helicase ring, polymerase clamp (leading + lagging —
  same label, since both are Pol III per the biological model). _Superseded in
  v77: that is a CIRCULAR-topology claim. In LINEAR they are genuinely different
  enzymes (Pol epsilon leading, Pol delta lagging) and the shared key splits —
  see the v77 addendum above._ **Labeled
  since (Complex-tier addendum)**: ligase, primase, Pol I — all built and
  wired.
- **Explicitly out of scope, unchanged**: base letters (A/T/C/G) and polarity
  markers (`5'`/`3'`) — per DESIGN.md these are standard notation, not
  natural-language text, and are never translated.
- **Still not included**: topoisomerase, SSB — no design doc for their
  visuals exists yet beyond Topoisomerase.md's speculative sketch, so no keys
  reserved for them yet either. Add when their own design docs firm up.

---

## Language switching: live, via Godot's built-in mechanism

The roadmap flagged this as needing a decision because it changes the hook's
shape. Resolution: **live switching, with minimal plumbing**, by leaning on a
mechanic Godot's `Control` nodes already have.

- Enzyme labels' text is set via `set_key()` to the raw translation key (e.g.
  `"ENZYME_HELICASE"`), never the display string.
- `Control`-derived text properties (including `RichTextLabel.text`) are
  **auto-translated**: with `auto_translate_mode` left at its default, Godot
  treats the assigned text as a translation key and displays `tr(text)` for
  you. Every `Control` also receives `NOTIFICATION_TRANSLATION_CHANGED`
  automatically whenever `TranslationServer.set_locale()` is called, and
  **re-applies the translation on its own** — no manual per-label refresh
  call needed. **Confirmed working in practice** (see As-Built).
- Practical consequence: `enzyme_label.gd` sets the key exactly once, at
  spawn time, and never touches `text` again. Changing the locale anywhere
  in the game updates every existing label with zero additional code.

### `LocaleManager` (scene node)

Follows the existing ComplexityManager/ThemeManager pattern: a plain `Node`
in the scene tree, Inspector-editable, not yet an autoload.

```
LocaleManager (Node, %LocaleManager)
├── @export default_locale: String = "en"
├── set_locale(code: String)     # calls TranslationServer.set_locale(code)
├── get_locale() -> String
└── signal locale_changed(new_locale: String)
```

`set_locale()` calls `TranslationServer.set_locale(code)` (which is what
actually fires `NOTIFICATION_TRANSLATION_CHANGED` on every `Control`) and
*also* emits `locale_changed` — kept even though no label needs it directly,
because a future language-picker widget (highlighting the current selection,
say) is not a `Control.text` case and would need an explicit signal. Same
"emit the signal even if nothing subscribes yet" pattern as `helicase.gd`'s
`phase_changed`.

**Setup traps** (see As-Built): the CSV must be added under Project
Settings → Localization → Translations, not just imported; and the
`LocaleManager` node needs "Access as Unique Name" explicitly enabled. Both
fail silently if missed.

---

## `enzyme_label.gd` + `EnzymeLabel.tscn` (shared component)

Shipped as a scene, not a bare-`Label` script (see As-Built for why).

```
EnzymeLabel.tscn  (root: PanelContainer, script: enzyme_label.gd)
└── RichTextLabel
      fit_content = true
      autowrap_mode = OFF
      bbcode_enabled = true
```

Public API:
```gdscript
set_key(key: String)                          # raw translation key, once
set_anchor_pos(anchor_pos: Vector2)           # parent-local point the
                                               # label's own center pins to
set_mirror(mirror: bool)                      # counter-scale for mirrored parents
set_style(font, font_size, text_color, panel_bg_color)
refresh_translation()                         # manual escape hatch, unused so far
```

- Spawned the same way every other enzyme visual is spawned (per SKILL.md's
  Architecture Patterns): instantiate → configure non-tree properties →
  `add_child()` → `set_key()` / `set_style()`.
- Owned by the enzyme script it labels (`helicase_ring.gd`,
  `polymerase_clamp.gd`), not by `replication_manager.gd` — consistent with
  "no script reaches into another script's owned visual nodes."
- Fade is free: a child `Control`'s rendering already multiplies against the
  parent `CanvasItem`'s `modulate`, so the label fades in/out with its parent
  enzyme automatically.
- Scrub-safe by construction: the label has no clock of its own and no
  tween; its only per-frame behavior is following its parent's transform,
  which is already scrub-safe.

---

## Positioning per enzyme

### Helicase ring
No mirroring involved. Label sits above the ring's rotation band, at a fixed
local offset that clears the tallest blob position, recomputed each
`_apply()` (so Inspector tuning of `ring_radius`/`max_blob_height` still
moves it) but with no dependency on rotation phase:

```
offset_y = ring_radius + max_blob_height * 0.5 + label_margin
label.set_anchor_pos(Vector2(0.0, -offset_y))
```

### Polymerase clamp — the mirroring wrinkle
The leading clamp is `scale.y = -1` on the whole node. A naive child `Label`
would render mirrored. Resolved via `set_mirror(_mirror)`, which sets the
label's own local `scale.y = -1` when mirrored — composed with the parent's
own `scale.y = -1`, this cancels to `1.0` for the label specifically, so
glyphs stay upright on both strands while every other part of the clamp
keeps the single shared mirrored geometry.

Position, in the clamp's own local frame (OUTSIDE = local `+y`): placed just
past the back body's **rest-state** outer edge (`half_down`, not the
pump-grown value, so it doesn't breathe with the clamp's animation):

```
label.set_anchor_pos(Vector2(0.0, half_down + polymerase_label_margin))
```

### Ligase — simplest case, single symmetric blob
No mirroring (ligase only ever operates on the lagging strand — one
instance, not two). Fixed offset above the blob's rest size, same
"recomputed each `_apply()`, no dependency on the pulse" shape as the two
above:

```
label.set_anchor_pos(Vector2(0.0, base_size * 0.5 + ligase_label_margin))
```

### Primase — same shape as ligase, opposite side
Also single-instance, no mirroring. Offset is negative (above the blob)
rather than positive — a small deliberate difference so the two enzymes'
labels don't visually collide if they're ever near each other on the strand
at the same time:

```
label.set_anchor_pos(Vector2(0.0, -(base_size * 0.5 + primase_blip_label_margin)))
```

### Pol I — the one anchor that needed revisiting more than once
No mirroring. Unlike the three single-piece enzymes above, the anchor has
to clear TWO stacked lobes (EXO above, POL below — see
OkazakiMaturationDesign.md's Pol I Implementation Status), not one blob's
own height, so it's derived from whichever lobe currently reaches
furthest rather than a single `base_size`. Current formula (post both
visual-tuning passes — see the addendum above): EXO sits at local origin
and is the tallest reference, so the anchor only needs to clear its own
half-height, not any additional lobe-gap term:

```
label.set_anchor_pos(Vector2(0.0, -(lobe_size * 0.5 + pol1_label_margin)))
```

---

## ThemeManager — "Polymerase Clamp" group additions

(Not a separate "Enzyme Labels" group as originally planned — see As-Built.
`helicase_ring.gd`'s label config lives as local `@export` vars on that
script instead.)

The name stayed "Polymerase Clamp" even after ligase, primase, and Pol I
started reading from it too — the five fields below are generic (font,
color, panel, z, the cross-cutting on/off lens), not clamp-specific, so
nothing about them needed a rename just because more enzymes share them.
Each enzyme keeps its OWN margin as a separate field in its OWN group
instead (`polymerase_label_margin`, `ligase_label_margin`,
`primase_blip_label_margin`, `pol1_label_margin`) — margin is the one
value that's genuinely per-shape, everything else is universal:

```
enzyme_labels_enabled: bool = true   # cross-cutting lens, same pattern as
                                      # wobble_enabled / atp_activation_enabled
label_font_size: int
label_color: Color
label_panel_color: Color
label_z: int
```

(`polymerase_label_margin` stays listed here in this group specifically —
the one enzyme whose margin field happens to live alongside the shared
fields rather than in a separate group, since polymerase_clamp.gd predates
the other three having their own groups at all.)

**Open question carried forward**: should the Low-Info theme variants
(TODO_List) default `enzyme_labels_enabled` to `false`? Labels aren't
animated, so they don't violate Low-Info's "fewer simultaneous animated
elements" rule directly, but they are additional simultaneous visual/reading
load. Left open until the Low-Info theme pass itself is designed.

---

## Translation key registry

CSV lives at `res://localization/enzyme_labels.csv`, registered under
Project Settings → Localization → Translations (not just imported — see
As-Built).

```
keys,en,pt_BR,es
ENZYME_HELICASE,Helicase,Helicase,Helicasa
ENZYME_HELICASE_FULL,DnaB Helicase,Helicase DnaB,Helicasa DnaB
ENZYME_POLYMERASE,Polymerase,Polimerase,Polimerasa
ENZYME_POLYMERASE_FULL,DNA Polymerase III,DNA Polimerase III,ADN Polimerasa III
ENZYME_POL3,Pol III,Pol III,Pol III
ENZYME_PRIMASE,Primase,Primase,Primasa
ENZYME_LIGASE,Ligase,Ligase,Ligasa
ENZYME_POL1,Pol I,Pol I,Pol I
ENZYME_POL1_FULL,DNA Polymerase I,DNA Polimerase I,ADN Polimerasa I
ENZYME_POL_EPSILON,Pol epsilon,Pol épsilon,Pol épsilon
ENZYME_POL_DELTA,Pol delta,Pol delta,Pol delta
```

- `ENZYME_POLYMERASE` is shared by both the leading and lagging clamp
  instances — one key, two label instances — matching PolymeraseDesign.md's
  "same enzyme, mirrored/recolored per strand" treatment. **v77: that sharing
  is CIRCULAR-only.** In LINEAR topology the two clamps are different enzymes
  and take `ENZYME_POL_EPSILON`/`ENZYME_POL_DELTA` — see the v77 addendum's
  key-selection matrix.
- `ENZYME_POL_EPSILON` / `ENZYME_POL_DELTA` (v77) are the **first genuinely
  translatable enzyme rows** in this file. Every row above is either a proper
  noun or a Roman numeral and lands identically across locales; spelled-out
  Greek letter names are ordinary words, so pt_BR/es want the accent
  ("épsilon"). Spelled rather than "Pol ε"/"Pol δ" deliberately — at label size
  on a moving clamp, a one-glyph difference between the two most important
  enzymes in the eukaryotic fork is the same failure the RNA/DNA rule already
  forbids. Accent spelling is a first-pass guess pending native-speaker review.
- `ENZYME_POL3` is the tier-conditional swap key — see the Complex-tier
  addendum above. Short form matches `ENZYME_POL1`'s own convention ("Pol
  III"/"Pol I"), not `ENZYME_POLYMERASE_FULL`'s longer scientific form.
- The two `_FULL` keys (`ENZYME_HELICASE_FULL`, `ENZYME_POLYMERASE_FULL`)
  are still reserved and still unused by any code path — `ENZYME_POL3`
  answered the actual disambiguation need without them. `ENZYME_POL1_FULL`
  was added for consistency with the pattern even though nothing reads it
  yet either — same "reserve the row now" reasoning `ENZYME_PRIMASE`/
  `ENZYME_LIGASE` originally used before their own enzymes existed.
- `ENZYME_PRIMASE` / `ENZYME_LIGASE` rows exist now so the CSV doesn't need a
  second edit pass when those tiers land. _(Both tiers have since landed —
  see the Complex-tier addendum above.)_

---

## Open items (not yet resolved)

- Whether `enzyme_labels_enabled` should default off in Low-Info themes
  (depends on the not-yet-designed Low-Info theme pass).
- Native-speaker review of the `_FULL` translations' word order (see
  As-Built) — currently inconsistent between the two rows. Now three rows
  with this exact shape (`ENZYME_HELICASE_FULL`, `ENZYME_POLYMERASE_FULL`,
  `ENZYME_POL1_FULL`), all still unread by any code path, all still worth
  the same review pass whenever it happens.
- Whether a language-picker UI belongs in `PlayerUI` now or waits until more
  than one language-dependent surface exists.
- UI text localization (`UI_CHAR_COUNT`, preset names, dialog/button text) —
  separate, unfinished thread; see As-Built.
- The temporary debug keybind in `locale_manager.gd` (`L` cycles locales)
  should be removed once locale switching has been exercised across a full
  play session, per this project's "debug scaffolding is temporary" rule.
- ~~Whether `topology_mode`'s eukaryotic label variants get their own CSV rows
  now or wait until `topology_mode` itself exists~~ — **RESOLVED (v77).** The
  precondition expired: topology_mode shipped with the telomerase tier. Two rows
  added (`ENZYME_POL_EPSILON`/`ENZYME_POL_DELTA`); the rest deliberately NOT
  reserved, because renaming primase to "Pol α-primase" or Pol I to "FEN1" while
  they keep bacterial mechanics teaches a falsehood about those proteins. See the
  v77 addendum for the honesty table, and the reasoning that narrowed
  OkazakiMaturationDesign.md's original blanket "label-only" decision.
- **Native-speaker review now covers three items, not one** (worth batching): the
  `_FULL` word-order inconsistency above; "Pol épsilon"'s accent in pt_BR/es —
  the first genuinely *translatable* enzyme rows in the file, since spelled-out
  Greek names are ordinary words where "Pol III"/"Pol I" were not; and
  "eucariota" vs "eucariótico" in the es `UI_TOPOLOGY_*` strings.
