-- =============================================================
-- L3FTools - Tabs/Atlas.lua
-- =============================================================
-- Three-pane Atlas: [Tree + search] | [NPC list] | [Detail].
-- Detail pane: interactive 3D model on the left, info sub-tabs on
-- the right (Spells, Notes, Drops, Location, Lore).
-- =============================================================

local addonName, L3F = ...

local SUB_TABS = { "spells", "notes", "drops", "location", "lore" }
local SUB_TAB_LABELS = {
    spells = "Spells", notes = "Notes", drops = "Drops",
    location = "Location", lore = "Lore",
}

local treePane, listPane, detailPane
local raidList, npcList, searchBox
local currentRaidName, currentNPC
local subTabButtons = {}
local subTabContent
local viewer, npcTitle, npcMeta


-- =============================================================
-- ITEM QUALITY COLOURING  (for drop labels)
-- =============================================================
-- GetItemInfo is async: it returns nil for an uncached item, then the data
-- arrives via GET_ITEM_INFO_RECEIVED. Colour the label immediately if cached,
-- otherwise queue it and recolour when the event fires.
local pendingItemColor = {}
local itemInfoFrame = CreateFrame("Frame")
itemInfoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemInfoFrame:SetScript("OnEvent", function(_, _, itemID)
    local labels = pendingItemColor[itemID]
    if not labels then return end
    pendingItemColor[itemID] = nil
    local _, _, quality = GetItemInfo(itemID)
    if quality then
        local r, g, b = GetItemQualityColor(quality)
        for _, fs in ipairs(labels) do fs:SetTextColor(r, g, b) end
    end
end)

local function colorByQuality(fs, itemID)
    if not itemID then return end
    local _, _, quality = GetItemInfo(itemID)
    if quality then
        local r, g, b = GetItemQualityColor(quality)
        fs:SetTextColor(r, g, b)
    else
        pendingItemColor[itemID] = pendingItemColor[itemID] or {}
        table.insert(pendingItemColor[itemID], fs)
    end
end


-- =============================================================
-- TREE PANE
-- =============================================================
local function buildTreePane(parent)
    treePane = CreateFrame("Frame", nil, parent)
    treePane:SetPoint("TOPLEFT",    parent, "TOPLEFT",    0, 0)
    treePane:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    treePane:SetWidth(140)
    local bg = treePane:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.18)

    searchBox = CreateFrame("EditBox", nil, treePane, "InputBoxTemplate")
    searchBox:SetSize(116, 22)
    searchBox:SetPoint("TOPLEFT", treePane, "TOPLEFT", 14, -8)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetScript("OnTextChanged", function()
        if L3F.RefreshNPCList then L3F.RefreshNPCList() end
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)

    local raidScroll = CreateFrame("ScrollFrame", nil, treePane, "UIPanelScrollFrameTemplate")
    raidScroll:SetPoint("TOPLEFT",     searchBox, "BOTTOMLEFT",  0, -6)
    raidScroll:SetPoint("BOTTOMRIGHT", treePane,  "BOTTOMRIGHT", -20, 6)
    raidList = CreateFrame("Frame", nil, raidScroll)
    raidList:SetSize(110, 1)
    raidScroll:SetScrollChild(raidList)

    L3F.RefreshRaidList = function()
        for _, c in ipairs({raidList:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        local y = 0
        for _, raid in ipairs(L3F.raids) do
            local row = CreateFrame("Button", nil, raidList)
            row:SetSize(110, 18)
            row:SetPoint("TOPLEFT", raidList, "TOPLEFT", 0, -y)
            local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            txt:SetPoint("LEFT", row, "LEFT", 6, 0)
            txt:SetText(raid.name)
            local rbg = row:CreateTexture(nil, "BACKGROUND")
            rbg:SetAllPoints()
            local active = (raid.name == currentRaidName)
            rbg:SetColorTexture(active and 0.30 or 0, active and 0.65 or 0, active and 1.0 or 0, active and 0.25 or 0)
            txt:SetTextColor(active and 1 or 0.85, active and 1 or 0.85, active and 1 or 0.85, 1)
            row:SetScript("OnClick", function()
                currentRaidName = raid.name
                L3F.db.atlas.lastSelectedRaid = raid.name
                if L3F.RefreshRaidList then L3F.RefreshRaidList() end
                if L3F.RefreshNPCList then L3F.RefreshNPCList() end
            end)
            row:SetScript("OnEnter", function()
                if raid.name ~= currentRaidName then rbg:SetColorTexture(1, 1, 1, 0.07) end
            end)
            row:SetScript("OnLeave", function()
                if raid.name == currentRaidName then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
                else rbg:SetColorTexture(0, 0, 0, 0) end
            end)
            y = y + 20
        end
        raidList:SetHeight(math.max(y, 1))
    end
end


-- =============================================================
-- LIST PANE
-- =============================================================
local function buildListPane(parent)
    listPane = CreateFrame("Frame", nil, parent)
    listPane:SetPoint("TOPLEFT",    treePane, "TOPRIGHT",    0, 0)
    listPane:SetPoint("BOTTOMLEFT", treePane, "BOTTOMRIGHT", 0, 0)
    listPane:SetWidth(180)

    local npcScroll = CreateFrame("ScrollFrame", nil, listPane, "UIPanelScrollFrameTemplate")
    npcScroll:SetPoint("TOPLEFT",     listPane, "TOPLEFT",     4, -4)
    npcScroll:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -20, 4)
    npcList = CreateFrame("Frame", nil, npcScroll)
    npcList:SetSize(150, 1)
    npcScroll:SetScrollChild(npcList)

    L3F.RefreshNPCList = function()
        for _, c in ipairs({npcList:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        if not currentRaidName then return end
        local raid
        for _, r in ipairs(L3F.raids) do
            if r.name == currentRaidName then raid = r; break end
        end
        if not raid then return end

        local search = (searchBox and searchBox:GetText() or ""):lower():gsub("^%s+",""):gsub("%s+$","")
        local y = 0

        local function addSection(title)
            local sec = CreateFrame("Frame", nil, npcList)
            sec:SetSize(150, 16)
            sec:SetPoint("TOPLEFT", npcList, "TOPLEFT", 0, -y)
            local t = sec:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            t:SetPoint("LEFT", sec, "LEFT", 4, 0)
            t:SetText(title:upper())
            y = y + 18
        end
        local function addNPC(npc)
            local row = CreateFrame("Button", nil, npcList)
            row:SetSize(150, 18)
            row:SetPoint("TOPLEFT", npcList, "TOPLEFT", 0, -y)
            local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            txt:SetPoint("LEFT", row, "LEFT", 8, 0)
            txt:SetText(npc.name)
            local rbg = row:CreateTexture(nil, "BACKGROUND")
            rbg:SetAllPoints()
            local active = currentNPC and currentNPC.id == npc.id
            rbg:SetColorTexture(active and 0.30 or 0, active and 0.65 or 0, active and 1 or 0, active and 0.25 or 0)
            txt:SetTextColor(active and 1 or 0.85, active and 1 or 0.85, active and 1 or 0.85, 1)
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
            y = y + 20
        end

        local matches = function(npc) return search == "" or npc.name:lower():find(search, 1, true) end
        if raid.sections then
            for _, sec in ipairs(raid.sections) do
                local hits = {}
                for _, npc in ipairs(sec.npcs) do
                    if matches(npc) then table.insert(hits, npc) end
                end
                if #hits > 0 then
                    addSection(sec.name)
                    for _, n in ipairs(hits) do addNPC(n) end
                end
            end
        elseif raid.npcs then
            for _, npc in ipairs(raid.npcs) do
                if matches(npc) then addNPC(npc) end
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
    subStrip:SetPoint("TOPRIGHT", infoHost, "TOPRIGHT", 0, 0)
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
        -- Build a richer meta line: "Level 72 Humanoid · Hellfire Citadel - The Blood Furnace"
        -- Falls back gracefully if level/type fields are absent (raids still get section · raid).
        local parts = {}
        if npc.level and npc.type then
            table.insert(parts, "Level " .. npc.level .. " " .. npc.type)
        elseif npc.level then
            table.insert(parts, "Level " .. npc.level)
        elseif npc.type then
            table.insert(parts, npc.type)
        end
        -- Location: prefer the raid's `location` string if loaded, else fall back to section + raid name.
        local locText
        if npc.section then
            locText = npc.section .. (npc.raid and (" · " .. npc.raid) or "")
        else
            -- find the raid record to read its .location field (heroics provide it)
            for _, r in ipairs(L3F.raids) do
                if r.name == npc.raid then locText = r.location or r.name; break end
            end
            locText = locText or npc.raid or ""
        end
        if locText ~= "" then table.insert(parts, locText) end
        npcMeta:SetText(table.concat(parts, " · "))

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
                    row:SetSize(420, 22)
                    row:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -y)
                    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    lbl:SetPoint("LEFT", row, "LEFT", 0, 0); lbl:SetWidth(280); lbl:SetJustifyH("LEFT")
                    lbl:SetText(drop.name or ("Item #" .. drop.id))
                    colorByQuality(lbl, drop.id)
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
                    y = y + 22
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
    buildTreePane(parent)
    buildListPane(parent)
    buildDetailPane(parent)

    currentRaidName = L3F.db.atlas.lastSelectedRaid
    if L3F.db.atlas.lastSelectedNPC then
        currentNPC = L3F.npcLookup[L3F.db.atlas.lastSelectedNPC]
    end

    L3F.RefreshRaidList()
    L3F.RefreshNPCList()
    L3F.RefreshDetailPane()
end

L3F.RegisterTab("atlas", "Atlas", nil, buildAtlas)
