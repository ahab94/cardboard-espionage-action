extends Node
## Demo autopilot: plays the current mission by itself, for recording demos
## and for checking that missions can be beaten.
##
## How it thinks: every enemy here runs on a schedule. Camera sweeps, guard
## patrols, drone routes and laser cycles are all predictable. So the bot
## forecasts the next ~12 seconds and searches over (tile, time) pairs for the
## quickest route on which nothing ever sees or touches it. Each step either
## moves one tile or waits one tile's worth of time. If the goal is out of
## reach within the forecast, it heads for the safe tile closest to the goal.
## It re-plans often, and if it's caught in a cone anyway it freezes in the box.
##
## Enable with the dev flag: `godot --path . -- --level=3 --autopilot`

const Maze := preload("res://scripts/maze.gd")
const WALKABLE := [".", "P", "G", "K", "-", "|"]
const HORIZON := 45          # steps of forecast (~12s)
const REPLAN_EVERY := 0.8    # seconds between re-plans
const BOX_HALF := 14.0       # half-size of the box, slightly generous
const DIRS := [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var game
var trace := false   # print decisions a few times a second (dev flag --trace)

var _step := 0.0     # seconds per step: one tile at a little under full speed
var _plan: Array[Vector2i] = []
var _plan_t0 := 0.0
var _goal := Vector2i(-1, -1)

# Forecast for the current plan, indexed by step k.
var _cam_angles := []    # per camera: Array of angles
var _soldier_fc := []    # per soldier: Array of [world-local pos, angle]
var _drone_fc := []      # per drone: Array of world-local pos
var _safe_cache := {}
var _los_cache := {}


func _physics_process(delta: float) -> void:
	var player = game.player
	player.bot_driven = true
	player.bot_move = Vector2.ZERO
	player.bot_hide = false
	if game.state != game.State.PLAYING:
		_plan.clear()
		_los_cache.clear()
		return
	if _step == 0.0:
		_step = Maze.TILE / (player.speed * 0.85)

	var t: float = game.elapsed - _plan_t0
	var due := _plan.size() < 2 or t + delta >= (_plan.size() - 1) * _step \
			or t > REPLAN_EVERY or _target_tile() != _goal
	if due and _near_tile_center(player.position):
		_replan()
		t = 0.0
	if _plan.size() < 2:
		player.bot_hide = _seen_now()
		return

	# Follow the plan on its schedule: aim where the box should be next frame.
	var tn := t + delta
	var j := mini(int(tn / _step), _plan.size() - 2)
	var f := clampf((tn - j * _step) / _step, 0.0, 1.0)
	var want: Vector2 = _center(_plan[j]).lerp(_center(_plan[j + 1]), f)
	var to: Vector2 = want - player.position
	if to.length() > 1.0:
		player.bot_move = to.normalized()
	elif _plan[j] == _plan[j + 1] and _seen_now():
		player.bot_hide = true  # the forecast was off: freeze and let the cone pass

	if trace and Engine.get_physics_frames() % 15 == 0:
		print("t=%.2f at=%s plan=%s det=%.2f hide=%s" % [game.elapsed, _tile_of(player.position),
				_plan.slice(j, j + 6), game.detection, player.bot_hide])


func _replan() -> void:
	var player = game.player
	_plan_t0 = game.elapsed
	_goal = _target_tile()
	var start := _tile_of(player.position)
	_forecast(HORIZON + 2)
	_safe_cache.clear()
	var dist := _distance_map(_goal)

	# Breadth-first over time: layer k holds every tile we can safely be on at
	# step k, with the tile we came from. The first layer with the goal wins.
	var layers := [{start: start}]
	var best := start
	var best_k := 0
	for k in range(1, HORIZON):
		var layer := {}
		for c in layers[k - 1]:
			for d in DIRS:
				var n: Vector2i = c + d
				if layer.has(n) or not _walkable(n) or not _safe_move(c, n, k - 1):
					continue
				layer[n] = c
		if layer.is_empty():
			break
		layers.append(layer)
		if layer.has(_goal):
			best = _goal
			best_k = k
			break
		for n in layer:
			if dist.get(n, INF) < dist.get(best, INF):
				best = n
				best_k = k
	_plan = [best]
	for k in range(best_k, 0, -1):
		_plan.push_front(layers[k][_plan[0]])
	# Pad with a wait so the executor always has a next step.
	if _plan.size() == 1:
		_plan.append(_plan[0])


func _forecast(steps: int) -> void:
	_cam_angles.clear()
	for cam in game.cameras:
		var angles := []
		for k in steps:
			angles.append(cam.angle_at(k * _step))
		_cam_angles.append(angles)
	_soldier_fc = game.soldiers.map(func(s): return s.forecast(steps, _step))
	_drone_fc = game.drones.map(func(d): return d.forecast(steps, _step))


## Moving from tile a (at step k) to tile b (at step k+1). The box spends the
## step between them, so check both tiles at both ends of the step.
func _safe_move(a: Vector2i, b: Vector2i, k: int) -> bool:
	if not _safe(b, k + 1):
		return false
	return a == b or (_safe(b, k) and _safe(a, k + 1))


func _safe(tile: Vector2i, k: int) -> bool:
	var key := Vector3i(tile.x, tile.y, k)
	if _safe_cache.has(key):
		return _safe_cache[key]
	var ok := _compute_safe(tile, k)
	_safe_cache[key] = ok
	return ok


func _compute_safe(tile: Vector2i, k: int) -> bool:
	var local := _center(tile)
	var g: Vector2 = game.world.to_global(local)
	var t := k * _step
	var h := BOX_HALF
	var points: Array[Vector2] = [g, g + Vector2(-h, -h), g + Vector2(h, -h), g + Vector2(-h, h), g + Vector2(h, h)]

	for laser in game.lasers:
		var a: Vector2 = laser.to_global(laser.from)
		var beam := Rect2(a, laser.to_global(laser.to) - a).abs().grow(2.0)
		if beam.intersects(Rect2(g - Vector2(24, 24), Vector2(48, 48))):
			if laser.active_after(t - 0.15) or laser.active_after(t) or laser.active_after(t + 0.2):
				return false
	for i in game.drones.size():
		if _drone_fc[i][k].distance_to(local) < game.drones[i].radius + 26.0:
			return false
	for i in game.soldiers.size():
		var s = game.soldiers[i]
		var pos: Vector2 = _soldier_fc[i][k][0]
		if pos.distance_to(local) < 1.4 * Maze.TILE:
			return false
		if _cone_sees(game.world.to_global(pos), _soldier_fc[i][k][1], s.fov + 0.15, s.view_range + 12.0, points, -1):
			return false
	for i in game.cameras.size():
		var cam = game.cameras[i]
		if _cone_sees(cam.global_position, _cam_angles[i][k], cam.fov + 0.12, cam.view_range + 8.0, points, i):
			return false
	return true


## Cone test with line of sight. Cameras never move, so their sight lines are
## cached per point (cache_id = camera index); guards' are cast fresh.
func _cone_sees(origin: Vector2, angle: float, fov: float, reach: float, points: Array[Vector2], cache_id: int) -> bool:
	for p in points:
		var to := p - origin
		if to.length() > reach or absf(angle_difference(angle, to.angle())) > fov * 0.5:
			continue
		var clear: bool
		var key := [cache_id, p]
		if cache_id >= 0 and _los_cache.has(key):
			clear = _los_cache[key]
		else:
			var query := PhysicsRayQueryParameters2D.create(origin, p, 1)
			clear = game.get_world_2d().direct_space_state.intersect_ray(query).is_empty()
			if cache_id >= 0:
				_los_cache[key] = clear
		if clear:
			return true
	return false


func _seen_now() -> bool:
	var points: Array[Vector2] = game.player.sight_points()
	for w in game.watchers:
		if w.can_see_any(points):
			return true
	return false


## Steps from every tile to `goal`, ignoring enemies: the "how close am I" score.
func _distance_map(goal: Vector2i) -> Dictionary:
	var dist := {goal: 0}
	var queue: Array[Vector2i] = [goal]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in DIRS.slice(1):
			var n: Vector2i = c + d
			if not dist.has(n) and _walkable(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	return dist


func _target_tile() -> Vector2i:
	if game.keycard and not game.keycard.collected:
		return _tile_of(game.keycard.position)
	return _tile_of(game.goal.position)


func _walkable(c: Vector2i) -> bool:
	var ch: String = game.maze.char_at(c)
	return ch in WALKABLE or (ch == "D" and game.maze.doors_open)


func _near_tile_center(pos: Vector2) -> bool:
	return pos.distance_to(_center(_tile_of(pos))) < 6.0 or _plan.size() < 2


func _center(c: Vector2i) -> Vector2:
	return game.maze.tile_center(c)


func _tile_of(pos: Vector2) -> Vector2i:
	return Vector2i((pos / Maze.TILE).floor())
