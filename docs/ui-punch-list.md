# UI: where it stands, what's available, what to do

September 2026. The editor is functional and plain: default Godot theme,
text buttons, fixed three-column layout. This is the survey of what Godot
offers to make it look and feel like a tool people enjoy, and a prioritised
punch list. Everything listed is MIT/OFL/CC0/Apache — safe for internal
commercial use.

## What's available (Godot 4.7, rendering stays in Godot)

**The Theme system itself.** Every Control reads colours, fonts, StyleBoxes
and constants from a `Theme`. A coherent look is one Theme resource with
`StyleBoxFlat`s (flat fills, rounded corners, borders, shadows) for
Button/Panel/Tree/Tabs/LineEdit… plus one UI font. The Godot editor's own
look is built exactly this way. No framework required; this is the main
lever.

**[ThemeGen](https://godotengine.org/asset-library/asset/3299)** (MIT) —
write the theme as GDScript from design tokens (a palette, spacing scale,
radii) instead of clicking through the Theme editor; regenerates on save.
Gives us dark/light variants and consistent spacing for free. Recommended.

**[godot-minimal-theme](https://github.com/passivestar/godot-minimal-theme)**
(MIT) — the flat "Modern" theme that became Godot 4.6's default *editor*
theme. It targets the editor, not runtime Controls, but its tokens (neutral
greys, 6px radii, 1px hairline borders, single accent) are a proven
reference for a Godot tool that looks good. We can lift the palette.

**[Themey](https://github.com/wadlo/Themey)** (MIT code) — collection of
runtime game themes. Game-flavoured (chunky, decorative); not a fit for a
production tool, but shows the range.

**[Godot Flat UI](https://jacksonpm.itch.io/godot-flat-ui)** — free token
based flat kit for 4.6+, "AI assisted", licence not stated. Skip.

**Icons.** [Lucide](https://godotengine.org/asset-library/asset/5047)
(icons ISC, addon MIT; 1,500+ consistent stroke icons), Material Symbols
(Apache-2.0), Tabler (MIT). We already rasterise SVG at runtime for packs,
so tool/menu icons need no addon: drop the SVGs in `hexmap/ui/icons/` and
load them at the toolbar's DPI. Icons are the single biggest visual lift
for the toolbar and the layers panel.

**Fonts.** Inter (OFL) for UI, JetBrains Mono (OFL) for coordinates and
numbers. Godot's fallback font is fine but generic.

**[godot-dockable-container](https://github.com/gilzoide/godot-dockable-container)**
(CC0) — editor-style docking: panels as tabs that can be split, dragged,
saved/restored as a Resource. Gives Photoshop/Godot-editor panel behaviour
(collapse the palette, tear layers off into their own tab) without writing
a docking system. Optional, medium effort.

**Not applicable:** web UI frameworks, Qt, Flutter — the interface stays
in Godot's Controls so the canvas and the panels are one app.

## Punch list

Ordered by payoff. P1 changes how it feels; P2 changes how it works; P3 is
polish.

### P1 — look
1. **One theme.** ThemeGen-style tokens: neutral dark palette (canvas
   darker than panels), 8px spacing scale, 6px radii, hairline borders,
   one accent colour for selection/focus, hover and pressed states on
   everything. Panel headers, section labels, disabled states.
2. **Icons on the toolbar and panels** (Lucide): tools become icon buttons
   with the letter shortcut in the tooltip; New/Open/Save, undo/redo, zoom,
   eye/lock in Layers, folder glyphs, per-type glyphs for elements.
3. **UI font** (Inter) at 13px, mono for the coordinate readout.
4. **Canvas frame**: neutral dark surround with a subtle drop shadow under
   the map, a faint page-style outline; grid colour and width defaults tuned
   against the placeholder art.
5. **Selection gizmos**: rotation handle and corner scale handles on a
   selected prop; hover outline before click; wall vertex handles that grow
   on hover. Cursor changes per tool.
6. **Palette**: larger swatches with a hover preview, pack name headers
   inside each tab, one search box that filters every tab, recently used
   row.

### P2 — workflow
7. **Docking / collapsible panels** (dockable-container): hide the palette
   while placing, widen the layers panel, remember layout in prefs.
8. **Status bar as controls**: zoom percentage as a dropdown (fit/50/100/
   200), snap mode and grid as icon toggles, GM/Player view toggle,
   level selector moved here from the toolbar.
9. **Right-click menus** on the canvas (delete, duplicate, send to folder,
   flip, lock) and in Layers (rename, group, delete, select all in folder).
10. **Recent files** in File menu and a start screen (recent maps with
    thumbnails, New, Open, examples).
11. **Inspector upgrades**: sliders for angle/radius/intensity, colour
    swatch row for lights, unit toggle for positions (px / hex / ft),
    multi-selection editing (shared fields).
12. **Undo history panel** and toast notifications for exports (with a
    progress bar for multi-page PDFs) instead of the status line.
13. **Navigator/minimap** in a corner of the canvas; smooth zoom to cursor.
14. **Duplicate** (Ctrl/Cmd+D) and copy/paste of elements between levels
    and maps.

### P3 — polish
15. HiDPI scale factor and a light theme variant from the same tokens.
16. Empty-state hints (blank map: "pick a terrain to start painting").
17. Tooltips with texture previews on palette items; shortcut cheatsheet
    overlay (hold `?`).
18. Keyboard navigation in Layers (arrows, space toggles eye).
19. Tool options bar under the toolbar (brush size, snap, rotation) instead
    of scattered controls in palette tabs.

## Suggested order

1–3 together (theme + icons + font) is one focused pass and transforms the
first impression. Then 5 and 6 (gizmos, palette) because they are where
hands spend the time. 7 (docking) and 8 (status bar) next. The rest as they
bite.

## First pass: theme variants (September 2026)

`hexmap/ui/theme_builder.gd` builds the Theme from tokens; four variants are
switchable live under View → Theme (also `--theme <name>` on the command
line). Same map, same state:

| Variant | Idea | Screenshot |
|---|---|---|
| Slate | Neutral cool greys, blue accent, 6px radii — the godot-minimal-theme lineage | `docs/images/themes/theme_slate.png` |
| Forge | Warm near-black, amber accent that matches torchlight, softer 8px radii, bigger icons | `docs/images/themes/theme_forge.png` |
| Studio | Mid-grey Photoshop/Blender density, teal accent, 3px radii, compact 12px type | `docs/images/themes/theme_studio.png` |
| Parchment | Light warm paper, ink text, deep-red accent — the print/rulebook feel | `docs/images/themes/theme_parchment.png` |

Also in this pass: Lucide icons on the toolbar, status bar and Layers
panel (eye/lock/folder/type glyphs), Inter + JetBrains Mono, themed inputs
and trees, a canvas surround colour with a drop shadow under the map, and
zoom controls in the status bar.

## Framework samples (September 2026)

Each candidate from the survey was actually installed and applied to the
editor in the same state (Forest Road, campfire selected). Switch live under
View → Theme and View → Dockable panels, or `--theme <id> --layout dock`.

| Sample | What it is | Runtime-usable? | Screenshot |
|---|---|---|---|
| Godot default | No theme at all, only icons/fonts. The baseline. | yes | `docs/images/frameworks/godot_default.png` |
| ThemeBuilder (ours) | Tokens → Theme in ~400 lines of our own GDScript, built at start-up, four variants | yes | `docs/images/frameworks/themebuilder_slate.png` |
| **ThemeGen** (MIT) | Same tokens written in ThemeGen's DSL (`hexmap/ui/themes/slate_gen.gd`, `inherit`/`merge` composition), generated to a `.tres` by an EditorScript; live preview when editing in the Godot editor | yes (the generated `.tres`); generation needs the editor process (`--editor`) | `docs/images/frameworks/themegen_slate.png` |
| **godot-minimal-theme** (MIT) | The Godot 4.6 "Modern" editor look | **no** — the `.tres` is a script that reads `EditorInterface.get_editor_settings()`; it only exists inside the editor. Its tokens informed Slate. | — |
| **Themey: Spacey** (MIT/CC0) | Texture-based sci-fi game theme | yes | `docs/images/frameworks/themey_spacey.png` |
| **Themey: Clashy** (MIT/CC0) | Chunky 3D game buttons | yes | `docs/images/frameworks/themey_clashy.png` |
| **godot-dockable-container** (CC0) | Panels as tabs: drag onto another panel to tab, to an edge to split; layouts are Resources | yes | `docs/images/frameworks/dockable_container.png` |
| Lucide addon (MIT) | Editor dock + `LucideIcon` node over the same SVGs | yes, but we already load the SVGs directly (`UiIcons`); the addon adds nothing at run time | — |

What the samples showed:

- **There is no runtime UI framework layer for Godot** in the web sense.
  Every option is either a Theme resource (a look), a way to author Theme
  resources (ThemeGen, our builder), or a layout container (dockable). The
  "framework" decision is therefore three independent choices: how we author
  the theme, whether we adopt docking, and which icon set.
- **ThemeGen vs ThemeBuilder** produce the same pixels from the same tokens
  (compare the two Slate shots; the ThemeGen one lacks icon overrides only
  because the sample did not port them). ThemeGen's wins are the
  `inherit`/`merge` composition and live preview *inside the Godot editor*;
  its costs are an editor-only generation step and a 290 KB generated file
  to keep in sync. We build our UI in code and rarely open the Godot editor,
  so the live preview is worth little to us.
- **Themey** is game UI: readable, but the wrong register for a production
  tool (Clashy especially). Useful as a reminder of the range, not a
  candidate.
- **Dockable container** is the one sample with a behavioural difference,
  and it works with our theme untouched (panels are TabContainers).

## Decision (September 2026)

- **Layout: godot-dockable-container**, adopted as the only layout. The
  arrangement is saved to `user://layout.tres` (`LayoutStore`), repaired on
  load if a panel is missing, and reset from the View menu. One upstream bug
  patched locally (see THIRD_PARTY.md).
- **Theme: ThemeBuilder tokens**, four palettes, chosen under View → Theme
  and remembered per user. ThemeGen and Themey
  samples removed.
- **Icons: Lucide SVGs** loaded directly by `UiIcons`.
- Tests: every variant builds with the expected variations and styles and
  passes WCAG contrast checks (text ≥ 7:1, hints ≥ 4.5:1, accent ≥ 3:1);
  every icon named in code exists and rasterises in the requested colour;
  layouts round-trip through disk and are repaired when a panel is missing;
  unknown theme ids fall back to Slate. `tools/ui_smoke.gd` drives the
  dropdown and the layout reset in a window.
