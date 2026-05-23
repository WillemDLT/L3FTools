-- =============================================================
-- L3FTools - UI/ModelViewer.lua
-- =============================================================
-- Reusable interactive 3D model viewer:
--   * Click + drag rotates the model
--   * Mousewheel zooms in/out
--   * Auto-rotate toggle slowly spins when not dragging
--   * Animation cycle button advances through stand animations
--   * Reset button restores defaults
--   * Optional pop-out button opens a larger floating viewer
--
-- Toolbar buttons use the same 22x22 native Blizzard icon textures as
-- AutomarkerL3F's preview - matches that look so the standalone addon
-- and this addon's Automarker tab feel like one product.
--
-- Usage:
--   local viewer = L3F.CreateModelViewer(parent, width, height, opts)
--     opts.popoutButton (bool, default true)  -- show the pop-out icon
--     opts.onHoverIn  (fn)  -- called when cursor enters toolbar buttons
--     opts.onHoverOut (fn)  -- called when cursor leaves
--   viewer:SetCreature(npcID)
-- =============================================================

local addonName, L3F = ...

local ANIMATIONS = { 0, 4, 5, 36, 37, 60, 65, 67, 69, 81, 96, 97 }
local POPOUT_WIDTH, POPOUT_HEIGHT = 480, 600

local BTN_SIZE = 22
local BTN_GAP  = 4

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
function L3F.CreateModelViewer(parent, width, height, opts)
    opts = opts or {}
    local showPopout = (opts.popoutButton ~= false)  -- default true
    local onHoverIn  = opts.onHoverIn
    local onHoverOut = opts.onHoverOut

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

    -- State (persisted across model swaps, not across sessions)
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
        if v.model.SetFacing       then v.model:SetFacing(v.angle) end
        if v.model.SetPosition     then v.model:SetPosition(0, 0, v.pitch or 0) end
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

    -- =========================================================
    -- TOOLBAR - native Blizzard 22x22 icon buttons, centred row
    -- Mirrors AutomarkerL3F's preview toolbar so the two addons feel
    -- like the same product. No chunky text buttons here.
    -- =========================================================
    local toolbar = CreateFrame("Frame", nil, v.frame)
    toolbar:SetPoint("TOPLEFT",  v.model, "BOTTOMLEFT",  0, -4)
    toolbar:SetPoint("TOPRIGHT", v.model, "BOTTOMRIGHT", 0, -4)
    toolbar:SetHeight(BTN_SIZE)

    local buttonCount = showPopout and 6 or 5
    local function placeBtn(btn, idx)
        local total  = buttonCount * BTN_SIZE + (buttonCount - 1) * BTN_GAP
        local startX = -total / 2 + BTN_SIZE / 2
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", toolbar, "CENTER",
            startX + (idx - 1) * (BTN_SIZE + BTN_GAP), 0)
    end

    local function makeIconBtn(idx, normal, pushed, tooltip, action)
        local b = CreateFrame("Button", nil, toolbar)
        b:SetSize(BTN_SIZE, BTN_SIZE)
        placeBtn(b, idx)
        b:SetNormalTexture(normal)
        if pushed then b:SetPushedTexture(pushed) end
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", action)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
            if onHoverIn then onHoverIn() end
        end)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if onHoverOut then onHoverOut() end
        end)
        return b
    end

    v.btnZoomOut = makeIconBtn(1,
        "Interface\\Buttons\\UI-MinusButton-Up",
        "Interface\\Buttons\\UI-MinusButton-Down",
        "Zoom out",
        function() v.zoom = math.max(0, v.zoom - 0.1) apply() end)

    v.btnZoomIn = makeIconBtn(2,
        "Interface\\Buttons\\UI-PlusButton-Up",
        "Interface\\Buttons\\UI-PlusButton-Down",
        "Zoom in",
        function() v.zoom = math.min(1, v.zoom + 0.1) apply() end)

    v.btnAnim = makeIconBtn(3,
        "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
        "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
        "Cycle animation",
        function()
            v.animIndex = (v.animIndex % #ANIMATIONS) + 1
            if v.model.SetAnimation then
                pcall(function() v.model:SetAnimation(ANIMATIONS[v.animIndex]) end)
            end
        end)

    v.btnRotate = makeIconBtn(4,
        "Interface\\Buttons\\UI-RotationRight-Button-Up",
        "Interface\\Buttons\\UI-RotationRight-Button-Down",
        "Toggle auto-rotate",
        function() v.autoRotate = not v.autoRotate end)

    v.btnReset = makeIconBtn(5,
        "Interface\\Buttons\\UI-RefreshButton",
        nil,
        "Reset view",
        function()
            v.angle, v.pitch, v.zoom = 0.5, 0, 0.6
            v.autoRotate = true
            if v.model.SetAnimation then
                pcall(function() v.model:SetAnimation(0) end)
            end
            apply()
        end)

    if showPopout then
        v.btnPopout = makeIconBtn(6,
            "Interface\\Icons\\INV_Misc_Spyglass_02",
            nil,
            "Pop out to large viewer",
            function()
                local p = buildPopout()
                if v.currentNPCID then
                    pcall(function()
                        p.model:SetCreature(v.currentNPCID)
                        if p.model.SetPortraitZoom then p.model:SetPortraitZoom(0) end
                    end)
                end
                p:Show()
            end)
    end

    -- =========================================================
    -- API
    -- =========================================================
    function v:SetCreature(npcID)
        v.currentNPCID = npcID
        if not npcID then v.model:ClearModel() return end
        local ok = pcall(function()
            v.model:SetCreature(npcID)
            if v.model.SetPortraitZoom then v.model:SetPortraitZoom(v.zoom) end
            if v.model.SetFacing       then v.model:SetFacing(v.angle) end
        end)
        if not ok then v.model:ClearModel() end
    end

    function v:Clear() v.currentNPCID = nil; v.model:ClearModel() end

    return v
end
