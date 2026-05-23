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
-- The three palette groups Willem itemised. Each entry carries an
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

-- Role icons (tank / healer / melee dps / ranged dps). Chosen for
-- visual distinguishability rather than the LFG sprite sheet (its
-- texcoords are fiddly and the LFG sheet has no "ranged" role).
local ROLES = {
    { key = "tank",   label = "Tank",       tex = "Interface\\Icons\\Spell_Holy_DevotionAura" },
    { key = "heal",   label = "Healer",     tex = "Interface\\Icons\\Spell_Nature_Healingtouch" },
    { key = "melee",  label = "Melee DPS",  tex = "Interface\\Icons\\Ability_Warrior_SavageBlow" },
    { key = "ranged", label = "Ranged DPS", tex = "Interface\\Icons\\Ability_Hunter_AimedShot" },
}

-- TBC classes. The Properties panel surfaces alternative form icons
-- via `variants` for classes that have a clear secondary identity in
-- TBC (Druid's 4 forms). All other classes have a single texture.
local CLASSES = {
    { key = "druid",   label = "Druid",   tex = "Interface\\Icons\\Ability_Druid_CatForm",
      variants = {
        { key = "cat",     label = "Cat",     tex = "Interface\\Icons\\Ability_Druid_CatForm" },
        { key = "bear",    label = "Bear",    tex = "Interface\\Icons\\Ability_Racial_BearForm" },
        { key = "tree",    label = "Tree",    tex = "Interface\\Icons\\Ability_Druid_TreeofLife" },
        { key = "moonkin", label = "Moonkin", tex = "Interface\\Icons\\Spell_Nature_ForceOfNature" },
      } },
    { key = "hunter",  label = "Hunter",  tex = "Interface\\Icons\\Ability_Hunter_BeastTaming" },
    { key = "mage",    label = "Mage",    tex = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
    { key = "paladin", label = "Paladin", tex = "Interface\\Icons\\Spell_Holy_HolyBolt" },
    { key = "priest",  label = "Priest",  tex = "Interface\\Icons\\Spell_Holy_PowerWordShield" },
    { key = "rogue",   label = "Rogue",   tex = "Interface\\Icons\\Ability_Stealth" },
    { key = "shaman",  label = "Shaman",  tex = "Interface\\Icons\\Spell_Nature_Lightning" },
    { key = "warlock", label = "Warlock", tex = "Interface\\Icons\\Spell_Shadow_DeathCoil" },
    { key = "warrior", label = "Warrior", tex = "Interface\\Icons\\Ability_Warrior_SavageBlow" },
}

-- Reverse lookup: any palette key (mark / role / class / class-variant)
-- -> the texture. Populated lazily because variant sub-tables nest
-- and we want all three palette families in one map for the canvas
-- renderer.
local KEY_TO_TEX = {}
local KEY_TO_LABEL = {}
local function buildPaletteIndex()
    if next(KEY_TO_TEX) then return end
    for _, m in ipairs(MARKS)   do KEY_TO_TEX[m.key], KEY_TO_LABEL[m.key] = m.tex, m.label end
    for _, r in ipairs(ROLES)   do KEY_TO_TEX[r.key], KEY_TO_LABEL[r.key] = r.tex, r.label end
    for _, c in ipairs(CLASSES) do
        KEY_TO_TEX[c.key], KEY_TO_LABEL[c.key] = c.tex, c.label
        for _, v in ipairs(c.variants or {}) do
            -- Variant keys are namespaced "<class>:<variant>" so two
            -- classes can share a variant name without collision.
            local vk = c.key .. ":" .. v.key
            KEY_TO_TEX[vk], KEY_TO_LABEL[vk] = v.tex, c.label .. " (" .. v.label .. ")"
        end
    end
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

local function findCatalogEncounter(name)
    for _, raid in ipairs(L3F.raidPlannerCatalog or {}) do
        for _, enc in ipairs(raid.encounters) do
            if enc.name == name then return enc, raid end
        end
    end
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
    ensureState()
    local rp = L3F.db.raidPlanner
    rp.plansByEncounter[encounterName] = rp.plansByEncounter[encounterName] or {}
    if #rp.plansByEncounter[encounterName] == 0 then
        table.insert(rp.plansByEncounter[encounterName], newEmptyPlan(encounterName))
    end
    return rp.plansByEncounter[encounterName]
end

local function currentPlan()
    ensureState()
    local rp = L3F.db.raidPlanner
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
    if type(OpenColorPicker) == "function" then
        OpenColorPicker(info)
    elseif ColorPickerFrame then
        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.opacity = 1
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Show()
    end

    -- TBC 2.5.x Anniversary ships an XML OK button OnClick that calls
    -- ColorPickerFrame.swatchFunc(), but the OpenColorPicker(info)
    -- helper on this build only writes ColorPickerFrame.func. That
    -- naming-mismatch leaves .swatchFunc nil and the OK click errors
    -- with "attempt to call field 'swatchFunc' (a nil value)" -- which
    -- shows up RANDOMLY while the user drags icons because the drop
    -- click sometimes lands on the still-visible OK button after they
    -- opened a color picker and never closed it. Set BOTH names
    -- explicitly so the XML handler can find a callable function under
    -- whichever field name it's coded to read.
    if ColorPickerFrame then
        ColorPickerFrame.func        = info.swatchFunc
        ColorPickerFrame.swatchFunc  = info.swatchFunc
        ColorPickerFrame.opacityFunc = info.swatchFunc
        ColorPickerFrame.cancelFunc  = info.cancelFunc
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
-- deferred refresh would never fire. Only declare the other three
-- forwards here.
local selectIcon, deselect, openContextMenu

local dragState = { active = false }

local follower = CreateFrame("Frame", "L3FRPDragFollower", UIParent)
follower:SetSize(PLACED_DEFAULT_SIZE, PLACED_DEFAULT_SIZE)
follower:SetFrameStrata("TOOLTIP")
follower:EnableMouse(false)
follower:Hide()
local followerTex = follower:CreateTexture(nil, "OVERLAY")
followerTex:SetAllPoints()
followerTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

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
local currentSelection

local penMode = {
    enabled  = false,
    size     = 4,
    color    = "ffffff",
    fadeOut  = 0,
}

local rightTab = "encounter"
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
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if iconData.iconTex then
            path = iconData.iconTex
        elseif iconData.variant then
            path = KEY_TO_TEX[iconData.key .. ":" .. iconData.variant]
        end
        path = path or KEY_TO_TEX[iconData.key]
        if path then tex:SetTexture(path) end
        if iconData.color and iconData.color ~= "ffffff" then
            local r = tonumber(iconData.color:sub(1, 2), 16)
            local g = tonumber(iconData.color:sub(3, 4), 16)
            local b = tonumber(iconData.color:sub(5, 6), 16)
            if r and g and b then tex:SetVertexColor(r/255, g/255, b/255, 1) end
        end
    end

    if currentSelection == idx then
        local ring = f:CreateTexture(nil, "OVERLAY")
        ring:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
        ring:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
        ring:SetTexture("Interface\\Buttons\\WHITE8X8")
        ring:SetVertexColor(0.3, 0.7, 1.0, 0.35)
        ring:SetDrawLayer("OVERLAY", -2)
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

    -- OnMouseUp only fires when WoW didn't escalate the gesture into
    -- a drag. Pure click -> select / context menu. (RegisterForDrag
    -- only watches LeftButton, so right-clicks always come here.)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            openContextMenu(self, idx)
        elseif button == "LeftButton" then
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
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetVertexColor(r, g, b, a)
    tex:SetWidth(len)
    tex:SetHeight(size)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", parent, "TOPLEFT", (x1 + x2) / 2, -(y1 + y2) / 2)
    tex:SetRotation(math.atan2(-dy, dx))
end

refreshDrawings = function()
    if not drawingHost then return end
    for _, c in ipairs({drawingHost:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    for _, r in ipairs({drawingHost:GetRegions()}) do r:Hide(); r:ClearAllPoints() end
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


-- =============================================================
-- 8. LEFT PANEL (mode toggle + palette / pen controls)
-- =============================================================
local leftPanel, iconControls, penControls

-- `dragSource` discriminates palette-vs-encounter drags so each
-- handler only acts on its own drop. Without this, a stale state
-- from a previous drag could cause palette's OnDragStop to fire
-- against an encounter-kind drag and produce a malformed icon.
local function startDragFromPalette(kind, key)
    dragState.active     = true
    dragState.dragSource = "palette"
    dragState.kind       = kind
    dragState.key        = key
    dragState.variant    = nil
    dragState.color      = "ffffff"
    dragState.text       = nil
    dragState.fromIcon   = nil
    dragState.npcID      = nil
    dragState.npcName    = nil
    followerTex:SetTexture(KEY_TO_TEX[key] or QUILL)
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
end

local function placeIconAt(kind, key, relX, relY, options)
    local plan = currentPlan()
    if not plan then return end
    local entry = {
        kind    = kind,
        key     = key,
        x       = relX or 0.5,
        y       = relY or 0.5,
        color   = (options and options.color) or "ffffff",
        text    = (options and options.text) or nil,
        variant = (options and options.variant) or nil,
        locked  = false,
    }
    if options and options.spellID then
        entry.spellID = options.spellID
        entry.iconTex = options.iconTex
    end
    if options and options.npcID then
        entry.npcID = options.npcID
    end
    table.insert(plan.icons, entry)
    currentSelection = #plan.icons
    -- Co-op: broadcast PLACE. Position-by-iconIdx isn't sent; each
    -- member appends to their own icons array. Out-of-order PLACE from
    -- two members causes the local indexes to diverge briefly until
    -- the next host snapshot resyncs. Acceptable for v1.
    notifyEdit("PLACE", {
        entry.kind or "", entry.key or "",
        string.format("%.4f", entry.x), string.format("%.4f", entry.y),
        entry.color or "ffffff", entry.text or "",
        entry.variant or "", entry.locked and "1" or "0",
    })
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
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
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

    btn:SetScript("OnDragStart", function() startDragFromPalette(kind, entry.key) end)
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
                { color = dragState.color, variant = dragState.variant })
        end
        resetDragState()
        follower:Hide()
    end)
    btn:SetScript("OnClick", function() placeIconAt(kind, entry.key, 0.5, 0.5) end)
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

local function canvasUpdate(self)
    if not currentStroke then return end
    if not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then
        broadcastStroke(currentStroke)
        currentStroke = nil
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
        broadcastStroke(currentStroke)
        currentStroke = nil
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

local clipboard = nil

local contextMenuFrame
openContextMenu = function(anchorBtn, iconIdx)
    if not contextMenuFrame then
        contextMenuFrame = CreateFrame("Frame", "L3FRPContextMenu", UIParent)
        contextMenuFrame:SetFrameStrata("DIALOG")
        contextMenuFrame:SetSize(140, 6 + 22 * 4)
        local bg = contextMenuFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
        contextMenuFrame:Hide()
        contextMenuFrame.buttons = {}
    end
    local f = contextMenuFrame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchorBtn, "BOTTOMRIGHT", 0, 0)
    f:Show()

    local plan = currentPlan()
    local icon = plan and plan.icons[iconIdx]

    local items = {
        { label = "Copy",   action = function() if icon then clipboard = CopyTable(icon) end; f:Hide() end },
        { label = "Paste",  action = function()
            if clipboard then
                local c = CopyTable(clipboard)
                c.x = (icon and icon.x or 0.5) + 0.03
                c.y = (icon and icon.y or 0.5) + 0.03
                table.insert(plan.icons, c)
                currentSelection = #plan.icons
                notifyEdit("PLACE", {
                    c.kind or "", c.key or "",
                    string.format("%.4f", c.x), string.format("%.4f", c.y),
                    c.color or "ffffff", c.text or "",
                    c.variant or "", c.locked and "1" or "0",
                })
                scheduleRefresh()
            end
            f:Hide()
        end },
        { label = "Delete", action = function()
            if icon then
                table.remove(plan.icons, iconIdx)
                notifyEdit("RM", { tostring(iconIdx) })
                currentSelection = nil
                scheduleRefresh()
            end
            f:Hide()
        end },
        { label = "Lock",   action = function()
            if icon then
                icon.locked = not icon.locked
                notifyEdit("PROPS", {
                    tostring(iconIdx),
                    icon.color or "ffffff", icon.text or "",
                    icon.variant or "", icon.locked and "1" or "0",
                })
            end
            refreshIcons()
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
        local label = item.label
        if label == "Lock" and icon and icon.locked then label = "Unlock" end
        b.text:SetText(label)
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

    local arrowBtn = CreateFrame("Button", nil, leftPanel)
    arrowBtn:SetSize(28, 28); arrowBtn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 2, -4)
    arrowBtn:SetNormalTexture("Interface\\Buttons\\UI-MicroButton-Friends-Up")
    arrowBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    arrowBtn:SetScript("OnClick", function() leftMode = "icons"; penMode.enabled = false; refreshPalette() end)
    arrowBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Icons mode"); GameTooltip:Show()
    end)
    arrowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local penBtn = CreateFrame("Button", nil, leftPanel)
    penBtn:SetSize(28, 28); penBtn:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 32, -4)
    penBtn:SetNormalTexture(QUILL)
    penBtn:GetNormalTexture():SetTexCoord(0.07, 0.93, 0.07, 0.93)
    penBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    penBtn:SetScript("OnClick", function() leftMode = "pen"; penMode.enabled = true; refreshPalette() end)
    penBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Pen mode"); GameTooltip:Show()
    end)
    penBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    iconControls = CreateFrame("Frame", nil, leftPanel)
    iconControls:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 2, -36)
    iconControls:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -2, 4)

    penControls = CreateFrame("Frame", nil, leftPanel)
    penControls:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 2, -36)
    penControls:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -2, 4)
    penControls:Hide()
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
        local sizeStr = CreateFrame("EditBox", nil, penControls, "InputBoxTemplate")
        sizeStr:SetSize(50, 22)
        sizeStr:SetPoint("TOPLEFT", penControls, "TOPLEFT", 6, -cy)
        sizeStr:SetAutoFocus(false); sizeStr:SetNumeric(true); sizeStr:SetMaxLetters(2)
        sizeStr:SetText(tostring(penMode.size))
        sizeStr:SetScript("OnEnterPressed", function(self)
            local n = tonumber(self:GetText()) or 4
            penMode.size = math.max(1, math.min(20, n))
            self:ClearFocus(); refreshPalette()
        end)
        cy = cy + 30

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

        label("Fade (sec, 0=off)", 0, cy); cy = cy + 14
        local fadeStr = CreateFrame("EditBox", nil, penControls, "InputBoxTemplate")
        fadeStr:SetSize(50, 22)
        fadeStr:SetPoint("TOPLEFT", penControls, "TOPLEFT", 6, -cy)
        fadeStr:SetAutoFocus(false); fadeStr:SetNumeric(true); fadeStr:SetMaxLetters(3)
        fadeStr:SetText(tostring(penMode.fadeOut))
        fadeStr:SetScript("OnEnterPressed", function(self)
            local n = tonumber(self:GetText()) or 0
            penMode.fadeOut = math.max(0, math.min(120, n))
            self:ClearFocus()
        end)
        cy = cy + 30

        local clearBtn = CreateFrame("Button", nil, penControls, "UIPanelButtonTemplate")
        clearBtn:SetSize(56, 22); clearBtn:SetText("Clear")
        clearBtn:SetPoint("TOPLEFT", penControls, "TOPLEFT", 0, -cy)
        clearBtn:SetScript("OnClick", function()
            local plan = currentPlan()
            if plan then
                plan.drawings = {}
                notifyEdit("PEN_CLEAR", {})
                refreshDrawings()
            end
        end)
    end
end


-- =============================================================
-- 9. RIGHT PANEL (Properties + tabs: Encounter / Search / Notes)
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

    local propsTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    propsTitle:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 8, -6)
    propsTitle:SetText("Properties")

    propsHost = CreateFrame("Frame", nil, rightPanel)
    propsHost:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 4, -24)
    propsHost:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -4, -24)
    propsHost:SetHeight(180)
    local propsBg = propsHost:CreateTexture(nil, "BACKGROUND")
    propsBg:SetAllPoints(); propsBg:SetColorTexture(0, 0, 0, 0.15)

    local tabsStrip = CreateFrame("Frame", nil, rightPanel)
    tabsStrip:SetPoint("TOPLEFT", propsHost, "BOTTOMLEFT", 0, -6)
    tabsStrip:SetPoint("TOPRIGHT", propsHost, "BOTTOMRIGHT", 0, -6)
    tabsStrip:SetHeight(22)

    local function makeTab(label, key, dx)
        local b = CreateFrame("Button", nil, tabsStrip, "UIPanelButtonTemplate")
        b:SetSize(70, 22); b:SetText(label)
        b:SetPoint("TOPLEFT", tabsStrip, "TOPLEFT", dx, 0)
        b:SetScript("OnClick", function()
            rightTab = key
            refreshEncounterPanel(); refreshSearchPanel(); refreshNotesPanel()
        end)
        rightTabButtons[key] = b
        return b
    end
    makeTab("Encounter", "encounter", 4)
    makeTab("Search", "search", 78)
    makeTab("Notes", "notes", 152)

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

    local rp = L3F.db.raidPlanner
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

    local scroll = CreateFrame("ScrollFrame", nil, notesHost, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", notesHost, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", notesHost, "BOTTOMRIGHT", -20, 4)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal); edit:SetMaxLetters(2000)
    edit:SetWidth(RIGHT_W - 40); edit:SetHeight(300)
    edit:SetText((currentPlan() and currentPlan().notes) or "")
    edit:SetScript("OnEditFocusLost", function(self)
        local p = currentPlan()
        if p then
            p.notes = self:GetText() or ""
            notifyEdit("NOTES", { p.notes })
        end
    end)
    scroll:SetScrollChild(edit)
end


-- =============================================================
-- 10. TOP STRIP
-- =============================================================
local topStripFrame
local nameEdit, encDD, bgDD, planTabsHost, prevBtn, nextBtn, addBtn, deleteBtn
local utilDD, shareBtn, saveBtn

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

    local thumb = topStripFrame:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(36, 36); thumb:SetPoint("TOPLEFT", topStripFrame, "TOPLEFT", 4, -2)
    thumb:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
    thumb:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    topStripFrame.thumb = thumb

    nameEdit = CreateFrame("EditBox", nil, topStripFrame, "InputBoxTemplate")
    nameEdit:SetSize(160, 22)
    nameEdit:SetPoint("LEFT", thumb, "RIGHT", 14, 0)
    nameEdit:SetAutoFocus(false); nameEdit:SetMaxLetters(32)
    nameEdit:SetScript("OnEditFocusLost", function(self)
        local p = currentPlan(); if p then p.name = self:GetText() or "" end
    end)

    encDD = makeGroupedDropdown(topStripFrame, "L3FRPEncounterDD", 180,
        function() return L3F.db.raidPlanner and L3F.db.raidPlanner.activeEncounter end,
        function()
            local groups = {}
            for _, raid in ipairs(L3F.raidPlannerCatalog or {}) do
                local entries = {}
                for _, enc in ipairs(raid.encounters) do
                    table.insert(entries, { value = enc.name, label = enc.name })
                end
                table.insert(groups, { header = raid.raid, entries = entries })
            end
            return groups
        end,
        function(value)
            L3F.db.raidPlanner.activeEncounter = value
            L3F.db.raidPlanner.activePlanIdx = 1
            ensurePlansFor(value)
            -- Co-op: host-only navigation broadcast. The receiver's
            -- BroadcastDelta NAV handler ignores planIdx/background
            -- changes from non-hosts.
            notifyEdit("NAV", { value, "1", "" })
            scheduleRefresh()
        end)
    encDD:SetPoint("LEFT", nameEdit, "RIGHT", 8, -2)

    bgDD = makeGroupedDropdown(topStripFrame, "L3FRPBackgroundDD", 110,
        function()
            local p = currentPlan(); return p and p.background
        end,
        function()
            local enc = findCatalogEncounter(L3F.db.raidPlanner.activeEncounter)
            local entries = {}
            for _, bg in ipairs(enc and enc.backgrounds or {}) do
                table.insert(entries, { value = bg.slug, label = bg.label })
            end
            return { { entries = entries } }
        end,
        function(value)
            local p = currentPlan()
            if p then
                p.background = value
                local rp = L3F.db.raidPlanner
                notifyEdit("NAV", {
                    rp.activeEncounter or "",
                    tostring(rp.activePlanIdx or 1),
                    value or "",
                })
                scheduleRefresh()
            end
        end)
    bgDD:SetPoint("LEFT", encDD, "RIGHT", 2, 0)

    utilDD = CreateFrame("Frame", "L3FRPUtilDD", topStripFrame, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(utilDD, function(self, level)
        local opts = {
            { text = "Clear plan", func = function()
                local p = currentPlan()
                if p then
                    p.icons = {}; p.drawings = {}
                    notifyEdit("CLEAR", {})
                    scheduleRefresh()
                end
            end },
            { text = "Clone plan", func = function()
                local plans = ensurePlansFor(L3F.db.raidPlanner.activeEncounter)
                local cur = plans[L3F.db.raidPlanner.activePlanIdx]
                if cur then
                    local copy = CopyTable(cur)
                    copy.name = (cur.name or "Plan") .. " copy"
                    table.insert(plans, copy)
                    L3F.db.raidPlanner.activePlanIdx = #plans
                    scheduleRefresh()
                end
            end },
        }
        for _, o in ipairs(opts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = o.text; info.func = o.func; info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(utilDD, "...")
    UIDropDownMenu_SetWidth(utilDD, 50)
    utilDD:SetPoint("LEFT", bgDD, "RIGHT", 2, 0)

    shareBtn = CreateFrame("Button", nil, topStripFrame, "UIPanelButtonTemplate")
    shareBtn:SetSize(60, 22); shareBtn:SetText("Share")
    shareBtn:SetPoint("LEFT", utilDD, "RIGHT", 8, 2)
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

    saveBtn = CreateFrame("Button", nil, topStripFrame, "UIPanelButtonTemplate")
    saveBtn:SetSize(110, 22); saveBtn:SetText("Save changes")
    saveBtn:SetPoint("LEFT", shareBtn, "RIGHT", 4, 0)
    saveBtn:SetScript("OnClick", function()
        print("|cffffd100L3FTools:|r plan saved (auto-saves apply continuously)")
    end)

    -- Co-op toggle button. Opens the floating roster + actions panel.
    local coopBtn = CreateFrame("Button", nil, topStripFrame, "UIPanelButtonTemplate")
    coopBtn:SetSize(56, 22); coopBtn:SetText("Co-op")
    coopBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)
    coopBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Toggle the co-op session panel")
        GameTooltip:AddLine("Host a live multi-player editing session, or",
            0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("accept an invite to join one.",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    coopBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    coopBtn:SetScript("OnClick", function()
        if L3F.RPCoOp and L3F.RPCoOp.ToggleRosterPanel then
            L3F.RPCoOp.ToggleRosterPanel()
        end
    end)
    topStripFrame.coopBtn = coopBtn

    planTabsHost = CreateFrame("Frame", nil, topStripFrame)
    planTabsHost:SetPoint("TOPLEFT", thumb, "BOTTOMLEFT", 0, -6)
    planTabsHost:SetSize(400, 24)

    addBtn = CreateFrame("Button", nil, topStripFrame, "UIPanelButtonTemplate")
    addBtn:SetSize(28, 24); addBtn:SetText("+")
    addBtn:SetScript("OnClick", function()
        local plans = ensurePlansFor(L3F.db.raidPlanner.activeEncounter)
        table.insert(plans, newEmptyPlan(L3F.db.raidPlanner.activeEncounter))
        L3F.db.raidPlanner.activePlanIdx = #plans
        notifyEdit("NEWPL", { tostring(#plans) })
        scheduleRefresh()
    end)

    prevBtn = CreateFrame("Button", nil, topStripFrame)
    prevBtn:SetSize(20, 20)
    prevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prevBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    prevBtn:SetScript("OnClick", function()
        local rp = L3F.db.raidPlanner
        rp.activePlanIdx = math.max(1, (rp.activePlanIdx or 1) - 1)
        notifyEdit("NAV", { rp.activeEncounter or "", tostring(rp.activePlanIdx), "" })
        scheduleRefresh()
    end)
    nextBtn = CreateFrame("Button", nil, topStripFrame)
    nextBtn:SetSize(20, 20)
    nextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    nextBtn:SetScript("OnClick", function()
        local rp = L3F.db.raidPlanner
        local plans = ensurePlansFor(rp.activeEncounter)
        rp.activePlanIdx = math.min(#plans, (rp.activePlanIdx or 1) + 1)
        notifyEdit("NAV", { rp.activeEncounter or "", tostring(rp.activePlanIdx), "" })
        scheduleRefresh()
    end)

    deleteBtn = CreateFrame("Button", nil, topStripFrame)
    deleteBtn:SetSize(20, 20)
    deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
    deleteBtn:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
    deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    deleteBtn:SetScript("OnClick", function()
        local rp = L3F.db.raidPlanner
        local plans = ensurePlansFor(rp.activeEncounter)
        if #plans > 1 then
            local idx = rp.activePlanIdx or 1
            table.remove(plans, idx)
            rp.activePlanIdx = math.max(1, math.min(#plans, rp.activePlanIdx))
            notifyEdit("DELPL", { tostring(idx) })
            scheduleRefresh()
        end
    end)
end

refreshTopStrip = function()
    if not topStripFrame then return end
    local rp = L3F.db.raidPlanner
    UIDropDownMenu_SetText(encDD, rp.activeEncounter or "(no encounter)")
    local plan = currentPlan()
    UIDropDownMenu_SetText(bgDD, plan and plan.background or "(no background)")
    nameEdit:SetText(plan and plan.name or "")

    for _, c in ipairs({planTabsHost:GetChildren()}) do c:Hide(); c:SetParent(nil) end
    local plans = ensurePlansFor(rp.activeEncounter)
    local cx = 0
    for i = 1, #plans do
        local b = CreateFrame("Button", nil, planTabsHost, "UIPanelButtonTemplate")
        b:SetSize(28, 22); b:SetText(tostring(i))
        b:SetPoint("LEFT", planTabsHost, "LEFT", cx, 0)
        if i == rp.activePlanIdx then b:SetButtonState("PUSHED", true) end
        b:SetScript("OnClick", function()
            rp.activePlanIdx = i
            notifyEdit("NAV", { rp.activeEncounter or "", tostring(i), "" })
            scheduleRefresh()
        end)
        cx = cx + 30
    end
    addBtn:ClearAllPoints()
    addBtn:SetPoint("LEFT", planTabsHost, "LEFT", cx + 4, 0)

    prevBtn:ClearAllPoints(); prevBtn:SetPoint("LEFT", addBtn, "RIGHT", 30, 0)
    nextBtn:ClearAllPoints(); nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    deleteBtn:ClearAllPoints(); deleteBtn:SetPoint("LEFT", nextBtn, "RIGHT", 12, 0)
end


-- =============================================================
-- 11. SHARE / EXPORT (L3F2 string)
-- =============================================================
local LibDeflate = LibStub and LibStub("LibDeflate", true)

local function serializePlan(plan, encounterName)
    local function encIcon(ic)
        local parts = {
            ic.kind or "",
            ic.key or "",
            string.format("%.4f", ic.x or 0.5),
            string.format("%.4f", ic.y or 0.5),
            ic.color or "ffffff",
            ic.variant or "",
            ic.locked and "1" or "0",
            (ic.text or ""):gsub(";", " "):gsub("|", "/"),
        }
        return table.concat(parts, ":")
    end
    local iconsCSV = {}
    for _, ic in ipairs(plan.icons or {}) do
        table.insert(iconsCSV, encIcon(ic))
    end
    local function encStroke(s)
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
    local drawCSV = {}
    for _, s in ipairs(plan.drawings or {}) do
        table.insert(drawCSV, encStroke(s))
    end
    local inner = "RPLAN1|"
        .. (encounterName or ""):gsub("|", "/") .. "|"
        .. ((plan.name or ""):gsub("|", "/")) .. "|"
        .. (plan.background or "") .. "|"
        .. table.concat(iconsCSV, ";") .. "|"
        .. table.concat(drawCSV, ";") .. "|"
        .. ((plan.notes or ""):gsub("|", "/"))
    if LibDeflate then
        local compressed = LibDeflate:CompressDeflate(inner)
        return "L3FRP:" .. LibDeflate:EncodeForPrint(compressed)
    end
    return "L3FRP1:" .. inner
end

local function openShareDialog()
    local plan = currentPlan()
    if not plan then return end
    local str = serializePlan(plan, L3F.db.raidPlanner.activeEncounter)
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


-- =============================================================
-- 11b. CO-OP INTEGRATION (exports for RaidPlannerCoOp.lua)
-- =============================================================
-- Decode an L3FRP / L3FRP1 share string back to a plan table.
local function deserializePlan(str)
    if not str or str == "" then return nil end
    local body
    if str:sub(1, 7) == "L3FRP1:" then
        body = str:sub(8)
    elseif str:sub(1, 6) == "L3FRP:" then
        if not LibDeflate then return nil end
        local raw = LibDeflate:DecodeForPrint(str:sub(7))
        if not raw then return nil end
        body = LibDeflate:DecompressDeflate(raw)
    else
        return nil
    end
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
            local kind, key, xs, ys, color, variant, locked, text =
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

L3F._RPSerializePlan = serializePlan

function L3F._RPApplySnapshot(encName, planIdx, payload)
    local plan = deserializePlan(payload)
    if not plan then return end
    L3F.db.raidPlanner = L3F.db.raidPlanner or {}
    L3F.db.raidPlanner.plansByEncounter =
        L3F.db.raidPlanner.plansByEncounter or {}
    L3F.db.raidPlanner.plansByEncounter[encName] =
        L3F.db.raidPlanner.plansByEncounter[encName] or {}
    L3F.db.raidPlanner.plansByEncounter[encName][planIdx or 1] = plan
    L3F.db.raidPlanner.activeEncounter = encName
    L3F.db.raidPlanner.activePlanIdx = planIdx or 1
    scheduleRefresh()
end

function L3F._RPApplyDelta(deltaType, encName, planIdx, ...)
    local rp = L3F.db.raidPlanner
    if not rp then return end
    rp.plansByEncounter = rp.plansByEncounter or {}
    rp.plansByEncounter[encName] = rp.plansByEncounter[encName] or {}
    local plans = rp.plansByEncounter[encName]
    if #plans == 0 then
        table.insert(plans, newEmptyPlan(encName))
    end
    local plan = plans[planIdx] or plans[1]

    if deltaType == "PLACE" then
        local kind, key, xs, ys, color, text, variant, locked = ...
        table.insert(plan.icons, {
            kind    = kind or "",
            key     = key or "",
            x       = tonumber(xs) or 0.5,
            y       = tonumber(ys) or 0.5,
            color   = color or "ffffff",
            text    = (text and text ~= "") and text or nil,
            variant = (variant and variant ~= "") and variant or nil,
            locked  = locked == "1",
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
        local idxStr, color, text, variant, locked = ...
        local idx = tonumber(idxStr)
        local ic = idx and plan.icons[idx]
        if ic then
            ic.color   = color or ic.color
            ic.text    = (text and text ~= "") and text or nil
            ic.variant = (variant and variant ~= "") and variant or nil
            ic.locked  = locked == "1"
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
    elseif deltaType == "CLEAR" then
        plan.icons = {}; plan.drawings = {}
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
-- 11c. SHARE-BUTTON 2-CHOICE POPUP (Copy string / Share to raid)
-- =============================================================
local sharePopup
local function openSharePopup()
    if not sharePopup then
        local f = CreateFrame("Frame", "L3FRPSharePopup", UIParent,
            "BasicFrameTemplateWithInset")
        f:SetSize(300, 150)
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
        local raidBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        raidBtn:SetSize(260, 24); raidBtn:SetText("Share to raid")
        raidBtn:SetPoint("TOP", copyBtn, "BOTTOM", 0, -6)
        raidBtn:SetScript("OnClick", function()
            f:Hide()
            if L3F.RPCoOp and L3F.RPCoOp.ShareToRaid then
                L3F.RPCoOp.ShareToRaid()
            end
        end)
        f.raidBtn = raidBtn
        sharePopup = f
    end
    -- Disable Share-to-raid when not in a party/raid.
    if sharePopup.raidBtn then
        if IsInRaid() or IsInGroup() then
            sharePopup.raidBtn:Enable()
        else
            sharePopup.raidBtn:Disable()
        end
    end
    sharePopup:Show()
end


-- =============================================================
-- 11d. INCOMING SHARE POPUP (receiver of a "Share to raid")
-- =============================================================
local incomingSharePopup
local function showIncomingShare(senderShort, encName, planIdx, payload)
    if not incomingSharePopup then
        local f = CreateFrame("Frame", "L3FRPIncomingShare", UIParent,
            "BasicFrameTemplateWithInset")
        f:SetSize(360, 130)
        f:SetPoint("TOP", UIParent, "TOP", 0, -120)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true); f:SetClampedToScreen(true)
        f:EnableMouse(true)
        if f.TitleText then f.TitleText:SetText("Shared raid plan") end
        f.msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.msg:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
        f.msg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -32)
        f.msg:SetJustifyH("LEFT")
        f.acc = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.acc:SetSize(100, 22); f.acc:SetText("View")
        f.acc:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
        f.dec = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.dec:SetSize(100, 22); f.dec:SetText("Discard")
        f.dec:SetPoint("RIGHT", f.acc, "LEFT", -8, 0)
        f.dec:SetScript("OnClick", function() f:Hide() end)
        incomingSharePopup = f
    end
    incomingSharePopup.msg:SetText(string.format(
        "|cffffd100%s|r shared a raid plan for |cffaaccff%s|r.\nView replaces your current plan for that encounter.",
        senderShort or "?", encName or "?"))
    incomingSharePopup.acc:SetScript("OnClick", function()
        L3F._RPApplySnapshot(encName, planIdx, payload)
        incomingSharePopup:Hide()
        -- Open the Raid Planner tab so the user lands on the shared
        -- plan immediately. The tab opener is exposed by Frame.lua.
        if L3F.ShowTab then pcall(L3F.ShowTab, "guild.raidplanner") end
    end)
    incomingSharePopup:Show()
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


local function buildRaidPlanner(parent)
    buildPaletteIndex()
    ensureState()

    buildTopStrip(parent)
    shareBtn:SetScript("OnClick", openSharePopup)

    buildLeftPanel(parent)
    buildRightPanel(parent)

    -- Co-op: build the roster panel (hidden by default) parented to
    -- the main planner area. The top-strip "Co-op" button toggles it.
    if L3F.RPCoOp and L3F.RPCoOp.AttachRosterPanel then
        local panel = L3F.RPCoOp.AttachRosterPanel(parent,
            "TOPRIGHT", parent, "TOPRIGHT", -8, -TOP_H - 8)
        if panel then panel:Hide() end
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
