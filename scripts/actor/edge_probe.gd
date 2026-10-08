class_name EdgeProbe
extends RefCounted

## Sonda de borde de la arquitectura: busca dónde pueden ir las manos, no dónde
## está el cuerpo. Sale un candidato de borde o nada.
##
## Un candidato es un diccionario con:
##   point:  el punto del filo en el mundo, sobre la cara de la pared a la
##           altura de la superficie de arriba;
##   normal: horizontal, de la pared hacia afuera (hacia quien cuelga);
##   base:   id de la base que lo lleva, o 0 si es geometría fija.
##
## Todo son consultas directas al espacio, así que da lo mismo en un tick
## repetido y en todas las máquinas.

## Manos: una caja chata delante del pecho, del borde de la cápsula hacia
## afuera. Es ancha y profunda para no saltarse paredes finas.
const HANDS_SIZE := Vector3(0.4, 0.06, 0.3)
## Cuánto entra la caja de las manos en la cápsula: así toca una pared pegada.
const HANDS_OVERLAP := 0.05
## La superficie de arriba se busca unos centímetros adentro del filo, para
## esquivar la arista redondeada de Jolt.
const TOP_INSET := 0.03
## Rayo de la cara: arranca este tanto por debajo del punto de contacto.
const FACE_DROP := 0.05
## Pendiente máxima de la superficie de arriba y de la cara (desde la vertical).
const MAX_TOP_ANGLE := deg_to_rad(30.0)
const MAX_FACE_TILT := deg_to_rad(20.0)
## Al revalidar un borde ya agarrado: cuánto puede moverse el filo encontrado.
const HOLD_TOLERANCE := 0.1


## Dónde van las manos con los pies en `feet`, mirando hacia `toward`.
static func hands_at(body: ActorBody, feet: Vector3, toward: Vector3, tuning: ActorTuning) -> Vector3:
	var forward := body.capsule_radius() - HANDS_OVERLAP + HANDS_SIZE.z * 0.5
	return feet + Vector3.UP * tuning.hang_height + toward * forward


## Barrido de manos: de `from` a `to`, mirando hacia `toward`. Si la caja ya
## arranca tocando algo (el barrido lo ignora), se prueba en la posición final.
##
## El filo se busca de frente al cuerpo, a la altura del contacto: la caja es
## ancha y puede tocar con una punta. Si de frente no hay borde (la punta tocó
## el final de una cornisa), se busca donde tocó.
static func find(body: ActorBody, from: Vector3, to: Vector3, toward: Vector3) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = HANDS_SIZE
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box
	params.collision_mask = body.collision_mask
	params.exclude = [body.get_rid()]
	var basis := Basis.looking_at(toward, Vector3.UP)
	params.transform = Transform3D(basis, from)
	params.motion = to - from
	var fractions := space.cast_motion(params)
	var at := to
	if fractions[1] < 1.0:
		at = from + (to - from) * fractions[1]
	params.transform = Transform3D(basis, at)
	params.motion = Vector3.ZERO
	var rest := space.get_rest_info(params)
	if rest.is_empty():
		return {}
	var contact: Vector3 = rest["point"]
	var ahead := _edge_from_contact(body, Vector3(at.x, contact.y, at.z), toward)
	if not ahead.is_empty():
		return ahead
	return _edge_from_contact(body, contact, toward)


## Revalida un borde agarrado en `point`, con la normal que tenía. Sirve cada
## tick colgado (el borde sigue ahí) y al desplazarse (el borde continúa).
static func hold(body: ActorBody, point: Vector3, normal: Vector3) -> Dictionary:
	var edge := _edge_from_contact(body, point - normal * TOP_INSET, -normal)
	if edge.is_empty() or edge["point"].distance_to(point) > HOLD_TOLERANCE:
		return {}
	return edge


## Con un punto que tocaron las manos y la dirección hacia la pared: la cara
## frontal con un rayo horizontal, la superficie de arriba con un rayo hacia
## abajo, y el filo donde se cruzan.
static func _edge_from_contact(body: ActorBody, contact: Vector3, toward: Vector3) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var face_from := contact + Vector3.DOWN * FACE_DROP - toward * 0.4
	var face := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			face_from, face_from + toward * 0.8, body.collision_mask, [body.get_rid()]))
	if face.is_empty():
		return {}
	var normal: Vector3 = face["normal"]
	if absf(normal.y) > sin(MAX_FACE_TILT):
		return {}
	normal = Vector3(normal.x, 0.0, normal.z).normalized()
	var face_point: Vector3 = face["position"]
	var top_x := face_point - normal * TOP_INSET
	var top_from := Vector3(top_x.x, contact.y + 0.25, top_x.z)
	var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			top_from, top_from + Vector3.DOWN * 0.5, body.collision_mask, [body.get_rid()]))
	if top.is_empty():
		return {}
	if (top["normal"] as Vector3).angle_to(Vector3.UP) > MAX_TOP_ANGLE:
		return {}
	var top_point: Vector3 = top["position"]
	if top_point.y < face_point.y:
		return {}
	var point := Vector3(face_point.x, top_point.y, face_point.z)
	return {"point": point, "normal": normal, "base": BaseRegistry.id_of(top["collider"])}
