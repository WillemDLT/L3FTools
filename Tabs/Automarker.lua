-- =============================================================
-- L3FTools - Tabs/Automarker.lua
-- =============================================================
-- The Automarker priority editor.
-- Top: master enable + combat-lock + once-placed-lock toggles.
-- Mid: raid dropdown selector.
-- Below: scrollable list of NPCs with per-row:
--   * checkbox (enable/disable marking for this NPC)
--   * name label
--   * 8 priority mark icons (toggle on/off; dim = excluded)
-- =============================================================

local addonName, L3F = ...

local MARK_ORDER   = { 8, 7, 6, 5, 4, 3, 2, 1 }
local MARK_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local ROW_HEIGHT      = 22
local SECTION_HEIGHT  = 22
local SECTION_TOP_GAP = 6

local currentRaidName

local function inList(markIdx, list)
    for _, m in ipairs(list) do
        if m == markIdx then return true end
    end
    return false
end

local function togglePriorityMark(npc, markIdx, mapID, wingIdx)
    local current
    if mapID and wingIdx and L3F.GetWingPriority then
        current = L3F.GetWingPriority(npc, mapID, wingIdx)
    else
        current = L3F.effectivePriority(npc)
    end
    local hadIt = inList(markIdx, current)
    local newList = {}
    for _, m in ipairs(MARK_ORDER) do
        local include = (m == markIdx) and (not hadIt) or
                        (m ~= markIdx and inList(m, current))
        if include then table.insert(newList, m) end
    end
    -- mapID+wingIdx -> per-wing override store; otherwise the global store.
    if L3F.SetWingPriority then
        L3F.SetWingPriority(npc.id, newList, mapID, wingIdx)
    else
        L3F.db.automarker.markPriorities[npc.id] = newList
    end
    if L3F.SyncActiveProfile then L3F.SyncActiveProfile() end
end

-- =============================================================
-- STRING DIALOG - a fixed-size, draggable window with a scrolling
-- multi-line edit box, used for profile Export / Import. Replaces
-- the StaticPopup edit box, whose multi-line form auto-grows over
-- the dialog's own buttons once the text is long.
-- =============================================================
local stringDialog
local function getStringDialog()
    if stringDialog then return stringDialog end
    local d = CreateFrame("Frame", "L3FToolsStringDialog", UIParent, "BasicFrameTemplateWithInset")
    d:SetSize(440, 340)
    d:SetPoint("CENTER")
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)

    d.heading = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.heading:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -28)
    d.heading:SetPoint("TOPRIGHT", d, "TOPRIGHT", -14, -28)
    d.heading:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", "L3FToolsStringDialogScroll", d, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -48)
    scroll:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -34, 44)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetMaxLetters(0)
    edit:SetWidth(384)
    edit:SetScript("OnEscapePressed", function() d:Hide() end)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    d.edit = edit

    d.accept = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.accept:SetSize(110, 24)
    d.accept:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -16, 12)

    d.cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.cancel:SetSize(110, 24)
    d.cancel:SetPoint("RIGHT", d.accept, "LEFT", -8, 0)
    d.cancel:SetText("Cancel")
    d.cancel:SetScript("OnClick", function() d:Hide() end)

    tinsert(UISpecialFrames, "L3FToolsStringDialog")
    stringDialog = d
    return d
end

-- opts = { title, text, acceptText, showCancel, selectAll, onAccept }
function L3F.ShowStringDialog(opts)
    local d = getStringDialog()
    d.heading:SetText(opts.title or "")
    d.accept:SetText(opts.acceptText or "OK")
    d.accept:SetScript("OnClick", function()
        local txt = d.edit:GetText()
        d:Hide()
        if opts.onAccept then opts.onAccept(txt) end
    end)
    d.cancel:SetShown(opts.showCancel ~= false)
    d.edit:SetText(opts.text or "")
    d.edit:SetCursorPosition(0)
    if opts.selectAll then d.edit:HighlightText() end
    d:Show()
    d.edit:SetFocus()
end

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

local function buildAutomarker(parent)
    -- Forward-declared so the profile strip's applyProfile callback can call it
    -- before its real assignment further down in this function.
    local rebuild

    local toggleRow = CreateFrame("Frame", nil, parent)
    toggleRow:SetHeight(28)
    toggleRow:SetPoint("TOPLEFT",  parent, "TOPLEFT",  8, -8)
    toggleRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8)

    local cbEnable = CreateFrame("CheckButton", nil, toggleRow, "UICheckButtonTemplate")
    cbEnable:SetPoint("LEFT", toggleRow, "LEFT", 0, 0)
    cbEnable:SetSize(20, 20)
    cbEnable:SetChecked(L3F.db.automarker.enabled)
    cbEnable.text:SetText("  Enable Automarker")
    cbEnable:SetScript("OnClick", function(self)
        L3F.db.automarker.enabled = self:GetChecked()
        if L3F.UpdateSwitcher then L3F.UpdateSwitcher() end
    end)

    local cbCombat = CreateFrame("CheckButton", nil, toggleRow, "UICheckButtonTemplate")
    cbCombat:SetPoint("LEFT", cbEnable, "RIGHT", 110, 0)
    cbCombat:SetSize(20, 20)
    cbCombat:SetChecked(L3F.db.automarker.combatLock)
    cbCombat.text:SetText("  Combat lock")
    cbCombat:SetScript("OnClick", function(self) L3F.db.automarker.combatLock = self:GetChecked() end)

    local cbOnce = CreateFrame("CheckButton", nil, toggleRow, "UICheckButtonTemplate")
    cbOnce:SetPoint("LEFT", cbCombat, "RIGHT", 80, 0)
    cbOnce:SetSize(20, 20)
    cbOnce:SetChecked(L3F.db.automarker.oncePlacedLock)
    cbOnce.text:SetText("  Once-placed lock")
    cbOnce:SetScript("OnClick", function(self) L3F.db.automarker.oncePlacedLock = self:GetChecked() end)

    -- =========================================================
    -- HOLD-TO-MARK KEYBIND PICKER - click it, then press a key.
    -- The same key is the WoW binding (Esc > Key Bindings too).
    -- =========================================================
    local kbLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kbLabel:SetPoint("TOPLEFT", toggleRow, "BOTTOMLEFT", 4, -8)
    kbLabel:SetText("Hold-to-mark key:")

    local kbBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    kbBtn:SetSize(150, 22)
    kbBtn:SetPoint("LEFT", kbLabel, "RIGHT", 8, 0)
    L3F.SetupKeybindButton(kbBtn, "L3FTOOLS_MOUSEOVERMARK")

    -- =========================================================
    -- PROFILE STRIP: [Profile: dropdown] [Save As] [Delete] [Export] [Import]
    -- =========================================================
    local profLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profLabel:SetPoint("TOPLEFT", kbLabel, "BOTTOMLEFT", 0, -12)
    profLabel:SetText("Profile:")

    local profDD = CreateFrame("Frame", "L3FToolsAMProfileDD", parent, "UIDropDownMenuTemplate")
    profDD:SetPoint("LEFT", profLabel, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(profDD, 160)

    -- Forward-declared so the dropdown init function can reach applyProfile.
    local applyProfile, refreshProfileDD

    local function initProfDD(self, level)
        for _, name in ipairs(L3F.GetProfileNames()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = (name == L3F.db.automarker.activeProfile)
            info.func = function() applyProfile(name) end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    -- Re-run Initialize every refresh so saved/deleted/imported profiles
    -- appear in the dropdown immediately (some Classic builds cache otherwise).
    refreshProfileDD = function()
        UIDropDownMenu_Initialize(profDD, initProfDD)
        UIDropDownMenu_SetText(profDD, L3F.db.automarker.activeProfile or "(unsaved)")
    end

    applyProfile = function(name)
        local ok, msg = L3F.LoadProfile(name)
        if ok then
            print("|cffffd100L3FTools|r " .. msg)
            refreshProfileDD()
            rebuild()
        else
            print("|cffff5555L3FTools|r " .. msg)
        end
    end

    UIDropDownMenu_Initialize(profDD, initProfDD)

    local function mkBtn(label, anchor, x, width, onClick)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(width or 70, 22); b:SetText(label)
        b:SetPoint("LEFT", anchor, "RIGHT", x or 2, 0)
        b:SetScript("OnClick", onClick)
        return b
    end

    local saveBtn = mkBtn("Save As", profDD, -8, 70, function()
        StaticPopupDialogs["L3F_AM_SAVE"] = {
            text = "Save current config as profile:",
            button1 = "Save", button2 = "Cancel",
            hasEditBox = true, maxLetters = 32,
            OnAccept = function(self)
                local name = self.EditBox:GetText():gsub("^%s+",""):gsub("%s+$","")
                if name ~= "" then
                    local ok, msg = L3F.SaveProfile(name)
                    print("|cffffd100L3FTools|r " .. msg)
                    refreshProfileDD()
                end
            end,
            EditBoxOnEnterPressed = function(self) local b = self:GetParent().button1; if b then b:Click() end end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("L3F_AM_SAVE")
    end)

    local delBtn = mkBtn("Delete", saveBtn, 2, 60, function()
        local active = L3F.db.automarker.activeProfile
        if not active then
            print("|cffffd100L3FTools|r No profile selected.")
            return
        end
        StaticPopupDialogs["L3F_AM_DEL"] = {
            text = "Delete profile '" .. active .. "'? Cannot be undone.",
            button1 = "Delete", button2 = "Cancel",
            OnAccept = function()
                local ok, msg = L3F.DeleteProfile(active)
                print("|cffffd100L3FTools|r " .. msg)
                refreshProfileDD()
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("L3F_AM_DEL")
    end)

    local expBtn = mkBtn("Export", delBtn, 2, 60, function()
        local active = L3F.db.automarker.activeProfile
        local profile = active and L3F.db.automarker.profiles[active]
        if not profile then
            print("|cffffd100L3FTools|r Save the current config as a profile first.")
            return
        end
        -- Refresh the stored profile from live config so the export reflects
        -- the user's CURRENT state, not a stale snapshot (e.g. a profile
        -- saved before sectionMarks was tracked, never re-synced since).
        if L3F.SyncActiveProfile then L3F.SyncActiveProfile() end
        L3F.ShowStringDialog({
            title = "Profile export - Ctrl+A then Ctrl+C to copy:",
            text = L3F.SerializeProfile(active, profile),
            acceptText = "Close",
            showCancel = false,
            selectAll = true,
        })
    end)

    local impBtn = mkBtn("Import", expBtn, 2, 60, function()
        L3F.ShowStringDialog({
            title = "Paste a profile export string, then Import:",
            text = "",
            acceptText = "Import",
            showCancel = true,
            onAccept = function(str)
                local name, profile = L3F.DeserializeProfile(str)
                if not name then
                    print("|cffff5555L3FTools|r Import failed: " .. tostring(profile))
                    return
                end
                L3F.db.automarker.profiles[name] = profile
                applyProfile(name)
                print("|cffffd100L3FTools|r Imported '" .. name .. "'.")
            end,
        })
    end)

    refreshProfileDD()

    local raidLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", profDD, "BOTTOMLEFT", 16, -16)
    raidLabel:SetText("Raid:")

    local dropdown = CreateFrame("Frame", "L3FToolsAutomarkerRaidDropdown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", raidLabel, "RIGHT", 0, -2)

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     dropdown, "BOTTOMLEFT", 16, -8)
    scroll:SetPoint("BOTTOMRIGHT", parent,   "BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(800, 1)
    scroll:SetScrollChild(content)

    local rowPool = {}

    local function getRow(i)
        local row = rowPool[i]
        if row then return row end
        row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(true)

        row.checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.checkbox:SetSize(20, 20)
        row.checkbox:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.label:SetPoint("LEFT", row.checkbox, "RIGHT", 4, 0)
        row.label:SetWidth(220)
        row.label:SetJustifyH("LEFT")

        -- Hover handlers: show preview popup with model + spells + notes
        row:SetScript("OnEnter", function(self)
            if self.currentNPC and L3F.HoverPreview then
                L3F.HoverPreview:Show(self.currentNPC, self)
            end
        end)
        row:SetScript("OnLeave", function(self)
            if L3F.HoverPreview then L3F.HoverPreview:ScheduleHide() end
        end)

        row.markIcons = {}
        for j, _ in ipairs(MARK_ORDER) do
            local btn = CreateFrame("Button", nil, row)
            btn:SetSize(20, 20)
            btn:SetPoint("LEFT", row, "LEFT", 250 + (j - 1) * 22, 0)
            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            btn.tex = tex
            row.markIcons[j] = btn
        end
        rowPool[i] = row
        return row
    end

    local function getSectionHeader(i)
        local pool = content.sectionPool
        if not pool then pool = {}; content.sectionPool = pool end
        local s = pool[i]
        if s then return s end
        s = CreateFrame("Frame", nil, content)
        s:SetHeight(SECTION_HEIGHT)
        s.label = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        s.label:SetPoint("LEFT", s, "LEFT", 4, 0)
        s.label:SetTextColor(1, 0.82, 0)
        pool[i] = s
        return s
    end

    rebuild = function()
        for _, r in ipairs(rowPool) do r:Hide() end
        if content.sectionPool then for _, s in ipairs(content.sectionPool) do s:Hide() end end
        if not currentRaidName then return end
        local raid
        for _, r in ipairs(L3F.raids) do
            if r.name == currentRaidName then raid = r; break end
        end
        if not raid then return end

        local rowIdx, secIdx = 0, 0
        local y = 0

        local function renderRow(npc, mapID, wingIdx)
            rowIdx = rowIdx + 1
            local row = getRow(rowIdx)
            row:SetWidth(content:GetWidth() - 8)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
            row.currentNPC = npc  -- so the OnEnter hover-preview handler can pick it up
            row.label:SetText(npc.name)
            row.checkbox:SetChecked(L3F.db.automarker.enabledNPCs[npc.id] and true or false)
            row.checkbox:SetScript("OnClick", function(self)
                L3F.db.automarker.enabledNPCs[npc.id] = self:GetChecked() and true or nil
                if L3F.SyncActiveProfile then L3F.SyncActiveProfile() end
            end)
            local priority
            if mapID and wingIdx and L3F.GetWingPriority then
                priority = L3F.GetWingPriority(npc, mapID, wingIdx)
            else
                priority = L3F.effectivePriority(npc)
            end
            for i, markIdx in ipairs(MARK_ORDER) do
                local btn = row.markIcons[i]
                btn.tex:SetTexture(string.format(MARK_TEXTURE, markIdx))
                local isOn = inList(markIdx, priority)
                btn.tex:SetVertexColor(1, 1, 1, isOn and 1.0 or 0.25)
                btn:SetScript("OnClick", function()
                    togglePriorityMark(npc, markIdx, mapID, wingIdx)
                    rebuild()
                end)
            end
            row:Show()
            y = y + ROW_HEIGHT + 2
        end

        local function renderSection(name)
            secIdx = secIdx + 1
            local s = getSectionHeader(secIdx)
            s:SetWidth(content:GetWidth() - 8)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y - SECTION_TOP_GAP)
            s.label:SetText(name)
            s:Show()
            y = y + SECTION_HEIGHT + SECTION_TOP_GAP
        end

        local secDef = L3F.GetRaidSections and L3F.GetRaidSections(raid.name)
        if secDef then
            for wIdx, wing in ipairs(secDef.sections) do
                renderSection(wing.name)
                for _, ref in ipairs(wing.npcs) do
                    local npc = L3F.npcLookup[ref.id]
                    if npc then renderRow(npc, secDef.mapID, wIdx) end
                end
            end
        elseif raid.sections then
            for _, sec in ipairs(raid.sections) do
                renderSection(sec.name)
                for _, npc in ipairs(sec.npcs) do renderRow(npc) end
            end
        elseif raid.npcs then
            for _, npc in ipairs(raid.npcs) do renderRow(npc) end
        end
        content:SetHeight(math.max(y + 8, 1))
    end

    local function selectRaid(name)
        currentRaidName = name
        UIDropDownMenu_SetText(dropdown, name)
        rebuild()
    end

    local function initDropdown(self, level)
        for _, raid in ipairs(L3F.raids) do
            -- Automarker tab is raid-only. Heroic dungeons register via the
            -- same RegisterRaid call but are flat (no `sections` field) and
            -- belong to the Atlas tab.
            if raid.sections then
                local info = UIDropDownMenu_CreateInfo()
                info.text = raid.name
                info.func = function() selectRaid(raid.name) end
                info.checked = (raid.name == currentRaidName)
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end
    UIDropDownMenu_Initialize(dropdown, initDropdown)
    UIDropDownMenu_SetWidth(dropdown, 200)

    local initial = L3F.db.atlas.lastSelectedRaid
    local found, firstRaid
    for _, r in ipairs(L3F.raids) do
        if r.sections then
            firstRaid = firstRaid or r.name
            if r.name == initial then found = initial; break end
        end
    end
    selectRaid(found or firstRaid or "")
end

L3F.RegisterTab("automarker", "Automarker", nil, buildAutomarker)

L3F.RegisterTab("automarker", "Automarker", nil, buildAutomarker)
