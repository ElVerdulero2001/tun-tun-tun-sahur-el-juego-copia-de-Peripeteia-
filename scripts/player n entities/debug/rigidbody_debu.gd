extends RigidBody3D

var _last_contact_count: int = -1

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 8


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var contact_count := state.get_contact_count()

	# Solo imprimir cuando cambia la cantidad de contactos
	if contact_count == _last_contact_count:
		return

	_last_contact_count = contact_count

	print("\n========================================")
	print("OBJETO: ", name)
	print("CONTACTOS: ", contact_count)

	if contact_count == 0:
		return

	for i in range(contact_count):

		var collider := state.get_contact_collider_object(i)

		print("----------------------------------------")
		print("Contacto: ", i)

		if collider:
			print("Collider: ", collider.name)
		else:
			print("Collider: null")

		print("Posición local: ", state.get_contact_local_position(i))
		print("Normal local: ", state.get_contact_local_normal(i))
		print("Velocidad del collider: ", state.get_contact_collider_velocity_at_position(i))
