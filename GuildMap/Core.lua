-- =============================================================
-- L3FTools - GuildMap/Core.lua
-- =============================================================
-- Live position sharing on world map + minimap, MapMate-style but
-- with explicit per-source privacy toggles (guild / group / friends).
--
-- This file owns:
--   * the first-run privacy popup
--   * the L3F.GuildMap namespace
--   * a slash sub-command to re-show the popup ("/l3f guildmap privacy")
--
-- The broadcast/receive wire format lives in GuildMap/Broadcast.lua
-- (chunk 3). Pin rendering lives in GuildMap/Pins.lua (chunk 4).
-- =============================================================

local addonName, L3F = ...

L3F.GuildMap = L3F.GuildMap or {}
local GM = L3F.GuildMap

-- =============================================================
-- First-run privacy popup
-- =============================================================
-- Defined once at file load. The popup is fired on PLAYER_LOGIN if
-- L3FToolsDB.guildMap.privacyAnswered is still false. It writes the
-- user's choice to shareWithGuild and flips the flag so it never
-- re-shows on /reload or future logins, only after a fresh install
-- that wipes SavedVariables.
StaticPopupDialogs["L3F_GUILDMAP_PRIVACY"] = {
    text = "L3FTools can show your |cffffd100guildmates|r and |cffffd100friends|r on the world map and minimap in real time.\n\n"
        .. "Share your live position with guildmates and friends who also run L3FTools?\n\n"
        .. "|cffaaaaaaYou can toggle each channel separately any time from the Map tab.|r",
    button1 = "Yes, share",
    button2 = "No, keep private",
    OnAccept = function()
        if not L3FToolsDB or not L3FToolsDB.guildMap then return end
        L3FToolsDB.guildMap.shareWithGuild   = true
        L3FToolsDB.guildMap.shareWithFriends = true
        L3FToolsDB.guildMap.privacyAnswered  = true
        print("|cffffd100L3FTools|r position sharing |cff00ff00enabled|r for guildmates and friends. "
            .. "Toggle each channel anytime in the Map tab.")
    end,
    OnCancel = function()
        if not L3FToolsDB or not L3FToolsDB.guildMap then return end
        L3FToolsDB.guildMap.shareWithGuild   = false
        L3FToolsDB.guildMap.shareWithFriends = false
        L3FToolsDB.guildMap.privacyAnswered  = true
        print("|cffffd100L3FTools|r position sharing |cffff5555disabled|r. "
            .. "You can enable each channel anytime in the Map tab.")
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = false,  -- force a deliberate choice
    preferredIndex = 3,
}

function GM.ShowPrivacyPopup()
    StaticPopup_Show("L3F_GUILDMAP_PRIVACY")
end

-- Re-arm the popup (useful for manual testing / second-thoughts).
function GM.ResetPrivacyAnswer()
    if not L3FToolsDB or not L3FToolsDB.guildMap then return end
    L3FToolsDB.guildMap.privacyAnswered = false
    print("|cffffd100L3FTools|r Privacy answer cleared. Popup will re-show on next /reload or login.")
end


-- =============================================================
-- PLAYER_LOGIN: fire the popup once per fresh install
-- =============================================================
-- We use PLAYER_LOGIN (not ADDON_LOADED) so the popup appears after
-- the loading screen and other addons have settled. A 2-second
-- C_Timer delay further reduces the chance of being buried under
-- welcome chatter from other addons or guild MOTDs.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_LOGIN" then return end
    if not L3FToolsDB or not L3FToolsDB.guildMap then return end
    if L3FToolsDB.guildMap.privacyAnswered then return end
    C_Timer.After(2, function()
        if L3FToolsDB and L3FToolsDB.guildMap and not L3FToolsDB.guildMap.privacyAnswered then
            GM.ShowPrivacyPopup()
        end
    end)
end)
