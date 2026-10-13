@tool
extends Node3D

## Torre de parkour del laboratorio: un recorrido que da la vuelta a un núcleo
## cuadrado de 6 × 6 m, subiendo por terrazas pegadas a sus caras, para probar
## juntos los movimientos que hay. Cada tramo tiene un cartel con su número:
##
##   1. Escalones de 25 cm, del piso a la terraza 1 (1,5 m).
##   2. Colgarse del borde de la terraza 2 (4 m) y saltar para arriba; o
##      colgarse del saliente de la cara de enfrente y correrse con A/D hasta
##      ese borde, que sigue a la misma altura.
##   3. Un techo a 1,3 m sobre la terraza 2: se pasa agachado.
##   4. Escalera a la terraza 3 (7 m).
##   5. Un hueco de 3,5 m en la terraza 3: se salta de una, o de a saltos cortos
##      por un pilar en el medio; desde el pilar se salta a un nicho en la
##      pared del núcleo, donde se puede parar.
##   6. Colgarse del borde de la terraza 4 (9,5 m) y saltar para arriba.
##   7. Un techo bajo de 3,5 m de largo sobre la terraza 4: se pasa deslizándose
##      (corriendo, Ctrl) o agachado.
##   8. Escalera a la terraza de arriba (12 m).
##   9. Un muro de 3,6 m: solo no se llega; desde el cajón uno se cuelga, se
##      corre, y el compañero se cuelga de su cintura.
##
## Y una escalera del piso a la terraza 2, para volver sin rehacer todo.
##
## Las alturas salen de los valores del Tuning de hoy: desde un piso las manos
## llegan a 3,12 m; colgado, los pies quedan 1,95 m debajo del filo; parado
## mide 1,8 m y agachado 1. Los bordes para colgarse están 2,5 m arriba del
## piso desde donde se salta, y los techos bajos a 1,3 m.
##
## El recorrido arranca del lado +Z local, frente a los escalones. Todo se arma
## al cargar, con el mismo código en todas las máquinas; con @tool también se
## arma en el editor, para verlo, y las piezas no se guardan en la escena.

## Núcleo: de -CORE a CORE en x y en z, y de 0 a CORE_TOP de alto.
const CORE := 3.0
const CORE_TOP := 12.0
## Hasta dónde salen las terrazas desde el centro.
const OUTER := 5.5
## Alturas de las terrazas (la de arriba es el techo del núcleo).
const LEVEL_1 := 1.5
const LEVEL_2 := 4.0
const LEVEL_3 := 7.0
const LEVEL_4 := 9.5
## Escalones: alto y fondo de cada uno, y ancho de la escalera.
const STEP_RISE := 0.25
const STEP_TREAD := 0.45
const STEP_WIDTH := 2.0
## Saliente de la cara +Z del núcleo: cuánto sale y su espesor. La terraza 2
## sale lo mismo hacia +Z, así su borde sigue al del saliente.
const LIP_OUT := 0.3
const LIP_THICKNESS := 0.15
## Lo que queda libre debajo de los techos bajos: agachado (1 m) pasa, parado
## (1,8 m) no.
const LOW_CLEARANCE := 1.3
const LOW_THICKNESS := 0.3
## Techo bajo de la terraza 2 y de la terraza 4: de dónde a dónde en z.
const CROUCH_Z := Vector2(-0.5, 1.5)
const SLIDE_Z := Vector2(-2.0, 1.5)
## Hueco de la terraza 3, en x; el pilar en el medio (x, z), y el nicho del
## núcleo detrás del pilar. El nicho es alto para entrar y salir saltando: la
## cabeza llega a casi 3 m sobre el piso en un salto.
const GAP_X := Vector2(-2.0, 1.5)
const PILLAR_X := Vector2(-0.5, 0.5)
const PILLAR_Z := Vector2(-5.0, -4.0)
const NICHE_X := Vector2(-0.8, 0.8)
const NICHE_DEPTH := 1.2
const NICHE_HEIGHT := 3.2
## Escaleras: id de red (las del nivel usan 1 y 2) y dónde van.
const LADDER_BACK_ID := 3
const LADDER_BACK_Z := 2.3
const LADDER_UP_ID := 4
const LADDER_UP_X := -4.25
const LADDER_TOP_ID := 5
const LADDER_TOP_Z := 2.25
## Muro de la terraza de arriba: 3,6 m, como el muro del compañero de la pista
## de bordes, con un cajón de 0,6 m delante de su punta -X.
const WALL_HEIGHT := 3.6
const WALL_X := Vector2(-2.0, 2.0)
const WALL_Z := Vector2(-2.7, -1.2)
const CRATE_SIZE := Vector3(1.2, 0.6, 1.0)
## Baranda de la terraza de arriba, del lado -X.
const RAIL_HEIGHT := 0.9
const RAIL_THICKNESS := 0.3

var _core_material := StandardMaterial3D.new()
var _floor_material := StandardMaterial3D.new()
var _low_material := StandardMaterial3D.new()
var _lip_material := StandardMaterial3D.new()


func _ready() -> void:
	_core_material.albedo_color = Color(0.48, 0.5, 0.56)
	_floor_material.albedo_color = Color(0.7, 0.64, 0.52)
	_low_material.albedo_color = Color(0.85, 0.5, 0.25)
	_lip_material.albedo_color = Color(0.35, 0.37, 0.42)
	for material in [_core_material, _floor_material, _low_material, _lip_material]:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_core()
	_build_route()
	_build_ladders()
	_build_labels()


## El núcleo, macizo salvo el nicho de la cara -Z a la altura de la terraza 3.
func _build_core() -> void:
	var niche_top := LEVEL_3 + NICHE_HEIGHT
	var niche_back := -CORE + NICHE_DEPTH
	_box(Vector3(-CORE, 0.0, -CORE), Vector3(CORE, LEVEL_3, CORE), _core_material)
	_box(Vector3(-CORE, LEVEL_3, niche_back), Vector3(CORE, niche_top, CORE), _core_material)
	_box(Vector3(-CORE, LEVEL_3, -CORE), Vector3(NICHE_X.x, niche_top, niche_back), _core_material)
	_box(Vector3(NICHE_X.y, LEVEL_3, -CORE), Vector3(CORE, niche_top, niche_back), _core_material)
	_box(Vector3(-CORE, niche_top, -CORE), Vector3(CORE, CORE_TOP, CORE), _core_material)


func _build_route() -> void:
	# 1. Escalones hacia -Z hasta la terraza 1, que va de punta a punta de la
	# cara +Z (también delante de la terraza 2).
	var steps := roundi(LEVEL_1 / STEP_RISE)
	var stairs_start := CORE + 2.5
	for i in steps:
		var near := stairs_start + STEP_TREAD * (steps - 1 - i)
		_box(Vector3(-STEP_WIDTH * 0.5, 0.0, near), Vector3(STEP_WIDTH * 0.5, STEP_RISE * (i + 1), near + STEP_TREAD),
				_floor_material)
	_box(Vector3(-OUTER, 0.0, CORE), Vector3(CORE, LEVEL_1, stairs_start), _floor_material)
	# 2. Terraza 2 en la cara -X, con el borde +Z a la altura del saliente.
	_box(Vector3(-OUTER, 0.0, -CORE), Vector3(-CORE, LEVEL_2, CORE + LIP_OUT), _floor_material)
	_box(Vector3(-CORE, LEVEL_2 - LIP_THICKNESS, CORE), Vector3(CORE, LEVEL_2, CORE + LIP_OUT), _lip_material)
	# 3. Techo bajo sobre la terraza 2.
	var crouch_bottom := LEVEL_2 + LOW_CLEARANCE
	_box(Vector3(-OUTER, crouch_bottom, CROUCH_Z.x), Vector3(-CORE, crouch_bottom + LOW_THICKNESS, CROUCH_Z.y),
			_low_material)
	# 5. Terraza 3 en la cara -Z, cortada por el hueco.
	_box(Vector3(-OUTER, 0.0, -OUTER), Vector3(GAP_X.x, LEVEL_3, -CORE), _floor_material)
	_box(Vector3(GAP_X.y, 0.0, -OUTER), Vector3(CORE, LEVEL_3, -CORE), _floor_material)
	_box(Vector3(PILLAR_X.x, 0.0, PILLAR_Z.x), Vector3(PILLAR_X.y, LEVEL_3, PILLAR_Z.y), _floor_material)
	# 6. Terraza 4 en la cara +X; su cara -X, sobre la terraza 3, es el borde.
	_box(Vector3(CORE, 0.0, -OUTER), Vector3(OUTER, LEVEL_4, CORE), _floor_material)
	# 7. Techo bajo sobre la terraza 4.
	var slide_bottom := LEVEL_4 + LOW_CLEARANCE
	_box(Vector3(CORE, slide_bottom, SLIDE_Z.x), Vector3(OUTER, slide_bottom + LOW_THICKNESS, SLIDE_Z.y), _low_material)
	# 9. Arriba: baranda del lado -X, el muro alto y el cajón.
	_box(Vector3(-CORE, CORE_TOP, -CORE), Vector3(-CORE + RAIL_THICKNESS, CORE_TOP + RAIL_HEIGHT, CORE), _lip_material)
	_box(Vector3(WALL_X.x, CORE_TOP, WALL_Z.x), Vector3(WALL_X.y, CORE_TOP + WALL_HEIGHT, WALL_Z.y), _core_material)
	_box(Vector3(WALL_X.x, CORE_TOP, WALL_Z.y), Vector3(WALL_X.x + CRATE_SIZE.x, CORE_TOP + CRATE_SIZE.y,
			WALL_Z.y + CRATE_SIZE.z), _floor_material)


## Las escaleras se trepan desde su lado +Z local: el giro las pone mirando
## hacia quien llega.
func _build_ladders() -> void:
	# Del piso a la terraza 2, en su cara -X.
	_ladder(LADDER_BACK_ID, Vector3(-OUTER, 0.0, LADDER_BACK_Z), -PI * 0.5, LEVEL_2)
	# 4. De la terraza 2 a la 3, en la cara +Z de la terraza 3.
	_ladder(LADDER_UP_ID, Vector3(LADDER_UP_X, LEVEL_2, -CORE), 0.0, LEVEL_3 - LEVEL_2)
	# 8. De la terraza 4 a la de arriba, en la cara +X del núcleo.
	_ladder(LADDER_TOP_ID, Vector3(CORE, LEVEL_4, LADDER_TOP_Z), PI * 0.5, CORE_TOP - LEVEL_4)


func _build_labels() -> void:
	_label("1 · escalones", Vector3(0.0, LEVEL_1 + 0.9, CORE + 4.5))
	_label("2 · colgate y saltá para arriba\no colgate del saliente y corréte con A/D",
			Vector3(-OUTER + 1.0, LEVEL_2 + 0.8, CORE + 1.2))
	_label("3 · agachado (Ctrl)", Vector3(-OUTER - 0.2, LEVEL_2 + LOW_CLEARANCE + 0.8, CROUCH_Z.y))
	_label("4 · escalera", Vector3(LADDER_UP_X, LEVEL_3 + 0.6, -CORE + 0.6))
	_label("5 · saltá el hueco, de una o por el pilar\ndesde el pilar, pará en el nicho",Vector3((GAP_X.x + GAP_X.y) * 0.5, LEVEL_3 + 2.8, -OUTER))
	_label("6 · colgate y saltá para arriba", Vector3(CORE - 0.6, LEVEL_4 + 0.8, -OUTER + 0.4))
	_label("7 · deslizate (corriendo, Ctrl)\no pasá agachado", Vector3(OUTER + 0.2, LEVEL_4 + LOW_CLEARANCE + 1.0, -CORE))
	_label("8 · escalera", Vector3(CORE + 0.6, CORE_TOP + 0.6, LADDER_TOP_Z))
	_label("9 · muro de 3,6 m: con un compañero\ndesde el cajón, colgate y corréte",
			Vector3(0.0, CORE_TOP + WALL_HEIGHT + 0.8, WALL_Z.y))
	_label("escalera de vuelta\na la terraza 2", Vector3(-OUTER - 0.6, 2.5, LADDER_BACK_Z))


## Una caja entre dos esquinas, en coordenadas de la torre.
func _box(low: Vector3, high: Vector3, material: Material) -> void:
	var size := high - low
	var shape := BoxShape3D.new()
	shape.size = size
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	body.position = (low + high) * 0.5
	add_child(body)


## Una escalera con los pies en `foot`, girada `yaw` sobre Y.
func _ladder(id: int, foot: Vector3, yaw: float, height: float) -> void:
	var ladder := Ladder.new()
	ladder.ladder_id = id
	ladder.height = height
	ladder.position = foot
	ladder.rotation.y = yaw
	add_child(ladder)


func _label(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.95, 0.95, 0.95)
	label.outline_modulate = Color(0.1, 0.1, 0.12)
	label.outline_size = 12
	label.position = at
	add_child(label)
