class_name PistaMedidor
extends Node

## Pruebas de la pista de objetos (--pista-log=RUTA): anota cada cuadro dibujado
## lo que se ve y lo que se simula, por separado, para medir después los saltos
## de la cámara, del personaje y de la caja (tools/testing/pista_objetos_report.mjs).
## Una línea CSV por cuadro; el tiempo es el del sistema, así las líneas del host
## y del invitado (en la misma PC) se pueden alinear.
##
## Columnas: ms, fase, tick, cámara (x y z y su giro), personaje dibujado (x y z), personaje simulado (x y z, sin el suavizado de las correcciones), caja
## dibujada (x y z y su giro como cuaternión), caja simulada en esta máquina
## (x y z), en mano, lista, pedido en viaje, contadores (correcciones del
## personaje, la última en metros, correcciones físicas de la caja, la última,
## recuperaciones, estados del host aplicados).

var pilot: PistaPiloto
var camera: LabCamera
var path := ""
## func() -> String: en qué paso va la prueba.
var phase: Callable
## func() -> ActorBody
var local_actor: Callable

## Con ventana: fases en las que se guarda una captura, y cuántos cuadros
## después de empezar cada una ({fase: cuadros}). Se guardan junto al registro.
var captures := {}
var _phase_frames := 0
var _last_phase := ""
var _taken := {}
var _lines := PackedStringArray()
var _done := false


func _ready() -> void:
	process_priority = 1000  # después de que la pista y la cámara dibujen
	_lines.append("ms,fase,tick,cam_x,cam_y,cam_z,cam_qx,cam_qy,cam_qz,cam_qw,act_x,act_y,act_z,raw_x,raw_y,raw_z,box_x,box_y,box_z,box_qx,box_qy,box_qz,box_qw," +
			"sim_x,sim_y,sim_z,held,ready,pending,act_corr,act_last,box_corr,box_last,recov,auth")


func _process(_delta: float) -> void:
	if _done or pilot == null or pilot.box_visual == null or not pilot.box_visual.visible:
		return
	var view := get_viewport().get_camera_3d()
	var cam := view.global_position if view != null else Vector3.ZERO
	var cq := view.global_basis.get_rotation_quaternion() if view != null else Quaternion.IDENTITY
	var actor: ActorBody = local_actor.call() if local_actor.is_valid() else null
	var act := actor.visual_root().get_global_transform_interpolated().origin if actor != null else Vector3.ZERO
	var raw := BaseRegistry.world_position(actor.state) if actor != null else Vector3.ZERO
	var box := pilot.box_visual.global_transform
	var q := box.basis.get_rotation_quaternion()
	var sample := pilot.box_sample()
	var sim: Vector3 = (sample.pose as Transform3D).origin if not sample.is_empty() else Vector3.INF
	var p := pilot.prediction
	_capture_if_asked()
	_lines.append("%d,%s,%d,%s,%.5f,%.5f,%.5f,%.5f,%s,%s,%s,%.5f,%.5f,%.5f,%.5f,%s,%d,%d,%d,%d,%.5f,%d,%.5f,%d,%d" % [
		int(Time.get_unix_time_from_system() * 1000.0), phase.call() if phase.is_valid() else "", pilot.clock.tick,
		_v(cam), cq.x, cq.y, cq.z, cq.w, _v(act), _v(raw), _v(box.origin), q.x, q.y, q.z, q.w, _v(sim) if sim.is_finite() else ",,",
		int(sample.get("held", false)), int(pilot.ready_to_play() or pilot.role == PistaPiloto.Role.HOST),
		int(pilot.pending()), p.corrections if p != null else 0, p.last_correction_meters if p != null else 0.0,
		pilot.box_corrections, pilot.last_box_correction, pilot.recoveries, pilot.authorities_applied])


func _capture_if_asked() -> void:
	var now: String = phase.call() if phase.is_valid() else ""
	if now != _last_phase:
		_last_phase = now
		_phase_frames = 0
	_phase_frames += 1
	if not captures.has(now) or _taken.has(now) or _phase_frames < int(captures[now]) or DisplayServer.get_name() == "headless":
		return
	_taken[now] = true
	var image := get_viewport().get_texture().get_image()
	if image != null and not image.is_empty():
		var file := path.get_base_dir().path_join("%s_%s.png" % [path.get_file().get_basename(), now])
		image.save_png(file)
		print("[pista] captura: %s" % file)


func _v(v: Vector3) -> String:
	return "%.5f,%.5f,%.5f" % [v.x, v.y, v.z]


func finish() -> void:
	if _done:
		return
	_done = true
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[pista] no se pudo escribir %s" % path)
		return
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	print("[pista] registro: %s (%d cuadros)" % [path, _lines.size() - 1])
