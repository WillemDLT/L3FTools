-- =============================================================
-- L3FTools - Minimap.lua
-- =============================================================
-- Minimap button via the standard LibDBIcon-1.0 library. Registers
-- the addon as a LibDataBroker-1.1 "launcher" object; LibDBIcon
-- turns that into a draggable minimap icon with the standard gold
-- tracking ring, correct anchor geometry, position persistence, and
-- compatibility with MinimapButtonFrame / Bagnon-style stash addons.
--
-- Also makes detectors (Leatrix Plus etc.) stop nagging about
-- custom buttons - LibDBIcon is exactly the convention they want.
-- =============================================================

local _, L3F = ...

local ADDON_NAME = "L3FTools"
local ICON_PATH  = "Interface\\AddOns\\L3FTools\\Media\\automarker"

local registered = false

function L3F.BuildMinimap()
    if registered then return end
    local LDB     = LibStub and LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0",      true)
    if not LDB or not LDBIcon then return end

    local obj = LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        icon = ICON_PATH,
        OnClick = function(_, button)
            if button == "LeftButton" then
                if L3F.ToggleFrame then L3F.ToggleFrame() end
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("|cffffd100L3FTools|r")
            tt:AddLine("Left-click: open",  1, 1, 1)
            tt:AddLine("Drag: reposition", 0.7, 0.7, 0.7)
        end,
    })

    -- LibDBIcon reads/writes `hide` and `minimapPos` on this table.
    L3F.db.minimap = L3F.db.minimap or {}
    LDBIcon:Register(ADDON_NAME, obj, L3F.db.minimap)

    if L3F.db.minimap.hide then LDBIcon:Hide(ADDON_NAME)
    else                        LDBIcon:Show(ADDON_NAME) end

    registered = true
end

function L3F.RefreshMinimap()
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not LDBIcon then return end
    if L3F.db.minimap.hide then
        LDBIcon:Hide(ADDON_NAME)
    else
        LDBIcon:Show(ADDON_NAME)
    end
end
