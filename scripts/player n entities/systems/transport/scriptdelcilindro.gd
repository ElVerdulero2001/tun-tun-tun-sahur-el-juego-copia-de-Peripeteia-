extends RigidBody3D

## Mientras este cuerpo está en contacto con un vehículo guiado,
## fuerza su velocidad para igualar la del vehículo y anula su rotación.
## No usa Area3D — se apoya en el contact monitoring nativo del RigidBody3D.

var _vehiculos_en_contacto: Dictionary = {}

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_shape_entered.connect(_on_body_shape_entered)
	body_shape_exited.connect(_on_body_shape_exited)

func _on_body_shape_entered(_body_rid: RID, body: Node, _body_shape_index: int, _local_shape_index: int) -> void:
	if body.has_method("get_velocidad_actual"):
		_vehiculos_en_contacto[body] = true

func _on_body_shape_exited(_body_rid: RID, body: Node, _body_shape_index: int, _local_shape_index: int) -> void:
	_vehiculos_en_contacto.erase(body)

func _physics_process(_delta: float) -> void:
	if _vehiculos_en_contacto.is_empty():
		return
	var vehiculo: Node = _vehiculos_en_contacto.keys()[0]
	linear_velocity = vehiculo.get_velocidad_actual()
	angular_velocity = Vector3.ZERO
