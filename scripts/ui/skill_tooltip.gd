class_name SkillTooltip
extends Control
## Clock Tower / Chaldea styled hover tooltip. It never captures the mouse and
## follows the cursor, so hovering over action buttons cannot flicker.

var _panel: PanelContainer
var _title: Label
var _meta: Label
var _body: Label
var _extra: Label

const OFFSET: Vector2 = Vector2(18.0, 18.0)
const MAX_WIDTH: float = 380.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	visible = false
	set_process(false)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(320.0, 0.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.085, 0.98)
	style.border_color = Color(0.72, 0.58, 0.28, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	style.border_width_left = 3
	style.border_color = Color(0.72, 0.58, 0.28, 0.95)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	_panel.add_child(column)

	_title = _make_label(15, Color(0.98, 0.88, 0.58))
	column.add_child(_title)
	_meta = _make_label(11, Color(0.66, 0.78, 1.0))
	column.add_child(_meta)
	_body = _make_label(11, Color(0.78, 0.82, 0.94))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(330.0, 0.0)
	column.add_child(_body)
	_extra = _make_label(10, Color(0.62, 0.68, 0.82))
	_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_extra.custom_minimum_size = Vector2(330.0, 0.0)
	column.add_child(_extra)


func _make_label(font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func show_skill(title: String, description: String, mana_cost: float = -1.0, cooldown: float = -1.0, extra: String = "") -> void:
	if _panel == null:
		return
	_title.text = title
	var meta_parts: PackedStringArray = PackedStringArray()
	if mana_cost >= 0.0:
		meta_parts.append("MANA %d" % int(round(mana_cost)))
	if cooldown >= 0.0:
		meta_parts.append("COOLDOWN %.1fs" % cooldown)
	_meta.text = "   ".join(meta_parts)
	_meta.visible = not meta_parts.is_empty()
	_body.text = description
	_extra.text = extra
	_extra.visible = not extra.is_empty()
	_panel.visible = true
	visible = true
	_layout()
	set_process(true)


func show_text(title: String, body_text: String, extra_text: String = "") -> void:
	if _panel == null:
		return
	_title.text = title
	_meta.visible = false
	_body.text = body_text
	_extra.text = extra_text
	_extra.visible = not extra_text.is_empty()
	_panel.visible = true
	visible = true
	_layout()
	set_process(true)


func hide_tooltip() -> void:
	visible = false
	set_process(false)


func _process(_delta: float) -> void:
	_layout()


func _layout() -> void:
	if _panel == null:
		return
	_panel.reset_size()
	var desired: Vector2 = _panel.get_combined_minimum_size()
	desired.x = minf(desired.x, MAX_WIDTH)
	_panel.size = desired
	size = desired
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var position_value: Vector2 = get_viewport().get_mouse_position() + OFFSET
	position_value.x = clampf(position_value.x, 4.0, maxf(viewport_size.x - desired.x - 4.0, 4.0))
	position_value.y = clampf(position_value.y, 4.0, maxf(viewport_size.y - desired.y - 4.0, 4.0))
	position = position_value
