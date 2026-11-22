class_name Challenges
extends RefCounted
## Preset battles (the Challenges tab): hand-made enemy armies on chosen
## battlefields, unlocked in order, each with a fixed reward for the first win.
##
## Enemy squads use explicit unit counts, and bosses are single units with
## battle modifiers ("mods", see Army.unit_stats) and a "title" shown in the UI.
## Rewards: gold, scouting maps, a trinket (sold for gold if already owned)
## and/or a unit (shards if already owned).
## "recommended" is the army power (as shown in the game) that wins the fight
## most of the time, measured by simulating a standard army against it.

## Shards given instead of a reward unit you already own.
const DUPLICATE_UNIT_SHARDS := 15

const CHAPTERS := [
	{"name": "Border Skirmishes", "desc": "Trouble on the frontier. Good practice for a young legion."},
	{"name": "The Wild Frontier", "desc": "Beasts, fortresses and the dead that won't stay buried."},
	{"name": "Dragon Lands", "desc": "Giants, titans and the oldest wyrm of all."},
]

const LIST := [
	# --- chapter 1 ---------------------------------------------------------------
	{"id": "rat_problem", "chapter": 0, "name": "Rat Problem", "map": "open_arena", "recommended": 120,
		"desc": "Giant rats are eating the grain stores. Clear them out before the village starves.",
		"enemy": [{"unit": "rat_swarm", "level": 1, "count": 45, "row": "front"}],
		"reward": {"gold": 150, "maps": 1}},
	{"id": "goblin_raid", "chapter": 0, "name": "Goblin Raiders", "map": "goblin_warrens", "recommended": 160,
		"desc": "A goblin warband raids the farms, slingers pelting anyone who gives chase.",
		"enemy": [{"unit": "goblin", "level": 2, "count": 40, "row": "front"},
			{"unit": "kobold_slinger", "level": 1, "count": 25, "row": "middle"}],
		"reward": {"gold": 250, "trinket": "copper_band"}},
	{"id": "hold_bridge", "chapter": 0, "name": "Hold the Bridge", "map": "narrow_bridge", "recommended": 300,
		"desc": "Skeletons march on the old bridge. The river leaves only one way across, for both sides.",
		"enemy": [{"unit": "skeleton", "level": 4, "count": 60, "row": "front"},
			{"unit": "kobold_slinger", "level": 3, "count": 30, "row": "back"}],
		"reward": {"gold": 350, "maps": 2}},
	{"id": "gruk", "chapter": 0, "name": "Gruk the Unbreakable", "map": "mossy_ruins", "recommended": 360,
		"desc": "An ogre warlord who has never lost a fight, guarded by his goblin rabble.",
		"enemy": [{"unit": "ogre", "level": 5, "count": 1, "row": "front", "title": "Gruk the Unbreakable",
				"mods": {"hp_mult": 30.0, "dmg_mult": 3.0, "aoe_add": 30.0}},
			{"unit": "goblin", "level": 4, "count": 40, "row": "front"}],
		"reward": {"gold": 500, "unit": "ogre"}},
	# --- chapter 2 ---------------------------------------------------------------
	{"id": "wolf_pack", "chapter": 1, "name": "The Wolf Pack", "map": "whispering_forest", "recommended": 380,
		"desc": "Dire wolves hunt in the forest with orc riders close behind.",
		"enemy": [{"unit": "dire_wolf", "level": 8, "count": 45, "row": "front"},
			{"unit": "orc_warrior", "level": 7, "count": 25, "row": "middle"}],
		"reward": {"gold": 600, "maps": 2, "trinket": "striped_boots"}},
	{"id": "fortress", "chapter": 1, "name": "Storm the Fortress", "map": "fortress_gate", "recommended": 780,
		"desc": "Break through the gate while elven archers rain arrows from behind the walls.",
		"enemy": [{"unit": "orc_warrior", "level": 9, "count": 35, "row": "front"},
			{"unit": "gnoll_shaman", "level": 8, "count": 25, "row": "middle"},
			{"unit": "elf_archer", "level": 9, "count": 55, "row": "back"}],
		"reward": {"gold": 800, "trinket": "kite_shield"}},
	{"id": "necromancer", "chapter": 1, "name": "The Necromancer", "map": "haunted_crypt", "recommended": 800,
		"desc": "Vorlath the Undying raises the crypt's dead. Destroy him and his army crumbles.",
		"enemy": [{"unit": "lich", "level": 10, "count": 1, "row": "back", "title": "Vorlath the Undying",
				"mods": {"hp_mult": 30.0, "dmg_mult": 2.5, "regen_pct": 0.01}},
			{"unit": "skeleton", "level": 10, "count": 110, "row": "front"}],
		"reward": {"gold": 1000, "unit": "lich"}},
	{"id": "grove", "chapter": 1, "name": "Wrath of the Grove", "map": "sunken_swamp", "recommended": 1220,
		"desc": "The forest itself marches to war: treants, centaurs and elven archers.",
		"enemy": [{"unit": "treant", "level": 12, "count": 18, "row": "front"},
			{"unit": "centaur", "level": 12, "count": 18, "row": "middle"},
			{"unit": "elf_archer", "level": 12, "count": 50, "row": "back"}],
		"reward": {"gold": 1200, "maps": 3}},
	# --- chapter 3 ---------------------------------------------------------------
	{"id": "giants_pass", "chapter": 2, "name": "The Giants' Pass", "map": "glacier_pass", "recommended": 1330,
		"desc": "Hill giants and dwarven berserkers hold the only pass through the ice.",
		"enemy": [{"unit": "hill_giant", "level": 14, "count": 14, "row": "front"},
			{"unit": "dwarf_berserker", "level": 14, "count": 60, "row": "front"}],
		"reward": {"gold": 1600, "trinket": "tower_shield"}},
	{"id": "titan", "chapter": 2, "name": "The Titan Awakens", "map": "dragon_peaks", "recommended": 1900,
		"desc": "The Colossus walks again, with griffons overhead and naga sharpshooters at its feet.",
		"enemy": [{"unit": "titan", "level": 12, "count": 1, "row": "front", "title": "The Colossus",
				"mods": {"hp_mult": 50.0, "dmg_mult": 4.0, "thorns": 0.2}},
			{"unit": "griffon", "level": 15, "count": 18, "row": "middle"},
			{"unit": "naga_sharpshooter", "level": 15, "count": 60, "row": "back"}],
		"reward": {"gold": 2500, "maps": 3, "trinket": "dragonscale_cloak"}},
	{"id": "phoenix", "chapter": 2, "name": "Rise of the Phoenix", "map": "infernal_gate", "recommended": 1950,
		"desc": "Ashwing the Phoenix burns at the gate, orc sorcerers chanting in its fire.",
		"enemy": [{"unit": "phoenix", "level": 10, "count": 1, "row": "middle", "title": "Ashwing",
				"mods": {"hp_mult": 16.0, "dmg_mult": 2.2, "regen_pct": 0.005}},
			{"unit": "orc_sorcerer", "level": 10, "count": 30, "row": "back"},
			{"unit": "orc_warrior", "level": 10, "count": 30, "row": "front"}],
		"reward": {"gold": 2000, "unit": "phoenix"}},
	{"id": "golden_wyrm", "chapter": 2, "name": "The Golden Wyrm", "map": "dragon_lair", "recommended": 3400,
		"desc": "Aurathrax, oldest of the golden dragons, guards the greatest hoard in the world.",
		"enemy": [{"unit": "golden_dragon", "level": 14, "count": 1, "row": "back", "title": "Aurathrax",
				"mods": {"hp_mult": 150.0, "dmg_mult": 6.0, "aoe_add": 40.0}},
			{"unit": "lich", "level": 18, "count": 12, "row": "back"},
			{"unit": "hill_giant", "level": 20, "count": 20, "row": "front"},
			{"unit": "griffon", "level": 18, "count": 18, "row": "middle"}],
		"reward": {"gold": 4000, "unit": "golden_dragon", "trinket": "dragon_kings_crest"}},
]


static func get_challenge(id: String) -> Dictionary:
	for c in LIST:
		if c["id"] == id:
			return c
	return {}


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i
	return -1


## The enemy army as battle squads (copies, so callers can't change the data).
static func enemy_squads(id: String) -> Array:
	var out: Array = []
	for sq in get_challenge(id).get("enemy", []):
		var s: Dictionary = (sq as Dictionary).duplicate(true)
		s["tier"] = 0
		s.erase("title")
		out.append(Difficulty.scale_challenge_squad(s))
	return out


## The recommended power shown in the game, scaled by the server's challenge
## difficulty.
static func recommended(id: String) -> int:
	return roundi(float(get_challenge(id).get("recommended", 0)) * Difficulty.challenge_mult)


static func enemy_power(id: String) -> float:
	return Army.army_power(enemy_squads(id))


## "Gold 500 · Ogre Brute · 2 maps" style summary of a reward.
static func reward_text(reward: Dictionary) -> String:
	var parts: Array = []
	if int(reward.get("gold", 0)) > 0:
		parts.append("%d gold" % int(reward["gold"]))
	if int(reward.get("maps", 0)) > 0:
		parts.append("%d scouting map%s" % [int(reward["maps"]), "" if int(reward["maps"]) == 1 else "s"])
	if Trinkets.exists(str(reward.get("trinket", ""))):
		parts.append(str(Trinkets.ALL[reward["trinket"]]["name"]) + " (trinket)")
	if GameData.UNITS.has(str(reward.get("unit", ""))):
		parts.append(str(GameData.UNITS[reward["unit"]]["name"]) + " (unit)")
	return " · ".join(PackedStringArray(parts))
