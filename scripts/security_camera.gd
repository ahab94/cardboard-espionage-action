extends "res://scripts/vision_cone.gd"
## A security camera. Wall cameras sweep back and forth around `facing`.
## A turret (spin_speed != 0) sits on a pillar and turns a full circle forever.

var facing := 0.0                   # centre of the sweep, radians
var sweep := deg_to_rad(40.0)       # swings this far either side of facing
var period := 5.0                   # seconds for a full back-and-forth
var phase := 0.0                    # offsets cameras so they don't move in lockstep
var spin_speed := 0.0               # radians/sec; non-zero makes this a turret

var _time := 0.0


func _ready() -> void:
	_aim()


func _physics_process(delta: float) -> void:
	_time += delta
	_aim()
	update_cone()


func _aim() -> void:
	angle = angle_at(0.0)


## Where the camera will be pointing `dt` seconds from now. Sweeps are pure
## functions of time, so the future is exactly predictable (the autopilot uses this).
func angle_at(dt: float) -> float:
	var t := _time + dt
	if spin_speed != 0.0:
		return facing + phase + spin_speed * t
	return facing + sweep * sin(TAU * t / period + phase)


func can_see_after(points: Array[Vector2], dt: float) -> bool:
	var now := angle
	angle = angle_at(dt)
	var seen := can_see_any(points)
	angle = now
	return seen


func _draw() -> void:
	draw_cone()
	var blink := alarmed or fmod(_time, 1.0) < 0.5
	if spin_speed != 0.0:
		# Turret dome on top of its pillar.
		draw_circle(Vector2.ZERO, 15.0, Color("1d2b36"))
		draw_arc(Vector2.ZERO, 15.0, 0, TAU, 32, Color("46d6ff"), 2.0)
		draw_set_transform(Vector2.ZERO, angle)
		draw_rect(Rect2(4, -4, 14, 8), Color("2c3e4c"))
		draw_circle(Vector2(17, 0), 3.5, ALARM if blink else Color("5a1a20"))
	else:
		draw_set_transform(Vector2.ZERO, angle)
		draw_rect(Rect2(-6, -7, 16, 14), Color("1d2b36"))
		draw_rect(Rect2(-6, -7, 16, 14), Color("46d6ff"), false, 1.5)
		draw_circle(Vector2(10, 0), 3.5, ALARM if blink else Color("5a1a20"))
	draw_set_transform(Vector2.ZERO)
