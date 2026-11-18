extends SceneTree
## Headless Milestone 3 integration test.
## Run: godot --headless --path . --script res://tests/smoke_test.gd

var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	await _test_rosters_and_triangle()
	await _test_ffa_arena()
	await _test_apocrypha_arena()
	_finish()


func _test_rosters_and_triangle() -> void:
	var servants: Array[ServantData] = Roster.get_servants()
	var masters: Array[MasterData] = Roster.get_masters()
	_check(servants.size() == 30, "30 named Servant resources load")
	_check(masters.size() == 15, "15 named Master resources load")

	var class_counts: Dictionary = {}
	for servant: ServantData in servants:
		class_counts[servant.servant_class] = int(class_counts.get(servant.servant_class, 0)) + 1
	for class_id: int in Roster.get_class_ids():
		_check(int(class_counts.get(class_id, 0)) >= 1, "class %s has at least one Servant" % Roster.class_name_for(class_id))
	_check(int(class_counts.get(ServantData.ServantClass.AVENGER, 0)) == 1, "Avenger roster is represented")
	_check(int(class_counts.get(ServantData.ServantClass.RULER, 0)) == 2, "Ruler roster has Jeanne and Amakusa")

	for named_id: String in [
		"artoria_pendragon", "emiya", "gilgamesh", "cu_chulainn", "medusa", "medea",
		"sasaki_kojiro", "heracles", "angra_mainyu", "mordred", "siegfried", "atalanta",
		"chiron", "karna", "vlad_iii", "achilles", "astolfo", "william_shakespeare",
		"avicebron", "semiramis", "jack_the_ripper", "spartacus", "frankenstein",
		"jeanne_darc", "amakusa_shirou",
	]:
		_check(Roster.find_servant(named_id) != null, "named Servant '%s' exists" % named_id)

	for master_id: String in [
		"rin_tohsaka", "shirou_emiya", "illyasviel_von_einzbern", "kirei_kotomine",
		"kiritsugu_emiya", "kairi_sisigou", "darnic_yggdmillennia", "fiore_yggdmillennia",
	]:
		var master: MasterData = Roster.find_master(master_id)
		_check(master != null, "named Master '%s' exists" % master_id)
		if master != null:
			_check(master.active_skills.size() == 2, "%s has two active skills" % master.display_name)
			_check(master.max_mana > 0.0 and master.mana_regeneration > 0.0, "%s has a Mana economy" % master.display_name)

	_check(is_equal_approx(ClassTriangle.get_total_multiplier(ServantData.ServantClass.SABER, ServantData.ServantClass.LANCER), ClassTriangle.ADVANTAGE), "Knight triangle: Saber > Lancer")
	_check(is_equal_approx(ClassTriangle.get_total_multiplier(ServantData.ServantClass.LANCER, ServantData.ServantClass.SABER), ClassTriangle.DISADVANTAGE), "Knight triangle reverse disadvantage")
	_check(is_equal_approx(ClassTriangle.get_total_multiplier(ServantData.ServantClass.ARCHER, ServantData.ServantClass.SABER), ClassTriangle.ADVANTAGE), "Knight triangle: Archer > Saber")
	_check(is_equal_approx(ClassTriangle.get_total_multiplier(ServantData.ServantClass.RIDER, ServantData.ServantClass.CASTER), ClassTriangle.ADVANTAGE), "Cavalry triangle: Rider > Caster")
	_check(is_equal_approx(ClassTriangle.get_total_multiplier(ServantData.ServantClass.CASTER, ServantData.ServantClass.ASSASSIN), ClassTriangle.ADVANTAGE), "Cavalry triangle: Caster > Assassin")
	_check(is_equal_approx(ClassTriangle.get_total_multiplier(ServantData.ServantClass.ASSASSIN, ServantData.ServantClass.RIDER), ClassTriangle.ADVANTAGE), "Cavalry triangle: Assassin > Rider")
	_check(is_equal_approx(ClassTriangle.get_total_multiplier(ServantData.ServantClass.BERSERKER, ServantData.ServantClass.SABER), 1.5), "Berserker deals 1.5x")
	_check(is_equal_approx(ClassTriangle.get_total_multiplier(ServantData.ServantClass.SABER, ServantData.ServantClass.BERSERKER), 1.5), "Berserker takes 1.5x")
	_check(is_equal_approx(ClassTriangle.get_total_multiplier(ServantData.ServantClass.SABER, ServantData.ServantClass.RULER), 0.75), "Ruler takes 0.75x from standard classes")
	_check(is_equal_approx(ClassTriangle.get_total_multiplier(ServantData.ServantClass.AVENGER, ServantData.ServantClass.RULER), 1.5), "Avenger deals 1.5x to Ruler")
	await process_frame


func _test_ffa_arena() -> void:
	var arena: Node2D = await _make_arena()
	_check(arena.get_match_mode() == MatchConfig.MatchMode.FUYUKI_FFA, "Fuyuki FFA is the default mode")
	_check(arena.get_leylines().size() == 3, "three Leylines are present")

	var players: Node = arena.get_node("Players")
	var pre_summon_units: int = 0
	for child: Node in players.get_children():
		if child.is_in_group("player_units"):
			pre_summon_units += 1
	_check(pre_summon_units == 0, "no units spawn before summoning")
	var overlay: CanvasLayer = arena.get_node_or_null("ClassSelectOverlay") as CanvasLayer
	_check(overlay != null and overlay.visible, "summoning overlay is visible")

	# Specific host Master + class selection through the public lobby API.
	arena.request_summon("shirou_emiya", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	await process_frame
	var host_entry: Dictionary = arena.get_lobby_state().get(1, {})
	_check(String(host_entry.get("master_id", "")) == "shirou_emiya", "specific host Master selection resolves")
	_check(int(host_entry.get("class_id", -1)) == ServantData.ServantClass.SABER, "host picks the Saber class")
	_check(Roster.find_servant(String(host_entry.get("servant_id", ""))) != null, "server secretly rolls a matching Servant")
	arena.request_deploy()
	await process_frame
	await process_frame

	var host_servant: ServantController = arena.get_local_servant()
	var host_master: MasterController = arena.get_local_master()
	_check(host_servant != null, "host Servant spawns")
	_check(host_master != null, "host Master spawns")
	if host_servant == null or host_master == null:
		await _drop_arena(arena)
		return
	_check(host_servant.servant_data.servant_class == ServantData.ServantClass.SABER, "rolled host Servant is a Saber")
	_check(host_master.master_data.master_id == "shirou_emiya", "host Master uses Shirou")
	_check(host_master.command_spells_left == 3, "Master starts with 3 Command Spells")
	_check(host_servant.master_unit == host_master and host_master.servant_unit == host_servant, "Master and Servant are linked")
	_check(host_servant.team_id == 1 and host_master.team_id == 1, "FFA host team is the peer id")
	await process_frame
	if overlay != null:
		_check(not overlay.visible, "overlay hides after deployment")

	var roster_pairs: Array = [
		[2, "rin_tohsaka", ServantData.ServantClass.ARCHER],
		[3, "kirei_kotomine", ServantData.ServantClass.LANCER],
		[4, "fiore_yggdmillennia", ServantData.ServantClass.CASTER],
		[5, "kairi_sisigou", ServantData.ServantClass.ASSASSIN],
		[6, "darnic_yggdmillennia", ServantData.ServantClass.BERSERKER],
		[7, "illyasviel_von_einzbern", ServantData.ServantClass.RULER],
	]
	for pair: Array in roster_pairs:
		arena.call("_server_summon", int(pair[0]), String(pair[1]), int(pair[2]), Roster.RollMode.SPECIFIC)
		arena.call("_server_deploy", int(pair[0]))
	await process_frame
	await process_frame

	var archer: ServantController = arena.call("_get_servant", 2) as ServantController
	var lancer: ServantController = arena.call("_get_servant", 3) as ServantController
	var caster: ServantController = arena.call("_get_servant", 4) as ServantController
	var assassin: ServantController = arena.call("_get_servant", 5) as ServantController
	var berserker: ServantController = arena.call("_get_servant", 6) as ServantController
	var ruler: ServantController = arena.call("_get_servant", 7) as ServantController
	var fiore_master: MasterController = arena.call("_get_master", 4) as MasterController
	var illya_master: MasterController = arena.call("_get_master", 7) as MasterController
	_check(archer != null and archer.servant_data.servant_class == ServantData.ServantClass.ARCHER, "Archer EMIYA deploys")
	_check(lancer != null and lancer.servant_data.servant_class == ServantData.ServantClass.LANCER, "Lancer Cu deploys")
	_check(caster != null and caster.servant_data.servant_class == ServantData.ServantClass.CASTER, "Caster Medea deploys")
	_check(assassin != null and assassin.servant_data.servant_class == ServantData.ServantClass.ASSASSIN, "Assassin Sasaki deploys")
	_check(berserker != null and berserker.servant_data.servant_class == ServantData.ServantClass.BERSERKER, "Berserker Heracles deploys")
	_check(ruler != null and ruler.servant_data.servant_class == ServantData.ServantClass.RULER, "Ruler Jeanne deploys")
	if archer == null or lancer == null or caster == null or assassin == null or berserker == null or ruler == null:
		await _drop_arena(arena)
		return

	# Actual class-triangle damage resolution.
	lancer.health = 1000.0
	lancer.receive_damage(100.0, 1, ServantData.ServantClass.SABER)
	_check(is_equal_approx(lancer.health, 865.0), "Saber deals 1.35x to Lancer")
	lancer.health = lancer.max_health

	ruler.health = 1000.0
	ruler.receive_damage(100.0, 1, ServantData.ServantClass.SABER)
	_check(is_equal_approx(ruler.health, 925.0), "Ruler takes 0.75x from Saber")
	ruler.health = 1000.0
	ruler.receive_damage(100.0, 8, ServantData.ServantClass.AVENGER)
	_check(is_equal_approx(ruler.health, 850.0), "Ruler takes 1.5x from Avenger")
	ruler.health = ruler.max_health

	# Fuyuki FFA runtime diplomacy changes damage legality.
	arena.request_stance(2, MatchConfig.Stance.ALLIED)
	archer.health = 100.0
	archer.receive_damage(10.0, 1, ServantData.ServantClass.SABER)
	_check(is_equal_approx(archer.health, 100.0), "Allied stance blocks incoming damage")
	arena.request_stance(2, MatchConfig.Stance.HOSTILE)
	archer.receive_damage(10.0, 1, ServantData.ServantClass.ARCHER)
	_check(archer.health < 100.0, "Hostile stance allows damage again")
	archer.health = archer.max_health

	# True-name concealment and Master scouting.
	_check(not archer.is_true_name_revealed, "enemy true name starts concealed")
	_check(archer.get_display_name_for(1).begins_with("Unknown [Archer]"), "concealed Servant displays Unknown [Class]")
	var archer_name: String = archer.servant_data.display_name
	var roster_before_reveal: String = String(arena.call("_format_roster"))
	_check(not roster_before_reveal.contains(archer_name), "HUD roster conceals enemy true names")
	_check(roster_before_reveal.contains("Unknown [Archer]"), "HUD roster shows Unknown [Class]")
	if fiore_master != null:
		fiore_master._server_use_skill(0, Vector2.RIGHT)
	await process_frame
	_check(archer.is_true_name_revealed, "Master scouting skill reveals true names")
	_check(archer.get_display_name_for(1) == archer_name, "revealed Servant displays its true name")
	_check(String(arena.call("_format_roster")).contains(archer_name), "HUD roster updates after true-name reveal")

	# Fog of war rules (pure visibility function, testable headless).
	var viewer_units: Array[Node2D] = [host_master, host_servant]
	archer.position = Vector2(650.0, 320.0)
	_check(not arena.is_unit_visible_to(archer, viewer_units, 1, 1), "Fog hides an enemy outside vision")
	archer.position = host_servant.position + Vector2(200.0, 0.0)
	_check(arena.is_unit_visible_to(archer, viewer_units, 1, 1), "Fog reveals an enemy inside vision")
	archer.is_stealthed = true
	_check(not arena.is_unit_visible_to(archer, viewer_units, 1, 1), "Presence Concealment hides an enemy inside normal vision")
	archer.position = host_servant.position + Vector2(80.0, 0.0)
	_check(arena.is_unit_visible_to(archer, viewer_units, 1, 1), "Close detection reveals a stealthed Assassin")
	archer.is_stealthed = false

	# RTS unit commands.
	var move_start: Vector2 = host_servant.position
	host_servant._rpc_command_move(move_start + Vector2(120.0, 0.0), false)
	await create_timer(0.6).timeout
	_check(host_servant.position.distance_to(move_start) > 30.0, "Servant responds to RTS move command")

	var master_start: Vector2 = host_master.position
	host_master._rpc_command_move(master_start + Vector2(-80.0, 0.0), false)
	await create_timer(0.5).timeout
	_check(host_master.position.distance_to(master_start) > 20.0, "Master responds to RTS move command")

	lancer.position = host_servant.position + Vector2(70.0, 0.0)
	lancer.health = lancer.max_health
	host_servant.mana = host_servant.max_mana
	host_servant._attack_ready_at_msec = 0
	host_servant._rpc_command_attack(lancer.get_path())
	await create_timer(0.6).timeout
	_check(lancer.health < lancer.max_health, "RTS attack command produces class-triangle damage")

	# Attack-move: Shift+RMB to ground auto-acquires a nearby hostile.
	archer.position = Vector2(640.0, 300.0)
	archer.health = archer.max_health
	lancer.position = host_servant.position + Vector2(100.0, 0.0)
	lancer.health = lancer.max_health
	host_servant.mana = host_servant.max_mana
	host_servant._attack_ready_at_msec = 0
	host_servant._rpc_command_move(host_servant.position + Vector2(260.0, 0.0), true)
	await create_timer(0.7).timeout
	_check(lancer.health < lancer.max_health, "RTS attack-move acquires and attacks a nearby enemy")

	# Command Spell: slot 1 uses Shirou's signature decree, slot 2 is standard warp.
	host_servant.health = 20.0
	host_servant.mana = 5.0
	host_master._server_use_command_spell()
	await process_frame
	_check(host_master.command_spells_left == 2, "Command Spell charge is consumed")
	_check(host_master.signature_command_spell_used, "first Command Spell uses the Master's signature decree")
	_check(host_servant.health > 20.0, "Signature Command Spell restores Servant HP")
	host_master._server_use_command_spell()
	await process_frame
	_check(host_master.command_spells_left == 1, "standard Command Spell slot consumes the second charge")
	_check(host_servant.health >= host_servant.max_health - 0.1, "standard Command Spell restores Servant HP")
	_check(host_servant.mana >= host_servant.max_mana - 0.1, "standard Command Spell restores Servant Mana")
	_check(host_servant.position.distance_to(host_master.position) < 120.0, "standard Command Spell warps Servant to Master")

	# Master Mana / Leyline capture economy.
	var base_master_regen: float = host_master.mana_regeneration
	var center_leyline: LeylineNode = arena.get_leylines()[2]
	host_master.position = center_leyline.global_position
	await create_timer(2.8).timeout
	_check(center_leyline.owner_peer_id == 1, "Master can capture a Leyline")
	_check(host_master.leylines_held == 1, "Master tracks a held Leyline")
	_check(host_master.mana_regeneration > base_master_regen, "Holding a Leyline boosts Master Mana regeneration")

	# Caster Territory Creation regression.
	var caster_base_regen: float = caster.servant_data.mana_regeneration
	var west_leyline: LeylineNode = arena.get_leylines()[0]
	caster.position = west_leyline.global_position
	await create_timer(2.8).timeout
	_check(caster.territory_bonus_active, "Caster Territory Creation activates inside a Leyline")
	_check(caster.leylines_held >= 1, "Caster captures a Leyline")
	_check(caster.mana > 0.0, "Caster Mana economy remains active")
	_check(caster.get_effective_spell_multiplier() > caster.servant_data.spell_damage_multiplier, "Territory Creation boosts Caster spell damage")

	# Master death eliminates the pair.
	if illya_master != null:
		illya_master.receive_damage(9999.0, 1, -1)
		await process_frame
		await process_frame
	_check(arena.call("_get_master", 7) == null, "Master death removes the Master unit")
	_check(arena.call("_get_servant", 7) == null, "Master death removes the linked Servant")
	_check(bool(arena.get_lobby_state().get(7, {}).get("eliminated", false)), "Master death marks the player eliminated")

	await _drop_arena(arena)


func _test_apocrypha_arena() -> void:
	var arena: Node2D = await _make_arena()
	arena.call("_server_set_match_mode", MatchConfig.MatchMode.APOCRYPHA_7V7)
	await process_frame
	_check(arena.get_match_mode() == MatchConfig.MatchMode.APOCRYPHA_7V7, "Apocrypha 7v7 mode can be selected")

	arena.call("_server_summon", 1, "shirou_emiya", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	arena.call("_server_deploy", 1)
	arena.call("_server_summon", 2, "rin_tohsaka", ServantData.ServantClass.ARCHER, Roster.RollMode.SPECIFIC)
	arena.call("_server_deploy", 2)
	arena.call("_server_summon", 3, "illyasviel_von_einzbern", ServantData.ServantClass.RULER, Roster.RollMode.SPECIFIC)
	arena.call("_server_deploy", 3)
	await process_frame
	await process_frame

	var match_state: MatchState = arena.get_match_state()
	_check(match_state.get_team(1) == MatchConfig.Team.RED, "Apocrypha peer 1 is RED")
	_check(match_state.get_team(2) == MatchConfig.Team.BLACK, "Apocrypha peer 2 is BLACK")
	_check(match_state.get_team(3) == MatchConfig.Team.NEUTRAL, "Ruler player becomes neutral arbiter")
	_check(match_state.can_damage(1, 2), "RED can damage BLACK")
	_check(not match_state.can_damage(1, 3), "Neutral arbiter cannot be damaged")
	_check(not match_state.can_damage(1, 1), "Self damage is blocked")

	# Server-side Random Summon.
	arena.call("_server_summon", 8, "", -1, Roster.RollMode.RANDOM_PAIR)
	await process_frame
	var random_entry: Dictionary = arena.get_lobby_state().get(8, {})
	_check(Roster.find_master(String(random_entry.get("master_id", ""))) != null, "Random Summon resolves a valid Master")
	_check(Roster.find_servant(String(random_entry.get("servant_id", ""))) != null, "Random Summon resolves a valid Servant")
	arena.call("_server_deploy", 8)
	await process_frame
	await process_frame
	var random_master: MasterController = arena.call("_get_master", 8) as MasterController
	var random_servant: ServantController = arena.call("_get_servant", 8) as ServantController
	_check(random_master != null and random_master.master_data.master_id == String(random_entry.get("master_id", "")), "Random Master spawns with the rolled identity")
	_check(random_servant != null and random_servant.servant_data.servant_id == String(random_entry.get("servant_id", "")), "Random Servant spawns with the rolled identity")
	var random_team: int = match_state.get_team(8)
	_check(random_team == MatchConfig.Team.RED or random_team == MatchConfig.Team.BLACK or (random_team == MatchConfig.Team.NEUTRAL and random_servant.servant_data.servant_class == ServantData.ServantClass.RULER), "Random player receives a valid Apocrypha team")

	# Random Servant Only keeps an explicitly selected, still-unclaimed Master.
	var claimed_masters: Dictionary = {}
	for entry_variant: Variant in arena.get_lobby_state().values():
		var claimed_entry: Dictionary = entry_variant
		claimed_masters[String(claimed_entry.get("master_id", ""))] = true
	var free_master_id: String = ""
	for master: MasterData in Roster.get_masters():
		if not claimed_masters.has(master.master_id):
			free_master_id = master.master_id
			break
	arena.call("_server_summon", 9, free_master_id, -1, Roster.RollMode.RANDOM_SERVANT)
	await process_frame
	var random_servant_entry: Dictionary = arena.get_lobby_state().get(9, {})
	_check(String(random_servant_entry.get("master_id", "")) == free_master_id, "Random Servant Only keeps the selected Master")
	_check(Roster.find_servant(String(random_servant_entry.get("servant_id", ""))) != null, "Random Servant Only rolls a valid Servant")
	arena.call("_server_deploy", 9)
	await process_frame
	await process_frame
	var chosen_master: MasterController = arena.call("_get_master", 9) as MasterController
	_check(chosen_master != null and chosen_master.master_data.master_id == free_master_id, "Random Servant Only deploys the chosen Master")

	_check(MatchConfig.mode_name(MatchConfig.MatchMode.APOCRYPHA_7V7) == "APOCRYPHA 7v7", "mode display names are available")
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
		print("MILESTONE 3 SMOKE TEST PASSED")
		quit(0)
	else:
		print("MILESTONE 3 SMOKE TEST FAILED (%d failure(s))" % _failures)
		quit(1)
