extends SceneTree
## Verifies that a persistent server returns to an empty Waiting Lobby after a
## match ends and can immediately host a consecutive match without restarting.

var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var director: Node = root.get_node_or_null("MatchDirector")
	_check(director != null, "MatchDirector is present")
	if director == null:
		_finish()
		return

	# --- Match 1: elimination ends the match and resets the lobby ----------
	director.call("host_match", false, 7825)
	var lobby: Node = await _wait_scene("Lobby", 4.0)
	_check(lobby != null, "first Waiting Lobby opens")
	director.call("request_auto_fill", false)
	director.call("request_summon", "shirou_emiya", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	await process_frame
	director.call("request_add_ai", "kirei_kotomine", ServantData.ServantClass.LANCER, Roster.RollMode.SPECIFIC)
	await process_frame
	director.call("request_start_match")

	var arena: Node = await _wait_scene("Arena", 6.0)
	_check(arena != null, "first match enters the arena")
	if arena == null:
		_finish()
		return
	await process_frame
	await process_frame

	var ai_peer: int = 0
	for key: Variant in (arena.call("get_lobby_state") as Dictionary).keys():
		var entry: Dictionary = (arena.call("get_lobby_state") as Dictionary)[key]
		if bool(entry.get("is_ai", false)):
			ai_peer = int(key)
			break
	_check(ai_peer != 0, "match contains an AI opponent")
	if ai_peer != 0:
		var ai_master: MasterController = arena.call("_get_master", ai_peer) as MasterController
		if ai_master != null:
			ai_master.receive_damage(999999.0, 1, -1)

	var back_at_lobby: Node = await _wait_scene("Lobby", 8.0)
	_check(back_at_lobby != null, "match end returns every peer to the Waiting Lobby")
	_check(not bool(director.get("match_started")), "match_started clears after the reset")
	_check(bool(director.get("lobby_active")), "lobby_active is restored after the reset")
	_check((director.get("entries") as Dictionary).is_empty(), "Waiting Lobby is empty after the reset")
	_check(int(director.get("draft_stage")) == 0, "draft stage returns to Master Selection")

	# --- Match 2: same process hosts another match immediately -------------
	director.call("request_fill_ai")
	await process_frame
	await process_frame
	director.call("request_start_match")
	var arena_two: Node = await _wait_scene("Arena", 6.0)
	_check(arena_two != null, "consecutive match starts without restarting the process")
	if arena_two != null:
		await process_frame
		_check((director.get("entries") as Dictionary).size() == 7, "second match fills a fresh FFA field")

	director.call("finish_match_and_reset", "SECOND MATCH COMPLETE")
	var lobby_two: Node = await _wait_scene("Lobby", 6.0)
	_check(lobby_two != null, "second match also resets to the Waiting Lobby")
	_check((director.get("entries") as Dictionary).is_empty(), "lobby is empty after the second reset")

	director.call("leave_match")
	await _wait_scene("MainMenu", 4.0)
	_finish()


func _wait_scene(expected: String, timeout: float) -> Node:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(timeout * 1000.0):
		await process_frame
		if current_scene != null and current_scene.name == expected:
			return current_scene
	return null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		push_error("  FAIL  %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("SERVER RESET TEST PASSED")
		quit(0)
	else:
		print("SERVER RESET TEST FAILED (%d failure(s))" % _failures)
		quit(1)
