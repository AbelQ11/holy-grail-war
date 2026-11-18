extends SceneTree
## Authoritative lobby server for the pre-match flow network test.
## Run: godot --headless --path . --port=7813 --script res://tests/net_lobby_server.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var director: Node = root.get_node_or_null("MatchDirector")
	if director == null:
		push_error("NET LOBBY SERVER FAILED: MatchDirector missing")
		quit(1)
		return
	director.call("host_match", false, 7813)
	await _wait_scene("Lobby", 3.0)
	director.call("request_add_ai", "kirei_kotomine", ServantData.ServantClass.LANCER, Roster.RollMode.SPECIFIC)
	print("NET LOBBY SERVER READY: waiting for client")
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 10000:
		var entries: Dictionary = director.get("entries")
		var has_client: bool = false
		for key: Variant in entries.keys():
			var entry: Dictionary = entries[key]
			if not bool(entry.get("is_ai", false)) and bool(entry.get("ready", false)):
				has_client = true
		if has_client:
			break
		await create_timer(0.2).timeout
	director.call("request_start_match")
	await _wait_scene("Arena", 5.0)
	var arena: Node = current_scene
	if arena == null:
		push_error("NET LOBBY SERVER FAILED: arena did not load")
		quit(1)
		return
	await create_timer(1.0).timeout
	var entries_final: Dictionary = director.get("entries")
	print("NET LOBBY SERVER STARTED: %d slots" % entries_final.size())
	await create_timer(15.0).timeout
	director.call("leave_match")
	quit(0)


func _wait_scene(expected: String, timeout: float) -> void:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(timeout * 1000.0):
		await process_frame
		if current_scene != null and current_scene.name == expected:
			return
