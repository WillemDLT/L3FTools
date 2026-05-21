-- =============================================================
-- L3FTools - GuildMap/Broadcast.lua
-- =============================================================
-- Position broadcast + receive over two channels:
--   * GUILD   - one fan-out packet per send for every L3FTools guildie
--   * WHISPER - one targeted packet per online friend with L3FTools
--
-- Wire format (CSV, single packet, well under the 255-byte limit):
--   name,level,class,x,y,mapID,hp%
-- e.g.  "Willem,70,WARLOCK,0.412,0.587,84,98"
--
-- Send conditions (the master gate + each channel independently):
--   * not (pauseInInstance AND we are inside a raid instance or BG)
--     - Morphéours: pause inside BGs too; teammates are stacked anyway and
--       BG positions leak useful intel to whoever runs L3FTools cross-faction
--   * we have moved more than MOVE_THRESHOLD since the last send
--     OR MAX_INTERVAL seconds have elapsed (heartbeat)
-- Per-channel:
--   * GUILD: shareWithGuild AND IsInGuild()
--   * WHISPER: shareWithFriends AND at least one online friend
--
-- Receive:
--   * incoming GUILD packets -> roster entry source=guild
--   * incoming WHISPER packets -> roster entry source=friend (but never
--     downgrade an existing guild entry to friend - guild label wins so
--     the world-map ring color stays consistent)
--   * GUILD_ROSTER_UPDATE removes entries for guildies who went offline
--   * FRIENDLIST_UPDATE removes entries for friends who went offline
--     (same safeguards as the guild path - empty-cache + heartbeat grace)
--   * a periodic TTL sweep removes entries whose lastSeen is > TTL old
-- =============================================================

local addonName, L3F = ...

local GM = L3F.GuildMap
GM.roster = GM.roster or {}
local roster = GM.roster

local PREFIX         = "L3FMap"
local TICK_INTERVAL  = 1.0        -- check broadcast eligibility this often
local MAX_INTERVAL   = 3.0        -- always send at least this often when eligible
local MOVE_THRESHOLD = 0.005      -- 0.5% of map width/height (was 1%; pin lag was painful)
local TTL            = 30         -- drop roster entries unseen for this many seconds

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

-- =============================================================
-- Send side
-- =============================================================
local lastSentTime = 0
local lastX, lastY, lastMap = nil, nil, nil

local function inSuppressedInstance()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return false end
    return instanceType == "raid" or instanceType == "pvp"
end

-- Online friends from the local friend list. The list is the same one
-- C_FriendList.ShowFriends() refreshes; we just iterate it.
local function snapshotOnlineFriends()
    local set = {}
    if not C_FriendList then return set end
    local n = (C_FriendList.GetNumFriends and C_FriendList.GetNumFriends()) or 0
    for i = 1, n do
        local info = C_FriendList.GetFriendInfoByIndex
            and C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected and info.name then
            -- info.name on TBC Classic is "Player" (no realm on a single-
            -- realm friend list). Ambiguate is a no-op there but keeps us
            -- safe if the client ever hands us a fully-qualified name.
            set[Ambiguate(info.name, "short")] = info.name
        end
    end
    return set
end

local function requestFriendList()
    if C_FriendList and C_FriendList.ShowFriends then
        C_FriendList.ShowFriends()  -- in modern TBC client this just refreshes the cache
    end
end

local function guildChannelEligible(gm)
    return gm.shareWithGuild and IsInGuild()
end

local function friendChannelEligible(gm)
    if not gm.shareWithFriends then return false end
    return next(snapshotOnlineFriends()) ~= nil
end

local function shouldBroadcast()
    if not L3FToolsDB or not L3FToolsDB.guildMap then return false end
    local gm = L3FToolsDB.guildMap
    if gm.pauseInInstance and inSuppressedInstance() then return false end
    return guildChannelEligible(gm) or friendChannelEligible(gm)
end

local function sendNow()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return false end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return false end
    local x, y = pos:GetXY()
    if not x or not y then return false end

    local name  = UnitName("player") or "?"
    local level = UnitLevel("player") or 0
    local _, classFile = UnitClass("player")
    local class = classFile or "UNKNOWN"
    local hpMax = UnitHealthMax("player") or 0
    local hp    = (hpMax > 0) and math.floor(UnitHealth("player") / hpMax * 100) or 100

    local msg = string.format("%s,%d,%s,%.3f,%.3f,%d,%d",
        name, level, class, x, y, mapID, hp)

    local gm = L3FToolsDB.guildMap
    local sent = false
    if guildChannelEligible(gm) then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
        sent = true
    end
    if gm.shareWithFriends then
        for _, fullName in pairs(snapshotOnlineFriends()) do
            C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", fullName)
            sent = true
        end
    end

    if sent then
        lastX, lastY, lastMap = x, y, mapID
        return true
    end
    return false
end

local function tick()
    if not shouldBroadcast() then return end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    -- IMPORTANT: do NOT write `local x, y = pos and pos:GetXY()` — Lua's
    -- `and` doesn't propagate multi-value returns, so y silently becomes
    -- nil and the moved check on line below crashes whenever the player
    -- stops moving (the x-delta short-circuit no longer hides the bug).
    -- That crash was the root cause of "pin disappears when immobile":
    -- tick aborted before sendNow, heartbeats stopped, TTL dropped us
    -- from every receiver after 30s.
    local x, y = pos:GetXY()
    if not x or not y then return end

    local now = GetTime()
    local timeSince = now - lastSentTime
    local mapChanged = (mapID ~= lastMap)
    local moved = mapChanged
        or (lastX == nil)
        or math.abs(x - lastX) > MOVE_THRESHOLD
        or math.abs(y - lastY) > MOVE_THRESHOLD

    if moved or timeSince >= MAX_INTERVAL then
        if sendNow() then
            lastSentTime = now
        end
    end
end

C_Timer.NewTicker(TICK_INTERVAL, tick)


-- =============================================================
-- Receive side
-- =============================================================
local function isSelf(sender)
    local short = Ambiguate(sender or "", "short")
    return short == UnitName("player")
end

local function ingest(senderShort, name, level, class, x, y, mapID, hp, source)
    local nx = tonumber(x) or 0
    local ny = tonumber(y) or 0
    if nx < 0 or nx > 1 then nx = 0 end
    if ny < 0 or ny > 1 then ny = 0 end
    -- Never downgrade an existing guild entry to friend. If we already
    -- saw a GUILD packet from this player, keep them tagged as guild
    -- so the world-map ring color stays consistent across reloads.
    local existing = roster[senderShort]
    local effectiveSource = source
    if existing and existing.source == "guild" and source == "friend" then
        effectiveSource = "guild"
    end
    roster[senderShort] = {
        name     = name or senderShort,
        level    = tonumber(level) or 0,
        class    = (type(class) == "string") and class:upper() or "UNKNOWN",
        x        = nx,
        y        = ny,
        mapID    = tonumber(mapID) or 0,
        hp       = tonumber(hp) or 100,
        lastSeen = GetTime(),
        source   = effectiveSource,
    }
    if GM.OnRosterUpdated then GM.OnRosterUpdated(senderShort) end
end

local recvFrame = CreateFrame("Frame")
recvFrame:RegisterEvent("CHAT_MSG_ADDON")
recvFrame:SetScript("OnEvent", function(self, event, prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if isSelf(sender) then return end
    if not text then return end
    local source
    if channel == "GUILD" then
        source = "guild"
    elseif channel == "WHISPER" then
        source = "friend"
    else
        return
    end
    local name, level, class, x, y, mapID, hp = strsplit(",", text)
    if not name then return end
    local short = Ambiguate(sender, "short")
    ingest(short, name, level, class, x, y, mapID, hp, source)
end)


-- =============================================================
-- Guild roster cleanup: drop pins for anyone who went offline
-- =============================================================
local function snapshotOnlineGuildies()
    local set = {}
    if not IsInGuild() then return set end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online then
            set[Ambiguate(name, "short")] = true
        end
    end
    return set
end

local function requestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

-- The "online" set returned by GetGuildRosterInfo can be incomplete for a
-- moment right after GuildRoster() is called (the local cache is still
-- populating). Two safeguards before we remove someone:
--   1. If the online set is empty we treat it as untrustworthy and skip
--      the sweep entirely — no mass-removal on a transient empty snapshot.
--   2. We only remove an entry if we have NOT received a heartbeat from
--      that player in the last OFFLINE_GRACE seconds. A fresh heartbeat
--      trumps a stale "offline" report (this was the root cause of
--      Morphéours' "pin disappears after ~10s while standing still" bug:
--      the 10s GuildRoster ticker briefly reported an active broadcaster
--      as offline, deleting their entry until the next heartbeat).
local OFFLINE_GRACE = 15

local guildFrame = CreateFrame("Frame")
guildFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
guildFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
guildFrame:SetScript("OnEvent", function()
    local online = snapshotOnlineGuildies()
    if not next(online) then return end  -- safeguard 1: empty cache
    local now = GetTime()
    for short, entry in pairs(roster) do
        if entry.source == "guild"
           and not online[short]
           and now - (entry.lastSeen or 0) > OFFLINE_GRACE then  -- safeguard 2
            roster[short] = nil
            if GM.OnRosterRemoved then GM.OnRosterRemoved(short) end
        end
    end
end)

-- Kick the roster once at load, then refresh every 10s while in a guild.
requestRoster()
C_Timer.NewTicker(10, function()
    if IsInGuild() then requestRoster() end
end)


-- =============================================================
-- Friend list cleanup: drop pins for friends who went offline
-- =============================================================
-- Same two safeguards as the guild path: empty cache = skip the sweep,
-- and a recent heartbeat (< OFFLINE_GRACE seconds) trumps a "not online"
-- friend-list snapshot.
local friendFrame = CreateFrame("Frame")
friendFrame:RegisterEvent("FRIENDLIST_UPDATE")
friendFrame:SetScript("OnEvent", function()
    local gm = L3FToolsDB and L3FToolsDB.guildMap
    if not gm or not gm.shareWithFriends then return end
    local online = snapshotOnlineFriends()
    if not next(online) then return end
    local now = GetTime()
    for short, entry in pairs(roster) do
        if entry.source == "friend"
           and not online[short]
           and now - (entry.lastSeen or 0) > OFFLINE_GRACE then
            roster[short] = nil
            if GM.OnRosterRemoved then GM.OnRosterRemoved(short) end
        end
    end
end)

-- Kick the friend list once at load and periodically afterwards so the
-- send-side snapshot is fresh.
requestFriendList()
C_Timer.NewTicker(15, function()
    local gm = L3FToolsDB and L3FToolsDB.guildMap
    if gm and gm.shareWithFriends then requestFriendList() end
end)


-- =============================================================
-- TTL sweep: drop entries we have not seen in TTL seconds
-- =============================================================
C_Timer.NewTicker(5, function()
    local now = GetTime()
    for short, entry in pairs(roster) do
        if now - (entry.lastSeen or 0) > TTL then
            roster[short] = nil
            if GM.OnRosterRemoved then GM.OnRosterRemoved(short) end
        end
    end
end)


-- =============================================================
-- Public surface
-- =============================================================
function GM.GetRoster()
    return roster
end

-- Force-send right now (debugging aid; ignores throttling but still respects
-- shouldBroadcast guards). Returns true on success, false if we were blocked.
function GM.BroadcastNow()
    if not shouldBroadcast() then return false end
    if sendNow() then
        lastSentTime = GetTime()
        return true
    end
    return false
end

-- Expose for the Map tab: kicks the friend list cache. Useful right after
-- the user enables shareWithFriends so we don't wait up to 15s for the
-- next ticker before the first WHISPER fan-out.
GM.RequestFriendList = requestFriendList

-- Expose the online-guildie snapshot for the Map-tab roster panel. The
-- panel needs to render guildies who are online but NOT broadcasting
-- (i.e. they don't run L3FTools) as greyed entries so the user can see
-- who to nag. Includes level + classFile so the panel can keep the same
-- visual format used for actual broadcasters.
function GM.GetOnlineGuildies()
    local list = {}
    if not IsInGuild() then return list end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name and online then
            local short = Ambiguate(name, "short")
            list[short] = {
                name  = short,
                level = level or 0,
                class = classFile or "UNKNOWN",
            }
        end
    end
    return list
end

-- Console dump of the current roster, useful while there is no Map tab UI.
function GM.DumpRoster()
    local n = 0
    for short, e in pairs(roster) do
        n = n + 1
        print(string.format(
            "|cffffd100L3FMap|r %s  L%d %s  map=%d  (%.2f, %.2f)  hp=%d%%  age=%.1fs",
            short, e.level, e.class, e.mapID, e.x, e.y, e.hp,
            GetTime() - (e.lastSeen or 0)))
    end
    if n == 0 then print("|cffffd100L3FMap|r roster is empty.") end
end
