class_name Army
extends RefCounted
## Pure helpers for army math: stats per level, squad sizes, power,
## shareable army codes and procedural opponent generation.
##
## A "squad" is a Dictionary: {"unit": String, "level": int, "tier": int, "row": String}

const CODE_PREFIX := "AB1:"


static func max_level_for_tier(tier: int) -> int:
	return GameData.BASE_MAX_LEVEL + GameData.LEVELS_PER_TIER * tier


static func level_mult(level: int) -> float:
	return 1.0 + 0.08 * float(level - 1)


static func squad_size(unit_id: String, tier: int) -> int:
	var r: Dictionary = GameData.RARITIES[GameData.UNITS[unit_id]["rarity"]]
	return int(r["squad_base"]) + int(r["squad_step"]) * tier


## Stats of a single unit at a given level.
static func unit_stats(unit_id: String, level: int) -> Dictionary:
	var base: Dictionary = GameData.UNITS[unit_id]
	var m := level_mult(level)
	var s := base.duplicate()
	s["hp"] = float(base["hp"]) * m
	s["dmg"] = float(base["dmg"]) * m
	s["heal"] = float(base["heal"]) * m
	s["regen"] = float(base["regen"]) * m
	return s


static func unit_power(unit_id: String, level: int) -> float:
	var s := unit_stats(unit_id, level)
	var cd: float = s["cooldown"]
	var dps: float = (float(s["dmg"]) * (1.0 + minf(float(s["aoe"]), 60.0) / 40.0) + float(s["heal"]) * 1.5) / cd + float(s["regen"])
	var reach_bonus := 1.0 + minf(float(s["range"]), 260.0) / 520.0
	# Big units are worth more than raw stats suggest (they can't be swarmed
	# as efficiently), so rarer units carry a calibrated multiplier.
	var rarity_mult: float = GameData.RARITIES[s["rarity"]]["power_mult"]
	return sqrt(float(s["hp"]) * dps * reach_bonus) * rarity_mult


## Units actually deployed per squad, respecting the global army unit cap.
static func deploy_counts(squads: Array) -> Array:
	var out: Array = []
	var remaining := GameData.ARMY_UNIT_CAP
	for sq in squads:
		var n := mini(squad_size(sq["unit"], int(sq["tier"])), remaining)
		out.append(n)
		remaining -= n
	return out


static func total_units(squads: Array) -> int:
	var t := 0
	for n in deploy_counts(squads):
		t += int(n)
	return t


static func army_power(squads: Array) -> float:
	var counts := deploy_counts(squads)
	var p := 0.0
	for i in squads.size():
		p += unit_power(squads[i]["unit"], int(squads[i]["level"])) * float(counts[i])
	return p


static func format_power(p: float) -> String:
	return str(roundi(p / 10.0))


# --- Army codes (shareable text for async PvP challenges) -------------------

static func encode(player_name: String, rating: int, squads: Array) -> String:
	var s: Array = []
	for sq in squads:
		s.append([sq["unit"], int(sq["level"]), int(sq["tier"]), GameData.ROWS.find(sq["row"])])
	var payload := {"n": player_name.left(24), "r": rating, "s": s}
	return CODE_PREFIX + Marshalls.utf8_to_base64(JSON.stringify(payload))


## Returns {} when the code is invalid. Values are clamped to legal ranges.
static func decode(code: String) -> Dictionary:
	code = code.strip_edges()
	if not code.begins_with(CODE_PREFIX):
		return {}
	var text := Marshalls.base64_to_utf8(code.substr(CODE_PREFIX.length()))
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("s") or typeof(parsed["s"]) != TYPE_ARRAY:
		return {}
	var squads: Array = []
	for entry in parsed["s"]:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 4:
			continue
		var uid := str(entry[0])
		if not GameData.UNITS.has(uid):
			continue
		var tier := clampi(int(entry[2]), 0, GameData.MAX_TIER)
		var level := clampi(int(entry[1]), 1, max_level_for_tier(tier))
		var row_i := clampi(int(entry[3]), 0, GameData.ROWS.size() - 1)
		squads.append({"unit": uid, "level": level, "tier": tier, "row": GameData.ROWS[row_i]})
		if squads.size() >= GameData.MAX_SQUADS:
			break
	if squads.is_empty():
		return {}
	return {
		"name": str(parsed.get("n", "Challenger")).left(24),
		"rating": int(parsed.get("r", 1000)),
		"squads": squads,
	}


# --- Opponent generation (ranked ghosts) ------------------------------------

const GHOST_NAMES := [
	"Warlord Grak", "Lady Vesper", "The Bone Duke", "Mira Swiftbow", "Old Thane Borin",
	"Sable Witch", "Captain Rook", "Iron Hilda", "Kael the Red", "Nyx", "Brother Ash",
	"Queen Morwen", "Zug Zug", "The Pale Rider", "Ser Galen", "Hexa", "Tuskbreaker",
]


static func generate_opponent(target_power: float, rating: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Higher ratings unlock rarer units for ghosts.
	var max_rarity := 1
	if rating >= 1050:
		max_rarity = 2
	if rating >= 1150:
		max_rarity = 3
	if rating >= 1300:
		max_rarity = 4
	var pool: Array = []
	for id in GameData.UNITS:
		if int(GameData.RARITIES[GameData.UNITS[id]["rarity"]]["order"]) <= max_rarity:
			pool.append(id)
	var squad_count := rng.randi_range(3, GameData.MAX_SQUADS)
	var squads: Array = []
	var used := {}
	for i in squad_count:
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		if used.has(id):
			continue
		used[id] = true
		squads.append({"unit": id, "level": 1, "tier": 0, "row": GameData.default_row_for(id)})
	# Upgrade random squads until we reach the target power.
	var guard := 0
	while army_power(squads) < target_power and guard < 2000:
		guard += 1
		var sq: Dictionary = squads[rng.randi_range(0, squads.size() - 1)]
		if rng.randf() < 0.55 and int(sq["level"]) < max_level_for_tier(int(sq["tier"])):
			sq["level"] = int(sq["level"]) + 1
		elif int(sq["tier"]) < GameData.MAX_TIER:
			sq["tier"] = int(sq["tier"]) + 1
		elif int(sq["level"]) < max_level_for_tier(int(sq["tier"])):
			sq["level"] = int(sq["level"]) + 1
	return {
		"name": GHOST_NAMES[rng.randi_range(0, GHOST_NAMES.size() - 1)],
		"rating": rating,
		"squads": squads,
	}


static func elo_delta(my_rating: int, opp_rating: int, score: float, k: float = 32.0) -> int:
	var expected := 1.0 / (1.0 + pow(10.0, float(opp_rating - my_rating) / 400.0))
	return roundi(k * (score - expected))
