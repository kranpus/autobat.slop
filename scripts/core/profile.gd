extends Node
## Autoload "Profile": the player's progress as the game sees it.
##
## Two modes:
## - Offline (guest): a local profile in user://profile.json, changed by
##   ProfileLogic right here.
## - Logged in: the profile lives on the server. `data` mirrors the server's
##   copy; every change is sent as an action to the server, which applies it
##   with the same ProfileLogic rules and sends the new profile back.
##
## Device settings (volume, interface size, server address, cached unit locks)
## live separately in user://settings.json and never go to the server.

signal changed
## Logged in only: the server rolled an expedition; the recruit choice is ready.
signal choice_ready(choice: Dictionary)
## Logged in only: the server applied a recruit pick ({unit, shards, new}).
signal recruit_result(result: Dictionary)
## Logged in only: the server rolled a trinket hunt ({site, options}).
signal trinket_choice_ready(choice: Dictionary)
## Logged in only: the server applied a trinket pick ({trinket, new, gold}).
signal trinket_result(result: Dictionary)

const SAVE_PATH := "user://profile.json"
const SETTINGS_PATH := "user://settings.json"
const MAP_REGEN_SECONDS := ProfileLogic.MAP_REGEN_SECONDS
const MAX_MAPS := ProfileLogic.MAX_MAPS
const SETTING_KEYS := ["music_volume", "sfx_volume", "ui_scale", "server_address", "unit_locks", "region_locks", "locks_version", "server_rewards", "drop_rates", "difficulty", "screen_shake"]

var logic := ProfileLogic.new()
var settings: Dictionary = {"music_volume": 0.6, "sfx_volume": 0.8}
## True while logged in to a server account (progress lives on the server).
var online := false
## The account name while logged in.
var account := ""

## The profile dictionary (the server's copy while logged in).
var data: Dictionary:
	get:
		return logic.data
	set(value):
		logic.data = value


## Load as soon as the autoload is created, so the profile is usable even
## before the scene tree is ready (e.g. from tool or test scripts).
func _init() -> void:
	load_settings()
	load_profile()
	if typeof(settings.get("unit_locks")) == TYPE_ARRAY:
		UnitLocks.set_locked_list(settings["unit_locks"])
	if typeof(settings.get("region_locks")) == TYPE_ARRAY:
		UnitLocks.set_locked_regions(settings["region_locks"])
	if int(settings.get("locks_version", 1)) < 2:
		# 0.9.5: Badlands Camp's units are open by default (the server does the
		# same with its own saved locks).
		for id in GameData.REGIONS["badlands"]["drops"]:
			UnitLocks.set_locked(id, false)
		settings["unit_locks"] = UnitLocks.locked_list()
		settings["locks_version"] = 2
	if typeof(settings.get("drop_rates")) == TYPE_DICTIONARY:
		DropRates.apply(settings["drop_rates"])
	if typeof(settings.get("difficulty")) == TYPE_DICTIONARY:
		Difficulty.apply(settings["difficulty"])
	logic.gold_mult = battle_gold_mult()


# --- files --------------------------------------------------------------------

func load_settings() -> void:
	var parsed = _read_json(SETTINGS_PATH)
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in parsed:
			settings[k] = parsed[k]
		return
	# First run with this version: move device settings out of an old profile.
	var old = _read_json(SAVE_PATH)
	if typeof(old) == TYPE_DICTIONARY:
		for k in SETTING_KEYS:
			if old.has(k):
				settings[k] = old[k]
	save_settings()


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))


## The local (offline/guest) profile.
func load_profile() -> void:
	var parsed = _read_json(SAVE_PATH)
	var source: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	for k in SETTING_KEYS:
		source.erase(k)
	logic.load_from(source)


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else null


## Write the local profile (offline only) and refresh the UI.
func save() -> void:
	if not online:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(data, "\t"))
	changed.emit()


func reset() -> void:
	if online:
		return  # server profiles can't be wiped from the client
	logic.reset()
	save()


# --- server session -------------------------------------------------------------

## Called by Party when the server accepted a login.
func enter_online(username: String, server_profile: Dictionary) -> void:
	online = true
	account = username
	logic.load_from(server_profile)
	logic.gold_mult = battle_gold_mult()
	changed.emit()


## The server sent an updated profile.
func apply_server_profile(server_profile: Dictionary) -> void:
	if not online:
		return
	logic.load_from(server_profile)
	changed.emit()


## Logged out: back to the local guest profile.
func leave_online() -> void:
	online = false
	account = ""
	load_profile()
	changed.emit()


## Send a progress-changing action to the server (logged in only).
func _remote(action: Array) -> void:
	Party.profile_action(action)


# --- read-only accessors (same in both modes) -------------------------------------

func seconds_to_next_map() -> int:
	return logic.seconds_to_next_map()


func gold() -> int:
	return logic.gold()


func maps() -> int:
	return logic.maps()


func rating() -> int:
	return logic.rating()


func player_id() -> String:
	var had := str(data.get("player_id", "")) != ""
	var id := logic.player_id()
	if not had and not online:
		save()
	return id


func player_name() -> String:
	return account if online else logic.player_name()


func owns(id: String) -> bool:
	return logic.owns(id)


func unit(id: String) -> Dictionary:
	return logic.unit(id)


func level_cap(id: String) -> int:
	return logic.level_cap(id)


func squad_size(id: String) -> int:
	return logic.squad_size(id)


func level_up_cost(id: String) -> int:
	return logic.level_up_cost(id)


func can_level_up(id: String) -> bool:
	return logic.can_level_up(id)


func tier_up_cost(id: String) -> Dictionary:
	return logic.tier_up_cost(id)


func can_tier_up(id: String) -> bool:
	return logic.can_tier_up(id)


func region_unlocked(region_id: String) -> bool:
	return logic.region_unlocked(region_id)


func can_explore(region_id: String) -> bool:
	return logic.can_explore(region_id)


func has_pending_choice() -> bool:
	return logic.has_pending_choice()


func pending_choice() -> Dictionary:
	return logic.pending_choice()


func pity_count(rarity: String) -> int:
	return logic.pity_count(rarity)


func pity_remaining(rarity: String) -> int:
	return logic.pity_remaining(rarity)


func drop_chance(region_id: String, unit_id: String) -> float:
	return logic.drop_chance(region_id, unit_id)


func army_squads() -> Array:
	return logic.army_squads()


func battle_squads() -> Array:
	return logic.battle_squads()


func army_code() -> String:
	return Army.encode(player_name(), rating(), battle_squads())


## Gold multiplier for battles, set by the Legion Draft server admin.
func battle_gold_mult() -> float:
	return float(settings.get("server_rewards", {}).get("battle_mult", 1.0))


# --- progress changes (local when offline, server when logged in) -----------------

func level_up(id: String) -> bool:
	if not can_level_up(id):
		return false
	if online:
		_remote(["level_up", id])
		return true
	logic.level_up(id)
	save()
	return true


func tier_up(id: String) -> bool:
	if not can_tier_up(id):
		return false
	if online:
		_remote(["tier_up", id])
		return true
	logic.tier_up(id)
	save()
	return true


## Offline: returns the recruit choice. Logged in: returns {} and the choice
## arrives through `choice_ready` once the server has rolled it.
func explore(region_id: String) -> Dictionary:
	if not can_explore(region_id):
		return {}
	if online:
		_remote(["explore", region_id])
		return {}
	var res := logic.explore(region_id)
	save()
	return res


## Offline: returns {unit, shards, new}. Logged in: returns {} and the result
## arrives through `recruit_result`.
func choose_recruit(index: int) -> Dictionary:
	if online:
		_remote(["choose_recruit", index])
		return {}
	var res := logic.choose_recruit(index)
	save()
	return res


func set_army(entries: Array) -> void:
	if online:
		logic.set_army(entries)  # show it right away; the server confirms
		changed.emit()
		_remote(["set_army", entries])
		return
	logic.set_army(entries)
	save()


# --- trinkets ----------------------------------------------------------------------

func owns_trinket(id: String) -> bool:
	return logic.owns_trinket(id)


func trinket_count() -> int:
	return logic.trinket_count()


func owned_trinkets() -> Array:
	return logic.owned_trinkets()


func trinkets_of(unit_id: String) -> Array:
	return logic.trinkets_of(unit_id)


func trinket_holder(id: String) -> String:
	return logic.trinket_holder(id)


func trinket_site_unlocked(site_id: String) -> bool:
	return logic.trinket_site_unlocked(site_id)


func can_hunt_trinkets(site_id: String) -> bool:
	return logic.can_hunt_trinkets(site_id)


func has_pending_trinket() -> bool:
	return logic.has_pending_trinket()


func pending_trinket() -> Dictionary:
	return logic.pending_trinket()


## Offline: returns the choice. Logged in: {} and `trinket_choice_ready` fires.
func hunt_trinkets(site_id: String) -> Dictionary:
	if not can_hunt_trinkets(site_id):
		return {}
	if online:
		_remote(["hunt_trinkets", site_id])
		return {}
	var res := logic.hunt_trinkets(site_id)
	save()
	return res


## Offline: returns {trinket, new, gold}. Logged in: {} and `trinket_result` fires.
func choose_trinket(index: int) -> Dictionary:
	if online:
		_remote(["choose_trinket", index])
		return {}
	var res := logic.choose_trinket(index)
	save()
	return res


func equip_trinket(unit_id: String, slot: int, id: String) -> bool:
	if not logic.equip_trinket(unit_id, slot, id):
		return false
	if online:
		changed.emit()   # shown right away; the server confirms
		_remote(["equip_trinket", unit_id, slot, id])
	else:
		save()
	return true


func unequip_trinket(unit_id: String, slot: int) -> bool:
	if not logic.unequip_trinket(unit_id, slot):
		return false
	if online:
		changed.emit()
		_remote(["unequip_trinket", unit_id, slot])
	else:
		save()
	return true


# --- challenges ---------------------------------------------------------------------

func challenge_cleared(id: String) -> bool:
	return logic.challenge_cleared(id)


func challenge_unlocked(id: String) -> bool:
	return logic.challenge_unlocked(id)


func challenges_cleared() -> int:
	return logic.challenges_cleared()


## Offline only; signed-in challenge battles are run and rewarded by the server.
func complete_challenge(id: String, won: bool) -> Dictionary:
	if online:
		return {}
	var res := logic.complete_challenge(id, won)
	save()
	return res


## Offline battles only; logged-in battle rewards are decided by the server.
func apply_battle_result(mode: String, score: float, opp_rating: int, enemy_killed: int, vs_ai: bool = false) -> Dictionary:
	if online:
		return {"gold": 0, "maps": 0, "rating": 0}
	logic.gold_mult = battle_gold_mult()
	var summary := logic.apply_battle_result(mode, score, opp_rating, enemy_killed, vs_ai)
	save()
	return summary


## Offline/LAN only; logged-in draft rewards are paid by the server.
func add_draft_reward(gold_reward: int, maps_reward: int, place: int) -> Dictionary:
	if online:
		return {"gold": 0, "maps": 0}
	var res := logic.add_draft_reward(gold_reward, maps_reward, place)
	save()
	return res
