extends Node2D
## A hovering drone that flies its route straight over walls. It looks
## straight down, so it sees whatever is inside its round spotlight and walls
## don't block it.

const SPEED := 75.0
const CALM := Color(0.45, 1.0, 0.72)
const SUSPICIOUS := Color(1.0, 0.82, 0.2)
const ALARM := Color(1.0, 0.2, 0.26)

var radius := 1.3 * 48.0
var waypoints: Array[Vector2] = []
var heat := 0.0
var alarmed := false

var _target := 0
var _time := 0.0


func setup(points: Array[Vector2]) -> void:
	waypoints = points
	position = points[0]
	_target = 1 % points.size()
	z_index = 2  # flies above walls and everything on the floor


func can_see_any(points: Array[Vector2]) -> bool:
	for p in points:
		if p.distance_to(global_position) <= radius:
			return true
	return false


## Positions every `dt` seconds for `steps` samples. Routes are fixed, so this is exact.
func forecast(steps: int, dt: float) -> Array:
	var pos := position
	var target := _target
	var out := []
	for k in steps:
		out.append(pos)
		var r := _advance(pos, target, dt)
		pos = r[0]
		target = r[1]
	return out


func _physics_process(delta: float) -> void:
	_time += delta
	if not alarmed:
		var r := _advance(position, _target, delta)
		position = r[0]
		_target = r[1]
	queue_redraw()


func _advance(pos: Vector2, target: int, delta: float) -> Array:
	var budget := SPEED * delta
	while waypoints.size() > 1 and budget > 0.0:
		var to := waypoints[target] - pos
		if to.length() <= budget:
			budget -= to.length()
			pos = waypoints[target]
			target = (target + 1) % waypoints.size()
		else:
			pos += to.normalized() * budget
			budget = 0.0
	return [pos, target]


func _draw() -> void:
	var t := ALARM if alarmed else CALM.lerp(SUSPICIOUS, heat)
	draw_circle(Vector2.ZERO, radius, Color(t, 0.14))
	draw_circle(Vector2.ZERO, radius * 0.55, Color(t, 0.10))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color(t, 0.6), 1.5)

	# The body hovers a little above its spotlight.
	var body := Vector2(0, -8 + sin(_time * 3.0) * 1.5)
	for corner in [Vector2(-13, -13), Vector2(13, -13), Vector2(-13, 13), Vector2(13, 13)]:
		var c: Vector2 = body + corner
		draw_line(body, c, Color("8fa3b0"), 3.0)
		draw_circle(c, 7.0, Color(0.6, 0.9, 1.0, 0.18))
		var blade := Vector2.from_angle(_time * 30.0) * 7.0
		draw_line(c - blade, c + blade, Color(0.8, 0.95, 1.0, 0.8), 1.5)
	draw_rect(Rect2(body - Vector2(7, 7), Vector2(14, 14)), Color("1d2b36"))
	draw_rect(Rect2(body - Vector2(7, 7), Vector2(14, 14)), Color("46d6ff"), false, 1.5)
	var blink := alarmed or fmod(_time, 0.8) < 0.4
	draw_circle(body, 3.0, ALARM if blink else Color("5a1a20"))
