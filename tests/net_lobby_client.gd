extends SceneTree
## Client half of the two-process lobby-flow test.
## Run: godot --headless --path . --connect=127.0.0.1:7813 --script res://tests/net_lobby_client.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var director: Node = root.get_node_or_null("MatchDirector")
	if director == null:
		push_error("NET LOBBY CLIENT FAILED: MatchDirector missing")
		quit(1)
		return
	director.call("join_match", "127.0.0.1", 7813)
	await _wait_scene("Lobby", 6.0)
	if current_scene == null or current_scene.name != "Lobby":
		print("NET LOBBY CLIENT FAILED: Waiting Lobby did not open")
		quit(1)
		return

	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 6000:
		if (director.get("entries") as Dictionary).size() > 0:
			break
		await create_timer(0.2).timeout

	director.call("request_summon", "shirou_emiya", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	await create_timer(0.4).timeout
	var local_id: int = root.multiplayer.get_unique_id()
	var local_entry: Dictionary = (director.get("entries") as Dictionary).get(local_id, {})
	if local_entry.is_empty():
		print("NET LOBBY CLIENT FAILED: synchronized lobby entry missing")
		quit(1)
		return
	director.call("request_player_ready", true)

	var arena: Node = await _wait_scene("Arena", 10.0)
	if arena == null:
		print("NET LOBBY CLIENT FAILED: arena transition did not arrive")
		quit(1)
		return

	start = Time.get_ticks_msec()
	var local_master: MasterController = null
	var local_servant: ServantController = null
	while Time.get_ticks_msec() - start < 8000:
		local_master = arena.call("_get_master", local_id) as MasterController
		local_servant = arena.call("_get_servant", local_id) as ServantController
		if local_master != null and local_servant != null:
			break
		await create_timer(0.2).timeout
	if local_master == null or local_servant == null:
		print("NET LOBBY CLIENT FAILED: arena units did not replicate")
		quit(1)
		return
	if local_master.master_data.master_id != "shirou_emiya" or local_servant.servant_data.servant_class != ServantData.ServantClass.SABER:
		print("NET LOBBY CLIENT FAILED: class-only loadout did not survive the lobby transition")
		quit(1)
		return
	var final_entries: Dictionary = director.get("entries")
	if final_entries.size() != 7:
		print("NET LOBBY CLIENT FAILED: expected 7 filled slots, got %d" % final_entries.size())
		quit(1)
		return

	print("NET LOBBY CLIENT PASSED: synchronized lobby reached 7 slots and entered arena with selected duo")
	await create_timer(0.2).timeout
	quit(0)


func _wait_scene(expected: String, timeout: float) -> Node:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(timeout * 1000.0):
		await process_frame
		if current_scene != null and current_scene.name == expected:
			return current_scene
	return null
