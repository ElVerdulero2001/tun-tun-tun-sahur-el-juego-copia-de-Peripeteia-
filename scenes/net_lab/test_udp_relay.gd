class_name TestUdpRelay
extends Node

## Solo para pruebas: un relevo UDP en la misma PC, entre el cliente y el host.
## El cliente se conecta al relevo, y el relevo le pasa cada paquete al host y
## cada respuesta al cliente. Con `cut` prendido no pasa nada en ninguna
## dirección: es un cable cortado, y ENet se entera como se enteraría de
## verdad. Cada conexión nueva del cliente (otro puerto) sale hacia el host por
## un puerto nuevo, como pasa al reconectarse.

var cut := false
var forwarded := 0
var dropped := 0
var _server := UDPServer.new()
var _target_address := ""
var _target_port := 0
## Por conexión: [lado del cliente, lado del host].
var _links: Array = []


func _init() -> void:
	# Antes que nada: así un paquete no espera un frame entero para pasar.
	process_priority = -100


func start(listen_port: int, target_address: String, target_port: int) -> Error:
	_target_address = target_address
	_target_port = target_port
	return _server.listen(listen_port, "127.0.0.1")


func _process(_delta: float) -> void:
	_server.poll()
	while _server.is_connection_available():
		var client_side := _server.take_connection()
		var host_side := PacketPeerUDP.new()
		host_side.connect_to_host(_target_address, _target_port)
		_links.append([client_side, host_side])
	for link in _links:
		_pump(link[0], link[1])
		_pump(link[1], link[0])


func _pump(from: PacketPeerUDP, to: PacketPeerUDP) -> void:
	while from.get_available_packet_count() > 0:
		var packet := from.get_packet()
		if cut:
			dropped += 1
		else:
			to.put_packet(packet)
			forwarded += 1
