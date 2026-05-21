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
local SKULL_TEXTURE = "Interface\\AddOns\\L3FTools\\Media\\Skull"

-- Role badges (LFG portrait icons). Self-assigned by the broadcaster
-- from the Map tab; arrive as entry.roles, a string of T/H/D chars in
-- canonical order. Each role lives in a fixed corner of the world pin
-- so the layout is predictable regardless of which combination a
-- player picks.
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_TCOORDS = {
    T = { 0,     19/64, 22/64, 41/64 },  -- Tank
    H = { 20/64, 39/64, 1/64,  20/64 },  -- Healer
    D = { 20/64, 39/64, 22/64, 41/64 },  -- DPS (Damager)
}
local ROLE_COLORS = {
    T = { 0.27, 0.42, 0.69 },  -- tank blue
    H = { 0.27, 0.62, 0.27 },  -- healer green
    D = { 0.78, 0.25, 0.27 },  -- dps red
}
local ROLE_LABELS = { T = "Tank", H = "Healer", D = "DPS" }
local ROLE_BADGE_BASE = 10  -- multiplied by worldPinSize at runtime

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

-- Wrapper that adds the dead-broadcaster swap. The skull stays for the
-- WHOLE death sequence - corpse (hp==0) AND ghost (UnitIsDeadOrGhost on
-- the broadcaster side, carried as entry.dead in the packet). Ghosts
-- have non-zero hp, so the hp==0 check alone would drop the skull the
-- moment the player releases their spirit. Source-tinted ring + HP bar
-- stay on top so you can still see who and where. Re-runs on every
-- roster update + every 2s safety tick, so revival flips the icon back.
local function applyWorldPinAppearance(frame, class, source, isDead)
    applyClassAndSource(frame, class, source)
    if frame.icon and isDead then
        frame.icon:SetTexture(SKULL_TEXTURE)
        frame.icon:SetTexCoord(0, 1, 0, 1)
        frame.icon:SetVertexColor(1, 1, 1, 1)
    end
end


-- =============================================================
-- Smooth movement: linear lerp between samples
-- =============================================================
-- Lerp state lives on pins[short].lerp (set-level) so the world pin
-- and the minimap pin for the same broadcaster share it. Each frame
-- has its own OnUpdate that looks up the set via self._short and
-- applies the lerped position through its own HBD surface call.
local LERP_TICK  = 0.1     -- 10 Hz HBD re-position cadence
local LERP_STALL = 6.0     -- after this long with no new sample, snap and stop animating

local function lerp(a, b, t) return a + (b - a) * t end

local function computeLerp(L, now)
    if not L.prevX or not L.nextX then
        return L.nextX or L.prevX, L.nextY or L.prevY
    end
    local dt = (L.nextT or 0) - (L.prevT or 0)
    if dt <= 0.05 then return L.nextX, L.nextY end
    local t = (now - L.prevT) / dt
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return lerp(L.prevX, L.nextX, t), lerp(L.prevY, L.nextY, t)
end

-- Called once per broadcast (from upsertPin) to advance the lerp:
-- "prev" becomes the currently-rendered position, "next" is what we
-- just received, and the animation is sized to the gap since the last
-- broadcast. Returns the starting position so the initial paint can
-- use it.
local function updateLerpState(set, entry)
    set.lerp = set.lerp or {}
    local L = set.lerp
    local now = GetTime()
    local mapChanged = L.mapID and (L.mapID ~= entry.mapID)
    local curX, curY
    if mapChanged or not L.nextX then
        curX, curY = entry.x, entry.y
    else
        curX, curY = computeLerp(L, now)
    end
    local dtEstimate = L.lastBroadcast and (now - L.lastBroadcast) or nil
    if not dtEstimate or dtEstimate < 0.2 or dtEstimate > LERP_STALL then
        dtEstimate = 1.5
    end
    L.prevX, L.prevY, L.prevT = curX,    curY,    now
    L.nextX, L.nextY, L.nextT = entry.x, entry.y, now + dtEstimate
    L.lastBroadcast = now
    L.mapID = entry.mapID
    return curX, curY
end

-- Shared OnUpdate logic. Caller passes an applyPosition function that
-- knows how to push the lerped (mapID, x, y) into its HBD surface.
-- World pin uses Remove+Add (canvas pool would otherwise leak); minimap
-- pin just uses Add (HBD's minimap path reuses minimapPins[icon] in
-- place, so Add alone is idempotent).
local function pinTick(self, elapsed, applyPosition)
    self._lerpAcc = (self._lerpAcc or 0) + elapsed
    if self._lerpAcc < LERP_TICK then return end
    self._lerpAcc = 0

    if not self._short then return end
    local set = pins[self._short]
    if not set then return end
    local L = set.lerp
    if not L or not L.nextX or not L.mapID then return end

    local now = GetTime()
    local renderX, renderY
    if not L.prevX or (L.lastBroadcast and now - L.lastBroadcast > LERP_STALL) then
        renderX, renderY = L.nextX, L.nextY
    else
        renderX, renderY = computeLerp(L, now)
    end

    if self._lastRenderedX
       and math.abs(renderX - self._lastRenderedX) < 0.0005
       and math.abs(renderY - self._lastRenderedY) < 0.0005 then
        return
    end
    self._lastRenderedX, self._lastRenderedY = renderX, renderY

    applyPosition(self, L.mapID, renderX, renderY)
end

local function applyWorldPinPosition(self, mapID, x, y)
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    -- Remove before Add: HBD's worldmap path pulls a fresh providerPin
    -- from the canvas pool each Add. Without the Remove the previous
    -- providerPin is never released, leaking + briefly resetting the
    -- canvas zoom-scale animation (the "flashing larger" bug).
    HBDPins:RemoveWorldMapIcon(REF_NAME, self)
    HBDPins:AddWorldMapIconMap(REF_NAME, self, mapID, x, y, HBD_PINS_WORLDMAP_SHOW_WORLD)
end

local function applyMinimapPinPosition(self, mapID, x, y)
    -- HBD's minimap path mutates minimapPins[icon] in place and
    -- queues a redraw - no canvas pool involved, so calling Add
    -- repeatedly is safe and cheap.
    HBDPins:AddMinimapIconMap(REF_NAME, self, mapID, x, y, true, false)
end

local function worldPinOnUpdate(self, elapsed)   pinTick(self, elapsed, applyWorldPinPosition)   end
local function minimapPinOnUpdate(self, elapsed) pinTick(self, elapsed, applyMinimapPinPosition) end

-- Role-badge factory: builds a single corner badge texture with a
-- shared role-icon spritesheet. Returns the texture so we can show/hide
-- and resize per pin update.
local function makeRoleBadge(frame, role, anchorPoint)
    local t = frame:CreateTexture(nil, "OVERLAY")
    t:SetTexture(ROLE_TEXTURE)
    local tc = ROLE_TCOORDS[role]
    if tc then t:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
    -- CENTER on the frame's corner = badge straddles the corner half
    -- inside / half outside. Sits over the class circle's transparent
    -- corner pixels, so no class-icon detail is occluded.
    t:SetPoint("CENTER", frame, anchorPoint, 0, 0)
    t:SetSize(ROLE_BADGE_BASE, ROLE_BADGE_BASE)
    t:Hide()
    return t
end

local function buildWorldPinFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(22, 22)

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetAllPoints()

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.icon:SetSize(18, 18)

    -- Role badges in fixed corners. Tank = TL, Healer = TR, DPS = BR.
    f.roleBadgeT = makeRoleBadge(f, "T", "TOPLEFT")
    f.roleBadgeH = makeRoleBadge(f, "H", "TOPRIGHT")
    f.roleBadgeD = makeRoleBadge(f, "D", "BOTTOMRIGHT")

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
        if self._roles and self._roles ~= "" then
            local parts = {}
            for i = 1, #self._roles do
                local r = self._roles:sub(i, i)
                local color = ROLE_COLORS[r]
                if color then
                    table.insert(parts, string.format(
                        "|cff%02x%02x%02x%s|r",
                        math.floor(color[1] * 255 + 0.5),
                        math.floor(color[2] * 255 + 0.5),
                        math.floor(color[3] * 255 + 0.5),
                        ROLE_LABELS[r] or r))
                end
            end
            if #parts > 0 then
                GameTooltip:AddLine("Role: " .. table.concat(parts, ", "), 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and self._name then
            showContextMenu(self._name, self._class)
        elseif button == "LeftButton" and self._clusterMembers then
            -- Clustered: open the per-cluster menu of all members instead
            -- of doing nothing on left-click.
            showClusterMenu(self._clusterMembers)
        end
    end)

    -- Per-pin smooth-movement ticker (linear lerp).
    f:SetScript("OnUpdate", worldPinOnUpdate)

    return f
end

local function applyRoleBadges(frame, roles, sizeMul)
    if not frame.roleBadgeT then return end
    local size = ROLE_BADGE_BASE * (sizeMul or 1)
    local map = { T = frame.roleBadgeT, H = frame.roleBadgeH, D = frame.roleBadgeD }
    for k, badge in pairs(map) do
        if roles and roles:find(k, 1, true) then
            badge:SetSize(size, size)
            badge:Show()
        else
            badge:Hide()
        end
    end
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

    -- Per-pin smooth-movement ticker (linear lerp); reads shared state
    -- from pins[self._short].lerp.
    f:SetScript("OnUpdate", minimapPinOnUpdate)

    return f
end


-- =============================================================
-- Build/refresh one player's pins from a roster entry
-- =============================================================
local function removePins(short)
    local set = pins[short]
    if not set then return end
    if set.world then
        set.world._nextX = nil  -- stop the lerp OnUpdate from re-adding
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
        set.world._nextX = nil  -- stop the lerp OnUpdate from re-adding
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

    -- If the base game already pins this player, hide ours and return early.
    -- (The roster entry stays — Map-tab UI still lists them.)
    if isPinnedByGame(entry.name) then
        hideBothPins(set)
        return
    end

    -- Advance the lerp state once; shared by world + minimap pins below.
    local curX, curY = updateLerpState(set, entry)

    -- WORLD MAP PIN
    if gm.showOnWorldMap ~= false then
        if not set.world then set.world = buildWorldPinFrame() end
        local wf = set.world
        wf._name  = entry.name or short
        wf._level = entry.level
        wf._class = entry.class
        wf._hp    = entry.hp
        wf._roles = entry.roles or ""

        -- "Dead" covers corpse (hp==0) AND ghost (entry.dead from the
        -- broadcaster's UnitIsDeadOrGhost). Older clients on the 7-field
        -- wire format won't set entry.dead, so we keep the hp==0 fallback.
        local isDead = entry.dead or (entry.hp == 0)

        applyWorldPinAppearance(wf, entry.class, entry.source or "guild", isDead)

        local sizeMul = gm.worldPinSize or 1.0
        wf:SetSize(22 * sizeMul, 22 * sizeMul)
        -- Dead broadcasters get a bigger skull so it reads as "dead" at a
        -- glance instead of just "icon swap". Skull overflows the source
        -- ring by a few px on each side - deliberate emphasis.
        local iconBase = isDead and 28 or 18
        wf.icon:SetSize(iconBase * sizeMul, iconBase * sizeMul)
        wf.hpBg:SetSize(20 * sizeMul, 3 * sizeMul)
        applyRoleBadges(wf, wf._roles, sizeMul)

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

        wf._short = short
        -- Frame-level "is this pin currently live?" markers. Cluster
        -- code reads these to decide whether to consider the pin.
        wf._mapID = entry.mapID
        wf._nextX = entry.x

        -- Initial paint so the pin appears immediately on first registration
        -- or after a hide; OnUpdate (10 Hz) takes over from here. Don't
        -- unconditionally Show() - that would un-hide a pin we deliberately
        -- hid as part of a cluster (until the next 0.3s cluster tick rehides).
        if not wf._isClusterMember then wf:Show() end
        -- Remove first - see comment in applyWorldPinPosition. Calling Add
        -- alone leaks a providerPin into HBD's canvas pool every invocation.
        HBDPins:RemoveWorldMapIcon(REF_NAME, wf)
        HBDPins:AddWorldMapIconMap(REF_NAME, wf, entry.mapID, curX, curY,
            HBD_PINS_WORLDMAP_SHOW_WORLD)
        wf._lastRenderedX, wf._lastRenderedY = curX, curY
    elseif set.world then
        set.world._nextX = nil  -- cluster code's "is live" check sees this and skips
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
        mf._short = short

        applyMinimapPin(mf)

        local sizeMul = gm.minimapPinSize or 1.0
        mf:SetSize(16 * sizeMul, 16 * sizeMul)

        -- Initial paint at the lerp's current start; OnUpdate slides it.
        -- showInParentZone=true (let sub-zone pins show on the parent map),
        -- floatOnEdge=false. floatOnEdge=true made distant guildies render
        -- at the minimap rim like a direction indicator - Morphéours
        -- reported pins showing "even at 20km away". With it false, pins
        -- only render when the guildie is genuinely inside the minimap's
        -- visible range.
        mf:Show()
        HBDPins:AddMinimapIconMap(REF_NAME, mf, entry.mapID, curX, curY, true, false)
        mf._lastRenderedX, mf._lastRenderedY = curX, curY
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
-- World-map clustering (zoom-aware, click-to-expand)
-- =============================================================
-- HBD has already positioned every pin on screen by the time this runs.
-- We walk our pin frames, find groups whose centers are within
-- CLUSTER_RADIUS_PX of each other in SCREEN space (so zoom changes auto-
-- adjust which pins overlap), and pick one "primary" per group to remain
-- visible with a count badge - the rest are hidden. Left-click on a
-- primary pops up a small list of the cluster's members; each row opens
-- the same Whisper/Invite menu the right-click context menu does.
--
-- Minimap pins are deliberately not touched here (Morphéours' explicit
-- "world map only" requirement).
local CLUSTER_RADIUS_PX = 22      -- approx pin diameter
local CLUSTER_TICK      = 0.3     -- recompute interval

local clusterMenu
local function getClusterMenu()
    if clusterMenu then return clusterMenu end
    local m = CreateFrame("Frame", "L3FGuildMapClusterMenu", UIParent, "BackdropTemplate")
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

    m.header = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    m.header:SetPoint("TOP", m, "TOP", 0, -8)

    m._rows = {}
    m:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsMouseOver() and not InCombatLockdown() then
            self._lingerTime = (self._lingerTime or 0) + (elapsed or 0.05)
            if self._lingerTime > 1.0 then self:Hide() end
        else
            self._lingerTime = 0
        end
    end)
    m:HookScript("OnShow", function(self) self._lingerTime = 0 end)

    clusterMenu = m
    return m
end

local function showClusterMenu(members)
    local m = getClusterMenu()
    for _, r in ipairs(m._rows) do r:Hide() end

    local W, HEADER_H, ROW_H = 170, 22, 18
    m.header:SetText(string.format("|cffffd100%d players|r", #members))

    for i, member in ipairs(members) do
        local r = m._rows[i]
        if not r then
            r = CreateFrame("Button", nil, m)
            r:SetHeight(ROW_H)
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            r.hl = r:CreateTexture(nil, "BACKGROUND")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.text:SetPoint("LEFT",  r, "LEFT",  8, 0)
            r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.text:SetJustifyH("LEFT")
            r:SetScript("OnEnter", function(self) self.hl:SetColorTexture(1, 1, 1, 0.10) end)
            r:SetScript("OnLeave", function(self) self.hl:SetColorTexture(1, 1, 1, 0)    end)
            r:SetScript("OnClick", function(self, button)
                if not self._name then return end
                showContextMenu(self._name, self._class)
                m:Hide()
            end)
            m._rows[i] = r
        end
        r._name  = member._name
        r._class = member._class
        local color = (member._class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member._class])
            or { r = 1, g = 1, b = 1 }
        local hex = string.format("%02x%02x%02x",
            math.floor(color.r * 255 + 0.5),
            math.floor(color.g * 255 + 0.5),
            math.floor(color.b * 255 + 0.5))
        r.text:SetText(string.format("|cff%s%s|r  |cff888888L%d|r",
            hex, member._name or "?", member._level or 0))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  m, "TOPLEFT",  6, -(HEADER_H + (i - 1) * ROW_H))
        r:SetPoint("TOPRIGHT", m, "TOPRIGHT", -6, -(HEADER_H + (i - 1) * ROW_H))
        r:Show()
    end

    m:SetSize(W, HEADER_H + #members * ROW_H + 12)
    local cx, cy = GetCursorPosition()
    local scale  = UIParent:GetEffectiveScale()
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    m:Show()
end

-- Union-find clustering by screen-pixel proximity. Returns a list of
-- groups; each group is { primary = frame, members = { frame, ... } }
-- with the primary chosen by alphabetical name for deterministic UI
-- (so the same pin stays visible across recompute cycles).
local function detectClusters()
    local visible = {}
    for _, set in pairs(pins) do
        local wf = set.world
        if wf and wf._mapID and wf._nextX and wf:IsShown() then
            local cx, cy = wf:GetCenter()
            if cx and cy then
                table.insert(visible, { frame = wf, x = cx, y = cy })
            end
        end
    end
    if #visible < 2 then return {} end

    local parent = {}
    for i = 1, #visible do parent[i] = i end
    local function find(i)
        while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end
        return i
    end
    local function union(i, j)
        local pi, pj = find(i), find(j)
        if pi ~= pj then parent[pi] = pj end
    end

    local r2 = CLUSTER_RADIUS_PX * CLUSTER_RADIUS_PX
    for i = 1, #visible - 1 do
        for j = i + 1, #visible do
            local dx = visible[i].x - visible[j].x
            local dy = visible[i].y - visible[j].y
            if dx * dx + dy * dy < r2 then union(i, j) end
        end
    end

    local roots = {}
    for i = 1, #visible do
        local r = find(i)
        roots[r] = roots[r] or {}
        table.insert(roots[r], visible[i].frame)
    end

    local clusters = {}
    for _, frames in pairs(roots) do
        if #frames > 1 then
            table.sort(frames, function(a, b)
                return (a._name or "") < (b._name or "")
            end)
            table.insert(clusters, { primary = frames[1], members = frames })
        end
    end
    return clusters
end

local activeClusters = {}  -- [primaryFrame] = members[]

local function clearClusters()
    for primary, members in pairs(activeClusters) do
        if primary.countBadge then primary.countBadge:Hide() end
        primary._clusterMembers = nil
        for _, m in ipairs(members) do
            m._isClusterMember = false
            if m ~= primary and m._nextX then
                m:Show()
            end
        end
    end
    activeClusters = {}
end

local function applyClusters()
    if not L3FToolsDB or not L3FToolsDB.guildMap then return end
    if L3FToolsDB.guildMap.showOnWorldMap == false then
        clearClusters()
        return
    end
    -- Only useful when the world map is up; pin centers are stale otherwise.
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        clearClusters()
        return
    end

    clearClusters()
    local clusters = detectClusters()
    for _, c in ipairs(clusters) do
        local primary = c.primary
        for _, m in ipairs(c.members) do
            if m ~= primary then
                m:Hide()
                m._isClusterMember = true
            else
                m._isClusterMember = false
            end
        end
        if not primary.countBadge then
            primary.countBadge = primary:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            primary.countBadge:SetPoint("TOPRIGHT", primary, "TOPRIGHT", 8, 6)
        end
        primary.countBadge:SetText(string.format("|cffffd100x%d|r", #c.members))
        primary.countBadge:Show()
        primary._clusterMembers = c.members
        activeClusters[primary] = c.members
    end
end

C_Timer.NewTicker(CLUSTER_TICK, applyClusters)

GM.OpenClusterMenuFor = function(frame)
    if frame and frame._clusterMembers then
        showClusterMenu(frame._clusterMembers)
        return true
    end
    return false
end


-- =============================================================
-- Public surface
-- =============================================================
-- Expose the pin's right-click context menu so other surfaces (e.g.
-- the Map-tab roster panel) can reuse the same Whisper/Invite UX.
function GM.OpenPinContextMenu(name, class)
    if not name then return end
    showContextMenu(name, class)
end

function GM.ClearAllPins()
    for short in pairs(pins) do
        removePins(short)
    end
    pins = {}
    GM.pins = pins
    if HBDPins.RemoveAllWorldMapIcons then HBDPins:RemoveAllWorldMapIcons(REF_NAME) end
    if HBDPins.RemoveAllMinimapIcons  then HBDPins:RemoveAllMinimapIcons(REF_NAME)  end
end
