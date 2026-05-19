-- =============================================================
-- L3FTools - Mouseover.lua
-- =============================================================
-- Hold-keybind: while the bound key is held, mousing over a mob
-- marks it - no click or target change needed.
--   * The key is registered in Bindings.xml and is rebindable in
--     the WoW Key Bindings UI under the "L3FTools" header.
--   * Held state is tracked with a CLICK button registered for
--     key-down AND key-up.
--   * On UPDATE_MOUSEOVER_UNIT, while held, the Automarker engine
--     runs on the "mouseover" unit - so it obeys every existing
--     rule (priority, once-placed lock, combat lock, wing scoping,
--     next-free-mark) exactly like click / target marking.
-- =============================================================

local _, L3F = ...

-- Friendly labels for the WoW Key Bindings UI.
BINDING_HEADER_L3FTOOLS = "L3FTools"
_G["BINDING_NAME_CLICK L3FToolsMouseoverButton:LeftButton"] = "Hold to mark mob under cursor"

-- Hold-state button. Bindings.xml binds a key to CLICK this button;
-- registering for down + up makes OnClick fire on both press and release.
local holdButton = CreateFrame("Button", "L3FToolsMouseoverButton", UIParent)
holdButton:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
holdButton:SetScript("OnClick", function(_, _, down)
    L3F.mouseoverHeld = down and true or false
end)

-- While the key is held, mark whatever the cursor passes over.
local ev = CreateFrame("Frame")
ev:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
ev:SetScript("OnEvent", function()
    if L3F.mouseoverHeld and L3F.AutomarkerTryMark then
        L3F.AutomarkerTryMark("mouseover")
    end
end)
