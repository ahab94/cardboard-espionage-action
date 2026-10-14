extends Node2D
## On-screen controls for touch screens (phones and tablets, including the
## browser version): a virtual joystick on the left, a big HIDE button on the
## right, and a pause button. They press the same input actions as the
## keyboard (move_*, hide, menu), so the rest of the game doesn't care where
## input came from.
##
## Touch basics in Godot: every finger gets an index. InputEventScreenTouch
## fires when a finger lands or lifts, InputEventScreenDrag while it moves.
## We remember which finger owns the joystick and which owns the HIDE button,
## so both thumbs work at once. Any other tap is reported through `tapped`
## (used for menus and "tap to continue").

signal tapped(position: Vector2)

const STICK_RADIUS := 72.0
const KNOB_RADIUS := 32.0
const DEADZONE := 0.18
const BUTTON_RADIUS := 64.0
const CYAN := Color("46d6ff")
const CARDBOARD := Color("c49a5a")

var playing := false   # set by the game: joystick and HIDE only work during a mission

var stick_center := Vector2.ZERO
var hide_center := Vector2.ZERO
var pause_rect := Rect2()

var _stick_finger := -1
var _hide_finger := -1
var _knob := Vector2.ZERO   # knob offset from the stick centre


## Places the controls for this screen size. `band_top` is where the bottom
## area reserved for controls starts.
func layout(screen: Vector2, band_top: float, pause_pos: Vector2) -> void:
	var y := (band_top + screen.y) * 0.5 if screen.y - band_top > STICK_RADIUS * 2.2 \
			else screen.y - STICK_RADIUS - 36.0
	stick_center = Vector2(STICK_RADIUS + 36.0, y)
	hide_center = Vector2(screen.x - BUTTON_RADIUS - 44.0, y)
	pause_rect = Rect2(pause_pos, Vector2(40, 34))
	queue_redraw()


func release_all() -> void:
	_stick_finger = -1
	_hide_finger = -1
	_knob = Vector2.ZERO
	_apply(Vector2.ZERO)
	Input.action_release("hide")
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			if pause_rect.grow(14).has_point(p):
				_tap_action("menu")
			elif playing and _stick_finger == -1 and p.distance_to(stick_center) < STICK_RADIUS * 1.9:
				_stick_finger = event.index
				_drag_stick(p)
			elif playing and _hide_finger == -1 and p.distance_to(hide_center) < BUTTON_RADIUS * 1.5:
				_hide_finger = event.index
				Input.action_press("hide")
				queue_redraw()
			else:
				tapped.emit(p)
		elif event.index == _stick_finger:
			_stick_finger = -1
			_knob = Vector2.ZERO
			_apply(Vector2.ZERO)
			queue_redraw()
		elif event.index == _hide_finger:
			_hide_finger = -1
			Input.action_release("hide")
			queue_redraw()
	elif event is InputEventScreenDrag and event.index == _stick_finger:
		_drag_stick(event.position)


func _drag_stick(p: Vector2) -> void:
	_knob = (p - stick_center).limit_length(STICK_RADIUS)
	var v := _knob / STICK_RADIUS
	_apply(v if v.length() >= DEADZONE else Vector2.ZERO)
	queue_redraw()


## Analog input: a small push presses the move actions gently, so the box creeps.
func _apply(v: Vector2) -> void:
	_press("move_right", maxf(v.x, 0.0))
	_press("move_left", maxf(-v.x, 0.0))
	_press("move_down", maxf(v.y, 0.0))
	_press("move_up", maxf(-v.y, 0.0))


func _press(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _tap_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _draw() -> void:
	# Pause button: always available.
	draw_rect(pause_rect, Color(0.03, 0.09, 0.15, 0.7))
	draw_rect(pause_rect, Color(CYAN, 0.8), false, 1.5)
	var c := pause_rect.get_center()
	draw_rect(Rect2(c + Vector2(-8, -9), Vector2(5, 18)), CYAN)
	draw_rect(Rect2(c + Vector2(3, -9), Vector2(5, 18)), CYAN)
	if not playing:
		return
	# Joystick.
	draw_circle(stick_center, STICK_RADIUS, Color(0.03, 0.09, 0.15, 0.45))
	draw_arc(stick_center, STICK_RADIUS, 0, TAU, 48, Color(CYAN, 0.55), 2.0)
	draw_circle(stick_center + _knob, KNOB_RADIUS, Color(CYAN, 0.55 if _stick_finger >= 0 else 0.35))
	draw_arc(stick_center + _knob, KNOB_RADIUS, 0, TAU, 32, CYAN, 2.0)
	# HIDE button: a cardboard-coloured disc that lights up while held.
	var held := _hide_finger >= 0
	draw_circle(hide_center, BUTTON_RADIUS, Color(CARDBOARD, 0.85 if held else 0.45))
	draw_arc(hide_center, BUTTON_RADIUS, 0, TAU, 48, Color("e2c58f"), 2.5)
	var box := Rect2(hide_center + Vector2(-17, -30), Vector2(34, 26))
	draw_rect(box, Color("8a6534"))
	draw_rect(Rect2(box.position + Vector2(14, 0), Vector2(6, 26)), Color("e2c58f"))
	draw_string(ThemeDB.fallback_font, hide_center + Vector2(-40, 26), "HIDE",
			HORIZONTAL_ALIGNMENT_CENTER, 80, 22, Color.WHITE)
