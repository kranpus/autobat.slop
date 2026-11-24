extends CanvasLayer
## Show-don't-tell tutorial: a spotlight on the one control to use next, a
## pulsing ring around it and a few words. The player does each step
## themselves; the tutorial notices and moves on.
##
## The guided first session is a chain of short chapters (first battle, level
## up, recruit, army, ranked, finale). Afterwards, one-off tips
## appear the first time a feature is opened (trinkets, Legion Draft,
## leaderboard). Progress is kept in the device settings ("tutorial");
## Settings → Replay tutorial starts again.
##
## Targets are controls marked with UIKit.tut(control, "id"), or a main tab:
## "tab:<Tab name>". A step:
##   target  id ("" = no spotlight: the bubble sits in the middle)
##   text    a few words
##   button  optional button text; `action` runs when it's pressed, then the
##           step is done
##   done    Callable -> bool: checked every frame
##   enter   optional Callable run when the step starts
##   hide    true: no overlay (e.g. while a battle plays); `text` shows as a
##           small caption at the top for a few seconds

const CHAIN := ["first_battle", "level_up", "recruit", "army", "ranked", "finale"]
const DIM := Color(0.02, 0.03, 0.06, 0.62)
const PAD := 6.0
const CAPTION_SECONDS := 4.0

var main: Node
var _chapter := ""
var _steps: Array = []
var _i := -1
var _state := {}             # per-step memory (baselines)
var _tip := ""               # a one-off tip being shown
var _time := 0.0
var _step_time := 0.0
var _root: Control
var _blockers: Array[ColorRect] = []
var _ring: Control
var _bubble: PanelContainer
var _text: Label
var _action: Button
var _skip: Button
var _caption: PanelContainer
var _caption_text: Label
var _target_rect := Rect2()


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIKit.make_theme()
	add_child(_root)
	for _k in 4:
		var b := ColorRect.new()
		b.color = DIM
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		_root.add_child(b)
		_blockers.append(b)
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.draw.connect(_draw_ring)
	_root.add_child(_ring)

	# The guide speaks on a scrap of parchment.
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", FantasySkin.parchment_box(20.0))
	_root.add_child(_bubble)
	var v := UIKit.vbox(10)
	_bubble.add_child(v)
	_text = UIKit.label("", 19, FantasySkin.INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(300, 0)
	v.add_child(_text)
	var row := UIKit.hbox(10)
	v.add_child(row)
	_skip = UIKit.button("Skip tutorial", skip_all)
	_skip.flat = true
	_skip.add_theme_font_size_override("font_size", 12)
	_skip.add_theme_color_override("font_color", FantasySkin.INK_DIM)
	_skip.add_theme_color_override("font_hover_color", FantasySkin.INK)
	row.add_child(_skip)
	row.add_child(UIKit.spacer())
	_action = UIKit.accent_button("OK", _on_action, 16)
	_action.custom_minimum_size = Vector2(110, 38)
	row.add_child(_action)

	_caption = PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.1, 0.11, 0.16, 0.88)
	cs.set_corner_radius_all(8)
	cs.set_content_margin_all(10)
	_caption.add_theme_stylebox_override("panel", cs)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_caption)
	_caption_text = UIKit.label("", 17, Color.WHITE)
	_caption.add_child(_caption_text)
	_hide_all()


# --- progress -------------------------------------------------------------------

func _progress() -> Dictionary:
	var t = Profile.settings.get("tutorial", null)
	return t if typeof(t) == TYPE_DICTIONARY else {}


func _save_progress(p: Dictionary) -> void:
	Profile.settings["tutorial"] = p
	Profile.save_settings()


func is_running() -> bool:
	return _chapter != "" or _tip != ""


## Called once the game is ready (signed in or playing offline). New players
## get the guided session; players who already played are left alone.
func start_if_new() -> void:
	var p := _progress()
	if p.is_empty():
		var fresh := int(Profile.data.get("wins", 0)) + int(Profile.data.get("losses", 0)) == 0 and Profile.challenges_cleared() == 0
		p = {"done": [], "off": not fresh}
		_save_progress(p)
	_resume()


## Settings → Replay tutorial.
func replay() -> void:
	_save_progress({"done": [], "off": false, "tips": []})
	_tip = ""
	_chapter = ""
	_resume()


func skip_all() -> void:
	var p := _progress()
	p["off"] = true
	_save_progress(p)
	_chapter = ""
	_tip = ""
	_hide_all()
	UIKit.toast("Tutorial skipped. Replay it any time from Settings.", UIKit.TEXT_DIM)


func _resume() -> void:
	var p := _progress()
	if bool(p.get("off", false)):
		return
	for c in CHAIN:
		if not (p.get("done", []) as Array).has(c):
			_start_chapter(c)
			return


func _start_chapter(id: String) -> void:
	_chapter = id
	_steps = _chapter_steps(id)
	_i = -1
	_next_step()


func _next_step() -> void:
	_i += 1
	_state = {}
	_step_time = 0.0
	if _i >= _steps.size():
		var p := _progress()
		var done: Array = p.get("done", [])
		if not done.has(_chapter):
			done.append(_chapter)
		p["done"] = done
		_save_progress(p)
		_chapter = ""
		_hide_all()
		_resume()
		return
	var step: Dictionary = _steps[_i]
	if step.has("enter"):
		(step["enter"] as Callable).call()
	Audio.play_sfx("toggle", -10.0)


func _on_action() -> void:
	if _tip != "":
		var p := _progress()
		var tips: Array = p.get("tips", [])
		tips.append(_tip)
		p["tips"] = tips
		_save_progress(p)
		_tip = ""
		_hide_all()
		return
	if _chapter == "" or _i < 0 or _i >= _steps.size():
		return
	var step: Dictionary = _steps[_i]
	if step.has("action"):
		(step["action"] as Callable).call()
	_next_step()


# --- per frame --------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_step_time += delta
	if main == null or _blocked():
		_hide_all()
		return
	if _chapter == "" and _tip == "":
		_check_tips()
		if _tip == "":
			_hide_all()
			return
	var step: Dictionary = _current_step()
	if _chapter != "" and step.has("done") and (step["done"] as Callable).call():
		_next_step()
		return
	_layout(step)


func _current_step() -> Dictionary:
	if _tip != "":
		return TIPS[_tip]
	return _steps[_i] if _i >= 0 and _i < _steps.size() else {}


## Never on top of the sign-in screen, the update prompt or a draft match.
func _blocked() -> bool:
	if main.login_layer and main.login_layer.get_child_count() > 0:
		return true
	if main.draft_layer and main.draft_layer.visible:
		return true
	return false


func _hide_all() -> void:
	for b in _blockers:
		b.visible = false
	_bubble.visible = false
	_caption.visible = false
	_target_rect = Rect2()
	_ring.queue_redraw()


func _layout(step: Dictionary) -> void:
	var view := _root.get_viewport_rect().size
	if bool(step.get("hide", false)):
		for b in _blockers:
			b.visible = false
		_bubble.visible = false
		_target_rect = Rect2()
		_ring.queue_redraw()
		_caption.visible = str(step.get("text", "")) != "" and _step_time < CAPTION_SECONDS
		if _caption.visible:
			_caption_text.text = step["text"]
			_caption.reset_size()
			_caption.position = Vector2((view.x - _caption.size.x) * 0.5, 70.0)
			_caption.modulate.a = clampf((CAPTION_SECONDS - _step_time) * 2.0, 0.0, 1.0)
		return
	_caption.visible = false
	var target := str(step.get("target", ""))
	var rect := _find_target(target) if target != "" else Rect2()
	_text.text = str(step.get("text", ""))
	_action.visible = step.has("button")
	_action.text = str(step.get("button", "OK"))
	_skip.visible = _tip == ""
	_bubble.visible = true
	_bubble.reset_size()
	var bs := _bubble.size
	if rect.has_area():
		_target_rect = rect.grow(PAD)
		_place_blockers(_target_rect, view)
		# The bubble sits below the target, or above it when there's no room.
		var pos := Vector2(_target_rect.get_center().x - bs.x * 0.5, _target_rect.end.y + 26.0)
		if pos.y + bs.y > view.y - 8.0:
			pos.y = _target_rect.position.y - bs.y - 26.0
		if pos.y < 8.0:
			# Neither fits (a big target): beside it.
			pos.y = clampf(_target_rect.get_center().y - bs.y * 0.5, 8.0, view.y - bs.y - 8.0)
			pos.x = _target_rect.end.x + 20.0 if _target_rect.end.x + 20.0 + bs.x < view.x else _target_rect.position.x - bs.x - 20.0
		_bubble.position = Vector2(clampf(pos.x, 8.0, view.x - bs.x - 8.0), clampf(pos.y, 8.0, view.y - bs.y - 8.0))
	elif target == "":
		# A message on its own: dim everything, bubble in the middle.
		_target_rect = Rect2()
		_place_blockers(Rect2(view * 0.5, Vector2.ZERO), view)
		_bubble.position = (view - bs) * 0.5
	else:
		# The target isn't on screen yet (loading, scrolling): don't block,
		# just keep the words visible at the bottom.
		_target_rect = Rect2()
		for b in _blockers:
			b.visible = false
		_bubble.position = Vector2((view.x - bs.x) * 0.5, view.y - bs.y - 16.0)
	_ring.queue_redraw()


## Four dark panels around the hole; clicks on them are swallowed, clicks in
## the hole reach the game underneath.
func _place_blockers(hole: Rect2, view: Vector2) -> void:
	var rects := [
		Rect2(0, 0, view.x, maxf(0.0, hole.position.y)),
		Rect2(0, hole.end.y, view.x, maxf(0.0, view.y - hole.end.y)),
		Rect2(0, hole.position.y, maxf(0.0, hole.position.x), hole.size.y),
		Rect2(hole.end.x, hole.position.y, maxf(0.0, view.x - hole.end.x), hole.size.y),
	]
	for k in 4:
		_blockers[k].visible = true
		_blockers[k].position = rects[k].position
		_blockers[k].size = rects[k].size


func _draw_ring() -> void:
	if not _target_rect.has_area():
		return
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	var r := _target_rect.grow(2.0 + pulse * 5.0)
	_ring.draw_rect(r, Color(UIKit.ACCENT, 0.55 + 0.45 * pulse), false, 3.0)
	# A bouncing arrow pointing at the target from the bubble's side.
	var below := _bubble.visible and _bubble.position.y > _target_rect.end.y
	var tip := Vector2(_target_rect.get_center().x, (_target_rect.end.y + 4.0) if below else (_target_rect.position.y - 4.0))
	var off := (6.0 + 6.0 * pulse) * (1.0 if below else -1.0)
	var a := tip + Vector2(0, off)
	var pts := PackedVector2Array([a, a + Vector2(-9, 12 * signf(off)), a + Vector2(9, 12 * signf(off))])
	_ring.draw_colored_polygon(pts, UIKit.ACCENT)


func _find_target(id: String) -> Rect2:
	if id.begins_with("tab:"):
		if not main.menu_layer.visible:
			return Rect2()
		# Sub-tabs (0.9.9): point at its top tab first, then at the sub-tab.
		var c: Control = main.find_tab(id.substr(4))
		if c == null:
			return Rect2()
		var m := c.get_parent() as TabContainer
		var tabs: TabContainer = main.tabs
		var bar := tabs.get_tab_bar()
		var i := m.get_index()
		if tabs.current_tab == i:
			bar = m.get_tab_bar()
			i = c.get_index()
		var r := bar.get_tab_rect(i)
		return Rect2(bar.get_global_rect().position + r.position, r.size)
	for n in get_tree().get_nodes_in_group("tut"):
		var c := n as Control
		if c == null or str(c.get_meta("tut", "")) != id or not c.is_visible_in_tree():
			continue
		if c is BaseButton and (c as BaseButton).disabled:
			continue
		var r := c.get_global_rect()
		if r.has_area() and _root.get_viewport_rect().intersects(r):
			return r
	return Rect2()


# --- conditions ---------------------------------------------------------------------

func _tab_is(name: String) -> bool:
	return main.menu_layer.visible and main.current_tab_name() == name


func _in_battle() -> bool:
	return main._battle != null


func _battle_running() -> bool:
	return main._battle != null and main._battle.view != null and main._battle.view.running


func _battle_over() -> bool:
	return main._battle != null and main._battle.sim != null and main._battle.sim.finished


func _total_levels() -> int:
	var n := 0
	for id in Profile.data["units"]:
		n += int(Profile.data["units"][id]["level"])
	return n


func _battle_tab_has_opponents() -> bool:
	var c: Control = main.find_tab("Ranked")
	return c != null and not (c.get("_opponents") as Array).is_empty()


## The usual end of a fight: press FIGHT, watch, then Continue.
func _battle_steps(continue_text: String) -> Array:
	return [
		{"target": "battle_fight", "text": "Press FIGHT!", "done": _battle_running},
		{"hide": true, "text": "Your army fights on its own. Watch!", "done": _battle_over},
		{"target": "battle_continue", "text": continue_text, "done": func(): return not _in_battle()},
	]


func _chapter_steps(id: String) -> Array:
	match id:
		"first_battle":
			return [
				{"target": "", "text": "Welcome, commander!\nYour legion fights on its own. Let's watch it.", "button": "Show me",
					"action": func(): main.start_tutorial_battle()},
				{"hide": true, "done": _in_battle},
			] + _battle_steps("Victory! Battles earn gold.")
		"level_up":
			return [
				{"target": "tab:Collection", "text": "Spend gold to make units stronger.", "done": func(): return _tab_is("Collection")},
				{"target": "level_up", "text": "Level up!", "enter": func(): _state["levels"] = _total_levels(),
					"done": func(): return _total_levels() > int(_state.get("levels", 0))},
			]
		"recruit":
			return [
				{"target": "tab:Expeditions", "text": "Find new units on expeditions.", "done": func(): return _tab_is("Expeditions")},
				{"target": "explore", "text": "Send your scouts.", "done": func(): return Profile.has_pending_choice()},
				{"hide": true, "done": func(): return not Profile.has_pending_choice()},
			]
		"army":
			return [
				{"target": "tab:Army", "text": "Put your new recruit to work.", "done": func(): return _tab_is("Army")},
				{"target": "auto_build", "text": "Build your strongest army.", "enter": func(): _state["army"] = JSON.stringify(Profile.data["army"]),
					"done": func(): return JSON.stringify(Profile.data["army"]) != str(_state.get("army", ""))},
				{"target": "army_columns", "text": "Front line, middle, back line: drag squads to choose where they fight.", "button": "Got it"},
			]
		"ranked":
			return [
				{"target": "tab:Ranked", "text": "Now fight other commanders' armies.", "done": func(): return _tab_is("Ranked")},
				{"target": "find_opponents", "text": "Find opponents.", "done": _battle_tab_has_opponents},
				{"target": "attack", "text": "Easy ones come first.", "done": _in_battle},
			] + _battle_steps("Ranked wins raise your rating, which unlocks new regions, and Challenges at %d." % ProfileLogic.CHALLENGES_RATING)
		"challenges":
			return [
				{"target": "tab:Challenges", "text": "Challenges: set battles with big rewards.", "done": func(): return _tab_is("Challenges")},
				{"target": "challenge_fight", "text": "Take one on.", "done": _in_battle},
			] + _battle_steps("Win to claim the reward. Lost? Grow stronger and come back.")
		"finale":
			return [
				{"target": "tab:Legion Draft", "text": "That's the loop: fight, upgrade, recruit.\nLegion Draft: play live against others. Good luck!", "button": "Let's go"},
			]
	return []


# --- one-off tips -----------------------------------------------------------------

## Shown the first time a feature opens, after the guided session.
var TIPS := {
	"trinkets": {"target": "trinket_hunt", "text": "Trinkets: gear for your units, 2 slots each. Hunt for them here.", "button": "Got it"},
	"draft": {"target": "draft_quick", "text": "Legion Draft: buy units in a shop each round and battle up to 7 other players.", "button": "Got it"},
	"leaderboard": {"target": "", "text": "The top commanders by rating. Win ranked battles to climb.", "button": "Got it"},
	"challenges": {"target": "challenge_fight", "text": "Challenges: set battles against named bosses. Win one for a big first-clear reward.", "button": "Got it"},
}


func _check_tips() -> void:
	var p := _progress()
	if bool(p.get("off", false)) or (p.get("done", []) as Array).size() < CHAIN.size():
		return
	var seen: Array = p.get("tips", [])
	var want := ""
	if _tab_is("Trinket Hunts") and _find_target("trinket_hunt").has_area():
		want = "trinkets"
	elif _tab_is("Legion Draft"):
		want = "draft"
	elif _tab_is("Leaderboard"):
		want = "leaderboard"
	elif _tab_is("Challenges"):
		want = "challenges"
	if want != "" and not seen.has(want):
		_tip = want
