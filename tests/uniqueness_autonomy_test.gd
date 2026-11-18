extends SceneTree
## Headless test for Master/Class uniqueness, class-only summoning, servant
## autonomy, Ask Name, public reveal, signature Command Spells, Trump Cards, and
## the 15-slot Apocrypha draft.
## Run: godot --headless --path . --script res://tests/uniqueness_autonomy_test.gd

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

	# --- FFA Master and Class uniqueness -----------------------------------
	director.call("host_match", false, 7820)
	var lobby: Node = await _wait_scene("Lobby", 3.0)
	_check(lobby != null, "FFA lobby opens")
	if lobby == null:
		_finish()
		return
	director.call("request_summon", "shirou_emiya", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	await process_frame
	var entries: Dictionary = director.get("entries")
	_check(String(entries.get(1, {}).get("master_id", "")) == "shirou_emiya", "host claims Shirou Emiya")
	_check(int(entries.get(1, {}).get("class_id", -1)) == ServantData.ServantClass.SABER, "host claims the Saber class")

	director.call("_server_summon", 2, "shirou_emiya", ServantData.ServantClass.ARCHER, Roster.RollMode.SPECIFIC)
	await process_frame
	_check(not (director.get("entries") as Dictionary).has(2), "server rejects a globally duplicate Master")
	director.call("_server_summon", 2, "rin_tohsaka", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	await process_frame
	_check(not (director.get("entries") as Dictionary).has(2), "server rejects a globally duplicate FFA class")
	director.call("_server_summon", 2, "rin_tohsaka", ServantData.ServantClass.ARCHER, Roster.RollMode.SPECIFIC)
	await process_frame
	_check(bool((director.get("entries") as Dictionary).has(2)), "different Master and class are accepted")
	director.call("_server_summon", 3, "", -1, Roster.RollMode.RANDOM_PAIR)
	await process_frame
	var random_entry: Dictionary = (director.get("entries") as Dictionary).get(3, {})
	_check(not random_entry.is_empty(), "Random Summon creates a slot")
	_check(String(random_entry.get("master_id", "")) not in ["shirou_emiya", "rin_tohsaka"], "Random Master roll excludes claimed Masters")
	_check(int(random_entry.get("class_id", -1)) not in [ServantData.ServantClass.SABER, ServantData.ServantClass.ARCHER], "Random Class roll excludes claimed classes")
	director.call("_on_peer_disconnected", 2)
	director.call("_on_peer_disconnected", 3)
	await process_frame
	director.call("request_auto_fill", false)
	director.call("request_start_match")
	var arena: Node = await _wait_scene("Arena", 5.0)
	_check(arena != null, "class-only FFA match enters the arena")
	if arena == null:
		_finish()
		return
	await process_frame
	await process_frame
	var servant: ServantController = arena.get_local_servant()
	var master: MasterController = arena.get_local_master()
	_check(servant != null and master != null, "rolled Servant and Master spawn")
	if servant == null or master == null:
		_finish()
		return
	_check(servant.servant_data.servant_class == ServantData.ServantClass.SABER, "server secretly rolls a Servant matching the chosen class")
	_check(not servant.is_name_known_to_master, "true name starts unknown to the Master")
	_check(servant.get_display_name_for(1).begins_with("Unknown [Saber]"), "own HUD masks the unknown Servant")
	var commanders: Dictionary = arena.get("_ai_commanders")
	_check(commanders.has(1), "autonomous servant receives an AICommander")
	var commander: AICommander = commanders.get(1, null) as AICommander
	_check(commander != null and not commander.control_master and commander.control_servant, "autonomy AI controls the Servant but not the Master")
	var action_buttons: Dictionary = arena.get("_action_buttons")
	_check(action_buttons["servant_1"].disabled, "servant skill buttons are sealed before name discovery")

	# Freeze autonomy to prove manual commands are rejected until Ask Name.
	if commander != null:
		commander.control_master = false
		commander.control_servant = false
	await create_timer(0.5).timeout
	var frozen_position: Vector2 = servant.position
	servant._rpc_command_move(frozen_position + Vector2(220.0, 0.0), false)
	await create_timer(0.5).timeout
	_check(servant.position.distance_to(frozen_position) < 6.0, "manual move command is ignored while identity is unknown")

	servant._rpc_ask_servant_name()
	await process_frame
	await process_frame
	_check(servant.is_name_known_to_master, "Ask Servant's Name unlocks the true name")
	_check(not bool(arena.call("has_ai_commander", 1)), "Ask Servant's Name detaches autonomy AI")
	_check(servant.get_display_name_for(1) == servant.servant_data.display_name, "owner HUD reveals the true name")
	_check(servant.get_display_name_for(2).begins_with("Unknown [Saber]"), "true name remains secret from enemies")
	await process_frame
	_check(not action_buttons["servant_1"].disabled, "servant skill buttons unlock after name discovery")
	var move_start: Vector2 = servant.position
	servant._rpc_command_move(move_start + Vector2(220.0, 0.0), false)
	await create_timer(0.7).timeout
	_check(servant.position.distance_to(move_start) > 20.0, "manual RTS movement works after name discovery")

	# Public reveal + Fame buff.
	servant._rpc_publicly_reveal_name()
	await process_frame
	_check(servant.is_true_name_revealed, "Publicly Reveal True Name broadcasts identity")
	_check(servant.is_fame_buffed, "Public reveal grants the Fame / Morale buff")
	_check(servant.get_display_name_for(2) == servant.servant_data.display_name, "enemies see the publicly revealed true name")
	var original_crit: float = servant.servant_data.critical_chance
	servant.servant_data.critical_chance = 0.0
	var buffed_damage: float = servant._outgoing_damage(100.0)
	servant.servant_data.critical_chance = original_crit
	_check(is_equal_approx(buffed_damage, 115.0), "Fame buff grants +15% outgoing combat damage")

	# Signature Command Spell then standard slot.
	servant.health = 20.0
	servant.mana = 5.0
	master._server_use_command_spell()
	await process_frame
	_check(master.signature_command_spell_used, "first Command Spell burns the signature decree")
	_check(master.command_spells_left == 2, "signature Command Spell consumes one of three charges")
	_check(servant.health > 20.0, "signature decree applies its unique effect")
	master._server_use_command_spell()
	await process_frame
	_check(master.command_spells_left == 1, "standard Command Spell consumes the second charge")
	_check(servant.health >= servant.max_health - 0.1 and servant.mana >= servant.max_mana - 0.1, "standard slots restore HP and Mana")
	_check(servant.position.distance_to(master.position) < 120.0, "standard Command Spell warps the Servant to the Master")

	# Master Trump Card.
	master.mana = master.max_mana
	master._rpc_use_trump_card(Vector2.RIGHT)
	await process_frame
	_check(not master.trump_card_ready, "Master Trump Card consumes its cooldown")
	_check(master.is_shielded, "Shirou's Rho Aias shields the Master")
	_check(servant.is_shielded, "Rho Aias also shields the Servant")
	var events: Array[String] = arena.get("_events")
	var has_decree: bool = false
	var has_trump: bool = false
	for event: String in events:
		if event.contains("SIGNATURE DECREE"):
			has_decree = true
		if event.contains("TRUMP CARD"):
			has_trump = true
	_check(has_decree and has_trump, "event ticker records signature decrees and Trump Cards")

	director.call("leave_match")
	await _wait_scene("MainMenu", 3.0)

	# --- Apocrypha 15-slot 3-stage draft ----------------------------------
	director.call("host_match", true, 7821)
	var apoc_lobby: Node = await _wait_scene("Lobby", 3.0)
	_check(apoc_lobby != null, "Apocrypha spectator lobby opens")
	if apoc_lobby == null:
		_finish()
		return
	director.call("request_mode", MatchConfig.MatchMode.APOCRYPHA_7V7)
	director.call("request_fill_ai")
	await process_frame
	await process_frame
	_check(int(director.get("draft_stage")) == 0, "Apocrypha enters Stage 1 Master Selection")
	var apoc_entries: Dictionary = director.get("entries")
	_check(apoc_entries.size() == 15, "Apocrypha fills 15 draft slots")
	var masters: Dictionary = {}
	var stage_one_classes_empty: bool = true
	for key: Variant in apoc_entries.keys():
		var entry: Dictionary = apoc_entries[key]
		masters[String(entry.get("master_id", ""))] = true
		if int(entry.get("class_id", -1)) >= 0:
			stage_one_classes_empty = false
	_check(masters.size() == 15, "Stage 1 uses 15 globally unique Masters")
	_check(stage_one_classes_empty, "Stage 1 does not yet assign Servant classes")

	director.call("request_shuffle_factions")
	await process_frame
	await process_frame
	_check(int(director.get("draft_stage")) == 2, "Stage 2 shuffles into Stage 3 Class Selection")
	var red: int = 0
	var black: int = 0
	var neutral: int = 0
	var neutral_class: int = -1
	for key: Variant in (director.get("entries") as Dictionary).keys():
		var entry: Dictionary = (director.get("entries") as Dictionary)[key]
		var team: int = int(entry.get("team", -1))
		if team == MatchConfig.Team.RED:
			red += 1
		elif team == MatchConfig.Team.BLACK:
			black += 1
		elif team == MatchConfig.Team.NEUTRAL:
			neutral += 1
			neutral_class = int(entry.get("class_id", -1))
	_check(red == 7 and black == 7 and neutral == 1, "Stage 2 creates 7 Red / 7 Black / 1 Neutral Arbiter")
	_check(neutral_class == ServantData.ServantClass.RULER, "Neutral Arbiter is locked to Ruler")

	director.call("request_start_match")
	var apoc_arena: Node = await _wait_scene("Arena", 5.0)
	_check(apoc_arena != null, "Apocrypha draft enters the arena")
	if apoc_arena != null:
		await process_frame
		await process_frame
		var final_entries: Dictionary = director.get("entries")
		_check(final_entries.size() == 15, "Apocrypha arena starts with 15 participants")
		var red_classes: Dictionary = {}
		var black_classes: Dictionary = {}
		for key: Variant in final_entries.keys():
			var entry: Dictionary = final_entries[key]
			var team: int = int(entry.get("team", -1))
			var class_id: int = int(entry.get("class_id", -1))
			if team == MatchConfig.Team.RED:
				red_classes[class_id] = true
			elif team == MatchConfig.Team.BLACK:
				black_classes[class_id] = true
		_check(red_classes.size() == 7 and black_classes.size() == 7, "Stage 3 enforces one unique class per faction")
		_check(apoc_arena.get_local_master() == null and apoc_arena.get_local_servant() == null, "spectator host retains no duo")
		director.call("leave_match")
		await _wait_scene("MainMenu", 3.0)

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
		print("UNIQUENESS / AUTONOMY TEST PASSED")
		quit(0)
	else:
		print("UNIQUENESS / AUTONOMY TEST FAILED (%d failure(s))" % _failures)
		quit(1)
