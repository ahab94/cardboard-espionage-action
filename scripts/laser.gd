extends Node2D
## A laser tripwire between two emitters. It cycles: on for `on_time`, off for
## `off_time`. It flickers just before switching on so the player can read it.
## Touching a live beam trips the alarm instantly, even while hiding in the box.

const WARN_TIME := 0.4
const RED := Color(1.0, 0.25, 0.32)

var from := Vector2.ZERO   # world-local endpoints
var to := Vector2.ZERO
var on_time := 1.5
var off_time := 1.5
var phase := 0.0

var _time := 0.0


func is_active() -> bool:
	return active_after(0.0)


## Whether the beam will be on `dt` seconds from now. Cycles are fixed, so this is exact.
func active_after(dt: float) -> bool:
	return fposmod(_time + dt + phase, on_time + off_time) < on_time


## Seconds until the beam next switches on (0 while it's on).
func time_until_on() -> float:
	if is_active():
		return 0.0
	var cycle := on_time + off_time
	return cycle - fposmod(_time + phase, cycle)


func touches(player: Node2D) -> bool:
	if not is_active():
		return false
	var box: Rect2 = player.bounds()
	var a := to_global(from)
	var beam := Rect2(a, to_global(to) - a).abs().grow(2.0)
	return box.intersects(beam)


func _physics_process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var active := is_active()
	var cycle := on_time + off_time
	var until_on := cycle - fposmod(_time + phase, cycle)
	if active:
		draw_line(from, to, Color(RED, 0.25), 9.0)
		draw_line(from, to, RED, 2.5)
	elif until_on < WARN_TIME and int(_time * 20.0) % 2 == 0:
		draw_line(from, to, Color(RED, 0.6), 1.0)
	else:
		draw_dashed_line(from, to, Color(RED, 0.18), 1.0, 6.0)
	var emitter := RED if active else Color("5a1a20")
	for p in [from, to]:
		draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), emitter)
