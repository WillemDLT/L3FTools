-- =============================================================
-- L3FTools - Tabs/Guild/RaidPlanner.lua
-- =============================================================
-- In-raid strategy planner. Modeled on raidplan.io + MRT:
-- assistant draws markers / freehand / ability icons on top of a
-- boss-room map; saves multi-page plans; broadcasts to the raid
-- channel (assistant-only gating via UnitIsGroupAssistant).
--
-- Placeholder content until Phase 4.
-- =============================================================

local addonName, L3F = ...

local function buildRaidPlanner(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    title:SetText("Raid Planner")

    local body = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("CENTER", parent, "CENTER", 0, 0)
    body:SetJustifyH("CENTER")
    body:SetText(
        "Draw strategy plans for raid bosses.\n\n" ..
        "|cffaaaaaaMarkers, freehand, ability icons, multi-page plans\n" ..
        "and assistant-only raid broadcast land here in Phase 4.|r"
    )
    body:SetTextColor(0.8, 0.8, 0.8, 1)
end

L3F.RegisterTab("guild.raidplanner", "Raid Planner", nil, buildRaidPlanner, { parent = "guild" })
