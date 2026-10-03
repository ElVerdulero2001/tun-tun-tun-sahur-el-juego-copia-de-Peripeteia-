class_name BaseRegistry
extends RefCounted

## Bases sobre las que se puede parar un actor: plataformas guionadas y balsas
## del host. El estado del actor guarda el id de su base y su posición relativa
## a ella; esto traduce el id al cuerpo que tiene cada máquina.
##
## Una base es un cuerpo con `base_id`, `base_origin()` (su origen tal como lo
## ven las consultas de física en este tick) y `base_velocity()` (la que hereda
## quien la deja). Por ahora las bases solo se trasladan: la posición relativa
## es la diferencia con su origen. El giro queda para más adelante.

static var _bases := {}  # id -> base


static func add(base) -> void:
	_bases[base.base_id] = base


static func remove(base) -> void:
	if _bases.get(base.base_id) == base:
		_bases.erase(base.base_id)


static func find(id: int):
	return _bases.get(id) if id != 0 else null


static func all() -> Array:
	return _bases.values()


## Origen de la base en este tick, o cero si no hay base (o ya no existe).
static func origin(id: int) -> Vector3:
	var base = find(id)
	return base.base_origin() if base != null else Vector3.ZERO


## Velocidad de la base en este tick, o cero.
static func velocity(id: int) -> Vector3:
	var base = find(id)
	return base.base_velocity() if base != null else Vector3.ZERO


## Id de base de un colisionador, o 0 si no es una base.
static func id_of(collider: Object) -> int:
	return collider.get("base_id") if collider != null and "base_id" in collider else 0


## Posición de un actor en el mundo: su posición relativa más el origen de su base.
static func world_position(state: ActorState) -> Vector3:
	return origin(state.base_id) + state.position
