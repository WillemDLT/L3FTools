-- Sections/ZulAman.lua  --  spatial wing layout for the Automarker wing switcher
local _, L3F = ...

L3F:RegisterSections({
    raid  = "Zul'Aman",
    mapID = 568,                                  -- Zul'Aman (instanceMapID)
    sections = {
        { name = "Path to Akil/Nalorakk/Jan", npcs = {
            { id = 23597, name = "Amani'shi Guardian" },
            { id = 23889, name = "Amani'shi Savage" },
            { id = 24179, name = "Amani'shi Wind Walker" },
            { id = 24180, name = "Amani'shi Protector" },
            { id = 24225, name = "Amani'shi Warrior" },
            { id = 24549, name = "Amani'shi Tempest" },
            { id = 24159, name = "Amani Eagle" },
            { id = 23581, name = "Amani'shi Medicine Man" },
            { id = 23582, name = "Amani'shi Tribesman" },
            { id = 23542, name = "Amani'shi Axe Thrower" },
            { id = 23584, name = "Amani Bear" },
            { id = 23580, name = "Amani'shi Warbringer" },
            { id = 24217, name = "Amani Bear Mount" },
            { id = 23596, name = "Amani'shi Flame Caster" },
            { id = 23586, name = "Amani'shi Scout" },
            { id = 23587, name = "Amani'shi Reinforcement" },
            { id = 23834, name = "Amani Dragonhawk" },
            { id = 23774, name = "Amani'shi Trainer" },
            { id = 23574, name = "Akil'zon (Eagle)" },
            { id = 24858, name = "Soaring Eagle" },
            { id = 23576, name = "Nalorakk (Bear)" },
            { id = 23578, name = "Jan'alai (Dragonhawk)" },
            { id = 23598, name = "Amani Dragonhawk Hatchling" },
            { id = 23818, name = "Amani'shi Hatcher" },
        }},
        { name = "Path to Halazzi", npcs = {
            { id = 24059, name = "Amani'shi Beast Tamer" },
            { id = 23596, name = "Amani'shi Flame Caster" },          -- also in Path to Akil/Nalorakk/Jan
            { id = 24530, name = "Amani Elder Lynx" },
            { id = 24064, name = "Amani Lynx Cub" },
            { id = 24138, name = "Tamed Amani Crocolisk" },
            { id = 24043, name = "Amani Lynx" },
            { id = 24065, name = "Amani'shi Handler" },
            { id = 23597, name = "Amani'shi Guardian" },              -- also in Path to Akil/Nalorakk/Jan
            { id = 23577, name = "Halazzi (Lynx)" },
            { id = 24224, name = "Corrupted Lightning Totem" },
            { id = 24143, name = "Spirit of the Lynx" },
        }},
        { name = "Path to Hex Lord", npcs = {
            { id = 24374, name = "Amani'shi Berserker" },
            { id = 23596, name = "Amani'shi Flame Caster" },          -- also in Path to Akil/Nalorakk/Jan
            { id = 24065, name = "Amani'shi Handler" },               -- also in Path to Halazzi
            { id = 24549, name = "Amani'shi Tempest" },               -- also in Path to Akil/Nalorakk/Jan
            { id = 23581, name = "Amani'shi Medicine Man" },          -- also in Path to Akil/Nalorakk/Jan
            { id = 24243, name = "Lord Raadan" },
            { id = 24240, name = "Alyson Antille" },
            { id = 24247, name = "Koragg" },
            { id = 24246, name = "Darkheart" },
            { id = 24245, name = "Fenstalker" },
            { id = 24244, name = "Gazakroth" },
            { id = 24241, name = "Thurg" },
            { id = 24242, name = "Slither" },
            { id = 24239, name = "Hex Lord Malacrass" },
        }},
        { name = "Path to Zul'Jin", npcs = {
            { id = 23889, name = "Amani'shi Savage" },                -- also in Path to Akil/Nalorakk/Jan
            { id = 23863, name = "Zul'jin" },
        }},
    },
})
