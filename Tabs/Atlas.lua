-- =============================================================
-- L3FTools - Tabs/Atlas.lua
-- =============================================================
-- Three-pane Atlas: [Tree + search] | [NPC list] | [Detail].
--
-- Left pane:
--   * Search box at top - GLOBAL search across every raid + heroic.
--   * Collapsible tree: Categories ("Raids", "Heroic Dungeons") with
--     raids as children, wings as grandchildren under each raid.
--   * Wings stay collapsed by default so the tree shows a tidy
--     overview instead of spamming every wing at first sight.
--
-- Middle pane:
--   * Search non-empty -> flat list of matches across the whole atlas,
--     each row showing a small "Wing - Raid" location line.
--   * Wing selected     -> just that wing's NPCs (no header - the
--                          wing name is already in the tree).
--   * Raid selected     -> the raid's NPCs grouped by wing with headers.
--   * Heroic selected   -> the dungeon's NPCs.
--
-- Right pane: model + sub-tabs (Spells / Notes / Drops / Location / Lore).
-- Drops sub-tab shows the item icon, name (coloured by quality) and chance.
-- =============================================================

local addonName, L3F = ...

local SUB_TABS = { "spells", "notes", "drops", "location", "lore" }
local SUB_TAB_LABELS = {
    spells = "Spells", notes = "Notes", drops = "Drops",
    location = "Location", lore = "Lore",
}

local CAT_RAIDS   = "Raids"
local CAT_HEROICS = "Heroic Dungeons"

local treePane, listPane, detailPane
local treeList, npcList, searchBox
local currentNPC
local subTabButtons = {}
local subTabContent
local viewer, npcTitle, npcMeta


-- =============================================================
-- ITEM INFO ASYNC CACHE  (icon + quality colour for drop rows)
-- =============================================================
-- GetItemInfo is async: it returns nil for an uncached item, then the
-- data arrives via GET_ITEM_INFO_RECEIVED. Apply the texture/colour
-- immediately if cached, otherwise queue and reapply when the event
-- fires.
local pendingItem = {}
local itemInfoFrame = CreateFrame("Frame")
itemInfoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

local function applyItemUI(itemID, label, icon)
    local _, _, quality, _, _, _, _, _, _, tex = GetItemInfo(itemID)
    if label and quality then
        local r, g, b = GetItemQualityColor(quality)
        label:SetTextColor(r, g, b)
    end
    if icon and tex then
        icon:SetTexture(tex)
    end
    return quality ~= nil and (icon == nil or tex ~= nil)
end

local function queueItemUI(itemID, label, icon)
    if not itemID then return end
    if applyItemUI(itemID, label, icon) then return end
    pendingItem[itemID] = pendingItem[itemID] or {}
    table.insert(pendingItem[itemID], { label = label, icon = icon })
end

itemInfoFrame:SetScript("OnEvent", function(_, _, itemID)
    local list = pendingItem[itemID]
    if not list then return end
    pendingItem[itemID] = nil
    for _, p in ipairs(list) do applyItemUI(itemID, p.label, p.icon) end
end)


-- =============================================================
-- TREE STATE  (persisted in L3F.db.atlas)
-- =============================================================
local function ensureState()
    L3F.db.atlas.tree = L3F.db.atlas.tree or {}
    L3F.db.atlas.tree.expanded = L3F.db.atlas.tree.expanded or { ["cat:" .. CAT_RAIDS] = true }
    -- Migrate the older single-raid selection into the new node-key model.
    if not L3F.db.atlas.selected then
        if L3F.db.atlas.lastSelectedRaid then
            L3F.db.atlas.selected = "raid:" .. L3F.db.atlas.lastSelectedRaid
        end
    end
end

local function isExpanded(key)
    ensureState()
    return L3F.db.atlas.tree.expanded[key] and true or false
end

local function setExpanded(key, val)
    ensureState()
    L3F.db.atlas.tree.expanded[key] = val and true or nil
end

local function isSelected(key)
    return L3F.db.atlas.selected == key
end

local function selectKey(key)
    L3F.db.atlas.selected = key
end


-- =============================================================
-- RAID HELPERS
-- =============================================================
local function categorizeRaids()
    local raids, heroics = {}, {}
    for _, r in ipairs(L3F.raids) do
        if r.sections then table.insert(raids, r) else table.insert(heroics, r) end
    end
    return raids, heroics
end

local function findRaid(name)
    for _, r in ipairs(L3F.raids) do
        if r.name == name then return r end
    end
end

-- Boss heuristic: raid data files use TRASH (the 8-entry {8,7,6,5,4,3,2,1}
-- priority list) for filler mobs and a short specific mark list ({8}, {7},
-- {8,7,6,5,4}, ...) for named encounters. Anything shorter than 8 marks
-- is a boss / named NPC. Players hunt bosses far more than trash, so this
-- is what powers the BOSSES/TRASH split + gold tint in the list pane.
local function isBoss(npc)
    return npc.marks and #npc.marks > 0 and #npc.marks < 8
end


-- =============================================================
-- TREE PANE
-- =============================================================
local function buildTreePane(parent)
    treePane = CreateFrame("Frame", nil, parent)
    treePane:SetPoint("TOPLEFT",    parent, "TOPLEFT",    0, 0)
    treePane:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    treePane:SetWidth(200)
    local bg = treePane:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.18)

    -- SEARCH BOX (global - filters the NPC list across every raid + heroic).
    searchBox = CreateFrame("EditBox", nil, treePane, "InputBoxTemplate")
    searchBox:SetSize(176, 22)
    searchBox:SetPoint("TOPLEFT", treePane, "TOPLEFT", 14, -8)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    placeholder:SetText("Search all NPCs...")
    searchBox:HookScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        if L3F.RefreshNPCList then L3F.RefreshNPCList() end
    end)
    searchBox:HookScript("OnEditFocusGained", function() placeholder:SetText("") end)
    searchBox:HookScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then placeholder:SetText("Search all NPCs...") end
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)

    local treeScroll = CreateFrame("ScrollFrame", nil, treePane, "UIPanelScrollFrameTemplate")
    treeScroll:SetPoint("TOPLEFT",     searchBox, "BOTTOMLEFT",  0, -6)
    treeScroll:SetPoint("BOTTOMRIGHT", treePane,  "BOTTOMRIGHT", -20, 6)
    treeList = CreateFrame("Frame", nil, treeScroll)
    treeList:SetSize(170, 1)
    treeScroll:SetScrollChild(treeList)

    -- ---------------------------------------------------------
    -- Row builder. Returns a Button that lays itself out at (indent, y).
    -- opts = {
    --   indent, y, key, label,
    --   font          (default GameFontNormalSmall),
    --   hasArrow      (bool; expandable row)
    --   expanded      (bool; arrow direction)
    --   onClickRow    (called when row is clicked)
    -- }
    -- ---------------------------------------------------------
    local function addRow(opts)
        local row = CreateFrame("Button", nil, treeList)
        row:SetSize(170 - opts.indent, 18)
        row:SetPoint("TOPLEFT", treeList, "TOPLEFT", opts.indent, -opts.y)

        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        local active = isSelected(opts.key)
        rbg:SetColorTexture(
            active and 0.30 or 0,
            active and 0.65 or 0,
            active and 1.0  or 0,
            active and 0.25 or 0)

        local textX = 4
        if opts.hasArrow then
            local arrow = row:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(12, 12)
            arrow:SetPoint("LEFT", row, "LEFT", 2, 0)
            arrow:SetTexture(opts.expanded
                and "Interface\\Buttons\\UI-MinusButton-Up"
                or  "Interface\\Buttons\\UI-PlusButton-Up")
            textX = 16
        end

        local txt = row:CreateFontString(nil, "OVERLAY", opts.font or "GameFontNormalSmall")
        txt:SetPoint("LEFT", row, "LEFT", textX, 0)
        txt:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        txt:SetJustifyH("LEFT")
        txt:SetText(opts.label)
        txt:SetTextColor(active and 1 or 0.85, active and 1 or 0.85, active and 1 or 0.85, 1)

        row:SetScript("OnClick", opts.onClickRow)
        row:SetScript("OnEnter", function()
            if not isSelected(opts.key) then rbg:SetColorTexture(1, 1, 1, 0.07) end
        end)
        row:SetScript("OnLeave", function()
            if isSelected(opts.key) then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
            else rbg:SetColorTexture(0, 0, 0, 0) end
        end)
        return row
    end

    -- ---------------------------------------------------------
    -- L3F.RefreshTree - rebuild the tree DOM. Cheap enough to call
    -- on every expand toggle / selection change (a few dozen rows).
    -- ---------------------------------------------------------
    L3F.RefreshTree = function()
        for _, c in ipairs({treeList:GetChildren()}) do c:Hide(); c:SetParent(nil) end

        local y = 0
        local raids, heroics = categorizeRaids()

        -- RAIDS category --------------------------------------
        local catRaidsKey   = "cat:" .. CAT_RAIDS
        local raidsExpanded = isExpanded(catRaidsKey)
        addRow{
            indent = 0, y = y,
            key = catRaidsKey, label = CAT_RAIDS,
            font = "GameFontNormal",
            hasArrow = true, expanded = raidsExpanded,
            onClickRow = function()
                setExpanded(catRaidsKey, not raidsExpanded)
                L3F.RefreshTree()
            end,
        }
        y = y + 20

        if raidsExpanded then
            for _, raid in ipairs(raids) do
                local raidKey = "raid:" .. raid.name
                local raidExpanded = isExpanded(raidKey)
                addRow{
                    indent = 16, y = y,
                    key = raidKey, label = raid.name,
                    font = "GameFontNormalSmall",
                    hasArrow = true, expanded = raidExpanded,
                    onClickRow = function()
                        setExpanded(raidKey, not raidExpanded)
                        selectKey(raidKey)
                        L3F.RefreshTree()
                        L3F.RefreshNPCList()
                    end,
                }
                y = y + 20

                if raidExpanded then
                    for wIdx, wing in ipairs(raid.sections) do
                        local wingKey = "wing:" .. raid.name .. "/" .. wIdx
                        addRow{
                            indent = 32, y = y,
                            key = wingKey, label = wing.name,
                            font = "GameFontHighlightSmall",
                            hasArrow = false,
                            onClickRow = function()
                                selectKey(wingKey)
                                L3F.RefreshTree()
                                L3F.RefreshNPCList()
                            end,
                        }
                        y = y + 18
                    end
                end
            end
        end

        -- HEROIC DUNGEONS category ----------------------------
        local catHeroKey   = "cat:" .. CAT_HEROICS
        local heroExpanded = isExpanded(catHeroKey)
        addRow{
            indent = 0, y = y,
            key = catHeroKey, label = CAT_HEROICS,
            font = "GameFontNormal",
            hasArrow = true, expanded = heroExpanded,
            onClickRow = function()
                setExpanded(catHeroKey, not heroExpanded)
                L3F.RefreshTree()
            end,
        }
        y = y + 20

        if heroExpanded then
            for _, heroic in ipairs(heroics) do
                local heroicKey = "heroic:" .. heroic.name
                addRow{
                    indent = 16, y = y,
                    key = heroicKey, label = heroic.name,
                    font = "GameFontNormalSmall",
                    hasArrow = false,
                    onClickRow = function()
                        selectKey(heroicKey)
                        L3F.RefreshTree()
                        L3F.RefreshNPCList()
                    end,
                }
                y = y + 20
            end
        end

        treeList:SetHeight(math.max(y, 1))
    end
end


-- =============================================================
-- LIST PANE
-- =============================================================
local function buildListPane(parent)
    listPane = CreateFrame("Frame", nil, parent)
    listPane:SetPoint("TOPLEFT",    treePane, "TOPRIGHT",    0, 0)
    listPane:SetPoint("BOTTOMLEFT", treePane, "BOTTOMRIGHT", 0, 0)
    listPane:SetWidth(200)

    local npcScroll = CreateFrame("ScrollFrame", nil, listPane, "UIPanelScrollFrameTemplate")
    npcScroll:SetPoint("TOPLEFT",     listPane, "TOPLEFT",     4, -4)
    npcScroll:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -20, 4)
    npcList = CreateFrame("Frame", nil, npcScroll)
    npcList:SetSize(170, 1)
    npcScroll:SetScrollChild(npcList)

    -- Section sub-header (e.g. wing name when "raid" is selected).
    local function addHeader(name, y)
        local sec = CreateFrame("Frame", nil, npcList)
        sec:SetSize(170, 16)
        sec:SetPoint("TOPLEFT", npcList, "TOPLEFT", 0, -y)
        local t = sec:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t:SetPoint("LEFT", sec, "LEFT", 4, 0)
        t:SetText(name:upper())
        return y + 18
    end

    -- NPC row. `location` is shown as a smaller dim line below the name
    -- in global-search results, so the user knows which raid each hit
    -- belongs to.
    local function addNPC(npc, y, location)
        local rowH = location and 30 or 18
        local row = CreateFrame("Button", nil, npcList)
        row:SetSize(170, rowH)
        row:SetPoint("TOPLEFT", npcList, "TOPLEFT", 0, -y)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        local active = currentNPC and currentNPC.id == npc.id
        rbg:SetColorTexture(active and 0.30 or 0, active and 0.65 or 0, active and 1 or 0, active and 0.25 or 0)

        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -1)
        txt:SetText(npc.name)
        -- Boss names get a subtle gold tint so they pop in flat raid
        -- views and in global search results.
        if isBoss(npc) then
            txt:SetTextColor(active and 1 or 1, active and 1 or 0.82, active and 1 or 0, 1)
        else
            txt:SetTextColor(active and 1 or 0.85, active and 1 or 0.85, active and 1 or 0.85, 1)
        end

        if location then
            local loc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            loc:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -14)
            loc:SetText(location)
        end

        row:SetScript("OnClick", function()
            currentNPC = npc
            L3F.db.atlas.lastSelectedNPC = npc.id
            if L3F.RefreshNPCList then L3F.RefreshNPCList() end
            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
        end)
        row:SetScript("OnEnter", function()
            if not currentNPC or currentNPC.id ~= npc.id then rbg:SetColorTexture(1, 1, 1, 0.07) end
        end)
        row:SetScript("OnLeave", function()
            if currentNPC and currentNPC.id == npc.id then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
            else rbg:SetColorTexture(0, 0, 0, 0) end
        end)
        return y + rowH + 2
    end

    L3F.RefreshNPCList = function()
        for _, c in ipairs({npcList:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        -- FontStrings created directly on npcList (the "No matches." and
        -- "Pick a raid..." placeholders below) are REGIONS, not children,
        -- so the loop above doesn't catch them. Without this they linger
        -- when the user clears the search.
        for _, r in ipairs({npcList:GetRegions()}) do
            r:Hide(); r:ClearAllPoints()
            if r.SetText then r:SetText("") end
        end
        local y = 0

        local search = (searchBox and searchBox:GetText() or "")
            :lower():gsub("^%s+", ""):gsub("%s+$", "")

        -- ---------------------------------------------------------
        -- GLOBAL SEARCH MODE - flat list across every raid + heroic.
        -- ---------------------------------------------------------
        if search ~= "" then
            local hits = {}
            for _, raid in ipairs(L3F.raids) do
                L3F.iterNPCs(raid, function(npc, sectionName)
                    if npc.name:lower():find(search, 1, true) then
                        local loc
                        if sectionName then
                            loc = sectionName .. " - " .. raid.name
                        else
                            loc = raid.name
                        end
                        table.insert(hits, { npc = npc, location = loc })
                    end
                end)
            end
            if #hits == 0 then
                local txt = npcList:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                txt:SetPoint("TOPLEFT", npcList, "TOPLEFT", 8, -8)
                txt:SetText("No matches.")
                npcList:SetHeight(32)
                return
            end
            for _, h in ipairs(hits) do
                y = addNPC(h.npc, y, h.location)
            end
            npcList:SetHeight(math.max(y, 1))
            return
        end

        -- ---------------------------------------------------------
        -- BROWSE MODE - tree-selected node drives the contents.
        -- ---------------------------------------------------------
        local sel = L3F.db.atlas.selected
        if not sel then
            local txt = npcList:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            txt:SetPoint("TOPLEFT", npcList, "TOPLEFT", 8, -8)
            txt:SetText("Pick a raid, wing or dungeon on the left.")
            npcList:SetHeight(32)
            return
        end

        -- Split an NPC list into bosses/trash and render with headers,
        -- so the bosses players actually hunt are always at the top.
        -- If a group is empty its header is skipped (a trash-only wing
        -- doesn't get a "BOSSES" placeholder).
        local function renderBossTrash(npcs)
            local bosses, trash = {}, {}
            for _, npc in ipairs(npcs) do
                if isBoss(npc) then table.insert(bosses, npc)
                else table.insert(trash, npc) end
            end
            if #bosses > 0 then
                y = addHeader("Bosses", y)
                for _, npc in ipairs(bosses) do y = addNPC(npc, y, nil) end
            end
            if #trash > 0 then
                y = addHeader("Trash", y)
                for _, npc in ipairs(trash) do y = addNPC(npc, y, nil) end
            end
        end

        if sel:sub(1, 5) == "wing:" then
            -- Wing selected -> just this wing's NPCs, bosses first.
            local raidName, wIdxStr = sel:sub(6):match("^(.+)/(%d+)$")
            local wIdx = tonumber(wIdxStr or "")
            local raid = raidName and findRaid(raidName)
            if raid and raid.sections and raid.sections[wIdx] then
                renderBossTrash(raid.sections[wIdx].npcs)
            end

        elseif sel:sub(1, 5) == "raid:" then
            -- Raid selected -> flat list of every NPC in the raid,
            -- grouped by Bosses then Trash (the wing breakdown stays
            -- visible in the tree on the left).
            local raid = findRaid(sel:sub(6))
            if raid and raid.sections then
                local all = {}
                for _, sec in ipairs(raid.sections) do
                    for _, npc in ipairs(sec.npcs) do table.insert(all, npc) end
                end
                renderBossTrash(all)
            end

        elseif sel:sub(1, 7) == "heroic:" then
            local heroic = findRaid(sel:sub(8))
            if heroic and heroic.npcs then
                renderBossTrash(heroic.npcs)
            end
        end

        npcList:SetHeight(math.max(y, 1))
    end
end


-- =============================================================
-- DETAIL PANE
-- =============================================================
local function buildDetailPane(parent)
    detailPane = CreateFrame("Frame", nil, parent)
    detailPane:SetPoint("TOPLEFT",     listPane, "TOPRIGHT",    0, 0)
    detailPane:SetPoint("BOTTOMRIGHT", parent,   "BOTTOMRIGHT", 0, 0)

    -- Model column
    local modelHost = CreateFrame("Frame", nil, detailPane)
    modelHost:SetPoint("TOPLEFT",    detailPane, "TOPLEFT",    8, -8)
    modelHost:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", 8, 8)
    modelHost:SetWidth(240)
    local mbg = modelHost:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints(); mbg:SetColorTexture(0, 0, 0, 0.18)

    viewer = L3F.CreateModelViewer(modelHost, 224, 240)
    viewer.frame:SetPoint("TOP", modelHost, "TOP", 0, -8)

    npcTitle = modelHost:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    npcTitle:SetPoint("TOP", viewer.frame, "BOTTOM", 0, -8)
    npcTitle:SetWidth(220)

    npcMeta = modelHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    npcMeta:SetPoint("TOP", npcTitle, "BOTTOM", 0, -4)
    npcMeta:SetWidth(220)
    npcMeta:SetJustifyH("CENTER")

    -- Info column
    local infoHost = CreateFrame("Frame", nil, detailPane)
    infoHost:SetPoint("TOPLEFT",     modelHost, "TOPRIGHT",    8, 0)
    infoHost:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -8, 8)

    local subStrip = CreateFrame("Frame", nil, infoHost)
    subStrip:SetHeight(22)
    subStrip:SetPoint("TOPLEFT",  infoHost, "TOPLEFT",  0, 0)
    subStrip:SetPoint("TOPRIGHT", infoHost, "TOPRIGHT", -60, 0)  -- clear the top-right guild logo
    local stripLine = subStrip:CreateTexture(nil, "OVERLAY")
    stripLine:SetColorTexture(1, 1, 1, 0.15); stripLine:SetHeight(1)
    stripLine:SetPoint("BOTTOMLEFT",  subStrip, "BOTTOMLEFT",  0, 0)
    stripLine:SetPoint("BOTTOMRIGHT", subStrip, "BOTTOMRIGHT", 0, 0)

    subTabContent = CreateFrame("ScrollFrame", nil, infoHost, "UIPanelScrollFrameTemplate")
    subTabContent:SetPoint("TOPLEFT",     subStrip,  "BOTTOMLEFT",  0, -4)
    subTabContent:SetPoint("BOTTOMRIGHT", infoHost,  "BOTTOMRIGHT", -20, 0)
    subTabContent.body = CreateFrame("Frame", nil, subTabContent)
    subTabContent.body:SetSize(400, 1)
    subTabContent:SetScrollChild(subTabContent.body)
    -- Keep the scroll child as wide as the visible scroll area, so notes
    -- wrap (and drops / other sub-tabs lay out) to the real width rather
    -- than the hardcoded 400. Height stays under per-sub-tab control.
    local function fitBody()
        local w = subTabContent:GetWidth()
        if w and w > 1 then subTabContent.body:SetWidth(w) end
    end
    subTabContent:HookScript("OnSizeChanged", fitBody)
    fitBody()

    local x = 0
    for _, key in ipairs(SUB_TABS) do
        local btn = CreateFrame("Button", nil, subStrip)
        btn:SetSize(80, 22)
        btn:SetPoint("BOTTOMLEFT", subStrip, "BOTTOMLEFT", x, 0)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("CENTER"); lbl:SetText(SUB_TAB_LABELS[key])
        btn.label = lbl
        local under = btn:CreateTexture(nil, "OVERLAY")
        under:SetColorTexture(0.30, 0.65, 1.0, 1); under:SetHeight(2)
        under:SetPoint("BOTTOMLEFT"); under:SetPoint("BOTTOMRIGHT"); under:Hide()
        btn.underline = under
        btn:SetScript("OnClick", function()
            L3F.db.atlas.lastActiveSubTab = key
            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
        end)
        subTabButtons[key] = btn
        x = x + 84
    end

    -- Distribute the sub-tab buttons across the strip width so they always fit,
    -- whatever size the user resizes the window to.
    local function layoutSubTabs()
        local w = subStrip:GetWidth()
        if not w or w <= 1 then return end
        local n = #SUB_TABS
        local gap = 4
        local bw = math.max(40, math.floor((w - gap * (n - 1)) / n))
        for i, key in ipairs(SUB_TABS) do
            local btn = subTabButtons[key]
            if btn then
                btn:SetSize(bw, 22)
                btn:ClearAllPoints()
                btn:SetPoint("BOTTOMLEFT", subStrip, "BOTTOMLEFT", (i - 1) * (bw + gap), 0)
            end
        end
    end
    subStrip:SetScript("OnSizeChanged", layoutSubTabs)
    layoutSubTabs()

    L3F.RefreshDetailPane = function()
        local npc = currentNPC
        for k, btn in pairs(subTabButtons) do
            local active = (k == L3F.db.atlas.lastActiveSubTab)
            btn.label:SetTextColor(active and 1 or 0.7, active and 1 or 0.7, active and 1 or 0.7, 1)
            if active then btn.underline:Show() else btn.underline:Hide() end
        end
        -- Clear both child frames AND regions (FontStrings/Textures from prior sub-tab).
        for _, c in ipairs({subTabContent.body:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        if subTabContent.body.GetRegions then
            for _, r in ipairs({subTabContent.body:GetRegions()}) do
                r:Hide(); r:ClearAllPoints()
                if r.SetText then r:SetText("") end
            end
        end

        if not npc then
            viewer:Clear()
            npcTitle:SetText("Select an NPC")
            npcMeta:SetText("")
            return
        end
        viewer:SetCreature(npc.id)
        npcTitle:SetText(npc.name)
        -- Build a richer meta line: "Level 72 Humanoid - Hellfire Citadel".
        -- Falls back gracefully if level/type fields are absent (raids still
        -- get section - raid).
        local parts = {}
        if npc.level and npc.type then
            table.insert(parts, "Level " .. npc.level .. " " .. npc.type)
        elseif npc.level then
            table.insert(parts, "Level " .. npc.level)
        elseif npc.type then
            table.insert(parts, npc.type)
        end
        local locText
        if npc.section then
            locText = npc.section .. (npc.raid and (" - " .. npc.raid) or "")
        else
            for _, r in ipairs(L3F.raids) do
                if r.name == npc.raid then locText = r.location or r.name; break end
            end
            locText = locText or npc.raid or ""
        end
        if locText ~= "" then table.insert(parts, locText) end
        npcMeta:SetText(table.concat(parts, " - "))

        local sub = L3F.db.atlas.lastActiveSubTab
        if sub == "spells" then
            if npc.spells and #npc.spells > 0 then
                local y = 0
                for _, spellID in ipairs(npc.spells) do
                    local row = CreateFrame("Button", nil, subTabContent.body)
                    row:SetSize(420, 24)
                    row:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -y)
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(20, 20); icon:SetPoint("LEFT", row, "LEFT", 0, 0)
                    local name, _, tex = GetSpellInfo(spellID)
                    icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
                    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                    lbl:SetText(name or ("Spell #" .. spellID))
                    local idText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    idText:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
                    idText:SetText(tostring(spellID))
                    row:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(spellID) end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    y = y + 26
                end
                subTabContent.body:SetHeight(math.max(y, 1))
            else
                local txt = subTabContent.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                txt:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -4)
                txt:SetText("No notable abilities documented.")
            end

        elseif sub == "notes" then
            local txt = subTabContent.body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            txt:SetPoint("TOPLEFT",  subTabContent.body, "TOPLEFT",  4, -4)
            txt:SetPoint("TOPRIGHT", subTabContent.body, "TOPRIGHT", -4, -4)
            txt:SetJustifyH("LEFT"); txt:SetJustifyV("TOP")
            txt:SetText(npc.notes or "No strategy notes yet.")
            txt:SetWidth(subTabContent.body:GetWidth() - 8)
            subTabContent.body:SetHeight(math.max(txt:GetStringHeight() + 8, 1))

        elseif sub == "drops" then
            if npc.drops and #npc.drops > 0 then
                local y = 0
                for _, drop in ipairs(npc.drops) do
                    local row = CreateFrame("Button", nil, subTabContent.body)
                    row:SetSize(420, 24)
                    row:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -y)
                    -- Item icon (async refresh once GetItemInfo populates)
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(20, 20); icon:SetPoint("LEFT", row, "LEFT", 0, 0)
                    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0); lbl:SetWidth(260); lbl:SetJustifyH("LEFT")
                    lbl:SetText(drop.name or ("Item #" .. drop.id))
                    queueItemUI(drop.id, lbl, icon)
                    local chance = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    chance:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
                    chance:SetText(string.format("%.1f%%", drop.chance or 0))
                    row:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(drop.id)
                        else GameTooltip:SetHyperlink("item:" .. drop.id) end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    y = y + 24
                end
                subTabContent.body:SetHeight(math.max(y, 1))
            else
                local txt = subTabContent.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                txt:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -4)
                txt:SetText("No drop table for this NPC.")
            end

        else
            local txt = subTabContent.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            txt:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -4)
            txt:SetText("Data for '" .. SUB_TAB_LABELS[sub] .. "' coming in v0.3.")
        end
    end
end


-- =============================================================
-- ENTRY POINT
-- =============================================================
local function buildAtlas(parent)
    ensureState()
    buildTreePane(parent)
    buildListPane(parent)
    buildDetailPane(parent)

    if L3F.db.atlas.lastSelectedNPC then
        currentNPC = L3F.npcLookup[L3F.db.atlas.lastSelectedNPC]
    end

    -- If the active raid is collapsed but selected, expand it so the user
    -- sees their context on first open.
    local sel = L3F.db.atlas.selected
    if sel and (sel:sub(1, 5) == "raid:" or sel:sub(1, 5) == "wing:") then
        setExpanded("cat:" .. CAT_RAIDS, true)
        local raidName = (sel:sub(1, 5) == "wing:")
            and sel:sub(6):match("^(.+)/%d+$")
            or  sel:sub(6)
        if raidName then setExpanded("raid:" .. raidName, true) end
    elseif sel and sel:sub(1, 7) == "heroic:" then
        setExpanded("cat:" .. CAT_HEROICS, true)
    end

    L3F.RefreshTree()
    L3F.RefreshNPCList()
    L3F.RefreshDetailPane()
end

L3F.RegisterTab("atlas", "Atlas", nil, buildAtlas)
