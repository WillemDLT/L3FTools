-- =============================================================
-- L3FTools - Engine.lua
-- =============================================================
-- Automarker engine. Two bug fixes in this revision:
--   1. findFreeMark now consults our session registry (assignedGUIDs)
--      in addition to nameplates - so it correctly avoids re-using a
--      mark we already placed on another same-NPC-ID mob even if that
--      mob's nameplate isn't visible.
--   2. The once-placed-lock is RELEASED automatically when a mob's
--      mark gets stolen by another (raid marks are unique per group,
--      so marking mob2 Skull removes Skull from mob1). On the next
--      click of mob1 we detect mark==nil + assignedGUID present and
--      let it re-mark with a fresh slot.
-- =============================================================

local addonName, L3F = ...

local assignedGUIDs = {}

local function getNPCID(unit)
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local kind = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    local _, _, _, _, _, npcIDStr = strsplit("-", guid)
    return tonumber(npcIDStr)
end

local function npcIDFromGUID(guid)
    if not guid then return nil end
    local kind = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    local _, _, _, _, _, npcIDStr = strsplit("-", guid)
    return tonumber(npcIDStr)
end

local function findFreeMark(priorityMarks)
    local used = {}
    -- ANY mark currently visible on a nameplate is taken (cross-type, not just same NPC ID).
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) then
            local m = GetRaidTargetIndex(u)
            if m then used[m] = true end
        end
    end
    -- ANY mark we've placed this session is taken too (works without nameplates).
    for _, tMark in pairs(assignedGUIDs) do
        used[tMark] = true
    end
    -- Sticky player marks are reserved - findFreeMark must never return one
    -- of these, otherwise the auto-marker would steal a mark off a tank/etc.
    if L3F.db and L3F.db.automarker and L3F.db.automarker.playerMarks then
        for _, m in pairs(L3F.db.automarker.playerMarks) do used[m] = true end
    end
    -- Walk the target NPC's priority list and return the first unused mark.
    for _, mark in ipairs(priorityMarks) do
        if not used[mark] then return mark end
    end
    return nil
end

local function tryMark(unit)
    if not L3F.db or not L3F.db.automarker.enabled then return end
    if not UnitExists(unit) then return end
    if not UnitCanAttack("player", unit) then return end
    if UnitIsDead(unit) then return end
    if L3F.db.automarker.combatLock and UnitAffectingCombat("player") then return end

    local guid = UnitGUID(unit)
    if not guid then return end

    local currentMark = GetRaidTargetIndex(unit)
    if currentMark then
        if assignedGUIDs[guid] and assignedGUIDs[guid] ~= currentMark then
            assignedGUIDs[guid] = currentMark
        end
        return
    end

    if L3F.db.automarker.oncePlacedLock and assignedGUIDs[guid] then
        assignedGUIDs[guid] = nil
    end

    local npcID = getNPCID(unit)
    if not npcID then return end
    -- Wing scoping: in a mapped raid, ignore mobs outside the active wing.
    -- NpcInActiveSection returns true when not in a mapped raid (fallback).
    if L3F.NpcInActiveSection and not L3F.NpcInActiveSection(npcID) then return end

    local cfg = L3F.npcLookup[npcID]
    if not cfg then return end
    if not L3F.db.automarker.enabledNPCs[npcID] then return end

    local priority = L3F.effectivePriority(cfg)
    if #priority == 0 then return end

    local mark = findFreeMark(priority)
    if mark then
        SetRaidTargetIcon(unit, mark)
        assignedGUIDs[guid] = mark
    end
end

L3F.AutomarkerTryMark    = tryMark
L3F.AutomarkerResetGUIDs = function() wipe(assignedGUIDs) end


-- =============================================================
-- PLAYER MARKS  (sticky per-player marks)
-- =============================================================
-- Storage:  L3F.db.automarker.playerMarks[shortName] = markIdx
-- Behavior: applied on assignment, GROUP_ROSTER_UPDATE, PLAYER_ENTERING_WORLD,
--           and at the end of ResetAllMarks (so they survive Clear All).
--           Reserved from findFreeMark so the engine never uses them on NPCs.
-- =============================================================

-- Walk party/raid units to find which token corresponds to a short name.
-- Returns the unit token ("player", "raid7", "party2", ...) or nil.
local function findUnitByName(name)
    if not name or name == "" then return nil end
    if UnitName("player") == name then return "player" end
    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and UnitName(u) == name then return u end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and UnitName(u) == name then return u end
        end
    end
    return nil
end
L3F.FindUnitByName = findUnitByName

-- Apply every saved player mark to its current unit token. Idempotent:
-- skips units that already hold the right mark.
--
-- "Free-slot guard": before re-applying a sticky mark to its owner, check
-- whether the mark is currently held by anyone else we can see (a nameplate
-- or another raid/party unit). If yes, leave the mark alone so we don't
-- yank it off a mob the raid leader is actively using or another player
-- it has been intentionally placed on. The mark restores naturally when
-- the holding mob dies (CLEU hook below calls this) or the user clears it
-- and the next trigger fires.
function L3F.ApplyPlayerMarks()
    if not L3F.db or not L3F.db.automarker then return end
    local marks = L3F.db.automarker.playerMarks
    if not marks then return end

    local inUse = {}
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) then
            local m = GetRaidTargetIndex(u)
            if m then inUse[m] = true end
        end
    end
    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) then
                local m = GetRaidTargetIndex(u)
                if m then inUse[m] = true end
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then
                local m = GetRaidTargetIndex(u)
                if m then inUse[m] = true end
            end
        end
    end

    for name, mark in pairs(marks) do
        local unit = findUnitByName(name)
        if unit and UnitExists(unit) then
            local current = GetRaidTargetIndex(unit)
            if current == mark then
                -- sticky owner already holds their mark; nothing to do
            elseif inUse[mark] then
                -- mark is on a visible mob or another player; leave it
            else
                -- mark slot is free; restore to the sticky owner
                SetRaidTarget(unit, mark)
            end
        end
    end
end

-- Assign a sticky mark to a player. Stores in savedvars + applies immediately
-- if the player is in the current group. Returns true on success, or
-- (false, errMsg) on validation failure.
function L3F.SetPlayerMark(name, mark)
    if not name or name == "" then return false, "No player name" end
    if type(mark) ~= "number" or mark < 1 or mark > 8 then
        return false, "Mark must be 1-8"
    end
    if not L3F.db or not L3F.db.automarker then return false, "DB not ready" end
    L3F.db.automarker.playerMarks = L3F.db.automarker.playerMarks or {}
    -- Strip any earlier holder of this same mark - WoW raid marks are unique,
    -- so two players cannot hold the same icon. Silent override; the UI
    -- prevents accidental conflicts by graying out already-held marks.
    for n, m in pairs(L3F.db.automarker.playerMarks) do
        if m == mark and n ~= name then
            L3F.db.automarker.playerMarks[n] = nil
        end
    end
    L3F.db.automarker.playerMarks[name] = mark
    local unit = findUnitByName(name)
    if unit and UnitExists(unit) then
        SetRaidTarget(unit, mark)
    end
    return true
end

function L3F.ClearPlayerMark(name)
    if not L3F.db or not L3F.db.automarker or not L3F.db.automarker.playerMarks then return end
    L3F.db.automarker.playerMarks[name] = nil
    local unit = findUnitByName(name)
    if unit and UnitExists(unit) then
        SetRaidTarget(unit, 0)
    end
end

-- Re-apply on roster/zone changes. PLAYER_ENTERING_WORLD comes with a brief
-- delay because units aren't always queryable the moment the event fires.
local pmFrame = CreateFrame("Frame")
pmFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
pmFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
pmFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.5, function() L3F.ApplyPlayerMarks() end)
    else
        L3F.ApplyPlayerMarks()
    end
end)


-- =============================================================
-- CLEU PRUNE + sticky player-mark restore
-- =============================================================
-- On every mob death we (a) drop the GUID from the session ledger so its
-- mark slot frees up for the next pack (Morphéours's "have to Clear All
-- between packs" fix), and (b) call ApplyPlayerMarks - if the dying mob
-- was holding a sticky player's mark, the slot is now free and the
-- sticky owner gets their mark back automatically. The free-slot guard
-- inside ApplyPlayerMarks prevents yanking marks off anything that
-- still legitimately holds them.
--
-- UNIT_DIED covers most mob deaths; UNIT_DESTROYED catches destructible
-- objects and some pet/vehicle teardowns; PARTY_KILL is a redundant
-- safety net for player-credited kills.
-- =============================================================
local cleu = CreateFrame("Frame")
cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
cleu:SetScript("OnEvent", function()
    local _, sub, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if not destGUID then return end
    if sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" or sub == "PARTY_KILL" then
        assignedGUIDs[destGUID] = nil
        if L3F.ApplyPlayerMarks then L3F.ApplyPlayerMarks() end
    end
end)
