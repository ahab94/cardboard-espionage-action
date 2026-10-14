extends Node
## Music and sound effects. Every file in audio/ is synthesized by
## tools/make_audio.py: original sounds built from oscillators and noise.
##
## The music adapts. During a mission, "sneak" always plays and "tension"
## (same tempo and length, started on the same frame so the two stay in step)
## fades in as the detection meter rises.
##
## Godot audio basics used here: an AudioStreamPlayer plays one stream at a
## time, and players route into named buses (Music, SFX) that mix into Master,
## so each group's volume can be set in one place.

const SFX := {
	"alert": preload("res://audio/sfx/alert.wav"),
	"suspicious": preload("res://audio/sfx/suspicious.wav"),
	"step": preload("res://audio/sfx/step.wav"),
	"hide": preload("res://audio/sfx/hide.wav"),
	"laser": preload("res://audio/sfx/laser.wav"),
	"keycard": preload("res://audio/sfx/keycard.wav"),
	"door": preload("res://audio/sfx/door.wav"),
	"complete": preload("res://audio/sfx/complete.wav"),
	"menu_move": preload("res://audio/sfx/menu_move.wav"),
	"menu_select": preload("res://audio/sfx/menu_select.wav"),
}
const MUSIC := {
	"sneak": preload("res://audio/music/sneak.wav"),
	"tension": preload("res://audio/music/tension.wav"),
	"menu": preload("res://audio/music/menu.wav"),
}
const DRONE_LOOP := preload("res://audio/sfx/drone_loop.wav")
const SILENT_DB := -60.0
const POOL_SIZE := 10

var music_on := true
var tension_level := 0.0   # 0..1, eased toward the target each frame

var _current := ""         # "mission", "menu" or "" (silence)
var _music: AudioStreamPlayer
var _tension: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _drones: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_ensure_bus("Music", -9.0)
	_ensure_bus("SFX", -3.0)
	for stream in MUSIC.values():
		_make_loop(stream)
	_make_loop(DRONE_LOOP)
	_music = _player("Music")
	_tension = _player("Music")
	for i in POOL_SIZE:
		_pool.append(_player("SFX"))


## One-shot effect. `pitch_jitter` varies the pitch a little each time so
## repeated sounds (footsteps) don't sound mechanical.
func play(sound: String, volume_db := 0.0, pitch_jitter := 0.0) -> void:
	var p := _pool[0]
	for candidate in _pool:
		if not candidate.playing:
			p = candidate
			break
	p.stream = SFX[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_music(track: String) -> void:
	if track == _current:
		return
	_current = track
	_start_current()


func toggle_music() -> bool:
	music_on = not music_on
	_start_current()
	return music_on


func current_music() -> String:
	return _current if music_on else ""


## Called every frame with how much danger the box is in (0..1).
func set_tension(target: float, delta: float) -> void:
	tension_level = move_toward(tension_level, clampf(target, 0.0, 1.0), delta * 1.5)
	_tension.volume_db = linear_to_db(maxf(tension_level, 0.001))


## One looping hum per drone, so each one's volume can follow its distance.
func set_drone_count(count: int) -> void:
	while _drones.size() > count:
		_drones.pop_back().queue_free()
	while _drones.size() < count:
		var p := _player("SFX")
		p.stream = DRONE_LOOP
		p.volume_db = SILENT_DB
		p.play()
		_drones.append(p)


func set_drone_volume(index: int, loudness: float) -> void:
	_drones[index].volume_db = linear_to_db(maxf(loudness, 0.001))


func _start_current() -> void:
	_music.stop()
	_tension.stop()
	if not music_on or _current == "":
		return
	if _current == "mission":
		_music.stream = MUSIC.sneak
		_tension.stream = MUSIC.tension
		tension_level = 0.0
		_tension.volume_db = SILENT_DB
		_music.play()
		_tension.play()
	else:
		_music.stream = MUSIC.menu
		_music.play()


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


static func _make_loop(stream: AudioStreamWAV) -> void:
	# The files are written to loop exactly, so loop the whole thing.
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(round(stream.get_length() * stream.mix_rate))


static func _ensure_bus(bus_name: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, volume_db)
