class_name ClassTriangle
extends RefCounted
## Fire Emblem-style class triangle and extra-class asymmetry.
##
## Attack multipliers are applied on the server at damage resolution. The
## resulting multiplier combines offense and defense (e.g. Berserker attacking
## Ruler = 1.5 * 0.75).

const ADVANTAGE: float = 1.35
const DISADVANTAGE: float = 0.75
const BERSERKER_OFFENSE: float = 1.5
const BERSERKER_DEFENSE: float = 1.5
const RULER_DEFENSE: float = 0.75
const RULER_VS_AVENGER: float = 1.5

const KNIGHT_CLASSES: Array = [
	ServantData.ServantClass.SABER,
	ServantData.ServantClass.LANCER,
	ServantData.ServantClass.ARCHER,
]
const CAVALRY_CLASSES: Array = [
	ServantData.ServantClass.RIDER,
	ServantData.ServantClass.CASTER,
	ServantData.ServantClass.ASSASSIN,
]
const STANDARD_CLASSES: Array = [
	ServantData.ServantClass.SABER,
	ServantData.ServantClass.ARCHER,
	ServantData.ServantClass.LANCER,
	ServantData.ServantClass.RIDER,
	ServantData.ServantClass.CASTER,
	ServantData.ServantClass.ASSASSIN,
	ServantData.ServantClass.BERSERKER,
]


static func get_offense_multiplier(attacker: int, defender: int) -> float:
	var multiplier: float = 1.0

	if attacker == ServantData.ServantClass.BERSERKER:
		multiplier *= BERSERKER_OFFENSE
	# Avenger -> Ruler is represented once, in Ruler's damage-taken rule below.

	multiplier *= _triangle_multiplier(attacker, defender)
	return multiplier


static func get_defense_multiplier(attacker: int, defender: int) -> float:
	var multiplier: float = 1.0

	if defender == ServantData.ServantClass.BERSERKER:
		multiplier *= BERSERKER_DEFENSE
	if defender == ServantData.ServantClass.RULER:
		if attacker == ServantData.ServantClass.AVENGER:
			multiplier *= RULER_VS_AVENGER
		elif STANDARD_CLASSES.has(attacker):
			multiplier *= RULER_DEFENSE

	return multiplier


static func get_total_multiplier(attacker: int, defender: int) -> float:
	if attacker < 0 or defender < 0:
		return 1.0
	return get_offense_multiplier(attacker, defender) * get_defense_multiplier(attacker, defender)


static func get_advantage_label(attacker: int, defender: int) -> String:
	var multiplier: float = get_total_multiplier(attacker, defender)
	if multiplier > 1.01:
		return "ADVANTAGE"
	if multiplier < 0.99:
		return "DISADVANTAGE"
	return "NEUTRAL"


static func _triangle_multiplier(attacker: int, defender: int) -> float:
	# Knight triangle: Saber > Lancer > Archer > Saber.
	if KNIGHT_CLASSES.has(attacker) and KNIGHT_CLASSES.has(defender):
		if attacker == ServantData.ServantClass.SABER and defender == ServantData.ServantClass.LANCER:
			return ADVANTAGE
		if attacker == ServantData.ServantClass.LANCER and defender == ServantData.ServantClass.ARCHER:
			return ADVANTAGE
		if attacker == ServantData.ServantClass.ARCHER and defender == ServantData.ServantClass.SABER:
			return ADVANTAGE
		if defender == ServantData.ServantClass.SABER and attacker == ServantData.ServantClass.LANCER:
			return DISADVANTAGE
		if defender == ServantData.ServantClass.LANCER and attacker == ServantData.ServantClass.ARCHER:
			return DISADVANTAGE
		if defender == ServantData.ServantClass.ARCHER and attacker == ServantData.ServantClass.SABER:
			return DISADVANTAGE

	# Cavalry/Extra triangle: Rider > Caster > Assassin > Rider.
	if CAVALRY_CLASSES.has(attacker) and CAVALRY_CLASSES.has(defender):
		if attacker == ServantData.ServantClass.RIDER and defender == ServantData.ServantClass.CASTER:
			return ADVANTAGE
		if attacker == ServantData.ServantClass.CASTER and defender == ServantData.ServantClass.ASSASSIN:
			return ADVANTAGE
		if attacker == ServantData.ServantClass.ASSASSIN and defender == ServantData.ServantClass.RIDER:
			return ADVANTAGE
		if defender == ServantData.ServantClass.CASTER and attacker == ServantData.ServantClass.ASSASSIN:
			return DISADVANTAGE
		if defender == ServantData.ServantClass.ASSASSIN and attacker == ServantData.ServantClass.RIDER:
			return DISADVANTAGE
		if defender == ServantData.ServantClass.RIDER and attacker == ServantData.ServantClass.CASTER:
			return DISADVANTAGE

	return 1.0
