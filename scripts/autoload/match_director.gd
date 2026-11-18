extends Node
## Persistent pre-match flow controller.
##
## Owns synchronized lobby slots, global Master/Class locks, the 15-slot
## Apocrypha draft, secret class-based Servant rolls, and the authoritative
## simultaneous launch into arena.tscn.

signal lobby_changed
signal notification(message: String)
signal returned_to_menu
signal arena_ready(peer_id: int)

const LOBBY_SCENE: String = "res://scenes/lobby.tscn"
const ARENA_SCENE: String = "res://scenes/arena.tscn"
const MENU_SCENE: String = "res://scenes/main_menu.tscn"
const AI_SLOT_BASE: int = 1_000_000
const STANDARD_CLASSES: Array = [
	ServantData.ServantClass.SABER,
	ServantData.ServantClass.ARCHER,
	ServantData.ServantClass.LANCER,
	ServantData.ServantClass.RIDER,
	ServantData.ServantClass.CASTER,
	ServantData.ServantClass.ASSASSIN,
	ServantData.ServantClass.BERSERKER,
]

enum DraftStage {
	MASTER_SELECTION,
	FACTION_SHUFFLE,
	CLASS_SELECTION,
	READY,
}

var mode: int = MatchConfig.MatchMode.FUYUKI_FFA
var entries: Dictionary = {}
var auto_fill: bool = true
var spectator_mode: bool = false
var match_started: bool = false
var lobby_active: bool = false
var draft_stage: int = DraftStage.MASTER_SELECTION

var _next_ai_id: int = AI_SLOT_BASE
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _arena_setup: Dictionary = {}
var _pending_join: bool = false
var _lobby_notice: String = ""
var _returning: bool = false
var _arena_ready_peers: Dictionary = {}
var _rolled_servant_ids: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	mode = _parse_mode_from_cli()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_boot_dedicated_lobby.call_deferred()


# --- Dedicated server boot ---------------------------------------------------

func _boot_dedicated_lobby() -> void:
	if not _should_auto_host():
		return
	var network: Node = get_node_or_null("/root/NetworkManager")
	if network == null:
		return
	if not bool(network.get("is_hosting")):
		var port: int = _cli_port()
		var err: Error = network.call("host_game", port)
		if err != OK:
			notification.emit("Dedicated server could not bind port %d." % port)
			return
	_clear_state()
	mode = _parse_mode_from_cli()
	auto_fill = true
	spectator_mode = _cli_args().has("--spectate")
	lobby_active = true
	print("[MatchDirector] Dedicated server ready in Waiting Lobby (mode=%s, spectator=%s)." % [
		MatchConfig.mode_name(mode), str(spectator_mode)
	])
	_change_scene(LOBBY_SCENE)


func _should_auto_host() -> bool:
	var args: PackedStringArray = _cli_args()
	# Tests, CI validation and clients must never be forced into hosting.
	if args.has("--script") or args.has("--check-only"):
		return false
	if args.has("--connect"):
		return false
	for arg: String in args:
		if arg.begins_with("--connect="):
			return false
	if args.has("--dedicated-server") or args.has("--server"):
		return true
	if OS.has_feature("dedicated_server"):
		return true
	return DisplayServer.get_name() == "headless"


func _cli_args() -> PackedStringArray:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return args


func _cli_port() -> int:
	var args: PackedStringArray = _cli_args()
	var index: int = 0
	while index < args.size():
		var arg: String = args[index]
		if arg == "--port" and index + 1 < args.size():
			return int(args[index + 1])
		if arg.begins_with("--port="):
			return int(arg.get_slice("=", 1))
		index += 1
	return 7777


func consume_lobby_notice() -> String:
	var notice: String = _lobby_notice
	_lobby_notice = ""
	return notice


# --- Menu / scenario entry points ------------------------------------------

func host_match(spectator: bool = false, port: int = 7777) -> Error:
	var network: Node = get_node_or_null("/root/NetworkManager")
	if network == null:
		return ERR_UNCONFIGURED
	var err: Error = network.call("host_game", port)
	if err != OK:
		notification.emit("Could not host on port %d." % port)
		return err
	_clear_state()
	spectator_mode = spectator
	lobby_active = true
	_change_scene(LOBBY_SCENE)
	return OK


func join_match(address: String, port: int = 7777) -> Error:
	var network: Node = get_node_or_null("/root/NetworkManager")
	if network == null:
		return ERR_UNCONFIGURED
	var err: Error = network.call("join_game", address, port)
	if err != OK:
		notification.emit("Could not connect to %s:%d." % [address, port])
		return err
	_clear_state()
	lobby_active = true
	_pending_join = true
	_change_scene(LOBBY_SCENE)
	return OK


func leave_lobby() -> void:
	leave_to_menu()


func leave_match() -> void:
	leave_to_menu()


func leave_to_menu() -> void:
	if _returning:
		return
	_returning = true
	var network: Node = get_node_or_null("/root/NetworkManager")
	lobby_active = false
	match_started = false
	_clear_state()
	Engine.time_scale = 1.0
	if network != null:
		network.call("disconnect_from_match")
	_change_scene(MENU_SCENE)
	_returning = false
	returned_to_menu.emit()


## Ends the current match and returns every peer to an empty Waiting Lobby
## while keeping the ENet transport alive for the next match.
func finish_match_and_reset(reason: String = "") -> void:
	if not multiplayer.is_server():
		return
	if not match_started and not lobby_active:
		return
	if multiplayer.get_peers().is_empty():
		_rpc_reset_to_lobby(reason)
	else:
		_rpc_reset_to_lobby.rpc(reason)


@rpc("authority", "call_local", "reliable")
func _rpc_reset_to_lobby(reason: String) -> void:
	var keep_mode: int = mode
	var keep_auto_fill: bool = auto_fill
	var keep_spectator: bool = spectator_mode
	_clear_state()
	mode = keep_mode
	auto_fill = keep_auto_fill
	spectator_mode = keep_spectator
	lobby_active = true
	draft_stage = DraftStage.MASTER_SELECTION
	_lobby_notice = reason
	Engine.time_scale = 1.0
	_change_scene(LOBBY_SCENE)
	if not reason.is_empty():
		notification.emit(reason)
	print("[MatchDirector] Match reset to Waiting Lobby. %s" % reason)


func _has_human_players() -> bool:
	for key: Variant in entries.keys():
		var entry: Dictionary = entries[key]
		if bool(entry.get("is_ai", false)):
			continue
		if bool(entry.get("spectating", false)):
			continue
		if bool(entry.get("eliminated", false)):
			continue
		if bool(entry.get("deployed", false)):
			return true
	return false


func return_to_menu(message: String = "") -> void:
	if _returning:
		return
	_returning = true
	var network: Node = get_node_or_null("/root/NetworkManager")
	lobby_active = false
	match_started = false
	_clear_state()
	Engine.time_scale = 1.0
	if network != null:
		network.call("disconnect_from_match")
	if not message.is_empty():
		notification.emit(message)
	_change_scene(MENU_SCENE)
	_returning = false
	returned_to_menu.emit()


func request_lobby_state() -> void:
	if not multiplayer.is_server():
		_rpc_request_state.rpc_id(1)


func report_arena_ready() -> void:
	if multiplayer.is_server():
		_arena_ready_peers[multiplayer.get_unique_id()] = true
	else:
		_rpc_arena_ready.rpc_id(1)


func is_peer_arena_ready(peer_id: int) -> bool:
	return _arena_ready_peers.has(peer_id)


# --- Queries ----------------------------------------------------------------

func get_entries_snapshot() -> Dictionary:
	return entries.duplicate(true)


func get_arena_setup() -> Dictionary:
	return _arena_setup.duplicate(true)


func is_lobby_active() -> bool:
	return lobby_active


func is_match_started() -> bool:
	return match_started


func is_spectator_mode() -> bool:
	return spectator_mode


func is_auto_fill() -> bool:
	return auto_fill


func get_mode() -> int:
	return mode


func get_draft_stage() -> int:
	return draft_stage


func get_capacity() -> int:
	return 7 if mode == MatchConfig.MatchMode.FUYUKI_FFA else 15


func get_local_entry() -> Dictionary:
	return entries.get(multiplayer.get_unique_id(), {})


func get_claimed_master_ids(exclude_peer: int = 0) -> Array:
	var claimed: Array = []
	for key: Variant in entries.keys():
		if int(key) == exclude_peer:
			continue
		var entry: Dictionary = entries[key]
		var master_id: String = String(entry.get("master_id", ""))
		if not master_id.is_empty():
			claimed.append(master_id)
	return claimed


func get_team_classes(team: int, exclude_peer: int = 0) -> Array:
	var classes: Array = []
	for key: Variant in entries.keys():
		if int(key) == exclude_peer:
			continue
		var entry: Dictionary = entries[key]
		if int(entry.get("team", -1)) != team:
			continue
		var class_id: int = int(entry.get("class_id", -1))
		if class_id >= 0 and not classes.has(class_id):
			classes.append(class_id)
	return classes


# --- Lobby actions ----------------------------------------------------------

func request_summon(master_id: String, class_id: int, roll_mode: int) -> void:
	if multiplayer.is_server():
		_server_summon(multiplayer.get_unique_id(), master_id, class_id, roll_mode)
	else:
		_rpc_summon.rpc_id(1, master_id, class_id, roll_mode)


func request_class(class_id: int) -> void:
	if multiplayer.is_server():
		_server_select_class(multiplayer.get_unique_id(), class_id)
	else:
		_rpc_select_class.rpc_id(1, class_id)


func request_random_class() -> void:
	if multiplayer.is_server():
		_server_random_class(multiplayer.get_unique_id())
	else:
		_rpc_random_class.rpc_id(1)


func request_player_ready(ready: bool) -> void:
	if multiplayer.is_server():
		_server_ready(multiplayer.get_unique_id(), ready)
	else:
		_rpc_ready.rpc_id(1, ready)


func request_add_ai(master_id: String, class_id: int, roll_mode: int) -> void:
	if multiplayer.is_server():
		_server_add_ai(master_id, class_id, roll_mode)
	else:
		_rpc_add_ai.rpc_id(1, master_id, class_id, roll_mode)


func request_remove_ai() -> void:
	if multiplayer.is_server():
		_server_remove_ai()
	else:
		_rpc_remove_ai.rpc_id(1)


func request_fill_ai() -> void:
	if multiplayer.is_server():
		_server_fill_ai()
	else:
		_rpc_fill_ai.rpc_id(1)


func request_shuffle_factions() -> void:
	if multiplayer.is_server():
		_server_shuffle_factions()
	else:
		_rpc_shuffle_factions.rpc_id(1)


func request_auto_fill(enabled: bool) -> void:
	if multiplayer.is_server():
		_server_set_auto_fill(enabled)
	else:
		_rpc_set_auto_fill.rpc_id(1, enabled)


func request_spectator_mode(enabled: bool) -> void:
	if multiplayer.is_server():
		_server_set_spectator(enabled)
	else:
		_rpc_set_spectator.rpc_id(1, enabled)


func request_mode(new_mode: int) -> void:
	if multiplayer.is_server():
		_server_set_mode(new_mode)
	else:
		_rpc_set_mode.rpc_id(1, new_mode)


func request_start_match() -> void:
	if multiplayer.is_server():
		_server_start_match()
	else:
		_rpc_start_match.rpc_id(1)


# --- RPCs -------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_state() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	_rpc_sync_lobby.rpc_id(sender, entries.duplicate(true), mode, spectator_mode, auto_fill, match_started, draft_stage)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_lobby(state: Dictionary, new_mode: int, spectator: bool, fill: bool, started: bool, stage: int) -> void:
	entries = state
	mode = new_mode
	spectator_mode = spectator
	auto_fill = fill
	match_started = started
	draft_stage = stage
	lobby_changed.emit()


@rpc("any_peer", "call_local", "reliable")
func _rpc_summon(master_id: String, class_id: int, roll_mode: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = _get_rpc_sender()
	if sender == 0:
		return
	_server_summon(sender, master_id, class_id, roll_mode)


@rpc("any_peer", "call_local", "reliable")
func _rpc_select_class(class_id: int) -> void:
	if not multiplayer.is_server():
		return
	_server_select_class(_get_rpc_sender(), class_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_random_class() -> void:
	if not multiplayer.is_server():
		return
	_server_random_class(_get_rpc_sender())


@rpc("any_peer", "call_local", "reliable")
func _rpc_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	_server_ready(_get_rpc_sender(), ready)


@rpc("any_peer", "call_local", "reliable")
func _rpc_add_ai(master_id: String, class_id: int, roll_mode: int) -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_add_ai(master_id, class_id, roll_mode)


@rpc("any_peer", "call_local", "reliable")
func _rpc_remove_ai() -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_remove_ai()


@rpc("any_peer", "call_local", "reliable")
func _rpc_fill_ai() -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_fill_ai()


@rpc("any_peer", "call_local", "reliable")
func _rpc_shuffle_factions() -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_shuffle_factions()


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_auto_fill(enabled: bool) -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_set_auto_fill(enabled)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_spectator(enabled: bool) -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_set_spectator(enabled)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_mode(new_mode: int) -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_set_mode(new_mode)


@rpc("any_peer", "call_local", "reliable")
func _rpc_start_match() -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_start_match()


@rpc("authority", "call_local", "reliable")
func _rpc_begin_match(setup: Dictionary) -> void:
	_arena_setup = setup
	match_started = true
	lobby_active = false
	_arena_ready_peers.clear()
	_change_scene(ARENA_SCENE)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_arena_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	_arena_ready_peers[sender] = true
	arena_ready.emit(sender)


# --- Server lobby state -----------------------------------------------------

func _server_summon(peer_id: int, master_id: String, class_id: int, roll_mode: int) -> void:
	if not lobby_active or match_started or spectator_mode:
		return
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and draft_stage >= DraftStage.CLASS_SELECTION and entries.has(peer_id):
		return
	var master: MasterData = _resolve_master(peer_id, master_id, roll_mode)
	if master == null:
		return
	var chosen_class: int = class_id
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and draft_stage == DraftStage.MASTER_SELECTION:
		chosen_class = -1
	elif chosen_class < 0 or roll_mode == Roster.RollMode.RANDOM_SERVANT:
		chosen_class = _random_available_class(peer_id, entries.get(peer_id, {}))
	if chosen_class >= 0 and not _class_available_for(peer_id, chosen_class, entries.get(peer_id, {})):
		return

	var team: int = _assign_team(peer_id, chosen_class)
	entries[peer_id] = {
		"master_id": master.master_id,
		"master_name": master.display_name,
		"class_id": chosen_class,
		"servant_id": "",
		"servant_name": _class_placeholder(chosen_class),
		"team": team,
		"is_ai": false,
		"ready": false,
		"spectating": false,
		"eliminated": false,
	}
	_broadcast_lobby()


func _server_select_class(peer_id: int, class_id: int) -> void:
	if not entries.has(peer_id) or match_started:
		return
	if mode == MatchConfig.MatchMode.FUYUKI_FFA:
		if _class_available_for(peer_id, class_id, entries[peer_id]):
			var entry: Dictionary = entries[peer_id]
			entry["class_id"] = class_id
			entry["servant_name"] = _class_placeholder(class_id)
			entries[peer_id] = entry
			_broadcast_lobby()
		return
	if draft_stage != DraftStage.CLASS_SELECTION and draft_stage != DraftStage.READY:
		return
	var entry: Dictionary = entries[peer_id]
	if int(entry.get("team", -1)) == MatchConfig.Team.NEUTRAL:
		return
	if not STANDARD_CLASSES.has(class_id):
		return
	if _class_available_for(peer_id, class_id, entry):
		entry["class_id"] = class_id
		entry["servant_name"] = _class_placeholder(class_id)
		entries[peer_id] = entry
		_broadcast_lobby()


func _server_random_class(peer_id: int) -> void:
	if not entries.has(peer_id) or match_started:
		return
	var entry: Dictionary = entries[peer_id]
	var class_id: int = _random_available_class(peer_id, entry)
	if class_id >= 0:
		_server_select_class(peer_id, class_id)


func _server_ready(peer_id: int, ready: bool) -> void:
	if not entries.has(peer_id):
		return
	var entry: Dictionary = entries[peer_id]
	if bool(entry.get("is_ai", false)):
		return
	entry["ready"] = ready
	entries[peer_id] = entry
	_broadcast_lobby()


func _server_set_auto_fill(enabled: bool) -> void:
	if match_started:
		return
	auto_fill = enabled
	_broadcast_lobby()


func _server_set_spectator(enabled: bool) -> void:
	if match_started:
		return
	spectator_mode = enabled
	_broadcast_lobby()


func _server_set_mode(new_mode: int) -> void:
	if match_started:
		return
	if new_mode != MatchConfig.MatchMode.FUYUKI_FFA and new_mode != MatchConfig.MatchMode.APOCRYPHA_7V7:
		return
	mode = new_mode
	draft_stage = DraftStage.MASTER_SELECTION
	for key: Variant in entries.keys():
		var entry: Dictionary = entries[key]
		entry["team"] = _assign_team(int(key), int(entry.get("class_id", -1)))
		entries[key] = entry
	_broadcast_lobby()


func _server_add_ai(master_id: String, class_id: int, roll_mode: int) -> int:
	if not lobby_active or match_started:
		return 0
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and draft_stage != DraftStage.MASTER_SELECTION:
		return 0
	if spectator_mode:
		if _ai_entry_count() >= get_capacity():
			return 0
	elif entries.size() >= get_capacity():
		return 0
	var master: MasterData = _resolve_master(0, master_id, roll_mode)
	if master == null:
		return 0
	var chosen_class: int = class_id
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and draft_stage == DraftStage.MASTER_SELECTION:
		chosen_class = -1
	elif chosen_class < 0 or roll_mode == Roster.RollMode.RANDOM_SERVANT:
		chosen_class = _random_available_class(0, {})
	if chosen_class >= 0 and not _class_available_for(0, chosen_class, {}):
		return 0
	var ai_id: int = _next_ai_id
	_next_ai_id += 1
	entries[ai_id] = {
		"master_id": master.master_id,
		"master_name": master.display_name,
		"class_id": chosen_class,
		"servant_id": "",
		"servant_name": _class_placeholder(chosen_class),
		"team": _assign_team(ai_id, chosen_class),
		"is_ai": true,
		"ai_slot": _ai_entry_count() + 1,
		"ready": true,
		"spectating": false,
		"eliminated": false,
	}
	_broadcast_lobby()
	return ai_id


func _server_remove_ai() -> void:
	if match_started:
		return
	var target_id: int = 0
	var target_slot: int = -1
	for key: Variant in entries.keys():
		var entry: Dictionary = entries[key]
		if not bool(entry.get("is_ai", false)):
			continue
		var slot: int = int(entry.get("ai_slot", 0))
		if slot > target_slot:
			target_slot = slot
			target_id = int(key)
	if target_id != 0:
		entries.erase(target_id)
		_broadcast_lobby()


func _server_fill_ai() -> void:
	if match_started:
		return
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and draft_stage != DraftStage.MASTER_SELECTION:
		return
	var guard: int = 0
	while guard < get_capacity() + 2:
		guard += 1
		var before: int = _ai_entry_count() if spectator_mode else entries.size()
		_server_add_ai("", -1, Roster.RollMode.RANDOM_PAIR)
		var after: int = _ai_entry_count() if spectator_mode else entries.size()
		if after <= before:
			break


func _server_shuffle_factions() -> void:
	if match_started or mode != MatchConfig.MatchMode.APOCRYPHA_7V7:
		return
	if spectator_mode:
		while _ai_entry_count() < get_capacity():
			if _server_add_ai("", -1, Roster.RollMode.RANDOM_PAIR) == 0:
				break
	else:
		while entries.size() < get_capacity():
			if _server_add_ai("", -1, Roster.RollMode.RANDOM_PAIR) == 0:
				break
	_shuffle_factions_internal()


func _shuffle_factions_internal() -> void:
	var keys: Array = entries.keys()
	if keys.size() < get_capacity():
		return
	keys.shuffle()
	for index: int in range(keys.size()):
		var key: int = int(keys[index])
		var entry: Dictionary = entries[key]
		if index < 7:
			entry["team"] = MatchConfig.Team.RED
			entry["class_id"] = -1
		elif index < 14:
			entry["team"] = MatchConfig.Team.BLACK
			entry["class_id"] = -1
		else:
			entry["team"] = MatchConfig.Team.NEUTRAL
			entry["class_id"] = ServantData.ServantClass.RULER
			entry["servant_name"] = _class_placeholder(ServantData.ServantClass.RULER)
			entry["ready"] = true
		entries[key] = entry
	draft_stage = DraftStage.CLASS_SELECTION
	_broadcast_lobby()


func _server_start_match() -> void:
	if match_started:
		return
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7:
		if entries.size() < get_capacity():
			if spectator_mode:
				while _ai_entry_count() < get_capacity():
					if _server_add_ai("", -1, Roster.RollMode.RANDOM_PAIR) == 0:
						break
			else:
				while entries.size() < get_capacity():
					if _server_add_ai("", -1, Roster.RollMode.RANDOM_PAIR) == 0:
						break
		if draft_stage < DraftStage.CLASS_SELECTION:
			_shuffle_factions_internal()
		_prepare_apocrypha_classes()
	elif auto_fill:
		while entries.size() < get_capacity():
			if _server_add_ai("", -1, Roster.RollMode.RANDOM_PAIR) == 0:
				break
		_prepare_ffa_classes()

	if entries.is_empty():
		return
	for key: Variant in entries.keys():
		var entry: Dictionary = entries[key]
		if bool(entry.get("spectating", false)):
			entry["deployed"] = false
		else:
			entry["deployed"] = true
			entry["servant_id"] = _roll_servant_id(int(entry.get("class_id", ServantData.ServantClass.SABER)))
			entry["servant_name"] = _servant_display_name(String(entry["servant_id"]))
		entry["eliminated"] = false
		entries[key] = entry

	var setup: Dictionary = {
		"entries": entries.duplicate(true),
		"mode": mode,
		"spectator_mode": spectator_mode,
		"auto_fill": auto_fill,
	}
	_arena_setup = setup
	match_started = true
	lobby_active = false
	_arena_ready_peers.clear()
	if multiplayer.get_peers().is_empty():
		_rpc_begin_match(setup)
	else:
		_rpc_begin_match.rpc(setup)


func _prepare_apocrypha_classes() -> void:
	for team: int in [MatchConfig.Team.RED, MatchConfig.Team.BLACK]:
		var used: Array = []
		var members: Array = []
		for key: Variant in entries.keys():
			var entry: Dictionary = entries[key]
			if int(entry.get("team", -1)) != team:
				continue
			members.append(int(key))
			var class_id: int = int(entry.get("class_id", -1))
			if STANDARD_CLASSES.has(class_id) and not used.has(class_id):
				used.append(class_id)
		var available: Array = []
		for class_id: int in STANDARD_CLASSES:
			if not used.has(class_id):
				available.append(class_id)
		for key: int in members:
			var entry: Dictionary = entries[key]
			var class_id: int = int(entry.get("class_id", -1))
			if not STANDARD_CLASSES.has(class_id) or used.count(class_id) > 1:
				if available.is_empty():
					continue
				var chosen: int = int(available.pop_front())
				entry["class_id"] = chosen
				entry["servant_name"] = _class_placeholder(chosen)
				entries[key] = entry
				used.append(chosen)
	for key: Variant in entries.keys():
		var entry: Dictionary = entries[key]
		if int(entry.get("team", -1)) == MatchConfig.Team.NEUTRAL:
			entry["class_id"] = ServantData.ServantClass.RULER
			entry["servant_name"] = _class_placeholder(ServantData.ServantClass.RULER)
			entries[key] = entry


func _prepare_ffa_classes() -> void:
	for key: Variant in entries.keys():
		var entry: Dictionary = entries[key]
		var class_id: int = int(entry.get("class_id", -1))
		if class_id >= 0:
			continue
		var chosen: int = _random_available_class(int(key), entry)
		if chosen >= 0:
			entry["class_id"] = chosen
			entry["servant_name"] = _class_placeholder(chosen)
			entries[key] = entry


# --- Helpers ----------------------------------------------------------------

func _resolve_master(peer_id: int, master_id: String, roll_mode: int) -> MasterData:
	if roll_mode == Roster.RollMode.RANDOM_PAIR or master_id.is_empty():
		return _random_unclaimed_master(peer_id)
	var master: MasterData = Roster.find_master(master_id)
	if master == null:
		return null
	if _master_claimed_by_other(peer_id, master_id):
		return null
	return master


func _master_claimed_by_other(peer_id: int, master_id: String) -> bool:
	for key: Variant in entries.keys():
		if int(key) == peer_id:
			continue
		var entry: Dictionary = entries[key]
		if String(entry.get("master_id", "")) == master_id:
			return true
	return false


func _random_unclaimed_master(peer_id: int) -> MasterData:
	var claimed: Array = get_claimed_master_ids(peer_id)
	var candidates: Array[MasterData] = []
	for master: MasterData in Roster.get_masters():
		if not claimed.has(master.master_id):
			candidates.append(master)
	if candidates.is_empty():
		return null
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _assign_team(peer_id: int, class_id: int) -> int:
	if mode == MatchConfig.MatchMode.FUYUKI_FFA:
		return peer_id
	if class_id == ServantData.ServantClass.RULER:
		return MatchConfig.Team.NEUTRAL
	var team: int = int(entries.get(peer_id, {}).get("team", -1))
	if team == MatchConfig.Team.RED or team == MatchConfig.Team.BLACK or team == MatchConfig.Team.NEUTRAL:
		return team
	var red: int = 0
	var black: int = 0
	for key: Variant in entries.keys():
		if int(key) == peer_id:
			continue
		var entry: Dictionary = entries[key]
		var entry_team: int = int(entry.get("team", -1))
		if entry_team == MatchConfig.Team.RED:
			red += 1
		elif entry_team == MatchConfig.Team.BLACK:
			black += 1
	if red < 7 and red <= black:
		return MatchConfig.Team.RED
	if black < 7:
		return MatchConfig.Team.BLACK
	return MatchConfig.Team.NEUTRAL


func _class_available_for(peer_id: int, class_id: int, entry: Dictionary) -> bool:
	if class_id < 0:
		return false
	if mode == MatchConfig.MatchMode.FUYUKI_FFA:
		for key: Variant in entries.keys():
			if int(key) == peer_id:
				continue
			var other: Dictionary = entries[key]
			if int(other.get("class_id", -1)) == class_id:
				return false
		return true
	var team: int = int(entry.get("team", entries.get(peer_id, {}).get("team", -1)))
	if team == MatchConfig.Team.NEUTRAL:
		return class_id == ServantData.ServantClass.RULER
	if not STANDARD_CLASSES.has(class_id):
		return false
	return not get_team_classes(team, peer_id).has(class_id)


func _random_available_class(peer_id: int, entry: Dictionary) -> int:
	var candidates: Array = []
	for class_id: int in Roster.get_class_ids():
		if _class_available_for(peer_id, class_id, entry):
			candidates.append(class_id)
	if candidates.is_empty():
		return -1
	return int(candidates[_rng.randi_range(0, candidates.size() - 1)])


func _class_placeholder(class_id: int) -> String:
	if class_id < 0:
		return "Unknown [Class]"
	return "Unknown [%s]" % Roster.class_name_for(class_id)


func _roll_servant_id(class_id: int) -> String:
	var candidates: Array[ServantData] = Roster.get_servants_for_class(class_id)
	if candidates.is_empty():
		var all: Array[ServantData] = Roster.get_servants()
		if all.is_empty():
			return ""
		return all[_rng.randi_range(0, all.size() - 1)].servant_id
	var available: Array[ServantData] = []
	for servant: ServantData in candidates:
		if not _rolled_servant_ids.has(servant.servant_id):
			available.append(servant)
	if available.is_empty():
		available = candidates
	var chosen: ServantData = available[_rng.randi_range(0, available.size() - 1)]
	_rolled_servant_ids[chosen.servant_id] = true
	return chosen.servant_id


func _servant_display_name(servant_id: String) -> String:
	var servant: ServantData = Roster.find_servant(servant_id)
	return servant.display_name if servant != null else "Unknown Servant"


func _ai_entry_count() -> int:
	var count: int = 0
	for entry_variant: Variant in entries.values():
		var entry: Dictionary = entry_variant
		if bool(entry.get("is_ai", false)):
			count += 1
	return count


# --- Networking -------------------------------------------------------------

func _broadcast_lobby() -> void:
	if not multiplayer.is_server():
		return
	lobby_changed.emit()
	if multiplayer.get_peers().is_empty():
		_rpc_sync_lobby(entries.duplicate(true), mode, spectator_mode, auto_fill, match_started, draft_stage)
	else:
		_rpc_sync_lobby.rpc(entries.duplicate(true), mode, spectator_mode, auto_fill, match_started, draft_stage)


func _get_rpc_sender() -> int:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server() or not lobby_active:
		return
	_rpc_sync_lobby.rpc_id(peer_id, entries.duplicate(true), mode, spectator_mode, auto_fill, match_started, draft_stage)
	_broadcast_lobby()


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if match_started:
		if spectator_mode:
			return
		var entry: Dictionary = entries.get(peer_id, {})
		var was_human_player: bool = (
			not entry.is_empty()
			and not bool(entry.get("is_ai", false))
			and not bool(entry.get("spectating", false))
			and bool(entry.get("deployed", false))
			and not bool(entry.get("eliminated", false))
		)
		entries.erase(peer_id)
		if was_human_player and not _has_human_players():
			finish_match_and_reset("All human Masters disconnected. Returning to the Waiting Lobby.")
		return
	if not lobby_active:
		return
	entries.erase(peer_id)
	_broadcast_lobby()


func _on_connected_to_server() -> void:
	_pending_join = false
	lobby_active = true
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path != LOBBY_SCENE:
		_change_scene(LOBBY_SCENE)
	else:
		request_lobby_state()


func _on_connection_failed() -> void:
	_pending_join = false
	if lobby_active:
		return_to_menu("Connection failed.")


func _on_server_disconnected() -> void:
	if lobby_active or match_started:
		return_to_menu("The host closed the session.")


func _clear_state() -> void:
	entries.clear()
	match_started = false
	lobby_active = false
	spectator_mode = false
	auto_fill = true
	draft_stage = DraftStage.MASTER_SELECTION
	_arena_setup = {}
	_next_ai_id = AI_SLOT_BASE
	_arena_ready_peers.clear()
	_rolled_servant_ids.clear()
	Engine.time_scale = 1.0


func _change_scene(path: String) -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.change_scene_to_file(path)


func _parse_mode_from_cli() -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg: String in args:
		if arg.begins_with("--match-mode=") or arg.begins_with("--mode="):
			var value: String = arg.get_slice("=", 1).to_lower()
			if value.begins_with("apocrypha") or value == "7v7":
				return MatchConfig.MatchMode.APOCRYPHA_7V7
	return MatchConfig.MatchMode.FUYUKI_FFA
