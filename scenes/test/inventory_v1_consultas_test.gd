extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory V1 · Paso 1.
##
## Ejercita ÚNICAMENTE las consultas read-only agregadas a inventory.gd:
##   - entry_en_celda(celda)
##   - celdas_ocupadas_por(entry)
##   - posicion_valida(item_instance, pos, rotated, excluir)
##
## Ninguna de las tres muta el InventoryV2, y este arnés tampoco: el
## inventario se puebla EXCLUSIVAMENTE por la ruta V0 (spawn de WorldItemV2
## + LocalAuthority -> pickup), sin backdoors de mutación.
##
## No hay UI ni reubicación: eso es Paso 2 en adelante.

@export var item_definition_test: ItemDefinition

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv_normal: InventoryV2 = $InventarioNormal      # 4x4
@onready var inv_angosto: InventoryV2 = $InventarioAngosto    # 1x4: fuerza rotación en el pickup
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== INVENTORY V1 · PASO 1 · CONSULTAS READ-ONLY =====")

	var normal := _sembrar(inv_normal, 3)
	var angosto := _sembrar(inv_angosto, 1)

	# Snapshot POR VALOR (no por referencia) del estado tras sembrar, para
	# poder detectar cualquier mutación provocada por las consultas.
	var pos_prev: Array[Vector2i] = []
	var rot_prev: Array[bool] = []
	var id_prev: Array[int] = []
	for e in normal:
		pos_prev.append(e.position)
		rot_prev.append(e.rotated)
		id_prev.append(e.item_instance.instance_id)

	_test_layout_sembrado(normal, angosto)
	_test_entry_en_celda(normal)
	_test_celdas_ocupadas_por(normal, angosto)
	_test_posicion_valida(normal)
	_test_no_mutacion(normal, pos_prev, rot_prev, id_prev)

	print("======================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: PASO 1 OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos del Paso 1 de V1")
	get_tree().quit(_fallos)


## Puebla `inventario` con `cantidad` ítems del mismo tipo usando SOLO la
## ruta V0. Devuelve las entries resultantes en orden de pickup.
func _sembrar(inventario: InventoryV2, cantidad: int) -> Array[InventoryEntry]:
	authority.set_inventory_receptor(inventario)
	for i in range(cantidad):
		var wi: WorldItemV2 = item_definition_test.world_scene.instantiate()
		wi.item_instance = ItemInstance.new(item_definition_test)
		add_child(wi)
		wi.global_position = punto_spawn.global_position
		wi.setup(authority)
		var ok: bool = wi._on_interact(Interaction.new(self, &"usar"))
		_check(ok, "siembra: pickup #%d en %s exitoso" % [i + 1, inventario.name])
	return inventario.get_entries()


## Documenta y fija la disposición que produce el first-fit de V0, de la
## que dependen el resto de los asserts.
func _test_layout_sembrado(normal: Array[InventoryEntry], angosto: Array[InventoryEntry]) -> void:
	print("-- layout sembrado (first-fit de V0) --")
	_check(normal.size() == 3, "inv_normal: 3 entries")
	_check(normal[0].position == Vector2i(0, 0) and not normal[0].rotated, "entry #1 en (0,0) sin rotar")
	_check(normal[1].position == Vector2i(2, 0) and not normal[1].rotated, "entry #2 en (2,0) sin rotar")
	_check(normal[2].position == Vector2i(0, 1) and not normal[2].rotated, "entry #3 en (0,1) sin rotar")
	_check(angosto.size() == 1, "inv_angosto: 1 entry")
	_check(angosto[0].position == Vector2i(0, 0) and angosto[0].rotated,
		"entry angosta en (0,0) ROTADA (grilla 1x4 obliga a rotar un 2x1)")


func _test_entry_en_celda(normal: Array[InventoryEntry]) -> void:
	print("-- entry_en_celda --")
	_check(inv_normal.entry_en_celda(Vector2i(0, 0)) == normal[0], "(0,0) -> entry #1")
	_check(inv_normal.entry_en_celda(Vector2i(1, 0)) == normal[0], "(1,0) -> entry #1 (2da celda de su footprint)")
	_check(inv_normal.entry_en_celda(Vector2i(2, 0)) == normal[1], "(2,0) -> entry #2")
	_check(inv_normal.entry_en_celda(Vector2i(3, 0)) == normal[1], "(3,0) -> entry #2 (2da celda de su footprint)")
	_check(inv_normal.entry_en_celda(Vector2i(0, 1)) == normal[2], "(0,1) -> entry #3")
	_check(inv_normal.entry_en_celda(Vector2i(0, 2)) == null, "(0,2) -> null (celda libre)")
	_check(inv_normal.entry_en_celda(Vector2i(3, 3)) == null, "(3,3) -> null (celda libre)")


func _test_celdas_ocupadas_por(normal: Array[InventoryEntry], angosto: Array[InventoryEntry]) -> void:
	print("-- celdas_ocupadas_por --")
	var c1 := inv_normal.celdas_ocupadas_por(normal[0])
	_check(
		c1.size() == 2 and c1.has(Vector2i(0, 0)) and c1.has(Vector2i(1, 0)),
		"entry #1 (sin rotar) ocupa (0,0),(1,0) -> %s" % [c1]
	)
	var ca := inv_angosto.celdas_ocupadas_por(angosto[0])
	_check(
		ca.size() == 2 and ca.has(Vector2i(0, 0)) and ca.has(Vector2i(0, 1)),
		"entry angosta (rotada) ocupa (0,0),(0,1) -> %s" % [ca]
	)


func _test_posicion_valida(normal: Array[InventoryEntry]) -> void:
	print("-- posicion_valida --")
	var it0: ItemInstance = normal[0].item_instance   # 2x1, can_rotate

	# Límites de grilla
	_check(not inv_normal.posicion_valida(it0, Vector2i(-1, 0), false), "x=-1 -> fuera de límites")
	_check(not inv_normal.posicion_valida(it0, Vector2i(3, 0), false), "(3,0) 2x1 se sale por derecha -> inválido")
	_check(not inv_normal.posicion_valida(it0, Vector2i(0, 3), true), "(0,3) rotado 1x2 se sale por abajo -> inválido")

	# Solapamiento SIN excluir
	_check(not inv_normal.posicion_valida(it0, Vector2i(0, 0), false), "(0,0) sin excluir -> solapa entry #1")
	_check(not inv_normal.posicion_valida(it0, Vector2i(1, 0), false), "(1,0) sin excluir -> solapa entries #1/#2")

	# Huecos libres
	_check(inv_normal.posicion_valida(it0, Vector2i(2, 1), false), "(2,1) 2x1 -> hueco libre -> válido")
	_check(inv_normal.posicion_valida(it0, Vector2i(2, 1), true), "(2,1) rotado 1x2 -> hueco libre -> válido")

	# excluir: el caso central de la reubicación
	_check(
		inv_normal.posicion_valida(it0, Vector2i(0, 0), false, normal[0]),
		"(0,0) excluyendo la PROPIA entry -> válido (no choca consigo misma)"
	)
	_check(
		not inv_normal.posicion_valida(it0, Vector2i(1, 0), false, normal[0]),
		"(1,0) excluyendo #1 -> todavía solapa #2 -> inválido"
	)
	_check(
		not inv_normal.posicion_valida(it0, Vector2i(0, 1), false, normal[0]),
		"(0,1) excluyendo #1 -> solapa entry #3 -> inválido"
	)
	_check(
		inv_normal.posicion_valida(it0, Vector2i(2, 2), false, normal[0]),
		"(2,2) excluyendo #1 -> libre -> válido"
	)


func _test_no_mutacion(
	live: Array[InventoryEntry], pos_prev: Array[Vector2i],
	rot_prev: Array[bool], id_prev: Array[int]
) -> void:
	print("-- las consultas NO mutan --")
	var ahora := inv_normal.get_entries()
	_check(ahora.size() == pos_prev.size(), "cantidad de entries sin cambios tras todas las consultas")
	var intacto := ahora.size() == live.size()
	for i in range(live.size()):
		if live[i].position != pos_prev[i] \
		or live[i].rotated != rot_prev[i] \
		or live[i].item_instance.instance_id != id_prev[i]:
			intacto = false
	_check(intacto, "cada entry conserva posición, rotación e instance_id originales")


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
