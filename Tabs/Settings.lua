-- =============================================================
-- L3FTools - Tabs/Settings.lua
-- =============================================================
-- Global preferences and addon info.
-- =============================================================

local addonName, L3F = ...

local function buildSettings(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    title:SetText("L3FTools settings")

    -- Master Automarker toggle
    local cb1 = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb1:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    cb1:SetChecked(L3F.db.automarker.enabled)
    cb1.text:SetText("  Enable Automarker (click a mob to mark it)")
    cb1:SetScript("OnClick", function(self)
        L3F.db.automarker.enabled = self:GetChecked()
        if L3F.UpdateSwitcher then L3F.UpdateSwitcher() end
    end)

    local cb2 = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb2:SetPoint("TOPLEFT", cb1, "BOTTOMLEFT", 0, -2)
    cb2:SetChecked(L3F.db.automarker.combatLock)
    cb2.text:SetText("  Combat lock (no new marks while in combat)")
    cb2:SetScript("OnClick", function(self) L3F.db.automarker.combatLock = self:GetChecked() end)

    local cb2b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb2b:SetPoint("TOPLEFT", cb2, "BOTTOMLEFT", 0, -2)
    cb2b:SetChecked(L3F.db.automarker.oncePlacedLock)
    cb2b.text:SetText("  Once-placed lock (never re-mark a GUID we've marked this session)")
    cb2b:SetScript("OnClick", function(self) L3F.db.automarker.oncePlacedLock = self:GetChecked() end)

    local cb3 = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb3:SetPoint("TOPLEFT", cb2b, "BOTTOMLEFT", 0, -2)
    cb3:SetChecked(not L3F.db.minimap.hide)
    cb3.text:SetText("  Show minimap button")
    cb3:SetScript("OnClick", function(self)
        L3F.db.minimap.hide = not self:GetChecked()
        if L3F.RefreshMinimap then L3F.RefreshMinimap() end
    end)

    -- Help text
    local help = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    help:SetPoint("TOPLEFT", cb3, "BOTTOMLEFT", 0, -24)
    help:SetWidth(560)
    help:SetJustifyH("LEFT")
    help:SetText(
        "|cffffd100Slash commands|r\n" ..
        "  /l3f                  open the window\n" ..
        "  /l3f automarker       open on Automarker tab\n" ..
        "  /l3f atlas            open on Atlas tab\n" ..
        "  /l3f map              open on Map tab\n" ..
        "  /l3f guild            open on Guild tab\n" ..
        "  /l3f settings         open on Settings tab\n" ..
        "  /l3f toggle           master Automarker enable on/off\n" ..
        "  /l3f minimap          hide/show the main minimap button\n" ..
        "  /l3f mappins          hide/show all guild-map pins\n"
    )

    local version = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 16, 12)
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    version:SetText("L3FTools v" .. ((getMeta and getMeta(addonName, "Version")) or "?") .. " - Les Trois Fromages")
end

L3F.RegisterTab("settings", "Settings", nil, buildSettings)
