-- Sections/HyjalSummit.lua  --  spatial wing layout for the Automarker wing switcher
local _, L3F = ...

L3F:RegisterSections({
    raid  = "Hyjal Summit",
    mapID = 534,                                  -- Hyjal Summit / Battle for Mount Hyjal (instanceMapID)
    sections = {
        { name = "Hyjal Summit", npcs = {
            { id = 17895, name = "Ghoul" },
            { id = 17897, name = "Crypt Fiend" },
            { id = 17898, name = "Abomination" },
            { id = 17899, name = "Shadowy Necromancer" },
            { id = 17905, name = "Banshee" },
            { id = 17906, name = "Gargoyle" },
            { id = 17916, name = "Fel Stalker" },
            { id = 17907, name = "Frost Wyrm" },
            { id = 17767, name = "Rage Winterchill" },
            { id = 17808, name = "Anetheron" },
            { id = 17908, name = "Giant Infernal" },
            { id = 17888, name = "Kaz'rogal" },
            { id = 17842, name = "Azgalor" },
            { id = 17864, name = "Lesser Doomguard" },
            { id = 17968, name = "Archimonde" },
        }},
    },
})
