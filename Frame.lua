-- =============================================================
-- L3FTools - Frame.lua
-- =============================================================
-- The main window. Resizable like a normal desktop app.
-- Horizontal tab strip below the title, three tabs:
--   Automarker | Atlas | Settings
-- Tab content frames live one level deeper; the actual UI for each
-- tab is built in Tabs/*.lua via L3F.RegisterTab(name, builderFn).
-- =============================================================

local addonName, L3F = ...

local MIN_WIDTH, MIN_HEIGHT = 700, 400

-- Max size = UIParent minus a 20px margin on each side, so the resize
-- grip stays grabbable. Computed dynamically each time it's needed - if
-- the player resizes the WoW window between sessions, the bound updates
-- next time they grab the grip.
local function getMaxSize()
    local sw, sh = UIParent:GetSize()
    return math.max(MIN_WIDTH,  math.floor((sw or 1280) - 40)),
           math.max(MIN_HEIGHT, math.floor((sh or 768)  - 40))
end

-- Tab registry. Each entry: { name, label, icon, builder, frame, built }
L3F.tabs = {}
L3F.tabOrder = {}

function L3F.RegisterTab(name, label, icon, builder)
    L3F.tabs[name] = {
        name = name, label = label, icon = icon,
        builder = builder, frame = nil, built = false,
    }
    table.insert(L3F.tabOrder, name)
end


-- =============================================================
-- BuildFrame
-- =============================================================
local mainFrame
local tabContentHost
local tabButtons = {}

local function showTab(name)
    if not L3F.tabs[name] then return end
    -- The hover preview is owned by the Automarker tab. Any tab switch
    -- (including swap-to-Automarker from elsewhere) should clear it so
    -- it doesn't linger over an unrelated tab.
    if L3F.HoverPreview then L3F.HoverPreview:Hide() end
    L3F.db.window.activeTab = name

    -- Build on first show (lazy load).
    for tabName, tab in pairs(L3F.tabs) do
        if tab.frame then tab.frame:Hide() end
    end
    local tab = L3F.tabs[name]
    if not tab.built and tab.builder then
        tab.frame = CreateFrame("Frame", nil, tabContentHost)
        tab.frame:SetAllPoints(tabContentHost)
        tab.builder(tab.frame)
        tab.built = true
    end
    if tab.frame then tab.frame:Show() end

    -- Highlight active tab button.
    for tabName, btn in pairs(tabButtons) do
        local active = (tabName == name)
        if active then
            btn.bg:SetColorTexture(1, 1, 1, 0.10)
            btn.underline:Show()
            btn.label:SetTextColor(1, 1, 1, 1)
        else
            btn.bg:SetColorTexture(0, 0, 0, 0)
            btn.underline:Hide()
            btn.label:SetTextColor(0.8, 0.8, 0.8, 1)
        end
    end
end
L3F.ShowTab = showTab

local function createTabButton(parent, name, label, icon, x)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(120, 28)
    btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 0)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0, 0, 0, 0)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.label:SetText(label)

    btn.underline = btn:CreateTexture(nil, "OVERLAY")
    btn.underline:SetColorTexture(0.30, 0.65, 1.0, 1)
    btn.underline:SetHeight(2)
    btn.underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    btn.underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    btn.underline:Hide()

    btn:SetScript("OnEnter", function(self)
        if self.bg then self.bg:SetColorTexture(1, 1, 1, 0.06) end
    end)
    btn:SetScript("OnLeave", function(self)
        if L3F.db.window.activeTab ~= name then
            self.bg:SetColorTexture(0, 0, 0, 0)
        else
            self.bg:SetColorTexture(1, 1, 1, 0.10)
        end
    end)
    btn:SetScript("OnClick", function() showTab(name) end)

    tabButtons[name] = btn
    return btn
end


local function applyResizeBounds(frame)
    local maxW, maxH = getMaxSize()
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, maxW, maxH)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
end

local function buildResizeGrip(frame)
    if frame.SetResizable then frame:SetResizable(true) end
    applyResizeBounds(frame)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    grip:SetScript("OnMouseDown", function(self)
        -- Refresh bounds in case the WoW window was resized since login.
        applyResizeBounds(frame)
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function(self)
        frame:StopMovingOrSizing()
        L3F.db.window.width  = math.floor(frame:GetWidth() + 0.5)
        L3F.db.window.height = math.floor(frame:GetHeight() + 0.5)
        if L3F.OnFrameResized then L3F.OnFrameResized() end
    end)
end


function L3F.BuildFrame()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "L3FToolsMainFrame", UIParent, "BasicFrameTemplateWithInset")
    -- Clamp the saved size against the current screen so an oversize value
    -- (e.g. the user resized past the screen and then logged in on a
    -- smaller display) doesn't trap the window with its grip off-screen.
    -- We don't write the clamped value back to db - if the player later
    -- comes back on a larger screen, the original size is restored.
    local maxW, maxH = getMaxSize()
    local loadW = math.min(L3F.db.window.width or 900, maxW)
    local loadH = math.min(L3F.db.window.height or 560, maxH)
    mainFrame:SetSize(loadW, loadH)
    -- DIALOG strata so add-on UI icons (WeakAuras, BigWigs bars, ...) at
    -- HIGH don't draw on top of our menu. The hover preview matches.
    mainFrame:SetFrameStrata("DIALOG")

    if L3F.db.window.x and L3F.db.window.y then
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", L3F.db.window.x, L3F.db.window.y)
    else
        mainFrame:SetPoint("CENTER")
    end

    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        L3F.db.window.x = math.floor(x + 0.5)
        L3F.db.window.y = math.floor(y + 0.5)
    end)
    mainFrame:Hide()

    -- When the main window closes, dismiss any open hover preview too.
    mainFrame:HookScript("OnHide", function()
        if L3F.HoverPreview then L3F.HoverPreview:Hide() end
    end)

    mainFrame.TitleText:SetText("L3FTools")

    -- L3F guild logo in the top-right of the inset
    local logo = mainFrame:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\L3FTools\\Media\\L3F")
    logo:SetSize(56, 56)
    logo:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -14, -28)
    mainFrame.logo = logo

    -- Tab strip frame (below the title bar)
    local tabStrip = CreateFrame("Frame", nil, mainFrame)
    tabStrip:SetHeight(28)
    tabStrip:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  6, -25)
    tabStrip:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -6, -25)
    local stripBg = tabStrip:CreateTexture(nil, "BACKGROUND")
    stripBg:SetAllPoints()
    stripBg:SetColorTexture(0, 0, 0, 0.25)
    mainFrame.tabStrip = tabStrip

    -- Tab content host (everything below the tab strip)
    tabContentHost = CreateFrame("Frame", nil, mainFrame)
    tabContentHost:SetPoint("TOPLEFT",     tabStrip,  "BOTTOMLEFT",  0, -2)
    tabContentHost:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -8, 8)
    mainFrame.contentHost = tabContentHost

    -- Render tab buttons in registration order
    local x = 4
    for _, name in ipairs(L3F.tabOrder) do
        local tab = L3F.tabs[name]
        createTabButton(tabStrip, name, tab.label, tab.icon, x)
        x = x + 124
    end

    buildResizeGrip(mainFrame)

    -- Show initial tab
    local initial = L3F.db.window.activeTab
    if not L3F.tabs[initial] then initial = L3F.tabOrder[1] end
    showTab(initial)

    L3F.mainFrame = mainFrame
    -- Reserve preview-width space on the left edge of the screen so the
    -- hover preview always has room and never overlaps the main window.
    if L3F.UpdateMainClampInsets then L3F.UpdateMainClampInsets() end
end


-- =============================================================
-- ClampRectInsets reserves preview-width worth of space along the
-- left edge of the screen. The hover preview anchors to the main
-- frame's left edge, so without this the player could drag the
-- main against the screen-left and the preview would spill off
-- screen / overlap the main window. Re-applied whenever the
-- preview width changes (from its grip).
-- =============================================================
local function getPreviewWidth()
    return (L3F.db and L3F.db.preview and L3F.db.preview.sizeW) or 280
end

function L3F.UpdateMainClampInsets()
    if not mainFrame then return end
    local pw = getPreviewWidth()
    mainFrame:SetClampRectInsets(pw, 0, 0, 0)
    -- Nudge the main back into the clamp area if a saved position
    -- (from before this fix shipped) puts its left edge below pw.
    local left = mainFrame:GetLeft()
    if left and left < pw then
        local x, y = mainFrame:GetCenter()
        if x then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
                pw + mainFrame:GetWidth() / 2, y)
        end
    end
end


function L3F.ToggleFrame()
    if not mainFrame then L3F.BuildFrame() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end


-- =============================================================
-- /l3f reset - recovery for a window that got dragged off-screen
-- or resized past the screen edge. Wipes the saved geometry and
-- re-centers at the 900x560 default.
-- =============================================================
function L3F.ResetWindow()
    L3F.db.window.width  = 900
    L3F.db.window.height = 560
    L3F.db.window.x      = nil
    L3F.db.window.y      = nil
    if mainFrame then
        local maxW, maxH = getMaxSize()
        mainFrame:SetSize(math.min(900, maxW), math.min(560, maxH))
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER")
        if not mainFrame:IsShown() then mainFrame:Show() end
    end
    print("|cffffd100L3FTools|r Window reset to default size and centered.")
end
