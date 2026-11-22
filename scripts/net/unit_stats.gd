class_name UnitStats
extends RefCounted
## Server-only balance statistics: how often each unit is used and how armies
## with it do, in ranked battles and in Legion Draft. Kept per game version
## ("patch"), so every balance change starts a fresh table while older patches
## stay available for comparison. Players never see these; the admin console
## shows them ('unitstats').
##
## What counts:
##   - ranked: the signed-in player's own army in every server-run ranked
##     battle (the opponent is a saved copy or a generated army, so it's not
##     counted again);
##   - draft: every human player's board in every Legion Draft battle on the
##     server (bots' boards are left out; a human's win over a bot counts).
## A unit counts once per army however many squads of it there are.
## Use rate = armies containing the unit / all armies recorded.

const PATH := "user://unit_stats.json"
const MODES := ["ranked", "draft"]
const LOW_SAMPLE := 20       # win rates from fewer games are marked as unreliable
const SAVE_DELAY_MS := 10000   # at most this much is lost if the server is killed

## {patch: {mode: {"armies": int, "units": {unit_id: [games, wins, losses, draws]}}}}
var data := {}
var _dirty_since := 0


func load_file() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		data = parsed


func save_file() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
	_dirty_since = 0


## Saves at most every SAVE_DELAY_MS (call regularly; also on shutdown).
func save_if_due(force: bool = false) -> void:
	if _dirty_since != 0 and (force or Time.get_ticks_msec() - _dirty_since > SAVE_DELAY_MS):
		save_file()


static func current_patch() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))


func _table(patch: String, mode: String) -> Dictionary:
	if not data.has(patch):
		data[patch] = {}
	if not data[patch].has(mode):
		data[patch][mode] = {"armies": 0, "units": {}}
	return data[patch][mode]


## One army's battle: squads (each with "unit"), score 1 win / 0 loss / 0.5 draw.
func record(mode: String, squads: Array, score: float) -> void:
	if not mode in MODES:
		return
	var seen := {}
	for sq in squads:
		var u := str((sq as Dictionary).get("unit", ""))
		if GameData.UNITS.has(u):
			seen[u] = true
	if seen.is_empty():
		return
	var t := _table(current_patch(), mode)
	t["armies"] = int(t["armies"]) + 1
	for u in seen:
		var row: Array = t["units"].get(u, [0, 0, 0, 0])
		row[0] = int(row[0]) + 1
		var k := 1 if score >= 1.0 else (2 if score <= 0.0 else 3)
		row[k] = int(row[k]) + 1
		t["units"][u] = row
	if _dirty_since == 0:
		_dirty_since = maxi(1, Time.get_ticks_msec())


func patches() -> Array:
	var list: Array = data.keys()
	list.sort()
	return list


func reset(patch: String) -> bool:
	if not data.has(patch):
		return false
	data.erase(patch)
	save_file()
	return true


## One row per unit: {unit, name, ranked: {...}, draft: {...}} where each mode
## has games, wins, losses, draws, use (0-1) and win (0-1, -1 with no games).
func rows(patch: String) -> Array:
	var out: Array = []
	for u in GameData.UNITS:
		var r := {"unit": u, "name": str(GameData.UNITS[u]["name"])}
		for mode in MODES:
			var t: Dictionary = data.get(patch, {}).get(mode, {"armies": 0, "units": {}})
			var row: Array = t["units"].get(u, [0, 0, 0, 0])
			var games := int(row[0])
			var armies := int(t["armies"])
			# Draws count as half a win.
			r[mode] = {"games": games, "wins": int(row[1]), "losses": int(row[2]), "draws": int(row[3]),
				"use": float(games) / float(armies) if armies > 0 else 0.0,
				"win": (float(row[1]) + 0.5 * float(row[3])) / float(games) if games > 0 else -1.0}
		out.append(r)
	return out


func armies(patch: String, mode: String) -> int:
	return int(data.get(patch, {}).get(mode, {}).get("armies", 0))


## The admin console table. args: optional "ranked"/"draft" (sort by that mode),
## a sort key ("use", "win", "games", "name"), "all" (include unused units),
## a patch ("0.8") and/or a row limit (a number). Default: use rate, both modes.
func report(args: PackedStringArray) -> String:
	var patch := current_patch()
	var sort_mode := ""
	var key := "use"
	var show_all := false
	var limit := 0
	for a in args:
		var w := a.to_lower()
		if w in MODES:
			sort_mode = w
		elif w in ["use", "win", "games", "name"]:
			key = w
		elif w == "all":
			show_all = true
		elif data.has(a):
			patch = a
		elif w.is_valid_int() and int(w) > 0:
			limit = int(w)
		else:
			return "Unknown option '%s'. Usage: unitstats [ranked|draft] [use|win|games|name] [all] [N] [patch]" % a
	var list := rows(patch)
	if not show_all:
		list = list.filter(func(r): return int(r["ranked"]["games"]) + int(r["draft"]["games"]) > 0)
	if list.is_empty():
		return "No unit stats recorded for patch %s yet (ranked battles and Legion Draft battles on this server are counted). Patches with data: %s" % [patch, ", ".join(PackedStringArray(patches())) if not data.is_empty() else "none"]
	var modes: Array = [sort_mode] if sort_mode != "" else MODES
	list.sort_custom(func(x, y):
		if key == "name":
			return str(x["name"]) < str(y["name"])
		var vx := 0.0
		var vy := 0.0
		for m in modes:
			vx += float(x[m][key]) if key != "win" else _win_for_sort(x[m])
			vy += float(y[m][key]) if key != "win" else _win_for_sort(y[m])
		if vx != vy:
			return vx > vy
		return str(x["name"]) < str(y["name"]))
	if limit > 0:
		list = list.slice(0, limit)
	var lines: Array = []
	var nr := armies(patch, "ranked")
	var nd := armies(patch, "draft")
	lines.append("Unit stats, patch %s: %d ranked arm%s, %d draft arm%s.%s" % [patch, nr, "y" if nr == 1 else "ies", nd, "y" if nd == 1 else "ies",
		"" if sort_mode == "" else " Sorted by %s %s." % [sort_mode, key]])
	lines.append("%-24s | %-28s | %-28s" % ["", "RANKED", "LEGION DRAFT"])
	lines.append("%-24s | %6s %6s %13s | %6s %6s %13s" % ["Unit", "use", "win", "W-L-D", "use", "win", "W-L-D"])
	for r in list:
		var cells: Array = [str(r["name"]).substr(0, 24)]
		for m in MODES:
			var s: Dictionary = r[m]
			if int(s["games"]) == 0:
				cells.append_array(["-", "-", "-"])
			else:
				cells.append("%.1f%%" % (float(s["use"]) * 100.0))
				cells.append(("%.1f%%" % (float(s["win"]) * 100.0)) + ("*" if int(s["games"]) < LOW_SAMPLE else ""))
				cells.append("%d-%d-%d" % [s["wins"], s["losses"], s["draws"]])
		lines.append("%-24s | %6s %6s %13s | %6s %6s %13s" % cells)
	lines.append("use = share of armies with the unit; win = win rate of those armies (draws count half); * = under %d games." % LOW_SAMPLE)
	return "\n".join(PackedStringArray(lines))


static func _win_for_sort(s: Dictionary) -> float:
	# Units with too few games sort below the rest.
	return float(s["win"]) if int(s["games"]) >= LOW_SAMPLE else float(s["win"]) - 2.0


## A spreadsheet of one patch, written next to the stats file.
func write_csv(patch: String) -> String:
	var path := "user://unit_stats_%s.csv" % patch.replace("/", "_")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_line("unit,name,ranked_games,ranked_wins,ranked_losses,ranked_draws,ranked_use,ranked_win,draft_games,draft_wins,draft_losses,draft_draws,draft_use,draft_win")
	for r in rows(patch):
		var cells: Array = [r["unit"], "\"%s\"" % r["name"]]
		for m in MODES:
			var s: Dictionary = r[m]
			cells.append_array([s["games"], s["wins"], s["losses"], s["draws"], "%.4f" % s["use"], "" if int(s["games"]) == 0 else "%.4f" % s["win"]])
		f.store_line(",".join(PackedStringArray(cells.map(func(c): return str(c)))))
	return ProjectSettings.globalize_path(path)
