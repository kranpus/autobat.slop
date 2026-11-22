extends Node
## Autoload "Audio": music playback and a small pooled, throttled SFX player
## so a 1000-unit battle doesn't trigger 1000 overlapping sounds.

const SFX := {
	"click": ["res://assets/sfx/ui_click.wav"],
	"hover": ["res://assets/sfx/ui_hover.wav"],
	"toggle": ["res://assets/sfx/ui_toggle.wav"],
	"melee": [
		"res://assets/sfx/sword_1.ogg", "res://assets/sfx/sword_2.ogg", "res://assets/sfx/sword_3.ogg", "res://assets/sfx/sword_4.ogg",
		"res://assets/sfx/clash_1.ogg", "res://assets/sfx/clash_2.ogg", "res://assets/sfx/clash_3.ogg", "res://assets/sfx/clash_4.ogg",
	],
	"shoot": ["res://assets/sfx/bow.ogg", "res://assets/sfx/arrow_hit.ogg"],
	"magic": ["res://assets/sfx/spell_fire.ogg", "res://assets/sfx/spell.ogg"],
	"die": ["res://assets/sfx/die_1.ogg", "res://assets/sfx/hurt_1.ogg", "res://assets/sfx/hurt_2.ogg",
		"res://assets/sfx/grunt_1.ogg", "res://assets/sfx/grunt_2.ogg", "res://assets/sfx/grunt_3.ogg"],
	"impact": ["res://assets/sfx/impact_1.ogg", "res://assets/sfx/impact_2.ogg", "res://assets/sfx/impact_3.ogg", "res://assets/sfx/impact_4.ogg"],
	"explosion": ["res://assets/sfx/explosion.ogg"],
	"swish": ["res://assets/sfx/swish_1.ogg", "res://assets/sfx/swish_2.ogg", "res://assets/sfx/swish_3.ogg"],
	"spell": ["res://assets/sfx/spell_1.ogg", "res://assets/sfx/spell_2.ogg", "res://assets/sfx/spell_3.ogg", "res://assets/sfx/spell_4.ogg"],
	"big_roar": ["res://assets/sfx/roar.ogg", "res://assets/sfx/roar_2.ogg", "res://assets/sfx/roar_3.ogg"],
	"horn": ["res://assets/sfx/war_horn.ogg"],
	"fanfare": ["res://assets/sfx/fanfare.ogg"],
	"coins": ["res://assets/sfx/coins.ogg"],
	"gem": ["res://assets/sfx/gem.ogg"],
	"scroll": ["res://assets/sfx/scroll.ogg"],
	"roar": ["res://assets/sfx/roar.ogg"],
}
## Each key can have several tracks; one is picked at random when it starts.
const MUSIC := {
	"menu": ["res://assets/music/town_theme.mp3"],
	"battle": ["res://assets/music/battle_theme_a.mp3", "res://assets/music/battle_theme_b.mp3", "res://assets/music/determined_pursuit.ogg"],
	"boss": ["res://assets/music/boss_battle.ogg"],
}
## Short pieces played once (no loop) at the end of a battle.
const STINGERS := {
	"victory": "res://assets/music/victory.ogg",
	"defeat": "res://assets/music/defeat.ogg",
}
const POOL_SIZE := 12
const MIN_INTERVAL_MS := 70

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}
var _cache := {}
var _music: AudioStreamPlayer
var _music_key := ""
var _rng := RandomNumberGenerator.new()
var music_volume := 0.6
var sfx_volume := 0.8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	music_volume = float(Profile.settings.get("music_volume", 0.6))
	sfx_volume = float(Profile.settings.get("sfx_volume", 0.8))
	_apply_music_volume()


func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


func play_sfx(key: String, volume_db: float = 0.0) -> void:
	if sfx_volume <= 0.001 or not SFX.has(key):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(key, -100000)) < MIN_INTERVAL_MS:
		return
	_last_played[key] = now
	var list: Array = SFX[key]
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = _stream(list[_rng.randi_range(0, list.size() - 1)])
	p.volume_db = volume_db + linear_to_db(sfx_volume)
	p.pitch_scale = _rng.randf_range(0.9, 1.1)
	p.play()


func play_music(key: String) -> void:
	if key == _music_key and _music.playing:
		return
	_music_key = key
	var tracks: Array = MUSIC[key]
	var s := _stream(tracks[_rng.randi_range(0, tracks.size() - 1)])
	_set_loop(s, true)
	_music.stream = s
	_apply_music_volume()
	_music.play()


## A short piece instead of the music (victory / defeat). The next
## play_music call starts the music again.
func play_stinger(key: String) -> void:
	if not STINGERS.has(key):
		return
	_music_key = "stinger:" + key
	var s := _stream(STINGERS[key])
	_set_loop(s, false)
	_music.stream = s
	_apply_music_volume()
	_music.play()


func _set_loop(s: AudioStream, on: bool) -> void:
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = on
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = on


func _exit_tree() -> void:
	# Release streams so nothing is reported as leaked on quit.
	if _music:
		_music.stop()
		_music.stream = null
	for p in _pool:
		p.stop()
		p.stream = null
	_cache.clear()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	Profile.settings["music_volume"] = music_volume
	_apply_music_volume()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	Profile.settings["sfx_volume"] = sfx_volume


func _apply_music_volume() -> void:
	if _music:
		_music.volume_db = linear_to_db(maxf(music_volume, 0.0001)) - 6.0


## Adds click/hover sounds to a button.
func hook_button(b: BaseButton) -> void:
	b.pressed.connect(func(): play_sfx("click", -4.0))
	b.mouse_entered.connect(func(): play_sfx("hover", -16.0))
