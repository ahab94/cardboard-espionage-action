extends Node2D
## Runs the Virtual Ops missions: builds a level from its map, tracks how close the
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
const TouchControls := preload("res://scripts/touch_controls.gd")
const Autopilot := preload("res://scripts/autopilot.gd")
const Sound := preload("res://scripts/sound.gd")

# Portrait mode (dev flag --portrait) renders 9:16 for phones and Shorts: a
# taller HUD, and a camera that follows the box, zoomed in.
const PORTRAIT_ZOOM := 1.5
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

var screen := Vector2(1152, 648)   # layout size; window scaling stretches it to fit
var hud_height := 48.0
var footer_height := 24.0   # in portrait on a touch screen this band holds the controls
var touch := false          # on-screen controls (phones/tablets, or --touch to test)
var portrait := false
var camera: Camera2D = null   # only in portrait mode
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

var sound   # music and sound effects (scripts/sound.gd)
# Edge detection for sound cues: we play a sound when something *changes*.
var _was_seen := false
var _was_hidden := false
var _step_timer := 0.0
var _laser_was_on: Array[bool] = []
var _resume_state := State.PLAYING
var _toast_timer := 0.0
var _title_label: Label
var _time_label: Label
var _key_label: Label
var _brief_label: Label
var _toast: Label
var _meter_fill: ColorRect
var _meter_width := 230.0
var _banner: Label
var _menu
var _touch = null   # scripts/touch_controls.gd when touch is on


func _ready() -> void:
	RenderingServer.set_default_clear_color(Maze.WALL_FILL)
	touch = DisplayServer.is_touchscreen_available() or _dev_flag("touch")
	if _dev_flag("touch"):
		Input.emulate_touch_from_mouse = true  # lets a mouse stand in for a finger when testing
	# A phone held upright gets the portrait layout automatically.
	var win := DisplayServer.window_get_size()
	if _dev_flag("portrait") or (touch and win.y > win.x and not _dev_flag("landscape")):
		_enter_portrait()
	if touch and portrait:
		footer_height = 230.0
	_setup_input()
	_build_hud()
	sound = Sound.new()
	add_child(sound)
	sound.music_on = not _dev_flag("no-music")  # recordings for videos add their own music
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
		bot.reckless = _dev_flag("reckless")
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
	if portrait:
		camera = Camera2D.new()
		camera.zoom = Vector2(PORTRAIT_ZOOM, PORTRAIT_ZOOM)
		world.add_child(camera)
		camera.make_current()
	else:
		var room := Vector2(screen.x, screen.y - hud_height - footer_height)
		world.position = Vector2(0, hud_height) + ((room - maze.pixel_size()) * 0.5).floor()

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
	_update_camera(0.0)  # snap to the box at the start

	# Drones go last so they draw over everything, the box included.
	for route in data.get("drones", []):
		var drone = Drone.new()
		drone.setup(_route_points(route))
		world.add_child(drone)
		drones.append(drone)
	watchers.append_array(drones)

	_laser_was_on.clear()
	for laser in lasers:
		_laser_was_on.append(laser.is_active())
	_was_seen = false
	_was_hidden = false
	sound.set_drone_count(drones.size())
	sound.play_music("mission")

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
	_update_audio(delta)
	_update_camera(delta)
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
	_play_cues(seen, hidden, delta)

	if keycard and not keycard.collected and player.position.distance_to(keycard.position) < Maze.TILE * 0.6:
		keycard.collected = true
		maze.open_doors()
		sound.play("keycard")
		_log_event("keycard")
		get_tree().create_timer(0.35).timeout.connect(sound.play.bind("door", -2.0))
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
	sound.play_music("")
	sound.play("alert")
	_log_event("alert")
	_show_banner("!  ALERT  !", Color("ff3344"))


func _complete_mission() -> void:
	player.controllable = false
	player.alert_mark = ""
	sound.play_music("")
	sound.play("complete")
	_log_event("complete")
	var record := ""
	if not best_times.has(level_index) or elapsed < best_times[level_index]:
		best_times[level_index] = elapsed
		record = "   NEW BEST"
	unlocked = maxi(unlocked, mini(level_index + 2, Levels.LEVELS.size()))
	_save_progress()
	var time_line := "TIME %s%s" % [_format_time(elapsed), record]
	if level_index + 1 < Levels.LEVELS.size():
		state = State.COMPLETE
		_show_banner("MISSION COMPLETE\n%s\n\n" + _prompt("for next mission") % time_line, Color("4dff9a"))
	else:
		state = State.FINISHED
		_show_banner("ALL VIRTUAL OPS COMPLETE\n%s\n\n" + _prompt("for mission select") % time_line, Color("4dff9a"))
	if _dev_flag("exit-on-end"):
		_end_run("complete", 2.0)


func open_menu() -> void:
	if state == State.MENU:
		return
	_resume_state = state
	state = State.MENU
	player.controllable = false
	sound.play_music("menu")
	_menu.open(Levels.LEVELS, unlocked, best_times, level_index)


func _close_menu() -> void:
	_menu.visible = false
	state = _resume_state
	player.controllable = state == State.PLAYING
	if state == State.PLAYING:
		sound.play_music("mission")


func _unhandled_input(event: InputEvent) -> void:
	if state == State.MENU:
		if event.is_action_pressed("move_up"):
			_menu.move(-1)
			sound.play("menu_move")
		elif event.is_action_pressed("move_down"):
			_menu.move(1)
			sound.play("menu_move")
		elif event.is_action_pressed("confirm") and _menu.is_unlocked(_menu.selected):
			sound.play("menu_select")
			load_level.call_deferred(_menu.selected)
		elif event.is_action_pressed("menu"):
			_close_menu()
		return
	if event.is_action_pressed("music"):
		_show_toast("MUSIC ON" if sound.toggle_music() else "MUSIC OFF")
	elif event.is_action_pressed("menu"):
		open_menu()
	elif event.is_action_pressed("restart"):
		load_level.call_deferred(level_index)
	elif event.is_action_pressed("confirm"):
		if state == State.COMPLETE:
			load_level.call_deferred(level_index + 1)
		elif state == State.FINISHED:
			open_menu()


# --- Sound cues ------------------------------------------------------------

func _play_cues(seen: bool, hidden: bool, delta: float) -> void:
	if seen and not _was_seen:
		sound.play("suspicious", -4.0)
		_log_event("spotted")
	if hidden and not _was_hidden:
		sound.play("hide", -3.0, 0.05)
		_log_event("hide")
	_was_seen = seen
	_was_hidden = hidden

	# Quiet cardboard shuffles while walking: felt more than heard.
	_step_timer -= delta
	if player.velocity.length() > 10.0 and _step_timer <= 0.0:
		sound.play("step", -18.0, 0.12)
		_step_timer = 0.3

	# Lasers zap as they switch on; nearer beams are louder, far ones silent.
	for i in lasers.size():
		var on: bool = lasers[i].is_active()
		if on and not _laser_was_on[i]:
			var mid: Vector2 = (lasers[i].from + lasers[i].to) * 0.5
			var near: float = 1.0 - player.position.distance_to(mid) / (5.0 * Maze.TILE)
			if near > 0.0:
				sound.play("laser", linear_to_db(near) - 6.0, 0.05)
		_laser_was_on[i] = on


func _update_audio(delta: float) -> void:
	# The tension layer rises with detection and lingers a little after.
	var danger := detection * 1.6 if state == State.PLAYING else 0.0
	sound.set_tension(danger, delta)
	for i in drones.size():
		var d: float = player.position.distance_to(drones[i].position)
		var loud := clampf(1.0 - d / (7.0 * Maze.TILE), 0.0, 1.0)
		sound.set_drone_volume(i, loud * loud * 0.7 if state != State.MENU else 0.0)


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
	bar.size = Vector2(screen.x, hud_height)
	hud.add_child(bar)
	var rule := ColorRect.new()
	rule.color = Color("46d6ff")
	rule.position = Vector2(0, hud_height - 2)
	rule.size = Vector2(screen.x, 2)
	hud.add_child(rule)
	var footer := ColorRect.new()
	footer.color = Color("071827")
	footer.position = Vector2(0, screen.y - footer_height)
	footer.size = Vector2(screen.x, footer_height)
	hud.add_child(footer)

	# Landscape: one row. Portrait: title on top, time and meter below it.
	var row2 := 44.0 if portrait else 0.0
	_title_label = _make_label(hud, Vector2(64 if touch else 20, 10), 22, Color("46d6ff"))
	_time_label = _make_label(hud, Vector2(20 if portrait else 470, 10 + row2), 22, Color.WHITE)
	_key_label = _make_label(hud, Vector2(196 if portrait else 660, 15 + row2), 14, Color("4a6577"))
	_key_label.text = "KEYCARD"

	_meter_width = 150.0 if portrait else 230.0
	var meter_x := screen.x - _meter_width - 20
	_make_label(hud, Vector2(meter_x - 100, 14 + row2), 14, Color("8fb8cc")).text = "DETECTION"
	var meter_bg := ColorRect.new()
	meter_bg.color = Color("10293a")
	meter_bg.position = Vector2(meter_x, 16 + row2)
	meter_bg.size = Vector2(_meter_width, 16)
	hud.add_child(meter_bg)
	_meter_fill = ColorRect.new()
	_meter_fill.position = meter_bg.position
	_meter_fill.size = Vector2(0, 16)
	hud.add_child(_meter_fill)

	_brief_label = _make_label(hud, Vector2(20, screen.y - footer_height + 3), 13, Color("8fb8cc"))
	var controls := _make_label(hud, Vector2(screen.x - 520, screen.y - 21), 13, Color("4a6577"))
	controls.size.x = 500
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.text = "WASD move   SPACE hide   R restart   M music   ESC missions"
	controls.visible = not portrait and not touch  # no room beside the briefing; no keyboard on a phone

	_toast = _make_label(hud, Vector2(0, hud_height + 10), 20, Color("ffd84a"))
	_toast.size.x = screen.x
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color("030a12"))

	if touch:
		_touch = TouchControls.new()
		hud.add_child(_touch)
		_touch.layout(screen, screen.y - footer_height + 24.0, Vector2(12, 7))
		_touch.tapped.connect(_on_tap)

	_banner = Label.new()
	_banner.size = screen
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 36 if portrait else 44)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.add_theme_color_override("font_outline_color", Color("030a12"))
	_banner.visible = false
	hud.add_child(_banner)

	_menu = MissionMenu.new()
	_menu.screen_size = screen
	_menu.touch = touch
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
	if _touch:
		var on := state == State.PLAYING
		if on != _touch.playing:
			_touch.playing = on
			if not on:
				_touch.release_all()  # never leave a finger "stuck" on a control
			_touch.queue_redraw()
	_time_label.text = "TIME " + _format_time(elapsed)
	_meter_fill.size.x = _meter_width * detection
	_meter_fill.color = Color("4dff9a").lerp(Color("ffd84a"), minf(detection * 2.0, 1.0)) \
			if detection < 0.5 else Color("ffd84a").lerp(Color("ff3344"), (detection - 0.5) * 2.0)
	_toast_timer = maxf(_toast_timer - delta, 0.0)
	_toast.modulate.a = clampf(_toast_timer, 0.0, 1.0)


func _prompt(what: String) -> String:
	return ("tap " if touch else "press ENTER ") + what


## Taps that didn't land on a control: pick missions and dismiss banners.
func _on_tap(pos: Vector2) -> void:
	match state:
		State.MENU:
			var i: int = _menu.row_at(pos)
			if i >= 0 and _menu.is_unlocked(i):
				sound.play("menu_select")
				load_level.call_deferred(i)
			elif i >= 0:
				_menu.select(i)
				sound.play("menu_move")
		State.COMPLETE:
			load_level.call_deferred(level_index + 1)
		State.FINISHED:
			open_menu()


func _format_time(t: float) -> String:
	return MissionMenu.format_time(t)


# --- Portrait mode ---------------------------------------------------------

func _enter_portrait() -> void:
	portrait = true
	screen = Vector2(648, 1152)
	hud_height = 84.0
	# Phones are often taller than 9:16. Keep the width and grow the layout
	# to the screen's real shape, so there are no black bars top and bottom.
	var win := DisplayServer.window_get_size()
	if touch and win.x > 0 and float(win.y) / win.x > screen.y / screen.x:
		screen.y = round(screen.x * float(win.y) / win.x)
	# Godot scales this layout size up to the real window (e.g. 1080x1920).
	get_window().content_scale_size = Vector2i(screen)
	if _dev_flag("portrait") and Engine.get_write_movie_path() == "" and OS.get_name() != "Web":
		DisplayServer.window_set_size(Vector2i(540, 960))


## Keeps the box in view: follows it, but never shows past the map's edges.
## The visible area is what's left between the HUD and the footer.
func _update_camera(delta: float) -> void:
	if camera == null or player == null:
		return
	var zoom := PORTRAIT_ZOOM
	var view := Vector2(screen.x, screen.y - hud_height - footer_height) / zoom
	# The usable area's centre sits below the screen centre by this much (in world units).
	var shift := ((hud_height - footer_height) * 0.5) / zoom
	var map: Vector2 = maze.pixel_size()
	var want := Vector2.ZERO
	for axis in 2:
		var half := view[axis] * 0.5
		want[axis] = map[axis] * 0.5 if map[axis] <= view[axis] \
				else clampf(player.position[axis], half, map[axis] - half)
	want.y -= shift
	var blend := 1.0 if delta == 0.0 else 1.0 - exp(-6.0 * delta)
	camera.position = camera.position.lerp(want, blend)


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
		"music": [KEY_M],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		# A low deadzone on movement lets a half-pushed joystick creep slowly.
		InputMap.add_action(action, 0.2 if action.begins_with("move_") else 0.5)
		for key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


# Dev flags go after `--`, e.g. `godot --path . -- --level=2 --screenshot=/tmp/l3.png`
# starts on the third mission (skipping the menu), saves a PNG after a second
# of play, and quits.
## With --log-events, prints "EVENT <seconds since launch> <name>" so video
## tooling can find moments (spotted, hide, alert, keycard, complete) in a
## recording of the same deterministic run.
func _log_event(what: String) -> void:
	if _dev_flag("log-events"):
		print("EVENT %.2f %s %.2f" % [_run_time, what, detection])


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
