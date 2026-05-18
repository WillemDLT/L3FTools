-- =============================================================
-- L3FTools - UI/ModelViewer.lua
-- =============================================================
-- Reusable interactive 3D model viewer:
--   * Click + drag rotates the model
--   * Mousewheel zooms in/out
--   * Auto-rotate toggle slowly spins when not dragging
--   * Reset button restores defaults
--   * Animation cycle button advances through stand animations
--   * Pop-out button opens a larger floating viewer
-- Usage:
--   local viewer = L3F.CreateModelViewer(parent, width, height)
--   viewer:SetCreature(npcID)
-- =============================================================

local addonName, L3F = ...

local ANIMATIONS = { 0, 4, 5, 36, 37, 60, 65, 67, 69, 81, 96, 97 }
local POPOUT_WIDTH, POPOUT_HEIGHT = 480, 600

-- =============================================================
-- Single popped-out floating viewer (one instance, recycled)
-- =============================================================
local popoutFrame
local function buildPopout()
    if popoutFrame then return popoutFrame end
    popoutFrame = CreateFrame("Frame", "L3FToolsModelPopout", UIParent, "BasicFrameTemplateWithInset")
    popoutFrame:SetSize(POPOUT_WIDTH, POPOUT_HEIGHT)
    popoutFrame:SetPoint("CENTER")
    popoutFrame:SetMovable(true)
    popoutFrame:SetClampedToScreen(true)
    popoutFrame:EnableMouse(true)
    popoutFrame:RegisterForDrag("LeftButton")
    popoutFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    popoutFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    popoutFrame.TitleText:SetText("Model Viewer")

    if popoutFrame.SetResizable then popoutFrame:SetResizable(true) end
    if popoutFrame.SetResizeBounds then popoutFrame:SetResizeBounds(280, 360)
    elseif popoutFrame.SetMinResize then popoutFrame:SetMinResize(280, 360) end

    popoutFrame.model = CreateFrame("PlayerModel", nil, popoutFrame)
    popoutFrame.model:SetPoint("TOPLEFT",     popoutFrame, "TOPLEFT",     12, -30)
    popoutFrame.model:SetPoint("BOTTOMRIGHT", popoutFrame, "BOTTOMRIGHT", -12, 12)

    local grip = CreateFrame("Button", nil, popoutFrame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", popoutFrame, "BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() popoutFrame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp",   function() popoutFrame:StopMovingOrSizing() end)

    popoutFrame:Hide()
    return popoutFrame
end


-- =============================================================
-- Per-viewer factory
-- =============================================================
function L3F.CreateModelViewer(parent, width, height)
    local v = {}
    v.parent = parent
    v.width  = width  or 240
    v.height = height or 240

    -- Container
    v.frame = CreateFrame("Frame", nil, parent)
    v.frame:SetSize(v.width, v.height + 28)  -- +28 for toolbar

    -- 3D model
    v.model = CreateFrame("PlayerModel", nil, v.frame)
    v.model:SetPoint("TOPLEFT",  v.frame, "TOPLEFT",  0, 0)
    v.model:SetPoint("TOPRIGHT", v.frame, "TOPRIGHT", 0, 0)
    v.model:SetHeight(v.height)
    v.model:EnableMouse(true)
    v.model:EnableMouseWheel(true)

    -- State
    v.angle        = 0.5
    v.pitch        = 0
    v.zoom         = 0.6
    v.autoRotate   = true
    v.animIndex    = 1
    v.dragging     = false
    v.dragStartX   = 0
    v.dragStartY   = 0
    v.dragAngle    = 0
    v.dragPitch    = 0
    v.currentNPCID = nil

    local function apply()
        if v.model.SetFacing   then v.model:SetFacing(v.angle) end
        if v.model.SetPosition then v.model:SetPosition(0, 0, v.pitch or 0) end
        if v.model.SetPortraitZoom then v.model:SetPortraitZoom(v.zoom) end
    end

    -- Click+drag rotate
    v.model:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        v.dragging = true
        v.dragStartX, v.dragStartY = GetCursorPosition()
        v.dragAngle = v.angle
        v.dragPitch = v.pitch
    end)
    v.model:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then v.dragging = false end
    end)
    v.model:SetScript("OnUpdate", function(self, elapsed)
        if v.dragging then
            local cx, cy = GetCursorPosition()
            v.angle = v.dragAngle + (cx - v.dragStartX) * 0.01
            v.pitch = math.max(-1.5, math.min(1.5, v.dragPitch + (cy - v.dragStartY) * 0.005))
            apply()
        elseif v.autoRotate and v.currentNPCID then
            v.angle = (v.angle + elapsed * 0.4) % (2 * math.pi)
            apply()
        end
    end)

    -- Mousewheel zoom
    v.model:SetScript("OnMouseWheel", function(self, delta)
        v.zoom = math.max(0, math.min(1, v.zoom + delta * 0.1))
        apply()
    end)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, v.frame)
    toolbar:SetPoint("TOPLEFT",  v.model, "BOTTOMLEFT",  0, -4)
    toolbar:SetPoint("TOPRIGHT", v.model, "BOTTOMRIGHT", 0, -4)
    toolbar:SetHeight(22)

    local function makeBtn(label, onClick, anchor, x)
        local b = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
        b:SetSize(28, 22)
        b:SetPoint("LEFT", anchor or toolbar, anchor and "RIGHT" or "LEFT", x or 0, 0)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end

    v.btnZoomOut  = makeBtn("-",  function() v.zoom = math.max(0, v.zoom - 0.1) apply() end)
    v.btnZoomIn   = makeBtn("+",  function() v.zoom = math.min(1, v.zoom + 0.1) apply() end, v.btnZoomOut, 2)
    v.btnAnim     = makeBtn("A",  function()
        v.animIndex = (v.animIndex % #ANIMATIONS) + 1
        if v.model.SetAnimation then v.model:SetAnimation(ANIMATIONS[v.animIndex]) end
    end, v.btnZoomIn, 2)
    v.btnRotate   = makeBtn("R",  function() v.autoRotate = not v.autoRotate end, v.btnAnim, 2)
    v.btnReset    = makeBtn("X",  function()
        v.angle, v.pitch, v.zoom = 0.5, 0, 0.6
        v.autoRotate = true
        if v.model.SetAnimation then v.model:SetAnimation(0) end
        apply()
    end, v.btnRotate, 2)
    v.btnPopout   = makeBtn("Pop", function()
        local p = buildPopout()
        if v.currentNPCID then
            pcall(function()
                p.model:SetCreature(v.currentNPCID)
                if p.model.SetPortraitZoom then p.model:SetPortraitZoom(0) end
            end)
        end
        p:Show()
    end, v.btnReset, 2)
    v.btnPopout:SetSize(38, 22)

    -- Method: set the displayed creature
    function v:SetCreature(npcID)
        v.currentNPCID = npcID
        if not npcID then v.model:ClearModel() return end
        local ok = pcall(function()
            v.model:SetCreature(npcID)
            if v.model.SetPortraitZoom then v.model:SetPortraitZoom(v.zoom) end
            if v.model.SetFacing then v.model:SetFacing(v.angle) end
        end)
        if not ok then v.model:ClearModel() end
    end

    function v:Clear() v.currentNPCID = nil; v.model:ClearModel() end

    return v
end
