@tool
extends Node3D

## Pista de salto agachado (pedida por el usuario, 2026-10-22; el diseño es de
## Claude): para probar saltar y agacharse en el aire. Agachado en el aire, la
## cápsula se achica desde abajo (de 1,8 a 1,0 m, con la cabeza quieta): los
## pies suben 0,8 m y se llega a lugares más altos que saltando parado.
## Agachado no se cuelga de los bordes: cae arriba o choca.
##
##   Fila de bloques (z = 0 a 2,5), de 1,2 a 2,2 m: parado se sube el de 1,2;
##   agachándote, hasta el de 2,0 (justo, desde cerca).
##   Fila de atrás (z = 6,5 a 9,5):
##   - Conducto: una repisa a 1,6 m con techo a 3,0 m (1,4 m de alto): se entra
##     solo saltando y agachándote en el aire, y adentro no se puede parar.
##   - Ventana alta: un muro de 3,6 m con un hueco de 1,8 a 3,1 m.
##   - Con el súper (2 del teclado numérico): bloques de 2,6, 3,0 y 3,4 m.
##
## Está al sur del piso del laboratorio, detrás de donde se aparece, con su
## propio piso pegado al borde (FLOOR_LOW y FLOOR_HIGH). Se entra a cada cosa
## caminando hacia +z. Todo se arma al cargar, con el mismo código en todas las
## máquinas; con @tool también se arma en el editor, y las piezas no se
## guardan en la escena. Para cambiar alturas o medidas, se cambian las
## constantes de acá.

const BLOCK_HEIGHTS := [1.2, 1.4, 1.6, 1.8, 2.0, 2.2]
const BOOST_HEIGHTS := [2.6, 3.0, 3.4]
## Ancho (x) y fondo (z) de cada bloque, y cada cuánto va uno.
const BLOCK_SIZE := Vector2(1.4, 2.5)
const BLOCK_PITCH := 1.8
## Fila de atrás: dónde empieza (z) y su fondo.
const BACK_ROW_Z := 6.5
const BACK_ROW_DEPTH := 3.0
## Conducto: de x = 0 a DUCT_WIDTH, repisa a DUCT_FLOOR y techo a DUCT_CEILING.
const DUCT_WIDTH := 3.5
const DUCT_FLOOR := 1.6
const DUCT_CEILING := 3.0
const SLAB := 0.2
## Ventana alta: el muro (de x a x, en z, alto) y el hueco.
const WINDOW_WALL_X := Vector2(4.5, 8.5)
const WINDOW_WALL_Z := 7.0
const WINDOW_WALL_THICKNESS := 0.3
const WINDOW_WALL_HEIGHT := 3.6
const WINDOW_X := Vector2(5.75, 7.25)
const WINDOW_Y := Vector2(1.8, 3.1)
## Bloques del súper: el primero en este x.
const BOOST_X := 10.0
## El piso propio de la pista, de esquina a esquina. Entra medio metro en el
## piso del laboratorio, que termina en z = -1 de la pista: así no queda una
## rendija entre los dos. Sigue 4 m detrás de la fila de atrás, para salir del
## conducto sin caerse del mapa.
const FLOOR_LOW := Vector3(-1.5, -0.5, -1.5)
const FLOOR_HIGH := Vector3(15.8, 0.0, 13.5)

var _material := StandardMaterial3D.new()
var _high_material := StandardMaterial3D.new()
var _boost_material := StandardMaterial3D.new()
var _floor_material := StandardMaterial3D.new()


func _ready() -> void:
	_material.albedo_color = Color(0.55, 0.62, 0.7)
	_high_material.albedo_color = Color(0.7, 0.55, 0.45)
	_boost_material.albedo_color = Color(0.75, 0.68, 0.35)
	_floor_material.albedo_color = Color(0.4, 0.42, 0.45)
	_box(FLOOR_LOW, FLOOR_HIGH, _floor_material)
	_label("Pista de salto agachado\nsaltá y apretá Ctrl en el aire: la cápsula se achica desde abajo (los pies suben 0,8 m)\ny llegás más alto. Agachado no te colgás de los bordes: caés arriba o chocás",
			Vector3(5.0, 3.6, -1.5), 64)
	for i in BLOCK_HEIGHTS.size():
		var height: float = BLOCK_HEIGHTS[i]
		var x := BLOCK_SIZE.x * 0.5 + BLOCK_PITCH * i
		var reach := "sin agacharte" if height <= 1.2 else ("agachándote, justo" if height >= 2.0 else "agachándote")
		if height > 2.0:
			reach = "ni agachándote\n(con el súper, sí)"
		_box(Vector3(x - BLOCK_SIZE.x * 0.5, 0, 0), Vector3(x + BLOCK_SIZE.x * 0.5, height, BLOCK_SIZE.y),
				_material if height <= 1.2 else _high_material)
		_label("%s m\n%s" % [_meters(height), reach], Vector3(x, height + 0.6, -0.2))
	# Conducto: la repisa, el techo y dos paredes que lo sostienen.
	var back := BACK_ROW_Z + BACK_ROW_DEPTH
	_box(Vector3(0, 0, BACK_ROW_Z), Vector3(DUCT_WIDTH, DUCT_FLOOR, back), _high_material)
	_box(Vector3(0, DUCT_CEILING, BACK_ROW_Z), Vector3(DUCT_WIDTH, DUCT_CEILING + SLAB, back))
	_box(Vector3(-SLAB, 0, BACK_ROW_Z), Vector3(0, DUCT_CEILING + SLAB, back))
	_box(Vector3(DUCT_WIDTH, 0, BACK_ROW_Z), Vector3(DUCT_WIDTH + SLAB, DUCT_CEILING + SLAB, back))
	_label("Conducto a %s m, de %s m de alto\nsaltá, agachate en el aire y entrá\nadentro no te podés parar: seguí agachado hasta el otro lado" % [
			_meters(DUCT_FLOOR), _meters(DUCT_CEILING - DUCT_FLOOR)], Vector3(DUCT_WIDTH * 0.5, DUCT_CEILING + 0.9, BACK_ROW_Z - 0.3))
	# Ventana alta: el muro en cuatro pedazos alrededor del hueco.
	var z0 := WINDOW_WALL_Z
	var z1 := WINDOW_WALL_Z + WINDOW_WALL_THICKNESS
	_box(Vector3(WINDOW_WALL_X.x, 0, z0), Vector3(WINDOW_X.x, WINDOW_WALL_HEIGHT, z1))
	_box(Vector3(WINDOW_X.y, 0, z0), Vector3(WINDOW_WALL_X.y, WINDOW_WALL_HEIGHT, z1))
	_box(Vector3(WINDOW_X.x, 0, z0), Vector3(WINDOW_X.y, WINDOW_Y.x, z1))
	_box(Vector3(WINDOW_X.x, WINDOW_Y.y, z0), Vector3(WINDOW_X.y, WINDOW_WALL_HEIGHT, z1))
	_label("Ventana a %s m, de %s m de alto\nsaltá caminando hacia ella y agachate en el aire\n(en cualquier momento antes de lo más alto)" % [
			_meters(WINDOW_Y.x), _meters(WINDOW_Y.y - WINDOW_Y.x)], Vector3((WINDOW_WALL_X.x + WINDOW_WALL_X.y) * 0.5, WINDOW_WALL_HEIGHT + 0.7, z0 - 0.3))
	# Bloques del súper.
	for i in BOOST_HEIGHTS.size():
		var height: float = BOOST_HEIGHTS[i]
		var x := BOOST_X + BLOCK_SIZE.x * 0.5 + BLOCK_PITCH * i
		_box(Vector3(x - BLOCK_SIZE.x * 0.5, 0, BACK_ROW_Z), Vector3(x + BLOCK_SIZE.x * 0.5, height, back), _boost_material)
		_label("%s m\n%s" % [_meters(height), "sin agacharte" if height <= 2.6 else "agachándote"], Vector3(x, height + 0.6, BACK_ROW_Z - 0.2))
	_label("Con el súper (2 del teclado numérico)", Vector3(BOOST_X + BLOCK_PITCH + BLOCK_SIZE.x * 0.5, 4.9, BACK_ROW_Z - 0.2))


## Un número con coma decimal y un decimal, como en los carteles.
static func _meters(value: float) -> String:
	return ("%.1f" % value).replace(".", ",")


func _box(low: Vector3, high: Vector3, material: Material = null) -> void:
	var size := high - low
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material if material != null else _material
	visual.mesh = mesh
	body.add_child(visual)
	body.position = (low + high) * 0.5
	add_child(body)


func _label(text: String, at: Vector3, size := 48) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.95, 0.95, 0.95)
	label.outline_modulate = Color(0.1, 0.1, 0.12)
	label.outline_size = 12
	label.position = at
	add_child(label)
