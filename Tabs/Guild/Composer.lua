-- =============================================================
-- L3FTools - Tabs/Guild/Composer.lua
-- =============================================================
-- TBC Classic Raid Comp Planner. Personal mode: client-side comp
-- with multiple named profiles, plus an L3F2 export/import string.
-- 27 specs (9 classes x 3) drag-drop or click-add into up to 9
-- groups of 5 slots + a Bench. Live buff/debuff coverage panel.
-- =============================================================

local addonName, L3F = ...

-- =============================================================
-- 1. SPEC + BUFF/DEBUFF DATA
-- =============================================================
-- Icon paths follow the in-client texture root. Where the literal
-- "Interface\\Icons\\<name>" doesn't resolve to a recognisable
-- texture, the row will render as the default question-mark glyph
-- and a beta-tester correction is the path forward (one entry per
-- spec is easy to swap). Buffs/debuffs are the canonical
-- raid-tracking strings - the bottom coverage panel keys off them.
local SPECS = {
    -- =============== DRUID ===============
    { key = "balance", class = "Druid", spec = "Balance",
      label = "Balance Druid",
      icon = "Interface\\Icons\\Spell_Nature_StarFall",
      buffs   = { "Mark of the Wild", "Improved Mark of the Wild", "Innervate", "Moonkin Form" },
      debuffs = { "Faerie Fire", "Improved Faerie Fire", "Insect Swarm" },
      partyAuras = {
          { name = "Moonkin Aura", icon = "Interface\\Icons\\Spell_Nature_ForceOfNature" },
      } },
    { key = "feral", class = "Druid", spec = "Feral",
      label = "Feral Druid",
      icon = "Interface\\Icons\\Ability_Druid_CatForm",
      buffs   = { "Mark of the Wild", "Innervate", "Leader of the Pack" },
      debuffs = { "Faerie Fire", "Mangle" },
      partyAuras = {
          { name = "Leader of the Pack", icon = "Interface\\Icons\\Spell_Nature_UnyeildingStamina" },
      } },
    { key = "restodruid", class = "Druid", spec = "Restoration",
      label = "Restoration Druid",
      icon = "Interface\\Icons\\Spell_Nature_Healingtouch",
      buffs   = { "Mark of the Wild", "Improved Mark of the Wild", "Innervate", "Tree of Life" },
      debuffs = { "Faerie Fire" },
      partyAuras = {
          { name = "Tree of Life", icon = "Interface\\Icons\\Ability_Druid_TreeofLife" },
      } },

    -- =============== HUNTER ===============
    { key = "bm", class = "Hunter", spec = "Beast Mastery",
      label = "Beast Mastery Hunter",
      icon = "Interface\\Icons\\Ability_Hunter_BeastTaming",
      buffs   = { "Ferocious Inspiration" },
      debuffs = { "Scorpid Sting" },
      partyAuras = {
          { name = "Ferocious Inspiration", icon = "Interface\\Icons\\Ability_Hunter_FerociousInspiration" },
      } },
    { key = "mm", class = "Hunter", spec = "Marksmanship",
      label = "Marksmanship Hunter",
      icon = "Interface\\Icons\\Ability_Marksmanship",
      buffs   = { "Trueshot Aura" },
      debuffs = { "Scorpid Sting" },
      partyAuras = {
          { name = "Trueshot Aura", icon = "Interface\\Icons\\Ability_TrueShot" },
      } },
    { key = "sv", class = "Hunter", spec = "Survival",
      label = "Survival Hunter",
      icon = "Interface\\Icons\\Ability_Hunter_SwiftStrike",
      buffs   = {},
      debuffs = { "Scorpid Sting", "Expose Weakness" },
      partyAuras = {} },

    -- =============== MAGE ===============
    { key = "arcanemage", class = "Mage", spec = "Arcane",
      label = "Arcane Mage",
      icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
      buffs   = { "Arcane Intellect" },
      debuffs = {},
      partyAuras = {} },
    { key = "firemage", class = "Mage", spec = "Fire",
      label = "Fire Mage",
      icon = "Interface\\Icons\\Spell_Fire_FireBolt02",
      buffs   = { "Arcane Intellect" },
      debuffs = { "Improved Scorch" },
      partyAuras = {} },
    { key = "frostmage", class = "Mage", spec = "Frost",
      label = "Frost Mage",
      icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
      buffs   = { "Arcane Intellect" },
      debuffs = { "Winter's Chill" },
      partyAuras = {} },

    -- =============== PALADIN ===============
    { key = "holypala", class = "Paladin", spec = "Holy",
      label = "Holy Paladin",
      icon = "Interface\\Icons\\Spell_Holy_HolyBolt",
      buffs   = { "Blessing of Kings", "Devotion Aura" },
      debuffs = {},
      partyAuras = {
          { name = "Devotion Aura", icon = "Interface\\Icons\\Spell_Holy_DevotionAura" },
      } },
    { key = "protpala", class = "Paladin", spec = "Protection",
      label = "Protection Paladin",
      icon = "Interface\\Icons\\Spell_Holy_DevotionAura",
      buffs   = { "Blessing of Kings", "Blessing of Sanctuary", "Devotion Aura" },
      debuffs = {},
      partyAuras = {
          { name = "Devotion Aura", icon = "Interface\\Icons\\Spell_Holy_DevotionAura" },
      } },
    { key = "retpala", class = "Paladin", spec = "Retribution",
      label = "Retribution Paladin",
      icon = "Interface\\Icons\\Spell_Holy_AuraOfLight",
      buffs   = { "Blessing of Kings", "Sanctity Aura" },
      debuffs = { "Improved Seal of the Crusader" },
      partyAuras = {
          { name = "Sanctity Aura", icon = "Interface\\Icons\\Spell_Holy_MindVision" },
      } },

    -- =============== PRIEST ===============
    { key = "discpriest", class = "Priest", spec = "Discipline",
      label = "Discipline Priest",
      icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
      buffs   = { "Pain Suppression", "Power Word: Fortitude", "Shadow Protection", "Divine Spirit" },
      debuffs = {},
      partyAuras = {} },
    { key = "holypriest", class = "Priest", spec = "Holy",
      label = "Holy Priest",
      icon = "Interface\\Icons\\Spell_Holy_GuardianSpirit",
      buffs   = { "Power Word: Fortitude", "Shadow Protection", "Divine Spirit" },
      debuffs = {},
      partyAuras = {} },
    { key = "shadowpriest", class = "Priest", spec = "Shadow",
      label = "Shadow Priest",
      icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
      buffs   = { "Power Word: Fortitude", "Shadow Protection" },
      debuffs = { "Shadow Weaving" },
      partyAuras = {
          { name = "Vampiric Touch", icon = "Interface\\Icons\\Spell_Holy_Stoicism" },
      } },

    -- =============== ROGUE ===============
    { key = "assrogue", class = "Rogue", spec = "Assassination",
      label = "Assassination Rogue",
      icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
      buffs   = {},
      debuffs = {},
      partyAuras = {} },
    { key = "combatrogue", class = "Rogue", spec = "Combat",
      label = "Combat Rogue",
      icon = "Interface\\Icons\\Ability_BackStab",
      buffs   = {},
      debuffs = { "Improved Expose Armor" },
      partyAuras = {} },
    { key = "subrogue", class = "Rogue", spec = "Subtlety",
      label = "Subtlety Rogue",
      icon = "Interface\\Icons\\Ability_Stealth",
      buffs   = {},
      debuffs = { "Hemorrhage" },
      partyAuras = {} },

    -- =============== SHAMAN ===============
    { key = "elesham", class = "Shaman", spec = "Elemental",
      label = "Elemental Shaman",
      icon = "Interface\\Icons\\Spell_Nature_Lightning",
      buffs   = { "Bloodlust", "Totem of Wrath" },
      debuffs = {},
      partyAuras = {
          { name = "Totem of Wrath", icon = "Interface\\Icons\\Spell_Fire_TotemOfWrath" },
          { name = "Wrath of Air Totem", icon = "Interface\\Icons\\Spell_Nature_SlowingTotem" },
      } },
    { key = "enhsham", class = "Shaman", spec = "Enhancement",
      label = "Enhancement Shaman",
      icon = "Interface\\Icons\\Spell_Nature_LightningShield",
      buffs   = { "Bloodlust", "Unleashed Rage" },
      debuffs = {},
      partyAuras = {
          { name = "Strength of Earth Totem", icon = "Interface\\Icons\\Spell_Nature_EarthBindTotem" },
          { name = "Windfury Totem", icon = "Interface\\Icons\\Spell_Nature_Cyclone" },
      } },
    { key = "restosham", class = "Shaman", spec = "Restoration",
      label = "Restoration Shaman",
      icon = "Interface\\Icons\\Spell_Nature_MagicImmunity",
      buffs   = { "Bloodlust", "Earth Shield", "Mana Tide Totem" },
      debuffs = {},
      partyAuras = {
          { name = "Mana Tide Totem", icon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental" },
          { name = "Mana Spring Totem", icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem" },
      } },

    -- =============== WARLOCK ===============
    { key = "afflock", class = "Warlock", spec = "Affliction",
      label = "Affliction Warlock",
      icon = "Interface\\Icons\\Spell_Shadow_DeathCoil",
      buffs   = { "Improved Imp" },
      debuffs = { "Improved Shadow Bolt", "Malediction" },
      partyAuras = {
          { name = "Blood Pact", icon = "Interface\\Icons\\Spell_Shadow_BloodBoil" },
      } },
    { key = "demolock", class = "Warlock", spec = "Demonology",
      label = "Demonology Warlock",
      icon = "Interface\\Icons\\Spell_Shadow_Metamorphosis",
      buffs   = { "Improved Healthstone" },
      debuffs = { "Improved Shadow Bolt" },
      partyAuras = {} },
    { key = "destrolock", class = "Warlock", spec = "Destruction",
      label = "Destruction Warlock",
      icon = "Interface\\Icons\\Spell_Shadow_RainOfFire",
      buffs   = { "Improved Healthstone" },
      debuffs = { "Improved Shadow Bolt" },
      partyAuras = {} },

    -- =============== WARRIOR ===============
    { key = "armswar", class = "Warrior", spec = "Arms",
      label = "Arms Warrior",
      icon = "Interface\\Icons\\Ability_Warrior_SavageBlow",
      buffs   = { "Battle Shout" },
      debuffs = { "Blood Frenzy", "Improved Demoralizing Shout", "Improved Thunder Clap" },
      partyAuras = {} },
    { key = "furywar", class = "Warrior", spec = "Fury",
      label = "Fury Warrior",
      icon = "Interface\\Icons\\Ability_Warrior_InnerRage",
      buffs   = { "Battle Shout" },
      debuffs = { "Improved Demoralizing Shout", "Improved Thunder Clap" },
      partyAuras = {} },
    { key = "protwar", class = "Warrior", spec = "Protection",
      label = "Protection Warrior",
      icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
      buffs   = { "Commanding Shout" },
      debuffs = { "Improved Demoralizing Shout", "Improved Thunder Clap" },
      partyAuras = {} },
}

-- Class display order in the palette: 5 classes in row 1, 4 in row 2.
local CLASS_ORDER = {
    "Druid", "Hunter", "Mage", "Paladin", "Priest",
    "Rogue", "Shaman", "Warlock", "Warrior",
}

-- Master raid-wide buff list (alphabetical) for the coverage panel.
local BUFFS_LIST = {
    "Arcane Intellect", "Battle Shout",
    "Blessing of Kings", "Blessing of Sanctuary",
    "Bloodlust", "Commanding Shout",
    "Devotion Aura", "Divine Spirit",
    "Earth Shield", "Ferocious Inspiration",
    "Improved Healthstone", "Improved Imp",
    "Improved Mark of the Wild", "Innervate",
    "Leader of the Pack", "Mana Tide Totem",
    "Mark of the Wild", "Moonkin Form",
    "Pain Suppression", "Power Word: Fortitude",
    "Sanctity Aura", "Shadow Protection",
    "Totem of Wrath", "Tree of Life",
    "Trueshot Aura", "Unleashed Rage",
}

local DEBUFFS_LIST = {
    "Blood Frenzy", "Expose Weakness",
    "Faerie Fire", "Hemorrhage",
    "Improved Demoralizing Shout", "Improved Expose Armor",
    "Improved Faerie Fire", "Improved Scorch",
    "Improved Seal of the Crusader", "Improved Shadow Bolt",
    "Improved Thunder Clap", "Insect Swarm",
    "Malediction", "Mangle",
    "Scorpid Sting", "Shadow Weaving",
    "Winter's Chill",
}

-- TBC max-rank spell IDs used by the buff/debuff tooltip on hover.
-- GameTooltip:SetSpellByID resolves these to the canonical, localized
-- in-game tooltip (rank, mana, range, cast time, description). Any ID
-- that doesn't resolve falls back to a plain-text tooltip with just
-- the name - easy per-entry correction when a beta tester flags one.
local SPELL_IDS = {
    -- Buffs
    ["Arcane Intellect"]              = 27126,
    ["Battle Shout"]                  = 25289,
    ["Blessing of Kings"]             = 20217,
    ["Blessing of Sanctuary"]         = 27168,
    ["Bloodlust"]                     =  2825,
    ["Commanding Shout"]              = 25289,  -- TBC Anniversary may map to a distinct spell ID
    ["Devotion Aura"]                 = 27149,
    ["Divine Spirit"]                 = 25312,
    ["Earth Shield"]                  = 32594,
    ["Ferocious Inspiration"]         = 34460,
    ["Improved Healthstone"]          = 18692,
    ["Improved Imp"]                  = 18696,
    ["Improved Mark of the Wild"]     = 17051,
    ["Innervate"]                     = 29166,
    ["Leader of the Pack"]            = 24932,
    ["Mana Tide Totem"]               = 16191,
    ["Mark of the Wild"]              = 26990,
    ["Moonkin Form"]                  = 24858,
    ["Pain Suppression"]              = 33206,
    ["Power Word: Fortitude"]         = 25389,
    ["Sanctity Aura"]                 = 31870,
    ["Shadow Protection"]             = 25433,
    ["Totem of Wrath"]                = 30706,
    ["Tree of Life"]                  = 33891,
    ["Trueshot Aura"]                 = 27066,
    ["Unleashed Rage"]                = 30802,
    -- Debuffs
    ["Blood Frenzy"]                  = 29859,
    ["Expose Weakness"]               = 34503,
    ["Faerie Fire"]                   = 26993,
    ["Hemorrhage"]                    = 16511,
    ["Improved Demoralizing Shout"]   = 12879,
    ["Improved Expose Armor"]         = 14169,
    ["Improved Faerie Fire"]          = 33602,
    ["Improved Scorch"]               = 22959,
    ["Improved Seal of the Crusader"] = 20335,
    ["Improved Shadow Bolt"]          = 17800,
    ["Improved Thunder Clap"]         = 12666,
    ["Insect Swarm"]                  = 27013,
    ["Malediction"]                   = 32379,
    ["Mangle"]                        = 33878,
    ["Scorpid Sting"]                 =  3043,
    ["Shadow Weaving"]                = 15334,
    ["Winter's Chill"]                = 28593,
}

local SPEC_LOOKUP = {}
for _, s in ipairs(SPECS) do SPEC_LOOKUP[s.key] = s end


-- =============================================================
-- 2. PROFILE STATE
-- =============================================================
local function newEmptyProfile()
    local p = { groups = {}, groupCount = 3 }
    for g = 1, 9 do
        local slots = {}
        for i = 1, 5 do slots[i] = nil end
        p.groups[g] = { name = "Group " .. g, slots = slots }
    end
    return p
end

local function ensureComposerState()
    L3F.db.composer = L3F.db.composer or {}
    if not L3F.db.composer.profiles or not next(L3F.db.composer.profiles) then
        L3F.db.composer.profiles = { ["Default"] = newEmptyProfile() }
        L3F.db.composer.activeProfile = "Default"
    end
    if not L3F.db.composer.activeProfile
       or not L3F.db.composer.profiles[L3F.db.composer.activeProfile] then
        L3F.db.composer.activeProfile =
            (next(L3F.db.composer.profiles)) or "Default"
        L3F.db.composer.profiles[L3F.db.composer.activeProfile] =
            L3F.db.composer.profiles[L3F.db.composer.activeProfile] or newEmptyProfile()
    end
    local p = L3F.db.composer.profiles[L3F.db.composer.activeProfile]
    p.groupCount = math.max(1, math.min(9, p.groupCount or 3))
    p.groups = p.groups or {}
    for g = 1, 9 do
        p.groups[g] = p.groups[g] or { name = "Group " .. g, slots = {} }
        for i = 1, 5 do p.groups[g].slots[i] = p.groups[g].slots[i] or nil end
    end
    -- 0.15.1: bench removed; silently strip from any pre-existing profile
    -- so SavedVariables don't accumulate dead fields.
    p.bench = nil
end

local function currentProfile()
    ensureComposerState()
    return L3F.db.composer.profiles[L3F.db.composer.activeProfile]
end


-- =============================================================
-- 3. BUFF/DEBUFF COVERAGE
-- =============================================================
local function computeCoverage()
    local covered = { buffs = {}, debuffs = {} }
    local groupAuras = {}
    local p = currentProfile()
    for g = 1, p.groupCount do
        groupAuras[g] = {}
        local seenAura = {}
        for _, slot in pairs(p.groups[g].slots) do
            if slot and slot.specKey then
                local s = SPEC_LOOKUP[slot.specKey]
                if s then
                    for _, b in ipairs(s.buffs or {})   do covered.buffs[b]   = true end
                    for _, d in ipairs(s.debuffs or {}) do covered.debuffs[d] = true end
                    for _, a in ipairs(s.partyAuras or {}) do
                        if not seenAura[a.name] then
                            seenAura[a.name] = true
                            table.insert(groupAuras[g], a)
                        end
                    end
                end
            end
        end
    end
    return covered, groupAuras
end


-- =============================================================
-- 4. PROFILE EXPORT / IMPORT
-- =============================================================
local LibDeflate = LibStub and LibStub("LibDeflate", true)

-- Wire format: COMP1|NAME|GC|G1S1,..,G1S5|G2..|...|G9..|GN1//GN2//...//GN9
-- (the bench row + bench name from 0.15.0 are gone in 0.15.1; the
-- decoder still tolerates strings that include them by silently
-- discarding those fields).
local function serializeProfile(name, profile)
    local function encodeSlot(slot)
        if not slot or not slot.specKey then return "" end
        local label = (slot.label or ""):gsub("|", "/"):gsub(",", " ")
        return slot.specKey .. ":" .. label
    end
    local parts = { name:gsub("|", "/"), tostring(profile.groupCount or 3) }
    for g = 1, 9 do
        local row = {}
        for i = 1, 5 do row[i] = encodeSlot(profile.groups[g] and profile.groups[g].slots[i]) end
        table.insert(parts, table.concat(row, ","))
    end
    local nameRow = {}
    for g = 1, 9 do nameRow[g] = (profile.groups[g].name or ("Group " .. g)):gsub("|", "/") end
    table.insert(parts, table.concat(nameRow, "//"))

    local inner = "COMP1|" .. table.concat(parts, "|")
    if LibDeflate then
        local compressed = LibDeflate:CompressDeflate(inner)
        return "L3F2C:" .. LibDeflate:EncodeForPrint(compressed)
    end
    return "L3F1C:" .. inner
end

local function deserializeProfile(str)
    if type(str) ~= "string" then return nil, "Not a string" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    local inner
    if str:sub(1, 6) == "L3F2C:" then
        if not LibDeflate then return nil, "LibDeflate not loaded; cannot decode" end
        local encoded = str:sub(7)
        local compressed = LibDeflate:DecodeForPrint(encoded)
        if not compressed then return nil, "Decode failed (corrupted string?)" end
        inner = LibDeflate:DecompressDeflate(compressed)
        if not inner then return nil, "Decompress failed (corrupted string?)" end
    elseif str:sub(1, 6) == "L3F1C:" then
        inner = str:sub(7)
    else
        return nil, "Invalid format (expected L3F1C: or L3F2C:)"
    end
    if not inner:match("^COMP1|") then return nil, "Not a Composer profile string" end
    inner = inner:sub(7)
    local parts = {}
    for piece in (inner .. "|"):gmatch("([^|]*)|") do table.insert(parts, piece) end
    if #parts < 11 then return nil, "Truncated profile string" end
    local p = newEmptyProfile()
    local function decodeRow(row, into)
        local i = 0
        for slotStr in (row .. ","):gmatch("([^,]*),") do
            i = i + 1
            if i > 5 then break end
            if slotStr ~= "" then
                local key, label = slotStr:match("^([^:]+):(.*)$")
                if key and SPEC_LOOKUP[key] then
                    into[i] = { specKey = key, label = label ~= "" and label or SPEC_LOOKUP[key].label }
                end
            end
        end
    end
    p.groupCount = math.max(1, math.min(9, tonumber(parts[2]) or 3))
    for g = 1, 9 do decodeRow(parts[2 + g], p.groups[g].slots) end
    -- 0.15.0 strings have a bench row at parts[12] and bench name at
    -- parts[14]. The group-names row was at parts[13] there, here at
    -- parts[12]. Try the new position first, fall back to the legacy
    -- one if the new position holds something that looks like a slot
    -- (legacy bench row).
    local nameRow
    if parts[12] and parts[12]:find("//") then
        nameRow = parts[12]
    elseif parts[13] and parts[13]:find("//") then
        nameRow = parts[13]
    end
    if nameRow and nameRow ~= "" then
        local g = 0
        for nm in (nameRow .. "//"):gmatch("([^/][^/]*)//") do
            g = g + 1
            if g > 9 then break end
            p.groups[g].name = nm
        end
    end
    return parts[1] or "Imported", p
end


-- =============================================================
-- 5. UI
-- =============================================================
local composerRoot
local refresh
local dragSpecKey

-- Cursor-follower icon for drag visuals. WoW's built-in drag system
-- only paints the cursor for system payloads (spells, items); for
-- custom payloads like our spec keys we attach a small textured
-- frame and reposition it every frame while a drag is active.
local follower = CreateFrame("Frame", "L3FComposerDragFollower", UIParent)
follower:SetSize(28, 28)
follower:SetFrameStrata("TOOLTIP")
follower:Hide()
local followerTex = follower:CreateTexture(nil, "OVERLAY")
followerTex:SetAllPoints()
followerTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
follower:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local s = self:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
end)

local function setSlot(target, idx, specKey)
    local s = SPEC_LOOKUP[specKey]
    if not s then return end
    target.slots[idx] = { specKey = specKey, label = s.label }
end

local function clearSlot(target, idx) target.slots[idx] = nil end

local function firstEmptySlot(target)
    for i = 1, 5 do if not target.slots[i] then return i end end
    return nil
end

-- Walk the parent chain of `frame` looking for one that's tagged
-- with `composerSlot = { target, idx }`. Used by drag-drop drop
-- detection: GetMouseFocus returns the deepest frame under the
-- cursor (often the background texture's region or a child of the
-- slot row), so we hop upward until we find the actual slot row.
local function findSlotUnderFrame(frame)
    while frame do
        if frame.composerSlot then return frame.composerSlot end
        if frame.GetParent then
            frame = frame:GetParent()
        else
            return nil
        end
    end
    return nil
end

StaticPopupDialogs["L3FCOMPOSER_TEXT"] = {
    text = "",
    button1 = OKAY or "Okay",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self, data)
        self.editBox:SetText(data.preset or "")
        self.editBox:HighlightText()
        self.text:SetText(data.prompt or "Enter text:")
    end,
    OnAccept = function(self, data)
        local txt = self.editBox:GetText() or ""
        if data.onAccept then data.onAccept(txt) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local data = parent.data
        if data and data.onAccept then data.onAccept(self:GetText() or "") end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function promptText(prompt, preset, onAccept)
    StaticPopup_Show("L3FCOMPOSER_TEXT", nil, nil,
        { prompt = prompt, preset = preset, onAccept = onAccept })
end

StaticPopupDialogs["L3FCOMPOSER_EXPORT"] = {
    text = "Copy this string to share the profile:",
    button1 = CLOSE or "Close",
    hasEditBox = true,
    editBoxWidth = 280,
    maxLetters = 0,
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self, data)
        self.editBox:SetText(data.payload or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["L3FCOMPOSER_IMPORT"] = {
    text = "Paste a Composer profile string:",
    button1 = OKAY or "Okay",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    editBoxWidth = 280,
    maxLetters = 0,
    timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self) self.editBox:SetText(""); self.editBox:SetFocus() end,
    OnAccept = function(self)
        local str = self.editBox:GetText() or ""
        local name, profile = deserializeProfile(str)
        if not name then
            print("|cffffd100L3FComp|r import failed: " .. tostring(profile))
            return
        end
        local base, idx = name, 1
        while L3F.db.composer.profiles[name] do
            idx = idx + 1
            name = base .. " (" .. idx .. ")"
        end
        L3F.db.composer.profiles[name] = profile
        L3F.db.composer.activeProfile = name
        if refresh then refresh() end
        print("|cffffd100L3FComp|r imported profile '" .. name .. "'")
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local SLOT_W, SLOT_H = 178, 22
local GROUP_W = 200
local PALETTE_ICON = 26
local PALETTE_GAP = 4
local PALETTE_CLASS_GAP = 10

local function buildPaletteIcon(parent, spec, x, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(PALETTE_ICON, PALETTE_ICON)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(spec.icon)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn:SetNormalTexture(tex)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hl:SetBlendMode("ADD")

    -- Drag-and-drop: RegisterForDrag arms OnDragStart on mouse motion
    -- while the button is held. Click (no motion) still fires OnClick
    -- via RegisterForClicks. Do NOT call SetMovable - that interprets
    -- the drag as "move the icon frame" and swallows the start event.
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(spec.label)
        if #spec.buffs > 0 then
            GameTooltip:AddLine("Buffs: " .. table.concat(spec.buffs, ", "), 0.7, 0.9, 0.7, true)
        end
        if #spec.debuffs > 0 then
            GameTooltip:AddLine("Debuffs: " .. table.concat(spec.debuffs, ", "), 0.9, 0.7, 0.7, true)
        end
        GameTooltip:AddLine("Drag onto a slot or click to add.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnDragStart", function()
        dragSpecKey = spec.key
        followerTex:SetTexture(spec.icon)
        follower:Show()
    end)
    btn:SetScript("OnDragStop", function()
        -- OnDragStop fires on mouse release; resolve the drop target
        -- via GetMouseFocus (the frame the cursor is currently over)
        -- and walk up to find a slot row tagged composerSlot.
        if dragSpecKey then
            local focus = GetMouseFocus and GetMouseFocus() or nil
            local target = findSlotUnderFrame(focus)
            if target then
                setSlot(target.target, target.idx, dragSpecKey)
            end
            dragSpecKey = nil
            follower:Hide()
            refresh()
        else
            follower:Hide()
        end
    end)
    btn:SetScript("OnClick", function()
        -- Click-to-add convenience: drop into the first empty group
        -- slot. There is no bench fallback as of 0.15.1 - if every
        -- visible group is full, the player should add a group.
        local p = currentProfile()
        for g = 1, p.groupCount do
            local idx = firstEmptySlot(p.groups[g])
            if idx then setSlot(p.groups[g], idx, spec.key); refresh(); return end
        end
        print("|cffffd100L3FComp|r all groups full - add a group first.")
    end)
end

local function buildPalette(parent, x, y)
    local byClass = {}
    for _, s in ipairs(SPECS) do
        byClass[s.class] = byClass[s.class] or {}
        table.insert(byClass[s.class], s)
    end
    local rowBreak = 5
    local cursorX, cursorY = x, y
    for i, className in ipairs(CLASS_ORDER) do
        local specs = byClass[className] or {}
        for j, sp in ipairs(specs) do
            local dx = (j - 1) * (PALETTE_ICON + PALETTE_GAP)
            buildPaletteIcon(parent, sp, cursorX + dx, cursorY)
        end
        cursorX = cursorX + #specs * (PALETTE_ICON + PALETTE_GAP) + PALETTE_CLASS_GAP
        if i == rowBreak then
            cursorX = x
            cursorY = cursorY + PALETTE_ICON + PALETTE_GAP + 4
        end
    end
end

local function buildSlotRow(parent, target, idx, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(SLOT_W, SLOT_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -y)
    row:EnableMouse(true)
    -- Tag the row so OnDragStop on the palette icon can identify
    -- this drop target via GetMouseFocus + findSlotUnderFrame.
    row.composerSlot = { target = target, idx = idx }

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.18)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    lbl:SetPoint("RIGHT", row, "RIGHT", -36, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)

    local editBtn = CreateFrame("Button", nil, row)
    editBtn:SetSize(16, 16)
    editBtn:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    editBtn:SetNormalTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Title-Background")
    editBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local editLbl = editBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    editLbl:SetPoint("CENTER"); editLbl:SetText("E")

    local xBtn = CreateFrame("Button", nil, row)
    xBtn:SetSize(16, 16)
    xBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    xBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    xBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local slot = target.slots[idx]
    if slot then
        local s = SPEC_LOOKUP[slot.specKey]
        if s then
            icon:SetTexture(s.icon); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            lbl:SetText(slot.label or s.label)
            lbl:SetTextColor(1, 0.6, 0.1, 1)
        end
        editBtn:SetScript("OnClick", function()
            promptText("Rename slot:", slot.label or "", function(txt)
                if txt and txt ~= "" then slot.label = txt; refresh() end
            end)
        end)
        xBtn:SetScript("OnClick", function() clearSlot(target, idx); refresh() end)
    else
        icon:SetColorTexture(0.08, 0.08, 0.08, 1)
        lbl:SetText("")
        editBtn:Hide(); xBtn:Hide()
    end
end

local function buildGroupFrame(parent, target, x, y, idxLabel)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(GROUP_W, 220)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)

    local hdr = CreateFrame("Button", nil, f)
    hdr:SetSize(GROUP_W - 22, 18)
    hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    local hdrTxt = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hdrTxt:SetPoint("LEFT", hdr, "LEFT", 4, 0); hdrTxt:SetText(target.name or "Group")
    hdr:SetScript("OnClick", function()
        promptText("Rename group:", target.name or "", function(txt)
            if txt and txt ~= "" then target.name = txt; refresh() end
        end)
    end)

    if idxLabel and idxLabel >= 2 then
        local rm = CreateFrame("Button", nil, f)
        rm:SetSize(16, 16)
        rm:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -1)
        rm:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
        rm:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        rm:SetScript("OnClick", function()
            local p = currentProfile()
            for g = idxLabel, 8 do p.groups[g] = p.groups[g + 1] end
            p.groups[9] = { name = "Group 9", slots = { nil, nil, nil, nil, nil } }
            p.groupCount = math.max(1, p.groupCount - 1)
            refresh()
        end)
    end

    local yy = 22
    for i = 1, 5 do
        buildSlotRow(f, target, i, yy)
        yy = yy + SLOT_H + 2
    end

    local _, groupAurasMap = computeCoverage()
    local strip = CreateFrame("Frame", nil, f)
    strip:SetSize(GROUP_W - 4, 26)
    strip:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -(yy + 4))
    local stripBg = strip:CreateTexture(nil, "BACKGROUND")
    stripBg:SetAllPoints(); stripBg:SetColorTexture(0, 0, 0, 0.18)
    local auras = (idxLabel and groupAurasMap[idxLabel]) or {}
    if #auras == 0 then
        local txt = strip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        txt:SetPoint("LEFT", strip, "LEFT", 4, 0)
        txt:SetText("No active group buffs")
    else
        local ax = 4
        for _, a in ipairs(auras) do
            local ic = strip:CreateTexture(nil, "ARTWORK")
            ic:SetSize(22, 22)
            ic:SetPoint("LEFT", strip, "LEFT", ax, 0)
            ic:SetTexture(a.icon); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local ib = CreateFrame("Frame", nil, strip)
            ib:SetAllPoints(ic)
            ib:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(a.name)
                GameTooltip:Show()
            end)
            ib:SetScript("OnLeave", function() GameTooltip:Hide() end)
            ax = ax + 26
        end
    end
end

-- Single buff/debuff list row. Returns the row Button so the caller
-- can install hover scripts; the row itself owns its dot + text.
local function buildBuffRow(parent, name, covered, y, panelW)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(panelW - 8, 20)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -y)

    local dot = row:CreateTexture(nil, "OVERLAY")
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", row, "LEFT", 4, 0)
    if covered then
        dot:SetColorTexture(0.30, 0.85, 0.30, 1)
    else
        dot:SetColorTexture(0.40, 0.40, 0.40, 1)
    end

    local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("LEFT", row, "LEFT", 18, 0)
    txt:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    txt:SetJustifyH("LEFT")
    txt:SetWordWrap(false)
    txt:SetText(name)
    if covered then
        txt:SetTextColor(1, 1, 1, 1)
    else
        txt:SetTextColor(0.6, 0.6, 0.6, 1)
    end

    -- Hover tooltip: SetSpellByID with the TBC max-rank ID for the
    -- buff/debuff (the canonical in-game tooltip). For names without
    -- a mapped ID, fall back to a name-only tooltip.
    local spellID = SPELL_IDS[name]
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if spellID and GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(spellID)
        else
            GameTooltip:SetText(name)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Subtle row highlight on hover so the tooltip target is obvious.
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
end

-- Right-side sidebar: BUFFS section above DEBUFFS section, single
-- column, full panel width per row so long names (e.g. "Improved
-- Demoralizing Shout") don't truncate. Returns the total height
-- consumed so the caller can size the scroll body.
local function buildBuffPanel(parent, covered, x, y, panelW)
    local f = CreateFrame("Frame", nil, parent)
    -- Height is computed below; placeholder for now.
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)

    local function section(title, list, covSet, sectionY)
        local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -sectionY)
        hdr:SetText(title)
        local box = CreateFrame("Frame", nil, f)
        box:SetSize(panelW, #list * 22 + 8)
        box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(sectionY + 22))
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints(); boxBg:SetColorTexture(0, 0, 0, 0.18)
        local rowY = 4
        for _, name in ipairs(list) do
            buildBuffRow(box, name, covSet[name], rowY, panelW)
            rowY = rowY + 22
        end
        return sectionY + 22 + box:GetHeight() + 12
    end

    local afterBuffs   = section("Buffs",   BUFFS_LIST,   covered.buffs,   0)
    local afterDebuffs = section("Debuffs", DEBUFFS_LIST, covered.debuffs, afterBuffs)
    f:SetSize(panelW, afterDebuffs)
    return afterDebuffs
end


-- =============================================================
-- 6. TOP STRIP (profile + Share / Import / Reset)
-- =============================================================
local function buildTopStrip(parent)
    local profLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    profLabel:SetText("Profile:")

    local profDD = CreateFrame("Frame", "L3FComposerProfileDD", parent, "UIDropDownMenuTemplate")
    profDD:SetPoint("LEFT", profLabel, "RIGHT", -8, -4)
    UIDropDownMenu_SetWidth(profDD, 140)
    UIDropDownMenu_SetText(profDD, L3F.db.composer.activeProfile or "Default")
    UIDropDownMenu_Initialize(profDD, function(self, level)
        for name, _ in pairs(L3F.db.composer.profiles) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.checked = (name == L3F.db.composer.activeProfile)
            info.func = function()
                L3F.db.composer.activeProfile = name
                refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local function smallBtn(label, anchor, dx, onClick, tooltip)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(64, 22); b:SetText(label)
        b:SetPoint("LEFT", anchor, "RIGHT", dx, 0)
        b:SetScript("OnClick", onClick)
        if tooltip then
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(tooltip)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return b
    end

    local newBtn = smallBtn("New", profDD, -4, function()
        promptText("New profile name:", "", function(txt)
            if not txt or txt == "" then return end
            if L3F.db.composer.profiles[txt] then
                print("|cffffd100L3FComp|r a profile named '" .. txt .. "' already exists.")
                return
            end
            L3F.db.composer.profiles[txt] = newEmptyProfile()
            L3F.db.composer.activeProfile = txt
            refresh()
        end)
    end, "Create a new empty profile")

    local delBtn = smallBtn("Delete", newBtn, 0, function()
        local cur = L3F.db.composer.activeProfile
        if not cur then return end
        local count = 0
        for _ in pairs(L3F.db.composer.profiles) do count = count + 1 end
        if count <= 1 then
            print("|cffffd100L3FComp|r can't delete the last profile.")
            return
        end
        L3F.db.composer.profiles[cur] = nil
        L3F.db.composer.activeProfile = next(L3F.db.composer.profiles)
        refresh()
    end, "Delete the active profile")

    local renameBtn = smallBtn("Rename", delBtn, 0, function()
        local cur = L3F.db.composer.activeProfile
        if not cur then return end
        promptText("Rename profile:", cur, function(txt)
            if not txt or txt == "" or txt == cur then return end
            if L3F.db.composer.profiles[txt] then
                print("|cffffd100L3FComp|r '" .. txt .. "' already exists.")
                return
            end
            L3F.db.composer.profiles[txt] = L3F.db.composer.profiles[cur]
            L3F.db.composer.profiles[cur] = nil
            L3F.db.composer.activeProfile = txt
            refresh()
        end)
    end, "Rename the active profile")

    local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    resetBtn:SetSize(64, 22); resetBtn:SetText("Reset")
    resetBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, -16)
    resetBtn:SetScript("OnClick", function()
        local cur = L3F.db.composer.activeProfile
        if not cur then return end
        L3F.db.composer.profiles[cur] = newEmptyProfile()
        refresh()
    end)

    local importBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    importBtn:SetSize(64, 22); importBtn:SetText("Import")
    importBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
    importBtn:SetScript("OnClick", function() StaticPopup_Show("L3FCOMPOSER_IMPORT") end)

    local shareBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    shareBtn:SetSize(64, 22); shareBtn:SetText("Share")
    shareBtn:SetPoint("RIGHT", importBtn, "LEFT", -4, 0)
    shareBtn:SetScript("OnClick", function()
        local cur = L3F.db.composer.activeProfile
        local payload = serializeProfile(cur, L3F.db.composer.profiles[cur])
        StaticPopup_Show("L3FCOMPOSER_EXPORT", nil, nil, { payload = payload })
    end)
end


-- =============================================================
-- 7. MAIN BUILDER
-- =============================================================
local function buildComposer(parent)
    composerRoot = parent
    ensureComposerState()

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     parent, "TOPLEFT",      4, -4)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24, 4)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(900, 1200)
    scroll:SetScrollChild(body)

    refresh = function()
        ensureComposerState()
        for _, c in ipairs({body:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        for _, r in ipairs({body:GetRegions()}) do r:Hide(); r:ClearAllPoints()
            if r.SetText then r:SetText("") end
        end

        buildTopStrip(body)

        local palY = 46
        local palLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        palLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 16, -palY)
        palLabel:SetText("Specs (Drag & Drop or Click to Add)")
        buildPalette(body, 16, palY + 18)

        local p = currentProfile()
        local gridY = palY + 18 + (PALETTE_ICON + PALETTE_GAP) * 2 + 16
        local colGap = 12
        local rowH = 230
        local groupColumns = 3
        -- Place each visible group in a 3-column grid on the LEFT.
        -- Bench was removed in 0.15.1; the empty space to the right is
        -- now reserved for the buffs/debuffs sidebar.
        for g = 1, p.groupCount do
            local row = math.floor((g - 1) / groupColumns)
            local col = (g - 1) % groupColumns
            local cx = 16 + col * (GROUP_W + colGap)
            local cy = gridY + row * rowH
            buildGroupFrame(body, p.groups[g], cx, cy, g)
        end

        local rows = math.ceil(p.groupCount / groupColumns)
        local afterGridY = gridY + rows * rowH + 4
        if p.groupCount < 9 then
            local addBtn = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
            addBtn:SetSize(GROUP_W, 28); addBtn:SetText("+ Add Group")
            addBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 16, -afterGridY)
            addBtn:SetScript("OnClick", function()
                local pp = currentProfile()
                pp.groupCount = math.min(9, pp.groupCount + 1)
                refresh()
            end)
            afterGridY = afterGridY + 34
        end

        -- Right-side sidebar: buffs + debuffs sections stacked vertically.
        -- Starts at the same y as the groups, fills the empty space.
        local covered = computeCoverage()
        local sidebarX = 16 + groupColumns * (GROUP_W + colGap) + 4
        local sidebarW = 290
        local sidebarH = buildBuffPanel(body, covered, sidebarX, gridY, sidebarW)

        -- Scroll body height = tallest of (groups column) and (sidebar).
        local groupsBottom = afterGridY
        local sidebarBottom = gridY + sidebarH
        body:SetHeight(math.max(groupsBottom, sidebarBottom) + 24)
    end

    refresh()
end

L3F.RegisterTab("guild.composer", "Composer", nil, buildComposer, { parent = "guild" })
