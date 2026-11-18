extends SceneTree
## End-to-end flow test: main-menu configuration -> waiting lobby -> AI-filled
## match -> 5-second AI war -> leave match -> leave lobby.
## Run: godot --headless --path . --script res://tests/lobby_flow_test.gd

var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	_check(String(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/main_menu.tscn", "main entry scene is the Main Menu")
	_check(load("res://scenes/main_menu.tscn") != null, "Main Menu scene loads")
	_check(load("res://scenes/lobby.tscn") != null, "Waiting Lobby scene loads")
	var missing_descriptions: int = 0
	for servant: ServantData in Roster.get_servants():
		if servant.skill_1_desc.is_empty() or servant.skill_2_desc.is_empty() or servant.noble_phantasm_desc.is_empty() or servant.np_desc.is_empty() or servant.passive_desc.is_empty():
			missing_descriptions += 1
	for master: MasterData in Roster.get_masters():
		if master.skill_1_desc.is_empty() or master.skill_2_desc.is_empty() or master.np_desc.is_empty() or master.passive_desc.is_empty() or master.signature_command_spell_desc.is_empty() or master.trump_card_desc.is_empty():
			missing_descriptions += 1
	_check(missing_descriptions == 0, "all 30 Servants and 15 Masters have structured tooltip descriptions")
	for zero_servant_id: String in ["diarmuid_ua_duibhne", "iskandar", "gilles_de_rais", "hassan_hundred_personas", "lancelot"]:
		_check(Roster.find_servant(zero_servant_id) != null, "Fate/Zero Servant '%s' exists" % zero_servant_id)
	for zero_master_id: String in ["tokiomi_tohsaka", "kayneth_el_melloi", "waver_velvet", "ryuunosuke_uryuu", "kariya_matou"]:
		_check(Roster.find_master(zero_master_id) != null, "Fate/Zero Master '%s' exists" % zero_master_id)
	var iskandar: ServantData = Roster.find_servant("iskandar")
	var lancelot: ServantData = Roster.find_servant("lancelot")
	var diarmuid: ServantData = Roster.find_servant("diarmuid_ua_duibhne")
	var gilles: ServantData = Roster.find_servant("gilles_de_rais")
	_check(iskandar != null and iskandar.reality_marble_auto_barrage, "Iskandar has a phalanx Reality Marble behavior")
	_check(lancelot != null and lancelot.projectile_appropriation and lancelot.identity_mask, "Lancelot appropriates projectiles and masks identity")
	_check(diarmuid != null and diarmuid.strips_buffs_on_np and diarmuid.anti_heal_duration > 0.0, "Diarmuid strips buffs and anti-heals")
	_check(gilles != null and gilles.skill_1_cost == 0.0, "Gilles has zero-Mana Sea Demon summons")
	var signature_names: Dictionary = {}
	var trump_names: Dictionary = {}
	for master: MasterData in Roster.get_masters():
		signature_names[master.signature_command_spell] = true
		trump_names[master.master_trump_card] = true
	_check(signature_names.size() == 15, "all 15 Masters have unique Signature Command Spells")
	_check(trump_names.size() == 15, "all 15 Masters have unique Master Trump Cards")

	var director: Node = root.get_node_or_null("MatchDirector")
	var network: Node = root.get_node_or_null("NetworkManager")
	_check(director != null, "MatchDirector autoload is present")
	_check(network != null, "NetworkManager autoload is present")
	if director == null or network == null:
		_finish()
		return

	var host_error: Error = director.call("host_match", false, 7811)
	_check(host_error == OK, "Host Match starts an ENet server")
	var lobby: Node = await _wait_for_scene("Lobby", 3.0)
	_check(lobby != null, "host is moved to scenes/lobby.tscn before the arena loads")
	if lobby == null:
		_finish()
		return
	_check(not director.get("match_started"), "match is not started while in the Waiting Lobby")
	var lobby_tooltip: Control = lobby.find_child("SkillTooltip", true, false) as Control
	_check(lobby_tooltip != null and lobby_tooltip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "lobby ability tooltip exists and ignores the mouse")

	# Add deterministic melee AI through the same public lobby API used by the UI.
	# Six duos keep the brawl alive for the full observation window even though a
	# completed match now auto-resets the persistent server to the lobby.
	director.call("request_auto_fill", false)
	director.call("request_add_ai", "darnic_yggdmillennia", ServantData.ServantClass.BERSERKER, Roster.RollMode.SPECIFIC)
	director.call("request_add_ai", "illyasviel_von_einzbern", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	director.call("request_add_ai", "kirei_kotomine", ServantData.ServantClass.LANCER, Roster.RollMode.SPECIFIC)
	director.call("request_add_ai", "rin_tohsaka", ServantData.ServantClass.ARCHER, Roster.RollMode.SPECIFIC)
	director.call("request_add_ai", "kayneth_el_melloi", ServantData.ServantClass.CASTER, Roster.RollMode.SPECIFIC)
	director.call("request_add_ai", "kairi_sisigou", ServantData.ServantClass.ASSASSIN, Roster.RollMode.SPECIFIC)
	await process_frame
	var entries: Dictionary = director.get("entries")
	_check(entries.size() == 6, "AI bot requests create synchronized lobby slots")

	director.call("request_start_match")
	var arena: Node = await _wait_for_scene("Arena", 5.0)
	_check(arena != null, "Start War transitions all peers into arena.tscn")
	if arena == null:
		_finish()
		return
	_check(bool(director.get("match_started")), "MatchDirector marks the war as started")
	entries = director.get("entries")
	_check(entries.size() == 6, "all configured AI bots enter the arena")

	await process_frame
	await process_frame
	var arena_tooltip: Control = arena.find_child("SkillTooltip", true, false) as Control
	_check(arena_tooltip != null and arena_tooltip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "in-game ability tooltip exists and ignores the mouse")
	var action_buttons: Dictionary = arena.get("_action_buttons")
	_check(action_buttons.size() == 9, "in-game HUD exposes Servant, Master, NP, Command Spell, Trump, Ask, and Reveal actions")
	var class_badge: Button = arena.get("_class_badge") as Button
	_check(class_badge != null and class_badge.text.begins_with("CLASS:"), "in-game class triangle badge is present")
	var ai_units: Array = []
	for peer_key: Variant in arena.get_lobby_state().keys():
		var entry: Dictionary = arena.get_lobby_state()[peer_key]
		if not bool(entry.get("is_ai", false)):
			continue
		var servant: ServantController = arena.call("_get_servant", int(peer_key)) as ServantController
		if servant != null:
			ai_units.append({"ref": weakref(servant), "health": servant.health, "position": servant.position})
	_check(ai_units.size() == 6, "all AI Servant units are spawned in the arena")

	var damage_seen: bool = false
	var movement_seen: bool = false
	var events: Array[String] = []
	# Sample during the war tick instead of only after it, so an early victory +
	# lobby reset cannot hide the movement that already happened.
	var elapsed: float = 0.0
	while elapsed < 5.0:
		await create_timer(0.25).timeout
		elapsed += 0.25
		if not is_instance_valid(arena) or bool(arena.is_queued_for_deletion()):
			break
		events = arena.call("get_events") as Array[String]
		for tracked: Dictionary in ai_units:
			var tracked_servant: Variant = tracked["ref"].get_ref()
			if tracked_servant == null or not is_instance_valid(tracked_servant):
				damage_seen = true
				continue
			if tracked_servant.health < float(tracked["health"]) - 0.1:
				damage_seen = true
			if tracked_servant.position.distance_to(tracked["position"]) > 10.0:
				movement_seen = true
	_check(movement_seen, "AI Servants change position during the 5-second war tick")
	_check(damage_seen, "AI Servants deal or receive damage during the 5-second war tick")

	if is_instance_valid(arena) and not arena.is_queued_for_deletion():
		events = arena.call("get_events") as Array[String]
	_check(not events.is_empty(), "in-game event ticker captures match activity")

	# Leave the match and return to the main menu.
	director.call("leave_match")
	var menu: Node = await _wait_for_scene("MainMenu", 3.0)
	_check(menu != null, "Leave Match returns to the Main Menu")
	_check(is_equal_approx(Engine.time_scale, 1.0), "leaving resets Engine.time_scale")
	_check((director.get("entries") as Dictionary).is_empty(), "leaving clears the lobby/slot dictionaries")
	_check(not bool(network.get("is_hosting")), "leaving closes the hosted ENet peer")
	_check(get_nodes_in_group("player_units").is_empty(), "leaving removes arena unit nodes")

	# Re-enter a lobby and leave it before starting.
	director.call("host_match", false, 7812)
	var lobby_two: Node = await _wait_for_scene("Lobby", 3.0)
	_check(lobby_two != null, "host can re-enter the Waiting Lobby")
	if lobby_two != null:
		director.call("leave_lobby")
		var menu_two: Node = await _wait_for_scene("MainMenu", 3.0)
		_check(menu_two != null, "Leave Lobby returns to the Main Menu")
		_check((director.get("entries") as Dictionary).is_empty(), "Leave Lobby clears synchronized slots")
		_check(not bool(network.get("is_hosting")), "Leave Lobby closes the ENet peer")
		_check(is_equal_approx(Engine.time_scale, 1.0), "Leave Lobby resets playback speed")

	# Full AI spectator path from the Main Menu: host has no duo, 14 AI slots.
	director.call("host_match", true, 7815)
	var spectator_lobby: Node = await _wait_for_scene("Lobby", 3.0)
	_check(spectator_lobby != null, "Full AI Spectator War opens the Waiting Lobby")
	if spectator_lobby != null:
		director.call("request_mode", MatchConfig.MatchMode.APOCRYPHA_7V7)
		await process_frame
		director.call("request_start_match")
		var spectator_arena: Node = await _wait_for_scene("Arena", 5.0)
		_check(spectator_arena != null, "spectator lobby transitions into the arena")
		await process_frame
		await process_frame
		var spectator_entries: Dictionary = director.get("entries")
		var red_count: int = 0
		var black_count: int = 0
		var neutral_count: int = 0
		var red_classes: Dictionary = {}
		var black_classes: Dictionary = {}
		for key: Variant in spectator_entries.keys():
			var entry: Dictionary = spectator_entries[key]
			if not bool(entry.get("is_ai", false)):
				continue
			var team: int = int(entry.get("team", -1))
			var class_id: int = int(entry.get("class_id", -1))
			if team == MatchConfig.Team.RED:
				red_count += 1
				red_classes[class_id] = true
			elif team == MatchConfig.Team.BLACK:
				black_count += 1
				black_classes[class_id] = true
			elif team == MatchConfig.Team.NEUTRAL:
				neutral_count += 1
		_check(spectator_entries.size() == 15, "spectator mode creates a full 15-slot Apocrypha field")
		_check(red_count == 7 and black_count == 7 and neutral_count == 1, "spectator field is 7 RED / 7 BLACK / 1 Neutral Arbiter")
		_check(red_classes.size() == 7 and black_classes.size() == 7, "Apocrypha AI respects one class per faction")
		_check(spectator_arena.get_local_master() == null and spectator_arena.get_local_servant() == null, "spectator host has no Master/Servant duo")
		director.call("leave_match")
		await _wait_for_scene("MainMenu", 3.0)

	_finish()


func _wait_for_scene(expected_name: String, timeout: float) -> Node:
	var start: int = Time.get_ticks_msec()
	var timeout_msec: int = int(timeout * 1000.0)
	while Time.get_ticks_msec() - start < timeout_msec:
		await process_frame
		if current_scene != null and current_scene.name == expected_name:
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
		print("LOBBY FLOW TEST PASSED")
		quit(0)
	else:
		print("LOBBY FLOW TEST FAILED (%d failure(s))" % _failures)
		quit(1)
