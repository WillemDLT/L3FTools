-- =============================================================
-- L3FTools - Tabs/Guild/RaidPlannerCoOp.lua
-- =============================================================
-- Live multi-player co-editing for the Raid Planner.
--
-- Architecture:
--   * Session is HOST-OWNED, EPHEMERAL. One player clicks "Start
--     co-op session"; their plan is canonical. Host disconnect /
--     /reload / "End session" tears down for everyone.
--   * Joined members can EDIT freely (place/move/remove icons,
--     draw pen strokes, change props). Host has kick + nav
--     control privileges.
--   * Navigation is HOST-LOCKED: encounter / page / background
--     switches broadcast from host only.
--   * Comm: prefix L3F_RPCO, WHISPER addon-message for in-session
--     deltas (per-member fan-out, throttled via ChatThrottleLib).
--     GUILD addon-message ONLY for the officer mass-invite path.
--     PARTY/RAID for ShareToRaid (one-shot snapshot, not session).
--   * Snapshot on join uses LibDeflate via the same serializer the
--     L3F2 share string uses (RaidPlanner.lua / serializePlan, re-
--     exported as L3F._RPSerializePlan).
--   * Receiver privacy filter on incoming invites: "anyone",
--     "guild_raid_friends", "guild", "raid", "off".
--   * Officer mass-invite gated by guild rank (default: rank <= 2),
--     5-minute cooldown per sender.
-- =============================================================

local addonName, L3F = ...

L3F.RPCoOp = L3F.RPCoOp or {}
local RPCoOp = L3F.RPCoOp

local PREFIX = "L3F_RPCO"
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
local MAX_ADDON_MSG_BYTES = 255
-- CHN2: raw chunk payload (faster, less overhead).
-- CHNK: legacy hex-chunk payload (kept for backward compatibility).
local CHUNK_KIND = "CHN2"
local CHUNK_KIND_HEX = "CHNK"
-- 232 + ~22 bytes header stays below the 255-byte addon limit.
local CHUNK_RAW_BYTES = 232
local CHUNK_TTL = 30

-- =============================================================
-- Settings (in SavedVariables under L3F.db.rpCoOp)
-- =============================================================
local DEFAULT_PRIVACY = "anyone"
local DEFAULT_OFFICER_RANK_MAX = 2
local MASS_INVITE_COOLDOWN = 300

local function db()
    L3F.db = L3F.db or {}
    L3F.db.rpCoOp = L3F.db.rpCoOp or {}
    local d = L3F.db.rpCoOp
    if d.privacy == nil then d.privacy = DEFAULT_PRIVACY end
    if d.officerRankMax == nil then d.officerRankMax = DEFAULT_OFFICER_RANK_MAX end
    return d
end

function RPCoOp.GetPrivacy() return db().privacy end
function RPCoOp.SetPrivacy(v) db().privacy = v end
function RPCoOp.GetOfficerRankMax() return db().officerRankMax end
function RPCoOp.SetOfficerRankMax(v)
    db().officerRankMax = math.max(0, math.min(9, tonumber(v) or 2))
end

RPCoOp.PRIVACY_LABELS = {
    anyone              = "Anyone",
    guild_raid_friends  = "Guild, raid, or friends",
    guild               = "Guild only",
    raid                = "Party or raid only",
    off                 = "Nobody (off)",
}
RPCoOp.PRIVACY_ORDER = {
    "anyone", "guild_raid_friends", "guild", "raid", "off",
}


-- =============================================================
-- Session state
-- =============================================================
local session = { state = "idle" }
local pendingInvites = {}   -- host-side outgoing invites (short -> sentAt)
local incomingInvites = {}  -- invitee-side (sessionId -> invite info)
local lastMassInviteAt = 0
local applying = false      -- echo-loop guard

function RPCoOp.IsActive()       return session.state ~= "idle" end
function RPCoOp.IsHost()         return session.state == "hosting" end
function RPCoOp.IsApplyingRemote() return applying end
function RPCoOp.GetSession()
    if session.state == "idle" then return nil end
    return session
end

function RPCoOp.GetPlannerState()
    if session.state ~= "joined" then return nil end
    session.raidPlannerState = session.raidPlannerState or {
        activeEncounter = nil,
        activePlanIdx = 1,
        plansByEncounter = {},
    }
    return session.raidPlannerState
end

function RPCoOp.GetPendingInvites()         return pendingInvites end
function RPCoOp.GetPendingIncomingInvites()
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
-- Privacy filter
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
    local p = db().privacy
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
-- Officer rank check
-- =============================================================
local function myGuildRankIndex()
    if not IsInGuild() then return nil end
    local n = GetNumGuildMembers() or 0
    local me = selfShort()
    for i = 1, n do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and shortName(name) == me then return rankIndex end
    end
    return nil
end

function RPCoOp.CanMassInvite()
    if not IsInGuild() then return false, "Not in a guild" end
    local rank = myGuildRankIndex()
    if not rank then return false, "Guild rank unknown (try /reload)" end
    if rank > db().officerRankMax then
        return false, "Requires guild rank " .. db().officerRankMax
            .. " or lower (you are rank " .. rank .. ")"
    end
    local now = GetTime()
    if (now - lastMassInviteAt) < MASS_INVITE_COOLDOWN then
        local left = math.ceil(MASS_INVITE_COOLDOWN - (now - lastMassInviteAt))
        return false, "Cooldown: " .. left .. "s remaining"
    end
    return true
end


-- =============================================================
-- Wire layer
-- =============================================================
local pendingChunks = {}

local function sendRawAddon(channel, target, msg, priority)
    priority = priority or "NORMAL"
    local CTL = _G.ChatThrottleLib
    if CTL and CTL.SendAddonMessage then
        CTL:SendAddonMessage(priority, PREFIX, msg, channel, target)
    else
        C_ChatInfo.SendAddonMessage(PREFIX, msg, channel, target)
    end
end

local function encodeChunkPayload(s)
    return (s:gsub(".", function(c)
        return string.format("%02x", string.byte(c))
    end))
end

local function decodeChunkPayload(s)
    return (s:gsub("%x%x", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local function sendChunked(channel, target, msg, priority)
    local chunkId = string.format("%06x", math.random(0, 0xFFFFFF))
    local rawChunks = {}
    local p = 1
    local n = #msg
    while p <= n do
        rawChunks[#rawChunks + 1] = msg:sub(p, p + CHUNK_RAW_BYTES - 1)
        p = p + CHUNK_RAW_BYTES
    end
    local total = #rawChunks
    for idx = 1, total do
        local wire = table.concat({
            CHUNK_KIND, chunkId, tostring(idx), tostring(total), rawChunks[idx]
        }, "|")
        if #wire > MAX_ADDON_MSG_BYTES then
            return
        end
        sendRawAddon(channel, target, wire, priority)
    end
end

local function sendAddon(channel, target, msg, priority)
    if not msg or msg == "" then return end
    if #msg > MAX_ADDON_MSG_BYTES then
        sendChunked(channel, target, msg, priority)
    else
        sendRawAddon(channel, target, msg, priority)
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

-- Like pack(), but leaves the last field untouched for encoded payloads.
local function packWithRawTail(...)
    local n = select("#", ...)
    if n <= 0 then return "" end
    if n == 1 then return tostring(select(1, ...) or "") end
    local parts = {}
    for i = 1, n - 1 do
        parts[i] = sanitize(select(i, ...))
    end
    parts[n] = tostring(select(n, ...) or "")
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
    if RPCoOp.OnRosterChanged then RPCoOp.OnRosterChanged() end
end
local function fireSessionChanged()
    if RPCoOp.OnSessionChanged then RPCoOp.OnSessionChanged() end
end
local function fireIncomingInvite(sessionId, hostName, encounterName)
    if RPCoOp.OnIncomingInvite then
        RPCoOp.OnIncomingInvite(sessionId, hostName, encounterName)
    end
end
local function fireIncomingInviteCanceled(sessionId, hostName)
    if RPCoOp.OnIncomingInviteCanceled then
        RPCoOp.OnIncomingInviteCanceled(sessionId, hostName)
    end
end
local function fireRemoteApplied(deltaType, encounterName, planIdx)
    if RPCoOp.OnRemoteApplied then
        RPCoOp.OnRemoteApplied(deltaType, encounterName, planIdx)
    end
end

local function refreshRaidPlanner()
    if L3F._RPRefresh then
        L3F._RPRefresh()
    end
end

local function toast(msg, color)
    color = color or "ffd100"
    print("|cff" .. color .. "L3F co-op:|r " .. msg)
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

local function cancelPendingInvites()
    if session.state ~= "hosting" then return end
    local sessionId = session.sessionId

    for short, info in pairs(pendingInvites or {}) do
        local target = (type(info) == "table" and info.name) or short
        if target and target ~= "" then
            sendToOne(target, pack("INVC", sessionId, selfShort()), "NORMAL")
        end
    end

    if session.guildMassInvite then
        sendAddon("GUILD", nil,
            pack("INVC", sessionId, selfShort()), "NORMAL")
    end
end


function RPCoOp.StartSession()
    if session.state ~= "idle" then
        toast("Already in a session.")
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
    toast("Session started. Invite players from the co-op panel.")
    fireSessionChanged()
    fireRosterChanged()
end

function RPCoOp.EndSession()
    if session.state == "idle" then return end
    if session.state == "hosting" then
        cancelPendingInvites()
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
    refreshRaidPlanner()
end

function RPCoOp.OnMainFrameHidden()
    if session.state ~= "idle" then
        RPCoOp.EndSession()
    end
end

function RPCoOp.Invite(fullName)
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
    if session.members[short] then
        toast(short .. " is already in the session.")
        return false, "Already in"
    end
    pendingInvites[short] = {
        name = fullName,
        sentAt = GetTime(),
    }
    local enc = (L3F.db and L3F.db.raidPlanner and L3F.db.raidPlanner.activeEncounter) or "?"
    sendToOne(fullName,
        pack("INV", session.sessionId, selfShort(), enc), "NORMAL")
    toast("Invite sent to " .. short)
    fireRosterChanged()
    return true
end

function RPCoOp.InviteAllGuild()
    if session.state ~= "hosting" then
        toast("Start a co-op session first.")
        return false, "Not hosting"
    end
    local ok, reason = RPCoOp.CanMassInvite()
    if not ok then
        toast("Cannot mass-invite: " .. reason)
        return false, reason
    end
    local enc = (L3F.db and L3F.db.raidPlanner and L3F.db.raidPlanner.activeEncounter) or "?"
    sendAddon("GUILD", nil,
        pack("INV", session.sessionId, selfShort(), enc), "NORMAL")
    session.guildMassInvite = true
    lastMassInviteAt = GetTime()
    toast("Mass-invite sent to entire online guild.")
    return true
end

function RPCoOp.AcceptInvite(sessionId)
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
        raidPlannerState = {
            activeEncounter = inv.encounterName,
            activePlanIdx = 1,
            plansByEncounter = {},
        },
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
    refreshRaidPlanner()
    if L3F.ShowFrame and (not L3F.mainFrame or not L3F.mainFrame:IsShown()) then
        L3F.ShowFrame("guild.raidplanner")
    end
end

function RPCoOp.DeclineInvite(sessionId)
    local inv = incomingInvites[sessionId]
    if not inv then return end
    incomingInvites[sessionId] = nil
    sendToOne(inv.fromFull or inv.hostName,
        pack("DEC", sessionId, selfShort()), "NORMAL")
end

function RPCoOp.Kick(short)
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
-- Snapshot (full state) and ShareToRaid (one-shot)
-- =============================================================
local function buildSnapshotPayload(encounterName, planIdx, plan)
    if not L3F._RPSerializePlan then return nil end
    return L3F._RPSerializePlan(plan, encounterName, {
        wire = "addon",
        maxCompress = true,
    })
end

local function buildShareBundlePayload(encounterName, activePlanIdx, plans)
    if L3F._RPSerializePlanBundle then
        return L3F._RPSerializePlanBundle(plans, encounterName, activePlanIdx, {
            wire = "addon",
            maxCompress = true,
        })
    end

    if not L3F._RPSerializePlan then return nil end
    local fallbackPlan = plans and (plans[activePlanIdx or 1] or plans[1])
    if not fallbackPlan then return nil end
    return L3F._RPSerializePlan(fallbackPlan, encounterName, {
        wire = "addon",
        maxCompress = true,
    })
end

local function copyIconsForShare(icons)
    local out = {}
    for i, ic in ipairs(icons or {}) do
        out[i] = {
            kind = ic.kind,
            key = ic.key,
            x = ic.x,
            y = ic.y,
            color = ic.color,
            text = ic.text,
            variant = ic.variant,
            locked = ic.locked,
            direction = ic.direction,
            npcID = ic.npcID,
            npcName = ic.npcName,
            iconTex = ic.iconTex,
        }
    end
    return out
end

local function compactStrokePoints(points)
    local n = #points
    if n <= 2 then
        local cp = {}
        for i = 1, n do
            cp[i] = { x = points[i].x, y = points[i].y }
        end
        return cp
    end

    -- Share path only: strongly downsample to reduce transfer time.
    local maxPts = 96
    local minStepSq = 0.004 * 0.004
    local stride = 1
    if n > 140 then
        stride = math.max(1, math.floor(n / maxPts))
    end

    local out = {}
    out[#out + 1] = { x = points[1].x, y = points[1].y }
    local lastX, lastY = points[1].x, points[1].y
    for i = 2, n - 1, stride do
        local p = points[i]
        local dx = (p.x or 0) - (lastX or 0)
        local dy = (p.y or 0) - (lastY or 0)
        if (dx * dx + dy * dy) >= minStepSq then
            out[#out + 1] = { x = p.x, y = p.y }
            lastX, lastY = p.x, p.y
        end
    end
    out[#out + 1] = { x = points[n].x, y = points[n].y }

    if #out <= maxPts then return out end

    local reduced = {}
    reduced[#reduced + 1] = out[1]
    local middle = #out - 2
    if middle > 0 then
        local keepMid = maxPts - 2
        local step = middle / math.max(1, keepMid)
        local idx = 1
        while #reduced < (maxPts - 1) do
            idx = idx + step
            local src = out[1 + math.floor(idx + 0.5)]
            if not src then break end
            reduced[#reduced + 1] = { x = src.x, y = src.y }
        end
    end
    reduced[#reduced + 1] = out[#out]
    return reduced
end

local function copyDrawingsForShare(drawings)
    local out = {}
    for _, s in ipairs(drawings or {}) do
        local pts = compactStrokePoints(s.points or {})
        out[#out + 1] = {
            color = s.color,
            size = s.size,
            fade = s.fade,
            points = pts,
        }
    end
    return out
end

local function copyPlanForShare(plan)
    return {
        name = plan and plan.name,
        background = plan and plan.background,
        icons = copyIconsForShare(plan and plan.icons),
        drawings = copyDrawingsForShare(plan and plan.drawings),
        notes = plan and plan.notes or "",
    }
end

local function sendSnapshotTo(targetFullName)
    if session.state ~= "hosting" then return end
    if not L3F.db or not L3F.db.raidPlanner then return end
    local rp = L3F.db.raidPlanner
    local enc = rp.activeEncounter or "?"
    local planIdx = rp.activePlanIdx or 1
    local plans = rp.plansByEncounter and rp.plansByEncounter[enc]
    local plan = plans and plans[planIdx]
    if not plan then return end
    local payload = buildShareBundlePayload(enc, planIdx, plans)
        or buildSnapshotPayload(enc, planIdx, plan)
    if not payload then return end
    sendToOne(targetFullName,
        packWithRawTail("SNAP", session.sessionId, enc, tostring(planIdx), payload),
        "BULK")
end

local function canSendVisualToGroup()
    if IsInRaid() then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end
    if IsInGroup() then
        return UnitIsGroupLeader("player")
    end
    return false
end

function RPCoOp.ShareToRaid()
    if not (IsInRaid() or IsInGroup()) then
        toast("Not in a party or raid.", "ff6666")
        return false
    end
    if not canSendVisualToGroup() then
        if IsInRaid() then
            toast("Only raid leader or assistants can send a visual.", "ff6666")
        else
            toast("Only the party leader can send a visual.", "ff6666")
        end
        return false
    end
    if not L3F.db or not L3F.db.raidPlanner then return false end
    local rp = L3F.db.raidPlanner
    local enc = rp.activeEncounter or "?"
    local planIdx = rp.activePlanIdx or 1
    local plans = rp.plansByEncounter and rp.plansByEncounter[enc]
    if not plans or #plans == 0 then
        toast("No plan to share.", "ff6666")
        return false
    end

    -- Visual-share payload: send every saved tab for this encounter,
    -- including plan notes, but downsample drawings for raid-friendly size.
    local visualPlans = {}
    for i, plan in ipairs(plans) do
        visualPlans[i] = copyPlanForShare(plan)
    end
    local payload = buildShareBundlePayload(enc, planIdx, visualPlans)
    if not payload then
        toast("Snapshot serializer not loaded.", "ff6666")
        return false
    end
    local channel = IsInRaid() and "RAID" or "PARTY"
    sendAddon(channel, nil,
        packWithRawTail("SHARE", selfShort(), enc, tostring(planIdx), payload),
        "ALERT")
    toast("Plans shared with " .. (IsInRaid() and "raid" or "party") .. ".")
    return true
end


-- =============================================================
-- Delta broadcast (called from RaidPlanner.lua mutation sites)
-- =============================================================
function RPCoOp.BroadcastDelta(deltaType, payloadFields, opts)
    if session.state == "idle" then return end
    if applying then return end
    if (deltaType == "NAV" or deltaType == "NEWPL" or deltaType == "DELPL")
       and session.state ~= "hosting" then
        return
    end
    local rp = RPCoOp.GetPlannerState()
        or (L3F.db and L3F.db.raidPlanner)
    local enc = rp and rp.activeEncounter or "?"
    local planIdx = rp and rp.activePlanIdx or 1
    local parts = { deltaType, session.sessionId, enc, tostring(planIdx) }
    for _, v in ipairs(payloadFields or {}) do
        table.insert(parts, v)
    end
    sendToMembers(pack(unpack(parts)), (opts and opts.priority) or "BULK")
end


-- =============================================================
-- Receive layer
-- =============================================================
local function onSnapshot(sessionId, enc, planIdxStr, payload)
    if session.state ~= "joined" or session.sessionId ~= sessionId then return end
    if not L3F._RPApplySnapshot then return end
    applying = true
    local ok = pcall(L3F._RPApplySnapshot, enc, tonumber(planIdxStr) or 1, payload)
    applying = false
    if ok then
        fireRemoteApplied("SNAP", enc, tonumber(planIdxStr) or 1)
        toast("Synced to host's plan.")
    end
end

local function applyRemoteDelta(deltaType, sessionId, enc, planIdxStr, ...)
    if session.state == "idle" or session.sessionId ~= sessionId then return end
    if not L3F._RPApplyDelta then return end
    local planIdx = tonumber(planIdxStr) or 1
    applying = true
    pcall(L3F._RPApplyDelta, deltaType, enc, planIdx, ...)
    applying = false
    fireRemoteApplied(deltaType, enc, planIdx)
end

local function onInvite(senderShort, senderFull, sessionId, hostName, encounterName)
    if not passesPrivacy(senderShort) then return end
    if session.state ~= "idle" then
        sendToOne(senderFull or hostName,
            pack("DEC", sessionId, selfShort()), "NORMAL")
        return
    end
    if incomingInvites[sessionId] then return end
    incomingInvites[sessionId] = {
        hostName      = senderShort,
        fromFull      = senderFull,
        encounterName = encounterName,
        receivedAt    = GetTime(),
    }
    fireIncomingInvite(sessionId, senderShort, encounterName)
end

local function onInviteCancel(senderShort, sessionId)
    local inv = incomingInvites[sessionId]
    if not inv then return end
    if inv.hostName and inv.hostName ~= senderShort then return end

    incomingInvites[sessionId] = nil
    fireIncomingInviteCanceled(sessionId, senderShort)
    toast((senderShort or "Host") .. " canceled the invite.")
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
    refreshRaidPlanner()
end

local function onEnd(sessionId)
    if session.state == "idle" or session.sessionId ~= sessionId then return end
    session = { state = "idle" }
    toast("Host ended the session.")
    fireSessionChanged()
    fireRosterChanged()
    refreshRaidPlanner()
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

local function onShare(senderShort, senderFull, enc, planIdxStr, payload)
    if senderShort == selfShort() then return end
    if not passesPrivacy(senderShort) then return end
    if RPCoOp.OnIncomingShare then
        RPCoOp.OnIncomingShare(senderShort, senderFull, enc,
            tonumber(planIdxStr) or 1, payload)
    end
end


-- =============================================================
-- CHAT_MSG_ADDON dispatcher
-- =============================================================
local function dispatchMessage(text, senderShort, sender)
    local kind = text:match("^[^|]+")
    if not kind then return end
    if kind == "SNAP" then
        local _, sessionId, enc, planIdxStr, payload = strsplit("|", text, 5)
        onSnapshot(sessionId, enc, planIdxStr, payload)
        return
    elseif kind == "SHARE" then
        local _, _senderName, enc, planIdxStr, payload = strsplit("|", text, 5)
        onShare(senderShort, sender, enc, planIdxStr, payload)
        return
    end

    local _, a, b, c, d, e, f, g, h, i, j = strsplit("|", text)
    if kind == "INV" then
        onInvite(senderShort, sender, a, b, c)
    elseif kind == "INVC" then
        onInviteCancel(senderShort, a)
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
    elseif kind == "PLACE" or kind == "MOVE" or kind == "RM"
        or kind == "PROPS" or kind == "DRAW" or kind == "RMDRAW"
        or kind == "PEN_CLEAR"
        or kind == "NAV" or kind == "NEWPL" or kind == "DELPL"
        or kind == "NOTES" then
        applyRemoteDelta(kind, a, b, c, d, e, f, g, h, i, j)
    end
end

local function cleanupPendingChunks(now)
    for k, data in pairs(pendingChunks) do
        if (now - (data.t or now)) > CHUNK_TTL then
            pendingChunks[k] = nil
        end
    end
end

local function ingestChunk(senderShort, text)
    local kind, chunkId, idxStr, totalStr, payloadEnc = strsplit("|", text, 5)
    local idx = tonumber(idxStr)
    local total = tonumber(totalStr)
    if not chunkId or not idx or not total or idx < 1 or total < 1
       or (kind ~= CHUNK_KIND and kind ~= CHUNK_KIND_HEX) then
        return nil
    end
    cleanupPendingChunks(GetTime())
    local key = senderShort .. ":" .. kind .. ":" .. chunkId
    local slot = pendingChunks[key]
    if not slot then
        slot = { total = total, parts = {}, got = 0, t = GetTime() }
        pendingChunks[key] = slot
    end
    if slot.total ~= total then
        pendingChunks[key] = nil
        return nil
    end
    if not slot.parts[idx] then
        if kind == CHUNK_KIND_HEX then
            slot.parts[idx] = decodeChunkPayload(payloadEnc or "")
        else
            slot.parts[idx] = payloadEnc or ""
        end
        slot.got = slot.got + 1
    end
    slot.t = GetTime()
    if slot.got < slot.total then
        return nil
    end
    local joined = {}
    for n = 1, slot.total do
        if not slot.parts[n] then return nil end
        joined[n] = slot.parts[n]
    end
    pendingChunks[key] = nil
    return table.concat(joined)
end

local recvFrame = CreateFrame("Frame")
recvFrame:RegisterEvent("CHAT_MSG_ADDON")
recvFrame:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    if prefix ~= PREFIX or not text then return end
    local me = selfShort()
    local senderShort = shortName(sender)
    if senderShort == me then return end
    if text:sub(1, #CHUNK_KIND + 1) == (CHUNK_KIND .. "|")
       or text:sub(1, #CHUNK_KIND_HEX + 1) == (CHUNK_KIND_HEX .. "|") then
        local rebuilt = ingestChunk(senderShort, text)
        if not rebuilt then return end
        text = rebuilt
    end
    dispatchMessage(text, senderShort, sender)
end)


-- =============================================================
-- Logout cleanup
-- =============================================================
local cleanupFrame = CreateFrame("Frame")
cleanupFrame:RegisterEvent("PLAYER_LOGOUT")
cleanupFrame:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_LOGOUT" and session.state ~= "idle" then
        pcall(RPCoOp.EndSession)
    end
end)
