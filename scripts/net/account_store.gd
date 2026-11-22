class_name AccountStore
extends RefCounted
## Server-side player accounts: one JSON file per account in user://accounts/.
##
## A record holds the username, the password's salt + PBKDF2 hash (never the
## password itself), hashed "remember me" tokens, and the player's profile.
## Profiles are changed only through ProfileLogic on the server.

const DIR := "user://accounts"
const TOKEN_DAYS := 30
const MAX_TOKENS := 5
const USERNAME_MIN := 3
const USERNAME_MAX := 20

var dir := DIR
var _records := {}       # key (lowercase username) -> record
var _logic := {}         # key -> ProfileLogic
var _board := {}         # key -> {name, rating, wins, losses}: leaderboard index
var _board_ready := false
var _board_sorted: Array = []
var _board_dirty := true


func _init(directory: String = DIR) -> void:
	dir = directory
	DirAccess.make_dir_recursive_absolute(dir)


static func key_of(username: String) -> String:
	return username.strip_edges().to_lower()


## "" when the username is acceptable, otherwise the reason.
static func check_username(username: String) -> String:
	var u := username.strip_edges()
	if u.length() < USERNAME_MIN or u.length() > USERNAME_MAX:
		return "Usernames are %d-%d characters." % [USERNAME_MIN, USERNAME_MAX]
	var re := RegEx.create_from_string("^[A-Za-z0-9_]+$")
	if re.search(u) == null:
		return "Usernames may only use letters, numbers and _."
	return ""


func _path(key: String) -> String:
	return "%s/%s.json" % [dir, key]


func exists(username: String) -> bool:
	var key := key_of(username)
	return _records.has(key) or FileAccess.file_exists(_path(key))


## The account record, or {} if there is none.
func get_record(username: String) -> Dictionary:
	var key := key_of(username)
	if check_username(key) != "":
		return {}
	if not _records.has(key):
		if not FileAccess.file_exists(_path(key)):
			return {}
		var f := FileAccess.open(_path(key), FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text()) if f else null
		if typeof(parsed) != TYPE_DICTIONARY:
			return {}
		_records[key] = parsed
	return _records[key]


## Create an account from an already-made password record (see Passwords).
func create(username: String, password_record: Dictionary) -> Dictionary:
	var key := key_of(username)
	var record := {
		"username": username.strip_edges(),
		"created": int(Time.get_unix_time_from_system()),
		"password": password_record,
		"tokens": {},
		"profile": ProfileLogic.default_profile(),
	}
	record["profile"]["name"] = record["username"]
	_records[key] = record
	save(username)
	return record


func save(username: String) -> void:
	var key := key_of(username)
	if not _records.has(key):
		return
	var record: Dictionary = _records[key]
	if _logic.has(key):
		record["profile"] = (_logic[key] as ProfileLogic).data
	var f := FileAccess.open(_path(key), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(record))
	if _board_ready:
		_index(key, record)


## The account's profile rules object (created on first use, kept cached).
func logic(username: String) -> ProfileLogic:
	var key := key_of(username)
	if not _logic.has(key):
		var record := get_record(username)
		var pl := ProfileLogic.new(record.get("profile", {}))
		pl.data["name"] = str(record.get("username", username))
		_logic[key] = pl
	return _logic[key]


func set_password(username: String, password_record: Dictionary) -> void:
	var record := get_record(username)
	if record.is_empty():
		return
	record["password"] = password_record
	record["tokens"] = {}   # changing the password signs out every device
	save(username)


# --- "remember me" tokens --------------------------------------------------------

## Issue a new login token. Only its SHA-256 is stored.
func issue_token(username: String) -> String:
	var record := get_record(username)
	var token := Passwords.random_token()
	var tokens: Dictionary = record.get("tokens", {})
	tokens[Passwords.sha256_hex(token)] = int(Time.get_unix_time_from_system()) + TOKEN_DAYS * 86400
	# Keep only the newest few.
	while tokens.size() > MAX_TOKENS:
		var oldest := ""
		for h in tokens:
			if oldest == "" or int(tokens[h]) < int(tokens[oldest]):
				oldest = h
		tokens.erase(oldest)
	record["tokens"] = tokens
	save(username)
	return token


func check_token(username: String, token: String) -> bool:
	var record := get_record(username)
	if record.is_empty() or token.length() != 64:
		return false
	var tokens: Dictionary = record.get("tokens", {})
	var h := Passwords.sha256_hex(token)
	return tokens.has(h) and int(tokens[h]) > int(Time.get_unix_time_from_system())


func revoke_token(username: String, token: String) -> void:
	var record := get_record(username)
	if record.is_empty():
		return
	(record.get("tokens", {}) as Dictionary).erase(Passwords.sha256_hex(token))
	save(username)


# --- leaderboard -------------------------------------------------------------------

func _index(key: String, record: Dictionary) -> void:
	var p: Dictionary = record.get("profile", {})
	var entry := {"name": str(record.get("username", key)), "rating": int(p.get("rating", 1000)),
		"wins": int(p.get("wins", 0)), "losses": int(p.get("losses", 0))}
	if _board.get(key, {}) != entry:
		_board[key] = entry
		_board_dirty = true


## Read every account once (without keeping the records in memory).
func _ensure_board() -> void:
	if _board_ready:
		return
	_board_ready = true
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"):
			continue
		var key := file.get_basename()
		if _records.has(key):
			_index(key, _records[key])
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [dir, file]))
		if typeof(parsed) == TYPE_DICTIONARY:
			_index(key, parsed)


func _sorted_board() -> Array:
	_ensure_board()
	if _board_dirty:
		_board_dirty = false
		_board_sorted = []
		for key in _board:
			var e: Dictionary = _board[key]
			# Only players who have fought at least one ranked battle.
			if int(e["wins"]) + int(e["losses"]) > 0:
				_board_sorted.append(e.merged({"key": key}))
		_board_sorted.sort_custom(func(a, b):
			if int(a["rating"]) != int(b["rating"]):
				return int(a["rating"]) > int(b["rating"])
			if int(a["wins"]) != int(b["wins"]):
				return int(a["wins"]) > int(b["wins"])
			return str(a["key"]) < str(b["key"]))
	return _board_sorted


## The top players: [{rank, name, rating, wins, losses}].
func leaderboard(limit: int = 50) -> Array:
	var out: Array = []
	var sorted := _sorted_board()
	for i in mini(limit, sorted.size()):
		var e: Dictionary = sorted[i]
		out.append({"rank": i + 1, "name": e["name"], "rating": e["rating"], "wins": e["wins"], "losses": e["losses"]})
	return out


## {rank, of, rating}: rank 0 until the player has fought a ranked battle.
func rank_of(username: String) -> Dictionary:
	var key := key_of(username)
	var sorted := _sorted_board()
	for i in sorted.size():
		if sorted[i]["key"] == key:
			return {"rank": i + 1, "of": sorted.size(), "rating": sorted[i]["rating"]}
	return {"rank": 0, "of": sorted.size(), "rating": int(_board.get(key, {}).get("rating", 1000))}


func count() -> int:
	var n := 0
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			n += 1
	return n
