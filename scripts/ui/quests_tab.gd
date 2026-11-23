extends VBoxContainer
## Quest log (0.9.7): your commander level, the story quest you're on (50 in
## order), and the daily and weekly quests, each a notice on parchment with a
## wax-seal Claim button.

var _level_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _unlocks: Label
var _list: VBoxContainer
var _timer_refresh := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var top := UIKit.hbox(14)
	top.add_child(UIKit.label("Quest Log", 22, UIKit.ACCENT))
	top.add_child(UIKit.spacer())
	_level_label = UIKit.label("", 18, UIKit.ACCENT)
	top.add_child(_level_label)
	add_child(top)
	var xp_row := UIKit.hbox(10)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(0, 14)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_row.add_child(_xp_bar)
	_xp_label = UIKit.label("", 13, UIKit.TEXT_DIM)
	xp_row.add_child(_xp_label)
	add_child(xp_row)
	_unlocks = UIKit.label("", 13, UIKit.TEXT_DIM)
	_unlocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_unlocks)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = UIKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	Profile.changed.connect(refresh)
	Profile.quest_claimed.connect(_on_claimed)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			Profile.refresh_quests()   # a new day may have started
			refresh())
	refresh()


func _process(delta: float) -> void:
	# Keep the reset countdowns current.
	_timer_refresh -= delta
	if _timer_refresh <= 0.0 and is_visible_in_tree():
		_timer_refresh = 30.0
		for c in _list.get_children():
			if c.has_meta("countdown"):
				(c as Label).text = _countdown_text(str(c.get_meta("countdown")))


func refresh() -> void:
	if not is_inside_tree():
		return
	var lvl := Profile.player_level()
	_level_label.text = "Commander level %d%s" % [lvl, " (max)" if lvl >= Progression.MAX_LEVEL else ""]
	var base := Progression.xp_for_level(lvl)
	var need := Progression.xp_for_next(lvl)
	_xp_bar.max_value = need
	_xp_bar.value = mini(need, Profile.xp() - base) if lvl < Progression.MAX_LEVEL else need
	_xp_label.text = "%d / %d XP" % [Profile.xp() - base, need] if lvl < Progression.MAX_LEVEL else "%d XP" % Profile.xp()
	var next: Array = []
	for l in Progression.UNLOCKS:
		if int(l) > lvl and next.size() < 3:
			next.append("Lv %d: %s" % [int(l), Progression.UNLOCKS[l]["text"]])
	_unlocks.text = ("Next unlocks: " + "   ·   ".join(PackedStringArray(next))) if not next.is_empty() else "Everything is unlocked."
	_unlocks.text += "\nEarn XP from battles, expeditions, upgrades, challenges, Legion Draft and quests. Every level pays gold; every 3rd brings scouting maps, every 6th a trinket."

	UIKit.clear(_list)
	var log := Profile.quest_log()
	_section("Story", "The road ahead: 50 quests, one after another (%d of %d)." % [mini(int(Profile.data["quests"]["story"]["index"]) + 1, Progression.STORY.size()), Progression.STORY.size()], "")
	var any_story := false
	for e in log:
		if e["kind"] == "story":
			_list.add_child(_card(e))
			any_story = true
	if not any_story:
		_list.add_child(UIKit.label("You've finished every story quest. Well fought, Commander!", 14, UIKit.GOOD))
	for kind in ["daily", "weekly"]:
		var key: String = kind
		var unlock := Progression.unlock_level(key)
		_section("Daily quests" if kind == "daily" else "Weekly quests", "", kind)
		if lvl < unlock:
			_list.add_child(UIKit.label("Unlocks at commander level %d." % unlock, 14, UIKit.TEXT_DIM))
			continue
		for e in log:
			if e["kind"] == kind:
				_list.add_child(_card(e))


func _section(title: String, sub: String, countdown_kind: String) -> void:
	var h := UIKit.hbox(12)
	h.add_child(UIKit.label(title, 18, UIKit.ACCENT))
	h.add_child(UIKit.spacer())
	_list.add_child(h)
	if countdown_kind != "":
		var c := UIKit.label(_countdown_text(countdown_kind), 13, UIKit.TEXT_DIM)
		c.set_meta("countdown", countdown_kind)
		h.add_child(c)
	if sub != "":
		var s := UIKit.label(sub, 13, UIKit.TEXT_DIM)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(s)


func _countdown_text(kind: String) -> String:
	var now := int(Time.get_unix_time_from_system())
	var sec := Progression.seconds_to_next_day(now) if kind == "daily" else Progression.seconds_to_next_week(now)
	return "New quests in %s" % Progression.duration_text(sec)


## A quest notice on parchment.
func _card(e: Dictionary) -> Control:
	var p := UIKit.parchment_panel(16.0)
	if bool(e["claimed"]):
		p.modulate = Color(0.72, 0.68, 0.6)
	var h := UIKit.hbox(14)
	p.add_child(h)
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UIKit.hbox(10)
	var prefix := "%d. " % (int(e["index"]) + 1) if e["kind"] == "story" else ""
	title.add_child(ScrollUnroll.ink(prefix + str(e["text"]), 18, FantasySkin.INK))
	if bool(e["claimed"]):
		title.add_child(ScrollUnroll.ink("✓ Done", 14, FantasySkin.INK_GOOD))
	v.add_child(title)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.max_value = maxi(1, int(e["n"]))
	bar.value = int(e["progress"])
	v.add_child(bar)
	v.add_child(ScrollUnroll.ink("%s / %s   ·   Reward: %s" % [_num(int(e["progress"])), _num(int(e["n"])), e["reward"]], 13, FantasySkin.INK_DIM))
	h.add_child(v)
	var b := ScrollUnroll.seal_button("Claim" if not bool(e["claimed"]) else "Claimed", _claim.bind(str(e["kind"]), int(e["index"])))
	b.custom_minimum_size = Vector2(110, 40)
	b.disabled = not bool(e["done"]) or bool(e["claimed"])
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return p


func _num(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _claim(kind: String, index: int) -> void:
	var res := Profile.claim_quest(kind, index)
	if not res.is_empty():
		_on_claimed(res)


func _on_claimed(res: Dictionary) -> void:
	Audio.play_sfx("coins")
	var parts: Array = []
	if int(res.get("gold", 0)) > 0:
		parts.append("+%d gold" % int(res["gold"]))
	if int(res.get("maps", 0)) > 0:
		parts.append("+%d maps" % int(res["maps"]))
	if str(res.get("trinket", "")) != "":
		parts.append(str(Trinkets.ALL[res["trinket"]]["name"]))
	if int(res.get("xp", 0)) > 0:
		parts.append("+%d XP" % int(res["xp"]))
	UIKit.toast("Quest complete: %s" % ", ".join(PackedStringArray(parts)), UIKit.GOOD)
