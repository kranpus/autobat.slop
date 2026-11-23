class_name Champion
extends RefCounted
## Patch 0.9.9: champions, the leaders of your army.
##
## Unlocked at commander level 6 (Progression.UNLOCKS). One champion per
## commander, customised in the Champion tab:
## - Appearance: race, hair, beard and halo (paper-doll layers from the Dungeon
##   Crawl Stone Soup tiles), plus whatever equipment it wears.
## - Stats: points in Might, Vitality, Haste, Swiftness and Focus.
## - Abilities: one equipped at a time, most of them army-wide auras.
## - Equipment: champion-only gear in 7 slots; the weapon sets how it fights
##   (melee, ranged or spells).
## All of it is unlocked at the Altar: each roll costs a Sigil and gives a stat
## point, a piece of equipment, an appearance part or an ability, at random.
##
## In battle the champion is one unit (a squad with "count": 1 and a
## "champion" key holding its compact data, see to_squad()). Its unit type is
## registered at run time under an id made from that data (register()).

const SPRITE_DIR := "res://assets/sprites/champion/"
const MAX_STAT := 30
const START_SIGILS := 5
const SIGIL_GOLD := 1500
const MAX_NAME := 20

## Stat points: what one point gives.
const STATS := {
	"might": {"name": "Might", "text": "+4% damage per point"},
	"vitality": {"name": "Vitality", "text": "+5% health per point"},
	"haste": {"name": "Haste", "text": "attacks 2% faster per point"},
	"swiftness": {"name": "Swiftness", "text": "+3% movement speed per point"},
	"focus": {"name": "Focus", "text": "+6 range per point (bows and staves), +2% damage with melee weapons"},
}
const STAT_ORDER := ["might", "vitality", "haste", "swiftness", "focus"]

## How it fights, by weapon class.
const CLASSES := {
	"melee": {"role": "melee", "hp": 520.0, "dmg": 42.0, "cooldown": 1.0, "range": 10.0, "speed": 78.0,
		"damage": "physical", "armor": "heavy", "projectile": "none"},
	"ranged": {"role": "ranged", "hp": 320.0, "dmg": 34.0, "cooldown": 1.1, "range": 230.0, "speed": 72.0,
		"damage": "physical", "armor": "light", "projectile": "arrow"},
	"caster": {"role": "caster", "hp": 300.0, "dmg": 46.0, "cooldown": 1.5, "range": 210.0, "speed": 66.0,
		"damage": "magic", "armor": "light", "projectile": "magic"},
}

## Champion abilities: each is a battle ability the simulator already knows
## ("ab", "value"), on a champion with a much wider reach (see BattleSim).
## "army": what it adds to the Strength of the rest of the army.
const ABILITIES := {
	"rally": {"name": "Rallying Cry", "ab": "inspire", "value": 0.2, "army": 0.06, "text": "Allies around the champion deal 20% more damage."},
	"bulwark": {"name": "Bulwark", "ab": "aegis", "value": 0.0, "army": 0.06, "text": "Allies around the champion take 20% less damage."},
	"warsong": {"name": "War Song", "ab": "song", "value": 0.25, "army": 0.06, "text": "Allies around the champion attack 25% faster."},
	"dread": {"name": "Dreadful Presence", "ab": "dread", "value": 0.0, "army": 0.06, "text": "Enemies around the champion deal 35% less damage."},
	"winter": {"name": "Winter's Breath", "ab": "frost_aura", "value": 0.0, "army": 0.05, "text": "Enemies around the champion are chilled: half speed."},
	"meteor": {"name": "Meteor", "ab": "thunderstrike", "value": 4.0, "army": 0.0, "text": "Every 4s a meteor strikes an enemy anywhere on the field."},
	"quake": {"name": "Earthshaker", "ab": "avalanche", "value": 7.0, "army": 0.0, "text": "Every 7s the ground buries the enemy ranks it faces: up to 8 enemies hit and chilled."},
	"resurgence": {"name": "Resurgence", "ab": "rebirth", "value": 1.0, "army": 0.0, "text": "The first time the champion falls, it rises again at full health."},
	"lifedrinker": {"name": "Lifedrinker", "ab": "devour", "value": 0.5, "army": 0.0, "text": "Heals for half the damage it deals."},
	"storm": {"name": "Storm Call", "ab": "chain", "value": 4.0, "army": 0.0, "text": "Its attacks arc to 4 more enemies."},
}
const START_ABILITY := "rally"

const SLOTS := ["weapon", "offhand", "armor", "helm", "boots", "gloves", "cloak"]
const SLOT_NAMES := {"weapon": "Weapon", "offhand": "Off-hand", "armor": "Armour", "helm": "Helm", "boots": "Boots", "gloves": "Gloves", "cloak": "Cloak"}
## Paper-doll layer of each slot.
const SLOT_LAYER := {"weapon": "hand_right", "offhand": "hand_left", "armor": "body", "helm": "head", "boots": "boots", "gloves": "gloves", "cloak": "cloak"}

## Champion-only equipment. "class" (weapons): how the champion fights.
const ITEMS := {
	# Weapons: melee
	"short_sword": {"name": "Short Sword", "slot": "weapon", "class": "melee", "rarity": "common", "sprite": "short_sword", "mods": {"dmg_mult": 1.05}},
	"hand_axe": {"name": "Hand Axe", "slot": "weapon", "class": "melee", "rarity": "common", "sprite": "hand_axe_new", "mods": {"dmg_mult": 1.08, "cooldown_mult": 1.03}},
	"long_sword": {"name": "Long Sword", "slot": "weapon", "class": "melee", "rarity": "uncommon", "sprite": "long_sword", "mods": {"dmg_mult": 1.1, "cooldown_mult": 0.97}},
	"battleaxe": {"name": "Battleaxe", "slot": "weapon", "class": "melee", "rarity": "uncommon", "sprite": "battleaxe", "mods": {"dmg_mult": 1.18, "cooldown_mult": 1.05}},
	"katana": {"name": "Katana", "slot": "weapon", "class": "melee", "rarity": "rare", "sprite": "katana", "mods": {"dmg_mult": 1.12, "cooldown_mult": 0.9}},
	"greatsword": {"name": "Greatsword", "slot": "weapon", "class": "melee", "rarity": "rare", "sprite": "great_sword", "mods": {"dmg_mult": 1.24}},
	"twinblade": {"name": "Twinblade", "slot": "weapon", "class": "melee", "rarity": "epic", "sprite": "double_sword_new", "mods": {"dmg_mult": 1.2, "cooldown_mult": 0.88}},
	"blessed_blade": {"name": "Blessed Blade", "slot": "weapon", "class": "melee", "rarity": "epic", "sprite": "blessed_blade", "mods": {"dmg_mult": 1.25, "regen_pct": 0.01}},
	"black_sword": {"name": "The Black Sword", "slot": "weapon", "class": "melee", "rarity": "legendary", "sprite": "black_sword", "mods": {"dmg_mult": 1.35, "lifesteal": 0.15}},
	"eveningstar": {"name": "Eveningstar", "slot": "weapon", "class": "melee", "rarity": "legendary", "sprite": "eveningstar_new", "mods": {"dmg_mult": 1.3, "cooldown_mult": 0.85}},
	# Weapons: ranged
	"hunting_bow": {"name": "Hunting Bow", "slot": "weapon", "class": "ranged", "rarity": "common", "sprite": "bow", "mods": {"dmg_mult": 1.05}},
	"crossbow": {"name": "Crossbow", "slot": "weapon", "class": "ranged", "rarity": "uncommon", "sprite": "crossbow", "mods": {"dmg_mult": 1.12, "range_add": 10.0}},
	"elven_bow": {"name": "Elven Bow", "slot": "weapon", "class": "ranged", "rarity": "rare", "sprite": "bow_blue", "mods": {"cooldown_mult": 0.88, "range_add": 20.0}},
	"great_bow": {"name": "Great Bow", "slot": "weapon", "class": "ranged", "rarity": "epic", "sprite": "great_bow", "mods": {"dmg_mult": 1.22, "range_add": 30.0}},
	"greenwood_bow": {"name": "Bow of the Greenwood", "slot": "weapon", "class": "ranged", "rarity": "legendary", "sprite": "legolas", "mods": {"dmg_mult": 1.3, "cooldown_mult": 0.85, "range_add": 40.0}},
	# Weapons: spells
	"quarterstaff": {"name": "Quarterstaff", "slot": "weapon", "class": "caster", "rarity": "common", "sprite": "quarterstaff", "mods": {"dmg_mult": 1.05}},
	"oak_rod": {"name": "Oak Rod", "slot": "weapon", "class": "caster", "rarity": "uncommon", "sprite": "rod_brown_new", "mods": {"dmg_mult": 1.12}},
	"sapphire_rod": {"name": "Sapphire Rod", "slot": "weapon", "class": "caster", "rarity": "rare", "sprite": "rod_blue_new", "mods": {"dmg_mult": 1.15, "range_add": 20.0}},
	"great_staff": {"name": "Great Staff", "slot": "weapon", "class": "caster", "rarity": "epic", "sprite": "great_staff", "mods": {"dmg_mult": 1.26, "cooldown_mult": 0.95}},
	"grey_staff": {"name": "Staff of the Grey Wanderer", "slot": "weapon", "class": "caster", "rarity": "legendary", "sprite": "gandalf", "mods": {"dmg_mult": 1.35, "cooldown_mult": 0.9, "range_add": 30.0}},
	# Off-hand
	"buckler": {"name": "Buckler", "slot": "offhand", "rarity": "common", "sprite": "buckler_green", "mods": {"hp_mult": 1.08}},
	"round_shield": {"name": "Round Shield", "slot": "offhand", "rarity": "uncommon", "sprite": "shield_round_1", "mods": {"hp_mult": 1.12, "thorns": 0.05}},
	"kite_shield": {"name": "Kite Shield", "slot": "offhand", "rarity": "rare", "sprite": "shield_kite_1", "mods": {"hp_mult": 1.18}},
	"knights_shield": {"name": "Knight's Shield", "slot": "offhand", "rarity": "epic", "sprite": "shield_knight_blue", "mods": {"hp_mult": 1.25, "thorns": 0.1}},
	"holy_shield": {"name": "Shield of the Dawn", "slot": "offhand", "rarity": "legendary", "sprite": "shield_holy", "mods": {"hp_mult": 1.35, "regen_pct": 0.01}},
	# Armour
	"leather": {"name": "Leather Armour", "slot": "armor", "rarity": "common", "sprite": "leather_2", "mods": {"hp_mult": 1.1}},
	"mage_robe": {"name": "Mage Robe", "slot": "armor", "rarity": "uncommon", "sprite": "robe_blue", "mods": {"hp_mult": 1.05, "dmg_mult": 1.08}},
	"chainmail": {"name": "Chainmail", "slot": "armor", "rarity": "uncommon", "sprite": "chainmail", "mods": {"hp_mult": 1.16}},
	"scalemail": {"name": "Scale Mail", "slot": "armor", "rarity": "rare", "sprite": "scalemail", "mods": {"hp_mult": 1.22}},
	"plate": {"name": "Plate Armour", "slot": "armor", "rarity": "epic", "sprite": "plate", "mods": {"hp_mult": 1.32, "speed_mult": 0.95}},
	"robe_of_night": {"name": "Robe of Night", "slot": "armor", "rarity": "epic", "sprite": "robe_of_night", "mods": {"hp_mult": 1.1, "dmg_mult": 1.15, "cooldown_mult": 0.95}},
	"gold_dragon_armour": {"name": "Gold Dragon Armour", "slot": "armor", "rarity": "legendary", "sprite": "dragon_armor_gold_new", "mods": {"hp_mult": 1.45, "thorns": 0.1}},
	# Helms
	"leather_cap": {"name": "Leather Cap", "slot": "helm", "rarity": "common", "sprite": "cap_black_1", "mods": {"hp_mult": 1.04}},
	"iron_helm": {"name": "Iron Helm", "slot": "helm", "rarity": "uncommon", "sprite": "iron_1", "mods": {"hp_mult": 1.08}},
	"plumed_helm": {"name": "Plumed Helm", "slot": "helm", "rarity": "rare", "sprite": "helm_plume", "mods": {"hp_mult": 1.1, "dmg_mult": 1.05}},
	"wizard_hat": {"name": "Wizard's Hat", "slot": "helm", "rarity": "rare", "sprite": "wizard_blue", "mods": {"dmg_mult": 1.1}},
	"gold_helm": {"name": "Golden Helm", "slot": "helm", "rarity": "epic", "sprite": "full_gold", "mods": {"hp_mult": 1.15, "dmg_mult": 1.05}},
	"crown": {"name": "Crown of Kings", "slot": "helm", "rarity": "legendary", "sprite": "crown_gold_1", "mods": {"hp_mult": 1.15, "dmg_mult": 1.15}},
	# Boots
	"worn_boots": {"name": "Worn Boots", "slot": "boots", "rarity": "common", "sprite": "short_brown", "mods": {"speed_mult": 1.05}},
	"marching_boots": {"name": "Marching Boots", "slot": "boots", "rarity": "uncommon", "sprite": "middle_gray", "mods": {"speed_mult": 1.1, "hp_mult": 1.03}},
	"riding_boots": {"name": "Riding Boots", "slot": "boots", "rarity": "rare", "sprite": "long_red", "mods": {"speed_mult": 1.15}},
	"windwalkers": {"name": "Windwalkers", "slot": "boots", "rarity": "epic", "sprite": "blue_gold", "mods": {"speed_mult": 1.2, "cooldown_mult": 0.95}},
	"sunstriders": {"name": "Sunstriders", "slot": "boots", "rarity": "legendary", "sprite": "middle_gold", "mods": {"speed_mult": 1.25, "cooldown_mult": 0.9, "hp_mult": 1.05}},
	# Gloves
	"work_gloves": {"name": "Work Gloves", "slot": "gloves", "rarity": "common", "sprite": "glove_brown", "mods": {"cooldown_mult": 0.97}},
	"iron_gloves": {"name": "Iron Gloves", "slot": "gloves", "rarity": "uncommon", "sprite": "glove_gray", "mods": {"cooldown_mult": 0.95}},
	"blue_gauntlets": {"name": "Blue Gauntlets", "slot": "gloves", "rarity": "rare", "sprite": "gauntlet_blue", "mods": {"cooldown_mult": 0.93, "hp_mult": 1.05}},
	"gilded_gloves": {"name": "Gilded Gloves", "slot": "gloves", "rarity": "epic", "sprite": "glove_gold", "mods": {"cooldown_mult": 0.9, "dmg_mult": 1.05}},
	"talons": {"name": "Dragon Talons", "slot": "gloves", "rarity": "legendary", "sprite": "claws", "mods": {"cooldown_mult": 0.85, "lifesteal": 0.08}},
	# Cloaks
	"travel_cloak": {"name": "Travelling Cloak", "slot": "cloak", "rarity": "common", "sprite": "brown", "mods": {"hp_mult": 1.04}},
	"ranger_cloak": {"name": "Ranger's Cloak", "slot": "cloak", "rarity": "uncommon", "sprite": "green", "mods": {"hp_mult": 1.06, "regen_pct": 0.004}},
	"sky_cloak": {"name": "Sky Cloak", "slot": "cloak", "rarity": "rare", "sprite": "blue", "mods": {"hp_mult": 1.08, "speed_mult": 1.05}},
	"war_cloak": {"name": "Crimson War Cloak", "slot": "cloak", "rarity": "epic", "sprite": "red", "mods": {"hp_mult": 1.08, "dmg_mult": 1.08}},
	"dragonskin_cloak": {"name": "Dragonskin Cloak", "slot": "cloak", "rarity": "legendary", "sprite": "dragonskin", "mods": {"hp_mult": 1.2, "regen_pct": 0.01}},
}
const STARTER_ITEMS := ["short_sword", "leather"]

## Appearance parts. "": none.
const LOOKS := {
	"race": ["human_male", "human_female", "elf_male", "elf_female", "dwarf_male", "dwarf_female", "orc_male", "orc_female",
		"deep_elf_male", "deep_elf_female", "halfling_male", "minotaur_male", "troll_male", "draconian_gold_male",
		"draconian_red_female", "demonspawn_red_male", "vampire_female", "merfolk_male", "spriggan_male", "gargoyle_male",
		"demigod_male", "mummy_male"],
	"hair": ["short_black", "short_red", "short_yellow", "short_white", "long_black", "long_red", "long_white", "long_yellow",
		"fem_black", "fem_red", "pigtails_brown", "knot_red", "elf_white"],
	"beard": ["short_black", "short_red", "short_yellow", "long_black", "long_red", "long_white"],
	"halo": ["halo_player"],
}
const LOOK_NAMES := {"race": "Race", "hair": "Hair", "beard": "Beard", "halo": "Halo"}
const STARTER_LOOKS := {"race": ["human_male", "human_female", "elf_male"], "hair": ["short_black", "long_yellow"], "beard": [], "halo": []}
## Draw order of the paper-doll layers (back to front).
const LAYER_ORDER := ["halo", "cloak", "race", "boots", "armor", "gloves", "beard", "hair", "helm", "weapon", "offhand"]
const LOOK_LAYER := {"race": "base", "hair": "hair", "beard": "beard", "halo": "halo"}

## The Altar: what a roll gives (weights), and item rarity weights.
const ROLL_ODDS := {"stat": 45, "item": 30, "look": 15, "ability": 10}
const ITEM_RARITY_ODDS := {"common": 40, "uncommon": 30, "rare": 17, "epic": 9, "legendary": 4}


# --- the profile's champion --------------------------------------------------------------

## A new champion: the starter kit.
static func new_champion(name: String = "Champion") -> Dictionary:
	var looks := {}
	for k in STARTER_LOOKS:
		looks[k] = STARTER_LOOKS[k].duplicate()
	return {
		"name": name, "stats": {"might": 0, "vitality": 0, "haste": 0, "swiftness": 0, "focus": 0},
		"items": STARTER_ITEMS.duplicate(), "equipped": {"weapon": "short_sword", "armor": "leather"},
		"abilities": [START_ABILITY], "ability": START_ABILITY,
		"looks": looks, "look": {"race": "human_male", "hair": "short_black", "beard": "", "halo": ""},
		"row": "", "rolls": 0, "last_roll": {},
	}


## Clean up a champion from untrusted input (a save, the server, an army code).
static func sanitize(c) -> Dictionary:
	var out := new_champion()
	if typeof(c) != TYPE_DICTIONARY:
		return out
	out["name"] = clean_name(str(c.get("name", "Champion")))
	var st = c.get("stats", {})
	for k in STATS:
		out["stats"][k] = clampi(int(st.get(k, 0)) if typeof(st) == TYPE_DICTIONARY else 0, 0, MAX_STAT)
	var items: Array = []
	for id in c.get("items", []) if typeof(c.get("items")) == TYPE_ARRAY else []:
		if ITEMS.has(str(id)) and not items.has(str(id)):
			items.append(str(id))
	for s in STARTER_ITEMS:
		if not items.has(s):
			items.append(s)
	out["items"] = items
	var eq := {}
	var raw_eq = c.get("equipped", {})
	if typeof(raw_eq) == TYPE_DICTIONARY:
		for slot in SLOTS:
			var id := str(raw_eq.get(slot, ""))
			if ITEMS.has(id) and ITEMS[id]["slot"] == slot and items.has(id):
				eq[slot] = id
	out["equipped"] = eq
	var abilities: Array = []
	for a in c.get("abilities", []) if typeof(c.get("abilities")) == TYPE_ARRAY else []:
		if ABILITIES.has(str(a)) and not abilities.has(str(a)):
			abilities.append(str(a))
	if not abilities.has(START_ABILITY):
		abilities.push_front(START_ABILITY)
	out["abilities"] = abilities
	out["ability"] = str(c.get("ability", START_ABILITY)) if abilities.has(str(c.get("ability", ""))) else START_ABILITY
	var raw_looks = c.get("looks", {})
	for part in LOOKS:
		var owned: Array = STARTER_LOOKS[part].duplicate()
		if typeof(raw_looks) == TYPE_DICTIONARY and typeof(raw_looks.get(part)) == TYPE_ARRAY:
			for v in raw_looks[part]:
				if LOOKS[part].has(str(v)) and not owned.has(str(v)):
					owned.append(str(v))
		out["looks"][part] = owned
	var raw_look = c.get("look", {})
	for part in LOOKS:
		var v := str(raw_look.get(part, "")) if typeof(raw_look) == TYPE_DICTIONARY else ""
		if v == "" and part != "race":
			out["look"][part] = ""
		elif (out["looks"][part] as Array).has(v):
			out["look"][part] = v
	out["row"] = str(c.get("row", "")) if str(c.get("row", "")) in GameData.ROWS else ""
	out["rolls"] = maxi(0, int(c.get("rolls", 0)))
	out["last_roll"] = c.get("last_roll", {}) if typeof(c.get("last_roll")) == TYPE_DICTIONARY else {}
	return out


static func clean_name(n: String) -> String:
	var s := n.strip_edges().left(MAX_NAME)
	return s if s != "" else "Champion"


static func weapon_class(c: Dictionary) -> String:
	var w := str(c.get("equipped", {}).get("weapon", ""))
	return str(ITEMS[w]["class"]) if ITEMS.has(w) else "melee"


## The row it fights in: its own choice, or by weapon (melee front, others back).
static func row_of(c: Dictionary) -> String:
	var r := str(c.get("row", ""))
	if r in GameData.ROWS:
		return r
	return "front" if weapon_class(c) == "melee" else "back"


## Stat level of a champion (Army.unit_stats scale) for a commander level.
static func stat_level(commander_level: int) -> int:
	return clampi(10 + commander_level, 11, 40)


## Modifiers from stat points and equipment (the Army.unit_stats mods format).
static func mods(c: Dictionary) -> Dictionary:
	var st: Dictionary = c.get("stats", {})
	var cls := weapon_class(c)
	var m := {
		"dmg_mult": (1.0 + 0.04 * int(st.get("might", 0))) * (1.0 + (0.02 * int(st.get("focus", 0)) if cls == "melee" else 0.0)),
		"hp_mult": 1.0 + 0.05 * int(st.get("vitality", 0)),
		"cooldown_mult": pow(0.98, int(st.get("haste", 0))),
		"speed_mult": 1.0 + 0.03 * int(st.get("swiftness", 0)),
		"range_add": 6.0 * int(st.get("focus", 0)) if cls != "melee" else 0.0,
		"lifesteal": 0.0, "thorns": 0.0, "regen_pct": 0.0,
	}
	for slot in c.get("equipped", {}):
		var id := str(c["equipped"][slot])
		if not ITEMS.has(id):
			continue
		for k in ITEMS[id]["mods"]:
			var v = ITEMS[id]["mods"][k]
			if k.ends_with("_mult"):
				m[k] = float(m.get(k, 1.0)) * float(v)
			else:
				m[k] = float(m.get(k, 0.0)) + float(v)
	return m


# --- in battle -----------------------------------------------------------------------------

## What a squad needs to carry a champion into battle (also what army codes
## store): no unlock lists, just how it looks and fights.
static func battle_data(c: Dictionary, commander_level: int) -> Dictionary:
	return {"name": c.get("name", "Champion"), "level": stat_level(commander_level), "stats": c.get("stats", {}).duplicate(),
		"equipped": c.get("equipped", {}).duplicate(), "ability": c.get("ability", START_ABILITY),
		"look": c.get("look", {}).duplicate(), "row": row_of(c)}


## Clean battle data from untrusted input (army codes, saved ranked armies).
static func sanitize_battle(d) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	var out := {"name": clean_name(str(d.get("name", "Champion"))), "level": clampi(int(d.get("level", 11)), 11, 40),
		"stats": {}, "equipped": {}, "ability": START_ABILITY, "look": {}, "row": "front"}
	for k in STATS:
		out["stats"][k] = clampi(int(d.get("stats", {}).get(k, 0)) if typeof(d.get("stats")) == TYPE_DICTIONARY else 0, 0, MAX_STAT)
	if typeof(d.get("equipped")) == TYPE_DICTIONARY:
		for slot in SLOTS:
			var id := str(d["equipped"].get(slot, ""))
			if ITEMS.has(id) and ITEMS[id]["slot"] == slot:
				out["equipped"][slot] = id
	if ABILITIES.has(str(d.get("ability", ""))):
		out["ability"] = str(d["ability"])
	for part in LOOKS:
		var v := str(d.get("look", {}).get(part, "")) if typeof(d.get("look")) == TYPE_DICTIONARY else ""
		out["look"][part] = v if LOOKS[part].has(v) else ("human_male" if part == "race" else "")
	out["row"] = str(d.get("row", "front")) if str(d.get("row", "")) in GameData.ROWS else "front"
	return out


## The battle squad for a champion's battle data.
static func to_squad(bd: Dictionary) -> Dictionary:
	return {"unit": register(bd), "level": int(bd["level"]), "count": 1, "row": str(bd["row"]),
		"mods": mods(bd), "champion": bd}


static var _registry := {}


## The unit definition of a champion, registered under an id made from its
## battle data (the same champion always gets the same id). Call on the
## main thread (squad building and BattleSim.setup do).
static func register(bd: Dictionary) -> String:
	var id := "champion_%d" % hash(JSON.stringify(bd))
	if not _registry.has(id):
		var cls := weapon_class(bd)
		var base: Dictionary = CLASSES[cls]
		var ab: Dictionary = ABILITIES.get(str(bd.get("ability", START_ABILITY)), ABILITIES[START_ABILITY])
		_registry[id] = {
			"name": str(bd.get("name", "Champion")), "rarity": "legendary", "role": base["role"],
			"hp": base["hp"], "dmg": base["dmg"], "cooldown": base["cooldown"], "range": base["range"], "speed": base["speed"],
			"damage": base["damage"], "armor": base["armor"], "aoe": 0.0, "heal": 0.0, "regen": 0.0,
			"projectile": base["projectile"], "radius": 13.0, "scale": 1.9, "flying": false,
			"desc": "%s, champion of the army." % bd.get("name", "Champion"),
			"ability": {"id": ab["ab"], "value": ab["value"]}, "champion": true, "battle_data": bd,
		}
	return id


static func unit_def(id: String) -> Dictionary:
	return _registry.get(id, {})


static func is_champion(unit_id: String) -> bool:
	return unit_id.begins_with("champion_")


## Strength the champion adds to the rest of its army (its ability's reach),
## on top of its own unit power.
static func army_share(bd: Dictionary) -> float:
	return float(ABILITIES.get(str(bd.get("ability", "")), {}).get("army", 0.0))


# --- training bands ---------------------------------------------------------------------------

## A random champion for a training band at a rating (none below 1000).
static func for_rating(rating: int, rng: RandomNumberGenerator) -> Dictionary:
	if rating < 1000:
		return {}
	var c := new_champion(["Sir Hadrik", "Vex the Cruel", "Lady Ombra", "Thane Ruk", "The Iron Saint", "Mirelle", "Grimbold", "Kaskar"][rng.randi_range(0, 7)])
	var points := clampi((rating - 1000) / 80, 0, MAX_STAT * 2)
	for _i in points:
		var k: String = STAT_ORDER[rng.randi_range(0, STAT_ORDER.size() - 1)]
		c["stats"][k] = mini(MAX_STAT, int(c["stats"][k]) + 1)
	var best := 0 if rating < 1500 else (1 if rating < 2000 else (2 if rating < 2600 else (3 if rating < 3200 else 4)))
	var rarities := ["common", "uncommon", "rare", "epic", "legendary"]
	var cls: String = ["melee", "ranged", "caster"][rng.randi_range(0, 2)]
	for slot in SLOTS:
		if slot != "weapon" and rng.randf() < 0.3:
			continue
		var pool: Array = ITEMS.keys().filter(func(id): return ITEMS[id]["slot"] == slot and rarities.find(ITEMS[id]["rarity"]) <= best \
			and (slot != "weapon" or ITEMS[id]["class"] == cls))
		if not pool.is_empty():
			c["equipped"][slot] = pool[rng.randi_range(0, pool.size() - 1)]
	c["ability"] = ABILITIES.keys()[rng.randi_range(0, ABILITIES.size() - 1)]
	c["look"]["race"] = LOOKS["race"][rng.randi_range(0, LOOKS["race"].size() - 1)]
	c["look"]["hair"] = LOOKS["hair"][rng.randi_range(0, LOOKS["hair"].size() - 1)]
	c["look"]["beard"] = LOOKS["beard"][rng.randi_range(0, LOOKS["beard"].size() - 1)] if rng.randf() < 0.4 else ""
	return battle_data(c, clampi((rating - 1000) / 100 + 6, 6, 30))


# --- looks --------------------------------------------------------------------------------------

static var _textures := {}


## The champion's sprite: its paper-doll layers drawn into one 32x32 image.
static func texture(look: Dictionary, equipped: Dictionary) -> Texture2D:
	var key := JSON.stringify([look, equipped])
	if _textures.has(key):
		return _textures[key]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for layer in LAYER_ORDER:
		var path := ""
		if LOOK_LAYER.has(layer):
			var v := str(look.get(layer, ""))
			if v != "":
				path = "%s%s/%s.png" % [SPRITE_DIR, LOOK_LAYER[layer], v]
		else:
			var id := str(equipped.get(layer, ""))
			if ITEMS.has(id):
				path = "%s%s/%s.png" % [SPRITE_DIR, SLOT_LAYER[layer], ITEMS[id]["sprite"]]
		if path == "" or not ResourceLoader.exists(path):
			continue
		var part: Image = (load(path) as Texture2D).get_image()
		if part.is_compressed():
			part.decompress()
		part.convert(Image.FORMAT_RGBA8)
		img.blend_rect(part, Rect2i(0, 0, mini(32, part.get_width()), mini(32, part.get_height())), Vector2i.ZERO)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


static func item_texture(id: String) -> Texture2D:
	if not ITEMS.has(id):
		return null
	var path := "%s%s/%s.png" % [SPRITE_DIR, SLOT_LAYER[ITEMS[id]["slot"]], ITEMS[id]["sprite"]]
	return load(path) if ResourceLoader.exists(path) else null


static func look_name(part: String, v: String) -> String:
	if v == "":
		return "None"
	return v.replace("_", " ").capitalize()
