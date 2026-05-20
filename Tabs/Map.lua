-- =============================================================
-- L3FTools - Tabs/Map.lua
-- =============================================================
-- Real-time map of guildmates / groupmates / friends. The actual
-- world-map and minimap pins live outside this tab (drawn by
-- HereBeDragons via GuildMap/Pins.lua); this tab is the control
-- panel: sharing toggles, roster view, display settings, safety.
--
-- Placeholder content until Phase 1 chunks 2-5 land.
-- =============================================================

local addonName, L3F = ...

local function buildMap(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    title:SetText("Map")

    local body = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("CENTER", parent, "CENTER", 0, 0)
    body:SetJustifyH("CENTER")
    body:SetText(
        "Real-time map of guildmates, groupmates and friends.\n\n" ..
        "|cffaaaaaaSharing toggles, roster view, display settings,\n" ..
        "and the live world-map / minimap pins land here.|r"
    )
    body:SetTextColor(0.8, 0.8, 0.8, 1)
end

L3F.RegisterTab("map", "Map", nil, buildMap)
