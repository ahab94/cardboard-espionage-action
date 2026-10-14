extends Control
## Mission select overlay: every Virtual Ops mission with its best time. Locked
## missions are shown but can't be started. The game handles the input and
## calls open() / move().

const CYAN := Color("46d6ff")
const DIM := Color("4a6577")
const ROW_HEIGHT := 40.0

var selected := 0
var screen_size := Vector2(1152, 648)
var touch := false   # show tap hints instead of keyboard hints   # set by the game before adding (portrait is 648x1152)

var _levels: Array = []
var _unlocked := 1
var _best := {}
var _names: Array[Label] = []
var _times: Array[Label] = []


func _ready() -> void:
	size = screen_size
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.04, 0.07, 0.93)
	dim.size = size
	add_child(dim)
	var y0 := _rows_top()
	var title := _label(Vector2(0, y0 - 96), 40 if size.x > size.y else 30, CYAN)
	title.size.x = size.x
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "CARDBOARD ESPIONAGE ACTION"
	var subtitle := _label(Vector2(0, y0 - 44), 16, DIM)
	subtitle.size.x = size.x
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.text = "V I R T U A L   O P S"
	var footer := _label(Vector2(0, size.y - 52), 15, DIM)
	footer.size.x = size.x
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.text = "TAP a mission to play" if touch else "UP / DOWN choose     ENTER start     ESC back"


func open(levels: Array, unlocked: int, best: Dictionary, current: int) -> void:
	_levels = levels
	_unlocked = unlocked
	_best = best
	selected = current
	while _names.size() < levels.size():
		var y := _rows_top() + _names.size() * ROW_HEIGHT
		_names.append(_label(Vector2(size.x * 0.5 - 236, y), 22, CYAN))
		_times.append(_label(Vector2(size.x * 0.5 + 124, y + 3), 18, CYAN))
	_refresh()
	visible = true


func move(step: int) -> void:
	selected = clampi(selected + step, 0, _levels.size() - 1)
	_refresh()


## Which mission row is at `pos` (screen coordinates), or -1.
func row_at(pos: Vector2) -> int:
	var i := int(floor((pos.y - _rows_top() + 6.0) / ROW_HEIGHT))
	if i < 0 or i >= _levels.size() or absf(pos.x - size.x * 0.5) > 300.0:
		return -1
	return i


func select(index: int) -> void:
	selected = index
	_refresh()


func is_unlocked(index: int) -> bool:
	return index < _unlocked


func _refresh() -> void:
	for i in _levels.size():
		var here := i == selected
		var open_ := is_unlocked(i)
		_names[i].text = (">  " if here else "    ") + String(_levels[i]["name"])
		if not open_:
			_times[i].text = "LOCKED"
		elif _best.has(i):
			_times[i].text = "BEST  " + format_time(_best[i])
		else:
			_times[i].text = "--"
		var color := Color.WHITE if here and open_ else (CYAN if open_ else DIM)
		_names[i].add_theme_color_override("font_color", color)
		_times[i].add_theme_color_override("font_color", color if open_ else DIM)


func _rows_top() -> float:
	return size.y * 0.5 - 206.0   # centres the list; 118 in landscape


func _label(pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


static func format_time(t: float) -> String:
	return "%02d:%04.1f" % [int(t / 60.0), fmod(t, 60.0)]
