-- =============================================================
-- L3FTools - GuildMap/PinToggle.lua
-- =============================================================
-- Two buttons, one per surface:
--   1. A custom minimap button (NOT LibDBIcon, see "opt-out" note
--      below) that toggles showOnMinimap.
--   2. A button anchored to WorldMapFrame (via Krowi_WorldMapButtons)
--      that toggles showOnWorldMap.
--
-- Each button is paired 1:1 with its Map-tab "Pins on world map" /
-- "Pins on minimap" checkbox - clicking the button updates the same
-- flag the checkbox reads, and vice versa. GM.NotifyPinSettingsChanged
-- pushes the change out to: pin renderer, button dim/tooltip, Map-tab
-- checkbox states.
--
-- Why the minimap button is NOT a LibDBIcon button:
-- Minimap-button collector addons (MinimapButtonButton, BBI, etc.)
-- pull every LibDBIcon-registered button into a single grouped
-- button by default. The only opt-out is the user manually
-- blacklisting the button by name via slash commands - there is no
-- self-opt-out hook from the addon side. Morpheours wants this
-- button to stay on the minimap rim independently. So we build a
-- custom button with a name that doesn't match any collector's
-- frame-name patterns ("L3FToolsMapPinsToggle" - no "Minimap"
-- substring, no "LibDBIcon10_" prefix, no trailing digit) and
-- register it directly on Minimap. Collectors leave it alone.
-- The main L3F minimap button (Minimap.lua, "open the addon
-- window") deliberately STAYS LibDBIcon - that one is a normal
-- launcher and is fine to be collected.
--
-- Visual style on both buttons matches the LibDBIcon ring + icon
-- look: UI-Minimap-Background disc + CheesePin icon +
-- MiniMap-TrackingBorder ring. The world map button rebuilds it
-- manually (RareScanner's RSWorldMapButtonTemplate pattern); the
-- minimap button copies the texture stack from LibDBIcon's
-- createButton (Interface\Minimap\* paths + offsets).
-- =============================================================

local addonName, L3F = ...

local GM = L3F.GuildMap
if not GM then return end

local ICON_PATH     = "Interface\\AddOns\\L3FTools\\Media\\CheesePin"
local MM_BTN_NAME   = "L3FToolsMapPinsToggle"
local MM_BTN_RADIUS = 5  -- matches LibDBIcon's lib.radius

-- Minimap-shape quadrant tables (from LibDBIcon - same shapes the
-- minimap-shape addons advertise via the global GetMinimapShape).
-- Each entry: {Q1, Q2, Q3, Q4} where true == "round in this quadrant"
-- (use the circular radius) and false == "squared off in this
-- quadrant" (use the diagonal radius up to the corner).
local MM_SHAPES = {
    ["ROUND"]                 = { true,  true,  true,  true  },
    ["SQUARE"]                = { false, false, false, false },
    ["CORNER-TOPLEFT"]        = { false, false, false, true  },
    ["CORNER-TOPRIGHT"]       = { false, false, true,  false },
    ["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
    ["CORNER-BOTTOMRIGHT"]    = { true,  false, false, false },
    ["SIDE-LEFT"]             = { false, true,  false, true  },
    ["SIDE-RIGHT"]            = { true,  false, true,  false },
    ["SIDE-TOP"]              = { false, false, true,  true  },
    ["SIDE-BOTTOM"]           = { true,  true,  false, false },
    ["TRICORNER-TOPLEFT"]     = { false, true,  true,  true  },
    ["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true  },
    ["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true  },
    ["TRICORNER-BOTTOMRIGHT"] = { true,  true,  true,  false },
}

local function db()
    return L3FToolsDB and L3FToolsDB.guildMap
end

local function worldShown()
    local gm = db(); return gm and gm.showOnWorldMap
end

local function minimapShown()
    local gm = db(); return gm and gm.showOnMinimap
end


-- =============================================================
-- Cross-cutting refresh: pins + button dim + tooltips + Map tab
-- =============================================================
local function applyVisualState()
    -- World map button: its own RefreshVisual reads showOnWorldMap.
    local wm = _G.L3FToolsMapPinWorldMapButton
    if wm and wm.RefreshVisual then wm:RefreshVisual() end
    -- Minimap button: dim based on showOnMinimap.
    local mm = _G[MM_BTN_NAME]
    if mm and mm.icon then
        mm.icon:SetVertexColor(1, 1, 1, minimapShown() and 1.0 or 0.35)
    end
end

-- If the mouse is currently over either toggle button, re-fire its
-- OnEnter so the "Currently: shown/hidden" line updates without the
-- user having to mouse out and back in.
local function refreshToggleTooltipIfShown()
    local candidates = {
        _G.L3FToolsMapPinWorldMapButton,
        _G[MM_BTN_NAME],
    }
    for _, btn in ipairs(candidates) do
        if btn and btn:IsMouseOver() then
            local onEnter = btn:GetScript("OnEnter")
            if onEnter then onEnter(btn) end
            return
        end
    end
end

-- Single notification entrypoint used by both buttons, the slash
-- command, AND the Map tab checkboxes. Re-renders pins, updates
-- button visuals + tooltip, and re-reads the Map tab checkboxes so
-- they stay in sync with whoever made the change.
local function notifyChanged()
    if GM.RefreshAll then GM.RefreshAll() end
    applyVisualState()
    refreshToggleTooltipIfShown()
    if L3F.MapTab_RefreshCheckboxes then L3F.MapTab_RefreshCheckboxes() end
end
GM.NotifyPinSettingsChanged = notifyChanged


-- =============================================================
-- Per-surface and master toggles
-- =============================================================
local function toggleWorldPins()
    local gm = db(); if not gm then return end
    gm.showOnWorldMap = not gm.showOnWorldMap
    notifyChanged()
    print("|cffffd100L3FTools|r world-map pins "
        .. (gm.showOnWorldMap and "|cff00ff00shown|r" or "|cffff5555hidden|r"))
end

local function toggleMinimapPins()
    local gm = db(); if not gm then return end
    gm.showOnMinimap = not gm.showOnMinimap
    notifyChanged()
    print("|cffffd100L3FTools|r minimap pins "
        .. (gm.showOnMinimap and "|cff00ff00shown|r" or "|cffff5555hidden|r"))
end

-- /l3f mappins still toggles BOTH surfaces together (legacy slash). If
-- either is currently shown, hide both; otherwise show both.
local function toggleAllPins()
    local gm = db(); if not gm then return end
    local anyShown = gm.showOnWorldMap or gm.showOnMinimap
    gm.showOnWorldMap = not anyShown
    gm.showOnMinimap  = not anyShown
    notifyChanged()
    print("|cffffd100L3FTools|r map pins "
        .. (anyShown and "|cffff5555hidden|r" or "|cff00ff00shown|r"))
end
GM.TogglePinsHidden = toggleAllPins  -- Core.lua's /l3f mappins keeps working


-- =============================================================
-- 1) Custom minimap button (rim-positioned, NOT LibDBIcon)
-- =============================================================
-- Position math + shape handling lifted from LibDBIcon-1.0's
-- updatePosition / onUpdate. Same savedvar shape as before
-- (L3FToolsDB.guildMap.pinsButton.{minimapPos, hide}) so existing
-- users' position carries over even though the underlying button
-- frame is different now.
local function updateMinimapButtonPosition(button, position)
    local angle = math.rad(position or 220)
    local x, y, q = math.cos(angle), math.sin(angle), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local minimapShape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
    local quadTable = MM_SHAPES[minimapShape] or MM_SHAPES.ROUND
    local w = (Minimap:GetWidth()  / 2) + MM_BTN_RADIUS
    local h = (Minimap:GetHeight() / 2) + MM_BTN_RADIUS
    if quadTable[q] then
        x, y = x * w, y * h
    else
        local diagW = math.sqrt(2 * w * w) - 10
        local diagH = math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * diagW, w))
        y = math.max(-h, math.min(y * diagH, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function dragOnUpdate(self)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale  = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    local pos = math.deg(math.atan2(py - my, px - mx)) % 360
    if self._db then self._db.minimapPos = pos end
    updateMinimapButtonPosition(self, pos)
end

local minimapBuilt = false
local function buildMinimapButton()
    if minimapBuilt or _G[MM_BTN_NAME] then return end
    if not L3FToolsDB or not L3FToolsDB.guildMap then return end
    if not Minimap then return end

    L3FToolsDB.guildMap.pinsButton = L3FToolsDB.guildMap.pinsButton or {}
    local saved = L3FToolsDB.guildMap.pinsButton

    local b = CreateFrame("Button", MM_BTN_NAME, Minimap)
    b._db = saved
    b:SetFrameStrata("MEDIUM")
    b:SetSize(31, 31)
    b:SetFrameLevel(8)
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Texture stack mirrors LibDBIcon's createButton so visually the
    -- button is indistinguishable from the main L3F button + every
    -- other LibDBIcon button on the rim.
    b.overlay = b:CreateTexture(nil, "OVERLAY")
    b.overlay:SetSize(53, 53)
    b.overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.overlay:SetPoint("TOPLEFT")

    b.background = b:CreateTexture(nil, "BACKGROUND")
    b.background:SetSize(20, 20)
    b.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.background:SetPoint("TOPLEFT", 7, -5)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetTexture(ICON_PATH)
    -- Cheese-pin anchored at (7, -7) - same offset we used to force on
    -- top of LibDBIcon's default in 0.8.4. Centers the pin head over
    -- the disc instead of riding above it.
    b.icon:SetPoint("TOPLEFT", 7, -7)

    b:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then toggleMinimapPins() end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffffd100L3FTools|r Minimap pins")
        GameTooltip:AddLine(minimapShown()
            and "Currently: |cff00ff00shown|r"
            or  "Currently: |cffff5555hidden|r", 1, 1, 1)
        GameTooltip:AddLine("Left-click: toggle",  0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag: reposition",    0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", dragOnUpdate)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)

    updateMinimapButtonPosition(b, saved.minimapPos or 220)

    if saved.hide then b:Hide() else b:Show() end

    minimapBuilt = true

    -- Restore dim state for showOnMinimap=false saved across reload.
    applyVisualState()
end


-- =============================================================
-- 2) World Map button
-- =============================================================
-- Anchoring goes through Krowi_WorldMapButtons-1.4, the same library
-- RareScanner uses. It stacks our button next to the existing
-- WorldMapFrame buttons (tracking pin, tracking options) so we never
-- overlap them and the placement matches what Morpheours expects.
--
-- Visual stack borrowed from RareScanner's RSWorldMapButtonTemplate:
--   * BG       UI-Minimap-Background          25x25 at (2, -4)
--   * Icon     L3FTools\Media\CheesePin       20x20 at (6, -6.5)
--   * Border   MiniMap-TrackingBorder         54x54 at (0, 0)
--   * Highlight UI-Minimap-ZoomButton-Highlight (ADD blend)
local function buildWorldMapButton()
    if _G.L3FToolsMapPinWorldMapButton then return end
    if not WorldMapFrame then return end

    local krowi = LibStub and LibStub("Krowi_WorldMapButtons-1.4", true)
    if not krowi then return end

    local b = krowi:Add(nil, "Button")
    if not b then return end

    _G.L3FToolsMapPinWorldMapButton = b

    b:SetSize(32, 32)

    b.Background = b:CreateTexture(nil, "BACKGROUND")
    b.Background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.Background:SetSize(25, 25)
    b.Background:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -4)
    b.Background:SetVertexColor(1, 1, 1, 1)

    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetTexture(ICON_PATH)
    b.Icon:SetSize(20, 20)
    b.Icon:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -6.5)

    b.Border = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.Border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.Border:SetSize(54, 54)
    b.Border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() toggleWorldPins() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffffd100L3FTools|r World-map pins")
        GameTooltip:AddLine(worldShown()
            and "Currently: |cff00ff00shown|r"
            or  "Currently: |cffff5555hidden|r", 1, 1, 1)
        GameTooltip:AddLine("Click to toggle.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Krowi calls button:Refresh() on RefreshOverlayFrames / OnMapChanged.
    b.Refresh = function() end

    -- Dim the icon when world-map pins are hidden.
    b.RefreshVisual = function(self)
        self.Icon:SetVertexColor(1, 1, 1, worldShown() and 1.0 or 0.35)
    end
    b:RefreshVisual()
end


-- =============================================================
-- Boot
-- =============================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name == addonName then
            buildMinimapButton()
        elseif name == "Blizzard_WorldMap" then
            buildWorldMapButton()
        end
    elseif event == "PLAYER_LOGIN" then
        buildMinimapButton()
        buildWorldMapButton()
    end
end)
