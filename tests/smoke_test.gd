extends SceneTree

func _init() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("cannot load main scene")
		quit(1)
		return
	var main := packed.instantiate()
	if main.get_node_or_null("TitleLabel") == null or main.get_node_or_null("Player") == null:
		push_error("missing TitleLabel or Player")
		quit(1)
		return
	print("SMOKE OK")
	quit(0)
