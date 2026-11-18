extends SceneTree
## Headless Milestone 4 AI/spectator regression test.
## Run: godot --headless --path . --script res://tests/ai_smoke_test.gd

var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	await _test_ai_slot_management()
	await _test_ai_auto_fill_and_activity()
	await _test_takeover_reclaim()
	await _test_ffa_spectator()
	await _test_apocrypha_spectator()
	await _test_auto_fill_toggle_off()
	_finish()


func _test_ai_slot_management() -> void:
	var arena: Node2D = await _make_arena()
	var ai_id: int = int(arena.call("_server_add_ai", "rin_tohsaka", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC))
	await process_frame
	await process_frame
	_check(ai_id >= 1_000_000, "specific AI bot receives a synthetic slot id")
	var entry: Dictionary = arena.get_lobby_state().get(ai_id, {})
	_check(bool(entry.get("is_ai", false)), "specific AI entry is marked as AI")
	_check(String(entry.get("master_id", "")) == "rin_tohsaka", "specific AI keeps the selected Master")
	_check(int(entry.get("class_id", -1)) == ServantData.ServantClass.SABER, "specific AI keeps the selected class")
	_check(Roster.find_servant(String(entry.get("servant_id", ""))) != null, "specific AI receives a secretly rolled Servant")
	_check(arena.call("_get_master", ai_id) != null, "AI Master unit spawns")
	_check(arena.call("_get_servant", ai_id) != null, "AI Servant unit spawns")
	_check(bool(arena.call("has_ai_commander", ai_id)), "AI commander attaches to the AI slot")

	arena.call("_server_remove_ai")
	await process_frame
	await process_frame
	_check(arena.get_lobby_state().get(ai_id, {}).is_empty(), "Remove AI removes the lobby slot")
	_check(arena.call("_get_master", ai_id) == null and arena.call("_get_servant", ai_id) == null, "Remove AI despawns the duo")
	_check(not bool(arena.call("has_ai_commander", ai_id)), "Remove AI detaches the commander")

	arena.call("_server_fill_ai")
	await process_frame
	await process_frame
	_check(int(arena.call("get_ai_slot_count")) == 7, "Fill Remaining Slots creates a full 7-slot FFA field")
	_check(arena.call("_deployed_pair_count") == 7, "All filled AI slots are deployed")
	await _drop_arena(arena)


func _test_ai_auto_fill_and_activity() -> void:
	var arena: Node2D = await _make_arena()
	arena.request_summon("shirou_emiya", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	await process_frame
	arena.request_deploy()
	await process_frame
	await process_frame

	arena.call("_server_start_match")
	await process_frame
	await process_frame
	_check(bool(arena.call("is_match_started")), "host can start the match")
	_check(int(arena.call("_deployed_pair_count")) == 7, "auto-fill reaches all 7 FFA slots")
	_check(int(arena.call("get_ai_slot_count")) == 6, "auto-fill adds AI to the six empty slots")

	var events: Array[String] = arena.call("get_events")
	var has_start_event: bool = false
	for event: String in events:
		if event.contains("MATCH STARTED"):
			has_start_event = true
	_check(has_start_event, "match start is written to the event ticker")

	var ai_masters: Array[MasterController] = []
	var ai_servants: Array[ServantController] = []
	for peer_key: Variant in arena.get_lobby_state().keys():
		var entry: Dictionary = arena.get_lobby_state()[peer_key]
		if not bool(entry.get("is_ai", false)):
			continue
		var ai_master: MasterController = arena.call("_get_master", int(peer_key)) as MasterController
		var ai_servant: ServantController = arena.call("_get_servant", int(peer_key)) as ServantController
		if ai_master != null and ai_servant != null:
			ai_masters.append(ai_master)
			ai_servants.append(ai_servant)
	_check(ai_masters.size() >= 4, "multiple AI duos are present in the war")

	var tracked_units: Array = []
	for ai_master: MasterController in ai_masters:
		tracked_units.append({"ref": weakref(ai_master), "position": ai_master.position})
	for ai_servant: ServantController in ai_servants:
		tracked_units.append({"ref": weakref(ai_servant), "position": ai_servant.position})
	await create_timer(1.3).timeout
	var moved: bool = false
	for tracked: Dictionary in tracked_units:
		var unit: Variant = tracked["ref"].get_ref()
		if unit != null and is_instance_valid(unit) and unit.position.distance_to(tracked["position"]) > 4.0:
			moved = true
			break
	_check(moved, "AI commanders issue live RTS movement intents")

	# Command Spell emergency: damage an AI Master that is still alive.
	var target_master: MasterController = null
	for peer_key: Variant in arena.get_lobby_state().keys():
		var lobby_entry: Dictionary = arena.get_lobby_state()[peer_key]
		if not bool(lobby_entry.get("is_ai", false)):
			continue
		var candidate: MasterController = arena.call("_get_master", int(peer_key)) as MasterController
		if candidate != null and candidate.is_alive:
			target_master = candidate
			break
	if target_master == null:
		_check(false, "an AI Master survived long enough for Command Spell testing")
	else:
		var charges_before: int = target_master.command_spells_left
		await create_timer(0.6).timeout
		if is_instance_valid(target_master):
			target_master.receive_damage(5.0, 1, -1)
		await create_timer(1.2).timeout
		var event_has_command_spell: bool = false
		for event: String in arena.call("get_events") as Array[String]:
			if event.contains("COMMAND SPELL"):
				event_has_command_spell = true
		var charges_after: int = target_master.command_spells_left if is_instance_valid(target_master) else 0
		_check(charges_after < charges_before or event_has_command_spell, "AI burns a Command Spell when its Master is damaged")

	await _drop_arena(arena)


func _test_takeover_reclaim() -> void:
	var arena: Node2D = await _make_arena()
	arena.call("_server_set_auto_fill", false)
	arena.request_summon("shirou_emiya", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	await process_frame
	arena.request_deploy()
	arena.call("_server_summon", 2, "rin_tohsaka", ServantData.ServantClass.ARCHER, Roster.RollMode.SPECIFIC)
	arena.call("_server_deploy", 2)
	await process_frame
	await process_frame
	arena.call("_server_start_match")
	await process_frame
	await process_frame

	var session_id: String = String(arena.call("get_session_id", 2))
	_check(not session_id.is_empty(), "human peer has a reconnect session id")
	var human_master: MasterController = arena.call("_get_master", 2) as MasterController
	var human_servant: ServantController = arena.call("_get_servant", 2) as ServantController
	_check(human_master != null and human_servant != null, "human duo exists before disconnect")
	if human_master == null or human_servant == null:
		await _drop_arena(arena)
		return

	var hp_before: float = human_master.health
	var mana_before: float = human_master.mana
	var cs_before: int = human_master.command_spells_left
	var pos_before: Vector2 = human_servant.position
	var reveal_before: bool = human_servant.is_true_name_revealed
	arena.call("_on_peer_left", 2)
	var entry_after: Dictionary = arena.get_lobby_state().get(2, {})
	_check(bool(entry_after.get("ai_takeover", false)), "disconnect marks the pair as AI takeover")
	_check(arena.call("_get_master", 2) != null and arena.call("_get_servant", 2) != null, "disconnect preserves the disconnected duo")
	_check(bool(arena.call("has_ai_commander", 2)), "disconnect attaches an AI commander")
	_check(is_equal_approx(human_master.health, hp_before) and is_equal_approx(human_master.mana, mana_before), "takeover preserves Master HP and Mana")
	_check(human_master.command_spells_left == cs_before, "takeover preserves Command Spell charges")
	_check(human_servant.position.distance_to(pos_before) < 1.0, "takeover preserves unit position")
	_check(human_servant.is_true_name_revealed == reveal_before, "takeover preserves true-name reveal state")
	var has_takeover_event: bool = false
	for event: String in arena.call("get_events") as Array[String]:
		if event.contains("Autopilot (AI Takeover)"):
			has_takeover_event = true
	_check(has_takeover_event, "takeover notification is broadcast to the event ticker")

	await create_timer(0.8).timeout
	if not is_instance_valid(human_master) or not is_instance_valid(human_servant):
		_check(false, "takeover duo survived until reconnect")
		await _drop_arena(arena)
		return
	arena.call("_server_reclaim_session", 20, session_id)
	await process_frame
	await process_frame
	_check(arena.get_lobby_state().get(2, {}).is_empty(), "reconnect removes the old session slot")
	_check(not arena.get_lobby_state().get(20, {}).is_empty(), "reconnect creates a session slot for the new peer")
	_check(not bool(arena.call("has_ai_commander", 2)), "reconnect detaches the takeover commander")
	var reclaimed_master: MasterController = arena.call("_get_master", 20) as MasterController
	var reclaimed_servant: ServantController = arena.call("_get_servant", 20) as ServantController
	_check(reclaimed_master != null and reclaimed_servant != null, "reclaimed units resolve by new owner id")
	_check(reclaimed_master != null and reclaimed_master.owner_id == 20, "Master ownership transfers to the reconnecting peer")
	_check(reclaimed_servant != null and reclaimed_servant.owner_id == 20, "Servant ownership transfers to the reconnecting peer")
	_check(String(arena.call("get_session_id", 20)) == session_id, "reconnect session id is remapped to the new peer")
	var reclaimed_state: MatchState = arena.get_match_state()
	_check(reclaimed_state.get_team(20) == 20, "reconnect transfers the FFA team identity")
	_check(not reclaimed_state.teams.has(2), "old peer team identity is removed")
	await _drop_arena(arena)


func _test_ffa_spectator() -> void:
	var arena: Node2D = await _make_arena()
	arena.call("_server_set_spectator_mode", true)
	_check(bool(arena.call("is_spectator_mode")), "FFA spectator mode can be enabled")
	arena.call("_server_start_match")
	await process_frame
	await process_frame
	_check(bool(arena.call("is_match_started")), "FFA spectator match starts")
	_check(int(arena.call("get_ai_slot_count")) == 7, "spectator mode fills all 7 FFA slots with AI")
	_check(int(arena.call("_deployed_pair_count")) == 7, "all seven FFA AI duos are deployed")
	_check(arena.call("get_local_master") == null and arena.call("get_local_servant") == null, "spectator host has no duo")
	var overlay: CanvasLayer = arena.get_node_or_null("ClassSelectOverlay") as CanvasLayer
	var spectator_panel: Control = arena.get("_spectator_panel") as Control
	_check(overlay != null and not overlay.visible, "spectator lobby overlay is hidden")
	_check(spectator_panel != null and spectator_panel.visible, "spectator controls are visible")

	var initial_fog: bool = bool(arena.get("_omniscient_view"))
	arena.call("_toggle_spectator_fog")
	_check(bool(arena.get("_omniscient_view")) != initial_fog, "spectator fog/omniscient toggle changes the view mode")
	arena.call("_toggle_spectator_fog")
	arena.call("_set_playback_speed", 4.0)
	_check(is_equal_approx(Engine.time_scale, 4.0), "spectator playback speed sets Engine.time_scale")
	arena.call("_set_playback_speed", 1.0)

	var spectator_units: Array = arena.call("_all_player_units")
	_check(spectator_units.size() >= 10, "spectator field contains AI units")
	var spectator_tracked: Array = []
	for unit: Node2D in spectator_units:
		spectator_tracked.append({"ref": weakref(unit), "position": unit.position})
	await create_timer(1.2).timeout
	var spectator_moved: bool = false
	for tracked: Dictionary in spectator_tracked:
		var unit: Variant = tracked["ref"].get_ref()
		if unit != null and is_instance_valid(unit) and unit.position.distance_to(tracked["position"]) > 2.0:
			spectator_moved = true
			break
	_check(spectator_moved, "spectator AI war continues simulating")
	await _drop_arena(arena)


func _test_apocrypha_spectator() -> void:
	var arena: Node2D = await _make_arena()
	arena.call("_server_set_match_mode", MatchConfig.MatchMode.APOCRYPHA_7V7)
	arena.call("_server_set_spectator_mode", true)
	arena.call("_server_start_match")
	await process_frame
	await process_frame
	_check(int(arena.call("get_ai_slot_count")) == 15, "Apocrypha spectator fills all 15 slots with AI")
	var team_counts: Dictionary = {MatchConfig.Team.RED: 0, MatchConfig.Team.BLACK: 0, MatchConfig.Team.NEUTRAL: 0}
	var team_classes: Dictionary = {MatchConfig.Team.RED: [], MatchConfig.Team.BLACK: [], MatchConfig.Team.NEUTRAL: []}
	for peer_key: Variant in arena.get_lobby_state().keys():
		var entry: Dictionary = arena.get_lobby_state()[peer_key]
		if not bool(entry.get("is_ai", false)):
			continue
		var team: int = int(entry.get("team", -1))
		if team_counts.has(team):
			team_counts[team] = int(team_counts[team]) + 1
			var class_list: Array = team_classes[team]
			class_list.append(int(entry.get("class_id", -1)))
			team_classes[team] = class_list
	_check(int(team_counts[MatchConfig.Team.RED]) == 7, "Apocrypha spectator has seven RED AI pairs")
	_check(int(team_counts[MatchConfig.Team.BLACK]) == 7, "Apocrypha spectator has seven BLACK AI pairs")
	_check(int(team_counts[MatchConfig.Team.NEUTRAL]) == 1, "Apocrypha spectator has one Neutral Ruler Arbiter")
	_check((team_classes[MatchConfig.Team.NEUTRAL] as Array).has(ServantData.ServantClass.RULER), "Neutral Arbiter is locked to the Ruler class")
	for team: int in [MatchConfig.Team.RED, MatchConfig.Team.BLACK]:
		var classes: Array = team_classes[team]
		var unique: Dictionary = {}
		for class_id: int in classes:
			unique[class_id] = true
		_check(classes.size() == 7 and unique.size() == 7, "%s has one AI per standard class" % MatchConfig.team_name(team))
	_check(int(arena.call("_ai_entry_count")) == 15, "15 AI commanders are registered")
	await _drop_arena(arena)


func _test_auto_fill_toggle_off() -> void:
	var arena: Node2D = await _make_arena()
	arena.request_summon("shirou_emiya", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	await process_frame
	arena.request_deploy()
	arena.call("_server_set_auto_fill", false)
	arena.call("_server_start_match")
	await process_frame
	_check(int(arena.call("get_ai_slot_count")) == 0, "auto-fill toggle off leaves empty slots as empty")
	_check(int(arena.call("_deployed_pair_count")) == 1, "only the human duo is deployed with auto-fill off")
	await _drop_arena(arena)


func _make_arena() -> Node2D:
	var scene: PackedScene = load("res://scenes/arena.tscn") as PackedScene
	var arena: Node2D = scene.instantiate() as Node2D
	root.add_child(arena)
	await process_frame
	await process_frame
	return arena


func _drop_arena(arena: Node2D) -> void:
	arena.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		push_error("  FAIL  %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("MILESTONE 4 AI SMOKE TEST PASSED")
		quit(0)
	else:
		print("MILESTONE 4 AI SMOKE TEST FAILED (%d failure(s))" % _failures)
		quit(1)
