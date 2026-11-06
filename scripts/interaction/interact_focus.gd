class_name InteractFocus
extends RefCounted

## Lo que el indicador de interacción (InteractIndicator) necesita saber del
## objetivo al que apunta el jugador: el nombre que se ve y la zona que se
## marca. Es la estructura común de los interactuables (desde el 2026-11-06):
## cada uno arma la suya en `interact_focus() -> InteractFocus`, y el HUD no
## sabe de qué tipo es (un objeto suelto, una caja, y más adelante una puerta,
## un NPC o un activador).
##
## La zona es una caja (`bounds`) en el espacio local de `anchor`, el nodo que
## sigue. El indicador la proyecta en cada cuadro con la cámara activa, con la
## posición de `anchor` tal como se dibuja: si el nodo se mueve, gira o va
## arriba de algo que se mueve, el marco lo acompaña. Para marcar solo una
## parte (la manija de una puerta, el botón de un activador), `anchor` es ese
## nodo y `bounds` el tamaño de esa parte.

## El nombre que se ve debajo del marco.
var display_name := ""
## El nodo que sigue la zona.
var anchor: Node3D
## La zona que se marca, en el espacio local de `anchor`.
var bounds := AABB()
## Opcional: el cartel 3D que ya muestra el nombre en el mundo. Mientras el
## objetivo está marcado, el indicador lo oculta, así el nombre se ve una sola
## vez; al dejar de marcarlo, lo vuelve a mostrar.
var name_label: Node3D


func _init(p_name := "", p_anchor: Node3D = null, p_bounds := AABB(), p_label: Node3D = null) -> void:
	display_name = p_name
	anchor = p_anchor
	bounds = p_bounds
	name_label = p_label


## Si se puede marcar: el nodo existe, está en el árbol, no se está borrando y se ve.
func is_valid() -> bool:
	return is_instance_valid(anchor) and anchor.is_inside_tree() and not anchor.is_queued_for_deletion() \
			and anchor.is_visible_in_tree()


## Las ocho esquinas de la zona en el mundo, como se dibujan en este cuadro.
func world_corners() -> PackedVector3Array:
	var place := anchor.get_global_transform_interpolated()
	var corners := PackedVector3Array()
	for i in 8:
		corners.append(place * bounds.get_endpoint(i))
	return corners


## La caja que encierra las mallas visibles de `root` (él mismo, si es una
## malla, y lo que cuelga de él), en el espacio de `root`. Los carteles
## (Label3D) y las colisiones no cuentan. Sirve fuera del árbol: suma las
## transformaciones locales.
static func mesh_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var found := false
	var own := root as MeshInstance3D
	if own != null and own.mesh != null:
		box = own.get_aabb()
		found = true
	var pending: Array = [[root, Transform3D.IDENTITY]]
	while not pending.is_empty():
		var entry: Array = pending.pop_back()
		var place: Transform3D = entry[1]
		for child: Node in (entry[0] as Node).get_children():
			var child_place := place
			if child is Node3D:
				if not (child as Node3D).visible:
					continue
				child_place = place * (child as Node3D).transform
			var mesh_node := child as MeshInstance3D
			if mesh_node != null and mesh_node.mesh != null:
				var part := child_place * mesh_node.get_aabb()
				box = box.merge(part) if found else part
				found = true
			pending.append([child, child_place])
	return box
