class_name InvLoadout
extends RefCounted

## Lo que es de un jugador además de su grilla: la barra rápida, lo que tiene
## equipado y la vitalidad de prueba. La barra guarda ids de objetos de la
## grilla, no copias: el objeto sigue ocupando su lugar. En el host vale; al
## dueño le llega una copia (InvReplica).
##
## La vitalidad de prueba es un contador para comprobar que los consumibles
## pasan por el host. No es un sistema de salud: no baja sola ni hace nada más.

const HOTBAR_SLOTS := 10
const TEST_VITALITY_MAX := 100
const TEST_VITALITY_START := 40

## Un id por acceso (teclas 1 a 9 y 0), o 0 si está vacío.
var hotbar: Array[int] = []
var equipped_uid := 0
var test_vitality := TEST_VITALITY_START
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
	return [revision, hotbar.duplicate(), equipped_uid, test_vitality]


static func from_snapshot(data: Variant) -> InvLoadout:
	if not data is Array or data.size() != 4 or typeof(data[0]) != TYPE_INT or not data[1] is Array \
			or data[1].size() != HOTBAR_SLOTS or typeof(data[2]) != TYPE_INT or typeof(data[3]) != TYPE_INT:
		return null
	var loadout := InvLoadout.new()
	loadout.revision = data[0]
	for i in HOTBAR_SLOTS:
		if typeof(data[1][i]) != TYPE_INT:
			return null
		loadout.hotbar[i] = data[1][i]
	loadout.equipped_uid = data[2]
	loadout.test_vitality = data[3]
	return loadout
