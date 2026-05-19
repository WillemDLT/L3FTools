-- Sections/MagtheridonsLair.lua  --  spatial wing layout for the Automarker wing switcher
local _, L3F = ...

L3F:RegisterSections({
    raid  = "Magtheridon's Lair",
    mapID = 544,                                  -- Magtheridon's Lair (instanceMapID)
    sections = {
        { name = "Trash", npcs = {
            { id = 18829, name = "Hellfire Warder" },
        }},
        { name = "Boss", npcs = {
            { id = 17256, name = "Hellfire Channeler" },
            { id = 17454, name = "Burning Abyssal" },
            { id = 17257, name = "Magtheridon" },
        }},
    },
})
