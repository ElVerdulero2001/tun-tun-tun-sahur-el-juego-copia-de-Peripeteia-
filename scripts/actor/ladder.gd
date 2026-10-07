class_name Ladder
extends Node3D

## Escalera: un objeto autorado con su eje y su alto, como pide la
## arquitectura. No se detectan peldaños: quien trepa se ubica sobre el eje,
## y su pose sale de la escalera y de la altura.
##
## El eje sale del nodo hacia arriba (+Y local). Se trepa desde el lado +Z
## local: esa cara mira hacia quien trepa. Los pies de quien está a la altura
## t van en pose_at(t), a `standoff` delante del eje.
##
## Por ahora las escaleras están fijas: no se mueven ni giran en el juego.

static var _ladders := {}  # id de red -> Ladder

## Id de red. Tiene que ser único y el mismo en todas las máquinas.
@export var ladder_id := 1
## Alto, en metros: arriba de todo, los pies quedan a esta altura del nodo.
@export var height := 2.5
@export var width := 0.8
## Distancia del eje al centro de la cápsula de quien trepa.
@export var standoff := 0.45
## Volumen de entrada: hasta esta distancia delante del eje se puede agarrar.
@export var reach := 0.9


static func find(id: int) -> Ladder:
	return _ladders.get(id) if id != 0 else null


static func all() -> Array:
	return _ladders.values()


func _enter_tree() -> void:
	_ladders[ladder_id] = self


func _exit_tree() -> void:
	if _ladders.get(ladder_id) == self:
		_ladders.erase(ladder_id)


func _ready() -> void:
	_build_visual()


func up() -> Vector3:
	return global_basis.y.normalized()


## Hacia dónde mira la cara: desde la escalera hacia quien trepa.
func outward() -> Vector3:
	return global_basis.z.normalized()


## Dónde van los pies de quien está a la altura t.
func pose_at(t: float) -> Vector3:
	return global_position + up() * t + outward() * standoff


## La altura sobre la escalera para unos pies en `feet`, o -1 si están fuera
## del volumen de entrada.
func height_for(feet: Vector3) -> float:
	var local := global_transform.affine_inverse() * feet
	if absf(local.x) > width * 0.5 + 0.3 or local.z < 0.0 or local.z > reach:
		return -1.0
	if local.y < -0.2 or local.y > height + 0.2:
		return -1.0
	return clampf(local.y, 0.0, height)


## Dos largueros y un peldaño cada 30 cm. Es solo dibujo, sin colisión.
func _build_visual() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.6, 0.25)
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(0.06, height + 0.4, 0.06)
		rail_mesh.material = material
		rail.mesh = rail_mesh
		rail.position = Vector3(side * width * 0.5, (height + 0.4) * 0.5, 0.05)
		add_child(rail)
	var rung_y := 0.3
	while rung_y < height + 0.35:
		var rung := MeshInstance3D.new()
		var rung_mesh := BoxMesh.new()
		rung_mesh.size = Vector3(width, 0.04, 0.04)
		rung_mesh.material = material
		rung.mesh = rung_mesh
		rung.position = Vector3(0.0, rung_y, 0.05)
		add_child(rung)
		rung_y += 0.3
