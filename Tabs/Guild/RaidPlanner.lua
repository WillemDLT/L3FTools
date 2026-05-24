-- =============================================================
-- L3FTools - Tabs/Guild/RaidPlanner.lua
-- =============================================================
-- Raid-planner canvas modelled on raidplan.io. Per-encounter plans
-- with multiple numbered pages, background image, drag-drop icon
-- palette (raid marks + roles + classes), freehand pen drawings,
-- placed-icon properties (text/color/variant), and an L3F2 share
-- string for handing the plan to other guildies. All state lives
-- in L3F.db.raidPlanner so reloads keep what was on screen.
-- =============================================================

local addonName, L3F = ...


-- =============================================================
-- 1. ICON PALETTES
-- =============================================================
-- The palette groups. Each entry carries an
-- internal `key` (also stored in savedvars), the display texture, an
-- optional `tooltip`, and per-group flags. Variants are sibling
-- entries that share the parent's `key` family (`feralbear` is the
-- bear-form variant of `feral`, etc.); the Properties panel offers
-- them as a swap-in-place toggle on a placed icon.

-- The 8 raid-target marks - built-in client textures.
local MARKS = {
    { key = "mark1", label = "Star",     tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
    { key = "mark2", label = "Circle",   tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
    { key = "mark3", label = "Diamond",  tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
    { key = "mark4", label = "Triangle", tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
    { key = "mark5", label = "Moon",     tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
    { key = "mark6", label = "Square",   tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
    { key = "mark7", label = "Cross",    tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
    { key = "mark8", label = "Skull",    tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
}

-- Role icons (tank / healer / melee dps / ranged dps).
-- Uses the Blizzard LFG role-sheet so the palette matches the
-- rounded icons style from the Raid Planner mockups.
local ROLE_SHEET = "Interface\\AddOns\\L3FTools\\Media\\RaidPlanner\\role-icons-agent.png"
local ROLES = {
    -- Inset each quadrant so role circles render larger (closer to raid mark "Circle" visual size).
    { key = "tank",   label = "Tank",       tex = ROLE_SHEET, tc = { 0.065, 0.435, 0.065, 0.435 } },
    { key = "heal",   label = "Healer",     tex = ROLE_SHEET, tc = { 0.565, 0.935, 0.065, 0.435 } },
    { key = "melee",  label = "Melee DPS",  tex = ROLE_SHEET, tc = { 0.065, 0.435, 0.565, 0.935 } },
    { key = "ranged", label = "Ranged DPS", tex = ROLE_SHEET, tc = { 0.565, 0.935, 0.565, 0.935 } },
}

-- TBC classes. The Properties panel surfaces alternative form icons
-- via `variants` for classes that have a clear secondary identity in
-- TBC (Druid's 4 forms). All other classes have a single texture.
local CLASS_ICON_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASSES = {
    { key = "druid",   label = "Druid",   tex = CLASS_ICON_SHEET, tc = "DRUID",
      variants = {
        { key = "cat",     label = "Cat",     tex = "Interface\\Icons\\Ability_Druid_CatForm" },
        { key = "bear",    label = "Bear",    tex = "Interface\\Icons\\Ability_Racial_BearForm" },
        { key = "tree",    label = "Tree",    tex = "Interface\\Icons\\Ability_Druid_TreeofLife" },
        { key = "moonkin", label = "Moonkin", tex = "Interface\\Icons\\Spell_Nature_ForceOfNature" },
      } },
    { key = "hunter",  label = "Hunter",  tex = CLASS_ICON_SHEET, tc = "HUNTER" },
    { key = "mage",    label = "Mage",    tex = CLASS_ICON_SHEET, tc = "MAGE" },
    { key = "paladin", label = "Paladin", tex = CLASS_ICON_SHEET, tc = "PALADIN" },
    { key = "priest",  label = "Priest",  tex = CLASS_ICON_SHEET, tc = "PRIEST" },
    { key = "rogue",   label = "Rogue",   tex = CLASS_ICON_SHEET, tc = "ROGUE" },
    { key = "shaman",  label = "Shaman",  tex = CLASS_ICON_SHEET, tc = "SHAMAN" },
    { key = "warlock", label = "Warlock", tex = CLASS_ICON_SHEET, tc = "WARLOCK" },
    { key = "warrior", label = "Warrior", tex = CLASS_ICON_SHEET, tc = "WARRIOR" },
}

-- Reverse lookup: any palette key (mark / role / class / encounter / class-variant)
-- -> the texture. Populated lazily because variant sub-tables nest
-- and we want all palette families in one map for the canvas
-- renderer.
local KEY_TO_TEX = {}
local KEY_TO_LABEL = {}
local KEY_TO_TEXCOORD = {}
local DEFAULT_ICON_TC = { 0.07, 0.93, 0.07, 0.93 }
local function applyIconTexCoord(tex, tc)
    if type(tc) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[tc] then
        tc = CLASS_ICON_TCOORDS[tc]
    end
    if tc and tc[1] and tc[2] and tc[3] and tc[4] then
        tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        tex:SetTexCoord(DEFAULT_ICON_TC[1], DEFAULT_ICON_TC[2], DEFAULT_ICON_TC[3], DEFAULT_ICON_TC[4])
    end
end
local function buildPaletteIndex()
    if next(KEY_TO_TEX) then return end
    for _, m in ipairs(MARKS) do
        KEY_TO_TEX[m.key], KEY_TO_LABEL[m.key], KEY_TO_TEXCOORD[m.key] = m.tex, m.label, m.tc
    end
    for _, r in ipairs(ROLES) do
        KEY_TO_TEX[r.key], KEY_TO_LABEL[r.key], KEY_TO_TEXCOORD[r.key] = r.tex, r.label, r.tc
    end
    for _, c in ipairs(CLASSES) do
        KEY_TO_TEX[c.key], KEY_TO_LABEL[c.key], KEY_TO_TEXCOORD[c.key] = c.tex, c.label, c.tc
        for _, v in ipairs(c.variants or {}) do
            -- Variant keys are namespaced "<class>:<variant>" so two
            -- classes can share a variant name without collision.
            local vk = c.key .. ":" .. v.key
            KEY_TO_TEX[vk], KEY_TO_LABEL[vk], KEY_TO_TEXCOORD[vk] =
                v.tex, c.label .. " (" .. v.label .. ")", v.tc
        end
    end
    for _, entries in pairs(L3F.RPEncounterIcons or {}) do
        for _, e in ipairs(entries) do
            KEY_TO_TEX[e.key], KEY_TO_LABEL[e.key], KEY_TO_TEXCOORD[e.key] = e.tex, e.label, e.tc
        end
    end
end

local function isEncounterPaletteIcon(entry)
    local key = entry and entry.key
    return key == "rpenc_gateway" or (key and string.find(key, "_npc_", 1, true))
end

-- Class -> variants[] lookup (Properties panel uses this to show the
-- variant swatches on a selected class icon).
local CLASS_VARIANTS = {}
for _, c in ipairs(CLASSES) do
    if c.variants then CLASS_VARIANTS[c.key] = c.variants end
end


-- =============================================================
-- 2. STATE / PLANS
-- =============================================================
-- L3F.db.raidPlanner state shape:
--   activeEncounter  = "Magtheridon"
--   activePlanIdx    = integer (1..#plans for activeEncounter)
--   plansByEncounter = {
--       ["Magtheridon"] = {
--           {
--               name        = "Phase 1",
--               background  = "magtheridon-wide",
--               icons       = { { kind, key, x, y, color, text, variant, locked }, ... },
--               drawings    = { { color, size, fade, points = {{x,y}, ...} }, ... },
--               notes       = "free text",
--           },
--           ...
--       },
--   }
-- `x, y` are stored as 0..1 fractional coordinates relative to the
-- canvas so resizing the addon window preserves layout.

local function ensureState()
    L3F.db.raidPlanner = L3F.db.raidPlanner or {}
    local rp = L3F.db.raidPlanner
    rp.plansByEncounter = rp.plansByEncounter or {}
    if rp.activeEncounter == nil then
        -- Default to the first encounter in the catalog.
        local cat = L3F.raidPlannerCatalog
        if cat and cat[1] and cat[1].encounters and cat[1].encounters[1] then
            rp.activeEncounter = cat[1].encounters[1].name
        end
    end
    rp.activePlanIdx = rp.activePlanIdx or 1
end

local function activePlannerState()
    if L3F.RPCoOp and L3F.RPCoOp.GetPlannerState then
        local coOpState = L3F.RPCoOp.GetPlannerState()
        if coOpState then
            ensureState()
            coOpState.plansByEncounter = coOpState.plansByEncounter or {}
            coOpState.activeEncounter = coOpState.activeEncounter
                or L3F.db.raidPlanner.activeEncounter
            coOpState.activePlanIdx = coOpState.activePlanIdx or 1
            return coOpState
        end
    end
    ensureState()
    return L3F.db.raidPlanner
end

local function usingCoOpPlannerState()
    return L3F.RPCoOp
        and L3F.RPCoOp.GetPlannerState
        and L3F.RPCoOp.GetPlannerState() ~= nil
end

local function isCoOpGuest()
    return usingCoOpPlannerState()
end

local function findCatalogEncounter(name)
    for _, raid in ipairs(L3F.raidPlannerCatalog or {}) do
        for _, enc in ipairs(raid.encounters) do
            if enc.name == name then return enc, raid end
        end
    end
end

local function normalizeRaidName(name)
    return tostring(name or ""):lower():gsub("[%s%p]", "")
end
local function normalizeKey(name)
    return tostring(name or ""):lower():gsub("[%s%p]", "")
end

local raidCatalogByNormName
local function raidCatalogIndexByName()
    if raidCatalogByNormName then return raidCatalogByNormName end
    local idx = {}
    for _, raid in ipairs(L3F.raidPlannerCatalog or {}) do
        idx[normalizeRaidName(raid.raid)] = raid
    end
    local function alias(aliasName, canonicalName)
        local canonical = idx[normalizeRaidName(canonicalName)]
        if canonical then
            idx[normalizeRaidName(aliasName)] = canonical
        end
    end
    alias("Tempest Keep", "The Eye: Tempest Keep")
    alias("The Eye", "The Eye: Tempest Keep")
    alias("Hyjal Summit", "Battle for Mount Hyjal")
    alias("Mount Hyjal", "Battle for Mount Hyjal")
    raidCatalogByNormName = idx
    return raidCatalogByNormName
end

local function currentInstanceRaidCatalog()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "raid" then return nil end
    local idx = raidCatalogIndexByName()
    local names = {
        GetInstanceInfo(),
        (GetRealZoneText and GetRealZoneText()) or "",
        (GetSubZoneText and GetSubZoneText()) or "",
    }
    for _, rawName in ipairs(names) do
        local key = normalizeRaidName(rawName)
        if key ~= "" then
            local direct = idx[key]
            if direct then return direct end
            for raidKey, raid in pairs(idx) do
                if raidKey and raid
                   and (string.find(key, raidKey, 1, true)
                        or string.find(raidKey, key, 1, true)) then
                    return raid
                end
            end
        end
    end
    return nil
end

local function syncEncounterToInstanceRaid()
    if usingCoOpPlannerState() then return false end
    local rp = L3F.db and L3F.db.raidPlanner
    if not rp then return false end
    local raid = currentInstanceRaidCatalog()
    if not raid or not raid.encounters or not raid.encounters[1] then return false end
    local _, activeRaid = findCatalogEncounter(rp.activeEncounter)
    if activeRaid == raid then return false end
    rp.activeEncounter = raid.encounters[1].name
    rp.activePlanIdx = 1
    return true
end

local function newEmptyPlan(encounterName)
    local enc = findCatalogEncounter(encounterName)
    local defaultBg = enc and enc.backgrounds[1] and enc.backgrounds[1].slug or nil
    return {
        name       = "Plan",
        background = defaultBg,
        icons      = {},
        drawings   = {},
        notes      = "",
    }
end

local function ensurePlansFor(encounterName)
    local rp = activePlannerState()
    rp.plansByEncounter[encounterName] = rp.plansByEncounter[encounterName] or {}
    if #rp.plansByEncounter[encounterName] == 0 then
        table.insert(rp.plansByEncounter[encounterName], newEmptyPlan(encounterName))
    end
    return rp.plansByEncounter[encounterName]
end

local function currentPlan()
    local rp = activePlannerState()
    local plans = ensurePlansFor(rp.activeEncounter)
    rp.activePlanIdx = math.max(1, math.min(#plans, rp.activePlanIdx or 1))
    return plans[rp.activePlanIdx], plans
end


-- =============================================================
-- 3. CONSTANTS / LAYOUT
-- =============================================================
local LEFT_W = 64
local RIGHT_W = 240
local TOP_H = 88
local PALETTE_ICON = 26
local PLACED_DEFAULT_SIZE = 32
local QUILL = "Interface\\Icons\\INV_Feather_07"

local function bgTexture(slug)
    return "Interface\\AddOns\\L3FTools\\Media\\RaidPlanner\\" .. slug
end

-- Wraps `refresh()` in a single-shot per-frame schedule. Why: many
-- refresh() callers run inside WoW event callbacks (OnDragStop,
-- OnClick, picker callbacks). refresh() destroys + rebuilds the
-- palette + props + canvas, which can synchronously orphan the
-- callback's own enclosing frame. In 0.20.1 this manifested as a
-- 263x stack overflow when palette OnDragStop's refresh() tore down
-- a palette button while that button's closure was still on the
-- stack. C_Timer.After(0, ...) defers to the NEXT frame, so the
-- current event callback finishes before refresh runs.
local refresh  -- forward decl

-- Co-op delta hook. No-op when the co-op module isn't loaded OR when
-- there's no active session OR when we're mid-apply of a remote delta
-- (BroadcastDelta itself guards against the last). Wired into every
-- local mutation site below.
local function notifyEdit(deltaType, fields, opts)
    if L3F.RPCoOp and L3F.RPCoOp.BroadcastDelta then
        L3F.RPCoOp.BroadcastDelta(deltaType, fields, opts)
    end
end
local refreshScheduled = false
local function scheduleRefresh()
    if refreshScheduled then return end
    refreshScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            refreshScheduled = false
            if refresh then refresh() end
        end)
    else
        refreshScheduled = false
        if refresh then refresh() end
    end
end

-- Module-level frame for the live picker poller. ONE per addon;
-- re-wired each openColorPicker call. Lives outside the function
-- because Lua 5.1 functions can't carry indexable fields (`f.x = y`
-- throws "attempt to index a function value") -- the 0.23.1 attempt
-- stored the poller on openColorPicker itself and silently errored
-- on every invocation, which is why pen color still drew white.
local colorPickerPoller

-- Opens the WoW client's built-in color picker via the canonical
-- OpenColorPicker(info) Blizzard helper. `initialHex` is six
-- lowercase hex chars (no '#'); `onAccept(hex)` is called as the
-- user drags the picker AND on cancel (cancel restores the
-- previous values). The helper writes `previousValues = {r=r,
-- g=g, b=b, opacity=op}` for us, so cancelFunc can read by key.
local function openColorPicker(initialHex, onAccept)
    initialHex = (initialHex and #initialHex == 6) and initialHex or "ffffff"
    local r = tonumber(initialHex:sub(1, 2), 16) / 255
    local g = tonumber(initialHex:sub(3, 4), 16) / 255
    local b = tonumber(initialHex:sub(5, 6), 16) / 255

    local function rgbToHex(nr, ng, nb)
        return string.format("%02x%02x%02x",
            math.floor((nr or 1) * 255 + 0.5),
            math.floor((ng or 1) * 255 + 0.5),
            math.floor((nb or 1) * 255 + 0.5))
    end

    -- Accept the color from EITHER the callback's positional args
    -- (some TBC 2.5.x builds pass r,g,b directly to swatchFunc) OR
    -- from ColorPickerFrame:GetColorRGB(). On builds where neither
    -- is reliable in the swatchFunc context (the original bug), the
    -- OnUpdate poller below catches the change.
    local function applyFromCallback(arg1, arg2, arg3)
        local cr, cg, cb
        if type(arg1) == "number" then
            cr, cg, cb = arg1, arg2, arg3
        elseif type(arg1) == "table" then
            cr, cg, cb = arg1.r, arg1.g, arg1.b
        end
        if not (cr and cg and cb) then
            cr, cg, cb = ColorPickerFrame:GetColorRGB()
        end
        if cr and cg and cb then
            onAccept(rgbToHex(cr, cg, cb))
        end
    end

    -- Use OpenColorPicker when available (TBC 2.5.x has it); fall
    -- back to the field-set + :Show() pattern as a safety net.
    local info = {
        r = r, g = g, b = b,
        hasOpacity = false,
        swatchFunc = applyFromCallback,
        cancelFunc = function(prev)
            if type(prev) == "table" and prev.r then
                onAccept(rgbToHex(prev.r, prev.g, prev.b))
            elseif type(prev) == "table" and prev[1] then
                onAccept(rgbToHex(prev[1], prev[2], prev[3]))
            else
                onAccept(initialHex)
            end
        end,
    }
    -- Some client builds call ColorPickerFrame.swatchFunc from the
    -- OK button path even when opened via OpenColorPicker(info).
    if ColorPickerFrame then
        ColorPickerFrame.swatchFunc = info.swatchFunc
        ColorPickerFrame.cancelFunc = info.cancelFunc
    end
    if type(OpenColorPicker) == "function" then
        OpenColorPicker(info)
    elseif ColorPickerFrame then
        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.opacity = 1
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        -- Client compatibility: some builds invoke swatchFunc
        -- directly from the OK button handler.
        ColorPickerFrame.swatchFunc = info.swatchFunc
        ColorPickerFrame.func = info.swatchFunc
        ColorPickerFrame.opacityFunc = info.swatchFunc
        ColorPickerFrame.cancelFunc = info.cancelFunc
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Show()
    end

    -- Live poller fallback. The TBC 2.5.x ColorPickerFrame slider
    -- callback (swatchFunc / func) is unreliable on this build:
    -- ColorPickerFrame:GetColorRGB() can return nil during the
    -- callback, and with rgbToHex's defensive `(nr or 1)` defaults
    -- that silently produces "ffffff" -- pen strokes draw white
    -- after picking any color. Polling the picker's live RGB on
    -- OnUpdate while it's visible bypasses the broken callback.
    -- The poller self-detaches on close. The original
    -- swatchFunc/cancelFunc remain wired for the Cancel-restore path.
    if ColorPickerFrame then
        if not colorPickerPoller then
            colorPickerPoller = CreateFrame("Frame")
        end
        local lastHex = initialHex
        colorPickerPoller:SetScript("OnUpdate", function(self)
            if not ColorPickerFrame:IsShown() then
                self:SetScript("OnUpdate", nil)
                return
            end
            local pr, pg, pb = ColorPickerFrame:GetColorRGB()
            if pr and pg and pb then
                local hex = rgbToHex(pr, pg, pb)
                if hex ~= lastHex then
                    lastHex = hex
                    onAccept(hex)
                end
            end
        end)
    end
end


-- =============================================================
-- 4. DRAG-DROP MACHINERY
-- =============================================================
-- Coord-based-hit-test pattern from Composer
-- (see [[reference-classic-custom-drag]]). The canvas is a single
-- Frame and placed icons are children whose absolute position is
-- computed from their stored 0..1 fractional coords.

-- `refresh` is forward-declared at the top of the file (right above
-- scheduleRefresh) so scheduleRefresh's closure captures it. Re-
-- declaring `local refresh` here would SHADOW that upvalue and the
-- deferred refresh would never fire. Only declare the other forwards here.
local selectIcon, deselect, openContextMenu, openDrawingContextMenu, broadcastIconProps

local dragState = { active = false }

local follower = CreateFrame("Frame", "L3FRPDragFollower", UIParent)
follower:SetSize(PLACED_DEFAULT_SIZE, PLACED_DEFAULT_SIZE)
follower:SetFrameStrata("TOOLTIP")
follower:EnableMouse(false)
follower:Hide()
local followerTex = follower:CreateTexture(nil, "OVERLAY")
followerTex:SetAllPoints()
applyIconTexCoord(followerTex)

local dragDriver = CreateFrame("Frame")
dragDriver:SetScript("OnUpdate", function()
    if not (dragState.active and follower:IsShown()) then return end
    local x, y = GetCursorPosition()
    local s = follower:GetEffectiveScale()
    follower:ClearAllPoints()
    follower:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
end)


-- =============================================================
-- 5. UI HOSTS (forward decls)
-- =============================================================
local canvasFrame, canvasBg, placedHost, drawingHost
local refreshIcons, refreshDrawings, refreshTopStrip
local refreshPalette, refreshPropsPanel, refreshEncounterPanel
local refreshSearchPanel, refreshNotesPanel
local drawingSegments = {}
local currentSelection
local leftClearPlanBtn, undoBtn, redoBtn

local plannerHistory = (function()
    local H = {}
    local undoStack, redoStack = {}, {}
    local HISTORY_LIMIT = 50

    local function copyIconData(icon)
        if not icon then return nil end
        local out = {}
        for k, v in pairs(icon) do
            out[k] = v
        end
        return out
    end

    local function copyStrokeData(stroke)
        if not stroke then return nil end
        local out = {
            color  = stroke.color,
            size   = stroke.size,
            fade   = stroke.fade,
            points = {},
        }
        for i, p in ipairs(stroke.points or {}) do
            out.points[i] = { x = p.x, y = p.y }
        end
        return out
    end

    local function copyIconList(icons)
        local out = {}
        for i, icon in ipairs(icons or {}) do
            out[i] = copyIconData(icon)
        end
        return out
    end

    local function copyDrawingList(drawings)
        local out = {}
        for i, stroke in ipairs(drawings or {}) do
            out[i] = copyStrokeData(stroke)
        end
        return out
    end

    local function copyPlanVisualState(plan)
        return {
            icons = copyIconList(plan and plan.icons),
            drawings = copyDrawingList(plan and plan.drawings),
        }
    end

    local function restoreDrawingList(plan, drawings)
        if not plan then return end
        plan.drawings = copyDrawingList(drawings)
    end

    local function restorePlanVisualState(plan, state)
        if not plan then return end
        state = state or {}
        plan.icons = copyIconList(state.icons)
        restoreDrawingList(plan, state.drawings)
    end

    local function visualStateHasContent(state)
        return state
            and ((state.icons and #state.icons > 0)
                or (state.drawings and #state.drawings > 0))
    end

    local function planHasVisualContent(plan)
        return plan
            and ((plan.icons and #plan.icons > 0)
                or (plan.drawings and #plan.drawings > 0))
    end

    local function clearRedo()
        for i = #redoStack, 1, -1 do
            redoStack[i] = nil
        end
    end

    local function findIconRefIndex(plan, iconRef)
        if not plan or not iconRef then return nil end
        for i, icon in ipairs(plan.icons or {}) do
            if icon == iconRef then return i end
        end
        return nil
    end

    local function findStrokeRefIndex(plan, strokeRef)
        if not plan or not strokeRef then return nil end
        for i, stroke in ipairs(plan.drawings or {}) do
            if stroke == strokeRef then return i end
        end
        return nil
    end

    local function broadcastIconPlacement(icon)
        if not icon then return end
        notifyEdit("PLACE", {
            icon.kind or "", icon.key or "",
            string.format("%.4f", icon.x or 0.5),
            string.format("%.4f", icon.y or 0.5),
            icon.color or "ffffff", icon.text or "",
            icon.variant or "", icon.locked and "1" or "0",
            tostring(icon.direction or ""),
        })
    end

    local function broadcastStrokePlacement(stroke)
        if not stroke or not stroke.points or #stroke.points < 2 then return end
        local pts = {}
        for _, p in ipairs(stroke.points) do
            table.insert(pts, string.format("%.3f,%.3f", p.x, p.y))
        end
        notifyEdit("DRAW", {
            stroke.color or "ffffff",
            tostring(stroke.size or 4),
            tostring(stroke.fade or 0),
            table.concat(pts, "/"),
        })
    end

    local function broadcastDrawingState(drawings)
        notifyEdit("PEN_CLEAR", {})
        for _, stroke in ipairs(drawings or {}) do
            broadcastStrokePlacement(stroke)
        end
    end

    local function broadcastPlanVisualState(state)
        notifyEdit("CLEAR", {})
        for _, icon in ipairs((state and state.icons) or {}) do
            broadcastIconPlacement(icon)
        end
        for _, stroke in ipairs((state and state.drawings) or {}) do
            broadcastStrokePlacement(stroke)
        end
    end

    local function currentPlanMatches(planRef)
        local plan = currentPlan()
        return plan and plan == planRef
    end

    local function canUndoRecordedAction(action, plan)
        if not (action and plan and plan == action.planRef) then return false end
        if action.type == "place" then
            return findIconRefIndex(plan, action.iconRef) ~= nil
        elseif action.type == "draw" then
            return findStrokeRefIndex(plan, action.strokeRef) ~= nil
        elseif action.type == "removeDraw" then
            return action.stroke ~= nil
        elseif action.type == "clear" then
            return visualStateHasContent(action.before)
        elseif action.type == "penClear" then
            return action.before and #action.before > 0
        end
        return false
    end

    local function fallbackUndoTarget(plan)
        if not plan then return nil end
        if currentSelection and plan.icons and plan.icons[currentSelection] then
            return { type = "place", idx = currentSelection }
        end
        if plan.drawings and #plan.drawings > 0 then
            return { type = "draw", idx = #plan.drawings }
        end
        if plan.icons and #plan.icons > 0 then
            return { type = "place", idx = #plan.icons }
        end
        return nil
    end

    local function canUndoPlannerAction()
        local plan = currentPlan()
        if not plan then return false end
        if canUndoRecordedAction(undoStack[#undoStack], plan) then
            return true
        end
        return fallbackUndoTarget(plan) ~= nil
    end

    local function canRedoPlannerAction()
        local action = redoStack[#redoStack]
        return action and currentPlanMatches(action.planRef)
    end

    function H.refreshButtons()
        if undoBtn then
            local enabled = canUndoPlannerAction()
            if enabled then undoBtn:Enable() else undoBtn:Disable() end
            undoBtn:SetAlpha(enabled and 1 or 0.35)
        end
        if redoBtn then
            local enabled = canRedoPlannerAction()
            if enabled then redoBtn:Enable() else redoBtn:Disable() end
            redoBtn:SetAlpha(enabled and 1 or 0.35)
        end
    end

    local function trimUndo()
        while #undoStack > HISTORY_LIMIT do
            table.remove(undoStack, 1)
        end
    end

    local function pushRedo(action)
        if not action then return end
        table.insert(redoStack, action)
        while #redoStack > HISTORY_LIMIT do
            table.remove(redoStack, 1)
        end
        H.refreshButtons()
    end

    local function pushUndo(action, preserveRedo)
        if not action then return end
        table.insert(undoStack, action)
        trimUndo()
        if not preserveRedo then clearRedo() end
        H.refreshButtons()
    end

    function H.clear()
        for i = #undoStack, 1, -1 do
            undoStack[i] = nil
        end
        clearRedo()
        H.refreshButtons()
    end

    function H.currentPlanMatches(planRef)
        return currentPlanMatches(planRef)
    end

    function H.findStrokeRefIndex(plan, strokeRef)
        return findStrokeRefIndex(plan, strokeRef)
    end

    function H.broadcastStrokePlacement(stroke)
        broadcastStrokePlacement(stroke)
    end

    function H.broadcastIconPlacement(icon)
        broadcastIconPlacement(icon)
    end

    function H.recordIconPlacement(plan, iconRef)
        if not (plan and iconRef) then return end
        pushUndo({ type = "place", planRef = plan, iconRef = iconRef })
    end

    function H.recordStrokePlacement(plan, strokeRef)
        if not (plan and strokeRef and strokeRef.points and #strokeRef.points >= 2) then return end
        pushUndo({ type = "draw", planRef = plan, strokeRef = strokeRef })
    end

    function H.recordDrawingRemoval(plan, stroke, idx)
        local strokeCopy = copyStrokeData(stroke)
        if not (plan and strokeCopy) then return end
        pushUndo({ type = "removeDraw", planRef = plan, stroke = strokeCopy, index = idx })
    end

    function H.recordClearPlan(plan)
        if not planHasVisualContent(plan) then return end
        pushUndo({
            type = "clear",
            planRef = plan,
            before = copyPlanVisualState(plan),
            after = { icons = {}, drawings = {} },
        })
    end

    function H.recordPenClear(plan)
        if not (plan and plan.drawings and #plan.drawings > 0) then return end
        pushUndo({
            type = "penClear",
            planRef = plan,
            before = copyDrawingList(plan.drawings),
            after = {},
        })
    end

    function H.undo()
        local action = undoStack[#undoStack]
        local plan = currentPlan()
        if not plan then return end

        if canUndoRecordedAction(action, plan) then
            if action.type == "place" then
                local idx = findIconRefIndex(plan, action.iconRef)
                local removed = copyIconData(plan.icons[idx])
                table.remove(undoStack)
                table.remove(plan.icons, idx)
                pushRedo({ type = "place", planRef = plan, icon = removed })
                currentSelection = nil
                notifyEdit("RM", { tostring(idx) })
                scheduleRefresh()
                return
            elseif action.type == "draw" then
                local idx = findStrokeRefIndex(plan, action.strokeRef)
                local removed = copyStrokeData(plan.drawings[idx])
                table.remove(undoStack)
                table.remove(plan.drawings, idx)
                pushRedo({ type = "draw", planRef = plan, stroke = removed })
                notifyEdit("RMDRAW", { tostring(idx) })
                scheduleRefresh()
                return
            elseif action.type == "removeDraw" then
                local restored = copyStrokeData(action.stroke)
                if not restored then return end
                plan.drawings = plan.drawings or {}
                local idx = action.index or (#plan.drawings + 1)
                if idx < 1 then idx = 1 end
                if idx > #plan.drawings + 1 then idx = #plan.drawings + 1 end
                table.remove(undoStack)
                table.insert(plan.drawings, idx, restored)
                pushRedo({
                    type = "removeDraw",
                    planRef = plan,
                    stroke = copyStrokeData(restored),
                    strokeRef = restored,
                    index = idx,
                })
                broadcastDrawingState(plan.drawings)
                scheduleRefresh()
                return
            elseif action.type == "clear" then
                local before = copyPlanVisualState(action.before)
                local after = copyPlanVisualState(plan)
                table.remove(undoStack)
                restorePlanVisualState(plan, before)
                pushRedo({ type = "clear", planRef = plan, before = before, after = after })
                currentSelection = nil
                broadcastPlanVisualState(before)
                scheduleRefresh()
                return
            elseif action.type == "penClear" then
                local before = copyDrawingList(action.before)
                local after = copyDrawingList(plan.drawings)
                table.remove(undoStack)
                restoreDrawingList(plan, before)
                pushRedo({ type = "penClear", planRef = plan, before = before, after = after })
                broadcastDrawingState(before)
                scheduleRefresh()
                return
            end
        end

        local fallback = fallbackUndoTarget(plan)
        if not fallback then return end
        if fallback.type == "place" then
            local idx = fallback.idx
            local removed = copyIconData(plan.icons[idx])
            table.remove(plan.icons, idx)
            pushRedo({ type = "place", planRef = plan, icon = removed })
            currentSelection = nil
            notifyEdit("RM", { tostring(idx) })
            scheduleRefresh()
        elseif fallback.type == "draw" then
            local idx = fallback.idx
            local removed = copyStrokeData(plan.drawings[idx])
            table.remove(plan.drawings, idx)
            pushRedo({ type = "draw", planRef = plan, stroke = removed })
            notifyEdit("RMDRAW", { tostring(idx) })
            scheduleRefresh()
        end
    end

    function H.redo()
        local action = redoStack[#redoStack]
        if not action then return end
        local plan = currentPlan()
        if not plan or plan ~= action.planRef then return end

        if action.type == "place" then
            local icon = copyIconData(action.icon)
            if not icon then return end
            table.insert(plan.icons, icon)
            table.remove(redoStack)
            pushUndo({ type = "place", planRef = plan, iconRef = icon }, true)
            currentSelection = #plan.icons
            broadcastIconPlacement(icon)
        elseif action.type == "draw" then
            local stroke = copyStrokeData(action.stroke)
            if not stroke then return end
            plan.drawings = plan.drawings or {}
            table.insert(plan.drawings, stroke)
            table.remove(redoStack)
            pushUndo({ type = "draw", planRef = plan, strokeRef = stroke }, true)
            broadcastStrokePlacement(stroke)
        elseif action.type == "removeDraw" then
            local idx = findStrokeRefIndex(plan, action.strokeRef) or action.index
            if not (idx and plan.drawings and plan.drawings[idx]) then return end
            local removed = copyStrokeData(plan.drawings[idx])
            table.remove(plan.drawings, idx)
            table.remove(redoStack)
            pushUndo({ type = "removeDraw", planRef = plan, stroke = removed, index = idx }, true)
            notifyEdit("RMDRAW", { tostring(idx) })
        elseif action.type == "clear" then
            local before = copyPlanVisualState(action.before)
            local after = copyPlanVisualState(action.after)
            table.remove(redoStack)
            restorePlanVisualState(plan, after)
            pushUndo({ type = "clear", planRef = plan, before = before, after = after }, true)
            currentSelection = nil
            broadcastPlanVisualState(after)
        elseif action.type == "penClear" then
            local before = copyDrawingList(action.before)
            local after = copyDrawingList(action.after)
            table.remove(redoStack)
            restoreDrawingList(plan, after)
            pushUndo({ type = "penClear", planRef = plan, before = before, after = after }, true)
            broadcastDrawingState(after)
        end

        scheduleRefresh()
    end

    return H
end)()
local function showClearPlanConfirm()
    if isCoOpGuest() then return end
    if not StaticPopupDialogs["L3F_RP_CONFIRM_CLEAR_PLAN"] then
        StaticPopupDialogs["L3F_RP_CONFIRM_CLEAR_PLAN"] = {
            text = "Are you sure you want to clear this plan?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                local p = currentPlan()
                if p then
                    plannerHistory.recordClearPlan(p)
                    p.icons = {}
                    p.drawings = {}
                    currentSelection = nil
                    notifyEdit("CLEAR", {})
                    scheduleRefresh()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show("L3F_RP_CONFIRM_CLEAR_PLAN")
end

local penMode = {
    enabled  = false,
    size     = 4,
    color    = "ffffff",
    fadeOut  = 0,
}

local rightTab = "notes"
local leftMode = "icons"


-- =============================================================
-- 6. CANVAS HELPERS
-- =============================================================
local function canvasSizePx()
    if not canvasFrame then return 0, 0 end
    return canvasFrame:GetWidth() or 0, canvasFrame:GetHeight() or 0
end

local function relToAbs(x, y)
    local w, h = canvasSizePx()
    return x * w, y * h
end

local function hasDirectionIndicator(iconData)
    return iconData
        and iconData.kind == "encounter"
        and iconData.key ~= "rpenc_gateway"
end

local DIRECTION_ARC_RADIUS = 21
local DIRECTION_ARC_SPAN = 105
local DIRECTION_ARC_STEPS = 24
local DIRECTION_ARC_WIDTH = 4
local DIRECTION_ARC_OVERLAP = 2
local DIRECTION_MARKER_LENGTH = 7
local DIRECTION_MARKER_HALF_WIDTH = 4
local DIRECTION_MARKER_WIDTH = 3
local ROTATION_HANDLE_RADIUS = 44

local function directionPoint(angle, radius)
    local rad = math.rad(angle)
    return math.cos(rad) * radius, math.sin(rad) * radius
end

local function setLineTexture(tex, parent, x1, y1, x2, y2, width, overlap)
    if not tex then return end
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.1 then
        tex:Hide()
        return
    end
    overlap = overlap or 0
    if overlap > 0 then
        local ux, uy = dx / len, dy / len
        x1, y1 = x1 - (ux * overlap), y1 - (uy * overlap)
        x2, y2 = x2 + (ux * overlap), y2 + (uy * overlap)
        dx, dy = x2 - x1, y2 - y1
        len = math.sqrt(dx * dx + dy * dy)
    end
    tex:Show()
    tex:ClearAllPoints()
    tex:SetSize(len, width or 2)
    tex:SetPoint("CENTER", parent, "CENTER", (x1 + x2) / 2, (y1 + y2) / 2)
    if tex.SetRotation then
        tex:SetRotation(math.atan2(dy, dx))
    end
end

local function updateDirectionIndicator(arc, iconData)
    if not arc or not arc.parent then return end
    local angle = tonumber(iconData.direction) or 45
    local halfSpan = DIRECTION_ARC_SPAN / 2
    local step = DIRECTION_ARC_SPAN / DIRECTION_ARC_STEPS

    for i, seg in ipairs(arc.segments or {}) do
        local a1 = angle + halfSpan - ((i - 1) * step)
        local a2 = angle + halfSpan - (i * step)
        local x1, y1 = directionPoint(a1, DIRECTION_ARC_RADIUS)
        local x2, y2 = directionPoint(a2, DIRECTION_ARC_RADIUS)
        setLineTexture(seg, arc.parent, x1, y1, x2, y2,
            DIRECTION_ARC_WIDTH, DIRECTION_ARC_OVERLAP)
    end

    local h = arc.head or {}
    local outerRadius = DIRECTION_ARC_RADIUS + (DIRECTION_ARC_WIDTH / 2)
    local tipX, tipY = directionPoint(angle, outerRadius + DIRECTION_MARKER_LENGTH)
    local baseX, baseY = directionPoint(angle, outerRadius)
    local sideX, sideY = directionPoint(angle + 90, 1)
    local b1x = baseX + (sideX * DIRECTION_MARKER_HALF_WIDTH)
    local b1y = baseY + (sideY * DIRECTION_MARKER_HALF_WIDTH)
    local b2x = baseX - (sideX * DIRECTION_MARKER_HALF_WIDTH)
    local b2y = baseY - (sideY * DIRECTION_MARKER_HALF_WIDTH)
    setLineTexture(h[1], arc.parent, tipX, tipY, b1x, b1y, DIRECTION_MARKER_WIDTH, 0.5)
    setLineTexture(h[2], arc.parent, tipX, tipY, b2x, b2y, DIRECTION_MARKER_WIDTH, 0.5)
    setLineTexture(h[3], arc.parent, b1x, b1y, b2x, b2y, DIRECTION_MARKER_WIDTH, 0.5)
    for i = 4, #h do
        h[i]:Hide()
    end
end

local function drawDirectionIndicator(parent, iconData)
    if not hasDirectionIndicator(iconData) then return end
    local arc = { parent = parent, segments = {}, head = {} }
    for i = 1, DIRECTION_ARC_STEPS do
        local seg = parent:CreateTexture(nil, "OVERLAY")
        seg:SetTexture("Interface\\Buttons\\WHITE8X8")
        seg:SetVertexColor(1, 0.02, 0.02, 0.95)
        arc.segments[i] = seg
    end
    for i = 1, 3 do
        local head = parent:CreateTexture(nil, "OVERLAY")
        head:SetTexture("Interface\\Buttons\\WHITE8X8")
        head:SetVertexColor(1, 0.02, 0.02, 0.95)
        arc.head[i] = head
    end
    updateDirectionIndicator(arc, iconData)
    return arc
end

local function updateRotationHandle(line, handle, parent, iconData)
    if not line or not handle then return end
    local angle = tonumber(iconData.direction) or 45
    local x, y = directionPoint(angle, ROTATION_HANDLE_RADIUS)
    setLineTexture(line, parent, 0, 0, x, y, 2)
    handle:ClearAllPoints()
    handle:SetPoint("CENTER", parent, "CENTER", x, y)
end

local function cursorPositionUI()
    if not GetCursorPosition then return nil, nil end
    local cx, cy = GetCursorPosition()
    if not cx or not cy then return nil, nil end
    local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    return cx / scale, cy / scale
end

local function cursorDirectionDegrees(frame)
    if not frame then return nil end
    local cx, cy = cursorPositionUI()
    if not cx or not cy then return nil end
    local fx, fy = frame:GetCenter()
    if not fx or not fy then return nil end

    local deg = math.deg(math.atan2(cy - fy, cx - fx))
    if deg < 0 then deg = deg + 360 end
    return deg
end


-- Build a placed-icon Frame bound to one entry in plan.icons.
--
-- Two big changes from 0.20.1:
--   1. Drag uses WoW's StartMoving / StopMovingOrSizing instead of a
--      follower-icon dance. The frame itself moves under the cursor;
--      on release we read its final GetCenter() to compute the new
--      fractional position. This eliminates the f:Hide() call in
--      OnDragStart that was *cancelling the active drag* in TBC 2.5.x
--      (hiding a drag source aborts the gesture; OnDragStop never
--      fires; the icon stays stuck mid-flight - the "sticky" symptom).
--   2. kind="boss" icons render a PlayerModel (small 3D portrait of
--      npc.npcID) instead of a texture. Same drag/click affordances.
local function buildPlacedIcon(plan, iconData, idx)
    local f = CreateFrame("Frame", nil, placedHost)
    f:SetSize(PLACED_DEFAULT_SIZE, PLACED_DEFAULT_SIZE)
    local ax, ay = relToAbs(iconData.x or 0.5, iconData.y or 0.5)
    f:SetPoint("CENTER", placedHost, "TOPLEFT", ax, -ay)
    local directionArc = drawDirectionIndicator(f, iconData)

    local path  -- texture path; nil for boss-kind (uses model instead)
    if iconData.kind == "boss" and iconData.npcID then
        local model = CreateFrame("PlayerModel", nil, f)
        model:SetAllPoints()
        model:EnableMouse(false)  -- click pass-through to the parent f
        pcall(function()
            model:SetCreature(iconData.npcID)
            model:SetCamDistanceScale(1.8)
            model:SetPortraitZoom(0.9)
        end)
    else
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        local tc
        if iconData.iconTex then
            path = iconData.iconTex
        elseif iconData.variant then
            local vk = iconData.key .. ":" .. iconData.variant
            path = KEY_TO_TEX[vk]
            tc = KEY_TO_TEXCOORD[vk]
        end
        path = path or KEY_TO_TEX[iconData.key]
        tc = tc or KEY_TO_TEXCOORD[iconData.key]
        if path then tex:SetTexture(path) end
        applyIconTexCoord(tex, tc)
        if iconData.color and iconData.color ~= "ffffff" then
            local r = tonumber(iconData.color:sub(1, 2), 16)
            local g = tonumber(iconData.color:sub(3, 4), 16)
            local b = tonumber(iconData.color:sub(5, 6), 16)
            if r and g and b then tex:SetVertexColor(r/255, g/255, b/255, 1) end
        end
    end

    local rotationLine, rotationHandle
    if currentSelection == idx then
        local ring = f:CreateTexture(nil, "OVERLAY")
        ring:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
        ring:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
        ring:SetTexture("Interface\\Buttons\\WHITE8X8")
        ring:SetVertexColor(0.3, 0.7, 1.0, 0.35)
        ring:SetDrawLayer("OVERLAY", -2)

        if hasDirectionIndicator(iconData) and not iconData.locked then
            rotationLine = f:CreateTexture(nil, "OVERLAY")
            rotationLine:SetTexture("Interface\\Buttons\\WHITE8X8")
            rotationLine:SetVertexColor(0.55, 0.58, 1.0, 0.9)

            rotationHandle = CreateFrame("Button", nil, placedHost)
            rotationHandle:SetSize(10, 10)
            rotationHandle:EnableMouse(true)
            rotationHandle:SetFrameLevel((f:GetFrameLevel() or 1) + 8)
            local handleBorder = rotationHandle:CreateTexture(nil, "BACKGROUND")
            handleBorder:SetAllPoints()
            handleBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
            handleBorder:SetVertexColor(0.12, 0.12, 0.35, 0.95)
            local handleTex = rotationHandle:CreateTexture(nil, "ARTWORK")
            handleTex:SetPoint("TOPLEFT", rotationHandle, "TOPLEFT", 2, -2)
            handleTex:SetPoint("BOTTOMRIGHT", rotationHandle, "BOTTOMRIGHT", -2, 2)
            handleTex:SetTexture("Interface\\Buttons\\WHITE8X8")
            handleTex:SetVertexColor(0.62, 0.62, 1.0, 1)
            updateRotationHandle(rotationLine, rotationHandle, f, iconData)
        end
    end

    if iconData.locked then
        local lockBg = f:CreateTexture(nil, "OVERLAY")
        lockBg:SetSize(10, 10)
        lockBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
        lockBg:SetColorTexture(0.9, 0.7, 0.1, 0.9)
    end

    if iconData.text and iconData.text ~= "" then
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOP", f, "BOTTOM", 0, -1)
        lbl:SetText(iconData.text)
        lbl:SetTextColor(1, 1, 1, 1)
    end

    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(false)
    f:RegisterForDrag("LeftButton")

    if hasDirectionIndicator(iconData) then
        f:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(iconData.text or KEY_TO_LABEL[iconData.key] or "Encounter icon")
            GameTooltip:AddLine("Select it, then drag the square handle to rotate.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local openedMenuOnRightDown = false
    local rotatingDirection = false

    local function setDirectionFromCursor()
        local deg = cursorDirectionDegrees(f)
        if not deg then return end
        iconData.direction = deg
        updateDirectionIndicator(directionArc, iconData)
        updateRotationHandle(rotationLine, rotationHandle, f, iconData)
    end

    local function finishDirectionRotation()
        if not rotatingDirection then return end
        rotatingDirection = false
        if rotationHandle then
            rotationHandle:SetScript("OnUpdate", nil)
        end
        currentSelection = idx
        if broadcastIconProps then
            broadcastIconProps(idx, iconData)
        end
        refreshPropsPanel()
        scheduleRefresh()
    end

    if rotationHandle then
        rotationHandle:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Rotate direction")
            GameTooltip:AddLine("Drag this handle around the icon.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        rotationHandle:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rotationHandle:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" and button ~= "Button1" then return end
            rotatingDirection = true
            currentSelection = idx
            setDirectionFromCursor()
            self:SetScript("OnUpdate", function()
                if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                    finishDirectionRotation()
                else
                    setDirectionFromCursor()
                end
            end)
        end)
        rotationHandle:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" or button == "Button1" then
                finishDirectionRotation()
            end
        end)
    end

    f:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" or button == "Button2" then
            openedMenuOnRightDown = true
            openContextMenu(self, idx)
        end
    end)

    -- Route left/right clicks from OnMouseUp. This is the most
    -- reliable path on this planner's draggable icon frames.
    f:SetScript("OnMouseUp", function(self, button)
        if openedMenuOnRightDown and (button == "RightButton" or button == "Button2") then
            openedMenuOnRightDown = false
            return
        end
        openedMenuOnRightDown = false
        if button == "RightButton" or button == "Button2" then
            openContextMenu(self, idx)
        elseif button == "LeftButton" or button == "Button1" then
            selectIcon(idx)
        end
    end)

    -- Track the icon's fractional position at drag start so OnDragStop
    -- can distinguish a real move from an accidental shake-during-click
    -- (WoW's drag threshold is generous; even a still-handed click can
    -- nudge the cursor ~2-3 px which is enough to fire OnDragStart).
    local dragStartX, dragStartY

    f:SetScript("OnDragStart", function()
        if iconData.locked then return end
        dragStartX, dragStartY = iconData.x, iconData.y
        f:StartMoving()  -- WoW now moves f under the cursor; no
                         -- follower / Hide / dragState manipulation.
    end)

    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local cx, cy = f:GetCenter()
        local l, r = canvasFrame:GetLeft(), canvasFrame:GetRight()
        local t, b = canvasFrame:GetTop(), canvasFrame:GetBottom()
        local newX, newY
        if cx and l then
            newX = (cx - l) / (r - l)
            newY = 1 - (cy - b) / (t - b)
        end
        local moved = newX and (
            math.abs(newX - (dragStartX or newX)) > 0.005 or
            math.abs(newY - (dragStartY or newY)) > 0.005)
        if not moved then
            -- Treated as a click - select instead of move (the frame
            -- snaps back to its original anchored position on the
            -- next scheduleRefresh tick).
            currentSelection = idx
        elseif newX and l and cx >= l and cx <= r and cy >= b and cy <= t then
            iconData.x = newX
            iconData.y = newY
            -- Co-op: broadcast MOVE with iconIdx + final position.
            notifyEdit("MOVE", {
                tostring(idx),
                string.format("%.4f", newX),
                string.format("%.4f", newY),
            })
        else
            -- Released outside canvas after a meaningful drag = yeet.
            for i, ic in ipairs(plan.icons) do
                if ic == iconData then
                    table.remove(plan.icons, i)
                    notifyEdit("RM", { tostring(i) })
                    break
                end
            end
        end
        -- Defer the rebuild - never recurse from inside the
        -- OnDragStop callback.
        scheduleRefresh()
    end)

    return f
end


-- =============================================================
-- 7. DRAWING LAYER (pen mode)
-- =============================================================
local function drawSegment(parent, x1, y1, x2, y2, size, r, g, b, a)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return end
    -- Extend a little past each endpoint so adjacent rotated quads
    -- overlap; this removes hairline seams between pen segments.
    local pad = math.max(1, (size or 4) * 0.35)
    local ux, uy = dx / len, dy / len
    local sx, sy = x1 - ux * pad, y1 - uy * pad
    local ex, ey = x2 + ux * pad, y2 + uy * pad
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetVertexColor(r, g, b, a)
    tex:SetWidth(len + (2 * pad))
    tex:SetHeight(size)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", parent, "TOPLEFT", (sx + ex) / 2, -(sy + ey) / 2)
    tex:SetRotation(math.atan2(-dy, dx))
    drawingSegments[#drawingSegments + 1] = tex
end

refreshDrawings = function()
    if not drawingHost then return end
    for i = 1, #drawingSegments do
        local tex = drawingSegments[i]
        if tex then
            tex:Hide()
            tex:SetParent(nil)
        end
    end
    wipe(drawingSegments)
    local plan = currentPlan()
    if not plan or not plan.drawings then return end
    local w, h = canvasSizePx()
    if w == 0 then return end
    for _, stroke in ipairs(plan.drawings) do
        local hex = stroke.color or "ffffff"
        local r = tonumber(hex:sub(1, 2), 16) / 255
        local g = tonumber(hex:sub(3, 4), 16) / 255
        local b = tonumber(hex:sub(5, 6), 16) / 255
        local size = stroke.size or 4
        local pts = stroke.points or {}
        for i = 2, #pts do
            local p1, p2 = pts[i - 1], pts[i]
            drawSegment(drawingHost,
                p1.x * w, p1.y * h, p2.x * w, p2.y * h,
                size, r, g, b, 1)
        end
    end
end

-- Incremental: draw ONLY the new segment from prevPt to newPt. Used
-- while the user is mid-stroke so we don't rebuild the whole drawings
-- layer on every cursor move. The previous full-rebuild approach was
-- O(N) per point - long strokes would lag and the renderer would
-- silently stop adding segments when the texture count grew large
-- (Morpheours's "stops showing after a certain length" report).
local function appendStrokeSegment(stroke, prevPt, newPt)
    if not drawingHost then return end
    local w, h = canvasSizePx()
    if w == 0 then return end
    local hex = stroke.color or "ffffff"
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    local size = stroke.size or 4
    drawSegment(drawingHost,
        prevPt.x * w, prevPt.y * h, newPt.x * w, newPt.y * h,
        size, r, g, b, 1)
end

local function cursorCanvasPointPx()
    if not (canvasFrame and GetCursorPosition) then return nil end
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    if not (cx and cy) then return nil end
    cx, cy = cx / scale, cy / scale

    local l, r = canvasFrame:GetLeft(), canvasFrame:GetRight()
    local t, b = canvasFrame:GetTop(), canvasFrame:GetBottom()
    if not (l and r and t and b) then return nil end
    if cx < l or cx > r or cy < b or cy > t then return nil end

    return cx - l, t - cy
end

local function distanceToSegmentSq(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local lenSq = dx * dx + dy * dy
    if lenSq <= 0.0001 then
        local ox, oy = px - x1, py - y1
        return ox * ox + oy * oy
    end

    local t = ((px - x1) * dx + (py - y1) * dy) / lenSq
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = x1 + t * dx, y1 + t * dy
    local ox, oy = px - qx, py - qy
    return ox * ox + oy * oy
end

local function hitTestDrawingStroke()
    local plan = currentPlan()
    if not (plan and plan.drawings) then return nil end

    local px, py = cursorCanvasPointPx()
    if not px then return nil end

    local w, h = canvasSizePx()
    if w == 0 or h == 0 then return nil end

    local bestIdx, bestDistSq
    for strokeIdx, stroke in ipairs(plan.drawings) do
        local pts = stroke.points or {}
        local threshold = math.max(8, (stroke.size or 4) + 6)
        local thresholdSq = threshold * threshold
        for i = 2, #pts do
            local p1, p2 = pts[i - 1], pts[i]
            local distSq = distanceToSegmentSq(
                px, py,
                p1.x * w, p1.y * h,
                p2.x * w, p2.y * h)
            if distSq <= thresholdSq and (not bestDistSq or distSq < bestDistSq) then
                bestIdx = strokeIdx
                bestDistSq = distSq
            end
        end
    end

    return bestIdx
end


-- =============================================================
-- 8. LEFT PANEL (mode toggle + palette / pen controls)
-- =============================================================
local leftPanel, iconControls, penControls

-- `dragSource` discriminates palette-vs-encounter drags so each
-- handler only acts on its own drop. Without this, a stale state
-- from a previous drag could cause palette's OnDragStop to fire
-- against an encounter-kind drag and produce a malformed icon.
local function startDragFromPalette(kind, key, opts)
    dragState.active     = true
    dragState.dragSource = "palette"
    dragState.kind       = kind
    dragState.key        = key
    dragState.variant    = nil
    dragState.color      = "ffffff"
    dragState.text       = nil
    dragState.fromIcon   = nil
    dragState.npcID      = opts and opts.npcID or nil
    dragState.npcName    = opts and opts.npcName or nil
    dragState.iconTex    = opts and opts.iconTex or nil
    followerTex:SetTexture((opts and opts.previewTex) or KEY_TO_TEX[key] or QUILL)
    applyIconTexCoord(followerTex, KEY_TO_TEXCOORD[key])
    follower:Show()
end

local function resetDragState()
    dragState.active     = false
    dragState.dragSource = nil
    dragState.kind       = nil
    dragState.key        = nil
    dragState.variant    = nil
    dragState.color      = nil
    dragState.text       = nil
    dragState.fromIcon   = nil
    dragState.npcID      = nil
    dragState.npcName    = nil
    dragState.iconTex    = nil
end

local function placeIconAt(kind, key, relX, relY, options)
    local plan = currentPlan()
    if not plan then return end
    local defaultText = options and options.text
    if (not defaultText or defaultText == "") and key == "rpenc_gateway" then
        defaultText = "Entrance"
    end
    local entry = {
        kind    = kind,
        key     = key,
        x       = relX or 0.5,
        y       = relY or 0.5,
        color   = (options and options.color) or "ffffff",
        text    = defaultText or nil,
        variant = (options and options.variant) or nil,
        locked  = false,
    }
    if options and options.spellID then
        entry.spellID = options.spellID
    end
    if options and options.iconTex then
        entry.iconTex = options.iconTex
    end
    if options and options.npcID then
        entry.npcID = options.npcID
    end
    if hasDirectionIndicator(entry) then
        entry.direction = tonumber(options and options.direction) or 45
    end
    table.insert(plan.icons, entry)
    plannerHistory.recordIconPlacement(plan, entry)
    currentSelection = #plan.icons
    -- Co-op: broadcast PLACE. Position-by-iconIdx isn't sent; each
    -- member appends to their own icons array. Out-of-order PLACE from
    -- two members causes the local indexes to diverge briefly until
    -- the next host snapshot resyncs. Acceptable for v1.
    plannerHistory.broadcastIconPlacement(entry)
    -- Deferred: we're often called from an event-handler closure
    -- whose own frame is about to be destroyed by refreshPalette.
    scheduleRefresh()
end

local function buildPaletteButton(parent, kind, entry, x, y, sz)
    sz = sz or PALETTE_ICON
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(sz, sz)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(entry.tex)
    applyIconTexCoord(tex, entry.tc)
    btn:SetNormalTexture(tex)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hl:SetBlendMode("ADD")

    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.label or entry.key)
        GameTooltip:AddLine("Drag onto the canvas, or click to place.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnDragStart", function()
        startDragFromPalette(kind, entry.key, {
            npcID = entry.npcID,
            npcName = entry.npcName,
            previewTex = entry.tex,
            iconTex = entry.iconTex or entry.tex,
        })
    end)
    btn:SetScript("OnDragStop", function()
        -- Only act if THIS palette drag is the active one. dragSource
        -- guard prevents firing against an encounter-kind drag state;
        -- when it doesn't match we just bail without touching state
        -- so the legitimate drag's own OnDragStop can still clean up.
        if not dragState.active or dragState.dragSource ~= "palette" then
            return
        end
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local l, r = canvasFrame:GetLeft(), canvasFrame:GetRight()
        local t, b = canvasFrame:GetTop(), canvasFrame:GetBottom()
        if l and cx >= l and cx <= r and cy >= b and cy <= t then
            placeIconAt(dragState.kind, dragState.key,
                (cx - l) / (r - l), 1 - (cy - b) / (t - b),
                {
                    color = dragState.color,
                    variant = dragState.variant,
                    npcID = dragState.npcID,
                    text = dragState.npcName,
                    iconTex = dragState.iconTex,
                })
        end
        resetDragState()
        follower:Hide()
    end)
    btn:SetScript("OnClick", function()
        placeIconAt(kind, entry.key, 0.5, 0.5, {
            npcID = entry.npcID,
            text = entry.npcName,
            iconTex = entry.iconTex or entry.tex,
        })
    end)
end


-- ---------- Pen-mode input on the canvas -----------------------
local currentStroke
local function canvasMouseDown(self, button)
    if button ~= "LeftButton" then return end
    if penMode.enabled then
        local plan = currentPlan()
        plan.drawings = plan.drawings or {}
        currentStroke = {
            color  = penMode.color,
            size   = penMode.size,
            fade   = penMode.fadeOut,
            points = {},
        }
        table.insert(plan.drawings, currentStroke)
    else
        deselect()
    end
end

local function broadcastStroke(stroke)
    plannerHistory.broadcastStrokePlacement(stroke)
end

local function finishCurrentStroke()
    if not currentStroke then return end
    local stroke = currentStroke
    currentStroke = nil

    local plan = currentPlan()
    if not (stroke.points and #stroke.points >= 2) then
        local idx = plannerHistory.findStrokeRefIndex(plan, stroke)
        if idx and plan and plan.drawings then
            table.remove(plan.drawings, idx)
            refreshDrawings()
        end
        return
    end

    plannerHistory.recordStrokePlacement(plan, stroke)
    broadcastStroke(stroke)
end

local function canvasUpdate(self)
    if not currentStroke then return end
    if not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then
        finishCurrentStroke()
        return
    end
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local l, r = canvasFrame:GetLeft(), canvasFrame:GetRight()
    local t, b = canvasFrame:GetTop(), canvasFrame:GetBottom()
    if not l then return end
    if cx < l or cx > r or cy < b or cy > t then return end
    local rx = (cx - l) / (r - l)
    local ry = 1 - (cy - b) / (t - b)
    local pts = currentStroke.points
    local last = pts[#pts]
    if not last or math.abs(last.x - rx) > 0.001 or math.abs(last.y - ry) > 0.001 then
        local newPt = { x = rx, y = ry }
        table.insert(pts, newPt)
        -- Append only the new segment - DO NOT call refreshDrawings,
        -- which would O(N) rebuild every existing segment on every
        -- frame. Long strokes would stop drawing because the renderer
        -- choked on the texture-creation flood.
        if last then
            appendStrokeSegment(currentStroke, last, newPt)
        end
    end
end

local function canvasMouseUp(self, button)
    if button == "LeftButton" then
        finishCurrentStroke()
    elseif button == "RightButton" or button == "Button2" then
        if currentStroke then return end
        local strokeIdx = hitTestDrawingStroke()
        if strokeIdx then
            deselect()
            openDrawingContextMenu(self, strokeIdx)
        end
    end
end


selectIcon = function(idx)
    currentSelection = idx
    refreshIcons()
    refreshPropsPanel()
end

deselect = function()
    if currentSelection then
        currentSelection = nil
        refreshIcons()
        refreshPropsPanel()
    end
end

local contextMenuFrame
local drawingContextMenuFrame
local textPromptFrame

local function findIconIndex(plan, iconRef)
    if not plan or not iconRef then return nil end
    for i, ic in ipairs(plan.icons or {}) do
        if ic == iconRef then return i end
    end
    return nil
end

local function findDrawingIndex(plan, strokeRef)
    if not plan or not strokeRef then return nil end
    for i, stroke in ipairs(plan.drawings or {}) do
        if stroke == strokeRef then return i end
    end
    return nil
end

broadcastIconProps = function(iconIdx, icon)
    notifyEdit("PROPS", {
        tostring(iconIdx or 0),
        icon.color or "ffffff",
        icon.text or "",
        icon.variant or "",
        icon.locked and "1" or "0",
        tostring(icon.direction or ""),
    })
end

local function ensureTextPromptFrame()
    if textPromptFrame then return textPromptFrame end
    local f = CreateFrame("Frame", "L3FRPIconTextPrompt", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(230, 96)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.9)
    local bd = f:CreateTexture(nil, "BORDER")
    bd:SetPoint("TOPLEFT", -1, 1); bd:SetPoint("BOTTOMRIGHT", 1, -1)
    bd:SetColorTexture(0.35, 0.35, 0.35, 0.9)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetText("Icon text")

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(194, 22)
    edit:SetPoint("TOP", title, "BOTTOM", 0, -8)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(24)
    f.edit = edit

    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(86, 22)
    saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10)
    saveBtn:SetText(ACCEPT or "Save")
    saveBtn:SetScript("OnClick", function()
        local plan, icon = f.plan, f.icon
        if not (plan and icon) then f:Hide(); return end
        local idx = findIconIndex(plan, icon)
        if not idx then f:Hide(); return end
        local text = (f.edit and f.edit:GetText()) or ""
        text = text:gsub("^%s*(.-)%s*$", "%1")
        icon.text = (text ~= "") and text or nil
        broadcastIconProps(idx, icon)
        refreshIcons()
        refreshPropsPanel()
        f:Hide()
    end)

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(86, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)
    cancelBtn:SetText(CANCEL or "Cancel")
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    edit:SetScript("OnEnterPressed", function() saveBtn:Click() end)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    f:Hide()
    textPromptFrame = f
    return f
end

local function showTextPrompt(plan, icon)
    if not (plan and icon) then return end
    local f = ensureTextPromptFrame()
    f.plan, f.icon = plan, icon
    f.edit:SetText(icon.text or "")
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

openContextMenu = function(anchorBtn, iconIdx)
    if not contextMenuFrame then
        contextMenuFrame = CreateFrame("Frame", "L3FRPContextMenu", UIParent)
        contextMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        contextMenuFrame:SetFrameLevel(200)
        contextMenuFrame:SetToplevel(true)
        contextMenuFrame:SetClampedToScreen(true)
        contextMenuFrame:EnableMouse(true)
        contextMenuFrame:SetSize(140, 6 + 22 * 4)
        local bg = contextMenuFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
        contextMenuFrame:Hide()
        contextMenuFrame.buttons = {}
    end
    local f = contextMenuFrame
    if drawingContextMenuFrame then drawingContextMenuFrame:Hide() end
    local cursorX, cursorY
    if GetCursorPosition and UIParent and UIParent.GetEffectiveScale then
        local s = UIParent:GetEffectiveScale() or 1
        local x, y = GetCursorPosition()
        if x and y then
            cursorX = x / s
            cursorY = y / s
        end
    end
    f:ClearAllPoints()
    if cursorX and cursorY then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX + 8, cursorY - 8)
    else
        f:SetPoint("TOPLEFT", anchorBtn, "BOTTOMRIGHT", 0, 0)
    end
    f:Show()

    local plan = currentPlan()
    local icon = plan and plan.icons[iconIdx]

    local items = {
        { label = "Text",   action = function()
            if icon and plan then
                showTextPrompt(plan, icon)
            end
            f:Hide()
        end },
        { label = "Color", action = function()
            if icon and plan then
                openColorPicker(icon.color or "ffffff", function(newHex)
                    local idx = findIconIndex(plan, icon)
                    if not idx then return end
                    icon.color = newHex
                    broadcastIconProps(idx, icon)
                    refreshIcons()
                    refreshPropsPanel()
                end)
            end
            f:Hide()
        end },
        { label = "Remove", action = function()
            if icon then
                local idx = findIconIndex(plan, icon)
                if idx then
                    table.remove(plan.icons, idx)
                    notifyEdit("RM", { tostring(idx) })
                    currentSelection = nil
                    scheduleRefresh()
                end
            end
            f:Hide()
        end },
        { label = "Cancel", action = function()
            f:Hide()
        end },
    }
    for _, btn in ipairs(f.buttons) do btn:Hide() end
    for i, item in ipairs(items) do
        local b = f.buttons[i] or CreateFrame("Button", nil, f)
        f.buttons[i] = b
        b:SetSize(130, 20)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -3 - (i - 1) * 22)
        b:Show()
        if not b.text then
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
        end
        b.text:SetText(item.label)
        b:SetScript("OnClick", item.action)
        local bg = b.bg or b:CreateTexture(nil, "BACKGROUND")
        b.bg = bg
        bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0)
        b:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.12) end)
        b:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
    end
    f:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() and IsMouseButtonDown
           and IsMouseButtonDown("LeftButton") then
            self:Hide(); self:SetScript("OnUpdate", nil)
        end
    end)
end

openDrawingContextMenu = function(anchorFrame, strokeIdx)
    local plan = currentPlan()
    local stroke = plan and plan.drawings and plan.drawings[strokeIdx]
    if not stroke then return end

    if not drawingContextMenuFrame then
        drawingContextMenuFrame = CreateFrame("Frame", "L3FRPDrawingContextMenu", UIParent)
        drawingContextMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        drawingContextMenuFrame:SetFrameLevel(200)
        drawingContextMenuFrame:SetToplevel(true)
        drawingContextMenuFrame:SetClampedToScreen(true)
        drawingContextMenuFrame:EnableMouse(true)
        drawingContextMenuFrame:SetSize(140, 6 + 22 * 2)
        local bg = drawingContextMenuFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
        drawingContextMenuFrame:Hide()
        drawingContextMenuFrame.buttons = {}
    end

    local f = drawingContextMenuFrame
    if contextMenuFrame then contextMenuFrame:Hide() end

    local cursorX, cursorY
    if GetCursorPosition and UIParent and UIParent.GetEffectiveScale then
        local s = UIParent:GetEffectiveScale() or 1
        local x, y = GetCursorPosition()
        if x and y then
            cursorX = x / s
            cursorY = y / s
        end
    end
    f:ClearAllPoints()
    if cursorX and cursorY then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX + 8, cursorY - 8)
    else
        f:SetPoint("TOPLEFT", anchorFrame, "BOTTOMRIGHT", 0, 0)
    end
    f:Show()

    local items = {
        { label = "Remove", action = function()
            local p = currentPlan()
            local idx = findDrawingIndex(p, stroke) or strokeIdx
            if p and p.drawings and idx and p.drawings[idx] then
                plannerHistory.recordDrawingRemoval(p, p.drawings[idx], idx)
                table.remove(p.drawings, idx)
                notifyEdit("RMDRAW", { tostring(idx) })
                refreshDrawings()
            end
            f:Hide()
        end },
        { label = "Cancel", action = function()
            f:Hide()
        end },
    }
    f:SetSize(140, 6 + 22 * #items)
    for _, btn in ipairs(f.buttons) do btn:Hide() end
    for i, item in ipairs(items) do
        local b = f.buttons[i] or CreateFrame("Button", nil, f)
        f.buttons[i] = b
        b:SetSize(130, 20)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -3 - (i - 1) * 22)
        b:Show()
        if not b.text then
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
        end
        b.text:SetText(item.label)
        b:SetScript("OnClick", item.action)
        local bg = b.bg or b:CreateTexture(nil, "BACKGROUND")
        b.bg = bg
        bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0)
        b:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.12) end)
        b:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
    end
    f:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() and IsMouseButtonDown
           and IsMouseButtonDown("LeftButton") then
            self:Hide(); self:SetScript("OnUpdate", nil)
        end
    end)
end


local function buildLeftPanel(parent)
    leftPanel = CreateFrame("Frame", nil, parent)
    leftPanel:SetSize(LEFT_W, 600)
    leftPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -TOP_H)
    leftPanel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 4, 4)
    local bg = leftPanel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.25)

    leftClearPlanBtn = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    leftClearPlanBtn:SetSize(58, 22)
    leftClearPlanBtn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 2, -4)
    leftClearPlanBtn:SetText("Clear plan")
    leftClearPlanBtn:SetScript("OnClick", showClearPlanConfirm)
    leftClearPlanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clear plan")
        GameTooltip:AddLine("Clear all icons and drawings in the current plan.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    leftClearPlanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    undoBtn = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    undoBtn:SetSize(28, 24); undoBtn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 2, -32)
    undoBtn:SetText("<")
    undoBtn:SetScript("OnClick", plannerHistory.undo)
    undoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Undo")
        GameTooltip:AddLine("Undo the last icon, drawing, or clear action.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    undoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    redoBtn = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    redoBtn:SetSize(28, 24); redoBtn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 32, -32)
    redoBtn:SetText(">")
    redoBtn:SetScript("OnClick", plannerHistory.redo)
    redoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Redo")
        GameTooltip:AddLine("Redo the last undone planner action.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    redoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local arrowBtn = CreateFrame("Button", nil, leftPanel)
    arrowBtn:SetSize(28, 28); arrowBtn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 2, -62)
    arrowBtn:SetNormalTexture("Interface\\AddOns\\L3FTools\\Media\\RaidPlanner\\icons-mode.png")
    arrowBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    arrowBtn:SetScript("OnClick", function() leftMode = "icons"; penMode.enabled = false; refreshPalette() end)
    arrowBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Icons mode"); GameTooltip:Show()
    end)
    arrowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local penBtn = CreateFrame("Button", nil, leftPanel)
    penBtn:SetSize(28, 28); penBtn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 32, -62)
    penBtn:SetNormalTexture(QUILL)
    penBtn:GetNormalTexture():SetTexCoord(0.07, 0.93, 0.07, 0.93)
    penBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    penBtn:SetScript("OnClick", function() leftMode = "pen"; penMode.enabled = true; refreshPalette() end)
    penBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Pen mode"); GameTooltip:Show()
    end)
    penBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    iconControls = CreateFrame("Frame", nil, leftPanel)
    iconControls:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 2, -94)
    iconControls:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -2, 4)

    penControls = CreateFrame("Frame", nil, leftPanel)
    penControls:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 2, -94)
    penControls:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -2, 4)
    penControls:Hide()
    plannerHistory.refreshButtons()
end

refreshPalette = function()
    if not iconControls or not penControls then return end
    for _, c in ipairs({iconControls:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    for _, r in ipairs({iconControls:GetRegions()}) do r:Hide(); r:ClearAllPoints()
        if r.SetText then r:SetText("") end
    end
    for _, c in ipairs({penControls:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    for _, r in ipairs({penControls:GetRegions()}) do r:Hide(); r:ClearAllPoints()
        if r.SetText then r:SetText("") end
    end

    if leftMode == "icons" then
        iconControls:Show(); penControls:Hide()
        local gap = 4
        local groupGap = 10
        local y = 0
        local col, maxCol = 0, 2
        local function encounterPaletteEntries()
            local rp = activePlannerState()
            if not rp or not rp.activeEncounter then return {} end
            local configured = L3F.RPEncounterIcons and L3F.RPEncounterIcons[rp.activeEncounter]
            if configured and #configured > 0 then
                local filtered = {}
                for _, entry in ipairs(configured) do
                    if isEncounterPaletteIcon(entry) then
                        table.insert(filtered, entry)
                    end
                end
                return filtered
            end
            local _, raidCat = findCatalogEncounter(rp.activeEncounter)
            local activeEncounter = rp.activeEncounter
            local target = normalizeKey(activeEncounter)
            local targetRaid = normalizeKey(raidCat and raidCat.raid)
            local out, seen = {}, {}
            local function sameRaidName(name)
                local k = normalizeKey(name)
                if k == "" or targetRaid == "" then return false end
                if k == targetRaid then return true end
                if (k == "tempestkeep" and targetRaid == "theeyetempestkeep")
                   or (k == "theeyetempestkeep" and targetRaid == "tempestkeep") then
                    return true
                end
                if (k == "hyjalsummit" and targetRaid == "battleformounthyjal")
                   or (k == "battleformounthyjal" and targetRaid == "hyjalsummit") then
                    return true
                end
                return false
            end
            local function npcTexture(npc)
                local tex = "Interface\\Icons\\INV_Misc_QuestionMark"
                if npc and npc.spells and npc.spells[1] then
                    tex = (GetSpellTexture and GetSpellTexture(npc.spells[1])) or tex
                end
                return tex
            end
            local function pushNpc(npcOrID, fallbackName)
                local npcID = type(npcOrID) == "table" and npcOrID.id or npcOrID
                if not npcID or seen[npcID] then return end
                seen[npcID] = true
                local npc = type(npcOrID) == "table" and npcOrID or (L3F.npcLookup and L3F.npcLookup[npcID])
                local label = (npc and npc.name) or fallbackName or ("NPC " .. tostring(npcID))
                local tex = npcTexture(npc)
                table.insert(out, {
                    key = "boss:" .. tostring(npcID),
                    label = label,
                    tex = tex,
                    iconTex = tex,
                    npcID = npcID,
                    npcName = label,
                })
            end
            local function pushSectionBosses(section)
                if not section or not section.npcs then return end
                for _, npc in ipairs(section.npcs) do
                    if npc and npc.kind == "boss" then
                        pushNpc(npc)
                    end
                end
            end
            local function sectionMatches(sectionName)
                local s = normalizeKey(sectionName)
                if s == "" then return false end
                if string.find(s, target, 1, true) or string.find(target, s, 1, true) then
                    return true
                end
                for raw in tostring(activeEncounter):gmatch("%w+") do
                    local token = normalizeKey(raw)
                    if #token >= 4 and string.find(s, token, 1, true) then
                        return true
                    end
                end
                return false
            end

            local tree
            if raidCat and L3F.bossTrees then
                tree = L3F.bossTrees[raidCat.raid]
                if not tree then
                    local aliases = {
                        ["theeyetempestkeep"] = "Tempest Keep",
                        ["battleformounthyjal"] = "Hyjal Summit",
                    }
                    tree = L3F.bossTrees[aliases[targetRaid] or ""]
                end
            end
            if tree then
                for _, parent in ipairs(tree) do
                    local pname = normalizeKey(parent and parent.name)
                    if parent and (pname == target or
                       (pname ~= "" and (string.find(target, pname, 1, true) or string.find(pname, target, 1, true)))) then
                        pushNpc(parent.npcID, parent.name)
                        for _, sub in ipairs(parent.subs or {}) do
                            pushNpc(sub.npcID, sub.name)
                        end
                        break
                    end
                end
            end

            if #out == 0 then
                for _, raid in ipairs(L3F.raids or {}) do
                    if sameRaidName(raid.name) then
                        for _, section in ipairs(raid.sections or {}) do
                            for _, npc in ipairs(section.npcs or {}) do
                                local n = normalizeKey(npc and npc.name)
                                if npc and n ~= "" and (n == target
                                   or string.find(n, target, 1, true)
                                   or string.find(target, n, 1, true)) then
                                    pushNpc(npc)
                                    pushSectionBosses(section)
                                    break
                                end
                            end
                            if #out > 0 then break end
                        end
                        break
                    end
                end
            end

            if #out == 0 then
                for _, raid in ipairs(L3F.raids or {}) do
                    if sameRaidName(raid.name) then
                        for _, section in ipairs(raid.sections or {}) do
                            if sectionMatches(section.name) then
                                pushSectionBosses(section)
                                break
                            end
                        end
                        break
                    end
                end
            end

            if #out == 0 then
                for _, raid in ipairs(L3F.raids or {}) do
                    if sameRaidName(raid.name) then
                        L3F.iterNPCs(raid, function(npc)
                            if #out < 12 and npc and npc.kind == "boss" then
                                pushNpc(npc)
                            end
                        end)
                        break
                    end
                end
            end

            if #out == 0 then
                local tex = "Interface\\Icons\\INV_Misc_QuestionMark"
                table.insert(out, {
                    key = "encounter:" .. target,
                    label = activeEncounter,
                    tex = tex,
                    iconTex = tex,
                    npcName = activeEncounter,
                })
            end
            return out
        end
        local function placeRow(entries, kind, sz)
            sz = sz or PALETTE_ICON
            col = 0
            for _, e in ipairs(entries) do
                local px = col * (sz + gap)
                buildPaletteButton(iconControls, kind, e, px, y, sz)
                col = col + 1
                if col >= maxCol then col = 0; y = y + sz + gap end
            end
            if col ~= 0 then y = y + sz + gap end
        end
        placeRow(MARKS, "mark", 26)
        y = y + groupGap - gap
        placeRow(ROLES, "role", 26)
        y = y + groupGap - gap
        placeRow(CLASSES, "class", 26)
        local encounterEntries = encounterPaletteEntries()
        if #encounterEntries > 0 then
            y = y + groupGap - gap
            placeRow(encounterEntries, "encounter", 26)
        end
    else
        iconControls:Hide(); penControls:Show()
        local cy = 0
        local function label(text, x, yOff)
            local fs = penControls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", penControls, "TOPLEFT", x, -yOff)
            fs:SetText(text)
            return fs
        end

        label("Preview", 0, cy); cy = cy + 14
        local prevHost = CreateFrame("Frame", nil, penControls)
        prevHost:SetSize(56, 28)
        prevHost:SetPoint("TOPLEFT", penControls, "TOPLEFT", 0, -cy)
        local prevBg = prevHost:CreateTexture(nil, "BACKGROUND")
        prevBg:SetAllPoints(); prevBg:SetColorTexture(0, 0, 0, 0.35)
        local prevDot = prevHost:CreateTexture(nil, "ARTWORK")
        prevDot:SetTexture("Interface\\Buttons\\WHITE8X8")
        prevDot:SetSize(penMode.size, penMode.size)
        prevDot:SetPoint("CENTER", prevHost, "CENTER")
        do
            local r = tonumber(penMode.color:sub(1,2),16)/255
            local g = tonumber(penMode.color:sub(3,4),16)/255
            local b = tonumber(penMode.color:sub(5,6),16)/255
            prevDot:SetVertexColor(r, g, b, 1)
        end
        cy = cy + 36

        label("Size", 0, cy); cy = cy + 14
        local sizeSlider = CreateFrame("Slider", nil, penControls, "OptionsSliderTemplate")
        sizeSlider:SetWidth(52)
        sizeSlider:SetHeight(18)
        sizeSlider:SetPoint("TOPLEFT", penControls, "TOPLEFT", 2, -cy)
        sizeSlider:SetMinMaxValues(1, 20)
        sizeSlider:SetValueStep(1)
        sizeSlider:SetObeyStepOnDrag(true)
        sizeSlider:SetValue(penMode.size or 4)
        if sizeSlider.Low then sizeSlider.Low:SetText("1") end
        if sizeSlider.High then sizeSlider.High:SetText("20") end
        if sizeSlider.Text then sizeSlider.Text:SetText("") end
        local sizeValue = penControls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sizeValue:SetPoint("TOPLEFT", penControls, "TOPLEFT", 8, -(cy + 16))
        local function syncPenSize(n)
            n = math.max(1, math.min(20, math.floor((tonumber(n) or 4) + 0.5)))
            penMode.size = n
            sizeValue:SetText(tostring(n))
            if prevDot then prevDot:SetSize(n, n) end
        end
        syncPenSize(penMode.size)
        sizeSlider:SetScript("OnValueChanged", function(self, value)
            syncPenSize(value)
        end)
        cy = cy + 42

        label("Color", 0, cy); cy = cy + 14
        local penColorBtn = CreateFrame("Button", nil, penControls)
        penColorBtn:SetSize(28, 22)
        penColorBtn:SetPoint("TOPLEFT", penControls, "TOPLEFT", 6, -cy)
        local penColorSwatch = penColorBtn:CreateTexture(nil, "ARTWORK")
        penColorSwatch:SetPoint("TOPLEFT", penColorBtn, "TOPLEFT", 1, -1)
        penColorSwatch:SetPoint("BOTTOMRIGHT", penColorBtn, "BOTTOMRIGHT", -1, 1)
        penColorSwatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        do
            local r = tonumber(penMode.color:sub(1, 2), 16) / 255
            local g = tonumber(penMode.color:sub(3, 4), 16) / 255
            local b = tonumber(penMode.color:sub(5, 6), 16) / 255
            penColorSwatch:SetVertexColor(r, g, b, 1)
        end
        local penBorder = penColorBtn:CreateTexture(nil, "OVERLAY")
        penBorder:SetAllPoints()
        penBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
        penBorder:SetVertexColor(0, 0, 0, 0.6)
        penBorder:SetDrawLayer("OVERLAY", -2)
        penColorBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        penColorBtn:SetScript("OnClick", function()
            openColorPicker(penMode.color, function(newHex)
                penMode.color = newHex
                local r = tonumber(newHex:sub(1, 2), 16) / 255
                local g = tonumber(newHex:sub(3, 4), 16) / 255
                local b = tonumber(newHex:sub(5, 6), 16) / 255
                penColorSwatch:SetVertexColor(r, g, b, 1)
                if prevDot then prevDot:SetVertexColor(r, g, b, 1) end
            end)
        end)
        penColorBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Pen color")
            GameTooltip:Show()
        end)
        penColorBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cy = cy + 30

        local clearBtn = CreateFrame("Button", nil, penControls, "UIPanelButtonTemplate")
        clearBtn:SetSize(56, 22); clearBtn:SetText("Clear")
        clearBtn:SetPoint("TOPLEFT", penControls, "TOPLEFT", 0, -cy)
        clearBtn:SetScript("OnClick", function()
            local plan = currentPlan()
            if plan then
                plannerHistory.recordPenClear(plan)
                plan.drawings = {}
                notifyEdit("PEN_CLEAR", {})
                refreshDrawings()
            end
        end)
    end
end


-- =============================================================
-- 9. RIGHT PANEL (Notes)
-- =============================================================
local rightPanel, propsHost, encHost, searchHost, notesHost
local rightTabButtons = {}

local function buildRightPanel(parent)
    rightPanel = CreateFrame("Frame", nil, parent)
    rightPanel:SetSize(RIGHT_W, 600)
    rightPanel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -TOP_H)
    rightPanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 4)
    local bg = rightPanel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.25)

    local tabsStrip = CreateFrame("Frame", nil, rightPanel)
    -- Keep the notes area below the co-op panel (220x240) that opens
    -- from the top-right of the planner.
    tabsStrip:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 4, -264)
    tabsStrip:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -4, -264)
    tabsStrip:SetHeight(22)

    local notesLabel = tabsStrip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesLabel:SetPoint("TOPLEFT", tabsStrip, "TOPLEFT", 8, -3)
    notesLabel:SetText("Notes")

    local hostParent = CreateFrame("Frame", nil, rightPanel)
    hostParent:SetPoint("TOPLEFT", tabsStrip, "BOTTOMLEFT", 0, -4)
    hostParent:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -4, 4)
    local hbg = hostParent:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(); hbg:SetColorTexture(0, 0, 0, 0.15)

    encHost    = CreateFrame("ScrollFrame", nil, hostParent, "UIPanelScrollFrameTemplate")
    searchHost = CreateFrame("Frame", nil, hostParent)
    notesHost  = CreateFrame("Frame", nil, hostParent)
    for _, h in ipairs({encHost, searchHost, notesHost}) do
        h:SetPoint("TOPLEFT",     hostParent, "TOPLEFT",      4, -4)
        h:SetPoint("BOTTOMRIGHT", hostParent, "BOTTOMRIGHT", -20, 4)
    end
    local encChild = CreateFrame("Frame", nil, encHost)
    encChild:SetSize(RIGHT_W - 30, 400)
    encHost:SetScrollChild(encChild)
    encHost._child = encChild
end

refreshPropsPanel = function()
    if not propsHost then return end
    for _, c in ipairs({propsHost:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    -- Don't wipe the background region.
    local kept = {}
    for _, r in ipairs({propsHost:GetRegions()}) do
        if r:GetObjectType() == "Texture" and not kept[r] then
            -- Keep all textures (the bg is one of them).
            kept[r] = true
        elseif r.SetText then
            r:Hide(); r:ClearAllPoints(); r:SetText("")
        else
            r:Hide(); r:ClearAllPoints()
        end
    end

    local plan = currentPlan()
    local icon = plan and currentSelection and plan.icons[currentSelection] or nil

    if not icon then
        local fs = propsHost:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        fs:SetPoint("CENTER", propsHost, "CENTER", 0, 0)
        fs:SetText("Nothing selected")
        return
    end

    local row = 6
    local textLabel = propsHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textLabel:SetPoint("TOPLEFT", propsHost, "TOPLEFT", 8, -row); row = row + 16
    textLabel:SetText("Text")

    local textEdit = CreateFrame("EditBox", nil, propsHost, "InputBoxTemplate")
    textEdit:SetSize(RIGHT_W - 30, 22)
    textEdit:SetPoint("TOPLEFT", propsHost, "TOPLEFT", 12, -row); row = row + 28
    textEdit:SetAutoFocus(false); textEdit:SetMaxLetters(24)
    textEdit:SetText(icon.text or "")
    local function broadcastProps()
        notifyEdit("PROPS", {
            tostring(currentSelection or 0),
            icon.color or "ffffff", icon.text or "",
            icon.variant or "", icon.locked and "1" or "0",
            tostring(icon.direction or ""),
        })
    end
    textEdit:SetScript("OnEnterPressed", function(self)
        icon.text = self:GetText() or ""
        broadcastProps()
        self:ClearFocus(); refreshIcons()
    end)
    textEdit:SetScript("OnEditFocusLost", function(self)
        icon.text = self:GetText() or ""
        broadcastProps()
        refreshIcons()
    end)

    local colorLabel = propsHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorLabel:SetPoint("TOPLEFT", propsHost, "TOPLEFT", 8, -row); row = row + 16
    colorLabel:SetText("Color")

    -- The swatch is now a clickable button that opens the WoW
    -- ColorPickerFrame. No more hex EditBox - Willem flagged it as
    -- unfriendly; the WoW palette is the standard UX everyone knows.
    local colorBtn = CreateFrame("Button", nil, propsHost)
    colorBtn:SetSize(28, 22)
    colorBtn:SetPoint("TOPLEFT", propsHost, "TOPLEFT", 12, -row)
    local colorSwatch = colorBtn:CreateTexture(nil, "ARTWORK")
    colorSwatch:SetPoint("TOPLEFT", colorBtn, "TOPLEFT", 1, -1)
    colorSwatch:SetPoint("BOTTOMRIGHT", colorBtn, "BOTTOMRIGHT", -1, 1)
    colorSwatch:SetTexture("Interface\\Buttons\\WHITE8X8")
    local border = colorBtn:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0, 0, 0, 0.6)
    border:SetDrawLayer("OVERLAY", -2)
    local hl = colorBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hl:SetBlendMode("ADD")
    do
        local r = tonumber((icon.color or "ffffff"):sub(1,2), 16)/255
        local g = tonumber((icon.color or "ffffff"):sub(3,4), 16)/255
        local b = tonumber((icon.color or "ffffff"):sub(5,6), 16)/255
        colorSwatch:SetVertexColor(r, g, b, 1)
    end
    local hexLabel = propsHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hexLabel:SetPoint("LEFT", colorBtn, "RIGHT", 8, 0)
    hexLabel:SetText("#" .. (icon.color or "ffffff"))
    colorBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Pick a color")
        GameTooltip:Show()
    end)
    colorBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    colorBtn:SetScript("OnClick", function()
        openColorPicker(icon.color or "ffffff", function(newHex)
            icon.color = newHex
            -- Live-update the swatch + label so the user sees the
            -- color change WHILE the picker is open. Avoids calling
            -- refresh() (which rebuilds propsHost - the picker's
            -- swatchFunc closure references THIS colorSwatch /
            -- hexLabel; if we destroyed them on every picker tick
            -- the in-flight callback would update orphan textures).
            local r = tonumber(newHex:sub(1, 2), 16) / 255
            local g = tonumber(newHex:sub(3, 4), 16) / 255
            local b = tonumber(newHex:sub(5, 6), 16) / 255
            colorSwatch:SetVertexColor(r, g, b, 1)
            hexLabel:SetText("#" .. newHex)
            broadcastProps()
            refreshIcons()
        end)
    end)
    row = row + 28

    if hasDirectionIndicator(icon) then
        local dirHint = propsHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        dirHint:SetPoint("TOPLEFT", propsHost, "TOPLEFT", 8, -row)
        dirHint:SetWidth(RIGHT_W - 24)
        dirHint:SetJustifyH("LEFT")
        dirHint:SetText("Drag the square handle to rotate the direction.")
        row = row + 24
    end

    local variants = (icon.kind == "class") and CLASS_VARIANTS[icon.key] or nil
    if variants then
        local varLabel = propsHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        varLabel:SetPoint("TOPLEFT", propsHost, "TOPLEFT", 8, -row); row = row + 16
        varLabel:SetText("Variant")
        for i, v in ipairs(variants) do
            local b = CreateFrame("Button", nil, propsHost)
            b:SetSize(22, 22)
            b:SetPoint("TOPLEFT", propsHost, "TOPLEFT", 12 + (i - 1) * 26, -row)
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints(); t:SetTexture(v.tex); t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            b:SetNormalTexture(t)
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            local active = (icon.variant == v.key)
            if active then
                local hl = b:CreateTexture(nil, "OVERLAY")
                hl:SetAllPoints(); hl:SetColorTexture(0.3, 0.7, 1, 0.4)
            end
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(v.label); GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function()
                icon.variant = v.key
                broadcastProps()
                scheduleRefresh()
            end)
        end
    end
end

refreshEncounterPanel = function()
    if not encHost then return end
    for k, btn in pairs(rightTabButtons) do
        btn:SetButtonState(rightTab == k and "PUSHED" or "NORMAL")
    end
    encHost:SetShown(rightTab == "encounter")
    searchHost:SetShown(rightTab == "search")
    notesHost:SetShown(rightTab == "notes")

    if rightTab ~= "encounter" then return end
    local child = encHost._child
    for _, c in ipairs({child:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    for _, r in ipairs({child:GetRegions()}) do r:Hide(); r:ClearAllPoints()
        if r.SetText then r:SetText("") end
    end

    local rp = activePlannerState()
    local _, raidCat = findCatalogEncounter(rp.activeEncounter)
    if not raidCat then return end

    local raid = nil
    for _, r in ipairs(L3F.raids or {}) do
        if r.name == raidCat.raid then raid = r; break end
    end
    if not raid then
        local fs = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -8)
        fs:SetText("No encounter data")
        return
    end

    local y = 4
    local rowH = 36   -- taller to give the 3D model some room
    L3F.iterNPCs(raid, function(npc)
        if npc.kind ~= "boss" then return end
        local row = CreateFrame("Frame", nil, child)
        row:SetSize(RIGHT_W - 36, rowH)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints(); rbg:SetColorTexture(0, 0, 0, 0.12)

        -- 3D portrait via PlayerModel SetCreature(npc.id). This works
        -- for any NPC the TBC 2.5.x client knows about; if the call
        -- errors (custom Anniversary npc id missing from the model
        -- DB) we hide the model and fall back to a generic icon.
        local model = CreateFrame("PlayerModel", nil, row)
        model:SetSize(32, 32); model:SetPoint("LEFT", row, "LEFT", 2, 0)
        local ok = pcall(function()
            model:SetCreature(npc.id)
            -- Pull the camera close so we see the head/torso, not a
            -- distant full-body shot. Magic numbers tuned by eye -
            -- WoW's default cam frames most TBC bosses too far out.
            model:SetCamDistanceScale(1.8)
            model:SetPortraitZoom(0.9)
        end)
        local iconFallback
        if not ok then
            model:Hide()
            iconFallback = row:CreateTexture(nil, "ARTWORK")
            iconFallback:SetSize(28, 28)
            iconFallback:SetPoint("LEFT", row, "LEFT", 4, 0)
            iconFallback:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
            iconFallback:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", row, "LEFT", 38, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
        lbl:SetText(npc.name)

        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            rbg:SetColorTexture(1, 1, 1, 0.07)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(npc.name)
            if npc.notes then GameTooltip:AddLine(npc.notes, 0.7, 0.7, 0.7, true) end
            GameTooltip:AddLine("Drag onto the canvas to place a 3D portrait.",
                0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            rbg:SetColorTexture(0, 0, 0, 0.12); GameTooltip:Hide()
        end)

        -- Drag the row onto the canvas to place a kind="boss" icon
        -- (rendered as a small PlayerModel portrait). Uses the same
        -- follower-icon pattern as the palette buttons.
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function()
            dragState.active     = true
            dragState.dragSource = "encounter"
            dragState.kind       = "boss"
            dragState.key        = "boss:" .. tostring(npc.id)
            dragState.npcID      = npc.id
            dragState.npcName    = npc.name
            dragState.color      = "ffffff"
            dragState.variant    = nil
            dragState.fromIcon   = nil
            followerTex:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
            follower:Show()
        end)
        row:SetScript("OnDragStop", function()
            if not dragState.active or dragState.dragSource ~= "encounter" then
                return  -- not our drag; leave state alone
            end
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local l, r = canvasFrame:GetLeft(), canvasFrame:GetRight()
            local t, b = canvasFrame:GetTop(), canvasFrame:GetBottom()
            if l and cx >= l and cx <= r and cy >= b and cy <= t then
                placeIconAt("boss", dragState.key,
                    (cx - l) / (r - l), 1 - (cy - b) / (t - b),
                    { npcID = dragState.npcID, text = dragState.npcName })
            end
            resetDragState()
            follower:Hide()
        end)

        y = y + rowH + 2
    end)
    child:SetHeight(math.max(y + 10, 200))
end

local searchEdit
refreshSearchPanel = function()
    if not searchHost then return end
    if rightTab ~= "search" then return end
    for _, c in ipairs({searchHost:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    for _, r in ipairs({searchHost:GetRegions()}) do r:Hide(); r:ClearAllPoints()
        if r.SetText then r:SetText("") end
    end

    searchEdit = CreateFrame("EditBox", nil, searchHost, "InputBoxTemplate")
    searchEdit:SetSize(RIGHT_W - 40, 22)
    searchEdit:SetPoint("TOPLEFT", searchHost, "TOPLEFT", 8, -4)
    searchEdit:SetAutoFocus(false); searchEdit:SetMaxLetters(40)
    searchEdit:SetText("")

    local list = CreateFrame("ScrollFrame", nil, searchHost, "UIPanelScrollFrameTemplate")
    list:SetPoint("TOPLEFT", searchEdit, "BOTTOMLEFT", 0, -6)
    list:SetPoint("BOTTOMRIGHT", searchHost, "BOTTOMRIGHT", -18, 4)
    local listChild = CreateFrame("Frame", nil, list)
    listChild:SetSize(RIGHT_W - 60, 600)
    list:SetScrollChild(listChild)

    local function runSearch(q)
        for _, c in ipairs({listChild:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        if q == "" then return end
        local needle = q:lower()
        local y = 0
        local hits = 0
        if L3F.bonusItemLookup then
            for spellID, sources in pairs(L3F.bonusItemLookup) do
                local src = sources[1]
                if src and src.kind == "spell" and src.name
                   and src.name:lower():find(needle, 1, true) then
                    local row = CreateFrame("Button", nil, listChild)
                    row:SetSize(RIGHT_W - 60, 24)
                    row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -y)
                    local rbg = row:CreateTexture(nil, "BACKGROUND")
                    rbg:SetAllPoints(); rbg:SetColorTexture(0, 0, 0, 0.12)
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(20, 20); icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    local tex = GetSpellTexture and GetSpellTexture(spellID)
                    if tex then icon:SetTexture(tex) end
                    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    lbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                    lbl:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                    lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
                    lbl:SetText(src.name)
                    row:SetScript("OnEnter", function(self)
                        rbg:SetColorTexture(1, 1, 1, 0.07)
                        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                        if GameTooltip.SetSpellByID then
                            GameTooltip:SetSpellByID(spellID)
                        end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function()
                        rbg:SetColorTexture(0, 0, 0, 0.12); GameTooltip:Hide()
                    end)
                    row:SetScript("OnClick", function()
                        placeIconAt("spell", "spell:" .. spellID, 0.5, 0.5,
                            { spellID = spellID,
                              iconTex = GetSpellTexture and GetSpellTexture(spellID) or nil })
                    end)
                    y = y + 26
                    hits = hits + 1
                    if hits >= 30 then break end
                end
            end
        end
        if hits == 0 then
            local fs = listChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            fs:SetPoint("CENTER", listChild, "CENTER", 0, 0)
            fs:SetText("No matches")
        end
        listChild:SetHeight(math.max(y, 100))
    end

    searchEdit:SetScript("OnTextChanged", function(self)
        runSearch((self:GetText() or ""):gsub("^%s+",""):gsub("%s+$",""))
    end)
end

refreshNotesPanel = function()
    if not notesHost then return end
    if rightTab ~= "notes" then return end
    for _, c in ipairs({notesHost:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    for _, r in ipairs({notesHost:GetRegions()}) do r:Hide(); r:ClearAllPoints() end

    local hint = notesHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", notesHost, "TOPLEFT", 6, -4)
    hint:SetWidth(RIGHT_W - 42)
    hint:SetJustifyH("LEFT")
    hint:SetText("Notes for the selected plan. They are included when sending visuals to raid.")

    local scroll = CreateFrame("ScrollFrame", nil, notesHost, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", notesHost, "TOPLEFT", 4, -30)
    scroll:SetPoint("BOTTOMRIGHT", notesHost, "BOTTOMRIGHT", -20, 4)
    local bg = scroll:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -2, 2)
    bg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 2, -2)
    bg:SetColorTexture(0, 0, 0, 0.35)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal); edit:SetMaxLetters(2000)
    edit:SetWidth(RIGHT_W - 44)
    edit:SetHeight(math.max(260, (notesHost:GetHeight() or 320) - 42))
    local p = currentPlan()
    edit:SetText((p and p.notes) or "")
    edit:SetCursorPosition(0)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local p = currentPlan()
        if p then
            p.notes = self:GetText() or ""
            notifyEdit("NOTES", { p.notes })
        end
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    scroll:SetScrollChild(edit)
end


-- =============================================================
-- 10. TOP STRIP
-- =============================================================
local topStripFrame
local encDD, bgDD, planTabsHost, addBtn
local planTabMenuFrame
local shareBtn, shareAllBtn, importBtn, sendRaidBtn
local planRenamePromptFrame

local function makeGroupedDropdown(parent, name, width, getValue, groupsFn, callback)
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, width)
    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, group in ipairs(groupsFn()) do
            if group.header then
                local info = UIDropDownMenu_CreateInfo()
                info.text = group.header
                info.isTitle = true; info.notCheckable = true
                UIDropDownMenu_AddButton(info, level)
            end
            for _, ent in ipairs(group.entries) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = ent.label
                info.checked = (ent.value == getValue())
                info.func = function() callback(ent.value); CloseDropDownMenus() end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
    UIDropDownMenu_SetText(dd, "")
    return dd
end

local function buildTopStrip(parent)
    topStripFrame = CreateFrame("Frame", nil, parent)
    topStripFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
    topStripFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
    topStripFrame:SetHeight(TOP_H - 6)

    local topLeftAnchor = CreateFrame("Frame", nil, topStripFrame)
    topLeftAnchor:SetSize(1, 1)
    topLeftAnchor:SetPoint("TOPLEFT", topStripFrame, "TOPLEFT", 4, -2)

    encDD = makeGroupedDropdown(topStripFrame, "L3FRPEncounterDD", 180,
        function()
            local rp = activePlannerState()
            return rp and rp.activeEncounter
        end,
        function()
            local groups = {}
            local raidList
            local raidInInstance = currentInstanceRaidCatalog()
            if raidInInstance then
                raidList = { raidInInstance }
            else
                raidList = L3F.raidPlannerCatalog or {}
            end
            for _, raid in ipairs(raidList) do
                local entries = {}
                for _, enc in ipairs(raid.encounters) do
                    table.insert(entries, { value = enc.name, label = enc.name })
                end
                table.insert(groups, { header = raid.raid, entries = entries })
            end
            return groups
        end,
        function(value)
            if isCoOpGuest() then return end
            local rp = activePlannerState()
            rp.activeEncounter = value
            rp.activePlanIdx = 1
            ensurePlansFor(value)
            -- Co-op: host-only navigation broadcast. The receiver's
            -- BroadcastDelta NAV handler ignores planIdx/background
            -- changes from non-hosts.
            notifyEdit("NAV", { value, "1", "" })
            scheduleRefresh()
        end)
    encDD:SetPoint("TOPLEFT", topLeftAnchor, "TOPLEFT", -12, 0)

    bgDD = makeGroupedDropdown(topStripFrame, "L3FRPBackgroundDD", 110,
        function()
            local p = currentPlan(); return p and p.background
        end,
        function()
            local rp = activePlannerState()
            local enc = findCatalogEncounter(rp and rp.activeEncounter)
            local entries = {}
            for _, bg in ipairs(enc and enc.backgrounds or {}) do
                table.insert(entries, { value = bg.slug, label = bg.label })
            end
            return { { entries = entries } }
        end,
        function(value)
            if isCoOpGuest() then return end
            local p = currentPlan()
            if p then
                p.background = value
                local rp = activePlannerState()
                notifyEdit("NAV", {
                    rp.activeEncounter or "",
                    tostring(rp.activePlanIdx or 1),
                    value or "",
                })
                scheduleRefresh()
            end
        end)
    bgDD:SetPoint("LEFT", encDD, "RIGHT", 2, 0)

    shareBtn = CreateFrame("Button", nil, topStripFrame, "UIPanelButtonTemplate")
    shareBtn:SetSize(60, 22); shareBtn:SetText("Share")
    shareBtn:SetPoint("LEFT", bgDD, "RIGHT", 6, 2)
    shareBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Export current plan as a share string")
        GameTooltip:AddLine("Paste-able into chat / Discord. The receiving",
            0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("guildie pastes back into the Import dialog.",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    shareBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    shareAllBtn = CreateFrame("Button", nil, topStripFrame, "UIPanelButtonTemplate")
    shareAllBtn:SetSize(72, 22); shareAllBtn:SetText("Share-all")
    shareAllBtn:SetPoint("LEFT", shareBtn, "RIGHT", 4, 0)
    shareAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Export all plans for the selected encounter")
        GameTooltip:AddLine("Creates one string containing every saved plan tab.",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    shareAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    importBtn = CreateFrame("Button", nil, topStripFrame, "UIPanelButtonTemplate")
    importBtn:SetSize(60, 22); importBtn:SetText("Import")
    importBtn:SetPoint("LEFT", shareAllBtn, "RIGHT", 4, 0)
    importBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Import a Raid Planner export")
        GameTooltip:AddLine("Supports both Share and Share-all strings.",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    importBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    sendRaidBtn = CreateFrame("Button", nil, topStripFrame, "UIPanelButtonTemplate")
    sendRaidBtn:SetSize(140, 22); sendRaidBtn:SetText("Send visuals to raid")
    sendRaidBtn:SetPoint("LEFT", importBtn, "RIGHT", 4, 0)
    sendRaidBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Send saved visual plans to your party/raid")
        GameTooltip:AddLine("Receiver gets a closable visual preview popup with plan tabs.",
            0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Raid: only leader or assistants can send.",
            1.0, 0.82, 0.0, true)
        GameTooltip:Show()
    end)
    sendRaidBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sendRaidBtn:SetScript("OnClick", function()
        if L3F.RPCoOp and L3F.RPCoOp.ShareToRaid then
            L3F.RPCoOp.ShareToRaid()
        end
    end)

    planTabsHost = CreateFrame("Frame", nil, topStripFrame)
    planTabsHost:SetPoint("TOPLEFT", topStripFrame, "TOPLEFT", 4, -44)
    planTabsHost:SetSize(400, 24)

    addBtn = CreateFrame("Button", nil, topStripFrame, "UIPanelButtonTemplate")
    addBtn:SetSize(28, 24); addBtn:SetText("+")
    addBtn:SetScript("OnClick", function()
        if isCoOpGuest() then return end
        local rp = activePlannerState()
        local plans = ensurePlansFor(rp.activeEncounter)
        table.insert(plans, newEmptyPlan(rp.activeEncounter))
        rp.activePlanIdx = #plans
        notifyEdit("NEWPL", { tostring(#plans) })
        scheduleRefresh()
    end)
end

local function ensurePlanRenamePrompt()
    if planRenamePromptFrame then return planRenamePromptFrame end
    local f = CreateFrame("Frame", "L3FRPPlanRenamePrompt", UIParent)
    f:SetSize(230, 96)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.05, 0.96)
    local bd = f:CreateTexture(nil, "BORDER")
    bd:SetPoint("TOPLEFT", -1, 1); bd:SetPoint("BOTTOMRIGHT", 1, -1)
    bd:SetColorTexture(0.35, 0.35, 0.35, 0.85)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetText("Rename plan")

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(194, 22)
    edit:SetPoint("TOP", title, "BOTTOM", 0, -8)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(32)
    f.edit = edit

    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(86, 22)
    saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10)
    saveBtn:SetText(SAVE or "Save")
    saveBtn:SetScript("OnClick", function()
        if not f.plan then f:Hide(); return end
        local newName = (f.edit:GetText() or ""):gsub("^%s*(.-)%s*$", "%1")
        if newName == "" then newName = "Plan" end
        f.plan.name = newName
        scheduleRefresh()
        f:Hide()
    end)

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(86, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)
    cancelBtn:SetText(CANCEL or "Cancel")
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    edit:SetScript("OnEnterPressed", function() saveBtn:Click() end)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    f:Hide()
    planRenamePromptFrame = f
    return f
end

local function showPlanRenamePrompt(plan)
    if not plan then return end
    local f = ensurePlanRenamePrompt()
    f.plan = plan
    f.edit:SetText(plan.name or "")
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

local function deletePlanAt(planIdx, planRef)
    if isCoOpGuest() then return end
    local rp = activePlannerState()
    if not rp then return end
    local plans = ensurePlansFor(rp.activeEncounter)
    if #plans <= 1 then return end

    local idx = planIdx
    if planRef and plans[idx] ~= planRef then
        idx = nil
        for i, plan in ipairs(plans) do
            if plan == planRef then
                idx = i
                break
            end
        end
    end
    if not (idx and plans[idx]) then return end

    table.remove(plans, idx)
    rp.activePlanIdx = math.max(1, math.min(#plans, rp.activePlanIdx or 1))
    notifyEdit("DELPL", { tostring(idx) })
    scheduleRefresh()
end

local function showDeletePlanConfirm(planIdx, planRef)
    if not planRef then return end
    if not StaticPopupDialogs["L3F_RP_CONFIRM_DELETE_PLAN"] then
        StaticPopupDialogs["L3F_RP_CONFIRM_DELETE_PLAN"] = {
            text = "Are you sure you want to delete \"%s\"?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function(_, data)
                if data then
                    deletePlanAt(data.planIdx, data.planRef)
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
    end

    local planName = (planRef.name and planRef.name ~= "") and planRef.name or ("Plan " .. tostring(planIdx or ""))
    StaticPopup_Show("L3F_RP_CONFIRM_DELETE_PLAN", planName, nil, {
        planIdx = planIdx,
        planRef = planRef,
    })
end

local function openPlanTabMenu(anchorBtn, planIdx)
    if isCoOpGuest() then return end
    if not planTabMenuFrame then
        planTabMenuFrame = CreateFrame("Frame", "L3FRPPlanTabMenu", UIParent)
        planTabMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        planTabMenuFrame:SetFrameLevel(200)
        planTabMenuFrame:SetToplevel(true)
        planTabMenuFrame:SetClampedToScreen(true)
        planTabMenuFrame:EnableMouse(true)
        planTabMenuFrame:SetSize(150, 6 + 22 * 3)
        local bg = planTabMenuFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
        planTabMenuFrame:Hide()
        planTabMenuFrame.buttons = {}
    end

    local menu = planTabMenuFrame
    local rp = activePlannerState()
    local plans = ensurePlansFor(rp.activeEncounter)
    local targetPlan = plans[planIdx]
    if not targetPlan then return end

    local cursorX, cursorY
    if GetCursorPosition and UIParent and UIParent.GetEffectiveScale then
        local s = UIParent:GetEffectiveScale() or 1
        local x, y = GetCursorPosition()
        if x and y then
            cursorX = x / s
            cursorY = y / s
        end
    end
    menu:ClearAllPoints()
    if cursorX and cursorY then
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX + 8, cursorY - 8)
    else
        menu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMRIGHT", 0, 0)
    end
    menu:Show()

    local items = {
        { label = "Rename", action = function()
            rp.activePlanIdx = planIdx
            notifyEdit("NAV", { rp.activeEncounter or "", tostring(planIdx), "" })
            scheduleRefresh()
            showPlanRenamePrompt(targetPlan)
            menu:Hide()
        end },
        { label = "Delete", action = function()
            if #plans > 1 and plans[planIdx] then
                showDeletePlanConfirm(planIdx, targetPlan)
            end
            menu:Hide()
        end },
        { label = "Cancel", action = function()
            menu:Hide()
        end },
    }
    for _, btn in ipairs(menu.buttons) do btn:Hide() end
    for i, item in ipairs(items) do
        local b = menu.buttons[i] or CreateFrame("Button", nil, menu)
        menu.buttons[i] = b
        b:SetSize(140, 20)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, -3 - (i - 1) * 22)
        b:Show()
        if not b.text then
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
        end
        b.text:SetText(item.label)
        b:SetScript("OnClick", item.action)
        local bg = b.bg or b:CreateTexture(nil, "BACKGROUND")
        b.bg = bg
        bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0)
        b:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.12) end)
        b:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0) end)
    end
    menu:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() and IsMouseButtonDown
           and IsMouseButtonDown("LeftButton") then
            self:Hide(); self:SetScript("OnUpdate", nil)
        end
    end)
end

refreshTopStrip = function()
    if not topStripFrame then return end
    local rp = activePlannerState()
    local guestLocked = isCoOpGuest()
    syncEncounterToInstanceRaid()
    UIDropDownMenu_SetText(encDD, rp.activeEncounter or "(no encounter)")
    local plan = currentPlan()
    UIDropDownMenu_SetText(bgDD, plan and plan.background or "(no background)")
    if encDD then encDD:SetShown(not guestLocked) end
    if bgDD then bgDD:SetShown(not guestLocked) end
    if shareBtn then shareBtn:SetShown(not guestLocked) end
    if shareAllBtn then shareAllBtn:SetShown(not guestLocked) end
    if importBtn then importBtn:SetShown(not guestLocked) end
    if sendRaidBtn then sendRaidBtn:SetShown(not guestLocked) end
    if sendRaidBtn then
        local canSend = false
        if guestLocked then
            canSend = false
        elseif IsInRaid() then
            canSend = UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
        elseif IsInGroup() then
            canSend = UnitIsGroupLeader("player")
        end
        if canSend then
            sendRaidBtn:Enable()
        else
            sendRaidBtn:Disable()
        end
    end

    for _, c in ipairs({planTabsHost:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    local plans = ensurePlansFor(rp.activeEncounter)
    local cx = 0
    for i = 1, #plans do
        local tabPlan = plans[i]
        local tabLabel = ((tabPlan and tabPlan.name) or ""):gsub("^%s*(.-)%s*$", "%1")
        if tabLabel == "" then tabLabel = tostring(i) end
        local b = CreateFrame("Button", nil, planTabsHost, "UIPanelButtonTemplate")
        b:SetText(tabLabel)
        local textW = b.GetTextWidth and b:GetTextWidth() or 24
        local tabW = math.max(28, math.min(96, math.floor(textW + 16)))
        b:SetSize(tabW, 22)
        b:SetPoint("LEFT", planTabsHost, "LEFT", cx, 0)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if i == rp.activePlanIdx then
            b:SetButtonState("PUSHED", true)
            local function edgeTexture()
                local t = b:CreateTexture(nil, "OVERLAY")
                t:SetTexture("Interface\\Buttons\\WHITE8X8")
                t:SetVertexColor(1.0, 0.9, 0.1, 0.95)
                t:SetDrawLayer("OVERLAY", -3)
                return t
            end
            local topEdge = edgeTexture()
            topEdge:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
            topEdge:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
            topEdge:SetHeight(1)

            local bottomEdge = edgeTexture()
            bottomEdge:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
            bottomEdge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
            bottomEdge:SetHeight(1)

            local leftEdge = edgeTexture()
            leftEdge:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
            leftEdge:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
            leftEdge:SetWidth(1)

            local rightEdge = edgeTexture()
            rightEdge:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
            rightEdge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
            rightEdge:SetWidth(1)
        end
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tabLabel)
            if guestLocked then
                GameTooltip:AddLine("The host controls plan selection in co-op.", 0.7, 0.7, 0.7, true)
            else
                GameTooltip:AddLine("Left click: select", 0.7, 0.7, 0.7, true)
                GameTooltip:AddLine("Right click: rename / delete", 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self, button)
            if guestLocked then return end
            if button == "RightButton" or button == "Button2" then
                openPlanTabMenu(self, i)
                return
            end
            rp.activePlanIdx = i
            notifyEdit("NAV", { rp.activeEncounter or "", tostring(i), "" })
            scheduleRefresh()
        end)
        cx = cx + tabW + 4
    end
    addBtn:ClearAllPoints()
    addBtn:SetPoint("LEFT", planTabsHost, "LEFT", cx + 4, 0)
    addBtn:SetShown(not guestLocked)
end


-- =============================================================
-- 11. SHARE / EXPORT (L3F2 string)
-- =============================================================
local LibDeflate = LibStub and LibStub("LibDeflate", true)
local RP_MAX_COMPRESS = { level = 9, strategy = "dynamic" }

local function encodePlanIcon(ic)
    local parts = {
        ic.kind or "",
        ic.key or "",
        string.format("%.4f", ic.x or 0.5),
        string.format("%.4f", ic.y or 0.5),
        ic.color or "ffffff",
        ic.variant or "",
        ic.locked and "1" or "0",
        (ic.text or ""):gsub(";", " "):gsub("|", "/"),
        tostring(ic.direction or ""),
    }
    return table.concat(parts, ":")
end

local function encodePlanStroke(s)
    local pts = {}
    for _, p in ipairs(s.points or {}) do
        table.insert(pts, string.format("%.3f,%.3f", p.x, p.y))
    end
    return table.concat({
        s.color or "ffffff",
        tostring(s.size or 4),
        tostring(s.fade or 0),
        table.concat(pts, "/"),
    }, ":")
end

local function encodePlanBody(plan, encounterName)
    local iconsCSV = {}
    for _, ic in ipairs((plan and plan.icons) or {}) do
        table.insert(iconsCSV, encodePlanIcon(ic))
    end
    local drawCSV = {}
    for _, s in ipairs((plan and plan.drawings) or {}) do
        table.insert(drawCSV, encodePlanStroke(s))
    end
    return "RPLAN1|"
        .. (encounterName or ""):gsub("|", "/") .. "|"
        .. (((plan and plan.name) or ""):gsub("|", "/")) .. "|"
        .. ((plan and plan.background) or "") .. "|"
        .. table.concat(iconsCSV, ";") .. "|"
        .. table.concat(drawCSV, ";") .. "|"
        .. (((plan and plan.notes) or ""):gsub("|", "/"))
end

local function encodeWireBody(inner, opts, compressedPrefix, rawPrefix)
    opts = opts or {}
    compressedPrefix = compressedPrefix
        or ((opts.wire == "addon") and "L3FRA:" or "L3FRP:")
    rawPrefix = rawPrefix
        or ((opts.wire == "addon") and "L3FRA1:" or "L3FRP1:")
    if LibDeflate then
        local compressed = LibDeflate:CompressDeflate(
            inner, opts.maxCompress and RP_MAX_COMPRESS or nil)
        if opts.wire == "addon" then
            return compressedPrefix .. LibDeflate:EncodeForWoWAddonChannel(compressed)
        end
        return compressedPrefix .. LibDeflate:EncodeForPrint(compressed)
    end
    return rawPrefix .. inner
end

local function serializePlan(plan, encounterName, opts)
    return encodeWireBody(encodePlanBody(plan, encounterName), opts)
end

local function serializePlanBundle(plans, encounterName, activePlanIdx, opts)
    opts = opts or {}
    local chunks = {}
    local count = 0
    for _, plan in ipairs(plans or {}) do
        local body = encodePlanBody(plan, encounterName)
        count = count + 1
        chunks[#chunks + 1] = tostring(#body) .. ":" .. body
    end
    if count == 0 then return nil end

    local inner = "RPLANS1|"
        .. (encounterName or ""):gsub("|", "/") .. "|"
        .. tostring(activePlanIdx or 1) .. "|"
        .. tostring(count) .. "|"
        .. table.concat(chunks)

    local compressedPrefix = (opts.wire == "addon") and "L3FRBA:" or "L3FRBP:"
    local rawPrefix = (opts.wire == "addon") and "L3FRBA1:" or "L3FRBP1:"
    return encodeWireBody(inner, opts, compressedPrefix, rawPrefix)
end

local function openShareDialog()
    local plan = currentPlan()
    if not plan then return end
    local rp = activePlannerState()
    local str = serializePlan(plan, rp and rp.activeEncounter)
    if L3F.ShowStringDialog then
        L3F.ShowStringDialog({
            title = "Raid plan export - Ctrl+A then Ctrl+C to copy:",
            text = str,
            acceptText = "Close",
            showCancel = false,
            selectAll = true,
        })
    else
        print("|cffffd100L3FTools:|r " .. str)
    end
end

local function openShareAllDialog()
    local rp = activePlannerState()
    if not (rp and rp.activeEncounter) then return end
    local plans = ensurePlansFor(rp.activeEncounter)
    local str = serializePlanBundle(plans, rp.activeEncounter, rp.activePlanIdx)
    if not str then return end

    if L3F.ShowStringDialog then
        L3F.ShowStringDialog({
            title = "Raid plans export - Ctrl+A then Ctrl+C to copy:",
            text = str,
            acceptText = "Close",
            showCancel = false,
            selectAll = true,
        })
    else
        print("|cffffd100L3FTools:|r " .. str)
    end
end


-- =============================================================
-- 11b. CO-OP INTEGRATION (exports for RaidPlannerCoOp.lua)
-- =============================================================
-- Decode an L3FRP/L3FRP1 (print wire) or L3FRA/L3FRA1 (addon wire)
-- share string back to a plan table.
local function decodeWireBody(str)
    if not str or str == "" then return nil end
    local body
    if str:sub(1, 8) == "L3FRBP1:" then
        body = str:sub(9)
    elseif str:sub(1, 8) == "L3FRBA1:" then
        body = str:sub(9)
    elseif str:sub(1, 7) == "L3FRBP:" then
        if not LibDeflate then return nil end
        local raw = LibDeflate:DecodeForPrint(str:sub(8))
        if not raw then return nil end
        body = LibDeflate:DecompressDeflate(raw)
    elseif str:sub(1, 7) == "L3FRBA:" then
        if not LibDeflate then return nil end
        local raw = LibDeflate:DecodeForWoWAddonChannel(str:sub(8))
        if not raw then return nil end
        body = LibDeflate:DecompressDeflate(raw)
    elseif str:sub(1, 7) == "L3FRP1:" then
        body = str:sub(8)
    elseif str:sub(1, 7) == "L3FRA1:" then
        body = str:sub(8)
    elseif str:sub(1, 6) == "L3FRP:" then
        if not LibDeflate then return nil end
        local raw = LibDeflate:DecodeForPrint(str:sub(7))
        if not raw then return nil end
        body = LibDeflate:DecompressDeflate(raw)
    elseif str:sub(1, 6) == "L3FRA:" then
        if not LibDeflate then return nil end
        local raw = LibDeflate:DecodeForWoWAddonChannel(str:sub(7))
        if not raw then return nil end
        body = LibDeflate:DecompressDeflate(raw)
    else
        return nil
    end
    return body
end

local function decodePlanBody(body)
    if not body or body:sub(1, 7) ~= "RPLAN1|" then return nil end
    local _, encName, planName, bgSlug, iconsCSV, drawCSV, notes =
        strsplit("|", body)
    local plan = {
        name       = planName or "Plan",
        background = (bgSlug ~= "" and bgSlug) or nil,
        icons      = {},
        drawings   = {},
        notes      = notes or "",
    }
    if iconsCSV and iconsCSV ~= "" then
        for entry in string.gmatch(iconsCSV, "[^;]+") do
            local kind, key, xs, ys, color, variant, locked, text, direction =
                strsplit(":", entry)
            table.insert(plan.icons, {
                kind    = kind or "",
                key     = key or "",
                x       = tonumber(xs) or 0.5,
                y       = tonumber(ys) or 0.5,
                color   = (color ~= "" and color) or "ffffff",
                variant = (variant ~= "" and variant) or nil,
                locked  = locked == "1",
                text    = (text and text ~= "") and text or nil,
                direction = tonumber(direction),
            })
        end
    end
    if drawCSV and drawCSV ~= "" then
        for entry in string.gmatch(drawCSV, "[^;]+") do
            local color, sizeStr, fadeStr, ptsCSV = strsplit(":", entry)
            local pts = {}
            if ptsCSV then
                for pair in string.gmatch(ptsCSV, "[^/]+") do
                    local x, y = strsplit(",", pair)
                    table.insert(pts, {
                        x = tonumber(x) or 0,
                        y = tonumber(y) or 0,
                    })
                end
            end
            table.insert(plan.drawings, {
                color  = color or "ffffff",
                size   = tonumber(sizeStr) or 4,
                fade   = tonumber(fadeStr) or 0,
                points = pts,
            })
        end
    end
    return plan, encName
end

local function deserializePlan(str)
    return decodePlanBody(decodeWireBody(str))
end

local function deserializePlanBundle(str, fallbackPlanIdx)
    local body = decodeWireBody(str)
    if not body then return nil end

    if body:sub(1, 8) == "RPLANS1|" then
        local _, encName, activeIdxStr, countStr, chunks =
            strsplit("|", body, 5)
        local count = tonumber(countStr) or 0
        local plans = {}
        local pos = 1
        chunks = chunks or ""

        for _ = 1, count do
            local colon = string.find(chunks, ":", pos, true)
            if not colon then return nil end
            local len = tonumber(string.sub(chunks, pos, colon - 1))
            if not len then return nil end
            local startPos = colon + 1
            local planBody = string.sub(chunks, startPos, startPos + len - 1)
            if #planBody < len then return nil end
            local plan = decodePlanBody(planBody)
            if plan then
                plans[#plans + 1] = plan
            end
            pos = startPos + len
        end

        if #plans == 0 then return nil end
        return {
            encounterName = encName,
            activePlanIdx = tonumber(activeIdxStr) or fallbackPlanIdx or 1,
            plans = plans,
        }
    end

    local plan, encName = decodePlanBody(body)
    if not plan then return nil end
    return {
        encounterName = encName,
        activePlanIdx = fallbackPlanIdx or 1,
        plans = { plan },
    }
end

local function openImportDialog()
    if isCoOpGuest() then return end
    if not L3F.ShowStringDialog then
        print("|cffff5555L3FTools:|r Import dialog is not available.")
        return
    end

    L3F.ShowStringDialog({
        title = "Paste a Raid Planner export string, then Import:",
        text = "",
        acceptText = "Import",
        showCancel = true,
        onAccept = function(str)
            str = (str or ""):gsub("^%s+", ""):gsub("%s+$", "")
            local bundle = deserializePlanBundle(str)
            if not (bundle and bundle.plans and bundle.plans[1]) then
                print("|cffff5555L3FTools:|r Import failed: invalid Raid Planner export.")
                return
            end

            local rp = activePlannerState()
            local encName = (bundle.encounterName and bundle.encounterName ~= "")
                and bundle.encounterName or rp.activeEncounter
            if not encName or encName == "" then
                print("|cffff5555L3FTools:|r Import failed: missing encounter name.")
                return
            end

            rp.plansByEncounter = rp.plansByEncounter or {}
            rp.plansByEncounter[encName] = rp.plansByEncounter[encName] or {}
            local targetPlans = rp.plansByEncounter[encName]
            local firstImportedIdx = #targetPlans + 1

            local function nameExists(name)
                for _, plan in ipairs(targetPlans) do
                    if plan.name == name then return true end
                end
                return false
            end

            local function uniquePlanName(base)
                base = (base and base ~= "") and base or "Imported plan"
                local name = base
                local n = 2
                while nameExists(name) do
                    name = base .. " (" .. tostring(n) .. ")"
                    n = n + 1
                end
                return name
            end

            for _, plan in ipairs(bundle.plans or {}) do
                plan.name = uniquePlanName(plan.name)
                table.insert(targetPlans, plan)
            end

            rp.activeEncounter = encName
            rp.activePlanIdx = firstImportedIdx
            plannerHistory.clear()
            scheduleRefresh()
            print(string.format("|cffffd100L3FTools:|r Imported %d raid plan%s for %s.",
                #bundle.plans, (#bundle.plans == 1 and "" or "s"), encName))
        end,
    })
end

L3F._RPSerializePlan = serializePlan
L3F._RPSerializePlanBundle = serializePlanBundle

function L3F._RPApplySnapshot(encName, planIdx, payload)
    local bundle = deserializePlanBundle(payload, planIdx)
    if not (bundle and bundle.plans and bundle.plans[1]) then return end
    local targetEnc = (encName and encName ~= "") and encName
        or bundle.encounterName
    if not targetEnc or targetEnc == "" then return end

    local rp = activePlannerState()
    rp.plansByEncounter = rp.plansByEncounter or {}
    rp.plansByEncounter[targetEnc] = bundle.plans
    rp.activeEncounter = targetEnc
    rp.activePlanIdx = math.max(1, math.min(#bundle.plans,
        bundle.activePlanIdx or planIdx or 1))
    scheduleRefresh()
end

function L3F._RPApplyDelta(deltaType, encName, planIdx, ...)
    local rp = activePlannerState()
    if not rp then return end
    rp.plansByEncounter = rp.plansByEncounter or {}
    rp.plansByEncounter[encName] = rp.plansByEncounter[encName] or {}
    local plans = rp.plansByEncounter[encName]
    if #plans == 0 then
        table.insert(plans, newEmptyPlan(encName))
    end
    local plan = plans[planIdx] or plans[1]

    if deltaType == "PLACE" then
        local kind, key, xs, ys, color, text, variant, locked, direction = ...
        table.insert(plan.icons, {
            kind    = kind or "",
            key     = key or "",
            x       = tonumber(xs) or 0.5,
            y       = tonumber(ys) or 0.5,
            color   = color or "ffffff",
            text    = (text and text ~= "") and text or nil,
            variant = (variant and variant ~= "") and variant or nil,
            locked  = locked == "1",
            direction = tonumber(direction),
        })
    elseif deltaType == "MOVE" then
        local idxStr, xs, ys = ...
        local idx = tonumber(idxStr)
        local ic = idx and plan.icons[idx]
        if ic then
            ic.x = tonumber(xs) or ic.x
            ic.y = tonumber(ys) or ic.y
        end
    elseif deltaType == "RM" then
        local idxStr = ...
        local idx = tonumber(idxStr)
        if idx and plan.icons[idx] then
            table.remove(plan.icons, idx)
        end
    elseif deltaType == "PROPS" then
        local idxStr, color, text, variant, locked, direction = ...
        local idx = tonumber(idxStr)
        local ic = idx and plan.icons[idx]
        if ic then
            ic.color   = color or ic.color
            ic.text    = (text and text ~= "") and text or nil
            ic.variant = (variant and variant ~= "") and variant or nil
            ic.locked  = locked == "1"
            ic.direction = tonumber(direction) or ic.direction
        end
    elseif deltaType == "DRAW" then
        local color, sizeStr, fadeStr, ptsCSV = ...
        local pts = {}
        if ptsCSV then
            for pair in string.gmatch(ptsCSV, "[^/]+") do
                local x, y = strsplit(",", pair)
                table.insert(pts, {
                    x = tonumber(x) or 0,
                    y = tonumber(y) or 0,
                })
            end
        end
        plan.drawings = plan.drawings or {}
        table.insert(plan.drawings, {
            color  = color or "ffffff",
            size   = tonumber(sizeStr) or 4,
            fade   = tonumber(fadeStr) or 0,
            points = pts,
        })
    elseif deltaType == "PEN_CLEAR" then
        plan.drawings = {}
    elseif deltaType == "RMDRAW" then
        local idxStr = ...
        local idx = tonumber(idxStr)
        if idx and plan.drawings and plan.drawings[idx] then
            table.remove(plan.drawings, idx)
        end
    elseif deltaType == "CLEAR" then
        plan.icons = {}; plan.drawings = {}
        if plannerHistory.currentPlanMatches(plan) then
            currentSelection = nil
            plannerHistory.clear()
        end
    elseif deltaType == "NAV" then
        local newEnc, newPlanIdxStr, bgSlug = ...
        if newEnc and newEnc ~= "" then
            rp.activeEncounter = newEnc
            rp.plansByEncounter[newEnc] = rp.plansByEncounter[newEnc] or {}
            if #rp.plansByEncounter[newEnc] == 0 then
                table.insert(rp.plansByEncounter[newEnc], newEmptyPlan(newEnc))
            end
        end
        if newPlanIdxStr then
            rp.activePlanIdx = tonumber(newPlanIdxStr) or rp.activePlanIdx
        end
        if bgSlug and bgSlug ~= "" then
            local p = rp.plansByEncounter[rp.activeEncounter]
            local cur = p and p[rp.activePlanIdx]
            if cur then cur.background = bgSlug end
        end
    elseif deltaType == "NEWPL" then
        local newIdxStr = ...
        table.insert(plans, newEmptyPlan(encName))
        rp.activePlanIdx = tonumber(newIdxStr) or #plans
    elseif deltaType == "DELPL" then
        local idxStr = ...
        local idx = tonumber(idxStr) or planIdx
        if #plans > 1 and plans[idx] then
            table.remove(plans, idx)
            rp.activePlanIdx = math.max(1, math.min(#plans, rp.activePlanIdx or 1))
        end
    elseif deltaType == "NOTES" then
        local text = ...
        plan.notes = text or ""
    end

    scheduleRefresh()
end


-- =============================================================
-- 11c. SHARE-BUTTON POPUP (Copy string)
-- =============================================================
local sharePopup
local function openSharePopup()
    if not sharePopup then
        local f = CreateFrame("Frame", "L3FRPSharePopup", UIParent,
            "BasicFrameTemplateWithInset")
        f:SetSize(300, 100)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true); f:SetClampedToScreen(true)
        f:EnableMouse(true); f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.TitleText then f.TitleText:SetText("Share plan") end
        tinsert(UISpecialFrames, "L3FRPSharePopup")
        local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        copyBtn:SetSize(260, 24); copyBtn:SetText("Copy as L3F2 string")
        copyBtn:SetPoint("TOP", f, "TOP", 0, -34)
        copyBtn:SetScript("OnClick", function()
            f:Hide()
            openShareDialog()
        end)
        sharePopup = f
    end
    sharePopup:Show()
end


-- =============================================================
-- 11d. INCOMING SHARE POPUP (visual-only preview, no auto-import)
-- =============================================================
local incomingSharePopup
local incomingShareDrawSegments = {}
local renderIncomingSharePreview

local function cleanedPlanNote(plan)
    local note = plan and plan.notes or ""
    note = tostring(note):gsub("^%s*(.-)%s*$", "%1")
    if note == "" then return nil end
    return note
end

local function clearIncomingShareDrawSegments()
    for i = 1, #incomingShareDrawSegments do
        local tex = incomingShareDrawSegments[i]
        if tex then
            tex:Hide()
            tex:SetParent(nil)
        end
    end
    wipe(incomingShareDrawSegments)
end

local function drawIncomingShareSegment(parent, x1, y1, x2, y2, size, r, g, b, a)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return end
    local pad = math.max(1, (size or 4) * 0.35)
    local ux, uy = dx / len, dy / len
    local sx, sy = x1 - ux * pad, y1 - uy * pad
    local ex, ey = x2 + ux * pad, y2 + uy * pad
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetVertexColor(r, g, b, a)
    tex:SetWidth(len + (2 * pad))
    tex:SetHeight(size)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", parent, "TOPLEFT", (sx + ex) / 2, -(sy + ey) / 2)
    tex:SetRotation(math.atan2(-dy, dx))
    incomingShareDrawSegments[#incomingShareDrawSegments + 1] = tex
end

local function ensureIncomingSharePopup()
    if incomingSharePopup then return incomingSharePopup end
    local f = CreateFrame("Frame", "L3FRPIncomingSharePreview", UIParent,
        "BasicFrameTemplateWithInset")
    f:SetSize(860, 620)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true); f:SetClampedToScreen(true)
    f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "L3FRPIncomingSharePreview")
    if f.TitleText then f.TitleText:SetText("Shared visual") end

    f.meta = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.meta:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
    f.meta:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -34)
    f.meta:SetJustifyH("LEFT")

    f.planTabsHost = CreateFrame("Frame", nil, f)
    f.planTabsHost:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -56)
    f.planTabsHost:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -56)
    f.planTabsHost:SetHeight(24)
    f.planTabsHost:Hide()
    f.planTabButtons = {}

    f.canvas = CreateFrame("Frame", nil, f)
    f.canvas:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -56)
    f.canvas:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    f.canvasBg = f.canvas:CreateTexture(nil, "BACKGROUND")
    f.canvasBg:SetAllPoints()
    f.canvasBg:SetColorTexture(0.05, 0.05, 0.05, 1)

    f.drawHost = CreateFrame("Frame", nil, f.canvas)
    f.drawHost:SetAllPoints(); f.drawHost:EnableMouse(false)
    f.iconsHost = CreateFrame("Frame", nil, f.canvas)
    f.iconsHost:SetAllPoints(); f.iconsHost:EnableMouse(false)

    f.notesHost = CreateFrame("Frame", nil, f)
    f.notesHost:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    f.notesHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    f.notesHost:SetHeight(74)
    local notesBg = f.notesHost:CreateTexture(nil, "BACKGROUND")
    notesBg:SetAllPoints()
    notesBg:SetColorTexture(0, 0, 0, 0.55)
    local notesTitle = f.notesHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesTitle:SetPoint("TOPLEFT", f.notesHost, "TOPLEFT", 8, -6)
    notesTitle:SetText("Notes")
    f.notesText = f.notesHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.notesText:SetPoint("TOPLEFT", notesTitle, "BOTTOMLEFT", 0, -4)
    f.notesText:SetPoint("BOTTOMRIGHT", f.notesHost, "BOTTOMRIGHT", -8, 6)
    f.notesText:SetJustifyH("LEFT")
    f.notesText:SetJustifyV("TOP")
    f.notesHost:Hide()

    incomingSharePopup = f
    return f
end

local function layoutIncomingSharePopup(f, hasPlanTabs, hasNotes)
    if not f then return end
    if f.planTabsHost then
        if hasPlanTabs then f.planTabsHost:Show() else f.planTabsHost:Hide() end
    end
    if f.notesHost then
        f.notesHost:SetShown(hasNotes and true or false)
    end
    if f.canvas then
        f.canvas:ClearAllPoints()
        f.canvas:SetPoint("TOPLEFT", f, "TOPLEFT", 14, hasPlanTabs and -84 or -56)
        f.canvas:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, hasNotes and 96 or 14)
    end
end

local function rebuildIncomingSharePlanTabs(f)
    if not f then return end
    local plans = f.sharedPlans or {}
    local showTabs = #plans > 1
    layoutIncomingSharePopup(f, showTabs, cleanedPlanNote(plans[f.activeSharedPlanIdx]) ~= nil)

    for _, btn in ipairs(f.planTabButtons or {}) do
        btn:Hide()
    end
    if not showTabs then return end

    local cx = 0
    for i, plan in ipairs(plans) do
        local tabLabel = ((plan and plan.name) or ""):gsub("^%s*(.-)%s*$", "%1")
        if tabLabel == "" then tabLabel = "Plan " .. tostring(i) end

        local b = f.planTabButtons[i] or CreateFrame("Button", nil, f.planTabsHost, "UIPanelButtonTemplate")
        f.planTabButtons[i] = b
        b:SetText(tabLabel)
        local textW = b.GetTextWidth and b:GetTextWidth() or 48
        local tabW = math.max(50, math.min(118, math.floor(textW + 18)))
        b:SetSize(tabW, 22)
        b:ClearAllPoints()
        b:SetPoint("LEFT", f.planTabsHost, "LEFT", cx, 0)
        b:Show()
        b:SetButtonState(i == f.activeSharedPlanIdx and "PUSHED" or "NORMAL", i == f.activeSharedPlanIdx)
        b:SetScript("OnClick", function()
            f.activeSharedPlanIdx = i
            rebuildIncomingSharePlanTabs(f)
            renderIncomingSharePreview(f, plans[i])
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tabLabel)
            GameTooltip:AddLine("Show this shared plan.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cx = cx + tabW + 4
    end
end

renderIncomingSharePreview = function(f, plan)
    if not (f and plan) then return end
    buildPaletteIndex()

    local note = cleanedPlanNote(plan)
    if f.notesText then
        f.notesText:SetText(note or "")
    end
    layoutIncomingSharePopup(f, #(f.sharedPlans or {}) > 1, note ~= nil)

    for _, c in ipairs({f.iconsHost:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    clearIncomingShareDrawSegments()

    if plan.background then
        f.canvasBg:SetTexture(bgTexture(plan.background))
        f.canvasBg:SetVertexColor(1, 1, 1, 1)
    else
        f.canvasBg:SetTexture(nil)
        f.canvasBg:SetColorTexture(0.05, 0.05, 0.05, 1)
    end

    local w = f.canvas:GetWidth() or 0
    local h = f.canvas:GetHeight() or 0
    if w <= 0 or h <= 0 then
        w, h = 700, 500
    end

    for _, icon in ipairs(plan.icons or {}) do
        local holder = CreateFrame("Frame", nil, f.iconsHost)
        holder:SetSize(PLACED_DEFAULT_SIZE, PLACED_DEFAULT_SIZE)
        holder:SetPoint("CENTER", f.canvas, "TOPLEFT",
            (icon.x or 0.5) * w, -((icon.y or 0.5) * h))
        drawDirectionIndicator(holder, icon)

        local tex = holder:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        local path, tc
        if icon.iconTex then
            path = icon.iconTex
        end
        if icon.variant and icon.key and icon.key ~= "" then
            local vk = icon.key .. ":" .. icon.variant
            path = path or KEY_TO_TEX[vk]
            tc = KEY_TO_TEXCOORD[vk]
        end
        path = path or KEY_TO_TEX[icon.key]
        tc = tc or KEY_TO_TEXCOORD[icon.key]
        if not path and icon.kind == "boss" then
            path = "Interface\\Icons\\INV_Misc_Head_Dragon_01"
        end
        if path then
            tex:SetTexture(path)
            applyIconTexCoord(tex, tc)
            local hex = icon.color or "ffffff"
            if hex ~= "ffffff" then
                local r = tonumber(hex:sub(1, 2), 16)
                local g = tonumber(hex:sub(3, 4), 16)
                local b = tonumber(hex:sub(5, 6), 16)
                if r and g and b then
                    tex:SetVertexColor(r / 255, g / 255, b / 255, 1)
                end
            end
        else
            tex:SetColorTexture(1, 1, 1, 0.25)
        end

        if icon.text and icon.text ~= "" then
            local lbl = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("TOP", holder, "BOTTOM", 0, -1)
            lbl:SetText(icon.text)
            lbl:SetTextColor(1, 1, 1, 1)
        end
    end

    for _, stroke in ipairs(plan.drawings or {}) do
        local hex = stroke.color or "ffffff"
        local r = tonumber(hex:sub(1, 2), 16) / 255
        local g = tonumber(hex:sub(3, 4), 16) / 255
        local b = tonumber(hex:sub(5, 6), 16) / 255
        local size = stroke.size or 4
        local pts = stroke.points or {}
        for i = 2, #pts do
            local p1, p2 = pts[i - 1], pts[i]
            drawIncomingShareSegment(f.drawHost,
                p1.x * w, p1.y * h, p2.x * w, p2.y * h,
                size, r, g, b, 1)
        end
    end
end

local function showIncomingShare(senderShort, encName, planIdx, payload)
    local bundle = deserializePlanBundle(payload, planIdx)
    if not bundle then
        print("|cffffd100L3FTools:|r received a shared visual, but it could not be decoded.")
        return
    end
    local f = ensureIncomingSharePopup()
    local shownEncName = (encName and encName ~= "")
        and encName or bundle.encounterName or "Unknown"
    f.sharedPlans = bundle.plans or {}
    f.activeSharedPlanIdx = math.max(1, math.min(#f.sharedPlans, bundle.activePlanIdx or 1))
    local count = #f.sharedPlans
    if count > 1 then
        f.meta:SetText(string.format("|cffffd100%s|r sent %d plans for |cffaaccff%s|r.",
            senderShort or "?", count, shownEncName))
    else
        f.meta:SetText(string.format("|cffffd100%s|r sent a visual for |cffaaccff%s|r.",
            senderShort or "?", shownEncName))
    end
    rebuildIncomingSharePlanTabs(f)
    f:Show()
    renderIncomingSharePreview(f, f.sharedPlans[f.activeSharedPlanIdx])
end


-- =============================================================
-- 12. MAIN BUILDER + REFRESH
-- =============================================================
refreshIcons = function()
    if not placedHost then return end
    for _, c in ipairs({placedHost:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    for _, r in ipairs({placedHost:GetRegions()}) do r:Hide(); r:ClearAllPoints() end
    local plan = currentPlan()
    if not plan then return end
    for i, ic in ipairs(plan.icons or {}) do
        if ic.spellID and not ic.iconTex then
            ic.iconTex = GetSpellTexture and GetSpellTexture(ic.spellID) or nil
        end
        buildPlacedIcon(plan, ic, i)
    end
end

refresh = function()
    refreshTopStrip()
    refreshPalette()
    refreshIcons()
    refreshDrawings()
    refreshPropsPanel()
    refreshEncounterPanel()
    refreshSearchPanel()
    refreshNotesPanel()
    plannerHistory.refreshButtons()
    if leftClearPlanBtn then
        leftClearPlanBtn:SetShown(not isCoOpGuest())
    end

    local plan = currentPlan()
    if canvasBg then
        if plan and plan.background then
            canvasBg:SetTexture(bgTexture(plan.background))
            canvasBg:SetVertexColor(1, 1, 1, 1)
        else
            canvasBg:SetTexture(nil)
            canvasBg:SetColorTexture(0.05, 0.05, 0.05, 1)
        end
    end
end

L3F._RPRefresh = scheduleRefresh


local function buildRaidPlanner(parent)
    buildPaletteIndex()
    ensureState()

    if not L3F._RPRaidContextWatcher then
        local watch = CreateFrame("Frame")
        watch:RegisterEvent("PLAYER_ENTERING_WORLD")
        watch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        watch:RegisterEvent("ZONE_CHANGED_INDOORS")
        watch:RegisterEvent("ZONE_CHANGED")
        watch:SetScript("OnEvent", function()
            syncEncounterToInstanceRaid()
            if topStripFrame and topStripFrame:IsShown() then
                scheduleRefresh()
            end
        end)
        L3F._RPRaidContextWatcher = watch
    end

    buildTopStrip(parent)
    shareBtn:SetScript("OnClick", openSharePopup)
    if shareAllBtn then shareAllBtn:SetScript("OnClick", openShareAllDialog) end
    if importBtn then importBtn:SetScript("OnClick", openImportDialog) end

    buildLeftPanel(parent)
    buildRightPanel(parent)

    -- Co-op: build the roster panel as a fixed always-visible panel
    -- on the planner (no top-strip toggle button).
    if L3F.RPCoOp and L3F.RPCoOp.AttachRosterPanel then
        local panel = L3F.RPCoOp.AttachRosterPanel(parent,
            "TOPRIGHT", parent, "TOPRIGHT", -8, -TOP_H - 8)
        if panel then panel:Show() end
    end
    -- Co-op: route incoming SHARE-to-raid messages through our popup.
    if L3F.RPCoOp then
        L3F.RPCoOp.OnIncomingShare = function(sender, senderFull, enc, planIdx, payload)
            showIncomingShare(sender, enc, planIdx, payload)
        end
    end

    canvasFrame = CreateFrame("Frame", nil, parent)
    canvasFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_W + 12, -TOP_H)
    canvasFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -RIGHT_W - 12, 4)
    canvasFrame:EnableMouse(true)
    -- No RegisterForDrag on the canvas: pen mode uses OnMouseDown +
    -- OnUpdate polling for stroke drawing, NOT drag events. Having
    -- RegisterForDrag here armed WoW's drag system for the empty
    -- canvas with no OnDragStart bound, which might have stolen drag
    -- events from placed-icon children.
    canvasBg = canvasFrame:CreateTexture(nil, "BACKGROUND")
    canvasBg:SetAllPoints()
    canvasBg:SetColorTexture(0.05, 0.05, 0.05, 1)

    drawingHost = CreateFrame("Frame", nil, canvasFrame)
    drawingHost:SetAllPoints(); drawingHost:EnableMouse(false)
    placedHost = CreateFrame("Frame", nil, canvasFrame)
    placedHost:SetAllPoints(); placedHost:EnableMouse(false)

    canvasFrame:SetScript("OnMouseDown", canvasMouseDown)
    canvasFrame:SetScript("OnMouseUp", canvasMouseUp)
    canvasFrame:SetScript("OnUpdate", canvasUpdate)
    canvasFrame:HookScript("OnSizeChanged", function()
        refreshIcons(); refreshDrawings()
    end)

    refresh()
end

L3F.RegisterTab("guild.raidplanner", "Raid Planner", nil, buildRaidPlanner, {
    parent = "guild",
    preferredWidth = 1200, preferredHeight = 760,
})
