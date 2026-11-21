class_name GameData
extends RefCounted
## Static game definitions: units, rarities, regions and damage tables.
## Everything here is plain data so it can be tweaked without touching logic.

const ARMY_UNIT_CAP := 1000
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
}

const FINDS_PER_EXPEDITION := 3

const ROWS := ["front", "middle", "back"]

const STARTER_UNITS := ["goblin", "kobold_slinger", "rat_swarm"]


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
