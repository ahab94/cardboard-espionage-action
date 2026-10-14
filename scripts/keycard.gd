extends Node2D
## A keycard pickup. Collecting it unlocks every vault door (D) in the level.

const COLOR := Color("ffd84a")

var collected := false
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if collected:
		return
	draw_arc(Vector2.ZERO, 18.0 + 2.0 * sin(_time * 4.0), 0, TAU, 32, Color(COLOR, 0.4), 1.5)
	draw_set_transform(Vector2(0, sin(_time * 3.0) * 2.0), 0.15 * sin(_time * 2.0))
	draw_rect(Rect2(-12, -8, 24, 16), COLOR)
	draw_rect(Rect2(-12, -4, 24, 4), Color("3a2a0a"))
	draw_rect(Rect2(-12, -8, 24, 16), Color("8a6a10"), false, 1.5)
	draw_set_transform(Vector2.ZERO)
