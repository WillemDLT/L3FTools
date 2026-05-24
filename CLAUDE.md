# L3FTools

Multi-tool successor to AutomarkerL3F for TBC Classic (Interface 20505). Bundles the Automarker plus an Atlas/encyclopedia of NPCs, drops, and heroic dungeon trash.

## What this addon does
- **Automarker tab** — same engine as AutomarkerL3F (auto-marks NPCs by ID + priority, unique-mark aware, profile-aware, wing-aware — see `Sections.lua`).
- **Atlas tab** — browse all known raid + heroic NPCs, view 3D model + spells + tactical notes + drops. Search bar filters across raids.
- **Settings tab** — toggles, slash help, version info.

## File layout
- `Core.lua` — bootstrap, SavedVariables, raid registry, profile API, slash commands
- `Engine.lua` — Automarker engine (mark assignment, GUID tracking, lock logic)
- `Mouseover.lua` — hold-keybind that marks the mob under the cursor (registered via `Bindings.xml`)
- `Bindings.xml` — declares the rebindable "hold to mark" key
- `Sections.lua` — wing-aware marking engine: instance detection by `instanceMapID`, active-wing scoping, per-wing mark priorities, on-screen switcher, 6h memory
- `Sections/<Raid>.lua` — spatial wing layout per raid; calls `L3F:RegisterSections{ raid, mapID, sections={...} }`. Build with the `wing-section-raid` skill (its Progress section tracks which raids are done)
- `Frame.lua` — main window scaffold, resizable, tab system
- `Tabs/Automarker.lua` — Automarker tab UI + profile strip
- `Tabs/Atlas.lua` — Atlas tab UI (tree + list + detail, Drops/Spells/Notes sub-tabs)
- `Tabs/Map.lua` — Guild Map tab (world map + minimap pin sharing)
- `Tabs/Guild.lua` — parent tab; sub-tabs live in `Tabs/Guild/*`
- `Tabs/Guild/Composer.lua` — Raid Composer (drag-drop palette + groups + bench grid)
- `Tabs/Guild/Crafts*.lua` — Guild-wide recipe directory, profession scrape, sync, tooltips, and chat posting
- `Tabs/Guild/RaidPlanner*.lua` — raidplan.io-style strategy canvas, sharing/import, and co-op tools
- `Tabs/Guild/Planner.lua` — free-form spreadsheet-style guild planner
- `Tabs/Settings.lua` — settings tab
- `GuildMap/*.lua` — shared map-pin infrastructure (Core, Broadcast, Pins, PinToggle)
- `UI/HoverPreview.lua` — Model tooltip + pin
- `UI/ModelViewer.lua` — interactive zoom/rotate/pop-out model panel
- `UI/PlayerMarksDialog.lua` — sticky per-player mark assignment dialog
- `Minimap.lua` — minimap button
- `Data/<Raid>.lua` — 9 raid NPC registries (mirror AutomarkerL3F's `Data/`); each NPC also carries `kind = "boss"|"trash"` for the Atlas Bosses/Trash split
- `Data/Drops/<Raid>.lua` — 9 drop tables (`L3F.RegisterDrops(npcID, dropList)`)
- `Data/Heroics/<Dungeon>.lua` — 16 heroic dungeon NPC catalogs with inline drops (Normal + Heroic difficulties)
- `Data/Consumables/*.lua` — 10 category files (Flasks, Battle Elixirs, etc.), `L3F.RegisterConsumables`
- `Data/Factions.lua` / `Data/Collections.lua` — bonus Atlas categories, `L3F.RegisterBonusCategory`
- `Media/` — icons
- `verify.sh` — pre-commit checker: brace/paren balance, NULL bytes, suspicious last line, Lua block balance, key-function presence, TOC load order, duplicate NPC id/name, Sections-vs-Data cross-check, `luac5.1 -p` syntax pass

## Schemas

NPC (same as AutomarkerL3F):
```lua
{ id = 17535, name = "Dorothee", marks = {8},
  spells = { 31013, 31014, 31012 },
  notes = "Wizard of Oz - main caster. Summons Tito at ~50% HP." },
```

Drop:
```lua
L3F.RegisterDrops(17535, {
  { id = 30664, chance = 18, name = "Calix's Hood" },
})
```

## Build / test loop
1. Edit Lua files
2. Run `./verify.ps1` on Windows or `bash verify.sh` in Git Bash/Linux — must report 0 file failures, 0 missing functions, toc load order OK
3. Commit + push to `dev` — GitHub Actions repackages the `beta` release asset
4. Morphéours (beta tester) pulls the `beta` zip, verifies in-game, reports back

## Critical conventions
- **Symmetric editing with AutomarkerL3F** — the raid `Data/<Raid>.lua` files, the `Sections/` wing layouts, and the Automarker / wing engine mirror between projects. Any change to a raid's NPC registry, mark assignments, wing layout, or engine behavior must land in both. Diff to confirm: `diff <(awk '/anchor/,/end/' AutomarkerL3F/path) <(awk '/anchor/,/end/' L3FTools/path)`.
- **Long-write protocol** — Edit and Write tools have a track record of silently truncating files >3KB on the Windows mount. For large rewrites use bash heredoc; never trust a single Write call on a long file. Run verify.sh after every edit pass.
- **Mover regex pitfall** — non-greedy regex over nested Lua tables stops at the first `},` which is a single NPC's terminator. Use unique downstream anchors or brace-depth tracking instead.
- **toc file** — `L3FTools.toc` lists load order. New files must be added there or they won't load. Verify with `verify.sh`.

## Git
- `main` = stable; `dev` = WIP. All work lands on `dev`; squash `dev` → `main` only after Morphéours verifies the change in-game.
- `.github/workflows/package.yml` repackages a correctly-named release zip on every push — the `beta` release asset tracks `dev`, the `live` asset tracks `main`.
- Morphéours downloads the `beta` release **asset**: `github.com/WillemDLT/L3FTools/releases/download/beta/L3FTools.zip`. Never hand him a raw `/archive/refs/heads/*.zip` — its wrapper folder won't match the `.toc` and WoW won't load it.
- GitHub ops use the `gh` CLI at `C:\Program Files\GitHub CLI\gh.exe` (not on Bash PATH; call by full path). No GitHub MCP.
- Author: Willem (willem-YT@hotmail.com). GitHub display name: WillemDLT.

## Project status
- Version 0.24.0 (`.toc`). All work lands on `dev`; Morphéours pulls the beta zip and reports back.
- **Wing-aware marking** + spatial sectioning for all 9 raids: shipped.
- **Atlas tab** complete: Raids / Heroic Dungeons / Consumables / Factions / Collections / **Professions** in a 3-pane tree → list → detail layout with sub-tabs Drops / Spells / Notes. Heroic dungeons carry Normal + Heroic drop tables. Bonus-category items use coordinate-based search + cross-link to NPC sources. Professions (10 professions, 2137 entries) come from Morphéours's hand-curated `Data-Professions.ods` + greenlit Wowhead supplements (`_migration/professions_ingest/supplements.json`). Recipe rows render the RESULT item's icon via `Data/ProfessionsRecipeMap.lua` (1943 spell→item mappings), sourced from the per-skill Wowhead TBC pages by the reusable scraper at `_migration/wowhead_scrape/fetch_listview.py`. Pre-BiS and PvP remain wiped (no hand-curated data yet).
- **Composer tab** (Tabs/Guild/Composer.lua) complete: 27-spec palette, drag-drop or click-to-add, 5 groups + 1 bench default (groups [1, 5], benches [0, 5]), per-group party-aura icons, raid-wide buffs/debuffs sidebar with hover tooltips, multiple named profiles, L3F2C share/import strings. Personal-only — permissions framework was dropped per Willem's 0.15.0 scope-in (see [[project-l3ftools-composer-official]]). See [[project-l3ftools-composer-complete]] for the build details + the drag-drop machinery's quirks.
- **Map tab** complete on a previous session (universal minimap-button collector opt-out). See [[project-l3ftools-map-complete]].
- **AutomarkerL3F** shipped to main, hands-off (see [[project-automarkerl3f-complete]]).
- **Crafts tab** implemented in 0.24.0: guild-wide recipe directory with crafter counts, recipe search/detail, profession-window scraping, guild sync, reagent tooltips, favorites, and post-to-guild helpers.
- **Raid Planner tab** implemented: encounter/page plans with background images, draggable icons, drawing tools, text/color/variant properties, L3F share/import strings, and co-op tools. Treat in-game polish and co-op edge cases as the next likely work, not initial build work.
- **Planner tab** implemented: free-form spreadsheet-style guild planner with editable cells, dropdown options, add row/column, undo, text size/color controls, merge/unmerge, and duplicate-row helper.
- No original Guild sub-tab is still a blank placeholder. Next work should start from bug reports, in-game verification, or UX polish rather than phase scaffolding.
- Per-tab `preferredWidth`/`preferredHeight` in `RegisterTab` opts auto-grows the main window on tab open.

## Atlas / WoW Data
The master reference behind the in-game Atlas tab lives at `C:\Users\pc\Downloads\WoW Addons\WoW Data\` (JSON, organised by category folder: `raids/<Raid>.json`, `consumables/`, `dungeons/`, ...). The addon's `Data/`, `Data/Drops/` and `Sections/` files are *derived* from it on a reviewed pull — never auto-edited. Extend the master via the `atlas` skill (one chunk per run); Gruul's Lair is the first pilot raid signed off.
