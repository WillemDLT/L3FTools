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
local currentNPC, currentConsumable, currentBonusItem, currentVirtualBoss
local subTabButtons = {}
local consumableSubTabButtons = {}
local subTabContent
local consumableSubStrip
local viewer, npcTitle, npcMeta


-- =============================================================
-- ITEM INFO ASYNC CACHE  (icon + quality colour + name for item rows)
-- =============================================================
-- GetItemInfo is async: it returns nil for an uncached item, then the
-- data arrives via GET_ITEM_INFO_RECEIVED. Apply the texture/colour/name
-- immediately if cached, otherwise queue and reapply when the event
-- fires.
--
-- In TBC Classic 2.5.x GetItemInfo only triggers a server fetch in some
-- cases - the reliable cross-version pattern is to feed the ID through
-- a hidden GameTooltip via SetItemByID, which forces the client to
-- request the item from the server. We do that once per uncached ID.
local pendingItem = {}
local fetchedOnce = {}
local itemInfoFrame = CreateFrame("Frame")
itemInfoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

local fetchTooltip = CreateFrame("GameTooltip", "L3FAtlasFetchTooltip",
                                  nil, "GameTooltipTemplate")
fetchTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function forceItemFetch(itemID)
    if not itemID or fetchedOnce[itemID] then return end
    fetchedOnce[itemID] = true
    -- SetItemByID + Show makes the client cache the item server-side.
    -- AtlasLoot, Pawn, etc. all use this trick on Classic.
    fetchTooltip:SetItemByID(itemID)
    fetchTooltip:Show()
    fetchTooltip:Hide()
end

local function applyItemUI(itemID, label, icon)
    local cachedName, _, quality, _, _, _, _, _, _, tex = GetItemInfo(itemID)
    if label and cachedName then
        -- Only rewrite the label text when it's currently the "Item #N"
        -- placeholder. Baked names (e.g. raid drop "Boots of the Darkwalker"
        -- in Data/Drops/<Raid>.lua) must NOT be clobbered - quality colour
        -- still applies on top of the kept text.
        local cur = label:GetText() or ""
        if cur:sub(1, 6) == "Item #" or cur == "" then
            label:SetText(cachedName)
        end
        if quality then
            local r, g, b = GetItemQualityColor(quality)
            label:SetTextColor(r, g, b)
        end
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
    -- Trigger the server fetch on Classic where GetItemInfo alone won't.
    forceItemFetch(itemID)
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

    -- Boss-tree row. Used by raids that have a L3F.bossTrees[raid]
    -- definition (Morpheours-spec hierarchical Boss leaf). Renders a
    -- single row with optional expand-arrow + indent. Variants:
    --   - real NPC (opts.npc): row uses NPC name + gold colour, click
    --     selects + toggles expand if it has children.
    --   - virtual parent (opts.virtualEntry): no NPC, just a header.
    --     Click toggles expand; if the entry has itemIDs (Kael's
    --     Legendaries), click also sets it as the virtual selection.
    --   - sub-NPC (opts.npc with opts.indent): same as real NPC but
    --     indented and uses muted text colour.
    local function addBossTreeRow(opts, y)
        local rowH = 20
        local row = CreateFrame("Button", nil, npcList)
        local indent = opts.indent or 0
        row:SetSize(170 - indent, rowH)
        row:SetPoint("TOPLEFT", npcList, "TOPLEFT", indent, -y)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()

        local active = false
        if opts.npc and currentNPC and currentNPC.id == opts.npc.id then
            active = true
        elseif opts.virtualEntry and currentVirtualBoss == opts.virtualEntry then
            active = true
        end
        rbg:SetColorTexture(active and 0.30 or 0, active and 0.65 or 0,
            active and 1 or 0, active and 0.25 or 0)

        local textX = 4
        if opts.hasArrow then
            local arrow = row:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(10, 10)
            arrow:SetPoint("LEFT", row, "LEFT", 2, 0)
            arrow:SetTexture(opts.expanded
                and "Interface\\Buttons\\UI-MinusButton-Up"
                or  "Interface\\Buttons\\UI-PlusButton-Up")
            textX = 14
        end

        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("LEFT", row, "LEFT", textX, 0)
        txt:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        txt:SetJustifyH("LEFT"); txt:SetWordWrap(false)
        txt:SetText(opts.label)
        -- Colour: real boss = gold, virtual = soft blue, sub = grey.
        if opts.virtualEntry then
            txt:SetTextColor(active and 1 or 0.6,
                             active and 1 or 0.8,
                             active and 1 or 1.0, 1)
        elseif opts.isSub then
            txt:SetTextColor(active and 1 or 0.75,
                             active and 1 or 0.75,
                             active and 1 or 0.75, 1)
        else
            txt:SetTextColor(active and 1 or 1,
                             active and 1 or 0.82,
                             active and 1 or 0, 1)
        end

        row:SetScript("OnClick", opts.onClick)
        row:SetScript("OnEnter", function()
            if not active then rbg:SetColorTexture(1, 1, 1, 0.07) end
        end)
        row:SetScript("OnLeave", function()
            if active then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
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

    -- Item-SET row. PvP Season "Sets" sections (and any other AtlasLoot
    -- table flagged TableType = "IT:Set") use SET IDs, not item IDs:
    -- GetItemInfo can't resolve them. GetItemSetInfo is synchronous and
    -- returns the localized set name + the list of pieces.
    local function addBonusSetRow(setID, y)
        local rowH = 24
        local row = CreateFrame("Button", nil, npcList)
        row:SetSize(170, rowH)
        row:SetPoint("TOPLEFT", npcList, "TOPLEFT", 0, -y)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        local active = currentBonusItem and currentBonusItem.id == setID and currentBonusItem.kind == "set"
        rbg:SetColorTexture(active and 0.30 or 0, active and 0.65 or 0, active and 1 or 0, active and 0.25 or 0)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        -- Sets use a generic "armor set" looking icon since there's no
        -- single texture per set on the client side.
        icon:SetTexture("Interface\\Icons\\INV_Chest_Plate06")

        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        txt:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        txt:SetJustifyH("LEFT")
        txt:SetWordWrap(false)
        local setName = GetItemSetInfo and GetItemSetInfo(setID) or nil
        txt:SetText(setName or ("Set #" .. setID))
        -- Sets are always epic-tier in TBC PvP; use the epic purple so the
        -- row doesn't look like a generic placeholder.
        txt:SetTextColor(0.64, 0.21, 0.93)

        row:SetScript("OnClick", function()
            currentBonusItem = { id = setID, kind = "set" }
            currentNPC = nil
            currentConsumable = nil
            if L3F.RefreshNPCList then L3F.RefreshNPCList() end
            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
        end)
        row:SetScript("OnEnter", function(self)
            if not active then rbg:SetColorTexture(1, 1, 1, 0.07) end
            -- A set tooltip via GameTooltip:SetItemSet doesn't exist; use
            -- the manual hyperlink which renders the set summary correctly.
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("itemset:" .. setID)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if active then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
            else rbg:SetColorTexture(0, 0, 0, 0) end
            GameTooltip:Hide()
        end)
        return y + rowH + 2
    end

    -- Bonus-category item row. Same async icon+name pattern as the
    -- consumable rows, plus a click handler that prefers the cross-link
    -- (jump to a dropping NPC when L3F.itemLookup[id] resolves; otherwise
    -- show the bonus-item card in the detail pane).
    --
    -- `displayName` (optional) is the spreadsheet-authoritative name
    -- (Professions ships it on every row); we seed the label with it
    -- so the row is readable BEFORE GetItemInfo resolves. queueItemUI's
    -- applyItemUI only overwrites text that starts with "Item #" or is
    -- empty, so a pre-set canonical name is preserved while the quality
    -- colour + icon still apply asynchronously.
    -- `skill` (optional, >0) renders as a trailing "  (390)" hint so
    -- Profession rows show their required skill inline.
    local function addBonusItemRow(itemID, displayName, skill, y)
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
        local seedName = displayName or ("Item #" .. itemID)
        if skill and skill > 0 then
            txt:SetText(seedName .. "  (" .. skill .. ")")
        else
            txt:SetText(seedName)
        end
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

    -- Spell-kind bonus row. Every Professions section uses this
    -- renderer because Morpheours's spreadsheet stores recipe spell
    -- ids, not item ids.
    --
    -- Icon resolution (per Morpheours 0.19.0):
    --   1. L3F.professionRecipeMap[spellID]  -> result item id; render
    --      via GetItemInfo + queueItemUI so the row shows the RESULT
    --      item's icon (the player's mental model). This is the common
    --      path for crafted gear, flasks, potions, bars, etc.
    --   2. GetSpellTexture(spellID)          -> the spell's own icon.
    --      Used as fallback when the map has no entry, which is the
    --      case for Enchants / Disenchant / other recipes with no
    --      result-item product.
    --   3. Question-mark placeholder         -> ultimate fallback.
    --
    -- Tooltip is always the spell tooltip (SetSpellByID) - the recipe
    -- text with reagents is more useful than the result-item tooltip.
    -- No cross-link / click handler - recipes don't have NPC sources.
    local function addBonusSpellRow(spellID, displayName, skill, y)
        local rowH = 24
        local row = CreateFrame("Frame", nil, npcList)
        row:SetSize(170, rowH)
        row:SetPoint("TOPLEFT", npcList, "TOPLEFT", 0, -y)
        row:EnableMouse(true)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        rbg:SetColorTexture(0, 0, 0, 0)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)

        local resultItemID = L3F.professionRecipeMap
            and L3F.professionRecipeMap[spellID] or nil
        if resultItemID then
            -- Render the result item's icon. queueItemUI handles the
            -- GetItemInfo async cache; if it's already cached the icon
            -- applies synchronously, otherwise we fall back to a
            -- question mark until the GET_ITEM_INFO_RECEIVED event
            -- fires.
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            queueItemUI(resultItemID, nil, icon)
        else
            local tex = GetSpellTexture and GetSpellTexture(spellID) or nil
            icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        end

        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        txt:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        txt:SetJustifyH("LEFT")
        txt:SetWordWrap(false)
        local seed = displayName or ("Spell #" .. spellID)
        if skill and skill > 0 then
            txt:SetText(seed .. "  (" .. skill .. ")")
        else
            txt:SetText(seed)
        end
        -- Spells don't carry item-quality colour; render in a soft
        -- gold so they're visually distinct from regular items but
        -- still readable on the dark list background.
        txt:SetTextColor(0.95, 0.85, 0.50)

        row:SetScript("OnEnter", function(self)
            rbg:SetColorTexture(1, 1, 1, 0.07)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(spellID)
            else
                GameTooltip:SetHyperlink("spell:" .. spellID)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            rbg:SetColorTexture(0, 0, 0, 0)
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

        -- Bonus hits can be item-kind, set-kind, or spell-kind (the
        -- Professions recipes). Spell-kind needs different icon
        -- resolution + a SetSpellByID tooltip; cached separately so
        -- the click + hover handlers below can branch without
        -- re-reading hit.source.
        local bonusSrcKind = (hit.kind == "bonus") and hit.source
                             and (hit.source.kind or "item") or nil

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
                if bonusSrcKind == "spell" then
                    -- Mirror the in-tree Profession row's icon logic:
                    -- result item via L3F.professionRecipeMap, fall back
                    -- to GetSpellTexture, fall back to question mark.
                    local resultItemID = L3F.professionRecipeMap
                        and L3F.professionRecipeMap[hit.itemID] or nil
                    if resultItemID then
                        queueItemUI(resultItemID, nil, icon)
                    else
                        local tex = GetSpellTexture and GetSpellTexture(hit.itemID) or nil
                        if tex then icon:SetTexture(tex) end
                    end
                else
                    queueItemUI(hit.itemID, nil, icon)
                end
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
            if bonusSrcKind == "spell" then
                -- Recipe rows render in the same soft gold the in-tree
                -- Profession rows use - GetItemInfo would resolve the
                -- spell id as some unrelated item and recolour wrong.
                title:SetTextColor(0.95, 0.85, 0.50)
            else
                queueItemUI(hit.itemID, title, nil)
            end
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
                local srcKind = hit.source and hit.source.kind or "item"
                if srcKind == "spell" then
                    -- Recipe rows don't have NPC sources or a bonus-
                    -- item card. Navigate to the parent profession leaf
                    -- (e.g. "bonus:professions:Alchemy") so the player
                    -- lands on the full profession list with their
                    -- searched recipe visible inline. Clearing the
                    -- search box is required - otherwise RefreshNPCList
                    -- stays in search-results mode and the navigation
                    -- has no visible effect on the list pane.
                    if hit.source and hit.source.catKey and hit.source.entry then
                        L3F.db.atlas.selected = "bonus:" .. hit.source.catKey
                            .. ":" .. hit.source.entry.key
                    end
                    if searchBox then searchBox:SetText("") end
                    currentNPC = nil
                    currentConsumable = nil
                    currentBonusItem = nil
                    if L3F.RefreshTree then L3F.RefreshTree() end
                elseif srcKind == "item" and L3F.itemLookup
                       and L3F.itemLookup[hit.itemID]
                       and L3F.itemLookup[hit.itemID][1] then
                    -- Bonus item that's ALSO an NPC drop: jump to the
                    -- dropping NPC (the "where do I farm this" path is
                    -- usually more useful than "the vendor list it's in").
                    local link = L3F.itemLookup[hit.itemID][1]
                    currentNPC = link.npc
                    currentConsumable = nil
                    currentBonusItem = nil
                    L3F.db.atlas.lastSelectedNPC = link.npc.id
                    L3F.db.atlas.lastActiveSubTab = "drops"
                else
                    currentBonusItem = { id = hit.itemID, kind = srcKind }
                    currentNPC = nil
                    currentConsumable = nil
                end
            else
                currentNPC = hit.npc
                currentConsumable = nil
                currentBonusItem = nil
                L3F.db.atlas.lastSelectedNPC = hit.npc.id
                if hit.kind == "drop" then
                    L3F.db.atlas.lastActiveSubTab = "drops"
                elseif hit.kind == "spell" then
                    L3F.db.atlas.lastActiveSubTab = "spells"
                end
            end
            if L3F.RefreshNPCList then L3F.RefreshNPCList() end
            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
        end)
        row:SetScript("OnEnter", function(self)
            if not active then rbg:SetColorTexture(1, 1, 1, 0.07) end
            -- Hover tooltips on search rows: spell-bonus hits show the
            -- recipe via SetSpellByID so the player can preview without
            -- clicking through. Other kinds keep the existing
            -- background-only highlight (matches the rest of the list).
            if hit.kind == "bonus" and bonusSrcKind == "spell" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetSpellByID then
                    GameTooltip:SetSpellByID(hit.itemID)
                else
                    GameTooltip:SetHyperlink("spell:" .. hit.itemID)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            if active then rbg:SetColorTexture(0.30, 0.65, 1.0, 0.25)
            else rbg:SetColorTexture(0, 0, 0, 0) end
            if hit.kind == "bonus" and bonusSrcKind == "spell" then
                GameTooltip:Hide()
            end
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
                -- Each source-of-this-id may be item-kind, spell-kind, or
                -- set-kind. Spell-kind sources match on their stored
                -- `name` (the recipe name from Morpheours's spreadsheet);
                -- item-kind sources match on the GetItemInfo-cached name
                -- with the numeric-id fallback. Numeric search hits both
                -- ID spaces.
                local cachedName = GetItemInfo(itemID)
                for _, src in ipairs(sources) do
                    local srcKind = src.kind or "item"
                    local label, matched
                    if srcKind == "spell" then
                        label = src.name or ("Spell #" .. itemID)
                        matched = (numericSearch == itemID)
                              or  (src.name and src.name:lower():find(search, 1, true) ~= nil)
                    else
                        label = cachedName or src.name or ("Item #" .. itemID)
                        matched = (numericSearch == itemID)
                              or  (cachedName and cachedName:lower():find(search, 1, true) ~= nil)
                              or  (src.name and src.name:lower():find(search, 1, true) ~= nil)
                    end
                    if matched then
                        -- One hit per source so the user sees which list
                        -- the entry lives in (Honored from Cenarion
                        -- Expedition; Profession - Alchemy; etc.).
                        table.insert(hits, {
                            kind     = "bonus",
                            itemID   = itemID,
                            source   = src,
                            label    = label,
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

        -- Render a raid that has a Morpheours-spec boss tree
        -- (L3F.bossTrees[raid.name]). Top-level rows are real bosses
        -- or virtual containers (Servant Quarters, Opera Event: ...,
        -- Kael's Legendaries); their `subs` (or `itemIDs`) appear
        -- indented when the parent is expanded.
        local function renderBossTree(raid, tree)
            for _, parent in ipairs(tree) do
                local expandKey = "boss-tree:" .. raid.name .. ":" .. parent.name
                local expanded = isExpanded(expandKey)
                local hasChildren = (parent.subs and #parent.subs > 0)
                                 or (parent.itemIDs and #parent.itemIDs > 0)

                if parent.virtual then
                    -- Virtual parent: header only. Click toggles
                    -- expand; for itemIDs variants (Kael's
                    -- Legendaries), also set virtual selection.
                    y = addBossTreeRow({
                        label    = parent.name,
                        indent   = 0,
                        hasArrow = hasChildren,
                        expanded = expanded,
                        virtualEntry = parent,
                        onClick  = function()
                            if hasChildren then
                                setExpanded(expandKey, not expanded)
                            end
                            if parent.itemIDs then
                                currentVirtualBoss = parent
                                currentNPC        = nil
                                currentConsumable = nil
                                currentBonusItem  = nil
                            end
                            if L3F.RefreshNPCList   then L3F.RefreshNPCList()   end
                            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
                        end,
                    }, y)
                elseif parent.npcID then
                    local pNpc = L3F.npcLookup[parent.npcID]
                    if pNpc then
                        y = addBossTreeRow({
                            npc      = pNpc,
                            label    = parent.name or pNpc.name,
                            indent   = 0,
                            hasArrow = hasChildren,
                            expanded = expanded,
                            onClick  = function()
                                if hasChildren then
                                    setExpanded(expandKey, not expanded)
                                end
                                currentNPC        = pNpc
                                currentConsumable = nil
                                currentBonusItem  = nil
                                currentVirtualBoss = nil
                                L3F.db.atlas.lastSelectedNPC = pNpc.id
                                if L3F.RefreshNPCList   then L3F.RefreshNPCList()   end
                                if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
                            end,
                        }, y)
                    end
                end

                if expanded then
                    if parent.subs then
                        for _, sub in ipairs(parent.subs) do
                            if sub.npcID then
                                local sNpc = L3F.npcLookup[sub.npcID]
                                if sNpc then
                                    y = addBossTreeRow({
                                        npc      = sNpc,
                                        label    = sub.name or sNpc.name,
                                        indent   = 18,
                                        hasArrow = false,
                                        isSub    = true,
                                        onClick  = function()
                                            currentNPC        = sNpc
                                            currentConsumable = nil
                                            currentBonusItem  = nil
                                            currentVirtualBoss = nil
                                            L3F.db.atlas.lastSelectedNPC = sNpc.id
                                            if L3F.RefreshNPCList   then L3F.RefreshNPCList()   end
                                            if L3F.RefreshDetailPane then L3F.RefreshDetailPane() end
                                        end,
                                    }, y)
                                end
                            end
                        end
                    elseif parent.itemIDs then
                        -- Indented item rows (Kael's Legendaries).
                        -- Use addBonusItemRow for the icon-name-tooltip
                        -- treatment (re-used from bonus categories).
                        for _, itemID in ipairs(parent.itemIDs) do
                            y = addBonusItemRow(itemID, nil, nil, y)
                        end
                    end
                end
            end
        end

        -- Order matters: the longer-prefix keys must match before their
        -- shorter cousins (raid-bosses: starts with "raid", heroic-bosses:
        -- starts with "heroic").
        if sel:sub(1, 12) == "raid-bosses:" then
            local raid = findRaid(sel:sub(13))
            if raid then
                local tree = L3F.bossTrees and L3F.bossTrees[raid.name]
                if tree then
                    renderBossTree(raid, tree)
                else
                    renderOneSide(collectRoster(raid), true)
                end
            end

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
            -- Sections flagged kind = "set" route their IDs through the
            -- set renderer (PvP Season sets, etc.) since GetItemInfo can't
            -- resolve item-set IDs.
            local rest = sel:sub(7)
            local catKey, entryKey = rest:match("^([^:]+):(.+)$")
            local entry = catKey and entryKey
                and L3F.bonusLookup and L3F.bonusLookup[catKey]
                and L3F.bonusLookup[catKey][entryKey]
            if entry and entry.sections then
                for _, section in ipairs(entry.sections) do
                    if section.items and #section.items > 0 then
                        y = addBonusSectionHeader(section.name or "", y)
                        -- Section-level kind: "set" routes ALL rows to
                        -- the set renderer (PvP season sets etc.).
                        -- Otherwise we dispatch per-item, supporting
                        -- mixed item / spell sections (Professions ships
                        -- one section per profession with Enchant /
                        -- Smelt / Transmute rows flagged kind = "spell"
                        -- inline alongside crafted items).
                        local sectionKind = section.kind
                        for _, item in ipairs(section.items) do
                            if item.id then
                                if sectionKind == "set" then
                                    y = addBonusSetRow(item.id, y)
                                elseif (item.kind or sectionKind) == "spell" then
                                    y = addBonusSpellRow(item.id, item.name, item.skill, y)
                                else
                                    y = addBonusItemRow(item.id, item.name, item.skill, y)
                                end
                            end
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
        local virtual = currentVirtualBoss

        -- Hide the Drops sub-tab when a tree sub-entity is selected
        -- (per Morpheours: subs only show Spells + Notes). Auto-switch
        -- to Spells if the active tab was Drops, so the user isn't
        -- stuck on a hidden tab.
        local isSubEntity = npc and L3F.bossTreeIndex
                            and L3F.bossTreeIndex[npc.id]
                            and L3F.bossTreeIndex[npc.id].isSub
        if isSubEntity and L3F.db.atlas.lastActiveSubTab == "drops" then
            L3F.db.atlas.lastActiveSubTab = "spells"
        end

        for k, btn in pairs(subTabButtons) do
            local active = (k == L3F.db.atlas.lastActiveSubTab)
            btn.label:SetTextColor(active and 1 or 0.7, active and 1 or 0.7, active and 1 or 0.7, 1)
            if active then btn.underline:Show() else btn.underline:Hide() end
            if isSubEntity and k == "drops" then
                btn:Hide()
            else
                btn:Show()
            end
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

            local isSet = (bonus.kind == "set")
            if isSet then
                -- Set detail: synchronous GetItemSetInfo. Use a chest-armor
                -- icon as the universal "set" glyph since the client has no
                -- per-set icon for arbitrary sets.
                local setName = GetItemSetInfo and GetItemSetInfo(bonus.id)
                                  or ("Set #" .. bonus.id)
                detailPane.consumableIcon:SetTexture("Interface\\Icons\\INV_Chest_Plate06")
                npcTitle:SetText(setName)
                npcTitle:SetTextColor(0.64, 0.21, 0.93)  -- epic purple
            else
                local cachedName = GetItemInfo(bonus.id) or ("Item #" .. bonus.id)
                npcTitle:SetText(cachedName)
                npcTitle:SetTextColor(1, 1, 1, 1)
                queueItemUI(bonus.id, npcTitle, detailPane.consumableIcon)
            end

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

        -- ---------------------------------------------------------
        -- VIRTUAL-BOSS PATH - Morpheours-spec parents that aren't real
        -- NPCs but list items (Kael's Legendaries with its 7 P2
        -- weapons). Hide the 3D model, render only the Drops sub-tab
        -- with the item rows; Spells / Notes don't apply.
        -- ---------------------------------------------------------
        if virtual then
            viewer.frame:Hide()
            subStrip:Show()
            consumableSubStrip:Hide()
            detailPane.consumableIcon:Hide()
            npcTitle:SetText(virtual.name or "")
            npcTitle:SetTextColor(0.6, 0.85, 1.0, 1)
            npcMeta:SetText("")

            -- Only the Drops tab is meaningful here; force it active
            -- and hide the others.
            L3F.db.atlas.lastActiveSubTab = "drops"
            for k, btn in pairs(subTabButtons) do
                if k == "drops" then
                    btn:Show()
                    btn.label:SetTextColor(1, 1, 1, 1); btn.underline:Show()
                else
                    btn:Hide()
                end
            end

            local y = 0
            if virtual.itemIDs then
                for _, itemID in ipairs(virtual.itemIDs) do
                    local row = CreateFrame("Button", nil, subTabContent.body)
                    row:SetSize(420, 24)
                    row:SetPoint("TOPLEFT", subTabContent.body, "TOPLEFT", 4, -y)
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(20, 20); icon:SetPoint("LEFT", row, "LEFT", 0, 0)
                    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                    lbl:SetText("Item #" .. itemID)
                    queueItemUI(itemID, lbl, icon)
                    row:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(itemID)
                        else GameTooltip:SetHyperlink("item:" .. itemID) end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    y = y + 26
                end
            end
            subTabContent.body:SetHeight(math.max(y, 1))
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
            -- Aggregate drops from `npc` PLUS its sub-entities if this
            -- is a tree parent. Morpheours-spec: clicking Attumen
            -- shows Attumen's drops + Midnight's drops as one Drops
            -- view; clicking Midnight directly shows nothing (Drops
            -- tab is hidden for subs - handled at sub-tab level above).
            local effectiveDrops = npc.drops or {}
            local treeInfo = L3F.bossTreeIndex and L3F.bossTreeIndex[npc.id]
            if treeInfo and treeInfo.isParent and treeInfo.parentEntry
               and treeInfo.parentEntry.subs then
                local seen, agg = {}, {}
                for _, d in ipairs(effectiveDrops) do
                    table.insert(agg, d); seen[d.id] = true
                end
                for _, sub in ipairs(treeInfo.parentEntry.subs) do
                    if sub.npcID then
                        local sNpc = L3F.npcLookup[sub.npcID]
                        if sNpc and sNpc.drops then
                            for _, d in ipairs(sNpc.drops) do
                                if not seen[d.id] then
                                    table.insert(agg, d); seen[d.id] = true
                                end
                            end
                        end
                    end
                end
                effectiveDrops = agg
            end

            if #effectiveDrops > 0 then
                -- Split into Normal / Heroic. Heroic-only entries (heroic
                -- dungeon bosses) ship without name + chance - GetItemInfo
                -- populates the name async; we hide the chance label entirely
                -- so we never display a misleading "0.0%".
                local normalDrops, heroicDrops = {}, {}
                for _, drop in ipairs(effectiveDrops) do
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

    -- Trigger the server fetch for every bonus item ID we know about, so
    -- their names + icons populate the client cache before the user clicks
    -- a leaf. In TBC Classic 2.5.x GetItemInfo alone isn't enough; we feed
    -- the IDs through a hidden tooltip via forceItemFetch which calls
    -- GameTooltip:SetItemByID. Sets are skipped (GetItemSetInfo is sync
    -- and already returns the name without any server round-trip); spells
    -- are skipped too (they're not items - GetSpellTexture is sync). Fires
    -- exactly once per session (forceItemFetch dedupes via fetchedOnce).
    if L3F.bonusItemLookup then
        for itemID, sources in pairs(L3F.bonusItemLookup) do
            -- An ID might appear under multiple kinds (rare item/spell
            -- collision). Fetch if ANY source treats it as an item.
            local anyItem = false
            for _, s in ipairs(sources) do
                if (s.kind or "item") == "item" then anyItem = true; break end
            end
            if anyItem then forceItemFetch(itemID) end
        end
    end

    -- Warm the cache for Profession recipe RESULT items too. The
    -- recipe rows themselves are spell-kind (skipped above) but their
    -- icons come from result-item lookups via L3F.professionRecipeMap.
    -- Without this prefetch the icons would stay as question marks
    -- until the player hovered each row.
    if L3F.professionRecipeMap then
        for _, itemID in pairs(L3F.professionRecipeMap) do
            forceItemFetch(itemID)
        end
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
L3F.RegisterTab("atlas", "Atlas", nil, buildAtlas, {
    minWidth = 960,
    preferredWidth = 1000, preferredHeight = 640,
})
