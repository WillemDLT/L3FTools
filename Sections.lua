-- =============================================================
-- L3FTools - Sections.lua
-- =============================================================
-- Wing-aware marking (Phases 2-4).
--   * Sections/<Raid>.lua files call L3F:RegisterSections{...}.
--   * On PLAYER_ENTERING_WORLD the current instance is detected by
--     its instanceMapID; if a Sections file matches, that raid's
--     wings become active.
--   * In a mapped raid the automarker only marks mobs in the
--     ACTIVE wing and uses that wing's per-wing mark priorities.
--   * In any unmapped raid / open world the automarker behaves
--     exactly as before (no scoping) - the feature is additive.
--   * A movable on-screen switcher steps wings with prev / next.
--   * The active wing per raid is remembered for 6 hours.
-- =============================================================

local addonName, L3F = ...

local MEMORY_SECONDS = 6 * 60 * 60


-- =============================================================
-- 1. SECTION REGISTRY  (Sections/<Raid>.lua -> L3F:RegisterSections)
-- =============================================================
L3F.sectionData = {}     -- mapID -> def

function L3F:RegisterSections(def)
    if type(def) ~= "table" or not def.mapID or not def.sections then return end
    for _, section in ipairs(def.sections) do
        section.npcSet = {}
        for _, npc in ipairs(section.npcs or {}) do
            section.npcSet[npc.id] = true
        end
    end
    L3F.sectionData[def.mapID] = def
end


-- =============================================================
-- 2. ACTIVE WING STATE
-- =============================================================
L3F.activeRaidSections = nil
L3F.activeSectionIndex = 1

local function sectionDB()
    L3F.db.sections          = L3F.db.sections or {}
    L3F.db.sections.progress = L3F.db.sections.progress or {}
    L3F.db.sections.marks    = L3F.db.sections.marks or {}
    return L3F.db.sections
end

local function activeSection()
    local def = L3F.activeRaidSections
    if not def then return nil end
    return def.sections[L3F.activeSectionIndex]
end
L3F.GetActiveSection = activeSection

-- True when not in a mapped raid, so the engine falls back cleanly.
function L3F.NpcInActiveSection(npcID)
    local sec = activeSection()
    if not sec then return true end
    return sec.npcSet[npcID] == true
end

-- Find a raid's section def by its display name (used by the config UI).
function L3F.GetRaidSections(raidName)
    for _, def in pairs(L3F.sectionData) do
        if def.raid == raidName then return def end
    end
    return nil
end


-- =============================================================
-- 3. PER-WING MARK PRIORITY
-- =============================================================
-- Overrides: db.sections.marks[mapID][sectionIndex][npcID] = { ... }
local function sectionMarkStore(create)
    local def = L3F.activeRaidSections
    if not def then return nil end
    local sdb = sectionDB()
    local byMap = sdb.marks[def.mapID]
    if not byMap then
        if not create then return nil end
        byMap = {}; sdb.marks[def.mapID] = byMap
    end
    local bySec = byMap[L3F.activeSectionIndex]
    if not bySec then
        if not create then return nil end
        bySec = {}; byMap[L3F.activeSectionIndex] = bySec
    end
    return bySec
end

-- Section-aware replacement for L3F.effectivePriority (defined in Core.lua):
-- active-wing override first, then the global override, then registry default.
L3F.effectivePriority = function(npc)
    if not L3F.db then return npc.marks end
    local store = sectionMarkStore(false)
    if store and store[npc.id] then return store[npc.id] end
    return L3F.db.automarker.markPriorities[npc.id] or npc.marks
end

-- Explicit-wing getter/setter for the config UI, which shows every wing
-- of a raid at once and therefore must address wings directly. With no
-- mapID/wingIdx these fall back to the global (non-wing) mark store.
function L3F.GetWingPriority(npc, mapID, wingIdx)
    if L3F.db and mapID and wingIdx then
        local sm = L3F.db.sections and L3F.db.sections.marks
        local bySec = sm and sm[mapID] and sm[mapID][wingIdx]
        if bySec and bySec[npc.id] then return bySec[npc.id] end
    end
    if not L3F.db then return npc.marks end
    return L3F.db.automarker.markPriorities[npc.id] or npc.marks
end

function L3F.SetWingPriority(npcID, list, mapID, wingIdx)
    if mapID and wingIdx then
        local sdb = sectionDB()
        sdb.marks[mapID] = sdb.marks[mapID] or {}
        sdb.marks[mapID][wingIdx] = sdb.marks[mapID][wingIdx] or {}
        sdb.marks[mapID][wingIdx][npcID] = list
    else
        L3F.db.automarker.markPriorities[npcID] = list
    end
end


-- =============================================================
-- 4. THE WING SWITCHER  (movable on-screen prev / next)
-- =============================================================
local switcher

local function buildSwitcher()
    if switcher then return switcher end

    local f = CreateFrame("Frame", "L3FToolsSwitcher", UIParent, "BackdropTemplate")
    f:SetSize(280, 40)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        sectionDB().switcher = { x = self:GetLeft(), y = self:GetBottom() }
    end)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
    end

    local sw = sectionDB().switcher
    if sw and sw.x and sw.y then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", sw.x, sw.y)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end

    local prev = CreateFrame("Button", nil, f)
    prev:SetSize(26, 26)
    prev:SetPoint("LEFT", f, "LEFT", 8, 0)
    prev:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prev:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prev:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    prev:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    prev:SetScript("OnClick", function() L3F.SwitchSection(-1) end)

    local nextb = CreateFrame("Button", nil, f)
    nextb:SetSize(26, 26)
    nextb:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    nextb:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextb:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextb:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
    nextb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    nextb:SetScript("OnClick", function() L3F.SwitchSection(1) end)

    local raidText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    raidText:SetPoint("TOP", f, "TOP", 0, -6)
    raidText:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    raidText:SetPoint("RIGHT", nextb, "LEFT", -2, 0)
    raidText:SetJustifyH("CENTER")
    raidText:SetWordWrap(false)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOM", f, "BOTTOM", 0, 7)
    label:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    label:SetPoint("RIGHT", nextb, "LEFT", -2, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetTextColor(1, 0.82, 0)

    f.prev, f.next, f.label, f.raidText = prev, nextb, label, raidText
    f:Hide()
    switcher = f
    return f
end

function L3F.UpdateSwitcher()
    if not L3F.db then return end
    local f = buildSwitcher()
    local def = L3F.activeRaidSections
    if not def then f:Hide(); return end
    local sec = def.sections[L3F.activeSectionIndex]
    f.raidText:SetText(def.raid or "")
    f.label:SetText((sec and sec.name) or "?")
    if L3F.activeSectionIndex <= 1 then f.prev:Disable() else f.prev:Enable() end
    if L3F.activeSectionIndex >= #def.sections then f.next:Disable() else f.next:Enable() end
    f:Show()
end

function L3F.SwitchSection(delta)
    local def = L3F.activeRaidSections
    if not def then return end
    local n = #def.sections
    local i = L3F.activeSectionIndex + delta
    if i < 1 then i = 1 elseif i > n then i = n end
    L3F.activeSectionIndex = i
    sectionDB().progress[def.mapID] = { index = i, t = time() }
    L3F.UpdateSwitcher()
end

function L3F.ToggleSwitcher()
    if not L3F.activeRaidSections then
        print("|cffffd100L3FTools|r The wing switcher only works inside a mapped raid.")
        return
    end
    local f = buildSwitcher()
    if f:IsShown() then f:Hide() else L3F.UpdateSwitcher() end
end


-- =============================================================
-- 5. INSTANCE DETECTION
-- =============================================================
local function refreshInstance()
    if not L3F.db then return end
    local _, _, _, _, _, _, _, mapID = GetInstanceInfo()
    L3F.activeRaidSections = mapID and L3F.sectionData[mapID] or nil

    local def = L3F.activeRaidSections
    if def then
        local prog = sectionDB().progress[def.mapID]
        if prog and prog.index and prog.t and (time() - prog.t) < MEMORY_SECONDS then
            L3F.activeSectionIndex = math.min(math.max(prog.index, 1), #def.sections)
        else
            L3F.activeSectionIndex = 1
        end
    else
        L3F.activeSectionIndex = 1
    end
    L3F.UpdateSwitcher()
end
L3F.RefreshInstanceSections = refreshInstance

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function() refreshInstance() end)
