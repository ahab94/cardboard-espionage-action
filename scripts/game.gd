extends Node2D
## Runs the VR missions: builds a level from its map, tracks how close the
## enemies are to spotting the box, and handles the alert, mission complete
## and mission select flow.

const Levels := preload("res://scripts/levels.gd")
const Maze := preload("res://scripts/maze.gd")
const PlayerScript := preload("res://scripts/player.gd")
const SecurityCamera := preload("res://scripts/security_camera.gd")
const Soldier := preload("res://scripts/soldier.gd")
const Drone := preload("res://scripts/drone.gd")
const Laser := preload("res://scripts/laser.gd")
const Keycard := preload("res://scripts/keycard.gd")
const Goal := preload("res://scripts/goal.gd")
const MissionMenu := preload("res://scripts/mission_menu.gd")
const Autopilot := preload("res://scripts/autopilot.gd")

const SCREEN := Vector2(1152, 648)
const HUD_HEIGHT := 48.0
const FOOTER_HEIGHT := 24.0
const SAVE_PATH := "user://progress.cfg"

# Detection is a 0..1 meter rather than instant game over: it fills fast while
# something sees you moving, slowly while you sit still in the box, and drains
# when you're out of sight. That gives the "freeze as a box" move its value.
# Hazards (live lasers, bumping into a guard) skip the meter and trip the alarm at once.
const SPOT_RATE_MOVING := 3.0    # ~0.33s in view -> alert
const SPOT_RATE_HIDDEN := 0.3    # ~3.3s in view as a still box -> alert
const DETECTION_DECAY := 0.6
const ALERT_RESTART_DELAY := 1.6

enum State { PLAYING, ALERT, COMPLETE, FINISHED, MENU }

var save_enabled := true   # tests turn this off so they never touch the real save
var level_index := 0
var state := State.PLAYING
var detection := 0.0
var elapsed := 0.0
var unlocked := 1
var best_times := {}

var world: Node2D
var maze
var player
var goal: Node2D
var keycard: Node2D = null
var cameras: Array = []
var soldiers: Array = []
var drones: Array = []
var lasers: Array = []
var watchers: Array = []   # anything with can_see_any(points): cameras, soldiers, drones
var hazards: Array = []    # anything with touches(player): lasers, soldiers

var _alert_timer := 0.0
var _alerts := 0          # alerts this session, for autopilot reports
var _run_time := 0.0
var _ending := false
var _resume_state := State.PLAYING
var _toast_timer := 0.0
var _title_label: Label
var _time_label: Label
var _key_label: Label
var _brief_label: Label
var _toast: Label
var _meter_fill: ColorRect
var _banner: Label
var _menu


func _ready() -> void:
	RenderingServer.set_default_clear_color(Maze.WALL_FILL)
	_setup_input()
	_build_hud()
	if _dev_flag("autopilot"):
		save_enabled = false  # demo runs must not touch the player's save
	_load_progress()
	var dev_level := _dev_arg("level", "")
	if dev_level != "":
		load_level(clampi(int(dev_level), 0, Levels.LEVELS.size() - 1))
	else:
		load_level(mini(unlocked, Levels.LEVELS.size()) - 1)
		open_menu()
	if _dev_flag("autopilot"):
		var bot = Autopilot.new()
		bot.game = self
		bot.trace = _dev_flag("trace")
		add_child(bot)
	var shot := _dev_arg("screenshot", "")
	if shot != "":
		_save_screenshot_and_quit(shot)


func load_level(index: int) -> void:
	level_index = index
	if world:
		remove_child(world)
		world.queue_free()
	for list in [cameras, soldiers, drones, lasers, watchers, hazards]:
		list.clear()
	keycard = null
	state = State.PLAYING
	detection = 0.0
	elapsed = 0.0
	if _menu:
		_menu.visible = false

	var data: Dictionary = Levels.LEVELS[index]
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	move_child(world, 0)  # keep the HUD drawn on top

	maze = Maze.new()
	world.add_child(maze)
	maze.build(data["map"])
	var room := Vector2(SCREEN.x, SCREEN.y - HUD_HEIGHT - FOOTER_HEIGHT)
	world.position = Vector2(0, HUD_HEIGHT) + ((room - maze.pixel_size()) * 0.5).floor()

	goal = Goal.new()
	goal.position = maze.tile_center(maze.find_all("G")[0])
	world.add_child(goal)
	for c in maze.find_all("K"):
		keycard = Keycard.new()
		keycard.position = maze.tile_center(c)
		world.add_child(keycard)

	_spawn_lasers(data.get("lasers", {}))
	_spawn_cameras(data.get("turret", {}))
	for route in data.get("soldiers", []):
		var soldier = Soldier.new()
		soldier.setup(_route_points(route))
		world.add_child(soldier)
		soldiers.append(soldier)
	watchers.append_array(soldiers)
	hazards.append_array(soldiers)

	player = PlayerScript.new()
	player.position = maze.tile_center(maze.find_all("P")[0])
	world.add_child(player)

	# Drones go last so they draw over everything, the box included.
	for route in data.get("drones", []):
		var drone = Drone.new()
		drone.setup(_route_points(route))
		world.add_child(drone)
		drones.append(drone)
	watchers.append_array(drones)

	_title_label.text = data["name"]
	_brief_label.text = data.get("brief", "")
	_key_label.visible = keycard != null
	_key_label.add_theme_color_override("font_color", Color("4a6577"))
	_banner.visible = false


func _spawn_cameras(turret: Dictionary) -> void:
	for ch in Maze.CAMERA_DIRS:
		var dir: Vector2 = Maze.CAMERA_DIRS[ch]
		for c in maze.find_all(ch):
			var cam = SecurityCamera.new()
			# Sit just outside the wall face so rays don't start inside the wall.
			cam.position = maze.tile_center(c) + dir * (Maze.TILE * 0.5 + 1.0)
			cam.facing = dir.angle()
			cam.phase = c.x * 1.7 + c.y * 0.9
			world.add_child(cam)
			cameras.append(cam)
	for c in maze.find_all(Maze.TURRET):
		var cam = SecurityCamera.new()
		cam.position = maze.tile_center(c)
		cam.spin_speed = turret.get("speed", 0.9)
		cam.view_range = turret.get("range", 5.5) * Maze.TILE
		cam.fov = deg_to_rad(45.0)
		cam.phase = c.x * 1.3
		world.add_child(cam)
		cameras.append(cam)
	watchers.append_array(cameras)


func _spawn_lasers(timing: Dictionary) -> void:
	var beams := []
	for run in maze.runs("-", true):
		var y: float = (run[0].y + 0.5) * Maze.TILE
		beams.append([Vector2(run[0].x * Maze.TILE, y), Vector2((run[1].x + 1) * Maze.TILE, y)])
	for run in maze.runs("|", false):
		var x: float = (run[0].x + 0.5) * Maze.TILE
		beams.append([Vector2(x, run[0].y * Maze.TILE), Vector2(x, (run[1].y + 1) * Maze.TILE)])
	for i in beams.size():
		var laser = Laser.new()
		laser.from = beams[i][0]
		laser.to = beams[i][1]
		laser.on_time = timing.get("on", 1.5)
		laser.off_time = timing.get("off", 1.5)
		laser.phase = -i * timing.get("stagger", 0.5)
		world.add_child(laser)
		lasers.append(laser)
	hazards.append_array(lasers)


func _route_points(route: Array) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for p in route:
		points.append(maze.tile_center(Vector2i(p[0], p[1])))
	return points


func _physics_process(delta: float) -> void:
	_run_time += delta
	var timeout := float(_dev_arg("timeout", "0"))
	if timeout > 0.0 and _run_time > timeout:
		_end_run("timeout")
	match state:
		State.PLAYING:
			_update_stealth(delta)
		State.ALERT:
			_alert_timer -= delta
			if _alert_timer <= 0.0:
				load_level(level_index)
	_update_hud(delta)


func _update_stealth(delta: float) -> void:
	elapsed += delta
	var points: Array[Vector2] = player.sight_points()
	var hidden: bool = player.hidden_in_box
	var seen := false
	for w in watchers:
		var sees: bool = w.can_see_any(points)
		if sees:
			seen = true
			if not hidden and w.has_method("notice"):
				w.notice(player.global_position)
		w.heat = detection if sees else maxf(w.heat - delta * 2.0, 0.0)

	if seen:
		var rate := SPOT_RATE_HIDDEN if hidden else SPOT_RATE_MOVING
		detection = minf(detection + rate * delta, 1.0)
	else:
		detection = maxf(detection - DETECTION_DECAY * delta, 0.0)
	for h in hazards:
		if h.touches(player):
			detection = 1.0
	player.alert_mark = "?" if seen else ""

	if keycard and not keycard.collected and player.position.distance_to(keycard.position) < Maze.TILE * 0.6:
		keycard.collected = true
		maze.open_doors()
		_key_label.add_theme_color_override("font_color", Color("ffd84a"))
		_show_toast("KEYCARD ACQUIRED  -  vault door unlocked")

	if detection >= 1.0:
		_raise_alert()
	elif player.position.distance_to(goal.position) < Maze.TILE * 0.5:
		_complete_mission()


func _raise_alert() -> void:
	state = State.ALERT
	_alerts += 1
	_alert_timer = ALERT_RESTART_DELAY
	player.controllable = false
	player.alert_mark = "!"
	for w in watchers:
		w.alarmed = true
	_show_banner("!  ALERT  !", Color("ff3344"))


func _complete_mission() -> void:
	player.controllable = false
	player.alert_mark = ""
	var record := ""
	if not best_times.has(level_index) or elapsed < best_times[level_index]:
		best_times[level_index] = elapsed
		record = "   NEW BEST"
	unlocked = maxi(unlocked, mini(level_index + 2, Levels.LEVELS.size()))
	_save_progress()
	var time_line := "TIME %s%s" % [_format_time(elapsed), record]
	if level_index + 1 < Levels.LEVELS.size():
		state = State.COMPLETE
		_show_banner("MISSION COMPLETE\n%s\n\npress ENTER for next mission" % time_line, Color("4dff9a"))
	else:
		state = State.FINISHED
		_show_banner("ALL VR MISSIONS COMPLETE\n%s\n\npress ENTER for mission select" % time_line, Color("4dff9a"))
	if _dev_flag("exit-on-end"):
		_end_run("complete", 2.0)


func open_menu() -> void:
	if state == State.MENU:
		return
	_resume_state = state
	state = State.MENU
	player.controllable = false
	_menu.open(Levels.LEVELS, unlocked, best_times, level_index)


func _close_menu() -> void:
	_menu.visible = false
	state = _resume_state
	player.controllable = state == State.PLAYING


func _unhandled_input(event: InputEvent) -> void:
	if state == State.MENU:
		if event.is_action_pressed("move_up"):
			_menu.move(-1)
		elif event.is_action_pressed("move_down"):
			_menu.move(1)
		elif event.is_action_pressed("confirm") and _menu.is_unlocked(_menu.selected):
			load_level.call_deferred(_menu.selected)
		elif event.is_action_pressed("menu"):
			_close_menu()
		return
	if event.is_action_pressed("menu"):
		open_menu()
	elif event.is_action_pressed("restart"):
		load_level.call_deferred(level_index)
	elif event.is_action_pressed("confirm"):
		if state == State.COMPLETE:
			load_level.call_deferred(level_index + 1)
		elif state == State.FINISHED:
			open_menu()


# --- Save data -------------------------------------------------------------

func _load_progress() -> void:
	if not save_enabled:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	unlocked = clampi(cfg.get_value("progress", "unlocked", 1), 1, Levels.LEVELS.size())
	for i in Levels.LEVELS.size():
		if cfg.has_section_key("best", str(i)):
			best_times[i] = float(cfg.get_value("best", str(i)))


func _save_progress() -> void:
	if not save_enabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	for i in best_times:
		cfg.set_value("best", str(i), best_times[i])
	cfg.save(SAVE_PATH)


# --- HUD -----------------------------------------------------------------

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	var bar := ColorRect.new()
	bar.color = Color("071827")
	bar.size = Vector2(SCREEN.x, HUD_HEIGHT)
	hud.add_child(bar)
	var rule := ColorRect.new()
	rule.color = Color("46d6ff")
	rule.position = Vector2(0, HUD_HEIGHT - 2)
	rule.size = Vector2(SCREEN.x, 2)
	hud.add_child(rule)
	var footer := ColorRect.new()
	footer.color = Color("071827")
	footer.position = Vector2(0, SCREEN.y - FOOTER_HEIGHT)
	footer.size = Vector2(SCREEN.x, FOOTER_HEIGHT)
	hud.add_child(footer)

	_title_label = _make_label(hud, Vector2(20, 10), 22, Color("46d6ff"))
	_time_label = _make_label(hud, Vector2(470, 10), 22, Color.WHITE)
	_key_label = _make_label(hud, Vector2(660, 15), 14, Color("4a6577"))
	_key_label.text = "KEYCARD"

	_make_label(hud, Vector2(800, 14), 14, Color("8fb8cc")).text = "DETECTION"
	var meter_bg := ColorRect.new()
	meter_bg.color = Color("10293a")
	meter_bg.position = Vector2(900, 16)
	meter_bg.size = Vector2(230, 16)
	hud.add_child(meter_bg)
	_meter_fill = ColorRect.new()
	_meter_fill.position = meter_bg.position
	_meter_fill.size = Vector2(0, 16)
	hud.add_child(_meter_fill)

	_brief_label = _make_label(hud, Vector2(20, SCREEN.y - 21), 13, Color("8fb8cc"))
	var controls := _make_label(hud, Vector2(SCREEN.x - 520, SCREEN.y - 21), 13, Color("4a6577"))
	controls.size.x = 500
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.text = "WASD move   SPACE hide   R restart   ESC missions"

	_toast = _make_label(hud, Vector2(0, HUD_HEIGHT + 10), 20, Color("ffd84a"))
	_toast.size.x = SCREEN.x
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color("030a12"))

	_banner = Label.new()
	_banner.size = SCREEN
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 44)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.add_theme_color_override("font_outline_color", Color("030a12"))
	_banner.visible = false
	hud.add_child(_banner)

	_menu = MissionMenu.new()
	_menu.visible = false
	hud.add_child(_menu)


func _make_label(parent: Node, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_timer = 2.5


func _update_hud(delta: float) -> void:
	_time_label.text = "TIME " + _format_time(elapsed)
	_meter_fill.size.x = 230.0 * detection
	_meter_fill.color = Color("4dff9a").lerp(Color("ffd84a"), minf(detection * 2.0, 1.0)) \
			if detection < 0.5 else Color("ffd84a").lerp(Color("ff3344"), (detection - 0.5) * 2.0)
	_toast_timer = maxf(_toast_timer - delta, 0.0)
	_toast.modulate.a = clampf(_toast_timer, 0.0, 1.0)


func _format_time(t: float) -> String:
	return MissionMenu.format_time(t)


# --- Input & dev flags ---------------------------------------------------

# Actions are registered in code so the whole control scheme lives in one
# place and project.godot stays readable.
func _setup_input() -> void:
	var bindings := {
		"move_left": [KEY_LEFT, KEY_A],
		"move_right": [KEY_RIGHT, KEY_D],
		"move_up": [KEY_UP, KEY_W],
		"move_down": [KEY_DOWN, KEY_S],
		"hide": [KEY_SPACE, KEY_SHIFT],
		"restart": [KEY_R],
		"confirm": [KEY_ENTER, KEY_KP_ENTER],
		"menu": [KEY_ESCAPE],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


# Dev flags go after `--`, e.g. `godot --path . -- --level=2 --screenshot=/tmp/l3.png`
# starts on the third mission (skipping the menu), saves a PNG after a second
# of play, and quits.
func _dev_flag(key: String) -> bool:
	return ("--" + key) in OS.get_cmdline_user_args()


## Prints a one-line result for scripts that run missions unattended, then quits.
func _end_run(result: String, linger := 0.0) -> void:
	if _ending:
		return
	_ending = true
	print("RESULT level=%d %s time=%.1f alerts=%d" % [level_index + 1, result, elapsed, _alerts])
	await get_tree().create_timer(linger).timeout
	get_tree().quit(0 if result == "complete" else 1)


func _dev_arg(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.trim_prefix("--%s=" % key)
	return fallback


func _save_screenshot_and_quit(path: String) -> void:
	await get_tree().create_timer(float(_dev_arg("wait", "1.0"))).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
