extends Node2D
## The extraction point: a pulsing square the box has to reach.

const COLOR := Color("4dff9a")
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var s := 40.0
	draw_rect(Rect2(-s / 2, -s / 2, s, s), Color(COLOR, 0.12 + 0.12 * pulse))
	var g := s + 6.0 * pulse
	draw_rect(Rect2(-g / 2, -g / 2, g, g), Color(COLOR, 0.9), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(-20, 5), "GOAL",
			HORIZONTAL_ALIGNMENT_CENTER, 40, 13, COLOR)
