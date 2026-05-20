-- =============================================================
-- L3FTools - GuildMap/Pins.lua
-- =============================================================
-- World map + minimap pin rendering for the guild roster.
-- Pins are class-icon textures on a colored backdrop (the border
-- color encodes which source the entry came from - currently only
-- guild=gold; chunk 6 will add group=green and friends=purple).
--
-- Updates are driven by GuildMap.OnRosterUpdated / OnRosterRemoved
-- callbacks fired by GuildMap/Broadcast.lua. A 1s safety ticker
-- catches any edge cases (e.g. the callbacks missed an event during
-- load order).
--
-- HereBeDragons-Pins-2.0 handles all the actual map position math;
-- we only build the frame and call AddWorldMapIconMap / AddMinimapIconMap.
-- =============================================================

local addonName, L3F = ...

local GM = L3F.GuildMap
if not GM then return end

local HBDPins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
if not HBDPins then
    -- HBD not loaded; skip module silently. /l3f gm dump still works.
    return
end

local REF_NAME = "L3FTools"  -- HBD bucket key; used in RemoveWorldMapIcon etc.

GM.pins = GM.pins or {}      -- short -> { world = frame, minimap = frame }
local pins = GM.pins

-- Class circle sprite; Blizzard ships these tcoords in CLASS_ICON_TCOORDS.
local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"

-- Source -> border color. Chunk 6 extends this with group and friend.
local SOURCE_BORDER = {
    guild   = { 1.00, 0.84, 0.00, 1 },  -- gold
    group   = { 0.30, 0.85, 0.30, 1 },  -- green (reserved for chunk 6)
    friend  = { 0.75, 0.40, 0.95, 1 },  -- purple (reserved for chunk 6)
}

-- HP% -> fill color
local function hpColor(pct)
    if pct >= 50 then return 0.10, 0.90, 0.10, 1 end
    if pct >= 25 then return 0.95, 0.80, 0.10, 1 end
    return 0.95, 0.20, 0.10, 1
end


-- =============================================================
-- Context menu (right-click a pin -> whisper / invite)
-- =============================================================
local contextMenu
local function getContextMenu()
    if contextMenu then return contextMenu end
    local m = CreateFrame("Frame", "L3FGuildMapPinMenu", UIParent, "BackdropTemplate")
    m:SetSize(130, 84)
    m:SetFrameStrata("DIALOG")
    m:SetFrameLevel(99)
    m:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    m:SetBackdropColor(0, 0, 0, 1)
    m:Hide()

    local function mkBtn(label, anchorY, onClick)
        local b = CreateFrame("Button", nil, m, "UIPanelButtonTemplate")
        b:SetSize(118, 22)
        b:SetPoint("TOP", m, "TOP", 0, anchorY)
        b:SetText(label)
        b:SetScript("OnClick", function()
            onClick(m._targetName)
            m:Hide()
        end)
        return b
    end

    mkBtn("Whisper", -6, function(name)
        if name then ChatFrame_SendTell(name) end
    end)
    mkBtn("Invite", -30, function(name)
        if not name then return end
        if C_PartyInfo and C_PartyInfo.InviteUnit then
            C_PartyInfo.InviteUnit(name)
        elseif InviteUnit then
            InviteUnit(name)
        end
    end)
    mkBtn("Cancel", -54, function() end)

    -- Auto-hide when mouse leaves.
    m:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() and not InCombatLockdown() then
            self._lingerTime = (self._lingerTime or 0) + 0.05
            if self._lingerTime > 1.0 then self:Hide() end
        else
            self._lingerTime = 0
        end
    end)
    m:HookScript("OnShow", function(self) self._lingerTime = 0 end)

    contextMenu = m
    return m
end

local function showContextMenu(name)
    local m = getContextMenu()
    m._targetName = name
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    m:Show()
end


-- =============================================================
-- Pin frame factories
-- =============================================================
local function applySourceBorder(frame, source)
    local c = SOURCE_BORDER[source] or SOURCE_BORDER.guild
    if frame.border then frame.border:SetColorTexture(c[1], c[2], c[3], c[4]) end
end

local function applyClassTexture(tex, class)
    tex:SetTexture(CLASS_TEXTURE)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function buildWorldPinFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(22, 22)

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetAllPoints()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.icon:SetSize(18, 18)

    -- Name below
    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.nameText:SetPoint("TOP", f, "BOTTOM", 0, -2)

    -- Level above
    f.levelText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.levelText:SetPoint("BOTTOM", f, "TOP", 0, 14)

    -- Thin HP bar above the icon
    f.hpBg = f:CreateTexture(nil, "ARTWORK")
    f.hpBg:SetColorTexture(0.10, 0.10, 0.10, 0.85)
    f.hpBg:SetSize(20, 3)
    f.hpBg:SetPoint("BOTTOM", f, "TOP", 0, 1)
    f.hpFill = f:CreateTexture(nil, "OVERLAY")
    f.hpFill:SetPoint("LEFT",  f.hpBg, "LEFT",  0, 0)
    f.hpFill:SetSize(20, 3)

    f:SetScript("OnEnter", function(self)
        if not self._name then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._name)
        GameTooltip:AddLine(string.format("Level %d %s", self._level or 0, self._class or "?"), 1, 1, 1)
        if self._hp then GameTooltip:AddLine(string.format("HP: %d%%", self._hp), 1, 1, 1) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and self._name then
            showContextMenu(self._name)
        end
    end)

    return f
end

local function buildMinimapPinFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(14, 14)

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetAllPoints()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.icon:SetSize(12, 12)

    f:SetScript("OnEnter", function(self)
        if not self._name then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._name)
        GameTooltip:AddLine(string.format("Level %d %s", self._level or 0, self._class or "?"), 1, 1, 1)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and self._name then
            showContextMenu(self._name)
        end
    end)

    return f
end


-- =============================================================
-- Build/refresh one player's pins from a roster entry
-- =============================================================
local function removePins(short)
    local set = pins[short]
    if not set then return end
    if set.world then
        HBDPins:RemoveWorldMapIcon(REF_NAME, set.world)
        set.world:Hide()
    end
    if set.minimap then
        HBDPins:RemoveMinimapIcon(REF_NAME, set.minimap)
        set.minimap:Hide()
    end
end

local function upsertPin(short, entry)
    local gm = L3FToolsDB and L3FToolsDB.guildMap or {}
    pins[short] = pins[short] or {}
    local set = pins[short]

    -- WORLD MAP PIN
    if gm.showOnWorldMap ~= false then
        if not set.world then set.world = buildWorldPinFrame() end
        local wf = set.world
        wf._name  = entry.name or short
        wf._level = entry.level
        wf._class = entry.class
        wf._hp    = entry.hp

        applySourceBorder(wf, entry.source or "guild")
        applyClassTexture(wf.icon, entry.class)

        local sizeMul = gm.worldPinSize or 1.0
        wf:SetSize(22 * sizeMul, 22 * sizeMul)
        wf.icon:SetSize(18 * sizeMul, 18 * sizeMul)
        wf.hpBg:SetSize(20 * sizeMul, 3 * sizeMul)

        if gm.showName then
            wf.nameText:Show(); wf.nameText:SetText(wf._name)
        else wf.nameText:Hide() end

        if gm.showLevel then
            wf.levelText:Show(); wf.levelText:SetText(tostring(wf._level or "?"))
        else wf.levelText:Hide() end

        if gm.showHP then
            wf.hpBg:Show()
            wf.hpFill:Show()
            local pct = math.max(0, math.min(100, wf._hp or 100))
            local r, g, b, a = hpColor(pct)
            wf.hpFill:SetColorTexture(r, g, b, a)
            wf.hpFill:SetSize(math.max(1, (20 * sizeMul) * pct / 100), 3 * sizeMul)
        else
            wf.hpBg:Hide(); wf.hpFill:Hide()
        end

        -- HBD: remove the previous registration (no-op if not registered)
        -- then add at the current map+xy. Cheap; HBD batches updates.
        HBDPins:RemoveWorldMapIcon(REF_NAME, wf)
        HBDPins:AddWorldMapIconMap(REF_NAME, wf, entry.mapID, entry.x, entry.y,
            HBD_PINS_WORLDMAP_SHOW_WORLD)
    elseif set.world then
        HBDPins:RemoveWorldMapIcon(REF_NAME, set.world)
        set.world:Hide()
    end

    -- MINIMAP PIN
    if gm.showOnMinimap ~= false then
        if not set.minimap then set.minimap = buildMinimapPinFrame() end
        local mf = set.minimap
        mf._name  = entry.name or short
        mf._level = entry.level
        mf._class = entry.class

        applySourceBorder(mf, entry.source or "guild")
        applyClassTexture(mf.icon, entry.class)

        local sizeMul = gm.minimapPinSize or 1.0
        mf:SetSize(14 * sizeMul, 14 * sizeMul)
        mf.icon:SetSize(12 * sizeMul, 12 * sizeMul)

        HBDPins:RemoveMinimapIcon(REF_NAME, mf)
        -- showInParentZone=true (let sub-zone pins show on the parent map),
        -- floatOnEdge=false. floatOnEdge=true made distant guildies render
        -- at the minimap rim like a direction indicator - Morphéours
        -- reported pins showing "even at 20km away". With it false, pins
        -- only render when the guildie is genuinely inside the minimap's
        -- visible range.
        HBDPins:AddMinimapIconMap(REF_NAME, mf, entry.mapID, entry.x, entry.y, true, false)
    elseif set.minimap then
        HBDPins:RemoveMinimapIcon(REF_NAME, set.minimap)
        set.minimap:Hide()
    end
end


-- =============================================================
-- Hook into the broadcast module's roster events
-- =============================================================
function GM.OnRosterUpdated(short)
    local roster = GM.GetRoster and GM.GetRoster() or {}
    local entry = roster[short]
    if entry then upsertPin(short, entry) end
end

function GM.OnRosterRemoved(short)
    removePins(short)
    pins[short] = nil
end

-- Safety net: also resync every 2s in case events got missed during
-- load. Cheap (one walk over roster) and self-healing.
C_Timer.NewTicker(2, function()
    local roster = GM.GetRoster and GM.GetRoster() or {}
    -- Add/refresh pins for everyone in the roster.
    for short, entry in pairs(roster) do
        upsertPin(short, entry)
    end
    -- Remove pins for players no longer in the roster.
    for short in pairs(pins) do
        if not roster[short] then
            removePins(short)
            pins[short] = nil
        end
    end
end)


-- =============================================================
-- Public surface
-- =============================================================
function GM.ClearAllPins()
    for short in pairs(pins) do
        removePins(short)
    end
    pins = {}
    GM.pins = pins
    if HBDPins.RemoveAllWorldMapIcons then HBDPins:RemoveAllWorldMapIcons(REF_NAME) end
    if HBDPins.RemoveAllMinimapIcons  then HBDPins:RemoveAllMinimapIcons(REF_NAME)  end
end
