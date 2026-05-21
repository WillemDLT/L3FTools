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
--   * Left column wrapped in a scroll frame - keeps Privacy reachable
--     no matter how short the window gets, and prevents the left drift
--     that came from chaining elements to each others' BOTTOMLEFT
--   * Right column: roster panel (its own scroll frame inside)
-- =============================================================

local addonName, L3F = ...

local function db()
    return (L3F.db and L3F.db.guildMap) or (L3FToolsDB and L3FToolsDB.guildMap) or {}
end

local function refreshPins()
    if L3F.GuildMap and L3F.GuildMap.RefreshAll then L3F.GuildMap.RefreshAll() end
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
-- Roster panel (class-sorted list of who is broadcasting to you)
-- =============================================================
local CLASS_NAME = LOCALIZED_CLASS_NAMES_MALE or {}

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
    title:SetText("|cffffd100Broadcasting to you|r")

    local count = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -10)
    count:SetText("0 players")

    local sf = CreateFrame("ScrollFrame", "L3FMapTabRosterScroll", box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     box, "TOPLEFT",     8,  -28)
    sf:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 8)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    child._rows = {}

    local empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("CENTER", box, "CENTER", 0, 0)
    empty:SetText("|cffaaaaaaNobody is broadcasting yet.|r")
    empty:SetJustifyH("CENTER")

    local rowIdx = 0
    local function getRow()
        rowIdx = rowIdx + 1
        local r = child._rows[rowIdx]
        if not r then
            r = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            child._rows[rowIdx] = r
        end
        r:ClearAllPoints()
        r:Show()
        return r
    end

    local function refresh()
        rowIdx = 0
        local roster = (L3F.GuildMap and L3F.GuildMap.GetRoster and L3F.GuildMap.GetRoster()) or {}

        local byClass, total = {}, 0
        for _, entry in pairs(roster) do
            total = total + 1
            local cls = entry.class or "UNKNOWN"
            byClass[cls] = byClass[cls] or {}
            table.insert(byClass[cls], entry)
        end
        count:SetText(total .. " player" .. (total == 1 and "" or "s"))

        if total == 0 then
            empty:Show()
            for i = 1, #child._rows do child._rows[i]:Hide() end
            child:SetHeight(1)
            return
        end
        empty:Hide()

        local classes = {}
        for c in pairs(byClass) do table.insert(classes, c) end
        table.sort(classes)

        local y = 4
        for _, cls in ipairs(classes) do
            local h = getRow()
            h:SetFontObject("GameFontNormal")
            local color = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls])
                or { r = 1, g = 1, b = 1 }
            h:SetTextColor(color.r, color.g, color.b)
            h:SetText(CLASS_NAME[cls] or cls)
            h:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
            y = y + 18

            table.sort(byClass[cls], function(a, b)
                return (a.name or "") < (b.name or "")
            end)

            for _, entry in ipairs(byClass[cls]) do
                local r = getRow()
                r:SetFontObject("GameFontNormalSmall")
                r:SetTextColor(0.9, 0.9, 0.9)
                r:SetText(string.format("    %s  |cff888888L%d|r",
                    entry.name or "?", entry.level or 0))
                r:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -y)
                y = y + 14
            end
            y = y + 4
        end

        for i = rowIdx + 1, #child._rows do child._rows[i]:Hide() end
        child:SetSize(sf:GetWidth(), math.max(y, sf:GetHeight()))
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
    -- The scroll frame keeps Privacy reachable even when the window
    -- is collapsed below the control stack's natural height.
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
    S:checkbox("Pins on world map",
        function() return db().showOnWorldMap end,
        function(v) db().showOnWorldMap = v end,
        refreshPins)
    S:checkbox("Pins on minimap",
        function() return db().showOnMinimap end,
        function(v) db().showOnMinimap = v end,
        refreshPins)
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

    S:gap(10)

    -- Privacy
    S:header("Privacy")
    S:button("Re-show first-install popup", 220, 22, function()
        if L3F.GuildMap and L3F.GuildMap.ResetPrivacyAnswer then
            L3F.GuildMap.ResetPrivacyAnswer()
        end
        if L3F.GuildMap and L3F.GuildMap.ShowPrivacyPopup then
            L3F.GuildMap.ShowPrivacyPopup()
        end
    end)

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
