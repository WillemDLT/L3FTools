-- =============================================================
-- L3FTools - UI/HoverPreview.lua
-- =============================================================
-- A floating popup that shows an NPC's 3D model + spells + notes.
-- Anchored to the LEFT of the main L3FTools window - matches the
-- standalone AutomarkerL3F's preview placement so the two addons
-- behave the same when you hover an NPC row.
--
-- Features:
--   * Pin button (top-right) keeps the panel open after mouseleave
--   * Resize handle (bottom-right); width/height saved across sessions
--   * Hover bridge: 1s grace period lets you slide the cursor onto it
--   * Fade-in on first show
--   * Mousewheel + drag rotate on the model (via ModelViewer)
--
-- API:
--   L3F.HoverPreview:Show(npc, anchorFrame)   -- show on hover
--   L3F.HoverPreview:ScheduleHide()           -- on leave; grace period
--   L3F.HoverPreview:CancelHide()             -- cancel pending hide
--   L3F.HoverPreview:Hide()                   -- force hide
-- =============================================================

local addonName, L3F = ...

local HIDE_GRACE      = 1.0
local FADE_DURATION   = 0.2
local DEFAULT_WIDTH   = 280
local DEFAULT_HEIGHT  = 540
local MIN_WIDTH, MIN_HEIGHT = 260, 400
local MAX_WIDTH, MAX_HEIGHT = 600, 900

local frame, viewer, scroll, spellHost, notesText
local pendingHide = false
local hideTimer   = 0
local fadeElapsed = 0
local currentNPC

local function isPinned()
    return L3F.db and L3F.db.preview and L3F.db.preview.pinned
end

local function cancelHide()
    pendingHide = false
end

local function scheduleHide()
    if isPinned() then return end
    pendingHide = true
    hideTimer = HIDE_GRACE
end

local function build()
    if frame then return frame end

    -- Saved size (per-character, persisted in db.preview).
    local sw = (L3F.db.preview and L3F.db.preview.sizeW) or DEFAULT_WIDTH
    local sh = (L3F.db.preview and L3F.db.preview.sizeH) or DEFAULT_HEIGHT

    frame = CreateFrame("Frame", "L3FToolsHoverPreview", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(sw, sh)
    -- Match the main frame's strata so the preview floats over the same
    -- third-party HIGH-strata UI icons.
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if frame.TitleText then frame.TitleText:SetText("Preview") end

    -- Hover-bridge: cursor on the preview cancels pending hide
    frame:SetScript("OnEnter", cancelHide)
    frame:SetScript("OnLeave", scheduleHide)

    -- ---------------------------------------------------------
    -- Resizable - same bounds as AutomarkerL3F's preview
    -- ---------------------------------------------------------
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
        if frame.SetMaxResize then frame:SetMaxResize(MAX_WIDTH, MAX_HEIGHT) end
    end

    -- ---------------------------------------------------------
    -- PIN button (top-right, just left of the close button)
    -- ---------------------------------------------------------
    local pin = CreateFrame("Button", nil, frame)
    pin:SetSize(20, 20)
    pin:SetPoint("TOPRIGHT", -28, -3)

    local function refreshPin()
        local locked = isPinned()
        pin:SetNormalTexture(locked
            and "Interface\\Buttons\\LockButton-Locked-Up"
            or  "Interface\\Buttons\\LockButton-Unlocked-Up")
        pin:SetPushedTexture(locked
            and "Interface\\Buttons\\LockButton-Locked-Down"
            or  "Interface\\Buttons\\LockButton-Unlocked-Down")
        pin:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        if frame.CloseButton then
            if locked then frame.CloseButton:Show() else frame.CloseButton:Hide() end
        end
    end
    pin:SetScript("OnClick", function()
        L3F.db.preview.pinned = not L3F.db.preview.pinned
        refreshPin()
    end)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Pin preview")
        GameTooltip:AddLine(isPinned()
            and "Currently pinned. Click to unpin."
            or  "Keep this panel open after the cursor leaves.", 1, 1, 1, true)
        GameTooltip:Show()
        cancelHide()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Close button only useful when pinned; otherwise hide it.
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    end
    refreshPin()

    -- ---------------------------------------------------------
    -- RESIZE handle (bottom-LEFT corner). Preview always sits to the
    -- LEFT of the main window with its right edge glued there, so the
    -- bottom-LEFT corner is the only "free" corner the player can
    -- grab. Texture is mirrored horizontally so the diagonal points
    -- outward. Height is pinned by the anchors set in Show(); only
    -- width is user-adjustable (StartSizing("LEFT") ignores cursor Y).
    -- ---------------------------------------------------------
    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(16, 16)
    resize:SetPoint("BOTTOMLEFT", 4, 4)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:GetNormalTexture():SetTexCoord(1, 0, 0, 1)
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:GetHighlightTexture():SetTexCoord(1, 0, 0, 1)
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize:GetPushedTexture():SetTexCoord(1, 0, 0, 1)
    resize:SetScript("OnMouseDown", function() frame:StartSizing("LEFT") end)
    resize:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        L3F.db.preview.sizeW = frame:GetWidth()
        -- Update the main frame's clamp insets so the user can't push
        -- main close enough to the screen edge that the (now wider/
        -- narrower) preview would overlap it.
        if L3F.UpdateMainClampInsets then L3F.UpdateMainClampInsets() end
    end)

    -- ---------------------------------------------------------
    -- MODEL VIEWER at the top - no popout button (this IS a popup)
    -- ---------------------------------------------------------
    viewer = L3F.CreateModelViewer(frame, sw - 30, 240, {
        popoutButton = false,
        onHoverIn    = cancelHide,
        onHoverOut   = scheduleHide,
    })
    viewer.frame:SetPoint("TOP", frame, "TOP", 0, -32)

    -- ---------------------------------------------------------
    -- Scrollable spells + notes below
    -- ---------------------------------------------------------
    scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     viewer.frame, "BOTTOMLEFT",  0, -8)
    scroll:SetPoint("BOTTOMRIGHT", frame,        "BOTTOMRIGHT", -28, 22)
    spellHost = CreateFrame("Frame", nil, scroll)
    spellHost:SetSize(220, 1)
    scroll:SetScrollChild(spellHost)

    notesText = spellHost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    notesText:SetWidth(212)
    notesText:SetJustifyH("LEFT")
    notesText:SetWordWrap(true)
    notesText:SetSpacing(2)

    -- ---------------------------------------------------------
    -- FADE-IN + HIDE TIMER
    -- ---------------------------------------------------------
    frame:SetScript("OnShow", function(self)
        fadeElapsed = 0
        self:SetAlpha(0)
        cancelHide()
    end)
    frame:SetScript("OnUpdate", function(self, elapsed)
        if fadeElapsed < FADE_DURATION then
            fadeElapsed = fadeElapsed + elapsed
            self:SetAlpha(math.min(1, fadeElapsed / FADE_DURATION))
        end
        if pendingHide then
            hideTimer = hideTimer - elapsed
            if hideTimer <= 0 then
                pendingHide = false
                self:Hide()
            end
        end
    end)

    frame:Hide()
    return frame
end

local function refreshContent(npc)
    if not npc then return end
    currentNPC = npc

    -- Title
    if frame.TitleText then frame.TitleText:SetText(npc.name or "Preview") end

    -- Model
    viewer:SetCreature(npc.id)

    -- Clear previous spell rows + notes
    for _, c in ipairs({spellHost:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    notesText:SetText("")
    notesText:ClearAllPoints()

    local y = -4

    -- SPELLS
    if npc.spells and #npc.spells > 0 then
        for _, spellID in ipairs(npc.spells) do
            local row = CreateFrame("Button", nil, spellHost)
            row:SetSize(210, 26)
            row:SetPoint("TOPLEFT", spellHost, "TOPLEFT", 4, y)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(22, 22)
            icon:SetPoint("LEFT", row, "LEFT", 0, 0)
            local name, _, tex = GetSpellInfo(spellID)
            icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")

            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            lbl:SetText(name or ("Spell #" .. spellID))

            row:SetScript("OnEnter", function(self)
                cancelHide()
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(spellID) end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            y = y - 28
        end
        y = y - 6
    end

    -- NOTES
    if npc.notes and npc.notes ~= "" then
        notesText:SetText(npc.notes)
        notesText:SetTextColor(1, 0.82, 0)
        notesText:SetPoint("TOPLEFT", spellHost, "TOPLEFT", 4, y)
        notesText:Show()
        y = y - (notesText:GetStringHeight() + 8)
    end

    spellHost:SetHeight(math.max(-y, 1))
end

L3F.HoverPreview = {}

function L3F.HoverPreview:Show(npc, anchorFrame)
    build()
    cancelHide()
    refreshContent(npc)

    -- Always anchor on the LEFT side of the main window. Pin BOTH
    -- right corners so the preview's height auto-tracks the main
    -- window however the player resizes it. Overlap on screen-edge
    -- is prevented by the main frame's ClampRectInsets (applied in
    -- Frame.lua) - the main is kept >= preview width from the left
    -- edge of the screen, so the preview always has room here.
    -- Fall back to anchorFrame (the row itself) if mainFrame isn't shown.
    frame:ClearAllPoints()
    if L3F.mainFrame and L3F.mainFrame:IsShown() then
        frame:SetPoint("TOPRIGHT",    L3F.mainFrame, "TOPLEFT",    0, 0)
        frame:SetPoint("BOTTOMRIGHT", L3F.mainFrame, "BOTTOMLEFT", 0, 0)
    elseif anchorFrame then
        frame:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -8, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
end

function L3F.HoverPreview:ScheduleHide()
    if not frame or not frame:IsShown() then return end
    scheduleHide()
end

function L3F.HoverPreview:CancelHide()
    cancelHide()
end

function L3F.HoverPreview:Hide()
    pendingHide = false
    if frame then frame:Hide() end
end
