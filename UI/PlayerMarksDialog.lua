-- =============================================================
-- L3FTools - UI/PlayerMarksDialog.lua
-- =============================================================
-- Manager popup for sticky per-player marks.
--
-- The top half lists current assignments (one row each, with a
-- Remove button). The bottom half is the Add panel: player
-- dropdown (current group members) + 8 mark icons + Assign button.
-- Already-assigned marks in the picker are dimmed and tooltipped
-- with the current holder, so no popup-warning is needed.
--
-- Data lives in L3F.db.automarker.playerMarks. The Engine.lua API
-- (L3F.SetPlayerMark / L3F.ClearPlayerMark / L3F.ApplyPlayerMarks)
-- handles the storage and the actual SetRaidTarget calls; this file
-- only paints UI and dispatches to those.
-- =============================================================

local addonName, L3F = ...

local MARK_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local MARK_NAME = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

local function getMarks()
    return (L3F.db and L3F.db.automarker and L3F.db.automarker.playerMarks) or {}
end


-- =============================================================
-- Dialog factory (lazy)
-- =============================================================
local dialog
local function buildDialog()
    if dialog then return dialog end

    local d = CreateFrame("Frame", "L3FToolsPlayerMarksDialog", UIParent, "BasicFrameTemplateWithInset")
    d:SetSize(460, 380)
    d:SetPoint("CENTER")
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d.TitleText:SetText("Player marks")

    -- Help text
    local help = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -32)
    help:SetPoint("TOPRIGHT", d, "TOPRIGHT", -14, -32)
    help:SetHeight(30)
    help:SetJustifyH("LEFT")
    help:SetJustifyV("TOP")
    help:SetText("Sticky marks survive Clear All Marks. The Automarker will not use these marks on NPCs.")

    -- Scrollable list of current assignments
    local scroll = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -68)
    scroll:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -36, 158)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(380, 200)
    scroll:SetScrollChild(content)

    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER", content, "CENTER", 0, 0)
    empty:SetText("(no player marks assigned)")

    -- Add panel
    local addLabel = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    addLabel:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 14, 116)
    addLabel:SetText("Add player mark:")

    local playerDD = CreateFrame("Frame", "L3FToolsPMDropdown", d, "UIDropDownMenuTemplate")
    playerDD:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(playerDD, 140)

    -- Mark picker row of 8 icons
    local markRow = CreateFrame("Frame", nil, d)
    markRow:SetPoint("LEFT", playerDD, "RIGHT", 4, 4)
    markRow:SetSize(8 * 26, 24)
    local markIcons = {}
    for i = 1, 8 do
        local btn = CreateFrame("Button", nil, markRow)
        btn:SetSize(24, 24)
        btn:SetPoint("LEFT", markRow, "LEFT", (i - 1) * 26, 0)
        btn.tex = btn:CreateTexture(nil, "ARTWORK")
        btn.tex:SetAllPoints()
        btn.tex:SetTexture(string.format(MARK_ICON, i))
        btn.sel = btn:CreateTexture(nil, "OVERLAY")
        btn.sel:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
        btn.sel:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
        btn.sel:SetColorTexture(1, 0.85, 0, 0.35)
        btn.sel:Hide()
        markIcons[i] = btn
    end

    -- Assign button
    local assignBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    assignBtn:SetSize(120, 22)
    assignBtn:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 14, 50)
    assignBtn:SetText("Assign mark")

    -- Status line (warns / informs in place of a popup)
    local statusLine = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLine:SetPoint("LEFT", assignBtn, "RIGHT", 12, 0)
    statusLine:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    statusLine:SetJustifyH("LEFT")
    statusLine:SetText("")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -14, 14)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() d:Hide() end)

    -- =========================================================
    -- State + render
    -- =========================================================
    d.selectedPlayer = nil
    d.selectedMark = nil

    local rowPool = {}
    local function getRow(i)
        local r = rowPool[i]
        if r then return r end
        r = CreateFrame("Frame", nil, content)
        r:SetHeight(24)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(20, 20)
        r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.remove = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.remove:SetSize(72, 20)
        r.remove:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        r.remove:SetText("Remove")
        rowPool[i] = r
        return r
    end

    local function clearPickerSelection()
        d.selectedMark = nil
        for _, b in ipairs(markIcons) do b.sel:Hide() end
    end

    local function refresh()
        local marks = getMarks()
        -- Hide previous rows; rebuild
        for _, r in ipairs(rowPool) do r:Hide() end
        local sorted = {}
        for n in pairs(marks) do table.insert(sorted, n) end
        table.sort(sorted)
        empty:SetShown(#sorted == 0)

        local y = 0
        for i, name in ipairs(sorted) do
            local r = getRow(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            r:SetWidth(content:GetWidth())
            r.icon:SetTexture(string.format(MARK_ICON, marks[name]))
            r.label:SetText(name .. "  -  " .. (MARK_NAME[marks[name]] or "?"))
            r.remove:SetScript("OnClick", function()
                if L3F.ClearPlayerMark then L3F.ClearPlayerMark(name) end
                refresh()
            end)
            r:Show()
            y = y + 26
        end
        content:SetHeight(math.max(y + 8, 1))

        -- Mark picker state: dim icons already held by another player.
        for i, btn in ipairs(markIcons) do
            local holder
            for n, m in pairs(marks) do
                if m == i and n ~= d.selectedPlayer then holder = n; break end
            end
            if holder then
                btn.tex:SetVertexColor(1, 1, 1, 0.30)
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(MARK_NAME[i] .. " - already on " .. holder)
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                btn:SetScript("OnClick", nil)
                if d.selectedMark == i then clearPickerSelection() end
            else
                btn.tex:SetVertexColor(1, 1, 1, 1.0)
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(MARK_NAME[i])
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                btn:SetScript("OnClick", function()
                    d.selectedMark = i
                    for j, b in ipairs(markIcons) do b.sel:SetShown(j == i) end
                    statusLine:SetText("")
                end)
            end
        end
    end
    d.refresh = refresh

    -- Player dropdown: lists self + raid/party members.
    local function initDropdown()
        local seen = {}
        local function add(name)
            if not name or name == "" or seen[name] then return end
            seen[name] = true
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = (name == d.selectedPlayer)
            info.func = function()
                d.selectedPlayer = name
                UIDropDownMenu_SetText(playerDD, name)
                refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
        add(UnitName("player"))
        if IsInRaid() then
            for i = 1, 40 do
                local u = "raid" .. i
                if UnitExists(u) then add(UnitName(u)) end
            end
        elseif IsInGroup() then
            for i = 1, 4 do
                local u = "party" .. i
                if UnitExists(u) then add(UnitName(u)) end
            end
        end
    end
    UIDropDownMenu_Initialize(playerDD, initDropdown)

    -- Assign button
    assignBtn:SetScript("OnClick", function()
        if not d.selectedPlayer then
            statusLine:SetText("|cffff9999Pick a player first.|r")
            return
        end
        if not d.selectedMark then
            statusLine:SetText("|cffff9999Pick a mark first.|r")
            return
        end
        if L3F.SetPlayerMark then
            local ok, err = L3F.SetPlayerMark(d.selectedPlayer, d.selectedMark)
            if ok then
                statusLine:SetText(string.format("|cff99ff99%s -> %s|r",
                    d.selectedPlayer, MARK_NAME[d.selectedMark] or "?"))
                clearPickerSelection()
            else
                statusLine:SetText("|cffff5555" .. (err or "Failed") .. "|r")
            end
        end
        refresh()
    end)

    -- Re-init dropdown each show (raid composition may have changed).
    d:HookScript("OnShow", function()
        UIDropDownMenu_Initialize(playerDD, initDropdown)
        UIDropDownMenu_SetText(playerDD, d.selectedPlayer or "Select player")
        statusLine:SetText("")
        refresh()
    end)

    tinsert(UISpecialFrames, "L3FToolsPlayerMarksDialog")
    dialog = d
    return d
end


-- =============================================================
-- Public entry points
-- =============================================================
function L3F.ShowPlayerMarksDialog()
    local d = buildDialog()
    d:Show()
end

-- Public alias matching the slash-command verb naming.
function L3F.TogglePlayerMarksDialog()
    local d = buildDialog()
    if d:IsShown() then d:Hide() else d:Show() end
end
