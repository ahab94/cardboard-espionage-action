extends SceneTree
## Headless gameplay checks. Run: godot --headless --path . --script res://tests/game_test.gd
## Static: every map is well-formed and finishable, and patrol routes are valid.
## Live:   cameras, hiding, alert, goal, lasers, soldiers, drones and keycards
##         behave as designed, and no mission spots the player at the start.

const Levels := preload("res://scripts/levels.gd")
const Maze := preload("res://scripts/maze.gd")
const TILES := ["#", ".", "P", "G", ">", "<", "^", "v", "@", "-", "|", "K", "D"]
const PASSABLE := [".", "P", "G", "K", "-", "|"]   # lasers pulse, so they're passable in time

var game
var failures := 0


func _initialize() -> void:
	_check_maps()
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.save_enabled = false
	root.add_child(game)
	_run.call_deferred()


func _run() -> void:
	await _frames(2)
	await _test_camera_and_hiding()
	await _test_alert_and_goal()
	await _test_laser()
	await _test_soldier()
	await _test_drone()
	await _test_keycard()
	await _test_spawns_are_safe()
	print("GAME OK" if failures == 0 else "GAME FAILED (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _test_camera_and_hiding() -> void:
	# VR-01: one camera at the top looking down. Freeze its sweep and park the
	# box two tiles in front of it.
	game.load_level(0)
	await _frames(2)
	var cam = game.cameras[0]
	cam.sweep = 0.0
	game.player.position = cam.position + Vector2.from_angle(cam.facing) * Maze.TILE * 2.0
	Input.action_press("hide")
	await _frames(10)
	_expect(cam.can_see(game.player.global_position), "camera sees box in its cone")
	_expect(game.detection > 0.0, "detection rises while seen")
	_expect(game.detection < 0.15, "hidden box fills detection slowly (got %.2f)" % game.detection)
	var mark: float = game.detection
	Input.action_release("hide")
	await _frames(10)
	_expect(game.detection - mark > 0.3, "standing in view fills detection fast")

	# Walls block sight: give the camera a full-circle view, then test a point
	# behind the divider wall vs. one in open view.
	cam.fov = TAU - 0.01
	cam.view_range = 2000.0
	var behind_wall: Vector2 = game.world.to_global(game.maze.tile_center(Vector2i(3, 3)))
	var open: Vector2 = game.world.to_global(game.maze.tile_center(Vector2i(12, 5)))
	_expect(not cam.can_see(behind_wall), "wall blocks camera sight")
	_expect(cam.can_see(open), "camera sees open floor")


func _test_alert_and_goal() -> void:
	await _frames(40)
	_expect(game.state == game.State.ALERT, "staying in view raises the alert")
	game.load_level(0)
	await _frames(2)
	game.player.position = game.goal.position
	await _frames(3)
	_expect(game.state == game.State.COMPLETE, "reaching the goal completes the mission")


func _test_laser() -> void:
	game.load_level(_level_with_tile("-"))
	await _frames(2)
	var laser = game.lasers[0]
	laser.phase = 0.0
	laser.on_time = 100.0
	game.player.position = (laser.from + laser.to) * 0.5
	Input.action_press("hide")  # hiding doesn't help against lasers
	await _frames(3)
	Input.action_release("hide")
	_expect(game.state == game.State.ALERT, "touching a live laser trips the alarm")

	game.load_level(_level_with_tile("-"))
	await _frames(2)
	laser = game.lasers[0]
	laser.phase = 0.0
	laser.on_time = 0.001
	laser.off_time = 100.0
	game.player.position = (laser.from + laser.to) * 0.5
	await _frames(3)
	_expect(game.state == game.State.PLAYING, "a laser that is off is safe to cross")


func _test_soldier() -> void:
	game.load_level(_level_with_key("soldiers"))
	await _frames(2)
	var soldier = game.soldiers[0]
	game.player.position = soldier.position
	await _frames(3)
	_expect(game.state == game.State.ALERT, "bumping into a soldier trips the alarm")

	game.load_level(_level_with_key("soldiers"))
	await _frames(2)
	soldier = game.soldiers[0]
	game.player.position = soldier.position + Vector2.from_angle(soldier.angle) * Maze.TILE * 2.0
	await _frames(5)
	_expect(soldier.is_investigating(), "a soldier who sees the box moving stops to investigate")


func _test_drone() -> void:
	game.load_level(_level_with_key("drones"))
	await _frames(2)
	var drone = game.drones[0]
	for i in 8:
		game.player.global_position = drone.global_position
		await _frames(1)
	_expect(game.detection > 0.0, "a drone's spotlight sees the box, even over walls")


func _test_keycard() -> void:
	game.load_level(_level_with_tile("K"))
	await _frames(2)
	_expect(not game.maze.doors_open, "vault door starts locked")
	game.player.position = game.keycard.position
	await _frames(3)
	_expect(game.keycard.collected, "keycard is picked up")
	_expect(game.maze.doors_open, "taking the keycard opens the vault door")


func _test_spawns_are_safe() -> void:
	for i in Levels.LEVELS.size():
		game.load_level(i)
		await _frames(150)
		_expect(game.state == game.State.PLAYING,
				"%s: player is spotted while standing at the start" % Levels.LEVELS[i]["name"])


# --- Static map checks ---------------------------------------------------

func _check_maps() -> void:
	for level in Levels.LEVELS:
		var rows: Array = level["map"]
		var title: String = level["name"]
		var w := (rows[0] as String).length()
		_expect(w <= 24 and rows.size() <= 12, "%s is larger than 24x12" % title)
		var counts := {}
		for y in rows.size():
			var row: String = rows[y]
			_expect(row.length() == w, "%s row %d has width %d, expected %d" % [title, y, row.length(), w])
			for x in row.length():
				var ch := row[x]
				_expect(ch in TILES, "%s has unknown tile '%s'" % [title, ch])
				counts[ch] = counts.get(ch, 0) + 1
		_expect(counts.get("P", 0) == 1 and counts.get("G", 0) == 1, "%s needs exactly one P and one G" % title)
		_expect(counts.get("K", 0) <= 1, "%s has more than one keycard" % title)
		_expect(counts.get("D", 0) == 0 or counts.get("K", 0) == 1, "%s has a door but no keycard" % title)

		var start := _find(rows, "P")
		var goal := _find(rows, "G")
		if counts.get("K", 0) == 1:
			# Doors stay shut until the keycard is reached without them.
			_expect(_reachable(rows, start, _find(rows, "K"), false), "%s: keycard not reachable" % title)
			_expect(_reachable(rows, start, goal, true), "%s: goal not reachable after keycard" % title)
		else:
			_expect(_reachable(rows, start, goal, false), "%s: goal not reachable from start" % title)

		for route in level.get("soldiers", []):
			for i in route.size():
				var a := Vector2i(route[i][0], route[i][1])
				var b := Vector2i(route[(i + 1) % route.size()][0], route[(i + 1) % route.size()][1])
				_expect(a.x == b.x or a.y == b.y, "%s: soldier leg %s->%s isn't straight" % [title, a, b])
				for c in _line(a, b):
					_expect(_tile(rows, c) in PASSABLE, "%s: soldier walks through %s at %s" % [title, _tile(rows, c), c])
		for route in level.get("drones", []):
			for p in route:
				_expect(p[0] >= 0 and p[1] >= 0 and p[0] < w and p[1] < rows.size(),
						"%s: drone waypoint %s off the map" % [title, p])


func _reachable(rows: Array, from: Vector2i, to: Vector2i, doors_open: bool) -> bool:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			return true
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			var ch := _tile(rows, n)
			if seen.has(n) or not (ch in PASSABLE or (doors_open and ch == "D")):
				continue
			seen[n] = true
			queue.append(n)
	return false


func _line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var c := a
	while c != b:
		c += Vector2i(signi(b.x - c.x), signi(b.y - c.y))
		out.append(c)
	return out


func _tile(rows: Array, c: Vector2i) -> String:
	if c.y < 0 or c.y >= rows.size() or c.x < 0 or c.x >= (rows[c.y] as String).length():
		return "#"
	return rows[c.y][c.x]


func _find(rows: Array, ch: String) -> Vector2i:
	for y in rows.size():
		var x := (rows[y] as String).find(ch)
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func _level_with_tile(ch: String) -> int:
	for i in Levels.LEVELS.size():
		if _find(Levels.LEVELS[i]["map"], ch).x >= 0:
			return i
	return 0


func _level_with_key(key: String) -> int:
	for i in Levels.LEVELS.size():
		if Levels.LEVELS[i].has(key):
			return i
	return 0


# --- Helpers ---------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + what)
