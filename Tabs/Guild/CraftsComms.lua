-- =============================================================
-- L3FTools - Tabs/Guild/CraftsComms.lua
-- =============================================================
-- Guild-channel comms for the Crafts directory. Ported from
-- GuildCrafts's DR/BDR + sync protocol, adapted to L3FTools's bare
-- (no AceComm) wire and our LibDeflate.
--
-- Message types (prefix L3F_CRFT, channel GUILD):
--   HI                  -- "I'm online with L3FTools Crafts vN"
--   HB                  -- DR heartbeat, every 60s
--   SREQ                -- "send me your full snapshot"
--   PDLT|<deflated>     -- profession delta for ONE (member, prof)
--   PDLTC|id|seq|tot|.. -- chunked variant when PDLT exceeds 240 bytes
--
-- DR election: alphabetical short-name of any addon-user heartbeat-
-- present in the last 180s. The DR is the only node that:
--   * Sends HB every 60s
--   * Responds to incoming SREQ with a full PDLT burst
--   * (Future) Responds first to `!gc <recipe>` in guild chat
-- Everyone broadcasts their own PDLT on local scrape regardless of DR.
--
-- SyncPausePolicy: HB + SREQ skipped while in a raid/BG instance to
-- keep chat throttling clean during combat. Self deltas (PDLT) still
-- send -- those are user-initiated profession opens, rare in combat.
-- =============================================================

local addonName, L3F = ...

L3F.CraftsComms = L3F.CraftsComms or {}
local Comms = L3F.CraftsComms
local Crafts = L3F.Crafts

local PREFIX = "L3F_CRFT"
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local PROTOCOL_VERSION = 1
local HEARTBEAT_INTERVAL = 60     -- DR sends every 60s
local PEER_TTL           = 180    -- evict peers after this without HB / HI
local HELLO_INTERVAL     = 300    -- re-announce HI every 5 min
local SREQ_DEBOUNCE      = 30     -- per-DR sync request cooldown
local CHUNK_PAYLOAD_BYTES = 200   -- safe chunk size under the 255 cap

local LibDeflate = LibStub and LibStub("LibDeflate", true)

-- =============================================================
-- State
-- =============================================================
-- Known L3FTools-running peers in our guild. Updated on HI / HB.
local peers = {}        -- [short] = { lastSeen, isDR }
local currentDR         -- short name or nil
local lastDRChange = 0  -- GetTime() of the last DR transition
local lastHelloAt = 0
local lastHeartbeatAt = 0
local lastSReqAt = {}   -- [drShort] = GetTime()
local sessionStart = GetTime()

-- Reassembly buffers for chunked deltas.
-- pendingChunks[sender][chunkId] = { received = N, total = M, parts = { [seq]=str } }
local pendingChunks = {}

local function shortName(s) return Ambiguate(s or "", "short") end
local function selfShort() return UnitName("player") or "?" end


-- =============================================================
-- SyncPausePolicy: suppress comms in raid/BG instances
-- =============================================================
local function inSuppressedInstance()
    if not IsInInstance then return false end
    local inI, t = IsInInstance()
    if not inI then return false end
    return t == "raid" or t == "pvp"
end


-- =============================================================
-- DR election (alphabetical of currently-seen peers + self)
-- =============================================================
local function electDR()
    local best = selfShort()
    local now = GetTime()
    for short, info in pairs(peers) do
        if (now - (info.lastSeen or 0)) <= PEER_TTL then
            if short < best then best = short end
        end
    end
    if best ~= currentDR then
        currentDR = best
        lastDRChange = now
    end
    return currentDR
end

function Comms.GetDR() return currentDR end
function Comms.IsDR() return currentDR == selfShort() end
function Comms.GetPeers()
    local out = {}
    for k, v in pairs(peers) do out[k] = v end
    return out
end


-- =============================================================
-- Wire layer
-- =============================================================
local function sendAddon(channel, target, msg, priority)
    priority = priority or "BULK"
    local CTL = _G.ChatThrottleLib
    if CTL and CTL.SendAddonMessage then
        CTL:SendAddonMessage(priority, PREFIX, msg, channel, target)
    else
        C_ChatInfo.SendAddonMessage(PREFIX, msg, channel, target)
    end
end

local function sendGuild(msg, priority)
    if not IsInGuild() then return end
    sendAddon("GUILD", nil, msg, priority)
end


-- =============================================================
-- Chunking
-- =============================================================
local chunkIdCounter = 0
local function nextChunkId()
    chunkIdCounter = chunkIdCounter + 1
    if chunkIdCounter > 999999 then chunkIdCounter = 1 end
    return chunkIdCounter
end

local function sendChunked(payload, msgType)
    -- msgType is the SINGLE-message kind (e.g. "PDLT"). When chunked
    -- we send "<msgType>C|id|seq|total|chunk".
    if #payload <= CHUNK_PAYLOAD_BYTES then
        sendGuild(msgType .. "|" .. payload, "BULK")
        return
    end
    local id = nextChunkId()
    local total = math.ceil(#payload / CHUNK_PAYLOAD_BYTES)
    for seq = 1, total do
        local start = (seq - 1) * CHUNK_PAYLOAD_BYTES + 1
        local stop  = math.min(seq * CHUNK_PAYLOAD_BYTES, #payload)
        local chunk = payload:sub(start, stop)
        sendGuild(string.format("%sC|%d|%d|%d|%s",
            msgType, id, seq, total, chunk), "BULK")
    end
end

local function tryReassemble(sender, msgType, body)
    -- body is "id|seq|total|chunk". Returns full payload when
    -- complete, or nil while still accumulating.
    local id, seq, total, chunk = strsplit("|", body, 4)
    id = tonumber(id); seq = tonumber(seq); total = tonumber(total)
    if not (id and seq and total and chunk) then return nil end
    pendingChunks[sender] = pendingChunks[sender] or {}
    local key = msgType .. ":" .. id
    local rec = pendingChunks[sender][key] or {
        received = 0, total = total, parts = {},
    }
    if not rec.parts[seq] then
        rec.parts[seq] = chunk
        rec.received = rec.received + 1
    end
    pendingChunks[sender][key] = rec
    if rec.received >= rec.total then
        pendingChunks[sender][key] = nil
        local parts = {}
        for i = 1, rec.total do parts[i] = rec.parts[i] end
        return table.concat(parts)
    end
    return nil
end


-- =============================================================
-- Delta serialization (one packet per profession)
-- =============================================================
local function encodeMemberProfession(short, profName, pd)
    -- Wire body shape (pre-compression):
    --   v1|short|classFile|level|lastUpdate|<profession-blob>
    local m = Crafts.GetMember(short)
    local classFile = m and m.classFile or "UNKNOWN"
    local level     = m and m.level or 0
    local lastUpd   = m and m.lastUpdate or 0
    local profBlob  = Crafts.SerializeProfession(profName, pd)
    local body = string.format("v1|%s|%s|%d|%d|%s",
        short, classFile, level, lastUpd, profBlob)
    if LibDeflate then
        local compressed = LibDeflate:CompressDeflate(body)
        return LibDeflate:EncodeForPrint(compressed)
    end
    return body
end

local function decodeMemberProfession(payload)
    local body
    if LibDeflate then
        local raw = LibDeflate:DecodeForPrint(payload)
        if raw then body = LibDeflate:DecompressDeflate(raw) end
    end
    if not body then body = payload end  -- fallback for uncompressed senders
    if not body or body:sub(1, 3) ~= "v1|" then return nil end
    body = body:sub(4)
    local short, classFile, level, lastUpd, profBlob =
        strsplit("|", body, 5)
    if not (short and profBlob) then return nil end
    local profName, pd = Crafts.DeserializeProfession(profBlob)
    if not profName then return nil end
    return short, classFile, tonumber(level) or 0,
        tonumber(lastUpd) or 0, profName, pd
end


-- =============================================================
-- Send paths
-- =============================================================
function Comms.SendHello()
    if not IsInGuild() then return end
    sendGuild(string.format("HI|%d", PROTOCOL_VERSION), "NORMAL")
    lastHelloAt = GetTime()
end

function Comms.SendHeartbeat()
    if not Comms.IsDR() then return end
    if inSuppressedInstance() then return end
    sendGuild(string.format("HB|%d", PROTOCOL_VERSION), "NORMAL")
    lastHeartbeatAt = GetTime()
end

function Comms.RequestSync()
    if not IsInGuild() then return end
    if inSuppressedInstance() then return end
    local dr = currentDR
    if not dr or dr == selfShort() then return end
    local now = GetTime()
    if (now - (lastSReqAt[dr] or 0)) < SREQ_DEBOUNCE then return end
    lastSReqAt[dr] = now
    sendGuild("SREQ|" .. selfShort(), "NORMAL")
end

-- Called by the scraper after a successful local profession scan.
function Comms.BroadcastSelfDelta(profName)
    if not IsInGuild() then return end
    local me = selfShort()
    local m = Crafts.GetMember(me)
    if not (m and m.professions and m.professions[profName]) then return end
    local payload = encodeMemberProfession(me, profName, m.professions[profName])
    sendChunked(payload, "PDLT")
end

-- DR responds to SREQ with one PDLT per (member, profession). Sent
-- with 0.5s gaps so we don't blow the chat throttle on a guild with
-- many crafters.
local function answerSyncRequest(requesterShort)
    if not Comms.IsDR() then return end
    if inSuppressedInstance() then return end
    local all = Crafts.GetAllMembers()
    local sends = {}
    for short, m in pairs(all) do
        if m.professions then
            for profName, pd in pairs(m.professions) do
                table.insert(sends, { short = short, profName = profName, pd = pd })
            end
        end
    end
    for i, item in ipairs(sends) do
        local payload = encodeMemberProfession(item.short, item.profName, item.pd)
        C_Timer.After((i - 1) * 0.5, function()
            sendChunked(payload, "PDLT")
        end)
    end
end


-- =============================================================
-- Receive layer
-- =============================================================
local function applyMemberProfessionPayload(payload)
    local short, classFile, level, lastUpd, profName, pd =
        decodeMemberProfession(payload)
    if not short then return end
    -- Don't overwrite our own data from echoes.
    if short == selfShort() then return end
    -- Last-write-wins by timestamp: if we already have newer data
    -- for this (member, profession), skip.
    local existing = Crafts.GetMember(short)
    if existing and existing.professions
       and existing.professions[profName]
       and (existing.professions[profName].lastScan or 0) > (pd.lastScan or 0) then
        return
    end
    Crafts.SetMemberData(short, classFile, level, profName, pd, lastUpd)
end

local function onHello(sender)
    peers[sender] = peers[sender] or {}
    peers[sender].lastSeen = GetTime()
    electDR()
end

local function onHeartbeat(sender)
    peers[sender] = peers[sender] or {}
    peers[sender].lastSeen = GetTime()
    peers[sender].isDR = true
    electDR()
end

local function onSReq(sender, requester)
    -- Anyone may send SREQ; only DR responds.
    onHello(sender)
    if Comms.IsDR() then
        answerSyncRequest(requester or sender)
    end
end

local function onPDLT(sender, payload)
    onHello(sender)
    applyMemberProfessionPayload(payload)
end

local function onPDLTC(sender, body)
    onHello(sender)
    local full = tryReassemble(sender, "PDLT", body)
    if full then applyMemberProfessionPayload(full) end
end

local recv = CreateFrame("Frame")
recv:RegisterEvent("CHAT_MSG_ADDON")
recv:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    if prefix ~= PREFIX or not text then return end
    if channel ~= "GUILD" then return end
    local senderShort = shortName(sender)
    if senderShort == selfShort() then return end
    local kind, body = text:match("^([^|]+)|?(.*)$")
    if not kind then return end
    if kind == "HI" then
        onHello(senderShort)
    elseif kind == "HB" then
        onHeartbeat(senderShort)
    elseif kind == "SREQ" then
        local requester = body and body:match("^([^|]*)") or senderShort
        onSReq(senderShort, requester ~= "" and requester or senderShort)
    elseif kind == "PDLT" then
        onPDLT(senderShort, body or "")
    elseif kind == "PDLTC" then
        onPDLTC(senderShort, body or "")
    end
end)


-- =============================================================
-- Periodic ticks
-- =============================================================
-- Heartbeat (DR only).
C_Timer.NewTicker(HEARTBEAT_INTERVAL, function()
    if Comms.IsDR() then Comms.SendHeartbeat() end
end)

-- Re-elect DR + evict stale peers.
C_Timer.NewTicker(30, function()
    local now = GetTime()
    for short, info in pairs(peers) do
        if (now - (info.lastSeen or 0)) > PEER_TTL then
            peers[short] = nil
        end
    end
    electDR()
end)

-- Re-announce HI periodically so new joiners pick us up.
C_Timer.NewTicker(HELLO_INTERVAL, function()
    if not inSuppressedInstance() then Comms.SendHello() end
end)


-- =============================================================
-- Bootstrap
-- =============================================================
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_GUILD_UPDATE")
boot:SetScript("OnEvent", function(_, ev)
    -- Short delay so the guild roster is populated before we
    -- broadcast/elect; also gives Crafts.RefreshOnlineCache a moment.
    C_Timer.After(3, function()
        Comms.SendHello()
        electDR()
        -- New install / fresh login: pull a snapshot from DR.
        C_Timer.After(5, function()
            if currentDR and currentDR ~= selfShort() then
                Comms.RequestSync()
            end
        end)
    end)
end)
