class_name ItemDefinition
extends Resource

## Describe QUE tipo de objeto es. Informacion compartida entre todas las
## instancias de este tipo; inmutable durante la partida (INV-02;
## docs/inventory_system_v0_v1.md seccion 4).
##
## No confundir con ItemInstance: esto es "AK-74" en abstracto, no
## "esta copia concreta con 17 balas".
##
## ── RUNTIME-INMUTABLE (INV-02 / D8; docs seccion 17) ──
## Despues de cargarse del .tres (o construirse), NINGUN campo se escribe en
## runtime. Auditoria de Batch B.2: 0 sitios de mutacion runtime en el repo
## (los campos solo se leen para footprint, can_rotate y la escena mundial).
## Un mismo ItemDefinition lo comparten TODAS las instancias de ese tipo y
## suele estar respaldado por un .tres en disco: mutar id / nombre /
## world_scene_path / grid_width / grid_height / can_rotate en gameplay dejaria
## geometria, validacion y render inconsistentes con lo ya colocado, para
## todas las instancias a la vez. GDScript 4.6.3 no lo impide (D8); es una
## LIMITACION DELIBERADA sostenida por convencion + tripwire
## (inventory_v1_identity_contract_test).

## Identificador estable del tipo de item. Unico por ItemDefinition.
@export var id: StringName = &""

## Nombre visible, solo para logs/debug en V0 (no hay UI final todavia).
@export var nombre: String = ""

## ── REPRESENTACION MUNDIAL DEL TIPO ──
## `world_scene_path` es la UNICA fuente de verdad: el res:// de la escena a
## instanciar cuando un item de este tipo vuelve al mundo (INVENTARIO -> MUNDO).
##
## Es un PATH (String), NO un `@export var world_scene: PackedScene`, A PROPOSITO.
## Un prop real referencia su ItemDefinition de forma tipada:
##     botella_standar_1.tscn  --@export definition-->  botella.tres
## Si `botella.tres` tuviera `@export var world_scene: PackedScene` apuntando de
## vuelta a `botella_standar_1.tscn`, se forma un ciclo DURO de recursos que el
## parser de texto de Godot NO resuelve en carga fria:
##     Parse Error: [ext_resource] referenced non-existent resource
## Guardar el path como String rompe esa arista de dependencia del parser (el
## ciclo SEMANTICO escena<->definicion sigue existiendo, y esta bien). La
## PackedScene se resuelve LAZY, en runtime, cuando ya no hay ciclo.
## NO volver a convertir esto en `@export var world_scene: PackedScene`.
@export_file("*.tscn") var world_scene_path: String = ""

## Alias de SOLO LECTURA sobre world_scene_path, para compatibilidad con arneses
## de test que instancian su WorldItemV2 leyendo `definition.world_scene`.
## NO almacena estado, NO tiene setter -> nadie puede desincronizarlo de
## world_scene_path. API CANONICA para codigo nuevo/de produccion:
## `get_world_scene()`.
var world_scene: PackedScene:
	get:
		return get_world_scene()

## Resuelve LAZY la PackedScene de la representacion mundial de este tipo.
## Devuelve una PackedScene valida, o null si world_scene_path esta vacio o no
## resuelve. NO instancia nada, NO conoce InventoryV2 / TransferOperation /
## Player / autoridad, NO muta estado runtime. Confia en el cache interno de
## ResourceLoader (no cachea en un campo propio).
func get_world_scene() -> PackedScene:
	if world_scene_path.is_empty():
		return null
	return load(world_scene_path) as PackedScene

## Huella en la grilla del inventario, orientacion normal (sin rotar).
@export var grid_width: int = 1
@export var grid_height: int = 1

## Si la instancia puede rotar 90 grados dentro del inventario (INV-04).
@export var can_rotate: bool = true
