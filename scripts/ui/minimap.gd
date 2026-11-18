class_name TacticalMinimap
extends Control
## Corner minimap with terrain, Leyline ownership, unit icons and click-to-pan.

signal pan_requested(world_position: Vector2)

const ICON_SIZE: float = 3.0
const MASTER_ICON: float = 4.5

var arena: Node2D

var _hovering: bool = false
var _snapshot: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(206.0, 132.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _process(_delta: float) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	if arena.has_method("get_minimap_snapshot"):
		_snapshot = arena.call("get_minimap_snapshot")
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovering = true


func _on_mouse_exited() -> void:
	_hovering = false


func _gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var world: Vector2 = _local_to_world(mouse_event.position)
	pan_requested.emit(world)
	accept_event()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.02, 0.028, 0.06, 0.88))
	draw_rect(rect, Color(0.55, 0.42, 0.8, 0.85), false, 1.5)
	if _snapshot.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(8.0, 18.0), "TACTICAL MAP", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(0.7, 0.74, 0.88))
		return

	var bounds_min: Vector2 = _snapshot.get("bounds_min", Vector2(-720.0, -400.0))
	var bounds_max: Vector2 = _snapshot.get("bounds_max", Vector2(720.0, 400.0))
	var world_size: Vector2 = bounds_max - bounds_min
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		return
	var inner: Rect2 = rect.grow(-5.0)

	# Terrain plate and central Grail circle.
	draw_rect(inner, Color(0.05, 0.065, 0.115, 0.9))
	draw_rect(inner, Color(0.18, 0.22, 0.34, 0.7), false, 1.0)
	var center: Vector2 = _world_to_local(Vector2.ZERO)
	var radius: float = 150.0 / world_size.x * inner.size.x
	draw_circle(center, maxf(radius, 2.0), Color(0.36, 0.24, 0.6, 0.22))

	# Leylines.
	for leyline_variant: Variant in _snapshot.get("leylines", []):
		var leyline: Dictionary = leyline_variant
		var point: Vector2 = _world_to_local(leyline.get("position", Vector2.ZERO))
		var owner_id: int = int(leyline.get("owner", 0))
		var colour: Color = Color(0.62, 0.46, 0.95, 0.95)
		if owner_id != 0:
			colour = Color.from_hsv(fmod(float(owner_id) * 0.173, 1.0), 0.55, 0.98)
		draw_circle(point, 4.0, Color(colour.r, colour.g, colour.b, 0.28))
		draw_arc(point, 4.0, 0.0, TAU, 14, colour, 1.4, true)

	# Units.
	for unit_variant: Variant in _snapshot.get("units", []):
		var unit: Dictionary = unit_variant
		if not bool(unit.get("visible", true)):
			continue
		var point: Vector2 = _world_to_local(unit.get("position", Vector2.ZERO))
		var relation: String = String(unit.get("relation", "enemy"))
		var colour: Color = Color(0.9, 0.35, 0.38, 0.95)
		match relation:
			"own":
				colour = Color(0.35, 0.95, 0.8, 1.0)
			"ally":
				colour = Color(0.45, 0.68, 1.0, 0.95)
			"neutral":
				colour = Color(0.85, 0.82, 0.55, 0.9)
		var is_servant: bool = bool(unit.get("is_servant", true))
		var half: float = ICON_SIZE if is_servant else MASTER_ICON
		if bool(unit.get("stealthed", false)):
			colour.a *= 0.55
		if is_servant:
			draw_circle(point, half, colour)
		else:
			draw_rect(Rect2(point - Vector2(half, half), Vector2(half, half) * 2.0), colour)

	# Camera view rectangle.
	var camera_rect: Rect2 = _snapshot.get("camera_rect", Rect2())
	if camera_rect.size.length_squared() > 0.0:
		var top_left: Vector2 = _world_to_local(camera_rect.position)
		var bottom_right: Vector2 = _world_to_local(camera_rect.position + camera_rect.size)
		draw_rect(Rect2(top_left, bottom_right - top_left), Color(0.85, 0.9, 1.0, 0.35), false, 1.0)

	draw_string(ThemeDB.fallback_font, Vector2(7.0, 13.0), "TACTICAL", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(0.7, 0.75, 0.9, 0.9))
	if _hovering:
		draw_rect(rect, Color(0.55, 0.85, 1.0, 0.55), false, 1.5)


func _world_to_local(world: Vector2) -> Vector2:
	var bounds_min: Vector2 = _snapshot.get("bounds_min", Vector2(-720.0, -400.0))
	var bounds_max: Vector2 = _snapshot.get("bounds_max", Vector2(720.0, 400.0))
	var world_size: Vector2 = bounds_max - bounds_min
	var inner: Rect2 = Rect2(Vector2.ZERO, size).grow(-5.0)
	var normalised: Vector2 = (world - bounds_min) / world_size
	return inner.position + normalised * inner.size


func _local_to_world(local: Vector2) -> Vector2:
	var bounds_min: Vector2 = _snapshot.get("bounds_min", Vector2(-720.0, -400.0))
	var bounds_max: Vector2 = _snapshot.get("bounds_max", Vector2(720.0, 400.0))
	var world_size: Vector2 = bounds_max - bounds_min
	var inner: Rect2 = Rect2(Vector2.ZERO, size).grow(-5.0)
	var normalised: Vector2 = (local - inner.position) / inner.size
	return bounds_min + normalised * world_size
