# L3FTools

Multi-tool successor to AutomarkerL3F for TBC Classic (Interface 20505). Bundles the Automarker plus an Atlas/encyclopedia of NPCs, drops, and heroic dungeon trash.

## What this addon does
- **Automarker tab** — same engine as AutomarkerL3F (auto-marks NPCs by ID + priority, unique-mark aware, profile-aware).
- **Atlas tab** — browse all known raid + heroic NPCs, view 3D model + spells + tactical notes + drops. Search bar filters across raids.
- **Settings tab** — toggles, slash help, version info.

## File layout
- `Core.lua` — bootstrap, SavedVariables, raid registry, profile API, slash commands
- `Engine.lua` — Automarker engine (mark assignment, GUID tracking, lock logic)
- `Frame.lua` — main window scaffold, resizable, tab system
- `Tabs/Automarker.lua` — Automarker tab UI + profile strip
- `Tabs/Atlas.lua` — Atlas tab UI (raid dropdown, NPC grid, sub-tabs)
- `Tabs/Settings.lua` — settings tab
- `UI/HoverPreview.lua` — Model tooltip + pin
- `UI/ModelViewer.lua` — interactive zoom/rotate/pop-out model panel
- `Minimap.lua` — minimap button
- `Data/<Raid>.lua` — 9 raid NPC registries (mirror AutomarkerL3F's `Data/`)
- `Data/Drops/<Raid>.lua` — 9 drop tables (`L3F.RegisterDrops(npcID, dropList)`)
- `Data/Heroics/<Dungeon>.lua` — 16 heroic dungeon NPC catalogs
- `Media/` — icons
- `verify.sh` — pre-commit checker (brace balance, NULL bytes, function presence, toc load order)

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
3. In WoW: `/reload`
4. Open with `/l3f` or minimap button; test the tab affected

## Critical conventions
- **Symmetric editing with AutomarkerL3F** — the raid `Data/<Raid>.lua` files and the Automarker engine code mirror between projects. Any change to a raid's NPC registry, mark assignments, or engine behavior must land in both. Diff to confirm: `diff <(awk '/anchor/,/end/' AutomarkerL3F/path) <(awk '/anchor/,/end/' L3FTools/path)`.
- **Long-write protocol** — Edit and Write tools have a track record of silently truncating files >3KB on the Windows mount. For large rewrites use bash heredoc; never trust a single Write call on a long file. Run verify.sh after every edit pass.
- **Mover regex pitfall** — non-greedy regex over nested Lua tables stops at the first `},` which is a single NPC's terminator. Use unique downstream anchors or brace-depth tracking instead.
- **toc file** — `L3FTools.toc` lists load order. New files must be added there or they won't load. Verify with `verify.sh`.

## Git
- `main` = stable; `dev` = WIP. Squash dev → main when in-game tested.
- Author: Willem (willem-YT@hotmail.com). GitHub display name: WillemDLT.

## Project status
- Currently at v0.4.0 baseline (committed locally 2026-05-18).
- Karazhan Opera section recently added — 10 NPCs across 3 variants (Wizard of Oz, Romulo & Julianne, Big Bad Wolf), uncommitted at time of writing.
- Open punch-list: Coilfang heroic trash IDs need re-verification; bundled default profiles deferred.
