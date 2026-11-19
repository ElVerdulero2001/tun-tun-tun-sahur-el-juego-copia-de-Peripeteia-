extends Node

## Registro de una partida manual. Cada línea se escribe durante la captura.
const SAMPLE_USEC := 33_333
const FLUSH_USEC := 1_000_000

var clock: SimClock
var sample: Callable
var path := ""
var _file: FileAccess
var _started_usec := 0
var _next_sample_usec := 0
var _next_flush_usec := 0


func _ready() -> void:
	process_priority = 1000  # Después de dibujar al personaje, la cámara y la caja.
	set_process(false)


func recording() -> bool:
	return _file != null


func start(folder: String, role_name: String) -> Error:
	if recording():
		return ERR_ALREADY_IN_USE
	var directory := ProjectSettings.globalize_path(folder)
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	var date := Time.get_datetime_string_from_system().replace(":", "-")
	_started_usec = Time.get_ticks_usec()
	var target := directory.path_join("pista_%s_%s_%d_%d.jsonl" % [
		role_name, date, OS.get_process_id(), _started_usec,
	])
	_file = FileAccess.open(target, FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	path = target
	_next_sample_usec = _started_usec
	_next_flush_usec = _started_usec + FLUSH_USEC
	record("start", {"schema": 1, "role": role_name, "engine": Engine.get_version_info().string})
	_file.flush()
	set_process(true)
	return OK


func record(event: String, fields: Dictionary = {}) -> void:
	if not recording():
		return
	var row := {
		"event": event,
		"tick": clock.tick,
		"elapsed_usec": Time.get_ticks_usec() - _started_usec,
		"unix_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"data": fields,
	}
	_file.store_line(JSON.stringify(row))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if now >= _next_sample_usec:
		_next_sample_usec = now + SAMPLE_USEC - now % SAMPLE_USEC
		record("sample", sample.call())
	if now >= _next_flush_usec:
		_next_flush_usec = now + FLUSH_USEC
		_file.flush()


func stop() -> void:
	if not recording():
		return
	record("stop")
	_file.close()
	_file = null
	set_process(false)


func _exit_tree() -> void:
	stop()


static func xyz(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
