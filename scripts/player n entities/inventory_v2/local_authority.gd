class_name LocalAuthority
extends Node

## Frontera explicita de autoridad (INV-08; docs/inventory_system_v0_v1.md
## secciones 6 y 13).
##
## Es el UNICO punto con permiso para invocar TransferOperation.validate() /
## commit(). Cualquier componente que quiera mover un ItemInstance (WorldItemV2;
## a futuro tambien Inventory-a-Inventory, UI, etc.) le SOLICITA a esta
## autoridad — nunca ejecuta la operacion por su cuenta.
##
## SIN MEMORIA DE ROUTING: cada solicitud especifica explicitamente sobre que
## InventoryV2 opera. La autoridad no guarda estado de "a que inventario van
## los pickups"; es intencionalmente el nodo mas "tonto" posible. Esto es lo
## que permite que el dia de mañana una autoridad remota (servidor) ocupe este
## mismo rol —arbitrando para muchos inventarios— sin reescribir Inventory,
## WorldItem ni TransferOperation.
##
## No es autoload ni manager global: vive como nodo de la entidad (o escena)
## que lo necesita. Para PlayerV2: una LocalAuthority por entidad, hermana de
## su InventoryV2 y su InventoryReceiver.

var _log_habilitado: bool = true

## Solicitud de pickup: mundo -> `inventory`.
## Devuelve true si la transferencia se completo, false si no.
func solicitar_pickup(world_item: WorldItemV2, inventory: InventoryV2) -> bool:
	if inventory == null:
		_log("pickup solicitado sin InventoryV2 destino")
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

## Solicitud de devolucion: `inventory` -> mundo.
## Devuelve el WorldItemV2 creado, o null si fallo. El WorldItemV2 nace
## NEUTRAL: no queda pre-atado a ninguna autoridad — quien lo recoja despues
## se resuelve por Interaction.actor -> InventoryReceiver.
func solicitar_devolucion(item_instance: ItemInstance, inventory: InventoryV2, parent: Node3D, position: Vector3) -> WorldItemV2:
	_log("SOLICITUD devolucion: %s | origen=Inventory(%s) | destino=World" % [item_instance, inventory.name])

	var op := TransferOperation.crear_inventario_a_mundo(item_instance, inventory, parent, position)
	var valido := op.validate()
	_log("VALIDATE devolucion: %s -> %s" % [item_instance, op.get_resultado_validacion()])

	if not valido:
		_log("COMMIT abortado (validacion fallida). %s permanece en el inventario." % item_instance)
		return null

	var nuevo_world_item: WorldItemV2 = op.commit()
	_log("COMMIT devolucion: %s -> exito=%s | contexto ahora=World" % [item_instance, nuevo_world_item != null])
	return nuevo_world_item

## Solicitud de reubicacion: mover y/o rotar un ItemInstance DENTRO de
## `inventory` (V1). Mismo patron que solicitar_pickup: construir la operacion,
## validar, y recien entonces commitear. Devuelve true si la reubicacion se
## completo, false si la validacion la rechazo (en cuyo caso el inventario
## queda identico y no se emite contenido_cambiado).
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

func _log(mensaje: String) -> void:
	if _log_habilitado:
		print("[LocalAuthority] ", mensaje)
