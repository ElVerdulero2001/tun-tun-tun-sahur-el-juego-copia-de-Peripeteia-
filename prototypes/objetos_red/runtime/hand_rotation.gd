extends RefCounted

## La orientación local se conserva como cuaternión unitario. No se acumulan
## matrices de float32 sin volver a imponer la condición de rotación.
var orientation := Quaternion.IDENTITY

func reset_basis(value: Basis) -> bool:
	if not value.is_finite() or not is_finite(value.determinant()) or value.determinant() <= 0.000001: return false
	var candidate := value.orthonormalized().get_rotation_quaternion().normalized()
	if not candidate.is_finite(): return false
	orientation = candidate
	return true

func rotate_mouse(delta: Vector2, camera_right: Vector3) -> bool:
	if not delta.is_finite() or not camera_right.is_finite() or camera_right.length_squared() < 0.000001: return false
	var yaw := Quaternion(Vector3.UP, -delta.x * 0.004)
	var pitch := Quaternion(camera_right.normalized(), -delta.y * 0.004)
	var candidate := (pitch * yaw * orientation).normalized()
	if not candidate.is_finite(): return false
	orientation = candidate
	return true

func basis() -> Basis:
	return Basis(orientation)

static func rotation_only_target(value: Transform3D):
	# Esta conversión pertenece a la API LOCAL de intención: el objetivo
	# representa posición y orientación, nunca escala o cizalla del cuerpo.
	# Los paquetes de red no pasan por aquí: deben ser rotaciones válidas.
	if not value.origin.is_finite() or not value.basis.is_finite() \
		or not is_finite(value.basis.determinant()) or value.basis.determinant() <= 0.000001: return null
	var q := value.basis.orthonormalized().get_rotation_quaternion().normalized()
	if not q.is_finite(): return null
	return Transform3D(Basis(q), value.origin)
