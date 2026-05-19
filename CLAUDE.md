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
- `Tabs/Atlas.lua` — Atlas tab UI (raid dropdown, NPC grid, sub-tabs)
- `Tabs/Settings.lua` — settings tab
- `UI/HoverPreview.lua` — Model tooltip + pin
- `UI/ModelViewer.lua` — interactive zoom/rotate/pop-out model panel
- `Minimap.lua` — minimap button
- `Data/<Raid>.lua` — 9 raid NPC registries plus `Stockade.lua` (mirror AutomarkerL3F's `Data/`)
- `Data/Drops/<Raid>.lua` — 9 drop tables (`L3F.RegisterDrops(npcID, dropList)`)
- `Data/Heroics/<Dungeon>.lua` — 16 heroic dungeon NPC catalogs
- `Media/` — icons
- `verify.sh` — pre-commit checker: brace/paren balance, NULL bytes, suspicious last line, Lua block balance, key-function presence, TOC load order, duplicate NPC id/name

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
2. Run `bash verify.sh` — must report 0 file failures, 0 missing functions, toc load order OK
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
- Version 0.5.0 (`.toc`). Both addons on `dev`, in sync, working tree clean.
- **Wing-aware marking** (`Sections.lua` + `Sections/`) is built and shipped on `dev` — engine, instance detection, on-screen wing switcher, per-wing mark config, 6h memory. Treated as correct unless in-game verification by Morphéours proves otherwise.
- Per-raid spatial sectioning done: Tempest Keep, Serpentshrine Cavern. Remaining 7 (Karazhan, Black Temple, Gruul's Lair, Magtheridon's Lair, Hyjal Summit, Zul'Aman, Sunwell Plateau) each await a section list, built via the `wing-section-raid` skill.
- Open punch-list: bundled default profiles deferred.
