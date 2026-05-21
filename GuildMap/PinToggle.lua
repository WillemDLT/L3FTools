-- =============================================================
-- L3FTools - GuildMap/PinToggle.lua
-- =============================================================
-- Two buttons whose only job is to show/hide L3FTools map pins:
--   1. A LibDBIcon minimap button (Questie-style; separate from the
--      main L3F button so users can hide pins without leaving the
--      addon's main window behind).
--   2. A button anchored to the top-right of WorldMapFrame in the
--      same visual style, so you can toggle pins from the world map
--      without minimizing it.
--
-- Both flip L3FToolsDB.guildMap.pinsHidden. Pins.lua reads that flag
-- in upsertPin() (master override; takes precedence over the
-- per-surface showOnWorldMap / showOnMinimap toggles).
-- =============================================================

local addonName, L3F = ...

local GM = L3F.GuildMap
if not GM then return end

local ICON_PATH = "Interface\\AddOns\\L3FTools\\Media\\L3F"
local LDB_NAME  = "L3FToolsMapPins"

local function isPinsHidden()
    return L3FToolsDB and L3FToolsDB.guildMap and L3FToolsDB.guildMap.pinsHidden
end

local function applyToWorldMapButton()
    local b = _G.L3FToolsMapPinWorldMapButton
    if b and b.RefreshVisual then b:RefreshVisual() end
end

local function togglePinsHidden()
    if not L3FToolsDB or not L3FToolsDB.guildMap then return end
    L3FToolsDB.guildMap.pinsHidden = not L3FToolsDB.guildMap.pinsHidden
    if GM.RefreshAll then GM.RefreshAll() end
    applyToWorldMapButton()
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

    minimapRegistered = true
end


-- =============================================================
-- 2) World Map button
-- =============================================================
-- Visual stack: a class-circle disc (vertex-tinted gold to match the
-- LibDBIcon ring look) plus the L3F icon on top. Anchored to the
-- top-right of WorldMapFrame, offset left of the close button so it
-- never overlaps the existing world map UI.
local function buildWorldMapButton()
    if _G.L3FToolsMapPinWorldMapButton then return end
    if not WorldMapFrame then return end

    local b = CreateFrame("Button", "L3FToolsMapPinWorldMapButton", WorldMapFrame)
    b:SetSize(26, 26)
    b:SetFrameStrata("HIGH")
    b:SetFrameLevel((WorldMapFrame:GetFrameLevel() or 0) + 10)
    -- Anchor: left of the world map's close button. -42 leaves room
    -- for the close button + the dropdown to its left in TBC.
    b:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -42, -4)

    -- Gold disc (uses the warrior class-circle texture as a generic
    -- circular shape, vertex-tinted gold).
    b.disc = b:CreateTexture(nil, "BACKGROUND")
    b.disc:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    b.disc:SetTexCoord(0, 0.25, 0, 0.25)  -- top-left quadrant: WARRIOR
    b.disc:SetVertexColor(1.00, 0.84, 0.00, 0.85)
    b.disc:SetAllPoints()

    -- L3F brand icon on top.
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(ICON_PATH)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon:SetSize(18, 18)

    -- Highlight on hover.
    local h = b:CreateTexture(nil, "HIGHLIGHT")
    h:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    h:SetAllPoints()
    h:SetBlendMode("ADD")

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

    -- Dim the icon when pins are hidden, so the visual state matches.
    b.RefreshVisual = function(self)
        local hidden = isPinsHidden()
        self.icon:SetVertexColor(1, 1, 1, hidden and 0.35 or 1.0)
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
