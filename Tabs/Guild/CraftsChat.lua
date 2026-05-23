-- =============================================================
-- L3FTools - Tabs/Guild/CraftsChat.lua
-- =============================================================
-- In-guild-chat features for the Crafts directory:
--   * Responder: anyone typing "!gc <recipe>" or "!l3f <recipe>" in
--     guild chat gets a reply listing crafters for that recipe.
--     Only the elected DR responds (deduplicates across guild
--     L3FTools users). Cap at 3 lines.
--   * Post-to-guild: callable from the Crafts UI to share a recipe's
--     crafter list to guild chat. 30s sender cooldown.
-- =============================================================

local addonName, L3F = ...

L3F.CraftsChat = L3F.CraftsChat or {}
local Chat = L3F.CraftsChat
local Crafts = L3F.Crafts
local Comms = L3F.CraftsComms

local TRIGGERS = { "!gc%s+(.+)", "!l3f%s+(.+)" }
local MAX_LINES = 3
local MAX_NAMES_PER_LINE = 5
local POST_COOLDOWN = 30
local RESPONDER_DELAY = 0.5  -- DR small delay so the asker sees their own message first

local lastPostAt = 0


-- =============================================================
-- Format helpers
-- =============================================================
local function shortName(s) return Ambiguate(s or "", "short") end

local function formatCrafterList(crafters)
    -- Returns up to MAX_LINES strings, each up to MAX_NAMES_PER_LINE
    -- names, online crafters first. crafters is sorted by online,
    -- then alpha (per Crafts.GetCraftersFor).
    local lines = {}
    local n = #crafters
    if n == 0 then return lines end
    local total = math.min(n, MAX_LINES * MAX_NAMES_PER_LINE)
    local i = 1
    while i <= total do
        local parts = {}
        for j = i, math.min(i + MAX_NAMES_PER_LINE - 1, total) do
            local c = crafters[j]
            local tag = c.online and "" or " (offline)"
            table.insert(parts, c.short .. tag)
        end
        table.insert(lines, table.concat(parts, ", "))
        i = i + MAX_NAMES_PER_LINE
    end
    if n > total then
        lines[#lines] = lines[#lines] .. string.format(" (+%d more)", n - total)
    end
    return lines
end


-- =============================================================
-- Recipe-name -> matching spell ID(s)
-- =============================================================
local function findRecipeMatches(query)
    if not query or query == "" then return {} end
    local q = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if q == "" then return {} end
    -- Use Crafts.SearchByName which already walks all known recipes
    -- across all guildies. Returns array of {spellID, name, profName, crafters}.
    return Crafts.SearchByName(q)
end


-- =============================================================
-- Responder
-- =============================================================
local function respondToGuildQuery(asker, recipeQuery)
    if not Comms or not Comms.IsDR or not Comms.IsDR() then return end
    if not IsInGuild() then return end

    local matches = findRecipeMatches(recipeQuery)
    if #matches == 0 then
        SendChatMessage(
            string.format("L3F Crafts: no guildie knows '%s'.", recipeQuery),
            "GUILD")
        return
    end

    -- If multiple recipes match, prefer one with crafters, then
    -- alphabetical. (SearchByName already returns alphabetical.)
    local pick
    for _, m in ipairs(matches) do
        if m.crafters and #m.crafters > 0 then pick = m; break end
    end
    pick = pick or matches[1]

    if not pick.crafters or #pick.crafters == 0 then
        SendChatMessage(
            string.format("L3F Crafts: '%s' known but no current crafter.", pick.name),
            "GUILD")
        return
    end

    SendChatMessage(
        string.format("L3F Crafts - %s (%s):", pick.name, pick.profName),
        "GUILD")
    for _, line in ipairs(formatCrafterList(pick.crafters)) do
        SendChatMessage("  " .. line, "GUILD")
    end
end

local function tryMatchTrigger(text)
    if not text then return nil end
    for _, pat in ipairs(TRIGGERS) do
        local q = text:match(pat)
        if q then return q end
    end
    return nil
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_GUILD")
listener:SetScript("OnEvent", function(_, _, msg, sender)
    local settings = Crafts.GetSettings()
    if not settings.chatResponderEnabled then return end
    local q = tryMatchTrigger(msg or "")
    if not q then return end
    local askerShort = shortName(sender)
    -- Defer slightly so the player's own message lands first in chat.
    C_Timer.After(RESPONDER_DELAY, function()
        respondToGuildQuery(askerShort, q)
    end)
end)


-- =============================================================
-- Post-to-guild (called from the UI)
-- =============================================================
function Chat.PostRecipeToGuild(spellID)
    if not IsInGuild() then
        print("|cffffd100L3F Crafts:|r not in a guild.")
        return
    end
    local now = GetTime()
    if (now - lastPostAt) < POST_COOLDOWN then
        local left = math.ceil(POST_COOLDOWN - (now - lastPostAt))
        print(string.format("|cffffd100L3F Crafts:|r post cooldown: %ds.", left))
        return
    end
    local name = Crafts.GetRecipeName(spellID)
    local crafters = Crafts.GetCraftersFor(spellID)
    if not crafters or #crafters == 0 then
        SendChatMessage(
            string.format("L3F Crafts - %s: no known crafter.", name),
            "GUILD")
    else
        SendChatMessage(
            string.format("L3F Crafts - %s:", name),
            "GUILD")
        for _, line in ipairs(formatCrafterList(crafters)) do
            SendChatMessage("  " .. line, "GUILD")
        end
    end
    lastPostAt = now
end

function Chat.GetPostCooldownRemaining()
    local now = GetTime()
    local left = POST_COOLDOWN - (now - lastPostAt)
    if left < 0 then return 0 end
    return math.ceil(left)
end
