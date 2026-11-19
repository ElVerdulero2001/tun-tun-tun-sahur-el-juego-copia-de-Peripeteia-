extends RefCounted

## El mundo de objetos de la pista (SahurObjectWorld, Rapier) con el tick del
## reloj del laboratorio. El mundo nativo arranca en el tick 0 y suma uno por
## paso; el reloj del laboratorio ya va por miles cuando alguien entra a la
## pista. Este envoltorio suma `base` al tick que informa el mundo (get_tick y
## el "tick" de sample) y deja todo lo demás igual: el adaptador, el registro
## del host y la reconciliación de la entrega 16 comparan esos ticks con los
## del reloj sin cambios.
##
## El host crea su mundo una vez, con base = el tick del reloj en ese momento,
## y le manda esa base al invitado. Un estado del host restaurado sobre otro
## mundo con la misma base da el mismo tick del reloj. El primer mundo del
## invitado (antes de recibir ningún estado) usa como base su propio tick:
## nunca se restaura ni se manda, solo sirve para arrancar en el tick de su reloj.

var native
var base := 0


func _init(p_native, p_base: int) -> void:
	native = p_native
	base = p_base


func get_tick() -> int:
	return native.get_tick() + base


func sample(uid: int, epoch: int) -> Dictionary:
	var out: Dictionary = native.sample(uid, epoch)
	if not out.is_empty():
		out.tick = int(out.tick) + base
	return out


func samples() -> Array:
	var out: Array = native.samples()
	for item: Dictionary in out:
		item.tick = int(item.tick) + base
	return out


func get_last_error() -> String:
	return native.get_last_error()


func step(dt: float) -> bool:
	return native.step(dt)


func cache_checkpoint() -> int:
	return native.cache_checkpoint()


func snapshot_trusted() -> PackedByteArray:
	return native.snapshot_trusted()


func restore_trusted(bytes: PackedByteArray) -> bool:
	return native.restore_trusted(bytes)


func begin_hold(uid: int, epoch: int, anchor: Vector3, goal: Transform3D) -> bool:
	return native.begin_hold(uid, epoch, anchor, goal)


func set_goal(uid: int, epoch: int, goal: Transform3D) -> bool:
	return native.set_goal(uid, epoch, goal)


func release_body(uid: int, epoch: int, impulse: Vector3) -> bool:
	return native.release_body(uid, epoch, impulse)


func apply_impulse(uid: int, epoch: int, impulse: Vector3) -> bool:
	return native.apply_impulse(uid, epoch, impulse)
