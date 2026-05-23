-- =============================================================
-- L3FTools - Tabs/Guild/Crafts.lua
-- =============================================================
-- Guild-wide recipe registry. Modeled on GuildCrafts:
-- each addon user broadcasts their own learned recipes; the union
-- becomes the guild crafting database. Search by item / recipe /
-- profession; tooltip integration; single-responder !gc chat lookup.
--
-- Placeholder content until Phase 3 (needs the permissions framework).
-- =============================================================

local addonName, L3F = ...

local function buildCrafts(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    title:SetText("Guild Crafts")

    local body = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("CENTER", parent, "CENTER", 0, 0)
    body:SetJustifyH("CENTER")
    body:SetText(
        "Find guild crafters instantly.\n\n" ..
        "|cffaaaaaaShared recipe database, item tooltip integration,\n" ..
        "and the !gc chat lookup land here in Phase 3.|r"
    )
    body:SetTextColor(0.8, 0.8, 0.8, 1)
end

L3F.RegisterTab("guild.crafts", "Crafts", nil, buildCrafts, { parent = "guild" })
