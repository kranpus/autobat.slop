extends Node
## Autoload "Profile": the player's persistent progress (collection, army,
## currencies, rating). Saved as JSON in user://.

signal changed

const SAVE_PATH := "user://profile.json"
const SAVE_VERSION := 1
const MAP_REGEN_SECONDS := 600
const MAX_MAPS := 10

var data: Dictionary = {}


## Load as soon as the autoload is created, so the profile is usable even
## before the scene tree is ready (e.g. from tool or test scripts).
func _init() -> void:
	load_profile()
	# Unit locks last received from the server (or the built-in defaults).
	if typeof(data.get("unit_locks")) == TYPE_ARRAY:
		UnitLocks.set_locked_list(data["unit_locks"])
	if typeof(data.get("region_locks")) == TYPE_ARRAY:
		UnitLocks.set_locked_regions(data["region_locks"])


func default_profile() -> Dictionary:
	var units := {}
	for id in GameData.STARTER_UNITS:
		units[id] = {"level": 1, "tier": 0, "shards": 0}
	var army: Array = []
	for id in GameData.STARTER_UNITS:
		army.append({"unit": id, "row": GameData.default_row_for(id)})
	return {
		"version": SAVE_VERSION,
		"name": "Commander",
		"gold": 600,
		"maps": 5,
		"map_clock": int(Time.get_unix_time_from_system()),
		"rating": 1000,
		"wins": 0,
		"losses": 0,
		"units": units,
		"army": army,
		"music_volume": 0.6,
		"sfx_volume": 0.8,
	}


func load_profile() -> void:
	data = default_profile()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				for k in parsed:
					data[k] = parsed[k]
	_sanitize()
	_regen_maps()


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
	changed.emit()


func reset() -> void:
	data = default_profile()
	save()


func _sanitize() -> void:
	# JSON turns ints into floats; normalise and drop unknown units.
	for k in ["gold", "maps", "map_clock", "rating", "wins", "losses"]:
		data[k] = int(data.get(k, 0))
	var units := {}
	for id in data.get("units", {}):
		if GameData.UNITS.has(id):
			var u: Dictionary = data["units"][id]
			units[id] = {"level": int(u.get("level", 1)), "tier": int(u.get("tier", 0)), "shards": int(u.get("shards", 0))}
	data["units"] = units
	var army: Array = []
	for sq in data.get("army", []):
		if typeof(sq) == TYPE_DICTIONARY and units.has(str(sq.get("unit", ""))):
			var row := str(sq.get("row", "front"))
			if row not in GameData.ROWS:
				row = "front"
			army.append({"unit": str(sq["unit"]), "row": row})
	data["army"] = army
	var pc = data.get("pending_choice", {})
	var clean_pc := {}
	if typeof(pc) == TYPE_DICTIONARY and pc.has("options") and typeof(pc["options"]) == TYPE_ARRAY:
		var opts: Array = []
		for o in pc["options"]:
			if typeof(o) == TYPE_DICTIONARY and GameData.UNITS.has(str(o.get("unit", ""))):
				opts.append({"unit": str(o["unit"]), "shards": int(o.get("shards", 1)), "guaranteed": bool(o.get("guaranteed", false))})
		if not opts.is_empty():
			clean_pc = {"region": str(pc.get("region", "")), "options": opts, "gold": int(pc.get("gold", 0))}
	data["pending_choice"] = clean_pc


func _regen_maps() -> void:
	var now := int(Time.get_unix_time_from_system())
	if int(data["maps"]) >= MAX_MAPS:
		data["map_clock"] = now
		return
	var elapsed := now - int(data["map_clock"])
	@warning_ignore("integer_division")
	var gained := elapsed / MAP_REGEN_SECONDS
	if gained > 0:
		data["maps"] = mini(MAX_MAPS, int(data["maps"]) + gained)
		data["map_clock"] = int(data["map_clock"]) + gained * MAP_REGEN_SECONDS


## Seconds until the next free scouting map, or -1 when full.
func seconds_to_next_map() -> int:
	_regen_maps()
	if int(data["maps"]) >= MAX_MAPS:
		return -1
	return MAP_REGEN_SECONDS - (int(Time.get_unix_time_from_system()) - int(data["map_clock"]))


# --- accessors --------------------------------------------------------------

func gold() -> int:
	return int(data["gold"])


func maps() -> int:
	_regen_maps()
	return int(data["maps"])


func rating() -> int:
	return int(data["rating"])


func player_name() -> String:
	return str(data["name"])


func owns(id: String) -> bool:
	return data["units"].has(id)


func unit(id: String) -> Dictionary:
	return data["units"].get(id, {})


func level_cap(id: String) -> int:
	return Army.max_level_for_tier(int(unit(id).get("tier", 0)))


func squad_size(id: String) -> int:
	return Army.squad_size(id, int(unit(id).get("tier", 0)))


# --- upgrades ---------------------------------------------------------------

func level_up_cost(id: String) -> int:
	var lvl := int(unit(id).get("level", 1))
	var mult: float = GameData.RARITIES[GameData.UNITS[id]["rarity"]]["cost_mult"]
	return roundi(40.0 * pow(float(lvl), 1.6) * mult)


func can_level_up(id: String) -> bool:
	return owns(id) and int(unit(id)["level"]) < level_cap(id) and gold() >= level_up_cost(id)


func level_up(id: String) -> bool:
	if not can_level_up(id):
		return false
	data["gold"] = gold() - level_up_cost(id)
	data["units"][id]["level"] = int(data["units"][id]["level"]) + 1
	save()
	return true


## {"gold": int, "shards": int} needed for the next squad-size tier.
func tier_up_cost(id: String) -> Dictionary:
	var tier := int(unit(id).get("tier", 0))
	var r: Dictionary = GameData.RARITIES[GameData.UNITS[id]["rarity"]]
	return {
		"shards": ceili(float(r["shard_base"]) * float(tier + 1) * 0.75),
		"gold": roundi(100.0 * float(tier + 1) * float(r["cost_mult"])),
	}


func can_tier_up(id: String) -> bool:
	if not owns(id) or int(unit(id)["tier"]) >= GameData.MAX_TIER:
		return false
	var c := tier_up_cost(id)
	return gold() >= int(c["gold"]) and int(unit(id)["shards"]) >= int(c["shards"])


func tier_up(id: String) -> bool:
	if not can_tier_up(id):
		return false
	var c := tier_up_cost(id)
	data["gold"] = gold() - int(c["gold"])
	var u: Dictionary = data["units"][id]
	u["shards"] = int(u["shards"]) - int(c["shards"])
	u["tier"] = int(u["tier"]) + 1
	save()
	return true


# --- expeditions (finding units) ------------------------------------------

func region_unlocked(region_id: String) -> bool:
	return rating() >= int(GameData.REGIONS[region_id]["min_rating"]) and not UnitLocks.is_region_locked(region_id)


func can_explore(region_id: String) -> bool:
	return not has_pending_choice() and region_unlocked(region_id) and maps() >= int(GameData.REGIONS[region_id]["cost_maps"]) \
		and not GameData.region_drops(region_id).is_empty()


func has_pending_choice() -> bool:
	return not data.get("pending_choice", {}).is_empty()


## The open recruit choice: {"region": id, "options": [{unit, shards}], "gold": int}
func pending_choice() -> Dictionary:
	return data.get("pending_choice", {})


## Spend maps, find gold, and roll 3 different units for the player to choose
## from. The choice is saved, so closing the game doesn't reroll it.
func explore(region_id: String) -> Dictionary:
	if not can_explore(region_id):
		return {}
	var region: Dictionary = GameData.REGIONS[region_id]
	if int(data["maps"]) >= MAX_MAPS:
		data["map_clock"] = int(Time.get_unix_time_from_system())
	data["maps"] = int(data["maps"]) - int(region["cost_maps"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool: Dictionary = GameData.region_drops(region_id)
	var picks: Array = []
	for _i in mini(GameData.FINDS_PER_EXPEDITION, pool.size()):
		var picked := _weighted_pick(pool, rng)
		pool.erase(picked)
		picks.append(picked)
	var guaranteed := _apply_pity(region_id, picks, rng)
	var options: Array = []
	for picked in picks:
		var range_: Array = GameData.RARITIES[GameData.UNITS[picked]["rarity"]]["find_shards"]
		var shards := rng.randi_range(int(range_[0]), int(range_[1])) * int(region["cost_maps"]) * GameData.CHOICE_SHARD_MULT
		options.append({"unit": picked, "shards": shards, "guaranteed": picked == guaranteed})
	var gold_found := rng.randi_range(15, 45) * int(region["cost_maps"])
	data["gold"] = gold() + gold_found
	data["pending_choice"] = {"region": region_id, "options": options, "gold": gold_found}
	save()
	return pending_choice()


func _rarity_order(unit_id: String) -> int:
	return int(GameData.RARITIES[GameData.UNITS[unit_id]["rarity"]]["order"])


## Expeditions since an offer last contained `rarity` or better.
func pity_count(rarity: String) -> int:
	return int(data.get("pity", {}).get(rarity, 0))


## How many more expeditions until `rarity`+ is guaranteed (1 = the next one).
func pity_remaining(rarity: String) -> int:
	for p in GameData.PITY:
		if p["rarity"] == rarity:
			return maxi(1, int(p["every"]) - pity_count(rarity))
	return -1


## Force rarer units into the offer when a pity counter is due, then update
## the counters. Returns the unit that was guaranteed ("" if none).
func _apply_pity(region_id: String, picks: Array, rng: RandomNumberGenerator) -> String:
	var drops: Dictionary = GameData.region_drops(region_id)
	var pity: Dictionary = data.get("pity", {})
	var guaranteed := ""
	# Highest tier first, so one forced legendary also satisfies rare/epic.
	for k in range(GameData.PITY.size() - 1, -1, -1):
		var rule: Dictionary = GameData.PITY[k]
		var need := int(GameData.RARITIES[rule["rarity"]]["order"])
		if int(pity.get(rule["rarity"], 0)) + 1 < int(rule["every"]):
			continue
		var has := false
		for u in picks:
			if _rarity_order(u) >= need:
				has = true
		if has:
			continue
		var candidates := {}
		for u in drops:
			if _rarity_order(u) >= need and u not in picks:
				candidates[u] = drops[u]
		if candidates.is_empty():
			continue  # this region has nothing that rare; keep the counter
		# Replace the most common unit in the offer.
		var worst := 0
		for i in picks.size():
			if _rarity_order(picks[i]) < _rarity_order(picks[worst]):
				worst = i
		picks[worst] = _weighted_pick(candidates, rng)
		if guaranteed == "":
			guaranteed = picks[worst]
	var best := 0
	for u in picks:
		best = maxi(best, _rarity_order(u))
	for rule in GameData.PITY:
		var r: String = rule["rarity"]
		var region_has := false
		for u in drops:
			if _rarity_order(u) >= int(GameData.RARITIES[r]["order"]):
				region_has = true
		if best >= int(GameData.RARITIES[r]["order"]):
			pity[r] = 0
		elif region_has:
			pity[r] = int(pity.get(r, 0)) + 1
	data["pity"] = pity
	return guaranteed


## Take option `index` from the pending choice. Returns {unit, shards, new}.
func choose_recruit(index: int) -> Dictionary:
	var pc := pending_choice()
	if pc.is_empty() or index < 0 or index >= pc["options"].size():
		return {}
	var opt: Dictionary = pc["options"][index]
	var id: String = opt["unit"]
	var shards := int(opt["shards"])
	var is_new := not owns(id)
	if is_new:
		data["units"][id] = {"level": 1, "tier": 0, "shards": shards}
	else:
		data["units"][id]["shards"] = int(data["units"][id]["shards"]) + shards
	data["pending_choice"] = {}
	save()
	return {"unit": id, "shards": shards, "new": is_new}


func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for id in weights:
		total += int(weights[id])
	var roll := rng.randi_range(1, total)
	for id in weights:
		roll -= int(weights[id])
		if roll <= 0:
			return id
	return weights.keys()[0]


## Probability that a unit is among the offered choices in a region.
func drop_chance(region_id: String, unit_id: String) -> float:
	var drops: Dictionary = GameData.region_drops(region_id)
	if not drops.has(unit_id):
		return 0.0
	return 1.0 - _miss_chance(drops, unit_id, mini(GameData.FINDS_PER_EXPEDITION, drops.size()))


## Chance that `unit_id` is NOT drawn in `draws` weighted draws without replacement.
func _miss_chance(weights: Dictionary, unit_id: String, draws: int) -> float:
	if draws <= 0:
		return 1.0
	var total := 0.0
	for id in weights:
		total += float(weights[id])
	var p := 0.0
	for id in weights:
		if id == unit_id:
			continue
		var rest := weights.duplicate()
		rest.erase(id)
		p += float(weights[id]) / total * _miss_chance(rest, unit_id, draws - 1)
	return p


# --- army -------------------------------------------------------------------

## Army entries in battle-ready form, with current levels and tiers.
func army_squads() -> Array:
	var out: Array = []
	for sq in data["army"]:
		var u := unit(sq["unit"])
		if u.is_empty():
			continue
		out.append({"unit": sq["unit"], "level": int(u["level"]), "tier": int(u["tier"]), "row": sq["row"]})
	return out


func set_army(entries: Array) -> void:
	data["army"] = entries.slice(0, GameData.MAX_SQUADS)
	save()


func army_code() -> String:
	return Army.encode(player_name(), rating(), battle_squads())


## The army as it actually deploys: squads of locked units stay out.
func battle_squads() -> Array:
	var out: Array = []
	for sq in army_squads():
		if not UnitLocks.is_locked(sq["unit"]):
			out.append(sq)
	return out


# --- battle results ---------------------------------------------------------

## mode: "ranked", "live" or "practice". score: 1 win, 0.5 draw, 0 loss.
## Returns a summary dictionary for the result screen.
func apply_battle_result(mode: String, score: float, opp_rating: int, enemy_killed: int) -> Dictionary:
	var summary := {"gold": 0, "maps": 0, "rating": 0}
	var g := 20 + enemy_killed / 5
	if mode == "ranked" or mode == "live":
		var delta := Army.elo_delta(rating(), opp_rating, score)
		data["rating"] = maxi(0, rating() + delta)
		summary["rating"] = delta
		if score >= 1.0:
			data["wins"] = int(data["wins"]) + 1
			g += 100 + maxi(0, (opp_rating - 900) / 4)
			summary["maps"] = 1
		elif score <= 0.0:
			data["losses"] = int(data["losses"]) + 1
			g += 30
		else:
			g += 60
	g = roundi(float(g) * battle_gold_mult())
	data["gold"] = gold() + g
	data["maps"] = int(data["maps"]) + int(summary["maps"])
	summary["gold"] = g
	save()
	return summary


## Gold multiplier for battles, set by the Legion Draft server admin.
func battle_gold_mult() -> float:
	return float(data.get("server_rewards", {}).get("battle_mult", 1.0))


## Rewards for finishing a Legion Draft match. The amounts come from the
## match host / server (so the server admin controls them).
func add_draft_reward(gold_reward: int, maps_reward: int, place: int) -> Dictionary:
	gold_reward = maxi(0, gold_reward)
	maps_reward = clampi(maps_reward, 0, 5)
	data["gold"] = gold() + gold_reward
	data["maps"] = int(data["maps"]) + maps_reward
	data["draft_played"] = int(data.get("draft_played", 0)) + 1
	if place == 1:
		data["draft_wins"] = int(data.get("draft_wins", 0)) + 1
	save()
	return {"gold": gold_reward, "maps": maps_reward}
