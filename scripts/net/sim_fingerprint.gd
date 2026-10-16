class_name SimFingerprint
extends RefCounted

## Huella de lo que tiene que ser igual en el host y en cada cliente para que
## la simulación dé lo mismo: los valores del Tuning, el código y el nivel. El
## cliente la manda al conectarse; si no coincide, el host no lo deja entrar y
## le dice qué parte es distinta. Sin esto, una copia vieja se conecta igual y
## todo anda raro, con correcciones a cada rato y sin aviso.
##
## Se arma con lo que hay en memoria y no con los archivos de escena, que el
## editor puede volver a guardar con otro formato sin cambiar nada.

enum Part { TUNING, CODE, LEVEL }
## Cómo se nombra cada parte en el aviso.
const PART_NAMES := ["los valores del Tuning", "el código", "el nivel"]
## Bytes por parte: los primeros del SHA-256 de su texto.
const PART_BYTES := 8
## Todo número se redondea a esto antes de entrar en la huella. Las piezas que
## arma el código del nivel usan tangentes y ángulos, y esas cuentas pueden
## diferir en el último decimal entre dos procesadores: sin redondear, dos
## copias iguales podrían dar huellas distintas.
const STEP := 0.0001
const BYTES := PART_BYTES * 3
## Carpetas con el código que simula, viaja por red o arma el nivel.
const CODE_DIRS := ["res://scripts/actor", "res://scripts/net", "res://scenes/net_lab"]


## La huella completa. Para el nivel, el texto de level_text(), tomado antes
## del primer tick: después las plataformas y la balsa ya se movieron.
static func compute(tuning: ActorTuning, level: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(_digest(tuning_text(tuning)))
	out.append_array(_digest(code_text()))
	out.append_array(_digest(level))
	return out


## Los nombres de las partes en que difieren dos huellas; vacío si son iguales.
static func differences(a: PackedByteArray, b: PackedByteArray) -> PackedStringArray:
	var names := PackedStringArray()
	for part in Part.size():
		var from := part * PART_BYTES
		if a.slice(from, from + PART_BYTES) != b.slice(from, from + PART_BYTES):
			names.append(PART_NAMES[part])
	return names


## Cada valor exportado del Tuning, con su nombre.
static func tuning_text(tuning: ActorTuning) -> String:
	return _exports_text(tuning, "")


## El texto de cada script de CODE_DIRS, en orden. En una versión exportada los
## .gd pueden no estar como texto; entonces esa parte queda vacía en todos lados.
static func code_text() -> String:
	var text := ""
	for dir in CODE_DIRS:
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for file in files:
			if file.ends_with(".gd"):
				var path: String = dir.path_join(file)
				text += "%s\n%s\n" % [path, FileAccess.get_file_as_string(path)]
	return text


## Lo que forma el nivel: cada forma de colisión con su lugar en el mundo y
## sus medidas, y los valores exportados y el lugar de cada nodo con script
## (escaleras, cables, plataformas, la balsa, las pistas armadas por código),
## con la curva de cada cable. En el orden del árbol.
static func level_text(level: Node) -> String:
	var text := ""
	var pending: Array[Node] = [level]
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		if node is CollisionShape3D:
			var shape_node := node as CollisionShape3D
			text += "forma %s %s %s\n" % [_value_text(shape_node.global_transform), shape_node.disabled,
					_value_text(shape_node.shape)]
		var script: Script = node.get_script()
		if script != null:
			# Con su ruta en el nivel: el número de cada cable sale de ahí.
			text += "nodo %s %s\n%s" % [level.get_path_to(node), script.resource_path, _exports_text(node, "  ")]
			# Dónde está: un cable o una escalera en otro lugar cambian la simulación.
			if node is Node3D:
				text += "  lugar %s\n" % _value_text((node as Node3D).global_transform)
			# La forma de un cable: su curva.
			if node is Path3D:
				text += "  curva %s\n" % _curve_text((node as Path3D).curve)
		pending.append_array(node.get_children())
	return text


## Una curva: cada cuánto se parte en tramos rectos, y cada punto con sus dos
## manijas.
static func _curve_text(curve: Curve3D) -> String:
	if curve == null:
		return "null"
	var parts := PackedStringArray([_value_text(curve.bake_interval)])
	for i in curve.point_count:
		parts.append("%s %s %s" % [_value_text(curve.get_point_position(i)), _value_text(curve.get_point_in(i)),
				_value_text(curve.get_point_out(i))])
	return "[%s]" % ", ".join(parts)


static func _digest(text: String) -> PackedByteArray:
	return text.sha256_buffer().slice(0, PART_BYTES)


## Las variables guardadas del script de un objeto (o, en un recurso, todas
## las guardadas), una por línea.
static func _exports_text(object: Object, indent: String) -> String:
	var text := ""
	var only_script := not (object is Resource)
	for property in object.get_property_list():
		var usage: int = property["usage"]
		if not usage & PROPERTY_USAGE_STORAGE or (only_script and not usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if property["name"] in ["resource_path", "resource_name", "resource_local_to_scene", "script"]:
			continue
		text += "%s%s=%s\n" % [indent, property["name"], _value_text(object.get(property["name"]))]
	return text


## Un valor como texto, con los números redondeados a STEP. Una forma, con su
## clase y sus medidas; cualquier otro objeto (un material), solo su clase: no
## cambia la simulación.
static func _value_text(value: Variant) -> String:
	match typeof(value):
		TYPE_FLOAT:
			return str(snappedf(value, STEP))
		TYPE_VECTOR2:
			return str(value.snapped(Vector2.ONE * STEP))
		TYPE_VECTOR3:
			return str(value.snapped(Vector3.ONE * STEP))
		TYPE_TRANSFORM3D:
			var t: Transform3D = value
			return "%s %s %s %s" % [_value_text(t.basis.x), _value_text(t.basis.y), _value_text(t.basis.z), _value_text(t.origin)]
		TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_ARRAY:
			var parts := PackedStringArray()
			for item in value:
				parts.append(_value_text(item))
			return "[%s]" % ", ".join(parts)
		TYPE_OBJECT:
			if value is Shape3D:
				return "%s{%s}" % [value.get_class(), _exports_text(value, "").replace("\n", "; ")]
			return value.get_class() if value != null else "null"
	return var_to_str(value)
