-- Sections/TempestKeep.lua  --  spatial wing layout for the Automarker wing switcher
local _, L3F = ...

L3F:RegisterSections({
    raid  = "Tempest Keep",
    mapID = 550,                                  -- The Eye (instanceMapID)
    sections = {
        { name = "Entrance to Al'ar", npcs = {
            { id = 20034, name = "Star Scryer" },
            { id = 20032, name = "Bloodwarder Vindicator" },
            { id = 20033, name = "Astromancer" },
            { id = 20031, name = "Bloodwarder Legionnaire" },
            { id = 20035, name = "Bloodwarder Marshal" },
            { id = 20036, name = "Bloodwarder Squire" },
            { id = 20038, name = "Phoenix-Hawk Hatchling" },
            { id = 20037, name = "Tempest Falconer" },
            { id = 20039, name = "Phoenix-Hawk" },
            { id = 19514, name = "Al'ar" },
            { id = 19551, name = "Ember of Al'ar" },
        }},
        { name = "Left path : to Void Reaver", npcs = {
            { id = 20040, name = "Crystalcore Devastator" },
            { id = 20041, name = "Crystalcore Sentinel" },
            { id = 20042, name = "Tempest-Smith" },
            { id = 20052, name = "Crystalcore Mechanic" },
            { id = 19516, name = "Void Reaver" },
        }},
        { name = "Right path : to Solarian", npcs = {
            { id = 20046, name = "Astromancer Lord" },
            { id = 20031, name = "Bloodwarder Legionnaire" },     -- also in Entrance to Al'ar
            { id = 20041, name = "Crystalcore Sentinel" },        -- also in Left path
            { id = 20044, name = "Novice Astromancer" },
            { id = 20043, name = "Apprentice Star Scryer" },
            { id = 20036, name = "Bloodwarder Squire" },          -- also in Entrance to Al'ar
            { id = 20045, name = "Nether Scryer" },
            { id = 18805, name = "High Astromancer Solarian" },
            { id = 18925, name = "Solarium Agent" },
            { id = 18806, name = "Solarium Priest" },
        }},
        { name = "Path to Kael'thas", npcs = {
            { id = 20048, name = "Crimson Hand Centurion" },
            { id = 20050, name = "Crimson Hand Inquisitor" },
            { id = 20047, name = "Crimson Hand Battle Mage" },
            { id = 20049, name = "Crimson Hand Blood Knight" },
        }},
        { name = "Kael'thas Room", npcs = {
            { id = 20049, name = "Crimson Hand Blood Knight" },   -- also in Path to Kael'thas
            { id = 20048, name = "Crimson Hand Centurion" },      -- also in Path to Kael'thas
            { id = 20050, name = "Crimson Hand Inquisitor" },     -- also in Path to Kael'thas
            { id = 20035, name = "Bloodwarder Marshal" },         -- also in Entrance to Al'ar
            { id = 20064, name = "Thaladred the Darkener" },
            { id = 20060, name = "Lord Sanguinar" },
            { id = 20062, name = "Grand Astromancer Capernian" },
            { id = 20063, name = "Master Engineer Telonicus" },
            { id = 19622, name = "Kael'thas Sunstrider" },
            { id = 21364, name = "Phoenix Egg" },
            { id = 21362, name = "Phoenix" },
            { id = 21272, name = "Warp Slicer" },
            { id = 21271, name = "Infinity Blades" },
            { id = 21273, name = "Phaseshift Bulwark" },
            { id = 21269, name = "Devastation" },
            { id = 21274, name = "Staff of Disintegration" },
            { id = 21270, name = "Cosmic Infuser" },
            { id = 21268, name = "Netherstrand Longbow" },
        }},
    },
})
