class_name MasterController
extends CharacterBody2D
## Server-authoritative RTS Master unit.
##
## Masters are fragile but own the Mana economy, two Magecraft skills, and the
## three Command Spells. Their death eliminates the player. They also contest
## Leylines alongside their Servant.

signal health_changed(current: float, maximum: float)
signal mana_changed(current: float, maximum: float)
signal died
signal eliminated(owner_id: int)
signal skill_used(slot: int)
signal command_spell_used(charges_left: int)
signal trump_card_used(card_name: String)
signal signature_decree_used(spell_name: String)
signal trump_telegraph(origin: Vector2, radius: float, duration: float, colour: Color)

const BODY_RADIUS: float = 14.0
const STOP_DISTANCE: float = 10.0
const LEYLINE_GROUP: StringName = &"leyline_nodes"

@export var master_data: MasterData
@export var move_speed: float = 260.0
@export var acceleration: float = 2100.0
@export var friction: float = 2500.0

var owner_id: int = 1
var team_id: int = 0
var spawn_slot: int = 1
var vision_radius: float = 520.0

var health: float = 90.0
var max_health: float = 90.0
var mana: float = 150.0
var max_mana: float = 150.0
var mana_regeneration: float = 8.0
var leylines_held: int = 0
var command_spells_left: int = MasterData.MAX_COMMAND_SPELLS
var is_haste_active: bool = false
var signature_command_spell_used: bool = false
var trump_card_ready: bool = true
var is_shielded: bool = false

var servant_unit: ServantController
var projectile_spawner: MultiplayerSpawner
var match_state: MatchState

var _is_alive: bool = true
var is_alive: bool:
	get:
		return _is_alive

var _move_target: Vector2 = Vector2.ZERO
var _has_move_target: bool = false
var _attack_move: bool = false
var _attack_target: Node2D
var _attack_ready_at_msec: int = 0
var _skill_ready_at_msec: Array[int] = [0, 0]
var _haste_until_msec: int = 0
var _shield_until_msec: int = 0
var _trump_ready_at_msec: int = 0
var _pending_trump_active: bool = false
var _pending_trump_style: int = -1
var _pending_trump_aim: Vector2 = Vector2.RIGHT
var _pending_trump_ready_msec: int = 0
var _collision_shape: CollisionShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 1 << 1
	collision_mask = 1 << 0
	add_to_group("player_units")
	add_to_group("masters")

	if master_data == null:
		master_data = MasterData.new()
	else:
		master_data = master_data.duplicate() as MasterData

	max_health = 55.0 + float(master_data.endurance) * 1.2
	move_speed = 190.0 + float(master_data.agility) * 4.0
	max_mana = master_data.max_mana
	health = max_health
	mana = max_mana
	vision_radius = master_data.vision_radius
	command_spells_left = master_data.command_spell_charges

	_build_collision()
	_build_synchronizer()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_tick(delta)
	queue_redraw()


func _server_tick(delta: float) -> void:
	if not _is_alive:
		_pending_trump_active = false
		return

	_resolve_pending_trump()
	_refresh_leylines()
	mana_regeneration = master_data.get_effective_regeneration(leylines_held)
	mana = clampf(mana + mana_regeneration * delta, 0.0, max_mana)

	var now: int = Time.get_ticks_msec()
	if is_haste_active and now >= _haste_until_msec:
		is_haste_active = false
	if is_shielded and now >= _shield_until_msec:
		is_shielded = false
	if not trump_card_ready and now >= _trump_ready_at_msec:
		trump_card_ready = true

	_resolve_commands(delta)


func _refresh_leylines() -> void:
	var held: int = 0
	for node: Node in get_tree().get_nodes_in_group(LEYLINE_GROUP):
		var leyline: LeylineNode = node as LeylineNode
		if leyline != null and leyline.owner_peer_id == owner_id:
			held += 1
	leylines_held = held


func _resolve_commands(delta: float) -> void:
	if _attack_target != null:
		if not is_instance_valid(_attack_target) or not _can_attack(_attack_target):
			_attack_target = null
	if _attack_target == null and _attack_move:
		_attack_target = _find_nearest_enemy(500.0)

	var direction: Vector2 = Vector2.ZERO
	if _attack_target != null:
		var offset: Vector2 = _attack_target.global_position - global_position
		if offset.length() > 500.0:
			direction = offset.normalized()
		else:
			_server_basic_attack(offset.normalized())
	elif _has_move_target:
		var to_target: Vector2 = _move_target - global_position
		if to_target.length() > STOP_DISTANCE:
			direction = to_target.normalized()
		else:
			_has_move_target = false
			_attack_move = false

	var speed: float = move_speed * (1.6 if is_haste_active else 1.0)
	if direction.length_squared() > 0.0001:
		velocity = velocity.move_toward(direction * speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()


func _server_basic_attack(direction: Vector2) -> void:
	if not _is_alive or projectile_spawner == null:
		return
	var now: int = Time.get_ticks_msec()
	if now < _attack_ready_at_msec:
		return
	var cost: float = 3.0
	if mana < cost:
		return
	mana -= cost
	_attack_ready_at_msec = now + 1000
	var damage: float = 8.0 + float(master_data.mana_rank) * 0.4
	_fire_projectile(direction, damage, 760.0, Color(0.65, 0.8, 1.0))


func _fire_projectile(direction: Vector2, damage: float, speed: float, color: Color) -> void:
	if projectile_spawner == null:
		return
	projectile_spawner.spawn({
		"owner_id": owner_id,
		"source_class": -1,
		"origin": global_position + direction * (BODY_RADIUS + 8.0),
		"direction": direction,
		"speed": speed,
		"damage": damage,
		"color": color,
	})


func receive_damage(amount: float, source_id: int = 0, _source_class: int = -1, _bypass_reflect: bool = false) -> void:
	if not multiplayer.is_server() or not _is_alive:
		return
	if source_id == owner_id:
		return
	if match_state != null and not match_state.can_damage(source_id, owner_id):
		return
	var incoming: float = maxf(amount, 0.0) * (0.5 if is_shielded else 1.0)
	health = maxf(health - incoming, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_handle_death()


func heal(amount: float) -> void:
	if not multiplayer.is_server() or not _is_alive:
		return
	health = clampf(health + maxf(amount, 0.0), 0.0, max_health)
	health_changed.emit(health, max_health)


func _handle_death() -> void:
	_is_alive = false
	_pending_trump_active = false
	velocity = Vector2.ZERO
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	died.emit()
	eliminated.emit(owner_id)
	queue_free()


## Server-internal command entry points shared by human RPCs and AI commanders.
func server_command_move(target: Vector2, attack_move: bool = false) -> void:
	if not multiplayer.is_server() or not _is_alive:
		return
	_move_target = target
	_has_move_target = true
	_attack_move = attack_move
	_attack_target = null


func server_command_attack(target: Node2D) -> void:
	if not multiplayer.is_server() or not _is_alive:
		return
	if target == null or not _can_attack(target):
		return
	_attack_target = target
	_attack_move = true


@rpc("any_peer", "call_local", "reliable")
func _rpc_command_move(target: Vector2, attack_move: bool = false) -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call() or not _is_alive:
		return
	server_command_move(target, attack_move)


@rpc("any_peer", "call_local", "reliable")
func _rpc_command_attack(target_path: NodePath) -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call() or not _is_alive:
		return
	server_command_attack(get_node_or_null(target_path) as Node2D)


@rpc("any_peer", "call_local", "reliable")
func _rpc_stop() -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call():
		return
	_has_move_target = false
	_attack_move = false
	_attack_target = null
	velocity = Vector2.ZERO


@rpc("any_peer", "call_local", "reliable")
func _rpc_use_skill(slot: int, direction: Vector2) -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call():
		return
	_server_use_skill(slot, direction)


@rpc("any_peer", "call_local", "reliable")
func _rpc_use_command_spell() -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call():
		return
	_server_use_command_spell()


@rpc("any_peer", "call_local", "reliable")
func _rpc_use_trump_card(direction: Vector2) -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call():
		return
	_server_use_trump_card(direction)


@rpc("any_peer", "call_local", "reliable")
func _rpc_ask_servant_name() -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call():
		return
	if servant_unit != null and is_instance_valid(servant_unit) and servant_unit.is_alive:
		servant_unit.learn_name_from_master()


@rpc("any_peer", "call_local", "reliable")
func _rpc_publicly_reveal_name() -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call():
		return
	if servant_unit != null and is_instance_valid(servant_unit) and servant_unit.is_alive:
		servant_unit.publicly_reveal_true_name()


func _server_use_skill(slot: int, direction: Vector2) -> void:
	if not _is_alive or slot < 0 or slot >= 2:
		return
	var now: int = Time.get_ticks_msec()
	if now < _skill_ready_at_msec[slot]:
		return
	var cost: float = master_data.skill_1_cost if slot == 0 else master_data.skill_2_cost
	if mana < cost:
		return
	var style: MasterData.MasterSkillStyle = master_data.skill_1_style if slot == 0 else master_data.skill_2_style
	var aim: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT

	match style:
		MasterData.MasterSkillStyle.BURST:
			_server_jewel_burst(aim)
		MasterData.MasterSkillStyle.HEAL_SERVANT:
			if servant_unit != null and is_instance_valid(servant_unit) and servant_unit.is_alive:
				servant_unit.heal(45.0 + float(master_data.mana_rank) * 0.8)
				servant_unit.mana = minf(servant_unit.mana + 25.0, servant_unit.max_mana)
		MasterData.MasterSkillStyle.HASTE_SELF:
			is_haste_active = true
			_haste_until_msec = now + 5000
		MasterData.MasterSkillStyle.REVEAL:
			_server_reveal(800.0)
		MasterData.MasterSkillStyle.DRAIN:
			_server_drain()
		MasterData.MasterSkillStyle.SHIELD_SERVANT:
			if servant_unit != null and is_instance_valid(servant_unit) and servant_unit.is_alive:
				servant_unit.apply_shield(5.0)

	mana -= cost
	var cooldown: float = master_data.skill_1_cooldown if slot == 0 else master_data.skill_2_cooldown
	_skill_ready_at_msec[slot] = now + int(cooldown * 1000.0)
	skill_used.emit(slot)


func _server_jewel_burst(direction: Vector2) -> void:
	var damage: float = 12.0 + float(master_data.mana_rank) * 0.6
	for index: int in range(8):
		var angle: float = TAU * float(index) / 8.0
		_fire_projectile(Vector2(cos(angle), sin(angle)), damage, 620.0, Color(1.0, 0.75, 0.4))
	if direction.length_squared() > 0.0001:
		_fire_projectile(direction, damage * 1.2, 760.0, Color(1.0, 0.75, 0.4))


func _server_reveal(radius: float) -> void:
	for node: Node in get_tree().get_nodes_in_group("servants"):
		var servant: ServantController = node as ServantController
		if servant == null or servant.owner_id == owner_id:
			continue
		if global_position.distance_to(servant.global_position) <= radius:
			servant.reveal_true_name()


func _server_drain() -> void:
	var nearest: ServantController = null
	var nearest_distance: float = 480.0
	for node: Node in get_tree().get_nodes_in_group("servants"):
		var servant: ServantController = node as ServantController
		if servant == null or servant.owner_id == owner_id or not servant.is_alive:
			continue
		if match_state != null and not match_state.can_damage(owner_id, servant.owner_id):
			continue
		var distance: float = global_position.distance_to(servant.global_position)
		if distance < nearest_distance:
			nearest = servant
			nearest_distance = distance
	if nearest != null:
		var drained: float = minf(nearest.mana, 35.0)
		nearest.mana -= drained
		mana = clampf(mana + drained * 0.5, 0.0, max_mana)
		nearest.reveal_true_name()


func _server_use_command_spell() -> void:
	if not _is_alive or command_spells_left <= 0:
		return
	if servant_unit == null or not is_instance_valid(servant_unit) or not servant_unit.is_alive:
		return
	if not master_data.consume_command_spell():
		return
	command_spells_left = master_data.command_spell_charges

	if not signature_command_spell_used:
		signature_command_spell_used = true
		_apply_signature_effect()
		signature_decree_used.emit(master_data.signature_command_spell)
	else:
		_standard_command_warp()
	# A Command Spell is an explicit override of Servant autonomy.
	servant_unit.learn_name_from_master()
	command_spell_used.emit(command_spells_left)
	_fx_text("COMMAND SPELL!", global_position + Vector2(0.0, -46.0), Color(0.95, 0.24, 0.3))
	_fx_sfx("command_spell", global_position)


func _standard_command_warp() -> void:
	servant_unit.position = global_position + Vector2(40.0, 0.0)
	servant_unit.health = servant_unit.max_health
	servant_unit.mana = servant_unit.max_mana
	servant_unit.apply_shield(3.0)


func _apply_signature_effect() -> void:
	match master_data.signature_style:
		MasterData.SignatureStyle.DECREE_WARP:
			_standard_command_warp()
		MasterData.SignatureStyle.OVERDRIVE:
			servant_unit.mana = servant_unit.max_mana
			servant_unit.grant_combat_buff(8.0)
			mana = clampf(mana + 30.0, 0.0, max_mana)
		MasterData.SignatureStyle.REVEAL:
			_server_reveal(900.0)
			servant_unit.heal(servant_unit.max_health * 0.3)
			servant_unit.apply_shield(4.0)
		MasterData.SignatureStyle.BIND:
			servant_unit.apply_shield(6.0)
			servant_unit.heal(servant_unit.max_health * 0.25)
			health = clampf(health + max_health * 0.2, 0.0, max_health)
		MasterData.SignatureStyle.SURGE:
			servant_unit.mana = servant_unit.max_mana
			mana = clampf(mana + 60.0, 0.0, max_mana)
			servant_unit.apply_shield(4.0)
		MasterData.SignatureStyle.RAMPAGE:
			servant_unit.grant_combat_buff(10.0)
			servant_unit.mana = clampf(servant_unit.mana + 30.0, 0.0, servant_unit.max_mana)
			_apply_self_damage(max_health * 0.08)


func _server_use_trump_card(direction: Vector2) -> void:
	if not _is_alive or master_data == null:
		return
	if not trump_card_ready:
		return
	var cost: float = master_data.trump_card_mana_cost
	if mana < cost:
		return
	mana -= cost
	trump_card_ready = false
	var now: int = Time.get_ticks_msec()
	_trump_ready_at_msec = now + int(maxf(master_data.trump_card_cooldown, 1.0) * 1000.0)
	var aim: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	if servant_unit != null and is_instance_valid(servant_unit):
		aim = _aim_from_servant_to_enemy()

	var style: int = master_data.trump_style
	if _trump_needs_telegraph(style):
		_pending_trump_active = true
		_pending_trump_style = style
		_pending_trump_aim = aim
		_pending_trump_ready_msec = now + 350
		_broadcast_trump_telegraph(global_position, _trump_telegraph_radius(style), 0.35, _trump_telegraph_colour(style))
		_fx_sfx("beam_charge", global_position)
		return
	_execute_trump_style(style, aim)


func _trump_needs_telegraph(style: int) -> bool:
	return style in [
		MasterData.TrumpStyle.JEWELED_SWORD,
		MasterData.TrumpStyle.ORIGIN_BULLET,
		MasterData.TrumpStyle.MERCURY_STORM,
		MasterData.TrumpStyle.BLOOD_CARNIVAL,
		MasterData.TrumpStyle.DRAIN_NOVA,
	]


func _trump_telegraph_radius(style: int) -> float:
	match style:
		MasterData.TrumpStyle.MERCURY_STORM:
			return 420.0
		MasterData.TrumpStyle.DRAIN_NOVA:
			return 360.0
		MasterData.TrumpStyle.BLOOD_CARNIVAL:
			return 280.0
		MasterData.TrumpStyle.ORIGIN_BULLET:
			return 240.0
	return 210.0


func _trump_telegraph_colour(style: int) -> Color:
	match style:
		MasterData.TrumpStyle.JEWELED_SWORD:
			return Color(0.65, 0.85, 1.0)
		MasterData.TrumpStyle.ORIGIN_BULLET:
			return Color(0.9, 0.35, 0.25)
		MasterData.TrumpStyle.MERCURY_STORM:
			return Color(0.72, 0.86, 0.96)
		MasterData.TrumpStyle.BLOOD_CARNIVAL:
			return Color(0.78, 0.12, 0.16)
		MasterData.TrumpStyle.DRAIN_NOVA:
			return Color(0.62, 0.32, 0.86)
	return Color(0.95, 0.8, 0.4)


func _resolve_pending_trump() -> void:
	if not _pending_trump_active:
		return
	if Time.get_ticks_msec() < _pending_trump_ready_msec:
		return
	_pending_trump_active = false
	_execute_trump_style(_pending_trump_style, _pending_trump_aim)


func _execute_trump_style(style: int, aim: Vector2) -> void:
	match style:
		MasterData.TrumpStyle.RHO_AIAS:
			is_shielded = true
			_shield_until_msec = Time.get_ticks_msec() + 7000
			if servant_unit != null and is_instance_valid(servant_unit):
				servant_unit.apply_shield(7.0)
				servant_unit.heal(servant_unit.max_health * 0.2)
		MasterData.TrumpStyle.JEWELED_SWORD:
			_fire_trump_projectile(aim, 95.0, 1250.0, Color(0.65, 0.85, 1.0))
		MasterData.TrumpStyle.ORIGIN_BULLET:
			_fire_trump_projectile(aim, 120.0, 1500.0, Color(0.9, 0.35, 0.25))
			is_haste_active = true
			_haste_until_msec = Time.get_ticks_msec() + 4000
		MasterData.TrumpStyle.MERCURY_STORM:
			_damage_nearby(420.0, 45.0)
			if servant_unit != null and is_instance_valid(servant_unit):
				servant_unit.apply_shield(5.0)
		MasterData.TrumpStyle.GLOBAL_REVEAL:
			_server_reveal(2000.0)
			mana = clampf(mana + 50.0, 0.0, max_mana)
		MasterData.TrumpStyle.NP_CHARGE_HP_COST:
			_apply_self_damage(max_health * 0.2)
			if servant_unit != null and is_instance_valid(servant_unit):
				servant_unit.mana = servant_unit.max_mana
				servant_unit.reset_np_cooldown()
				servant_unit.grant_combat_buff(5.0)
		MasterData.TrumpStyle.BLOOD_CARNIVAL:
			for index: int in range(12):
				var angle: float = TAU * float(index) / 12.0
				_fire_trump_projectile(Vector2(cos(angle), sin(angle)), 35.0, 760.0, Color(0.75, 0.1, 0.15))
		MasterData.TrumpStyle.HEAL_SHIELD:
			health = clampf(health + max_health * 0.35, 0.0, max_health)
			if servant_unit != null and is_instance_valid(servant_unit):
				servant_unit.heal(servant_unit.max_health * 0.4)
				servant_unit.apply_shield(6.0)
		MasterData.TrumpStyle.DRAIN_NOVA:
			_damage_nearby(360.0, 40.0)
			if servant_unit != null and is_instance_valid(servant_unit):
				servant_unit.mana = clampf(servant_unit.mana + 60.0, 0.0, servant_unit.max_mana)
	trump_card_used.emit(master_data.master_trump_card)
	_fx_impact(global_position, 0.75, "trump_impact")
	_fx_text(master_data.master_trump_card.to_upper(), global_position + Vector2(0.0, -52.0), Color(1.0, 0.86, 0.42))


func _broadcast_trump_telegraph(origin: Vector2, radius: float, duration: float, colour: Color) -> void:
	if multiplayer.get_peers().is_empty():
		_rpc_trump_telegraph(origin, radius, duration, colour)
	else:
		_rpc_trump_telegraph.rpc(origin, radius, duration, colour)


@rpc("authority", "call_local", "reliable")
func _rpc_trump_telegraph(origin: Vector2, radius: float, duration: float, colour: Color) -> void:
	trump_telegraph.emit(origin, radius, duration, colour)


func _fire_trump_projectile(direction: Vector2, damage: float, speed: float, color: Color) -> void:
	if projectile_spawner == null:
		return
	projectile_spawner.spawn({
		"owner_id": owner_id,
		"source_class": -1,
		"origin": global_position + direction * (BODY_RADIUS + 8.0),
		"direction": direction,
		"speed": speed,
		"damage": damage,
		"color": color,
	})


func _damage_nearby(radius: float, damage: float) -> void:
	for node: Node in get_tree().get_nodes_in_group("player_units"):
		var unit: Node2D = node as Node2D
		if unit == null or not unit.has_method("receive_damage"):
			continue
		var other_owner: int = int(unit.get("owner_id"))
		if other_owner == owner_id:
			continue
		if match_state != null and not match_state.can_damage(owner_id, other_owner):
			continue
		if global_position.distance_to(unit.global_position) <= radius:
			unit.call("receive_damage", damage, owner_id, -1)


func _aim_from_servant_to_enemy() -> Vector2:
	if servant_unit == null:
		return Vector2.RIGHT
	var nearest: Node2D = _find_nearest_enemy(800.0)
	if nearest == null:
		return Vector2.RIGHT
	var offset: Vector2 = nearest.global_position - servant_unit.global_position
	return offset.normalized() if offset.length_squared() > 0.0001 else Vector2.RIGHT


func _apply_self_damage(amount: float) -> void:
	if not multiplayer.is_server() or not _is_alive:
		return
	health = maxf(health - maxf(amount, 0.0), 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_handle_death()


func _can_attack(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.has_method("receive_damage"):
		return false
	var target_owner: int = int(target.get("owner_id"))
	if target_owner == owner_id:
		return false
	if match_state != null:
		return match_state.can_damage(owner_id, target_owner)
	return true


func _find_nearest_enemy(max_distance: float) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = max_distance
	for node: Node in get_tree().get_nodes_in_group("player_units"):
		var unit: Node2D = node as Node2D
		if unit == null or unit == self or int(unit.get("owner_id")) == owner_id:
			continue
		if match_state != null and not match_state.can_damage(owner_id, int(unit.get("owner_id"))):
			continue
		var distance: float = global_position.distance_to(unit.global_position)
		if distance < nearest_distance:
			nearest = unit
			nearest_distance = distance
	return nearest


func _is_valid_peer_call() -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == owner_id:
		return true
	return sender == 0 and owner_id == multiplayer.get_unique_id()


func _build_collision() -> void:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = BODY_RADIUS
	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "BodyCollision"
	_collision_shape.shape = shape
	add_child(_collision_shape)


func _build_synchronizer() -> void:
	var sync: MultiplayerSynchronizer = MultiplayerSynchronizer.new()
	sync.name = "StateSynchronizer"
	sync.root_path = NodePath("..")

	var config: SceneReplicationConfig = SceneReplicationConfig.new()
	for path: NodePath in [
		NodePath(".:position"),
		NodePath(".:owner_id"),
		NodePath(".:health"),
		NodePath(".:mana"),
		NodePath(".:mana_regeneration"),
		NodePath(".:leylines_held"),
		NodePath(".:team_id"),
		NodePath(".:command_spells_left"),
		NodePath(".:is_haste_active"),
		NodePath(".:is_shielded"),
		NodePath(".:signature_command_spell_used"),
		NodePath(".:trump_card_ready"),
	]:
		config.add_property(path)
		config.property_set_spawn(path, true)

	sync.replication_config = config
	sync.replication_interval = 1.0 / 20.0
	add_child(sync)


func _draw() -> void:
	var down: bool = not _is_alive
	var color: Color = Color(0.75, 0.72, 0.55) if not down else Color(0.3, 0.3, 0.34, 0.5)
	if is_haste_active:
		color = color.lerp(Color(0.4, 0.8, 1.0), 0.45)

	draw_circle(Vector2(0.0, 4.0), BODY_RADIUS + 2.0, Color(0.0, 0.0, 0.0, 0.35))
	draw_circle(Vector2.ZERO, BODY_RADIUS, color)
	draw_arc(Vector2.ZERO, BODY_RADIUS, 0.0, TAU, 28, Color(0.1, 0.1, 0.14, 0.9), 2.0, true)
	if is_haste_active:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 7.0, 0.0, TAU, 28, Color(0.4, 0.8, 1.0, 0.65), 2.0, true)
	if is_shielded:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 10.0, 0.0, TAU, 30, Color(0.85, 0.92, 1.0, 0.7), 2.0, true)

	var bar_width: float = 42.0
	var health_ratio: float = clampf(health / max_health, 0.0, 1.0) if max_health > 0.0 else 0.0
	var mana_ratio: float = clampf(mana / max_mana, 0.0, 1.0) if max_mana > 0.0 else 0.0
	draw_rect(Rect2(-bar_width * 0.5, -28.0, bar_width, 3.0), Color(0.08, 0.09, 0.13, 0.9))
	draw_rect(Rect2(-bar_width * 0.5, -28.0, bar_width * health_ratio, 3.0), Color(0.9, 0.35, 0.35))
	draw_rect(Rect2(-bar_width * 0.5, -23.0, bar_width, 3.0), Color(0.08, 0.09, 0.13, 0.9))
	draw_rect(Rect2(-bar_width * 0.5, -23.0, bar_width * mana_ratio, 3.0), Color(0.35, 0.65, 1.0))

	var viewer: int = multiplayer.get_unique_id()
	var name_text: String = master_data.display_name if viewer == owner_id else "Master P%d" % owner_id
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-bar_width * 0.5, -34.0),
		name_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color(0.86, 0.84, 0.7)
	)


func _fx_text(text: String, world_position: Vector2, colour: Color) -> void:
	var fx: Node = get_node_or_null("/root/AudioManager")
	if fx != null:
		fx.call("broadcast_text", text, world_position, colour)


func _fx_sfx(kind: String, world_position: Vector2 = Vector2.ZERO) -> void:
	var fx: Node = get_node_or_null("/root/AudioManager")
	if fx != null:
		fx.call("broadcast_sfx", kind, world_position)


func _fx_impact(world_position: Vector2, strength: float, kind: String) -> void:
	var fx: Node = get_node_or_null("/root/AudioManager")
	if fx != null:
		fx.call("broadcast_impact", world_position, strength, kind)
