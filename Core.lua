-- =============================================================
-- L3FTools - Core.lua
-- =============================================================
-- Bootstrap, saved variables, raid registry, slash commands.
-- The Automarker engine lives in Engine.lua. The window in Frame.lua.
-- Tab contents in Tabs/*.lua.
-- =============================================================

local addonName, L3F = ...
_G.L3FTools = L3F

-- Key Bindings UI labels. Set here in the first-loaded file so they exist
-- before Bindings.xml is processed - otherwise the Key Bindings window shows
-- the raw header key ("HEADER_L3FTOOLS") instead of a friendly name.
BINDING_HEADER_L3FTOOLS = "L3FTools"
BINDING_NAME_L3FTOOLS_MOUSEOVERMARK = "Hold to mark mob under cursor"
BINDING_NAME_L3FTOOLS_RESETMARKS    = "Clear all raid marks"

-- LibDeflate (loaded from Libs/) - used to compress profile export strings.
local LibDeflate = LibStub and LibStub("LibDeflate", true)


-- =============================================================
-- 1.  RAID REGISTRY  (used by both Automarker tab and Atlas tab)
-- =============================================================
L3F.raids = {}

function L3F:RegisterRaid(raidDef)
    table.insert(self.raids, raidDef)
end

function L3F.iterNPCs(raid, cb)
    if raid.sections then
        for _, section in ipairs(raid.sections) do
            for _, npc in ipairs(section.npcs) do
                cb(npc, section.name)
            end
        end
    elseif raid.npcs then
        for _, npc in ipairs(raid.npcs) do
            cb(npc, nil)
        end
    end
end

L3F.npcLookup = nil

-- Pending drops registered by Data/Drops/*.lua before npcLookup is built.
-- Attached to NPCs in buildLookup().
L3F.pendingDrops = {}

function L3F.RegisterDrops(npcID, dropList)
    L3F.pendingDrops[npcID] = dropList
end

-- Inverse index: item ID -> { {npc=..., chance=..., raid=...}, ... }
-- Built after npcLookup so a future Atlas search bar can do reverse-lookup.
L3F.itemLookup = nil

-- =============================================================
-- CONSUMABLES REGISTRY (Atlas-only - the Automarker never reads these)
-- =============================================================
-- Each consumable is a record { id, name, category, effect, notes, [nameFR] }.
-- The category groups it under the Consumables tree node (e.g. "Flasks",
-- "Battle Elixirs"). consumableCategoryOrder preserves registration order
-- so Data/Consumables/Flasks.lua appears before Data/Consumables/Food.lua
-- if listed that way in the .toc.
L3F.consumables = {}              -- categoryName -> { item, item, ... }
L3F.consumableLookup = {}         -- itemID -> item
L3F.consumableCategoryOrder = {}  -- ordered list of category names

function L3F.RegisterConsumables(items)
    for _, item in ipairs(items) do
        local cat = item.category or "Other"
        if not L3F.consumables[cat] then
            L3F.consumables[cat] = {}
            table.insert(L3F.consumableCategoryOrder, cat)
        end
        table.insert(L3F.consumables[cat], item)
        if item.id then L3F.consumableLookup[item.id] = item end
    end
end

-- =============================================================
-- BONUS CATEGORIES  (Atlas-only: Factions / Pre-BiS / PvP / Professions /
-- Collections). These are reference lists of items grouped into sections
-- (Friendly/Honored/Revered/Exalted for factions, slot-grouped for Pre-BiS,
-- recipe-grouped for Professions, etc.). The Automarker never reads them.
--
-- bonusCategories preserves registration order so the Atlas tree shows
-- the categories in the order the .toc loads them. bonusLookup is the
-- O(1) reverse map used by the search + cross-link paths.
-- =============================================================
L3F.bonusCategories = {}        -- ordered { { key, label, entries }, ... }
L3F.bonusLookup    = {}         -- catKey -> { entryKey -> entry }
-- Inverse: item ID -> { {catKey=..., entry=..., sectionName=...}, ... }.
-- Populated by RegisterBonusCategory so the Atlas's global search can find
-- bonus items by ID and so the detail pane can label an item's source
-- ("Honored reward from Cenarion Expedition") without re-scanning.
L3F.bonusItemLookup = {}

function L3F.RegisterBonusCategory(catKey, displayName, entries)
    table.insert(L3F.bonusCategories,
        { key = catKey, label = displayName, entries = entries })
    L3F.bonusLookup[catKey] = L3F.bonusLookup[catKey] or {}
    for _, entry in ipairs(entries) do
        L3F.bonusLookup[catKey][entry.key] = entry
        for _, section in ipairs(entry.sections or {}) do
            -- Default kind is "item"; sections flagged kind = "set" hold
            -- item-set IDs (resolve via GetItemSetInfo). Propagate to the
            -- per-source lookup record so the Atlas search + detail pane
            -- can pick the right resolver.
            local kind = section.kind or "item"
            for _, item in ipairs(section.items or {}) do
                if item.id then
                    L3F.bonusItemLookup[item.id] = L3F.bonusItemLookup[item.id] or {}
                    table.insert(L3F.bonusItemLookup[item.id], {
                        catKey      = catKey,
                        catLabel    = displayName,
                        entry       = entry,
                        sectionName = section.name,
                        kind        = kind,
                    })
                end
            end
        end
    end
end

local function buildLookup()
    L3F.npcLookup = {}
    L3F.itemLookup = {}
    for _, raid in ipairs(L3F.raids) do
        L3F.iterNPCs(raid, function(npc, sectionName)
            npc.raid = raid.name
            npc.section = sectionName
            L3F.npcLookup[npc.id] = npc
        end)
    end
    -- Enrich NPCs with their drop tables
    for npcID, drops in pairs(L3F.pendingDrops) do
        local npc = L3F.npcLookup[npcID]
        if npc then
            npc.drops = drops
            for _, drop in ipairs(drops) do
                if not L3F.itemLookup[drop.id] then L3F.itemLookup[drop.id] = {} end
                table.insert(L3F.itemLookup[drop.id], {
                    npcID = npcID, npc = npc, chance = drop.chance,
                })
            end
        end
    end
end
L3F.buildLookup = buildLookup


-- =============================================================
-- 2.  SAVED VARIABLES
-- =============================================================
local DEFAULTS = {
    -- Window state
    window = {
        x = nil, y = nil,
        width  = 900,
        height = 560,
        activeTab = "automarker",
    },
    -- Automarker module
    automarker = {
        enabled         = true,
        combatLock      = true,
        oncePlacedLock  = true,   -- if true, never re-mark a GUID we've already marked
        enabledNPCs     = {},     -- LIVE config - engine reads here
        markPriorities  = {},     -- LIVE config
        profiles        = {},     -- name -> { enabledNPCs={...}, markPriorities={...} }
        activeProfile   = nil,
        _initialized    = false,
        -- Player marks: sticky per-player mark assignments. Survive Clear All
        -- (Sections.lua's ResetAllMarks re-applies them after the cycle+clear).
        -- The engine reserves these mark indices so it never uses them for
        -- NPCs (findFreeMark in Engine.lua treats them as taken).
        playerMarks     = {},     -- shortCharName -> markIdx (1..8)
    },
    -- Atlas module
    atlas = {
        lastSelectedRaid = "Karazhan",
        lastSelectedNPC  = nil,
        -- Default lands new installs on Drops - it's the first tab in the
        -- 0.13.1 sub-tab strip order (Drops / Spells / Notes). Existing
        -- users keep whatever they had saved.
        lastActiveSubTab = "drops",
    },
    -- Preview (the hover popup next to the Automarker tab; also shared
    -- state for Atlas's embedded model viewer where applicable).
    preview = {
        zoom       = 1.0,
        autoRotate = true,
        pinned     = false,
        sizeW      = 280,
        sizeH      = 540,
    },
    -- Minimap button (LibDBIcon-managed; see Minimap.lua)
    minimap = {
        hide       = false,
        minimapPos = 200,   -- degrees around the minimap; LibDBIcon reads/writes this key
    },
    -- Guild Map module (live position sharing on world map + minimap)
    guildMap = {
        privacyAnswered  = false,  -- set true after the user has answered the first-run popup
        shareWithGuild   = false,  -- broadcast position to guild members with L3FTools
        shareWithFriends = false,  -- whisper-broadcast position to char-friends with L3FTools
        -- Note: myRoles lives in the PER-CHARACTER savedvar (L3FToolsCharDB),
        -- not here. The original implementation put it in guildMap which made
        -- it account-wide; moved out in 0.11.6.
        -- Auto-pause broadcasting inside any raid instance OR battleground.
        -- (Pre-rename name was pauseInRaidInstance; migrated below.)
        pauseInInstance  = true,
        blockedPlayers   = {},     -- characters this client refuses to share with
        -- Display preferences (used by chunks 4-5; saved here so the panel
        -- can reach them through a single namespace).
        showOnWorldMap   = true,
        showOnMinimap    = true,
        iconStyle        = "class",   -- "class" | "dot"
        worldPinSize     = 0.8,
        minimapPinSize   = 1.0,
        showName         = true,
        showLevel        = true,
        showHP           = true,
        -- LibDBIcon savedvar for the pin-visibility minimap button.
        pinsButton       = { hide = false, minimapPos = 230 },
    },
}

local function deepCopyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                local t = {}
                for kk, vv in pairs(v) do t[kk] = vv end
                target[k] = t
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            deepCopyDefaults(target[k], v)
        end
    end
end

local function initDB()
    L3FToolsDB     = L3FToolsDB     or {}
    L3FToolsCharDB = L3FToolsCharDB or {}
    -- One-time per-character migration: if this character has no
    -- per-char myRoles yet, seed from the previous account-wide value
    -- so 0.11.5-and-earlier users don't see their roles wiped on
    -- upgrade. Each character on the account independently runs this
    -- on its first 0.11.6+ login; once seeded, each diverges.
    -- The account-wide field is left in place (orphaned, harmless) so
    -- alt characters who log in later still get the same seed.
    if L3FToolsCharDB.myRoles == nil then
        L3FToolsCharDB.myRoles = (L3FToolsDB.guildMap and L3FToolsDB.guildMap.myRoles) or ""
    end
    -- One-time migration: older builds used a custom minimap button that
    -- saved its angle under `angle`. LibDBIcon (now used by Minimap.lua)
    -- reads/writes the angle under `minimapPos`. Carry the user's saved
    -- position across the rename. Runs BEFORE deepCopyDefaults so the
    -- default minimapPos=200 doesn't overwrite the migrated value.
    if L3FToolsDB.minimap
       and L3FToolsDB.minimap.minimapPos == nil
       and L3FToolsDB.minimap.angle then
        L3FToolsDB.minimap.minimapPos = L3FToolsDB.minimap.angle
        L3FToolsDB.minimap.angle = nil
    end
    -- One-time migration: pauseInRaidInstance -> pauseInInstance (now covers
    -- raid AND BG instances per Morphéours B.4). Keep the user's prior choice.
    if L3FToolsDB.guildMap
       and L3FToolsDB.guildMap.pauseInInstance == nil
       and L3FToolsDB.guildMap.pauseInRaidInstance ~= nil then
        L3FToolsDB.guildMap.pauseInInstance = L3FToolsDB.guildMap.pauseInRaidInstance
        L3FToolsDB.guildMap.pauseInRaidInstance = nil
    end
    -- One-time migration: pin-size defaults dropped from 1.0 to 0.8 per
    -- Morphéours' eye. If the user still has the OLD default (1.0) at this
    -- point, bump them down to the new default. Guarded by a flag so a
    -- user who later sets back to 1.0 on purpose isn't re-migrated.
    if L3FToolsDB.guildMap and not L3FToolsDB.guildMap._pinSizeMigratedTo08 then
        if L3FToolsDB.guildMap.worldPinSize == 1.0 then
            L3FToolsDB.guildMap.worldPinSize = 0.8
        end
        if L3FToolsDB.guildMap.minimapPinSize == 1.0 then
            L3FToolsDB.guildMap.minimapPinSize = 0.8
        end
        L3FToolsDB.guildMap._pinSizeMigratedTo08 = true
    end
    -- Follow-up migration: minimapPinSize moves BACK to 1.0 (Morphéours
    -- said 0.8 was too small on the minimap). Only flips users still on
    -- the previous-default 0.8; if they've since picked anything else,
    -- we leave it alone.
    if L3FToolsDB.guildMap and not L3FToolsDB.guildMap._minimapSizeRevertedToOne then
        if L3FToolsDB.guildMap.minimapPinSize == 0.8 then
            L3FToolsDB.guildMap.minimapPinSize = 1.0
        end
        L3FToolsDB.guildMap._minimapSizeRevertedToOne = true
    end
    -- Migration: the old master pinsHidden flag is gone. If a user had
    -- toggled pins off via the (now removed) master toggle, fold that
    -- into the per-surface flags so their pins stay hidden after upgrade.
    if L3FToolsDB.guildMap and L3FToolsDB.guildMap.pinsHidden then
        L3FToolsDB.guildMap.showOnWorldMap = false
        L3FToolsDB.guildMap.showOnMinimap  = false
    end
    if L3FToolsDB.guildMap then
        L3FToolsDB.guildMap.pinsHidden = nil
    end
    -- Drop shareWithGroup. Party/raid members are pinned natively by the
    -- WoW client, so an L3FTools group broadcast would always be redundant.
    -- The field is gone from DEFAULTS; clear any saved value.
    if L3FToolsDB.guildMap then
        L3FToolsDB.guildMap.shareWithGroup = nil
    end
    deepCopyDefaults(L3FToolsDB, DEFAULTS)
    -- First-ever launch: enable Automarker for every NPC we know about.
    if not L3FToolsDB.automarker._initialized then
        for id in pairs(L3F.npcLookup) do
            L3FToolsDB.automarker.enabledNPCs[id] = true
        end
        L3FToolsDB.automarker._initialized = true
    end
    -- Profile migration: snapshot current config as "Default" if no profiles yet.
    L3FToolsDB.automarker.profiles = L3FToolsDB.automarker.profiles or {}
    if not next(L3FToolsDB.automarker.profiles) then
        local snap = { enabledNPCs = {}, markPriorities = {} }
        for k, v in pairs(L3FToolsDB.automarker.enabledNPCs) do snap.enabledNPCs[k] = v end
        for k, v in pairs(L3FToolsDB.automarker.markPriorities) do
            local copy = {}
            for i, m in ipairs(v) do copy[i] = m end
            snap.markPriorities[k] = copy
        end
        L3FToolsDB.automarker.profiles["Default"] = snap
        L3FToolsDB.automarker.activeProfile = L3FToolsDB.automarker.activeProfile or "Default"
    end
    L3F.db = L3FToolsDB
end


-- =============================================================
-- 3.  PRIORITY HELPERS (shared with the Automarker tab)
-- =============================================================
function L3F.effectivePriority(npc)
    return L3F.db.automarker.markPriorities[npc.id] or npc.marks
end


-- =============================================================
-- PROFILES (save/load/delete/export/import)
-- =============================================================
function L3F.GetProfileNames()
    local names = {}
    if L3F.db and L3F.db.automarker.profiles then
        for n in pairs(L3F.db.automarker.profiles) do table.insert(names, n) end
        table.sort(names)
    end
    return names
end

-- Deep copy of the wing-priority store (sections.marks[mapID][wingIdx][npcID]).
local function copySectionMarks(src)
    local out = {}
    for mapID, byMap in pairs(src or {}) do
        out[mapID] = {}
        for wingIdx, byWing in pairs(byMap) do
            out[mapID][wingIdx] = {}
            for npcID, list in pairs(byWing) do
                local c = {}
                for i, m in ipairs(list) do c[i] = m end
                out[mapID][wingIdx][npcID] = c
            end
        end
    end
    return out
end

function L3F.SaveProfile(name)
    if not name or name == "" then return false, "Empty profile name" end
    local am = L3F.db.automarker
    local p = { enabledNPCs = {}, markPriorities = {} }
    for k, v in pairs(am.enabledNPCs) do p.enabledNPCs[k] = v end
    for k, v in pairs(am.markPriorities) do
        local copy = {}
        for i, m in ipairs(v) do copy[i] = m end
        p.markPriorities[k] = copy
    end
    p.sectionMarks = copySectionMarks(L3F.db.sections and L3F.db.sections.marks)
    am.profiles[name] = p
    am.activeProfile = name
    return true, "Saved profile '" .. name .. "'"
end

function L3F.LoadProfile(name)
    local am = L3F.db.automarker
    local p = am.profiles and am.profiles[name]
    if not p then return false, "No profile named '" .. tostring(name) .. "'" end
    wipe(am.enabledNPCs); wipe(am.markPriorities)
    for k, v in pairs(p.enabledNPCs or {}) do am.enabledNPCs[k] = v end
    for k, v in pairs(p.markPriorities or {}) do
        local copy = {}
        for i, m in ipairs(v) do copy[i] = m end
        am.markPriorities[k] = copy
    end
    if p.sectionMarks then
        L3F.db.sections = L3F.db.sections or {}
        L3F.db.sections.marks = copySectionMarks(p.sectionMarks)
    end
    am.activeProfile = name
    return true, "Loaded profile '" .. name .. "'"
end

function L3F.DeleteProfile(name)
    local am = L3F.db.automarker
    if not am.profiles or not am.profiles[name] then return false, "No such profile" end
    am.profiles[name] = nil
    if am.activeProfile == name then am.activeProfile = nil end
    return true, "Deleted profile '" .. name .. "'"
end

function L3F.SyncActiveProfile()
    local am = L3F.db.automarker
    if not am.activeProfile then return end
    local p = am.profiles[am.activeProfile]
    if not p then return end
    p.enabledNPCs = {}
    for k, v in pairs(am.enabledNPCs) do p.enabledNPCs[k] = v end
    p.markPriorities = {}
    for k, v in pairs(am.markPriorities) do
        local copy = {}
        for i, m in ipairs(v) do copy[i] = m end
        p.markPriorities[k] = copy
    end
    p.sectionMarks = copySectionMarks(L3F.db.sections and L3F.db.sections.marks)
end

function L3F.SerializeProfile(name, profile)
    if not profile then return nil end
    local enabled = {}
    for id in pairs(profile.enabledNPCs or {}) do table.insert(enabled, tostring(id)) end
    table.sort(enabled, function(a, b) return tonumber(a) < tonumber(b) end)
    local prios = {}
    local keys = {}
    for id in pairs(profile.markPriorities or {}) do table.insert(keys, id) end
    table.sort(keys)
    for _, id in ipairs(keys) do
        table.insert(prios, tostring(id) .. "=" .. table.concat(profile.markPriorities[id], ","))
    end
    local secs = {}
    for mapID, byMap in pairs(profile.sectionMarks or {}) do
        for wingIdx, byWing in pairs(byMap) do
            for npcID, list in pairs(byWing) do
                table.insert(secs, mapID .. "." .. wingIdx .. "." .. npcID
                    .. "=" .. table.concat(list, ","))
            end
        end
    end
    table.sort(secs)
    local safeName = (name or "Untitled"):gsub(":", "_")
    local inner = safeName .. ":e" .. table.concat(enabled, ",")
        .. ":p" .. table.concat(prios, ";")
        .. ":s" .. table.concat(secs, ";")
    if LibDeflate then
        local compressed = LibDeflate:CompressDeflate(inner)
        return "L3F2:" .. LibDeflate:EncodeForPrint(compressed)
    end
    return "L3F1:" .. inner
end

function L3F.DeserializeProfile(str)
    if type(str) ~= "string" then return nil, "Not a string" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    local inner
    if str:sub(1, 5) == "L3F2:" then
        if not LibDeflate then return nil, "LibDeflate not loaded; cannot decode L3F2 string" end
        local encoded = str:sub(6)
        local compressed = LibDeflate:DecodeForPrint(encoded)
        if not compressed then return nil, "Decode failed (corrupted L3F2 string?)" end
        inner = LibDeflate:DecompressDeflate(compressed)
        if not inner then return nil, "Decompress failed (corrupted L3F2 string?)" end
    elseif str:sub(1, 5) == "L3F1:" then
        inner = str:sub(6)
    else
        return nil, "Invalid format (expected L3F1: or L3F2:)"
    end
    local name, rest = inner:match("^([^:]+):(.+)$")
    if not name then return nil, "Invalid format (missing name)" end
    local enabledPart = rest:match(":?e([^:]*)") or ""
    local prioPart    = rest:match(":?p([^:]*)") or ""
    local sectionPart = rest:match(":?s(.*)$") or ""
    local profile = { enabledNPCs = {}, markPriorities = {}, sectionMarks = {} }
    for id in enabledPart:gmatch("(%d+)") do
        profile.enabledNPCs[tonumber(id)] = true
    end
    for entry in prioPart:gmatch("([^;]+)") do
        local idStr, marksStr = entry:match("^(%d+)=(.+)$")
        if idStr and marksStr then
            local list = {}
            for m in marksStr:gmatch("(%d+)") do table.insert(list, tonumber(m)) end
            profile.markPriorities[tonumber(idStr)] = list
        end
    end
    for entry in sectionPart:gmatch("([^;]+)") do
        local mapID, wingIdx, npcID, marksStr = entry:match("^(%d+)%.(%d+)%.(%d+)=(.+)$")
        if mapID then
            local list = {}
            for m in marksStr:gmatch("(%d+)") do table.insert(list, tonumber(m)) end
            mapID, wingIdx, npcID = tonumber(mapID), tonumber(wingIdx), tonumber(npcID)
            local sm = profile.sectionMarks
            sm[mapID] = sm[mapID] or {}
            sm[mapID][wingIdx] = sm[mapID][wingIdx] or {}
            sm[mapID][wingIdx][npcID] = list
        end
    end
    return name, profile
end


-- =============================================================
-- 4.  EVENTS
-- =============================================================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        buildLookup()
        initDB()
        if L3F.BuildFrame    then L3F.BuildFrame()    end
        if L3F.BuildMinimap  then L3F.BuildMinimap()  end
        print("|cffffd100L3FTools|r loaded. Type |cffffff00/l3f|r or click the minimap icon.")
    elseif event == "PLAYER_TARGET_CHANGED" then
        if L3F.AutomarkerTryMark then L3F.AutomarkerTryMark("target") end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if L3F.AutomarkerResetGUIDs then L3F.AutomarkerResetGUIDs() end
    end
end)


-- =============================================================
-- 5.  SLASH COMMANDS
-- =============================================================
local function handleSlash(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "toggle" then
        L3F.db.automarker.enabled = not L3F.db.automarker.enabled
        print("|cffffd100L3FTools|r Automarker " ..
            (L3F.db.automarker.enabled and "|cff00ff00enabled|r" or "|cffff5555disabled|r"))
        if L3F.UpdateSwitcher then L3F.UpdateSwitcher() end
    elseif msg == "minimap" then
        L3F.db.minimap.hide = not L3F.db.minimap.hide
        if L3F.RefreshMinimap then L3F.RefreshMinimap() end
        print("|cffffd100L3FTools|r minimap button " ..
            (L3F.db.minimap.hide and "|cffff5555hidden|r" or "|cff00ff00shown|r"))
    elseif msg == "mappins" then
        if L3F.GuildMap and L3F.GuildMap.TogglePinsHidden then
            L3F.GuildMap.TogglePinsHidden()
        end
    elseif msg == "switcher" or msg == "wing" then
        if L3F.ToggleSwitcher then L3F.ToggleSwitcher() end
    elseif msg == "automarker" or msg == "atlas" or msg == "map" or msg == "guild" or msg == "settings" then
        if not L3F.mainFrame then if L3F.BuildFrame then L3F.BuildFrame() end end
        if L3F.ShowTab then L3F.ShowTab(msg) end
        if L3F.mainFrame and not L3F.mainFrame:IsShown() then L3F.mainFrame:Show() end
    elseif msg == "reset" or msg == "resetwindow" then
        if L3F.ResetWindow then L3F.ResetWindow() end
    elseif msg:match("^gm%s") or msg == "gm" then
        -- /l3f gm <sub> - GuildMap debug commands. Hidden from /l3f help
        -- until Phase 1 chunks land; intended for in-game verification
        -- during chunk 3/4 testing.
        local sub = msg:match("^gm%s+(.+)$") or ""
        if sub == "dump" then
            if L3F.GuildMap and L3F.GuildMap.DumpRoster then L3F.GuildMap.DumpRoster() end
        elseif sub == "send" then
            if L3F.GuildMap and L3F.GuildMap.BroadcastNow then
                local ok = L3F.GuildMap.BroadcastNow()
                print("|cffffd100L3FMap|r send: " .. (ok and "|cff00ff00ok|r" or "|cffff5555blocked|r"))
            end
        elseif sub == "privacy" then
            if L3F.GuildMap and L3F.GuildMap.ShowPrivacyPopup then L3F.GuildMap.ShowPrivacyPopup() end
        elseif sub == "resetprivacy" then
            if L3F.GuildMap and L3F.GuildMap.ResetPrivacyAnswer then L3F.GuildMap.ResetPrivacyAnswer() end
        else
            print("|cffffd100L3FMap|r commands: dump | send | privacy | resetprivacy")
        end
    elseif msg == "help" then
        print("|cffffd100L3FTools|r commands:")
        print("  /l3f                open the window")
        print("  /l3f automarker     open on Automarker tab")
        print("  /l3f atlas          open on Atlas tab")
        print("  /l3f map            open on Map tab")
        print("  /l3f guild          open on Guild tab")
        print("  /l3f settings       open on Settings tab")
        print("  /l3f toggle         master Automarker enable on/off")
        print("  /l3f minimap        hide/show the main minimap button")
        print("  /l3f mappins        hide/show all guild-map pins")
        print("  /l3f switcher       show/hide the wing switcher")
        print("  /l3f reset          reset window size + position to defaults")
    else
        if L3F.ToggleFrame then L3F.ToggleFrame() end
    end
end

SLASH_L3FTOOLS1 = "/l3f"
SLASH_L3FTOOLS2 = "/l3ftools"
SlashCmdList["L3FTOOLS"] = handleSlash
