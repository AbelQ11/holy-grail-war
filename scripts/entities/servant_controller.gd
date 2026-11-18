class_name ServantController
extends CharacterBody2D
## Server-authoritative RTS Servant unit.
##
## Clients select units locally in the arena and send reliable move / attack /
## ability commands. The server owns movement, Mana, cooldowns, class-triangle
## damage, concealment flags, Leyline bonuses, and Noble Phantasm resolution.

signal health_changed(current: float, maximum: float)
signal mana_changed(current: float, maximum: float)
signal died
signal reality_marble_state_changed(active: bool)
signal stealth_state_changed(active: bool)
signal true_name_revealed
signal name_knowledge_changed(known: bool)
signal publicly_revealed
signal skill_used(slot: int)
signal np_telegraph(style: int, origin: Vector2, direction: Vector2, length: float, duration: float, colour: Color)

enum EffectKind {
	NONE,
	SLASH,
	BEAM,
	NOVA,
	DASH,
}

const BODY_RADIUS: float = 18.0
const LEYLINE_GROUP: StringName = &"leyline_nodes"
const BEAM_WIDTH: float = 76.0
const DASH_HIT_RADIUS: float = 58.0
const EFFECT_DURATION_MSEC: int = 420
const STOP_DISTANCE: float = 10.0
const NP_WINDUP_SECONDS: float = 0.45
const CONCEALMENT_SHADER: Shader = preload("res://shaders/presence_concealment.gdshader")

@export_group("Movement")
@export var move_speed: float = 300.0
@export var acceleration: float = 2200.0
@export var friction: float = 2600.0

@export_group("Vitals")
@export var max_health: float = 120.0

@export_group("Data")
@export var servant_data: ServantData

## Peer that commands this unit. The server remains the multiplayer authority.
var owner_id: int = 1
var team_id: int = 0
var spawn_slot: int = 0
var vision_radius: float = 520.0

var health: float = 120.0
var mana: float = 100.0
var max_mana: float = 100.0
var aim_direction: Vector2 = Vector2.RIGHT
var leylines_held: int = 0
var territory_bonus_active: bool = false
var is_shielded: bool = false
var is_reflecting: bool = false
var is_damage_buffed: bool = false
var is_speed_buffed: bool = false
var is_true_name_revealed: bool = false
var is_name_known_to_master: bool = false
var is_fame_buffed: bool = false
var is_anti_healed: bool = false

var projectile_spawner: MultiplayerSpawner
var trap_spawner: MultiplayerSpawner
var master_unit: MasterController
var match_state: MatchState

var _is_alive: bool = true
var _is_stealthed: bool = false
var _reality_marble_active: bool = false

var is_alive: bool:
	get:
		return _is_alive

var is_stealthed: bool:
	get:
		return _is_stealthed
	set(value):
		if _is_stealthed == value:
			return
		_is_stealthed = value
		_apply_concealment_material(value)
		queue_redraw()
		stealth_state_changed.emit(value)

var is_reality_marble_active: bool:
	get:
		return _reality_marble_active
	set(value):
		if _reality_marble_active == value:
			return
		_reality_marble_active = value
		queue_redraw()
		reality_marble_state_changed.emit(value)

var _move_target: Vector2 = Vector2.ZERO
var _has_move_target: bool = false
var _attack_move: bool = false
var _attack_target: Node2D
var _attack_ready_at_msec: int = 0
var _skill_ready_at_msec: Array[int] = [0, 0]
var _np_ready_at_msec: int = 0
var _stealth_until_msec: int = 0
var _shield_until_msec: int = 0
var _reflect_until_msec: int = 0
var _damage_buff_until_msec: int = 0
var _speed_buff_until_msec: int = 0
var _barrage_active: bool = false
var _collision_shape: CollisionShape2D
var _fame_until_msec: int = 0
var _anti_heal_until_msec: int = 0
var _appropriation_ready_msec: int = 0
var _rm_barrage_accum: float = 0.0
var _last_damage_text_msec: int = 0
var _concealment_material: ShaderMaterial
var _pending_np_active: bool = false
var _pending_np_style: int = -1
var _pending_np_direction: Vector2 = Vector2.RIGHT
var _pending_np_ready_msec: int = 0

var _effect_kind: EffectKind = EffectKind.NONE
var _effect_origin: Vector2 = Vector2.ZERO
var _effect_direction: Vector2 = Vector2.RIGHT
var _effect_length: float = 0.0
var _effect_color: Color = Color.WHITE
var _effect_start_msec: int = 0
var _effect_until_msec: int = 0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 1 << 1  # servants and masters
	collision_mask = 1 << 0   # world boundaries
	add_to_group("player_units")
	add_to_group("servants")

	if servant_data == null:
		servant_data = ServantData.new()

	max_health = 80.0 + float(servant_data.endurance) * 1.6
	move_speed = 170.0 + float(servant_data.agility) * 3.4
	max_mana = servant_data.max_mana
	health = max_health
	mana = max_mana
	vision_radius = servant_data.vision_radius

	_build_collision()
	_build_synchronizer()
	_build_concealment_material()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_tick(delta)
	queue_redraw()


func receive_damage(amount: float, source_id: int = 0, source_class: int = -1, bypass_reflect: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if not _is_alive:
		return
	if source_id == owner_id:
		return
	if match_state != null and not match_state.can_damage(source_id, owner_id):
		return

	if is_reflecting and not bypass_reflect and source_id != 0:
		var attacker: Node2D = _find_unit_by_owner(source_id)
		if attacker != null and attacker.has_method("receive_damage"):
			attacker.call("receive_damage", amount, owner_id, servant_data.servant_class, true)
			return

	var class_multiplier: float = ClassTriangle.get_total_multiplier(source_class, servant_data.servant_class)
	var shield_multiplier: float = 0.5 if is_shielded else 1.0
	var final_damage: float = maxf(amount, 0.0) * class_multiplier * shield_multiplier
	health = maxf(health - final_damage, 0.0)
	health_changed.emit(health, max_health)
	_report_damage_feedback(final_damage, class_multiplier)
	if health <= 0.0:
		_handle_death()


func _report_damage_feedback(final_damage: float, class_multiplier: float) -> void:
	if final_damage <= 0.0:
		return
	var now: int = Time.get_ticks_msec()
	var advantage: bool = class_multiplier > 1.05
	if not advantage and now - _last_damage_text_msec < 220:
		return
	_last_damage_text_msec = now
	var text: String = "-%d" % int(round(final_damage))
	var colour: Color = Color(0.95, 0.9, 0.82)
	if advantage:
		text = "ADVANTAGE! -%d" % int(round(final_damage))
		colour = Color(1.0, 0.78, 0.28)
	elif class_multiplier < 0.95:
		colour = Color(0.72, 0.78, 0.92)
	_fx_text(text, global_position + Vector2(0.0, -34.0), colour)


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


func reveal_true_name() -> void:
	if not multiplayer.is_server():
		return
	if is_true_name_revealed:
		return
	if servant_data != null and servant_data.identity_mask:
		return
	is_true_name_revealed = true
	true_name_revealed.emit()


func get_effective_attack_cooldown() -> float:
	if servant_data == null:
		return 0.4
	var cooldown: float = servant_data.attack_cooldown
	if is_reality_marble_active and servant_data.reality_marble_haste > 0.0:
		cooldown *= servant_data.reality_marble_haste
	return maxf(cooldown, 0.05)


func get_effective_spell_multiplier() -> float:
	if servant_data == null:
		return 1.0
	var multiplier: float = servant_data.spell_damage_multiplier
	if territory_bonus_active:
		multiplier *= 1.0 + servant_data.territory_spell_bonus
	return multiplier


func get_effective_move_speed() -> float:
	if is_speed_buffed:
		return move_speed * servant_data.skill_buff_speed_multiplier
	return move_speed


func get_display_name_for(viewer_peer_id: int) -> String:
	if viewer_peer_id == owner_id:
		if is_name_known_to_master:
			return servant_data.display_name
		return "Unknown [%s]" % servant_data.get_class_name_text()
	if is_true_name_revealed:
		return servant_data.display_name
	return "Unknown [%s]" % servant_data.get_class_name_text()


func _build_collision() -> void:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = BODY_RADIUS
	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "BodyCollision"
	_collision_shape.shape = shape
	add_child(_collision_shape)


func _build_concealment_material() -> void:
	if _concealment_material != null:
		return
	_concealment_material = ShaderMaterial.new()
	_concealment_material.shader = CONCEALMENT_SHADER


func _apply_concealment_material(active: bool) -> void:
	if _concealment_material == null:
		_build_concealment_material()
	if _concealment_material == null:
		return
	material = _concealment_material if active else null


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
		NodePath(".:aim_direction"),
		NodePath(".:team_id"),
		NodePath(".:leylines_held"),
		NodePath(".:territory_bonus_active"),
		NodePath(".:is_shielded"),
		NodePath(".:is_reflecting"),
		NodePath(".:is_damage_buffed"),
		NodePath(".:is_speed_buffed"),
		NodePath(".:is_true_name_revealed"),
		NodePath(".:is_name_known_to_master"),
		NodePath(".:is_fame_buffed"),
		NodePath(".:is_anti_healed"),
		NodePath(".:is_stealthed"),
		NodePath(".:is_reality_marble_active"),
	]:
		config.add_property(path)
		config.property_set_spawn(path, true)

	sync.replication_config = config
	sync.replication_interval = 1.0 / 20.0
	add_child(sync)


func _server_tick(delta: float) -> void:
	if not _is_alive:
		_pending_np_active = false
		velocity = Vector2.ZERO
		return

	_resolve_pending_noble_phantasm()
	_refresh_leyline_state()
	_tick_timers()
	_regenerate_mana(delta)
	_resolve_commands(delta)

	if is_reality_marble_active:
		var drain: float = maxf(servant_data.reality_marble_drain_per_second, 0.0)
		mana = maxf(mana - drain * delta, 0.0)
		if servant_data.reality_marble_auto_barrage:
			_rm_barrage_accum += delta
			if _rm_barrage_accum >= servant_data.reality_marble_barrage_interval:
				_rm_barrage_accum = 0.0
				var phalanx_target: Node2D = _find_nearest_enemy(servant_data.vision_radius)
				if phalanx_target != null:
					_fire_projectile(
						_aim_at(phalanx_target),
						_outgoing_damage(servant_data.attack_damage * 0.55),
						servant_data.projectile_speed * 0.9,
						servant_data.noble_phantasm_color
					)
		if mana <= 0.0:
			is_reality_marble_active = false


func _refresh_leyline_state() -> void:
	var held: int = 0
	var inside_any: bool = false
	for node: Node in get_tree().get_nodes_in_group(LEYLINE_GROUP):
		var leyline: LeylineNode = node as LeylineNode
		if leyline == null:
			continue
		if leyline.owner_peer_id == owner_id:
			held += 1
		if leyline.is_point_inside(global_position):
			inside_any = true

	leylines_held = held
	territory_bonus_active = servant_data.servant_class == ServantData.ServantClass.CASTER and inside_any


func _tick_timers() -> void:
	var now: int = Time.get_ticks_msec()
	if is_stealthed and now >= _stealth_until_msec:
		is_stealthed = false
	if is_shielded and now >= _shield_until_msec:
		is_shielded = false
	if is_reflecting and now >= _reflect_until_msec:
		is_reflecting = false
	if is_damage_buffed and now >= _damage_buff_until_msec:
		is_damage_buffed = false
	if is_speed_buffed and now >= _speed_buff_until_msec:
		is_speed_buffed = false
	if is_fame_buffed and now >= _fame_until_msec:
		is_fame_buffed = false
	if is_anti_healed and now >= _anti_heal_until_msec:
		is_anti_healed = false


func _regenerate_mana(delta: float) -> void:
	var base_regen: float = servant_data.mana_regeneration
	if territory_bonus_active:
		base_regen += servant_data.territory_mana_bonus

	var supply_ratio: float = 1.0
	if master_unit != null and is_instance_valid(master_unit) and master_unit.is_alive:
		var upkeep: float = servant_data.get_effective_upkeep(is_reality_marble_active)
		var upkeep_cost: float = upkeep * delta
		var paid: float = minf(master_unit.mana, upkeep_cost)
		if upkeep_cost > 0.0:
			supply_ratio = clampf(paid / upkeep_cost, 0.0, 1.0)
		master_unit.mana = maxf(master_unit.mana - paid, 0.0)
		base_regen *= 0.25 + 0.75 * supply_ratio
	else:
		base_regen -= servant_data.get_effective_upkeep(is_reality_marble_active)

	mana = clampf(mana + base_regen * delta, 0.0, max_mana)


func _resolve_commands(delta: float) -> void:
	if _attack_target != null:
		if not is_instance_valid(_attack_target) or not _can_attack(_attack_target):
			_attack_target = null
	if _attack_target == null and _attack_move:
		_attack_target = _find_nearest_enemy(servant_data.vision_radius)

	var direction: Vector2 = Vector2.ZERO

	if _attack_target != null:
		var offset: Vector2 = _attack_target.global_position - global_position
		aim_direction = offset.normalized()
		if offset.length() > servant_data.attack_range:
			direction = offset.normalized()
		else:
			_server_attack(aim_direction)
	elif _has_move_target:
		var to_target: Vector2 = _move_target - global_position
		if to_target.length() > STOP_DISTANCE:
			direction = to_target.normalized()
			aim_direction = direction
		else:
			_has_move_target = false
			_attack_move = false

	var target_velocity: Vector2 = direction * get_effective_move_speed()
	if direction.length_squared() > 0.0001:
		velocity = velocity.move_toward(target_velocity, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()


func _server_attack(direction: Vector2) -> void:
	if not _is_alive:
		return
	var now: int = Time.get_ticks_msec()
	if now < _attack_ready_at_msec:
		return
	if mana < servant_data.attack_mana_cost:
		return

	mana -= servant_data.attack_mana_cost
	_attack_ready_at_msec = now + int(get_effective_attack_cooldown() * 1000.0)
	if direction.length_squared() > 0.0001:
		aim_direction = direction.normalized()
	_break_stealth()

	if servant_data.attack_style == ServantData.AttackStyle.SLASH:
		_server_melee_slash(aim_direction)
	else:
		_server_fire_primary_projectile(aim_direction)


func _server_melee_slash(direction: Vector2) -> void:
	var half_arc: float = deg_to_rad(servant_data.melee_arc_degrees) * 0.5
	var damage: float = _outgoing_damage(servant_data.attack_damage)

	for target: Node2D in _enemy_units(servant_data.attack_range + BODY_RADIUS):
		var offset: Vector2 = target.global_position - global_position
		if absf(angle_difference(direction.angle(), offset.angle())) > half_arc:
			continue
		target.call("receive_damage", damage, owner_id, servant_data.servant_class)

	_broadcast_effect(EffectKind.SLASH, global_position, direction, servant_data.attack_range)
	_fx_sfx("sword_clash", global_position)


func _server_fire_primary_projectile(direction: Vector2) -> void:
	var damage: float = servant_data.attack_damage
	if servant_data.servant_class == ServantData.ServantClass.CASTER:
		damage *= get_effective_spell_multiplier()
	damage = _outgoing_damage(damage)
	_fire_projectile(direction, damage, servant_data.projectile_speed, _class_color())


func _fire_projectile(direction: Vector2, damage: float, speed: float, color: Color) -> void:
	if projectile_spawner == null:
		return
	var payload: Dictionary = {
		"owner_id": owner_id,
		"source_class": servant_data.servant_class,
		"origin": global_position + direction * (BODY_RADIUS + 10.0),
		"direction": direction,
		"speed": speed,
		"damage": damage,
		"color": color,
	}
	projectile_spawner.spawn(payload)


# --- RTS commands and abilities --------------------------------------------

## Server-internal command entry points. Human RPC handlers validate the sender
## and then call these; AI commanders call them directly with the same intents.
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
	_move_target = target.global_position
	_has_move_target = true
	_attack_move = true


@rpc("any_peer", "call_local", "reliable")
func _rpc_command_move(target: Vector2, attack_move: bool = false) -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call() or not _is_alive:
		return
	if not is_name_known_to_master:
		return
	server_command_move(target, attack_move)


@rpc("any_peer", "call_local", "reliable")
func _rpc_command_attack(target_path: NodePath) -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call() or not _is_alive:
		return
	if not is_name_known_to_master:
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
	if not is_name_known_to_master:
		return
	_server_use_skill(slot, direction)


@rpc("any_peer", "call_local", "reliable")
func _rpc_use_noble_phantasm(direction: Vector2) -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call():
		return
	if not is_name_known_to_master:
		return
	_server_use_noble_phantasm(direction)


@rpc("any_peer", "call_local", "reliable")
func _rpc_ask_servant_name() -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call():
		return
	learn_name_from_master()


@rpc("any_peer", "call_local", "reliable")
func _rpc_publicly_reveal_name() -> void:
	if not multiplayer.is_server() or not _is_valid_peer_call():
		return
	publicly_reveal_true_name()


func _server_use_skill(slot: int, direction: Vector2) -> void:
	if not _is_alive or slot < 0 or slot >= 2:
		return
	var now: int = Time.get_ticks_msec()
	if now < _skill_ready_at_msec[slot]:
		return
	var style: ServantData.SkillStyle = servant_data.skill_1_style if slot == 0 else servant_data.skill_2_style
	var cost: float = servant_data.skill_1_cost if slot == 0 else servant_data.skill_2_cost
	if mana < cost:
		return
	if direction.length_squared() > 0.0001:
		aim_direction = direction.normalized()

	var used: bool = true
	match style:
		ServantData.SkillStyle.BARRAGE:
			used = _server_start_barrage(aim_direction)
		ServantData.SkillStyle.TRAP:
			used = _server_place_trap()
		ServantData.SkillStyle.STEALTH:
			used = _server_activate_stealth()
		ServantData.SkillStyle.DASH:
			_server_skill_dash(aim_direction)
		ServantData.SkillStyle.BUFF:
			_apply_buff()
		ServantData.SkillStyle.SCAN:
			_server_scan_reveal(servant_data.skill_scan_radius)
			_broadcast_effect(EffectKind.NOVA, global_position, aim_direction, servant_data.skill_scan_radius)
		ServantData.SkillStyle.HEAL:
			_server_heal(servant_data.skill_heal_amount)
			_broadcast_effect(EffectKind.NOVA, global_position, aim_direction, 120.0)
		ServantData.SkillStyle.AOE:
			_server_aoe_damage(servant_data.skill_aoe_radius, _outgoing_damage(servant_data.attack_damage * 1.4))
			_broadcast_effect(EffectKind.NOVA, global_position, aim_direction, servant_data.skill_aoe_radius)

	if not used:
		return
	mana -= cost
	var cooldown: float = servant_data.skill_1_cooldown if slot == 0 else servant_data.skill_2_cooldown
	_skill_ready_at_msec[slot] = now + int(cooldown * 1000.0)
	if style != ServantData.SkillStyle.STEALTH:
		_break_stealth()
	skill_used.emit(slot)


func _server_start_barrage(direction: Vector2) -> bool:
	if _barrage_active or projectile_spawner == null:
		return false
	_barrage_active = true
	_run_barrage(direction)
	return true


func _run_barrage(direction: Vector2) -> void:
	var count: int = maxi(servant_data.barrage_projectiles, 3)
	var interval: float = servant_data.barrage_interval
	if is_reality_marble_active and servant_data.reality_marble_haste > 0.0:
		interval *= servant_data.reality_marble_haste
	var spread: float = deg_to_rad(servant_data.barrage_spread_degrees)

	for index: int in range(count):
		if not is_inside_tree() or not _is_alive:
			break
		var ratio: float = 0.0 if count <= 1 else float(index) / float(count - 1) - 0.5
		var shot: Vector2 = direction.rotated(spread * ratio)
		_fire_projectile(shot, _outgoing_damage(servant_data.attack_damage), servant_data.projectile_speed * 1.15, _class_color())
		if index < count - 1:
			await get_tree().create_timer(interval).timeout

	_barrage_active = false


func _server_place_trap() -> bool:
	if trap_spawner == null or servant_data.trap_damage <= 0.0:
		return false
	var cast_distance: float = clampf(servant_data.trap_cast_range, 40.0, 500.0)
	var payload: Dictionary = {
		"owner_id": owner_id,
		"source_class": servant_data.servant_class,
		"origin": global_position + aim_direction * cast_distance,
		"radius": servant_data.trap_radius,
		"damage": servant_data.trap_damage * get_effective_spell_multiplier(),
		"duration": servant_data.trap_duration,
		"pulse_interval": servant_data.trap_pulse_interval,
		"color": Color(0.68, 0.42, 1.0),
	}
	return trap_spawner.spawn(payload) != null


func _server_activate_stealth() -> bool:
	if servant_data.stealth_duration <= 0.0 or is_stealthed:
		return false
	is_stealthed = true
	_stealth_until_msec = Time.get_ticks_msec() + int(servant_data.stealth_duration * 1000.0)
	return true


func _server_skill_dash(direction: Vector2) -> void:
	var start: Vector2 = global_position
	var motion: Vector2 = direction * servant_data.skill_dash_distance
	var collision: KinematicCollision2D = move_and_collide(motion)
	if collision != null:
		motion = collision.get_travel()
	var end: Vector2 = global_position
	var damage: float = _outgoing_damage(servant_data.attack_damage * 1.3)
	for target: Node2D in _enemy_units(servant_data.skill_dash_distance + 80.0):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(target.global_position, start, end)
		if closest.distance_to(target.global_position) <= DASH_HIT_RADIUS + BODY_RADIUS:
			target.call("receive_damage", damage, owner_id, servant_data.servant_class)
			if servant_data.strips_buffs_on_np and target.has_method("strip_buffs"):
				target.call("strip_buffs")
				if servant_data.anti_heal_duration > 0.0 and target.has_method("apply_anti_heal"):
					target.call("apply_anti_heal", servant_data.anti_heal_duration)
	_broadcast_effect(EffectKind.DASH, start, direction, start.distance_to(end))


func _apply_buff() -> void:
	var now: int = Time.get_ticks_msec()
	var duration_ms: int = int(servant_data.skill_buff_duration * 1000.0)
	is_damage_buffed = true
	is_speed_buffed = true
	_damage_buff_until_msec = now + duration_ms
	_speed_buff_until_msec = now + duration_ms


func _server_scan_reveal(radius: float) -> void:
	for node: Node in get_tree().get_nodes_in_group("servants"):
		var target: ServantController = node as ServantController
		if target == null or target.owner_id == owner_id:
			continue
		if global_position.distance_to(target.global_position) <= radius:
			target.reveal_true_name()


func _server_heal(amount: float) -> void:
	health = clampf(health + amount, 0.0, max_health)
	health_changed.emit(health, max_health)
	if master_unit != null and is_instance_valid(master_unit) and master_unit.is_alive:
		master_unit.heal(amount * 0.6)


func _server_aoe_damage(radius: float, damage: float) -> void:
	for target: Node2D in _enemy_units(radius):
		target.call("receive_damage", damage, owner_id, servant_data.servant_class)


func _server_use_noble_phantasm(direction: Vector2) -> void:
	if not _is_alive:
		return
	var now: int = Time.get_ticks_msec()

	if servant_data.noble_phantasm_style == ServantData.NoblePhantasmStyle.REALITY_MARBLE and is_reality_marble_active:
		is_reality_marble_active = false
		return
	if now < _np_ready_at_msec:
		return
	if direction.length_squared() > 0.0001:
		aim_direction = direction.normalized()
	if mana < servant_data.noble_phantasm_cost:
		return

	mana -= servant_data.noble_phantasm_cost
	_np_ready_at_msec = now + 1000
	_break_stealth()
	reveal_true_name()

	# Telegraphed windup: the ground warning appears now, damage detonates after
	# NP_WINDUP_SECONDS on the authoritative server.
	_pending_np_active = true
	_pending_np_style = servant_data.noble_phantasm_style
	_pending_np_direction = aim_direction
	_pending_np_ready_msec = now + int(NP_WINDUP_SECONDS * 1000.0)
	_broadcast_np_telegraph(_pending_np_style, global_position, aim_direction, _telegraph_length(_pending_np_style))
	_fx_sfx("beam_charge", global_position)


func _telegraph_length(style: int) -> float:
	match style:
		ServantData.NoblePhantasmStyle.BEAM, ServantData.NoblePhantasmStyle.DASH:
			return maxf(servant_data.noble_phantasm_range, 240.0)
		ServantData.NoblePhantasmStyle.NOVA:
			return maxf(servant_data.noble_phantasm_range, 150.0)
		ServantData.NoblePhantasmStyle.BARRAGE:
			return 300.0
		ServantData.NoblePhantasmStyle.REALITY_MARBLE:
			return 760.0
	return maxf(servant_data.noble_phantasm_range, 180.0)


func _resolve_pending_noble_phantasm() -> void:
	if not _pending_np_active:
		return
	if Time.get_ticks_msec() < _pending_np_ready_msec:
		return
	_pending_np_active = false
	_execute_noble_phantasm(_pending_np_style, _pending_np_direction)


func _execute_noble_phantasm(style: int, direction: Vector2) -> void:
	_fx_impact(global_position, 0.85, "np_impact")
	match style:
		ServantData.NoblePhantasmStyle.BEAM:
			_server_np_beam(direction)
		ServantData.NoblePhantasmStyle.REALITY_MARBLE:
			is_reality_marble_active = true
		ServantData.NoblePhantasmStyle.DASH:
			_server_np_dash(direction)
		ServantData.NoblePhantasmStyle.NOVA:
			_server_np_nova(direction)
		ServantData.NoblePhantasmStyle.BARRAGE:
			_server_np_barrage(direction)
		ServantData.NoblePhantasmStyle.SUPPORT:
			_server_np_support()
		ServantData.NoblePhantasmStyle.REFLECT:
			_server_np_reflect()


func _broadcast_np_telegraph(style: int, origin: Vector2, direction: Vector2, length: float) -> void:
	var colour: Color = servant_data.noble_phantasm_color
	if multiplayer.get_peers().is_empty():
		_rpc_np_telegraph(style, origin, direction, length, NP_WINDUP_SECONDS, colour)
	else:
		_rpc_np_telegraph.rpc(style, origin, direction, length, NP_WINDUP_SECONDS, colour)


@rpc("authority", "call_local", "reliable")
func _rpc_np_telegraph(style: int, origin: Vector2, direction: Vector2, length: float, duration: float, colour: Color) -> void:
	np_telegraph.emit(style, origin, direction, length, duration, colour)


func _server_np_beam(direction: Vector2) -> void:
	var beam_range: float = maxf(servant_data.noble_phantasm_range, 240.0)
	var damage: float = _outgoing_damage(servant_data.noble_phantasm_damage)
	for target: Node2D in _enemy_units(beam_range + BODY_RADIUS):
		var offset: Vector2 = target.global_position - global_position
		var along: float = offset.dot(direction)
		if along <= 0.0 or along > beam_range + BODY_RADIUS:
			continue
		if absf(offset.cross(direction)) > BEAM_WIDTH * 0.5 + BODY_RADIUS:
			continue
		target.call("receive_damage", damage, owner_id, servant_data.servant_class)
	_broadcast_effect(EffectKind.BEAM, global_position, direction, beam_range)


func _server_np_dash(direction: Vector2) -> void:
	var start: Vector2 = global_position
	var motion: Vector2 = direction * maxf(servant_data.noble_phantasm_range, 160.0)
	var collision: KinematicCollision2D = move_and_collide(motion)
	if collision != null:
		motion = collision.get_travel()
	var end: Vector2 = global_position
	var damage: float = _outgoing_damage(servant_data.noble_phantasm_damage)
	for target: Node2D in _enemy_units(start.distance_to(end) + 120.0):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(target.global_position, start, end)
		if closest.distance_to(target.global_position) <= DASH_HIT_RADIUS + BODY_RADIUS:
			target.call("receive_damage", damage, owner_id, servant_data.servant_class)
			if servant_data.strips_buffs_on_np and target.has_method("strip_buffs"):
				target.call("strip_buffs")
				if servant_data.anti_heal_duration > 0.0 and target.has_method("apply_anti_heal"):
					target.call("apply_anti_heal", servant_data.anti_heal_duration)
	_broadcast_effect(EffectKind.DASH, start, direction, start.distance_to(end))


func _server_np_nova(_direction: Vector2) -> void:
	var radius: float = maxf(servant_data.noble_phantasm_range, 140.0)
	var damage: float = _outgoing_damage(servant_data.noble_phantasm_damage * get_effective_spell_multiplier())
	_server_aoe_damage(radius, damage)
	_broadcast_effect(EffectKind.NOVA, global_position, aim_direction, radius)


func _server_np_barrage(direction: Vector2) -> void:
	var count: int = maxi(servant_data.barrage_projectiles, 8)
	var spread: float = deg_to_rad(38.0)
	for index: int in range(count):
		var ratio: float = float(index) / float(maxi(count - 1, 1)) - 0.5
		var shot: Vector2 = direction.rotated(spread * ratio)
		_fire_projectile(shot, _outgoing_damage(servant_data.noble_phantasm_damage), servant_data.projectile_speed * 1.25, servant_data.noble_phantasm_color)
	_broadcast_effect(EffectKind.NOVA, global_position, direction, 140.0)


func _server_np_support() -> void:
	var radius: float = maxf(servant_data.noble_phantasm_range, 180.0)
	health = clampf(health + servant_data.noble_phantasm_damage, 0.0, max_health)
	is_shielded = true
	_shield_until_msec = Time.get_ticks_msec() + int(servant_data.noble_phantasm_duration * 1000.0)
	if master_unit != null and is_instance_valid(master_unit) and master_unit.is_alive:
		master_unit.heal(servant_data.noble_phantasm_damage)
	for ally: Node2D in _allied_units(radius):
		if ally.has_method("heal"):
			ally.call("heal", servant_data.noble_phantasm_damage * 0.6)
	_broadcast_effect(EffectKind.NOVA, global_position, aim_direction, radius)


func _server_np_reflect() -> void:
	is_reflecting = true
	_reflect_until_msec = Time.get_ticks_msec() + int(servant_data.noble_phantasm_duration * 1000.0)
	_broadcast_effect(EffectKind.NOVA, global_position, aim_direction, maxf(servant_data.noble_phantasm_range, 120.0))


func _outgoing_damage(base_damage: float) -> float:
	var damage: float = base_damage
	if is_damage_buffed:
		damage *= servant_data.skill_buff_damage_multiplier
	if servant_data.critical_chance > 0.0 and randf() < servant_data.critical_chance:
		damage *= servant_data.critical_multiplier
	if is_fame_buffed:
		damage *= 1.15
	return damage


func _handle_death() -> void:
	_is_alive = false
	_is_stealthed = false
	is_reality_marble_active = false
	velocity = Vector2.ZERO
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	died.emit()


func heal(amount: float) -> void:
	if not multiplayer.is_server() or not _is_alive:
		return
	if is_anti_healed:
		return
	health = clampf(health + maxf(amount, 0.0), 0.0, max_health)
	health_changed.emit(health, max_health)


func learn_name_from_master() -> void:
	if not multiplayer.is_server():
		return
	if is_name_known_to_master:
		return
	is_name_known_to_master = true
	name_knowledge_changed.emit(true)
	queue_redraw()


func publicly_reveal_true_name() -> void:
	if not multiplayer.is_server():
		return
	if not is_name_known_to_master or is_true_name_revealed:
		return
	is_true_name_revealed = true
	is_fame_buffed = true
	_fame_until_msec = Time.get_ticks_msec() + 30000
	true_name_revealed.emit()
	publicly_revealed.emit()
	_fx_text("TRUE NAME REVEALED!", global_position + Vector2(0.0, -54.0), Color(0.98, 0.82, 0.35))
	_fx_sfx("command_spell", global_position)
	queue_redraw()


func grant_combat_buff(duration: float) -> void:
	if not multiplayer.is_server():
		return
	var now: int = Time.get_ticks_msec()
	is_damage_buffed = true
	is_speed_buffed = true
	_damage_buff_until_msec = maxi(_damage_buff_until_msec, now + int(duration * 1000.0))
	_speed_buff_until_msec = maxi(_speed_buff_until_msec, _damage_buff_until_msec)
	queue_redraw()


func apply_anti_heal(duration: float) -> void:
	if not multiplayer.is_server():
		return
	if duration <= 0.0:
		return
	is_anti_healed = true
	_anti_heal_until_msec = maxi(_anti_heal_until_msec, Time.get_ticks_msec() + int(duration * 1000.0))
	queue_redraw()


func strip_buffs() -> void:
	if not multiplayer.is_server():
		return
	is_damage_buffed = false
	is_speed_buffed = false
	is_shielded = false
	is_reality_marble_active = false
	queue_redraw()


func try_appropriate_projectile() -> bool:
	if not multiplayer.is_server():
		return false
	if servant_data == null or not servant_data.projectile_appropriation:
		return false
	var now: int = Time.get_ticks_msec()
	if now < _appropriation_ready_msec:
		return false
	_appropriation_ready_msec = now + 2000
	return true


func reset_np_cooldown() -> void:
	if multiplayer.is_server():
		_np_ready_at_msec = 0


func _aim_at(target: Node2D) -> Vector2:
	var offset: Vector2 = target.global_position - global_position
	if offset.length_squared() < 0.0001:
		return Vector2.RIGHT
	return offset.normalized()


func apply_shield(duration: float) -> void:
	if not multiplayer.is_server() or not _is_alive:
		return
	is_shielded = true
	_shield_until_msec = maxi(_shield_until_msec, Time.get_ticks_msec() + int(maxf(duration, 0.5) * 1000.0))


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
	for target: Node2D in _enemy_units(max_distance):
		var distance: float = global_position.distance_to(target.global_position)
		if distance < nearest_distance:
			nearest = target
			nearest_distance = distance
	return nearest


func _enemy_units(max_distance: float = INF) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("player_units"):
		var unit: Node2D = node as Node2D
		if unit == null or unit == self:
			continue
		if not unit.has_method("receive_damage"):
			continue
		if int(unit.get("owner_id")) == owner_id:
			continue
		if match_state != null and not match_state.can_damage(owner_id, int(unit.get("owner_id"))):
			continue
		if global_position.distance_to(unit.global_position) <= max_distance:
			result.append(unit)
	return result


func _allied_units(max_distance: float = INF) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("player_units"):
		var unit: Node2D = node as Node2D
		if unit == null or unit == self:
			continue
		if int(unit.get("owner_id")) == owner_id:
			continue
		if match_state != null and match_state.are_allied(owner_id, int(unit.get("owner_id"))):
			if global_position.distance_to(unit.global_position) <= max_distance:
				result.append(unit)
	return result


func _find_unit_by_owner(peer_id: int) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("player_units"):
		var unit: Node2D = node as Node2D
		if unit != null and int(unit.get("owner_id")) == peer_id:
			return unit
	return null


func _break_stealth() -> void:
	if is_stealthed:
		is_stealthed = false


func _is_valid_peer_call() -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == owner_id:
		return true
	return sender == 0 and owner_id == multiplayer.get_unique_id()


func _broadcast_effect(kind: EffectKind, origin: Vector2, direction: Vector2, length: float) -> void:
	var normalized: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	if multiplayer.get_peers().is_empty():
		_rpc_play_effect(kind, origin, normalized, length)
	else:
		_rpc_play_effect.rpc(kind, origin, normalized, length)


@rpc("authority", "call_local", "reliable")
func _rpc_play_effect(kind: EffectKind, origin: Vector2, direction: Vector2, length: float) -> void:
	_effect_kind = kind
	_effect_origin = origin
	_effect_direction = direction
	_effect_length = length
	_effect_color = _effect_color_for(kind)
	_effect_start_msec = Time.get_ticks_msec()
	_effect_until_msec = _effect_start_msec + EFFECT_DURATION_MSEC
	queue_redraw()


func _effect_color_for(kind: EffectKind) -> Color:
	match kind:
		EffectKind.BEAM, EffectKind.NOVA:
			return servant_data.noble_phantasm_color
		EffectKind.SLASH:
			return _class_color().lightened(0.25)
		EffectKind.DASH:
			return servant_data.noble_phantasm_color.lightened(0.2)
	return Color.WHITE


func _draw() -> void:
	var body_color: Color = _class_color()
	var down: bool = not _is_alive
	if down:
		body_color = Color(0.28, 0.3, 0.36, 0.5)
	elif is_reality_marble_active:
		body_color = body_color.lerp(Color(0.95, 0.2, 0.55), 0.4)

	draw_circle(Vector2(0.0, 5.0), BODY_RADIUS + 3.0, Color(0.0, 0.0, 0.0, 0.35))
	draw_circle(Vector2.ZERO, BODY_RADIUS, body_color)
	draw_arc(Vector2.ZERO, BODY_RADIUS, 0.0, TAU, 32, Color(0.05, 0.06, 0.1, 0.9), 2.0, true)

	if is_shielded:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 7.0, 0.0, TAU, 40, Color(0.7, 0.85, 1.0, 0.8), 3.0, true)
	if is_reflecting:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 10.0, 0.0, TAU, 40, Color(0.7, 0.15, 0.2, 0.8), 3.0, true)
	if is_reality_marble_active:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 13.0, 0.0, TAU, 40, Color(0.95, 0.25, 0.6, 0.6), 2.0, true)
	if territory_bonus_active:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 16.0, 0.0, TAU, 40, Color(0.72, 0.45, 1.0, 0.6), 2.0, true)
	if is_stealthed:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 5.0, 0.0, TAU, 28, Color(0.7, 0.75, 0.9, 0.35), 1.5, true)
	if is_damage_buffed:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 19.0, 0.0, TAU, 32, Color(1.0, 0.55, 0.2, 0.55), 2.0, true)
	if is_fame_buffed:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 22.0, 0.0, TAU, 36, Color(0.95, 0.82, 0.3, 0.65), 2.0, true)
	if is_anti_healed:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 5.0, 0.0, TAU, 30, Color(0.45, 0.9, 0.35, 0.4), 1.5, true)

	if not down:
		draw_line(Vector2.ZERO, aim_direction * (BODY_RADIUS + 14.0), Color(1.0, 0.92, 0.65), 3.0, true)

	var bar_width: float = 48.0
	var health_ratio: float = clampf(health / max_health, 0.0, 1.0) if max_health > 0.0 else 0.0
	var mana_ratio: float = clampf(mana / max_mana, 0.0, 1.0) if max_mana > 0.0 else 0.0
	draw_rect(Rect2(-bar_width * 0.5, -36.0, bar_width, 4.0), Color(0.08, 0.09, 0.13, 0.9))
	draw_rect(Rect2(-bar_width * 0.5, -36.0, bar_width * health_ratio, 4.0), Color(0.9, 0.28, 0.3))
	draw_rect(Rect2(-bar_width * 0.5, -30.0, bar_width, 4.0), Color(0.08, 0.09, 0.13, 0.9))
	draw_rect(Rect2(-bar_width * 0.5, -30.0, bar_width * mana_ratio, 4.0), Color(0.28, 0.62, 1.0))

	var viewer: int = multiplayer.get_unique_id()
	var label: String = get_display_name_for(viewer)
	if down:
		label += " [DOWN]"
	elif is_stealthed:
		label += " [STEALTH]"
	if is_fame_buffed:
		label += " [FAME]"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-bar_width * 0.5, -44.0),
		"%s P%d" % [label, owner_id],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color(0.78, 0.82, 0.95)
	)

	_draw_effect()


func _draw_effect() -> void:
	if _effect_kind == EffectKind.NONE:
		return
	var now: int = Time.get_ticks_msec()
	if now >= _effect_until_msec:
		return
	var elapsed: float = float(now - _effect_start_msec) / float(EFFECT_DURATION_MSEC)
	var alpha: float = clampf(1.0 - elapsed, 0.0, 1.0)
	var color: Color = _effect_color
	var start: Vector2 = to_local(_effect_origin)
	var end: Vector2 = start + _effect_direction * _effect_length

	match _effect_kind:
		EffectKind.SLASH:
			var arc: float = deg_to_rad(servant_data.melee_arc_degrees)
			var facing: float = _effect_direction.angle()
			draw_arc(start, _effect_length, facing - arc * 0.5, facing + arc * 0.5, 32, Color(color.r, color.g, color.b, alpha * 0.8), 8.0, true)
		EffectKind.BEAM:
			draw_line(start, end, Color(color.r, color.g, color.b, alpha * 0.22), 38.0, true)
			draw_line(start, end, Color(color.r, color.g, color.b, alpha * 0.85), 14.0, true)
			draw_line(start, end, Color(1.0, 1.0, 1.0, alpha * 0.8), 4.0, true)
		EffectKind.NOVA:
			var radius: float = _effect_length * (0.55 + elapsed * 0.45)
			draw_circle(start, radius, Color(color.r, color.g, color.b, alpha * 0.1))
			draw_arc(start, radius, 0.0, TAU, 64, Color(color.r, color.g, color.b, alpha * 0.9), 6.0, true)
		EffectKind.DASH:
			draw_line(start, end, Color(color.r, color.g, color.b, alpha * 0.2), 30.0, true)
			draw_line(start, end, Color(color.r, color.g, color.b, alpha * 0.9), 6.0, true)


func _class_color() -> Color:
	match servant_data.servant_class:
		ServantData.ServantClass.SABER:
			return Color(0.35, 0.6, 1.0)
		ServantData.ServantClass.ARCHER:
			return Color(0.35, 0.85, 0.65)
		ServantData.ServantClass.LANCER:
			return Color(0.85, 0.4, 0.45)
		ServantData.ServantClass.RIDER:
			return Color(0.9, 0.7, 0.3)
		ServantData.ServantClass.CASTER:
			return Color(0.6, 0.45, 0.95)
		ServantData.ServantClass.ASSASSIN:
			return Color(0.45, 0.45, 0.52)
		ServantData.ServantClass.BERSERKER:
			return Color(0.8, 0.25, 0.2)
		ServantData.ServantClass.RULER:
			return Color(0.95, 0.9, 0.55)
		ServantData.ServantClass.AVENGER:
			return Color(0.5, 0.12, 0.18)
	return Color(0.7, 0.7, 0.9)
