-- =============================================================
-- L3FTools - Minimap.lua
-- =============================================================
-- Custom minimap button. Left-click opens the main window;
-- left-drag slides it around the minimap edge. Right-click ignored.
-- =============================================================

local _, L3F = ...

local BUTTON_RADIUS = 80

local function reposition(btn)
    local angle = L3F.db.minimap.angle or 200
    local rad = math.rad(angle)
    local x = math.cos(rad) * BUTTON_RADIUS
    local y = math.sin(rad) * BUTTON_RADIUS
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function dragUpdate(btn)
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local angle = math.deg(math.atan2(cy - my, cx - mx))
    L3F.db.minimap.angle = angle
    reposition(btn)
end

function L3F.BuildMinimap()
    if L3F.minimapButton then return L3F.minimapButton end

    local btn = CreateFrame("Button", "L3FToolsMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)

    -- Geometry matches LibDBIcon-1.0 convention so the gold tracking-
    -- border ring lines up around our icon the way every other addon's
    -- minimap button looks. The MiniMap-TrackingBorder texture is NOT
    -- symmetric around its own image center - it is drawn to be placed
    -- at TOPLEFT(0, 0) of a 31x31 button, with the icon TOPLEFT-anchored
    -- at (5.5, -5) size 20x20. Centering the texture (our prior code)
    -- lands the ring off-center because we were assuming a symmetry
    -- the asset does not have.
    local function placeIcon(tex)
        if not tex then return end
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 5.5, -5)
        tex:SetSize(20, 20)
    end

    btn:SetNormalTexture("Interface\\AddOns\\L3FTools\\Media\\automarker")
    placeIcon(btn:GetNormalTexture())

    btn:SetHighlightTexture("Interface\\AddOns\\L3FTools\\Media\\automarker", "ADD")
    local hl = btn:GetHighlightTexture()
    placeIcon(hl)
    if hl then hl:SetAlpha(0.4) end

    btn:SetPushedTexture("Interface\\AddOns\\L3FTools\\Media\\automarker")
    local pushed = btn:GetPushedTexture()
    placeIcon(pushed)
    if pushed then pushed:SetVertexColor(0.8, 0.8, 0.8) end

    -- Gold tracking-border ring drawn over the icon (Blizzard texture).
    -- TOPLEFT 0,0 size 53x53 - LibDBIcon-1.0 convention.
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", dragUpdate)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            if L3F.ToggleFrame then L3F.ToggleFrame() end
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffffd100L3FTools|r")
        GameTooltip:AddLine("Left-click: open", 1, 1, 1)
        GameTooltip:AddLine("Drag: reposition", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    L3F.minimapButton = btn
    L3F.RefreshMinimap = function()
        if L3F.db.minimap.hide then btn:Hide()
        else btn:Show(); reposition(btn) end
    end

    L3F.RefreshMinimap()
    return btn
end
