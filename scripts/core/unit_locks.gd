class_name UnitLocks
extends RefCounted
## Which units are locked: unavailable in expeditions, shops, ranked
## opponents, army codes and Legion Draft, and unable to deploy in battle.
##
## Defaults come from GameData ("locked": true). The Legion Draft server can
## lock/unlock any unit at runtime (`lock` / `unlock` console commands); the
## list is pushed to players and remembered in their profile.

static var _locked := {}
static var _initialized := false


## Units locked when nothing else has been decided (the not-yet-released set).
static func defaults() -> Array:
	var out: Array = []
	for id in GameData.UNITS:
		if bool(GameData.UNITS[id].get("locked", false)):
			out.append(id)
	out.sort()
	return out


static func _ensure() -> void:
	if not _initialized:
		set_locked_list(defaults())


static func is_locked(id: String) -> bool:
	_ensure()
	return _locked.has(id)


static func locked_list() -> Array:
	_ensure()
	var out: Array = _locked.keys()
	out.sort()
	return out


static func as_dict() -> Dictionary:
	_ensure()
	return _locked.duplicate()


## Replace the locked set. Unknown ids are ignored.
static func set_locked_list(list: Array) -> void:
	_locked = {}
	for id in list:
		if GameData.UNITS.has(str(id)):
			_locked[str(id)] = true
	_initialized = true


static func set_locked(id: String, locked: bool) -> void:
	_ensure()
	if locked:
		_locked[id] = true
	else:
		_locked.erase(id)


static func unlocked_ids() -> Array:
	var out: Array = []
	for id in GameData.UNITS:
		if not is_locked(id):
			out.append(id)
	return out
