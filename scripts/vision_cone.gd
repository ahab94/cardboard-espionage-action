extends Node2D
## Shared sight for cameras, turrets and soldiers: a cone `fov` wide pointing
## at `angle`, out to `view_range`. The cone is rebuilt from ray casts every
## physics frame, so walls cast real shadows. Anything behind a wall is both
## unseen and drawn outside the cone.

const RAYS := 48
const WALL_MASK := 1

const CALM := Color(0.45, 1.0, 0.72)
const SUSPICIOUS := Color(1.0, 0.82, 0.2)
const ALARM := Color(1.0, 0.2, 0.26)

var angle := 0.0
var fov := deg_to_rad(50.0)
var view_range := 6.5 * 48.0

var heat := 0.0       # 0..1, set by the game: how close this watcher is to raising the alarm
var alarmed := false

var _cone := PackedVector2Array()


func can_see(point: Vector2) -> bool:
	var to := point - global_position
	if to.length() > view_range:
		return false
	if absf(angle_difference(angle, to.angle())) > fov * 0.5:
		return false
	return _cast(point).is_empty()


func can_see_any(points: Array[Vector2]) -> bool:
	for p in points:
		if can_see(p):
			return true
	return false


func tint() -> Color:
	return ALARM if alarmed else CALM.lerp(SUSPICIOUS, heat)


func update_cone() -> void:
	_cone.clear()
	for i in RAYS + 1:
		var a := angle - fov * 0.5 + fov * float(i) / RAYS
		var end := global_position + Vector2.from_angle(a) * view_range
		var hit := _cast(end)
		var p: Vector2 = hit.position if not hit.is_empty() else end
		_cone.append(p - global_position)
	queue_redraw()


func draw_cone() -> void:
	var t := tint()
	var near := Color(t, 0.30)
	var far := Color(t, 0.06)
	# A fan of triangles is always drawable, even when walls clip the cone
	# into a shape a polygon triangulator would reject.
	for i in _cone.size() - 1:
		var a := _cone[i]
		var b := _cone[i + 1]
		draw_primitive(PackedVector2Array([Vector2.ZERO, a, b]),
				PackedColorArray([near, far.lerp(near, 1.0 - a.length() / view_range),
						far.lerp(near, 1.0 - b.length() / view_range)]),
				PackedVector2Array())
	if _cone.size() > 1:
		draw_polyline(_cone, Color(t, 0.45), 1.5)
		draw_line(Vector2.ZERO, _cone[0], Color(t, 0.45), 1.5)
		draw_line(Vector2.ZERO, _cone[_cone.size() - 1], Color(t, 0.45), 1.5)


func _cast(target: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(global_position, target, WALL_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query)
