class_name DraftData
extends RefCounted
## Rules and content for the Legion Draft game mode: shop economy, unit
## abilities (out-of-battle effects) and trinkets.

const BOARD_SLOTS := 6
const TURN_GOLD := 10
const UNIT_COST := 3
const TRINKET_COST := 3
const REROLL_COST := 1
const BATTLES_PER_TIER := 3
const MAX_TIER := 6
const SHOP_UNIT_SLOTS := [3, 3, 4, 4, 5, 5]      # by shop tier 1..6
const SHOP_TRINKET_SLOTS := [1, 1, 2, 2, 2, 2]
const MAX_XP := 6                                # 1-2 copies = Lv1, 3-5 = Lv2, 6 = Lv3
const MAX_BONUS := 500                           # cap on % buffs from abilities

## Shop tier at which each rarity starts appearing.
const RARITY_TIER := {"common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 5}
## Squad size at level 1 by rarity; multiplied by LEVEL_COUNT_MULT.
const BASE_COUNT := {"common": 16, "uncommon": 8, "rare": 3, "epic": 2, "legendary": 1}
const LEVEL_COUNT_MULT := [1.0, 2.0, 3.0]
## Battle stat level used for draft levels 1/2/3 (+0%, +40%, +88%).
const LEVEL_SIM_LEVEL := [1, 6, 12]

## Board slot -> battle row. Slots 0-1 are the front line.
const SLOT_ROWS := ["front", "front", "middle", "middle", "back", "back"]

# --- Unit abilities ---------------------------------------------------------
# trigger: buy, sell, level_up, turn_start, turn_end, trinket, ally_sold,
#          battle_won, battle_lost
# effect:  buff_hp, buff_dmg, buff_both (amount = % points), gold, count, trinket
# target:  self, others, random1, random2, front, back, adjacent, beasts
# Amounts are multiplied by the unit's level.
const ABILITIES := {
	"goblin":            {"name": "Scavenger",       "trigger": "sell",        "effect": "gold",      "amount": 1,  "target": "self",    "text": "When sold: gain +1 extra gold."},
	"kobold_slinger":    {"name": "Spotter",         "trigger": "turn_start",  "effect": "buff_dmg",  "amount": 4,  "target": "random1", "text": "Start of turn: a random ally gets +4% damage."},
	"rat_swarm":         {"name": "Breed",           "trigger": "turn_end",    "effect": "count",     "amount": 2,  "target": "self",    "text": "End of turn: +2 rats join this squad."},
	"skeleton":          {"name": "Undying",         "trigger": "battle_lost", "effect": "buff_hp",   "amount": 10, "target": "self",    "text": "After a lost battle: +10% HP."},
	"orc_warrior":       {"name": "Warcry",          "trigger": "turn_end",    "effect": "buff_dmg",  "amount": 4,  "target": "front",   "text": "End of turn: other front-row allies get +4% damage."},
	"elf_archer":        {"name": "Volley Drill",    "trigger": "buy",         "effect": "buff_dmg",  "amount": 6,  "target": "back",    "text": "When bought: other back-row allies get +6% damage."},
	"gnoll_shaman":      {"name": "Mend",            "trigger": "turn_end",    "effect": "buff_hp",   "amount": 5,  "target": "random2", "text": "End of turn: 2 random allies get +5% HP."},
	"dwarf_berserker":   {"name": "Forgemaster",     "trigger": "level_up",    "effect": "buff_hp",   "amount": 8,  "target": "others",  "text": "On level up: all other allies get +8% HP."},
	"dire_wolf":         {"name": "Pack Hunter",     "trigger": "buy",         "effect": "buff_dmg",  "amount": 8,  "target": "beasts",  "text": "When bought: other beast allies get +8% damage."},
	"ogre":              {"name": "Glutton",         "trigger": "trinket",     "effect": "buff_hp",   "amount": 15, "target": "self",    "text": "When given a trinket: +15% HP."},
	"centaur":           {"name": "Outrider",        "trigger": "sell",        "effect": "buff_dmg",  "amount": 8,  "target": "random2", "text": "When sold: 2 random allies get +8% damage."},
	"orc_sorcerer":      {"name": "Arcane Study",    "trigger": "turn_end",    "effect": "buff_dmg",  "amount": 5,  "target": "self",    "text": "End of turn: +5% damage."},
	"naga_sharpshooter": {"name": "Overwatch",       "trigger": "battle_won",  "effect": "buff_dmg",  "amount": 8,  "target": "self",    "text": "After a won battle: +8% damage."},
	"treant":            {"name": "Deep Roots",      "trigger": "turn_start",  "effect": "buff_hp",   "amount": 6,  "target": "adjacent", "text": "Start of turn: neighbouring allies get +6% HP."},
	"hill_giant":        {"name": "Earthshaker",     "trigger": "buy",         "effect": "buff_hp",   "amount": 12, "target": "front",   "text": "When bought: other front-row allies get +12% HP."},
	"lich":              {"name": "Soul Harvest",    "trigger": "ally_sold",   "effect": "buff_dmg",  "amount": 10, "target": "self",    "text": "When an ally is sold: +10% damage."},
	"griffon":           {"name": "Treasure Hunter", "trigger": "level_up",    "effect": "trinket",   "amount": 1,  "target": "self",    "text": "On level up: gain a random trinket (or give one to an ally)."},
	"golden_dragon":     {"name": "Hoard",           "trigger": "turn_start",  "effect": "gold",      "amount": 1,  "target": "self",    "text": "Start of turn: gain +1 gold."},
	"titan":             {"name": "Colossus",        "trigger": "buy",         "effect": "buff_both", "amount": 8,  "target": "others",  "text": "When bought: all other allies get +8% HP and damage."},
	"phoenix":           {"name": "Rekindle",        "trigger": "sell",        "effect": "buff_both", "amount": 10, "target": "others",  "text": "When sold: all other allies get +10% HP and damage."},
}

# --- Trinkets ---------------------------------------------------------------
# kind "equip": held by a unit (one each, a new one replaces the old) and
#               applies "mods" in battle (see Army.unit_stats).
# kind "consume": used immediately for a permanent "effect".
const TRINKETS := {
	"iron_ring":        {"name": "Iron Ring",        "tier": 1, "kind": "equip",   "desc": "+15% HP.", "mods": {"hp_mult": 1.15}},
	"whetstone":        {"name": "Whetstone",        "tier": 1, "kind": "equip",   "desc": "+15% damage.", "mods": {"dmg_mult": 1.15}},
	"ration":           {"name": "Field Ration",     "tier": 1, "kind": "consume", "desc": "Permanently +6% HP and +6% damage.", "effect": {"hp": 6, "dmg": 6}},
	"swift_boots":      {"name": "Swift Boots",      "tier": 2, "kind": "equip",   "desc": "+25% movement speed.", "mods": {"speed_mult": 1.25}},
	"spiked_shield":    {"name": "Spiked Shield",    "tier": 2, "kind": "equip",   "desc": "Melee attackers take 25% of the damage they deal.", "mods": {"thorns": 0.25}},
	"war_horn":         {"name": "War Horn",         "tier": 2, "kind": "consume", "desc": "Permanently +4 units in this squad.", "effect": {"count": 4}},
	"blood_amulet":     {"name": "Blood Amulet",     "tier": 3, "kind": "equip",   "desc": "Heals for 20% of damage dealt.", "mods": {"lifesteal": 0.2}},
	"blast_powder":     {"name": "Blast Powder",     "tier": 3, "kind": "equip",   "desc": "Attacks splash +30 px (or gain a small splash).", "mods": {"aoe_add": 30.0}},
	"training_manual":  {"name": "Training Manual",  "tier": 3, "kind": "consume", "desc": "Counts as one extra copy toward the next level.", "effect": {"xp": 1}},
	"dragonhide":       {"name": "Dragonhide",       "tier": 4, "kind": "equip",   "desc": "+40% HP and heavy armor.", "mods": {"hp_mult": 1.4, "armor": "heavy"}},
	"rune_blade":       {"name": "Rune Blade",       "tier": 4, "kind": "equip",   "desc": "Damage becomes magic and +20% damage.", "mods": {"dmg_mult": 1.2, "damage": "magic"}},
	"quickdraw_gloves": {"name": "Quickdraw Gloves", "tier": 4, "kind": "equip",   "desc": "Attacks 25% faster.", "mods": {"cooldown_mult": 0.75}},
	"ember_charm":      {"name": "Ember Charm",      "tier": 5, "kind": "equip",   "desc": "Regenerates 2% max HP per second.", "mods": {"regen_pct": 0.02}},
	"giants_mantle":    {"name": "Giant's Mantle",   "tier": 5, "kind": "equip",   "desc": "+60% HP, -15% speed.", "mods": {"hp_mult": 1.6, "speed_mult": 0.85}},
	"elixir":           {"name": "Elixir of Might",  "tier": 5, "kind": "consume", "desc": "Permanently +15% HP and +15% damage.", "effect": {"hp": 15, "dmg": 15}},
	"wind_fan":         {"name": "Wind Fan",         "tier": 6, "kind": "equip",   "desc": "The squad flies over terrain and melee.", "mods": {"flying": true}},
	"legion_helm":      {"name": "Legion Helm",      "tier": 6, "kind": "equip",   "desc": "+50% units in this squad.", "mods": {"count_mult": 1.5}},
	"titans_orb":       {"name": "Titan's Orb",      "tier": 6, "kind": "equip",   "desc": "+50% HP and +50% damage.", "mods": {"hp_mult": 1.5, "dmg_mult": 1.5}},
}


static func trinket_texture(id: String) -> Texture2D:
	return load("res://assets/sprites/trinkets/%s.png" % id)


static func tier_for_battles(battles_played: int) -> int:
	@warning_ignore("integer_division")
	return mini(MAX_TIER, 1 + battles_played / BATTLES_PER_TIER)


static func level_for_xp(xp: int) -> int:
	if xp >= 6:
		return 3
	if xp >= 3:
		return 2
	return 1


## Copies still needed for the next level ("" at max level).
static func xp_text(xp: int) -> String:
	if xp >= 6:
		return "MAX"
	if xp >= 3:
		return "%d/3 to Lv3" % (xp - 3)
	return "%d/2 to Lv2" % (xp - 1)


static func units_for_tier(tier: int) -> Array:
	var out: Array = []
	for id in GameData.UNITS:
		if int(RARITY_TIER[GameData.UNITS[id]["rarity"]]) <= tier:
			out.append(id)
	return out


static func trinkets_for_tier(tier: int) -> Array:
	var out: Array = []
	for id in TRINKETS:
		if int(TRINKETS[id]["tier"]) <= tier:
			out.append(id)
	return out


static func new_entry(unit_id: String) -> Dictionary:
	return {"unit": unit_id, "xp": 1, "hp_b": 0, "dmg_b": 0, "count_b": 0, "trinket": ""}


static func entry_level(e: Dictionary) -> int:
	return level_for_xp(int(e.get("xp", 1)))


static func entry_count(e: Dictionary) -> int:
	var lvl := entry_level(e)
	var base: int = BASE_COUNT[GameData.UNITS[e["unit"]]["rarity"]]
	var c := float(base) * float(LEVEL_COUNT_MULT[lvl - 1]) + float(e.get("count_b", 0))
	var t := str(e.get("trinket", ""))
	if TRINKETS.has(t):
		c *= float(TRINKETS[t].get("mods", {}).get("count_mult", 1.0))
	return maxi(1, roundi(c))


## Battle modifiers for a board entry: ability buffs + equipped trinket.
static func entry_mods(e: Dictionary) -> Dictionary:
	var mods := {
		"hp_mult": 1.0 + float(e.get("hp_b", 0)) / 100.0,
		"dmg_mult": 1.0 + float(e.get("dmg_b", 0)) / 100.0,
	}
	var t := str(e.get("trinket", ""))
	if TRINKETS.has(t) and TRINKETS[t]["kind"] == "equip":
		var tm: Dictionary = TRINKETS[t]["mods"]
		for k in tm:
			if k == "count_mult":
				continue
			if k.ends_with("_mult") and mods.has(k):
				mods[k] = float(mods[k]) * float(tm[k])
			else:
				mods[k] = tm[k]
	return mods


## Board (Array of BOARD_SLOTS entries, {} for empty) -> battle squads.
static func board_to_squads(board: Array) -> Array:
	var squads: Array = []
	for i in board.size():
		var e: Dictionary = board[i]
		if e.is_empty():
			continue
		squads.append({
			"unit": e["unit"],
			"level": LEVEL_SIM_LEVEL[entry_level(e) - 1],
			"tier": 0,
			"row": SLOT_ROWS[mini(i, SLOT_ROWS.size() - 1)],
			"count": entry_count(e),
			"mods": entry_mods(e),
		})
	return squads


## Validate a board received over the network.
static func sanitize_board(raw) -> Array:
	var out: Array = []
	for i in BOARD_SLOTS:
		out.append({})
	if typeof(raw) != TYPE_ARRAY:
		return out
	for i in mini(BOARD_SLOTS, raw.size()):
		var e = raw[i]
		if typeof(e) != TYPE_DICTIONARY or not GameData.UNITS.has(str(e.get("unit", ""))):
			continue
		var t := str(e.get("trinket", ""))
		out[i] = {
			"unit": str(e["unit"]),
			"xp": clampi(int(e.get("xp", 1)), 1, MAX_XP),
			"hp_b": clampi(int(e.get("hp_b", 0)), 0, MAX_BONUS),
			"dmg_b": clampi(int(e.get("dmg_b", 0)), 0, MAX_BONUS),
			"count_b": clampi(int(e.get("count_b", 0)), 0, 200),
			"trinket": t if TRINKETS.has(t) and TRINKETS[t]["kind"] == "equip" else "",
		}
	return out


static func board_is_empty(board: Array) -> bool:
	for e in board:
		if not (e as Dictionary).is_empty():
			return false
	return true
