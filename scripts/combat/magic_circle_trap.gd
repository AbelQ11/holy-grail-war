class_name MagicCircleTrap
extends Area2D
## Persistent Caster trap. The server owns pulse timing and damage; clients render
## the replicated spawn payload (position, radius, colour) and never roll hits.

var owner_id: int = 1
var source_class: int = -1
var radius: float = 55.0
var damage: float = 22.0
var duration: float = 10.0
var pulse_interval: float = 1.0
var tint: Color = Color(0.7, 0.45, 1.0)

var _time_left: float = 10.0
var _pulse_left: float = 0.45


func _ready() -> void:
	collision_layer = 1 << 4  # traps
	collision_mask = 1 << 1   # servants
	monitorable = false
	monitoring = multiplayer.is_server()
	_time_left = duration
	_pulse_left = 0.45

	_build_collision()

	if not multiplayer.is_server():
		set_physics_process(false)
	queue_redraw()


func configure(payload: Dictionary) -> void:
	owner_id = int(payload.get("owner_id", 1))
	source_class = int(payload.get("source_class", -1))
	position = payload.get("origin", Vector2.ZERO)
	radius = float(payload.get("radius", radius))
	damage = float(payload.get("damage", damage))
	duration = float(payload.get("duration", duration))
	pulse_interval = float(payload.get("pulse_interval", pulse_interval))
	tint = payload.get("color", tint)
	_time_left = duration


func _process(_delta: float) -> void:
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_time_left -= delta
	if _time_left <= 0.0:
		queue_free()
		return

	_pulse_left -= delta
	if _pulse_left > 0.0:
		return

	_pulse_left = pulse_interval
	for body: Node2D in get_overlapping_bodies():
		if body.has_method("receive_damage"):
			var body_owner: int = int(body.get("owner_id"))
			if body_owner != owner_id:
				body.call("receive_damage", damage, owner_id, source_class)


func _build_collision() -> void:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = radius
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.name = "TrapArea"
	collision.shape = shape
	add_child(collision)


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.005)
	var core: Color = Color(tint.r, tint.g, tint.b, 0.12 + pulse * 0.05)
	draw_circle(Vector2.ZERO, radius, core)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(tint.r, tint.g, tint.b, 0.85), 2.5, true)
	draw_arc(Vector2.ZERO, radius * 0.66, 0.0, TAU, 48, Color(tint.r, tint.g, tint.b, 0.45), 1.5, true)

	var rotation_offset: float = float(Time.get_ticks_msec()) * 0.0007
	for index: int in range(8):
		var angle: float = rotation_offset + TAU * float(index) / 8.0
		var inner: Vector2 = Vector2(cos(angle), sin(angle)) * (radius * 0.2)
		var outer: Vector2 = Vector2(cos(angle), sin(angle)) * (radius * 0.92)
		draw_line(inner, outer, Color(tint.r, tint.g, tint.b, 0.35), 1.5, true)

	var rune_color: Color = Color(1.0, 0.9, 0.6, 0.75)
	draw_circle(Vector2.ZERO, 6.0 + pulse * 2.0, rune_color)
