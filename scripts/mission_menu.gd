extends Control
## Mission select overlay: every Virtual Ops mission with its best time. Locked
## missions are shown but can't be started. The game handles the input and
## calls open() / move().

const CYAN := Color("46d6ff")
const DIM := Color("4a6577")
const ROW_HEIGHT := 40.0

var selected := 0

var _levels: Array = []
var _unlocked := 1
var _best := {}
var _names: Array[Label] = []
var _times: Array[Label] = []


func _ready() -> void:
	size = Vector2(1152, 648)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.04, 0.07, 0.93)
	dim.size = size
	add_child(dim)
	var title := _label(Vector2(0, 22), 40, CYAN)
	title.size.x = size.x
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "CARDBOARD ESPIONAGE ACTION"
	var subtitle := _label(Vector2(0, 74), 16, DIM)
	subtitle.size.x = size.x
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.text = "V I R T U A L   O P S"
	var footer := _label(Vector2(0, size.y - 52), 15, DIM)
	footer.size.x = size.x
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.text = "UP / DOWN choose     ENTER start     ESC back"


func open(levels: Array, unlocked: int, best: Dictionary, current: int) -> void:
	_levels = levels
	_unlocked = unlocked
	_best = best
	selected = current
	while _names.size() < levels.size():
		var y := 118.0 + _names.size() * ROW_HEIGHT
		_names.append(_label(Vector2(340, y), 22, CYAN))
		_times.append(_label(Vector2(700, y + 3), 18, CYAN))
	_refresh()
	visible = true


func move(step: int) -> void:
	selected = clampi(selected + step, 0, _levels.size() - 1)
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


func _label(pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


static func format_time(t: float) -> String:
	return "%02d:%04.1f" % [int(t / 60.0), fmod(t, 60.0)]
