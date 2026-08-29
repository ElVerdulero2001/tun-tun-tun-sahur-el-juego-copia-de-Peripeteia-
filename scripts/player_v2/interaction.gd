extends Node

## InteractionV2 — capacidad de interacción de PlayerV2 (SUA-1.2).
##
## Responsabilidad ÚNICA: cada frame físico determina qué InteractionComponent
## tiene el Player apuntado, dentro del rango de interacción y SIN oclusión; y al
## recibir el input "interactuar", le entrega un Interaction(actor, &"usar").
##
## NO es: percepción general, fuente de targets para Kick, servicio de "qué mira
## el Player", HUD, sistema de debug, ni coordinador del Player. Sólo sabe qué
## significa INTERACTUABLE.
##
## Las tres dependencias se cablean por @export dentro de player_v2.tscn. No usa
## grupos, get_node por nombre, get_parent, búsquedas por tipo ni autoloads.
## Su posición en el árbol NO forma parte de su contrato.

# ── Dependencias explícitas (cableadas en player_v2.tscn) ────────────
## Quién realiza la interacción. Se coloca en Interaction.actor. Es PlayerV2.
@export var actor: Node
## Cuerpo físico del actor: se excluye de la query por su RID. Es Body.
@export var physics_body: CollisionObject3D
## Origen (global_position) y dirección (-global_transform.basis.z) del rayo.
## Es la Camera3D.
@export var aim_source: Node3D
## Máscara del rayo = "interactuables + oclusores". Valor provisional: layer 1
## (mundo/oclusores) + layer 2 (interactuables) = 3. Se revisa cuando el proyecto
## normalice sus collision layers (fuera del alcance de SUA-1.2).
@export_flags_3d_physics var interaction_ray_mask: int = 3

# ── Parámetro ───────────────────────────────────────────────────────
const INTERACTION_RANGE := 2.5

# ── Estado ──────────────────────────────────────────────────────────
## Único estado semántico del target. El propietario se DERIVA, no se copia.
var _current_component: InteractionComponent = null
## Sólo observabilidad/diagnóstico — NO es API pública.
var _last_hit_collider: Node = null

# ── API pública ─────────────────────────────────────────────────────

## Propietario del interactuable apuntado, o null si no hay target.
## Sólo lectura. Consumidores previstos: HUD, marco de enfoque, tests.
var current_target_owner: Node:
	get:
		return _current_component.get_parent() if _current_component != null else null

## Entrega un Interaction(actor, &"usar") al InteractionComponent apuntado.
## true = se ENTREGÓ (no implica que la acción del propietario haya tenido éxito;
## eso vive en interaction.resultado, que hoy no exponemos).
func try_interact() -> bool:
	if _current_component == null:
		return false
	var interaction := Interaction.new(actor, &"usar")
	_current_component.recibir_interaccion(interaction)
	return true

# ── Verificación de cableado (assert: sólo debug/editor, como InteractionComponent) ──
func _ready() -> void:
	assert(actor != null, "InteractionV2: 'actor' sin cablear (esperado: PlayerV2).")
	assert(physics_body != null, "InteractionV2: 'physics_body' sin cablear (esperado: Body).")
	assert(aim_source != null, "InteractionV2: 'aim_source' sin cablear (esperado: Camera3D).")

# ── Query propia, en el step físico ────────────────────────────────
func _physics_process(_delta: float) -> void:
	_current_component = null
	_last_hit_collider = null

	var space := aim_source.get_world_3d().direct_space_state
	var origin := aim_source.global_position
	var forward := -aim_source.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + forward * INTERACTION_RANGE, interaction_ray_mask
	)
	var exclude: Array[RID] = [physics_body.get_rid()]
	query.exclude = exclude

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return

	# El hit más cercano manda: no hay segunda query "para buscar detrás".
	_last_hit_collider = hit.collider as Node
	_current_component = _resolver_componente(hit.collider)

## Regla V2: el collider interactuable lleva un InteractionComponent como HIJO
## DIRECTO. Sin walk por ancestros, sin búsqueda por nombre.
func _resolver_componente(collider: Object) -> InteractionComponent:
	if not (collider is Node):
		return null
	for child in (collider as Node).get_children():
		if child is InteractionComponent:
			return child
	return null

# ── Input propio (único: "interactuar") ────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interactuar"):
		try_interact()
