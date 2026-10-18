@tool
extends Node3D

## Pista de colgarse del compañero (pedida por el usuario, 2026-10-18): para
## probar cuánta libertad da el agarre de cilindro (de cualquier lado, W/S
## suben y bajan, A/D giran) y si sirve para atravesar paredes o pisos. En cada
## estación uno se agarra del cable, de la escalera o del borde, y el otro se
## cuelga de él y prueba pasar al otro lado de lo que tiene cerca.
##
##   Cables, a 3,6 m y a lo largo de x, con un cajón de 1 m en una punta para
##   subirse (z = -7, -1, 5 y 11):
##   1. Junto a una pared gruesa, a 10 cm del cuerpo del de arriba.
##   2. Cruzado por una pared de 5 cm.
##   3. En un pasillo de 1,2 m: solo se cabe adelante o atrás de él.
##   4. Sobre un piso a 2,4 m con un agujero de 2,4 m, con un cajón en una
##      esquina del agujero para subirse.
##   Escaleras (z = 20):
##   5. Contra una pared de 5 m.
##   6. Suelta, sin pared: la escalera no tiene colisión.
##   7. Atravesando un piso a 2,8 m por un agujero justo para el que trepa.
##   Bordes, a 3,6 m, con un cajón de 1 m para subirse (z = 27):
##   8. Un muro grueso.
##   9. Una losa de 5 cm sin nada abajo, sostenida desde atrás.
##   10. Una columna de 1 m.
##
## Todo se arma al cargar, con el mismo código en todas las máquinas; con @tool
## también se arma en el editor, y las piezas no se guardan en la escena. Los
## cables y las escaleras se numeran solos, por su ruta en la escena.

const CABLE_HEIGHT := 3.6
const CABLE_HALF := 3.0
const WALL_HEIGHT := 4.5
const EDGE_HEIGHT := 3.6
const STEP := 1.0
const THIN := 0.05

var _material := StandardMaterial3D.new()
var _thin_material := StandardMaterial3D.new()
var _step_material := StandardMaterial3D.new()


func _ready() -> void:
	_material.albedo_color = Color(0.5, 0.52, 0.58)
	_thin_material.albedo_color = Color(0.75, 0.45, 0.4)
	_step_material.albedo_color = Color(0.45, 0.6, 0.45)
	_label("Pista de colgarse del compañero\nuno se agarra del cable, la escalera o el borde; el otro se cuelga de él\ny prueba pasar al otro lado de lo que tiene cerca (W/S suben y bajan, A/D giran)",
			Vector3(0, 5.2, -10.5), 64)
	# 1. Cable junto a una pared gruesa.
	_cable_station(1, -7.0)
	_box(Vector3(-CABLE_HALF, 0, -6.55), Vector3(CABLE_HALF, WALL_HEIGHT, -6.25))
	_label("1 · cable junto a una pared gruesa\ncolgado, girá con A/D hacia la pared y subí con W", Vector3(0, 5.0, -7.6))
	# 2. Cable cruzado por una pared de 5 cm.
	_cable_station(2, -1.0)
	_box(Vector3(-THIN * 0.5, 0, -2.5), Vector3(THIN * 0.5, WALL_HEIGHT, 0.5), _thin_material)
	_label("2 · pared de 5 cm que cruza el cable\nel de arriba a un lado de la pared; el de abajo, probá pasar al otro lado\ngirando o subiendo, o colgarte de él desde el otro lado", Vector3(0, 5.0, -1.6))
	# 3. Cable en un pasillo de 1,2 m.
	_cable_station(3, 5.0)
	_box(Vector3(-CABLE_HALF, 0, 4.1), Vector3(CABLE_HALF, WALL_HEIGHT, 4.4))
	_box(Vector3(-CABLE_HALF, 0, 5.6), Vector3(CABLE_HALF, WALL_HEIGHT, 5.9))
	_label("3 · pasillo de 1,2 m\nal costado de él no cabés: probá girar y colgarte desde la punta del pasillo", Vector3(0, 5.0, 4.4))
	# 4. Cable sobre un piso con un agujero.
	_cable_station(4, 11.0, false)
	var floor_low := 2.4
	var floor_high := 2.6
	var hole := 1.2
	_box(Vector3(-4, floor_low, 8), Vector3(-hole, floor_high, 14))
	_box(Vector3(hole, floor_low, 8), Vector3(4, floor_high, 14))
	_box(Vector3(-hole, floor_low, 8), Vector3(hole, floor_high, 11 - hole))
	_box(Vector3(-hole, floor_low, 11 + hole), Vector3(hole, floor_high, 14))
	_box(Vector3(-hole, 0, 11 - hole), Vector3(-hole + 0.7, STEP, 11 - hole + 0.7), _step_material)
	_label("4 · piso a 2,4 m con un agujero de 2,4 m (subite desde el cajón de la esquina)\ncolgado debajo, subí con W y girá: ¿salís por arriba del piso?", Vector3(0, 5.0, 10.4))
	# 5. Escalera contra una pared.
	_box(Vector3(-3.5, 0, 19), Vector3(-1.5, 5, 20))
	_ladder("EscaleraColgarse5", Vector3(-2.5, 0, 20), 5.0)
	_label("5 · escalera contra una pared\ncolgado de su espalda, girá hasta el costado y probá meterte en la pared", Vector3(-2.5, 5.8, 20.6))
	# 6. Escalera suelta.
	_ladder("EscaleraColgarse6", Vector3(2.5, 0, 20.5), 4.0)
	_label("6 · escalera suelta, sin pared\nprobá girar hasta el lado de la escalera: no tendría que dejarte", Vector3(2.5, 4.8, 21.1))
	# 7. Escalera que atraviesa un piso por un agujero justo.
	var slab_low := 2.6
	var slab_high := 2.8
	_box(Vector3(5.5, slab_low, 18.5), Vector3(6.8, slab_high, 23.5))
	_box(Vector3(8.2, slab_low, 18.5), Vector3(9.5, slab_high, 23.5))
	_box(Vector3(6.8, slab_low, 18.5), Vector3(8.2, slab_high, 20))
	_box(Vector3(6.8, slab_low, 21.4), Vector3(8.2, slab_high, 23.5))
	_box(Vector3(6.8, 0, 19.6), Vector3(8.2, slab_low, 20))
	_ladder("EscaleraColgarse7", Vector3(7.5, 0, 20), slab_high)
	_label("7 · escalera que atraviesa un piso a 2,8 m\ncolgado del que trepa, subí con W: ¿pasás por el piso?", Vector3(7.5, 4.0, 22))
	# 8. Borde de un muro grueso.
	_box(Vector3(-4, 0, 27), Vector3(-1, EDGE_HEIGHT, 29))
	_box(Vector3(-4, 0, 26), Vector3(-3, STEP, 27), _step_material)
	_label("8 · borde de un muro grueso (subite desde el cajón)\ncolgado de su espalda, girá hasta el costado y bajá con S", Vector3(-2.5, 4.4, 26.4))
	# 9. Borde de una losa de 5 cm sin nada abajo.
	_box(Vector3(0.5, EDGE_HEIGHT - THIN, 26), Vector3(4.5, EDGE_HEIGHT, 29), _thin_material)
	_box(Vector3(0.5, 0, 28.7), Vector3(4.5, EDGE_HEIGHT - THIN, 29))
	_box(Vector3(0.5, 0, 25), Vector3(1.5, STEP, 26), _step_material)
	_label("9 · borde de una losa de 5 cm, sin nada abajo (subite desde el cajón)\ngirá y subí: ¿te podés meter debajo de la losa o pasarla?", Vector3(2.5, 4.4, 25.4))
	# 10. Borde de una columna.
	_box(Vector3(6.5, 0, 27), Vector3(7.5, EDGE_HEIGHT, 28))
	# El cajón, un poco a un costado: si no, queda donde cuelga el de abajo.
	_box(Vector3(5.3, 0, 25.8), Vector3(6.3, STEP, 26.8), _step_material)
	_label("10 · columna de 1 m (subite desde el cajón)\nel de arriba cerca de una esquina; el de abajo, girá hacia la esquina", Vector3(7, 4.4, 26.4))


## Un cable de estación: a CABLE_HEIGHT, de x = -CABLE_HALF a CABLE_HALF en `z`,
## con un cajón de STEP en la punta de -x para subirse (si `step`).
func _cable_station(number: int, z: float, step := true) -> void:
	var cable := Cable.new()
	cable.name = "CableColgarse%d" % number
	var curve := Curve3D.new()
	curve.add_point(Vector3(-CABLE_HALF, 0, 0))
	curve.add_point(Vector3(CABLE_HALF, 0, 0))
	cable.curve = curve
	cable.position = Vector3(0, CABLE_HEIGHT, z)
	add_child(cable)
	if step:
		_box(Vector3(-CABLE_HALF - 1.2, 0, z - 0.5), Vector3(-CABLE_HALF - 0.2, STEP, z + 0.5), _step_material)


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


## Una escalera que se trepa desde +z (el nombre va antes de agregarla: el
## número sale de la ruta).
func _ladder(ladder_name: StringName, at: Vector3, height: float) -> void:
	var ladder := Ladder.new()
	ladder.name = ladder_name
	ladder.height = height
	ladder.position = at
	add_child(ladder)


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
