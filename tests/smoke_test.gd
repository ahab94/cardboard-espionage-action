extends SceneTree

func _init() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("cannot load main scene")
		quit(1)
		return
	var main := packed.instantiate()
	if main.get_script() == null or not main.has_method("load_level"):
		push_error("main scene is missing the game script")
		quit(1)
		return
	main.free()
	print("SMOKE OK")
	quit(0)
