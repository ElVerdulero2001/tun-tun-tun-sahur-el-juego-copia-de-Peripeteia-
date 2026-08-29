extends StaticBody3D

## Interactuable mínimo del sandbox de PlayerV2 (SUA-1.2).
##
## Usa el InteractionComponent y el contrato _on_interact(interaction) ACTUALES,
## sin tocar Inventario, terminales, puertas ni ningún sistema del juego.
## Al recibir Interaction(&"usar") cambia de color y loguea UNA línea puntual
## (no por frame) con el actor recibido, para verificar el contrato a ojo y en
## consola — en particular que interaction.actor == PlayerV2 (no Body).

@export var color_inactivo: Color = Color(0.55, 0.56, 0.62)
@export var color_activo: Color = Color(0.20, 0.80, 0.35)

var veces_usado: int = 0

@onready var _mesh: MeshInstance3D = $MeshInstance3D
var _material: StandardMaterial3D

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = color_inactivo
	_mesh.material_override = _material

## Contrato de InteractionComponent.
func _on_interact(interaction: Interaction) -> Variant:
	if interaction.accion != &"usar":
		return false
	veces_usado += 1
	var a := interaction.actor
	var actor_desc := "%s [%s]" % [a.name, a.get_class()] if a != null else "<null>"
	print("[%s] usar #%d — actor recibido: %s" % [name, veces_usado, actor_desc])
	_material.albedo_color = color_activo if (veces_usado % 2 == 1) else color_inactivo
	return true
