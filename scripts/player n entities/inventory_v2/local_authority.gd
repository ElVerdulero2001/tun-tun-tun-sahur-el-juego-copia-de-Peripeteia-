class_name LocalAuthority
extends Node

## Frontera explicita de autoridad (INV-08, doc V0 seccion 7 del encargo).
##
## Este nodo es el UNICO lugar de esta escena de prueba con permiso para
## invocar TransferOperation.validate() / commit(). Cualquier componente
## que quiera mover un ItemInstance (WorldItemV2, en V0; a futuro tambien
## Inventory-a-Inventory, UI, etc.) le SOLICITA a esta autoridad — nunca
## ejecuta la operacion por su cuenta.
##
## En V0 la autoridad es local (este mismo nodo, sin red). El objetivo
## de que exista esta frontera separada — en vez de que cada solicitante
## llame TransferOperation directamente — es que el dia de mañana una
## autoridad remota (servidor) pueda ocupar este mismo rol sin que
## Inventory, WorldItem ni TransferOperation deban reescribirse. No se
## implementa ningun transporte de red aca: es intencionalmente el nodo
## mas "tonto" posible.
##
## No confundir con un manager global: esto NO es autoload, vive como
## nodo de la escena de prueba concreta, inyectado via setup() a quien
## lo necesite (mismo patron que Player inyecta sus controllers).

var _log_habilitado: bool = true

## Solicitud de pickup: mundo -> inventario.
## Devuelve true si la transferencia se completo, false si no.
func solicitar_pickup(world_item: WorldItemV2) -> bool:
	var inventory := _encontrar_inventory_receptor()
	if inventory == null:
		_log("pickup solicitado pero no hay Inventory receptor configurado")
		return false

	var item := world_item.item_instance
	_log("SOLICITUD pickup: %s | origen=World | destino=Inventory(%s)" % [item, inventory.name])

	var op := TransferOperation.crear_mundo_a_inventario(world_item, inventory)
	var valido := op.validate()
	_log("VALIDATE pickup: %s -> %s" % [item, op.get_resultado_validacion()])

	if not valido:
		_log("COMMIT abortado (validacion fallida). %s permanece en el mundo." % item)
		return false

	var resultado: bool = op.commit()
	_log("COMMIT pickup: %s -> exito=%s | contexto ahora=Inventory(%s)" % [item, resultado, inventory.name])
	return resultado

## Solicitud de devolucion: inventario -> mundo.
## Devuelve el WorldItemV2 creado, o null si fallo.
func solicitar_devolucion(item_instance: ItemInstance, inventory: InventoryV2, parent: Node3D, position: Vector3) -> WorldItemV2:
	_log("SOLICITUD devolucion: %s | origen=Inventory(%s) | destino=World" % [item_instance, inventory.name])

	var op := TransferOperation.crear_inventario_a_mundo(item_instance, inventory, parent, position)
	var valido := op.validate()
	_log("VALIDATE devolucion: %s -> %s" % [item_instance, op.get_resultado_validacion()])

	if not valido:
		_log("COMMIT abortado (validacion fallida). %s permanece en el inventario." % item_instance)
		return null

	var nuevo_world_item: WorldItemV2 = op.commit()
	if nuevo_world_item:
		nuevo_world_item.setup(self)
	_log("COMMIT devolucion: %s -> exito=%s | contexto ahora=World" % [item_instance, nuevo_world_item != null])
	return nuevo_world_item

## Solicitud de reubicacion: mover y/o rotar un ItemInstance DENTRO de su
## mismo InventoryV2 (V1). Mismo patron que solicitar_pickup: construir la
## operacion, validar, y recien entonces commitear. Devuelve true si la
## reubicacion se completo, false si la validacion la rechazo (en cuyo caso
## el inventario queda identico y no se emite contenido_cambiado).
func solicitar_reubicacion(item_instance: ItemInstance, inventory: InventoryV2, nueva_pos: Vector2i, nuevo_rotated: bool) -> bool:
	_log("SOLICITUD reubicacion: %s | Inventory(%s) -> celda %s rotated=%s" % [item_instance, inventory.name, nueva_pos, nuevo_rotated])

	var op := TransferOperation.crear_reubicar(item_instance, inventory, nueva_pos, nuevo_rotated)
	var valido := op.validate()
	_log("VALIDATE reubicacion: %s -> %s" % [item_instance, op.get_resultado_validacion()])

	if not valido:
		_log("COMMIT abortado (validacion fallida). %s no se movio." % item_instance)
		return false

	var resultado: bool = op.commit()
	_log("COMMIT reubicacion: %s -> exito=%s | celda ahora=%s rotated=%s" % [item_instance, resultado, nueva_pos, nuevo_rotated])
	return resultado

## En V0 solo hay un inventario receptor posible: el hijo InventoryV2
## de la entidad "jugador" de prueba. Esto es deliberadamente ingenuo
## (ver deuda tecnica en el resumen final) — resolver "a que inventario
## va este pickup" con criterio real (cual jugador, que entidad) es
## logica de interaccion/targeting que esta fuera del alcance de V0.
var _inventory_receptor: InventoryV2 = null

func set_inventory_receptor(inventory: InventoryV2) -> void:
	_inventory_receptor = inventory

func _encontrar_inventory_receptor() -> InventoryV2:
	return _inventory_receptor

func _log(mensaje: String) -> void:
	if _log_habilitado:
		print("[LocalAuthority] ", mensaje)
