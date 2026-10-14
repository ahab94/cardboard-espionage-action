extends Node2D

@export var speed := 300.0

func _process(delta: float) -> void:
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down"))
	position += dir * speed * delta
