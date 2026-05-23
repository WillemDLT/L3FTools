-- Sections/Karazhan.lua  --  spatial wing layout for the Automarker wing switcher
local _, L3F = ...

L3F:RegisterSections({
    raid  = "Karazhan",
    mapID = 532,                                  -- Karazhan (instanceMapID)
    sections = {
        { name = "Entrance to Attumen", npcs = {
            { id = 15547, name = "Spectral Charger" },
            { id = 15548, name = "Spectral Stallion" },
            { id = 15551, name = "Spectral Stable Hand" },
            { id = 16151, name = "Midnight" },
            { id = 16152, name = "Attumen the Huntsman" },
        }},
        { name = "Path to Moroes", npcs = {
            { id = 16408, name = "Phantom Valet" },
            { id = 16409, name = "Phantom Guest" },
            { id = 16415, name = "Skeletal Waiter" },
            { id = 16414, name = "Ghostly Steward" },
            { id = 16406, name = "Phantom Attendant" },
            { id = 16410, name = "Spectral Retainer" },
            { id = 16407, name = "Spectral Servant" },
            { id = 16389, name = "Spectral Apprentice" },
            { id = 16412, name = "Ghostly Baker" },
            { id = 16411, name = "Spectral Chef" },
            { id = 15687, name = "Moroes" },
            { id = 19874, name = "Baron Rafe Dreuger" },
            { id = 19875, name = "Baroness Dorothea Millstipe" },
            { id = 19872, name = "Lady Catriona Von'Indi" },
            { id = 17007, name = "Lady Keira Berrybuck" },
            { id = 19873, name = "Lord Crispin Ference" },
            { id = 19876, name = "Lord Robin Daris" },
        }},
        { name = "Path to Maiden", npcs = {
            { id = 16407, name = "Spectral Servant" },        -- also in Path to Moroes
            { id = 16409, name = "Phantom Guest" },           -- also in Path to Moroes
            { id = 16408, name = "Phantom Valet" },           -- also in Path to Moroes
            { id = 16410, name = "Spectral Retainer" },       -- also in Path to Moroes
            { id = 16406, name = "Phantom Attendant" },       -- also in Path to Moroes
            { id = 16425, name = "Phantom Guardsman" },
            { id = 17067, name = "Phantom Hound" },
            { id = 16424, name = "Spectral Sentry" },
            { id = 16460, name = "Night Mistress" },
            { id = 184259, name = "Night Lord" },
            { id = 16459, name = "Wanton Hostess" },
            { id = 184261, name = "Wanton Host" },
            { id = 16461, name = "Zealous Paramour" },
            { id = 184263, name = "Zealous Consort" },
            { id = 16457, name = "Maiden of Virtue" },
        }},
        { name = "Path to Opera", npcs = {
            { id = 16471, name = "Skeletal Usher" },
            { id = 16473, name = "Spectral Performer" },
            { id = 16472, name = "Phantom Stagehand" },
            { id = 17535, name = "Dorothee" },
            { id = 17548, name = "Tito" },
            { id = 17543, name = "Strawman" },
            { id = 17547, name = "Tinhead" },
            { id = 17546, name = "Roar" },
            { id = 18168, name = "The Crone" },
            { id = 17533, name = "Romulo" },
            { id = 17534, name = "Julianne" },
            { id = 17521, name = "The Big Bad Wolf" },
        }},
        { name = "Path to Nightbane", npcs = {
            { id = 16468, name = "Spectral Patron" },
            { id = 16470, name = "Ghostly Philanthropist" },
            { id = 16482, name = "Trapped Soul" },
            { id = 16481, name = "Ghastly Haunt" },
            { id = 17225, name = "Nightbane" },
            { id = 17261, name = "Restless Skeleton" },
        }},
        { name = "Path to Curator", npcs = {
            { id = 16482, name = "Trapped Soul" },            -- also in Path to Nightbane
            { id = 16481, name = "Ghastly Haunt" },           -- also in Path to Nightbane
            { id = 16485, name = "Arcane Watchman" },
            { id = 16488, name = "Arcane Anomaly" },
            { id = 16492, name = "Syphoner" },
            { id = 15691, name = "The Curator" },
        }},
        { name = "Path to Teres", npcs = {
            { id = 16485, name = "Arcane Watchman" },         -- also in Path to Curator
            { id = 16504, name = "Arcane Protector" },
            { id = 16489, name = "Chaotic Sentience" },
            { id = 16491, name = "Mana Feeder" },
            { id = 16529, name = "Magical Horror" },
            { id = 16530, name = "Mana Warp" },
            { id = 16525, name = "Spell Shade" },
            { id = 16540, name = "Shadow Pillager" },
            { id = 16539, name = "Homunculus" },
            { id = 15688, name = "Terestian Illhoof" },
            { id = 17229, name = "Kil'rek" },
            { id = 17267, name = "Fiendish Imp" },
            { id = 17248, name = "Demon Chains" },
        }},
        { name = "Path to Aran", npcs = {
            { id = 16525, name = "Spell Shade" },             -- also in Path to Teres
            { id = 16524, name = "Shade of Aran" },
            { id = 17167, name = "Conjured Elemental" },
        }},
        { name = "Path to Netherspite/Chess", npcs = {
            { id = 16525, name = "Spell Shade" },             -- also in Path to Teres, Path to Aran
            { id = 16526, name = "Sorcerous Shade" },
            { id = 16544, name = "Ethereal Thief" },
            { id = 16545, name = "Ethereal Spellfilcher" },
            { id = 15689, name = "Netherspite" },
        }},
        { name = "Path to Prince", npcs = {
            { id = 16595, name = "Fleshbeast" },
            { id = 16596, name = "Greater Fleshbeast" },
            { id = 15690, name = "Prince Malchezaar" },
        }},
    },
})
