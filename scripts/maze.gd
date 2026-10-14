extends Node2D
## Turns an ASCII map into wall collision and draws the VR-style grid.
## See levels.gd for what each character means.

const TILE := 48.0
const CAMERA_DIRS := {">": Vector2.RIGHT, "<": Vector2.LEFT, "^": Vector2.UP, "v": Vector2.DOWN}
const TURRET := "@"
const DOOR := "D"

const FLOOR_COLOR := Color("06121f")
const GRID_COLOR := Color(0.27, 0.84, 1.0, 0.09)
const WALL_FILL := Color("0b2a40")
const WALL_EDGE := Color("46d6ff")
const DOOR_COLOR := Color("ffa63d")

var rows: Array = []
var width := 0
var height := 0
var doors_open := false

var _door_shapes: Array[CollisionShape2D] = []


func build(map: Array) -> void:
	rows = map
	height = rows.size()
	width = (rows[0] as String).length()

	# One static body; each horizontal run of the *same* solid tile becomes one
	# rectangle. Fewer, longer shapes mean fewer seams for the player to snag on.
	# Cameras, turrets and doors keep their own shapes. Doors need that so they
	# can open. Turrets need it because their rays start inside their pillar,
	# and a ray ignores the shape it starts in, so the pillar must not share a
	# shape with the walls around it.
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for y in height:
		var x := 0
		while x < width:
			var ch := char_at(Vector2i(x, y))
			if not is_solid(Vector2i(x, y)):
				x += 1
				continue
			var start := x
			x += 1
			while ch == "#" and x < width and char_at(Vector2i(x, y)) == "#":
				x += 1
			var shape := RectangleShape2D.new()
			shape.size = Vector2((x - start) * TILE, TILE)
			var col := CollisionShape2D.new()
			col.shape = shape
			col.position = Vector2((start + x) * 0.5 * TILE, (y + 0.5) * TILE)
			body.add_child(col)
			if ch == DOOR:
				_door_shapes.append(col)
	queue_redraw()


func open_doors() -> void:
	doors_open = true
	for col in _door_shapes:
		col.set_deferred("disabled", true)
	queue_redraw()


func char_at(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
		return "#"
	return rows[c.y][c.x]


## Permanent walls: plain walls plus the blocks cameras and turrets sit on.
func is_wall(c: Vector2i) -> bool:
	var ch := char_at(c)
	return ch == "#" or ch == TURRET or CAMERA_DIRS.has(ch)


func is_solid(c: Vector2i) -> bool:
	return is_wall(c) or (char_at(c) == DOOR and not doors_open)


func find_all(ch: String) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y in height:
		for x in width:
			if rows[y][x] == ch:
				found.append(Vector2i(x, y))
	return found


## Contiguous runs of `ch`, as [first_tile, last_tile] pairs, scanning
## horizontally or vertically. Used to merge laser tiles into single beams.
func runs(ch: String, horizontal: bool) -> Array:
	var result := []
	var step := Vector2i.RIGHT if horizontal else Vector2i.DOWN
	for c in find_all(ch):
		if char_at(c - step) == ch:
			continue  # not the start of a run
		var end := c
		while char_at(end + step) == ch:
			end += step
		result.append([c, end])
	return result


func tile_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * TILE


func pixel_size() -> Vector2:
	return Vector2(width, height) * TILE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, pixel_size()), FLOOR_COLOR)
	for x in width + 1:
		draw_line(Vector2(x * TILE, 0), Vector2(x * TILE, height * TILE), GRID_COLOR, 1.0)
	for y in height + 1:
		draw_line(Vector2(0, y * TILE), Vector2(width * TILE, y * TILE), GRID_COLOR, 1.0)

	# Fill wall tiles, then outline only the edges that face open floor, so
	# adjacent wall tiles read as one glowing block.
	var sides := [
		[Vector2i.UP, Vector2(0, 0), Vector2(1, 0)],
		[Vector2i.DOWN, Vector2(0, 1), Vector2(1, 1)],
		[Vector2i.LEFT, Vector2(0, 0), Vector2(0, 1)],
		[Vector2i.RIGHT, Vector2(1, 0), Vector2(1, 1)],
	]
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			var origin := Vector2(c) * TILE
			if char_at(c) == DOOR:
				_draw_door(Rect2(origin, Vector2(TILE, TILE)))
				continue
			if not is_wall(c):
				continue
			draw_rect(Rect2(origin, Vector2(TILE, TILE)), WALL_FILL)
			for side in sides:
				var n: Vector2i = c + side[0]
				if n.x < 0 or n.y < 0 or n.x >= width or n.y >= height or is_wall(n):
					continue
				var a: Vector2 = origin + side[1] * TILE
				var b: Vector2 = origin + side[2] * TILE
				draw_line(a, b, Color(WALL_EDGE, 0.18), 6.0)
				draw_line(a, b, WALL_EDGE, 2.0)


func _draw_door(r: Rect2) -> void:
	if doors_open:
		draw_rect(r.grow(-4), Color(DOOR_COLOR, 0.35), false, 1.0)
		return
	draw_rect(r, Color("2a1a06"))
	for i in 4:  # hazard stripes
		var x := r.position.x + 4 + i * 11
		draw_line(Vector2(x, r.end.y - 4), Vector2(x + 8, r.position.y + 4), Color(DOOR_COLOR, 0.7), 3.0)
	draw_rect(r.grow(-1), DOOR_COLOR, false, 2.0)
