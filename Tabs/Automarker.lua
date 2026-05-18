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

local function togglePriorityMark(npc, markIdx)
    local current = L3F.effectivePriority(npc)
    local hadIt = inList(markIdx, current)
    local newList = {}
    for _, m in ipairs(MARK_ORDER) do
        local include = (m == markIdx) and (not hadIt) or
                        (m ~= markIdx and inList(m, current))
        if include then table.insert(newList, m) end
    end
    L3F.db.automarker.markPriorities[npc.id] = newList
    if L3F.SyncActiveProfile then L3F.SyncActiveProfile() end
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
    cbEnable:SetScript("OnClick", function(self) L3F.db.automarker.enabled = self:GetChecked() end)

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
    -- PROFILE STRIP: [Profile: dropdown] [Save As] [Delete] [Export] [Import]
    -- =========================================================
    local profLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profLabel:SetPoint("TOPLEFT", toggleRow, "BOTTOMLEFT", 4, -10)
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
                local name = self.editBox:GetText():gsub("^%s+",""):gsub("%s+$","")
                if name ~= "" then
                    local ok, msg = L3F.SaveProfile(name)
                    print("|cffffd100L3FTools|r " .. msg)
                    refreshProfileDD()
                end
            end,
            EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
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
        local str = L3F.SerializeProfile(active, profile)
        StaticPopupDialogs["L3F_AM_EXP"] = {
            text = "Profile export (Ctrl+A, Ctrl+C):",
            button1 = "Close", hasEditBox = true, maxLetters = 0,
            OnShow = function(self)
                self.editBox:SetMultiLine(true)
                self.editBox:SetText(str)
                self.editBox:HighlightText()
                self.editBox:SetFocus()
            end,
            EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("L3F_AM_EXP")
    end)

    local impBtn = mkBtn("Import", expBtn, 2, 60, function()
        StaticPopupDialogs["L3F_AM_IMP"] = {
            text = "Paste profile export string:",
            button1 = "Import", button2 = "Cancel",
            hasEditBox = true, maxLetters = 0,
            OnShow = function(self) self.editBox:SetText(""); self.editBox:SetFocus() end,
            OnAccept = function(self)
                local str = self.editBox:GetText()
                local name, profile = L3F.DeserializeProfile(str)
                if not name then
                    print("|cffff5555L3FTools|r Import failed: " .. tostring(profile))
                    return
                end
                L3F.db.automarker.profiles[name] = profile
                applyProfile(name)
                print("|cffffd100L3FTools|r Imported '" .. name .. "'.")
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("L3F_AM_IMP")
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

        local function renderRow(npc)
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
            local priority = L3F.effectivePriority(npc)
            for i, markIdx in ipairs(MARK_ORDER) do
                local btn = row.markIcons[i]
                btn.tex:SetTexture(string.format(MARK_TEXTURE, markIdx))
                local isOn = inList(markIdx, priority)
                btn.tex:SetVertexColor(1, 1, 1, isOn and 1.0 or 0.25)
                btn:SetScript("OnClick", function()
                    togglePriorityMark(npc, markIdx)
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

        if raid.sections then
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
            local info = UIDropDownMenu_CreateInfo()
            info.text = raid.name
            info.func = function() selectRaid(raid.name) end
            info.checked = (raid.name == currentRaidName)
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(dropdown, initDropdown)
    UIDropDownMenu_SetWidth(dropdown, 200)

    local initial = L3F.db.atlas.lastSelectedRaid
    local found
    for _, r in ipairs(L3F.raids) do if r.name == initial then found = initial; break end end
    selectRaid(found or (L3F.raids[1] and L3F.raids[1].name) or "")
end

L3F.RegisterTab("automarker", "Automarker", nil, buildAutomarker)
    local found
    for _, r in ipairs(L3F.raids) do if r.name == initial then found = initial; break end end
    selectRaid(found or (L3F.raids[1] and L3F.raids[1].name) or "")
end

L3F.RegisterTab("automarker", "Automarker", nil, buildAutomarker)
