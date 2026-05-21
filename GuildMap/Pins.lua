-- =============================================================
-- L3FTools - GuildMap/Pins.lua
-- =============================================================
-- World map + minimap pin rendering for the guild roster.
-- Pins are class-icon textures wrapped in a circular source-tinted
-- ring (gold=guild; chunk 6 will add group=green and friends=purple).
-- The ring uses the class-circle texture itself sized slightly larger
-- than the icon, so corners stay transparent (no yellow-square halo).
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
-- Layout: name header at the top (class-colored), thin divider, then
-- the three action buttons. Header was a Morphéours request - knowing
-- WHO you're about to whisper/invite without re-reading the tooltip.
local contextMenu
local function getContextMenu()
    if contextMenu then return contextMenu end
    local m = CreateFrame("Frame", "L3FGuildMapPinMenu", UIParent, "BackdropTemplate")
    m:SetSize(140, 116)
    -- FULLSCREEN_DIALOG (one strata above the main window's DIALOG) so
    -- the right-click context menu always appears IN FRONT of L3FTools'
    -- main window if the player has it open underneath the map.
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(99)
    m:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    m:SetBackdropColor(0, 0, 0, 1)
    m:Hide()

    -- Header: player name, class-colored.
    m.nameLabel = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    m.nameLabel:SetPoint("TOP", m, "TOP", 0, -8)
    m.nameLabel:SetJustifyH("CENTER")
    m.nameLabel:SetWidth(124)
    m.nameLabel:SetWordWrap(false)

    -- Thin divider line under the header.
    m.divider = m:CreateTexture(nil, "ARTWORK")
    m.divider:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    m.divider:SetSize(118, 1)
    m.divider:SetPoint("TOP", m, "TOP", 0, -28)

    local function mkBtn(label, anchorY, onClick)
        local b = CreateFrame("Button", nil, m, "UIPanelButtonTemplate")
        b:SetSize(124, 22)
        b:SetPoint("TOP", m, "TOP", 0, anchorY)
        b:SetText(label)
        b:SetScript("OnClick", function()
            onClick(m._targetName)
            m:Hide()
        end)
        return b
    end

    mkBtn("Whisper", -34, function(name)
        if name then ChatFrame_SendTell(name) end
    end)
    mkBtn("Invite", -58, function(name)
        if not name then return end
        if C_PartyInfo and C_PartyInfo.InviteUnit then
            C_PartyInfo.InviteUnit(name)
        elseif InviteUnit then
            InviteUnit(name)
        end
    end)
    mkBtn("Cancel", -82, function() end)

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

local function showContextMenu(name, class)
    local m = getContextMenu()
    m._targetName = name
    if m.nameLabel then
        local color = (class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
            or { r = 1, g = 1, b = 1 }
        m.nameLabel:SetTextColor(color.r, color.g, color.b)
        m.nameLabel:SetText(name or "?")
    end
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    m:Show()
end


-- =============================================================
-- Pin frame factories
-- =============================================================
-- Both .border and .icon use the same class-circle texture; the
-- border is sized to fill the frame (slightly larger than the icon)
-- and tinted to the source color, so only a thin ring of source
-- color shows around the class icon - and the corners of the frame
-- stay transparent (which the old solid-color backdrop did not).
local function applyClassAndSource(frame, class, source)
    local c = SOURCE_BORDER[source] or SOURCE_BORDER.guild
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    local l, r, t, b
    if coords then
        l, r, t, b = coords[1], coords[2], coords[3], coords[4]
    else
        l, r, t, b = 0, 1, 0, 1
    end
    if frame.border then
        frame.border:SetTexture(CLASS_TEXTURE)
        frame.border:SetTexCoord(l, r, t, b)
        frame.border:SetVertexColor(c[1], c[2], c[3], c[4])
    end
    if frame.icon then
        frame.icon:SetTexture(CLASS_TEXTURE)
        frame.icon:SetTexCoord(l, r, t, b)
        frame.icon:SetVertexColor(1, 1, 1, 1)
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

    -- Thin HP bar above the icon. Anchored to the frame top so it
    -- scales naturally with worldPinSize.
    f.hpBg = f:CreateTexture(nil, "ARTWORK")
    f.hpBg:SetColorTexture(0.10, 0.10, 0.10, 0.85)
    f.hpBg:SetSize(20, 3)
    f.hpBg:SetPoint("BOTTOM", f, "TOP", 0, 1)
    f.hpFill = f:CreateTexture(nil, "OVERLAY")
    f.hpFill:SetPoint("LEFT",  f.hpBg, "LEFT",  0, 0)
    f.hpFill:SetSize(20, 3)

    -- Level just above the HP bar (Morphéours: "should almost be touching").
    f.levelText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.levelText:SetPoint("BOTTOM", f.hpBg, "TOP", 0, 0)

    -- Name directly below the icon (Morphéours: was too far below).
    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.nameText:SetPoint("TOP", f, "BOTTOM", 0, 0)

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
            showContextMenu(self._name, self._class)
        end
    end)

    return f
end

-- Minimap pin: the CheesePin icon (same one as the toggle buttons), no
-- per-source tint. Morphéours' explicit ask - the source distinction
-- lives on the WORLD map ring color; the minimap is just "a player is
-- here" and the tooltip carries name/class/level if you want details.
-- 16x16 base size gives the tall cheese-pin shape enough room to read
-- (frame is square; the pin's natural aspect ratio is ~0.66:1, so it
-- renders as a narrow tall pin with horizontal padding).
local MINI_PIN_TEXTURE = "Interface\\AddOns\\L3FTools\\Media\\CheesePin"

local function applyMinimapPin(frame)
    if frame.icon then
        frame.icon:SetTexture(MINI_PIN_TEXTURE)
        frame.icon:SetVertexColor(1, 1, 1, 1)
    end
end

local function buildMinimapPinFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(16, 16)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()

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
            showContextMenu(self._name, self._class)
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

-- Suppress rendering for players the base game is already pinning natively
-- (party + raid). Morphéours' rule: avoid stacking our class-icon on top of
-- the vanilla group dot.
local function isPinnedByGame(name)
    if not name or name == "" then return false end
    if UnitInRaid and UnitInRaid(name) then return true end
    if UnitInParty and UnitInParty(name) then return true end
    return false
end

local function hideBothPins(set)
    if set.world then
        HBDPins:RemoveWorldMapIcon(REF_NAME, set.world); set.world:Hide()
    end
    if set.minimap then
        HBDPins:RemoveMinimapIcon(REF_NAME, set.minimap); set.minimap:Hide()
    end
end

local function upsertPin(short, entry)
    local gm = L3FToolsDB and L3FToolsDB.guildMap or {}
    pins[short] = pins[short] or {}
    local set = pins[short]

    -- Master toggle (pin-visibility button): hide everything immediately.
    -- Takes precedence over the per-surface showOnWorldMap / showOnMinimap.
    if gm.pinsHidden then
        hideBothPins(set)
        return
    end

    -- If the base game already pins this player, hide ours and return early.
    -- (The roster entry stays — Map-tab UI still lists them.)
    if isPinnedByGame(entry.name) then
        hideBothPins(set)
        return
    end

    -- WORLD MAP PIN
    if gm.showOnWorldMap ~= false then
        if not set.world then set.world = buildWorldPinFrame() end
        local wf = set.world
        wf._name  = entry.name or short
        wf._level = entry.level
        wf._class = entry.class
        wf._hp    = entry.hp

        applyClassAndSource(wf, entry.class, entry.source or "guild")

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

        applyMinimapPin(mf)

        local sizeMul = gm.minimapPinSize or 0.8
        mf:SetSize(16 * sizeMul, 16 * sizeMul)

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
local function resyncAll()
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
end
C_Timer.NewTicker(2, resyncAll)
GM.RefreshAll = resyncAll  -- exposed for PinToggle's master-toggle action

-- Re-evaluate immediately when group membership changes - someone joining
-- our party means we stop drawing their pin (game pins them now); someone
-- leaving means we resume.
local groupFrame = CreateFrame("Frame")
groupFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
groupFrame:RegisterEvent("PARTY_LEADER_CHANGED")
groupFrame:SetScript("OnEvent", resyncAll)


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
