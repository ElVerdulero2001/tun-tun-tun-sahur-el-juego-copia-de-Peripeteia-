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
## (los campos solo se leen para footprint, can_rotate y world_scene).
## Un mismo ItemDefinition lo comparten TODAS las instancias de ese tipo y
## suele estar respaldado por un .tres en disco: mutar id / nombre /
## world_scene / grid_width / grid_height / can_rotate en gameplay dejaria
## geometria, validacion y render inconsistentes con lo ya colocado, para
## todas las instancias a la vez. GDScript 4.6.3 no lo impide (D8); es una
## LIMITACION DELIBERADA sostenida por convencion + tripwire
## (inventory_v1_identity_contract_test).

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
