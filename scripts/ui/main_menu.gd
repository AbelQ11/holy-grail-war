extends Control
## Main menu entry point. Hosts/joins ENet sessions and then opens the waiting
## lobby before arena.tscn is ever loaded.

var _ip_edit: LineEdit
var _port_edit: LineEdit
var _status_label: Label
var _host_button: Button
var _join_button: Button
var _spectator_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	var director: Node = get_node_or_null("/root/MatchDirector")
	if director != null:
		director.connect("notification", Callable(self, "_on_notification"))
	var network: Node = get_node_or_null("/root/NetworkManager")
	if network != null:
		network.connect("connection_failed", Callable(self, "_on_connection_failed"))
		network.connect("server_disconnected", Callable(self, "_on_server_disconnected"))


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.015, 0.02, 0.045)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520.0, 0.0)
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.06, 0.11, 0.98)
	panel_style.border_color = Color(0.58, 0.42, 0.85, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title: Label = Label.new()
	title.text = "HOLY GRAIL WAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.7))
	column.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "RTS COMMAND  /  SUMMONING WAR"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.68, 0.84))
	column.add_child(subtitle)

	column.add_child(HSeparator.new())

	var connection_row: HBoxContainer = HBoxContainer.new()
	connection_row.add_theme_constant_override("separation", 8)
	column.add_child(connection_row)
	var ip_label: Label = Label.new()
	ip_label.text = "IP"
	connection_row.add_child(ip_label)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(220.0, 32.0)
	connection_row.add_child(_ip_edit)
	var port_label: Label = Label.new()
	port_label.text = "Port"
	connection_row.add_child(port_label)
	_port_edit = LineEdit.new()
	_port_edit.text = "7777"
	_port_edit.custom_minimum_size = Vector2(80.0, 32.0)
	connection_row.add_child(_port_edit)

	_host_button = Button.new()
	_host_button.text = "HOST MATCH"
	_host_button.custom_minimum_size = Vector2(0.0, 42.0)
	_host_button.pressed.connect(_on_host_pressed)
	column.add_child(_host_button)

	_join_button = Button.new()
	_join_button.text = "JOIN MATCH"
	_join_button.custom_minimum_size = Vector2(0.0, 42.0)
	_join_button.pressed.connect(_on_join_pressed)
	column.add_child(_join_button)

	_spectator_button = Button.new()
	_spectator_button.text = "FULL AI SPECTATOR WAR"
	_spectator_button.custom_minimum_size = Vector2(0.0, 42.0)
	_spectator_button.pressed.connect(_on_spectator_pressed)
	column.add_child(_spectator_button)

	var quit_button: Button = Button.new()
	quit_button.text = "QUIT"
	quit_button.custom_minimum_size = Vector2(0.0, 36.0)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit_button)

	_status_label = Label.new()
	_status_label.text = "Host a war, join a session, or watch a full AI war."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.66, 0.72, 0.86))
	column.add_child(_status_label)


func _on_host_pressed() -> void:
	var director: Node = get_node_or_null("/root/MatchDirector")
	if director != null:
		director.call("host_match", false, _port())
		_set_busy("Opening waiting lobby...")


func _on_join_pressed() -> void:
	var director: Node = get_node_or_null("/root/MatchDirector")
	if director != null:
		director.call("join_match", _ip_edit.text.strip_edges(), _port())
		_set_busy("Connecting to %s..." % _ip_edit.text.strip_edges())


func _on_spectator_pressed() -> void:
	var director: Node = get_node_or_null("/root/MatchDirector")
	if director != null:
		director.call("host_match", true, _port())
		_set_busy("Opening AI spectator lobby...")


func _port() -> int:
	return maxi(int(_port_edit.text.strip_edges()), 1024)


func _set_busy(message: String) -> void:
	_status_label.text = message
	_host_button.disabled = true
	_join_button.disabled = true
	_spectator_button.disabled = true


func _on_notification(message: String) -> void:
	_status_label.text = message
	if _host_button != null:
		_host_button.disabled = false
		_join_button.disabled = false
		_spectator_button.disabled = false


func _on_connection_failed() -> void:
	_status_label.text = "Connection failed. Check the address and port."
	_host_button.disabled = false
	_join_button.disabled = false
	_spectator_button.disabled = false


func _on_server_disconnected() -> void:
	_status_label.text = "The host closed the session."
	_host_button.disabled = false
	_join_button.disabled = false
	_spectator_button.disabled = false
