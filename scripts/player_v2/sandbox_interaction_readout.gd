extends Label

## Lectura en vivo del estado de InteractionV2, SÓLO para las pruebas manuales
## de SUA-1.2. NO forma parte de InteractionV2 — vive únicamente en el sandbox.
##
## Muestra:
##   target : current_target_owner (API pública)
##   hit    : _last_hit_collider (var de diagnóstico) → permite distinguir
##            "no golpeó nada" / "golpeó no-interactuable" / "golpeó interactuable"

@export var interaction: Node

func _process(_delta: float) -> void:
	if interaction == null:
		text = "InteractionV2: <sin cablear>"
		return
	var target := interaction.get("current_target_owner") as Node
	var hit := interaction.get("_last_hit_collider") as Node
	text = "target: %s\nhit:    %s" % [
		target.name if target != null else "(ninguno)",
		hit.name if hit != null else "(nada)",
	]
