class_name InvHandPrefs
extends RefCounted

## Las preferencias de la mano de cada jugador (desde el 2026-11-14): qué
## botones agarran y lanzan, y si se sostiene alternando o manteniendo. Son de
## cada PC, no viajan por red ni entran en la huella. Se cambian en el panel
## Opciones (F3, o el botón del menú del laboratorio).
##
## El laboratorio no tenía dónde guardar preferencias: van en un archivo propio,
## `user://opciones_del_laboratorio.cfg` (en Windows,
## %APPDATA%\Godot\app_userdata\Tun tun tun sahur\opciones_del_laboratorio.cfg),
## sección [mano]. Si no está o tiene algo raro, se usan las de fábrica:
## botones principales y alternar. Borrarlo vuelve a las de fábrica.

enum Buttons { PRIMARY, SIDE }
enum Mode { TOGGLE, HOLD }

const PATH := "user://opciones_del_laboratorio.cfg"
const SECTION := "mano"

## PRIMARY: derecho agarra y suelta, izquierdo lanza. SIDE: el lateral
## trasero (cerca de la palma, MOUSE_BUTTON_XBUTTON1) agarra y suelta, el
## lateral delantero (cerca del cable, MOUSE_BUTTON_XBUTTON2) lanza.
var buttons := Buttons.PRIMARY
## TOGGLE: un clic agarra y otro del mismo botón suelta. HOLD: agarra al
## apretar y suelta al soltar el botón.
var mode := Mode.TOGGLE


## Las acciones del Mapa de entrada que usa cada esquema: [agarrar, lanzar].
func actions() -> Array[StringName]:
	if buttons == Buttons.SIDE:
		return [&"objeto_agarrar_lateral", &"objeto_lanzar_lateral"]
	return [&"objeto_agarrar", &"objeto_lanzar"]


static func load_saved(path := PATH) -> InvHandPrefs:
	var prefs := InvHandPrefs.new()
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return prefs
	var saved_buttons: Variant = file.get_value(SECTION, "botones", "principales")
	var saved_mode: Variant = file.get_value(SECTION, "sostener", "alternar")
	prefs.buttons = Buttons.SIDE if saved_buttons == "laterales" else Buttons.PRIMARY
	prefs.mode = Mode.HOLD if saved_mode == "mantener" else Mode.TOGGLE
	return prefs


func save(path := PATH) -> Error:
	var file := ConfigFile.new()
	file.load(path)
	file.set_value(SECTION, "botones", "laterales" if buttons == Buttons.SIDE else "principales")
	file.set_value(SECTION, "sostener", "mantener" if mode == Mode.HOLD else "alternar")
	return file.save(path)


func describe() -> String:
	return "%s, %s" % ["laterales" if buttons == Buttons.SIDE else "principales",
			"mantener" if mode == Mode.HOLD else "alternar"]
