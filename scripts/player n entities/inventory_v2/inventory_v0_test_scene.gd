extends Node3D

## Coordinador de la escena de prueba V0 (Mundo -> Inventario -> Mundo).
## No es parte del sistema de inventario en si: es el arnes de prueba
## que arma las referencias y expone un input de debug para la mitad
## "devolver al mundo" del ciclo, que en V0 no tiene todavia un
## disparador de gameplay real (eso queda fuera de alcance a proposito).
##
## Responsabilidad: instanciar el ItemInstance inicial, inyectar la
## LocalAuthority donde corresponda (mismo patron setup() que Player),
## y and loguear el estado antes/despues de cada ciclo para poder
## verificar el ID logico en runtime.

@export var item_definition_test: ItemDefinition

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inventory: InventoryV2 = $EntidadConInventario/InventoryV2
@onready var world_item_inicial: WorldItemV2 = $test_item_v0
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo

func _ready() -> void:
	authority.set_inventory_receptor(inventory)

	var item := ItemInstance.new(item_definition_test)
	world_item_inicial.item_instance = item
	world_item_inicial.setup(authority)

	print("[TestScene] Listo. Item inicial: ", item, " en el mundo.")
	print("[TestScene] Mira el objeto e interactua (tecla 'interactuar') para recogerlo.")
	print("[TestScene] Con el item en el inventario, presiona 'ui_accept' (Enter/Espacio) para devolverlo al mundo.")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_solicitar_devolucion_debug()

## Devuelve al mundo el primer item que encuentre en el inventario de
## prueba. Es deliberadamente el metodo mas simple posible: V0 no
## implementa todavia drop/throw/place/give/equip, solo UNA forma
## generica de devolucion (docs/inventory_system_v0_v1.md seccion 18).
func _solicitar_devolucion_debug() -> void:
	var entries := inventory.get_entries()
	if entries.is_empty():
		print("[TestScene] Inventario vacio, nada que devolver.")
		return

	var item := entries[0].item_instance
	var nuevo_world_item := authority.solicitar_devolucion(
		item, inventory, self, punto_spawn.global_position
	)
	if nuevo_world_item:
		print("[TestScene] Devuelto al mundo: ", item)
	else:
		print("[TestScene] No se pudo devolver: ", item)
