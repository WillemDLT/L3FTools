-- =============================================================
-- L3FTools - Tabs/Guild/ComposerCoOpUI.lua
-- =============================================================
-- UI widgets for the Composer co-op session feature.
-- Public API (under L3F.ComposerCoOp):
--   ComposerCoOp.AttachRosterPanel(parent, anchor, ref, relPoint, ox, oy)
--   ComposerCoOp.ToggleRosterPanel()
--   ComposerCoOp.ShowInvitePopup()
--   ComposerCoOp.ShowIncomingInvitePopup(sessionId, hostName)
-- =============================================================

local addonName, L3F = ...

L3F.ComposerCoOp = L3F.ComposerCoOp or {}
local CoOp = L3F.ComposerCoOp

local function classColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class or ""]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end
local function shortName(s) return Ambiguate(s or "", "short") end
local function selfShort()  return UnitName("player") or "?" end


-- =============================================================
-- ROSTER PANEL
-- =============================================================
local rosterPanel
local rosterRows = {}
local statusFS, hostBtns, joinedBtns, idleBtns

local function rebuildRoster()
    if not rosterPanel then return end
    local sess = CoOp.GetSession()
    for _, row in ipairs(rosterRows) do row:Hide() end

    if not sess then
        statusFS:SetText("|cffaaaaaaNot in a session|r")
        idleBtns:Show(); hostBtns:Hide(); joinedBtns:Hide()
        return
    end

    if sess.state == "hosting" then
        statusFS:SetText("|cff66ff66Hosting:|r " .. (sess.sessionId or ""))
        idleBtns:Hide(); hostBtns:Show(); joinedBtns:Hide()
    else
        statusFS:SetText("|cff66ccffJoined:|r " .. (sess.hostName or "?") .. "'s session")
        idleBtns:Hide(); hostBtns:Hide(); joinedBtns:Show()
    end

    local list = {}
    for short, info in pairs(sess.members or {}) do
        table.insert(list, { short = short, info = info })
    end
    table.sort(list, function(a, b)
        local aIsHost = (sess.state == "joined" and a.short == sess.hostName)
            or (sess.state == "hosting" and a.short == selfShort())
        local bIsHost = (sess.state == "joined" and b.short == sess.hostName)
            or (sess.state == "hosting" and b.short == selfShort())
        if aIsHost ~= bIsHost then return aIsHost end
        return a.short < b.short
    end)

    for i, ent in ipairs(list) do
        local row = rosterRows[i]
        if not row then
            row = CreateFrame("Button", nil, rosterPanel)
            row:SetSize(196, 18)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.text:SetJustifyH("LEFT")
            row.kick = CreateFrame("Button", nil, row)
            row.kick:SetSize(14, 14)
            row.kick:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            local kx = row.kick:CreateTexture(nil, "ARTWORK")
            kx:SetAllPoints()
            kx:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            row.kick:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            rosterRows[i] = row
        end
        row:Show()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rosterPanel, "TOPLEFT", 8, -68 - (i - 1) * 18)

        local isHost = (sess.state == "joined" and ent.short == sess.hostName)
            or (sess.state == "hosting" and ent.short == selfShort())
        local prefix = isHost and "[H] " or ""
        local r, g, b = classColor(ent.info.className)
        local hex = string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
        row.text:SetText("|c" .. hex .. prefix .. ent.short .. "|r")

        if sess.state == "hosting" and ent.short ~= selfShort() then
            row.kick:Show()
            row.kick:SetScript("OnClick", function() CoOp.Kick(ent.short) end)
        else
            row.kick:Hide()
            row.kick:SetScript("OnClick", nil)
        end
    end

    for j = #list + 1, #rosterRows do rosterRows[j]:Hide() end
end

CoOp.OnRosterChanged  = rebuildRoster
CoOp.OnSessionChanged = rebuildRoster

function CoOp.AttachRosterPanel(parent, anchor, ref, relPoint, ox, oy)
    if rosterPanel then return rosterPanel end
    rosterPanel = CreateFrame("Frame", "L3FCompCoOpPanel", parent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    rosterPanel:SetSize(220, 240)
    rosterPanel:SetPoint(anchor or "TOPRIGHT", ref or parent, relPoint or "TOPRIGHT",
        ox or -8, oy or -8)
    local bg = rosterPanel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
    local border = rosterPanel:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.3, 0.3, 0.6)

    local title = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", rosterPanel, "TOPLEFT", 8, -6)
    title:SetText("Composer co-op")

    local close = CreateFrame("Button", nil, rosterPanel, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", rosterPanel, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() rosterPanel:Hide() end)

    statusFS = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusFS:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    statusFS:SetPoint("RIGHT", rosterPanel, "RIGHT", -24, 0)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetText("|cffaaaaaaNot in a session|r")

    idleBtns = CreateFrame("Frame", nil, rosterPanel)
    idleBtns:SetSize(204, 26)
    idleBtns:SetPoint("BOTTOMLEFT", rosterPanel, "BOTTOMLEFT", 8, 8)
    local startBtn = CreateFrame("Button", nil, idleBtns, "UIPanelButtonTemplate")
    startBtn:SetSize(200, 22); startBtn:SetText("Start co-op session")
    startBtn:SetPoint("BOTTOMLEFT", idleBtns, "BOTTOMLEFT", 0, 0)
    startBtn:SetScript("OnClick", function() CoOp.StartSession() end)

    hostBtns = CreateFrame("Frame", nil, rosterPanel)
    hostBtns:SetSize(204, 26)
    hostBtns:SetPoint("BOTTOMLEFT", rosterPanel, "BOTTOMLEFT", 8, 8)
    local inviteBtn = CreateFrame("Button", nil, hostBtns, "UIPanelButtonTemplate")
    inviteBtn:SetSize(96, 22); inviteBtn:SetText("Invite")
    inviteBtn:SetPoint("BOTTOMLEFT", hostBtns, "BOTTOMLEFT", 0, 0)
    inviteBtn:SetScript("OnClick", function() CoOp.ShowInvitePopup() end)
    local endBtn = CreateFrame("Button", nil, hostBtns, "UIPanelButtonTemplate")
    endBtn:SetSize(96, 22); endBtn:SetText("End session")
    endBtn:SetPoint("BOTTOMLEFT", hostBtns, "BOTTOMLEFT", 104, 0)
    endBtn:SetScript("OnClick", function() CoOp.EndSession() end)
    hostBtns:Hide()

    joinedBtns = CreateFrame("Frame", nil, rosterPanel)
    joinedBtns:SetSize(204, 26)
    joinedBtns:SetPoint("BOTTOMLEFT", rosterPanel, "BOTTOMLEFT", 8, 8)
    local leaveBtn = CreateFrame("Button", nil, joinedBtns, "UIPanelButtonTemplate")
    leaveBtn:SetSize(200, 22); leaveBtn:SetText("Leave session")
    leaveBtn:SetPoint("BOTTOMLEFT", joinedBtns, "BOTTOMLEFT", 0, 0)
    leaveBtn:SetScript("OnClick", function() CoOp.EndSession() end)
    joinedBtns:Hide()

    rebuildRoster()
    return rosterPanel
end

function CoOp.ToggleRosterPanel()
    if rosterPanel then
        rosterPanel:SetShown(not rosterPanel:IsShown())
    end
end


-- =============================================================
-- INVITE POPUP (guild-only -- single picker, no source tabs)
-- =============================================================
local invitePopup

local function listGuildOnline()
    local out = {}
    if not IsInGuild() then return out end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name and online and shortName(name) ~= selfShort() then
            table.insert(out, {
                name = name,
                short = shortName(name),
                class = classFile or "UNKNOWN",
            })
        end
    end
    table.sort(out, function(a, b) return a.short < b.short end)
    return out
end

local function buildInvitePopup()
    if invitePopup then return invitePopup end
    local f = CreateFrame("Frame", "L3FCompInvitePopup", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(320, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true); f:SetClampedToScreen(true)
    f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText("Invite a guildie") end
    tinsert(UISpecialFrames, "L3FCompInvitePopup")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)
    hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -28)
    hint:SetJustifyH("LEFT")
    hint:SetText("Composer co-op is guild-scoped. Pick an online guildie below.")

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -56)
    f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 12)

    f.refresh = function()
        for _, c in ipairs({f.body:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        for _, r in ipairs({f.body:GetRegions()}) do r:Hide(); r:ClearAllPoints() end

        if not CoOp.IsHost() then
            local fs = f.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            fs:SetPoint("CENTER", f.body, "CENTER", 0, 0)
            fs:SetText("Start a co-op session first.")
            return
        end

        local list = listGuildOnline()
        if #list == 0 then
            local fs = f.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            fs:SetPoint("CENTER", f.body, "CENTER", 0, 0)
            fs:SetText("No guildies online (or not in a guild).")
            return
        end

        local searchEdit = CreateFrame("EditBox", nil, f.body, "InputBoxTemplate")
        searchEdit:SetSize(280, 22)
        searchEdit:SetPoint("TOPLEFT", f.body, "TOPLEFT", 10, -2)
        searchEdit:SetAutoFocus(false)

        local scroll = CreateFrame("ScrollFrame", nil, f.body, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -30)
        scroll:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT", -20, 0)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(280, 600)
        scroll:SetScrollChild(content)

        local function render(filter)
            for _, c in ipairs({content:GetChildren()}) do c:Hide(); c:SetParent(nil) end
            local f2 = (filter or ""):lower()
            local shown = 0
            for _, ent in ipairs(list) do
                if f2 == "" or ent.short:lower():find(f2, 1, true) then
                    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
                    b:SetSize(260, 20)
                    b:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(shown * 22))
                    local r, g, bl = classColor(ent.class)
                    b:SetText(string.format("|cff%02x%02x%02x%s|r",
                        r * 255, g * 255, bl * 255, ent.short))
                    b:SetScript("OnClick", function() CoOp.Invite(ent.name) end)
                    shown = shown + 1
                end
            end
            content:SetHeight(math.max(20, shown * 22 + 8))
        end
        searchEdit:SetScript("OnTextChanged", function(self) render(self:GetText()) end)
        render("")
    end

    invitePopup = f
    return f
end

function CoOp.ShowInvitePopup()
    local f = buildInvitePopup()
    f.refresh()
    f:Show()
end


-- =============================================================
-- INCOMING-INVITE POPUP (receiver side)
-- =============================================================
local incomingStack = {}

local function dismissIncoming(sessionId)
    for i = #incomingStack, 1, -1 do
        if incomingStack[i].sessionId == sessionId then
            incomingStack[i].frame:Hide()
            table.remove(incomingStack, i)
        end
    end
end

function CoOp.ShowIncomingInvitePopup(sessionId, hostName)
    local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(360, 130)
    local y = -120 - (#incomingStack * 140)
    f:SetPoint("TOP", UIParent, "TOP", 0, y)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true); f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if f.TitleText then f.TitleText:SetText("Composer co-op invite") end
    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    msg:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
    msg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -32)
    msg:SetJustifyH("LEFT")
    msg:SetText(string.format(
        "|cffffd100%s|r invites you to a Composer co-op session.",
        hostName or "?"))

    local acc = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    acc:SetSize(100, 22); acc:SetText("Accept")
    acc:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    acc:SetScript("OnClick", function()
        CoOp.AcceptInvite(sessionId)
        dismissIncoming(sessionId)
    end)
    local dec = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dec:SetSize(100, 22); dec:SetText("Decline")
    dec:SetPoint("RIGHT", acc, "LEFT", -8, 0)
    dec:SetScript("OnClick", function()
        CoOp.DeclineInvite(sessionId)
        dismissIncoming(sessionId)
    end)
    C_Timer.After(60, function() dismissIncoming(sessionId) end)

    table.insert(incomingStack, { frame = f, sessionId = sessionId })
    f:Show()
end

CoOp.OnIncomingInvite = function(sessionId, hostName)
    CoOp.ShowIncomingInvitePopup(sessionId, hostName)
end
