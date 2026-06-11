extends Node3D
## ============================================================
## SETUP DE ENTORNO — TEST DE ESCALA (estética Max Payne 2) v2
## ============================================================
## Uso:
##   1. Adjuntar a un Node3D dentro de la escena de test.
##   2. Ejecutar. El script:
##      - Si ya existe un WorldEnvironment en la escena, le PISA
##        el environment con el del test (no hace falta tocar nada).
##      - Apaga todas las DirectionalLight3D que encuentre
##        (toggle en el Inspector). Tu escena no se modifica:
##        esto pasa solo en runtime.
##      - Crea marcadores de distancia y farolas de muestra.
##
## Todo lo importante está expuesto en el Inspector.
##
## NOTA: SSAO y fog volumétrico requieren el renderer Forward+.
## Si estás en Compatibility, el script los saltea solo.

@export_group("Escala y visibilidad")
## Distancia aproximada (en metros) a la que el fog tapa todo.
## ESTE es el valor que estás testeando. Probá 60, 100, 120.
@export var distancia_visibilidad: float = 100.0

@export_group("Control de la escena")
## Pisar el environment de cualquier WorldEnvironment existente.
## Si está apagado y hay otro WorldEnvironment, el test NO aplica.
@export var tomar_control_del_environment: bool = true
## Apagar todas las DirectionalLight3D al iniciar (solo runtime).
## La estética es "sin sol": dejalo prendido salvo que pruebes otra cosa.
@export var apagar_luces_direccionales: bool = true

@export_group("Ayudas de test")
## Pilares emisivos cada 25 m para VER dónde muere la visibilidad.
@export var crear_marcadores: bool = true
## Hasta qué distancia colocar marcadores.
@export var distancia_maxima_marcadores: float = 300.0
## Tres farolas de sodio de muestra (luz puntual, sombras duras).
@export var crear_farolas_demo: bool = true

@export_group("Estética (Max Payne 2)")
## Fog volumétrico: conos de luz visibles alrededor de las farolas.
## Más caro. Activalo recién cuando el greybox ande fluido.
@export var fog_volumetrico: bool = false
## Color del fog / del "cielo". Azul noche sucio.
@export var color_fog: Color = Color(0.035, 0.045, 0.065)
## Color de la luz ambiente. Apenas para que las sombras no sean negro puro.
@export var color_ambiente: Color = Color(0.10, 0.12, 0.16)
## Energía de la luz ambiente. MP2 vive entre 0.3 y 0.5.
@export var energia_ambiente: float = 0.4
## Color sodio de las farolas (naranja sucio).
@export var color_farola: Color = Color(1.0, 0.72, 0.40)


func _ready() -> void:
	_aplicar_environment()
	if apagar_luces_direccionales:
		_apagar_directional_lights()
	if crear_marcadores:
		_crear_marcadores_distancia()
	if crear_farolas_demo:
		_crear_farola(Vector3(6, 0, -15))
		_crear_farola(Vector3(-10, 0, -45))
		_crear_farola(Vector3(4, 0, -80))


# ============================================================
# ENVIRONMENT
# ============================================================
func _aplicar_environment() -> void:
	var env := _construir_environment()

	if tomar_control_del_environment:
		var existentes: Array[Node] = get_tree().current_scene.find_children(
			"*", "WorldEnvironment", true, false
		)
		if existentes.size() > 0:
			# El primero recibe el environment del test;
			# los demás se anulan para que no compitan.
			for i in existentes.size():
				var we_nodo := existentes[i] as WorldEnvironment
				we_nodo.environment = env if i == 0 else null
			print("[TestEscala] Environment pisado en: ", existentes[0].get_path())
			return

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment_Test"
	we.environment = env
	add_child(we)
	print("[TestEscala] WorldEnvironment nuevo creado.")


func _construir_environment() -> Environment:
	var env := Environment.new()

	# --- Fondo: sin cielo, sin sol. Negro azulado. ---
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.015, 0.022)

	# --- Ambiente: mínimo, frío. Las farolas hacen el trabajo. ---
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = color_ambiente
	env.ambient_light_energy = energia_ambiente

	# --- Fog exponencial: LA herramienta de escala. ---
	# Transmitancia = exp(-densidad * distancia).
	# densidad = 3 / d  =>  a la distancia d queda ~5% visible.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = color_fog
	env.fog_light_energy = 1.0
	env.fog_density = 3.0 / distancia_visibilidad
	env.fog_sky_affect = 1.0  # el fondo se funde con el fog: no hay horizonte

	# --- Tonemap: contraste filmico. ---
	# Alternativa: TONE_MAPPER_AGX (más cinematográfico en escenas oscuras,
	# pero desatura; vale la pena probar ambos).
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0

	# --- Glow: halo sutil en las luces puntuales y los marcadores. ---
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# --- Contraste alto, saturación baja: hormigón mojado. ---
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.15
	env.adjustment_saturation = 0.85

	# --- Solo Forward+ ---
	var metodo_render: String = str(
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")
	)
	if metodo_render == "forward_plus":
		# SSAO: oscurece rincones y encuentros de hormigón. Clave en greybox
		# sin texturas para leer los volúmenes.
		env.ssao_enabled = true
		env.ssao_radius = 2.0
		env.ssao_intensity = 2.0

		if fog_volumetrico:
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.03
			env.volumetric_fog_albedo = Color(0.5, 0.55, 0.65)
			env.volumetric_fog_length = 80.0
			env.volumetric_fog_anisotropy = 0.5
			env.volumetric_fog_detail_spread = 2.0
	else:
		push_warning("Renderer no es Forward+: SSAO y fog volumétrico desactivados.")

	return env


# ============================================================
# APAGAR SOLES (solo en runtime, la escena guardada no cambia)
# ============================================================
func _apagar_directional_lights() -> void:
	var soles: Array[Node] = get_tree().current_scene.find_children(
		"*", "DirectionalLight3D", true, false
	)
	for sol in soles:
		(sol as DirectionalLight3D).visible = false
		print("[TestEscala] DirectionalLight apagada: ", sol.get_path())


# ============================================================
# MARCADORES DE DISTANCIA (cada 25 m hacia -Z)
# ============================================================
func _crear_marcadores_distancia() -> void:
	var contenedor := Node3D.new()
	contenedor.name = "MarcadoresDistancia"
	add_child(contenedor)

	var distancia: float = 25.0
	var indice: int = 1
	while distancia <= distancia_maxima_marcadores:
		var pilar := MeshInstance3D.new()
		pilar.name = "Marcador_%dm" % int(distancia)

		var malla := BoxMesh.new()
		malla.size = Vector3(1.0, 8.0, 1.0)
		pilar.mesh = malla

		var mat := StandardMaterial3D.new()
		# Alternar cian / magenta para contar pilares fácil a la distancia.
		var color_base: Color = Color(0.1, 0.9, 0.9) if indice % 2 == 1 else Color(0.9, 0.2, 0.7)
		mat.albedo_color = color_base
		mat.emission_enabled = true
		mat.emission = color_base
		mat.emission_energy_multiplier = 1.5
		pilar.material_override = mat

		pilar.position = Vector3(0.0, 4.0, -distancia)
		contenedor.add_child(pilar)

		distancia += 25.0
		indice += 1


# ============================================================
# FAROLA DE MUESTRA (poste + OmniLight sodio con sombras)
# ============================================================
func _crear_farola(pos: Vector3) -> void:
	var farola := Node3D.new()
	farola.name = "Farola"
	farola.position = pos
	add_child(farola)

	var poste := MeshInstance3D.new()
	var malla_poste := BoxMesh.new()
	malla_poste.size = Vector3(0.2, 5.0, 0.2)
	poste.mesh = malla_poste
	poste.position = Vector3(0.0, 2.5, 0.0)
	farola.add_child(poste)

	var luz := OmniLight3D.new()
	luz.light_color = color_farola
	luz.light_energy = 20.0
	luz.omni_range = 15.0
	luz.shadow_enabled = true
	# Charco de luz definido, caída rápida: lighting puntual estilo MP2.
	luz.omni_attenuation = 1.5
	luz.position = Vector3(0.0, 4.8, 0.0)
	farola.add_child(luz)
