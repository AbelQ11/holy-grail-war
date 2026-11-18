class_name CommandSpellSigils
extends Control
## Diegetic Command Spell display: three crest sigils that shatter as charges
## are spent. Slot 1 carries a gold border while the Master's unique Signature
## Command Spell is still available.

const SLOT_COUNT: int = 3
const SLOT_WIDTH: float = 38.0
const SLOT_HEIGHT: float = 34.0
const SHATTER_MSEC: int = 480

var charges_left: int = SLOT_COUNT
var signature_used: bool = false

var _displayed_charges: int = SLOT_COUNT
var _initialized: bool = false
var _shatter_start: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(SLOT_WIDTH * SLOT_COUNT + 8.0, SLOT_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func set_state(new_charges: int, new_signature_used: bool) -> void:
	var clamped: int = clampi(new_charges, 0, SLOT_COUNT)
	if not _initialized:
		_displayed_charges = clamped
		_initialized = true
	elif clamped < _displayed_charges:
		var now: int = Time.get_ticks_msec()
		for slot: int in range(clamped, _displayed_charges):
			_shatter_start[slot] = now
	_displayed_charges = clamped
	charges_left = clamped
	signature_used = new_signature_used


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var label_colour: Color = Color(0.82, 0.72, 0.55, 0.9)
	draw_string(ThemeDB.fallback_font, Vector2(0.0, 9.0), "COMMAND SPELLS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, label_colour)
	for slot: int in range(SLOT_COUNT):
		var center: Vector2 = Vector2(SLOT_WIDTH * 0.5 + float(slot) * SLOT_WIDTH + 2.0, SLOT_HEIGHT * 0.58)
		_draw_sigil(slot, center)


func _draw_sigil(slot: int, center: Vector2) -> void:
	var spent: bool = slot >= charges_left
	var is_signature_slot: bool = slot == 0 and not signature_used
	var now: int = Time.get_ticks_msec()

	var main: Color = Color(0.92, 0.16, 0.24, 1.0) if not spent else Color(0.32, 0.12, 0.16, 0.55)
	if is_signature_slot:
		main = Color(1.0, 0.22, 0.28, 1.0)

	var glow_pulse: float = 0.55 + 0.45 * sin(float(now) * 0.004 + float(slot) * 1.7)
	var radius: float = 12.0
	if not spent:
		draw_circle(center, radius + 3.0, Color(main.r, main.g, main.b, 0.10 + 0.06 * glow_pulse))
		draw_arc(center, radius + 1.5, 0.0, TAU, 28, Color(main.r, main.g, main.b, 0.55), 1.2, true)

	if is_signature_slot:
		# Gold border identifies the unique Signature Command Spell in slot 1.
		draw_arc(center, radius + 4.5, 0.0, TAU, 30, Color(0.95, 0.78, 0.32, 0.95), 2.0, true)

	if spent:
		_draw_shattered(slot, center, main, now)
		return

	# Three-pointed Command Spell crest.
	for index: int in range(3):
		var angle: float = -PI * 0.5 + TAU * float(index) / 3.0
		var tip: Vector2 = center + Vector2(cos(angle), sin(angle)) * (radius + 4.0)
		var left: Vector2 = center + Vector2(cos(angle - 0.34), sin(angle - 0.34)) * (radius * 0.42)
		var right: Vector2 = center + Vector2(cos(angle + 0.34), sin(angle + 0.34)) * (radius * 0.42)
		draw_colored_polygon(PackedVector2Array([left, tip, right]), main)
	draw_circle(center, 3.2, Color(1.0, 0.85, 0.7, 0.95))
	draw_arc(center, radius * 0.52, 0.0, TAU, 20, Color(1.0, 0.72, 0.55, 0.85), 1.0, true)


func _draw_shattered(slot: int, center: Vector2, colour: Color, now: int) -> void:
	var start: int = int(_shatter_start.get(slot, 0))
	var progress: float = 1.0
	if start > 0:
		progress = clampf(float(now - start) / float(SHATTER_MSEC), 0.0, 1.0)
	var fade: float = 1.0 - progress
	var spread: float = 6.0 + progress * 16.0

	for index: int in range(4):
		var angle: float = -PI * 0.5 + TAU * float(index) / 4.0 + 0.4
		var fragment_center: Vector2 = center + Vector2(cos(angle), sin(angle)) * spread
		var fragment: PackedVector2Array = PackedVector2Array([
			fragment_center + Vector2(0.0, -4.0),
			fragment_center + Vector2(3.5, 3.0),
			fragment_center + Vector2(-3.0, 2.4),
		])
		draw_colored_polygon(fragment, Color(colour.r, colour.g, colour.b, 0.45 * fade))

	# Cracks across the dead crest.
	draw_line(center + Vector2(-9.0, -7.0), center + Vector2(2.0, 1.0), Color(0.1, 0.04, 0.06, 0.9), 1.2, true)
	draw_line(center + Vector2(2.0, 1.0), center + Vector2(8.0, -6.0), Color(0.1, 0.04, 0.06, 0.9), 1.0, true)
	draw_line(center + Vector2(2.0, 1.0), center + Vector2(5.0, 9.0), Color(0.1, 0.04, 0.06, 0.9), 1.0, true)
	draw_arc(center, 11.0, 0.0, TAU, 24, Color(0.22, 0.09, 0.12, 0.5), 1.0, true)
