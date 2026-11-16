extends SceneTree

## Inspección de capacidades del binario instalado. No ejecuta simulación.
func _initialize() -> void:
	var methods: Array[String] = []
	for method: Dictionary in PhysicsServer3D.get_method_list():
		var name: String = method.name
		if "step" in name or "save" in name or "restore" in name:
			methods.append(name)
	print(JSON.stringify({"engine": Engine.get_version_info().string,
		"physics_server": PhysicsServer3D.get_class(), "step_state_methods": methods}))
	quit()
