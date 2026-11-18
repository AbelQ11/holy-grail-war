class_name LeylineNode
extends Area2D
## Capturable Leyline point.
##
## The server resolves capture from overlapping Servants. Ownership is synced to
## clients through a programmatically assembled [MultiplayerSynchronizer], and
## [ServantController] polls this node's owner to grant Master Mana regeneration.

signal ownership_changed(new_owner: int, previous_owner: int)

const GROUP: StringName = &"leyline_nodes"
const CAPTURE_SECONDS: float = 2.5
const CONTEST_DECAY_MULTIPLIER: float = 0.55

@export var leyline_name: String = "Leyline"
@export var capture_radius: float = 82.0
@export var accent_color: Color = Color(0.6, 0.45, 0.95)

## 0 means neutral; otherwise the peer whose Master currently holds this node.
var owner_peer_id: int = 0
var capturing_peer_id: int = 0
var capture_progress: float = 0.0

var _synchronizer: MultiplayerSynchronizer


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = 1 << 1  # servants only
	monitorable = false
	monitoring = true

	_build_collision()
	_build_synchronizer()
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	var occupants: Dictionary = {}
	for body: Node2D in get_overlapping_bodies():
		if not (body is ServantController) and not (body is MasterController):
			continue
		var unit_owner: int = int(body.get("owner_id"))
		var unit_alive: bool = bool(body.get("is_alive"))
		if unit_alive:
			occupants[unit_owner] = true

	if occupants.size() == 1:
		var candidate: int = int(occupants.keys()[0])
		if candidate == owner_peer_id:
			capturing_peer_id = 0
			_decay_progress(delta)
		else:
			if capturing_peer_id != candidate:
				capturing_peer_id = candidate
				capture_progress = 0.0
			capture_progress = minf(capture_progress + (100.0 / CAPTURE_SECONDS) * delta, 100.0)
			if capture_progress >= 100.0:
				_set_owner(candidate)
	else:
		# Empty or contested: progress bleeds away and no one can claim the node.
		capturing_peer_id = 0
		_decay_progress(delta)


func is_point_inside(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= capture_radius


## Clears ownership when the holding peer disconnects. Server-only.
func release_owner() -> void:
	if not multiplayer.is_server():
		return
	if owner_peer_id == 0:
		return
	var previous_owner: int = owner_peer_id
	owner_peer_id = 0
	capturing_peer_id = 0
	capture_progress = 0.0
	ownership_changed.emit(0, previous_owner)
	queue_redraw()


func _decay_progress(delta: float) -> void:
	var decay: float = (100.0 / CAPTURE_SECONDS) * CONTEST_DECAY_MULTIPLIER * delta
	capture_progress = move_toward(capture_progress, 0.0, decay)


func _set_owner(new_owner: int) -> void:
	var previous_owner: int = owner_peer_id
	owner_peer_id = new_owner
	capturing_peer_id = 0
	capture_progress = 0.0
	ownership_changed.emit(new_owner, previous_owner)
	queue_redraw()


func _build_collision() -> void:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = capture_radius
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.name = "CaptureArea"
	collision.shape = shape
	add_child(collision)


func _build_synchronizer() -> void:
	_synchronizer = MultiplayerSynchronizer.new()
	_synchronizer.name = "StateSynchronizer"
	_synchronizer.root_path = NodePath("..")

	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for path: NodePath in [
		NodePath(".:owner_peer_id"),
		NodePath(".:capturing_peer_id"),
		NodePath(".:capture_progress"),
	]:
		config.add_property(path)
		config.property_set_spawn(path, true)

	_synchronizer.replication_config = config
	_synchronizer.replication_interval = 0.1
	add_child(_synchronizer)


func _draw() -> void:
	var owned: bool = owner_peer_id != 0
	var owner_color: Color = _owner_color()
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.003)

	draw_circle(Vector2.ZERO, capture_radius, Color(owner_color.r, owner_color.g, owner_color.b, 0.08))
	draw_arc(Vector2.ZERO, capture_radius, 0.0, TAU, 64, Color(owner_color.r, owner_color.g, owner_color.b, 0.65), 2.0, true)
	draw_circle(Vector2.ZERO, capture_radius * (0.34 + pulse * 0.03), Color(owner_color.r, owner_color.g, owner_color.b, 0.05))

	# Slowly rotating rune spokes.
	var rotation_offset: float = float(Time.get_ticks_msec()) * 0.00035
	for index: int in range(6):
		var angle: float = rotation_offset + TAU * float(index) / 6.0
		var inner: Vector2 = Vector2(cos(angle), sin(angle)) * (capture_radius * 0.42)
		var outer: Vector2 = Vector2(cos(angle), sin(angle)) * (capture_radius * 0.92)
		draw_line(inner, outer, Color(owner_color.r, owner_color.g, owner_color.b, 0.3), 2.0, true)

	if capture_progress > 0.0:
		var capture_color: Color = Color(0.95, 0.82, 0.35, 0.9)
		var end_angle: float = -PI * 0.5 + TAU * (capture_progress / 100.0)
		draw_arc(Vector2.ZERO, capture_radius + 8.0, -PI * 0.5, end_angle, 48, capture_color, 4.0, true)

	var title: String = leyline_name.to_upper()
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-110.0, capture_radius + 24.0),
		title,
		HORIZONTAL_ALIGNMENT_CENTER,
		220.0,
		11,
		Color(owner_color.r, owner_color.g, owner_color.b, 0.9)
	)

	var status: String = "UNCLAIMED"
	if capture_progress > 0.0 and capturing_peer_id != 0:
		status = "CAPTURING P%d %d%%" % [capturing_peer_id, int(round(capture_progress))]
	elif owned:
		status = "HELD BY P%d" % owner_peer_id
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-110.0, capture_radius + 40.0),
		status,
		HORIZONTAL_ALIGNMENT_CENTER,
		220.0,
		10,
		Color(0.72, 0.76, 0.9, 0.85)
	)


func _owner_color() -> Color:
	if owner_peer_id == 0:
		return accent_color
	var hue: float = fmod(float(owner_peer_id) * 0.173, 1.0)
	return Color.from_hsv(hue, 0.55, 0.95)
