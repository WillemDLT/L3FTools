-- =============================================================
-- L3FTools - GuildMap/Broadcast.lua
-- =============================================================
-- Position broadcast + receive over the GUILD addon channel.
--
-- Wire format (CSV, single packet, well under the 255-byte limit):
--   name,level,class,x,y,mapID,hp%
-- e.g.  "Willem,70,WARLOCK,0.412,0.587,84,98"
--
-- Send conditions (all must hold):
--   * L3FToolsDB.guildMap.shareWithGuild == true
--   * IsInGuild()
--   * not (pauseInInstance is on AND we are inside a raid instance or BG)
--     - Morphéours: pause inside BGs too; teammates are stacked anyway and
--       BG positions leak useful intel to whoever runs L3FTools cross-faction
--   * we have moved more than MOVE_THRESHOLD since the last send
--     OR MAX_INTERVAL seconds have elapsed (heartbeat)
--
-- Receive:
--   * incoming "L3FMap" packets on GUILD update L3F.GuildMap.roster[short]
--   * GUILD_ROSTER_UPDATE removes entries for guildies who went offline
--   * a periodic TTL sweep removes entries whose lastSeen is > TTL old
--     (catches "guildie disabled the toggle" silently)
--
-- No pins or UI yet - that's chunk 4. Verify in-game with /l3f gm dump.
-- =============================================================

local addonName, L3F = ...

local GM = L3F.GuildMap
GM.roster = GM.roster or {}
local roster = GM.roster

local PREFIX         = "L3FMap"
local TICK_INTERVAL  = 2.0        -- check broadcast eligibility this often
local MAX_INTERVAL   = 5.0        -- always send at least this often when eligible
local MOVE_THRESHOLD = 0.01       -- 1% of map width/height
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

local function shouldBroadcast()
    if not L3FToolsDB or not L3FToolsDB.guildMap then return false end
    local gm = L3FToolsDB.guildMap
    if not gm.shareWithGuild then return false end
    if not IsInGuild() then return false end
    if gm.pauseInInstance and inSuppressedInstance() then return false end
    return true
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
    C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
    lastX, lastY, lastMap = x, y, mapID
    return true
end

local function tick()
    if not shouldBroadcast() then return end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y = pos and pos:GetXY()
    if not x then return end

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

local function ingest(senderShort, name, level, class, x, y, mapID, hp)
    local nx = tonumber(x) or 0
    local ny = tonumber(y) or 0
    if nx < 0 or nx > 1 then nx = 0 end
    if ny < 0 or ny > 1 then ny = 0 end
    roster[senderShort] = {
        name     = name or senderShort,
        level    = tonumber(level) or 0,
        class    = (type(class) == "string") and class:upper() or "UNKNOWN",
        x        = nx,
        y        = ny,
        mapID    = tonumber(mapID) or 0,
        hp       = tonumber(hp) or 100,
        lastSeen = GetTime(),
        source   = "guild",
    }
    if GM.OnRosterUpdated then GM.OnRosterUpdated(senderShort) end
end

local recvFrame = CreateFrame("Frame")
recvFrame:RegisterEvent("CHAT_MSG_ADDON")
recvFrame:SetScript("OnEvent", function(self, event, prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if channel ~= "GUILD" then return end
    if isSelf(sender) then return end
    if not text then return end
    local name, level, class, x, y, mapID, hp = strsplit(",", text)
    if not name then return end
    local short = Ambiguate(sender, "short")
    ingest(short, name, level, class, x, y, mapID, hp)
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
