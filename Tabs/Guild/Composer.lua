-- =============================================================
-- L3FTools - Tabs/Guild/Composer.lua
-- =============================================================
-- Raid composer sub-tab. Modeled on wowtbc.gg/raid-comp:
-- 5 groups + bench, drag/drop or click-to-add specs, auto-tally
-- of which raid-wide buffs and debuffs are covered.
--
-- Personal mode (Phase 2): client-side draft + export-string sharing.
-- Official mode (Phase 2.5): guild-wide "comp for tonight" with
-- rank-based edit permissions.
--
-- Placeholder content until Phase 2.
-- =============================================================

local addonName, L3F = ...

local function buildComposer(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    title:SetText("Raid Composer")

    local body = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("CENTER", parent, "CENTER", 0, 0)
    body:SetJustifyH("CENTER")
    body:SetText(
        "Plan your 25-man comp.\n\n" ..
        "|cffaaaaaaSpecs, groups, buff/debuff coverage,\n" ..
        "and export-string sharing land here in Phase 2.|r"
    )
    body:SetTextColor(0.8, 0.8, 0.8, 1)
end

L3F.RegisterTab("guild.composer", "Composer", nil, buildComposer, { parent = "guild" })
