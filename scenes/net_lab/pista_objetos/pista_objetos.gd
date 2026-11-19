class_name PistaObjetos
extends Node3D

## Pista de objetos (piloto, desde el 2026-11-18): una sala cerrada del
## laboratorio con una caja que se mueve en un mundo Rapier propio
## (SahurObjectWorld) y no en Jolt. La sala tiene las medidas de la sala de
## objetos aprobada (prototypes/objetos_adaptador/play_room.gd): piso de 12 m,
## paredes, el bloque bajo y la misma caja. Se agregó una puerta, para entrar
## desde el resto del laboratorio, y un techo, para que la caja no salga.
##
## Cada parte existe dos veces con las mismas medidas: en Jolt, donde camina el
## personaje y miran los rayos, y en el mundo de objetos, donde choca la caja.
## La caja solo existe en el mundo de objetos. La puerta y el techo tienen una
## barrera que solo frena a la caja: en Jolt va en OBJECT_ONLY_LAYER, que el
## personaje no mira, y en el mundo de objetos es una pared más.
##
## Esta pista arma solo la geometría y dice dónde va cada cosa. El mundo de
## objetos, la red y lo que se dibuja de la caja son de PistaPiloto.

## Identidad y medidas de la caja (las de la sala aprobada).
const BOX_ID := 2
const BOX_SIZE := Vector3(0.52, 0.45, 0.58)
const BOX_MASS := 2.0
const BOX_START := Vector3(0, 0.24, -1.15)
## Revisión del modelo de la pista: va sellada en el mundo de objetos. Si
## cambian las medidas, se sube: un estado de otra revisión no se acepta.
const MODEL_REVISION := 101
## Capa de Jolt de lo que solo frena a la caja (la barrera de la puerta y el
## techo): el personaje (máscara 1 | 4) y los rayos de alcance no la miran.
const OBJECT_ONLY_LAYER := 1 << 9
## Alto de las paredes y del techo. La caja sostenida puede subir hasta los
## ojos más el alcance de la mano (unos 4,4 m arriba): con paredes de 3 m, como
## en la sala, se la podía pasar por arriba.
const WALL_HEIGHT := 4.5
const DOOR_WIDTH := 1.6
const DOOR_HEIGHT := 2.4

const FLOOR_ID := 1
const BLOCK_ID := 7

## Partes fijas, en el espacio de la pista: [id, medidas, centro, en Jolt].
## "solido": capa 1 y se dibuja; "barrera": solo frena a la caja; "" no va a Jolt.
var _parts: Array = []


func _ready() -> void:
	var half := 6.0
	var door_half := DOOR_WIDTH * 0.5
	var side := (2.0 * half - DOOR_WIDTH) * 0.5
	var wall_y := WALL_HEIGHT * 0.5
	_parts = [
		# Las cinco primeras, como en la sala: piso, las tres paredes enteras y el bloque bajo.
		[FLOOR_ID, Vector3(12, 0.25, 12), Vector3(0, -0.125, 0), ""],
		[3, Vector3(12, WALL_HEIGHT, 0.25), Vector3(0, wall_y, -half), "solido"],
		[4, Vector3(12, WALL_HEIGHT, 0.25), Vector3(0, wall_y, half), "solido"],
		[6, Vector3(0.25, WALL_HEIGHT, 12), Vector3(half, wall_y, 0), "solido"],
		[BLOCK_ID, Vector3(2.1, 0.5, 0.8), Vector3(2.5, 0.25, -2.75), "solido"],
		# La pared de la puerta (x = -6), en dos tramos y un dintel.
		[5, Vector3(0.25, WALL_HEIGHT, side), Vector3(-half, wall_y, -(door_half + side * 0.5)), "solido"],
		[8, Vector3(0.25, WALL_HEIGHT, side), Vector3(-half, wall_y, door_half + side * 0.5), "solido"],
		[9, Vector3(0.25, WALL_HEIGHT - DOOR_HEIGHT, DOOR_WIDTH),
				Vector3(-half, DOOR_HEIGHT + (WALL_HEIGHT - DOOR_HEIGHT) * 0.5, 0), "solido"],
		# Lo que solo frena a la caja: el hueco de la puerta y el techo.
		[10, Vector3(0.25, DOOR_HEIGHT, DOOR_WIDTH), Vector3(-half, DOOR_HEIGHT * 0.5, 0), "barrera"],
		[11, Vector3(12, 0.25, 12), Vector3(0, WALL_HEIGHT + 0.125, 0), "barrera"],
	]
	# El piso de Jolt es más grande que el de la caja: del lado de la puerta llega
	# hasta el borde de la pista de física de la zona de inventario (x = 44 en el
	# mundo, con la pista en x = 53), por donde se viene caminando desde el piso
	# del laboratorio. No se superpone con nada.
	_add_jolt(Vector3(16, 1, 14), Vector3(-1, -0.5, 0), 1, Color("#4d6470"))
	for part in _parts:
		match part[3]:
			"solido":
				_add_jolt(part[1], part[2], 1, Color("#324651"))
			"barrera":
				_add_jolt(part[1], part[2], OBJECT_ONLY_LAYER, Color(0.55, 0.8, 0.95, 0.18) if part[0] == 10 else Color.TRANSPARENT)
	# La grilla del piso, para ver si se mueve todo o solo la caja (como en la sala).
	for i in range(-5, 6):
		_add_mesh(Vector3(0.018, 0.002, 11.5), Vector3(i, 0.002, 0), Color("#263943"))
		_add_mesh(Vector3(11.5, 0.002, 0.018), Vector3(0, 0.003, i), Color("#263943"))
	var banner := Label3D.new()
	banner.text = "Pista de objetos (piloto)\nLa caja la mueve el invitado"
	banner.pixel_size = 0.006
	banner.font_size = 48
	banner.outline_size = 10
	banner.position = Vector3(-half - 0.2, DOOR_HEIGHT + 0.6, 0)
	banner.rotation = Vector3(0, -PI / 2.0, 0)
	add_child(banner)


## Las partes fijas para el mundo de objetos, en el espacio del mundo:
## [id, medidas, Transform3D]. Las mismas medidas que en Jolt.
func native_parts() -> Array:
	var out: Array = []
	for part in _parts:
		out.append([part[0], part[1], Transform3D(Basis.IDENTITY, to_global(part[2]))])
	return out


## Dónde arranca la caja, en el espacio del mundo.
func box_start() -> Transform3D:
	return Transform3D(Basis.IDENTITY, to_global(BOX_START))


## Las caras de arriba en las que se apoya la caja (el piso y el bloque), en el
## espacio del mundo: el dibujo de la caja suelta no las atraviesa.
func supports() -> Array[AABB]:
	var out: Array[AABB] = []
	for part in _parts:
		if part[0] == FLOOR_ID or part[0] == BLOCK_ID:
			out.append(AABB(to_global(part[2]) - part[1] * 0.5, part[1]))
	return out


## Lugares de aparición dentro de la pista, en el espacio del mundo, en orden de
## llegada: el host a un costado y el primer invitado frente a la caja, donde
## aparece en la sala aprobada.
func spawn_slots() -> Array:
	var local := [Vector3(-2, 0, 2.5), Vector3(0, 0, 0.95), Vector3(2, 0, 2.5), Vector3(-3.5, 0, 3.5),
			Vector3(3.5, 0, 3.5), Vector3(-2, 0, 4.5), Vector3(0, 0, 4.5), Vector3(2, 0, 4.5)]
	return local.map(func(p: Vector3) -> Vector3: return to_global(p))


## Si un punto del mundo está dentro de la sala.
func contains(point: Vector3) -> bool:
	var p := to_local(point)
	return absf(p.x) < 6.0 and absf(p.z) < 6.0 and p.y > -1.0 and p.y < WALL_HEIGHT + 1.0


func _add_jolt(size: Vector3, center: Vector3, layer: int, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = center
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	if color.a > 0.0:
		var mesh := _add_mesh(size, Vector3.ZERO, color, body)
		if color.a < 1.0:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_mesh(size: Vector3, center: Vector3, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var model := BoxMesh.new()
	model.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	model.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = model
	instance.position = center
	parent.add_child(instance)
	return instance
