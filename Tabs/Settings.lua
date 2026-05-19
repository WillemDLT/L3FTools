-- =============================================================
-- L3FTools - Tabs/Settings.lua
-- =============================================================
-- Global preferences and addon info.
-- =============================================================

local addonName, L3F = ...

-- =============================================================
-- KEYBIND PICKER - SetupKeybindButton turns a UIPanelButton into a
-- "click, then press a key" picker for a binding from Bindings.xml.
-- It drives WoW's own binding system, so the Esc > Key Bindings
-- entry stays in sync with whatever is set here.
-- =============================================================
local KB_MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function kbModified(key)
    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
       or key == "LALT" or key == "RALT" or key == "UNKNOWN" then
        return nil
    end
    local p = ""
    if IsAltKeyDown()     then p = "ALT-" .. p end
    if IsControlKeyDown() then p = "CTRL-" .. p end
    if IsShiftKeyDown()   then p = "SHIFT-" .. p end
    return p .. key
end

function L3F.SetupKeybindButton(btn, command)
    local listening = false

    local function refresh()
        if listening then return end
        local k = GetBindingKey(command)
        btn:SetText(k and (GetBindingText(k, "KEY_") or k) or "Not bound")
    end

    local function stop()
        listening = false
        btn:EnableKeyboard(false)
        btn:UnlockHighlight()
        refresh()
    end

    local function apply(key)
        local existing = GetBindingKey(command)
        while existing do
            SetBinding(existing)
            existing = GetBindingKey(command)
        end
        if key then SetBinding(key, command) end
        SaveBindings(GetCurrentBindingSet())
        stop()
    end

    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function(self)
        if listening then return end
        if InCombatLockdown() then
            print("|cffff5555L3FTools|r Can't change key bindings while in combat.")
            return
        end
        listening = true
        self:EnableKeyboard(true)
        self:LockHighlight()
        self:SetText("Press a key  (Esc = clear)")
    end)
    btn:SetScript("OnKeyDown", function(self, key)
        if not listening then return end
        if key == "ESCAPE" then apply(nil) return end
        local k = kbModified(key)
        if k then apply(k) end
    end)
    btn:SetScript("OnMouseDown", function(self, mb)
        if listening and KB_MOUSE[mb] then apply(kbModified(KB_MOUSE[mb])) end
    end)
    btn:SetScript("OnMouseWheel", function(self, delta)
        if listening then apply(kbModified(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")) end
    end)
    btn:SetScript("OnShow", refresh)
    btn:SetScript("OnEnter", function(self)
        if listening then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Hold-to-mark key")
        GameTooltip:AddLine("Click, then press a key. Hold that key and mouse over a mob to mark it - no target or click needed.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    refresh()
end

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

    -- Hold-to-mark keybind picker - click it, then press a key.
    local kbLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kbLabel:SetPoint("TOPLEFT", cb3, "BOTTOMLEFT", 4, -18)
    kbLabel:SetText("Hold-to-mark key:")

    local kbBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    kbBtn:SetSize(150, 22)
    kbBtn:SetPoint("LEFT", kbLabel, "RIGHT", 8, 0)
    L3F.SetupKeybindButton(kbBtn, "L3FTOOLS_MOUSEOVERMARK")

    -- Help text
    local help = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    help:SetPoint("TOPLEFT", kbLabel, "BOTTOMLEFT", -4, -20)
    help:SetWidth(560)
    help:SetJustifyH("LEFT")
    help:SetText(
        "|cffffd100Slash commands|r\n" ..
        "  /l3f                  open the window\n" ..
        "  /l3f automarker       open on Automarker tab\n" ..
        "  /l3f atlas            open on Atlas tab\n" ..
        "  /l3f settings         open on Settings tab\n" ..
        "  /l3f toggle           master Automarker enable on/off\n" ..
        "  /l3f minimap          hide/show the minimap button\n"
    )

    local version = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 16, 12)
    version:SetText("L3FTools v0.2.0 - Les Trois Fromages")
end

L3F.RegisterTab("settings", "Settings", nil, buildSettings)
