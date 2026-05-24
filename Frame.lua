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

local MIN_HEIGHT_FLOOR = 400  -- absolute floor; per-tab minHeight may raise it

-- Dynamic minimum width. Combines:
--   (a) Row 1 tab-strip floor: enough room for every top-level tab button.
--   (b) Row 2 sub-tab strip floor: widest sub-tab parent's row, accounting
--       for the brick-wall offset.
--   (c) The largest per-tab `minWidth` declared in any L3F.RegisterTab opts.
-- Lazy-evaluated and cached so every per-tab file gets a chance to register
-- before the first read.
local _minWidthCache
local function getMinWidth()
    if _minWidthCache then return _minWidthCache end
    local BTN_W, GAP, PAD, BRICK = 120, 4, 12, 60
    local nTop = #L3F.tabOrder
    local stripMin = PAD + nTop * BTN_W + math.max(0, nTop - 1) * GAP
    local subStripMin = 0
    for _, subList in pairs(L3F.subTabOrder) do
        local n = #subList
        local w = PAD + BRICK + n * BTN_W + math.max(0, n - 1) * GAP
        if w > subStripMin then subStripMin = w end
    end
    local contentMin = 0
    for _, t in pairs(L3F.tabs) do
        local m = t.minWidth or 0
        if m > contentMin then contentMin = m end
    end
    _minWidthCache = math.max(stripMin, subStripMin, contentMin, 400)
    return _minWidthCache
end

-- Dynamic minimum height. The floor is MIN_HEIGHT_FLOOR, but any tab can
-- raise it via opts.minHeight on RegisterTab so its content stops fitting
-- before the resize grip lets the window collapse over the controls.
local _minHeightCache
local function getMinHeight()
    if _minHeightCache then return _minHeightCache end
    local contentMin = 0
    for _, t in pairs(L3F.tabs) do
        local m = t.minHeight or 0
        if m > contentMin then contentMin = m end
    end
    _minHeightCache = math.max(contentMin, MIN_HEIGHT_FLOOR)
    return _minHeightCache
end

-- Max size = UIParent minus a 20px margin on each side, so the resize
-- grip stays grabbable. Computed dynamically each time it's needed - if
-- the player resizes the WoW window between sessions, the bound updates
-- next time they grab the grip.
local function getMaxSize()
    local sw, sh = UIParent:GetSize()
    return math.max(getMinWidth(),  math.floor((sw or 1280) - 40)),
           math.max(getMinHeight(), math.floor((sh or 768)  - 40))
end

-- Tab registry. Each entry: { name, label, icon, builder, frame, built, parent }
-- Top-level tabs (parent=nil) render in row 1 (the main tab strip).
-- Sub-tabs (parent="<top-level-name>") render in row 2 (the brick-wall strip),
-- only visible when their parent is the active top-level tab.
L3F.tabs = {}
L3F.tabOrder = {}        -- top-level tabs only, in registration order
L3F.subTabOrder = {}     -- parentName -> { subTabName, subTabName, ... } in registration order

function L3F.RegisterTab(name, label, icon, builder, opts)
    local parent = opts and opts.parent or nil
    L3F.tabs[name] = {
        name = name, label = label, icon = icon,
        builder = builder, frame = nil, built = false,
        parent = parent,
        -- Optional declared minimum content width/height. Feed into
        -- getMinWidth() / getMinHeight() so the user can't shrink the
        -- window below what this tab needs to render its UI without
        -- clipping or overflowing.
        minWidth  = opts and opts.minWidth  or nil,
        minHeight = opts and opts.minHeight or nil,
        -- 0.16.0: each tab can declare its preferred display size. When
        -- the tab is shown, the main window auto-grows (never shrinks)
        -- to meet these. Clamped to screen size minus a small margin.
        preferredWidth  = opts and opts.preferredWidth  or nil,
        preferredHeight = opts and opts.preferredHeight or nil,
    }
    if parent then
        L3F.subTabOrder[parent] = L3F.subTabOrder[parent] or {}
        table.insert(L3F.subTabOrder[parent], name)
    else
        table.insert(L3F.tabOrder, name)
    end
end


-- =============================================================
-- BuildFrame
-- =============================================================
local mainFrame
local tabStrip
local subTabStrip
local tabContentHost
local tabButtons = {}        -- top-level (row 1) buttons by tab name
local subTabButtons = {}     -- sub-tab (row 2) buttons by tab name

-- Returns the actual content tab to render for a given clicked name.
-- If name is a top-level tab WITH sub-tabs, routes to the last-active
-- sub-tab (or the first if none remembered). If name is a sub-tab,
-- returns it directly.
local function resolveContentTab(name)
    local tab = L3F.tabs[name]
    if not tab then return nil, nil end
    if not tab.parent and L3F.subTabOrder[name] then
        local subs = L3F.subTabOrder[name]
        local lastSub = (L3F.db.window.activeSubTab or {})[name]
        local target
        if lastSub and L3F.tabs[lastSub] and L3F.tabs[lastSub].parent == name then
            target = lastSub
        else
            target = subs[1]
        end
        return L3F.tabs[target], target
    end
    return tab, name
end

-- Repaint both rows' highlight state from L3F.db.window.
local function refreshButtonHighlights()
    local activeTop = L3F.db.window.activeTab
    local activeSub = (L3F.db.window.activeSubTab or {})[activeTop]
    for n, btn in pairs(tabButtons) do
        local active = (n == activeTop)
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
    for n, btn in pairs(subTabButtons) do
        local active = (n == activeSub)
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

-- Show/hide row 2 strip + its buttons (only those matching the active top-tab).
-- Reanchors the content host below row 2 when visible, below row 1 otherwise.
local function updateStripVisibility()
    if not subTabStrip or not tabContentHost or not mainFrame then return end
    local activeTop = L3F.db.window.activeTab
    local hasSubTabs = L3F.subTabOrder[activeTop] ~= nil

    for _, btn in pairs(subTabButtons) do
        btn:SetShown(btn._parentName == activeTop)
    end

    tabContentHost:ClearAllPoints()
    if hasSubTabs then
        subTabStrip:Show()
        tabContentHost:SetPoint("TOPLEFT",     subTabStrip, "BOTTOMLEFT",  0, -2)
        tabContentHost:SetPoint("BOTTOMRIGHT", mainFrame,   "BOTTOMRIGHT", -8, 8)
    else
        subTabStrip:Hide()
        tabContentHost:SetPoint("TOPLEFT",     tabStrip,    "BOTTOMLEFT",  0, -2)
        tabContentHost:SetPoint("BOTTOMRIGHT", mainFrame,   "BOTTOMRIGHT", -8, 8)
    end
end

local function showTab(name)
    local tab = L3F.tabs[name]
    if not tab then return end
    -- The hover preview is owned by the Automarker tab. Any tab switch
    -- (including swap-to-Automarker from elsewhere) should clear it so
    -- it doesn't linger over an unrelated tab.
    if L3F.HoverPreview then L3F.HoverPreview:Hide() end

    -- Persist the requested tab. Sub-tab clicks also remember themselves
    -- under their parent so re-opening the parent later restores them.
    if tab.parent then
        L3F.db.window.activeTab = tab.parent
        L3F.db.window.activeSubTab = L3F.db.window.activeSubTab or {}
        L3F.db.window.activeSubTab[tab.parent] = name
    else
        L3F.db.window.activeTab = name
    end

    -- Resolve which content frame to actually build/show. A click on a
    -- top-level tab WITH sub-tabs routes to its last-active sub-tab;
    -- direct sub-tab clicks resolve to themselves; everything else maps 1:1.
    local contentTab, _
    if tab.parent then
        contentTab = tab
    else
        contentTab = resolveContentTab(name)
    end

    -- Hide all built tab frames; build & show the one we need.
    for _, t in pairs(L3F.tabs) do
        if t.frame then t.frame:Hide() end
    end
    if contentTab and contentTab.builder then
        if not contentTab.built then
            contentTab.frame = CreateFrame("Frame", nil, tabContentHost)
            contentTab.frame:SetAllPoints(tabContentHost)
            contentTab.builder(contentTab.frame)
            contentTab.built = true
        end
        if contentTab.frame then contentTab.frame:Show() end

        -- Auto-grow the main window to fit the new tab if needed. The
        -- window NEVER shrinks here - a user who manually enlarged the
        -- frame keeps their size. Saves the user from having to drag
        -- the resize grip every time they open a content-rich tab.
        local pw = contentTab.preferredWidth  or 0
        local ph = contentTab.preferredHeight or 0
        if (pw > 0 or ph > 0) and mainFrame then
            local maxW, maxH = getMaxSize()
            local minW = getMinWidth()
            local minH = getMinHeight()
            local cw, ch = mainFrame:GetWidth(), mainFrame:GetHeight()
            local targetW = math.max(cw, math.min(math.max(pw, minW), maxW))
            local targetH = math.max(ch, math.min(math.max(ph, minH), maxH))
            if targetW > cw + 1 or targetH > ch + 1 then
                mainFrame:SetSize(targetW, targetH)
                L3F.db.window.width  = math.floor(targetW + 0.5)
                L3F.db.window.height = math.floor(targetH + 0.5)
                if L3F.OnFrameResized then L3F.OnFrameResized() end
            end
        end
    end

    updateStripVisibility()
    refreshButtonHighlights()
end
L3F.ShowTab = showTab

-- Shared styling for both row 1 and row 2 buttons. isSubTab flips the
-- OnLeave highlight check to use activeSubTab instead of activeTab so a
-- sub-tab button knows when it itself is the active one.
local function styleTabButton(btn, name, label, isSubTab)
    btn:SetSize(120, 28)

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
        local isActive
        if isSubTab then
            isActive = ((L3F.db.window.activeSubTab or {})[self._parentName] == name)
        else
            isActive = (L3F.db.window.activeTab == name)
        end
        if isActive then
            self.bg:SetColorTexture(1, 1, 1, 0.10)
        else
            self.bg:SetColorTexture(0, 0, 0, 0)
        end
    end)
    btn:SetScript("OnClick", function() showTab(name) end)
end

local function createTabButton(parent, name, label, icon, x)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 0)
    styleTabButton(btn, name, label, false)
    tabButtons[name] = btn
    return btn
end

local function createSubTabButton(parent, name, label, x, parentName)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 0)
    btn._parentName = parentName
    styleTabButton(btn, name, label, true)
    subTabButtons[name] = btn
    return btn
end


local function applyResizeBounds(frame)
    local maxW, maxH = getMaxSize()
    local minW = getMinWidth()
    local minH = getMinHeight()
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    elseif frame.SetMinResize then
        frame:SetMinResize(minW, minH)
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
    -- Clamp saved size against the dynamic min in addition to the screen
    -- max, so a width saved before a new tab raised getMinWidth() snaps
    -- back up to the new minimum instead of starting clipped.
    local loadW = math.max(getMinWidth(),  math.min(L3F.db.window.width  or 900, maxW))
    local loadH = math.max(getMinHeight(), math.min(L3F.db.window.height or 560, maxH))
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
        if L3F.RPCoOp and L3F.RPCoOp.OnMainFrameHidden then
            L3F.RPCoOp.OnMainFrameHidden()
        end
    end)

    mainFrame.TitleText:SetText("L3FTools")

    -- L3F guild logo in the top-right of the inset
    local logo = mainFrame:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\L3FTools\\Media\\L3F")
    logo:SetSize(56, 56)
    logo:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -14, -28)
    mainFrame.logo = logo

    -- Row 1: top-level tab strip (below the title bar).
    tabStrip = CreateFrame("Frame", nil, mainFrame)
    tabStrip:SetHeight(28)
    tabStrip:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  6, -25)
    tabStrip:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -6, -25)
    local stripBg = tabStrip:CreateTexture(nil, "BACKGROUND")
    stripBg:SetAllPoints()
    stripBg:SetColorTexture(0, 0, 0, 0.25)
    mainFrame.tabStrip = tabStrip

    -- Row 2: sub-tab strip (brick-wall row below row 1). Hidden by default;
    -- updateStripVisibility() shows it whenever the active top-level tab
    -- has any sub-tabs registered against it.
    subTabStrip = CreateFrame("Frame", nil, mainFrame)
    subTabStrip:SetHeight(28)
    subTabStrip:SetPoint("TOPLEFT",  tabStrip, "BOTTOMLEFT",  0, -2)
    subTabStrip:SetPoint("TOPRIGHT", tabStrip, "BOTTOMRIGHT", 0, -2)
    local subStripBg = subTabStrip:CreateTexture(nil, "BACKGROUND")
    subStripBg:SetAllPoints()
    subStripBg:SetColorTexture(0, 0, 0, 0.15)  -- slightly lighter shelf
    subTabStrip:Hide()
    mainFrame.subTabStrip = subTabStrip

    -- Tab content host. Reanchored on every tab switch by updateStripVisibility()
    -- so it sits below row 2 when row 2 is visible, below row 1 otherwise.
    tabContentHost = CreateFrame("Frame", nil, mainFrame)
    tabContentHost:SetPoint("TOPLEFT",     tabStrip,  "BOTTOMLEFT",  0, -2)
    tabContentHost:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -8, 8)
    mainFrame.contentHost = tabContentHost

    -- Render row 1 buttons in registration order. Spacing 124 = 120w + 4 gap.
    local x = 4
    for _, name in ipairs(L3F.tabOrder) do
        local tab = L3F.tabs[name]
        createTabButton(tabStrip, name, tab.label, tab.icon, x)
        x = x + 124
    end

    -- Render row 2 buttons for every parent that has sub-tabs registered.
    -- Buttons are all anchored to the same subTabStrip; they're shown/hidden
    -- per-parent by updateStripVisibility() so only the active parent's row
    -- appears at a time. The 60px x-offset gives the brick-wall feel: row 2
    -- button centers land between row 1 button edges.
    local BRICK_OFFSET = 60
    for parentName, subList in pairs(L3F.subTabOrder) do
        local sx = 4 + BRICK_OFFSET
        for _, subName in ipairs(subList) do
            local subTab = L3F.tabs[subName]
            createSubTabButton(subTabStrip, subName, subTab.label, sx, parentName)
            sx = sx + 124
        end
    end

    buildResizeGrip(mainFrame)

    -- Show initial tab. If the saved activeTab no longer exists (e.g. an old
    -- savedvar from before this build), fall back to the first registered
    -- top-level tab so the window always opens to *something* sensible.
    local initial = L3F.db.window.activeTab
    if not L3F.tabs[initial] or L3F.tabs[initial].parent then
        initial = L3F.tabOrder[1]
    end
    showTab(initial)

    L3F.mainFrame = mainFrame
end


function L3F.ToggleFrame()
    if not mainFrame then L3F.BuildFrame() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

function L3F.ShowFrame(tabName)
    if not mainFrame then L3F.BuildFrame() end
    if tabName and L3F.tabs[tabName] then
        showTab(tabName)
    end
    if mainFrame and not mainFrame:IsShown() then
        mainFrame:Show()
    end
end


-- =============================================================
-- Temporary main-frame fade
-- =============================================================
-- Called by the Map tab when the user clicks a roster row: drops the
-- main window's alpha so the world-map sonar-ping behind it is
-- visible, then fades back to fully opaque. Total duration matches
-- the sonar ping (~2s) so the window finishes restoring just as the
-- last ring vanishes.
local FADE_DIM_ALPHA = 0.25
local FADE_OUT_TIME  = 0.2
local FADE_IN_TIME   = 0.2

local fadeState = {}      -- { startTime, duration, active }
local fadeDriver

local function restoreMainFrameAlpha()
    if mainFrame then mainFrame:SetAlpha(1.0) end
    fadeState.active = false
    if fadeDriver then fadeDriver:Hide() end
end

local function fadeAlphaAt(elapsed, duration)
    -- Returns the alpha to apply at this point in the timeline.
    if elapsed < 0 or elapsed >= duration then return 1.0 end
    local holdEnd = duration - FADE_IN_TIME
    if elapsed < FADE_OUT_TIME then
        local t = elapsed / FADE_OUT_TIME
        return 1.0 + (FADE_DIM_ALPHA - 1.0) * t
    elseif elapsed < holdEnd then
        return FADE_DIM_ALPHA
    else
        local t = (elapsed - holdEnd) / FADE_IN_TIME
        return FADE_DIM_ALPHA + (1.0 - FADE_DIM_ALPHA) * t
    end
end

function L3F.FadeMainFrameFor(seconds)
    if not mainFrame or not mainFrame:IsShown() then return end
    seconds = seconds or 2.0
    if seconds < FADE_OUT_TIME + FADE_IN_TIME then return end

    -- Lazy-init the driver + the OnHide restore hook.
    if not fadeDriver then
        fadeDriver = CreateFrame("Frame")
        fadeDriver:Hide()
        fadeDriver:SetScript("OnUpdate", function()
            if not fadeState.active or not mainFrame then return end
            local elapsed = GetTime() - fadeState.startTime
            if elapsed >= fadeState.duration then
                restoreMainFrameAlpha()
                return
            end
            mainFrame:SetAlpha(fadeAlphaAt(elapsed, fadeState.duration))
        end)
        -- If the window is closed mid-fade, restore alpha so re-opening
        -- doesn't show it at 0.25.
        mainFrame:HookScript("OnHide", function()
            if fadeState.active then restoreMainFrameAlpha() end
        end)
    end

    -- (Re-)start the fade from now. If a previous fade was in progress
    -- the alpha will briefly snap to 1.0 on the next OnUpdate tick
    -- before fading back out - acceptable for a 0.2s blip.
    fadeState.startTime = GetTime()
    fadeState.duration  = seconds
    fadeState.active    = true
    fadeDriver:Show()
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
