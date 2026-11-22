class_name RankedPool
extends RefCounted
## Server-side store of players' saved ranked armies ("defense snapshots").
## Each player keeps their latest army together with the rating they had when
## it was saved. Ranked opponents are drawn from players with a similar
## rating at save time.

const PATH := "user://ranked_armies.json"
const MAX_ENTRIES := 20000
const MAX_AGE_DAYS := 30
const START_WINDOW := 50
const MAX_WINDOW := 1600

var entries := {}          # player id -> {pid, name, rating, code, power, saved_at}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func load_file() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text()) if f else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	entries = {}
	for pid in parsed:
		var e = parsed[pid]
		if typeof(e) == TYPE_DICTIONARY and str(e.get("code", "")) != "":
			entries[str(pid)] = {"pid": str(pid), "name": str(e.get("name", "Commander")), "rating": int(e.get("rating", 1000)),
				"code": str(e["code"]), "power": int(e.get("power", 0)), "saved_at": int(e.get("saved_at", 0))}
	prune()


func save_file() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(entries))


## Save (or replace) a player's army. Returns false if the army is invalid.
func add(pid: String, player_name: String, rating: int, code: String) -> bool:
	pid = pid.strip_edges().left(40)
	var army := Army.decode(code)
	if pid == "" or army.is_empty() or code.length() > 4096:
		return false
	entries[pid] = {
		"pid": pid, "name": player_name.strip_edges().left(24), "rating": clampi(rating, 0, 5000),
		"code": code, "power": roundi(Army.army_power(army["squads"]) / 10.0),
		"saved_at": int(Time.get_unix_time_from_system()),
	}
	if entries.size() > MAX_ENTRIES:
		prune()
	return true


## Drop old snapshots, and the oldest ones if the pool is over capacity.
func prune() -> void:
	var cutoff := int(Time.get_unix_time_from_system()) - MAX_AGE_DAYS * 86400
	for pid in entries.keys():
		if int(entries[pid]["saved_at"]) < cutoff:
			entries.erase(pid)
	if entries.size() > MAX_ENTRIES:
		var list: Array = entries.values()
		list.sort_custom(func(a, b): return int(a["saved_at"]) < int(b["saved_at"]))
		for i in list.size() - MAX_ENTRIES:
			entries.erase(list[i]["pid"])


## Up to `count` armies from other players whose saved rating is close to
## `rating`. The search window widens until enough are found. Picks one
## close match, then one at/below and one at/above the player when possible.
## Armies near `rating`. The search starts close and widens, but never past
## `max_window` rating points either way.
func find(rating: int, exclude_pid: String, count: int = 3, max_window: int = MAX_WINDOW) -> Array:
	max_window = maxi(1, max_window)
	var window := mini(START_WINDOW, max_window)
	var candidates: Array = []
	while true:
		candidates = []
		for pid in entries:
			if pid == exclude_pid:
				continue
			if absi(int(entries[pid]["rating"]) - rating) <= window:
				candidates.append(entries[pid])
		if candidates.size() >= count or window >= max_window:
			break
		window = mini(window * 2, max_window)
	if candidates.is_empty():
		return []
	# Shuffle first so equally close armies are picked at random.
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	candidates.sort_custom(func(a, b): return absi(int(a["rating"]) - rating) < absi(int(b["rating"]) - rating))
	var picked: Array = [candidates.pop_front()]
	var below := -1
	var above := -1
	for i in candidates.size():
		var r := int(candidates[i]["rating"])
		if below == -1 and r <= rating:
			below = i
		if above == -1 and r >= rating and i != below:
			above = i
	for idx in [below, above]:
		if idx != -1 and picked.size() < count:
			picked.append(candidates[idx])
	for c in candidates:
		if picked.size() >= count:
			break
		if c not in picked:
			picked.append(c)
	return picked


func stats() -> String:
	if entries.is_empty():
		return "Ranked pool: no saved armies yet."
	var lo := 99999
	var hi := 0
	for pid in entries:
		lo = mini(lo, int(entries[pid]["rating"]))
		hi = maxi(hi, int(entries[pid]["rating"]))
	return "Ranked pool: %d saved armies, ratings %d-%d." % [entries.size(), lo, hi]
