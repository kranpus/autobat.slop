class_name GameData
extends RefCounted
## Static game definitions: units, rarities, regions and damage tables.
## Everything here is plain data so it can be tweaked without touching logic.

const MAX_SQUADS := 8
const MAX_TIER := 10
const BASE_MAX_LEVEL := 10
const LEVELS_PER_TIER := 4

const RARITIES := {
	"common":    {"name": "Common",    "color": "b8b8b8", "order": 0, "power_mult": 1.0, "squad_base": 30, "squad_step": 15, "cost_mult": 1.0, "shard_base": 10, "find_shards": [3, 6]},
	"uncommon":  {"name": "Uncommon",  "color": "5fd35f", "order": 1, "power_mult": 1.0, "squad_base": 15, "squad_step": 8,  "cost_mult": 1.5, "shard_base": 8,  "find_shards": [2, 4]},
	"rare":      {"name": "Rare",      "color": "4f9dff", "order": 2, "power_mult": 1.1, "squad_base": 6,  "squad_step": 3,  "cost_mult": 2.5, "shard_base": 5,  "find_shards": [1, 3]},
	"epic":      {"name": "Epic",      "color": "c065ff", "order": 3, "power_mult": 1.3, "squad_base": 2,  "squad_step": 1,  "cost_mult": 4.0, "shard_base": 3,  "find_shards": [1, 2]},
	"legendary": {"name": "Legendary", "color": "ffb43c", "order": 4, "power_mult": 1.8, "squad_base": 1,  "squad_step": 1,  "cost_mult": 6.0, "shard_base": 2,  "find_shards": [1, 1]},
}

# Damage types and armor classes. DAMAGE_MULT[damage][armor].
const DAMAGE_TYPES := ["physical", "pierce", "magic", "fire"]
const ARMOR_TYPES := ["light", "heavy", "undead", "beast"]
const DAMAGE_MULT := [
	# light heavy undead beast
	[1.00, 0.70, 1.00, 1.15],  # physical
	[1.30, 0.60, 0.60, 1.10],  # pierce
	[1.00, 1.40, 0.90, 1.00],  # magic
	[1.10, 0.90, 1.50, 1.30],  # fire
]
const MELEE_VS_FLYING_MULT := 0.6

const ROLES := ["melee", "ranged", "caster", "healer", "tank"]
const PROJECTILES := ["none", "arrow", "stone", "javelin", "magic", "fire"]
const PROJECTILE_SPEED := [0.0, 560.0, 420.0, 500.0, 380.0, 340.0]

# Base stats at level 1. range is the extra reach beyond body radius.
# speed in px/s, cooldown in seconds, aoe radius in px, regen in hp/s.
const UNITS := {
	"goblin": {
		"name": "Goblin Skirmisher", "rarity": "common", "role": "melee",
		"hp": 60.0, "dmg": 9.0, "cooldown": 0.8, "range": 6.0, "speed": 72.0,
		"damage": "physical", "armor": "light", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 7.0, "scale": 0.8, "flying": false,
		"desc": "Cheap, quick and numerous. Overwhelms archers.",
	},
	"kobold_slinger": {
		"name": "Kobold Slinger", "rarity": "common", "role": "ranged",
		"hp": 40.0, "dmg": 8.0, "cooldown": 1.2, "range": 140.0, "speed": 55.0,
		"damage": "physical", "armor": "light", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "stone", "radius": 7.0, "scale": 0.8, "flying": false,
		"desc": "Flings stones from behind the line.",
	},
	"rat_swarm": {
		"name": "Giant Rat", "rarity": "common", "role": "melee",
		"hp": 35.0, "dmg": 6.0, "cooldown": 0.6, "range": 5.0, "speed": 96.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 6.0, "scale": 0.7, "flying": false,
		"desc": "Very fast swarm. Great for flanking backlines.",
	},
	"skeleton": {
		"name": "Skeleton Warrior", "rarity": "common", "role": "melee",
		"hp": 90.0, "dmg": 10.0, "cooldown": 1.0, "range": 6.0, "speed": 50.0,
		"damage": "physical", "armor": "undead", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 7.0, "scale": 0.85, "flying": false,
		"desc": "Shrugs off arrows. Burns easily.",
	},
	"orc_warrior": {
		"name": "Orc Warrior", "rarity": "uncommon", "role": "melee",
		"hp": 150.0, "dmg": 16.0, "cooldown": 1.0, "range": 6.0, "speed": 55.0,
		"damage": "physical", "armor": "heavy", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 8.0, "scale": 0.9, "flying": false,
		"desc": "Armoured frontline infantry.",
	},
	"elf_archer": {
		"name": "Elven Archer", "rarity": "uncommon", "role": "ranged",
		"hp": 70.0, "dmg": 14.0, "cooldown": 1.1, "range": 220.0, "speed": 60.0,
		"damage": "pierce", "armor": "light", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "arrow", "radius": 7.0, "scale": 0.85, "flying": false,
		"desc": "Long range. Shreds light armour and beasts.",
	},
	"gnoll_shaman": {
		"name": "Gnoll Shaman", "rarity": "uncommon", "role": "healer",
		"hp": 80.0, "dmg": 5.0, "cooldown": 1.5, "range": 150.0, "speed": 55.0,
		"damage": "magic", "armor": "beast", "aoe": 0.0, "heal": 20.0, "regen": 0.0,
		"projectile": "magic", "radius": 7.0, "scale": 0.85, "flying": false,
		"desc": "Heals the most wounded ally in range.",
	},
	"dwarf_berserker": {
		"name": "Dwarf Berserker", "rarity": "uncommon", "role": "melee",
		"hp": 180.0, "dmg": 22.0, "cooldown": 1.1, "range": 6.0, "speed": 50.0,
		"damage": "physical", "armor": "heavy", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 8.0, "scale": 0.85, "flying": false,
		"desc": "Hits hard, takes hits harder.",
	},
	"dire_wolf": {
		"name": "Dire Wolf", "rarity": "uncommon", "role": "melee",
		"hp": 110.0, "dmg": 14.0, "cooldown": 0.7, "range": 6.0, "speed": 112.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 8.0, "scale": 0.9, "flying": false,
		"desc": "Fast hunters that dive enemy ranged units.",
	},
	"ogre": {
		"name": "Ogre Brute", "rarity": "rare", "role": "tank",
		"hp": 520.0, "dmg": 45.0, "cooldown": 1.6, "range": 8.0, "speed": 45.0,
		"damage": "physical", "armor": "beast", "aoe": 30.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 12.0, "scale": 1.3, "flying": false,
		"desc": "Club swings hit everything nearby.",
	},
	"centaur": {
		"name": "Centaur Warrior", "rarity": "rare", "role": "ranged",
		"hp": 260.0, "dmg": 30.0, "cooldown": 1.2, "range": 200.0, "speed": 90.0,
		"damage": "pierce", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "javelin", "radius": 11.0, "scale": 1.2, "flying": false,
		"desc": "Mobile javelin thrower.",
	},
	"orc_sorcerer": {
		"name": "Orc Sorcerer", "rarity": "rare", "role": "caster",
		"hp": 160.0, "dmg": 34.0, "cooldown": 2.0, "range": 200.0, "speed": 45.0,
		"damage": "fire", "armor": "light", "aoe": 45.0, "heal": 0.0, "regen": 0.0,
		"projectile": "fire", "radius": 8.0, "scale": 1.0, "flying": false,
		"desc": "Fireballs devastate packed formations.",
	},
	"naga_sharpshooter": {
		"name": "Naga Sharpshooter", "rarity": "rare", "role": "ranged",
		"hp": 220.0, "dmg": 40.0, "cooldown": 1.4, "range": 260.0, "speed": 45.0,
		"damage": "pierce", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "arrow", "radius": 10.0, "scale": 1.1, "flying": false,
		"desc": "Longest-ranged archer in the realm.",
	},
	"treant": {
		"name": "Ancient Treant", "rarity": "rare", "role": "tank",
		"hp": 900.0, "dmg": 30.0, "cooldown": 1.8, "range": 8.0, "speed": 30.0,
		"damage": "physical", "armor": "heavy", "aoe": 0.0, "heal": 0.0, "regen": 8.0,
		"projectile": "none", "radius": 13.0, "scale": 1.4, "flying": false,
		"desc": "Slow, regenerating wall of bark. Fears fire.",
	},
	"hill_giant": {
		"name": "Hill Giant", "rarity": "epic", "role": "tank",
		"hp": 1200.0, "dmg": 73.0, "cooldown": 2.0, "range": 10.0, "speed": 40.0,
		"damage": "physical", "armor": "beast", "aoe": 50.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 16.0, "scale": 1.8, "flying": false,
		"desc": "Stomps whole squads flat.",
	},
	"lich": {
		"name": "Lich", "rarity": "epic", "role": "caster",
		"hp": 460.0, "dmg": 46.0, "cooldown": 2.2, "range": 240.0, "speed": 40.0,
		"damage": "magic", "armor": "undead", "aoe": 70.0, "heal": 0.0, "regen": 0.0,
		"projectile": "magic", "radius": 10.0, "scale": 1.3, "flying": false,
		"desc": "Arcane blasts melt heavy armour.",
	},
	"griffon": {
		"name": "Griffon", "rarity": "epic", "role": "melee",
		"hp": 730.0, "dmg": 40.0, "cooldown": 0.9, "range": 8.0, "speed": 130.0,
		"damage": "pierce", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 14.0, "scale": 1.6, "flying": true,
		"desc": "Flies over the melee to hunt casters.",
	},
	"golden_dragon": {
		"name": "Golden Dragon", "rarity": "legendary", "role": "caster",
		"hp": 3000.0, "dmg": 80.0, "cooldown": 2.0, "range": 170.0, "speed": 70.0,
		"damage": "fire", "armor": "beast", "aoe": 80.0, "heal": 0.0, "regen": 0.0,
		"projectile": "fire", "radius": 22.0, "scale": 2.4, "flying": true,
		"desc": "Breathes fire over entire regiments.",
	},
	"titan": {
		"name": "Storm Titan", "rarity": "legendary", "role": "tank",
		"hp": 1750.0, "dmg": 55.0, "cooldown": 1.8, "range": 12.0, "speed": 45.0,
		"damage": "magic", "armor": "heavy", "aoe": 70.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 22.0, "scale": 2.4, "flying": false,
		"desc": "An unstoppable colossus.",
	},
	"phoenix": {
		"name": "Phoenix", "rarity": "legendary", "role": "caster",
		"hp": 1750.0, "dmg": 55.0, "cooldown": 1.4, "range": 180.0, "speed": 110.0,
		"damage": "fire", "armor": "beast", "aoe": 60.0, "heal": 0.0, "regen": 20.0,
		"projectile": "fire", "radius": 18.0, "scale": 2.0, "flying": true,
		"desc": "Blazing, fast and self-healing.",
	},
	# --- Locked by default (enable with the server's `unlock` command) ---
	"jackal": {
		"name": "Jackal Pack", "rarity": "common", "role": "melee", "locked": true,
		"hp": 45.0, "dmg": 7.0, "cooldown": 0.6, "range": 5.0, "speed": 105.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 6.0, "scale": 0.7, "flying": false,
		"desc": "Fast scavengers that hunt in packs.",
	},
	"giant_frog": {
		"name": "Giant Frog", "rarity": "common", "role": "melee", "locked": true,
		"hp": 70.0, "dmg": 8.0, "cooldown": 0.9, "range": 5.0, "speed": 80.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 7.0, "scale": 0.8, "flying": false,
		"desc": "Leaps into the fray and soaks up blows.",
	},
	"hobgoblin": {
		"name": "Hobgoblin", "rarity": "common", "role": "melee", "locked": true,
		"hp": 85.0, "dmg": 10.0, "cooldown": 1.0, "range": 6.0, "speed": 60.0,
		"damage": "physical", "armor": "light", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 7.0, "scale": 0.8, "flying": false,
		"desc": "Tougher goblin kin with crude shields.",
	},
	"gnoll_raider": {
		"name": "Gnoll Raider", "rarity": "common", "role": "melee", "locked": true,
		"hp": 75.0, "dmg": 11.0, "cooldown": 0.9, "range": 6.0, "speed": 70.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 7.0, "scale": 0.8, "flying": false,
		"desc": "Cackling raiders that strike hard and fast.",
	},
	"kobold_brute": {
		"name": "Kobold Brute", "rarity": "common", "role": "melee", "locked": true,
		"hp": 95.0, "dmg": 9.0, "cooldown": 1.0, "range": 6.0, "speed": 55.0,
		"damage": "physical", "armor": "light", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 8.0, "scale": 0.9, "flying": false,
		"desc": "The biggest kobold in the warren.",
	},
	"cave_bat": {
		"name": "Cave Bat", "rarity": "common", "role": "melee", "locked": true,
		"hp": 30.0, "dmg": 6.0, "cooldown": 0.6, "range": 5.0, "speed": 120.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 6.0, "scale": 0.7, "flying": true,
		"desc": "Flitting swarms that fly over terrain.",
	},
	"soldier_ant": {
		"name": "Soldier Ant", "rarity": "common", "role": "melee", "locked": true,
		"hp": 55.0, "dmg": 8.0, "cooldown": 0.8, "range": 5.0, "speed": 75.0,
		"damage": "physical", "armor": "heavy", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 6.0, "scale": 0.8, "flying": false,
		"desc": "Armoured insects that come in endless numbers.",
	},
	"goblin_archer": {
		"name": "Goblin Archer", "rarity": "common", "role": "ranged", "locked": true,
		"hp": 40.0, "dmg": 8.0, "cooldown": 1.1, "range": 170.0, "speed": 60.0,
		"damage": "pierce", "armor": "light", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "arrow", "radius": 7.0, "scale": 0.8, "flying": false,
		"desc": "Goblins with short bows and shorter tempers.",
	},
	"orc_knight": {
		"name": "Orc Knight", "rarity": "uncommon", "role": "tank", "locked": true,
		"hp": 260.0, "dmg": 18.0, "cooldown": 1.1, "range": 6.0, "speed": 50.0,
		"damage": "physical", "armor": "heavy", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 9.0, "scale": 1.0, "flying": false,
		"desc": "Plate-armoured orc veterans.",
	},
	"elf_knight": {
		"name": "Elven Knight", "rarity": "uncommon", "role": "melee", "locked": true,
		"hp": 170.0, "dmg": 20.0, "cooldown": 0.9, "range": 6.0, "speed": 70.0,
		"damage": "physical", "armor": "light", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 8.0, "scale": 0.9, "flying": false,
		"desc": "Swift blades of the deep elves.",
	},
	"hippogriff": {
		"name": "Hippogriff", "rarity": "uncommon", "role": "melee", "locked": true,
		"hp": 200.0, "dmg": 16.0, "cooldown": 0.8, "range": 6.0, "speed": 120.0,
		"damage": "pierce", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 10.0, "scale": 1.1, "flying": true,
		"desc": "A lighter cousin of the griffon.",
	},
	"war_hound": {
		"name": "War Hound", "rarity": "uncommon", "role": "melee", "locked": true,
		"hp": 130.0, "dmg": 15.0, "cooldown": 0.7, "range": 6.0, "speed": 115.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 8.0, "scale": 0.8, "flying": false,
		"desc": "Trained to tear into archers.",
	},
	"black_bear": {
		"name": "Black Bear", "rarity": "uncommon", "role": "tank", "locked": true,
		"hp": 280.0, "dmg": 20.0, "cooldown": 1.2, "range": 6.0, "speed": 55.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 10.0, "scale": 1.1, "flying": false,
		"desc": "Thick fur and a thicker skull.",
	},
	"elf_mage": {
		"name": "Elven Mage", "rarity": "uncommon", "role": "caster", "locked": true,
		"hp": 80.0, "dmg": 22.0, "cooldown": 1.8, "range": 190.0, "speed": 55.0,
		"damage": "magic", "armor": "light", "aoe": 30.0, "heal": 0.0, "regen": 0.0,
		"projectile": "magic", "radius": 7.0, "scale": 0.8, "flying": false,
		"desc": "Arcane bolts that splash small groups.",
	},
	"wight": {
		"name": "Wight", "rarity": "uncommon", "role": "melee", "locked": true,
		"hp": 160.0, "dmg": 16.0, "cooldown": 1.0, "range": 6.0, "speed": 50.0,
		"damage": "physical", "armor": "undead", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 8.0, "scale": 0.9, "flying": false,
		"desc": "Restless dead that grow stronger in defeat.",
	},
	"naga_warrior": {
		"name": "Naga Warrior", "rarity": "uncommon", "role": "melee", "locked": true,
		"hp": 190.0, "dmg": 18.0, "cooldown": 1.0, "range": 6.0, "speed": 50.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 9.0, "scale": 1.0, "flying": false,
		"desc": "Serpentine fighters that crush in their coils.",
	},
	"merfolk_impaler": {
		"name": "Merfolk Impaler", "rarity": "uncommon", "role": "melee", "locked": true,
		"hp": 150.0, "dmg": 19.0, "cooldown": 1.1, "range": 18.0, "speed": 55.0,
		"damage": "pierce", "armor": "light", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 8.0, "scale": 0.9, "flying": false,
		"desc": "Long tridents strike over the front rank.",
	},
	"tengu_warrior": {
		"name": "Tengu Warrior", "rarity": "uncommon", "role": "melee", "locked": true,
		"hp": 120.0, "dmg": 16.0, "cooldown": 0.8, "range": 6.0, "speed": 110.0,
		"damage": "physical", "armor": "light", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 8.0, "scale": 0.9, "flying": true,
		"desc": "Winged swordsmen who strike from above.",
	},
	"troll": {
		"name": "Troll", "rarity": "rare", "role": "tank", "locked": true,
		"hp": 620.0, "dmg": 38.0, "cooldown": 1.4, "range": 8.0, "speed": 50.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 10.0,
		"projectile": "none", "radius": 12.0, "scale": 1.3, "flying": false,
		"desc": "Regenerates its wounds in moments.",
	},
	"troll_berserker": {
		"name": "Troll Berserker", "rarity": "rare", "role": "melee", "locked": true,
		"hp": 480.0, "dmg": 48.0, "cooldown": 1.1, "range": 8.0, "speed": 60.0,
		"damage": "physical", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 12.0, "scale": 1.3, "flying": false,
		"desc": "Pure fury on two enormous legs.",
	},
	"cyclops": {
		"name": "Cyclops", "rarity": "rare", "role": "ranged", "locked": true,
		"hp": 520.0, "dmg": 50.0, "cooldown": 2.0, "range": 220.0, "speed": 40.0,
		"damage": "physical", "armor": "beast", "aoe": 35.0, "heal": 0.0, "regen": 0.0,
		"projectile": "stone", "radius": 13.0, "scale": 1.4, "flying": false,
		"desc": "Hurls boulders across the battlefield.",
	},
	"minotaur": {
		"name": "Minotaur", "rarity": "rare", "role": "melee", "locked": true,
		"hp": 560.0, "dmg": 44.0, "cooldown": 1.2, "range": 8.0, "speed": 65.0,
		"damage": "physical", "armor": "beast", "aoe": 20.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 12.0, "scale": 1.3, "flying": false,
		"desc": "Charges through formations horns-first.",
	},
	"manticore": {
		"name": "Manticore", "rarity": "rare", "role": "ranged", "locked": true,
		"hp": 420.0, "dmg": 34.0, "cooldown": 1.1, "range": 180.0, "speed": 80.0,
		"damage": "pierce", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "javelin", "radius": 12.0, "scale": 1.3, "flying": false,
		"desc": "Flings tail spikes while it circles.",
	},
	"ettin": {
		"name": "Ettin", "rarity": "rare", "role": "tank", "locked": true,
		"hp": 760.0, "dmg": 40.0, "cooldown": 1.5, "range": 8.0, "speed": 45.0,
		"damage": "physical", "armor": "beast", "aoe": 30.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 13.0, "scale": 1.4, "flying": false,
		"desc": "Two heads, two clubs, no mercy.",
	},
	"salamander_firebrand": {
		"name": "Salamander Firebrand", "rarity": "rare", "role": "caster", "locked": true,
		"hp": 200.0, "dmg": 36.0, "cooldown": 1.8, "range": 180.0, "speed": 55.0,
		"damage": "fire", "armor": "beast", "aoe": 40.0, "heal": 0.0, "regen": 0.0,
		"projectile": "fire", "radius": 9.0, "scale": 1.0, "flying": false,
		"desc": "Lobs blazing fireballs into the crowd.",
	},
	"vampire_knight": {
		"name": "Vampire Knight", "rarity": "rare", "role": "melee", "locked": true,
		"hp": 440.0, "dmg": 36.0, "cooldown": 1.0, "range": 8.0, "speed": 60.0,
		"damage": "physical", "armor": "undead", "aoe": 0.0, "heal": 0.0, "regen": 6.0,
		"projectile": "none", "radius": 10.0, "scale": 1.1, "flying": false,
		"desc": "Drains the life of everything it cuts.",
	},
	"orc_warlord": {
		"name": "Orc Warlord", "rarity": "rare", "role": "tank", "locked": true,
		"hp": 600.0, "dmg": 40.0, "cooldown": 1.2, "range": 8.0, "speed": 50.0,
		"damage": "physical", "armor": "heavy", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 11.0, "scale": 1.2, "flying": false,
		"desc": "Leads from the front with a giant axe.",
	},
	"death_knight": {
		"name": "Death Knight", "rarity": "rare", "role": "melee", "locked": true,
		"hp": 520.0, "dmg": 42.0, "cooldown": 1.2, "range": 8.0, "speed": 50.0,
		"damage": "magic", "armor": "undead", "aoe": 0.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 11.0, "scale": 1.2, "flying": false,
		"desc": "Cursed steel that cuts through plate.",
	},
	"stone_giant": {
		"name": "Stone Giant", "rarity": "epic", "role": "ranged", "locked": true,
		"hp": 1300.0, "dmg": 80.0, "cooldown": 2.4, "range": 240.0, "speed": 38.0,
		"damage": "physical", "armor": "beast", "aoe": 45.0, "heal": 0.0, "regen": 0.0,
		"projectile": "stone", "radius": 16.0, "scale": 1.8, "flying": false,
		"desc": "Throws boulders the size of houses.",
	},
	"frost_giant": {
		"name": "Frost Giant", "rarity": "epic", "role": "tank", "locked": true,
		"hp": 1400.0, "dmg": 70.0, "cooldown": 2.0, "range": 10.0, "speed": 40.0,
		"damage": "magic", "armor": "beast", "aoe": 45.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 16.0, "scale": 1.8, "flying": false,
		"desc": "Ice-rimed fists shatter armour.",
	},
	"fire_giant": {
		"name": "Fire Giant", "rarity": "epic", "role": "caster", "locked": true,
		"hp": 1200.0, "dmg": 75.0, "cooldown": 2.0, "range": 180.0, "speed": 40.0,
		"damage": "fire", "armor": "beast", "aoe": 55.0, "heal": 0.0, "regen": 0.0,
		"projectile": "fire", "radius": 16.0, "scale": 1.8, "flying": false,
		"desc": "Hurls molten iron from its forge.",
	},
	"sphinx": {
		"name": "Sphinx", "rarity": "epic", "role": "caster", "locked": true,
		"hp": 900.0, "dmg": 55.0, "cooldown": 1.8, "range": 200.0, "speed": 90.0,
		"damage": "magic", "armor": "beast", "aoe": 40.0, "heal": 0.0, "regen": 0.0,
		"projectile": "magic", "radius": 14.0, "scale": 1.6, "flying": true,
		"desc": "An ancient riddler with withering spells.",
	},
	"ice_dragon": {
		"name": "Ice Dragon", "rarity": "epic", "role": "caster", "locked": true,
		"hp": 1000.0, "dmg": 60.0, "cooldown": 1.9, "range": 170.0, "speed": 75.0,
		"damage": "magic", "armor": "beast", "aoe": 60.0, "heal": 0.0, "regen": 0.0,
		"projectile": "magic", "radius": 16.0, "scale": 1.8, "flying": true,
		"desc": "Freezing breath over whole regiments.",
	},
	"hydra": {
		"name": "Hydra", "rarity": "epic", "role": "tank", "locked": true,
		"hp": 1600.0, "dmg": 50.0, "cooldown": 0.8, "range": 10.0, "speed": 40.0,
		"damage": "pierce", "armor": "beast", "aoe": 0.0, "heal": 0.0, "regen": 25.0,
		"projectile": "none", "radius": 16.0, "scale": 1.8, "flying": false,
		"desc": "Cut off one head and two grow back.",
	},
	"bone_dragon": {
		"name": "Bone Dragon", "rarity": "epic", "role": "melee", "locked": true,
		"hp": 1100.0, "dmg": 65.0, "cooldown": 1.2, "range": 10.0, "speed": 85.0,
		"damage": "physical", "armor": "undead", "aoe": 30.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 16.0, "scale": 1.8, "flying": true,
		"desc": "A dragon that refused to stay dead.",
	},
	"juggernaut": {
		"name": "Juggernaut", "rarity": "epic", "role": "tank", "locked": true,
		"hp": 1800.0, "dmg": 70.0, "cooldown": 1.6, "range": 10.0, "speed": 45.0,
		"damage": "physical", "armor": "heavy", "aoe": 40.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 16.0, "scale": 1.8, "flying": false,
		"desc": "Nothing stops it. Nothing.",
	},
	"shadow_dragon": {
		"name": "Shadow Dragon", "rarity": "legendary", "role": "caster", "locked": true,
		"hp": 3000.0, "dmg": 85.0, "cooldown": 2.0, "range": 170.0, "speed": 75.0,
		"damage": "magic", "armor": "beast", "aoe": 75.0, "heal": 0.0, "regen": 0.0,
		"projectile": "magic", "radius": 22.0, "scale": 2.4, "flying": true,
		"desc": "Darkness given wings and hunger.",
	},
	"storm_dragon": {
		"name": "Storm Dragon", "rarity": "legendary", "role": "caster", "locked": true,
		"hp": 2800.0, "dmg": 80.0, "cooldown": 1.6, "range": 190.0, "speed": 85.0,
		"damage": "magic", "armor": "beast", "aoe": 65.0, "heal": 0.0, "regen": 0.0,
		"projectile": "magic", "radius": 22.0, "scale": 2.4, "flying": true,
		"desc": "Calls lightning down on the enemy lines.",
	},
	"seraph": {
		"name": "Seraph", "rarity": "legendary", "role": "healer", "locked": true,
		"hp": 2000.0, "dmg": 40.0, "cooldown": 1.2, "range": 180.0, "speed": 90.0,
		"damage": "magic", "armor": "light", "aoe": 0.0, "heal": 120.0, "regen": 0.0,
		"projectile": "magic", "radius": 18.0, "scale": 2.0, "flying": true,
		"desc": "Heals whole squads with radiant light.",
	},
	"grand_avatar": {
		"name": "Grand Avatar", "rarity": "legendary", "role": "tank", "locked": true,
		"hp": 4000.0, "dmg": 100.0, "cooldown": 1.8, "range": 12.0, "speed": 45.0,
		"damage": "magic", "armor": "heavy", "aoe": 60.0, "heal": 0.0, "regen": 0.0,
		"projectile": "none", "radius": 22.0, "scale": 2.4, "flying": false,
		"desc": "A god's will in physical form.",
	},
}

# Expedition regions: where specific units can be found.
# drops: unit id -> weight.
const REGIONS := {
	"warrens": {
		"name": "Goblin Warrens", "tile": "warrens", "cost_maps": 1, "min_rating": 0,
		"desc": "Damp tunnels crawling with greenskins.",
		"drops": {"goblin": 34, "kobold_slinger": 28, "rat_swarm": 18, "orc_warrior": 12, "ogre": 6, "hill_giant": 2},
	},
	"crypt": {
		"name": "Haunted Crypt", "tile": "crypt", "cost_maps": 1, "min_rating": 0,
		"desc": "The dead do not rest here.",
		"drops": {"skeleton": 38, "rat_swarm": 22, "gnoll_shaman": 18, "orc_sorcerer": 12, "lich": 4},
	},
	"forest": {
		"name": "Whispering Forest", "tile": "forest", "cost_maps": 1, "min_rating": 1000,
		"desc": "Elves, wolves and older things beneath the canopy.",
		"drops": {"elf_archer": 30, "dire_wolf": 30, "centaur": 14, "treant": 12, "griffon": 5, "phoenix": 1},
	},
	"deep": {
		"name": "Dwarven Deeps", "tile": "deep", "cost_maps": 2, "min_rating": 1050,
		"desc": "Forgotten halls under the mountain.",
		"drops": {"dwarf_berserker": 30, "kobold_slinger": 22, "naga_sharpshooter": 14, "ogre": 12, "hill_giant": 4, "titan": 1},
	},
	"peaks": {
		"name": "Dragon Peaks", "tile": "peaks", "cost_maps": 3, "min_rating": 1150,
		"desc": "Only the bold climb where dragons nest.",
		"drops": {"orc_sorcerer": 24, "centaur": 20, "griffon": 16, "hill_giant": 12, "lich": 10, "golden_dragon": 3, "phoenix": 2, "titan": 2},
	},
	# --- Locked by default (enable with the server's `unlock region` command) ---
	"badlands": {
		"name": "Badlands Camp", "tile": "badlands", "cost_maps": 1, "min_rating": 0, "locked": true,
		"desc": "A warband's camp in the scrublands: hounds, raiders and their bosses.",
		"drops": {"jackal": 30, "hobgoblin": 30, "gnoll_raider": 26, "goblin_archer": 26, "war_hound": 16, "orc_knight": 14, "orc_warlord": 7, "cyclops": 5},
	},
	"marsh": {
		"name": "Sunken Marsh", "tile": "marsh", "cost_maps": 1, "min_rating": 0, "locked": true,
		"desc": "Reeds, black water and things with too many teeth.",
		"drops": {"giant_frog": 34, "cave_bat": 22, "naga_warrior": 16, "merfolk_impaler": 16, "troll": 8, "hydra": 3},
	},
	"hive_tunnels": {
		"name": "Hive Tunnels", "tile": "hive_tunnels", "cost_maps": 1, "min_rating": 0, "locked": true,
		"desc": "Burrows dug by giant ants, now home to worse.",
		"drops": {"soldier_ant": 36, "kobold_brute": 30, "cave_bat": 18, "black_bear": 14, "troll_berserker": 7, "ettin": 6},
	},
	"elven_glade": {
		"name": "Elven Glade", "tile": "elven_glade", "cost_maps": 2, "min_rating": 1000, "locked": true,
		"desc": "A hidden grove guarded by the elven host.",
		"drops": {"elf_knight": 26, "elf_mage": 24, "hippogriff": 18, "tengu_warrior": 16, "sphinx": 4, "seraph": 1},
	},
	"bone_fields": {
		"name": "Bone Fields", "tile": "bone_fields", "cost_maps": 2, "min_rating": 1000, "locked": true,
		"desc": "An old battlefield where the fallen still march.",
		"drops": {"wight": 34, "minotaur": 12, "vampire_knight": 12, "death_knight": 10, "bone_dragon": 4},
	},
	"giants_steps": {
		"name": "Giant's Steps", "tile": "giants_steps", "cost_maps": 2, "min_rating": 1100, "locked": true,
		"desc": "Mountain terraces carved by giants.",
		"drops": {"cyclops": 22, "ettin": 22, "stone_giant": 10, "frost_giant": 9, "fire_giant": 9, "juggernaut": 6},
	},
	"dragons_hoard": {
		"name": "Dragon's Hoard", "tile": "dragons_hoard", "cost_maps": 3, "min_rating": 1150, "locked": true,
		"desc": "Treasure caves where the great wyrms sleep.",
		"drops": {"salamander_firebrand": 30, "manticore": 28, "ice_dragon": 8, "shadow_dragon": 3, "storm_dragon": 3},
	},
	"celestial_spire": {
		"name": "Celestial Spire", "tile": "celestial_spire", "cost_maps": 3, "min_rating": 1200, "locked": true,
		"desc": "A tower above the clouds, home to winged hosts.",
		"drops": {"tengu_warrior": 30, "hippogriff": 28, "sphinx": 10, "seraph": 3, "grand_avatar": 2},
	},
}

const FINDS_PER_EXPEDITION := 3   # units offered per expedition; the player keeps one
const CHOICE_SHARD_MULT := 2      # shards per pick are doubled since only one of three is kept

## Pity: an expedition is guaranteed to offer a unit of at least this rarity
## once this many expeditions in a row have gone without one.
## Legendary pity only fires in regions that have legendary units.
## Guaranteed pulls ("pity") are set in DropRates (the server can change them).

const ROWS := ["front", "middle", "back"]

const STARTER_UNITS := ["goblin", "kobold_slinger", "rat_swarm"]


## A region's drop table: weights after the server's drop multipliers
## (DropRates), without locked units or units whose rarity is switched off.
static func region_drops(region_id: String) -> Dictionary:
	var out := {}
	var drops: Dictionary = REGIONS[region_id]["drops"]
	for id in drops:
		if UnitLocks.is_locked(id):
			continue
		var w := DropRates.unit_weight(id, float(drops[id]))
		if w > 0.0:
			out[id] = w
	return out


static func unit_ids_sorted() -> Array:
	var ids: Array = UNITS.keys()
	ids.sort_custom(func(a, b):
		var ra: int = RARITIES[UNITS[a]["rarity"]]["order"]
		var rb: int = RARITIES[UNITS[b]["rarity"]]["order"]
		if ra != rb:
			return ra < rb
		return String(UNITS[a]["name"]) < String(UNITS[b]["name"]))
	return ids


static func rarity_color(rarity: String) -> Color:
	return Color.html(RARITIES[rarity]["color"])


static func unit_texture(id: String) -> Texture2D:
	return load("res://assets/sprites/units/%s.png" % id)


static func tile_texture(tile: String) -> Texture2D:
	return load("res://assets/sprites/tiles/%s.png" % tile)


static func regions_for_unit(id: String) -> Array:
	var out: Array = []
	for rid in REGIONS:
		if REGIONS[rid]["drops"].has(id):
			out.append(REGIONS[rid]["name"])
	return out


static func default_row_for(id: String) -> String:
	match String(UNITS[id]["role"]):
		"tank", "melee":
			return "front"
		"caster", "healer":
			return "back"
		_:
			return "middle"
