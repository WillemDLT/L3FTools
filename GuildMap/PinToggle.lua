-- =============================================================
-- L3FTools - GuildMap/PinToggle.lua
-- =============================================================
-- Two buttons, one per surface:
--   1. A LibDBIcon minimap button that toggles showOnMinimap.
--   2. A button anchored to WorldMapFrame (via Krowi_WorldMapButtons)
--      that toggles showOnWorldMap.
--
-- Each button is paired 1:1 with its Map-tab "Pins on world map" /
-- "Pins on minimap" checkbox - clicking the button updates the same
-- flag the checkbox reads, and vice versa. GM.NotifyPinSettingsChanged
-- pushes the change out to: pin renderer, button dim/tooltip, Map-tab
-- checkbox states.
--
-- Visual style on both buttons matches the LibDBIcon ring + icon look:
-- UI-Minimap-Background disc + CheesePin icon + MiniMap-TrackingBorder
-- ring. LibDBIcon supplies that stack for the minimap button on its
-- own; the world map button rebuilds it manually (RareScanner's
-- RSWorldMapButtonTemplate pattern).
-- =============================================================

local addonName, L3F = ...

local GM = L3F.GuildMap
if not GM then return end

local ICON_PATH = "Interface\\AddOns\\L3FTools\\Media\\CheesePin"
local LDB_NAME  = "L3FToolsMapPins"

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
    -- Minimap (LibDBIcon) button: dim based on showOnMinimap.
    local mm = _G["LibDBIcon10_" .. LDB_NAME]
    if mm and mm.icon then
        mm.icon:SetVertexColor(1, 1, 1, minimapShown() and 1.0 or 0.35)
    end
end

-- If the mouse is currently over either toggle button, re-fire its
-- OnEnter so the "Currently: shown/hidden" line updates without the
-- user having to mouse out and back in. (LibDBIcon owns its own
-- LibDBIconTooltip frame, so we use IsMouseOver rather than
-- GameTooltip:IsOwned which would miss the minimap case.)
local function refreshToggleTooltipIfShown()
    local candidates = {
        _G.L3FToolsMapPinWorldMapButton,
        _G["LibDBIcon10_" .. LDB_NAME],
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
-- 1) Minimap LibDBIcon button
-- =============================================================
local minimapRegistered = false
local function buildMinimapButton()
    if minimapRegistered then return end
    if not L3FToolsDB or not L3FToolsDB.guildMap then return end
    local LDB     = LibStub and LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0",      true)
    if not LDB or not LDBIcon then return end

    local obj = LDB:NewDataObject(LDB_NAME, {
        type = "launcher",
        icon = ICON_PATH,
        OnClick = function(_, button)
            if button == "LeftButton" then toggleMinimapPins() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("|cffffd100L3FTools|r Minimap pins")
            tt:AddLine(minimapShown()
                and "Currently: |cff00ff00shown|r"
                or  "Currently: |cffff5555hidden|r", 1, 1, 1)
            tt:AddLine("Left-click: toggle",  0.7, 0.7, 0.7)
            tt:AddLine("Drag: reposition",    0.7, 0.7, 0.7)
        end,
    })

    L3FToolsDB.guildMap.pinsButton = L3FToolsDB.guildMap.pinsButton or {}
    LDBIcon:Register(LDB_NAME, obj, L3FToolsDB.guildMap.pinsButton)

    if L3FToolsDB.guildMap.pinsButton.hide then LDBIcon:Hide(LDB_NAME)
    else                                        LDBIcon:Show(LDB_NAME) end

    -- LibDBIcon anchors the icon at TOPLEFT (5.5, -5); the disc
    -- background sits at TOPLEFT (7, -5). Re-anchor to (7, -7) so the
    -- icon (a) shares the x of the disc and (b) sits ~2 px below the
    -- disc top - the cheese-pin's heavy "head" then lands over the
    -- disc center instead of riding above it.
    local btn = _G["LibDBIcon10_" .. LDB_NAME]
    if btn and btn.icon then
        btn.icon:ClearAllPoints()
        btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -7)
    end

    minimapRegistered = true

    -- Restore dim state from saved per-surface flag (LibDBIcon doesn't
    -- persist vertex color across reloads).
    applyVisualState()
end


-- =============================================================
-- 2) World Map button
-- =============================================================
-- Anchoring goes through Krowi_WorldMapButtons-1.4, the same library
-- RareScanner uses. It stacks our button next to the existing
-- WorldMapFrame buttons (tracking pin, tracking options) so we never
-- overlap them and the placement matches what Morphéours expects.
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
