@tool
extends Node3D

## Pista de cables del laboratorio: postes, plataformas, una escalera y carteles
## para los cuatro cables, que son nodos Cable hijos de este en la escena (se
## mueven y se cambian en el Inspector; los postes no los siguen).
##
##   Fila 1 (z = 0): un cable plano a 2,9 m, entre dos postes. Desde el piso,
##   saltando debajo, se agarra. Tubo.
##   Fila 2 (z = 4): un cable a 10°, menos que el ángulo de deslizarse: se
##   mueve solo con A y D. Textura.
##   Fila 3 (z = 9): un cable con 1 m de comba entre dos plataformas de 2,5 m:
##   desde las puntas, con W mirando hacia abajo, se desliza hacia el medio.
##   Modelo (eslabones de cadena).
##   Fila 4 (z = 14): una tirolesa a 25° desde una plataforma de 6 m con
##   escalera: con W mirando hacia abajo se desliza; para volver a subir, S
##   (o W mirando para arriba), más lento. Tubo.
##
## Todo se arma al cargar, con el mismo código en todas las máquinas. Con
## @tool también se arma en el editor; las piezas no se guardan en la escena.

## Nombre de la escalera de la plataforma alta (el número sale solo, por la
## ruta en la escena; el nombre va antes de agregarla).
const LADDER_NAME := &"EscaleraTirolesa"
const POST := 0.2
const TALL_TOP := 6.0
const PLATFORM_TOP := 2.5

var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.albedo_color = Color(0.55, 0.5, 0.45)
	# Fila 1: plano.
	_post(Vector3(-0.15, 0, 0), 3.0)
	_post(Vector3(8.15, 0, 0), 3.0)
	_label("cable plano: saltá debajo o tirate encima y te agarrás\nte movés con las teclas, según la cámara", Vector3(4, 3.6, 0.3))
	# Fila 2: a 10°.
	_post(Vector3(-0.15, 0, 4), 3.0)
	_post(Vector3(8.15, 0, 4), 4.45)
	_label("cable a 10°: muy poco inclinado para deslizarte", Vector3(4, 4.3, 4.3))
	# Fila 3: con comba, entre dos plataformas.
	_box(Vector3(-2, 0, 8), Vector3(0, PLATFORM_TOP, 10))
	_box(Vector3(10, 0, 8), Vector3(12, PLATFORM_TOP, 10))
	_post(Vector3(-0.15, PLATFORM_TOP, 9), 1.2)
	_post(Vector3(10.15, PLATFORM_TOP, 9), 1.2)
	_label("cable con comba: desde las puntas, W mirando hacia abajo\npara deslizarte hacia el medio", Vector3(5, 4.3, 9.3))
	# Fila 4: tirolesa desde una plataforma alta con escalera.
	_box(Vector3(-3, 0, 12.5), Vector3(0, TALL_TOP, 15.5))
	# Arriba, el poste va al costado, con un brazo por encima de la cabeza del
	# que se acerca caminando: el cable arranca en el borde de la plataforma.
	_post(Vector3(-0.15, TALL_TOP, 15.2), 2.2)
	_prop(Vector3(-0.25, TALL_TOP + 2.1, 13.9), Vector3(0.05, TALL_TOP + 2.2, 15.3))
	_prop(Vector3(-0.02, 7.5, 13.98), Vector3(0.02, TALL_TOP + 2.1, 14.02))
	_post(Vector3(10.15, 0, 14), 2.95)
	_ladder(Vector3(-3, 0, 14))
	_label("tirolesa a 25°: W mirando hacia abajo para deslizarte\nsoltá W para frenar · S frena y sube (más lento)", Vector3(5, 7.0, 14.3))


func _post(foot: Vector3, height: float) -> void:
	_box(foot - Vector3(POST * 0.5, 0, POST * 0.5), foot + Vector3(POST * 0.5, height, POST * 0.5))


## Solo dibujo, sin colisión.
func _prop(low: Vector3, high: Vector3) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = high - low
	mesh.material = _material
	visual.mesh = mesh
	visual.position = (low + high) * 0.5
	add_child(visual)


func _box(low: Vector3, high: Vector3) -> void:
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
	mesh.material = _material
	visual.mesh = mesh
	body.add_child(visual)
	body.position = (low + high) * 0.5
	add_child(body)


## La escalera de la plataforma alta, en su cara -X: se trepa desde -X.
func _ladder(at: Vector3) -> void:
	var ladder := Ladder.new()
	ladder.name = LADDER_NAME
	ladder.height = TALL_TOP
	ladder.position = at
	ladder.rotation.y = -PI * 0.5
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
