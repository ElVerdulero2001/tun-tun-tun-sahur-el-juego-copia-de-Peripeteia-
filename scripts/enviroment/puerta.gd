extends AnimatableBody3D

@export var angulo_apertura: float = 90.0
@export var velocidad: float = 2.0
@export var requiere_llave: bool = false
## Definición V2 (InventoryV2/ItemDefinition) del ítem que abre esta puerta.
## Identidad estable por referencia de recurso — no un id numérico frágil.
@export var llave_requerida: ItemDefinition

var abierta: bool = false
var moviendose: bool = false
var angulo_actual: float = 0.0
var direccion: float = 1.0
var desbloqueada: bool = false

func _on_interact(interaction: Interaction) -> Variant:
	match interaction.accion:
		&"usar":
			return _toggle(interaction.actor)
		_:
			return false

func _toggle(actor: Node = null) -> bool:
	if requiere_llave and not desbloqueada:
		if not _actor_tiene_llave(actor):
			# Antes iba un print acá ("Necesitas una llave"). Ese feedback
			# es de UI, no de esta lógica — el sistema que consuma este
			# false todavía no está diseñado.
			return false
		# La llave es credencial de desbloqueo, no consumible: no se toca
		# InventoryV2 acá. Desde este punto la puerta queda desbloqueada de
		# por vida para esta instancia — no vuelve a consultar InventoryV2
		# aunque el actor pierda la llave después.
		desbloqueada = true

	if moviendose:
		return false

	abierta = !abierta
	direccion = 1.0 if abierta else -1.0
	angulo_actual = 0.0
	moviendose = true
	return true

func desbloquear() -> void:
	desbloqueada = true
	_toggle()

## Consulta si `actor` posee un ítem cuya ItemDefinition sea `llave_requerida`,
## a través de la capacidad InventoryReceiver que el propio actor exponga
## como hijo directo — mismo patrón de resolución que
## WorldItemV2._resolver_receiver(): sin grupos, sin rutas rígidas, sin
## conocer el tipo concreto del actor. No toca Inventario (autoload V1).
func _actor_tiene_llave(actor: Node) -> bool:
	if actor == null or llave_requerida == null:
		return false
	var receiver: InventoryReceiver = null
	for child in actor.get_children():
		if child is InventoryReceiver:
			receiver = child
			break
	if receiver == null:
		return false
	for entry in receiver.inventory.get_entries():
		if entry.item_instance.definition == llave_requerida:
			return true
	return false

func _physics_process(delta):
	if not moviendose:
		return
	var paso = velocidad * delta
	rotate(Vector3.UP, paso * direccion)
	angulo_actual += paso
	if angulo_actual >= deg_to_rad(angulo_apertura):
		moviendose = false
		angulo_actual = 0.0
