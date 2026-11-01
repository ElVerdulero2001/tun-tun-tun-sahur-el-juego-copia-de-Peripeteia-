class_name InvCatalog
extends Resource

## Lista de los tipos de objeto que existen. Los mensajes de red nombran un
## tipo por su id, y del otro lado se busca acá: un id que no está no es un
## objeto. Lo referencia explícitamente quien lo necesita (InvNet, la zona de
## prueba); no es global.

@export var items: Array[InvItemDef] = []

var _by_id := {}


func find(def_id: StringName) -> InvItemDef:
	if _by_id.size() != items.size():
		_by_id.clear()
		for item in items:
			if item != null:
				_by_id[item.id] = item
	return _by_id.get(def_id)


## Avisos de un catálogo mal armado: ids vacíos o repetidos.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var seen := {}
	for item in items:
		if item == null:
			found.append("hay un lugar vacío en la lista")
			continue
		if String(item.id) == "":
			found.append("%s no tiene id" % item.resource_path)
		elif seen.has(item.id):
			found.append("el id %s está repetido" % item.id)
		seen[item.id] = true
	return found


func fingerprint_text() -> String:
	var lines := PackedStringArray()
	for item in items:
		lines.append(item.fingerprint_text() if item != null else "null")
	return "\n".join(lines)
