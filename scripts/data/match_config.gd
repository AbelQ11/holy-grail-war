class_name MatchConfig
extends Resource
## Match-level configuration for the two supported modes.

enum MatchMode {
	FUYUKI_FFA,
	APOCRYPHA_7V7,
}

enum Team {
	RED,
	BLACK,
	NEUTRAL,
}

enum Stance {
	HOSTILE,
	NEUTRAL,
	ALLIED,
}

const TEAM_NAMES: Array = ["RED", "BLACK", "NEUTRAL"]
const STANCE_NAMES: Array = ["HOSTILE", "NEUTRAL", "ALLIED"]

@export var mode: MatchMode = MatchMode.FUYUKI_FFA
@export_range(1, 7, 1) var max_pairs_per_side: int = 7
@export var allow_ruler_arbiter: bool = true


static func mode_name(value: int) -> String:
	match value:
		MatchMode.FUYUKI_FFA:
			return "FUYUKI FFA"
		MatchMode.APOCRYPHA_7V7:
			return "APOCRYPHA 7v7"
	return "UNKNOWN"


static func team_name(value: int) -> String:
	if value < 0:
		return "PENDING"
	if value >= 0 and value < TEAM_NAMES.size():
		return String(TEAM_NAMES[value])
	return "FFA"


static func stance_name(value: int) -> String:
	if value >= 0 and value < STANCE_NAMES.size():
		return String(STANCE_NAMES[value])
	return "HOSTILE"
