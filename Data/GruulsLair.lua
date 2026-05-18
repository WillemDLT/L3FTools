-- Automarker L3F - Gruul's Lair (with spell IDs and notes)
local _, L3F = ...

local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Gruul's Lair",
    sections = {
        {
            name = "High King Maulgar & Council",
            npcs = {
                { id = 18831, name = "High King Maulgar",  marks = {8},
                  spells = { 33230, 33238, 39144, 16508, 26561 },
                  notes = "5-target pull - each council member tanked by a class counter (priest/warlock/mage/shaman) before focusing Maulgar. Mighty Blow knocks the tank back and deals huge damage; at 50% he drops his weapon, gains Berserker Charge and Intimidating Roar, so a second tank must be ready to taunt during fears." },
                { id = 18832, name = "Krosh Firehand",     marks = {7},
                  spells = { 33051, 33054, 33061 },
                  notes = "Range-tank by a Mage who Spellsteals his Spell Shield buff to mitigate Greater Fireball damage (~9k unmitigated, ~2.2k with shield). Keep melee away from his Blast Wave AoE; the tank-mage needs ~13k HP and full spell hit so the steal doesn't resist." },
                { id = 18835, name = "Kiggler the Crazed", marks = {6},
                  spells = { 36152, 33173, 33237, 33175 },
                  notes = "Range-tank him (Moonkin druid ideal - immune to Greater Polymorph) and keep him separated from the rest of the council. His Arcane Explosion knockback reduces threat, so two ranged tanks rotating threat is the safe play." },
                { id = 18836, name = "Blindeye the Seer",  marks = {5},
                  spells = { 33147, 33152, 33144 },
                  notes = "Kill him first - his Heal and Prayer of Healing fully restore the other council if uninterrupted. Burn through or Mass Dispel his Greater Power Word: Shield (absorbs 25k and blocks interrupts), then chain interrupts on the heal cast." },
                { id = 18834, name = "Olm the Summoner",   marks = {4},
                  spells = { 33129, 33130, 33131 },
                  notes = "Warlocks must Enslave the Wild Felhunters he summons and use them to tank him - Death Coil fears and heals him off any normal tank. Stacking Dark Decay is undispellable. A fresh hound must be enslaved each summon." },
            },
        },
        {
            name = "Gruul",
            npcs = {
                { id = 19044, name = "Gruul the Dragonkiller", marks = {8},
                  spells = { 36300, 33813, 33525, 33572, 33654 },
                  notes = "DPS race against Growth (+15% damage every 30s, stacks 30) - kill him by ~13-15 stacks before tank damage becomes unhealable. After Ground Slam everyone is rooted by Gronn Lord's Grasp then turned to Stoned - spread to 20+ yards before Shatter detonates or it one-shots the raid. Off-tank must always be #2 threat in melee range to eat Hurtful Strike." },
            },
        },
        {
            name = "Trash",
            npcs = {
                { id = 19389, name = "Lair Brute",       marks = TRASH,
                  spells = { 24193, 39171, 39174 },
                  notes = "Heavy-hitting ogre with Cleave (39174, frontal cone) and Mortal Strike (39171, -50% healing 5s). Charge (24193) random-targets a non-tank, dumps aggro and stuns. Tank faces away, raid stacks tight behind, off-tank taunts back after a charge." },
                { id = 21350, name = "Gronn-Priest",     marks = TRASH,
                  spells = { 22884, 36678, 36679 },
                  notes = "Caster trash that hardcasts Heal (36678 - MUST be kicked/silenced on cooldown), ticks an undispellable Renew (36679) a Mage can Spellsteal, and panics with Psychic Scream (22884, 8yd fear). Lock kicks/silences or they top each other off." },
                { id = 18847, name = "Wild Fel Stalker", marks = TRASH,
                  spells = { 33086, 33091, 33096 },
                  notes = "Olm-summoned felhound. Wild Bite (33086) ignores armor; Determination (33091) self-cleanses debuffs every 10s; Threaten (33096) force-pulls aggro at 20yd via 10k threat. Banish or Warlock-Enslave on sight; as pet it tanks Olm." },
                { id = 11859, name = "Doomguard",        marks = TRASH,
                  spells = { 89, 19474 },
                  notes = "Demon caster found among Gronn-Priest packs. Channels Rain of Fire (19474 - AoE, move out / kick) and applies Cripple (89, -40% movement, -45% attack speed, magic-dispellable). Banish/Enslave is viable; otherwise burn fast." },
            },
        },
    },
})
