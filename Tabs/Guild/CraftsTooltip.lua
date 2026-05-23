-- =============================================================
-- L3FTools - Tabs/Guild/CraftsTooltip.lua
-- =============================================================
-- Hook item tooltips so any item that's a profession-result-item
-- gets a "Crafted by: X, Y" appendix listing guildies who know the
-- recipe. Uses L3F.professionRecipeMap (spellID -> itemID) reversed
-- as the lookup, plus Crafts.GetCraftersFor for the live list.
--
-- Hooks GameTooltip and ItemRefTooltip (the latter handles chat
-- link clicks). Throttled per-item with a 0.25s cache so OnUpdate
-- spam from the tooltip doesn't re-run the lookup every frame.
-- =============================================================

local addonName, L3F = ...

local Crafts = L3F.Crafts
if not Crafts then return end  -- core didn't load, no-op

-- =============================================================
-- itemID -> spellID reverse lookup, built lazily on first hit.
-- =============================================================
local itemToSpell

local function ensureReverseMap()
    if itemToSpell then return end
    itemToSpell = {}
    if not L3F.professionRecipeMap then return end
    for spellID, itemID in pairs(L3F.professionRecipeMap) do
        -- Multiple spells can produce the same itemID (e.g. rank
        -- variants); we just store one. Last-wins is fine for
        -- "is this item crafted by anyone".
        itemToSpell[itemID] = spellID
    end
end


-- =============================================================
-- Per-tooltip cache to dedupe within one OnTooltipSetItem burst.
-- =============================================================
local lastItemID, lastResultLines, lastResultAt = nil, nil, 0
local CACHE_TTL = 0.25

local function craftersFor(itemID)
    if not itemID then return nil end
    local now = GetTime()
    if itemID == lastItemID and (now - lastResultAt) < CACHE_TTL then
        return lastResultLines
    end
    ensureReverseMap()
    local spellID = itemToSpell[itemID]
    if not spellID then
        lastItemID, lastResultLines, lastResultAt = itemID, nil, now
        return nil
    end
    local list = Crafts.GetCraftersFor(spellID)
    if not list or #list == 0 then
        lastItemID, lastResultLines, lastResultAt = itemID, nil, now
        return nil
    end
    -- Build the line(s). Online crafters first (already sorted).
    -- Cap at 5 names + " (+N more)".
    local maxShow = 5
    local shown = math.min(#list, maxShow)
    local parts = {}
    for i = 1, shown do
        local c = list[i]
        local short = c.short
        if c.online then
            short = "|cff66ff66" .. short .. "|r"  -- light green
        else
            short = "|cff888888" .. short .. "|r"  -- dim
        end
        table.insert(parts, short)
    end
    local line = table.concat(parts, ", ")
    if #list > maxShow then
        line = line .. string.format(" |cffaaaaaa(+%d more)|r", #list - maxShow)
    end
    lastItemID = itemID
    lastResultLines = { header = "L3F Crafts:", body = line }
    lastResultAt = now
    return lastResultLines
end


-- =============================================================
-- Tooltip injection
-- =============================================================
local function injectIntoTooltip(tt)
    local settings = Crafts.GetSettings()
    if not settings.tooltipEnabled then return end
    if not tt or not tt.GetItem then return end
    local name, link = tt:GetItem()
    if not link then return end
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end
    local res = craftersFor(itemID)
    if not res then return end
    tt:AddLine(" ")  -- separator
    tt:AddLine(res.header, 1, 0.82, 0)
    tt:AddLine(res.body, 1, 1, 1, true)
    tt:Show()
end

if GameTooltip then
    GameTooltip:HookScript("OnTooltipSetItem", injectIntoTooltip)
end
if ItemRefTooltip then
    ItemRefTooltip:HookScript("OnTooltipSetItem", injectIntoTooltip)
end
if ShoppingTooltip1 then
    ShoppingTooltip1:HookScript("OnTooltipSetItem", injectIntoTooltip)
end
if ShoppingTooltip2 then
    ShoppingTooltip2:HookScript("OnTooltipSetItem", injectIntoTooltip)
end
