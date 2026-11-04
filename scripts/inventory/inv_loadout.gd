class_name InvLoadout
extends RefCounted

## Lo que es de un jugador además de su grilla: la barra rápida y lo que tiene
## equipado. La barra guarda ids de objetos de la grilla, no copias: el objeto
## sigue ocupando su lugar. En el host vale; al dueño le llega una copia
## (InvReplica).
##
## Hasta el 2026-11-01 también tenía la vitalidad de prueba, un contador que
## subían los consumibles. Se sacó: los consumibles cambian la salud y la
## estamina del personaje (ActorState, ActorVitals), así no hay dos números que
## parezcan la salud.

const HOTBAR_SLOTS := 10

## Un id por acceso (teclas 1 a 9 y 0), o 0 si está vacío.
var hotbar: Array[int] = []
var equipped_uid := 0
## Sube con cada cambio, como la de la grilla.
var revision := 0


func _init() -> void:
	hotbar.resize(HOTBAR_SLOTS)
	hotbar.fill(0)


## El acceso que guarda ese objeto, o -1.
func slot_of(uid: int) -> int:
	return hotbar.find(uid) if uid != 0 else -1


## Saca de la barra y del equipo lo que ya no está en la grilla: se soltó, se
## pasó a otro inventario, se gastó o se juntó con otra pila. No busca otro del
## mismo tipo para reemplazarlo. Devuelve si cambió algo.
func forget_missing(grid: InvGrid) -> bool:
	var changed := false
	for i in HOTBAR_SLOTS:
		if hotbar[i] != 0 and not grid.has(hotbar[i]):
			hotbar[i] = 0
			changed = true
	if equipped_uid != 0 and not grid.has(equipped_uid):
		equipped_uid = 0
		changed = true
	return changed


func snapshot() -> Array:
	return [revision, hotbar.duplicate(), equipped_uid]


static func from_snapshot(data: Variant) -> InvLoadout:
	if not data is Array or data.size() != 3 or typeof(data[0]) != TYPE_INT or not data[1] is Array \
			or data[1].size() != HOTBAR_SLOTS or typeof(data[2]) != TYPE_INT:
		return null
	var loadout := InvLoadout.new()
	loadout.revision = data[0]
	for i in HOTBAR_SLOTS:
		if typeof(data[1][i]) != TYPE_INT:
			return null
		loadout.hotbar[i] = data[1][i]
	loadout.equipped_uid = data[2]
	return loadout
