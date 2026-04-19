extends Node

var prefabs = {
	1: "res://scenes/props/llave_comun_1.tscn",
	2: "res://scenes/props/botella_standar_1.tscn",
	3: "res://scenes/props/sable_san_martin_1.tscn",
}

func get_prefab(item_id: int) -> PackedScene:
	if not prefabs.has(item_id):
		print("Error: no existe prefab para el ID ", item_id)
		return null
	return load(prefabs[item_id])
