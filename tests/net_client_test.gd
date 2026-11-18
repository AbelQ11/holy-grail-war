extends SceneTree
## Headless client replication test for Milestone 3.
## Start tests/net_server_test.gd first, then:
##   godot --headless --path . --connect=127.0.0.1:7796 --script res://tests/net_client_test.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	var scene: PackedScene = load("res://scenes/arena.tscn") as PackedScene
	var arena: Node2D = scene.instantiate() as Node2D
	root.add_child(arena)

	var waited: float = 0.0
	while waited < 6.0:
		var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
		if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		await create_timer(0.2).timeout
		waited += 0.2

	var peer_after: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if peer_after == null or peer_after.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		print("NET CLIENT TEST FAILED: never connected")
		quit(1)
		return

	var local_id: int = root.multiplayer.get_unique_id()

	# Client uses the server-side Random Summon option.
	arena.request_summon("", -1, Roster.RollMode.RANDOM_PAIR)

	var waited_for_summon: float = 0.0
	var entry: Dictionary = {}
	while waited_for_summon < 5.0:
		entry = arena.get_lobby_state().get(local_id, {})
		if not String(entry.get("servant_id", "")).is_empty():
			break
		await create_timer(0.2).timeout
		waited_for_summon += 0.2

	if entry.is_empty() or String(entry.get("servant_id", "")).is_empty():
		print("NET CLIENT TEST FAILED: Random Summon result was not replicated")
		quit(1)
		return

	var expected_master: String = String(entry.get("master_id", ""))
	var expected_servant: String = String(entry.get("servant_id", ""))
	if Roster.find_master(expected_master) == null or Roster.find_servant(expected_servant) == null:
		print("NET CLIENT TEST FAILED: Random Summon returned unknown resources")
		quit(1)
		return

	arena.request_deploy()

	var waited_for_spawn: float = 0.0
	var local_master: MasterController = null
	var local_servant: ServantController = null
	while waited_for_spawn < 8.0:
		await create_timer(0.2).timeout
		waited_for_spawn += 0.2
		local_master = arena.call("_get_master", local_id) as MasterController
		local_servant = arena.call("_get_servant", local_id) as ServantController
		if local_master != null and local_servant != null:
			break

	if local_master == null or local_servant == null:
		print("NET CLIENT TEST FAILED: randomized Master/Servant duo did not replicate")
		quit(1)
		return
	if local_master.master_data.master_id != expected_master:
		print("NET CLIENT TEST FAILED: replicated Master does not match the rolled result")
		quit(1)
		return
	if local_servant.servant_data.servant_id != expected_servant:
		print("NET CLIENT TEST FAILED: replicated Servant does not match the rolled result")
		quit(1)
		return
	if local_master.command_spells_left != 3:
		print("NET CLIENT TEST FAILED: replicated Master does not have 3 Command Spells")
		quit(1)
		return

	var host_master: MasterController = arena.call("_get_master", 1) as MasterController
	var host_servant: ServantController = arena.call("_get_servant", 1) as ServantController
	if host_master == null or host_servant == null:
		print("NET CLIENT TEST FAILED: specific host duo was not replicated to the late joiner")
		quit(1)
		return
	if host_master.master_data.master_id != "shirou_emiya" or host_servant.servant_data.servant_class != ServantData.ServantClass.SABER:
		print("NET CLIENT TEST FAILED: host class-only summon replicated incorrectly")
		quit(1)
		return

	# Late-join Leyline ownership synchronization.
	var west_leyline: LeylineNode = arena.get_leylines()[0]
	var waited_for_leyline: float = 0.0
	while waited_for_leyline < 5.0:
		if west_leyline.owner_peer_id == 1:
			break
		await create_timer(0.2).timeout
		waited_for_leyline += 0.2
	if west_leyline.owner_peer_id != 1:
		print("NET CLIENT TEST FAILED: late-join Leyline ownership did not replicate")
		quit(1)
		return

	# RTS command RPC: move the locally controlled Servant on the server.
	var start_position: Vector2 = local_servant.position
	local_servant._rpc_command_move.rpc_id(1, start_position + Vector2(120.0, 0.0), false)
	await create_timer(1.0).timeout
	if local_servant.position.distance_to(start_position) < 25.0:
		print("NET CLIENT TEST FAILED: RTS move command was not applied by the server")
		quit(1)
		return

	var lobby: Dictionary = arena.get_lobby_state()
	var host_entry: Dictionary = lobby.get(1, {})
	var local_entry: Dictionary = lobby.get(local_id, {})
	if not bool(local_entry.get("deployed", false)) or not bool(host_entry.get("deployed", false)):
		print("NET CLIENT TEST FAILED: lobby deployment state did not replicate")
		quit(1)
		return

	print("NET CLIENT TEST PASSED: peer %d rolled %s + %s, received both duos, Leyline, and RTS move replication" % [local_id, expected_master, expected_servant])
	await create_timer(0.2).timeout
	quit(0)
