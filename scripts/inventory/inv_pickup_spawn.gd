@tool
class_name InvPickupSpawn
extends Marker3D

## Dónde empieza un objeto en el mundo, para recogerlo con E. Al arrancar, el
## host crea ahí el objeto (con un id nuevo) y se lo cuenta a todos; el
## marcador en sí no se ve en el juego. Su posición es la base del objeto.
##
## Desde el 2026-11-14 los objetos sueltos tienen física y giran: el objeto
## arranca también con el giro del marcador (spawn_transform), y la vista
## previa del editor lo muestra así. Un marcador sin girar, como todos los de
## antes, lo deja igual que siempre. La escala del marcador no cuenta (el
## cuerpo físico no se escala). El objeto arranca quieto y dormido, donde está
## el marcador: no se mueve hasta que algo lo toca o alguien lo agarra. Un
## marcador en el aire deja el objeto flotando hasta entonces.

@export var item: InvItemDef:
	set(value):
		if item == value:
			return
		if Engine.is_editor_hint() and item != null:
			item.changed.disconnect(_queue_preview)
		item = value
		if Engine.is_editor_hint():
			if item != null:
				item.changed.connect(_queue_preview)
			_queue_preview()

## Si una escena vieja excede la pila, el host recorta la cantidad y avisa.
@export_range(1, 9999) var quantity := 1:
	set(value):
		quantity = value
		if Engine.is_editor_hint() and is_inside_tree():
			update_configuration_warnings()

## Lo que cambia del estado de fábrica del tipo, por ejemplo {"carga": 40}.
@export var state_override := {}

## El cartel que flota sobre el objeto en el juego, con su nombre y su
## cantidad. Apagado, el objeto aparece sin cartel; el indicador de lo que se
## mira igual muestra su nombre. El host lo manda con cada objeto. Entra en la
## huella del laboratorio, como los demás valores de este nodo, por el texto de
## la zona o del nivel donde está (SimFingerprint.level_text, que recorre los
## valores exportados de cada nodo con script) y no por
## InvNet.fingerprint_text: las dos PC lo tienen igual o la otra no entra. Lo
## comprueba inv_lab_test. Si alguien lo recoge y lo vuelve a soltar, ya es
## otro objeto y lleva cartel (desde el 2026-11-06).
@export var show_label := true

var _preview: Node3D
var _preview_pending := false


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		_queue_preview()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_instance_valid(_preview):
		# Al aparecer, el host toma el lugar y el giro del marcador, sin su escala.
		_preview.global_transform = spawn_transform()


func _validate_property(property: Dictionary) -> void:
	if property["name"] == &"quantity" and item != null:
		property["hint_string"] = "1,%d,1" % item.stack_limit()


func _get_configuration_warnings() -> PackedStringArray:
	if item == null:
		return PackedStringArray(["Elegí un ítem en el Inspector."])
	var limit := item.stack_limit()
	if quantity < 1 or quantity > limit:
		return PackedStringArray(["La cantidad debe estar entre 1 y %d para este ítem." % limit])
	return PackedStringArray()


func _queue_preview() -> void:
	if is_inside_tree() and not _preview_pending:
		_preview_pending = true
		_refresh_preview.call_deferred()


func _refresh_preview() -> void:
	_preview_pending = false
	if not is_inside_tree():
		return
	if is_instance_valid(_preview):
		remove_child(_preview)
		_preview.queue_free()
		_preview = null
	if item != null:
		_preview = InvVisuals.world_model(item)
		_preview.top_level = true
		add_child(_preview, false, Node.INTERNAL_MODE_BACK)
		_preview.global_transform = spawn_transform()
	notify_property_list_changed()
	update_configuration_warnings()


## Dónde y con qué giro aparece el objeto: el lugar y el giro del marcador en
## el mundo, sin escala.
func spawn_transform() -> Transform3D:
	return Transform3D(global_basis.orthonormalized(), global_position)


func initial_state() -> Dictionary:
	var state := item.default_state.duplicate(true) if item != null else {}
	state.merge(state_override, true)
	return state
