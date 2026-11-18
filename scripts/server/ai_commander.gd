class_name AICommander
extends Node
## Server-only tactical commander for AI slots and disconnected-player takeover.
##
## The AI never mutates combat state directly. It issues the same move / attack /
## skill / Noble Phantasm / Command Spell intents that human RPC handlers use and
## lets the authoritative units resolve them.

var arena: Node
var owner_id: int = 0
var control_master: bool = true
var control_servant: bool = true

var _think_timer: float = 0.0
var _think_interval: float = 0.4
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_master_health: float = -1.0
var _last_servant_health: float = -1.0
var _last_command_spell_msec: int = 0


func _ready() -> void:
	_rng.randomize()
	_think_interval = _rng.randf_range(0.3, 0.5)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_think_timer += delta
	if _think_timer < _think_interval:
		return
	_think_timer = 0.0
	_think_interval = _rng.randf_range(0.3, 0.5)
	_think()


func _think() -> void:
	if arena == null or not is_instance_valid(arena):
		queue_free()
		return
	if arena.has_method("is_match_started") and not bool(arena.call("is_match_started")):
		return

	var servant: ServantController = arena.call("_get_servant", owner_id) as ServantController
	var master: MasterController = arena.call("_get_master", owner_id) as MasterController
	if servant == null and master == null:
		queue_free()
		return

	var match_state: MatchState = arena.call("get_match_state") as MatchState
	var enemies: Array[Node2D] = _enemy_units(servant, master, match_state)

	# Detect direct Master damage and emergency Servant duels.
	if control_master and master != null and master.is_alive:
		if _last_master_health >= 0.0 and master.health < _last_master_health - 0.5:
			_try_command_spell(master, servant, enemies, true)
		_last_master_health = master.health
	if servant != null and servant.is_alive:
		_last_servant_health = servant.health

	if control_master and master != null and master.is_alive and servant != null and servant.is_alive:
		var servant_hp_ratio: float = servant.health / maxf(servant.max_health, 1.0)
		var close_enemy: Node2D = _nearest_enemy(enemies, servant.global_position)
		if servant_hp_ratio < 0.28 and close_enemy != null:
			if close_enemy.global_position.distance_to(servant.global_position) < 360.0:
				_try_command_spell(master, servant, enemies, false)

	var best_leyline: LeylineNode = _choose_leyline(master, match_state)

	if control_master and master != null and master.is_alive:
		_drive_master(master, servant, enemies, best_leyline)

	if control_servant and servant != null and servant.is_alive:
		_drive_servant(servant, master, enemies, best_leyline)

	if control_servant:
		_use_skills(servant, master, enemies, best_leyline)
		_use_noble_phantasm(servant, enemies)
	if control_master:
		_use_master_skills(master, servant, enemies)


func _drive_master(master: MasterController, servant: ServantController, enemies: Array[Node2D], best_leyline: LeylineNode) -> void:
	var nearest: Node2D = _nearest_enemy(enemies, master.global_position)
	var nearest_distance: float = 99999.0
	if nearest != null:
		nearest_distance = master.global_position.distance_to(nearest.global_position)

	if nearest != null and nearest_distance < 430.0 and master.mana >= 3.0:
		master.server_command_attack(nearest)
		return

	if nearest != null and nearest_distance < 260.0 and master.health / maxf(master.max_health, 1.0) < 0.45:
		var escape_point: Vector2 = _master_retreat_point(master, servant)
		master.server_command_move(escape_point, false)
		return

	if best_leyline != null:
		var distance: float = master.global_position.distance_to(best_leyline.global_position)
		var should_move: bool = distance > 95.0
		if master.mana / maxf(master.max_mana, 1.0) < 0.5:
			should_move = distance > 45.0
		if should_move:
			master.server_command_move(best_leyline.global_position, false)
			return

	if servant != null and servant.is_alive:
		var escort: Vector2 = servant.global_position - (servant.global_position - master.global_position).normalized() * 110.0
		if master.global_position.distance_to(escort) > 140.0:
			master.server_command_move(escort, false)


func _drive_servant(servant: ServantController, master: MasterController, enemies: Array[Node2D], best_leyline: LeylineNode) -> void:
	var target: Node2D = _choose_target(servant, enemies)
	var hp_ratio: float = servant.health / maxf(servant.max_health, 1.0)

	if target != null:
		var target_distance: float = servant.global_position.distance_to(target.global_position)
		var retreat: bool = _should_retreat(servant, target, hp_ratio)

		# Assassins open with Presence Concealment before flanking a Master.
		if servant.servant_data.servant_class == ServantData.ServantClass.ASSASSIN and not servant.is_stealthed:
			var stealth_slot: int = _find_skill_slot(servant, ServantData.SkillStyle.STEALTH)
			if stealth_slot >= 0:
				servant._server_use_skill(stealth_slot, _direction_to(servant, target))

		if retreat:
			servant.server_command_move(_retreat_point(servant, master), false)
			return

		if servant.servant_data.attack_style == ServantData.AttackStyle.PROJECTILE:
			var preferred_distance: float = maxf(servant.servant_data.attack_range * 0.65, 220.0)
			if target_distance < preferred_distance and servant.servant_data.servant_class != ServantData.ServantClass.BERSERKER:
				var away: Vector2 = (servant.global_position - target.global_position).normalized()
				servant.server_command_move(servant.global_position + away * 170.0, false)
				return

		servant.server_command_attack(target)
		return

	# No visible/hostile unit: push toward the contested Leyline or the arena
	# centre while the Master secures the Mana economy.
	if best_leyline != null:
		var forward: Vector2 = best_leyline.global_position
		var radial: Vector2 = forward.normalized()
		if radial.length_squared() < 0.001:
			radial = Vector2.RIGHT
		var push_point: Vector2 = forward + radial * 150.0
		if servant.global_position.distance_to(push_point) > 60.0:
			servant.server_command_move(push_point, true)
			return
	servant.server_command_move(Vector2.ZERO, true)


func _use_skills(servant: ServantController, master: MasterController, enemies: Array[Node2D], best_leyline: LeylineNode) -> void:
	if servant == null or not servant.is_alive or servant.servant_data == null:
		return
	var target: Node2D = _choose_target(servant, enemies)
	var direction: Vector2 = _direction_to(servant, target)
	var hp_ratio: float = servant.health / maxf(servant.max_health, 1.0)

	# Ruler scouting: reveal unrevealed enemies.
	if servant.servant_data.servant_class == ServantData.ServantClass.RULER:
		var scan_slot: int = _find_skill_slot(servant, ServantData.SkillStyle.SCAN)
		if scan_slot >= 0 and _has_unrevealed_enemy(enemies):
			servant._server_use_skill(scan_slot, direction)
			return

	# Caster traps are placed on the contested/captured Leyline.
	if servant.servant_data.servant_class == ServantData.ServantClass.CASTER and best_leyline != null:
		var trap_slot: int = _find_skill_slot(servant, ServantData.SkillStyle.TRAP)
		if trap_slot >= 0:
			servant._server_use_skill(trap_slot, _direction_to(servant, best_leyline))
			return

	# Assassin stealth when a target is available.
	if servant.servant_data.servant_class == ServantData.ServantClass.ASSASSIN and target != null and not servant.is_stealthed:
		var stealth_slot_2: int = _find_skill_slot(servant, ServantData.SkillStyle.STEALTH)
		if stealth_slot_2 >= 0:
			servant._server_use_skill(stealth_slot_2, direction)
			return

	# Generic offensive/support skill priority.
	for slot: int in range(2):
		var style: int = servant.servant_data.skill_1_style if slot == 0 else servant.servant_data.skill_2_style
		var cost: float = servant.servant_data.skill_1_cost if slot == 0 else servant.servant_data.skill_2_cost
		if servant.mana < cost:
			continue
		match style:
			ServantData.SkillStyle.BUFF:
				if target != null and not servant.is_damage_buffed:
					servant._server_use_skill(slot, direction)
					return
			ServantData.SkillStyle.AOE:
				if target != null and servant.global_position.distance_to(target.global_position) <= servant.servant_data.skill_aoe_radius + 100.0:
					servant._server_use_skill(slot, direction)
					return
			ServantData.SkillStyle.DASH:
				if target != null and servant.global_position.distance_to(target.global_position) > servant.servant_data.attack_range:
					servant._server_use_skill(slot, direction)
					return
			ServantData.SkillStyle.BARRAGE:
				if target != null:
					servant._server_use_skill(slot, direction)
					return
			ServantData.SkillStyle.HEAL:
				if hp_ratio < 0.65:
					servant._server_use_skill(slot, direction)
					return
			ServantData.SkillStyle.SCAN:
				if _has_unrevealed_enemy(enemies):
					servant._server_use_skill(slot, direction)
					return


func _use_noble_phantasm(servant: ServantController, enemies: Array[Node2D]) -> void:
	if servant == null or not servant.is_alive or servant.servant_data == null:
		return
	if servant.mana < servant.servant_data.noble_phantasm_cost:
		return
	var target: Node2D = _choose_target(servant, enemies)
	if target == null and servant.servant_data.noble_phantasm_style != ServantData.NoblePhantasmStyle.SUPPORT:
		return
	var distance: float = 0.0
	if target != null:
		distance = servant.global_position.distance_to(target.global_position)
	var style: int = servant.servant_data.noble_phantasm_style
	var range: float = maxf(servant.servant_data.noble_phantasm_range, 220.0)
	var hp_ratio: float = servant.health / maxf(servant.max_health, 1.0)

	match style:
		ServantData.NoblePhantasmStyle.SUPPORT:
			if hp_ratio < 0.55 or _nearby_enemy_count(servant, enemies, 320.0) > 0:
				servant._server_use_noble_phantasm(_direction_to(servant, target))
		ServantData.NoblePhantasmStyle.REFLECT:
			if hp_ratio < 0.65 and _nearby_enemy_count(servant, enemies, 320.0) > 0:
				servant._server_use_noble_phantasm(_direction_to(servant, target))
		ServantData.NoblePhantasmStyle.REALITY_MARBLE:
			if target != null and distance < 620.0 and not servant.is_reality_marble_active:
				servant._server_use_noble_phantasm(_direction_to(servant, target))
		_:
			if target != null and distance <= range + 180.0:
				servant._server_use_noble_phantasm(_direction_to(servant, target))


func _use_master_skills(master: MasterController, servant: ServantController, enemies: Array[Node2D]) -> void:
	if master == null or not master.is_alive or master.master_data == null:
		return
	var target: Node2D = _nearest_enemy(enemies, master.global_position)
	var servant_hp_ratio: float = 1.0
	if servant != null and servant.is_alive:
		servant_hp_ratio = servant.health / maxf(servant.max_health, 1.0)

	for slot: int in range(2):
		var style: int = master.master_data.skill_1_style if slot == 0 else master.master_data.skill_2_style
		var cost: float = master.master_data.skill_1_cost if slot == 0 else master.master_data.skill_2_cost
		if master.mana < cost:
			continue
		match style:
			MasterData.MasterSkillStyle.HEAL_SERVANT, MasterData.MasterSkillStyle.SHIELD_SERVANT:
				if servant_hp_ratio < 0.7:
					master._server_use_skill(slot, _direction_to(master, target))
					return
			MasterData.MasterSkillStyle.BURST, MasterData.MasterSkillStyle.DRAIN:
				if target != null and master.global_position.distance_to(target.global_position) < 520.0:
					master._server_use_skill(slot, _direction_to(master, target))
					return
			MasterData.MasterSkillStyle.REVEAL:
				if _has_unrevealed_enemy(enemies):
					master._server_use_skill(slot, _direction_to(master, target))
					return
			MasterData.MasterSkillStyle.HASTE_SELF:
				if target != null and master.global_position.distance_to(target.global_position) < 380.0:
					master._server_use_skill(slot, _direction_to(master, target))
					return


func _try_command_spell(master: MasterController, servant: ServantController, _enemies: Array[Node2D], direct_master_damage: bool) -> void:
	if master == null or not master.is_alive or servant == null or not servant.is_alive:
		return
	if master.command_spells_left <= 0:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_command_spell_msec < 2000:
		return
	if direct_master_damage or servant.health / maxf(servant.max_health, 1.0) < 0.3:
		master._server_use_command_spell()
		_last_command_spell_msec = now


func _choose_leyline(master: MasterController, match_state: MatchState) -> LeylineNode:
	var leylines: Array[LeylineNode] = arena.call("get_leylines")
	if leylines.is_empty():
		return null
	var origin: Vector2 = master.global_position if master != null and master.is_alive else Vector2.ZERO
	var lowest_mana: bool = true
	if master != null and master.is_alive:
		lowest_mana = master.mana / maxf(master.max_mana, 1.0) < 0.5

	var best: LeylineNode = null
	var best_score: float = INF
	for leyline: LeylineNode in leylines:
		var score: float = origin.distance_to(leyline.global_position)
		if leyline.owner_peer_id == owner_id:
			score += 900.0 if lowest_mana else -120.0
		elif leyline.owner_peer_id == 0:
			score += 0.0
		else:
			score -= 60.0
		if score < best_score:
			best_score = score
			best = leyline
	return best


func _choose_target(servant: ServantController, enemies: Array[Node2D]) -> Node2D:
	if enemies.is_empty():
		return null
	var best: Node2D = null
	var best_score: float = -INF
	for enemy: Node2D in enemies:
		if not enemy.has_method("receive_damage"):
			continue
		var score: float = 50.0
		var distance: float = servant.global_position.distance_to(enemy.global_position)
		score -= distance * 0.06
		if enemy is ServantController:
			var other: ServantController = enemy as ServantController
			if other.servant_data != null:
				score += ClassTriangle.get_total_multiplier(servant.servant_data.servant_class, other.servant_data.servant_class) * 70.0
				score += (1.0 - other.health / maxf(other.max_health, 1.0)) * 25.0
		else:
			score += 35.0
			if servant.servant_data.servant_class == ServantData.ServantClass.ASSASSIN:
				score += 30.0
		if score > best_score:
			best_score = score
			best = enemy
	return best


func _should_retreat(servant: ServantController, target: Node2D, hp_ratio: float) -> bool:
	if servant.servant_data.servant_class == ServantData.ServantClass.BERSERKER and hp_ratio > 0.2:
		return false
	if hp_ratio < 0.32:
		return true
	if target is ServantController:
		var other: ServantController = target as ServantController
		if other.servant_data != null:
			var threat: float = ClassTriangle.get_total_multiplier(other.servant_data.servant_class, servant.servant_data.servant_class)
			if threat >= 1.2 and hp_ratio < 0.68:
				return true
	return false


func _retreat_point(unit: Node2D, master: MasterController) -> Vector2:
	if master != null and master.is_alive:
		var offset: Vector2 = unit.global_position - master.global_position
		if offset.length_squared() < 25.0:
			offset = Vector2.RIGHT
		return master.global_position + offset.normalized() * 90.0
	return Vector2.ZERO


func _master_retreat_point(master: MasterController, servant: ServantController) -> Vector2:
	if servant != null and servant.is_alive:
		var offset: Vector2 = servant.global_position - master.global_position
		if offset.length_squared() > 25.0:
			return master.global_position + offset.normalized() * 100.0
	var leylines: Array[LeylineNode] = arena.call("get_leylines")
	var best: LeylineNode = null
	var best_distance: float = INF
	for leyline: LeylineNode in leylines:
		if leyline.owner_peer_id != owner_id:
			continue
		var distance: float = master.global_position.distance_to(leyline.global_position)
		if distance < best_distance:
			best_distance = distance
			best = leyline
	if best != null:
		return best.global_position
	return Vector2.ZERO


func _enemy_units(servant: ServantController, master: MasterController, match_state: MatchState) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("player_units"):
		var unit: Node2D = node as Node2D
		if unit == null or not unit.has_method("receive_damage"):
			continue
		var foreign_owner: int = int(unit.get("owner_id"))
		if foreign_owner == owner_id:
			continue
		if not bool(unit.get("is_alive")):
			continue
		if match_state != null and not match_state.can_damage(owner_id, foreign_owner):
			continue
		result.append(unit)
	return result


func _nearest_enemy(enemies: Array[Node2D], from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for enemy: Node2D in enemies:
		var distance: float = from.distance_to(enemy.global_position)
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best


func _nearby_enemy_count(servant: ServantController, enemies: Array[Node2D], radius: float) -> int:
	var count: int = 0
	for enemy: Node2D in enemies:
		if servant.global_position.distance_to(enemy.global_position) <= radius:
			count += 1
	return count


func _has_unrevealed_enemy(enemies: Array[Node2D]) -> bool:
	for enemy: Node2D in enemies:
		if enemy is ServantController:
			var servant: ServantController = enemy as ServantController
			if not servant.is_true_name_revealed:
				return true
	return false


func _find_skill_slot(servant: ServantController, style: int) -> int:
	if servant.servant_data == null:
		return -1
	if servant.servant_data.skill_1_style == style:
		return 0
	if servant.servant_data.skill_2_style == style:
		return 1
	return -1


func _direction_to(unit: Node2D, target: Node2D) -> Vector2:
	if target == null:
		return Vector2.RIGHT
	var offset: Vector2 = target.global_position - unit.global_position
	if offset.length_squared() < 0.0001:
		return Vector2.RIGHT
	return offset.normalized()
