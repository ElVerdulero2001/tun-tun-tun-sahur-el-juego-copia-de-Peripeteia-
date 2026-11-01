class_name InvVisuals
extends RefCounted

## Arma lo que se ve de un tipo de objeto, para el mundo, la mano y la
## miniatura: solo sus mallas, copiadas a nodos nuevos. El modelo original se
## instancia afuera del juego y se borra sin entrar al árbol: no corren sus
## scripts, ni su física, ni sus efectos.


## Un nodo con las mallas del tipo (su modelo, o su malla suelta). Vacío si no
## tiene ninguna de las dos.
static func build(def: InvItemDef) -> Node3D:
	var root := Node3D.new()
	root.name = "Modelo"
	if def == null:
		return root
	if def.model != null:
		var instance := def.model.instantiate()
		if instance != null:
			_copy_meshes(instance, Transform3D.IDENTITY, root)
			instance.free()
	elif def.mesh != null:
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = def.mesh
		var material := def.mesh.surface_get_material(0) if def.mesh.get_surface_count() > 0 else null
		if material == null:
			var plain := StandardMaterial3D.new()
			plain.albedo_color = def.color
			mesh_node.material_override = plain
		root.add_child(mesh_node)
	return root


static func _copy_meshes(node: Node, parent_transform: Transform3D, out: Node3D) -> void:
	var place := parent_transform
	if node is Node3D:
		place = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var source := node as MeshInstance3D
		if source.mesh != null and source.visible:
			var copy := MeshInstance3D.new()
			copy.mesh = source.mesh
			copy.transform = place
			copy.material_override = source.material_override
			for i in source.get_surface_override_material_count():
				copy.set_surface_override_material(i, source.get_surface_override_material(i))
			out.add_child(copy)
	for child in node.get_children():
		_copy_meshes(child, place, out)


## Caja que encierra todas las mallas, en el espacio de `root`.
static func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in root.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var part := mesh_node.transform * mesh_node.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## El modelo dentro de un nodo que lo escala para que su lado más largo mida
## `size`, centrado y, con `on_floor`, con la base en el origen.
static func fitted(def: InvItemDef, size: float, on_floor: bool) -> Node3D:
	var holder := Node3D.new()
	var model := build(def)
	holder.add_child(model)
	var box := bounds(model)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.0001:
		return holder
	var scale := size / longest
	model.scale = Vector3.ONE * scale
	var center := box.get_center()
	model.position = -Vector3(center.x, box.position.y if on_floor else center.y, center.z) * scale
	return holder


## Una caja de color, para lo que no tiene modelo.
static func placeholder(def: InvItemDef, size: float) -> Node3D:
	var holder := Node3D.new()
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	var foot := def.size if def != null else Vector2i.ONE
	var longest := float(maxi(foot.x, foot.y))
	box.size = Vector3(foot.x / longest, 0.5, foot.y / longest) * size
	var material := StandardMaterial3D.new()
	material.albedo_color = def.color if def != null else Color.GRAY
	box.material = material
	mesh_node.mesh = box
	mesh_node.position = Vector3.UP * box.size.y / 2.0
	holder.add_child(mesh_node)
	return holder


static func has_visual(def: InvItemDef) -> bool:
	return def != null and (def.model != null or def.mesh != null)
