extends "res://scripts/vision_cone.gd"
## A guard walking a patrol route. At each waypoint they pause and look around.
## If they spot the box moving they stop and stare at where they saw it. A box
## sitting still doesn't catch their interest, but walking into one does.

const SPEED := 65.0
const PAUSE := 1.4
const LOOK_SWING := deg_to_rad(55.0)
const INVESTIGATE_TIME := 2.5
const TOUCH_RADIUS := 24.0

var waypoints: Array[Vector2] = []   # world-local positions; the route loops back to the first

# Patrol state lives in one dictionary so the same advance() step can drive
# the real guard and also forecast where they'll be (used by the autopilot).
var _s := {"target": 0, "pause": 0.0, "heading": 0.0, "investigate": 0.0, "suspect": Vector2.ZERO}


func setup(points: Array[Vector2]) -> void:
	waypoints = points
	position = points[0]
	fov = deg_to_rad(70.0)
	view_range = 4.5 * 48.0
	_s.target = 1 % points.size()
	if points.size() > 1:
		_s.heading = (points[_s.target] - points[0]).angle()
	angle = _s.heading


## Called by the game when this soldier sees the box moving.
func notice(global_point: Vector2) -> void:
	_s.suspect = global_point
	_s.investigate = INVESTIGATE_TIME


func is_investigating() -> bool:
	return _s.investigate > 0.0


func touches(player: Node2D) -> bool:
	return global_position.distance_to(player.global_position) < TOUCH_RADIUS


## [position, angle] every `dt` seconds for `steps` samples, assuming nothing
## new catches the guard's eye. Patrols are deterministic, so this is exact.
func forecast(steps: int, dt: float) -> Array:
	var s := _s.duplicate()
	s.pos = position
	s.angle = angle
	s.global_offset = global_position - position
	var out := []
	var sub := 1.0 / 60.0
	var t := 0.0
	for k in steps:
		while t < k * dt:
			_advance(s, sub)
			t += sub
		out.append([s.pos, s.angle])
	return out


func _physics_process(delta: float) -> void:
	var s := _s
	s.pos = position
	s.angle = angle
	s.global_offset = global_position - position
	_advance(s, delta)
	position = s.pos
	angle = s.angle
	update_cone()


func _advance(s: Dictionary, delta: float) -> void:
	if alarmed or s.investigate > 0.0:
		s.investigate = maxf(s.investigate - delta, 0.0)
		var look: float = (s.suspect - (s.pos + s.global_offset)).angle()
		s.angle = rotate_toward(s.angle, look, 5.0 * delta)
	elif s.pause > 0.0:
		s.pause -= delta
		var look: float = s.heading + LOOK_SWING * sin((1.0 - s.pause / PAUSE) * TAU)
		s.angle = rotate_toward(s.angle, look, 5.0 * delta)
	elif waypoints.size() > 1:
		var to: Vector2 = waypoints[s.target] - s.pos
		var step := SPEED * delta
		if to.length() <= step:
			s.pos = waypoints[s.target]
			s.target = (s.target + 1) % waypoints.size()
			s.heading = (waypoints[s.target] - s.pos).angle()
			s.pause = PAUSE
		else:
			s.pos += to.normalized() * step
			s.heading = to.angle()
			s.angle = rotate_toward(s.angle, s.heading, 8.0 * delta)
	else:
		s.pause = PAUSE  # a one-point route is a sentry who just keeps looking around


func _draw() -> void:
	draw_cone()
	draw_set_transform(Vector2.ZERO, angle)
	var outline := ALARM if alarmed else Color("ff7a5e")
	draw_rect(Rect2(-7, -13, 14, 26), Color("3b4a3a"))          # shoulders
	draw_rect(Rect2(-7, -13, 14, 26), outline, false, 1.5)
	draw_rect(Rect2(4, 5, 17, 4), Color("1a1a1a"))              # rifle
	draw_circle(Vector2.ZERO, 8.0, Color("56664f"))              # helmet
	draw_arc(Vector2.ZERO, 8.0, 0, TAU, 20, outline, 1.5)
	draw_set_transform(Vector2.ZERO)
	var mark := "!" if alarmed else ("?" if is_investigating() else "")
	if mark != "":
		draw_string(ThemeDB.fallback_font, Vector2(-8, -20), mark,
				HORIZONTAL_ALIGNMENT_CENTER, 16, 26, ALARM if alarmed else SUSPICIOUS)
