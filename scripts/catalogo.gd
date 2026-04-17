extends Node

var prefabs = {
	"botella": "res://scenes/props/botella_standar_1.tscn",
	"sable": "res://scenes/props/sable_san_martin_1.tscn",
	"llave": "res://scenes/props/llave_comun_1.tscn",
}

func get_prefab(tipo: String) -> PackedScene:
	if not prefabs.has(tipo):
		return null
	return load(prefabs[tipo])
