-- =============================================================
-- L3FTools - Tabs/Guild/Crafts.lua
-- =============================================================
-- Crafts tab UI: guild-wide recipe directory. 3-pane layout
-- modelled on GuildCrafts: left = profession list with crafter
-- counts; middle = recipe list (filtered by profession or by
-- search query); right = recipe detail panel (reagents tooltip,
-- crafter list, favorite + post-to-guild buttons).
--
-- Data layer: L3F.Crafts (CraftsCore.lua).
-- Sync layer: L3F.CraftsComms.
-- Chat layer: L3F.CraftsChat.
-- Scrape:    L3F.CraftsScraper (auto-fires when player opens a
--            profession window).
-- =============================================================

local addonName, L3F = ...

local Crafts = L3F.Crafts
local Chat   = L3F.CraftsChat
local Comms  = L3F.CraftsComms

-- =============================================================
-- Constants
-- =============================================================
local LEFT_W   = 180
local RIGHT_W  = 300
local ROW_H    = 22
local TOP_H    = 50


-- =============================================================
-- State (tab-local, rebuilt on tab open)
-- =============================================================
local panel
local leftHost, middleHost, rightHost
local searchEdit, onlineOnlyCB, refreshAllBtn
local middleScroll, middleContent
local rightTitleFS, rightProfFS, rightCrafterScroll, rightCrafterContent
local rightFavBtn, rightPostBtn, rightTooltipBtn

local state = {
    selectedProf   = nil,   -- string profession name, or "_search" for search results
    selectedSpellID = nil,
    searchQuery    = "",
    onlineOnly     = false,
}


-- =============================================================
-- Helpers
-- =============================================================
local function classColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class or ""]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

local function classColorHex(class)
    local r, g, b = classColor(class)
    return string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function wipeChildren(frame)
    if not frame then return end
    for _, c in ipairs({frame:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    for _, r in ipairs({frame:GetRegions()}) do
        r:Hide(); r:ClearAllPoints()
        if r.SetText then r:SetText("") end
    end
end


-- =============================================================
-- Profession enumeration with crafter counts
-- =============================================================
local function professionCrafterCounts()
    -- Returns { [profName] = N } where N = number of guildies who
    -- have at least one recipe in that profession.
    local counts = {}
    for _, p in ipairs(Crafts.PROFESSIONS) do counts[p] = 0 end
    local all = Crafts.GetAllMembers()
    for _, m in pairs(all) do
        if m.professions then
            for profName, pd in pairs(m.professions) do
                if counts[profName] ~= nil and pd.recipes and next(pd.recipes) then
                    counts[profName] = counts[profName] + 1
                end
            end
        end
    end
    return counts
end


-- =============================================================
-- LEFT PANEL: profession list
-- =============================================================
local function refreshLeftPanel()
    if not leftHost then return end
    wipeChildren(leftHost)

    local title = leftHost:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", leftHost, "TOPLEFT", 8, -8)
    title:SetText("Crafts")

    local counts = professionCrafterCounts()

    local y = 36
    local function row(label, profKey, count)
        local b = CreateFrame("Button", nil, leftHost)
        b:SetSize(LEFT_W - 12, ROW_H)
        b:SetPoint("TOPLEFT", leftHost, "TOPLEFT", 6, -y)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if state.selectedProf == profKey then
            bg:SetColorTexture(0.3, 0.5, 0.8, 0.4)
        else
            bg:SetColorTexture(1, 1, 1, 0)
        end
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

        local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("LEFT", b, "LEFT", 8, 0)
        txt:SetText(label)
        if count == 0 then txt:SetTextColor(0.5, 0.5, 0.5, 1) end

        local cnt = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cnt:SetPoint("RIGHT", b, "RIGHT", -8, 0)
        cnt:SetText("(" .. count .. ")")

        b:SetScript("OnClick", function()
            state.selectedProf = profKey
            state.selectedSpellID = nil
            state.searchQuery = ""
            if searchEdit then searchEdit:SetText("") end
            refreshLeftPanel()
            refreshMiddlePanel()
            refreshRightPanel()
        end)
        y = y + ROW_H + 2
    end

    -- All-search pseudo-prof at the top (active when state.selectedProf == "_search")
    row("All (search)", "_search", 0)
    y = y + 6

    for _, profName in ipairs(Crafts.PROFESSIONS) do
        row(profName, profName, counts[profName] or 0)
    end

    -- "My professions" mini-section at the bottom
    local me = Crafts.GetMyData()
    if me and me.professions then
        y = y + 8
        local subTitle = leftHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        subTitle:SetPoint("TOPLEFT", leftHost, "TOPLEFT", 8, -y)
        subTitle:SetText("|cffaaccffMy professions|r")
        y = y + 16
        for profName, pd in pairs(me.professions) do
            local fs = leftHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            fs:SetPoint("TOPLEFT", leftHost, "TOPLEFT", 10, -y)
            fs:SetText(string.format("%s %d/%d",
                profName, pd.skillRank or 0, pd.skillMax or 0))
            y = y + 14
        end
    end
end


-- =============================================================
-- MIDDLE PANEL: recipe list
-- =============================================================
local function buildMiddleRow(parent, y, spellID, name, profName, crafterCount)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(parent:GetWidth() - 8, ROW_H)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -y)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if state.selectedSpellID == spellID then
        bg:SetColorTexture(0.3, 0.5, 0.8, 0.4)
    else
        bg:SetColorTexture(1, 1, 1, 0)
    end
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- Favorite star
    local star = b:CreateTexture(nil, "ARTWORK")
    star:SetSize(14, 14)
    star:SetPoint("LEFT", b, "LEFT", 4, 0)
    if Crafts.IsFavorite(spellID) then
        star:SetTexture("Interface\\Common\\ReputationStar")
        star:SetTexCoord(0, 0.5, 0, 0.5)  -- filled
    else
        star:SetTexture(nil)
    end

    -- Recipe icon (via professionRecipeMap -> itemID -> GetItemIcon)
    local iconTex = b:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(16, 16)
    iconTex:SetPoint("LEFT", b, "LEFT", 22, 0)
    local itemID = L3F.professionRecipeMap and L3F.professionRecipeMap[spellID]
    if itemID and GetItemIcon then
        local tex = GetItemIcon(itemID)
        if tex then iconTex:SetTexture(tex) end
    end
    if not iconTex:GetTexture() and GetSpellTexture then
        iconTex:SetTexture(GetSpellTexture(spellID))
    end
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("LEFT", b, "LEFT", 44, 0)
    txt:SetPoint("RIGHT", b, "RIGHT", -60, 0)
    txt:SetJustifyH("LEFT")
    txt:SetText(name or ("spell:" .. spellID))

    local right = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    right:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    if state.selectedProf == "_search" then
        right:SetText(string.format("%s (%d)", profName or "?", crafterCount or 0))
    else
        right:SetText(tostring(crafterCount or 0) .. " crafter" .. (crafterCount == 1 and "" or "s"))
    end

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(spellID)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetScript("OnClick", function()
        state.selectedSpellID = spellID
        refreshMiddlePanel()
        refreshRightPanel()
    end)

    return b
end

local function getMiddleRows()
    -- Returns an array of { spellID, name, profName, crafters }
    -- based on current state (selected prof or search query).
    if state.selectedProf == "_search" then
        if state.searchQuery == "" then return {} end
        return Crafts.SearchByName(state.searchQuery)
    end
    if not state.selectedProf then return {} end

    -- Profession-filtered: gather all spell IDs known by any crafter
    -- in this profession.
    local out = {}
    local seen = {}
    for _, info in ipairs(Crafts.GetMembersByProfession(state.selectedProf)) do
        for spellID in pairs(info.profData.recipes or {}) do
            if not seen[spellID] then
                seen[spellID] = true
                local crafters = Crafts.GetCraftersFor(spellID)
                if not state.onlineOnly or
                   (function()
                       for _, c in ipairs(crafters) do
                           if c.online then return true end
                       end
                       return false
                   end)() then
                    table.insert(out, {
                        spellID = spellID,
                        name = Crafts.GetRecipeName(spellID),
                        profName = state.selectedProf,
                        crafters = crafters,
                    })
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if Crafts.IsFavorite(a.spellID) ~= Crafts.IsFavorite(b.spellID) then
            return Crafts.IsFavorite(a.spellID)
        end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

function refreshMiddlePanel()
    if not middleContent then return end
    wipeChildren(middleContent)

    local rows = getMiddleRows()

    if #rows == 0 then
        local fs = middleContent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        fs:SetPoint("CENTER", middleContent, "CENTER", 0, -40)
        fs:SetJustifyH("CENTER")
        if state.selectedProf == "_search" and state.searchQuery == "" then
            fs:SetText("Type a recipe name above to search across all professions.")
        elseif state.selectedProf == "_search" then
            fs:SetText("No matches.")
        elseif state.selectedProf then
            fs:SetText("No crafter known for this profession yet.")
        else
            fs:SetText("Pick a profession on the left.")
        end
        middleContent:SetHeight(80)
        return
    end

    local y = 4
    for _, r in ipairs(rows) do
        buildMiddleRow(middleContent, y, r.spellID, r.name, r.profName, #r.crafters)
        y = y + ROW_H + 2
    end
    middleContent:SetHeight(math.max(80, y + 8))
end


-- =============================================================
-- RIGHT PANEL: recipe detail
-- =============================================================
function refreshRightPanel()
    if not rightHost then return end
    wipeChildren(rightCrafterContent)

    if not state.selectedSpellID then
        rightTitleFS:SetText("|cffaaaaaaSelect a recipe|r")
        rightProfFS:SetText("")
        rightFavBtn:Hide()
        rightPostBtn:Hide()
        rightTooltipBtn:Hide()
        local fs = rightCrafterContent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        fs:SetPoint("CENTER", rightCrafterContent, "CENTER", 0, 0)
        fs:SetText("Pick a recipe in the middle column to see its crafters.")
        return
    end

    local spellID = state.selectedSpellID
    local name = Crafts.GetRecipeName(spellID)
    rightTitleFS:SetText(name)

    -- Profession the recipe belongs to (look it up from bundled data).
    local profName = nil
    local entries = L3F.bonusItemLookup and L3F.bonusItemLookup[spellID]
    if entries then
        for _, e in ipairs(entries) do
            if e.entry and Crafts.PROFESSION_SET[e.entry.key] then
                profName = e.entry.key; break
            end
        end
    end
    rightProfFS:SetText(profName and ("Profession: " .. profName) or "")

    rightFavBtn:Show()
    rightPostBtn:Show()
    rightTooltipBtn:Show()

    if Crafts.IsFavorite(spellID) then
        rightFavBtn:SetText("Unfavorite")
    else
        rightFavBtn:SetText("Favorite")
    end
    rightFavBtn:SetScript("OnClick", function()
        Crafts.SetFavorite(spellID, not Crafts.IsFavorite(spellID))
        refreshRightPanel()
        refreshMiddlePanel()
    end)
    rightPostBtn:SetScript("OnClick", function()
        if Chat and Chat.PostRecipeToGuild then
            Chat.PostRecipeToGuild(spellID)
        end
    end)
    rightTooltipBtn:SetScript("OnClick", function()
        if GameTooltip.SetSpellByID then
            GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
            GameTooltip:SetSpellByID(spellID)
            GameTooltip:Show()
        end
    end)

    local crafters = Crafts.GetCraftersFor(spellID)
    if state.onlineOnly then
        local filtered = {}
        for _, c in ipairs(crafters) do
            if c.online then table.insert(filtered, c) end
        end
        crafters = filtered
    end

    if #crafters == 0 then
        local fs = rightCrafterContent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        fs:SetPoint("TOPLEFT", rightCrafterContent, "TOPLEFT", 4, -4)
        fs:SetText("No crafter known for this recipe.")
        rightCrafterContent:SetHeight(40)
        return
    end

    local y = 4
    for _, c in ipairs(crafters) do
        local row = CreateFrame("Frame", nil, rightCrafterContent)
        row:SetSize(rightCrafterContent:GetWidth() - 8, ROW_H)
        row:SetPoint("TOPLEFT", rightCrafterContent, "TOPLEFT", 4, -y)
        local dot = row:CreateTexture(nil, "ARTWORK")
        dot:SetSize(10, 10)
        dot:SetPoint("LEFT", row, "LEFT", 4, 0)
        dot:SetTexture("Interface\\Buttons\\WHITE8X8")
        if c.online then
            dot:SetVertexColor(0.4, 1, 0.4, 1)
        else
            dot:SetVertexColor(0.5, 0.5, 0.5, 1)
        end
        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("LEFT", row, "LEFT", 20, 0)
        local member = Crafts.GetMember(c.short)
        local roster = Crafts.GetRosterInfo(c.short)
        local classFile = (member and member.classFile)
            or (roster and roster.classFile) or "UNKNOWN"
        local hex = classColorHex(classFile)
        local tag = ""
        if member then
            local age = Crafts.AgeDays(member)
            if Crafts.IsStale(member) then
                tag = string.format(" |cffaaaaaa(%dd old)|r", age)
            end
        end
        txt:SetText(string.format("|c%s%s|r%s", hex, c.short, tag))
        y = y + ROW_H + 1
    end
    rightCrafterContent:SetHeight(math.max(40, y + 8))
end


-- =============================================================
-- Main builder
-- =============================================================
local function buildCrafts(parent)
    panel = parent

    -- =====================
    -- TOP BAR
    -- =====================
    local top = CreateFrame("Frame", nil, parent)
    top:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
    top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
    top:SetHeight(TOP_H - 8)

    local title = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("LEFT", top, "LEFT", 8, 0)
    title:SetText("Guild Crafts")

    searchEdit = CreateFrame("EditBox", nil, top, "InputBoxTemplate")
    searchEdit:SetSize(200, 22)
    searchEdit:SetPoint("LEFT", title, "RIGHT", 24, 0)
    searchEdit:SetAutoFocus(false)
    searchEdit:SetScript("OnTextChanged", function(self)
        state.searchQuery = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if state.searchQuery ~= "" then
            state.selectedProf = "_search"
            state.selectedSpellID = nil
        end
        refreshLeftPanel()
        refreshMiddlePanel()
        refreshRightPanel()
    end)
    local searchLabel = top:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchLabel:SetPoint("RIGHT", searchEdit, "LEFT", -4, 0)
    searchLabel:SetText("Search:")

    onlineOnlyCB = CreateFrame("CheckButton", nil, top, "UICheckButtonTemplate")
    onlineOnlyCB:SetSize(22, 22)
    onlineOnlyCB:SetPoint("LEFT", searchEdit, "RIGHT", 12, 0)
    onlineOnlyCB.text:SetText("  Online only")
    onlineOnlyCB:SetChecked(state.onlineOnly)
    onlineOnlyCB:SetScript("OnClick", function(self)
        state.onlineOnly = self:GetChecked()
        refreshMiddlePanel()
        refreshRightPanel()
    end)

    refreshAllBtn = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
    refreshAllBtn:SetSize(110, 22)
    refreshAllBtn:SetPoint("RIGHT", top, "RIGHT", -8, 0)
    refreshAllBtn:SetText("Request sync")
    refreshAllBtn:SetScript("OnClick", function()
        if Comms and Comms.RequestSync then
            Comms.RequestSync()
            print("|cffffd100L3F Crafts:|r sync requested from DR ("
                .. tostring(Comms.GetDR() or "?") .. ").")
        end
    end)
    refreshAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Pull a fresh snapshot from the elected guild DR")
        GameTooltip:AddLine("DR (Designated Responder) is the alphabetically-",
            0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("first guildie running L3FTools. They serve sync requests.",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    refreshAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- =====================
    -- LEFT panel
    -- =====================
    leftHost = CreateFrame("Frame", nil, parent)
    leftHost:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -TOP_H)
    leftHost:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 4, 4)
    leftHost:SetWidth(LEFT_W)
    local leftBg = leftHost:CreateTexture(nil, "BACKGROUND")
    leftBg:SetAllPoints(); leftBg:SetColorTexture(0, 0, 0, 0.25)

    -- =====================
    -- RIGHT panel
    -- =====================
    rightHost = CreateFrame("Frame", nil, parent)
    rightHost:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -TOP_H)
    rightHost:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 4)
    rightHost:SetWidth(RIGHT_W)
    local rightBg = rightHost:CreateTexture(nil, "BACKGROUND")
    rightBg:SetAllPoints(); rightBg:SetColorTexture(0, 0, 0, 0.25)

    rightTitleFS = rightHost:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rightTitleFS:SetPoint("TOPLEFT", rightHost, "TOPLEFT", 10, -10)
    rightTitleFS:SetPoint("RIGHT", rightHost, "RIGHT", -10, 0)
    rightTitleFS:SetJustifyH("LEFT")

    rightProfFS = rightHost:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    rightProfFS:SetPoint("TOPLEFT", rightTitleFS, "BOTTOMLEFT", 0, -4)

    -- Button row
    rightFavBtn = CreateFrame("Button", nil, rightHost, "UIPanelButtonTemplate")
    rightFavBtn:SetSize(90, 22); rightFavBtn:SetText("Favorite")
    rightFavBtn:SetPoint("TOPLEFT", rightProfFS, "BOTTOMLEFT", 0, -10)
    rightPostBtn = CreateFrame("Button", nil, rightHost, "UIPanelButtonTemplate")
    rightPostBtn:SetSize(90, 22); rightPostBtn:SetText("Post")
    rightPostBtn:SetPoint("LEFT", rightFavBtn, "RIGHT", 4, 0)
    rightTooltipBtn = CreateFrame("Button", nil, rightHost, "UIPanelButtonTemplate")
    rightTooltipBtn:SetSize(90, 22); rightTooltipBtn:SetText("Recipe")
    rightTooltipBtn:SetPoint("LEFT", rightPostBtn, "RIGHT", 4, 0)
    rightTooltipBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Show full recipe tooltip (reagents, skill)")
        GameTooltip:Show()
    end)
    rightTooltipBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Crafter list scroll area
    local crafterHeader = rightHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    crafterHeader:SetPoint("TOPLEFT", rightFavBtn, "BOTTOMLEFT", 0, -16)
    crafterHeader:SetText("Crafters:")

    rightCrafterScroll = CreateFrame("ScrollFrame", nil, rightHost, "UIPanelScrollFrameTemplate")
    rightCrafterScroll:SetPoint("TOPLEFT", crafterHeader, "BOTTOMLEFT", 0, -4)
    rightCrafterScroll:SetPoint("BOTTOMRIGHT", rightHost, "BOTTOMRIGHT", -24, 8)
    rightCrafterContent = CreateFrame("Frame", nil, rightCrafterScroll)
    rightCrafterContent:SetSize(RIGHT_W - 32, 100)
    rightCrafterScroll:SetScrollChild(rightCrafterContent)

    -- =====================
    -- MIDDLE panel (scroll + content)
    -- =====================
    middleHost = CreateFrame("Frame", nil, parent)
    middleHost:SetPoint("TOPLEFT", leftHost, "TOPRIGHT", 6, 0)
    middleHost:SetPoint("BOTTOMRIGHT", rightHost, "BOTTOMLEFT", -6, 0)
    local midBg = middleHost:CreateTexture(nil, "BACKGROUND")
    midBg:SetAllPoints(); midBg:SetColorTexture(0, 0, 0, 0.15)

    middleScroll = CreateFrame("ScrollFrame", nil, middleHost, "UIPanelScrollFrameTemplate")
    middleScroll:SetPoint("TOPLEFT", middleHost, "TOPLEFT", 4, -4)
    middleScroll:SetPoint("BOTTOMRIGHT", middleHost, "BOTTOMRIGHT", -24, 4)
    middleContent = CreateFrame("Frame", nil, middleScroll)
    middleContent:SetSize(middleHost:GetWidth() - 28, 200)
    middleScroll:SetScrollChild(middleContent)

    middleHost:HookScript("OnSizeChanged", function(_, w, h)
        if w and w > 0 then middleContent:SetWidth(w - 28) end
        refreshMiddlePanel()
    end)

    -- Default selection: first profession with any crafter, or "_search".
    local counts = professionCrafterCounts()
    for _, p in ipairs(Crafts.PROFESSIONS) do
        if counts[p] > 0 then state.selectedProf = p; break end
    end
    if not state.selectedProf then state.selectedProf = "_search" end

    refreshLeftPanel()
    refreshMiddlePanel()
    refreshRightPanel()
end


-- =============================================================
-- Subscribe to data changes so UI refreshes when comms / scrape /
-- roster events update the underlying tables.
-- =============================================================
if Crafts and Crafts.OnDataChanged then
    Crafts.OnDataChanged(function(kind, key)
        if not panel or not panel:IsShown() then return end
        if kind == "favorite" then
            refreshMiddlePanel()
            refreshRightPanel()
        elseif kind == "roster" then
            refreshLeftPanel()
            refreshRightPanel()
        else
            refreshLeftPanel()
            refreshMiddlePanel()
            refreshRightPanel()
        end
    end)
end


L3F.RegisterTab("guild.crafts", "Crafts", nil, buildCrafts, {
    parent = "guild",
    preferredWidth = 1100, preferredHeight = 600,
})
