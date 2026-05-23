-- =============================================================
-- L3FTools - Tabs/Guild/CraftsScraper.lua
-- =============================================================
-- TradeSkillFrame scrape. Hooks the open/update events on the
-- profession window; when the player opens a profession, walks
-- GetTradeSkillInfo, builds a {recipeName,...} set, looks each up
-- against our bundled name->spellID map, and writes the result to
-- L3F.Crafts.SetMyProfession. After a successful scrape, fires a
-- delta broadcast so guildies running L3FTools see the update.
--
-- TBC 2.5.x API used:
--   GetTradeSkillLine() -> profName, currentRank, maxRank
--   GetNumTradeSkills() -> totalRows (headers + recipes)
--   GetTradeSkillInfo(idx) -> name, type, ...
--   GetTradeSkillRecipeLink(idx) -> recipe spell link (rarely needed)
--   Events: TRADE_SKILL_SHOW / TRADE_SKILL_UPDATE / TRADE_SKILL_CLOSE
-- =============================================================

local addonName, L3F = ...

L3F.Crafts = L3F.Crafts or {}
local Crafts = L3F.Crafts

-- Throttle: don't re-scan more than once per second even if the
-- TradeSkillFrame fires UPDATE rapidly (it does, several times after
-- open and on every filter change).
local SCAN_THROTTLE = 1.0
local lastScanAt = 0

-- Map any profession name the trade skill frame returns to our
-- canonical English keys. The frame already returns localized names;
-- for non-English clients an alias table would go here. L3FTools is
-- English-only so the identity mapping covers it -- but we still
-- normalize trivial casing / whitespace.
local function canonicalProfName(name)
    if not name then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if Crafts.PROFESSION_SET[name] then return name end
    -- Common alias quirks (e.g. WoW returns "First Aid" with a space).
    local lower = name:lower()
    for _, p in ipairs(Crafts.PROFESSIONS) do
        if p:lower() == lower then return p end
    end
    return nil
end


-- =============================================================
-- Scan
-- =============================================================
local function scanTradeSkill()
    if not GetTradeSkillLine then return end
    local profName, curRank, maxRank = GetTradeSkillLine()
    profName = canonicalProfName(profName)
    if not profName then return end  -- "UNKNOWN" or a non-tracked profession

    local total = GetNumTradeSkills and GetNumTradeSkills() or 0
    if total == 0 then return end

    local recipes = {}
    local matched, unmatched = 0, 0
    for i = 1, total do
        local recipeName, recipeType = GetTradeSkillInfo(i)
        if recipeName and recipeType ~= "header" then
            local spellID = Crafts.LookupSpellByName(profName, recipeName)
            if spellID then
                recipes[spellID] = true
                matched = matched + 1
            else
                unmatched = unmatched + 1
                -- Fallback: store as a name-keyed pseudo-spell so it at
                -- least shows up in lists. Use a stable negative-hash
                -- of the name. Receiving members without the bundled
                -- name lookup will still see it as a string-named row.
                -- (Skipped for v1 to keep the wire format clean; will
                -- revisit if Morpheours hits unmapped recipes.)
            end
        end
    end

    -- Specialization (Alchemy / Blacksmithing / Tailoring / Leatherworking
    -- /Engineering have these on TBC). Some clients expose via
    -- GetSpellInfo on a known spec spell ID; simplest is to read the
    -- "Specialization" string off the frame title if present. For v1
    -- we leave spec=nil; the field is in the schema for later.
    local spec = nil

    Crafts.SetMyProfession(profName, recipes, spec,
        tonumber(curRank) or 0, tonumber(maxRank) or 0)

    -- Tell the comms layer to broadcast a delta (if loaded).
    if L3F.CraftsComms and L3F.CraftsComms.BroadcastSelfDelta then
        L3F.CraftsComms.BroadcastSelfDelta(profName)
    end

    if matched > 0 or unmatched > 0 then
        -- Cheap diag visible in /etrace; uncomment for development.
        -- print(string.format("|cffffd100L3F Crafts:|r %s scanned: %d matched, %d unmatched",
        --     profName, matched, unmatched))
    end
end

local function scheduleScan()
    local t = GetTime()
    if (t - lastScanAt) < SCAN_THROTTLE then return end
    lastScanAt = t
    -- Defer to next frame so we don't race with TradeSkillFrame's
    -- own OnShow setup (some entries are populated after a one-frame
    -- delay in TBC 2.5.x's trade skill code).
    C_Timer.After(0.05, scanTradeSkill)
end


-- =============================================================
-- Event hooks
-- =============================================================
local f = CreateFrame("Frame")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("TRADE_SKILL_UPDATE")
f:RegisterEvent("TRADE_SKILL_CLOSE")
f:SetScript("OnEvent", function(_, ev)
    if ev == "TRADE_SKILL_SHOW" or ev == "TRADE_SKILL_UPDATE" then
        scheduleScan()
    end
end)


-- =============================================================
-- Slash hook (manual rescan from /l3f crafts scan)
-- =============================================================
L3F.Crafts = L3F.Crafts or {}
function L3F.Crafts.ManualScan()
    if not (CloseTradeSkill and GetTradeSkillLine and GetTradeSkillLine()) then
        print("|cffffd100L3F Crafts:|r open a profession window first.")
        return
    end
    lastScanAt = 0
    scheduleScan()
end
