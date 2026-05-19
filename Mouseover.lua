-- =============================================================
-- L3FTools - Mouseover.lua
-- =============================================================
-- Hold-keybind: while the bound key is held, mousing over a mob
-- marks it - no click or target change needed.
--   * The key is declared in Bindings.xml, which the client loads
--     automatically (it is NOT listed in the .toc). The key is
--     rebindable in the WoW Key Bindings UI under the "L3FTools"
--     header.
--   * The binding has runOnUp set, so it fires on both press and
--     release: it sets L3F.mouseoverHeld true on key-down and
--     false on key-up.
--   * On UPDATE_MOUSEOVER_UNIT, while held, the Automarker engine
--     runs on the "mouseover" unit - so it obeys every existing
--     rule (priority, once-placed lock, combat lock, wing scoping,
--     next-free-mark) exactly like click / target marking.
-- =============================================================

local _, L3F = ...

-- The Key Bindings labels (BINDING_HEADER_* / BINDING_NAME_*) are set in
-- Core.lua so they exist before Bindings.xml is processed.

-- While the key is held, mark whatever the cursor passes over.
local ev = CreateFrame("Frame")
ev:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
ev:SetScript("OnEvent", function()
    if L3F.mouseoverHeld and L3F.AutomarkerTryMark then
        L3F.AutomarkerTryMark("mouseover")
    end
end)
