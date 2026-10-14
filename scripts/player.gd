extends CharacterBody2D
## The protagonist: a cardboard box. Move with arrows/WASD; hold SPACE to drop
## the box and sit still. A still box draws far less suspicion from cameras.

const SIZE := 30.0
const CARDBOARD := Color("c49a5a")
const CARDBOARD_DARK := Color("8a6534")
const TAPE := Color("e2c58f")

@export var speed := 170.0

var controllable := true
var hidden_in_box := false
var alert_mark := ""   # "", "?" or "!" drawn above the box

# The demo autopilot drives the box through these instead of the keyboard.
var bot_driven := false
var bot_move := Vector2.ZERO
var bot_hide := false

var _facing := Vector2.RIGHT
var _waddle := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = MOTION_MODE_FLOATING
	var shape := RectangleShape2D.new()
	shape.size = Vector2(SIZE, SIZE)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)


func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	hidden_in_box = false
	if controllable and bot_driven:
		dir = bot_move
		hidden_in_box = bot_hide
	elif controllable:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		hidden_in_box = Input.is_action_pressed("hide")
	if hidden_in_box:
		dir = Vector2.ZERO
	if dir != Vector2.ZERO:
		_facing = dir
		_waddle += delta * 14.0
	else:
		_waddle = 0.0
	velocity = dir * speed
	move_and_slide()
	queue_redraw()


## The box's footprint in global coordinates (used for laser hits).
func bounds() -> Rect2:
	return Rect2(global_position - Vector2(SIZE, SIZE) * 0.5, Vector2(SIZE, SIZE))


## Points cameras test for line of sight: centre plus four inset corners, so a
## box half-peeking round a corner can still be seen.
func sight_points() -> Array[Vector2]:
	var h := SIZE * 0.5 - 3.0
	var p := global_position
	return [p, p + Vector2(-h, -h), p + Vector2(h, -h), p + Vector2(-h, h), p + Vector2(h, h)]


func _draw() -> void:
	var h := SIZE * 0.5
	if hidden_in_box:
		# Flaps shut, box pressed flat to the floor: slightly wider, darker.
		var r := Rect2(-h - 2, -h + 2, SIZE + 4, SIZE - 2)
		draw_rect(r, CARDBOARD_DARK)
		draw_rect(r.grow(-3), CARDBOARD.darkened(0.15))
		draw_rect(Rect2(-3, r.position.y, 6, r.size.y), TAPE.darkened(0.2))
		draw_rect(r, Color.BLACK, false, 2.0)
	else:
		draw_set_transform(Vector2.ZERO, sin(_waddle) * 0.08)
		var r := Rect2(-h, -h, SIZE, SIZE)
		draw_rect(r, CARDBOARD)
		draw_rect(Rect2(-3, -h, 6, SIZE), TAPE)
		draw_rect(r, CARDBOARD_DARK, false, 2.0)
		# A peeking slit with two eyes that look where the box is heading.
		draw_rect(Rect2(-9, -5, 18, 7), Color(0.05, 0.03, 0.02))
		var look := _facing.normalized() * 2.0
		draw_circle(Vector2(-4, -1.5) + look, 1.8, Color.WHITE)
		draw_circle(Vector2(4, -1.5) + look, 1.8, Color.WHITE)
		draw_set_transform(Vector2.ZERO)
	if alert_mark != "":
		var color := Color("ff3344") if alert_mark == "!" else Color("ffd84a")
		draw_string(ThemeDB.fallback_font, Vector2(-8, -h - 6), alert_mark,
				HORIZONTAL_ALIGNMENT_CENTER, 16, 28, color)
