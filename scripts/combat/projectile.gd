class_name ServantProjectile
extends Area2D
## Server-simulated ability projectile shared by Servants and Masters.
##
## The server advances the projectile and resolves hits; clients receive its
## position through a programmatically built [MultiplayerSynchronizer] and run no
## collision logic. Class-triangle multipliers are applied by the target's
## receive_damage() so all damage sources share the same rules.

var owner_id: int = 1
var source_class: int = -1
var direction: Vector2 = Vector2.RIGHT
var speed: float = 720.0
var damage: float = 18.0
var tint: Color = Color(1.0, 0.9, 0.6)
var lifetime: float = 2.0


func _ready() -> void:
	collision_layer = 1 << 3  # projectiles
	collision_mask = 1 << 1   # servants and masters
	monitoring = true

	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 6.0
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.name = "Hitbox"
	collision.shape = shape
	add_child(collision)

	body_entered.connect(_on_body_entered)
	_build_synchronizer()

	if not multiplayer.is_server():
		monitoring = false
		monitorable = false
		set_physics_process(false)
	queue_redraw()


func configure(payload: Dictionary) -> void:
	owner_id = int(payload.get("owner_id", 1))
	source_class = int(payload.get("source_class", -1))
	position = payload.get("origin", Vector2.ZERO)
	var raw_direction: Vector2 = payload.get("direction", Vector2.RIGHT)
	if raw_direction.length_squared() > 0.0001:
		direction = raw_direction.normalized()
	speed = float(payload.get("speed", speed))
	damage = float(payload.get("damage", damage))
	tint = payload.get("color", tint)


func _build_synchronizer() -> void:
	var sync: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	sync.name = "StateSynchronizer"
	sync.root_path = NodePath("..")

	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	var root_position: NodePath = NodePath(".:position")
	config.add_property(root_position)
	config.property_set_spawn(root_position, true)
	sync.replication_config = config
	sync.replication_interval = 1.0 / 20.0
	add_child(sync)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return

	if body is ServantController:
		var servant: ServantController = body as ServantController
		if servant.owner_id != owner_id and servant.try_appropriate_projectile():
			# Lancelot's Knight of Owner: steal the projectile and return it.
			owner_id = servant.owner_id
			source_class = servant.servant_data.servant_class
			direction = -direction
			damage *= 1.1
			tint = Color(0.72, 0.55, 0.95)
			position += direction * 28.0
			queue_redraw()
			return

	if body.has_method("receive_damage"):
		var body_owner: int = int(body.get("owner_id"))
		if body_owner != owner_id:
			body.call("receive_damage", damage, owner_id, source_class)
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 12.0, Color(tint.r, tint.g, tint.b, 0.18))
	draw_circle(Vector2.ZERO, 5.0, tint)
	draw_line(Vector2.ZERO, -direction * 20.0, Color(tint.r, tint.g, tint.b, 0.45), 2.0, true)
