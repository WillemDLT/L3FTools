-- L3FTools - The Shattered Halls
local _, L3F = ...
local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "The Shattered Halls",
    location = "Hellfire Citadel - The Shattered Halls",
    npcs = {
        { id = 16807, name = "Grand Warlock Nethekurse", marks = {8},
          level = 70, type = "Humanoid",
          spells = { 30910, 30909, 30907, 30529 },
          notes = "Trash phase: he buffs Shadowmoon Darkcasters with Dark Spin / Death Coils - kill all four casters before engaging the boss. In boss phase, dispel Dark Spin on tank and spread out for Shadowburn explosions.",
          drops = {
              { id = 27502, name = "Embrace of Everlasting Prayer", chance = 18.7 },
              { id = 27503, name = "Boots of the Shifting Sands", chance = 18.5 },
              { id = 27504, name = "Hope Bearer Helm", chance = 18.3 },
              { id = 29434, name = "Badge of Justice", chance = 100.0 },
          } },
        { id = 16809, name = "Warbringer O'mrogg", marks = {8},
          level = 70, type = "Humanoid",
          spells = { 30616, 32154, 30618 },
          notes = "Two-headed ogre - one head taunts a random player, the other keeps tanking. Burst threat for the off-tank during Burning Maul; spread for Thunderclap-style AoE.",
          drops = {
              { id = 27507, name = "Adamantine Plate Gloves", chance = 18.6 },
              { id = 27508, name = "Adamantine Plate Belt", chance = 18.4 },
              { id = 29434, name = "Badge of Justice", chance = 100.0 },
          } },
        { id = 16808, name = "Warchief Kargath Bladefist", marks = {8},
          level = 70, type = "Humanoid",
          spells = { 30620, 30621, 30627 },
          notes = "Blade Dance phase - he becomes immune and chases random targets dealing massive damage. Pre-event spawns Shattered Hand wave-adds; kill Executioners that drag/execute caged orcs first.",
          drops = {
              { id = 28267, name = "Bloodlust Brooch", chance = 19.0 },
              { id = 28268, name = "Liar's Tongue Gloves", chance = 18.7 },
              { id = 28266, name = "Wastewalker Helm", chance = 18.5 },
              { id = 28269, name = "Earthwarden", chance = 18.3 },
              { id = 28270, name = "Edge of the Cosmos", chance = 18.1 },
              { id = 29434, name = "Badge of Justice", chance = 100.0 },
          } },
    },
})
