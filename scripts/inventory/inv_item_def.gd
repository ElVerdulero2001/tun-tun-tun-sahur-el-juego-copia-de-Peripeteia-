@tool
class_name InvItemDef
extends Resource

## Definición de un tipo de objeto: lo que comparten todas sus instancias. Es
## un recurso compartido y en el juego no se modifica nunca: la cantidad, el
## estado y el lugar de cada objeto van en su InvStack y en su colocación
## dentro de una InvGrid.
##
## Para crear un tipo: en FileSystem, clic derecho → Create New → Resource… →
## InvItemDef; completarlo en el Inspector y sumarlo a la lista del catálogo
## (InvCatalog). El id tiene que ser único: es lo que viaja por red. El panel
## Objetos del editor (addons/inventario_objetos) hace todo eso con un botón.

## Identificador estable del tipo. Viaja por red; no se muestra.
@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""

@export_group("Grilla")
## Ancho y alto en celdas, sin girar.
@export var size := Vector2i.ONE
## Si se puede girar (R con el objeto en la mano: 90° por vez, cuatro posiciones).
@export var can_rotate := true

@export_group("Pila")
@export var stackable := false
## Cuántas unidades entran en una pila. Sin apilar, siempre 1.
@export_range(1, 9999) var max_stack := 1

@export_group("Capacidades")
## Lo que se puede hacer con él (usar, equipar). La primera es la que hace la
## barra rápida.
@export var abilities: Array[InvAbility] = []

@export_group("Estado")
## Estado con que nace cada instancia (por ejemplo {"carga": 100}). Dos pilas
## del mismo tipo se juntan solo si su estado es igual.
@export var default_state := {}

@export_group("Modelo")
## Lo que se ve en el mundo, en la mano y en la miniatura: un .glb o un .tscn.
## Solo se usan sus mallas: no corre sus scripts ni su física.
@export var model: PackedScene
## Alternativa sin modelo: una malla suelta, con este color si no trae material.
@export var mesh: Mesh
@export var color := Color(0.62, 0.62, 0.66)
## Medida del lado más largo en el mundo, en metros.
@export var world_size := 0.45

@export_group("Miniatura")
## Giro del modelo para la miniatura, en grados.
@export var thumbnail_rotation := Vector3(-20.0, 35.0, 0.0)
## Más de 1 acerca el modelo; menos, deja más margen.
@export_range(0.3, 3.0, 0.05) var thumbnail_zoom := 1.0
## Cuánto se corre el modelo dentro de la miniatura, en partes del cuadro:
## (0.25, 0) lo lleva un cuarto del ancho a la derecha; y positivo, para abajo.
@export var thumbnail_offset := Vector2.ZERO
## Si el lado largo del modelo no coincide con el de la huella, lo acuesta 90°.
@export var thumbnail_auto_align := true


## Cuántas unidades entran en una pila de este tipo.
func stack_limit() -> int:
	return maxi(max_stack, 1) if stackable else 1


## Ancho y alto en celdas con ese giro (0 a 3, de a 90° en el sentido del
## reloj): girado 90° o 270°, se cambian el ancho y el alto.
func footprint(rot: int) -> Vector2i:
	return Vector2i(size.y, size.x) if posmod(rot, 2) == 1 else size


## La primera capacidad de ese tipo, o null.
func ability_of(kind: int) -> InvAbility:
	for ability in abilities:
		if ability != null and ability.kind() == kind:
			return ability
	return null


## Cómo se ve: dos tipos con el mismo modelo y el mismo encuadre comparten
## miniatura.
func appearance_key() -> String:
	var source := ""
	if model != null:
		source = model.resource_path
	elif mesh != null:
		source = mesh.resource_path if mesh.resource_path != "" else "malla %d" % mesh.get_instance_id()
	return "%s|%s|%s|%s|%s|%s|%s" % [source, color.to_html(), size, thumbnail_rotation, thumbnail_zoom, thumbnail_offset,
			thumbnail_auto_align]


## Lo que tiene que ser igual en el host y en los clientes (SimFingerprint).
func fingerprint_text() -> String:
	var parts := PackedStringArray([String(id), str(size), str(can_rotate), str(stackable), str(stack_limit()),
			var_to_str(default_state)])
	for ability in abilities:
		parts.append(ability.fingerprint_text() if ability != null else "null")
	return " ".join(parts)
