extends Node2D
## Holy Grail War RTS arena.
##
## Server-authoritative match state:
##   * Summoning lobby (specific pair, random Servant, random pair, match mode)
##   * Master + Servant duo spawning with shared Mana bottlenecks
##   * Leylines, class triangle, true-name concealment, Fog of War
##   * Fuyuki FFA diplomacy and Apocrypha RED/BLACK teams
##
## Clients only select units, pan the camera, and send reliable command intents.

const ARENA_HALF_EXTENTS: Vector2 = Vector2(720.0, 400.0)
const WALL_THICKNESS: float = 40.0
const MAX_SPAWN_SLOTS: int = 15
const FUYUKI_MAX_PAIRS: int = 7
const APOCRYPHA_MAX_PAIRS: int = 15
const SERVANT_SCENE: PackedScene = preload("res://scenes/servant_controller.tscn")
const MASTER_SCENE: PackedScene = preload("res://scenes/master_controller.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const TRAP_SCENE: PackedScene = preload("res://scenes/magic_circle_trap.tscn")
const FOG_SHADER: Shader = preload("res://shaders/fog_of_war.gdshader")
const MARBLE_SHADER: Shader = preload("res://shaders/reality_marble.gdshader")
const CLOSE_DETECTION_RADIUS: float = 150.0
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

var _players_root: Node2D
var _projectiles_root: Node2D
var _traps_root: Node2D
var _servant_spawner: MultiplayerSpawner
var _master_spawner: MultiplayerSpawner
var _projectile_spawner: MultiplayerSpawner
var _trap_spawner: MultiplayerSpawner

var _leylines_root: Node2D
var _leylines: Array[LeylineNode] = []

var _hud: CanvasLayer
var _status_label: Label
var _duo_label: Label
var _roster_label: Label
var _event_label: Label
var _reality_marble_label: Label
var _reality_marble_owner_id: int = 0
var _overlay: ClassSelectOverlay
var _lobby_state: Dictionary = {}
var _next_spawn_slot: int = 0

var _match_config: MatchConfig
var _match_state: MatchState
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pending_summon: Dictionary = {}
var _pending_deploy: bool = false

var _camera: Camera2D
var _camera_initialized: bool = false
var _selected_units: Array[Node2D] = []
var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_current_world: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _selection_box_active: bool = false
var _stance_message: String = ""
var _stance_cache: Dictionary = {}
var _director: Node
var _direct_match: bool = false
var _setup_spawn_pending: bool = false
var _setup_ready_peers: Dictionary = {}
var _setup_wait_started_msec: int = 0
var _match_started: bool = false
var _match_end_pending: bool = false
var _match_end_at_msec: int = 0
var _match_end_reason: String = ""
var _spectator_mode: bool = false
var _auto_fill: bool = true
var _omniscient_view: bool = true
var _next_ai_id: int = AI_SLOT_BASE
var _ai_commanders: Dictionary = {}
var _session_ids: Dictionary = {}
var _local_session_id: String = ""
var _events: Array[String] = []
var _spectator_hud: CanvasLayer
var _spectator_panel: PanelContainer
var _fog_button: Button
var _speed_label: Label
var _reconnect_panel: PanelContainer
var _reconnect_input: LineEdit
var _tooltip: SkillTooltip
var _action_buttons: Dictionary = {}
var _class_badge: Button
var _pause_panel: PanelContainer
var _pause_button: Button

var _telegraph_layer: NpTelegraphLayer
var _minimap: TacticalMinimap
var _sigils: CommandSpellSigils
var _fog_material: ShaderMaterial
var _marble_material: ShaderMaterial
var _fog_overlay: ColorRect
var _marble_overlay: ColorRect
var _fog_strength: float = 0.9
var _marble_owner_servant: ServantController
var _marble_shock_start_msec: int = 0
var _marble_intensity: float = 0.0
var _shake_strength: float = 0.0
var _shake_until_msec: int = 0
var _shake_direction: Vector2 = Vector2.RIGHT
var _fx_layer: CanvasLayer
var _floating_texts: Array[Dictionary] = []


func _ready() -> void:
	_director = get_node_or_null("/root/MatchDirector")
	var setup: Dictionary = {}
	if _director != null:
		setup = _director.call("get_arena_setup")
	_direct_match = not setup.is_empty()

	_match_config = MatchConfig.new()
	_match_config.mode = int(setup.get("mode", _parse_mode_from_cli())) if _direct_match else _parse_mode_from_cli()
	_match_state = MatchState.new(_match_config.mode)
	_rng.randomize()

	if _direct_match:
		_lobby_state = setup.get("entries", {}).duplicate(true)
		_spectator_mode = bool(setup.get("spectator_mode", false))
		_auto_fill = bool(setup.get("auto_fill", true))
		_match_started = true

	_build_world()
	_build_multiplayer_roots()
	_build_leylines()
	_build_hud()
	if not _direct_match:
		_build_lobby()
	_build_camera()
	_build_spectator_hud()
	_build_action_bar()
	_build_pause_menu()
	_build_presentation_layers()

	if not multiplayer.peer_connected.is_connected(_on_peer_joined):
		multiplayer.peer_connected.connect(_on_peer_joined)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_left):
		multiplayer.peer_disconnected.connect(_on_peer_left)

	if _direct_match:
		_apply_direct_setup(setup)
		if not multiplayer.is_server():
			if _director != null:
				_director.call("report_arena_ready")
	elif multiplayer.is_server():
		_apply_lobby_state()
	else:
		if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
			multiplayer.connected_to_server.connect(_on_connected_to_server)
		if _is_connected_to_server():
			_rpc_request_lobby_state.rpc_id(1)

	queue_redraw()


func _apply_direct_setup(setup: Dictionary) -> void:
	_match_started = true
	if _spectator_panel != null:
		_spectator_panel.visible = _spectator_mode and _match_started
	if _fog_button != null:
		_fog_button.text = "Fog: OFF (Omniscient)" if _omniscient_view else "Fog: ON"
	if multiplayer.is_server():
		for peer_key: Variant in _lobby_state.keys():
			var entry: Dictionary = _lobby_state[peer_key]
			_match_state.assign_peer(int(peer_key), int(entry.get("team", -1)))
		_setup_spawn_pending = true
		_setup_ready_peers = {multiplayer.get_unique_id(): true}
		_setup_wait_started_msec = Time.get_ticks_msec()
		_try_spawn_setup(false)


func _spawn_setup_duos() -> void:
	for peer_key: Variant in _lobby_state.keys():
		var peer_id: int = int(peer_key)
		var entry: Dictionary = _lobby_state[peer_key]
		if bool(entry.get("spectating", false)) or bool(entry.get("eliminated", false)):
			continue
		var master: MasterData = Roster.find_master(String(entry.get("master_id", "")))
		var servant: ServantData = Roster.find_servant(String(entry.get("servant_id", "")))
		if master == null or servant == null:
			continue
		var slot: int = _next_spawn_slot
		_next_spawn_slot = (_next_spawn_slot + 1) % MAX_SPAWN_SLOTS
		var servant_position: Vector2 = _get_spawn_position(slot)
		var payload: Dictionary = {
			"id": peer_id,
			"master_id": master.master_id,
			"servant_id": servant.servant_id,
			"team": int(entry.get("team", 0)),
			"slot": slot,
			"servant_origin": servant_position,
			"master_origin": servant_position + Vector2(0.0, 42.0),
		}
		_master_spawner.spawn(payload)
		_servant_spawner.spawn(payload)
		entry["deployed"] = true
		_lobby_state[peer_id] = entry
		if bool(entry.get("is_ai", false)):
			_attach_ai(peer_id)
		else:
			_attach_ai(peer_id, false, true)
			_ensure_session(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_arena_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	_setup_ready_peers[sender] = true
	_try_spawn_setup(false)


func _try_spawn_setup(force: bool) -> void:
	if not multiplayer.is_server() or not _setup_spawn_pending:
		return
	if not force:
		for peer_id: int in multiplayer.get_peers():
			if _setup_ready_peers.has(peer_id):
				continue
			if _director != null and bool(_director.call("is_peer_arena_ready", peer_id)):
				continue
			return
	_setup_spawn_pending = false
	_spawn_setup_duos()
	_log_event("MATCH STARTED: %s" % MatchConfig.mode_name(_match_config.mode))


func _process(delta: float) -> void:
	if not is_inside_tree() or multiplayer == null:
		return
	_maybe_finish_match()
	if multiplayer.is_server() and _setup_spawn_pending:
		_try_spawn_setup(false)
		if _setup_spawn_pending and Time.get_ticks_msec() - _setup_wait_started_msec > 3000:
			_try_spawn_setup(true)
	_update_selection()
	_update_reconnect_panel()
	_update_fog_of_war()
	_update_camera(delta)
	_update_hud()
	_update_presentation(delta)
	_poll_ability_input()
	if not DisplayServer.get_name() == "headless":
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _overlay != null and _overlay.visible:
		return
	if DisplayServer.get_name() == "headless":
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_drag_start_world = get_global_mouse_position()
				_drag_current_world = _drag_start_world
				_dragging = true
				_selection_box_active = false
			elif _dragging:
				_dragging = false
				_finish_selection(mouse_event.shift_pressed)
				_selection_box_active = false
				queue_redraw()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_issue_world_command(get_global_mouse_position(), mouse_event.shift_pressed)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_camera(-0.1)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_camera(0.1)
	elif event is InputEventMouseMotion and _dragging:
		_drag_current_world = get_global_mouse_position()
		if _drag_start_world.distance_to(_drag_current_world) > 12.0:
			_selection_box_active = true
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_T:
			_cycle_stance_nearest_enemy()
		elif key_event.pressed and not key_event.echo and key_event.keycode == KEY_G:
			_cast_trump_card()


# --- Construction -----------------------------------------------------------

func _build_world() -> void:
	var bounds: Vector2 = ARENA_HALF_EXTENTS
	var outer: Vector2 = bounds + Vector2(WALL_THICKNESS, WALL_THICKNESS) * 0.5
	_add_wall("WallTop", Vector2(0.0, -outer.y), Vector2(outer.x * 2.0 + WALL_THICKNESS, WALL_THICKNESS))
	_add_wall("WallBottom", Vector2(0.0, outer.y), Vector2(outer.x * 2.0 + WALL_THICKNESS, WALL_THICKNESS))
	_add_wall("WallLeft", Vector2(-outer.x, 0.0), Vector2(WALL_THICKNESS, outer.y * 2.0))
	_add_wall("WallRight", Vector2(outer.x, 0.0), Vector2(WALL_THICKNESS, outer.y * 2.0))


func _add_wall(node_name: String, center: Vector2, size: Vector2) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = node_name
	body.position = center
	body.collision_layer = 1 << 0
	body.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	add_child(body)


func _build_multiplayer_roots() -> void:
	_players_root = Node2D.new()
	_players_root.name = "Players"
	add_child(_players_root)

	# Added before units so additive telegraphs render beneath them.
	_telegraph_layer = NpTelegraphLayer.new()
	_telegraph_layer.name = "NpTelegraphs"
	_players_root.add_child(_telegraph_layer)

	_projectiles_root = Node2D.new()
	_projectiles_root.name = "Projectiles"
	add_child(_projectiles_root)

	_traps_root = Node2D.new()
	_traps_root.name = "Traps"
	add_child(_traps_root)

	_servant_spawner = MultiplayerSpawner.new()
	_servant_spawner.name = "ServantSpawner"
	add_child(_servant_spawner)
	_servant_spawner.spawn_path = _servant_spawner.get_path_to(_players_root)
	_servant_spawner.spawn_function = _spawn_servant

	_master_spawner = MultiplayerSpawner.new()
	_master_spawner.name = "MasterSpawner"
	add_child(_master_spawner)
	_master_spawner.spawn_path = _master_spawner.get_path_to(_players_root)
	_master_spawner.spawn_function = _spawn_master

	_projectile_spawner = MultiplayerSpawner.new()
	_projectile_spawner.name = "ProjectileSpawner"
	add_child(_projectile_spawner)
	_projectile_spawner.spawn_path = _projectile_spawner.get_path_to(_projectiles_root)
	_projectile_spawner.spawn_function = _spawn_projectile

	_trap_spawner = MultiplayerSpawner.new()
	_trap_spawner.name = "TrapSpawner"
	add_child(_trap_spawner)
	_trap_spawner.spawn_path = _trap_spawner.get_path_to(_traps_root)
	_trap_spawner.spawn_function = _spawn_trap


func _build_leylines() -> void:
	_leylines_root = get_node_or_null("Leylines") as Node2D
	if _leylines_root == null:
		_leylines_root = Node2D.new()
		_leylines_root.name = "Leylines"
		add_child(_leylines_root)
	for child: Node in _leylines_root.get_children():
		var leyline: LeylineNode = child as LeylineNode
		if leyline == null:
			continue
		if not leyline.ownership_changed.is_connected(_on_leyline_ownership_changed):
			leyline.ownership_changed.connect(_on_leyline_ownership_changed.bind(leyline))
		_leylines.append(leyline)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	_hud.layer = 10
	add_child(_hud)

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 16)

	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	_class_badge = Button.new()
	_class_badge.text = "CLASS: -"
	_class_badge.flat = true
	_class_badge.focus_mode = Control.FOCUS_NONE
	_class_badge.add_theme_font_size_override("font_size", 12)
	_class_badge.add_theme_color_override("font_color", Color(0.88, 0.78, 0.5))
	_class_badge.mouse_entered.connect(_show_class_tooltip)
	_class_badge.mouse_exited.connect(_hide_tooltip)
	column.add_child(_class_badge)

	_sigils = CommandSpellSigils.new()
	_sigils.name = "CommandSpellSigils"
	column.add_child(_sigils)

	_status_label = _make_hud_label(16, Color(0.86, 0.89, 1.0))
	column.add_child(_status_label)
	_duo_label = _make_hud_label(13, Color(0.74, 0.82, 0.95))
	column.add_child(_duo_label)
	_roster_label = _make_hud_label(11, Color(0.62, 0.68, 0.82))
	column.add_child(_roster_label)
	_event_label = _make_hud_label(11, Color(0.78, 0.72, 0.5))
	_event_label.text = "EVENTS  |  no events yet"
	column.add_child(_event_label)
	_reality_marble_label = _make_hud_label(14, Color(1.0, 0.45, 0.7))
	_reality_marble_label.visible = false
	column.add_child(_reality_marble_label)
	var hint: Label = _make_hud_label(12, Color(0.58, 0.63, 0.78))
	hint.text = "LMB select / drag-box   RMB move   RMB enemy attack   Shift+RMB attack-move   Q/E skills   R NP   F Command Spell   G Trump Card   T stance   Wheel zoom   Edge pan / minimap click-pan"
	column.add_child(hint)


func _make_hud_label(font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


func _build_lobby() -> void:
	_overlay = ClassSelectOverlay.new()
	_overlay.name = "ClassSelectOverlay"
	add_child(_overlay)
	_overlay.set_local_peer_id(multiplayer.get_unique_id())
	_overlay.set_is_host(multiplayer.is_server() and multiplayer.get_unique_id() == 1)
	_overlay.set_match_mode(_match_config.mode)
	_overlay.summon_requested.connect(_on_summon_requested)
	_overlay.deploy_requested.connect(_on_deploy_requested)
	_overlay.match_mode_requested.connect(_on_match_mode_requested)
	_overlay.ai_add_requested.connect(_on_ai_add_requested)
	_overlay.ai_remove_requested.connect(_on_ai_remove_requested)
	_overlay.ai_fill_requested.connect(_on_ai_fill_requested)
	_overlay.auto_fill_toggled.connect(_on_auto_fill_toggled)
	_overlay.spectate_toggled.connect(_on_spectate_toggled)
	_overlay.start_match_requested.connect(_on_start_match_requested)
	_overlay.reclaim_requested.connect(_on_reclaim_requested)


func _build_camera() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_camera = Camera2D.new()
	_camera.name = "RTSCamera"
	_camera.zoom = Vector2(1.0, 1.0)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)
	_camera.make_current()


func _build_spectator_hud() -> void:
	_spectator_hud = CanvasLayer.new()
	_spectator_hud.name = "SpectatorHUD"
	_spectator_hud.layer = 12
	add_child(_spectator_hud)

	var root_control: Control = Control.new()
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectator_hud.add_child(root_control)
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_spectator_panel = PanelContainer.new()
	_spectator_panel.name = "SpectatorPanel"
	_spectator_panel.visible = false
	_spectator_panel.custom_minimum_size = Vector2(260.0, 150.0)
	root_control.add_child(_spectator_panel)
	_spectator_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_spectator_panel.offset_left = -292.0
	_spectator_panel.offset_top = -176.0
	_spectator_panel.offset_right = -16.0
	_spectator_panel.offset_bottom = -16.0

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.05, 0.09, 0.94)
	panel_style.border_color = Color(0.6, 0.5, 0.85, 0.8)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(12)
	_spectator_panel.add_theme_stylebox_override("panel", panel_style)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_spectator_panel.add_child(column)

	var title: Label = Label.new()
	title.text = "SPECTATOR_AI_WAR"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	column.add_child(title)

	_fog_button = Button.new()
	_fog_button.text = "Fog: OFF (Omniscient)"
	_fog_button.pressed.connect(_toggle_spectator_fog)
	column.add_child(_fog_button)

	_speed_label = Label.new()
	_speed_label.text = "Playback: 1x"
	_speed_label.add_theme_font_size_override("font_size", 11)
	_speed_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	column.add_child(_speed_label)

	var speed_row: HBoxContainer = HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	column.add_child(speed_row)
	for speed: float in [1.0, 2.0, 4.0]:
		var speed_button: Button = Button.new()
		speed_button.text = "%dx" % int(speed)
		speed_button.pressed.connect(_set_playback_speed.bind(speed))
		speed_row.add_child(speed_button)

	_reconnect_panel = PanelContainer.new()
	_reconnect_panel.name = "ReconnectPanel"
	_reconnect_panel.visible = false
	root_control.add_child(_reconnect_panel)
	_reconnect_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_reconnect_panel.offset_left = 16.0
	_reconnect_panel.offset_top = -104.0
	_reconnect_panel.offset_right = 396.0
	_reconnect_panel.offset_bottom = -16.0
	var reconnect_column: VBoxContainer = VBoxContainer.new()
	reconnect_column.add_theme_constant_override("separation", 4)
	_reconnect_panel.add_child(reconnect_column)
	var reconnect_title: Label = Label.new()
	reconnect_title.text = "RECONNECT TO AUTOPILOT SESSION"
	reconnect_title.add_theme_font_size_override("font_size", 11)
	reconnect_title.add_theme_color_override("font_color", Color(0.85, 0.82, 0.65))
	reconnect_column.add_child(reconnect_title)
	var reconnect_row: HBoxContainer = HBoxContainer.new()
	reconnect_column.add_child(reconnect_row)
	_reconnect_input = LineEdit.new()
	_reconnect_input.placeholder_text = "Session ID"
	_reconnect_input.custom_minimum_size = Vector2(250.0, 28.0)
	reconnect_row.add_child(_reconnect_input)
	var reconnect_button: Button = Button.new()
	reconnect_button.text = "RECLAIM"
	reconnect_button.pressed.connect(_on_reconnect_submit)
	reconnect_row.add_child(reconnect_button)


func _update_reconnect_panel() -> void:
	if _reconnect_panel == null:
		return
	var show: bool = _match_started \
		and not _spectator_mode \
		and get_local_master() == null \
		and get_local_servant() == null
	_reconnect_panel.visible = show
	if show and _reconnect_input != null and _reconnect_input.text.is_empty() and not _local_session_id.is_empty():
		_reconnect_input.text = _local_session_id


func _on_reconnect_submit() -> void:
	if _reconnect_input == null:
		return
	var session_id: String = _reconnect_input.text.strip_edges()
	if not session_id.is_empty():
		request_reclaim_session(session_id)


func _toggle_spectator_fog() -> void:
	_omniscient_view = not _omniscient_view
	if _fog_button != null:
		_fog_button.text = "Fog: OFF (Omniscient)" if _omniscient_view else "Fog: ON"
	_update_fog_of_war()


func _set_playback_speed(speed: float) -> void:
	Engine.time_scale = speed
	if _speed_label != null:
		_speed_label.text = "Playback: %dx" % int(speed)




func _build_action_bar() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "ActionBar"
	layer.layer = 14
	add_child(layer)
	var root_control: Control = Control.new()
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root_control)
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_END
	root_control.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bar: HBoxContainer = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bar)
	var definitions: Array = [
		["servant_1", "Q  SKILL 1"],
		["servant_2", "E  SKILL 2"],
		["noble_phantasm", "R  NOBLE PHANTASM"],
		["master_1", "MASTER Q"],
		["master_2", "MASTER E"],
		["command_spell", "F  COMMAND SPELL"],
		["trump_card", "G  TRUMP CARD"],
		["ask_name", "ASK NAME"],
		["public_reveal", "PUBLIC REVEAL"],
	]
	for definition: Array in definitions:
		var key: String = String(definition[0])
		var button: Button = Button.new()
		button.text = String(definition[1])
		button.custom_minimum_size = Vector2(118.0, 34.0)
		button.add_theme_font_size_override("font_size", 11)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_action_button.bind(key))
		button.mouse_entered.connect(_show_action_tooltip.bind(key))
		button.mouse_exited.connect(_hide_tooltip)
		bar.add_child(button)
		_action_buttons[key] = button
	column.add_child(_make_spacer(14))

	var tooltip_layer: CanvasLayer = CanvasLayer.new()
	tooltip_layer.name = "TooltipLayer"
	tooltip_layer.layer = 90
	add_child(tooltip_layer)
	_tooltip = SkillTooltip.new()
	_tooltip.name = "SkillTooltip"
	tooltip_layer.add_child(_tooltip)


func _make_spacer(height: float) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _build_pause_menu() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "PauseMenu"
	layer.layer = 16
	add_child(layer)
	var root_control: Control = Control.new()
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root_control)
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_button = Button.new()
	_pause_button.text = "MENU"
	_pause_button.custom_minimum_size = Vector2(72.0, 30.0)
	_pause_button.pressed.connect(_toggle_pause_panel)
	root_control.add_child(_pause_button)
	_pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_button.offset_left = -90.0
	_pause_button.offset_top = 14.0
	_pause_button.offset_right = -16.0
	_pause_button.offset_bottom = 44.0

	_pause_panel = PanelContainer.new()
	_pause_panel.visible = false
	root_control.add_child(_pause_panel)
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.offset_left = -180.0
	_pause_panel.offset_top = -90.0
	_pause_panel.offset_right = 180.0
	_pause_panel.offset_bottom = 90.0
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.05, 0.09, 0.98)
	panel_style.border_color = Color(0.65, 0.5, 0.85, 0.85)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(18)
	_pause_panel.add_theme_stylebox_override("panel", panel_style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(column)
	var title: Label = Label.new()
	title.text = "MATCH MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.84, 0.65))
	column.add_child(title)
	var resume: Button = Button.new()
	resume.text = "RESUME"
	resume.pressed.connect(_toggle_pause_panel)
	column.add_child(resume)
	var leave: Button = Button.new()
	leave.text = "LEAVE MATCH / RETURN TO MENU"
	leave.pressed.connect(_on_leave_match)
	column.add_child(leave)


func _build_presentation_layers() -> void:
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null:
		if not audio.is_connected("floating_text_requested", Callable(self, "_on_floating_text_requested")):
			audio.connect("floating_text_requested", Callable(self, "_on_floating_text_requested"))
		if not audio.is_connected("impact_requested", Callable(self, "_on_impact_requested")):
			audio.connect("impact_requested", Callable(self, "_on_impact_requested"))

	if DisplayServer.get_name() != "headless":
		var marble_layer: CanvasLayer = CanvasLayer.new()
		marble_layer.name = "RealityMarbleLayer"
		marble_layer.layer = 6
		add_child(marble_layer)
		_marble_overlay = ColorRect.new()
		_marble_overlay.name = "RealityMarble"
		_marble_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_marble_overlay.color = Color(1.0, 1.0, 1.0, 1.0)
		_marble_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_marble_material = ShaderMaterial.new()
		_marble_material.shader = MARBLE_SHADER
		_marble_overlay.material = _marble_material
		_marble_overlay.visible = false
		marble_layer.add_child(_marble_overlay)

		var fog_layer: CanvasLayer = CanvasLayer.new()
		fog_layer.name = "FogLayer"
		fog_layer.layer = 8
		add_child(fog_layer)
		_fog_overlay = ColorRect.new()
		_fog_overlay.name = "FogOfWar"
		_fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fog_overlay.color = Color(1.0, 1.0, 1.0, 1.0)
		_fog_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_fog_material = ShaderMaterial.new()
		_fog_material.shader = FOG_SHADER
		_fog_overlay.material = _fog_material
		_fog_overlay.visible = false
		fog_layer.add_child(_fog_overlay)

	_fx_layer = CanvasLayer.new()
	_fx_layer.name = "CombatTextLayer"
	_fx_layer.layer = 9
	add_child(_fx_layer)

	var minimap_layer: CanvasLayer = CanvasLayer.new()
	minimap_layer.name = "MinimapLayer"
	minimap_layer.layer = 13
	add_child(minimap_layer)
	var minimap_root: Control = Control.new()
	minimap_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	minimap_layer.add_child(minimap_root)
	_minimap = TacticalMinimap.new()
	_minimap.name = "TacticalMinimap"
	_minimap.arena = self
	minimap_root.add_child(_minimap)
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.offset_left = -222.0
	_minimap.offset_top = 54.0
	_minimap.offset_right = -16.0
	_minimap.offset_bottom = 196.0
	_minimap.pan_requested.connect(_on_minimap_pan_requested)


func _on_floating_text_requested(world_position: Vector2, text: String, color: Color) -> void:
	_spawn_floating_text(world_position, text, color)


func _on_impact_requested(world_position: Vector2, strength: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_shake_strength = maxf(_shake_strength, 4.0 + 18.0 * clampf(strength, 0.0, 1.0))
	_shake_until_msec = Time.get_ticks_msec() + 360
	if _camera != null:
		var away: Vector2 = world_position - _camera.position
		if away.length_squared() > 0.01:
			_shake_direction = away.normalized()


func _on_minimap_pan_requested(world_position: Vector2) -> void:
	if _camera == null:
		return
	_camera.position = Vector2(
		clampf(world_position.x, -ARENA_HALF_EXTENTS.x, ARENA_HALF_EXTENTS.x),
		clampf(world_position.y, -ARENA_HALF_EXTENTS.y, ARENA_HALF_EXTENTS.y)
	)
	_camera_initialized = true


func _spawn_floating_text(world_position: Vector2, text: String, color: Color) -> void:
	if _fx_layer == null or DisplayServer.get_name() == "headless":
		return
	if not _spectator_mode and not _is_world_point_near_own_vision(world_position):
		return
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	label.size = Vector2(260.0, 20.0)
	_fx_layer.add_child(label)
	_floating_texts.append({
		"label": label,
		"world_position": world_position,
		"age": 0.0,
		"life": 1.05,
	})


func _is_world_point_near_own_vision(world_position: Vector2) -> bool:
	if _spectator_mode:
		return true
	for unit: Node2D in _own_units():
		if not bool(unit.get("is_alive")):
			continue
		var vision: float = float(unit.get("vision_radius")) + 140.0
		if unit.global_position.distance_to(world_position) <= vision:
			return true
	return false


func _update_floating_texts(delta: float) -> void:
	if _floating_texts.is_empty():
		return
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var index: int = _floating_texts.size() - 1
	while index >= 0:
		var entry: Dictionary = _floating_texts[index]
		var age: float = float(entry["age"]) + delta
		entry["age"] = age
		var label: Label = entry["label"] as Label
		var life: float = float(entry["life"])
		if label == null or not is_instance_valid(label) or age >= life:
			if label != null and is_instance_valid(label):
				label.queue_free()
			_floating_texts.remove_at(index)
			index -= 1
			continue
		var screen: Vector2 = canvas_transform * (entry["world_position"] as Vector2)
		label.position = screen + Vector2(-130.0, -34.0 - age * 42.0)
		var fade: float = 1.0 - age / life
		label.modulate = Color(1.0, 1.0, 1.0, clampf(fade, 0.0, 1.0))
		index -= 1


func _update_presentation(delta: float) -> void:
	_update_floating_texts(delta)
	if DisplayServer.get_name() == "headless":
		return
	_update_fog_overlay()
	_update_marble_overlay(delta)


func _update_fog_overlay() -> void:
	if _fog_overlay == null or _fog_material == null:
		return
	var reveal_all: bool = _spectator_mode and _omniscient_view
	if not _match_started or reveal_all:
		_fog_overlay.visible = false
		return
	var source_units: Array[Node2D] = _all_player_units() if _spectator_mode else _own_units()
	var positions: PackedVector2Array = PackedVector2Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	positions.resize(24)
	radii.resize(24)
	var count: int = 0
	for unit: Node2D in source_units:
		if count >= 24:
			break
		if not bool(unit.get("is_alive")):
			continue
		positions[count] = unit.global_position
		radii[count] = maxf(float(unit.get("vision_radius")), 60.0)
		count += 1
	var stealth_positions: PackedVector2Array = PackedVector2Array()
	stealth_positions.resize(8)
	var stealth_count: int = 0
	for unit: Node2D in _own_units():
		if stealth_count >= 8:
			break
		var servant: ServantController = unit as ServantController
		if servant == null or not servant.is_alive or not servant.is_stealthed:
			continue
		stealth_positions[stealth_count] = servant.global_position
		stealth_count += 1
	var view_rect: Rect2 = get_camera_view_rect()
	_fog_material.set_shader_parameter("view_origin", view_rect.position)
	_fog_material.set_shader_parameter("view_size", view_rect.size)
	_fog_material.set_shader_parameter("light_positions", positions)
	_fog_material.set_shader_parameter("light_radii", radii)
	_fog_material.set_shader_parameter("light_count", count)
	_fog_material.set_shader_parameter("stealth_positions", stealth_positions)
	_fog_material.set_shader_parameter("stealth_count", stealth_count)
	_fog_material.set_shader_parameter("fog_strength", _fog_strength)
	_fog_overlay.visible = true


func _update_marble_overlay(delta: float) -> void:
	if _marble_overlay == null or _marble_material == null:
		return
	var target: float = 1.0 if _reality_marble_owner_id != 0 else 0.0
	_marble_intensity = move_toward(_marble_intensity, target, delta * 2.4)
	if _marble_intensity <= 0.01:
		_marble_overlay.visible = false
		return
	_marble_overlay.visible = true
	var center: Vector2 = Vector2.ZERO
	var tint: Color = Color(0.9, 0.22, 0.52)
	var owner_servant: ServantController = _get_servant(_reality_marble_owner_id)
	if owner_servant != null and owner_servant.servant_data != null:
		center = owner_servant.global_position
		tint = owner_servant.servant_data.noble_phantasm_color
	var progress: float = 1.0
	if _marble_shock_start_msec > 0:
		progress = clampf(float(Time.get_ticks_msec() - _marble_shock_start_msec) / 1300.0, 0.0, 1.0)
	var view_rect: Rect2 = get_camera_view_rect()
	_marble_material.set_shader_parameter("view_origin", view_rect.position)
	_marble_material.set_shader_parameter("view_size", view_rect.size)
	_marble_material.set_shader_parameter("marble_center", center)
	_marble_material.set_shader_parameter("shock_progress", progress)
	_marble_material.set_shader_parameter("intensity", _marble_intensity)
	_marble_material.set_shader_parameter("tint", tint)


func get_camera_view_rect() -> Rect2:
	if _camera == null:
		return Rect2(-ARENA_HALF_EXTENTS, ARENA_HALF_EXTENTS * 2.0)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom_value: float = maxf(_camera.zoom.x, 0.01)
	var world_size: Vector2 = viewport_size / zoom_value
	var center: Vector2 = _camera.get_screen_center_position()
	return Rect2(center - world_size * 0.5, world_size)


func get_minimap_snapshot() -> Dictionary:
	var local_id: int = multiplayer.get_unique_id()
	var local_team: int = _local_team_id()
	var unit_entries: Array = []
	for unit: Node2D in _all_player_units():
		if not bool(unit.get("is_alive")):
			continue
		var owner_id: int = int(unit.get("owner_id"))
		var relation: String = "enemy"
		if owner_id == local_id:
			relation = "own"
		elif _match_config.mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and int(unit.get("team_id")) == local_team:
			relation = "ally"
		elif _match_config.mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and int(unit.get("team_id")) == MatchConfig.Team.NEUTRAL:
			relation = "neutral"
		var servant: ServantController = unit as ServantController
		unit_entries.append({
			"position": unit.global_position,
			"relation": relation,
			"is_servant": servant != null,
			"visible": true if _spectator_mode else unit.visible,
			"stealthed": servant != null and servant.is_stealthed,
		})
	var leyline_entries: Array = []
	for leyline: LeylineNode in _leylines:
		if leyline == null:
			continue
		leyline_entries.append({
			"position": leyline.global_position,
			"owner": leyline.owner_peer_id,
		})
	return {
		"bounds_min": -ARENA_HALF_EXTENTS,
		"bounds_max": ARENA_HALF_EXTENTS,
		"units": unit_entries,
		"leylines": leyline_entries,
		"camera_rect": get_camera_view_rect(),
	}


func _toggle_pause_panel() -> void:
	if _pause_panel != null:
		_pause_panel.visible = not _pause_panel.visible


func _on_leave_match() -> void:
	if _director != null:
		_director.call("leave_match")
		return
	var network: Node = get_node_or_null("/root/NetworkManager")
	if network != null:
		network.call("disconnect_from_match")
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.hide_tooltip()


func _show_action_tooltip(key: String) -> void:
	if _tooltip == null:
		return
	var servant: ServantController = get_local_servant()
	var master: MasterController = get_local_master()
	match key:
		"servant_1", "servant_2":
			if servant == null or servant.servant_data == null:
				_hide_tooltip()
				return
			if not servant.is_name_known_to_master:
				_tooltip.show_text("SEALED SERVANT ABILITY", "The Servant's abilities are sealed behind its unknown identity. Use ASK NAME or a Command Spell to learn its True Name and unlock manual command.", "Class: %s" % servant.servant_data.get_class_name_text())
				return
			var slot: int = 0 if key == "servant_1" else 1
			var title: String = String(servant.servant_data.active_skills[slot]) if servant.servant_data.active_skills.size() > slot else "Servant Skill %d" % (slot + 1)
			var desc: String = servant.servant_data.skill_1_desc if slot == 0 else servant.servant_data.skill_2_desc
			var cost: float = servant.servant_data.skill_1_cost if slot == 0 else servant.servant_data.skill_2_cost
			var cooldown: float = servant.servant_data.skill_1_cooldown if slot == 0 else servant.servant_data.skill_2_cooldown
			_tooltip.show_skill(title, desc, cost, cooldown, "Servant ability  |  Class: %s" % servant.servant_data.get_class_name_text())
		"noble_phantasm":
			if servant == null or servant.servant_data == null:
				_hide_tooltip()
				return
			if not servant.is_name_known_to_master:
				_tooltip.show_text("SEALED NOBLE PHANTASM", "The Noble Phantasm is unknown until the Servant's True Name is learned.", "Class: %s" % servant.servant_data.get_class_name_text())
				return
			_tooltip.show_skill(servant.servant_data.noble_phantasm_name, servant.servant_data.noble_phantasm_desc, servant.servant_data.noble_phantasm_cost, 1.0, "Noble Phantasm  |  Reveals true name on use")
		"master_1", "master_2":
			if master == null or master.master_data == null:
				_hide_tooltip()
				return
			var slot: int = 0 if key == "master_1" else 1
			var title: String = master.master_data.skill_1_name if slot == 0 else master.master_data.skill_2_name
			var desc: String = master.master_data.skill_1_desc if slot == 0 else master.master_data.skill_2_desc
			var cost: float = master.master_data.skill_1_cost if slot == 0 else master.master_data.skill_2_cost
			var cooldown: float = master.master_data.skill_1_cooldown if slot == 0 else master.master_data.skill_2_cooldown
			_tooltip.show_skill(title, desc, cost, cooldown, "Master Magecraft  |  %s" % master.master_data.display_name)
		"command_spell":
			if master == null or master.master_data == null:
				_hide_tooltip()
				return
			if not master.signature_command_spell_used:
				_tooltip.show_text("SIGNATURE COMMAND SPELL: %s" % master.master_data.signature_command_spell, master.master_data.signature_command_spell_desc, "SLOT 1 OF 3   |   CHARGES %d/3   |   KEY F" % master.command_spells_left)
			else:
				_tooltip.show_text("TACTICAL WARP / EMERGENCY SURGE", master.master_data.command_spell_desc, "STANDARD COMMAND SPELL   |   CHARGES %d/3   |   KEY F" % master.command_spells_left)
		"trump_card":
			if master == null or master.master_data == null:
				_hide_tooltip()
				return
			var ready_text: String = "READY" if master.trump_card_ready else "RECHARGING"
			_tooltip.show_skill(master.master_data.master_trump_card, master.master_data.trump_card_desc, master.master_data.trump_card_mana_cost, master.master_data.trump_card_cooldown, "MASTER TRUMP CARD  |  %s" % ready_text)
		"ask_name":
			if servant == null or servant.servant_data == null:
				_hide_tooltip()
				return
			if servant.is_name_known_to_master:
				_tooltip.show_text("TRUE NAME KNOWN", "You already know this Servant's True Name. Manual RTS control and the full skill glossary are unlocked.", "Do not reveal it publicly without accepting the +15% Fame buff tradeoff.")
			else:
				_tooltip.show_text("ASK SERVANT'S NAME", "Spend the Master interaction to learn the Servant's True Name. This unlocks manual RTS control and the full ability glossary.", "The Servant remains autonomous until you ask or use a Command Spell.")
		"public_reveal":
			if servant == null or servant.servant_data == null:
				_hide_tooltip()
				return
			if not servant.is_name_known_to_master:
				_tooltip.show_text("PUBLIC REVEAL LOCKED", "Learn the Servant's True Name before publicly revealing it.", "")
			elif servant.is_true_name_revealed:
				_tooltip.show_text("TRUE NAME ALREADY PUBLIC", "The Servant's identity is already known to all enemies.", "Fame / Morale buff is active or expired.")
			else:
				_tooltip.show_text("PUBLICLY REVEAL TRUE NAME", "Broadcast the Servant's identity to all enemies. In exchange, the Servant gains a +15% Fame / Morale combat buff for 30 seconds.", "One-time public reveal.")


func _on_action_button(key: String) -> void:
	match key:
		"servant_1":
			_cast_local_servant_skill(0)
		"servant_2":
			_cast_local_servant_skill(1)
		"noble_phantasm":
			_cast_noble_phantasm()
		"master_1":
			_cast_local_master_skill(0)
		"master_2":
			_cast_local_master_skill(1)
		"command_spell":
			_cast_command_spell()
		"trump_card":
			_cast_trump_card()
		"ask_name":
			_ask_servant_name()
		"public_reveal":
			_publicly_reveal_name()


func _cast_trump_card() -> void:
	var master: MasterController = get_local_master()
	if master == null:
		return
	var direction: Vector2 = (get_global_mouse_position() - master.global_position).normalized()
	if multiplayer.is_server():
		master.call("_rpc_use_trump_card", direction)
	else:
		master.rpc_id(1, "_rpc_use_trump_card", direction)


func _ask_servant_name() -> void:
	var servant: ServantController = get_local_servant()
	if servant == null:
		return
	if multiplayer.is_server():
		servant.call("_rpc_ask_servant_name")
	else:
		servant.rpc_id(1, "_rpc_ask_servant_name")


func _publicly_reveal_name() -> void:
	var servant: ServantController = get_local_servant()
	if servant == null:
		return
	if multiplayer.is_server():
		servant.call("_rpc_publicly_reveal_name")
	else:
		servant.rpc_id(1, "_rpc_publicly_reveal_name")


func _cast_local_servant_skill(slot: int) -> void:
	var servant: ServantController = get_local_servant()
	if servant == null:
		return
	var direction: Vector2 = (get_global_mouse_position() - servant.global_position).normalized()
	if multiplayer.is_server():
		servant.call("_rpc_use_skill", slot, direction)
	else:
		servant.rpc_id(1, "_rpc_use_skill", slot, direction)


func _cast_local_master_skill(slot: int) -> void:
	var master: MasterController = get_local_master()
	if master == null:
		return
	var direction: Vector2 = (get_global_mouse_position() - master.global_position).normalized()
	if multiplayer.is_server():
		master.call("_rpc_use_skill", slot, direction)
	else:
		master.rpc_id(1, "_rpc_use_skill", slot, direction)


func _show_class_tooltip() -> void:
	if _tooltip == null:
		return
	var servant: ServantController = get_local_servant()
	if servant == null or servant.servant_data == null:
		_hide_tooltip()
		return
	var class_id: int = servant.servant_data.servant_class
	var lines: PackedStringArray = PackedStringArray()
	for target_class: int in Roster.get_class_ids():
		if target_class == class_id:
			continue
		var multiplier: float = ClassTriangle.get_total_multiplier(class_id, target_class)
		if multiplier > 1.01:
			lines.append("Strong vs %s  %.2fx" % [Roster.class_name_for(target_class), multiplier])
		elif multiplier < 0.99:
			lines.append("Weak vs %s  %.2fx" % [Roster.class_name_for(target_class), multiplier])
	if lines.is_empty():
		lines.append("Neutral against all standard classes.")
	_tooltip.show_text("CLASS TRIANGLE - %s" % Roster.class_name_for(class_id).to_upper(), "\n".join(lines), "Knight: Saber > Lancer > Archer > Saber. Cavalry: Rider > Caster > Assassin > Rider. Berserker 1.5x dealt/taken. Ruler 0.75x taken from standard classes, 1.5x from Avenger.")


func _update_action_buttons() -> void:
	if _action_buttons.is_empty():
		return
	var servant: ServantController = get_local_servant()
	var master: MasterController = get_local_master()
	var servant_alive: bool = servant != null and servant.is_alive
	var master_alive: bool = master != null and master.is_alive
	if servant_alive and servant.servant_data != null:
		if servant.is_name_known_to_master:
			var skills: PackedStringArray = servant.servant_data.active_skills
			var skill_1_name: String = String(skills[0]) if skills.size() > 0 else "Skill 1"
			var skill_2_name: String = String(skills[1]) if skills.size() > 1 else "Skill 2"
			_action_buttons["servant_1"].text = "Q  %s" % skill_1_name
			_action_buttons["servant_2"].text = "E  %s" % skill_2_name
			_action_buttons["noble_phantasm"].text = "R  %s" % servant.servant_data.noble_phantasm_name
		else:
			_action_buttons["servant_1"].text = "Q  SEALED"
			_action_buttons["servant_2"].text = "E  SEALED"
			_action_buttons["noble_phantasm"].text = "R  SEALED"
		_action_buttons["servant_1"].disabled = not servant.is_name_known_to_master
		_action_buttons["servant_2"].disabled = not servant.is_name_known_to_master
		_action_buttons["noble_phantasm"].disabled = not servant.is_name_known_to_master
		_action_buttons["ask_name"].disabled = servant.is_name_known_to_master
		_action_buttons["public_reveal"].disabled = (not servant.is_name_known_to_master) or servant.is_true_name_revealed
		_class_badge.text = "CLASS: %s" % servant.servant_data.get_class_name_text().to_upper()
	else:
		_action_buttons["servant_1"].disabled = true
		_action_buttons["servant_2"].disabled = true
		_action_buttons["noble_phantasm"].disabled = true
		_action_buttons["ask_name"].disabled = true
		_action_buttons["public_reveal"].disabled = true
		_class_badge.text = "CLASS: -"
	if master_alive and master.master_data != null:
		_action_buttons["master_1"].text = "M-Q  %s" % master.master_data.skill_1_name
		_action_buttons["master_2"].text = "M-E  %s" % master.master_data.skill_2_name
		_action_buttons["command_spell"].text = "F  CS %d/3" % master.command_spells_left
		_action_buttons["trump_card"].text = "G  %s" % master.master_data.master_trump_card
		_action_buttons["trump_card"].disabled = not master.trump_card_ready
		_action_buttons["master_1"].disabled = false
		_action_buttons["master_2"].disabled = false
		_action_buttons["command_spell"].disabled = master.command_spells_left <= 0
	else:
		_action_buttons["master_1"].disabled = true
		_action_buttons["master_2"].disabled = true
		_action_buttons["command_spell"].disabled = true
		_action_buttons["trump_card"].disabled = true


# --- Public match API -------------------------------------------------------

func get_lobby_state() -> Dictionary:
	return _lobby_state.duplicate(true)


func get_match_state() -> MatchState:
	return _match_state


func get_match_mode() -> int:
	return _match_config.mode


func get_leylines() -> Array[LeylineNode]:
	return _leylines.duplicate()


func get_local_servant() -> ServantController:
	return _get_servant(multiplayer.get_unique_id())


func get_local_master() -> MasterController:
	return _get_master(multiplayer.get_unique_id())


func get_selected_units() -> Array[Node2D]:
	return _selected_units.duplicate()


func request_summon(master_id: String, class_id: int, roll_mode: int) -> void:
	if multiplayer.is_server():
		_server_summon(multiplayer.get_unique_id(), master_id, class_id, roll_mode)
	elif not _is_connected_to_server():
		_pending_summon = {"master_id": master_id, "class_id": class_id, "roll_mode": roll_mode}
	else:
		_rpc_summon.rpc_id(1, master_id, class_id, roll_mode)


func request_deploy() -> void:
	if multiplayer.is_server():
		_server_deploy(multiplayer.get_unique_id())
	elif not _is_connected_to_server():
		_pending_deploy = true
	else:
		_rpc_deploy.rpc_id(1)


func request_match_mode(mode: int) -> void:
	if not multiplayer.is_server():
		_rpc_set_match_mode.rpc_id(1, mode)
		return
	_server_set_match_mode(mode)


func request_stance(target_peer: int, stance: int) -> void:
	if multiplayer.is_server():
		_server_set_stance(multiplayer.get_unique_id(), target_peer, stance)
	else:
		_rpc_set_stance.rpc_id(1, target_peer, stance)


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


func request_auto_fill(enabled: bool) -> void:
	if multiplayer.is_server():
		_server_set_auto_fill(enabled)
	else:
		_rpc_set_auto_fill.rpc_id(1, enabled)


func request_spectator_mode(enabled: bool) -> void:
	if multiplayer.is_server():
		_server_set_spectator_mode(enabled)
	else:
		_rpc_set_spectator_mode.rpc_id(1, enabled)


func request_start_match() -> void:
	if multiplayer.is_server():
		_server_start_match()
	else:
		_rpc_start_match.rpc_id(1)


func request_reclaim_session(session_id: String) -> void:
	if multiplayer.is_server():
		_server_reclaim_session(multiplayer.get_unique_id(), session_id)
	else:
		_rpc_reclaim_session.rpc_id(1, session_id)


func get_local_session_id() -> String:
	return _local_session_id


func get_session_id(peer_id: int) -> String:
	return String(_session_ids.get(peer_id, ""))


func is_match_started() -> bool:
	return _match_started


func is_spectator_mode() -> bool:
	return _spectator_mode


func get_events() -> Array[String]:
	return _events.duplicate()


func has_ai_commander(peer_id: int) -> bool:
	return _ai_commanders.has(peer_id)


func get_ai_slot_count() -> int:
	return _ai_entry_count()


# --- Lobby RPCs -------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _rpc_summon(master_id: String, class_id: int, roll_mode: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = _get_rpc_sender()
	if sender == 0:
		return
	_server_summon(sender, master_id, class_id, roll_mode)


@rpc("any_peer", "call_local", "reliable")
func _rpc_deploy() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = _get_rpc_sender()
	if sender == 0:
		return
	_server_deploy(sender)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_match_mode(mode: int) -> void:
	if not multiplayer.is_server():
		return
	if _get_rpc_sender() != 1:
		return
	_server_set_match_mode(mode)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_stance(target_peer: int, stance: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = _get_rpc_sender()
	if sender == 0:
		return
	_server_set_stance(sender, target_peer, stance)


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
func _rpc_set_auto_fill(enabled: bool) -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_set_auto_fill(enabled)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_spectator_mode(enabled: bool) -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_set_spectator_mode(enabled)


@rpc("any_peer", "call_local", "reliable")
func _rpc_start_match() -> void:
	if not multiplayer.is_server() or _get_rpc_sender() != 1:
		return
	_server_start_match()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_reclaim_session(session_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	_server_reclaim_session(sender, session_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_session_assigned(session_id: String) -> void:
	_local_session_id = session_id
	if _overlay != null:
		_overlay.set_session_id(session_id)
	if _reconnect_input != null and _reconnect_input.text.is_empty():
		_reconnect_input.text = session_id


@rpc("authority", "call_local", "reliable")
func _rpc_log_event(message: String) -> void:
	_events.append(message)
	while _events.size() > 10:
		_events.pop_front()
	if _event_label != null:
		var first_visible: int = maxi(_events.size() - 4, 0)
		var recent: Array[String] = []
		for index: int in range(first_visible, _events.size()):
			recent.append(_events[index])
		_event_label.text = "EVENTS  |  " + "   |   ".join(recent)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_lobby_state() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	_rpc_sync_lobby.rpc_id(
		sender,
		_lobby_state.duplicate(true),
		_match_config.mode,
		_spectator_mode,
		_auto_fill,
		_match_started
	)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_lobby(state: Dictionary, mode: int, spectator: bool, auto_fill: bool, started: bool) -> void:
	_lobby_state = state
	_match_config.mode = mode
	_spectator_mode = spectator
	_auto_fill = auto_fill
	_match_started = started
	if _match_state == null:
		_match_state = MatchState.new(mode)
	_apply_lobby_state()


@rpc("authority", "call_local", "reliable")
func _rpc_stance_changed(attacker: int, defender: int, stance: int) -> void:
	if attacker == multiplayer.get_unique_id():
		_stance_cache[defender] = stance
	_stance_message = "P%d vs P%d: %s" % [attacker, defender, MatchConfig.stance_name(stance)]


func _get_rpc_sender() -> int:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender


func _server_summon(peer_id: int, master_id: String, class_id: int, roll_mode: int) -> void:
	if _match_started or _spectator_mode:
		return
	var existing: Dictionary = _lobby_state.get(peer_id, {})
	if bool(existing.get("deployed", false)):
		return
	if existing.is_empty() and _lobby_state.size() >= _pair_cap():
		return

	# Global unique Master lock: claimed names are never rolled or accepted twice.
	var master: MasterData = null
	if not master_id.is_empty() and roll_mode != Roster.RollMode.RANDOM_PAIR:
		master = Roster.find_master(master_id)
		if master != null and _master_claimed_by_other(peer_id, master.master_id):
			return
	if master == null:
		master = _random_unclaimed_master(peer_id)
	if master == null:
		return

	# Class-only summoning: the named Heroic Spirit is always rolled by the server.
	var chosen_class: int = class_id
	if roll_mode == Roster.RollMode.RANDOM_SERVANT or roll_mode == Roster.RollMode.RANDOM_PAIR:
		chosen_class = _random_available_class(peer_id)
	if chosen_class >= 0 and not _class_available_for(peer_id, chosen_class):
		return
	var servant: ServantData = _roll_servant_for_class(chosen_class, peer_id)
	if servant == null:
		return

	_lobby_state[peer_id] = {
		"master_id": master.master_id,
		"master_name": master.display_name,
		"servant_id": servant.servant_id,
		"servant_name": servant.display_name,
		"class_id": servant.servant_class,
		"team": -1,
		"preferred_team": -1,
		"deployed": false,
		"eliminated": false,
		"is_ai": false,
		"ai_takeover": false,
		"spectating": false,
	}
	_ensure_session(peer_id)
	_broadcast_lobby_state()


func _server_deploy(peer_id: int) -> void:
	if _match_started:
		return
	var entry: Dictionary = _lobby_state.get(peer_id, {})
	if entry.is_empty() or bool(entry.get("deployed", false)):
		return
	if _spectator_mode and not bool(entry.get("is_ai", false)):
		return
	if _deployed_pair_count() >= _pair_cap():
		return
	var master: MasterData = Roster.find_master(String(entry.get("master_id", "")))
	var servant: ServantData = Roster.find_servant(String(entry.get("servant_id", "")))
	if master == null or servant == null:
		return

	if not bool(entry.get("is_ai", false)):
		_ensure_session(peer_id)

	var preferred_team: int = int(entry.get("preferred_team", -1))
	var team: int = _assign_team(peer_id, servant.servant_class, preferred_team)
	entry["team"] = team
	entry["deployed"] = true
	entry["eliminated"] = false
	_lobby_state[peer_id] = entry

	var slot: int = _next_spawn_slot
	_next_spawn_slot = (_next_spawn_slot + 1) % MAX_SPAWN_SLOTS
	var servant_position: Vector2 = _get_spawn_position(slot)
	var payload: Dictionary = {
		"id": peer_id,
		"master_id": master.master_id,
		"servant_id": servant.servant_id,
		"team": team,
		"slot": slot,
		"servant_origin": servant_position,
		"master_origin": servant_position + Vector2(0.0, 42.0),
	}
	_master_spawner.spawn(payload)
	_servant_spawner.spawn(payload)
	if bool(entry.get("is_ai", false)):
		_attach_ai(peer_id)
	_broadcast_lobby_state()


func _assign_team(peer_id: int, servant_class: int, preferred_team: int = -1) -> int:
	if _match_config.mode == MatchConfig.MatchMode.FUYUKI_FFA:
		return _match_state.assign_peer(peer_id)
	if preferred_team >= 0:
		return _match_state.assign_peer(peer_id, preferred_team)
	if _match_config.allow_ruler_arbiter and servant_class == ServantData.ServantClass.RULER:
		return _match_state.assign_peer(peer_id, MatchConfig.Team.NEUTRAL)
	return _match_state.assign_peer(peer_id)


func _pair_cap() -> int:
	return FUYUKI_MAX_PAIRS if _match_config.mode == MatchConfig.MatchMode.FUYUKI_FFA else APOCRYPHA_MAX_PAIRS


func _deployed_pair_count() -> int:
	var count: int = 0
	for entry_variant: Variant in _lobby_state.values():
		var entry: Dictionary = entry_variant
		if bool(entry.get("deployed", false)) and not bool(entry.get("eliminated", false)):
			count += 1
	return count


func _neutral_entry_count() -> int:
	var count: int = 0
	for entry_variant: Variant in _lobby_state.values():
		var entry: Dictionary = entry_variant
		var team: int = int(entry.get("team", -1))
		if team < 0:
			team = int(entry.get("preferred_team", -1))
		if team == MatchConfig.Team.NEUTRAL:
			count += 1
	return count


func _ai_entry_count() -> int:
	var count: int = 0
	for entry_variant: Variant in _lobby_state.values():
		var entry: Dictionary = entry_variant
		if bool(entry.get("is_ai", false)):
			count += 1
	return count


func _next_ai_team() -> int:
	if _match_config.mode == MatchConfig.MatchMode.FUYUKI_FFA:
		return -1
	var red_count: int = 0
	var black_count: int = 0
	for entry_variant: Variant in _lobby_state.values():
		var entry: Dictionary = entry_variant
		var team: int = int(entry.get("team", -1))
		if team < 0:
			team = int(entry.get("preferred_team", -1))
		if team == MatchConfig.Team.RED:
			red_count += 1
		elif team == MatchConfig.Team.BLACK:
			black_count += 1
	return MatchConfig.Team.RED if red_count <= black_count else MatchConfig.Team.BLACK


func _master_claimed_by_other(peer_id: int, master_id: String) -> bool:
	for key: Variant in _lobby_state.keys():
		if int(key) == peer_id:
			continue
		var entry: Dictionary = _lobby_state[key]
		if String(entry.get("master_id", "")) == master_id:
			return true
	return false


func _servant_claimed_by_other(peer_id: int, servant_id: String) -> bool:
	for key: Variant in _lobby_state.keys():
		if int(key) == peer_id:
			continue
		var entry: Dictionary = _lobby_state[key]
		if String(entry.get("servant_id", "")) == servant_id:
			return true
	return false


func _random_unclaimed_master(peer_id: int) -> MasterData:
	var candidates: Array[MasterData] = []
	for master: MasterData in Roster.get_masters():
		if not _master_claimed_by_other(peer_id, master.master_id):
			candidates.append(master)
	if candidates.is_empty():
		return null
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _prospective_team(peer_id: int, class_id: int) -> int:
	if _match_config.mode == MatchConfig.MatchMode.FUYUKI_FFA:
		return -1
	var entry: Dictionary = _lobby_state.get(peer_id, {})
	var team: int = int(entry.get("team", -1))
	if team < 0:
		team = int(entry.get("preferred_team", -1))
	if team >= 0:
		return team
	if class_id == ServantData.ServantClass.RULER:
		return MatchConfig.Team.NEUTRAL
	return _next_ai_team()


func _class_available_for_team(team: int, class_id: int, exclude_peer: int = 0) -> bool:
	if class_id < 0:
		return false
	if _match_config.mode == MatchConfig.MatchMode.FUYUKI_FFA:
		for key: Variant in _lobby_state.keys():
			if int(key) == exclude_peer:
				continue
			var entry: Dictionary = _lobby_state[key]
			if int(entry.get("class_id", -1)) == class_id:
				return false
		return true
	if team == MatchConfig.Team.NEUTRAL:
		return class_id == ServantData.ServantClass.RULER
	if not STANDARD_CLASSES.has(class_id):
		return false
	return not _team_classes_in_use(team).has(class_id)


func _class_available_for(peer_id: int, class_id: int) -> bool:
	return _class_available_for_team(_prospective_team(peer_id, class_id), class_id, peer_id)


func _random_available_class(peer_id: int) -> int:
	var candidates: Array = []
	for class_id: int in Roster.get_class_ids():
		if _class_available_for(peer_id, class_id):
			candidates.append(class_id)
	if candidates.is_empty():
		return -1
	return int(candidates[_rng.randi_range(0, candidates.size() - 1)])


func _roll_servant_for_class(class_id: int, peer_id: int = 0) -> ServantData:
	if class_id < 0:
		return Roster.random_servant(_rng)
	var candidates: Array[ServantData] = Roster.get_servants_for_class(class_id)
	if candidates.is_empty():
		return Roster.random_servant(_rng)
	var available: Array[ServantData] = []
	for servant: ServantData in candidates:
		if not _servant_claimed_by_other(peer_id, servant.servant_id):
			available.append(servant)
	if available.is_empty():
		available = candidates
	return available[_rng.randi_range(0, available.size() - 1)]


func _team_classes_in_use(team: int) -> Array:
	var used: Array = []
	for entry_variant: Variant in _lobby_state.values():
		var entry: Dictionary = entry_variant
		var entry_team: int = int(entry.get("team", -1))
		if entry_team < 0:
			entry_team = int(entry.get("preferred_team", -1))
		if entry_team != team:
			continue
		var class_id: int = int(entry.get("class_id", -1))
		if class_id >= 0 and not used.has(class_id):
			used.append(class_id)
	return used


func _random_servant_for_team(team: int) -> ServantData:
	var used: Array = _team_classes_in_use(team)
	var available: Array = []
	for class_id: int in STANDARD_CLASSES:
		if not used.has(class_id):
			available.append(class_id)
	if available.is_empty():
		return Roster.random_servant(_rng)
	var class_id: int = int(available[_rng.randi_range(0, available.size() - 1)])
	var candidates: Array[ServantData] = Roster.get_servants_for_class(class_id)
	if candidates.is_empty():
		return Roster.random_servant(_rng)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _resolve_ai_loadout(master_id: String, class_id: int, roll_mode: int) -> Dictionary:
	# Global unique Master lock for AI drafts too.
	var master: MasterData = null
	if not master_id.is_empty() and roll_mode != Roster.RollMode.RANDOM_PAIR:
		master = Roster.find_master(master_id)
		if master != null and _master_claimed_by_other(0, master.master_id):
			master = null
	if master == null:
		master = _random_unclaimed_master(0)

	var preferred_team: int = -1
	if _match_config.mode == MatchConfig.MatchMode.APOCRYPHA_7V7:
		preferred_team = _next_ai_team()

	var servant: ServantData = null
	var chosen_class: int = class_id
	if roll_mode == Roster.RollMode.RANDOM_SERVANT or roll_mode == Roster.RollMode.RANDOM_PAIR:
		chosen_class = -1
	if chosen_class >= 0 and _class_available_for_team(preferred_team, chosen_class):
		servant = _roll_servant_for_class(chosen_class)
	if servant == null:
		if preferred_team >= 0:
			servant = _random_servant_for_team(preferred_team)
		else:
			var rolled_class: int = _random_available_class(0)
			servant = _roll_servant_for_class(rolled_class) if rolled_class >= 0 else Roster.random_servant(_rng)

	if master == null or servant == null:
		return {}
	return {"master": master, "servant": servant, "preferred_team": preferred_team}


func _server_add_ai(master_id: String, class_id: int, roll_mode: int) -> int:
	if _match_started:
		return 0
	if _spectator_mode:
		if _ai_entry_count() >= _pair_cap():
			return 0
	elif _lobby_state.size() >= _pair_cap():
		return 0

	var needs_arbiter: bool = _match_config.mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and _neutral_entry_count() == 0 and _lobby_state.size() == 14
	var loadout: Dictionary = {}
	if needs_arbiter:
		var arbiter_master: MasterData = null
		if not master_id.is_empty():
			arbiter_master = Roster.find_master(master_id)
			if arbiter_master != null and _master_claimed_by_other(0, arbiter_master.master_id):
				arbiter_master = null
		if arbiter_master == null:
			arbiter_master = _random_unclaimed_master(0)
		var ruler_pool: Array[ServantData] = Roster.get_servants_for_class(ServantData.ServantClass.RULER)
		var arbiter_servant: ServantData = ruler_pool[_rng.randi_range(0, ruler_pool.size() - 1)] if not ruler_pool.is_empty() else Roster.random_servant(_rng)
		if arbiter_master == null or arbiter_servant == null:
			return 0
		loadout = {"master": arbiter_master, "servant": arbiter_servant, "preferred_team": MatchConfig.Team.NEUTRAL}
	else:
		loadout = _resolve_ai_loadout(master_id, class_id, roll_mode)
	if loadout.is_empty():
		return 0
	var master: MasterData = loadout["master"]
	var servant: ServantData = loadout["servant"]
	var ai_id: int = _next_ai_id
	_next_ai_id += 1
	_lobby_state[ai_id] = {
		"master_id": master.master_id,
		"master_name": master.display_name,
		"servant_id": servant.servant_id,
		"servant_name": servant.display_name,
		"class_id": servant.servant_class,
		"team": -1,
		"preferred_team": int(loadout["preferred_team"]),
		"deployed": false,
		"eliminated": false,
		"is_ai": true,
		"ai_slot": _ai_entry_count() + 1,
		"ai_takeover": false,
		"spectating": false,
	}
	_server_deploy(ai_id)
	if _get_master(ai_id) == null and _get_servant(ai_id) == null:
		_lobby_state.erase(ai_id)
		return 0
	_attach_ai(ai_id)
	_broadcast_lobby_state()
	return ai_id


func _server_remove_ai() -> void:
	if _match_started:
		return
	var target_id: int = 0
	var target_slot: int = -1
	for peer_key: Variant in _lobby_state.keys():
		var entry: Dictionary = _lobby_state[peer_key]
		if not bool(entry.get("is_ai", false)):
			continue
		var ai_slot: int = int(entry.get("ai_slot", 0))
		if ai_slot > target_slot:
			target_slot = ai_slot
			target_id = int(peer_key)
	if target_id == 0:
		return
	_lobby_state.erase(target_id)
	_match_state.remove_peer(target_id)
	_detach_ai(target_id)
	_free_duo(target_id)
	_broadcast_lobby_state()


func _server_fill_ai() -> void:
	if _match_started:
		return
	var guard: int = 0
	var limit: int = _pair_cap() + 2
	while guard < limit:
		guard += 1
		var before: int = _ai_entry_count() if _spectator_mode else _lobby_state.size()
		var ai_id: int = _server_add_ai("", -1, Roster.RollMode.RANDOM_PAIR)
		if ai_id == 0:
			break
		var after: int = _ai_entry_count() if _spectator_mode else _lobby_state.size()
		if after <= before:
			break


func _server_set_auto_fill(enabled: bool) -> void:
	if _match_started:
		return
	_auto_fill = enabled
	_broadcast_lobby_state()


func _server_set_spectator_mode(enabled: bool) -> void:
	if _match_started:
		return
	if enabled:
		for entry_variant: Variant in _lobby_state.values():
			var entry: Dictionary = entry_variant
			if bool(entry.get("deployed", false)) and not bool(entry.get("is_ai", false)):
				return
	_spectator_mode = enabled
	if enabled:
		_omniscient_view = true
	_broadcast_lobby_state()


func _server_start_match() -> void:
	if _match_started:
		return

	if _spectator_mode:
		for peer_key: Variant in _lobby_state.keys():
			var entry: Dictionary = _lobby_state[peer_key]
			if not bool(entry.get("is_ai", false)):
				entry["spectating"] = true
				entry["deployed"] = false
				_lobby_state[peer_key] = entry
		var guard: int = 0
		while _ai_entry_count() < _pair_cap() and guard < _pair_cap() + 2:
			guard += 1
			_server_add_ai("", -1, Roster.RollMode.RANDOM_PAIR)
	else:
		for peer_key: Variant in _lobby_state.keys():
			var entry: Dictionary = _lobby_state[peer_key]
			if bool(entry.get("is_ai", false)):
				continue
			if bool(entry.get("deployed", false)) or bool(entry.get("eliminated", false)):
				continue
			if not String(entry.get("servant_id", "")).is_empty():
				_server_deploy(int(peer_key))
		if _auto_fill:
			_server_fill_ai()

	_match_started = true
	_apply_lobby_state()
	_broadcast_lobby_state()
	_log_event("MATCH STARTED: %s" % MatchConfig.mode_name(_match_config.mode))


func _attach_ai(peer_id: int, control_master: bool = true, control_servant: bool = true) -> void:
	if not multiplayer.is_server():
		return
	if _ai_commanders.has(peer_id):
		var existing: AICommander = _ai_commanders[peer_id] as AICommander
		if existing != null and is_instance_valid(existing):
			existing.control_master = control_master
			existing.control_servant = control_servant
		return
	if _get_master(peer_id) == null and _get_servant(peer_id) == null:
		return
	var commander: AICommander = AICommander.new()
	commander.name = "AICommander_%d" % peer_id
	commander.arena = self
	commander.owner_id = peer_id
	commander.control_master = control_master
	commander.control_servant = control_servant
	add_child(commander)
	_ai_commanders[peer_id] = commander


func _detach_ai(peer_id: int) -> void:
	if not _ai_commanders.has(peer_id):
		return
	var commander: Node = _ai_commanders[peer_id]
	_ai_commanders.erase(peer_id)
	if commander != null and is_instance_valid(commander):
		commander.queue_free()


func _ensure_session(peer_id: int) -> void:
	if _session_ids.has(peer_id):
		return
	var session_id: String = "S%d-%d" % [peer_id, _rng.randi_range(100000, 999999)]
	_session_ids[peer_id] = session_id
	if peer_id == multiplayer.get_unique_id():
		_rpc_session_assigned(session_id)
	elif multiplayer.get_peers().has(peer_id):
		_rpc_session_assigned.rpc_id(peer_id, session_id)


func _find_session_peer(session_id: String) -> int:
	for peer_key: Variant in _session_ids.keys():
		if String(_session_ids[peer_key]) == session_id:
			return int(peer_key)
	return 0


func _server_reclaim_session(new_peer: int, session_id: String) -> void:
	if not _match_started:
		return
	var old_peer: int = _find_session_peer(session_id)
	if old_peer == 0 or old_peer == new_peer:
		return
	if _lobby_state.has(new_peer):
		return
	var entry: Dictionary = _lobby_state.get(old_peer, {})
	if entry.is_empty() or bool(entry.get("eliminated", false)):
		return
	if not bool(entry.get("ai_takeover", false)):
		return
	var master: MasterController = _get_master(old_peer)
	var servant: ServantController = _get_servant(old_peer)
	if master == null or servant == null:
		return

	_detach_ai(old_peer)
	_lobby_state.erase(old_peer)
	entry["ai_takeover"] = false
	entry["deployed"] = true
	_lobby_state[new_peer] = entry
	_session_ids.erase(old_peer)
	_session_ids[new_peer] = session_id
	master.owner_id = new_peer
	servant.owner_id = new_peer
	_match_state.transfer_peer(old_peer, new_peer)
	if not servant.is_name_known_to_master:
		_attach_ai(new_peer, false, true)
	if new_peer == multiplayer.get_unique_id():
		_rpc_session_assigned(session_id)
	elif multiplayer.get_peers().has(new_peer):
		_rpc_session_assigned.rpc_id(new_peer, session_id)
	_broadcast_lobby_state()
	_log_event("%s reclaimed control from Autopilot" % String(entry.get("master_name", "Master")))


func _log_event(message: String) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		_rpc_log_event(message)
	else:
		_rpc_log_event.rpc(message)


func _server_set_match_mode(mode: int) -> void:
	if _match_started:
		return
	if mode != MatchConfig.MatchMode.FUYUKI_FFA and mode != MatchConfig.MatchMode.APOCRYPHA_7V7:
		return
	for entry_variant: Variant in _lobby_state.values():
		var entry: Dictionary = entry_variant
		if bool(entry.get("deployed", false)):
			return
	_match_config.mode = mode
	_match_state.set_mode(mode)
	for peer_key: Variant in _lobby_state.keys():
		var entry: Dictionary = _lobby_state[peer_key]
		entry["team"] = -1
		_lobby_state[peer_key] = entry
	_broadcast_lobby_state()


func _server_set_stance(attacker: int, defender: int, stance: int) -> void:
	if attacker == defender:
		return
	_match_state.set_stance(attacker, defender, stance)
	if multiplayer.get_peers().is_empty():
		_rpc_stance_changed(attacker, defender, stance)
	else:
		_rpc_stance_changed.rpc(attacker, defender, stance)


func _broadcast_lobby_state() -> void:
	if not multiplayer.is_server():
		return
	var snapshot: Dictionary = _lobby_state.duplicate(true)
	if multiplayer.get_peers().is_empty():
		_rpc_sync_lobby(snapshot, _match_config.mode, _spectator_mode, _auto_fill, _match_started)
	else:
		_rpc_sync_lobby.rpc(snapshot, _match_config.mode, _spectator_mode, _auto_fill, _match_started)


func _apply_lobby_state() -> void:
	if _overlay == null:
		return
	_overlay.set_match_mode(_match_config.mode)
	_overlay.set_is_host(multiplayer.get_unique_id() == 1)
	_overlay.set_spectator_mode(_spectator_mode)
	_overlay.set_auto_fill(_auto_fill)
	_overlay.set_match_started(_match_started)
	_overlay.set_lobby_state(_lobby_state)
	var local_entry: Dictionary = _lobby_state.get(multiplayer.get_unique_id(), {})
	_overlay.set_local_deployed(bool(local_entry.get("deployed", false)) or _match_started)
	if _spectator_panel != null:
		_spectator_panel.visible = _spectator_mode and _match_started
	if _fog_button != null:
		_fog_button.text = "Fog: OFF (Omniscient)" if _omniscient_view else "Fog: ON"


func _on_summon_requested(master_id: String, class_id: int, roll_mode: int) -> void:
	request_summon(master_id, class_id, roll_mode)


func _on_deploy_requested() -> void:
	request_deploy()


func _on_match_mode_requested(mode: int) -> void:
	request_match_mode(mode)


func _on_ai_add_requested(master_id: String, class_id: int, roll_mode: int) -> void:
	request_add_ai(master_id, class_id, roll_mode)


func _on_ai_remove_requested() -> void:
	request_remove_ai()


func _on_ai_fill_requested() -> void:
	request_fill_ai()


func _on_auto_fill_toggled(enabled: bool) -> void:
	request_auto_fill(enabled)


func _on_spectate_toggled(enabled: bool) -> void:
	request_spectator_mode(enabled)


func _on_start_match_requested() -> void:
	request_start_match()


func _on_reclaim_requested(session_id: String) -> void:
	request_reclaim_session(session_id)


func _on_connected_to_server() -> void:
	_rpc_request_lobby_state.rpc_id(1)
	if not _pending_summon.is_empty():
		_rpc_summon.rpc_id(
			1,
			String(_pending_summon.get("master_id", "")),
			int(_pending_summon.get("class_id", -1)),
			int(_pending_summon.get("roll_mode", Roster.RollMode.SPECIFIC))
		)
		_pending_summon.clear()
	if _pending_deploy:
		_rpc_deploy.rpc_id(1)
		_pending_deploy = false


func _is_connected_to_server() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# --- Spawning ---------------------------------------------------------------

func _spawn_servant(payload: Variant) -> Node:
	var data: Dictionary = payload
	var peer_id: int = int(data.get("id", 1))
	var servant: ServantController = SERVANT_SCENE.instantiate() as ServantController
	servant.name = _servant_node_name(peer_id)
	servant.owner_id = peer_id
	servant.team_id = int(data.get("team", 0))
	servant.spawn_slot = int(data.get("slot", 0))
	servant.position = data.get("servant_origin", Vector2.ZERO)
	servant.servant_data = Roster.find_servant(String(data.get("servant_id", "")))
	if not _direct_match:
		servant.is_name_known_to_master = true
	servant.projectile_spawner = _projectile_spawner
	servant.trap_spawner = _trap_spawner
	if multiplayer.is_server():
		servant.match_state = _match_state
	servant.reality_marble_state_changed.connect(_on_reality_marble_state_changed.bind(peer_id))
	servant.np_telegraph.connect(_on_np_telegraph)
	servant.true_name_revealed.connect(_on_servant_true_name_revealed.bind(peer_id))
	servant.name_knowledge_changed.connect(_on_servant_name_known.bind(peer_id))
	servant.died.connect(_on_servant_died.bind(peer_id))
	call_deferred("_link_units", peer_id)
	return servant


func _spawn_master(payload: Variant) -> Node:
	var data: Dictionary = payload
	var peer_id: int = int(data.get("id", 1))
	var master: MasterController = MASTER_SCENE.instantiate() as MasterController
	master.name = _master_node_name(peer_id)
	master.owner_id = peer_id
	master.team_id = int(data.get("team", 0))
	master.spawn_slot = int(data.get("slot", 0))
	master.position = data.get("master_origin", Vector2.ZERO)
	master.master_data = Roster.find_master(String(data.get("master_id", "")))
	master.projectile_spawner = _projectile_spawner
	if multiplayer.is_server():
		master.match_state = _match_state
	master.eliminated.connect(_on_master_eliminated)
	master.command_spell_used.connect(_on_master_command_spell.bind(peer_id))
	master.trump_card_used.connect(_on_trump_card_used.bind(peer_id))
	master.trump_telegraph.connect(_on_trump_telegraph)
	master.signature_decree_used.connect(_on_signature_decree_used.bind(peer_id))
	call_deferred("_link_units", peer_id)
	return master


func _link_units(peer_id: int) -> void:
	var servant: ServantController = _get_servant(peer_id)
	var master: MasterController = _get_master(peer_id)
	if servant != null and master != null:
		servant.master_unit = master
		master.servant_unit = servant


func _spawn_projectile(payload: Variant) -> Node:
	var projectile: ServantProjectile = PROJECTILE_SCENE.instantiate() as ServantProjectile
	projectile.configure(payload)
	return projectile


func _spawn_trap(payload: Variant) -> Node:
	var trap: MagicCircleTrap = TRAP_SCENE.instantiate() as MagicCircleTrap
	trap.configure(payload)
	return trap


func _get_spawn_position(slot: int) -> Vector2:
	var count: int = APOCRYPHA_MAX_PAIRS if _match_config.mode == MatchConfig.MatchMode.APOCRYPHA_7V7 else FUYUKI_MAX_PAIRS
	var angle: float = TAU * float(slot) / float(count) - PI * 0.5
	return Vector2(cos(angle), sin(angle)) * 280.0


func _servant_node_name(peer_id: int) -> String:
	return "Player_%d" % peer_id


func _master_node_name(peer_id: int) -> String:
	return "Master_%d" % peer_id


func _get_servant(peer_id: int) -> ServantController:
	if _players_root == null or peer_id == 0:
		return null
	var named: Node = _players_root.get_node_or_null(_servant_node_name(peer_id))
	if named is ServantController and (named as ServantController).owner_id == peer_id:
		return named as ServantController
	for child: Node in _players_root.get_children():
		var servant: ServantController = child as ServantController
		if servant != null and servant.owner_id == peer_id:
			return servant
	return null


func _get_master(peer_id: int) -> MasterController:
	if _players_root == null or peer_id == 0:
		return null
	var named: Node = _players_root.get_node_or_null(_master_node_name(peer_id))
	if named is MasterController and (named as MasterController).owner_id == peer_id:
		return named as MasterController
	for child: Node in _players_root.get_children():
		var master: MasterController = child as MasterController
		if master != null and master.owner_id == peer_id:
			return master
	return null


# --- RTS selection and commands --------------------------------------------

func _all_player_units() -> Array[Node2D]:
	var result: Array[Node2D] = []
	if _players_root == null:
		return result
	for child: Node in _players_root.get_children():
		var unit: Node2D = child as Node2D
		if unit != null and unit.is_in_group("player_units"):
			result.append(unit)
	return result


func _own_units() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var local_id: int = multiplayer.get_unique_id()
	for unit: Node2D in _all_player_units():
		if int(unit.get("owner_id")) == local_id:
			result.append(unit)
	return result


func _update_selection() -> void:
	var cleaned: Array[Node2D] = []
	for unit: Node2D in _selected_units:
		if is_instance_valid(unit) and unit.visible:
			cleaned.append(unit)
	_selected_units = cleaned


func _finish_selection(additive: bool) -> void:
	var chosen: Array[Node2D] = []
	if _selection_box_active:
		var rect: Rect2 = Rect2(
			Vector2(minf(_drag_start_world.x, _drag_current_world.x), minf(_drag_start_world.y, _drag_current_world.y)),
			Vector2(absf(_drag_current_world.x - _drag_start_world.x), absf(_drag_current_world.y - _drag_start_world.y))
		)
		for unit: Node2D in _own_units():
			if rect.has_point(unit.global_position):
				chosen.append(unit)
	else:
		var picked: Node2D = _find_own_unit_at(_drag_start_world)
		if picked != null:
			chosen.append(picked)

	if additive:
		for unit: Node2D in chosen:
			if not _selected_units.has(unit):
				_selected_units.append(unit)
	elif not chosen.is_empty():
		_selected_units = chosen
	else:
		_selected_units.clear()
	queue_redraw()


func _find_own_unit_at(world_point: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance: float = 28.0
	for unit: Node2D in _own_units():
		var distance: float = world_point.distance_to(unit.global_position)
		if distance < best_distance:
			best = unit
			best_distance = distance
	return best


func _find_enemy_at(world_point: Vector2) -> Node2D:
	var local_id: int = multiplayer.get_unique_id()
	var local_team: int = _local_team_id()
	var best: Node2D = null
	var best_distance: float = 28.0
	for unit: Node2D in _all_player_units():
		var owner: int = int(unit.get("owner_id"))
		if owner == local_id or not unit.visible:
			continue
		if _match_config.mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and int(unit.get("team_id")) == local_team:
			continue
		if _match_config.mode == MatchConfig.MatchMode.FUYUKI_FFA:
			var stance: int = int(_stance_cache.get(owner, MatchConfig.Stance.HOSTILE))
			if stance != MatchConfig.Stance.HOSTILE:
				continue
		var distance: float = world_point.distance_to(unit.global_position)
		if distance < best_distance:
			best = unit
			best_distance = distance
	return best


func _local_team_id() -> int:
	var own_units: Array[Node2D] = _own_units()
	if own_units.is_empty():
		return 0
	return int(own_units[0].get("team_id"))


func _issue_world_command(target: Vector2, attack_move: bool) -> void:
	if _selected_units.is_empty():
		return
	var enemy: Node2D = _find_enemy_at(target)
	for unit: Node2D in _selected_units:
		if enemy != null:
			_issue_attack(unit, enemy)
		else:
			_issue_move(unit, target, attack_move)


func _issue_move(unit: Node2D, target: Vector2, attack_move: bool) -> void:
	if multiplayer.is_server():
		unit.call("_rpc_command_move", target, attack_move)
	else:
		unit.rpc_id(1, "_rpc_command_move", target, attack_move)


func _issue_attack(unit: Node2D, enemy: Node2D) -> void:
	if multiplayer.is_server():
		unit.call("_rpc_command_attack", enemy.get_path())
	else:
		unit.rpc_id(1, "_rpc_command_attack", enemy.get_path())


func _poll_ability_input() -> void:
	if _overlay != null and _overlay.visible:
		return
	if Input.is_action_just_pressed("skill_1"):
		_cast_skill(0)
	if Input.is_action_just_pressed("skill_2"):
		_cast_skill(1)
	if Input.is_action_just_pressed("noble_phantasm"):
		_cast_noble_phantasm()
	if Input.is_action_just_pressed("command_spell"):
		_cast_command_spell()


func _cast_skill(slot: int) -> void:
	var caster: Node2D = _first_selected_unit()
	if caster == null:
		return
	var direction: Vector2 = (get_global_mouse_position() - caster.global_position).normalized()
	if multiplayer.is_server():
		caster.call("_rpc_use_skill", slot, direction)
	else:
		caster.rpc_id(1, "_rpc_use_skill", slot, direction)


func _cast_noble_phantasm() -> void:
	var servant: ServantController = _find_selected_servant()
	if servant == null:
		servant = get_local_servant()
	if servant == null:
		return
	var direction: Vector2 = (get_global_mouse_position() - servant.global_position).normalized()
	if multiplayer.is_server():
		servant.call("_rpc_use_noble_phantasm", direction)
	else:
		servant.rpc_id(1, "_rpc_use_noble_phantasm", direction)


func _cast_command_spell() -> void:
	var master: MasterController = _find_selected_master()
	if master == null:
		master = get_local_master()
	if master == null:
		return
	if multiplayer.is_server():
		master.call("_rpc_use_command_spell")
	else:
		master.rpc_id(1, "_rpc_use_command_spell")


func _first_selected_unit() -> Node2D:
	if _selected_units.is_empty():
		return null
	return _selected_units[0]


func _find_selected_servant() -> ServantController:
	for unit: Node2D in _selected_units:
		var servant: ServantController = unit as ServantController
		if servant != null:
			return servant
	return null


func _find_selected_master() -> MasterController:
	for unit: Node2D in _selected_units:
		var master: MasterController = unit as MasterController
		if master != null:
			return master
	return null


# --- Fog of war -------------------------------------------------------------

func _update_fog_of_war() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _spectator_mode and _match_started:
		var all_units: Array[Node2D] = _all_player_units()
		if _omniscient_view:
			for unit: Node2D in all_units:
				unit.visible = true
			return
		for unit: Node2D in all_units:
			var sources: Array[Node2D] = []
			for other: Node2D in all_units:
				if other != unit and bool(other.get("is_alive")):
					sources.append(other)
			unit.visible = is_unit_visible_to(unit, sources, -1, -1)
		return

	var own_units: Array[Node2D] = _own_units()
	var local_team: int = 0
	if not own_units.is_empty():
		local_team = int(own_units[0].get("team_id"))
	for unit: Node2D in _all_player_units():
		unit.visible = is_unit_visible_to(unit, own_units, multiplayer.get_unique_id(), local_team)


## Pure visibility rule shared by the fog renderer and headless tests.
func is_unit_visible_to(unit: Node2D, viewer_units: Array[Node2D], viewer_peer_id: int, viewer_team: int) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var owner: int = int(unit.get("owner_id"))
	if owner == viewer_peer_id:
		return true
	if _match_config.mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and int(unit.get("team_id")) == viewer_team:
		return true

	for source: Node2D in viewer_units:
		if source == null or not is_instance_valid(source) or not bool(source.get("is_alive")):
			continue
		var vision: float = float(source.get("vision_radius"))
		var distance: float = source.global_position.distance_to(unit.global_position)
		if distance > vision:
			continue
		if unit is ServantController and bool(unit.get("is_stealthed")):
			if distance <= CLOSE_DETECTION_RADIUS:
				return true
		else:
			return true
	return false


# --- Camera -----------------------------------------------------------------

func _update_camera(delta: float) -> void:
	if _camera == null:
		return
	if not _camera_initialized:
		var focus_units: Array[Node2D] = _all_player_units() if (_spectator_mode and _match_started) else _own_units()
		if not focus_units.is_empty():
			var center: Vector2 = Vector2.ZERO
			for unit: Node2D in focus_units:
				center += unit.global_position
			_camera.position = center / float(focus_units.size())
			_camera_initialized = true

	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var pan: Vector2 = Vector2.ZERO
	var margin: float = 16.0
	if mouse_position.x < margin:
		pan.x -= 1.0
	elif mouse_position.x > viewport_size.x - margin:
		pan.x += 1.0
	if mouse_position.y < margin:
		pan.y -= 1.0
	elif mouse_position.y > viewport_size.y - margin:
		pan.y += 1.0
	if pan.length_squared() > 0.0:
		_camera.position += pan.normalized() * 620.0 * delta / maxf(_camera.zoom.x, 0.1)
	_camera.position.x = clampf(_camera.position.x, -ARENA_HALF_EXTENTS.x, ARENA_HALF_EXTENTS.x)
	_camera.position.y = clampf(_camera.position.y, -ARENA_HALF_EXTENTS.y, ARENA_HALF_EXTENTS.y)

	var now: int = Time.get_ticks_msec()
	if now < _shake_until_msec and _shake_strength > 0.0:
		var remaining: float = float(_shake_until_msec - now) / 360.0
		var amplitude: float = _shake_strength * clampf(remaining, 0.0, 1.0)
		var jitter: Vector2 = Vector2(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0)
		).normalized()
		var direction: Vector2 = (_shake_direction * 0.72 + jitter * 0.28).normalized()
		_camera.offset = direction * amplitude
	else:
		_shake_strength = 0.0
		_camera.offset = _camera.offset.lerp(Vector2.ZERO, clampf(delta * 18.0, 0.0, 1.0))


func _zoom_camera(amount: float) -> void:
	if _camera == null:
		return
	var zoom_value: float = clampf(_camera.zoom.x + amount, 0.6, 1.8)
	_camera.zoom = Vector2(zoom_value, zoom_value)


# --- Diplomacy --------------------------------------------------------------

func _cycle_stance_nearest_enemy() -> void:
	if _match_config.mode != MatchConfig.MatchMode.FUYUKI_FFA:
		return
	var own_units: Array[Node2D] = _own_units()
	if own_units.is_empty():
		return
	var origin: Vector2 = own_units[0].global_position
	var nearest_peer: int = 0
	var nearest_distance: float = INF
	for unit: Node2D in _all_player_units():
		var owner: int = int(unit.get("owner_id"))
		if owner == multiplayer.get_unique_id():
			continue
		var distance: float = origin.distance_to(unit.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_peer = owner
	if nearest_peer == 0:
		return
	var current: int = MatchConfig.Stance.HOSTILE
	if multiplayer.is_server() and _match_state != null:
		current = _match_state.get_stance(multiplayer.get_unique_id(), nearest_peer)
	elif _stance_cache.has(nearest_peer):
		current = int(_stance_cache[nearest_peer])
	var next: int = MatchConfig.Stance.HOSTILE
	match current:
		MatchConfig.Stance.HOSTILE:
			next = MatchConfig.Stance.NEUTRAL
		MatchConfig.Stance.NEUTRAL:
			next = MatchConfig.Stance.ALLIED
		_:
			next = MatchConfig.Stance.HOSTILE
	_stance_cache[nearest_peer] = next
	_stance_message = "P%d vs P%d: %s" % [multiplayer.get_unique_id(), nearest_peer, MatchConfig.stance_name(next)]
	request_stance(nearest_peer, next)


# --- HUD / Canvas -----------------------------------------------------------

func _update_hud() -> void:
	if _status_label == null:
		return
	var mode_name: String = MatchConfig.mode_name(_match_config.mode)
	if _spectator_mode and _match_started:
		mode_name = "SPECTATOR_AI_WAR"
	var faction: String = _local_faction_name()
	_status_label.text = "HOLY GRAIL WAR - RTS COMMAND   |   %s   |   %s   |   Peer %d   |   AI %d/%d   |   Selected %d" % [
		mode_name, faction, multiplayer.get_unique_id(), _ai_entry_count(), _pair_cap(), _selected_units.size()
	]

	var master: MasterController = get_local_master()
	var servant: ServantController = get_local_servant()
	var lines: PackedStringArray = PackedStringArray()
	if master != null:
		lines.append("MASTER %s  HP %d/%d  MANA %d/%d (+%.1f/s)  CS %d/3  LEY %d" % [
			master.master_data.display_name,
			int(round(master.health)), int(round(master.max_health)),
			int(round(master.mana)), int(round(master.max_mana)),
			master.mana_regeneration, master.command_spells_left, master.leylines_held,
		])
		lines.append("MASTER SKILLS  Q: %s   E: %s" % [master.master_data.skill_1_name, master.master_data.skill_2_name])
	if servant != null:
		lines.append("SERVANT %s  HP %d/%d  MANA %d/%d  LEY %d%s" % [
			servant.get_display_name_for(multiplayer.get_unique_id()),
			int(round(servant.health)), int(round(servant.max_health)),
			int(round(servant.mana)), int(round(servant.max_mana)),
			servant.leylines_held,
			"  [TERRITORY]" if servant.territory_bonus_active else "",
		])
		var servant_skills: PackedStringArray = servant.servant_data.active_skills
		var skill_1_name: String = String(servant_skills[0]) if servant_skills.size() > 0 else "Skill 1"
		var skill_2_name: String = String(servant_skills[1]) if servant_skills.size() > 1 else "Skill 2"
		if servant.is_name_known_to_master:
			lines.append("SERVANT SKILLS  Q: %s   E: %s   R: %s" % [skill_1_name, skill_2_name, servant.servant_data.noble_phantasm_name])
		else:
			lines.append("SERVANT IDENTITY UNKNOWN - autonomy active. Use ASK NAME or a Command Spell to unlock manual control.")
		if servant.is_fame_buffed:
			lines.append("FAME / MORALE: +15% damage buff active")
	if master == null and servant == null:
		var entry: Dictionary = _lobby_state.get(multiplayer.get_unique_id(), {})
		if _spectator_mode and _match_started:
			lines.append("SPECTATOR MODE - free observer camera. Fog toggle and playback speed are bottom-right.")
		elif bool(entry.get("eliminated", false)):
			lines.append("ELIMINATED - Master has fallen.")
		elif _match_started:
			lines.append("SPECTATING - no duo deployed.")
		else:
			lines.append("AWAITING SUMMON / DEPLOYMENT")
	_duo_label.text = "\n".join(lines)

	if _sigils != null:
		if master != null:
			_sigils.set_state(master.command_spells_left, master.signature_command_spell_used)
		else:
			_sigils.set_state(0, false)

	_roster_label.text = _format_roster()
	_update_action_buttons()
	if not _stance_message.is_empty():
		_roster_label.text += "\nSTANCE: " + _stance_message

	if _reality_marble_label != null:
		_reality_marble_label.visible = _reality_marble_owner_id != 0
		if _reality_marble_owner_id != 0:
			var marble_owner: ServantController = _get_servant(_reality_marble_owner_id)
			var marble_title: String = "REALITY MARBLE"
			if marble_owner != null and marble_owner.servant_data != null and not marble_owner.servant_data.noble_phantasm_name.is_empty():
				marble_title = marble_owner.servant_data.noble_phantasm_name.to_upper()
			_reality_marble_label.text = "%s - P%d" % [marble_title, _reality_marble_owner_id]


func _local_faction_name() -> String:
	if _spectator_mode and _match_started:
		return "SPECTATOR"
	var mode: int = _match_config.mode
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7:
		var entry: Dictionary = _lobby_state.get(multiplayer.get_unique_id(), {})
		return MatchConfig.team_name(int(entry.get("team", MatchConfig.Team.NEUTRAL)))
	return "FFA P%d" % multiplayer.get_unique_id()


func _format_roster() -> String:
	if _lobby_state.is_empty():
		return "ROSTER  |  no summons yet"
	var local_id: int = multiplayer.get_unique_id()
	var keys: Array = _lobby_state.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for key: Variant in keys:
		var peer_id: int = int(key)
		var entry: Dictionary = _lobby_state[key]
		var team: String = MatchConfig.team_name(int(entry.get("team", -1)))
		var status: String = "READY" if bool(entry.get("deployed", false)) else "SUMMON"
		if bool(entry.get("eliminated", false)):
			status = "OUT"
		elif bool(entry.get("ai_takeover", false)):
			status = "AUTOPILOT"
		elif bool(entry.get("spectating", false)):
			status = "SPECTATOR"
		var servant_name: String = String(entry.get("servant_name", "?"))
		if bool(entry.get("deployed", false)) and not bool(entry.get("eliminated", false)):
			var listed_servant: ServantController = _get_servant(peer_id)
			if peer_id == local_id:
				if listed_servant != null and not listed_servant.is_name_known_to_master:
					servant_name = "Unknown [%s]" % Roster.class_name_for(int(entry.get("class_id", 0)))
			elif listed_servant == null or not listed_servant.is_true_name_revealed:
				servant_name = "Unknown [%s]" % Roster.class_name_for(int(entry.get("class_id", 0)))
		var label: String = "AI%d" % int(entry.get("ai_slot", 0)) if bool(entry.get("is_ai", false)) else "P%d" % peer_id
		parts.append("%s[%s] %s/%s %s" % [label, team, String(entry.get("master_name", "?")), servant_name, status])
	return "ROSTER  |  " + "   ".join(parts)


func _on_peer_joined(peer_id: int) -> void:
	if not multiplayer.is_server() or _match_started:
		return
	_rpc_sync_lobby.rpc_id(
		peer_id,
		_lobby_state.duplicate(true),
		_match_config.mode,
		_spectator_mode,
		_auto_fill,
		_match_started
	)
	_broadcast_lobby_state()


func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var entry: Dictionary = _lobby_state.get(peer_id, {})
	var can_take_over: bool = _match_started 		and bool(entry.get("deployed", false)) 		and not bool(entry.get("eliminated", false)) 		and not bool(entry.get("is_ai", false)) 		and (_get_master(peer_id) != null or _get_servant(peer_id) != null)
	if can_take_over:
		entry["ai_takeover"] = true
		_lobby_state[peer_id] = entry
		_attach_ai(peer_id)
		_log_event("%s has fallen into Autopilot (AI Takeover)" % String(entry.get("master_name", "Master")))
		_broadcast_lobby_state()
		return

	_lobby_state.erase(peer_id)
	_match_state.remove_peer(peer_id)
	for leyline: LeylineNode in _leylines:
		if leyline.owner_peer_id == peer_id:
			leyline.release_owner()
	_free_duo(peer_id)
	_broadcast_lobby_state()


func _on_master_eliminated(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_detach_ai(peer_id)
	if _lobby_state.has(peer_id):
		var entry: Dictionary = _lobby_state[peer_id]
		entry["eliminated"] = true
		entry["ai_takeover"] = false
		_lobby_state[peer_id] = entry
		_log_event("PLAYER ELIMINATED: %s" % String(entry.get("master_name", "Master")))
	_session_ids.erase(peer_id)
	for leyline: LeylineNode in _leylines:
		if leyline.owner_peer_id == peer_id:
			leyline.release_owner()
	_free_servant(peer_id)
	_broadcast_lobby_state()
	_arm_match_end_check()


func _arm_match_end_check() -> void:
	if not multiplayer.is_server() or not _match_started or not _direct_match:
		return
	if _director == null or _match_end_pending:
		return
	if _deployed_pair_count() > 1:
		return
	var winner: String = ""
	for entry_variant: Variant in _lobby_state.values():
		var entry: Dictionary = entry_variant
		if bool(entry.get("deployed", false)) and not bool(entry.get("eliminated", false)):
			winner = String(entry.get("master_name", "Master"))
			break
	if winner.is_empty():
		_match_end_reason = "MATCH COMPLETE: no survivors. Returning to the Waiting Lobby."
	else:
		_match_end_reason = "MATCH COMPLETE: %s wins. Returning to the Waiting Lobby." % winner
	_match_end_pending = true
	_match_end_at_msec = Time.get_ticks_msec() + 2000
	_log_event(_match_end_reason)


func _maybe_finish_match() -> void:
	if not _match_end_pending:
		return
	if Time.get_ticks_msec() < _match_end_at_msec:
		return
	_match_end_pending = false
	if _director != null:
		_director.call_deferred("finish_match_and_reset", _match_end_reason)


func _free_duo(peer_id: int) -> void:
	_detach_ai(peer_id)
	_session_ids.erase(peer_id)
	_free_servant(peer_id)
	var master: MasterController = _get_master(peer_id)
	if master != null:
		master.queue_free()


func _free_servant(peer_id: int) -> void:
	var servant: ServantController = _get_servant(peer_id)
	if servant != null:
		servant.queue_free()


func _on_leyline_ownership_changed(new_owner: int, _previous_owner: int, leyline: LeylineNode) -> void:
	queue_redraw()
	if not multiplayer.is_server() or leyline == null:
		return
	if new_owner == 0:
		_log_event("LEYLINE LOST: %s" % leyline.leyline_name)
	else:
		_log_event("%s claimed %s" % [_master_name_for(new_owner), leyline.leyline_name])
		_fx_sfx("leyline_capture", leyline.global_position)


func _on_servant_true_name_revealed(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var entry: Dictionary = _lobby_state.get(peer_id, {})
	_log_event("TRUE NAME REVEALED: %s" % String(entry.get("servant_name", "Unknown Servant")))


func _on_servant_died(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var entry: Dictionary = _lobby_state.get(peer_id, {})
	var servant: ServantController = _get_servant(peer_id)
	var eliminated_name: String = "Unknown [%s]" % Roster.class_name_for(int(entry.get("class_id", 0)))
	if servant != null and servant.is_true_name_revealed:
		eliminated_name = servant.servant_data.display_name
	_log_event("SERVANT ELIMINATED: %s" % eliminated_name)


func _on_servant_name_known(_known: bool, peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var commander: AICommander = _ai_commanders.get(peer_id, null) as AICommander
	if commander != null and not commander.control_master:
		_detach_ai(peer_id)
		var entry: Dictionary = _lobby_state.get(peer_id, {})
		_log_event("TRUE NAME LEARNED: %s has bound their Servant's identity privately" % String(entry.get("master_name", "Master")))


func _on_master_command_spell(charges_left: int, peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var entry: Dictionary = _lobby_state.get(peer_id, {})
	_log_event("COMMAND SPELL: %s (%d left)" % [String(entry.get("master_name", "Master")), charges_left])


func _on_trump_card_used(card_name: String, peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var entry: Dictionary = _lobby_state.get(peer_id, {})
	_log_event("TRUMP CARD: %s unleashed %s" % [String(entry.get("master_name", "Master")), card_name])


func _on_signature_decree_used(spell_name: String, peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var entry: Dictionary = _lobby_state.get(peer_id, {})
	_log_event("SIGNATURE DECREE: %s - %s" % [String(entry.get("master_name", "Master")), spell_name])


func _master_name_for(peer_id: int) -> String:
	var entry: Dictionary = _lobby_state.get(peer_id, {})
	if not entry.is_empty():
		return String(entry.get("master_name", "P%d" % peer_id))
	return "P%d" % peer_id


func _on_reality_marble_state_changed(active: bool, peer_id: int) -> void:
	if active:
		_reality_marble_owner_id = peer_id
		_marble_shock_start_msec = Time.get_ticks_msec()
		if _telegraph_layer != null:
			var marble_servant: ServantController = _get_servant(peer_id)
			if marble_servant != null and marble_servant.servant_data != null:
				_telegraph_layer.add_telegraph(
					ServantData.NoblePhantasmStyle.REALITY_MARBLE,
					marble_servant.global_position,
					Vector2.RIGHT,
					760.0,
					1.1,
					marble_servant.servant_data.noble_phantasm_color
				)
	elif _reality_marble_owner_id == peer_id:
		_reality_marble_owner_id = 0
		_marble_shock_start_msec = 0
	queue_redraw()


func _on_np_telegraph(style: int, origin: Vector2, direction: Vector2, length: float, duration: float, colour: Color) -> void:
	if _telegraph_layer == null:
		return
	_telegraph_layer.add_telegraph(style, origin, direction, length, duration, colour)


func _on_trump_telegraph(origin: Vector2, radius: float, duration: float, colour: Color) -> void:
	if _telegraph_layer == null:
		return
	_telegraph_layer.add_telegraph(
		ServantData.NoblePhantasmStyle.NOVA,
		origin,
		Vector2.RIGHT,
		radius,
		duration,
		colour
	)


func _parse_mode_from_cli() -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg: String in args:
		if arg.begins_with("--match-mode=") or arg.begins_with("--mode="):
			var value: String = arg.get_slice("=", 1).to_lower()
			if value.begins_with("apocrypha") or value == "7v7":
				return MatchConfig.MatchMode.APOCRYPHA_7V7
	return MatchConfig.MatchMode.FUYUKI_FFA


func _draw() -> void:
	var bounds: Vector2 = ARENA_HALF_EXTENTS
	var arena_rect: Rect2 = Rect2(-bounds, bounds * 2.0)

	draw_rect(arena_rect, Color(0.045, 0.055, 0.09))
	draw_rect(arena_rect, Color(0.1, 0.12, 0.2), false, 2.0)

	var grid_color: Color = Color(0.16, 0.19, 0.3, 0.45)
	var x: float = -bounds.x
	while x <= bounds.x:
		draw_line(Vector2(x, -bounds.y), Vector2(x, bounds.y), grid_color, 1.0)
		x += 80.0
	var y: float = -bounds.y
	while y <= bounds.y:
		draw_line(Vector2(-bounds.x, y), Vector2(bounds.x, y), grid_color, 1.0)
		y += 80.0

	draw_circle(Vector2.ZERO, 150.0, Color(0.3, 0.2, 0.55, 0.06))
	draw_arc(Vector2.ZERO, 150.0, 0.0, TAU, 64, Color(0.55, 0.4, 0.85, 0.25), 2.0, true)

	for slot: int in range(_pair_cap()):
		var point: Vector2 = _get_spawn_position(slot)
		draw_arc(point, 22.0, 0.0, TAU, 24, Color(0.32, 0.38, 0.55, 0.6), 2.0, true)

	if _reality_marble_owner_id != 0:
		draw_rect(arena_rect, Color(0.45, 0.04, 0.24, 0.14))
		draw_rect(arena_rect, Color(0.95, 0.25, 0.58, 0.6), false, 4.0)
		var marble_servant: ServantController = _get_servant(_reality_marble_owner_id)
		if marble_servant != null and marble_servant.servant_data != null and marble_servant.servant_data.noble_phantasm_style == ServantData.NoblePhantasmStyle.REALITY_MARBLE:
			for index: int in range(18):
				var angle: float = TAU * float(index) / 18.0 + 0.12
				var inner: Vector2 = Vector2(cos(angle), sin(angle)) * 180.0
				var outer: Vector2 = Vector2(cos(angle), sin(angle)) * 360.0
				draw_line(inner, outer, Color(0.65, 0.8, 1.0, 0.24), 3.0, true)

	for unit: Node2D in _selected_units:
		if is_instance_valid(unit):
			draw_arc(unit.global_position, 27.0, 0.0, TAU, 28, Color(0.35, 0.95, 0.8, 0.9), 2.0, true)

	if _selection_box_active:
		var box_rect: Rect2 = Rect2(
			Vector2(minf(_drag_start_world.x, _drag_current_world.x), minf(_drag_start_world.y, _drag_current_world.y)),
			Vector2(absf(_drag_current_world.x - _drag_start_world.x), absf(_drag_current_world.y - _drag_start_world.y))
		)
		draw_rect(box_rect, Color(0.35, 0.95, 0.8, 0.15))
		draw_rect(box_rect, Color(0.35, 0.95, 0.8, 0.85), false, 2.0)


func _fx_sfx(kind: String, world_position: Vector2 = Vector2.ZERO) -> void:
	var fx: Node = get_node_or_null("/root/AudioManager")
	if fx != null:
		fx.call("broadcast_sfx", kind, world_position)
