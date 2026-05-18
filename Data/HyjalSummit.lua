-- Automarker L3F - Battle for Mount Hyjal (with spell IDs and notes)
local _, L3F = ...

local TRASH = {8, 7, 6, 5, 4, 3, 2, 1}

L3F:RegisterRaid({
    name = "Hyjal Summit",
    sections = {
        {
            name = "Bosses",
            npcs = {
                { id = 17767, name = "Rage Winterchill", marks = {8},
                  spells = { 31258, 31249, 31250, 31256 },
                  notes = "Healer-driven: Icebolt frozen-stuns a random target and deals ~15k frost damage over 5s while they can't pot or self-heal, so dedicated fast heals (or Frost Resistance) on the icebolted player is mandatory. Move immediately out of Death and Decay puddles. Frost Nova is mostly a cosmetic delay." },
                { id = 17808, name = "Anetheron",        marks = {8},
                  spells = { 31306, 38196, 31292, 31299 },
                  notes = "Spread healers in a wide circle so Carrion Swarm (frontal cone, 75% reduced healing done) only hits one at a time. Every ~60s he drops a Towering Infernal - the FR-geared off-tank near Jaina must immediately taunt and the raid burns it. Keep Mortal Strike / Wound Poison up to counter his Vampiric Aura self-healing before the 10-min enrage." },
                { id = 17888, name = "Kaz'rogal",        marks = {8},
                  spells = { 31447, 31436, 31480 },
                  notes = "DPS race against an accelerating Mark of Kaz'rogal that drains 600 mana/sec for 5s; anyone going OOM explodes for ~10k AoE so they must run out before detonating. Mana users chug pots non-stop, wear Shadow Resistance, warlocks Demonic Sacrifice the felhunter. Tank near the Tauren warriors and Thrall for extra DPS." },
                { id = 17842, name = "Azgalor",          marks = {8},
                  spells = { 31340, 31347, 31344, 39042 },
                  notes = "Doom is cast every ~45s on a random player who dies in 20s and spawns a Lesser Doomguard - the target must run to the off-tank near the Tauren warriors before death. Soulstone rotation keeps DPS up. Howl of Azgalor AoE-silences every 20s so keep HoTs rolling on tanks. Everyone must move out of Rain of Fire pools fast." },
                { id = 17968, name = "Archimonde",       marks = {8},
                  spells = { 32014, 31970, 31944, 31972, 35354 },
                  notes = "Everyone must carry Tears of the Goddess and use it the instant Air Burst launches them so they don't take fatal fall damage - practice this until it's instinct. Spread out to dodge Doomfire pillars and to keep Fear/Grip of the Legion (decursable shadow DoT) from chaining people into the fire. Hand of Death is his 10-minute enrage wipe, so kill before then." },
            },
        },
        {
            name = "Wave Trash",
            npcs = {
                { id = 17895, name = "Ghoul",              marks = TRASH,
                  spells = { 31540 },
                  notes = "Lowest-priority cannon fodder. Frenzy is a self attack-speed enrage that can be Tranquilizing Shot / Soothe-removed. Stack them on the off-tank and AoE down." },
                { id = 17897, name = "Crypt Fiend",        marks = TRASH,
                  spells = {},
                  notes = "Periodically Web-roots a random raid member for ~10s, making them eat melee from anything in range. Trinket/free the webbed player and burn the Fiend (interruptible, Shackleable since humanoid)." },
                { id = 17898, name = "Abomination",        marks = TRASH,
                  spells = { 31607, 31610 },
                  notes = "Permanent Disease Cloud aura ticks ~700 nature/3s in 5yd, plus Knockdown stuns the tank for 2s. Kite with stuns/slows/roots rather than face-tanking; keep melee out of the cloud unless cleansed." },
                { id = 17899, name = "Shadowy Necromancer", marks = TRASH,
                  spells = { 31627, 31626 },
                  notes = "TOP kill priority. Hardcasts Shadow Bolt (~3k shadow) and casts Unholy Frenzy on other trash to double their attack speed. Interrupt/silence/stun; a shadow priest can MC one to buff melee." },
                { id = 17905, name = "Banshee",            marks = TRASH,
                  spells = { 38183, 31651, 31662 },
                  notes = "Banshee Curse drops the target's hit chance by 66% for 5min - DECURSE IMMEDIATELY. When she casts Anti-Magic Shell she absorbs 200k magic damage, so physical DPS focus her down before the shell goes up." },
                { id = 17906, name = "Gargoyle",           marks = TRASH,
                  spells = { 31664 },
                  notes = "Spawns airborne and spams Gargoyle Strike (~850 nature) at range. A ranged player pulls threat and kites to ground for melee cleanup; watch for spawns from behind the camp attacking friendly NPCs." },
                { id = 17907, name = "Frost Wyrm",         marks = {8},
                  spells = { 31688 },
                  notes = "Frost Breath is a long-range cone hitting target + everyone within 8yd for ~2550 frost + 50% snare for 6s. Spread out behind the tank and burn fast; Frost Resistance helps on Rage Winterchill's wave." },
                { id = 17908, name = "Giant Infernal",     marks = TRASH,
                  spells = { 31723 },
                  notes = "Permanent Immolation aura burns everything within 8yd for ~713-787 fire damage per tick. Use a fire-resist tank to gather them or split the group so melee/healers aren't stacked in overlapping auras." },
                { id = 17916, name = "Fel Stalker",        marks = TRASH,
                  spells = { 31729 },
                  notes = "Mana Burn at 30yd drains ~1140 mana per cast from casters/healers. Kill or Banish (demon) before they shred your mana pool for the upcoming boss." },
            },
        },
    },
})
