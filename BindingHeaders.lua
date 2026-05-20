-- =============================================================
-- L3FTools - BindingHeaders.lua
-- =============================================================
-- Sourced by Bindings.xml via <Script file="..."/> at parse time,
-- BEFORE the <Binding> element below it is registered. This is the
-- only reliable point on TBC Anniversary where the BINDING_HEADER_*
-- global is set early enough to land the binding under its own
-- category in the Key Bindings UI instead of falling through to
-- "Other" / "HEADER_L3FTOOLS".
--
-- The same assignments also exist in Core.lua's top-level for the
-- BINDING_NAME_* live lookup at display time; this file's job is
-- specifically the parse-time header.
-- =============================================================

BINDING_HEADER_L3FTOOLS = "L3FTools"
BINDING_NAME_L3FTOOLS_MOUSEOVERMARK = "Hold to mark mob under cursor"
