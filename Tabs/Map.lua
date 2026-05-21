-- =============================================================
-- L3FTools - Tabs/Map.lua
-- =============================================================
-- Control panel for the live guild-map module. The actual pins
-- live in GuildMap/Pins.lua (rendered through HereBeDragons); this
-- tab is the user-facing surface: sharing toggles, display toggles,
-- privacy reset, and a roster of who is currently broadcasting to
-- you (sorted by class per Morphéours' B.3 answer).
--
-- Layout:
--   * Title + hint anchored to the tab parent (always visible)
--   * Left column wrapped in a scroll frame - prevents the left drift
--     that came from chaining elements to each others' BOTTOMLEFT, and
--     keeps everything reachable when the window is collapsed short
--   * Right column: roster panel (its own scroll frame inside)
-- =============================================================

local addonName, L3F = ...

local function db()
    return (L3F.db and L3F.db.guildMap) or (L3FToolsDB and L3FToolsDB.guildMap) or {}
end

local function refreshPins()
    if L3F.GuildMap and L3F.GuildMap.RefreshAll then L3F.GuildMap.RefreshAll() end
end

-- Pin-visibility changes need to ripple to the world-map + minimap
-- toggle buttons (dim, tooltip), the live pins themselves, AND back
-- to our own checkboxes if the change came from a button. The
-- NotifyPinSettingsChanged entrypoint in PinToggle.lua handles all of
-- that, and uses our L3F.MapTab_RefreshCheckboxes (registered below)
-- to push state back to us on the way back.
local function notifyPinVisibility()
    if L3F.GuildMap and L3F.GuildMap.NotifyPinSettingsChanged then
        L3F.GuildMap.NotifyPinSettingsChanged()
    else
        refreshPins()  -- fall back to bare re-render if PinToggle missing
    end
end


-- =============================================================
-- Stack helper - every widget anchors to scrollChild's TOPLEFT
-- with a fixed x indent, and a running y cursor stacks them. This
-- replaces the previous "anchor to previous BOTTOMLEFT with x=-4"
-- pattern that caused the column to drift left as it grew.
-- =============================================================
local function newStack(parent, indent, cbIndent)
    local s = {
        parent   = parent,
        indent   = indent or 12,
        cbIndent = cbIndent or 12,
        y        = 8,           -- top padding inside the scroll child
    }

    function s:gap(px) self.y = self.y + (px or 8) end

    function s:header(text)
        local h = self.parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.indent, -self.y)
        h:SetText("|cffffd100" .. text .. "|r")
        self.y = self.y + 20
        return h
    end

    function s:checkbox(label, getter, setter, onChanged)
        local cb = CreateFrame("CheckButton", nil, self.parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.cbIndent, -self.y)
        cb:SetChecked(getter())
        cb.text:SetText("  " .. label)
        cb:SetScript("OnClick", function(self_)
            setter(self_:GetChecked())
            if onChanged then onChanged() end
        end)
        self.y = self.y + 24
        return cb
    end

    function s:slider(name, label, minV, maxV, step, getter, setter, onChanged)
        -- OptionsSliderTemplate's label sits ABOVE the slider, so we
        -- pad y by 14 before placing the slider's own top-left.
        local sl = CreateFrame("Slider", "L3FMapTab_" .. name, self.parent, "OptionsSliderTemplate")
        sl:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.cbIndent + 4, -(self.y + 14))
        sl:SetWidth(220)
        sl:SetMinMaxValues(minV, maxV)
        sl:SetValueStep(step)
        sl:SetObeyStepOnDrag(true)
        sl:SetValue(getter())
        _G[sl:GetName() .. "Low"]:SetText(tostring(minV))
        _G[sl:GetName() .. "High"]:SetText(tostring(maxV))
        _G[sl:GetName() .. "Text"]:SetText(string.format("%s: %.1f", label, getter()))
        sl:SetScript("OnValueChanged", function(self_, v)
            setter(v)
            _G[self_:GetName() .. "Text"]:SetText(string.format("%s: %.1f", label, v))
            if onChanged then onChanged() end
        end)
        -- 14 (label above) + 17 (track) + 12 (Low/High labels below) + 4 pad
        self.y = self.y + 14 + 17 + 12 + 4
        return sl
    end

    function s:button(label, w, h, onClick)
        local b = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
        b:SetSize(w or 220, h or 22)
        b:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.cbIndent, -self.y)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        self.y = self.y + (h or 22) + 4
        return b
    end

    function s:finalize()
        if self.parent.SetHeight then
            self.parent:SetHeight(math.max(self.y + 8, 1))
        end
    end

    return s
end


-- =============================================================
-- Roster panel
-- =============================================================
-- A single scrollable list of everyone we know about: each broadcaster
-- (guild source = currently in roster from a GUILD packet; friend
-- source = from a WHISPER packet) plus, for the "nag list" use case,
-- online guildies who AREN'T broadcasting (i.e. don't run L3FTools).
-- Filter dropdown narrows the list to one of:
--   All / Guild / Friends / Not running L3F
-- Search box filters by case-insensitive substring on the player name.
-- Click handling:
--   Left-click on a broadcasting entry opens the world map and switches
--     to that player's mapID.
--   Right-click on any entry (broadcasting or not) opens the same
--     Whisper / Invite / Cancel menu the world-map pin already has.
local ROW_HEIGHT = 18

local FILTER_OPTIONS = {
    { value = "all",        label = "All" },
    { value = "guild",      label = "Guild" },
    { value = "friend",     label = "Friends" },
    { value = "notrunning", label = "Not running L3F" },
}

local function panWorldMapTo(mapID)
    if not mapID or mapID == 0 then return end
    if not WorldMapFrame then return end
    if not WorldMapFrame:IsShown() then
        if ToggleWorldMap then ToggleWorldMap() else WorldMapFrame:Show() end
    end
    if WorldMapFrame.SetMapID then
        WorldMapFrame:SetMapID(mapID)
    elseif SetMapByID then
        SetMapByID(mapID)
    end
end

local function buildRosterPanel(parent)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.45)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
    title:SetText("|cffffd100Roster|r")

    local count = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -10)
    count:SetText("")

    -- Filter dropdown (top-left under the title)
    local currentFilter = "all"
    local filter = CreateFrame("Frame", "L3FMapTabFilterDD", box, "UIDropDownMenuTemplate")
    filter:SetPoint("TOPLEFT", box, "TOPLEFT", -6, -26)
    UIDropDownMenu_SetWidth(filter, 110)
    UIDropDownMenu_SetText(filter, "All")
    local refresh  -- forward declaration so the dropdown can call it
    UIDropDownMenu_Initialize(filter, function(self, level)
        for _, opt in ipairs(FILTER_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.checked = (currentFilter == opt.value)
            info.func = function()
                currentFilter = opt.value
                UIDropDownMenu_SetText(filter, opt.label)
                CloseDropDownMenus()
                if refresh then refresh() end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Search box (top-right under the count)
    local currentSearch = ""
    local search = CreateFrame("EditBox", "L3FMapTabSearchBox", box, "InputBoxTemplate")
    search:SetAutoFocus(false)
    search:SetSize(120, 18)
    search:SetPoint("TOPRIGHT", box, "TOPRIGHT", -16, -28)
    search:SetMaxLetters(20)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function(self)
        currentSearch = (self:GetText() or ""):lower()
        if refresh then refresh() end
    end)
    local searchHint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("RIGHT", search, "LEFT", -4, 0)
    searchHint:SetText("Search:")

    -- Scrollable list, sitting under filter + search
    local sf = CreateFrame("ScrollFrame", "L3FMapTabRosterScroll", box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     box, "TOPLEFT",     8,  -56)
    sf:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 8)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    child._rows = {}

    local empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("CENTER", sf, "CENTER", 0, 0)
    empty:SetText("|cffaaaaaaNobody to show.|r")
    empty:SetJustifyH("CENTER")

    -- Row factory: each row is a clickable Button with a FontString inside.
    -- Pool grows lazily; refresh() hides any leftover rows from prior renders.
    local function getRow(idx)
        local r = child._rows[idx]
        if not r then
            r = CreateFrame("Button", nil, child)
            r:SetHeight(ROW_HEIGHT)
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            r.hl = r:CreateTexture(nil, "BACKGROUND")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0)

            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.text:SetPoint("LEFT",  r, "LEFT",  6, 0)
            r.text:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.text:SetJustifyH("LEFT")

            r:SetScript("OnEnter", function(self)
                self.hl:SetColorTexture(1, 1, 1, 0.10)
            end)
            r:SetScript("OnLeave", function(self)
                self.hl:SetColorTexture(1, 1, 1, 0)
            end)
            r:SetScript("OnClick", function(self, button)
                local e = self._entry
                if not e then return end
                if button == "LeftButton" then
                    -- Pan only makes sense for someone we're actively
                    -- receiving from; a "not running L3F" guildie has no
                    -- pin to pan to.
                    if e.broadcasting and e.mapID then panWorldMapTo(e.mapID) end
                elseif button == "RightButton" then
                    if L3F.GuildMap and L3F.GuildMap.OpenPinContextMenu then
                        L3F.GuildMap.OpenPinContextMenu(e.name, e.class)
                    end
                end
            end)

            child._rows[idx] = r
        end
        r:Show()
        return r
    end

    local function passesFilter(e)
        if currentFilter == "all"        then return true end
        if currentFilter == "guild"      then return e.source == "guild" end
        if currentFilter == "friend"     then return e.source == "friend" end
        if currentFilter == "notrunning" then
            return e.source == "guild" and not e.broadcasting
        end
        return true
    end

    local function passesSearch(e)
        if currentSearch == "" then return true end
        return string.find((e.name or ""):lower(), currentSearch, 1, true) ~= nil
    end

    refresh = function()
        local roster  = (L3F.GuildMap and L3F.GuildMap.GetRoster         and L3F.GuildMap.GetRoster())         or {}
        local onlineG = (L3F.GuildMap and L3F.GuildMap.GetOnlineGuildies and L3F.GuildMap.GetOnlineGuildies()) or {}
        local onlineF = (L3F.GuildMap and L3F.GuildMap.GetOnlineFriends  and L3F.GuildMap.GetOnlineFriends())  or {}

        -- Build the unified entry list. Broadcasters come from the roster
        -- (we know their live x/y/mapID/HP). Non-broadcasting guildies
        -- come from the guild roster snapshot - we know their name +
        -- level + class but they have no pin. isGuildie / isFriend are
        -- looked up from the online sets, NOT from entry.source - source
        -- only records which CHANNEL carried the most recent broadcast,
        -- not the actual relationship(s).
        local entries = {}
        for short, entry in pairs(roster) do
            table.insert(entries, {
                name         = entry.name or short,
                level        = entry.level,
                class        = entry.class,
                source       = entry.source,
                broadcasting = true,
                mapID        = entry.mapID,
                isGuildie    = onlineG[short] ~= nil,
                isFriend     = onlineF[short] ~= nil,
            })
        end
        for short, info in pairs(onlineG) do
            if not roster[short] then
                table.insert(entries, {
                    name         = info.name,
                    level        = info.level,
                    class        = info.class,
                    source       = "guild",
                    broadcasting = false,
                    isGuildie    = true,
                    isFriend     = onlineF[short] ~= nil,
                })
            end
        end

        local filtered = {}
        for _, e in ipairs(entries) do
            if passesFilter(e) and passesSearch(e) then
                table.insert(filtered, e)
            end
        end

        -- Sort: broadcasters first, then alphabetical by name within
        -- each group. Inside broadcasters, friends end up sorted in
        -- among guildies alphabetically (the filter dropdown is the
        -- way to isolate one source).
        table.sort(filtered, function(a, b)
            if a.broadcasting ~= b.broadcasting then
                return a.broadcasting
            end
            return (a.name or "") < (b.name or "")
        end)

        count:SetText(#filtered .. " player" .. (#filtered == 1 and "" or "s"))

        if #filtered == 0 then
            empty:Show()
            for i = 1, #child._rows do child._rows[i]:Hide() end
            child:SetHeight(1)
            return
        end
        empty:Hide()

        local sfWidth = sf:GetWidth()
        if not sfWidth or sfWidth < 50 then sfWidth = 260 end

        for i, e in ipairs(filtered) do
            local r = getRow(i)
            r._entry = e
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -(i - 1) * ROW_HEIGHT)
            r:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)

            local color = (e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class])
                or { r = 0.85, g = 0.85, b = 0.85 }
            local hex = string.format("%02x%02x%02x",
                math.floor(color.r * 255 + 0.5),
                math.floor(color.g * 255 + 0.5),
                math.floor(color.b * 255 + 0.5))

            local nameStr, levelStr, suffix
            if e.broadcasting then
                nameStr  = string.format("|cff%s%s|r", hex, e.name or "?")
                levelStr = string.format("|cff888888L%d|r", e.level or 0)
                -- Membership-based tag, NOT broadcast-channel based. A
                -- player who is both a guildy and a friend gets the
                -- combined tag with each label in its own color (gold
                -- for guild, purple for friend, mirroring the world-map
                -- ring colors in SOURCE_BORDER).
                local GUILD_TAG  = "|cffffd100(Guildy)|r"
                local FRIEND_TAG = "|cff9966ff(Friend)|r"
                if e.isGuildie and e.isFriend then
                    suffix = "  " .. GUILD_TAG .. " & " .. FRIEND_TAG
                elseif e.isFriend then
                    suffix = "  " .. FRIEND_TAG
                elseif e.isGuildie then
                    suffix = "  " .. GUILD_TAG
                else
                    suffix = ""
                end
            else
                -- Greyed: online guildie not running L3FTools.
                nameStr  = string.format("|cff666666%s|r", e.name or "?")
                levelStr = string.format("|cff555555L%d|r", e.level or 0)
                suffix   = "  |cff555555(not running L3F)|r"
            end
            r.text:SetText(nameStr .. "  " .. levelStr .. suffix)
        end

        for i = #filtered + 1, #child._rows do child._rows[i]:Hide() end
        child:SetSize(sfWidth, math.max(#filtered * ROW_HEIGHT + 4, sf:GetHeight() or 1))
    end

    return box, refresh
end


-- =============================================================
-- Tab build
-- =============================================================
local function buildMap(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    title:SetText("Map")

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetText("Live guild positions on the world map and minimap.")

    -- ---------- LEFT COLUMN: scrollable control stack ----------
    -- The scroll frame keeps every control reachable even when the
    -- window is collapsed below the control stack's natural height.
    local leftScroll = CreateFrame("ScrollFrame", "L3FMapTabLeftScroll", parent, "UIPanelScrollFrameTemplate")
    leftScroll:SetPoint("TOPLEFT",     parent, "TOPLEFT",     8,  -52)
    leftScroll:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  8,   16)
    leftScroll:SetWidth(294)

    local leftChild = CreateFrame("Frame", nil, leftScroll)
    leftChild:SetSize(280, 1)
    leftScroll:SetScrollChild(leftChild)

    local S = newStack(leftChild, 4, 4)

    -- Sharing
    S:header("Sharing")
    S:checkbox(
        "Share my position with guildmates",
        function() return db().shareWithGuild end,
        function(v)
            db().shareWithGuild = v
            print("|cffffd100L3FTools|r guild position sharing "
                .. (v and "|cff00ff00enabled|r" or "|cffff5555disabled|r"))
        end)
    S:checkbox(
        "Share my position with friends",
        function() return db().shareWithFriends end,
        function(v)
            db().shareWithFriends = v
            -- Kick the friend list right away so the first WHISPER fan-out
            -- doesn't wait up to 15s for the periodic refresh.
            if v and L3F.GuildMap and L3F.GuildMap.RequestFriendList then
                L3F.GuildMap.RequestFriendList()
            end
            print("|cffffd100L3FTools|r friend position sharing "
                .. (v and "|cff00ff00enabled|r" or "|cffff5555disabled|r"))
        end)
    S:checkbox(
        "Pause sharing inside raids and battlegrounds",
        function() return db().pauseInInstance end,
        function(v) db().pauseInInstance = v end)

    S:gap(8)

    -- Display
    S:header("Display")
    local cbWorld = S:checkbox("Pins on world map",
        function() return db().showOnWorldMap end,
        function(v) db().showOnWorldMap = v end,
        notifyPinVisibility)
    local cbMini = S:checkbox("Pins on minimap",
        function() return db().showOnMinimap end,
        function(v) db().showOnMinimap = v end,
        notifyPinVisibility)

    -- Expose a refresher so the toggle buttons (PinToggle.lua) can push
    -- their state back into our checkbox visuals after the user clicks
    -- a button. Without this, the box stays stale until the tab is
    -- closed and reopened.
    L3F.MapTab_RefreshCheckboxes = function()
        if cbWorld then cbWorld:SetChecked(db().showOnWorldMap) end
        if cbMini  then cbMini:SetChecked(db().showOnMinimap)  end
    end
    S:checkbox("Show player name on pin",
        function() return db().showName end,
        function(v) db().showName = v end,
        refreshPins)
    S:checkbox("Show level on pin",
        function() return db().showLevel end,
        function(v) db().showLevel = v end,
        refreshPins)
    S:checkbox("Show HP bar on pin",
        function() return db().showHP end,
        function(v) db().showHP = v end,
        refreshPins)
    S:slider("WorldSize", "World pin size", 0.5, 2.0, 0.1,
        function() return db().worldPinSize or 0.8 end,
        function(v) db().worldPinSize = v end,
        refreshPins)
    S:slider("MinimapSize", "Minimap pin size", 0.5, 2.0, 0.1,
        function() return db().minimapPinSize or 0.8 end,
        function(v) db().minimapPinSize = v end,
        refreshPins)

    S:finalize()

    -- ---------- RIGHT COLUMN: roster ----------
    local roster, refreshRoster = buildRosterPanel(parent)
    roster:SetPoint("TOPLEFT",     parent, "TOPLEFT",     320, -52)
    roster:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16,  16)

    parent:HookScript("OnShow", function() refreshRoster() end)
    if parent:IsShown() then refreshRoster() end

    parent._mapTabTicker = C_Timer.NewTicker(2, function()
        if parent:IsShown() then refreshRoster() end
    end)
end

-- minWidth: enough for the 294-wide left scroll + the ~300-wide
-- roster panel + chrome. minHeight: even with the scroll frame, we
-- want the window to at least show the roster comfortably.
L3F.RegisterTab("map", "Map", nil, buildMap, { minWidth = 720, minHeight = 460 })
