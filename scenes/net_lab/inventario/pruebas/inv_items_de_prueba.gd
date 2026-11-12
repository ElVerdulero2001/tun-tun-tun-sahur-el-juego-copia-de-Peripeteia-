extends RefCounted

## Objetos de prueba controlados para las pruebas del inventario (desde la
## auditoría del 2026-11-08, PRU-01). Hasta ese día, lo que mide giros, lugares
## en la grilla y miniaturas usaba el machete del laboratorio: es contenido que
## se edita (ese día pasó de 1 × 3 a 1 × 6 y recibió hitbox y encuadres
## propios), y una edición válida rompía tres pruebas y tapaba las regresiones
## de verdad. Lo de acá vive solo en memoria: se suma al catálogo antes de que
## arranque el inventario y no se guarda en ningún archivo.
##
## Se usa con preload, sin class_name: no es parte del juego.

const BAR_ID := &"barra_de_prueba"
const BAR_SIZE := Vector2i(1, 3)
## Dónde se coloca, en la zona de inventario (sus coordenadas): al final de la
## columna del machete, lejos de las cajas y de la pared.
const BAR_SPOT := Vector3(-3, 0, 5.8)


## Una barra de 1 × 3 que se gira, sin capacidades, con la miniatura de fábrica
## y sin encuadre propio en la barra rápida. Se ve con una malla simple, así no
## depende de ningún modelo importado.
static func bar_def() -> InvItemDef:
	var def := InvItemDef.new()
	def.id = BAR_ID
	def.display_name = "Barra de prueba"
	def.size = BAR_SIZE
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.6)
	def.mesh = mesh
	def.color = Color(0.3, 0.55, 0.9)
	def.world_size = 0.6
	return def


## La suma al catálogo del laboratorio `lab` y la coloca en su zona de
## inventario con un InvPickupSpawn. Va antes de que `lab` entre al árbol (como
## en inv_hitbox_test): así el host la junta con los demás objetos iniciales.
## Devuelve el tipo.
static func add_bar(lab: Node) -> InvItemDef:
	var net := lab.get_node("Inventario") as InvNet
	var def := net.catalog.find(BAR_ID)
	if def == null:
		def = bar_def()
		net.catalog.items.append(def)
	var spawn := InvPickupSpawn.new()
	spawn.name = "BarraDePrueba"
	spawn.item = def
	spawn.position = BAR_SPOT
	lab.get_node("ZonaDeInventario").add_child(spawn)
	return def


## Los InvPickupSpawn que el host pone en el mundo al arrancar, contados como
## los junta InvNet._collect: los de `world_root` y los de `pickup_root` (el
## nivel), sin repetir, y solo los que tienen un tipo del catálogo
## (InvAuthority.add_spawn descarta los demás).
static func initial_spawns(net: InvNet) -> Array[InvPickupSpawn]:
	var found: Array[InvPickupSpawn] = []
	for root: Node in [net.world_root, net.pickup_root]:
		if root == null:
			continue
		for node in root.find_children("*", "InvPickupSpawn", true, false):
			var spawn := node as InvPickupSpawn
			if spawn != null and not spawn in found and spawn.item != null and net.catalog.find(spawn.item.id) == spawn.item:
				found.append(spawn)
	return found
