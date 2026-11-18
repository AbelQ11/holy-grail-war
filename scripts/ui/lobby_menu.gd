extends Control
## Pre-match Waiting Lobby.
## Owned data lives in MatchDirector. Players choose a globally unique Master and
## a Servant Class (the named Servant is secretly rolled at match start).

var _director: Node
var _mode_label: Label
var _stage_label: Label
var _slots_box: HBoxContainer
var _master_select: OptionButton
var _class_select: OptionButton
var _ready_check: CheckButton
var _status_label: Label
var _ai_fill_check: CheckButton
var _spectate_check: CheckButton
var _start_button: Button
var _shuffle_button: Button
var _summon_button: Button
var _ready_panel: Control
var _host_panel: Control
var _leave_button: Button
var _tooltip: SkillTooltip
var _class_badge: Button
var _master_detail: Label

var _masters: Array[MasterData] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_director = get_node_or_null("/root/MatchDirector")
	_masters = Roster.get_masters()
	_build_ui()
	if _director != null:
		if not _director.is_connected("lobby_changed", Callable(self, "_refresh")):
			_director.connect("lobby_changed", Callable(self, "_refresh"))
		if not _director.is_connected("notification", Callable(self, "_on_notification")):
			_director.connect("notification", Callable(self, "_on_notification"))
		if not multiplayer.is_server():
			if _is_connected_to_server():
				_director.call("request_lobby_state")
			elif not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
				multiplayer.connected_to_server.connect(_on_connected_to_server)
	_refresh()
	if _director != null:
		var notice: String = String(_director.call("consume_lobby_notice"))
		if not notice.is_empty() and _status_label != null:
			_status_label.text = notice


func _is_connected_to_server() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _on_connected_to_server() -> void:
	if _director != null:
		_director.call("request_lobby_state")


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.012, 0.018, 0.04)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin: MarginContainer = MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)

	var panel: PanelContainer = PanelContainer.new()
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.055, 0.10, 0.99)
	panel_style.border_color = Color(0.55, 0.4, 0.82, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	margin.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)

	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var title: Label = Label.new()
	title.text = "WAITING LOBBY"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.7))
	header.add_child(title)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 13)
	_mode_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	header.add_child(_mode_label)
	_stage_label = Label.new()
	_stage_label.add_theme_font_size_override("font_size", 12)
	_stage_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	header.add_child(_stage_label)

	var slots_scroll: ScrollContainer = ScrollContainer.new()
	slots_scroll.custom_minimum_size = Vector2(0.0, 198.0)
	slots_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(slots_scroll)
	_slots_box = HBoxContainer.new()
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_box.add_theme_constant_override("separation", 20)
	slots_scroll.add_child(_slots_box)

	column.add_child(HSeparator.new())

	var selectors: HBoxContainer = HBoxContainer.new()
	selectors.add_theme_constant_override("separation", 8)
	column.add_child(selectors)
	_master_select = OptionButton.new()
	_master_select.custom_minimum_size = Vector2(300.0, 32.0)
	selectors.add_child(_master_select)
	_class_select = OptionButton.new()
	_class_select.custom_minimum_size = Vector2(250.0, 32.0)
	selectors.add_child(_class_select)
	_master_detail = Label.new()
	_master_detail.add_theme_font_size_override("font_size", 11)
	_master_detail.add_theme_color_override("font_color", Color(0.66, 0.72, 0.86))
	selectors.add_child(_master_detail)

	var preview_row: HBoxContainer = HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 5)
	column.add_child(preview_row)
	_class_badge = Button.new()
	_class_badge.text = "CLASS: -"
	_class_badge.flat = true
	_class_badge.focus_mode = Control.FOCUS_NONE
	_class_badge.add_theme_color_override("font_color", Color(0.88, 0.78, 0.5))
	_class_badge.mouse_entered.connect(_show_class_tooltip)
	_class_badge.mouse_exited.connect(_hide_tooltip)
	preview_row.add_child(_class_badge)
	_make_preview_button(preview_row, "MASTER SKILL 1", _show_master_skill.bind(0))
	_make_preview_button(preview_row, "MASTER SKILL 2", _show_master_skill.bind(1))
	_make_preview_button(preview_row, "SIGNATURE CS", _show_signature_spell)
	_make_preview_button(preview_row, "TRUMP CARD", _show_trump_card)

	var summon_row: HBoxContainer = HBoxContainer.new()
	summon_row.add_theme_constant_override("separation", 8)
	column.add_child(summon_row)
	_summon_button = _make_button(summon_row, "SUMMON MASTER + CLASS", _on_summon_selected)
	_make_button(summon_row, "RANDOM CLASS", _on_random_class)
	_make_button(summon_row, "RANDOM SUMMON", _on_random_summon)

	_ready_panel = HBoxContainer.new()
	_ready_panel.add_theme_constant_override("separation", 10)
	column.add_child(_ready_panel)
	_ready_check = CheckButton.new()
	_ready_check.text = "READY"
	_ready_check.toggled.connect(_on_ready_toggled)
	_ready_panel.add_child(_ready_check)
	var leave_spacer: Control = Control.new()
	leave_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_panel.add_child(leave_spacer)
	_leave_button = Button.new()
	_leave_button.text = "LEAVE LOBBY / DISCONNECT"
	_leave_button.pressed.connect(_on_leave)
	_ready_panel.add_child(_leave_button)

	_host_panel = VBoxContainer.new()
	_host_panel.add_theme_constant_override("separation", 5)
	column.add_child(_host_panel)

	var mode_row: HBoxContainer = HBoxContainer.new()
	_host_panel.add_child(mode_row)
	_make_button(mode_row, "FUYUKI FFA", _on_mode_ffa)
	_make_button(mode_row, "APOCRYPHA 15", _on_mode_apocrypha)
	_ai_fill_check = CheckButton.new()
	_ai_fill_check.text = "Auto-Fill Empty Slots on Start"
	_ai_fill_check.button_pressed = true
	_ai_fill_check.toggled.connect(_on_auto_fill_toggled)
	mode_row.add_child(_ai_fill_check)
	_spectate_check = CheckButton.new()
	_spectate_check.text = "Spectate Full AI War"
	_spectate_check.toggled.connect(_on_spectate_toggled)
	mode_row.add_child(_spectate_check)

	var ai_row: HBoxContainer = HBoxContainer.new()
	_host_panel.add_child(ai_row)
	_make_button(ai_row, "ADD AI (SELECTED)", _on_add_ai_selected)
	_make_button(ai_row, "ADD AI (RANDOM)", _on_add_ai_random)
	_make_button(ai_row, "REMOVE AI", _on_remove_ai)
	_make_button(ai_row, "FILL WITH AI", _on_fill_ai)
	_shuffle_button = _make_button(ai_row, "SHUFFLE FACTIONS", _on_shuffle_factions)
	_start_button = Button.new()
	_start_button.text = "START WAR"
	_start_button.custom_minimum_size = Vector2(130.0, 34.0)
	_start_button.add_theme_font_size_override("font_size", 15)
	_start_button.pressed.connect(_on_start)
	ai_row.add_child(_start_button)

	_status_label = Label.new()
	_status_label.text = "Choose a Master and Servant Class."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.9))
	column.add_child(_status_label)

	_build_tooltip()


func _make_button(parent: Node, text: String, callable: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 32.0)
	button.pressed.connect(callable)
	parent.add_child(button)
	return button


func _make_preview_button(parent: Node, text: String, show_callable: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 10)
	button.mouse_entered.connect(show_callable)
	button.mouse_exited.connect(_hide_tooltip)
	parent.add_child(button)


func _build_tooltip() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 95
	add_child(layer)
	_tooltip = SkillTooltip.new()
	_tooltip.name = "SkillTooltip"
	layer.add_child(_tooltip)


func _refresh() -> void:
	if _director == null:
		return
	var mode: int = int(_director.get("mode"))
	var stage: int = int(_director.get("draft_stage"))
	var spectator: bool = bool(_director.get("spectator_mode"))
	var local_entry: Dictionary = _director.call("get_local_entry")
	_mode_label.text = MatchConfig.mode_name(mode)
	_stage_label.text = _stage_text(mode, stage)
	_ai_fill_check.set_pressed_no_signal(bool(_director.get("auto_fill")))
	_spectate_check.set_pressed_no_signal(spectator)
	_host_panel.visible = multiplayer.get_unique_id() == 1
	_shuffle_button.visible = mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and stage == 0
	_ready_check.set_pressed_no_signal(bool(local_entry.get("ready", false)))
	_ready_check.visible = not local_entry.is_empty() and not bool(local_entry.get("is_ai", false))
	_populate_masters(mode, local_entry)
	_master_select.disabled = mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and stage >= 2
	_populate_classes(mode, stage, local_entry)
	_update_control_labels(mode, stage, local_entry)
	_rebuild_slots()
	_update_preview_badge()
	if spectator:
		_status_label.text = "SPECTATOR_AI_WAR: a full 15-slot AI draft will be generated."
	elif local_entry.is_empty():
		_status_label.text = "Choose a Master. The named Servant is rolled secretly at match start."
	elif bool(local_entry.get("ready", false)):
		_status_label.text = "READY. Waiting for the host to start the war."
	else:
		_status_label.text = "Loadout synchronized. Toggle READY when prepared."


func _stage_text(mode: int, stage: int) -> String:
	if mode == MatchConfig.MatchMode.FUYUKI_FFA:
		return "STAGE: MASTER + CLASS"
	match stage:
		0:
			return "STAGE 1: MASTER SELECTION"
		1:
			return "STAGE 2: FACTION SHUFFLE"
		2:
			return "STAGE 3: CLASS SELECTION"
	return "STAGE: READY"


func _populate_masters(mode: int, local_entry: Dictionary) -> void:
	var local_id: int = multiplayer.get_unique_id()
	var claimed: Array = _director.call("get_claimed_master_ids", local_id)
	var current_master: String = String(local_entry.get("master_id", ""))
	var previous: String = ""
	if _master_select.item_count > 0 and _master_select.selected >= 0:
		var meta: Variant = _master_select.get_item_metadata(_master_select.selected)
		if meta != null:
			previous = String(meta)
	_master_select.clear()
	var selected_index: int = 0
	for index: int in range(_masters.size()):
		var master: MasterData = _masters[index]
		_master_select.add_item(master.display_name)
		_master_select.set_item_metadata(index, master.master_id)
		var locked: bool = claimed.has(master.master_id) and master.master_id != current_master
		_master_select.set_item_disabled(index, locked)
		if master.master_id == current_master or (current_master.is_empty() and master.master_id == previous):
			selected_index = index
		if current_master.is_empty() and locked:
			_master_select.set_item_disabled(index, true)
	_master_select.select(selected_index)


func _populate_classes(mode: int, stage: int, local_entry: Dictionary) -> void:
	var local_id: int = multiplayer.get_unique_id()
	var current_class: int = int(local_entry.get("class_id", -1))
	var previous_class: int = -1
	if _class_select.item_count > 0 and _class_select.selected >= 0:
		var meta: Variant = _class_select.get_item_metadata(_class_select.selected)
		if meta != null:
			previous_class = int(meta)
	_class_select.clear()
	var team: int = int(local_entry.get("team", -1))
	var used: Array = []
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7:
		used = _director.call("get_team_classes", team, local_id)
	else:
		var entries: Dictionary = _director.get("entries")
		for key: Variant in entries.keys():
			if int(key) == local_id:
				continue
			var other: Dictionary = entries[key]
			var other_class: int = int(other.get("class_id", -1))
			if other_class >= 0 and not used.has(other_class):
				used.append(other_class)
	var selected_index: int = 0
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and stage == 0:
		_class_select.add_item("MASTER SELECTION ONLY")
		_class_select.set_item_metadata(0, -1)
		_class_select.set_item_disabled(0, true)
		_class_select.disabled = true
		return
	_class_select.disabled = false
	var all_classes: Array = Roster.get_class_ids()
	for index: int in range(all_classes.size()):
		var class_id: int = int(all_classes[index])
		if mode == MatchConfig.MatchMode.APOCRYPHA_7V7:
			if team == MatchConfig.Team.NEUTRAL:
				if class_id != ServantData.ServantClass.RULER:
					continue
			elif not STANDARD_CLASSES_LOCAL.has(class_id):
				continue
		_class_select.add_item(Roster.class_name_for(class_id))
		_class_select.set_item_metadata(_class_select.item_count - 1, class_id)
		var locked: bool = used.has(class_id) and class_id != current_class
		_class_select.set_item_disabled(_class_select.item_count - 1, locked)
		if class_id == current_class or (current_class < 0 and class_id == previous_class):
			selected_index = _class_select.item_count - 1
	_class_select.select(selected_index)


func _update_control_labels(mode: int, stage: int, local_entry: Dictionary) -> void:
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and stage == 0:
		_summon_button.text = "LOCK MASTER (STAGE 1)"
		_class_select.disabled = true
	elif mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and stage >= 2:
		_summon_button.text = "CONFIRM CLASS"
	else:
		_summon_button.text = "SUMMON MASTER + CLASS"


func _rebuild_slots() -> void:
	for child: Node in _slots_box.get_children():
		child.queue_free()
	var mode: int = int(_director.get("mode"))
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7:
		var red_column: VBoxContainer = _make_slot_column("RED FACTION")
		var black_column: VBoxContainer = _make_slot_column("BLACK FACTION")
		var arbiter_column: VBoxContainer = _make_slot_column("ARBITER")
		_slots_box.add_child(red_column)
		_slots_box.add_child(black_column)
		_slots_box.add_child(arbiter_column)
		_fill_team_column(red_column, MatchConfig.Team.RED, 7)
		_fill_team_column(black_column, MatchConfig.Team.BLACK, 7)
		_fill_team_column(arbiter_column, MatchConfig.Team.NEUTRAL, 1)
	else:
		var ffa_column: VBoxContainer = _make_slot_column("FUYUKI FFA")
		_slots_box.add_child(ffa_column)
		_fill_team_column(ffa_column, -1, 7)


func _make_slot_column(title: String) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3)
	var heading: Label = Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 12)
	heading.add_theme_color_override("font_color", Color(0.82, 0.74, 0.55))
	column.add_child(heading)
	return column


func _fill_team_column(column: VBoxContainer, team: int, capacity: int) -> void:
	var entries: Array = _sorted_entries(team)
	for slot: int in range(capacity):
		var text: String = "SLOT %d  EMPTY" % (slot + 1)
		if slot < entries.size():
			text = _slot_text(slot + 1, entries[slot])
		column.add_child(_slot_label(text))


func _sorted_entries(team: int) -> Array:
	var entries: Dictionary = _director.get("entries")
	var result: Array = []
	for key: Variant in entries.keys():
		var entry: Dictionary = entries[key]
		if team >= 0 and int(entry.get("team", -1)) != team:
			continue
		result.append({"id": int(key), "entry": entry})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return result


func _slot_text(slot: int, wrapper: Dictionary) -> String:
	var peer_id: int = int(wrapper["id"])
	var entry: Dictionary = wrapper["entry"]
	var identity: String = "AI%d" % int(entry.get("ai_slot", 0)) if bool(entry.get("is_ai", false)) else "P%d" % peer_id
	if peer_id == multiplayer.get_unique_id():
		identity += " (you)"
	var ready_text: String = "READY" if bool(entry.get("ready", false)) else "SELECTING"
	if bool(entry.get("spectating", false)):
		ready_text = "SPECTATOR"
	var class_id: int = int(entry.get("class_id", -1))
	var class_text: String = Roster.class_name_for(class_id) if class_id >= 0 else "NO CLASS YET"
	return "SLOT %d  %s  |  %s + %s  [%s]" % [
		slot, identity, String(entry.get("master_name", "?")), class_text, ready_text,
	]


func _slot_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.88))
	return label


func _selected_master() -> MasterData:
	if _master_select.item_count == 0:
		return null
	var meta: Variant = _master_select.get_item_metadata(_master_select.selected)
	return Roster.find_master(String(meta)) if meta != null else null


func _selected_class() -> int:
	if _class_select.item_count == 0:
		return -1
	var meta: Variant = _class_select.get_item_metadata(_class_select.selected)
	return int(meta) if meta != null else -1


func _on_summon_selected() -> void:
	var master: MasterData = _selected_master()
	if master == null:
		_status_label.text = "Choose an unclaimed Master."
		return
	var mode: int = int(_director.get("mode"))
	var stage: int = int(_director.get("draft_stage"))
	var local_entry: Dictionary = _director.call("get_local_entry")
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and stage >= 2 and not local_entry.is_empty():
		var chosen: int = _selected_class()
		if chosen < 0:
			_status_label.text = "Select an available Servant Class."
			return
		_director.call("request_class", chosen)
		return
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and stage == 0:
		_director.call("request_summon", master.master_id, -1, Roster.RollMode.SPECIFIC)
		return
	var chosen: int = _selected_class()
	if chosen < 0:
		_status_label.text = "Select a Servant Class."
		return
	_director.call("request_summon", master.master_id, chosen, Roster.RollMode.SPECIFIC)


func _on_random_class() -> void:
	var mode: int = int(_director.get("mode"))
	var stage: int = int(_director.get("draft_stage"))
	var local_entry: Dictionary = _director.call("get_local_entry")
	if mode == MatchConfig.MatchMode.APOCRYPHA_7V7 and stage >= 2 and not local_entry.is_empty():
		_director.call("request_random_class")
		return
	var master: MasterData = _selected_master()
	if master == null:
		_status_label.text = "Choose an unclaimed Master first."
		return
	_director.call("request_summon", master.master_id, -1, Roster.RollMode.RANDOM_SERVANT)


func _on_random_summon() -> void:
	_director.call("request_summon", "", -1, Roster.RollMode.RANDOM_PAIR)


func _on_ready_toggled(enabled: bool) -> void:
	_director.call("request_player_ready", enabled)


func _on_mode_ffa() -> void:
	_director.call("request_mode", MatchConfig.MatchMode.FUYUKI_FFA)


func _on_mode_apocrypha() -> void:
	_director.call("request_mode", MatchConfig.MatchMode.APOCRYPHA_7V7)


func _on_auto_fill_toggled(enabled: bool) -> void:
	_director.call("request_auto_fill", enabled)


func _on_spectate_toggled(enabled: bool) -> void:
	_director.call("request_spectator_mode", enabled)


func _on_add_ai_selected() -> void:
	var master: MasterData = _selected_master()
	if master == null:
		_status_label.text = "Select an unclaimed Master for the AI."
		return
	_director.call("request_add_ai", master.master_id, _selected_class(), Roster.RollMode.SPECIFIC)


func _on_add_ai_random() -> void:
	_director.call("request_add_ai", "", -1, Roster.RollMode.RANDOM_PAIR)


func _on_remove_ai() -> void:
	_director.call("request_remove_ai")


func _on_fill_ai() -> void:
	_director.call("request_fill_ai")


func _on_shuffle_factions() -> void:
	_director.call("request_shuffle_factions")


func _on_start() -> void:
	_director.call("request_start_match")


func _on_leave() -> void:
	if _director != null:
		_director.call("leave_lobby")


func _on_notification(message: String) -> void:
	_status_label.text = message


func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.hide_tooltip()


func _show_master_skill(slot: int) -> void:
	var master: MasterData = _selected_master()
	if _tooltip == null or master == null:
		_hide_tooltip()
		return
	var title: String = master.skill_1_name if slot == 0 else master.skill_2_name
	var desc: String = master.skill_1_desc if slot == 0 else master.skill_2_desc
	var cost: float = master.skill_1_cost if slot == 0 else master.skill_2_cost
	var cooldown: float = master.skill_1_cooldown if slot == 0 else master.skill_2_cooldown
	_tooltip.show_skill(title, desc, cost, cooldown, "Master Magecraft preview  |  %s" % master.display_name)


func _show_signature_spell() -> void:
	var master: MasterData = _selected_master()
	if _tooltip == null or master == null:
		_hide_tooltip()
		return
	_tooltip.show_text("SIGNATURE COMMAND SPELL: %s" % master.signature_command_spell, master.signature_command_spell_desc, "Replaces Command Spell slot 1. Also overrides Servant AI autonomy.")


func _show_trump_card() -> void:
	var master: MasterData = _selected_master()
	if _tooltip == null or master == null:
		_hide_tooltip()
		return
	_tooltip.show_skill(master.master_trump_card, master.trump_card_desc, master.trump_card_mana_cost, master.trump_card_cooldown, "Master Trump Card preview  |  %s" % master.display_name)


func _show_class_tooltip() -> void:
	var class_id: int = _selected_class()
	if _tooltip == null or class_id < 0:
		_hide_tooltip()
		return
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
	_tooltip.show_text("CLASS TRIANGLE - %s" % Roster.class_name_for(class_id).to_upper(), "\\n".join(lines), "Knight: Saber > Lancer > Archer > Saber. Cavalry: Rider > Caster > Assassin > Rider. Berserker 1.5x dealt/taken. Ruler 0.75x taken from standard classes, 1.5x from Avenger.")


func _update_preview_badge() -> void:
	var class_id: int = _selected_class()
	if _class_badge != null:
		_class_badge.text = "CLASS: %s" % Roster.class_name_for(class_id).to_upper() if class_id >= 0 else "CLASS: -"
	var master: MasterData = _selected_master()
	if _master_detail != null:
		_master_detail.text = "" if master == null else "SIGNATURE: %s   |   TRUMP: %s" % [master.signature_command_spell, master.master_trump_card]


const STANDARD_CLASSES_LOCAL: Array = [
	ServantData.ServantClass.SABER,
	ServantData.ServantClass.ARCHER,
	ServantData.ServantClass.LANCER,
	ServantData.ServantClass.RIDER,
	ServantData.ServantClass.CASTER,
	ServantData.ServantClass.ASSASSIN,
	ServantData.ServantClass.BERSERKER,
]
