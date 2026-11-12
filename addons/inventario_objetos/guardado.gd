@tool
extends RefCounted

## Lo que guarda el panel Objetos. Valida y escribe los ítems (un .tres de
## InvItemDef cada uno, más su lugar en el catálogo) y los contenedores (una
## escena heredada de caja.tscn). Cada operación valida todo antes de escribir;
## si después falla un paso, deshace lo que esa misma operación ya había
## escrito y dice qué quedó. Devuelven {"ok": bool, "message": String}.
##
## `writer` guarda un recurso en una ruta y devuelve el Error, como
## ResourceSaver.save (es lo que se usa si no se pasa otro). Las pruebas le
## pasan uno que falla a propósito, para probar la vuelta atrás sin romper nada.
##
## Los recursos y las escenas abiertos en el editor tienen sus scripts sin
## correr (no son @tool): sus valores se leen y se escriben con get y set.

const Destinos := preload("destinos.gd")

## Lo que el panel edita de un InvItemDef. Lo demás del recurso (metadatos, o
## campos que se agreguen un día) queda como estaba.
const ITEM_FIELDS: Array[StringName] = [&"id", &"display_name", &"description", &"size", &"can_rotate", &"stackable",
		&"max_stack", &"abilities", &"default_state", &"model", &"mesh", &"color", &"world_size", &"pickup_hitbox",
		&"thumbnail_rotation", &"thumbnail_zoom", &"thumbnail_offset", &"thumbnail_auto_align",
		&"custom_hotbar_thumbnail", &"hotbar_thumbnail_rotation", &"hotbar_thumbnail_zoom", &"hotbar_thumbnail_offset"]
## Lo que el panel edita de un contenedor (InvContainer), además del nombre
## del nodo. Desde el 2026-11-11 no hay alcance propio de cada caja: se abre con
## el alcance común del Tuning (Interaction Range).
const BOX_FIELDS: Array[StringName] = [&"display_name", &"columns", &"rows", &"box_size", &"color"]
## Las grillas van de 1 a 64 celdas por lado (InvInventory, InvContainer).
const MAX_CELLS := 64
const MAX_STACK := 9999
## Lo más que cura, daña o recupera un consumible por unidad (InvConsumable).
const MAX_EFFECT := 10000
## Lo más que puede durar un daño en el tiempo, en segundos (InvConsumable).
const MAX_EFFECT_SECONDS := 600.0
## Radio del personaje: en la vista previa de una caja, el personaje se para a
## esto más medio lado de la caja, al lado de ella.
const ACTOR_RADIUS := 0.35
## Archivo de paso para armar un contenedor heredado (se borra enseguida).
const SEED_PATH := "user://inventario_objetos_contenedor_base.tscn"


# --- Ítems -----------------------------------------------------------------------

## El id y el nombre del archivo: en minúsculas, sin tildes y con _ en vez de
## espacios y signos. "Termo de café" → termo_de_cafe.
static func id_for(text: String) -> String:
	var plain := text.strip_edges().to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"]]:
		plain = plain.replace(pair[0], pair[1])
	var out := ""
	for c in plain:
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	# Un nombre muy largo no da un ID de más de 64 letras.
	return out.lstrip("_").substr(0, 64).rstrip("_")


static func is_valid_id(id: String) -> bool:
	if id == "" or id.length() > 64:
		return false
	for c in id:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true


## Cuántas unidades entran en una pila de ese tipo (como InvItemDef.stack_limit).
static func stack_limit(def: Resource) -> int:
	return maxi(int(def.get(&"max_stack")), 1) if def.get(&"stackable") else 1


## Lo que impide guardar ese borrador. `original`: el recurso que se edita, o
## null si es nuevo (entonces `path` es donde se va a crear y `catalog`, donde
## se va a sumar).
static func check_item(draft: Resource, path: String, original: Resource, catalog: Resource) -> PackedStringArray:
	var errors := PackedStringArray()
	if String(draft.get(&"display_name")).strip_edges() == "":
		errors.append("Poné un nombre visible.")
	var id := String(draft.get(&"id"))
	if id.length() > 64:
		errors.append("El ID tiene más de 64 letras: acortalo.")
	elif not is_valid_id(id):
		errors.append("El ID tiene que tener solo minúsculas sin tildes, números y _ (por ejemplo cuerda_larga).")
	if original == null:
		if catalog == null:
			errors.append("No encontré el catálogo (%s)." % Destinos.CATALOG_PATH)
		else:
			for item: Resource in catalog.get(&"items"):
				if item != null and String(item.get(&"id")) == id:
					errors.append("Ya hay un objeto con el ID %s en el catálogo (%s)." % [id, item.resource_path.get_file()])
		var path_problem := Destinos.check_new_path(path, "tres")
		if path_problem != "":
			errors.append(path_problem)
	elif id != String(original.get(&"id")):
		errors.append("El ID de un objeto ya creado no se cambia desde acá: cambiarlo rompería sus referencias.")
	var cells: Vector2i = draft.get(&"size")
	if cells.x < 1 or cells.y < 1 or cells.x > MAX_CELLS or cells.y > MAX_CELLS:
		errors.append("El tamaño en la grilla va de 1 a %d celdas por lado." % MAX_CELLS)
	var max_stack := int(draft.get(&"max_stack"))
	if max_stack < 1 or max_stack > MAX_STACK:
		errors.append("El límite de la pila va de 1 a %d." % MAX_STACK)
	elif draft.get(&"stackable") and max_stack < 2:
		errors.append("Si se apila, en una pila tienen que entrar 2 o más.")
	var world_size := float(draft.get(&"world_size"))
	if not is_finite(world_size) or world_size < 0.02 or world_size > 10.0:
		errors.append("El tamaño en el mundo va de 0,02 a 10 m.")
	var zoom := float(draft.get(&"thumbnail_zoom"))
	if not is_finite(zoom) or zoom < 0.3 or zoom > 3.0:
		errors.append("El zoom de la miniatura va de 0,3 a 3.")
	var turn: Vector3 = draft.get(&"thumbnail_rotation")
	if not turn.is_finite():
		errors.append("El giro de la miniatura no es un número.")
	var shift: Vector2 = draft.get(&"thumbnail_offset")
	if not shift.is_finite() or absf(shift.x) > 1.0 or absf(shift.y) > 1.0:
		errors.append("En la miniatura, el objeto quedó corrido fuera del cuadro: apretá Centrar.")
	var hotbar_zoom := float(draft.get(&"hotbar_thumbnail_zoom"))
	if not is_finite(hotbar_zoom) or hotbar_zoom < 0.3 or hotbar_zoom > 3.0:
		errors.append("El zoom de la miniatura de la barra rápida va de 0,3 a 3.")
	var hotbar_turn: Vector3 = draft.get(&"hotbar_thumbnail_rotation")
	if not hotbar_turn.is_finite():
		errors.append("El giro de la miniatura de la barra rápida no es un número.")
	var hotbar_shift: Vector2 = draft.get(&"hotbar_thumbnail_offset")
	if not hotbar_shift.is_finite() or absf(hotbar_shift.x) > 1.0 or absf(hotbar_shift.y) > 1.0:
		errors.append("La miniatura de la barra rápida quedó corrida fuera del cuadro: apretá Centrar.")
	var model: Variant = draft.get(&"model")
	if model != null and not model is PackedScene:
		errors.append("El modelo tiene que ser una escena (.glb o .tscn).")
	var mesh: Variant = draft.get(&"mesh")
	if mesh != null and not mesh is Mesh:
		errors.append("La malla no es una malla.")
	var hitbox: Variant = draft.get(&"pickup_hitbox")
	if hitbox != null and not hitbox is InvPickupHitbox:
		errors.append("La hitbox de agarre no es una InvPickupHitbox.")
	elif hitbox != null:
		for problem in (hitbox as InvPickupHitbox).problems():
			errors.append("Hitbox de agarre: " + problem)
	errors.append_array(check_abilities(draft.get(&"abilities")))
	var state_problem := check_state(draft.get(&"default_state"))
	if state_problem != "":
		errors.append("Estado inicial: " + state_problem)
	return errors


## Problemas de la lista de capacidades: lugares vacíos, dos del mismo tipo o
## valores fuera de rango.
static func check_abilities(abilities: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for ability: Resource in abilities:
		if ability == null:
			errors.append("Hay un lugar vacío en la lista de capacidades: sacalo.")
			continue
		var kind := ability_kind(ability)
		if kind == "":
			continue
		if seen.has(kind):
			errors.append("Hay dos capacidades de %s: dejá una sola, si no, no se sabe cuál vale." % kind)
		seen[kind] = true
		if kind == "consumible":
			var health: Variant = ability.get(&"health")
			var stamina: Variant = ability.get(&"stamina")
			var over_time: Variant = ability.get(&"damage_over_time")
			var seconds: Variant = ability.get(&"damage_seconds")
			var parts: Variant = ability.get(&"part_repair")
			if typeof(health) != TYPE_INT or absi(health) > MAX_EFFECT:
				errors.append("El efecto en la salud del consumible va de −%d a %d." % [MAX_EFFECT, MAX_EFFECT])
			elif typeof(stamina) != TYPE_INT or stamina < 0 or stamina > MAX_EFFECT:
				errors.append("La estamina que recupera el consumible va de 0 a %d." % MAX_EFFECT)
			elif typeof(over_time) != TYPE_INT or over_time < 0 or over_time > MAX_EFFECT:
				errors.append("El daño en el tiempo del consumible va de 0 a %d puntos." % MAX_EFFECT)
			elif over_time > 0 and (typeof(seconds) != TYPE_FLOAT or not is_finite(seconds) or seconds < 0.1 or seconds > MAX_EFFECT_SECONDS):
				errors.append("El daño en el tiempo dura de 0,1 a %d segundos." % roundi(MAX_EFFECT_SECONDS))
			elif not typeof(parts) in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(parts)) or float(parts) < 0.0 or float(parts) > 100.0:
				errors.append("Lo que cura de una parte del cuerpo va de 0 a 100 %.")
			elif health == 0 and stamina == 0 and over_time == 0 and float(parts) == 0.0:
				errors.append("El consumible no hace nada: poné un efecto en la salud (cura o daña), estamina que recupere, un daño en el tiempo o lo que cura de una parte del cuerpo.")
		elif kind == "equipable":
			var offset: Vector3 = ability.get(&"hold_offset")
			var rotation: Vector3 = ability.get(&"hold_rotation")
			var hold_size := float(ability.get(&"hold_size"))
			if not offset.is_finite() or absf(offset.x) > 3.0 or absf(offset.y) > 3.0 or absf(offset.z) > 3.0:
				errors.append("La posición en la mano va de −3 a 3 m en cada eje.")
			if not rotation.is_finite() or absf(rotation.x) > 360.0 or absf(rotation.y) > 360.0 or absf(rotation.z) > 360.0:
				errors.append("El giro en la mano va de −360° a 360° en cada eje.")
			if not is_finite(hold_size) or hold_size < 0.02 or hold_size > 5.0:
				errors.append("El tamaño en la mano va de 0,02 a 5 m.")
	return errors


## Qué hace un consumible, en una oración, para el panel. Es lo mismo que dice
## InvConsumable.describe() en el juego (en el editor su script no corre).
static func consumable_summary(health: int, stamina: int, over_time := 0, seconds := 2.0, parts := 0.0) -> String:
	var effects := PackedStringArray()
	if health > 0:
		effects.append("cura %d de salud (sin pasar del máximo; con la salud completa no se usa ni se gasta)" % health)
	elif health < 0:
		effects.append("quita %d de salud (se usa aunque tengas la salud completa; si llega a 0, muerte de prueba)" % -health)
	if stamina > 0:
		effects.append("recupera %d de estamina (sin pasar de la reserva completa)" % stamina)
	if over_time > 0:
		var rate := over_time / maxf(seconds, 0.1)
		effects.append("quita %d de salud de a poco en %s s, %s por segundo (se usa con la salud completa; se corta si morís)" % [
				over_time, decimal(seconds), decimal(rate)])
	# Las partes del cuerpo no son el uso normal: van aparte (InvConsumable.describe).
	var on_part := ""
	if is_finite(parts) and parts > 0.0:
		on_part = "Con Tab, soltado sobre una parte dañada del cuerpo, %s y gasta una unidad, sin tocar la salud." % (
				"la deja entera" if parts >= 100.0 else "le devuelve %s %% (sin pasar del 100 %%)" % decimal(parts))
	if effects.is_empty():
		return "Así no hace nada: no se puede guardar." if on_part == "" \
				else "Usado normal (menú o barra rápida) no hace nada y no se gasta. %s" % on_part
	var normal := "Al usar una unidad: %s." % "; además, ".join(effects)
	return normal if on_part == "" else "%s %s" % [normal, on_part]


## Un número con hasta dos decimales, con coma y sin ceros de más: 2, 2,5, 0,33.
static func decimal(value: float) -> String:
	var rounded := snappedf(value, 0.01)
	if is_equal_approx(rounded, roundf(rounded)):
		return "%d" % roundi(rounded)
	return ("%.2f" % rounded).rstrip("0").replace(".", ",")


## "consumible", "equipable", o "" si el panel no la conoce (otra capacidad,
## que se conserva tal cual).
static func ability_kind(ability: Resource) -> String:
	var script: Script = ability.get_script() if ability != null else null
	if script == InvConsumable:
		return "consumible"
	if script == InvEquippable:
		return "equipable"
	return ""


## Si una capacidad es un archivo aparte (compartido), y no parte del objeto.
static func is_external(resource: Resource) -> bool:
	return resource != null and resource.resource_path != "" and not resource.resource_path.contains("::")


## Por qué ese estado no sirve, o "" si sirve. Las claves son textos; los
## valores, datos simples (números, textos, sí/no, vectores, colores, listas):
## nada de nodos, recursos ni código. Tiene que poder viajar por red igual.
static func check_state(state: Variant) -> String:
	if not state is Dictionary:
		return "no es una lista de datos."
	for key: Variant in state:
		if typeof(key) != TYPE_STRING or String(key).strip_edges() == "":
			return "cada dato necesita un nombre de texto, no vacío."
		var problem := _check_value(state[key])
		if problem != "":
			return "%s %s" % [key, problem]
	if bytes_to_var(var_to_bytes(state)) != state:
		return "no viajaría igual por red."
	return ""


static func _check_value(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I:
			return ""
		TYPE_FLOAT:
			return "" if is_finite(value) else "no es un número."
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR:
			return "" if value.is_finite() else "no es un número."
		TYPE_ARRAY:
			for item: Variant in value:
				var problem := _check_value(item)
				if problem != "":
					return problem
			return ""
		TYPE_DICTIONARY:
			return "" if check_state(value) == "" else "tiene adentro algo que no sirve."
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			return ""
	return "es de un tipo que no se guarda en el estado (%s)." % type_string(typeof(value))


## Avisos que no impiden guardar: si entra en la grilla del jugador y en los
## contenedores conocidos, y qué se ve. `boxes`: [{"name", "columns", "rows"}].
static func item_notes(draft: Resource, player: Vector2i, boxes: Array) -> PackedStringArray:
	var notes := PackedStringArray()
	var cells: Vector2i = draft.get(&"size")
	var rotates: bool = draft.get(&"can_rotate")
	if not fits(cells, rotates, player):
		notes.append("Con %d × %d no entra en la grilla del jugador (%d × %d): solo se podría guardar en un contenedor más grande." % [
				cells.x, cells.y, player.x, player.y])
	var small := PackedStringArray()
	for box: Dictionary in boxes:
		if not fits(cells, rotates, Vector2i(box["columns"], box["rows"])):
			small.append("%s (%d × %d)" % [box["name"], box["columns"], box["rows"]])
	if not small.is_empty():
		notes.append("No entra en: %s." % ", ".join(small))
	if not draft.get(&"stackable") and int(draft.get(&"max_stack")) > 1:
		notes.append("No se apila: el límite guardado (%d) no se usa." % int(draft.get(&"max_stack")))
	return notes


static func fits(cells: Vector2i, rotates: bool, grid: Vector2i) -> bool:
	return (cells.x <= grid.x and cells.y <= grid.y) or (rotates and cells.y <= grid.x and cells.x <= grid.y)


## Lo que cambia para lo que ya está colocado en la zona si se guarda ese
## borrador en lugar del original: marcadores con más unidades de las que
## entran en una pila. Nada se corrige solo: se avisa para que decidas.
static func edit_consequences(original: Resource, draft: Resource, zone_root: Node) -> PackedStringArray:
	var lines := PackedStringArray()
	if original == null:
		return lines
	# La hitbox de agarre no se mueve sola con el modelo (desde el 2026-11-07).
	var hitbox: Variant = draft.get(&"pickup_hitbox")
	if hitbox is InvPickupHitbox and (hitbox as InvPickupHitbox).is_configured() \
			and value_text(original.get(&"pickup_hitbox")) == value_text(hitbox) and look_changed(original, draft):
		lines.append("Cambió el modelo o su tamaño, y la hitbox de agarre quedó igual: puede que ya no le quede bien. Revisala en la vista previa (o apretá «Ajustar al modelo»), o guardá igual.")
	if zone_root == null:
		return lines
	var limit := stack_limit(draft)
	var markers := 0
	for marker in zone_root.find_children("*", "InvPickupSpawn", true, false):
		var item: Resource = marker.get(&"item")
		if item == null or item.resource_path != original.resource_path:
			continue
		markers += 1
		var quantity := int(marker.get(&"quantity"))
		if quantity > limit:
			lines.append("En la zona, %s tiene %d unidades y en una pila van a entrar %d: al jugar se recorta a %d. Cambiá su Quantity o dividilo." % [
					marker.name, quantity, limit, limit])
	if markers > 0 and Vector2i(draft.get(&"size")) != Vector2i(original.get(&"size")):
		lines.append("Cambia el tamaño en la grilla: los %d marcadores de la zona siguen igual; revisá que entre donde lo pensabas guardar." % markers)
	return lines


## Si cambia lo que hace la caja del modelo en el piso: el modelo, la malla, el
## tamaño en el piso o las celdas (la caja de color de los que no tienen modelo).
static func look_changed(before: Resource, after: Resource) -> bool:
	for field: StringName in [&"model", &"mesh", &"world_size", &"size"]:
		if value_text(before.get(field)) != value_text(after.get(field)):
			return true
	return false


## Crea un ítem nuevo: guarda el borrador en `path` y lo suma una vez al
## catálogo, apuntando al archivo. Si no se puede guardar el catálogo, borra el
## .tres recién creado.
static func create_item(draft: Resource, path: String, catalog: Resource, writer: Callable = Callable()) -> Dictionary:
	var write := _writer(writer)
	var errors := check_item(draft, path, null, catalog)
	if not errors.is_empty():
		return _fail("\n".join(errors))
	var files := EditorInterface.get_resource_filesystem()
	var saved: int = write.call(draft, path)
	if saved != OK:
		return _fail("No se pudo guardar %s (error %d). No se creó nada." % [path.get_file(), saved])
	# Sin su ruta, el catálogo guardaría una copia adentro de él en vez de
	# apuntar al .tres (guardar no se la deja puesta).
	draft.take_over_path(path)
	files.update_file(path)
	var problem := _append_to_catalog(draft, catalog, write)
	if problem == "":
		return {"ok": true, "message": "Guardado %s y sumado al catálogo." % path.get_file()}
	draft.resource_path = ""
	var removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	files.update_file(path)
	if removed == OK:
		return _fail("%s Se borró %s: no quedó nada creado." % [problem, path.get_file()])
	return _fail("%s Tampoco se pudo borrar %s (error %d): borralo a mano. El catálogo quedó como estaba." % [
			problem, path, removed])


## Suma un ítem que ya tiene su .tres (y no estaba en el catálogo).
static func add_to_catalog(def: Resource, catalog: Resource, writer: Callable = Callable()) -> Dictionary:
	if catalog == null:
		return _fail("No encontré el catálogo (%s)." % Destinos.CATALOG_PATH)
	if not is_external(def):
		return _fail("Primero guardalo en su archivo.")
	for item: Resource in catalog.get(&"items"):
		if item != null and String(item.get(&"id")) == String(def.get(&"id")):
			return _fail("Ya hay un objeto con el ID %s en el catálogo." % def.get(&"id"))
	var problem := _append_to_catalog(def, catalog, _writer(writer))
	return _fail(problem) if problem != "" else {"ok": true, "message": "Sumado al catálogo."}


static func _append_to_catalog(def: Resource, catalog: Resource, write: Callable) -> String:
	var items: Array = catalog.get(&"items")
	var before := items.duplicate()
	items.append(def)
	catalog.set(&"items", items)
	var saved: int = write.call(catalog, Destinos.CATALOG_PATH)
	if saved != OK:
		catalog.set(&"items", before)
		return "No se pudo guardar el catálogo (error %d)." % saved
	EditorInterface.get_resource_filesystem().update_file(Destinos.CATALOG_PATH)
	return ""


## Guarda lo editado en el borrador sobre el recurso original, en su mismo
## archivo: conserva su ruta, su uid y a todos los que lo usan. Solo pasa los
## campos de ITEM_FIELDS. Si falla, el original vuelve a como estaba.
## Después, el borrador comparte capacidades y malla con el original: hay que
## hacer otro (el panel lo hace).
static func save_item(original: Resource, draft: Resource, writer: Callable = Callable()) -> Dictionary:
	var errors := check_item(draft, original.resource_path, original, null)
	if not errors.is_empty():
		return _fail("\n".join(errors))
	var backup := {}
	for field in ITEM_FIELDS:
		backup[field] = original.get(field)
	for field in ITEM_FIELDS:
		original.set(field, field_copy(draft, field))
	var saved: int = _writer(writer).call(original, original.resource_path)
	if saved != OK:
		for field in ITEM_FIELDS:
			original.set(field, backup[field])
		return _fail("No se pudo guardar %s (error %d): quedó como estaba." % [original.resource_path.get_file(), saved])
	EditorInterface.get_resource_filesystem().update_file(original.resource_path)
	return {"ok": true, "message": "Guardado %s." % original.resource_path.get_file()}


## El valor de un campo para pasarlo a otro recurso: la lista de capacidades,
## como lista nueva con su tipo; el estado, copiado.
static func field_copy(source: Resource, field: StringName) -> Variant:
	var value: Variant = source.get(field)
	if field == &"abilities":
		var list: Array[InvAbility] = []
		for ability: Resource in value:
			list.append(ability)
		return list
	if field == &"default_state":
		return (value as Dictionary).duplicate(true)
	return value


## Una copia de trabajo de un ítem: sus capacidades, su malla interna, su
## hitbox de agarre (con su forma propia, si es interna) y su estado son
## copias; el modelo y lo que esté en archivos aparte se comparten.
static func working_copy(def: Resource) -> Resource:
	return def.duplicate(true)


## Todo lo que el panel edita de un ítem, como texto: dos textos iguales son
## el mismo contenido (sirve para saber si hay cambios sin guardar).
static func snapshot(def: Resource) -> String:
	if def == null:
		return ""
	var parts := PackedStringArray()
	for field in ITEM_FIELDS:
		parts.append("%s=%s" % [field, value_text(def.get(field))])
	return "\n".join(parts)


static func value_text(value: Variant) -> String:
	if value is Resource:
		var resource := value as Resource
		if is_external(resource):
			return "archivo(%s)" % resource.resource_path
		var script: Script = resource.get_script()
		var parts := PackedStringArray([resource.get_class(), script.resource_path if script != null else ""])
		for property in resource.get_property_list():
			if property["usage"] & PROPERTY_USAGE_STORAGE and not property["name"] in ["resource_path", "resource_name",
					"resource_local_to_scene", "script", "resource_scene_unique_id"]:
				parts.append("%s:%s" % [property["name"], value_text(resource.get(property["name"]))])
		return "{%s}" % " ".join(parts)
	if value is Array:
		var parts := PackedStringArray()
		for item: Variant in value:
			parts.append(value_text(item))
		return "[%s]" % ", ".join(parts)
	return var_to_str(value)


# --- Contenedores ----------------------------------------------------------------

## Los valores de un contenedor nuevo, como los de caja.tscn.
static func box_defaults() -> Dictionary:
	var script: Script = InvContainer
	var values := {"node_name": "Contenedor"}
	for field in BOX_FIELDS:
		values[field] = script.get_property_default_value(field)
	return values


## Los valores de un contenedor desde su escena guardada (sin abrirla en el
## editor), o {} si no es un contenedor.
static func box_values(path: String) -> Dictionary:
	var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if scene == null:
		return {}
	var root := scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if root == null:
		return {}
	var values := {}
	if root.get_script() == InvContainer:
		values["node_name"] = String(root.name)
		for field in BOX_FIELDS:
			values[field] = root.get(field)
	root.free()
	return values


static func box_snapshot(values: Dictionary) -> String:
	return var_to_str(values)


## Lo que impide guardar un contenedor. `path`: dónde se crea, si es nuevo.
static func check_box(values: Dictionary, path: String, is_new: bool) -> PackedStringArray:
	var errors := PackedStringArray()
	if String(values["display_name"]).strip_edges() == "":
		errors.append("Poné un nombre visible.")
	var node_name := String(values["node_name"])
	if node_name == "" or node_name.validate_node_name() != node_name:
		errors.append("El nombre del nodo no puede estar vacío ni tener . : @ / \" %.")
	var columns := int(values["columns"])
	var rows := int(values["rows"])
	if columns < 1 or rows < 1 or columns > MAX_CELLS or rows > MAX_CELLS:
		errors.append("Las columnas y las filas van de 1 a %d." % MAX_CELLS)
	var size: Vector3 = values["box_size"]
	if not size.is_finite() or size.x < 0.1 or size.y < 0.1 or size.z < 0.1 or size.x > 10.0 or size.y > 10.0 or size.z > 10.0:
		errors.append("Las medidas de la caja van de 0,1 a 10 m.")
	if is_new:
		var path_problem := Destinos.check_new_path(path, "tscn", Destinos.CONTAINERS_DIR)
		if path_problem != "":
			errors.append(path_problem)
	return errors


## Crea la escena de un contenedor nuevo, heredada de caja.tscn: la caja trae
## su InvContainer, su hijo Inventario (InvInventory) y la referencia entre los
## dos; la escena nueva solo cambia los valores. Cada caja colocada tiene su
## propio nodo Inventario, así que no comparten lo que tienen adentro.
static func create_box(values: Dictionary, path: String, writer: Callable = Callable()) -> Dictionary:
	var errors := check_box(values, path, true)
	if not errors.is_empty():
		return _fail("\n".join(errors))
	var root := _box_seed()
	if root == null:
		return _fail("No pude armar la caja desde %s. No se creó nada." % Destinos.BOX_BASE_PATH)
	root.name = String(values["node_name"])
	for field in BOX_FIELDS:
		root.set(field, values[field])
	var problem := check_box_node(root)
	var packed := PackedScene.new()
	var packed_ok := packed.pack(root) if problem == "" else FAILED
	root.free()
	if problem != "":
		return _fail(problem + " No se creó nada.")
	if packed_ok != OK:
		return _fail("No se pudo armar la escena (error %d). No se creó nada." % packed_ok)
	var dir := path.get_base_dir()
	var made_dir := not DirAccess.dir_exists_absolute(dir)
	if made_dir:
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			return _fail("No se pudo crear la carpeta %s (error %d). No se creó nada." % [dir, made])
	var saved: int = _writer(writer).call(packed, path)
	var files := EditorInterface.get_resource_filesystem()
	if saved != OK:
		if made_dir:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
		return _fail("No se pudo guardar %s (error %d). No se creó nada." % [path.get_file(), saved])
	packed.take_over_path(path)
	if made_dir:
		files.scan()
	else:
		files.update_file(path)
	return {"ok": true, "message": "Guardado %s." % path.get_file()}


## Si ese nodo es un contenedor bien armado: un InvContainer con su Inventory
## apuntando a un InvInventory suyo. "" si está bien.
static func check_box_node(root: Node) -> String:
	if root == null or root.get_script() != InvContainer:
		return "La escena no es un contenedor (InvContainer)."
	var inventory: Variant = root.get(&"inventory")
	if not inventory is Node or not root.is_ancestor_of(inventory) or (inventory as Node).get_script() != InvInventory:
		return "El contenedor no tiene su Inventory apuntando a un nodo InvInventory suyo."
	return ""


## Guarda lo editado de un contenedor que ya existe, en su misma escena. Lo
## hace el editor (la abre, cambia la raíz y la guarda), así las cajas
## colocadas en otras escenas abiertas toman los valores nuevos y se conservan
## los nodos que le hayas agregado. No se hace si esa escena ya tenía cambios
## sin guardar: no se guarda trabajo ajeno. Las otras escenas con cambios sin
## guardar que usan esa caja siguen marcadas así (_keep_unsaved).
static func save_box(path: String, values: Dictionary) -> Dictionary:
	var errors := check_box(values, path, false)
	if not errors.is_empty():
		return _fail("\n".join(errors))
	# Qué tenía cambios sin guardar antes de empezar: eso no se guarda ni se
	# recarga.
	var unsaved := EditorInterface.get_unsaved_scenes()
	if path in unsaved:
		return _fail("%s está abierta en el editor con cambios sin guardar: guardala o descartalos y probá de nuevo." % path.get_file())
	var current := EditorInterface.get_edited_scene_root()
	var previous := current.scene_file_path if current != null else ""
	var was_open := path in EditorInterface.get_open_scenes()
	EditorInterface.open_scene_from_path(path)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != path:
		return _fail("No pude abrir %s." % path.get_file())
	var problem := check_box_node(root)
	if problem != "":
		_leave(path, was_open, previous)
		return _fail(problem)
	var backup := {"node_name": root.name}
	for field in BOX_FIELDS:
		backup[field] = root.get(field)
	_apply_box(root, values)
	var saved := EditorInterface.save_scene()
	if saved != OK:
		_apply_box(root, backup)
		EditorInterface.mark_scene_as_unsaved()
		_leave(path, was_open, previous)
		return _fail("No se pudo guardar %s (error %d): la escena quedó abierta como estaba, sin guardar." % [path.get_file(), saved])
	_leave(path, was_open, previous)
	var message := "Guardado %s." % path.get_file()
	var rebuilt := _keep_unsaved(path, unsaved, previous)
	var stale := _refresh_instances(path, unsaved, rebuilt)
	if not rebuilt.is_empty():
		message += " %s tiene cambios sin guardar: el editor la volvió a armar con las cajas nuevas y eso borró su historial de deshacer (Ctrl+Z ya no vuelve a lo de antes de guardar la caja). Tus cambios siguen ahí y sigue marcada sin guardar." \
				% ", ".join(Array(rebuilt).map(func(scene: String) -> String: return scene.get_file()))
	if not stale.is_empty():
		message += " %s tiene cambios sin guardar: hasta que la guardes y la vuelvas a abrir, el editor muestra esas cajas con los valores de antes (al jugar ya salen con los nuevos)." \
				% ", ".join(stale)
	return {"ok": true, "message": message}


## Las escenas que ya tenían cambios sin guardar y usan esa caja (desde la
## auditoría del 2026-11-08, OBJ-02). Al volver a una de ellas, el editor de
## Godot a veces la vuelve a armar con las cajas nuevas: cuando nota que el
## archivo de la caja cambió (según su hora de modificación, que va de a
## segundo). Así los cambios en memoria siguen, pero borra su historial de
## deshacer, y con él la marca de cambios sin guardar: el panel dejaba de
## ofrecer «Guardar la zona» y nada avisaba. Acá se pasa por cada una (así el
## editor hace eso ahora y no más tarde, por sorpresa); si perdió la marca, se
## le vuelve a poner. Devuelve las que el editor volvió a armar. Termina en la
## escena que estaba a la vista.
static func _keep_unsaved(path: String, unsaved: PackedStringArray, previous: String) -> PackedStringArray:
	var rebuilt := PackedStringArray()
	var touched := false
	for scene in unsaved:
		if scene == path or not scene in EditorInterface.get_open_scenes():
			continue
		var root := _open_root(scene)
		if root == null or not _uses(root, path):
			continue
		var current := EditorInterface.get_edited_scene_root()
		if current == null or current.scene_file_path != scene:
			EditorInterface.open_scene_from_path(scene)
			touched = true
		if not scene in EditorInterface.get_unsaved_scenes():
			EditorInterface.mark_scene_as_unsaved()
			rebuilt.append(scene)
	if touched and previous != "" and previous in EditorInterface.get_open_scenes():
		EditorInterface.open_scene_from_path(previous)
	return rebuilt


## La raíz de esa escena abierta en el editor, o null.
static func _open_root(scene: String) -> Node:
	for root: Node in EditorInterface.get_open_scene_roots():
		if root != null and root.scene_file_path == scene:
			return root
	return null


## Si en esa escena hay alguna instancia de `path`.
static func _uses(root: Node, path: String) -> bool:
	return root.find_children("*", "", true, true).any(func(node: Node) -> bool: return node.scene_file_path == path)


## Las escenas abiertas que tienen cajas de ese contenedor siguen mostrando los
## valores viejos: el editor no siempre las actualiza solo. Las que no tienen
## cambios sin guardar se vuelven a cargar; las otras no se tocan (se perdería
## ese trabajo) y se devuelven sus nombres, salvo las que el editor ya volvió a
## armar (`rebuilt`, de _keep_unsaved): esas ya muestran los valores nuevos.
static func _refresh_instances(path: String, unsaved: PackedStringArray, rebuilt := PackedStringArray()) -> PackedStringArray:
	var stale := PackedStringArray()
	unsaved = unsaved + EditorInterface.get_unsaved_scenes()
	var reload := PackedStringArray()
	for root: Node in EditorInterface.get_open_scene_roots():
		if root == null or root.scene_file_path == path or root.scene_file_path == "" or root.scene_file_path in rebuilt:
			continue
		if not _uses(root, path):
			continue
		if root.scene_file_path in unsaved:
			stale.append(root.scene_file_path.get_file())
		else:
			reload.append(root.scene_file_path)
	for scene in reload:
		EditorInterface.reload_scene_from_path(scene)
	return stale


static func _apply_box(root: Node, values: Dictionary) -> void:
	root.name = String(values["node_name"])
	for field in BOX_FIELDS:
		root.set(field, values[field])


## Deja las pestañas del editor como estaban: cierra la escena si la abrió el
## panel y vuelve a la que estaba a la vista.
static func _leave(path: String, was_open: bool, previous: String) -> void:
	if not was_open and EditorInterface.get_edited_scene_root() != null \
			and EditorInterface.get_edited_scene_root().scene_file_path == path:
		EditorInterface.close_scene()
	if previous != "" and previous != path:
		EditorInterface.open_scene_from_path(previous)


## La raíz de una caja heredada de caja.tscn, sin guardar todavía. El editor
## arma una escena heredada desde un archivo que diga de cuál hereda: se
## escribe uno de paso afuera del proyecto y se borra enseguida.
static func _box_seed() -> Node:
	var file := FileAccess.open(SEED_PATH, FileAccess.WRITE)
	if file == null:
		return null
	file.store_string('[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="%s" id="1_base"]\n\n[node name="Contenedor" instance=ExtResource("1_base")]\n'
			% Destinos.BOX_BASE_PATH)
	file.close()
	var seed := ResourceLoader.load(SEED_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SEED_PATH))
	return seed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN) if seed != null else null


static func _writer(writer: Callable) -> Callable:
	if writer.is_valid():
		return writer
	return func(resource: Resource, path: String) -> int: return ResourceSaver.save(resource, path)


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}

