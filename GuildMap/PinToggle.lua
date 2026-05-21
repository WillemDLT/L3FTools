-- =============================================================
-- L3FTools - GuildMap/PinToggle.lua
-- =============================================================
-- Two buttons whose only job is to show/hide L3FTools map pins:
--   1. A LibDBIcon minimap button (separate from the main L3F
--      button so users can hide pins without leaving the addon's
--      main window behind).
--   2. A button anchored to WorldMapFrame via Krowi_WorldMapButtons
--      (same library RareScanner uses) so it lands in the standard
--      "extra buttons" stack instead of floating in the title bar.
--
-- Visual style on both buttons matches the LibDBIcon ring + icon
-- look: UI-Minimap-Background disc, the CheesePin icon Willem
-- shipped, and MiniMap-TrackingBorder for the gold ring. LibDBIcon
-- supplies that stack for the minimap button on its own; the world
-- map button rebuilds it manually (RSWorldMapButtonTemplate pattern).
--
-- Both flip L3FToolsDB.guildMap.pinsHidden. Pins.lua reads that flag
-- in upsertPin() (master override; takes precedence over the
-- per-surface showOnWorldMap / showOnMinimap toggles).
-- =============================================================

local addonName, L3F = ...

local GM = L3F.GuildMap
if not GM then return end

local ICON_PATH = "Interface\\AddOns\\L3FTools\\Media\\CheesePin"
local LDB_NAME  = "L3FToolsMapPins"

local function isPinsHidden()
    return L3FToolsDB and L3FToolsDB.guildMap and L3FToolsDB.guildMap.pinsHidden
end

local function applyVisualState()
    -- World map button: has its own RefreshVisual that dims the icon.
    local wm = _G.L3FToolsMapPinWorldMapButton
    if wm and wm.RefreshVisual then wm:RefreshVisual() end
    -- Minimap (LibDBIcon) button: dim its icon the same way.
    local mm = _G["LibDBIcon10_" .. LDB_NAME]
    if mm and mm.icon then
        mm.icon:SetVertexColor(1, 1, 1, isPinsHidden() and 0.35 or 1.0)
    end
end

-- If GameTooltip is currently anchored to either toggle button, re-fire
-- that button's OnEnter so the "Currently: shown/hidden" line updates
-- without the user having to mouse out and back in. (LibDBIcon's tooltip
-- comes from the same OnEnter path.)
local function refreshToggleTooltipIfShown()
    if not GameTooltip or not GameTooltip:IsShown() then return end
    local candidates = {
        _G.L3FToolsMapPinWorldMapButton,
        _G["LibDBIcon10_" .. LDB_NAME],
    }
    for _, btn in ipairs(candidates) do
        if btn and GameTooltip:IsOwned(btn) then
            local onEnter = btn:GetScript("OnEnter")
            if onEnter then onEnter(btn) end
            return
        end
    end
end

local function togglePinsHidden()
    if not L3FToolsDB or not L3FToolsDB.guildMap then return end
    L3FToolsDB.guildMap.pinsHidden = not L3FToolsDB.guildMap.pinsHidden
    if GM.RefreshAll then GM.RefreshAll() end
    applyVisualState()
    refreshToggleTooltipIfShown()
    print("|cffffd100L3FTools|r map pins "
        .. (L3FToolsDB.guildMap.pinsHidden and "|cffff5555hidden|r" or "|cff00ff00shown|r"))
end
GM.TogglePinsHidden = togglePinsHidden  -- expose for slash command


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
            if button == "LeftButton" then togglePinsHidden() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("|cffffd100L3FTools Map Pins|r")
            tt:AddLine(isPinsHidden()
                and "Currently: |cffff5555hidden|r"
                or  "Currently: |cff00ff00shown|r", 1, 1, 1)
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

    -- If the user previously toggled pins hidden, restore the dim state
    -- on the icon (LibDBIcon doesn't persist vertex color across reloads).
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
--   * Icon     L3FTools\Media\CheesePin       20x20 at (7.2, -6)
--   * Border   MiniMap-TrackingBorder         54x54 at (0, 0)
--   * Highlight UI-Minimap-ZoomButton-Highlight (ADD blend)
local function buildWorldMapButton()
    if _G.L3FToolsMapPinWorldMapButton then return end
    if not WorldMapFrame then return end

    local krowi = LibStub and LibStub("Krowi_WorldMapButtons-1.4", true)
    if not krowi then return end

    local b = krowi:Add(nil, "Button")
    if not b then return end

    -- Stable global name for the slash-toggle / RefreshVisual hookups.
    -- (Krowi gives the frame its own name; we add an alias for ours.)
    _G.L3FToolsMapPinWorldMapButton = b

    b:SetSize(32, 32)

    -- BACKGROUND disc
    b.Background = b:CreateTexture(nil, "BACKGROUND")
    b.Background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b.Background:SetSize(25, 25)
    b.Background:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -4)
    b.Background:SetVertexColor(1, 1, 1, 1)

    -- Icon. (4.5, -6.5) put us "even more off to the left" per Morphéours,
    -- so we drift back toward RareScanner's (7.2, -6). Settled on (6, -6.5)
    -- which sits visually mid-disc with the cheese-pin's head over the
    -- center.
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetTexture(ICON_PATH)
    b.Icon:SetSize(20, 20)
    b.Icon:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -6.5)

    -- Tracking-border ring (slightly larger than the button itself).
    b.Border = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.Border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.Border:SetSize(54, 54)
    b.Border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() togglePinsHidden() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffffd100L3FTools Map Pins|r")
        GameTooltip:AddLine(isPinsHidden()
            and "Currently: |cffff5555hidden|r"
            or  "Currently: |cff00ff00shown|r", 1, 1, 1)
        GameTooltip:AddLine("Click to toggle.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Krowi calls button:Refresh() on RefreshOverlayFrames / OnMapChanged.
    -- Our button is static; no state to re-fetch on map change.
    b.Refresh = function() end

    -- Dim the icon when pins are hidden so the visual state matches.
    b.RefreshVisual = function(self)
        local hidden = isPinsHidden()
        self.Icon:SetVertexColor(1, 1, 1, hidden and 0.35 or 1.0)
    end
    b:RefreshVisual()
end


-- =============================================================
-- Boot
-- =============================================================
-- Minimap button can build as soon as the addon's SavedVariables
-- exist (ADDON_LOADED for our own name); WorldMapFrame may be lazy-
-- loaded by Blizzard_WorldMap, so we also retry on its load and on
-- PLAYER_LOGIN as a final safety net.
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
