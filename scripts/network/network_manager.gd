extends Node

# NetworkManager — autoload singleton.
#
# Handles multiplayer setup for three modes:
#   OFFLINE   — single player, no network, OfflineMultiplayerPeer
#   HOST      — this instance is the server + a local player
#   CLIENT    — this instance connects to a remote host
#
# All gameplay code should use RPCs and MultiplayerSynchronizer rather than
# calling NetworkManager directly. NetworkManager only handles connection setup.

signal server_started
signal client_connected
signal connection_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

enum Mode { OFFLINE, HOST, CLIENT }

const DEFAULT_PORT := 7777
const MAX_PEERS    := 16

var mode: Mode = Mode.OFFLINE
var local_peer_id: int = 1  # 1 = server authority in Godot multiplayer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


# --- Public API ---

func start_offline() -> void:
	var peer := OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	mode = Mode.OFFLINE
	local_peer_id = 1
	server_started.emit()


func start_host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		connection_failed.emit("Failed to start server on port %d (error %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	local_peer_id = 1
	server_started.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("Failed to connect to %s:%d (error %d)" % [address, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return OK


func disconnect_from_session() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE


func is_server() -> bool:
	return multiplayer.is_server()


func is_offline() -> bool:
	return mode == Mode.OFFLINE


func get_peer_id() -> int:
	return multiplayer.get_unique_id()


# --- Callbacks ---

func _on_peer_connected(id: int) -> void:
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	client_connected.emit()


func _on_connection_failed() -> void:
	connection_failed.emit("Connection to server failed.")
