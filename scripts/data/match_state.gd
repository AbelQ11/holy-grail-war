class_name MatchState
extends RefCounted
## Server-authoritative team and diplomacy state for a running match.
##
## Fuyuki FFA gives every peer its own team and defaults all pairs to HOSTILE.
## Apocrypha assigns balanced RED/BLACK teams; Ruler players can be NEUTRAL
## arbiters. Damage is only allowed when [method can_damage] returns true.

var mode: MatchConfig.MatchMode = MatchConfig.MatchMode.FUYUKI_FFA
var teams: Dictionary = {}
var stances: Dictionary = {}

var _ffa_team_counter: int = 0


func _init(initial_mode: MatchConfig.MatchMode = MatchConfig.MatchMode.FUYUKI_FFA) -> void:
	mode = initial_mode


func set_mode(new_mode: MatchConfig.MatchMode) -> void:
	mode = new_mode
	teams.clear()
	stances.clear()
	_ffa_team_counter = 0


## Registers a peer. Optionally force a team; Apocrypha otherwise balances.
func assign_peer(peer_id: int, preferred_team: int = -1) -> int:
	if mode == MatchConfig.MatchMode.FUYUKI_FFA:
		_ffa_team_counter += 1
		teams[peer_id] = peer_id if peer_id != 0 else _ffa_team_counter
		return int(teams[peer_id])

	var team: int = preferred_team
	if team < 0:
		var red_count: int = 0
		var black_count: int = 0
		for assigned: int in teams.values():
			if assigned == MatchConfig.Team.RED:
				red_count += 1
			elif assigned == MatchConfig.Team.BLACK:
				black_count += 1
		team = MatchConfig.Team.RED if red_count <= black_count else MatchConfig.Team.BLACK
	teams[peer_id] = team
	return team


func get_team(peer_id: int) -> int:
	if teams.has(peer_id):
		return int(teams[peer_id])
	if mode == MatchConfig.MatchMode.FUYUKI_FFA:
		return peer_id
	return MatchConfig.Team.NEUTRAL


func set_stance(attacker: int, defender: int, stance: int) -> void:
	if not stances.has(attacker):
		stances[attacker] = {}
	if not stances.has(defender):
		stances[defender] = {}
	stances[attacker][defender] = stance
	stances[defender][attacker] = stance


func get_stance(attacker: int, defender: int) -> int:
	if stances.has(attacker):
		var row: Dictionary = stances[attacker]
		if row.has(defender):
			return int(row[defender])
	return MatchConfig.Stance.HOSTILE


func can_damage(attacker: int, defender: int) -> bool:
	if attacker == defender:
		return false

	if mode == MatchConfig.MatchMode.FUYUKI_FFA:
		return get_stance(attacker, defender) == MatchConfig.Stance.HOSTILE

	var attacker_team: int = get_team(attacker)
	var defender_team: int = get_team(defender)
	if attacker_team == MatchConfig.Team.NEUTRAL or defender_team == MatchConfig.Team.NEUTRAL:
		return false
	return attacker_team != defender_team


func are_allied(attacker: int, defender: int) -> bool:
	if mode == MatchConfig.MatchMode.FUYUKI_FFA:
		return get_stance(attacker, defender) == MatchConfig.Stance.ALLIED
	if get_team(attacker) == MatchConfig.Team.NEUTRAL or get_team(defender) == MatchConfig.Team.NEUTRAL:
		return true
	return get_team(attacker) == get_team(defender)


func remove_peer(peer_id: int) -> void:
	teams.erase(peer_id)
	stances.erase(peer_id)
	for row_key: Variant in stances.keys():
		var row: Dictionary = stances[row_key]
		row.erase(peer_id)


## Moves team/diplomacy state when an AI-takeover slot is reclaimed by a new
## peer id. In FFA the team identity follows the new peer.
func transfer_peer(old_peer: int, new_peer: int) -> void:
	if old_peer == new_peer:
		return
	var old_team: int = get_team(old_peer)
	teams.erase(old_peer)
	if mode == MatchConfig.MatchMode.FUYUKI_FFA:
		teams[new_peer] = new_peer
	else:
		teams[new_peer] = old_team

	if stances.has(old_peer):
		var old_row: Dictionary = stances[old_peer]
		stances.erase(old_peer)
		stances[new_peer] = old_row
	for row_key: Variant in stances.keys():
		var row: Dictionary = stances[row_key]
		if row.has(old_peer):
			var stance: int = int(row[old_peer])
			row.erase(old_peer)
			row[new_peer] = stance
