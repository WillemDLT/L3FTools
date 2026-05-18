-- L3FTools - Shadow Labyrinth
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Shadow Labyrinth",
    location = "Auchindoun - Shadow Labyrinth",
    npcs = {
        { id = 18731, name = "Ambassador Hellmaw", marks = {8},
          level = 72, type = "Demon",
          spells = { 33547, 33551 },
          notes = "AoE Fear on ~30s CD - use tremor totem or fear ward. Corrosive Acid frontal cone (armor debuff) - tank face away. Killing the last Overseer activates him.",
          drops = {} },
        { id = 18667, name = "Blackheart the Inciter", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 33676, 33707 },
          notes = "Incite Chaos at 25s and 1m30s - MCs the entire party to attack each other. Burn cooldowns before each cast. Random charges and War Stomps reset aggro.",
          drops = {} },
        { id = 18732, name = "Grandmaster Vorpil", marks = {8},
          level = 72, type = "Humanoid",
          spells = { 32963, 33617, 33768 },
          notes = "Periodically teleports party to himself + Rain of Fire (run out). Summons 3 Void Travelers per cycle - kill or banish before they reach him (heal him on contact).",
          drops = {} },
        { id = 18708, name = "Murmur", marks = {8},
          level = 72, type = "Elemental",
          spells = { 33923, 33711, 33651, 33689 },
          notes = "Starts at 40% HP. Sonic Boom AoE ~8500 nature - everyone OUT of circle on cast. Murmur's Touch silences + 15s timer that explodes target. Resonance debuffs if you're out of melee.",
          drops = {} },
    },
})
