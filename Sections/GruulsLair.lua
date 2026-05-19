-- Sections/GruulsLair.lua  --  spatial wing layout for the Automarker wing switcher
local _, L3F = ...

L3F:RegisterSections({
    raid  = "Gruul's Lair",
    mapID = 565,                                  -- Gruul's Lair (instanceMapID)
    sections = {
        { name = "Entrance/Maulgar", npcs = {
            { id = 19389, name = "Lair Brute" },
            { id = 21350, name = "Gronn-Priest" },
            { id = 18831, name = "High King Maulgar" },
            { id = 18832, name = "Krosh Firehand" },
            { id = 18835, name = "Kiggler the Crazed" },
            { id = 18836, name = "Blindeye the Seer" },
            { id = 18834, name = "Olm the Summoner" },
            { id = 18847, name = "Wild Fel Stalker" },
        }},
        { name = "Path to Gruul", npcs = {
            { id = 19389, name = "Lair Brute" },              -- also in Entrance/Maulgar
            { id = 21350, name = "Gronn-Priest" },            -- also in Entrance/Maulgar
            { id = 19044, name = "Gruul the Dragonkiller" },
        }},
    },
})
