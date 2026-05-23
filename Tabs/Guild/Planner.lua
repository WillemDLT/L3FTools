-- =============================================================
-- L3FTools - Tabs/Guild/Planner.lua
-- =============================================================
-- Spreadsheet-like guild planner:
--   * Cell editing
--   * Per-cell dropdown options
--   * Add row / add column
--   * Undo stack
--   * Text size + text color controls
--   * Merge / unmerge selected range
--   * Extra feature: quick duplicate selected row
-- =============================================================

local addonName, L3F = ...

local CELL_W = 96
local CELL_H = 24
local HEADER_W = 52
local HEADER_H = 20
local GRID_COLS_VISIBLE = 8
local GRID_ROWS_VISIBLE = 12

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function deepcopy(obj)
    if type(obj) ~= "table" then return obj end
    local out = {}
    for k, v in pairs(obj) do
        out[k] = deepcopy(v)
    end
    return out
end

local function splitCSV(text)
    local out = {}
    for token in (text or ""):gmatch("([^,]+)") do
        token = token:gsub("^%s+", ""):gsub("%s+$", "")
        if token ~= "" then out[#out + 1] = token end
    end
    return out
end

local function colLabel(col)
    local s = ""
    while col > 0 do
        local rem = (col - 1) % 26
        s = string.char(65 + rem) .. s
        col = math.floor((col - 1) / 26)
    end
    return s
end

local function makeDefaultState()
    local cells = {}
    for r = 1, 20 do
        cells[r] = {}
        for c = 1, 12 do
            cells[r][c] = {
                text = "",
                size = 12,
                color = { 1, 1, 1, 1 },
                dropdown = nil,
                mergedTo = nil,
                mergeSpan = nil,
            }
        end
    end
    return {
        rows = 20,
        cols = 12,
        cells = cells,
        viewRow = 1,
        viewCol = 1,
        selected = { row = 1, col = 1 },
        rangeEnd = nil,
        undo = {},
    }
end

local function ensureState()
    L3F.db.guildPlanner = L3F.db.guildPlanner or makeDefaultState()
    local p = L3F.db.guildPlanner
    p.rows = p.rows or 20
    p.cols = p.cols or 12
    p.cells = p.cells or {}
    p.viewRow = clamp(tonumber(p.viewRow or 1) or 1, 1, p.rows)
    p.viewCol = clamp(tonumber(p.viewCol or 1) or 1, 1, p.cols)
    p.selected = p.selected or { row = 1, col = 1 }
    p.undo = p.undo or {}

    for r = 1, p.rows do
        p.cells[r] = p.cells[r] or {}
        for c = 1, p.cols do
            p.cells[r][c] = p.cells[r][c] or {
                text = "",
                size = 12,
                color = { 1, 1, 1, 1 },
                dropdown = nil,
                mergedTo = nil,
                mergeSpan = nil,
            }
            local cell = p.cells[r][c]
            cell.text = cell.text or ""
            cell.size = tonumber(cell.size or 12) or 12
            cell.color = cell.color or { 1, 1, 1, 1 }
        end
    end
    return p
end

local function cellAt(p, row, col)
    if row < 1 or col < 1 or row > p.rows or col > p.cols then return nil end
    return p.cells[row] and p.cells[row][col] or nil
end

local function pushUndo(p)
    p.undo[#p.undo + 1] = {
        rows = p.rows,
        cols = p.cols,
        cells = deepcopy(p.cells),
        selected = deepcopy(p.selected),
        rangeEnd = deepcopy(p.rangeEnd),
    }
    if #p.undo > 30 then table.remove(p.undo, 1) end
end

local function getSelectionRect(p)
    local a = p.selected or { row = 1, col = 1 }
    local b = p.rangeEnd or a
    local r1 = math.min(a.row, b.row)
    local r2 = math.max(a.row, b.row)
    local c1 = math.min(a.col, b.col)
    local c2 = math.max(a.col, b.col)
    return r1, c1, r2, c2
end

local function clearMergeMarksInRect(p, r1, c1, r2, c2)
    for r = r1, r2 do
        for c = c1, c2 do
            local cell = cellAt(p, r, c)
            if cell then
                cell.mergedTo = nil
                cell.mergeSpan = nil
            end
        end
    end
end

local function addRow(p)
    pushUndo(p)
    local new = {}
    for c = 1, p.cols do
        new[c] = { text = "", size = 12, color = { 1, 1, 1, 1 }, dropdown = nil, mergedTo = nil, mergeSpan = nil }
    end
    p.rows = p.rows + 1
    p.cells[p.rows] = new
end

local function addCol(p)
    pushUndo(p)
    p.cols = p.cols + 1
    for r = 1, p.rows do
        p.cells[r][p.cols] = { text = "", size = 12, color = { 1, 1, 1, 1 }, dropdown = nil, mergedTo = nil, mergeSpan = nil }
    end
end

local function duplicateSelectedRow(p)
    local sr = clamp((p.selected and p.selected.row) or 1, 1, p.rows)
    pushUndo(p)
    local src = p.cells[sr]
    local copy = {}
    for c = 1, p.cols do copy[c] = deepcopy(src[c]) end
    table.insert(p.cells, sr + 1, copy)
    p.rows = p.rows + 1
    p.selected.row = sr + 1
end

local function buildPlanner(parent)
    local planner = ensureState()
    local ui = {}

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -12)
    title:SetText("Planner Sheet")

    local toolbar = CreateFrame("Frame", nil, parent)
    toolbar:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    toolbar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -40)
    toolbar:SetHeight(28)

    local function mkBtn(label, w, x)
        local b = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("LEFT", toolbar, "LEFT", x, 0)
        b:SetText(label)
        return b
    end

    local btnAddRow = mkBtn("+ Row", 62, 0)
    local btnAddCol = mkBtn("+ Col", 62, 68)
    local btnUndo = mkBtn("Undo", 62, 136)
    local btnMerge = mkBtn("Merge", 62, 204)
    local btnUnmerge = mkBtn("Unmerge", 66, 272)
    local btnDupRow = mkBtn("Dup Row", 74, 344)

    local ddLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ddLabel:SetPoint("LEFT", toolbar, "LEFT", 426, 0)
    ddLabel:SetText("Dropdown:")

    local ddInput = CreateFrame("EditBox", nil, toolbar, "InputBoxTemplate")
    ddInput:SetAutoFocus(false)
    ddInput:SetSize(170, 20)
    ddInput:SetPoint("LEFT", ddLabel, "RIGHT", 6, 0)
    ddInput:SetTextInsets(4, 4, 2, 2)

    local btnSetDD = mkBtn("Apply", 52, 612)

    local sizeLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sizeLabel:SetPoint("LEFT", btnSetDD, "RIGHT", 10, 0)
    sizeLabel:SetText("Size")

    local sizeSlider = CreateFrame("Slider", "L3FGuildPlannerSizeSlider", toolbar, "OptionsSliderTemplate")
    sizeSlider:SetPoint("LEFT", sizeLabel, "RIGHT", 2, 0)
    sizeSlider:SetWidth(110)
    sizeSlider:SetMinMaxValues(9, 22)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    _G[sizeSlider:GetName() .. "Low"]:SetText("9")
    _G[sizeSlider:GetName() .. "High"]:SetText("22")
    _G[sizeSlider:GetName() .. "Text"]:SetText("")

    local colorLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colorLabel:SetPoint("LEFT", sizeSlider, "RIGHT", 6, 0)
    colorLabel:SetText("Color")

    local colorBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    colorBtn:SetSize(54, 22)
    colorBtn:SetPoint("LEFT", colorLabel, "RIGHT", 6, 0)
    colorBtn:SetText("Pick")

    local host = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    host:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    host:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 14)
    host:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, tile = true, tileSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    host:SetBackdropColor(0.06, 0.06, 0.08, 0.92)

    local grid = CreateFrame("Frame", nil, host)
    grid:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -8)
    grid:SetSize(HEADER_W + GRID_COLS_VISIBLE * CELL_W, HEADER_H + GRID_ROWS_VISIBLE * CELL_H)

    local corner = CreateFrame("Frame", nil, grid, "BackdropTemplate")
    corner:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, 0)
    corner:SetSize(HEADER_W, HEADER_H)
    corner:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    corner:SetBackdropColor(0.2, 0.2, 0.22, 1)

    ui.colHeaders = {}
    for i = 1, GRID_COLS_VISIBLE do
        local f = CreateFrame("Frame", nil, grid, "BackdropTemplate")
        f:SetPoint("TOPLEFT", grid, "TOPLEFT", HEADER_W + (i - 1) * CELL_W, 0)
        f:SetSize(CELL_W - 1, HEADER_H)
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        f:SetBackdropColor(0.2, 0.2, 0.22, 1)
        f.t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.t:SetPoint("CENTER")
        ui.colHeaders[i] = f
    end

    ui.rowHeaders = {}
    for i = 1, GRID_ROWS_VISIBLE do
        local f = CreateFrame("Frame", nil, grid, "BackdropTemplate")
        f:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -HEADER_H - (i - 1) * CELL_H)
        f:SetSize(HEADER_W, CELL_H - 1)
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        f:SetBackdropColor(0.2, 0.2, 0.22, 1)
        f.t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.t:SetPoint("CENTER")
        ui.rowHeaders[i] = f
    end

    ui.cells = {}
    for vr = 1, GRID_ROWS_VISIBLE do
        ui.cells[vr] = {}
        for vc = 1, GRID_COLS_VISIBLE do
            local b = CreateFrame("Button", nil, grid, "BackdropTemplate")
            b:SetPoint("TOPLEFT", grid, "TOPLEFT",
                HEADER_W + (vc - 1) * CELL_W, -HEADER_H - (vr - 1) * CELL_H)
            b:SetSize(CELL_W - 1, CELL_H - 1)
            b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            b:SetBackdropColor(0.1, 0.1, 0.12, 1)
            b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.txt:SetPoint("LEFT", b, "LEFT", 4, 0)
            b.txt:SetPoint("RIGHT", b, "RIGHT", -4, 0)
            b.txt:SetJustifyH("LEFT")
            b.txt:SetWordWrap(false)
            b.txt:SetText("")
            ui.cells[vr][vc] = b
        end
    end

    local vScroll = CreateFrame("Slider", nil, host, "UIPanelScrollBarTemplate")
    vScroll:SetPoint("TOPRIGHT", host, "TOPRIGHT", -6, -28)
    vScroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -6, 24)
    vScroll:SetWidth(16)
    vScroll:SetMinMaxValues(1, 1)
    vScroll:SetValueStep(1)
    vScroll:SetObeyStepOnDrag(true)

    local hScroll = CreateFrame("Slider", "L3FGuildPlannerHScroll", host, "OptionsSliderTemplate")
    hScroll:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 40, 8)
    hScroll:SetWidth(240)
    hScroll:SetMinMaxValues(1, 1)
    hScroll:SetValueStep(1)
    hScroll:SetObeyStepOnDrag(true)
    _G[hScroll:GetName() .. "Low"]:SetText("Col")
    _G[hScroll:GetName() .. "High"]:SetText("")
    _G[hScroll:GetName() .. "Text"]:SetText("")

    local menuFrame = CreateFrame("Frame", "L3FGuildPlannerDropdownMenu", UIParent, "UIDropDownMenuTemplate")

    local editor = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editor:SetAutoFocus(false)
    editor:Hide()
    editor:SetScript("OnEnterPressed", function(self)
        local row, col = self.row, self.col
        local cell = cellAt(planner, row, col)
        if cell then
            pushUndo(planner)
            cell.text = self:GetText() or ""
        end
        self:Hide()
        ui.refresh()
    end)
    editor:SetScript("OnEscapePressed", function(self) self:Hide() end)
    editor:SetScript("OnEditFocusLost", function(self) self:Hide() end)

    function ui.refresh()
        local maxRowStart = math.max(1, planner.rows - GRID_ROWS_VISIBLE + 1)
        local maxColStart = math.max(1, planner.cols - GRID_COLS_VISIBLE + 1)
        planner.viewRow = clamp(planner.viewRow, 1, maxRowStart)
        planner.viewCol = clamp(planner.viewCol, 1, maxColStart)

        vScroll:SetMinMaxValues(1, maxRowStart)
        vScroll:SetValue(planner.viewRow)
        hScroll:SetMinMaxValues(1, maxColStart)
        hScroll:SetValue(planner.viewCol)

        for i = 1, GRID_COLS_VISIBLE do
            local c = planner.viewCol + i - 1
            ui.colHeaders[i].t:SetText(colLabel(c))
        end
        for i = 1, GRID_ROWS_VISIBLE do
            local r = planner.viewRow + i - 1
            ui.rowHeaders[i].t:SetText(tostring(r))
        end

        local sr1, sc1, sr2, sc2 = getSelectionRect(planner)

        for vr = 1, GRID_ROWS_VISIBLE do
            for vc = 1, GRID_COLS_VISIBLE do
                local r = planner.viewRow + vr - 1
                local c = planner.viewCol + vc - 1
                local btn = ui.cells[vr][vc]
                local cell = cellAt(planner, r, c)
                if not cell or cell.mergedTo then
                    btn:Hide()
                else
                    btn:Show()
                    local span = cell.mergeSpan
                    local w = CELL_W - 1
                    local h = CELL_H - 1
                    if span then
                        w = CELL_W * span.cols - 1
                        h = CELL_H * span.rows - 1
                    end
                    btn:SetSize(w, h)
                    btn:SetPoint("TOPLEFT", grid, "TOPLEFT",
                        HEADER_W + (vc - 1) * CELL_W, -HEADER_H - (vr - 1) * CELL_H)
                    btn.txt:SetText(cell.text or "")
                    local fontPath = "Fonts\\FRIZQT__.TTF"
                    btn.txt:SetFont(fontPath, cell.size or 12, "")
                    local cr, cg, cb, ca = 1, 1, 1, 1
                    if cell.color then cr, cg, cb, ca = unpack(cell.color) end
                    btn.txt:SetTextColor(cr, cg, cb, ca)

                    local inSel = r >= sr1 and r <= sr2 and c >= sc1 and c <= sc2
                    if inSel then
                        btn:SetBackdropColor(0.18, 0.28, 0.45, 0.95)
                    else
                        btn:SetBackdropColor(0.1, 0.1, 0.12, 1)
                    end
                end
            end
        end
    end

    local function selectCell(r, c, extend)
        planner.selected = planner.selected or { row = r, col = c }
        if extend then
            planner.rangeEnd = { row = r, col = c }
        else
            planner.selected.row = r
            planner.selected.col = c
            planner.rangeEnd = nil
        end
    end

    for vr = 1, GRID_ROWS_VISIBLE do
        for vc = 1, GRID_COLS_VISIBLE do
            local b = ui.cells[vr][vc]
            b:SetScript("OnClick", function(self, button)
                local r = planner.viewRow + vr - 1
                local c = planner.viewCol + vc - 1
                local cell = cellAt(planner, r, c)
                if not cell then return end
                if IsShiftKeyDown() then
                    selectCell(r, c, true)
                    ui.refresh()
                    return
                end
                selectCell(r, c, false)
                ui.refresh()

                if button == "RightButton" and cell.dropdown and #cell.dropdown > 0 then
                    local menu = {}
                    for _, opt in ipairs(cell.dropdown) do
                        menu[#menu + 1] = {
                            text = opt,
                            notCheckable = true,
                            func = function()
                                pushUndo(planner)
                                cell.text = opt
                                ui.refresh()
                            end
                        }
                    end
                    EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
                    return
                end

                editor:SetParent(parent)
                editor:ClearAllPoints()
                editor:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
                editor:SetSize(self:GetWidth() - 2, self:GetHeight() - 2)
                editor:SetText(cell.text or "")
                editor.row = r
                editor.col = c
                editor:Show()
                editor:SetFocus()
                editor:HighlightText()
            end)
        end
    end

    vScroll:SetScript("OnValueChanged", function(_, v)
        planner.viewRow = math.floor(v + 0.5)
        ui.refresh()
    end)
    hScroll:SetScript("OnValueChanged", function(_, v)
        planner.viewCol = math.floor(v + 0.5)
        ui.refresh()
    end)

    btnAddRow:SetScript("OnClick", function() addRow(planner); ui.refresh() end)
    btnAddCol:SetScript("OnClick", function() addCol(planner); ui.refresh() end)
    btnDupRow:SetScript("OnClick", function() duplicateSelectedRow(planner); ui.refresh() end)

    btnUndo:SetScript("OnClick", function()
        local prev = table.remove(planner.undo)
        if not prev then return end
        planner.rows = prev.rows
        planner.cols = prev.cols
        planner.cells = prev.cells
        planner.selected = prev.selected
        planner.rangeEnd = prev.rangeEnd
        ui.refresh()
    end)

    btnSetDD:SetScript("OnClick", function()
        local sr = planner.selected
        if not sr then return end
        local cell = cellAt(planner, sr.row, sr.col)
        if not cell then return end
        pushUndo(planner)
        local list = splitCSV(ddInput:GetText() or "")
        cell.dropdown = (#list > 0) and list or nil
        ui.refresh()
    end)

    sizeSlider:SetScript("OnValueChanged", function(_, v)
        local r1, c1, r2, c2 = getSelectionRect(planner)
        pushUndo(planner)
        for r = r1, r2 do
            for c = c1, c2 do
                local cell = cellAt(planner, r, c)
                if cell then cell.size = math.floor(v + 0.5) end
            end
        end
        ui.refresh()
    end)

    colorBtn:SetScript("OnClick", function()
        local sr = planner.selected
        if not sr then return end
        local cell = cellAt(planner, sr.row, sr.col)
        if not cell then return end
        local r, g, b = 1, 1, 1
        if cell.color then r, g, b = cell.color[1] or 1, cell.color[2] or 1, cell.color[3] or 1 end
        local function commit(restore)
            pushUndo(planner)
            local cr, cg, cb
            if restore then
                cr, cg, cb = ColorPickerFrame:GetPreviousValues()
            else
                cr, cg, cb = ColorPickerFrame:GetColorRGB()
            end
            local r1, c1, r2, c2 = getSelectionRect(planner)
            for rr = r1, r2 do
                for cc = c1, c2 do
                    local target = cellAt(planner, rr, cc)
                    if target then target.color = { cr, cg, cb, 1 } end
                end
            end
            ui.refresh()
        end
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = function() commit(false) end
        ColorPickerFrame.cancelFunc = function() commit(true) end
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Show()
    end)

    btnMerge:SetScript("OnClick", function()
        local r1, c1, r2, c2 = getSelectionRect(planner)
        if r1 == r2 and c1 == c2 then return end
        pushUndo(planner)
        clearMergeMarksInRect(planner, r1, c1, r2, c2)
        local root = cellAt(planner, r1, c1)
        if root then
            root.mergeSpan = { rows = (r2 - r1 + 1), cols = (c2 - c1 + 1) }
            for r = r1, r2 do
                for c = c1, c2 do
                    if not (r == r1 and c == c1) then
                        local cell = cellAt(planner, r, c)
                        if cell then cell.mergedTo = { row = r1, col = c1 } end
                    end
                end
            end
        end
        ui.refresh()
    end)

    btnUnmerge:SetScript("OnClick", function()
        local sr = planner.selected
        if not sr then return end
        local cell = cellAt(planner, sr.row, sr.col)
        if not cell then return end
        local rr, cc = sr.row, sr.col
        if cell.mergedTo then
            rr, cc = cell.mergedTo.row, cell.mergedTo.col
            cell = cellAt(planner, rr, cc)
            if not cell then return end
        end
        local span = cell.mergeSpan
        if not span then return end
        pushUndo(planner)
        clearMergeMarksInRect(planner, rr, cc, rr + span.rows - 1, cc + span.cols - 1)
        ui.refresh()
    end)

    sizeSlider:SetValue(12)
    ui.refresh()
end

L3F.RegisterTab("guild.planner", "Planner", nil, buildPlanner, { parent = "guild" })
