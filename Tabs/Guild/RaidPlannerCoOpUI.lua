-- =============================================================
-- L3FTools - Tabs/Guild/RaidPlannerCoOpUI.lua
-- =============================================================
-- UI widgets for the Raid Planner co-op session feature.
-- Public API (all under L3F.RPCoOp):
--   RPCoOp.AttachRosterPanel(parent, anchorPoint, refFrame, relPoint, x, y)
--     Builds the co-op roster + action-buttons panel as a child of
--     `parent`, anchored to `refFrame` at the given points. Returns
--     the frame. Idempotent (returns the cached frame on re-call).
--   RPCoOp.ShowInvitePopup()
--     Floating picker frame with 4 source tabs (party/raid, guild,
--     by-name, mass-invite).
--   RPCoOp.ShowIncomingInvitePopup(sessionId, hostName, encounterName)
--     Modal-ish accept/decline popup the receiver sees on INV.
-- =============================================================

local addonName, L3F = ...

L3F.RPCoOp = L3F.RPCoOp or {}
local RPCoOp = L3F.RPCoOp

-- WoW class colors for the roster name swatches.
local function classColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class or ""]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end


-- =============================================================
-- ROSTER PANEL
-- =============================================================
local rosterPanel
local rosterRows = {}
local statusFS, hostBtns, joinedBtns, idleBtns

local function shortName(s) return Ambiguate(s or "", "short") end
local function selfShort() return UnitName("player") or "?" end

local function rebuildRoster()
    if not rosterPanel then return end
    local sess = RPCoOp.GetSession()
    -- Tear down existing rows.
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

    -- Render members. Host first, then alpha by short name.
    local list = {}
    for short, info in pairs(sess.members or {}) do
        table.insert(list, { short = short, info = info })
    end
    table.sort(list, function(a, b)
        local aIsHost = (a.short == sess.hostName) or (a.short == selfShort() and sess.state == "hosting")
        local bIsHost = (b.short == sess.hostName) or (b.short == selfShort() and sess.state == "hosting")
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

        local isHost = (ent.short == (sess.hostName or selfShort()))
            and (sess.state == "joined" and ent.short == sess.hostName
                 or sess.state == "hosting" and ent.short == selfShort())
        local prefix = isHost and "[H] " or ""
        local r, g, b = classColor(ent.info.className)
        local hex = string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
        row.text:SetText("|c" .. hex .. prefix .. ent.short .. "|r")

        -- Kick button only visible to host, only on non-host rows.
        if sess.state == "hosting" and ent.short ~= selfShort() then
            row.kick:Show()
            row.kick:SetScript("OnClick", function() RPCoOp.Kick(ent.short) end)
        else
            row.kick:Hide()
            row.kick:SetScript("OnClick", nil)
        end
    end

    -- Hide unused rows.
    for j = #list + 1, #rosterRows do rosterRows[j]:Hide() end
end

RPCoOp.OnRosterChanged   = rebuildRoster
RPCoOp.OnSessionChanged  = rebuildRoster

function RPCoOp.AttachRosterPanel(parent, anchor, ref, relPoint, ox, oy)
    if rosterPanel then return rosterPanel end
    rosterPanel = CreateFrame("Frame", "L3FRPCoOpPanel", parent,
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
    title:SetText("Co-op session")

    statusFS = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusFS:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    statusFS:SetPoint("RIGHT", rosterPanel, "RIGHT", -8, 0)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetText("|cffaaaaaaNot in a session|r")

    -- Action button groups -- one shown at a time based on session state.
    idleBtns = CreateFrame("Frame", nil, rosterPanel)
    idleBtns:SetSize(204, 26)
    idleBtns:SetPoint("BOTTOMLEFT", rosterPanel, "BOTTOMLEFT", 8, 8)
    local startBtn = CreateFrame("Button", nil, idleBtns, "UIPanelButtonTemplate")
    startBtn:SetSize(200, 22); startBtn:SetText("Start co-op session")
    startBtn:SetPoint("BOTTOMLEFT", idleBtns, "BOTTOMLEFT", 0, 0)
    startBtn:SetScript("OnClick", function() RPCoOp.StartSession() end)

    hostBtns = CreateFrame("Frame", nil, rosterPanel)
    hostBtns:SetSize(204, 26)
    hostBtns:SetPoint("BOTTOMLEFT", rosterPanel, "BOTTOMLEFT", 8, 8)
    local inviteBtn = CreateFrame("Button", nil, hostBtns, "UIPanelButtonTemplate")
    inviteBtn:SetSize(96, 22); inviteBtn:SetText("Invite")
    inviteBtn:SetPoint("BOTTOMLEFT", hostBtns, "BOTTOMLEFT", 0, 0)
    inviteBtn:SetScript("OnClick", function() RPCoOp.ShowInvitePopup() end)
    local endBtn = CreateFrame("Button", nil, hostBtns, "UIPanelButtonTemplate")
    endBtn:SetSize(96, 22); endBtn:SetText("End session")
    endBtn:SetPoint("BOTTOMLEFT", hostBtns, "BOTTOMLEFT", 104, 0)
    endBtn:SetScript("OnClick", function() RPCoOp.EndSession() end)
    hostBtns:Hide()

    joinedBtns = CreateFrame("Frame", nil, rosterPanel)
    joinedBtns:SetSize(204, 26)
    joinedBtns:SetPoint("BOTTOMLEFT", rosterPanel, "BOTTOMLEFT", 8, 8)
    local leaveBtn = CreateFrame("Button", nil, joinedBtns, "UIPanelButtonTemplate")
    leaveBtn:SetSize(200, 22); leaveBtn:SetText("Leave session")
    leaveBtn:SetPoint("BOTTOMLEFT", joinedBtns, "BOTTOMLEFT", 0, 0)
    leaveBtn:SetScript("OnClick", function() RPCoOp.EndSession() end)
    joinedBtns:Hide()

    rebuildRoster()
    return rosterPanel
end

function RPCoOp.ToggleRosterPanel()
    if rosterPanel then
        -- Fixed panel mode for Raid Planner: keep it visible.
        rosterPanel:Show()
    end
end


-- =============================================================
-- INVITE POPUP (4 source modes)
-- =============================================================
local invitePopup
local inviteMode = "raid"  -- "raid" | "guild" | "name" | "mass"

local function listGuildOnline()
    local out = {}
    if not IsInGuild() then return out end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name and online and shortName(name) ~= selfShort() then
            table.insert(out, { name = name, short = shortName(name), class = classFile or "UNKNOWN" })
        end
    end
    table.sort(out, function(a, b) return a.short < b.short end)
    return out
end

local function listPartyRaid()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n, _, _, _, _, classFile = GetRaidRosterInfo(i)
            if n and shortName(n) ~= selfShort() then
                table.insert(out, { name = n, short = shortName(n), class = classFile or "UNKNOWN" })
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            local n = UnitName(unit)
            local _, classFile = UnitClass(unit)
            if n and shortName(n) ~= selfShort() then
                table.insert(out, { name = n, short = shortName(n), class = classFile or "UNKNOWN" })
            end
        end
    end
    table.sort(out, function(a, b) return a.short < b.short end)
    return out
end

local function buildInvitePopup()
    if invitePopup then return invitePopup end
    local f = CreateFrame("Frame", "L3FRPInvitePopup", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(340, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText("Invite to co-op") end
    tinsert(UISpecialFrames, "L3FRPInvitePopup")

    -- Source mode buttons.
    local modes = {
        { key = "raid",  label = "Party/raid" },
        { key = "guild", label = "Guildie" },
        { key = "name",  label = "By name" },
        { key = "mass",  label = "All guild" },
    }
    f.modeButtons = {}
    for i, m in ipairs(modes) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(72, 20); b:SetText(m.label)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + (i - 1) * 78, -28)
        b:SetScript("OnClick", function()
            inviteMode = m.key
            f.refresh()
        end)
        f.modeButtons[m.key] = b
    end

    -- List area scaffold (rebuilt per mode).
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -56)
    f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 36)

    f.statusFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.statusFS:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 12)
    f.statusFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 12)
    f.statusFS:SetJustifyH("LEFT")

    local function closeAfterInvite(ok)
        if ok then f:Hide() end
    end

    f.refresh = function()
        -- Active button highlight.
        for k, b in pairs(f.modeButtons) do
            if k == inviteMode then b:LockHighlight() else b:UnlockHighlight() end
        end
        -- Wipe body.
        for _, c in ipairs({f.body:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        for _, r in ipairs({f.body:GetRegions()}) do r:Hide(); r:ClearAllPoints() end

        if not RPCoOp.IsHost() then
            local fs = f.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            fs:SetPoint("CENTER", f.body, "CENTER", 0, 0)
            fs:SetText("Start a co-op session first.")
            f.statusFS:SetText("")
            return
        end

        if inviteMode == "raid" then
            local list = listPartyRaid()
            if #list == 0 then
                local fs = f.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                fs:SetPoint("CENTER", f.body, "CENTER", 0, 0)
                fs:SetText("Not in a party or raid.")
                return
            end
            local scroll = CreateFrame("ScrollFrame", nil, f.body, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, 0)
            scroll:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT", -20, 0)
            local content = CreateFrame("Frame", nil, scroll)
            content:SetSize(280, #list * 22 + 8)
            scroll:SetScrollChild(content)
            for i, ent in ipairs(list) do
                local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
                b:SetSize(260, 20)
                b:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -((i - 1) * 22))
                local r, g, bl = classColor(ent.class)
                b:SetText(string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, bl * 255, ent.short))
                b:SetScript("OnClick", function()
                    closeAfterInvite(RPCoOp.Invite(ent.name))
                end)
            end
            f.statusFS:SetText("Click a name to invite.")

        elseif inviteMode == "guild" then
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
                        b:SetText(string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, bl * 255, ent.short))
                        b:SetScript("OnClick", function()
                            closeAfterInvite(RPCoOp.Invite(ent.name))
                        end)
                        shown = shown + 1
                    end
                end
                content:SetHeight(math.max(20, shown * 22 + 8))
            end
            searchEdit:SetScript("OnTextChanged", function(self) render(self:GetText()) end)
            render("")
            f.statusFS:SetText("Click a name to invite. " .. #list .. " online.")

        elseif inviteMode == "name" then
            local label = f.body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", f.body, "TOPLEFT", 10, -8)
            label:SetText("Player name:")
            local nameEdit = CreateFrame("EditBox", nil, f.body, "InputBoxTemplate")
            nameEdit:SetSize(220, 22)
            nameEdit:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -8)
            nameEdit:SetAutoFocus(true); nameEdit:SetMaxLetters(64)
            local sendBtn = CreateFrame("Button", nil, f.body, "UIPanelButtonTemplate")
            sendBtn:SetSize(90, 22); sendBtn:SetText("Invite")
            sendBtn:SetPoint("LEFT", nameEdit, "RIGHT", 6, 0)
            local function go()
                local n = nameEdit:GetText() or ""
                if n ~= "" then
                    local ok = RPCoOp.Invite(n)
                    if ok then
                        nameEdit:SetText("")
                    end
                    closeAfterInvite(ok)
                end
            end
            sendBtn:SetScript("OnClick", go)
            nameEdit:SetScript("OnEnterPressed", go)
            f.statusFS:SetText("Same-realm only. Use 'Name' (no -Realm suffix).")

        elseif inviteMode == "mass" then
            local label = f.body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", f.body, "TOPLEFT", 10, -8)
            label:SetWidth(310); label:SetJustifyH("LEFT")
            local ok, reason = RPCoOp.CanMassInvite()
            if ok then
                label:SetText("Send an invite to every online guildie.\nTheir privacy setting decides if they see it.")
                local sendBtn = CreateFrame("Button", nil, f.body, "UIPanelButtonTemplate")
                sendBtn:SetSize(180, 24); sendBtn:SetText("Invite entire online guild")
                sendBtn:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -16)
                sendBtn:SetScript("OnClick", function()
                    local ok = RPCoOp.InviteAllGuild()
                    if ok then
                        f:Hide()
                    else
                        f.refresh()
                    end
                end)
                f.statusFS:SetText("5-minute cooldown applies after sending.")
            else
                label:SetTextColor(1, 0.4, 0.4)
                label:SetText("Cannot mass-invite: " .. (reason or "?"))
                f.statusFS:SetText("Adjust officer-rank threshold in Settings.")
            end
        end
    end

    invitePopup = f
    return f
end

function RPCoOp.ShowInvitePopup()
    local f = buildInvitePopup()
    f.refresh()
    f:Show()
end


-- =============================================================
-- INCOMING-INVITE POPUP (receiver side)
-- =============================================================
local incomingStack = {}  -- list of { frame, sessionId }

local function dismissIncoming(sessionId)
    for i = #incomingStack, 1, -1 do
        if incomingStack[i].sessionId == sessionId then
            incomingStack[i].frame:Hide()
            table.remove(incomingStack, i)
        end
    end
end

function RPCoOp.ShowIncomingInvitePopup(sessionId, hostName, encounterName)
    local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(360, 130)
    -- Stack popups vertically so multiple invites don't overlap.
    local y = -120 - (#incomingStack * 140)
    f:SetPoint("TOP", UIParent, "TOP", 0, y)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true); f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if f.TitleText then f.TitleText:SetText("Co-op invite") end
    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    msg:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
    msg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -32)
    msg:SetJustifyH("LEFT")
    msg:SetText(string.format(
        "|cffffd100%s|r invites you to a Raid Planner co-op session\nfor |cffaaccff%s|r.",
        hostName or "?", encounterName or "?"))

    local acc = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    acc:SetSize(100, 22); acc:SetText("Accept")
    acc:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    acc:SetScript("OnClick", function()
        RPCoOp.AcceptInvite(sessionId)
        dismissIncoming(sessionId)
    end)
    local dec = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dec:SetSize(100, 22); dec:SetText("Decline")
    dec:SetPoint("RIGHT", acc, "LEFT", -8, 0)
    dec:SetScript("OnClick", function()
        RPCoOp.DeclineInvite(sessionId)
        dismissIncoming(sessionId)
    end)
    -- Auto-dismiss after 60s so the popup doesn't linger if the
    -- recipient ignores it; the session host gets an implicit "no reply".
    C_Timer.After(60, function() dismissIncoming(sessionId) end)

    table.insert(incomingStack, { frame = f, sessionId = sessionId })
    f:Show()
end

-- Wire the co-op module's incoming-invite signal to our popup.
RPCoOp.OnIncomingInvite = function(sessionId, hostName, encounterName)
    RPCoOp.ShowIncomingInvitePopup(sessionId, hostName, encounterName)
end

RPCoOp.OnIncomingInviteCanceled = function(sessionId)
    dismissIncoming(sessionId)
end
