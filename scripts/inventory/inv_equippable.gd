class_name InvEquippable
extends InvAbility

## Equipable: se lleva en la mano sin sacarlo de la grilla. Hay uno equipado a
## la vez; equipar otro reemplaza al anterior. Los demás jugadores lo ven en el
## personaje (InvEquipView). Soltarlo, pasarlo a una caja o gastarlo entero lo
## desequipa.

@export_group("En la mano")
## Dónde va, respecto de los pies del personaje y mirando hacia donde mira él.
@export var hold_offset := Vector3(0.38, 1.0, -0.25)
## Giro del modelo en la mano, en grados.
@export var hold_rotation := Vector3.ZERO
## Medida del lado más largo del modelo en la mano, en metros.
@export var hold_size := 0.5


func kind() -> int:
	return Kind.EQUIP


func action_text(loadout: InvLoadout, stack: InvStack) -> String:
	return "Desequipar" if loadout != null and stack != null and loadout.equipped_uid == stack.uid else "Equipar"


func apply(loadout: InvLoadout, stack: InvStack, _vitals: ActorVitals) -> int:
	loadout.equipped_uid = 0 if loadout.equipped_uid == stack.uid else stack.uid
	return 0


func describe() -> String:
	return "Se equipa en la mano: no sale de la grilla y los demás lo ven"


func fingerprint_text() -> String:
	return super()
