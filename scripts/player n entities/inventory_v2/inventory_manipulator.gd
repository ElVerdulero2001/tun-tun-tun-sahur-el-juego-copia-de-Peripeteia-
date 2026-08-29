class_name InventoryManipulator
extends Control

## Máquina de estados de manipulación de un InventoryV2 dentro de su
## InventoryGridView (Inventory V1, Paso 5).
##
## NO muta el InventoryV2 nunca. Toda reubicación real pasa por
## LocalAuthority.solicitar_reubicacion(). Durante el preview NADA del
## modelo cambia: la celda y la rotación tentativas viven SOLO acá.
##
## Reglas:
##  - no llama _agregar_entry / _quitar_entry / _reubicar_entry;
##  - el único camino de mutación es LocalAuthority;
##  - si el drop falla, el ítem sigue "held" y el modelo queda idéntico;
##  - cancelar() descarta el estado transitorio sin tocar el modelo.
##
## El ghost/preview lo dibuja ESTE nodo. La vista (InventoryGridView) sigue
## siendo estrictamente read-only.
##
## La capa de input (_unhandled_input) es fina: solo traduce eventos a las
## transiciones públicas (agarrar_en / mover_hover_a / rotar_tentativo /
## soltar / cancelar / descartar_fuera), que también usan los tests.
## Al soltar con item held, el cursor cae en una de tres regiones (ver
## _region_de_drop, en pixeles local-space de InventoryGridView):
##   GRILLA      -> soltar() (reubicacion; puede fallar y seguir held);
##   ZONA_NEUTRA -> NO-OP absoluto: el item sigue held/unido al mouse (evita
##                  drops accidentales al pasarse apenas del borde);
##   EXTERIOR    -> descartar_fuera() (emite la INTENCION drop_fuera_solicitado;
##                  no toca el modelo ni la autoridad).
##
## ACTIVACIÓN: _unhandled_input SOLO corre si el manipulator está activo
## (activar() / desactivar()). Ocultar la UI (visible=false) NO frena _input
## en Godot, así que la vista/harness debe llamar desactivar() al cerrar y
## activar() al abrir. Con el manipulator inactivo ningún clic/mouse/R puede
## seleccionar, mover, rotar ni soltar. Las transiciones públicas siguen
## siendo llamables directamente (los tests las usan como caja blanca).

signal agarrado(entry: InventoryEntry)
signal soltado(entry: InventoryEntry, exito: bool)
signal preview_cambiado()
signal cancelado(entry: InventoryEntry)
signal rotacion_rechazada(entry: InventoryEntry)
## El usuario solto el item held con el cursor FUERA del rectangulo de la grilla.
## Es INTENCION, no ejecucion: el manipulator NO saca el item del InventoryV2 ni
## llama a LocalAuthority — solo sabe que se pidio soltarlo afuera. Quien conecte
## esta señal decide que hacer (drop al mundo, dar a otra entidad, etc.). Si esa
## operacion no ocurre o falla, el ItemInstance sigue en InventoryV2 en su celda
## original (el manipulator no lo movio).
signal drop_fuera_solicitado(item_instance: ItemInstance)

## Region donde cayo el cursor al soltar un item held (ver _region_de_drop).
enum RegionDrop { GRILLA, ZONA_NEUTRA, EXTERIOR }

@export var color_ghost_valido: Color = Color(0.30, 0.90, 0.40, 0.45)
@export var color_ghost_invalido: Color = Color(0.95, 0.30, 0.30, 0.45)
@export var color_origen: Color = Color(1, 1, 1, 0.14)
## Margen en pixeles del anillo NEUTRO alrededor de la grilla. Existe SOLO para
## evitar drops accidentales al pasarse apenas del borde: soltar dentro de ese
## anillo es NO-OP (el item sigue held). NO se liga a cell_size — se ajusta por
## sensacion sin tocar reglas del inventario. 0 = sin zona neutra (equivale a la
## semantica de C5-B: fuera de la grilla = descartar_fuera).
@export var drop_neutral_margin_px: float = 24.0

var _view: InventoryGridView = null
var _authority: LocalAuthority = null

## Solo cuando está activo se procesa input (ver activar() / desactivar()).
var _activo: bool = false

## SNAPSHOT (copia detached) de la entry agarrada, tomada en agarrar_en().
## NUNCA la entry viva del modelo (D1): mutarla no afecta al inventario.
## Valida durante todo el grab porque la entry real no se reubica mientras
## hay un grab en curso (soltar/cancelar lo terminan). item_instance ES la
## referencia real (identidad compartida) -> se usa para pedirle a la
## autoridad la reubicacion.
var _seleccionada: InventoryEntry = null
var _rotacion_tentativa: bool = false
var _celda_hover: Vector2i = Vector2i.ZERO

## Celda agarrada, relativa a entry.position, SIEMPRE expresada en el frame
## de la orientacion NORMAL (sin rotar) del item — su frame canonico.
## Guardada una sola vez al agarrar y nunca mutada: por eso alternar la
## rotacion tentativa N veces no puede acumular desplazamiento.
## El offset efectivo (en la orientacion tentativa actual) se deriva bajo
## demanda con _offset_efectivo(); ver nota en agarrar_en().
var _agarre_rel_normal: Vector2i = Vector2i.ZERO


func _ready() -> void:
	# Arranca INACTIVO: nada de input hasta que la UI se abra y llame activar().
	set_process_unhandled_input(false)


func setup(view: InventoryGridView, authority: LocalAuthority) -> void:
	_view = view
	_authority = authority
	queue_redraw()


func esta_activo() -> bool:
	return _activo

## Al ABRIR la UI. Parte de estado limpio (sin held ni preview) y habilita
## el procesamiento de input.
func activar() -> void:
	cancelar()                       # garantiza que no quede held previo
	_celda_hover = Vector2i.ZERO
	_activo = true
	set_process_unhandled_input(true)
	queue_redraw()

## Al CERRAR la UI. Cancela cualquier held (como ya estaba previsto) y deja
## de procesar input: con la UI cerrada el manipulator queda totalmente inerte.
func desactivar() -> void:
	cancelar()
	_activo = false
	set_process_unhandled_input(false)
	queue_redraw()


func _inventario() -> InventoryV2:
	return _view.get_inventory() if _view != null else null


# ── Estado / consultas (puras) ─────────────────────────────────────

func esta_agarrando() -> bool:
	return _seleccionada != null

## SNAPSHOT de la entry agarrada (o null). NO es la entry viva del modelo.
func entry_agarrada() -> InventoryEntry:
	return _seleccionada

## ItemInstance agarrado (identidad real compartida), o null.
func item_agarrado() -> ItemInstance:
	return _seleccionada.item_instance if _seleccionada != null else null

func rotacion_tentativa() -> bool:
	return _rotacion_tentativa

func celda_hover() -> Vector2i:
	return _celda_hover

## Offset del punto de agarre DENTRO del footprint, en la orientacion
## tentativa actual. Si la rotacion tentativa coincide con la normal es
## _agarre_rel_normal tal cual; si esta rotada, se transforma 90°. Siempre
## cae dentro del footprint tentativo -> el cursor nunca "sale" del ghost.
func _offset_efectivo() -> Vector2i:
	if _seleccionada == null:
		return Vector2i.ZERO
	if not _rotacion_tentativa:
		return _agarre_rel_normal
	return _rel_normal_a_rotada(_agarre_rel_normal, _seleccionada.item_instance.definition)

## Diagnostico/tests: el offset efectivo actual del punto de agarre.
func offset_agarre_actual() -> Vector2i:
	return _offset_efectivo()

func celda_destino_tentativa() -> Vector2i:
	return _celda_hover - _offset_efectivo()

func destino_es_valido() -> bool:
	if _seleccionada == null:
		return false
	var inv := _inventario()
	if inv == null:
		return false
	return inv.posicion_valida(
		_seleccionada.item_instance, celda_destino_tentativa(),
		_rotacion_tentativa, _seleccionada.item_instance
	)


# ── Transiciones (input las llama; los tests también) ──────────────

## Agarra la entry que ocupa `celda`. Devuelve true si había algo.
## NO muta el modelo: la entry sigue en _entries en su posición real.
func agarrar_en(celda: Vector2i) -> bool:
	if _seleccionada != null:
		return false
	var inv := _inventario()
	if inv == null:
		return false
	var entry := inv.entry_en_celda(celda)
	if entry == null:
		return false
	_seleccionada = entry
	_rotacion_tentativa = entry.rotated
	# La celda agarrada llega en el frame de la orientacion ACTUAL de la
	# entry; la guardamos siempre en el frame normal (canonico) para que la
	# rotacion tentativa pueda transformarla sin acumular error.
	var celda_rel := celda - entry.position
	if entry.rotated:
		_agarre_rel_normal = _rel_rotada_a_normal(celda_rel, entry.item_instance.definition)
	else:
		_agarre_rel_normal = celda_rel
	_celda_hover = celda
	queue_redraw()
	agarrado.emit(entry)
	return true

## Mueve la celda bajo el cursor. Solo repinta/emite si hay algo agarrado.
func mover_hover_a(celda: Vector2i) -> void:
	if _celda_hover == celda:
		return
	_celda_hover = celda
	if _seleccionada != null:
		queue_redraw()
		preview_cambiado.emit()

## Alterna la rotación TENTATIVA. Solo si ItemDefinition.can_rotate.
## Devuelve true si se aplicó. NO muta entry.rotated real.
func rotar_tentativo() -> bool:
	if _seleccionada == null:
		return false
	if not _seleccionada.item_instance.definition.can_rotate:
		rotacion_rechazada.emit(_seleccionada)
		return false
	_rotacion_tentativa = not _rotacion_tentativa
	queue_redraw()
	preview_cambiado.emit()
	return true

## Suelta el ítem held en la celda destino tentativa, vía LocalAuthority.
## true si la reubicación se completó. Si falla: sigue held, modelo idéntico.
func soltar() -> bool:
	if _seleccionada == null:
		return false
	var inv := _inventario()
	if _authority == null or inv == null:
		return false
	var entry := _seleccionada
	var exito: bool = _authority.solicitar_reubicacion(
		entry.item_instance, inv, celda_destino_tentativa(), _rotacion_tentativa
	)
	if exito:
		_seleccionada = null
		_rotacion_tentativa = false
		_agarre_rel_normal = Vector2i.ZERO
	queue_redraw()
	soltado.emit(entry, exito)
	return exito

## Descarta el estado transitorio SIN mutar el modelo. La entry queda
## exactamente donde estaba. Se llama al cerrar la UI o con ui_cancel.
func cancelar() -> void:
	if _seleccionada == null:
		return
	var entry := _seleccionada
	_seleccionada = null
	_rotacion_tentativa = false
	_agarre_rel_normal = Vector2i.ZERO
	queue_redraw()
	cancelado.emit(entry)

## Transicion: el usuario suelta el held con el cursor FUERA del rectangulo de
## la grilla. NO es reubicacion (no toca LocalAuthority) ni cancelacion (no
## emite `cancelado`): es una SOLICITUD de sacar el item. Pasos (C5-B):
##   1. captura la referencia real de ItemInstance;
##   2. limpia el estado held LOCAL (igual que cancelar, sin tocar el modelo);
##   3. repinta (el ghost desaparece);
##   4. emite drop_fuera_solicitado(item_instance).
## El InventoryV2 NO se modifica aca. Si el consumidor no completa el drop, el
## item sigue en su celda original.
func descartar_fuera() -> void:
	if _seleccionada == null:
		return
	var ii := _seleccionada.item_instance
	_seleccionada = null
	_rotacion_tentativa = false
	_agarre_rel_normal = Vector2i.ZERO
	queue_redraw()
	drop_fuera_solicitado.emit(ii)


# ── Input real (fino: solo traduce a las transiciones de arriba) ────

func _unhandled_input(event: InputEvent) -> void:
	if not _activo:
		return
	if _view == null or _inventario() == null:
		return

	if event is InputEventMouseMotion:
		mover_hover_a(_celda_bajo_mouse())
		return

	if event.is_action_pressed("rotar_item"):
		rotar_tentativo()
		return

	if event.is_action_pressed("ui_cancel"):
		cancelar()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_celda_hover = _celda_bajo_mouse()
		if _seleccionada == null:
			agarrar_en(_celda_hover)
		else:
			_resolver_click_held(_view.get_local_mouse_position())


func _celda_bajo_mouse() -> Vector2i:
	var cs: int = _view.cell_size
	var pos := _view.get_local_mouse_position()
	return Vector2i(floori(pos.x / cs), floori(pos.y / cs))


## Resuelve un click izquierdo CON item held segun la region donde cayo el
## cursor (`pos_local` en el espacio de InventoryGridView). Lo llama
## _unhandled_input con la posicion real; los tests lo llaman con posiciones
## explicitas (headless no puede posicionar el mouse real).
func _resolver_click_held(pos_local: Vector2) -> void:
	match _region_de_drop(pos_local):
		RegionDrop.GRILLA:
			soltar()                 # reubicacion; si el destino es invalido -> sigue held
		RegionDrop.EXTERIOR:
			descartar_fuera()        # intencion de drop (C5-B); no toca el modelo
		RegionDrop.ZONA_NEUTRA:
			pass                     # NO-OP absoluto: el item sigue held/unido al mouse


## Clasifica `pos_local` (espacio local de InventoryGridView, donde la grilla se
## dibuja desde el origen) en una de tres regiones:
##   GRILLA      = rectangulo real de celdas: Rect2(0, 0, W*cell_size, H*cell_size).
##   ZONA_NEUTRA = ese rectangulo crecido drop_neutral_margin_px (anillo de guarda).
##   EXTERIOR    = mas alla.
## Fuente geometrica: grid_width/grid_height (InventoryV2, ya se leen aca) +
## cell_size (InventoryGridView, ya se lee en _celda_bajo_mouse). No necesita
## API nueva de InventoryGridView. No hardcodea dimensiones ni cell_size.
##
## Convencion de bordes (Rect2.has_point de Godot: superior-izquierda inclusive,
## inferior-derecha exclusive):
##   - borde derecho/inferior a EXACTAMENTE `margin` px  -> EXTERIOR;
##   - borde izquierdo/superior a EXACTAMENTE `-margin` px -> ZONA_NEUTRA.
## No es un anillo perfectamente simetrico a nivel subpixel; es la convencion de
## Rect2 y se testea asi.
func _region_de_drop(pos_local: Vector2) -> RegionDrop:
	var inv := _inventario()
	if _view == null or inv == null:
		return RegionDrop.EXTERIOR
	var cs: int = _view.cell_size
	var grid_rect := Rect2(Vector2.ZERO, Vector2(inv.grid_width * cs, inv.grid_height * cs))
	if grid_rect.has_point(pos_local):
		return RegionDrop.GRILLA
	if grid_rect.grow(drop_neutral_margin_px).has_point(pos_local):
		return RegionDrop.ZONA_NEUTRA
	return RegionDrop.EXTERIOR


func _footprint_de(def: ItemDefinition, rotated: bool) -> Vector2i:
	if rotated:
		return Vector2i(def.grid_height, def.grid_width)
	return Vector2i(def.grid_width, def.grid_height)


# ── Transformacion de una celda-relativa entre las dos orientaciones ──
# Rotacion de 90° horaria. _rel_rotada_a_normal es su inversa EXACTA, asi
# que alternar la rotacion N veces devuelve siempre a _agarre_rel_normal
# sin acumular desplazamiento. `def` aporta el tamano NORMAL (W = grid_width,
# H = grid_height); el footprint rotado es (H, W).

## (x, y) en el footprint normal (W x H)  ->  celda en el rotado (H x W).
func _rel_normal_a_rotada(c: Vector2i, def: ItemDefinition) -> Vector2i:
	return Vector2i(def.grid_height - 1 - c.y, c.x)

## (x, y) en el footprint rotado (H x W)  ->  celda en el normal (W x H).
func _rel_rotada_a_normal(c: Vector2i, def: ItemDefinition) -> Vector2i:
	return Vector2i(c.y, def.grid_height - 1 - c.x)


func _draw() -> void:
	if _view == null or _seleccionada == null:
		return
	var cs: int = _view.cell_size

	# celda(s) de origen, tenues
	var fp_orig := _seleccionada.get_footprint()
	draw_rect(Rect2(
		_seleccionada.position.x * cs, _seleccionada.position.y * cs,
		fp_orig.x * cs, fp_orig.y * cs), color_origen, true)

	# ghost del destino tentativo (verde válido / rojo inválido)
	var fp := _footprint_de(_seleccionada.item_instance.definition, _rotacion_tentativa)
	var destino := celda_destino_tentativa()
	var col := color_ghost_valido if destino_es_valido() else color_ghost_invalido
	draw_rect(Rect2(destino.x * cs, destino.y * cs, fp.x * cs, fp.y * cs), col, true)
