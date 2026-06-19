extends Path3D


func _ready() -> void:

	actualizar_routepoints()


func actualizar_routepoints() -> void:

	var routepoints: Array = []

	for child in get_children():

		if child is PathFollow3D:
			routepoints.append(child)

	routepoints.sort_custom(
		func(a, b):
			return a.progress < b.progress
	)

	print("")
	print("===== ROUTEPOINTS =====")
	print("")

	for i in range(routepoints.size()):

		var rp = routepoints[i]

		var tipo := "DESCONOCIDO"

		match rp.point_type:

			rp.RoutePointType.BRAKE:
				tipo = "BRAKE"

			rp.RoutePointType.STOP:
				tipo = "STOP"

			rp.RoutePointType.CRUISE:
				tipo = "CRUISE"

		print(
			"#",
			i,
			" | ",
			rp.name,
			" | ",
			tipo,
			" | Progress: ",
			rp.progress,
			"m"
		)

	print("")
	print("======================")
	print("")
