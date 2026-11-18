class_name NpTelegraphLayer
extends Node2D
## Additive ground telegraphs drawn before units: warning rings, beams and
## lanes that flash while a Noble Phantasm winds up.

const AGE_EPSILON: float = 0.001

var _entries: Array[Dictionary] = []


func _ready() -> void:
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	z_as_relative = true
	z_index = 0


func add_telegraph(style: int, origin: Vector2, direction: Vector2, length: float, duration: float, colour: Color) -> void:
	_entries.append({
		"style": style,
		"origin": origin,
		"direction": direction.normalized() if direction.length_squared() > AGE_EPSILON else Vector2.RIGHT,
		"length": maxf(length, 40.0),
		"duration": maxf(duration, 0.05),
		"age": 0.0,
		"colour": colour,
	})
	queue_redraw()


func clear_all() -> void:
	_entries.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _entries.is_empty():
		return
	var index: int = _entries.size() - 1
	while index >= 0:
		var entry: Dictionary = _entries[index]
		entry["age"] = float(entry["age"]) + delta
		if float(entry["age"]) >= float(entry["duration"]):
			_entries.remove_at(index)
		index -= 1
	queue_redraw()


func _draw() -> void:
	for entry_variant: Variant in _entries:
		var entry: Dictionary = entry_variant
		var colour: Color = entry["colour"]
		var age: float = float(entry["age"])
		var duration: float = float(entry["duration"])
		var progress: float = clampf(age / duration, 0.0, 1.0)
		var pulse: float = 0.55 + 0.45 * sin(age * 26.0)
		var alpha: float = (1.0 - progress * 0.35) * pulse
		var origin: Vector2 = entry["origin"]
		var direction: Vector2 = entry["direction"]
		var length: float = float(entry["length"])
		var style: int = int(entry["style"])

		match style:
			ServantData.NoblePhantasmStyle.BEAM:
				var width: float = 26.0 + progress * 16.0
				draw_line(origin, origin + direction * length, Color(colour.r, colour.g, colour.b, 0.12 * alpha), width * 1.8, true)
				draw_line(origin, origin + direction * length, Color(colour.r, colour.g, colour.b, 0.5 * alpha), width * 0.35, true)
				_draw_warning_ring(origin, 30.0 + progress * 12.0, colour, alpha)
			ServantData.NoblePhantasmStyle.DASH:
				var lane: float = 58.0
				_draw_lane(origin, direction, length, lane, colour, alpha, progress)
				_draw_warning_ring(origin, 26.0 + progress * 10.0, colour, alpha)
			ServantData.NoblePhantasmStyle.BARRAGE:
				for offset: int in range(-2, 3):
					var shot: Vector2 = direction.rotated(deg_to_rad(12.0) * float(offset))
					draw_line(origin, origin + shot * length, Color(colour.r, colour.g, colour.b, 0.22 * alpha), 3.0, true)
				_draw_warning_ring(origin, 34.0 + progress * 18.0, colour, alpha)
			ServantData.NoblePhantasmStyle.REALITY_MARBLE:
				_draw_reality_marble(origin, colour, alpha, progress)
			_:
				_draw_warning_ring(origin, length * (0.3 + progress * 0.7), colour, alpha)


func _draw_warning_ring(center: Vector2, radius: float, colour: Color, alpha: float) -> void:
	draw_circle(center, radius, Color(colour.r, colour.g, colour.b, 0.045 * alpha))
	draw_arc(center, radius, 0.0, TAU, 48, Color(colour.r, colour.g, colour.b, 0.68 * alpha), 2.4, true)
	draw_arc(center, radius * 0.62, -PI * 0.5, -PI * 0.5 + TAU * 0.75, 36, Color(1.0, 1.0, 1.0, 0.32 * alpha), 1.4, true)


func _draw_lane(origin: Vector2, direction: Vector2, length: float, half_width: float, colour: Color, alpha: float, progress: float) -> void:
	var side: Vector2 = direction.orthogonal()
	var start: Vector2 = origin
	var end: Vector2 = origin + direction * length
	var polygon: PackedVector2Array = PackedVector2Array([
		start + side * half_width,
		end + side * half_width,
		end - side * half_width,
		start - side * half_width,
	])
	draw_colored_polygon(polygon, Color(colour.r, colour.g, colour.b, 0.07 * alpha))
	draw_line(start + side * half_width, end + side * half_width, Color(colour.r, colour.g, colour.b, 0.55 * alpha), 2.0, true)
	draw_line(start - side * half_width, end - side * half_width, Color(colour.r, colour.g, colour.b, 0.55 * alpha), 2.0, true)
	var tip: Vector2 = start + direction * length * progress
	draw_line(start, tip, Color(1.0, 1.0, 1.0, 0.30 * alpha), 3.0, true)


func _draw_reality_marble(origin: Vector2, colour: Color, alpha: float, progress: float) -> void:
	var max_radius: float = 760.0
	var radius: float = max_radius * progress
	draw_circle(origin, max_radius, Color(colour.r, colour.g, colour.b, 0.03 * alpha))
	draw_arc(origin, radius, 0.0, TAU, 72, Color(colour.r, colour.g, colour.b, 0.6 * alpha), 4.0, true)
	draw_arc(origin, radius * 0.85, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.25 * alpha), 2.0, true)
	for index: int in range(12):
		var angle: float = TAU * float(index) / 12.0 + progress * 0.4
		var inner: Vector2 = origin + Vector2(cos(angle), sin(angle)) * radius * 0.35
		var outer: Vector2 = origin + Vector2(cos(angle), sin(angle)) * radius
		draw_line(inner, outer, Color(colour.r, colour.g, colour.b, 0.28 * alpha), 2.0, true)
