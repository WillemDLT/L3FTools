-- =============================================================
-- L3FTools - Tabs/Guild/ComposerCoOp.lua
-- =============================================================
-- Live multi-player co-editing for the Raid Composer.
--
-- Architecture (deliberately simpler than RaidPlanner co-op):
--   * Host-owned, ephemeral. One player clicks "Start co-op session"
--     from the Composer tab; their active profile is canonical.
--   * Invite scope: GUILD ONLY. Single invite path -- pick a guildie
--     from the guild roster. No party/raid, no by-name, no officer
--     mass-invite (per Morpheours's scope-down for Composer).
--   * Sync model: SNAPSHOT-ONLY. The Composer's L3F2C-format profile
--     is ~1KB compressed; per-mutation deltas aren't worth the
--     complexity. Instead, every local mutation marks the session
--     dirty; a 300ms debounce coalesces bursts into one snapshot
--     broadcast.
--   * Privacy framework REUSED from L3F.RPCoOp. Recipients with
--     L3F.RPCoOp.GetPrivacy() == "off" / scope mismatch silently
--     skip the popup. One shared player setting covers both features.
--   * Comm: prefix L3F_COCO, WHISPER addon-message for in-session
--     traffic (BULK priority via ChatThrottleLib).
-- =============================================================

local addonName, L3F = ...

L3F.ComposerCoOp = L3F.ComposerCoOp or {}
local CoOp = L3F.ComposerCoOp

local PREFIX = "L3F_COCO"
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

-- Pull privacy from the shared RPCoOp settings. Default to "anyone"
-- if RPCoOp isn't loaded yet (which shouldn't happen given TOC order).
local function getPrivacy()
    return (L3F.RPCoOp and L3F.RPCoOp.GetPrivacy and L3F.RPCoOp.GetPrivacy())
        or "anyone"
end


-- =============================================================
-- Session state
-- =============================================================
local session = { state = "idle" }
local pendingInvites = {}
local incomingInvites = {}
local applying = false

function CoOp.IsActive()         return session.state ~= "idle" end
function CoOp.IsHost()           return session.state == "hosting" end
function CoOp.IsApplyingRemote() return applying end
function CoOp.GetSession()
    if session.state == "idle" then return nil end
    return session
end
function CoOp.GetPendingInvites() return pendingInvites end
function CoOp.GetPendingIncomingInvites()
    local out = {}
    for k, v in pairs(incomingInvites) do out[k] = v end
    return out
end

local function shortName(s) return Ambiguate(s or "", "short") end
local function selfShort()  return UnitName("player") or "?" end
local function selfClass()
    local _, c = UnitClass("player")
    return c or "UNKNOWN"
end


-- =============================================================
-- Privacy + guild gating
-- =============================================================
local function isGuildmate(short)
    if not IsInGuild() then return false end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name and shortName(name) == short then return true end
    end
    return false
end

local function isInPartyOrRaid(short)
    if short == selfShort() then return true end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n = GetRaidRosterInfo(i)
            if n and shortName(n) == short then return true end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local n = UnitName("party" .. i)
            if n and shortName(n) == short then return true end
        end
    end
    return false
end

local function isFriend(short)
    if not C_FriendList or not C_FriendList.GetNumFriends then return false end
    local n = C_FriendList.GetNumFriends() or 0
    for i = 1, n do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name and shortName(info.name) == short then return true end
    end
    return false
end

local function passesPrivacy(senderShort)
    local p = getPrivacy()
    if p == "off" then return false end
    if p == "anyone" then return true end
    if p == "guild" then return isGuildmate(senderShort) end
    if p == "raid"  then return isInPartyOrRaid(senderShort) end
    if p == "guild_raid_friends" then
        return isGuildmate(senderShort)
            or isInPartyOrRaid(senderShort)
            or isFriend(senderShort)
    end
    return true
end


-- =============================================================
-- Wire layer
-- =============================================================
local function sendAddon(channel, target, msg, priority)
    priority = priority or "NORMAL"
    local CTL = _G.ChatThrottleLib
    if CTL and CTL.SendAddonMessage then
        CTL:SendAddonMessage(priority, PREFIX, msg, channel, target)
    else
        C_ChatInfo.SendAddonMessage(PREFIX, msg, channel, target)
    end
end

local function sanitize(s)
    s = tostring(s or "")
    s = s:gsub("|", "/"):gsub("\n", " "):gsub("\r", " ")
    return s
end

local function pack(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = sanitize(select(i, ...)) end
    return table.concat(parts, "|")
end


-- =============================================================
-- Roster helpers
-- =============================================================
local function rosterCSV()
    local parts = {}
    for short, info in pairs(session.members or {}) do
        table.insert(parts, short .. ":" .. (info.className or "UNKNOWN"))
    end
    return table.concat(parts, ";")
end

local function parseRosterCSV(csv)
    local out = {}
    for entry in string.gmatch(csv or "", "[^;]+") do
        local s, c = strsplit(":", entry)
        if s and s ~= "" then
            out[s] = { name = s, className = c or "UNKNOWN", joinedAt = GetTime() }
        end
    end
    return out
end

local function newSessionId()
    local s = selfShort()
    local rnd = string.format("%06x", math.random(0, 0xFFFFFF))
    return s:sub(1, 8) .. rnd
end

local function fireRosterChanged()
    if CoOp.OnRosterChanged then CoOp.OnRosterChanged() end
end
local function fireSessionChanged()
    if CoOp.OnSessionChanged then CoOp.OnSessionChanged() end
end
local function fireIncomingInvite(sessionId, hostName)
    if CoOp.OnIncomingInvite then
        CoOp.OnIncomingInvite(sessionId, hostName)
    end
end

local function toast(msg, color)
    color = color or "ffd100"
    print("|cff" .. color .. "L3F Composer co-op:|r " .. msg)
end


-- =============================================================
-- Send paths
-- =============================================================
local function sendToMembers(msg, priority)
    if session.state == "idle" then return end
    local me = selfShort()
    for short, info in pairs(session.members or {}) do
        if short ~= me and info.name then
            sendAddon("WHISPER", info.name, msg, priority)
        end
    end
end

local function sendToOne(targetFullName, msg, priority)
    sendAddon("WHISPER", targetFullName, msg, priority)
end


function CoOp.StartSession()
    if session.state ~= "idle" then
        toast("Already in a session.")
        return
    end
    if not IsInGuild() then
        toast("Composer co-op is guild-scoped. You must be in a guild.", "ff6666")
        return
    end
    local me = selfShort()
    session = {
        state = "hosting",
        sessionId = newSessionId(),
        members = {
            [me] = {
                name = UnitName("player"),
                className = selfClass(),
                joinedAt = GetTime(),
            },
        },
    }
    pendingInvites = {}
    toast("Session started. Invite guildies from the co-op panel.")
    fireSessionChanged()
    fireRosterChanged()
end

function CoOp.EndSession()
    if session.state == "idle" then return end
    if session.state == "hosting" then
        sendToMembers(pack("END", session.sessionId), "NORMAL")
    elseif session.state == "joined" then
        local host = session.members and session.members[session.hostName]
        if host and host.name then
            sendToOne(host.name,
                pack("LEAVE", session.sessionId, selfShort()), "NORMAL")
        end
    end
    session = { state = "idle" }
    pendingInvites = {}
    toast("Session ended.")
    fireSessionChanged()
    fireRosterChanged()
end

-- Guild-only invite. The picker UI restricts to guildies; this guard
-- defends against a malformed call from elsewhere.
function CoOp.Invite(fullName)
    if session.state ~= "hosting" then
        toast("Start a co-op session first.")
        return false, "Not hosting"
    end
    if not fullName or fullName == "" then return false, "No name" end
    local short = shortName(fullName)
    if short == selfShort() then
        toast("You cannot invite yourself.")
        return false, "Self"
    end
    if not isGuildmate(short) then
        toast(short .. " is not a guildmate.", "ff6666")
        return false, "Not guildmate"
    end
    if session.members[short] then
        toast(short .. " is already in the session.")
        return false, "Already in"
    end
    pendingInvites[short] = GetTime()
    sendToOne(fullName,
        pack("INV", session.sessionId, selfShort()), "NORMAL")
    toast("Invite sent to " .. short)
    fireRosterChanged()
    return true
end

function CoOp.AcceptInvite(sessionId)
    local inv = incomingInvites[sessionId]
    if not inv then
        toast("That invite expired.")
        return
    end
    incomingInvites[sessionId] = nil
    session = {
        state = "joined",
        sessionId = sessionId,
        hostName = inv.hostName,
        members = {
            [inv.hostName] = {
                name = inv.fromFull or inv.hostName,
                className = "UNKNOWN",
                joinedAt = GetTime(),
            },
            [selfShort()] = {
                name = UnitName("player"),
                className = selfClass(),
                joinedAt = GetTime(),
            },
        },
    }
    sendToOne(inv.fromFull or inv.hostName,
        pack("ACC", sessionId, selfShort(), selfClass()), "NORMAL")
    toast("Joined " .. inv.hostName .. " session. Waiting for snapshot...")
    fireSessionChanged()
    fireRosterChanged()
end

function CoOp.DeclineInvite(sessionId)
    local inv = incomingInvites[sessionId]
    if not inv then return end
    incomingInvites[sessionId] = nil
    sendToOne(inv.fromFull or inv.hostName,
        pack("DEC", sessionId, selfShort()), "NORMAL")
end

function CoOp.Kick(short)
    if session.state ~= "hosting" then return end
    local m = session.members and session.members[short]
    if not m then return end
    sendToOne(m.name, pack("KICK", session.sessionId), "NORMAL")
    session.members[short] = nil
    sendToMembers(pack("ROSTER", session.sessionId, rosterCSV()), "NORMAL")
    toast("Kicked " .. short)
    fireRosterChanged()
end


-- =============================================================
-- Snapshot push (called by debounced notifyComposerEdit in Composer.lua)
-- =============================================================
local function buildSnapshotPayload()
    if not L3F._CompSerializeProfile then return nil end
    if not L3F.db or not L3F.db.composer then return nil end
    local activeName = L3F.db.composer.activeProfile or "Default"
    local profile = L3F.db.composer.profiles
        and L3F.db.composer.profiles[activeName]
    if not profile then return nil end
    return L3F._CompSerializeProfile(activeName, profile), activeName
end

function CoOp.BroadcastSnapshot()
    if session.state == "idle" then return end
    if applying then return end
    local payload, activeName = buildSnapshotPayload()
    if not payload then return end
    -- The active profile name is folded into the payload by the
    -- serializer; we also send it as a separate header field so the
    -- receiver knows which profile slot to overwrite.
    sendToMembers(pack("SNAP", session.sessionId,
        activeName or "", payload), "BULK")
end

-- Per-joiner snapshot (host sends right after ACC arrives).
local function sendSnapshotTo(targetFullName)
    if session.state ~= "hosting" then return end
    local payload, activeName = buildSnapshotPayload()
    if not payload then return end
    sendToOne(targetFullName,
        pack("SNAP", session.sessionId, activeName or "", payload),
        "BULK")
end


-- =============================================================
-- Receive layer
-- =============================================================
local function onSnapshot(sessionId, activeName, payload)
    if session.state == "idle" or session.sessionId ~= sessionId then return end
    if not L3F._CompApplySnapshot then return end
    applying = true
    local ok = pcall(L3F._CompApplySnapshot, activeName, payload)
    applying = false
    if ok and CoOp.OnRemoteApplied then CoOp.OnRemoteApplied() end
end

local function onInvite(senderShort, senderFull, sessionId, hostName)
    if not passesPrivacy(senderShort) then return end
    if not isGuildmate(senderShort) then
        -- Even if privacy allows, Composer is guild-scoped.
        return
    end
    if session.state ~= "idle" then
        sendToOne(senderFull or hostName,
            pack("DEC", sessionId, selfShort()), "NORMAL")
        return
    end
    if incomingInvites[sessionId] then return end
    incomingInvites[sessionId] = {
        hostName   = senderShort,
        fromFull   = senderFull,
        receivedAt = GetTime(),
    }
    fireIncomingInvite(sessionId, senderShort)
end

local function onAccept(senderShort, senderFull, sessionId, joinerShort, joinerClass)
    if session.state ~= "hosting" or session.sessionId ~= sessionId then return end
    pendingInvites[senderShort] = nil
    local short = joinerShort or senderShort
    session.members[short] = {
        name = senderFull or short,
        className = joinerClass or "UNKNOWN",
        joinedAt = GetTime(),
    }
    sendToMembers(pack("ROSTER", sessionId, rosterCSV()), "NORMAL")
    sendSnapshotTo(senderFull or short)
    toast(senderShort .. " joined the session.")
    fireRosterChanged()
end

local function onDecline(senderShort, sessionId)
    if session.state ~= "hosting" or session.sessionId ~= sessionId then return end
    pendingInvites[senderShort] = nil
    toast(senderShort .. " declined the invite.")
    fireRosterChanged()
end

local function onLeave(senderShort, sessionId)
    if session.state ~= "hosting" or session.sessionId ~= sessionId then return end
    if session.members and session.members[senderShort] then
        session.members[senderShort] = nil
        sendToMembers(pack("ROSTER", sessionId, rosterCSV()), "NORMAL")
        toast(senderShort .. " left the session.")
        fireRosterChanged()
    end
end

local function onKick(sessionId)
    if session.state ~= "joined" or session.sessionId ~= sessionId then return end
    session = { state = "idle" }
    toast("Host kicked you from the session.", "ff6666")
    fireSessionChanged()
    fireRosterChanged()
end

local function onEnd(sessionId)
    if session.state == "idle" or session.sessionId ~= sessionId then return end
    session = { state = "idle" }
    toast("Host ended the session.")
    fireSessionChanged()
    fireRosterChanged()
end

local function onRoster(sessionId, csv)
    if session.state == "idle" or session.sessionId ~= sessionId then return end
    if session.state == "joined" then
        local newMembers = parseRosterCSV(csv)
        local me = selfShort()
        if newMembers[me] then
            newMembers[me] = {
                name = UnitName("player"),
                className = selfClass(),
                joinedAt = (session.members[me] and session.members[me].joinedAt)
                    or GetTime(),
            }
        end
        local host = session.hostName
        if host and newMembers[host] and session.members[host]
           and session.members[host].name then
            newMembers[host].name = session.members[host].name
        end
        session.members = newMembers
        fireRosterChanged()
    end
end


-- =============================================================
-- CHAT_MSG_ADDON dispatcher
-- =============================================================
local recvFrame = CreateFrame("Frame")
recvFrame:RegisterEvent("CHAT_MSG_ADDON")
recvFrame:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    if prefix ~= PREFIX or not text then return end
    local me = selfShort()
    local senderShort = shortName(sender)
    if senderShort == me then return end
    local kind, a, b, c = strsplit("|", text, 4)
    if not kind then return end
    if kind == "INV" then
        onInvite(senderShort, sender, a, b)
    elseif kind == "ACC" then
        onAccept(senderShort, sender, a, b, c)
    elseif kind == "DEC" then
        onDecline(senderShort, a)
    elseif kind == "LEAVE" then
        onLeave(senderShort, a)
    elseif kind == "KICK" then
        onKick(a)
    elseif kind == "END" then
        onEnd(a)
    elseif kind == "ROSTER" then
        onRoster(a, b)
    elseif kind == "SNAP" then
        onSnapshot(a, b, c)
    end
end)


-- =============================================================
-- Logout cleanup
-- =============================================================
local cleanupFrame = CreateFrame("Frame")
cleanupFrame:RegisterEvent("PLAYER_LOGOUT")
cleanupFrame:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_LOGOUT" and session.state ~= "idle" then
        pcall(CoOp.EndSession)
    end
end)
