class_name BattleView
extends Node2D
## Renders a BattleSim. One MultiMeshInstance2D per unit type keeps 1000+
## sprites to a handful of draw calls. Positions are interpolated between
## simulation ticks so movement stays smooth at any frame rate.

signal battle_finished(winner: int)

const TEAM_TINT := [Color(0.88, 0.94, 1.0), Color(1.0, 0.86, 0.84)]
const TEAM_BASE := [Color(0.25, 0.55, 1.0, 0.55), Color(1.0, 0.3, 0.25, 0.55)]
const CORPSE_TICKS := 80
const PROJECTILE_TEX := ["", "arrow", "stone", "javelin", "magic_bolt", "fire"]
const PROJECTILE_SCALE := [1.0, 0.7, 0.45, 0.8, 0.55, 0.7]
const MAX_STEPS_PER_FRAME := 8

var sim: BattleSim
var speed_mult := 1.0
var running := false
var _acc := 0.0
var _time := 0.0
var _unit_mm: Array[MultiMesh] = []
var _kind_units: Array = []          # kind -> PackedInt32Array of unit indexes
var _kind_scale: PackedFloat32Array = PackedFloat32Array()
var _base_mm: MultiMesh
var _proj_mm: Array[MultiMesh] = []
var _fx: Array = []                  # [type, x, y, radius, age, life]
var _camera: Camera2D
var _dragging := false
var _finished_emitted := false
var _big_units := PackedInt32Array()
var _overlay: Node2D                 # draws FX and health bars above the sprites


func setup(battle: BattleSim) -> void:
	sim = battle
	_build_background(String(BattleMaps.get_map(sim.map_id)["tile"]))
	_build_obstacle_layer()
	_build_team_bases()
	_build_unit_meshes()
	_build_projectile_meshes()
	_overlay = Node2D.new()
	_overlay.z_index = 5
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_camera = Camera2D.new()
	add_child(_camera)
	fit_camera()
	for i in sim.n:
		if sim.max_hp[i] >= 500.0:
			_big_units.append(i)
	_sync_visuals(0.0)


func fit_camera() -> void:
	var vp := get_viewport_rect().size
	var z := minf(vp.x / (sim.map_w * 0.92), vp.y / (sim.map_h * 0.92))
	_camera.zoom = Vector2(z, z)
	_camera.position = Vector2(sim.map_w, sim.map_h) * 0.5


static func make_quad(size: float) -> ArrayMesh:
	var h := size * 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _new_multimesh(count: int, size: float) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = make_quad(size)
	mm.instance_count = count
	return mm


func _build_background(tile: String) -> void:
	var bg := Sprite2D.new()
	bg.texture = GameData.tile_texture(tile)
	bg.centered = false
	bg.region_enabled = true
	bg.region_rect = Rect2(0, 0, sim.map_w, sim.map_h)
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.modulate = Color(0.75, 0.75, 0.75)
	add_child(bg)


func _build_obstacle_layer() -> void:
	var obstacles := BattleMaps.obstacles(sim.map_id)
	if obstacles.is_empty():
		return
	# 1) soft shadows, 2) textured fills (Polygon2D tiles the texture), 3) outlines + decor.
	var shadows := Node2D.new()
	shadows.draw.connect(_draw_obstacle_shadows.bind(shadows, obstacles))
	add_child(shadows)
	for o in obstacles:
		var info: Dictionary = BattleMaps.OBSTACLE_KINDS[o[0]]
		if info["style"] == "sprite":
			continue
		var c := Vector2(float(o[1]), float(o[2]))
		var r: float = o[3]
		var poly := Polygon2D.new()
		var pts := PackedVector2Array()
		var segs := clampi(int(r / 4.0), 16, 64)
		for k in segs:
			var a := TAU * float(k) / float(segs)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		poly.polygon = pts
		poly.texture = BattleMaps.terrain_texture(info["texture"])
		poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(poly)
	var decor := Node2D.new()
	decor.draw.connect(_draw_obstacle_decor.bind(decor, obstacles))
	add_child(decor)
	_add_obstacle_sprites(obstacles)


func _draw_obstacle_shadows(layer: Node2D, obstacles: Array) -> void:
	for o in obstacles:
		var r: float = o[3]
		layer.draw_circle(Vector2(float(o[1]), float(o[2])) + Vector2(4, 7), r, Color(0, 0, 0, 0.35))


## Outlines on top of the fills.
func _draw_obstacle_decor(layer: Node2D, obstacles: Array) -> void:
	for o in obstacles:
		var info: Dictionary = BattleMaps.OBSTACLE_KINDS[o[0]]
		var c := Vector2(float(o[1]), float(o[2]))
		var r: float = o[3]
		if info["style"] == "sprite":
			layer.draw_circle(c, r, Color(0, 0, 0, 0.25))
		else:
			layer.draw_arc(c, r, 0.0, TAU, clampi(int(r / 4.0), 16, 64), Color(0, 0, 0, 0.55), 4.0)


## Trees (groves) and pillars/statues are Sprite2D nodes.
func _add_obstacle_sprites(obstacles: Array) -> void:
	var tree_textures := [BattleMaps.terrain_texture("tree_green"), BattleMaps.terrain_texture("tree_yellow"), BattleMaps.terrain_texture("tree_red")]
	for o in obstacles:
		var info: Dictionary = BattleMaps.OBSTACLE_KINDS[o[0]]
		var c := Vector2(float(o[1]), float(o[2]))
		var r: float = o[3]
		if info["style"] == "sprite":
			var sp := Sprite2D.new()
			sp.texture = BattleMaps.terrain_texture(info["texture"])
			sp.scale = Vector2.ONE * (r * 2.6 / 32.0)
			sp.position = c - Vector2(0, r * 0.2)
			add_child(sp)
		elif info["style"] == "grove":
			var trng := RandomNumberGenerator.new()
			trng.seed = int(c.x) * 7919 + int(c.y) * 104729
			for _t in maxi(1, int(r * r / 1500.0)):
				var ang := trng.randf() * TAU
				var dist := sqrt(trng.randf()) * r * 0.78
				var sp := Sprite2D.new()
				sp.texture = tree_textures[trng.randi_range(0, 2)]
				sp.scale = Vector2.ONE * (trng.randf_range(40.0, 56.0) / 32.0)
				sp.position = c + Vector2(cos(ang), sin(ang)) * dist - Vector2(0, 8)
				add_child(sp)


func _build_team_bases() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var dx := (float(x) - 15.5) / 15.5
			var dy := (float(y) - 15.5) / 15.5
			var d := dx * dx + dy * dy
			var a: float = clampf((1.0 - d) * 3.0, 0.0, 1.0) if d < 1.0 else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var node := MultiMeshInstance2D.new()
	node.texture = ImageTexture.create_from_image(img)
	_base_mm = _new_multimesh(sim.n, 1.0)
	node.multimesh = _base_mm
	add_child(node)


func _build_unit_meshes() -> void:
	_kind_units.resize(sim.unit_ids.size())
	for k in sim.unit_ids.size():
		_kind_units[k] = PackedInt32Array()
	for i in sim.n:
		var list: PackedInt32Array = _kind_units[sim.kind[i]]
		list.append(i)
		_kind_units[sim.kind[i]] = list
	# Draw small units first so big ones sit on top.
	var order: Array = range(sim.unit_ids.size())
	order.sort_custom(func(a, b): return float(GameData.UNITS[sim.unit_ids[a]]["scale"]) < float(GameData.UNITS[sim.unit_ids[b]]["scale"]))
	_unit_mm.resize(sim.unit_ids.size())
	_kind_scale.resize(sim.unit_ids.size())
	for k in order:
		var uid: String = sim.unit_ids[k]
		var node := MultiMeshInstance2D.new()
		node.texture = GameData.unit_texture(uid)
		var mm := _new_multimesh((_kind_units[k] as PackedInt32Array).size(), 32.0)
		node.multimesh = mm
		_unit_mm[k] = mm
		_kind_scale[k] = float(GameData.UNITS[uid]["scale"])
		if bool(GameData.UNITS[uid]["flying"]):
			node.z_index = 2
		add_child(node)


func _build_projectile_meshes() -> void:
	_proj_mm.resize(PROJECTILE_TEX.size())
	for k in range(1, PROJECTILE_TEX.size()):
		var node := MultiMeshInstance2D.new()
		node.texture = load("res://assets/sprites/fx/%s.png" % PROJECTILE_TEX[k])
		node.z_index = 3
		var mm := _new_multimesh(64, 32.0)
		mm.visible_instance_count = 0
		node.multimesh = mm
		_proj_mm[k] = mm
		add_child(node)


# --- frame update -----------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if running and not sim.finished:
		_acc += delta * speed_mult
		var steps := 0
		while _acc >= BattleSim.DT and not sim.finished and steps < MAX_STEPS_PER_FRAME:
			sim.step()
			_handle_events(sim.drain_events())
			_acc -= BattleSim.DT
			steps += 1
		if steps >= MAX_STEPS_PER_FRAME:
			_acc = 0.0
	var alpha := clampf(_acc / BattleSim.DT, 0.0, 1.0)
	if sim.finished:
		alpha = 1.0
	_sync_visuals(alpha)
	_update_fx(delta)
	_overlay.queue_redraw()
	if sim.finished and not _finished_emitted:
		_finished_emitted = true
		battle_finished.emit(sim.winner)


func skip_to_end() -> void:
	sim.run_to_end()
	_acc = 0.0


func _handle_events(evs: Array) -> void:
	var melee := 0
	var shots := 0
	var magic := 0
	var deaths := 0
	for e in evs:
		match int(e[0]):
			BattleSim.Ev.MELEE_HIT:
				melee += 1
			BattleSim.Ev.SHOT:
				if int(e[3]) >= 4:
					magic += 1
				else:
					shots += 1
			BattleSim.Ev.BLAST:
				_fx.append([0, e[1], e[2], e[3], 0.0, 0.35])
			BattleSim.Ev.HEAL:
				_fx.append([1, e[1], e[2], 10.0, 0.0, 0.5])
			BattleSim.Ev.DIE:
				deaths += 1
	if speed_mult > 2.0 and randf() < 0.5:
		return
	if melee > 0:
		Audio.play_sfx("melee", -10.0 + minf(6.0, float(melee) * 0.3))
	if shots > 0:
		Audio.play_sfx("shoot", -14.0)
	if magic > 0:
		Audio.play_sfx("magic", -10.0)
	if deaths > 0:
		Audio.play_sfx("die", -12.0 + minf(6.0, float(deaths)))


func _sync_visuals(alpha: float) -> void:
	var t := sim.tick
	for k in _unit_mm.size():
		var mm: MultiMesh = _unit_mm[k]
		var list: PackedInt32Array = _kind_units[k]
		var base_scale: float = _kind_scale[k]
		for idx in list.size():
			var i := list[idx]
			var x := lerpf(sim.prev_x[i], sim.px[i], alpha)
			var y := lerpf(sim.prev_y[i], sim.py[i], alpha)
			if sim.alive[i] == 1:
				# Most source sprites face left, so the left-side army is mirrored.
				var face := -1.0 if sim.team[i] == 0 else 1.0
				var toward := 1.0 if sim.team[i] == 0 else -1.0
				var moving := absf(sim.px[i] - sim.prev_x[i]) + absf(sim.py[i] - sim.prev_y[i]) > 0.05
				var bob := 0.0
				if moving:
					bob = absf(sin(_time * 12.0 + float(i))) * -2.0
				var lunge := 0.0
				var since_attack := t - sim.attack_tick[i]
				if since_attack < 3:
					lunge = (3.0 - float(since_attack)) * 1.5
				var fly := -10.0 if sim.flying[i] == 1 else 0.0
				var xf := Transform2D(0.0, Vector2(base_scale * face, base_scale), 0.0, Vector2(x + lunge * toward, y + bob + fly - 6.0 * base_scale))
				mm.set_instance_transform_2d(idx, xf)
				var c: Color = TEAM_TINT[sim.team[i]]
				if t - sim.hit_tick[i] < 2:
					c = Color(1.0, 0.45, 0.45)
				mm.set_instance_color(idx, c)
				_base_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(sim.radius[i] * 2.4, sim.radius[i] * 1.2), 0.0, Vector2(x, y + 2.0)))
				_base_mm.set_instance_color(i, TEAM_BASE[sim.team[i]])
			else:
				var age := t - sim.death_tick[i]
				if age < CORPSE_TICKS:
					var fade := 1.0 - float(age) / float(CORPSE_TICKS)
					var rot := PI * 0.5 * (-1.0 if sim.team[i] == 1 else 1.0)
					mm.set_instance_transform_2d(idx, Transform2D(rot, Vector2(base_scale, base_scale), 0.0, Vector2(x, y)))
					mm.set_instance_color(idx, Color(0.45, 0.3, 0.3, 0.8 * fade))
				else:
					mm.set_instance_transform_2d(idx, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2(-1000, -1000)))
				_base_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2(-1000, -1000)))
	_sync_projectiles()


func _sync_projectiles() -> void:
	var counts := PackedInt32Array()
	counts.resize(PROJECTILE_TEX.size())
	counts.fill(0)
	for p in sim.pr_count:
		if sim.pr_alive[p] == 1:
			counts[sim.pr_kind[p]] += 1
	for k in range(1, PROJECTILE_TEX.size()):
		var mm: MultiMesh = _proj_mm[k]
		if counts[k] > mm.instance_count:
			mm.instance_count = maxi(counts[k], mm.instance_count * 2)
		mm.visible_instance_count = counts[k]
	counts.fill(0)
	for p in sim.pr_count:
		if sim.pr_alive[p] == 0:
			continue
		var k := sim.pr_kind[p]
		var mm: MultiMesh = _proj_mm[k]
		var c := counts[k]
		var s: float = PROJECTILE_SCALE[k]
		mm.set_instance_transform_2d(c, Transform2D(sim.pr_ang[p], Vector2(s, s), 0.0, Vector2(sim.pr_x[p], sim.pr_y[p])))
		mm.set_instance_color(c, Color.WHITE)
		counts[k] = c + 1


func _update_fx(delta: float) -> void:
	var keep: Array = []
	for f in _fx:
		f[4] = float(f[4]) + delta * speed_mult
		if float(f[4]) < float(f[5]):
			keep.append(f)
	_fx = keep


func _draw_overlay() -> void:
	# Arena border
	_overlay.draw_rect(Rect2(0, 0, sim.map_w, sim.map_h), Color(0, 0, 0, 0.6), false, 6.0)
	_overlay.draw_line(Vector2(sim.map_w * 0.5, 0), Vector2(sim.map_w * 0.5, sim.map_h), Color(1, 1, 1, 0.06), 2.0)
	for f in _fx:
		var k := float(f[4]) / float(f[5])
		var pos := Vector2(float(f[1]), float(f[2]))
		if int(f[0]) == 0:
			var r := float(f[3]) * (0.4 + 0.6 * k)
			_overlay.draw_circle(pos, r, Color(1.0, 0.55, 0.15, 0.35 * (1.0 - k)))
			_overlay.draw_arc(pos, r, 0.0, TAU, 24, Color(1.0, 0.85, 0.4, 0.8 * (1.0 - k)), 2.0)
		else:
			var y := pos.y - 10.0 - 14.0 * k
			_overlay.draw_line(Vector2(pos.x - 4, y), Vector2(pos.x + 4, y), Color(0.4, 1.0, 0.4, 1.0 - k), 2.0)
			_overlay.draw_line(Vector2(pos.x, y - 4), Vector2(pos.x, y + 4), Color(0.4, 1.0, 0.4, 1.0 - k), 2.0)
	# Health bars for big units
	for i in _big_units:
		if sim.alive[i] == 0:
			continue
		var w := sim.radius[i] * 2.0
		var scale_px: float = 32.0 * float(GameData.UNITS[sim.unit_ids[sim.kind[i]]]["scale"])
		var x := sim.px[i] - w * 0.5
		var y := sim.py[i] - scale_px * 0.5 - 14.0 - (10.0 if sim.flying[i] == 1 else 0.0)
		var ratio := sim.hp[i] / sim.max_hp[i]
		_overlay.draw_rect(Rect2(x, y, w, 4), Color(0, 0, 0, 0.7))
		_overlay.draw_rect(Rect2(x, y, w * ratio, 4), Color(0.3, 0.9, 0.3) if sim.team[i] == 0 else Color(0.95, 0.3, 0.3))


# --- camera controls --------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(1.15, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(1.0 / 1.15, mb.position)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		_camera.position -= (event as InputEventMouseMotion).relative / _camera.zoom
	elif event is InputEventMagnifyGesture:
		_zoom_at((event as InputEventMagnifyGesture).factor, get_viewport_rect().size * 0.5)
	elif event is InputEventPanGesture:
		_camera.position += (event as InputEventPanGesture).delta * 8.0 / _camera.zoom


func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var vp_center := get_viewport_rect().size * 0.5
	var world := _camera.position + (screen_pos - vp_center) / _camera.zoom
	var z := clampf(_camera.zoom.x * factor, 0.2, 4.0)
	_camera.zoom = Vector2(z, z)
	_camera.position = world - (screen_pos - vp_center) / _camera.zoom
