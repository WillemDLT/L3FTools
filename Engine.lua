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
