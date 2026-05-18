-- =============================================================
-- L3FTools - UI/HoverPreview.lua
-- =============================================================
-- A floating popup that shows an NPC's 3D model + spells + notes.
-- Used by the Automarker tab when hovering an NPC row. Hover-bridge
-- pattern lets the cursor travel from the row to the preview without
-- the preview dismissing.
--
-- API:
--   L3F.HoverPreview:Show(npc, anchorFrame)   -- show on hover
--   L3F.HoverPreview:ScheduleHide()           -- on leave; grace period
--   L3F.HoverPreview:Hide()                   -- force hide
-- =============================================================

local addonName, L3F = ...

local HIDE_GRACE = 1.0
local PREVIEW_WIDTH  = 280
local PREVIEW_HEIGHT = 540

local frame, viewer, spellHost, notesText
local pendingHide = false
local hideTimer   = 0
local currentNPC

local function build()
    if frame then return frame end

    frame = CreateFrame("Frame", "L3FToolsHoverPreview", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(PREVIEW_WIDTH, PREVIEW_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if frame.TitleText then frame.TitleText:SetText("Preview") end

    -- Hover-bridge: cursor on the preview cancels pending hide
    frame:SetScript("OnEnter", function() pendingHide = false end)
    frame:SetScript("OnLeave", function()
        pendingHide = true
        hideTimer = HIDE_GRACE
    end)

    -- ModelViewer at the top
    viewer = L3F.CreateModelViewer(frame, PREVIEW_WIDTH - 30, 240)
    viewer.frame:SetPoint("TOP", frame, "TOP", 0, -32)

    -- Scrollable spells + notes below
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     viewer.frame, "BOTTOMLEFT",  0, -8)
    scroll:SetPoint("BOTTOMRIGHT", frame,        "BOTTOMRIGHT", -28, 10)
    spellHost = CreateFrame("Frame", nil, scroll)
    spellHost:SetSize(220, 1)
    scroll:SetScrollChild(spellHost)

    notesText = spellHost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    notesText:SetWidth(212)
    notesText:SetJustifyH("LEFT")
    notesText:SetWordWrap(true)
    notesText:SetSpacing(2)

    -- OnUpdate ticks the hide timer
    frame:SetScript("OnUpdate", function(_, elapsed)
        if pendingHide then
            hideTimer = hideTimer - elapsed
            if hideTimer <= 0 then
                pendingHide = false
                frame:Hide()
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
                pendingHide = false
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
    pendingHide = false
    refreshContent(npc)

    -- Anchor to the right of the main L3FTools window if available, else cursor
    frame:ClearAllPoints()
    if L3F.mainFrame and L3F.mainFrame:IsShown() then
        frame:SetPoint("TOPLEFT", L3F.mainFrame, "TOPRIGHT", 4, 0)
    elseif anchorFrame then
        frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
end

function L3F.HoverPreview:ScheduleHide()
    if not frame or not frame:IsShown() then return end
    pendingHide = true
    hideTimer = HIDE_GRACE
end

function L3F.HoverPreview:Hide()
    pendingHide = false
    if frame then frame:Hide() end
end

function L3F.HoverPreview:CancelHide()
    pendingHide = false
end
