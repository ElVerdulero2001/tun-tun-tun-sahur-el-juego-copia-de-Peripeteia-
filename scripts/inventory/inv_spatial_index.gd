class_name InvSpatialIndex
extends RefCounted

## Una grilla de celdas en el mundo para encontrar, sin recorrer todos, los
## objetos sueltos que puede tocar un segmento (desde el 2026-11-14, pedido de
## docs/net/prompt_claude_objetos_dinamicos.md; la auditoría del 2026-11-12,
## REND-02, medía que mirar el vacío costaba según todos los objetos del mapa).
##
## Cada objeto se anota en las celdas que toca su caja en el mundo (la de su
## modelo y la de su cuerpo físico, ya movida y girada; InvItemSpace). Al
## moverse se vuelve a anotar solo si cambian sus celdas. Un segmento recorre
## las celdas que cruza, en orden (el recorrido de Amanatides y Woo), y junta
## los objetos de cada una sin repetirlos: es la fase de candidatos. Lo preciso
## (los triángulos del modelo) lo decide InvReach.first_hit con cada candidato.
##
## No hay un límite de candidatos: si en una celda hay cien objetos, salen los
## cien. Cualquier objeto cuya caja cruza el segmento sale, porque el punto
## donde la cruza está en una celda que el segmento recorre y que su caja toca.

## Lado de cada celda, en metros. Los objetos del laboratorio miden de 5 cm a
## 2 m, y un rayo de la mano, unos 3 m: cruza 4 o 5 celdas.
const CELL := 1.0
## Cuánto se agranda la caja de cada objeto al anotarla, por si un borde cae
## justo sobre el límite de dos celdas.
const PAD := 0.002

## celda (Vector3i) -> {número del objeto: true}
var _cells := {}
## número del objeto -> [celda mínima, celda máxima] donde está anotado
var _spans := {}
## Para la medición: cuántos objetos distintos juntó el último segmento y
## cuántas celdas recorrió.
var last_candidates := 0
var last_cells := 0


func clear() -> void:
	_cells.clear()
	_spans.clear()


func size() -> int:
	return _spans.size()


func has(uid: int) -> bool:
	return _spans.has(uid)


## Anota (o vuelve a anotar) un objeto con su caja en el mundo. Si sus celdas
## no cambiaron, no hace nada.
func put(uid: int, box: AABB) -> void:
	if not box.position.is_finite() or not box.size.is_finite():
		remove(uid)
		return
	var grown := box.grow(PAD)
	var low := _cell_of(grown.position)
	var high := _cell_of(grown.end)
	var known: Array = _spans.get(uid, [])
	if not known.is_empty() and known[0] == low and known[1] == high:
		return
	if not known.is_empty():
		_unmark(uid, known[0], known[1])
	_spans[uid] = [low, high]
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				var cell := Vector3i(x, y, z)
				var bucket: Dictionary = _cells.get_or_add(cell, {})
				bucket[uid] = true


func remove(uid: int) -> void:
	var known: Array = _spans.get(uid, [])
	if known.is_empty():
		return
	_unmark(uid, known[0], known[1])
	_spans.erase(uid)


func _unmark(uid: int, low: Vector3i, high: Vector3i) -> void:
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				var cell := Vector3i(x, y, z)
				var bucket: Dictionary = _cells.get(cell, {})
				bucket.erase(uid)
				if bucket.is_empty():
					_cells.erase(cell)


## Los objetos anotados en las celdas que toca `box` (sin repetir, por
## número): los que pueden tocarla. Para ver si un lugar está libre.
func near(box: AABB) -> Array[int]:
	var out: Array[int] = []
	if _spans.is_empty() or not box.position.is_finite() or not box.size.is_finite():
		return out
	var low := _cell_of(box.position)
	var high := _cell_of(box.end)
	var seen := {}
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				for uid: int in _cells.get(Vector3i(x, y, z), {}):
					if not seen.has(uid):
						seen[uid] = true
						out.append(uid)
	out.sort()
	return out


## Los objetos de las celdas que cruza el segmento de `from` a `to`, en el
## orden en que el segmento entra a sus celdas: [[distancia desde `from` a la
## que entra a esa celda, [números nuevos en esa celda]], ...]. Quien busca lo
## primero que toca puede dejar de mirar cuando lo que ya encontró está más
## cerca que la entrada a la celda siguiente.
func along(from: Vector3, to: Vector3) -> Array:
	last_candidates = 0
	last_cells = 0
	var out: Array = []
	if _spans.is_empty() or not from.is_finite() or not to.is_finite():
		return out
	var seen := {}
	var delta := to - from
	var length := delta.length()
	var cell := _cell_of(from)
	var last := _cell_of(to)
	var step := Vector3i.ZERO
	var t_max := Vector3.ONE * INF
	var t_delta := Vector3.ONE * INF
	if length > 0.0:
		var direction := delta / length
		for axis in 3:
			if direction[axis] > 0.0:
				step[axis] = 1
				t_max[axis] = ((cell[axis] + 1) * CELL - from[axis]) / direction[axis]
				t_delta[axis] = CELL / direction[axis]
			elif direction[axis] < 0.0:
				step[axis] = -1
				t_max[axis] = (cell[axis] * CELL - from[axis]) / direction[axis]
				t_delta[axis] = -CELL / direction[axis]
	var entry := 0.0
	# Un segmento cruza como mucho las celdas de su largo en cada eje, más una.
	var budget := 3 + int(ceilf(absf(delta.x) / CELL) + ceilf(absf(delta.y) / CELL) + ceilf(absf(delta.z) / CELL))
	while budget > 0:
		budget -= 1
		last_cells += 1
		var bucket: Dictionary = _cells.get(cell, {})
		if not bucket.is_empty():
			var fresh: Array[int] = []
			for uid: int in bucket:
				if not seen.has(uid):
					seen[uid] = true
					fresh.append(uid)
			if not fresh.is_empty():
				# El mismo orden en todas las máquinas: por número.
				fresh.sort()
				out.append([entry, fresh])
				last_candidates += fresh.size()
		if cell == last:
			break
		var axis := 0
		if t_max.y < t_max[axis]:
			axis = 1
		if t_max.z < t_max[axis]:
			axis = 2
		entry = t_max[axis]
		if entry > length:
			break
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
	return out


static func _cell_of(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / CELL), floori(point.y / CELL), floori(point.z / CELL))
