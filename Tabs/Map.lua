-- =============================================================
-- L3FTools - Tabs/Map.lua
-- =============================================================
-- Control panel for the live guild-map module. The actual pins
-- live in GuildMap/Pins.lua (rendered through HereBeDragons); this
-- tab is the user-facing surface: sharing toggles, display toggles,
-- privacy reset, and a roster of who is currently broadcasting to
-- you (sorted by class per Morphéours' B.3 answer).
-- =============================================================

local addonName, L3F = ...

local function db()
    return (L3F.db and L3F.db.guildMap) or (L3FToolsDB and L3FToolsDB.guildMap) or {}
end

local function refreshPins()
    if L3F.GuildMap and L3F.GuildMap.RefreshAll then L3F.GuildMap.RefreshAll() end
end


-- =============================================================
-- Section helpers
-- =============================================================
local function header(parent, anchor, text, dx, dy)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx or 0, dy or -12)
    h:SetText("|cffffd100" .. text .. "|r")
    return h
end

local function checkbox(parent, anchor, label, getter, setter, dy)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -4, dy or -2)
    cb:SetChecked(getter())
    cb.text:SetText("  " .. label)
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    return cb
end

local function slider(parent, anchor, name, label, minV, maxV, step, getter, setter)
    local s = CreateFrame("Slider", "L3FMapTab_" .. name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -22)
    s:SetWidth(220)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetValue(getter())
    _G[s:GetName() .. "Low"]:SetText(tostring(minV))
    _G[s:GetName() .. "High"]:SetText(tostring(maxV))
    _G[s:GetName() .. "Text"]:SetText(string.format("%s: %.1f", label, getter()))
    s:SetScript("OnValueChanged", function(self, v)
        setter(v)
        _G[self:GetName() .. "Text"]:SetText(string.format("%s: %.1f", label, v))
        refreshPins()
    end)
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

    -- Scroll frame
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

        -- Bucket by class
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

        -- Sorted class order
        local classes = {}
        for c in pairs(byClass) do table.insert(classes, c) end
        table.sort(classes)

        local y = 4
        for _, cls in ipairs(classes) do
            -- Class header
            local h = getRow()
            h:SetFontObject("GameFontNormal")
            local color = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls])
                or { r = 1, g = 1, b = 1 }
            h:SetTextColor(color.r, color.g, color.b)
            h:SetText(CLASS_NAME[cls] or cls)
            h:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
            y = y + 18

            -- Within-class: sort alphabetically by name
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

        -- Hide leftover rows from the pool
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

    -- Hint under the title
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetText("Live guild positions on the world map and minimap.")

    -- ---------- LEFT COLUMN: controls ----------
    -- Sharing
    local sharingHdr = header(parent, hint, "Sharing")

    local cbShare = checkbox(parent, sharingHdr,
        "Share my position with guildmates",
        function() return db().shareWithGuild end,
        function(v)
            db().shareWithGuild = v
            print("|cffffd100L3FTools|r position sharing "
                .. (v and "|cff00ff00enabled|r" or "|cffff5555disabled|r"))
        end,
        -4)

    local cbPause = checkbox(parent, cbShare,
        "Pause sharing inside raids and battlegrounds",
        function() return db().pauseInInstance end,
        function(v) db().pauseInInstance = v end)

    -- Display
    local displayHdr = header(parent, cbPause, "Display")

    local cbWorld = checkbox(parent, displayHdr,
        "Pins on world map",
        function() return db().showOnWorldMap end,
        function(v) db().showOnWorldMap = v; refreshPins() end,
        -4)

    local cbMini = checkbox(parent, cbWorld,
        "Pins on minimap",
        function() return db().showOnMinimap end,
        function(v) db().showOnMinimap = v; refreshPins() end)

    local cbName = checkbox(parent, cbMini,
        "Show player name on pin",
        function() return db().showName end,
        function(v) db().showName = v; refreshPins() end)

    local cbLevel = checkbox(parent, cbName,
        "Show level on pin",
        function() return db().showLevel end,
        function(v) db().showLevel = v; refreshPins() end)

    local cbHP = checkbox(parent, cbLevel,
        "Show HP bar on pin",
        function() return db().showHP end,
        function(v) db().showHP = v; refreshPins() end)

    local sWorld = slider(parent, cbHP, "WorldSize", "World pin size",
        0.5, 2.0, 0.1,
        function() return db().worldPinSize or 1.0 end,
        function(v) db().worldPinSize = v end)

    local sMini  = slider(parent, sWorld, "MinimapSize", "Minimap pin size",
        0.5, 2.0, 0.1,
        function() return db().minimapPinSize or 1.0 end,
        function(v) db().minimapPinSize = v end)

    -- Privacy
    local privacyHdr = header(parent, sMini, "Privacy", 0, -18)

    local btnPrivacy = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btnPrivacy:SetSize(220, 22)
    btnPrivacy:SetPoint("TOPLEFT", privacyHdr, "BOTTOMLEFT", 0, -6)
    btnPrivacy:SetText("Re-show first-install popup")
    btnPrivacy:SetScript("OnClick", function()
        if L3F.GuildMap and L3F.GuildMap.ResetPrivacyAnswer then
            L3F.GuildMap.ResetPrivacyAnswer()
        end
        if L3F.GuildMap and L3F.GuildMap.ShowPrivacyPopup then
            L3F.GuildMap.ShowPrivacyPopup()
        end
    end)

    -- ---------- RIGHT COLUMN: roster ----------
    local roster, refreshRoster = buildRosterPanel(parent)
    roster:SetPoint("TOPLEFT",     parent, "TOPLEFT",     310, -52)
    roster:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16,  16)

    -- Refresh roster when the tab becomes visible, and periodically while
    -- shown so new broadcasts surface within 2 seconds.
    parent:HookScript("OnShow", function()
        refreshRoster()
    end)
    if parent:IsShown() then refreshRoster() end

    local ticker = C_Timer.NewTicker(2, function()
        if parent:IsShown() then refreshRoster() end
    end)
    parent._mapTabTicker = ticker
end

L3F.RegisterTab("map", "Map", nil, buildMap)
