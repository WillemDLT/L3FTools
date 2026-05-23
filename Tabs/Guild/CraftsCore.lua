-- =============================================================
-- L3FTools - Tabs/Guild/CraftsCore.lua
-- =============================================================
-- Data model + member DB + RecipeDB + public API for the Crafts
-- guild-directory feature. Ported from the GuildCrafts addon
-- (https://www.curseforge.com/wow/addons/guildcrafts), adapted to
-- L3FTools's bare-Ace conventions and existing Professions registry.
--
-- Storage shape:
--   L3FToolsDB.guildCrafts[guildKey] = {
--     members = {
--       [memberShort] = {
--         professions = {
--           [profName] = {              -- canonical English ("Alchemy", ...)
--             recipes  = { [spellID] = true, ... },
--             spec     = "Potion Master" or nil,
--             skillRank = 375,
--             skillMax  = 375,
--             lastScan = unixTime,
--           },
--         },
--         classFile = "WARRIOR",
--         level     = 70,
--         lastUpdate = unixTime,
--       },
--     },
--     dataFormat = 1,
--   }
--   L3FToolsCharDB.guildCraftsFavorites = { [spellID] = true, ... }
--   L3FToolsDB.guildCraftsSettings = { ... }
--
-- guildKey = realmName .. ":" .. guildName so a player who's been in
-- multiple guilds (or on multiple realms) gets isolated caches per
-- guild. No cross-guild data leakage.
-- =============================================================

local addonName, L3F = ...

L3F.Crafts = L3F.Crafts or {}
local Crafts = L3F.Crafts

Crafts.DATA_FORMAT = 1

-- Canonical English profession names. The scraper / UI all key off
-- these. L3FTools is English-only (Morpheours plays in English) so
-- we don't need GuildCrafts's spell-ID-based locale normalization.
Crafts.PROFESSIONS = {
    "Alchemy", "Blacksmithing", "Enchanting", "Engineering",
    "Jewelcrafting", "Leatherworking", "Tailoring",
    "Cooking", "First Aid", "Fishing",
}
Crafts.PROFESSION_SET = {}
for _, p in ipairs(Crafts.PROFESSIONS) do Crafts.PROFESSION_SET[p] = true end

-- Default settings.
local DEFAULTS = {
    showStaleness        = true,
    stalenessWarnDays    = 30,
    stalenessPruneDays   = 45,  -- still-in-guild stale cap
    exMemberPruneDays    = 7,   -- left-the-guild cap
    chatResponderEnabled = true,
    tooltipEnabled       = true,
    postCooldownSeconds  = 30,
}


-- =============================================================
-- Helpers
-- =============================================================
local function shortName(s)
    return Ambiguate(s or "", "short")
end

local function selfShort()
    return UnitName("player") or "?"
end

local function selfClass()
    local _, c = UnitClass("player")
    return c or "UNKNOWN"
end

local function selfLevel()
    return UnitLevel("player") or 0
end

local function now()
    return time and time() or 0
end

local function guildName()
    if not IsInGuild() then return nil end
    local n = GetGuildInfo and GetGuildInfo("player")
    return n
end

local function realmName()
    return (GetRealmName and GetRealmName()) or "?"
end

function Crafts.GetGuildKey()
    local g = guildName()
    if not g then return nil end
    return realmName() .. ":" .. g
end


-- =============================================================
-- DB bootstrap
-- =============================================================
local function db()
    L3FToolsDB = L3FToolsDB or {}
    L3FToolsDB.guildCrafts = L3FToolsDB.guildCrafts or {}
    L3FToolsDB.guildCraftsSettings = L3FToolsDB.guildCraftsSettings or {}
    -- Layer defaults onto missing keys.
    for k, v in pairs(DEFAULTS) do
        if L3FToolsDB.guildCraftsSettings[k] == nil then
            L3FToolsDB.guildCraftsSettings[k] = v
        end
    end
    return L3FToolsDB.guildCrafts, L3FToolsDB.guildCraftsSettings
end

local function charDB()
    L3FToolsCharDB = L3FToolsCharDB or {}
    L3FToolsCharDB.guildCraftsFavorites = L3FToolsCharDB.guildCraftsFavorites or {}
    return L3FToolsCharDB
end

function Crafts.GetSettings()
    local _, s = db()
    return s
end

function Crafts.SetSetting(k, v)
    local _, s = db()
    s[k] = v
end

-- Returns the guild's member-keyed table, or nil if we're not in a
-- guild. Auto-bootstraps the slot.
local function guildTable()
    local key = Crafts.GetGuildKey()
    if not key then return nil end
    local all = db()
    all[key] = all[key] or { members = {}, dataFormat = Crafts.DATA_FORMAT }
    return all[key], key
end

function Crafts.GetMember(short)
    local gt = guildTable()
    if not gt then return nil end
    return gt.members[short]
end

function Crafts.GetAllMembers()
    local gt = guildTable()
    if not gt then return {} end
    return gt.members
end


-- =============================================================
-- Online + roster cache (refreshed by external GUILD_ROSTER_UPDATE)
-- =============================================================
local onlineCache = {}

function Crafts.RefreshOnlineCache()
    wipe(onlineCache)
    if not IsInGuild() then return end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = shortName(name)
            onlineCache[short] = {
                online    = online and true or false,
                level     = level or 0,
                classFile = classFile or "UNKNOWN",
            }
        end
    end
end

function Crafts.IsOnline(short)
    local e = onlineCache[short]
    return e and e.online
end

function Crafts.GetRosterInfo(short)
    return onlineCache[short]
end


-- =============================================================
-- Write own data (called by the scraper after a TradeSkill scan)
-- =============================================================
function Crafts.SetMyProfession(profName, recipes, spec, skillRank, skillMax)
    if not Crafts.PROFESSION_SET[profName] then return end
    local gt = guildTable()
    if not gt then return end
    local me = selfShort()
    gt.members[me] = gt.members[me] or {
        professions = {},
        classFile = selfClass(),
        level = selfLevel(),
        lastUpdate = now(),
    }
    local m = gt.members[me]
    m.classFile = selfClass()
    m.level = selfLevel()
    m.professions = m.professions or {}
    m.professions[profName] = {
        recipes   = recipes or {},
        spec      = spec,
        skillRank = skillRank or 0,
        skillMax  = skillMax or 0,
        lastScan  = now(),
    }
    m.lastUpdate = now()
    Crafts.FireDataChanged("self", me)
end

function Crafts.SetMemberData(short, classFile, level, profName, profData, lastUpdate)
    -- Called by the comms layer when a delta or snapshot arrives.
    if not Crafts.PROFESSION_SET[profName] then return end
    local gt = guildTable()
    if not gt then return end
    gt.members[short] = gt.members[short] or {
        professions = {},
        classFile = classFile or "UNKNOWN",
        level = level or 0,
        lastUpdate = lastUpdate or now(),
    }
    local m = gt.members[short]
    if classFile then m.classFile = classFile end
    if level and level > 0 then m.level = level end
    m.professions = m.professions or {}
    m.professions[profName] = profData
    m.lastUpdate = lastUpdate or now()
    Crafts.FireDataChanged("remote", short)
end

function Crafts.RemoveMemberProfession(short, profName)
    local gt = guildTable()
    if not gt then return end
    local m = gt.members[short]
    if m and m.professions then m.professions[profName] = nil end
    Crafts.FireDataChanged("remote", short)
end

function Crafts.RemoveMember(short)
    local gt = guildTable()
    if not gt then return end
    gt.members[short] = nil
    Crafts.FireDataChanged("prune", short)
end


-- =============================================================
-- Queries
-- =============================================================
function Crafts.GetMyData()
    return Crafts.GetMember(selfShort())
end

function Crafts.GetCraftersFor(spellID)
    -- Returns array of { short, profName, online } for every member who
    -- knows this spell ID. Online crafters listed first, then alpha.
    local out = {}
    local gt = guildTable()
    if not gt then return out end
    for short, m in pairs(gt.members) do
        if m.professions then
            for profName, pd in pairs(m.professions) do
                if pd.recipes and pd.recipes[spellID] then
                    table.insert(out, {
                        short = short,
                        profName = profName,
                        online = Crafts.IsOnline(short) or false,
                    })
                    break  -- one entry per crafter even if multiple profs know it
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.short < b.short
    end)
    return out
end

function Crafts.GetMembersByProfession(profName)
    -- Returns array of { short, profData, online, classFile, level }
    -- for every member who has this profession.
    local out = {}
    local gt = guildTable()
    if not gt then return out end
    for short, m in pairs(gt.members) do
        if m.professions and m.professions[profName] then
            table.insert(out, {
                short = short,
                profData = m.professions[profName],
                online = Crafts.IsOnline(short) or false,
                classFile = m.classFile or "UNKNOWN",
                level = m.level or 0,
            })
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.short < b.short
    end)
    return out
end

function Crafts.SearchByName(query)
    -- Returns array of { spellID, name, profName, crafters } across
    -- all professions and members. Uses the L3F.professionRecipeMap and
    -- L3F.RegisterBonusCategory("professions") tables for canonical
    -- recipe names. Substring (case-insensitive) match.
    local out = {}
    if not query or query == "" then return out end
    local q = query:lower()
    local seen = {}  -- dedup by spellID

    local gt = guildTable()
    if not gt then return out end

    -- Walk every known recipe across every member, grouped by spellID.
    -- Match by GetSpellInfo (cheaper than building a full name index).
    for short, m in pairs(gt.members) do
        if m.professions then
            for profName, pd in pairs(m.professions) do
                if pd.recipes then
                    for spellID in pairs(pd.recipes) do
                        if not seen[spellID] then
                            local name = GetSpellInfo and GetSpellInfo(spellID)
                            if name and name:lower():find(q, 1, true) then
                                seen[spellID] = true
                                table.insert(out, {
                                    spellID = spellID,
                                    name = name,
                                    profName = profName,
                                    crafters = Crafts.GetCraftersFor(spellID),
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end


-- =============================================================
-- Recipe-name -> spell-ID lookup (built lazily from L3F.bonusLookup
-- .professions, which RegisterBonusCategory populates at load).
-- The scraper uses this to convert TradeSkillFrame's recipe NAMES
-- (which is what GetTradeSkillInfo returns) to canonical spell IDs.
-- =============================================================
local nameToSpellByProf

local function buildNameLookup()
    nameToSpellByProf = {}
    local profCat = L3F.bonusLookup and L3F.bonusLookup.professions
    if not profCat then return end
    for _, profName in ipairs(Crafts.PROFESSIONS) do
        local entry = profCat[profName]
        if entry and entry.sections then
            nameToSpellByProf[profName] = nameToSpellByProf[profName] or {}
            for _, section in ipairs(entry.sections) do
                for _, item in ipairs(section.items or {}) do
                    if item.id and item.name then
                        nameToSpellByProf[profName][item.name] = item.id
                    end
                end
            end
        end
    end
end

function Crafts.LookupSpellByName(profName, recipeName)
    if not nameToSpellByProf then buildNameLookup() end
    local prof = nameToSpellByProf[profName]
    return prof and prof[recipeName] or nil
end

-- For UI display: get the localized recipe name for a stored spell ID.
-- Falls back to whatever the bonusLookup has cached, or "spell:<id>".
function Crafts.GetRecipeName(spellID)
    if not spellID then return "?" end
    local name = GetSpellInfo and GetSpellInfo(spellID)
    if name then return name end
    -- Fallback via bonusItemLookup (the registered "name" field).
    local entries = L3F.bonusItemLookup and L3F.bonusItemLookup[spellID]
    if entries and entries[1] and entries[1].name then
        return entries[1].name
    end
    return "spell:" .. spellID
end


-- =============================================================
-- Favorites (per-character)
-- =============================================================
function Crafts.IsFavorite(spellID)
    local cdb = charDB()
    return cdb.guildCraftsFavorites[spellID] == true
end

function Crafts.SetFavorite(spellID, on)
    local cdb = charDB()
    if on then
        cdb.guildCraftsFavorites[spellID] = true
    else
        cdb.guildCraftsFavorites[spellID] = nil
    end
    Crafts.FireDataChanged("favorite", spellID)
end


-- =============================================================
-- Staleness / pruning
-- =============================================================
function Crafts.AgeDays(member)
    if not member or not member.lastUpdate then return 999 end
    local diff = now() - member.lastUpdate
    return math.floor(diff / 86400)
end

function Crafts.IsStale(member)
    local s = Crafts.GetSettings()
    return Crafts.AgeDays(member) >= s.stalenessWarnDays
end

function Crafts.PruneStale()
    local gt = guildTable()
    if not gt then return 0 end
    local s = Crafts.GetSettings()
    local cutoffStill = now() - (s.stalenessPruneDays * 86400)
    local cutoffEx    = now() - (s.exMemberPruneDays * 86400)

    -- Build set of currently-in-guild members.
    local inGuild = {}
    if IsInGuild() then
        local n = GetNumGuildMembers() or 0
        for i = 1, n do
            local name = GetGuildRosterInfo(i)
            if name then inGuild[shortName(name)] = true end
        end
    end

    local pruned = 0
    for short, m in pairs(gt.members) do
        local cutoff = inGuild[short] and cutoffStill or cutoffEx
        if (m.lastUpdate or 0) < cutoff then
            gt.members[short] = nil
            pruned = pruned + 1
        end
    end
    if pruned > 0 then Crafts.FireDataChanged("prune") end
    return pruned
end


-- =============================================================
-- Serialization (used by the comms layer)
-- =============================================================
local function encProfession(profName, pd)
    -- profName|spec|rank|max|lastScan|spell1,spell2,...
    local spells = {}
    if pd.recipes then
        for spellID in pairs(pd.recipes) do
            table.insert(spells, spellID)
        end
    end
    table.sort(spells)
    return table.concat({
        profName,
        (pd.spec or ""):gsub("|", "/"),
        tostring(pd.skillRank or 0),
        tostring(pd.skillMax or 0),
        tostring(pd.lastScan or 0),
        table.concat(spells, ","),
    }, "|")
end

local function decProfession(blob)
    local profName, spec, rank, mx, lastScan, spells = strsplit("|", blob, 6)
    if not Crafts.PROFESSION_SET[profName] then return nil end
    local recipes = {}
    if spells and spells ~= "" then
        for s in string.gmatch(spells, "[^,]+") do
            local id = tonumber(s)
            if id then recipes[id] = true end
        end
    end
    return profName, {
        spec      = (spec and spec ~= "") and spec or nil,
        skillRank = tonumber(rank) or 0,
        skillMax  = tonumber(mx) or 0,
        lastScan  = tonumber(lastScan) or 0,
        recipes   = recipes,
    }
end

function Crafts.SerializeProfession(profName, pd)
    return encProfession(profName, pd)
end

function Crafts.DeserializeProfession(blob)
    return decProfession(blob)
end

-- Full-member serialization for sync/snapshot transport. Returns one
-- blob per profession plus a header. The comms layer chunks these
-- into wire-safe packets.
function Crafts.SerializeMember(short)
    local m = Crafts.GetMember(short)
    if not m then return nil end
    local profBlobs = {}
    if m.professions then
        for profName, pd in pairs(m.professions) do
            table.insert(profBlobs, encProfession(profName, pd))
        end
    end
    return {
        short      = short,
        classFile  = m.classFile or "UNKNOWN",
        level      = m.level or 0,
        lastUpdate = m.lastUpdate or now(),
        profBlobs  = profBlobs,
    }
end


-- =============================================================
-- Event surface (UI / comms subscribe)
-- =============================================================
local listeners = {}
function Crafts.OnDataChanged(fn)
    table.insert(listeners, fn)
end

function Crafts.FireDataChanged(kind, key)
    for _, fn in ipairs(listeners) do pcall(fn, kind, key) end
end


-- =============================================================
-- Bootstrap on load
-- =============================================================
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("GUILD_ROSTER_UPDATE")
boot:SetScript("OnEvent", function(_, ev)
    if ev == "PLAYER_ENTERING_WORLD" then
        db(); charDB()  -- bootstrap savedvars
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then
            GuildRoster()
        end
    elseif ev == "GUILD_ROSTER_UPDATE" then
        Crafts.RefreshOnlineCache()
        Crafts.FireDataChanged("roster")
    end
end)

-- Periodic stale-prune sweep (every 10 minutes, well below cutoff
-- thresholds). Also kicks the roster cache so online state stays
-- fresh for the UI.
C_Timer.NewTicker(600, function()
    Crafts.PruneStale()
end)
C_Timer.NewTicker(10, function()
    Crafts.RefreshOnlineCache()
end)
