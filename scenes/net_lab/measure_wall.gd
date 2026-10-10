@tool
extends StaticBody3D

## Pared de medidas del laboratorio, para usar de escala: rayas cada 10 cm
## desde el piso, más largas cada 50 cm y de lado a lado cada metro, con la
## altura escrita al costado. Las rayas son solo dibujo, sin colisión.
##
## La pared es una caja centrada en el nodo; las rayas van en su cara +Z. Con
## @tool también se dibujan en el editor; no se guardan en la escena.

@export var size := Vector3(4.0, 3.5, 0.2)

const STEP := 0.1
const LINE_THICKNESS := 0.012
const LABEL_WIDTH := 0.6


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.08, 0.1)
	var face := size.z * 0.5 + 0.003
	var left := -size.x * 0.5
	var floor_y := -size.y * 0.5
	for i in range(int(round(size.y / STEP)) + 1):
		var height := i * STEP
		var length := 0.25
		if i % 10 == 0:
			length = size.x - LABEL_WIDTH
		elif i % 5 == 0:
			length = 0.8
		var line := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(length, LINE_THICKNESS, 0.004)
		mesh.material = material
		line.mesh = mesh
		line.position = Vector3(left + LABEL_WIDTH + length * 0.5, floor_y + height, face)
		add_child(line)
		if i % 5 == 0:
			var label := Label3D.new()
			label.text = ("%.1f m" % height).replace(".", ",")
			label.font_size = 40
			label.pixel_size = 0.004
			label.modulate = Color(0.08, 0.08, 0.1)
			label.outline_size = 0
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			label.position = Vector3(left + LABEL_WIDTH - 0.05, floor_y + height + 0.01, face)
			add_child(label)
