extends CanvasLayer

@onready var campo = $Control/PanelContainer/VBoxContainer/LineEdit
@onready var feedback = $Control/PanelContainer/VBoxContainer/Label2
@onready var boton = $Control/PanelContainer/VBoxContainer/confirmar

var terminal_actual: Terminal = null

func _ready():
	visible = false
	boton.pressed.connect(_on_confirmar)

func abrir(terminal: Terminal):
	terminal_actual = terminal
	campo.text = ""
	feedback.text = ""
	visible = true
	campo.grab_focus()
	get_tree().paused = true

func cerrar():
	visible = false
	terminal_actual = null
	get_tree().paused = false

func _on_confirmar():
	if terminal_actual == null:
		return
	if campo.text == terminal_actual.contrasena:
		feedback.text = "ACCESO CONCEDIDO"
		var objetivo = terminal_actual.get_node(terminal_actual.objetivo)
		if objetivo:
			objetivo.desbloquear()
		await get_tree().create_timer(1.0).timeout
		cerrar()
	else:
		feedback.text = "CONTRASEÑA INCORRECTA"

func _input(event):
	if visible and event.is_action_pressed("ui_cancel"):
		cerrar()
