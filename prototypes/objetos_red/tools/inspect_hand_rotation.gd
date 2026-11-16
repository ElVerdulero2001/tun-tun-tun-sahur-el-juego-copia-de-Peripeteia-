extends SceneTree

## Comprobación de construcción del productor real, no reemplaza el test
## independiente I16 que reproduce la fórmula antigua.
const Rotation := preload("res://runtime/hand_rotation.gd")
const HandInput := preload("res://runtime/hand_input.gd")

func _initialize() -> void:
	var rotation := Rotation.new()
	var failed := -1
	for i in 20001:
		var delta := Vector2(float(((i * 7) % 11) - 5), float(((i * 5) % 7) - 3))
		if not rotation.rotate_mouse(delta, Vector3.RIGHT):
			failed = i + 1
			break
		var frame := {"uid": 1, "epoch": 1, "session": 1, "tick": i,
			"target": Transform3D(rotation.basis(), Vector3(0, 1, 0))}
		if not HandInput.valid(frame) or HandInput.encode([frame]).size() != 48:
			failed = i + 1
			break
	print("HAND_ROTATION_PRODUCER " + JSON.stringify({"events": 20001, "first_failure": failed, "passed": failed == -1}))
	quit(0 if failed == -1 else 1)
