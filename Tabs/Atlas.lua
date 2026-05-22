-- =============================================================
-- L3FTools - Tabs/Atlas.lua
-- =============================================================
-- Three-pane Atlas: [Tree + search] | [NPC list] | [Detail].
--
-- Left pane:
--   * Search box at top - GLOBAL search across every raid + heroic.
--   * Collapsible tree: Categories ("Raids", "Heroic Dungeons") with
--     raids as children, wings as grandchildren under each raid.
--   * Wings stay collapsed by default so the tree shows a tidy
--     overview instead of spamming every wing at first sight.
--
-- Middle pane:
--   * Search non-empty -> flat list of matches across the whole atlas,
--     each row showing a small "Wing - Raid" location line.
--   * Wing selected     -> just that wing's NPCs (no header - the
--                          wing name is already in the tree).
--   * Raid selected     -> the raid's NPCs grouped by wing with headers.
--   * Heroic selected   -> the dungeon's NPCs.
--
-- Right pane: model + sub-tabs (Spells / Notes / Drops).
-- Drops sub-tab shows the item icon, name (coloured by quality) and chance,
-- with NORMAL/HEROIC sub-headers when a heroic-dungeon boss has both modes.
-- =============================================================

local addonName, L3F = ...

-- Strip order per Morphéours: Drops first (the thing players check most),
-- Spells second, Notes third. Existing players keep their saved active key.
local SUB_TABS = { "drops", "spells", "notes" }
local SUB_TAB_LABELS = {
    drops = "Drops", spells = "Spells", notes = "Notes",
}

-- Consumable-specific sub-tab strip (a separate strip, shown when a
-- consumable is selected; the NPC strip stays hidden in that case).
local CONSUMABLE_SUB_TABS = { "effects", "obtain" }
local CONSUMABLE_SUB_TAB_LABELS = {
    effects = "Effects",
    obtain  = "How to obtain",
}

local CAT_RAIDS       = "Raids"
local CAT_HEROICS     = "Heroic Dungeons"
local CAT_CONSUMABLES = "Consumables"

local treePane, listPane, detailPane
local treeList, npcList, searchBox
local currentNPC, currentConsumable, currentBonusItem
local subTabButtons = {}
local consumableSubTabButtons = {}
local subTabContent
local consumableSubStrip
local viewer, npcTitle, npcMeta


-- =============================================================
-- ITEM INFO ASYNC CACHE  (icon + quality colour for drop rows)
-- =============================================================
-- GetItemInfo is async: it returns nil for an uncached item, then the
-- data arrives via GET_ITEM_INFO_RECEIVED. Apply the texture/colour
-- immediately if cached, otherwise queue and reapply when the event
-- fires.
local pendingItem = {}
local itemInfoFrame = CreateFrame("Frame")
itemInfoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

local function applyItemUI(itemID, label, icon)
    local _, _, quality, _, _, _, _, _, _, tex = GetItemInfo(itemID)
    if label and quality then
        local r, g, b = GetItemQualityColor(quality)
        label:SetTextColor(r, g, b)
    end
    if icon and tex then
        icon:SetTexture(tex)
    end
    return quality ~= nil and (icon == nil or tex ~= nil)
end

local function queueItemUI(itemID, label, icon)
    if not itemID then return end
    if applyItemUI(itemID, label, icon) then return end
    pendingItem[itemID] = pendingItem[itemID] or {}
    table.insert(pendingItem[itemID], { label = label, icon = icon })
end

itemInfoFrame:SetScript("OnEvent", function(_, _, itemID)
    local list = pendingItem[itemID]
    if not list then return end
    pendingItem[itemID] = nil
    for _, p in ipairs(list) do applyItemUI(itemID, p.label, p.icon) end
end)


-- =============================================================
-- TREE STATE  (persisted in L3F.db.atlas)
-- =============================================================
local function ensureState()
    L3F.db.atlas.tree = L3F.db.atlas.tree or {}
    L3F.db.atlas.tree.expanded = L3F.db.atlas.tree.expanded or { ["cat:" .. CAT_RAIDS] = true }
    -- Migrate the older single-raid selection into the new node-key model.
    if not L3F.db.atlas.selected then
        if L3F.db.atlas.lastSelectedRaid then
            L3F.db.atlas.selected = "raid-bosses:" .. L3F.db.atlas.lastSelectedRaid
        end
    end
    -- 0.13.1 tree restructure: wings are gone from the Atlas; each raid /
    -- heroic now expands to Bosses + Trash sub-leaves. Coerce any saved
    -- selection that pointed at the old keys so the user lands somewhere
    -- sensible instead of a blank middle pane.
    local sel = L3F.db.atlas.selected
    if sel then
        if sel:sub(1, 5) == "raid:" then
            L3F.db.atlas.selected = "raid-bosses:" .. sel:sub(6)
        elseif sel:sub(1, 5) == "wing:" then
            local raidName = sel:sub(6):match("^(.+)/%d+$")
            if raidName then
                L3F.db.atlas.selected = "raid-bosses:" .. raidName
            end
        elseif sel:sub(1, 7) == "heroic:" then
            L3F.db.atlas.selected = "heroic-bosses:" .. sel:sub(8)
        end
    end
end

local function isExpanded(key)
    ensureState()
    return L3F.db.atlas.tree.expanded[key] and true or false
end

local function setExpanded(key, val)
    ensureState()
    L3F.db.atlas.tree.expanded[key] = val and true or nil
end

local function isSelected(key)
    return L3F.db.atlas.selected == key
end

local function selectKey(key)
    L3F.db.atlas.selected = key
end


-- =============================================================
-- RAID HELPERS
-- =============================================================
local function categorizeRaids()
    local raids, heroics = {}, {}
    for _, r in ipairs(L3F.raids) do
        if r.sections then table.insert(raids, r) else table.insert(heroics, r) end
    end
    return raids, heroics
end

local function findRaid(name)
    for _, r in ipairs(L3F.raids) do
        if r.name == name then return r end
    end
end

-- Boss classifier. Primary source: the `kind` field stamped onto every NPC
-- entry by phase_a_kind_enrich.py (sourced from the JSON; "boss"/"trash").
-- Fallback for any unenriched NPC: the marks-count heuristic - raid data
-- files use the 8-entry TRASH constant for filler mobs and a shorter mark
-- list ({8}, {7}, {8,7,6,5,4}, ...) for named encounters. The fallback
-- mis-classifies elite-trash in SlavePens/Steamvault/Underbog (those use
-- marks={N} too), which is exactly what the `kind` field was added to fix.
local function isBoss(npc)
    if npc.kind then return npc.kind == "boss" end
    return npc.marks and #npc.marks > 0 and #npc.marks < 8
end


-- =============================================================
-- TREE PANE
-- =============================================================
local function buildTreePane(parent)
    treePane = CreateFrame("Frame", nil, parent)
    treePane:SetPoint("TOPLEFT",    parent, "TOPLEFT",    0, 0)
    treePane:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    treePane:SetWidth(200)
    local bg = treePane:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.18)

    -- SEARCH BOX (global - filters the NPC list across every raid + heroic).
    -- Right text inset reserves room for the X clear button so long
    -- queries can't visually slide under it.
    searchBox = CreateFrame("EditBox", nil, treePane, "InputBoxTemplate")
    searchBox:SetSize(176, 22)
    searchBox:SetPoint("TOPLEFT", treePane, "TOPLEFT", 14, -8)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetTextInsets(0, 20, 0, 0)
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    placeholder:SetText("Search")
    searchBox:HookScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        if L3F.RefreshNPCList then L3F.RefreshNPCList() end
    end)
    searchBox:HookScript("OnEditFocusGained", function() placeholder:SetText("") end)
    searchBox:HookScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then placeholder:SetText("Search") end
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)

    -- X clear button (mirrors the Automarker tab's button so the two
    -- search boxes feel the same; also serves as a Backspace fallback).
    local clearBtn = CreateFrame("Button", nil, searchBox)
    clearBtn:SetSize(16, 16)
    clearBtn:SetPoint("RIGHT", searchBox, "RIGHT", -2, 0)
    clearBtn:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    clearBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
    end)
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clear search")
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local treeScroll = CreateFrame("ScrollFrame", nil, treePane, "UIPanelScrollFrameTemplate")
    treeScroll:SetPoint("TOPLEFT",     searchBox, "BOTTOMLEFT",  0, -6)
    treeScroll:SetPoint("BOTTOMRIGHT", treePane,  "BOTTOMRIGHT", -20, 6)
    treeList = CreateFrame("Frame", nil, treeScroll)
    treeList:SetSize(170, 1)
    treeScroll:SetScrollChild(treeList)

    -- ---------------------------------------------------------
    -- Row builder. Returns a Button that lays itself out at (indent, y).
    -- opts = {
    --   indent, y, key, label,
    --   font          (default GameFontNormalSmall),
    --   hasArrow      (bool; expandable row)
    --   expanded      (bool; arrow direction)
    --   onClickRow    (called when row is clicked)
    -- }
    -- ---------------------------------------------------------
    local function addRow(opts)
        local row = CreateFrame("Button", nil, treeList)
        row:SetSize(170 - opts.indent, 18)
        row:SetPoint("TOPLEFT", treeList, "TOPLEFT", opts.indent, -opts.y)

        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        local active = isSelected(opts.key)
        rbg:SetColorTexture(
            active and 0.30 or 0,
            active and 0.65 or 0,
            active and 1.0  or 0,
            active and 0.25 or 0)

        local textX = 4
        if opts.hasArrow then
            local arrow = row:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(12, 12)
            arrow:SetPoint("LEFT", row, "LEFT", 2, 0)
            arrow:SetTexture(opts.expanded
                and "Interface\\Buttons\\UI-MinusButton-Up"
                or  "Interface\\Buttons\\UI-PlusButton-Up")
            textX = 16
        end

        local txt = row:CreateFontString(nil, "OVERLAY", opts.font or "GameFontNormalSmall")
        txt:SetPoint("LEFT", row, "LEFT", textX, 0)
        txt:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        txt:SetJustifyH("LEFT")
        txt:SetText(opts.label)
        txt:SetTextColor(active and 1 or 0.85, active and 1 or 0.85, active and 1 or 0.85, 1)

        row:SetScript("OnClick", opts.onClickRow)
        row:SetScript("OnEnter", function()
            if not isSelected(opts.key) then rbg:SetColorTexture(1, 1, 1, 0.07) end
        end)
        row:SetScript("OnLeave", function()
            if isSelected(opts.key) then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
            else rbg:SetColorTexture(0, 0, 0, 0) end
        end)
        return row
    end

    -- ---------------------------------------------------------
    -- L3F.RefreshTree - rebuild the tree DOM. Cheap enough to call
    -- on every expand toggle / selection change (a few dozen rows).
    -- ---------------------------------------------------------
    L3F.RefreshTree = function()
        for _, c in ipairs({treeList:GetChildren()}) do c:Hide(); c:SetParent(nil) end

        local y = 0
        local raids, heroics = categorizeRaids()

        -- RAIDS category --------------------------------------
        local catRaidsKey   = "cat:" .. CAT_RAIDS
        local raidsExpanded = isExpanded(catRaidsKey)
        addRow{
            indent = 0, y = y,
            key = catRaidsKey, label = CAT_RAIDS,
            font = "GameFontNormal",
            hasArrow = true, expanded = raidsExpanded,
            onClickRow = function()
                setExpanded(catRaidsKey, not raidsExpanded)
                L3F.RefreshTree()
            end,
        }
        y = y + 20

        -- Renders the "Bosses" + "Trash" sub-leaves under a raid or heroic
        -- parent row. Used for both categories below. `prefix` is the
        -- selection key prefix - "raid" or "heroic" - which RefreshNPCList
        -- dispatches on. `parentName` is the raid / heroic display name.
        local function addBossTrashLeaves(prefix, parentName)
            local bossKey  = prefix .. "-bosses:" .. parentName
            local trashKey = prefix .. "-trash:"  .. parentName
            addRow{
                indent = 32, y = y,
                key = bossKey, label = "Bosses",
                font = "GameFontHighlightSmall",
                hasArrow = false,
                onClickRow = function()
                    selectKey(bossKey)
                    L3F.RefreshTree()
                    L3F.RefreshNPCList()
                end,
            }
            y = y + 18
            addRow{
                indent = 32, y = y,
                key = trashKey, label = "Trash",
                font = "GameFontHighlightSmall",
                hasArrow = false,
                onClickRow = function()
                    selectKey(trashKey)
                    L3F.RefreshTree()
                    L3F.RefreshNPCList()
                end,
            }
            y = y + 18
        end

        if raidsExpanded then
            for _, raid in ipairs(raids) do
                local raidKey = "raid:" .. raid.name
                local raidExpanded = isExpanded(raidKey)
                -- Raid row is a pure expand toggle - no selection. The two
                -- meaningful selections sit under it. This is the Morphéours
                -- 0.13.1 restructure: wings are gone from the Atlas, replaced
                -- by Bosses / Trash sub-leaves so each list pane shows only
                -- one of the two, never mixed.
                addRow{
                    indent = 16, y = y,
                    key = raidKey, label = raid.name,
                    font = "GameFontNormalSmall",
                    hasArrow = true, expanded = raidExpanded,
                    onClickRow = function()
                        setExpanded(raidKey, not raidExpanded)
                        L3F.RefreshTree()
                    end,
                }
                y = y + 20

                if raidExpanded then
                    addBossTrashLeaves("raid", raid.name)
                end
            end
        end

        -- HEROIC DUNGEONS category ----------------------------
        local catHeroKey   = "cat:" .. CAT_HEROICS
        local heroExpanded = isExpanded(catHeroKey)
        addRow{
            indent = 0, y = y,
            key = catHeroKey, label = CAT_HEROICS,
            font = "GameFontNormal",
            hasArrow = true, expanded = heroExpanded,
            onClickRow = function()
                setExpanded(catHeroKey, not heroExpanded)
                L3F.RefreshTree()
            end,
        }
        y = y + 20

        if heroExpanded then
            for _, heroic in ipairs(heroics) do
                local heroicKey = "heroic:" .. heroic.name
                local heroicExpanded = isExpanded(heroicKey)
                -- Heroic row, like the raid row above, is now an expand
                -- toggle that opens Bosses / Trash leaves. Trash will be
                -- empty for most heroics (HFR/BF/etc. only have boss entries
                -- in the Lua); SlavePens / Steamvault / Underbog have real
                -- elite-trash there.
                addRow{
                    indent = 16, y = y,
                    key = heroicKey, label = heroic.name,
                    font = "GameFontNormalSmall",
                    hasArrow = true, expanded = heroicExpanded,
                    onClickRow = function()
                        setExpanded(heroicKey, not heroicExpanded)
                        L3F.RefreshTree()
                    end,
                }
                y = y + 20

                if heroicExpanded then
                    addBossTrashLeaves("heroic", heroic.name)
                end
            end
        end

        -- CONSUMABLES category ---------------------------------
        -- Atlas-only; the Automarker never sees these. The tree is empty
        -- until Data/Consumables/*.lua files (loaded via the .toc) call
        -- L3F.RegisterConsumables - this scaffolding lights up the moment
        -- the data populate task runs.
        local catConsKey   = "cat:" .. CAT_CONSUMABLES
        local consExpanded = isExpanded(catConsKey)
        addRow{
            indent = 0, y = y,
            key = catConsKey, label = CAT_CONSUMABLES,
            font = "GameFontNormal",
            hasArrow = true, expanded = consExpanded,
            onClickRow = function()
                setExpanded(catConsKey, not consExpanded)
                L3F.RefreshTree()
            end,
        }
        y = y + 20

        if consExpanded then
            -- Categories are clickable LEAVES - no further sub-expansion.
            -- Clicking a category selects it and the middle list pane
            -- shows the items it contains (handled in RefreshNPCList).
            -- Mirrors how Heroic Dungeons leaves work.
            for _, catName in ipairs(L3F.consumableCategoryOrder) do
                local subKey = "consumable-cat:" .. catName
                addRow{
                    indent = 16, y = y,
                    key = subKey, label = catName,
                    font = "GameFontNormalSmall",
                    hasArrow = false,
                    onClickRow = function()
                        selectKey(subKey)
                        currentConsumable = nil
                        currentNPC = nil
                        currentBonusItem = nil
                        L3F.RefreshTree()
                        L3F.RefreshNPCList()
                        L3F.RefreshDetailPane()
                    end,
                }
                y = y + 20
            end
        end

        -- BONUS CATEGORIES  (Factions / Pre-BiS / PvP / Professions /
        -- Collections). Order follows L3F.bonusCategories which is the
        -- .toc load order. Each top-level row expands into entry leaves
        -- (e.g. faction names, class/spec rows, arena seasons). Selecting
        -- an entry shows section-grouped items in the middle list pane.
        for _, cat in ipairs(L3F.bonusCategories or {}) do
            local catBonusKey = "cat:bonus:" .. cat.key
            local bonusExpanded = isExpanded(catBonusKey)
            addRow{
                indent = 0, y = y,
                key = catBonusKey, label = cat.label,
                font = "GameFontNormal",
                hasArrow = true, expanded = bonusExpanded,
                onClickRow = function()
                    setExpanded(catBonusKey, not bonusExpanded)
                    L3F.RefreshTree()
                end,
            }
            y = y + 20

            if bonusExpanded then
                for _, entry in ipairs(cat.entries) do
                    local entryKey = "bonus:" .. cat.key .. ":" .. entry.key
                    addRow{
                        indent = 16, y = y,
                        key = entryKey, label = entry.name,
                        font = "GameFontNormalSmall",
                        hasArrow = false,
                        onClickRow = function()
                            selectKey(entryKey)
                            currentNPC = nil
                            currentConsumable = nil
                            currentBonusItem = nil
                            L3F.RefreshTree()
                            L3F.RefreshNPCList()
                            L3F.RefreshDetailPane()
                        end,
                    }
                    y = y + 20
                end
            end
        end

        treeList:SetHeight(math.max(y, 1))
    end
end


-- =============================================================
-- LIST PANE
-- =============================================================
local function buildListPane(parent)
    listPane = CreateFrame("Frame", nil, parent)
    listPane:SetPoint("TOPLEFT",    treePane, "TOPRIGHT",    0, 0)
    listPane:SetPoint("BOTTOMLEFT", treePane, "BOTTOMRIGHT", 0, 0)
    listPane:SetWidth(200)

    local npcScroll = CreateFrame("ScrollFrame", nil, listPane, "UIPanelScrollFrameTemplate")
    npcScroll:SetPoint("TOPLEFT",     listPane, "TOPLEFT",     4, -4)
    npcScroll:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -20, 4)
    npcList = CreateFrame("Frame", nil, npcScroll)
    npcList:SetSize(170, 1)
    npcScroll:SetScrollChild(npcList)

    -- NPC row. `location` is shown as a smaller dim line below the name
    -- in global-search results, so the user knows which raid each hit
    -- belongs to.
    local function addNPC(npc, y, location)
        local rowH = location and 30 or 18
        local row = CreateFrame("Button", nil, npcList)
        row:SetSize(170, rowH)
        row:SetPoint("TOPLEFT", npcList, "TOPLEFT", 0, -y)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        local active = currentNPC and currentNPC.id == npc.id
        rbg:SetColorTexture(active and 0.30 or 0, active and 0.65 or 0, active and 1 or 0, active and 0.25 or 0)

        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -1)
        txt:SetText(npc.name)
        -- Boss names get a subtle gold tint so they pop in flat raid
        -- views and in global search results.
        if isBoss(npc) then
            txt:SetTextColor(active and 1 or 1, active and 1 or 0.82, active and 1 or 0, 1)
        else
            txt:SetTextColor(active and 1 or 0.85, active and 1 or 0.85, active and 1 or 0.85, 1)
        end

        if location then
            local loc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            loc:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -14)
            loc:SetText(location)
        end

        row:SetScript("OnClick", function()
            currentNPC = npc
            currentConsumable = nil
            currentBonusItem = nil
            L3F.db.atlas.lastSelectedNPC = npc.id
            if L3F.RefreshNPCList then L3F.RefreshNPCList() end
            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
        end)
        row:SetScript("OnEnter", function()
            if not currentNPC or currentNPC.id ~= npc.id then rbg:SetColorTexture(1, 1, 1, 0.07) end
        end)
        row:SetScript("OnLeave", function()
            if currentNPC and currentNPC.id == npc.id then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
            else rbg:SetColorTexture(0, 0, 0, 0) end
        end)
        return y + rowH + 2
    end

    -- Consumable list row. Used when a consumable-cat: node is selected
    -- in the tree. Each row gets the item's icon (async via queueItemUI),
    -- the name (quality-coloured once the item info caches), and a
    -- mouseover that shows the in-game item tooltip - the player can
    -- read effect + source straight from WoW.
    local function addConsumableRow(item, y)
        local rowH = 24
        local row = CreateFrame("Button", nil, npcList)
        row:SetSize(170, rowH)
        row:SetPoint("TOPLEFT", npcList, "TOPLEFT", 0, -y)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        local active = currentConsumable and currentConsumable == item
        rbg:SetColorTexture(active and 0.30 or 0, active and 0.65 or 0, active and 1 or 0, active and 0.25 or 0)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        txt:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        txt:SetJustifyH("LEFT")
        txt:SetWordWrap(false)
        txt:SetText(item.name or "")
        if item.id then
            queueItemUI(item.id, txt, icon)
        else
            txt:SetTextColor(active and 1 or 0.85, active and 1 or 0.85, active and 1 or 0.85, 1)
        end

        row:SetScript("OnClick", function()
            currentConsumable = item
            currentNPC = nil
            currentBonusItem = nil
            if L3F.RefreshNPCList then L3F.RefreshNPCList() end
            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
        end)
        row:SetScript("OnEnter", function(self)
            if not active then rbg:SetColorTexture(1, 1, 1, 0.07) end
            if item.id then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then GameTooltip:SetItemByID(item.id)
                else GameTooltip:SetHyperlink("item:" .. item.id) end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            if active then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
            else rbg:SetColorTexture(0, 0, 0, 0) end
            GameTooltip:Hide()
        end)
        return y + rowH + 2
    end

    -- Bonus-category section header (e.g. "Exalted" within a faction's
    -- list; "Head" within a Pre-BiS slot list). Rendered above the rows
    -- belonging to that section.
    local function addBonusSectionHeader(name, y)
        local h = npcList:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", npcList, "TOPLEFT", 6, -y - 2)
        h:SetText(name:upper())
        return y + 16
    end

    -- Bonus-category item row. Same async icon+name pattern as the
    -- consumable rows, plus a click handler that prefers the cross-link
    -- (jump to a dropping NPC when L3F.itemLookup[id] resolves; otherwise
    -- show the bonus-item card in the detail pane).
    local function addBonusItemRow(itemID, y)
        local rowH = 24
        local row = CreateFrame("Button", nil, npcList)
        row:SetSize(170, rowH)
        row:SetPoint("TOPLEFT", npcList, "TOPLEFT", 0, -y)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        local active = currentBonusItem and currentBonusItem.id == itemID
        rbg:SetColorTexture(active and 0.30 or 0, active and 0.65 or 0, active and 1 or 0, active and 0.25 or 0)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        txt:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        txt:SetJustifyH("LEFT")
        txt:SetWordWrap(false)
        txt:SetText("Item #" .. itemID)
        queueItemUI(itemID, txt, icon)

        row:SetScript("OnClick", function()
            -- Cross-link: if this item is dropped by a known NPC, jump there
            -- and land on the Drops sub-tab. This is the killer Phase C path
            -- for Pre-BiS items - one click takes the player straight to
            -- the boss they need to farm. Items that have no drop source
            -- (vendor / crafted / PvP-only) fall through to the bonus card.
            if L3F.itemLookup and L3F.itemLookup[itemID]
               and L3F.itemLookup[itemID][1] then
                local link = L3F.itemLookup[itemID][1]
                currentNPC = link.npc
                currentConsumable = nil
                currentBonusItem = nil
                L3F.db.atlas.lastSelectedNPC = link.npc.id
                L3F.db.atlas.lastActiveSubTab = "drops"
            else
                currentBonusItem = { id = itemID }
                currentNPC = nil
                currentConsumable = nil
            end
            if L3F.RefreshNPCList then L3F.RefreshNPCList() end
            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
        end)
        row:SetScript("OnEnter", function(self)
            if not active then rbg:SetColorTexture(1, 1, 1, 0.07) end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(itemID)
            else GameTooltip:SetHyperlink("item:" .. itemID) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if active then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
            else rbg:SetColorTexture(0, 0, 0, 0) end
            GameTooltip:Hide()
        end)
        return y + rowH + 2
    end

    -- Search-result row. Renders five kinds of hits in a unified layout:
    --   kind = "npc"        -> bare NPC name (with location subtitle)
    --   kind = "drop"       -> item icon + drop name + "from NPC"
    --   kind = "spell"      -> spell icon + spell name + "by NPC"
    --   kind = "consumable" -> item icon + name + "Consumable - <category>"
    --   kind = "bonus"      -> item icon + name + "<Category> - <Entry>"
    -- Clicking a drop/spell result selects the underlying NPC AND switches
    -- the detail pane to the matching sub-tab. Clicking a consumable
    -- selects it (clears the current NPC) and renders the consumable card.
    -- Clicking a bonus result jumps to a known dropping NPC if the item is
    -- in L3F.itemLookup; otherwise shows the bonus-item card.
    local function addSearchHit(hit, y)
        local rowH = 30
        local row = CreateFrame("Button", nil, npcList)
        row:SetSize(170, rowH)
        row:SetPoint("TOPLEFT", npcList, "TOPLEFT", 0, -y)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        local active = false
        if hit.kind == "consumable" then
            active = currentConsumable and currentConsumable == hit.consumable
        elseif hit.kind == "bonus" then
            active = currentBonusItem and currentBonusItem.id == hit.itemID
        else
            active = currentNPC and currentNPC.id == hit.npc.id
        end
        rbg:SetColorTexture(active and 0.30 or 0, active and 0.65 or 0, active and 1 or 0, active and 0.25 or 0)

        local textX = 6
        if hit.kind ~= "npc" then
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            if hit.kind == "drop" then
                queueItemUI(hit.drop.id, nil, icon)
            elseif hit.kind == "spell" then
                local _, _, tex = GetSpellInfo(hit.spellID)
                if tex then icon:SetTexture(tex) end
            elseif hit.kind == "consumable" and hit.consumable.id then
                queueItemUI(hit.consumable.id, nil, icon)
            elseif hit.kind == "bonus" then
                queueItemUI(hit.itemID, nil, icon)
            end
            textX = 24
        end

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -1)
        title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(hit.label)
        if hit.kind == "npc" and isBoss(hit.npc) then
            title:SetTextColor(active and 1 or 1, active and 1 or 0.82, active and 1 or 0, 1)
        elseif hit.kind == "drop" then
            queueItemUI(hit.drop.id, title, nil)
        elseif hit.kind == "consumable" and hit.consumable.id then
            queueItemUI(hit.consumable.id, title, nil)
        elseif hit.kind == "bonus" then
            queueItemUI(hit.itemID, title, nil)
        else
            title:SetTextColor(active and 1 or 0.85, active and 1 or 0.85, active and 1 or 0.85, 1)
        end

        local sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("TOPLEFT", row, "TOPLEFT", textX + 4, -14)
        sub:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -14)
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(false)
        sub:SetText(hit.subtitle or "")

        row:SetScript("OnClick", function()
            if hit.kind == "consumable" then
                currentConsumable = hit.consumable
                currentNPC = nil
                currentBonusItem = nil
            elseif hit.kind == "bonus" then
                -- Bonus-item search hit. Prefer the cross-link: if the item
                -- also has a known NPC drop entry, jump there (the player
                -- usually cares MORE about "where do I farm this" than "the
                -- vendor list it's in"). Otherwise show the bonus-item card.
                if L3F.itemLookup and L3F.itemLookup[hit.itemID]
                   and L3F.itemLookup[hit.itemID][1] then
                    local link = L3F.itemLookup[hit.itemID][1]
                    currentNPC = link.npc
                    currentConsumable = nil
                    currentBonusItem = nil
                    L3F.db.atlas.lastSelectedNPC = link.npc.id
                    L3F.db.atlas.lastActiveSubTab = "drops"
                else
                    currentBonusItem = { id = hit.itemID }
                    currentNPC = nil
                    currentConsumable = nil
                end
            else
                currentNPC = hit.npc
                currentConsumable = nil
                currentBonusItem = nil
                L3F.db.atlas.lastSelectedNPC = hit.npc.id
                -- Land on the sub-tab that contains the matched item so
                -- the player sees the drop / spell they searched for.
                if hit.kind == "drop" then
                    L3F.db.atlas.lastActiveSubTab = "drops"
                elseif hit.kind == "spell" then
                    L3F.db.atlas.lastActiveSubTab = "spells"
                end
            end
            if L3F.RefreshNPCList then L3F.RefreshNPCList() end
            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
        end)
        row:SetScript("OnEnter", function()
            if not active then rbg:SetColorTexture(1, 1, 1, 0.07) end
        end)
        row:SetScript("OnLeave", function()
            if active then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
            else rbg:SetColorTexture(0, 0, 0, 0) end
        end)
        return y + rowH + 2
    end

    L3F.RefreshNPCList = function()
        for _, c in ipairs({npcList:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        -- FontStrings created directly on npcList (the "No matches." and
        -- "Pick a raid..." placeholders below) are REGIONS, not children,
        -- so the loop above doesn't catch them. Without this they linger
        -- when the user clears the search.
        for _, r in ipairs({npcList:GetRegions()}) do
            r:Hide(); r:ClearAllPoints()
            if r.SetText then r:SetText("") end
        end
        local y = 0

        local search = (searchBox and searchBox:GetText() or "")
            :lower():gsub("^%s+", ""):gsub("%s+$", "")

        -- ---------------------------------------------------------
        -- GLOBAL SEARCH MODE - matches NPC names, drop item names, and
        -- spell names across every raid + heroic. The "I know what drops
        -- this item but not who drops it" case: typing the item name lands
        -- the player on the right NPC's Drops tab in one click.
        -- ---------------------------------------------------------
        if search ~= "" then
            local hits = {}
            for _, raid in ipairs(L3F.raids) do
                L3F.iterNPCs(raid, function(npc, sectionName)
                    local loc = sectionName and (sectionName .. " - " .. raid.name) or raid.name

                    -- 1. NPC name match
                    if npc.name:lower():find(search, 1, true) then
                        table.insert(hits, {
                            kind = "npc", npc = npc,
                            label = npc.name, subtitle = loc,
                        })
                    end

                    -- 2. Drop name matches. drop.name is bundled in the
                    -- Data/Drops files so we can match without waiting on
                    -- GetItemInfo to cache.
                    if npc.drops then
                        for _, drop in ipairs(npc.drops) do
                            local dropName = drop.name or ("Item #" .. drop.id)
                            if dropName:lower():find(search, 1, true) then
                                table.insert(hits, {
                                    kind = "drop", npc = npc, drop = drop,
                                    label = dropName,
                                    subtitle = "from " .. npc.name,
                                })
                            end
                        end
                    end

                    -- 3. Spell name matches. GetSpellInfo returns the
                    -- localized name; uncached spells return nil and are
                    -- skipped (subsequent searches once cached will match).
                    if npc.spells then
                        for _, spellID in ipairs(npc.spells) do
                            local spellName = GetSpellInfo(spellID)
                            if spellName and spellName:lower():find(search, 1, true) then
                                table.insert(hits, {
                                    kind = "spell", npc = npc, spellID = spellID,
                                    label = spellName,
                                    subtitle = "by " .. npc.name,
                                })
                            end
                        end
                    end
                end)
            end

            -- 4. Consumable matches (Atlas-only). Matches the English name
            -- and the optional French name (nameFR) so the L3F guild can
            -- find an item by either label.
            for _, catName in ipairs(L3F.consumableCategoryOrder) do
                for _, item in ipairs(L3F.consumables[catName] or {}) do
                    local match = item.name and item.name:lower():find(search, 1, true)
                    if not match and item.nameFR then
                        match = item.nameFR:lower():find(search, 1, true)
                    end
                    if match then
                        table.insert(hits, {
                            kind = "consumable", consumable = item,
                            label = item.name,
                            subtitle = "Consumable - " .. catName,
                        })
                    end
                end
            end

            -- 5. Bonus-category item matches (Factions / Pre-BiS / PvP /
            -- Professions / Collections). These items have no `name` field
            -- in the Lua - GetItemInfo resolves it. We try the cached name
            -- first; otherwise we let a pure-digit search match the item ID
            -- directly (e.g. typing "32486" finds it regardless of cache
            -- state). Each unique item is hit once per registration (an
            -- item that appears in BOTH a faction list and a Pre-BiS list
            -- gets two hits with different subtitles, which is the desired
            -- behaviour - the player picks the relevant context).
            local numericSearch = tonumber(search)
            for itemID, sources in pairs(L3F.bonusItemLookup or {}) do
                local cachedName = GetItemInfo(itemID)
                local matched = false
                if numericSearch and numericSearch == itemID then
                    matched = true
                elseif cachedName and cachedName:lower():find(search, 1, true) then
                    matched = true
                end
                if matched then
                    -- One hit per source entry so the user sees which list
                    -- the item lives in (Honored from Cenarion Expedition,
                    -- Pre-BiS Druid Balance / Head, etc.).
                    for _, src in ipairs(sources) do
                        table.insert(hits, {
                            kind     = "bonus",
                            itemID   = itemID,
                            source   = src,
                            label    = cachedName or ("Item #" .. itemID),
                            subtitle = src.catLabel .. " - " .. src.entry.name
                                       .. (src.sectionName and (" / " .. src.sectionName) or ""),
                        })
                    end
                end
            end

            if #hits == 0 then
                local txt = npcList:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                txt:SetPoint("TOPLEFT", npcList, "TOPLEFT", 8, -8)
                txt:SetText("No matches.")
                npcList:SetHeight(32)
                return
            end
            for _, h in ipairs(hits) do
                y = addSearchHit(h, y)
            end
            npcList:SetHeight(math.max(y, 1))
            return
        end

        -- ---------------------------------------------------------
        -- BROWSE MODE - tree-selected node drives the contents.
        -- ---------------------------------------------------------
        local sel = L3F.db.atlas.selected
        if not sel then
            local txt = npcList:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            txt:SetPoint("TOPLEFT", npcList, "TOPLEFT", 8, -8)
            txt:SetText("Pick a Bosses or Trash leaf on the left.")
            npcList:SetHeight(32)
            return
        end

        -- Flatten the raid's NPC roster across all spatial sections, OR
        -- return the heroic dungeon's flat NPC list. The Atlas no longer
        -- shows the wings themselves (the spatial Sections/<Raid>.lua data
        -- still drives the Automarker tab; this is just the Atlas tree).
        local function collectRoster(parent)
            if parent.sections then
                local all = {}
                for _, sec in ipairs(parent.sections) do
                    for _, npc in ipairs(sec.npcs) do table.insert(all, npc) end
                end
                return all
            end
            return parent.npcs or {}
        end

        -- Filter `roster` to just bosses or just trash and render.
        local function renderOneSide(roster, wantBoss)
            local out = {}
            for _, npc in ipairs(roster) do
                if isBoss(npc) == wantBoss then table.insert(out, npc) end
            end
            if #out == 0 then
                local txt = npcList:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                txt:SetPoint("TOPLEFT", npcList, "TOPLEFT", 8, -8)
                txt:SetText(wantBoss and "No bosses listed." or "No trash listed.")
                return
            end
            for _, npc in ipairs(out) do y = addNPC(npc, y, nil) end
        end

        -- Order matters: the longer-prefix keys must match before their
        -- shorter cousins (raid-bosses: starts with "raid", heroic-bosses:
        -- starts with "heroic").
        if sel:sub(1, 12) == "raid-bosses:" then
            local raid = findRaid(sel:sub(13))
            if raid then renderOneSide(collectRoster(raid), true) end

        elseif sel:sub(1, 11) == "raid-trash:" then
            local raid = findRaid(sel:sub(12))
            if raid then renderOneSide(collectRoster(raid), false) end

        elseif sel:sub(1, 14) == "heroic-bosses:" then
            local heroic = findRaid(sel:sub(15))
            if heroic then renderOneSide(collectRoster(heroic), true) end

        elseif sel:sub(1, 13) == "heroic-trash:" then
            local heroic = findRaid(sel:sub(14))
            if heroic then renderOneSide(collectRoster(heroic), false) end

        elseif sel:sub(1, 15) == "consumable-cat:" then
            -- Consumable category selected -> list the items in that
            -- category. Each row mouseover triggers the in-game item
            -- tooltip; clicking selects the item for the detail pane.
            local catName = sel:sub(16)
            local items = L3F.consumables[catName] or {}
            for _, item in ipairs(items) do
                y = addConsumableRow(item, y)
            end

        elseif sel:sub(1, 6) == "bonus:" then
            -- Bonus-category entry selected -> render each section as a
            -- dim uppercase header followed by its item rows. Format key:
            --   bonus:<catKey>:<entryKey>
            local rest = sel:sub(7)
            local catKey, entryKey = rest:match("^([^:]+):(.+)$")
            local entry = catKey and entryKey
                and L3F.bonusLookup and L3F.bonusLookup[catKey]
                and L3F.bonusLookup[catKey][entryKey]
            if entry and entry.sections then
                for _, section in ipairs(entry.sections) do
                    if section.items and #section.items > 0 then
                        y = addBonusSectionHeader(section.name or "", y)
                        for _, item in ipairs(section.items) do
                            if item.id then y = addBonusItemRow(item.id, y) end
                        end
                        y = y + 4
                    end
                end
            end
        end

        npcList:SetHeight(math.max(y, 1))
    end
end


-- =============================================================
-- DETAIL PANE
-- =============================================================
local function buildDetailPane(parent)
    detailPane = CreateFrame("Frame", nil, parent)
    detailPane:SetPoint("TOPLEFT",     listPane, "TOPRIGHT",    0, 0)
    detailPane:SetPoint("BOTTOMRIGHT", parent,   "BOTTOMRIGHT", 0, 0)

    -- Model column
    local modelHost = CreateFrame("Frame", nil, detailPane)
    modelHost:SetPoint("TOPLEFT",    detailPane, "TOPLEFT",    8, -8)
    modelHost:SetPoint("BOTTOMLEFT", detailPane, "BOTTOMLEFT", 8, 8)
    modelHost:SetWidth(240)
    local mbg = modelHost:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints(); mbg:SetColorTexture(0, 0, 0, 0.18)

    viewer = L3F.CreateModelViewer(modelHost, 224, 240)
    viewer.frame:SetPoint("TOP", modelHost, "TOP", 0, -8)

    -- Consumable icon. Hidden by default; takes the model viewer's spot
    -- when a consumable (no 3D model) is selected. queueItemUI populates
    -- its texture from GetItemInfo asynchronously.
    local consumableIcon = modelHost:CreateTexture(nil, "ARTWORK")
    consumableIcon:SetSize(96, 96)
    consumableIcon:SetPoint("TOP", modelHost, "TOP", 0, -32)
    consumableIcon:Hide()
    detailPane.consumableIcon = consumableIcon

    npcTitle = modelHost:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    npcTitle:SetPoint("TOP", viewer.frame, "BOTTOM", 0, -8)
    npcTitle:SetWidth(220)

    npcMeta = modelHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    npcMeta:SetPoint("TOP", npcTitle, "BOTTOM", 0, -4)
    npcMeta:SetWidth(220)
    npcMeta:SetJustifyH("CENTER")

    -- Info column
    local infoHost = CreateFrame("Frame", nil, detailPane)
    infoHost:SetPoint("TOPLEFT",     modelHost, "TOPRIGHT",    8, 0)
    infoHost:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -8, 8)

    local subStrip = CreateFrame("Frame", nil, infoHost)
    subStrip:SetHeight(22)
    subStrip:SetPoint("TOPLEFT",  infoHost, "TOPLEFT",  0, 0)
    subStrip:SetPoint("TOPRIGHT", infoHost, "TOPRIGHT", -60, 0)  -- clear the top-right guild logo
    local stripLine = subStrip:CreateTexture(nil, "OVERLAY")
    stripLine:SetColorTexture(1, 1, 1, 0.15); stripLine:SetHeight(1)
    stripLine:SetPoint("BOTTOMLEFT",  subStrip, "BOTTOMLEFT",  0, 0)
    stripLine:SetPoint("BOTTOMRIGHT", subStrip, "BOTTOMRIGHT", 0, 0)

    subTabContent = CreateFrame("ScrollFrame", nil, infoHost, "UIPanelScrollFrameTemplate")
    subTabContent:SetPoint("TOPLEFT",     subStrip,  "BOTTOMLEFT",  0, -4)
    subTabContent:SetPoint("BOTTOMRIGHT", infoHost,  "BOTTOMRIGHT", -20, 0)
    subTabContent.body = CreateFrame("Frame", nil, subTabContent)
    subTabContent.body:SetSize(400, 1)
    subTabContent:SetScrollChild(subTabContent.body)
    -- Keep the scroll child as wide as the visible scroll area, so notes
    -- wrap (and drops / other sub-tabs lay out) to the real width rather
    -- than the hardcoded 400. Height stays under per-sub-tab control.
    local function fitBody()
        local w = subTabContent:GetWidth()
        if w and w > 1 then subTabContent.body:SetWidth(w) end
        -- Sub-tabs whose rendered height depends on the new width (e.g.
        -- the Notes wrapping FontString) register a callback here so
        -- they re-measure on every window resize. Cleared at the start
        -- of each RefreshDetailPane so stale callbacks don't leak.
        if subTabContent.body.onWidthChange then
            subTabContent.body.onWidthChange()
        end
    end
    subTabContent:HookScript("OnSizeChanged", fitBody)
    fitBody()

    local x = 0
    for _, key in ipairs(SUB_TABS) do
        local btn = CreateFrame("Button", nil, subStrip)
        btn:SetSize(80, 22)
        btn:SetPoint("BOTTOMLEFT", subStrip, "BOTTOMLEFT", x, 0)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("CENTER"); lbl:SetText(SUB_TAB_LABELS[key])
        btn.label = lbl
        local under = btn:CreateTexture(nil, "OVERLAY")
        under:SetColorTexture(0.30, 0.65, 1.0, 1); under:SetHeight(2)
        under:SetPoint("BOTTOMLEFT"); under:SetPoint("BOTTOMRIGHT"); under:Hide()
        btn.underline = under
        btn:SetScript("OnClick", function()
            L3F.db.atlas.lastActiveSubTab = key
            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
        end)
        subTabButtons[key] = btn
        x = x + 84
    end

    -- Distribute the sub-tab buttons across the strip width so they always fit,
    -- whatever size the user resizes the window to.
    local function layoutSubTabs()
        local w = subStrip:GetWidth()
        if not w or w <= 1 then return end
        local n = #SUB_TABS
        local gap = 4
        local bw = math.max(40, math.floor((w - gap * (n - 1)) / n))
        for i, key in ipairs(SUB_TABS) do
            local btn = subTabButtons[key]
            if btn then
                btn:SetSize(bw, 22)
                btn:ClearAllPoints()
                btn:SetPoint("BOTTOMLEFT", subStrip, "BOTTOMLEFT", (i - 1) * (bw + gap), 0)
            end
        end
    end
    subStrip:SetScript("OnSizeChanged", layoutSubTabs)
    layoutSubTabs()

    -- Consumable sub-tab strip - identical chrome to the NPC strip but
    -- with its own buttons (Effects, How to obtain). Shown when a
    -- consumable is selected; hidden otherwise (the NPC strip takes
    -- the same screen position when NPCs are shown).
    consumableSubStrip = CreateFrame("Frame", nil, infoHost)
    consumableSubStrip:SetHeight(22)
    consumableSubStrip:SetPoint("TOPLEFT",  infoHost, "TOPLEFT",  0, 0)
    consumableSubStrip:SetPoint("TOPRIGHT", infoHost, "TOPRIGHT", -60, 0)
    local consStripLine = consumableSubStrip:CreateTexture(nil, "OVERLAY")
    consStripLine:SetColorTexture(1, 1, 1, 0.15); consStripLine:SetHeight(1)
    consStripLine:SetPoint("BOTTOMLEFT",  consumableSubStrip, "BOTTOMLEFT",  0, 0)
    consStripLine:SetPoint("BOTTOMRIGHT", consumableSubStrip, "BOTTOMRIGHT", 0, 0)
    consumableSubStrip:Hide()

    for _, key in ipairs(CONSUMABLE_SUB_TABS) do
        local btn = CreateFrame("Button", nil, consumableSubStrip)
        btn:SetSize(120, 22)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("CENTER"); lbl:SetText(CONSUMABLE_SUB_TAB_LABELS[key])
        btn.label = lbl
        local under = btn:CreateTexture(nil, "OVERLAY")
        under:SetColorTexture(0.30, 0.65, 1.0, 1); under:SetHeight(2)
        under:SetPoint("BOTTOMLEFT"); under:SetPoint("BOTTOMRIGHT"); under:Hide()
        btn.underline = under
        btn:SetScript("OnClick", function()
            L3F.db.atlas.lastActiveConsumableSubTab = key
            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
        end)
        consumableSubTabButtons[key] = btn
    end

    local function layoutConsumableSubTabs()
        local w = consumableSubStrip:GetWidth()
        if not w or w <= 1 then return end
        local n = #CONSUMABLE_SUB_TABS
        local gap = 4
        local bw = math.max(40, math.floor((w - gap * (n - 1)) / n))
        for i, key in ipairs(CONSUMABLE_SUB_TABS) do
            local btn = consumableSubTabButtons[key]
            if btn then
                btn:SetSize(bw, 22)
                btn:ClearAllPoints()
                btn:SetPoint("BOTTOMLEFT", consumableSubStrip, "BOTTOMLEFT", (i - 1) * (bw + gap), 0)
            end
        end
    end
    consumableSubStrip:SetScript("OnSizeChanged", layoutConsumableSubTabs)
    layoutConsumableSubTabs()

    L3F.RefreshDetailPane = function()
        local npc = currentNPC
        local item = currentConsumable
        local bonus = currentBonusItem
        for k, btn in pairs(subTabButtons) do
            local active = (k == L3F.db.atlas.lastActiveSubTab)
            btn.label:SetTextColor(active and 1 or 0.7, active and 1 or 0.7, active and 1 or 0.7, 1)
            if active then btn.underline:Show() else btn.underline:Hide() end
        end
        -- Drop any resize callback from the previous sub-tab; the new
        -- render below installs its own if needed.
        subTabContent.body.onWidthChange = nil
        -- Clear both child frames AND regions (FontStrings/Textures from prior sub-tab).
        for _, c in ipairs({subTabContent.body:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        if subTabContent.body.GetRegions then
            for _, r in ipairs({subTabContent.body:GetRegions()}) do
                r:Hide(); r:ClearAllPoints()
                if r.SetText then r:SetText("") end
            end
        end

        -- ---------------------------------------------------------
        -- CONSUMABLE PATH - no 3D model, no NPC sub-tabs. Icon + name
        -- + category on the left; consumable sub-tab strip on the
        -- right (Effects / How to obtain).
        -- ---------------------------------------------------------
        if item then
            viewer.frame:Hide()
            subStrip:Hide()
            consumableSubStrip:Show()
            detailPane.consumableIcon:Show()
            detailPane.consumableIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            npcTitle:SetText(item.name or "")
            npcMeta:SetText(item.category or "")
            if item.id then
                queueItemUI(item.id, npcTitle, detailPane.consumableIcon)
            else
                npcTitle:SetTextColor(1, 1, 1, 1)
            end

            -- Highlight the active consumable sub-tab.
            local activeKey = L3F.db.atlas.lastActiveConsumableSubTab or "effects"
            L3F.db.atlas.lastActiveConsumableSubTab = activeKey
            for k, btn in pairs(consumableSubTabButtons) do
                local on = (k == activeKey)
                btn.label:SetTextColor(on and 1 or 0.7, on and 1 or 0.7, on and 1 or 0.7, 1)
                if on then btn.underline:Show() else btn.underline:Hide() end
            end

            local y = 4
            local function addLine(label, value, fontObj)
                if not value or value == "" then return end
                local fs = subTabContent.body:CreateFontString(nil, "OVERLAY", fontObj or "GameFontNormal")
                fs:SetPoint("TOPLEFT",  subTabContent.body, "TOPLEFT",  4, -y)
                fs:SetPoint("TOPRIGHT", subTabContent.body, "TOPRIGHT", -4, -y)
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(true)
                fs:SetText(label and (label .. ": " .. value) or value)
                y = y + math.max(fs:GetStringHeight() + 6, 18)
            end

            if activeKey == "effects" then
                addLine("Effect",   item.effect, "GameFontHighlight")
                addLine("Duration", item.duration)
                -- Rule/usage notes (e.g. "Classified as a Potion for
                -- Alchemy Masteries but acts like a Guardian Elixir")
                -- come last as a dim aside.
                addLine(nil,        item.notes)
            else  -- "obtain"
                local placeholder = "Source info not yet entered in the addon. "
                    .. "Hover the item in the list on the left for the in-game "
                    .. "tooltip - it shows where the item drops / who sells / "
                    .. "how it's crafted."
                addLine(nil, placeholder)
                -- Re-flow on resize: the placeholder is a single
                -- wrapping FontString; same callback pattern Notes uses.
                local txt = subTabContent.body.GetRegions and ({subTabContent.body:GetRegions()})[1]
                if txt then
                    subTabContent.body.onWidthChange = function()
                        subTabContent.body:SetHeight(math.max(txt:GetStringHeight() + 8, 1))
                    end
                end
            end

            subTabContent.body:SetHeight(math.max(y, 1))
            return
        end

        -- ---------------------------------------------------------
        -- BONUS-ITEM PATH - rendered when a player clicks a bonus list item
        -- that DOESN'T resolve to a known NPC drop (vendor / crafted / PvP
        -- exclusive items). Reuses the consumable icon scaffold; both
        -- sub-tab strips stay hidden because a bonus item has no sub-tabs
        -- to show. The body lists the item's source contexts (the catLabel
        -- and entry it came from) so the player can flip between, say, the
        -- Pre-BiS entry that recommends the item and the Faction page that
        -- sells it.
        -- ---------------------------------------------------------
        if bonus then
            viewer.frame:Hide()
            subStrip:Hide()
            consumableSubStrip:Hide()
            detailPane.consumableIcon:Show()
            detailPane.consumableIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            local cachedName = GetItemInfo(bonus.id) or ("Item #" .. bonus.id)
            npcTitle:SetText(cachedName)
            queueItemUI(bonus.id, npcTitle, detailPane.consumableIcon)

            -- Build the source list from L3F.bonusItemLookup. Multiple
            -- entries are possible (e.g. an item that's both a Faction
            -- reward and a Pre-BiS recommendation).
            local sources = L3F.bonusItemLookup and L3F.bonusItemLookup[bonus.id] or {}
            if sources[1] then
                local s = sources[1]
                npcMeta:SetText(s.catLabel .. " - " .. s.entry.name)
            else
                npcMeta:SetText("")
            end

            local y2 = 8
            local function addBlock(text, fontObj)
                local fs = subTabContent.body:CreateFontString(nil, "OVERLAY", fontObj or "GameFontNormal")
                fs:SetPoint("TOPLEFT",  subTabContent.body, "TOPLEFT",  4, -y2)
                fs:SetPoint("TOPRIGHT", subTabContent.body, "TOPRIGHT", -4, -y2)
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(true)
                fs:SetText(text)
                y2 = y2 + math.max(fs:GetStringHeight() + 6, 18)
            end

            if #sources == 0 then
                addBlock("Source info not registered for this item.")
            else
                addBlock("Listed in:", "GameFontHighlight")
                for _, src in ipairs(sources) do
                    local line = "- " .. src.catLabel .. " - " .. src.entry.name
                    if src.sectionName and src.sectionName ~= "" then
                        line = line .. " / " .. src.sectionName
                    end
                    addBlock(line)
                end
            end
            addBlock(" ")
            addBlock("Hover the item in the list on the left for the full "
                .. "in-game tooltip with stats and source.", "GameFontDisable")

            subTabContent.body:SetHeight(math.max(y2, 1))
            return
        end

        -- NPC / empty paths re-show the widgets the consumable path hid.
        viewer.frame:Show()
        subStrip:Show()
        consumableSubStrip:Hide()
        detailPane.consumableIcon:Hide()

        if not npc then
            viewer:Clear()
            npcTitle:SetText("Select an NPC")
            npcTitle:SetTextColor(1, 0.82, 0, 1)
            npcMeta:SetText("")
            return
        end
        viewer:SetCreature(npc.id)
        npcTitle:SetText(npc.name)
        -- Build a richer meta line: "Level 72 Humanoid - Hellfire Citadel".
        -- Falls back gracefully if level/type fields are absent (raids still
        -- get section - raid).
        local parts = {}
        if npc.level and npc.type then
            table.insert(parts, "Level " .. npc.level .. " " .. npc.type)
        elseif npc.level then
            table.insert(parts, "Level " .. npc.level)
        elseif npc.type then
            table.insert(parts, npc.type)
        end
        local locText
        if npc.section then
            locText = npc.section .. (npc.raid and (" - " .. npc.raid) or "")
        else
            for _, r in ipairs(L3F.raids) do
                if r.name == npc.raid then locText = r.location or r.name; break end
            end
            locText = locText or npc.raid or ""
        end
        if locText ~= "" then table.insert(parts, locText) end
        npcMeta:SetText(table.concat(parts, " - "))

        local sub = L3F.db.atlas.lastActiveSubTab
        if sub == "spells" then
            if npc.spells and #npc.spells > 0 then
                local y = 0
                for _, spellID in ipairs(npc.spells) do
                    local row = CreateFrame("Button", nil, subTabContent.body)
                    row:SetSize(420, 24)
                    row:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -y)
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(20, 20); icon:SetPoint("LEFT", row, "LEFT", 0, 0)
                    local name, _, tex = GetSpellInfo(spellID)
                    icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
                    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                    lbl:SetText(name or ("Spell #" .. spellID))
                    local idText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    idText:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
                    idText:SetText(tostring(spellID))
                    row:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(spellID) end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    y = y + 26
                end
                subTabContent.body:SetHeight(math.max(y, 1))
            else
                local txt = subTabContent.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                txt:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -4)
                txt:SetText("No notable abilities documented.")
            end

        elseif sub == "notes" then
            local txt = subTabContent.body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            txt:SetPoint("TOPLEFT",  subTabContent.body, "TOPLEFT",  4, -4)
            txt:SetPoint("TOPRIGHT", subTabContent.body, "TOPRIGHT", -4, -4)
            txt:SetJustifyH("LEFT"); txt:SetJustifyV("TOP")
            txt:SetText(npc.notes or "No strategy notes yet.")
            -- No SetWidth: anchors govern the FontString's width, so the
            -- text re-flows whenever the body width changes. Re-measure
            -- and re-set body height now AND on every subsequent resize
            -- via the onWidthChange callback the scroll runs from fitBody.
            local function relayoutNotes()
                subTabContent.body:SetHeight(math.max(txt:GetStringHeight() + 8, 1))
            end
            relayoutNotes()
            subTabContent.body.onWidthChange = relayoutNotes

        elseif sub == "drops" then
            if npc.drops and #npc.drops > 0 then
                -- Split into Normal / Heroic. Heroic-only entries (heroic
                -- dungeon bosses) ship without name + chance - GetItemInfo
                -- populates the name async; we hide the chance label entirely
                -- so we never display a misleading "0.0%".
                local normalDrops, heroicDrops = {}, {}
                for _, drop in ipairs(npc.drops) do
                    if drop.difficulty == "heroic" then
                        table.insert(heroicDrops, drop)
                    else
                        table.insert(normalDrops, drop)
                    end
                end

                local y = 0
                local function addHeader(label)
                    local h = subTabContent.body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    h:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -y)
                    h:SetText(label:upper())
                    y = y + 16
                end
                local function addDropRow(drop)
                    local row = CreateFrame("Button", nil, subTabContent.body)
                    row:SetSize(420, 24)
                    row:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -y)
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(20, 20); icon:SetPoint("LEFT", row, "LEFT", 0, 0)
                    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0); lbl:SetWidth(260); lbl:SetJustifyH("LEFT")
                    lbl:SetText(drop.name or ("Item #" .. drop.id))
                    queueItemUI(drop.id, lbl, icon)
                    -- Hide the chance label entirely when no confirmed % is
                    -- available (Heroic-mode rows, or any future entry that
                    -- ships without a chance field). Showing "0.0%" would be
                    -- misleading - the drop happens, we just don't have a
                    -- verified rate yet.
                    if drop.chance and drop.chance > 0 then
                        local chance = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                        chance:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
                        chance:SetText(string.format("%.1f%%", drop.chance))
                    end
                    row:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(drop.id)
                        else GameTooltip:SetHyperlink("item:" .. drop.id) end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    y = y + 24
                end

                if #heroicDrops > 0 and #normalDrops > 0 then
                    addHeader("Normal")
                    for _, d in ipairs(normalDrops) do addDropRow(d) end
                    y = y + 4
                    addHeader("Heroic")
                    for _, d in ipairs(heroicDrops) do addDropRow(d) end
                else
                    -- One mode only - no header needed (raid bosses or any
                    -- NPC without a heroic table).
                    for _, d in ipairs(normalDrops) do addDropRow(d) end
                    for _, d in ipairs(heroicDrops) do addDropRow(d) end
                end
                subTabContent.body:SetHeight(math.max(y, 1))
            else
                local txt = subTabContent.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                txt:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -4)
                txt:SetText("No drop table for this NPC.")
            end
        end
    end
end


-- =============================================================
-- ENTRY POINT
-- =============================================================
local function buildAtlas(parent)
    ensureState()
    -- Migration: "location" and "lore" sub-tabs were dropped in 0.13.0.
    -- Coerce any saved active key that no longer maps to a button so the
    -- detail pane lands on a real tab instead of falling through to nil.
    -- (Default-new-install sits on "drops" per the 0.13.1 reorder.)
    if not SUB_TAB_LABELS[L3F.db.atlas.lastActiveSubTab or ""] then
        L3F.db.atlas.lastActiveSubTab = "drops"
    end
    buildTreePane(parent)
    buildListPane(parent)
    buildDetailPane(parent)

    -- Collapse the tree the moment the user closes the main window. Per
    -- Morphéours: every category folds back so the next open lands on a
    -- tidy collapsed tree instead of whatever the user left expanded last
    -- time. Selection is preserved (the middle/detail panes still remember
    -- which Boss / Trash leaf the user picked) - only the expand state
    -- resets. Hook fires once per session; buildAtlas itself runs only
    -- once via RegisterTab's first-show.
    if L3F.mainFrame then
        L3F.mainFrame:HookScript("OnHide", function()
            if L3F.db and L3F.db.atlas and L3F.db.atlas.tree then
                L3F.db.atlas.tree.expanded = {}
            end
            -- Re-render the tree while it's hidden so the collapsed rows are
            -- ready the next time the user opens the window.
            if L3F.RefreshTree then L3F.RefreshTree() end
        end)
    end

    if L3F.db.atlas.lastSelectedNPC then
        currentNPC = L3F.npcLookup[L3F.db.atlas.lastSelectedNPC]
    end

    -- First session-build: expand the path down to the saved selection so
    -- the user sees their context. Subsequent open/close cycles wipe the
    -- expand state via the OnHide hook above, so this only fires the very
    -- first time the Atlas tab is built per session.
    local sel = L3F.db.atlas.selected
    if sel then
        if sel:sub(1, 12) == "raid-bosses:" or sel:sub(1, 11) == "raid-trash:" then
            setExpanded("cat:" .. CAT_RAIDS, true)
            local raidName = sel:match("^raid-bosses:(.+)$") or sel:match("^raid-trash:(.+)$")
            if raidName then setExpanded("raid:" .. raidName, true) end
        elseif sel:sub(1, 14) == "heroic-bosses:" or sel:sub(1, 13) == "heroic-trash:" then
            setExpanded("cat:" .. CAT_HEROICS, true)
            local heroicName = sel:match("^heroic-bosses:(.+)$") or sel:match("^heroic-trash:(.+)$")
            if heroicName then setExpanded("heroic:" .. heroicName, true) end
        elseif sel:sub(1, 15) == "consumable-cat:" then
            setExpanded("cat:" .. CAT_CONSUMABLES, true)
        elseif sel:sub(1, 6) == "bonus:" then
            -- bonus:<catKey>:<entryKey> - expand the matching top-level
            -- bonus category so the entry leaf is visible on first build.
            local catKey = sel:sub(7):match("^([^:]+):")
            if catKey then setExpanded("cat:bonus:" .. catKey, true) end
        end
    end

    L3F.RefreshTree()
    L3F.RefreshNPCList()
    L3F.RefreshDetailPane()
end

-- minWidth: 3-pane layout (tree 200 + list 200 + detail) where detail
-- itself is split into modelHost (240) + infoHost. The infoHost hosts
-- the sub-tab strip (Spells/Notes/Drops) and the strip leaves a 60px
-- buffer for the top-right L3F logo. The 3 sub-tab buttons clamp to
-- 40px each (3*40 + 4 gap*2 = 128 needed). Walking back: subStrip >= 128,
-- infoHost >= 188, detailPane >= 444, mainFrame >= 872. We keep 960 as
-- the floor so the buttons feel comfortable rather than crammed and so
-- existing saved window widths don't trigger an unexpected resize.
L3F.RegisterTab("atlas", "Atlas", nil, buildAtlas, { minWidth = 960 })
