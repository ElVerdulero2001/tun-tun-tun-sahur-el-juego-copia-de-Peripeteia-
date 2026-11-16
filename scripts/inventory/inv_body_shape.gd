@tool
class_name InvBodyShape
extends InvPickupHitbox

## El cuerpo físico de un tipo de objeto suelto (desde el 2026-11-14): con qué
## formas cae, choca con el nivel y con los demás objetos, se apoya y pasa por
## una abertura cuando de verdad cabe. Va en InvItemDef.body_shape, se guarda
## con el resto del tipo y lo edita el panel Objetos (sección «Cuerpo físico»).
##
## Es independiente de la hitbox de agarre (InvItemDef.pickup_hitbox, con qué
## se apunta y se agarra): son dos recursos distintos, cada uno con lo suyo. Que
## esta clase herede de InvPickupHitbox es solo para compartir las formas
## simples, sus medidas, su lugar y sus validaciones; ninguna de las dos se usa
## en lugar de la otra.
##
## Las formas (desde el 2026-11-15, revisión pedida en
## docs/net/prompt_claude_revision_objetos_fisicos.md):
##
## - **Del modelo** (Kind.MODEL): las arma Godot con los triángulos del modelo
##   tal como se ve suelto (InvReach.item_faces), al preparar el objeto en el
##   editor (panel Objetos, «Generar», o addons/inventario_objetos/
##   preparar_cuerpos.gd para todos los del catálogo), y quedan guardadas acá en
##   `shapes`. El juego solo las carga: no genera nada al jugar, ni en cada
##   objeto, ni en cada conexión. Dos maneras (`generation`):
##   - CONVEX: una sola forma convexa que envuelve el modelo
##     (Mesh.create_convex_shape). Para lo compacto: tapa los huecos.
##   - PARTS: varias formas convexas, de la descomposición de Godot (V-HACD,
##     MeshInstance3D.create_multiple_convex_collisions), que conserva huecos y
##     entrantes: el aro de una llave, las patas de un banquito, un marco. Con
##     `max_parts`, `concavity` y `resolution` se ajusta.
##   `source` dice de qué modelo y con qué valores salieron. Si el modelo o los
##   valores cambian, quedan desactualizadas: el panel lo avisa y el juego no
##   las usa (InvItemPhysics usa una sola forma convexa del modelo y lo avisa en
##   la consola).
## - **Caja, esfera, cilindro**: una primitiva, con sus medidas y su lugar. Una
##   caja ajustada a una tabla es la mejor forma de una tabla.
## - **Forma propia** (Kind.CUSTOM, en el Inspector): un recurso de colisión
##   convexo, tal cual.
##
## Todo en el espacio del objeto suelto: el origen es el centro de la base del
## modelo ya escalado, en metros (como la hitbox de agarre).
##
## Hasta el 2026-11-15, con Kind.MODEL el juego partía el modelo en tajadas
## (`auto_parts`, `auto_axis`) en cada PC: dejaba rendijas de hasta 20 cm en la
## tabla larga (docs/net/problemas_objetos_fisicos_2026-11-14.md, punto 2). Eso
## ya no existe; un .tres de esos días que tenga esos dos valores los ignora.

enum Generation { CONVEX, PARTS }

## Lo más que puede partirse la descomposición.
const MAX_PARTS := 32
## Los límites de la concavidad y de la resolución de la descomposición.
const MIN_CONCAVITY := 0.001
const MAX_CONCAVITY := 1.0
const MIN_RESOLUTION := 10000
const MAX_RESOLUTION := 400000

@export_group("Del modelo")
## Cómo se arman las formas del modelo: una sola convexa, o varias (que
## conservan los huecos).
@export var generation := Generation.CONVEX
## Varias: cuántas formas, como mucho.
@export_range(1, 32) var max_parts := 16
## Varias: cuánto entrante deja pasar cada forma, en metros (más chico, más
## formas y más fieles al modelo). Con la de fábrica de Godot (1) un aro sale
## tapado. La de acá (0,01) y la resolución (100000) las eligió Claude el
## 2026-11-15: medido con la llave, el machete y la granada, la resolución es la
## que más cambia; con 10000 la llave sobraba el doble de su volumen.
@export_range(0.001, 1.0, 0.001) var concavity := 0.01
## Varias: con cuántos vóxeles mira el modelo (más, más fiel y más lento).
@export_range(10000, 400000, 10000) var resolution := 100000
## Las formas preparadas, en el espacio del objeto suelto.
@export var shapes: Array[ConvexPolygonShape3D] = []
## De qué salieron: la huella de los triángulos del modelo y cómo se armaron
## (InvItemPhysics.source_key). Distinta de la de ahora: desactualizadas.
@export var source := ""

# Sin _init que cambie `kind`: Godot no guarda un valor igual al de fábrica de
# la variable (Kind.BOX, el de la hitbox), y al leer el archivo quedaría el que
# pusiera _init. El panel Objetos la crea con lo que corresponde.


## Si tiene una forma configurada (siempre: también la del modelo es una
## elección, con sus formas preparadas).
func is_configured() -> bool:
	return true


## El cuerpo físico configurado de un tipo, si no tiene problemas; o null.
static func active_body(def: InvItemDef) -> InvBodyShape:
	var shape := def.body_shape if def != null else null
	if shape == null or not shape.problems().is_empty():
		return null
	return shape


func problems() -> PackedStringArray:
	var found := super.problems()
	if kind == Kind.MODEL:
		if generation != Generation.CONVEX and generation != Generation.PARTS:
			found.append("no es una manera conocida de armar las formas del modelo (%s)." % generation)
		if max_parts < 1 or max_parts > MAX_PARTS:
			found.append("las formas del modelo van de 1 a %d." % MAX_PARTS)
		if not is_finite(concavity) or concavity < MIN_CONCAVITY or concavity > MAX_CONCAVITY:
			found.append("la concavidad va de %s a %s." % [MIN_CONCAVITY, MAX_CONCAVITY])
		if resolution < MIN_RESOLUTION or resolution > MAX_RESOLUTION:
			found.append("la resolución va de %d a %d." % [MIN_RESOLUTION, MAX_RESOLUTION])
		for shape in shapes:
			var problem := shape_problem(shape)
			if problem != "":
				found.append("una de las formas preparadas no sirve: " + problem)
				break
	return found


## Cómo se arman las formas del modelo, en texto (va en `source`).
func generation_text() -> String:
	if generation == Generation.CONVEX:
		return "convexa"
	return "partes %d concavidad %s resolución %d" % [max_parts, _number_text(concavity), resolution]


## Lo que va en la huella: la forma y lo que cuenta de ella (las formas
## preparadas las suma InvItemPhysics, con sus puntos).
func effective_text() -> String:
	if kind == Kind.MODEL:
		return "del modelo " + generation_text()
	return super.effective_text()
