class_name Roster
extends RefCounted
## Loads the authored Servant and Master resources and provides filtering and
## server-side random rolls for the summoning lobby.

const SERVANT_DIR: String = "res://resources/servants"
const MASTER_DIR: String = "res://resources/masters"

enum RollMode {
	SPECIFIC,
	RANDOM_SERVANT,
	RANDOM_PAIR,
}

static var _servants: Array[ServantData] = []
static var _masters: Array[MasterData] = []
static var _loaded: bool = false


static func get_servants() -> Array[ServantData]:
	_ensure_loaded()
	return _servants.duplicate()


static func get_masters() -> Array[MasterData]:
	_ensure_loaded()
	return _masters.duplicate()


static func get_servants_for_class(class_id: int) -> Array[ServantData]:
	var result: Array[ServantData] = []
	for servant: ServantData in get_servants():
		if servant.servant_class == class_id:
			result.append(servant)
	return result


static func find_servant(servant_id: String) -> ServantData:
	for servant: ServantData in get_servants():
		if servant.servant_id == servant_id:
			return servant
	return null


static func find_master(master_id: String) -> MasterData:
	for master: MasterData in get_masters():
		if master.master_id == master_id:
			return master
	return null


static func random_servant(rng: RandomNumberGenerator) -> ServantData:
	var servants: Array[ServantData] = get_servants()
	if servants.is_empty():
		return null
	return servants[rng.randi_range(0, servants.size() - 1)]


static func random_master(rng: RandomNumberGenerator) -> MasterData:
	var masters: Array[MasterData] = get_masters()
	if masters.is_empty():
		return null
	return masters[rng.randi_range(0, masters.size() - 1)]


static func get_class_ids() -> Array:
	return [
		ServantData.ServantClass.SABER,
		ServantData.ServantClass.ARCHER,
		ServantData.ServantClass.LANCER,
		ServantData.ServantClass.RIDER,
		ServantData.ServantClass.CASTER,
		ServantData.ServantClass.ASSASSIN,
		ServantData.ServantClass.BERSERKER,
		ServantData.ServantClass.RULER,
		ServantData.ServantClass.AVENGER,
	]


static func class_name_for(class_id: int) -> String:
	var names: Array = ServantData.ServantClass.keys()
	if class_id >= 0 and class_id < names.size():
		return String(names[class_id]).capitalize()
	return "Servant"


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_servants = _load_servants()
	_masters = _load_masters()


static func _load_servants() -> Array[ServantData]:
	var result: Array[ServantData] = []
	for file_name: String in DirAccess.get_files_at(SERVANT_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var resource: Resource = load("%s/%s" % [SERVANT_DIR, file_name])
		var servant: ServantData = resource as ServantData
		if servant != null and not servant.servant_id.is_empty():
			result.append(servant)
	result.sort_custom(func(a: ServantData, b: ServantData) -> bool: return a.display_name < b.display_name)
	return result


static func _load_masters() -> Array[MasterData]:
	var result: Array[MasterData] = []
	for file_name: String in DirAccess.get_files_at(MASTER_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var resource: Resource = load("%s/%s" % [MASTER_DIR, file_name])
		var master: MasterData = resource as MasterData
		if master != null and not master.master_id.is_empty():
			result.append(master)
	result.sort_custom(func(a: MasterData, b: MasterData) -> bool: return a.display_name < b.display_name)
	return result
