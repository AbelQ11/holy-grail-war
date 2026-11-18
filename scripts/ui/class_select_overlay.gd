class_name ClassSelectOverlay
extends CanvasLayer
## Pre-match summoning lobby.
##
## Players choose a globally unique Master and a Servant Class (or ask the
## server to roll a random class / a fully random pair). The named Heroic Spirit
## matching the chosen class is rolled secretly by the server and broadcast only
## when the identity rules allow it; the overlay only renders the result.

signal summon_requested(master_id: String, class_id: int, roll_mode: int)
signal deploy_requested
signal match_mode_requested(mode: int)
signal ai_add_requested(master_id: String, class_id: int, roll_mode: int)
signal ai_remove_requested
signal ai_fill_requested
signal auto_fill_toggled(enabled: bool)
signal spectate_toggled(enabled: bool)
signal start_match_requested
signal reclaim_requested(session_id: String)

var local_peer_id: int = 1
var is_host: bool = false

var _class_select: OptionButton
var _master_select: OptionButton
var _details_label: Label
var _status_label: Label
var _roster_label: Label
var _mode_label: Label
var _ffa_button: Button
var _apocrypha_button: Button
var _summon_button: Button
var _random_class_button: Button
var _random_pair_button: Button
var _deploy_button: Button
var _host_controls: VBoxContainer
var _auto_fill_check: CheckButton
var _spectate_check: CheckButton
var _start_button: Button
var _capacity_label: Label
var _session_label: Label
var _session_input: LineEdit
var _reclaim_button: Button
var _match_started: bool = false

var _masters: Array[MasterData] = []
var _class_ids: Array[int] = []
var _resolved: bool = false
var _current_mode: int = MatchConfig.MatchMode.FUYUKI_FFA
var _lobby_state: Dictionary = {}


func _ready() -> void:
	layer = 30
	_masters = Roster.get_masters()
	_class_ids.clear()
	for class_id: int in Roster.get_class_ids():
		_class_ids.append(class_id)
	_build_ui()
	_populate_masters()
	_rebuild_class_options()
	_update_details()


func set_local_peer_id(peer_id: int) -> void:
	local_peer_id = peer_id


func set_is_host(value: bool) -> void:
	is_host = value
	if _ffa_button != null:
		_ffa_button.visible = value
		_apocrypha_button.visible = value
	if _host_controls != null:
		_host_controls.visible = value


func set_match_mode(mode: int) -> void:
	_current_mode = mode
	if _mode_label != null:
		_mode_label.text = "MATCH MODE: %s" % MatchConfig.mode_name(mode)


func set_spectator_mode(enabled: bool) -> void:
	if _spectate_check != null:
		_spectate_check.set_pressed_no_signal(enabled)


func set_auto_fill(enabled: bool) -> void:
	if _auto_fill_check != null:
		_auto_fill_check.set_pressed_no_signal(enabled)


func set_match_started(started: bool) -> void:
	_match_started = started
	if started:
		visible = false


func set_session_id(session_id: String) -> void:
	if _session_label != null:
		_session_label.text = "SESSION: %s" % session_id


func set_lobby_state(state: Dictionary) -> void:
	_lobby_state = state
	if _roster_label == null:
		return
	var lines: PackedStringArray = PackedStringArray(["ROSTER"])
	var peer_keys: Array = state.keys()
	peer_keys.sort()
	for peer_key: Variant in peer_keys:
		var peer_id: int = int(peer_key)
		var entry_variant: Variant = state[peer_key]
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var team_name: String = MatchConfig.team_name(int(entry.get("team", -1)))
		var master_name: String = String(entry.get("master_name", "?"))
		var class_id: int = int(entry.get("class_id", -1))
		var class_text: String = Roster.class_name_for(class_id) if class_id >= 0 else "Choosing..."
		var state_text: String = "DEPLOYED" if bool(entry.get("deployed", false)) else "SELECTING"
		if bool(entry.get("eliminated", false)):
			state_text = "ELIMINATED"
		elif bool(entry.get("ai_takeover", false)):
			state_text = "AUTOPILOT"
		elif bool(entry.get("spectating", false)):
			state_text = "SPECTATOR"
		var suffix: String = " (you)" if peer_id == local_peer_id else ""
		var label: String = "AI%d" % int(entry.get("ai_slot", 0)) if bool(entry.get("is_ai", false)) else "P%d" % peer_id
		lines.append("%s%s  [%s]  %s + %s  [%s]" % [label, suffix, team_name, master_name, class_text, state_text])
	_roster_label.text = "\n".join(lines)
	if _capacity_label != null:
		var ai_count: int = 0
		for entry_variant: Variant in state.values():
			var entry: Dictionary = entry_variant
			if bool(entry.get("is_ai", false)):
				ai_count += 1
		_capacity_label.text = "SLOTS %d / %d  |  AI BOTS %d" % [state.size(), _capacity_for_mode(), ai_count]

	var local_entry: Dictionary = state.get(local_peer_id, {})
	_resolved = int(local_entry.get("class_id", -1)) >= 0
	if _resolved and not bool(local_entry.get("deployed", false)):
		var master_name: String = String(local_entry.get("master_name", "Master"))
		var class_id: int = int(local_entry.get("class_id", -1))
		var class_text: String = Roster.class_name_for(class_id)
		_status_label.text = "SUMMON CONFIRMED: %s + Unknown [%s] (identity sealed)" % [master_name, class_text]
		_deploy_button.disabled = false
		_deploy_button.text = "DEPLOY DUO"
	elif not _resolved and not bool(local_entry.get("deployed", false)):
		_status_label.text = "Choose a Master and Servant Class, or request a random summon."
		_deploy_button.disabled = true
		_deploy_button.text = "DEPLOY DUO"
	_populate_masters()
	_rebuild_class_options()


func set_local_deployed(deployed: bool) -> void:
	visible = not (deployed or _match_started)


func _build_ui() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.01, 0.015, 0.03, 0.86)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(940.0, 0.0)
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.06, 0.115, 0.98)
	panel_style.border_color = Color(0.52, 0.38, 0.82, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title: Label = Label.new()
	title.text = "HOLY GRAIL WAR - SUMMONING LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	column.add_child(title)

	var mode_row: HBoxContainer = HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 8)
	column.add_child(mode_row)

	_mode_label = Label.new()
	_mode_label.text = "MATCH MODE: FUYUKI FFA"
	_mode_label.add_theme_font_size_override("font_size", 13)
	_mode_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	mode_row.add_child(_mode_label)

	_ffa_button = Button.new()
	_ffa_button.text = "FUYUKI FFA"
	_ffa_button.pressed.connect(_on_match_mode_pressed.bind(MatchConfig.MatchMode.FUYUKI_FFA))
	mode_row.add_child(_ffa_button)
	_apocrypha_button = Button.new()
	_apocrypha_button.text = "APOCRYPHA 7v7"
	_apocrypha_button.pressed.connect(_on_match_mode_pressed.bind(MatchConfig.MatchMode.APOCRYPHA_7V7))
	mode_row.add_child(_apocrypha_button)
	_ffa_button.visible = false
	_apocrypha_button.visible = false

	column.add_child(HSeparator.new())

	var selectors: HBoxContainer = HBoxContainer.new()
	selectors.add_theme_constant_override("separation", 10)
	column.add_child(selectors)

	_master_select = OptionButton.new()
	_master_select.custom_minimum_size = Vector2(300.0, 34.0)
	_master_select.item_selected.connect(_on_selection_changed)
	selectors.add_child(_master_select)

	_class_select = OptionButton.new()
	_class_select.custom_minimum_size = Vector2(300.0, 34.0)
	_class_select.item_selected.connect(_on_selection_changed)
	selectors.add_child(_class_select)

	_details_label = Label.new()
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_label.custom_minimum_size = Vector2(880.0, 64.0)
	_details_label.add_theme_font_size_override("font_size", 12)
	_details_label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.88))
	column.add_child(_details_label)

	_host_controls = VBoxContainer.new()
	_host_controls.visible = false
	_host_controls.add_theme_constant_override("separation", 6)
	column.add_child(_host_controls)

	var ai_row: HBoxContainer = HBoxContainer.new()
	ai_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ai_row.add_theme_constant_override("separation", 6)
	_host_controls.add_child(ai_row)

	var add_ai_pair: Button = Button.new()
	add_ai_pair.text = "ADD AI (SELECTED MASTER + CLASS)"
	add_ai_pair.pressed.connect(_on_add_ai_specific)
	ai_row.add_child(add_ai_pair)

	var add_ai_random: Button = Button.new()
	add_ai_random.text = "ADD AI (RANDOM)"
	add_ai_random.pressed.connect(_on_add_ai_random)
	ai_row.add_child(add_ai_random)

	var remove_ai: Button = Button.new()
	remove_ai.text = "REMOVE AI"
	remove_ai.pressed.connect(func() -> void: ai_remove_requested.emit())
	ai_row.add_child(remove_ai)

	var fill_ai: Button = Button.new()
	fill_ai.text = "FILL REMAINING SLOTS WITH AI"
	fill_ai.pressed.connect(func() -> void: ai_fill_requested.emit())
	ai_row.add_child(fill_ai)

	var host_settings: HBoxContainer = HBoxContainer.new()
	host_settings.alignment = BoxContainer.ALIGNMENT_CENTER
	host_settings.add_theme_constant_override("separation", 18)
	_host_controls.add_child(host_settings)

	_auto_fill_check = CheckButton.new()
	_auto_fill_check.text = "Auto-Fill Empty Slots on Match Start"
	_auto_fill_check.button_pressed = true
	_auto_fill_check.toggled.connect(func(enabled: bool) -> void: auto_fill_toggled.emit(enabled))
	host_settings.add_child(_auto_fill_check)

	_spectate_check = CheckButton.new()
	_spectate_check.text = "Spectate Full AI War"
	_spectate_check.toggled.connect(func(enabled: bool) -> void: spectate_toggled.emit(enabled))
	host_settings.add_child(_spectate_check)

	_start_button = Button.new()
	_start_button.text = "START MATCH"
	_start_button.custom_minimum_size = Vector2(150.0, 34.0)
	_start_button.pressed.connect(func() -> void: start_match_requested.emit())
	host_settings.add_child(_start_button)

	_capacity_label = Label.new()
	_capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_capacity_label.add_theme_font_size_override("font_size", 11)
	_capacity_label.add_theme_color_override("font_color", Color(0.68, 0.72, 0.86))
	_capacity_label.text = "SLOTS 0 / 7  |  AI BOTS 0"
	_host_controls.add_child(_capacity_label)

	var recon_row: HBoxContainer = HBoxContainer.new()
	recon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	recon_row.add_theme_constant_override("separation", 6)
	column.add_child(recon_row)
	_session_label = Label.new()
	_session_label.text = "SESSION: (assigned after summon)"
	_session_label.add_theme_font_size_override("font_size", 10)
	_session_label.add_theme_color_override("font_color", Color(0.6, 0.64, 0.78))
	recon_row.add_child(_session_label)
	_session_input = LineEdit.new()
	_session_input.placeholder_text = "Session ID (reconnect)"
	_session_input.custom_minimum_size = Vector2(300.0, 30.0)
	recon_row.add_child(_session_input)
	_reclaim_button = Button.new()
	_reclaim_button.text = "RECLAIM"
	_reclaim_button.pressed.connect(_on_reclaim)
	recon_row.add_child(_reclaim_button)

	var summon_row: HBoxContainer = HBoxContainer.new()
	summon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	summon_row.add_theme_constant_override("separation", 12)
	column.add_child(summon_row)

	_summon_button = Button.new()
	_summon_button.text = "SUMMON SELECTED MASTER + CLASS"
	_summon_button.custom_minimum_size = Vector2(280.0, 40.0)
	_summon_button.pressed.connect(_on_summon_specific)
	summon_row.add_child(_summon_button)

	_random_class_button = Button.new()
	_random_class_button.text = "RANDOM CLASS ONLY"
	_random_class_button.custom_minimum_size = Vector2(220.0, 40.0)
	_random_class_button.pressed.connect(_on_random_class)
	summon_row.add_child(_random_class_button)

	_random_pair_button = Button.new()
	_random_pair_button.text = "RANDOM SUMMON"
	_random_pair_button.custom_minimum_size = Vector2(200.0, 40.0)
	_random_pair_button.pressed.connect(_on_random_pair)
	summon_row.add_child(_random_pair_button)

	_deploy_button = Button.new()
	_deploy_button.text = "DEPLOY DUO"
	_deploy_button.disabled = true
	_deploy_button.custom_minimum_size = Vector2(220.0, 44.0)
	_deploy_button.add_theme_font_size_override("font_size", 16)
	_deploy_button.pressed.connect(_on_deploy)
	column.add_child(_deploy_button)

	_status_label = Label.new()
	_status_label.text = "Choose a Master and Servant Class, or request a random summon."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.95))
	column.add_child(_status_label)

	column.add_child(HSeparator.new())

	var roster_scroll: ScrollContainer = ScrollContainer.new()
	roster_scroll.custom_minimum_size = Vector2(0.0, 108.0)
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(roster_scroll)
	_roster_label = Label.new()
	_roster_label.text = "ROSTER"
	_roster_label.add_theme_font_size_override("font_size", 12)
	_roster_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	roster_scroll.add_child(_roster_label)


func _populate_masters() -> void:
	var previous: String = ""
	if _master_select.item_count > 0 and _master_select.selected >= 0:
		previous = String(_master_select.get_item_metadata(_master_select.selected))
	_master_select.clear()
	var claimed: Dictionary = {}
	var local_master_id: String = String(_lobby_state.get(local_peer_id, {}).get("master_id", ""))
	for key: Variant in _lobby_state.keys():
		if int(key) == local_peer_id:
			continue
		var entry: Dictionary = _lobby_state[key]
		var claimed_id: String = String(entry.get("master_id", ""))
		if not claimed_id.is_empty():
			claimed[claimed_id] = true
	var selected: int = 0
	for index: int in range(_masters.size()):
		var master: MasterData = _masters[index]
		_master_select.add_item(master.display_name)
		_master_select.set_item_metadata(index, master.master_id)
		var locked: bool = claimed.has(master.master_id) and master.master_id != local_master_id
		_master_select.set_item_disabled(index, locked)
		if master.master_id == local_master_id or (local_master_id.is_empty() and master.master_id == previous):
			selected = index
	if _masters.is_empty():
		_master_select.add_item("No Masters available")


func _rebuild_class_options() -> void:
	if _class_select == null:
		return
	var previous: int = -1
	if _class_select.item_count > 0 and _class_select.selected >= 0:
		var previous_meta: Variant = _class_select.get_item_metadata(_class_select.selected)
		if previous_meta != null:
			previous = int(previous_meta)
	var local_entry: Dictionary = _lobby_state.get(local_peer_id, {})
	var current_class: int = int(local_entry.get("class_id", -1))
	_class_select.clear()
	var used: Dictionary = {}
	for key: Variant in _lobby_state.keys():
		if int(key) == local_peer_id:
			continue
		var entry: Dictionary = _lobby_state[key]
		var class_id: int = int(entry.get("class_id", -1))
		if class_id >= 0:
			used[class_id] = true
	var selected: int = 0
	for index: int in range(_class_ids.size()):
		var class_id: int = _class_ids[index]
		_class_select.add_item(Roster.class_name_for(class_id))
		_class_select.set_item_metadata(index, class_id)
		var locked: bool = used.has(class_id) and class_id != current_class
		_class_select.set_item_disabled(index, locked)
		if class_id == current_class or (current_class < 0 and class_id == previous):
			selected = index
	if _class_select.item_count > 0:
		_class_select.select(selected)


func _on_selection_changed(_index: int) -> void:
	_update_details()


func _selected_class() -> int:
	if _class_select == null or _class_select.item_count == 0:
		return -1
	var metadata: Variant = _class_select.get_item_metadata(maxi(_class_select.selected, 0))
	return int(metadata) if metadata != null else -1


func _selected_master() -> MasterData:
	if _master_select.item_count == 0:
		return null
	var metadata: Variant = _master_select.get_item_metadata(maxi(_master_select.selected, 0))
	return Roster.find_master(String(metadata))


func _update_details() -> void:
	var class_id: int = _selected_class()
	var master: MasterData = _selected_master()
	var lines: PackedStringArray = PackedStringArray()
	if class_id >= 0:
		lines.append("%s  |  The server rolls a hidden Heroic Spirit of this class at match start." % Roster.class_name_for(class_id).to_upper())
		lines.append("Class Triangle: Knight Saber > Lancer > Archer > Saber. Cavalry Rider > Caster > Assassin > Rider. Berserker 1.5x dealt/taken. Ruler 0.75x taken from standard classes, 1.5x from Avenger.")
	if master != null:
		lines.append("Master: %s  Mana %d  Regen %.1f/s  Vision %d  |  Signature: %s  |  Trump: %s" % [
			master.display_name, int(master.max_mana), master.mana_regeneration,
			int(master.vision_radius), master.signature_command_spell, master.master_trump_card,
		])
	_details_label.text = "\n".join(lines)


func _on_summon_specific() -> void:
	var master: MasterData = _selected_master()
	var class_id: int = _selected_class()
	if master == null or class_id < 0:
		_status_label.text = "Select both a Master and a Servant Class."
		return
	_resolved = false
	_deploy_button.disabled = true
	_status_label.text = "Requesting summon: %s + Unknown [%s]..." % [master.display_name, Roster.class_name_for(class_id)]
	summon_requested.emit(master.master_id, class_id, Roster.RollMode.SPECIFIC)


func _on_random_class() -> void:
	var master: MasterData = _selected_master()
	if master == null:
		_status_label.text = "Select a Master first, then request a random Servant Class."
		return
	_resolved = false
	_deploy_button.disabled = true
	_status_label.text = "Server is rolling a random Servant Class for %s..." % master.display_name
	summon_requested.emit(master.master_id, -1, Roster.RollMode.RANDOM_SERVANT)


func _on_random_pair() -> void:
	_resolved = false
	_deploy_button.disabled = true
	_status_label.text = "Server is rolling a random Master and Servant Class..."
	summon_requested.emit("", -1, Roster.RollMode.RANDOM_PAIR)


func _on_deploy() -> void:
	if not _resolved:
		return
	_deploy_button.disabled = true
	_deploy_button.text = "DEPLOYING..."
	deploy_requested.emit()


func _on_match_mode_pressed(mode: int) -> void:
	if not is_host:
		return
	match_mode_requested.emit(mode)


func _on_add_ai_specific() -> void:
	if not is_host:
		return
	var master: MasterData = _selected_master()
	var class_id: int = _selected_class()
	if master == null or class_id < 0:
		_status_label.text = "Select a Master and Servant Class before adding a specific AI."
		return
	ai_add_requested.emit(master.master_id, class_id, Roster.RollMode.SPECIFIC)


func _on_add_ai_random() -> void:
	if not is_host:
		return
	ai_add_requested.emit("", -1, Roster.RollMode.RANDOM_PAIR)


func _on_reclaim() -> void:
	var session_id: String = _session_input.text.strip_edges()
	if session_id.is_empty():
		_status_label.text = "Enter the session ID from the previous connection."
		return
	reclaim_requested.emit(session_id)


func _capacity_for_mode() -> int:
	return 15 if _current_mode == MatchConfig.MatchMode.APOCRYPHA_7V7 else 7
