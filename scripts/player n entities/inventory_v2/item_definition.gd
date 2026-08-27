class_name ItemDefinition
extends Resource

## Describe QUE tipo de objeto es. Informacion compartida entre todas las
## instancias de este tipo; inmutable durante la partida (INV-02, doc V0
## seccion 3.1).
##
## No confundir con ItemInstance: esto es "AK-74" en abstracto, no
## "esta copia concreta con 17 balas".

## Identificador estable del tipo de item. Unico por ItemDefinition.
@export var id: StringName = &""

## Nombre visible, solo para logs/debug en V0 (no hay UI final todavia).
@export var nombre: String = ""

## Escena a instanciar en el mundo cuando este item se devuelve al mundo.
@export var world_scene: PackedScene

## Huella en la grilla del inventario, orientacion normal (sin rotar).
@export var grid_width: int = 1
@export var grid_height: int = 1

## Si la instancia puede rotar 90 grados dentro del inventario (INV-04).
@export var can_rotate: bool = true
