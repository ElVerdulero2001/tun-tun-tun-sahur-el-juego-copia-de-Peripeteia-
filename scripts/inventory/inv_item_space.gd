class_name InvItemSpace
extends RefCounted

## Los objetos sueltos tal como los consulta el rayo de la mano (InvReach):
## cada uno con su pila y su transformación entera (lugar y giro), y un índice
## espacial (InvSpatialIndex) para no recorrerlos todos en cada rayo (desde el
## 2026-11-14). Hay uno por máquina y por uso:
##
## - en el host, el de la autoridad (InvAuthority.space): los cuerpos como los
##   simula Jolt, puestos al día en cada tick solo los que se mueven. Guarda
##   además, de los que se movieron, su pose en cada tick del último segundo
##   (`history_ticks`), para validar un pedido con lo que veía el jugador
##   (pose_at);
## - en un cliente, el de lo que se ve (InvBodies): la pose interpolada que se
##   dibuja, o la que se adelanta para lo que sostiene el propio jugador.
##
## Un objeto que no se mueve no se toca: el índice y la historia solo cambian
## con lo que entra, sale o se mueve.

var catalog: InvCatalog
var index := InvSpatialIndex.new()
## número -> {"stack": InvStack, "xf": Transform3D}
var items := {}
## Host: cuántos ticks se recuerda la pose de lo que se mueve (0: nada).
var history_ticks := 0

## número -> [[tick, Transform3D], ...] del más viejo al más nuevo
var _history := {}
## número -> último tick en que se movió
var _moved := {}


func clear() -> void:
	items.clear()
	index.clear()
	_history.clear()
	_moved.clear()


func has(uid: int) -> bool:
	return items.has(uid)


func size() -> int:
	return items.size()


## Agrega o reemplaza un objeto, en `place`.
func put(uid: int, stack: InvStack, place: Transform3D, tick := -1) -> void:
	var known: Dictionary = items.get(uid, {})
	if not known.is_empty():
		known["stack"] = stack
		move(uid, place, tick)
		return
	items[uid] = {"stack": stack, "xf": place}
	_index(uid)


## Lo mueve. Con historia, anota su pose en ese tick (y, si recién empieza a
## moverse, la de antes, para poder volver a ella).
func move(uid: int, place: Transform3D, tick := -1) -> void:
	var item: Dictionary = items.get(uid, {})
	if item.is_empty():
		return
	var before: Transform3D = item["xf"]
	if before.is_equal_approx(place):
		return
	item["xf"] = place
	_index(uid)
	if history_ticks > 0 and tick >= 0:
		var list: Array = _history.get_or_add(uid, [])
		if list.is_empty() or list[-1][0] < tick - 1:
			list.append([tick - 1, before])
		if not list.is_empty() and list[-1][0] == tick:
			list[-1][1] = place
		else:
			list.append([tick, place])
		while list.size() > 2 and list[1][0] < tick - history_ticks:
			list.pop_front()
		_moved[uid] = tick


## Cambia la pila (por ejemplo, al recoger una parte) sin moverlo.
func set_stack(uid: int, stack: InvStack) -> void:
	if items.has(uid):
		items[uid]["stack"] = stack


func remove(uid: int) -> void:
	items.erase(uid)
	index.remove(uid)
	_history.erase(uid)
	_moved.erase(uid)


func transform_of(uid: int) -> Transform3D:
	return items[uid]["xf"] if items.has(uid) else Transform3D.IDENTITY


## La pose de un objeto en el tick `at` (con decimales: entre dos ticks, el
## medio, como lo interpola un cliente). Sin historia de ese momento, la de
## ahora: no se movió desde entonces. Antes de lo que se recuerda, la más vieja.
func pose_at(uid: int, at: float) -> Transform3D:
	var list: Array = _history.get(uid, [])
	if list.is_empty() or at < 0.0 or at >= list[-1][0]:
		return transform_of(uid)
	if at <= list[0][0]:
		return list[0][1]
	for i in range(list.size() - 1, 0, -1):
		var from: Array = list[i - 1]
		if from[0] <= at:
			var to: Array = list[i]
			var weight := clampf((at - from[0]) / maxf(to[0] - from[0], 0.0001), 0.0, 1.0)
			return (from[1] as Transform3D).interpolate_with(to[1], weight)
	return list[0][1]


## Los que se movieron desde el tick `since` (para validar con poses viejas:
## pueden estar en otro lado que lo que dice el índice de ahora).
func moved_since(since: float) -> Array[int]:
	var out: Array[int] = []
	for uid: int in _moved.keys():
		if _moved[uid] < since - 1.0 - history_ticks:
			_moved.erase(uid)
			_history.erase(uid)
		elif _moved[uid] >= since - 1.0:
			out.append(uid)
	out.sort()
	return out


func _index(uid: int) -> void:
	var item: Dictionary = items[uid]
	var def := catalog.find((item["stack"] as InvStack).def_id) if catalog != null else null
	index.put(uid, (item["xf"] as Transform3D) * InvItemPhysics.local_bounds(def))
