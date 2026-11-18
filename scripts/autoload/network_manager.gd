extends Node
## Autoload that owns the ENet transport for the Holy Grail War.
##
## The server is authoritative: gameplay simulation runs only on the host and
## clients exchange input intents/requests over RPC. Scene spawning is handled by
## [MultiplayerSpawner] instances owned by the arena.
##
## CLI usage:
##   godot --headless --host --port=7777
##   godot --headless --port=7777          # headless implies --host unless --connect is given
##   godot --connect=192.168.1.20:7777
##   godot --connect=192.168.1.20 --port=7777

signal server_started(port: int)
signal client_connected
signal connection_failed
signal server_disconnected
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const DEFAULT_PORT: int = 7777
const DEFAULT_ADDRESS: String = "127.0.0.1"
const MAX_CLIENTS: int = 8

var is_headless: bool = false
var is_hosting: bool = false
var server_port: int = DEFAULT_PORT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_headless = _detect_headless()
	_connect_multiplayer_signals()
	_configure_from_cli()


## Starts an authoritative ENet server on [param port].
func host_game(port: int = DEFAULT_PORT, max_clients: int = MAX_CLIENTS) -> Error:
	_reset_peer()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, max_clients)
	if err != OK:
		push_error("NetworkManager: failed to host on port %d (error %d)." % [port, err])
		return err

	multiplayer.multiplayer_peer = peer
	server_port = port
	is_hosting = true
	print("[NetworkManager] Hosting on port %d (max %d peers, headless=%s)." % [port, max_clients, str(is_headless)])
	server_started.emit(port)
	return OK


## Connects this process to a server as a client.
func join_game(address: String = DEFAULT_ADDRESS, port: int = DEFAULT_PORT) -> Error:
	_reset_peer()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		push_error("NetworkManager: failed to connect to %s:%d (error %d)." % [address, port, err])
		return err

	multiplayer.multiplayer_peer = peer
	server_port = port
	is_hosting = false
	print("[NetworkManager] Connecting to %s:%d ..." % [address, port])
	return OK


## Closes the active transport and returns to offline (single-process) mode.
func disconnect_from_game() -> void:
	_reset_peer()
	is_hosting = false
	print("[NetworkManager] Disconnected; running offline.")


## Explicit match-flow alias used by the lobby and in-game leave controls.
func disconnect_from_match() -> void:
	disconnect_from_game()


func get_local_id() -> int:
	return multiplayer.get_unique_id()


func get_peer_count() -> int:
	# MultiplayerAPI.get_peers() excludes the local peer.
	return multiplayer.get_peers().size() + 1


func _reset_peer() -> void:
	var current: MultiplayerPeer = multiplayer.multiplayer_peer
	if current != null and not (current is OfflineMultiplayerPeer):
		current.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _detect_headless() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	if OS.has_feature("headless"):
		return true
	var args: PackedStringArray = OS.get_cmdline_args()
	if args.has("--headless"):
		return true
	return OS.get_cmdline_user_args().has("--headless")


func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _configure_from_cli() -> void:
	var cli: Dictionary = _parse_cli()
	var connect_target: String = cli.get("connect", "")
	var port: int = int(cli.get("port", DEFAULT_PORT))

	if not connect_target.is_empty():
		var address: String = connect_target
		if connect_target.contains(":"):
			address = connect_target.get_slice(":", 0)
			port = int(connect_target.get_slice(":", 1))
		join_game(address, port)
	elif is_headless or bool(cli.get("host", false)):
		host_game(port)


func _parse_cli() -> Dictionary:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var parsed: Dictionary = {
		"host": false,
		"connect": "",
		"port": DEFAULT_PORT,
	}
	var index: int = 0
	while index < args.size():
		var arg: String = args[index]
		if arg == "--host" or arg == "--server":
			parsed["host"] = true
		elif arg == "--connect" and index + 1 < args.size():
			index += 1
			parsed["connect"] = args[index]
		elif arg.begins_with("--connect="):
			parsed["connect"] = arg.get_slice("=", 1)
		elif arg == "--port" and index + 1 < args.size():
			index += 1
			parsed["port"] = int(args[index])
		elif arg.begins_with("--port="):
			parsed["port"] = int(arg.get_slice("=", 1))
		index += 1
	return parsed


func _on_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] Peer %d connected." % peer_id)
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] Peer %d disconnected." % peer_id)
	peer_left.emit(peer_id)


func _on_connected_to_server() -> void:
	print("[NetworkManager] Connected as peer %d." % multiplayer.get_unique_id())
	client_connected.emit()


func _on_connection_failed() -> void:
	push_error("NetworkManager: connection failed.")
	_reset_peer()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("[NetworkManager] Server closed the connection.")
	_reset_peer()
	server_disconnected.emit()
