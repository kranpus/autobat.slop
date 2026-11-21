class_name DraftRun
extends RefCounted
## One player's Legion Draft run: gold, shop, board, abilities and trinkets.
## Used for the local player and for bots (see auto_play). Pure logic, no UI.

var slots := DraftData.BOARD_SLOTS   # board size: 4, 6 or 8
var board: Array = []            # one entry per slot; {} = empty slot
var shop_units: Array = []       # [{"unit": id, "frozen": bool}]
var shop_trinkets: Array = []    # [{"trinket": id, "frozen": bool}]
var gold := 0
var battles_played := 0
var lives := 5
var wins := 0
var log_lines: Array = []        # recent ability messages for the UI
var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0, board_slots: int = DraftData.BOARD_SLOTS) -> void:
	slots = DraftData.valid_slots(board_slots)
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	board.resize(slots)
	for i in slots:
		board[i] = {}


func tier() -> int:
	return DraftData.tier_for_battles(battles_played)


func battles_to_next_tier() -> int:
	if tier() >= DraftData.MAX_TIER:
		return -1
	return DraftData.BATTLES_PER_TIER - battles_played % DraftData.BATTLES_PER_TIER


func round_number() -> int:
	return battles_played + 1


func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 30:
		log_lines.pop_front()


# --- turn flow --------------------------------------------------------------

func begin_turn() -> void:
	gold = DraftData.TURN_GOLD
	_roll_shop(true)
	_trigger_all("turn_start")


func end_turn() -> Array:
	_trigger_all("turn_end")
	return board.duplicate(true)


## outcome: 1 win, 0 loss, 0.5 draw. lives/wins are the host's authoritative totals.
func apply_battle_result(outcome: float, new_lives: int, new_wins: int) -> void:
	battles_played += 1
	lives = new_lives
	wins = new_wins
	if outcome >= 1.0:
		_trigger_all("battle_won")
	elif outcome <= 0.0:
		_trigger_all("battle_lost")


# --- shop -------------------------------------------------------------------

func _roll_shop(keep_frozen: bool) -> void:
	var t := tier()
	var kept_units: Array = []
	var kept_trinkets: Array = []
	if keep_frozen:
		for s in shop_units:
			if bool(s["frozen"]):
				kept_units.append(s)
		for s in shop_trinkets:
			if bool(s["frozen"]):
				kept_trinkets.append(s)
	var unit_pool := DraftData.units_for_tier(t)
	var trinket_pool := DraftData.trinkets_for_tier(t)
	shop_units = kept_units
	while shop_units.size() < int(DraftData.SHOP_UNIT_SLOTS[t - 1]):
		shop_units.append({"unit": unit_pool[rng.randi_range(0, unit_pool.size() - 1)], "frozen": false})
	shop_trinkets = kept_trinkets
	while shop_trinkets.size() < int(DraftData.SHOP_TRINKET_SLOTS[t - 1]):
		shop_trinkets.append({"trinket": trinket_pool[rng.randi_range(0, trinket_pool.size() - 1)], "frozen": false})


func reroll() -> bool:
	if gold < DraftData.REROLL_COST:
		return false
	gold -= DraftData.REROLL_COST
	_roll_shop(true)
	return true


func toggle_freeze_unit(i: int) -> void:
	if i >= 0 and i < shop_units.size():
		shop_units[i]["frozen"] = not bool(shop_units[i]["frozen"])


func toggle_freeze_trinket(i: int) -> void:
	if i >= 0 and i < shop_trinkets.size():
		shop_trinkets[i]["frozen"] = not bool(shop_trinkets[i]["frozen"])


func can_place_unit(unit_id: String, slot: int) -> bool:
	if slot < 0 or slot >= slots:
		return false
	var e: Dictionary = board[slot]
	return e.is_empty() or (e["unit"] == unit_id and int(e["xp"]) < DraftData.MAX_XP)


## Buy shop unit i into a board slot: an empty slot places it, a slot with
## the same unit merges it in as an extra copy.
func buy_unit(i: int, slot: int) -> bool:
	if i < 0 or i >= shop_units.size() or gold < DraftData.UNIT_COST:
		return false
	var uid: String = shop_units[i]["unit"]
	if not can_place_unit(uid, slot):
		return false
	gold -= DraftData.UNIT_COST
	shop_units.remove_at(i)
	var e: Dictionary = board[slot]
	if e.is_empty():
		board[slot] = DraftData.new_entry(uid)
		_log("Recruited %s." % _uname(uid))
		_trigger(slot, "buy")
	else:
		_add_xp(slot, 1)
		_trigger(slot, "buy")
	return true


## Use shop trinket i on the unit in slot.
func buy_trinket(i: int, slot: int) -> bool:
	if i < 0 or i >= shop_trinkets.size() or gold < DraftData.TRINKET_COST:
		return false
	if slot < 0 or slot >= slots or (board[slot] as Dictionary).is_empty():
		return false
	var tid: String = shop_trinkets[i]["trinket"]
	gold -= DraftData.TRINKET_COST
	shop_trinkets.remove_at(i)
	_apply_trinket(slot, tid)
	return true


func _apply_trinket(slot: int, tid: String) -> void:
	var e: Dictionary = board[slot]
	var t: Dictionary = DraftData.TRINKETS[tid]
	if t["kind"] == "equip":
		e["trinket"] = tid
		_log("%s equipped %s." % [_uname(e["unit"]), t["name"]])
	else:
		var fx: Dictionary = t["effect"]
		_buff(slot, int(fx.get("hp", 0)), int(fx.get("dmg", 0)))
		e["count_b"] = int(e["count_b"]) + int(fx.get("count", 0))
		_log("%s used %s." % [_uname(e["unit"]), t["name"]])
		if int(fx.get("xp", 0)) > 0:
			_add_xp(slot, int(fx["xp"]))
	_trigger(slot, "trinket")


func sell(slot: int) -> bool:
	if slot < 0 or slot >= slots:
		return false
	var e: Dictionary = board[slot]
	if e.is_empty():
		return false
	var lvl := DraftData.entry_level(e)
	_trigger(slot, "sell")
	gold += lvl
	_log("Sold %s for %d gold." % [_uname(e["unit"]), lvl])
	board[slot] = {}
	for s in slots:
		if not (board[s] as Dictionary).is_empty():
			_trigger(s, "ally_sold")
	return true


## Move a board unit: into an empty slot, merge onto the same unit, or swap.
func move(from: int, to: int) -> bool:
	if from == to or from < 0 or to < 0 or from >= slots or to >= slots:
		return false
	var a: Dictionary = board[from]
	var b: Dictionary = board[to]
	if a.is_empty():
		return false
	if not b.is_empty() and a["unit"] == b["unit"] and int(b["xp"]) < DraftData.MAX_XP:
		# Merge: keep the best buffs, add copies, keep a trinket.
		b["hp_b"] = mini(DraftData.MAX_BONUS, maxi(int(a["hp_b"]), int(b["hp_b"])) + 2)
		b["dmg_b"] = mini(DraftData.MAX_BONUS, maxi(int(a["dmg_b"]), int(b["dmg_b"])) + 2)
		b["count_b"] = maxi(int(a["count_b"]), int(b["count_b"]))
		if str(b["trinket"]) == "":
			b["trinket"] = a["trinket"]
		board[from] = {}
		_add_xp(to, int(a["xp"]))
		return true
	board[from] = b
	board[to] = a
	return true


func _add_xp(slot: int, amount: int) -> void:
	var e: Dictionary = board[slot]
	var before := DraftData.entry_level(e)
	e["xp"] = mini(DraftData.MAX_XP, int(e["xp"]) + amount)
	var after := DraftData.entry_level(e)
	if after > before:
		_log("%s reached level %d!" % [_uname(e["unit"]), after])
		_trigger(slot, "level_up")


# --- abilities --------------------------------------------------------------

func _trigger_all(trigger: String) -> void:
	for s in slots:
		if not (board[s] as Dictionary).is_empty():
			_trigger(s, trigger)


func _trigger(slot: int, trigger: String) -> void:
	var e: Dictionary = board[slot]
	if e.is_empty() or not DraftData.ABILITIES.has(e["unit"]):
		return
	var ab: Dictionary = DraftData.ABILITIES[e["unit"]]
	if ab["trigger"] != trigger:
		return
	var amount := int(ab["amount"]) * DraftData.entry_level(e)
	var effect: String = ab["effect"]
	match effect:
		"gold":
			gold += amount
			_log("%s (%s): +%d gold." % [_uname(e["unit"]), ab["name"], amount])
			return
		"trinket":
			_ability_trinket(slot, ab)
			return
	var targets := _targets(slot, ab["target"])
	if targets.is_empty():
		return
	for t in targets:
		match effect:
			"buff_hp":
				_buff(t, amount, 0)
			"buff_dmg":
				_buff(t, 0, amount)
			"buff_both":
				_buff(t, amount, amount)
			"count":
				board[t]["count_b"] = int(board[t]["count_b"]) + amount
	var what := {"buff_hp": "+%d%% HP", "buff_dmg": "+%d%% damage", "buff_both": "+%d%% HP & damage", "count": "+%d units"}
	_log("%s (%s): %s to %s." % [_uname(e["unit"]), ab["name"], String(what.get(effect, "%d")) % amount, _target_names(targets, slot)])


func _ability_trinket(slot: int, ab: Dictionary) -> void:
	var pool: Array = []
	for id in DraftData.trinkets_for_tier(tier()):
		if DraftData.TRINKETS[id]["kind"] == "equip":
			pool.append(id)
	if pool.is_empty():
		return
	var receiver := slot
	if str(board[slot]["trinket"]) != "":
		receiver = -1
		for s in slots:
			if not (board[s] as Dictionary).is_empty() and str(board[s]["trinket"]) == "":
				receiver = s
				break
	if receiver == -1:
		return
	var tid: String = pool[rng.randi_range(0, pool.size() - 1)]
	board[receiver]["trinket"] = tid
	_log("%s (%s): %s gets %s." % [_uname(board[slot]["unit"]), ab["name"], _uname(board[receiver]["unit"]), DraftData.TRINKETS[tid]["name"]])


func _buff(slot: int, hp_pct: int, dmg_pct: int) -> void:
	var e: Dictionary = board[slot]
	e["hp_b"] = mini(DraftData.MAX_BONUS, int(e["hp_b"]) + hp_pct)
	e["dmg_b"] = mini(DraftData.MAX_BONUS, int(e["dmg_b"]) + dmg_pct)


func _targets(slot: int, target: String) -> Array:
	var others: Array = []
	for s in slots:
		if s != slot and not (board[s] as Dictionary).is_empty():
			others.append(s)
	match target:
		"self":
			return [slot]
		"others":
			return others
		"random1", "random2":
			var want := 1 if target == "random1" else 2
			var pool := others.duplicate()
			var out: Array = []
			while out.size() < want and not pool.is_empty():
				out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
			return out
		"front", "back":
			var out: Array = []
			for s in others:
				if DraftData.slot_row(slots, s) == target:
					out.append(s)
			return out
		"adjacent":
			var out: Array = []
			for s in others:
				if absi(s - slot) == 1:
					out.append(s)
			return out
		"beasts":
			var out: Array = []
			for s in others:
				if GameData.UNITS[board[s]["unit"]]["armor"] == "beast":
					out.append(s)
			return out
	return []


func _uname(uid: String) -> String:
	return str(GameData.UNITS[uid]["name"])


func _target_names(targets: Array, slot: int) -> String:
	if targets.size() == 1:
		return "itself" if targets[0] == slot else _uname(board[targets[0]]["unit"])
	return "%d allies" % targets.size()


# --- helpers ----------------------------------------------------------------

func squads() -> Array:
	return DraftData.board_to_squads(board)


func unit_count() -> int:
	var n := 0
	for e in board:
		if not (e as Dictionary).is_empty():
			n += 1
	return n


func first_empty_slot() -> int:
	for s in slots:
		if (board[s] as Dictionary).is_empty():
			return s
	return -1


func slot_of_unit(uid: String) -> int:
	for s in slots:
		var e: Dictionary = board[s]
		if not e.is_empty() and e["unit"] == uid and int(e["xp"]) < DraftData.MAX_XP:
			return s
	return -1


# --- bot --------------------------------------------------------------------

## Simple bot: merge duplicates, fill empty slots, replace the weakest unit
## with rarer ones, buy trinkets with spare gold, keep melee in front.
func auto_play() -> void:
	var guard := 0
	while gold > 0 and guard < 40:
		guard += 1
		var acted := false
		# 1. Merge duplicates from the shop.
		for i in shop_units.size():
			var s := slot_of_unit(shop_units[i]["unit"])
			if s != -1 and gold >= DraftData.UNIT_COST:
				acted = buy_unit(i, s)
				break
		if acted:
			continue
		# 2. Fill empty slots with the rarest unit on offer.
		var empty := first_empty_slot()
		if empty != -1 and gold >= DraftData.UNIT_COST and not shop_units.is_empty():
			acted = buy_unit(_best_shop_unit(), empty)
			if acted:
				continue
		# 3. Full board: swap the weakest unit for a clearly rarer one.
		if empty == -1 and gold >= DraftData.UNIT_COST and not shop_units.is_empty():
			var best := _best_shop_unit()
			var weakest := _weakest_slot()
			var best_order: int = GameData.RARITIES[GameData.UNITS[shop_units[best]["unit"]]["rarity"]]["order"]
			var weak_e: Dictionary = board[weakest]
			var weak_order: int = GameData.RARITIES[GameData.UNITS[weak_e["unit"]]["rarity"]]["order"]
			if best_order > weak_order and DraftData.entry_level(weak_e) == 1:
				sell(weakest)
				acted = buy_unit(best, weakest)
				if acted:
					continue
		# 4. Trinkets for units without one (consumables go anywhere).
		if gold >= DraftData.TRINKET_COST and not shop_trinkets.is_empty() and unit_count() > 0:
			var tid: String = shop_trinkets[0]["trinket"]
			var target := -1
			for s in slots:
				var e: Dictionary = board[s]
				if e.is_empty():
					continue
				if DraftData.TRINKETS[tid]["kind"] == "consume" or str(e["trinket"]) == "":
					target = s
					break
			if target != -1:
				acted = buy_trinket(0, target)
				if acted:
					continue
		# 5. Reroll if there's money left, otherwise stop.
		if gold >= DraftData.REROLL_COST + DraftData.UNIT_COST:
			reroll()
			continue
		break
	_arrange_rows()


func _best_shop_unit() -> int:
	var best := 0
	var best_order := -1
	for i in shop_units.size():
		var o: int = GameData.RARITIES[GameData.UNITS[shop_units[i]["unit"]]["rarity"]]["order"]
		if o > best_order:
			best_order = o
			best = i
	return best


func _weakest_slot() -> int:
	var weakest := 0
	var low := INF
	for s in slots:
		var e: Dictionary = board[s]
		if e.is_empty():
			continue
		var p := Army.unit_power(e["unit"], DraftData.LEVEL_SIM_LEVEL[DraftData.entry_level(e) - 1], DraftData.entry_mods(e)) * float(DraftData.entry_count(e))
		if p < low:
			low = p
			weakest = s
	return weakest


## Put melee/tanks in the front slots and ranged/casters/healers in the back.
func _arrange_rows() -> void:
	var units: Array = []
	for e in board:
		if not (e as Dictionary).is_empty():
			units.append(e)
	var order := {"tank": 0, "melee": 1, "ranged": 2, "caster": 3, "healer": 4}
	units.sort_custom(func(a, b): return int(order[GameData.UNITS[a["unit"]]["role"]]) < int(order[GameData.UNITS[b["unit"]]["role"]]))
	for s in slots:
		board[s] = units[s] if s < units.size() else {}


# --- networking: state sync and replayable actions --------------------------

## Full state, including the RNG position, so a client can mirror the
## server's run exactly and replay the same actions with the same results.
func to_dict() -> Dictionary:
	return {
		"board": board.duplicate(true), "shop_units": shop_units.duplicate(true),
		"shop_trinkets": shop_trinkets.duplicate(true), "gold": gold,
		"battles_played": battles_played, "lives": lives, "wins": wins,
		"seed": rng.seed, "state": rng.state, "log": log_lines.duplicate(), "slots": slots,
	}


func load_dict(d: Dictionary) -> void:
	slots = DraftData.valid_slots(int(d.get("slots", slots)))
	board = DraftData.sanitize_board(d.get("board", []), slots)
	shop_units = []
	for s in d.get("shop_units", []):
		if typeof(s) == TYPE_DICTIONARY and GameData.UNITS.has(str(s.get("unit", ""))):
			shop_units.append({"unit": str(s["unit"]), "frozen": bool(s.get("frozen", false))})
	shop_trinkets = []
	for s in d.get("shop_trinkets", []):
		if typeof(s) == TYPE_DICTIONARY and DraftData.TRINKETS.has(str(s.get("trinket", ""))):
			shop_trinkets.append({"trinket": str(s["trinket"]), "frozen": bool(s.get("frozen", false))})
	gold = int(d.get("gold", 0))
	battles_played = int(d.get("battles_played", 0))
	lives = int(d.get("lives", lives))
	wins = int(d.get("wins", 0))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("state", 0))
	log_lines = Array(d.get("log", []))


## Apply a player action such as ["buy_unit", shop_index, slot]. The same
## action list applied to the same state always gives the same result, which
## is how the server verifies what clients do.
func apply_action(action: Array) -> bool:
	if action.is_empty():
		return false
	var a := func(i: int) -> int: return int(action[i]) if action.size() > i else -1
	match str(action[0]):
		"buy_unit":
			return buy_unit(a.call(1), a.call(2))
		"buy_trinket":
			return buy_trinket(a.call(1), a.call(2))
		"sell":
			return sell(a.call(1))
		"move":
			return move(a.call(1), a.call(2))
		"reroll":
			return reroll()
		"freeze_unit":
			if a.call(1) < 0 or a.call(1) >= shop_units.size():
				return false
			toggle_freeze_unit(a.call(1))
			return true
		"freeze_trinket":
			if a.call(1) < 0 or a.call(1) >= shop_trinkets.size():
				return false
			toggle_freeze_trinket(a.call(1))
			return true
	return false
