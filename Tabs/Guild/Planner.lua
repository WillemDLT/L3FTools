-- =============================================================
-- L3FTools - Tabs/Guild/Planner.lua
-- =============================================================
-- Free-form guild planner. Scope to be defined by Morpheours
-- ("a planner that works a bit like Excel" - up for refinement:
-- attendance tracker / loot / DKP / todo / free-form notes).
-- Rank-based edit ACL via the permissions framework when it lands.
--
-- Placeholder content until Phase 5 (and a scoping pass).
-- =============================================================

local addonName, L3F = ...

local function buildPlanner(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    title:SetText("Planner")

    local body = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("CENTER", parent, "CENTER", 0, 0)
    body:SetJustifyH("CENTER")
    body:SetText(
        "Free-form guild planner.\n\n" ..
        "|cffaaaaaaScope pending. Waiting on Morpheours\n" ..
        "for the specific use case before building.|r"
    )
    body:SetTextColor(0.8, 0.8, 0.8, 1)
end

L3F.RegisterTab("guild.planner", "Planner", nil, buildPlanner, { parent = "guild" })
