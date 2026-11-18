class_name MasterData
extends Resource
## Static definition of a Master: personal parameters, Mana economy, leyline
## affinity, and the three Command Spells that can override a Servant.

const MAX_COMMAND_SPELLS: int = 3

enum MasterSkillStyle {
	BURST,
	HEAL_SERVANT,
	HASTE_SELF,
	REVEAL,
	DRAIN,
	SHIELD_SERVANT,
}

enum SignatureStyle {
	DECREE_WARP,
	OVERDRIVE,
	REVEAL,
	BIND,
	SURGE,
	RAMPAGE,
}

enum TrumpStyle {
	RHO_AIAS,
	JEWELED_SWORD,
	ORIGIN_BULLET,
	MERCURY_STORM,
	GLOBAL_REVEAL,
	NP_CHARGE_HP_COST,
	BLOOD_CARNIVAL,
	HEAL_SHIELD,
	DRAIN_NOVA,
}

@export var master_id: String = ""
@export var display_name: String = "Unnamed Master"
@export_multiline var description: String = ""
@export_range(100.0, 2000.0, 10.0) var vision_radius: float = 520.0

@export_group("Magecraft Skills")
@export var active_skills: PackedStringArray = PackedStringArray()
@export var skill_1_name: String = "Magecraft"
@export var skill_2_name: String = "Magecraft"
@export var skill_1_style: MasterSkillStyle = MasterSkillStyle.BURST
@export var skill_2_style: MasterSkillStyle = MasterSkillStyle.HEAL_SERVANT
@export_range(0.0, 200.0, 0.5) var skill_1_cost: float = 25.0
@export_range(0.0, 200.0, 0.5) var skill_2_cost: float = 35.0
@export_range(0.0, 100.0, 0.1) var skill_1_cooldown: float = 6.0
@export_range(0.0, 100.0, 0.1) var skill_2_cooldown: float = 10.0
@export_multiline var skill_1_desc: String = ""
@export_multiline var skill_2_desc: String = ""
@export_multiline var command_spell_desc: String = ""
@export_multiline var np_desc: String = ""
@export_multiline var passive_desc: String = ""

@export_group("Signature Command Spell")
@export var signature_command_spell: String = "Command Spell Decree"
@export_multiline var signature_command_spell_desc: String = ""
@export var signature_style: SignatureStyle = SignatureStyle.DECREE_WARP

@export_group("Master Trump Card")
@export var master_trump_card: String = "Mystic Code Ultimate"
@export_multiline var trump_card_desc: String = ""
@export var trump_style: TrumpStyle = TrumpStyle.HEAL_SHIELD
@export_range(0.0, 300.0, 1.0) var trump_card_cooldown: float = 60.0
@export_range(0.0, 500.0, 1.0) var trump_card_mana_cost: float = 0.0

@export_group("Parameters")
@export_range(1, 100, 1) var strength: int = 5
@export_range(1, 100, 1) var endurance: int = 5
@export_range(1, 100, 1) var agility: int = 5
@export_range(1, 100, 1) var mana_rank: int = 5
@export_range(1, 100, 1) var luck: int = 5
@export_range(1, 100, 1) var noble_phantasm_rank: int = 0

@export_group("Mana")
@export_range(0.0, 2000.0, 1.0) var max_mana: float = 200.0
@export_range(0.0, 100.0, 0.1) var mana_regeneration: float = 8.0
@export_range(0.0, 100.0, 0.1) var mana_upkeep_cost: float = 2.0

@export_group("Leylines")
@export_range(0.0, 5.0, 0.05) var leyline_affinity: float = 1.0
@export var leyline_linked: bool = false
@export_range(0.0, 2.0, 0.05) var leyline_regen_bonus_per_node: float = 0.35

@export_group("Command Spells")
@export_range(0, 3, 1) var command_spell_charges: int = MAX_COMMAND_SPELLS

@export_group("Contract")
@export var linked_servant: ServantData


## Spends one Command Spell. Returns false when the Master has none left.
func consume_command_spell() -> bool:
	if command_spell_charges <= 0:
		return false
	command_spell_charges -= 1
	return true


## Restores one Command Spell, capped at three.
func restore_command_spell() -> bool:
	if command_spell_charges >= MAX_COMMAND_SPELLS:
		return false
	command_spell_charges += 1
	return true


## Master Mana regen per second. Each held Leyline adds a stacking bonus on top
## of the Master's affinity, which is the economic reward for capture.
func get_effective_regeneration(leylines_held: int = 0) -> float:
	var linked: bool = leyline_linked or leylines_held > 0
	var leyline_bonus: float = leyline_affinity if linked else 0.0
	var holding_multiplier: float = 1.0 + leyline_regen_bonus_per_node * float(maxi(leylines_held, 0))
	return mana_regeneration * (1.0 + leyline_bonus) * holding_multiplier


func get_stat(stat: ServantData.Stat) -> int:
	match stat:
		ServantData.Stat.STRENGTH:
			return strength
		ServantData.Stat.ENDURANCE:
			return endurance
		ServantData.Stat.AGILITY:
			return agility
		ServantData.Stat.MANA:
			return mana_rank
		ServantData.Stat.LUCK:
			return luck
		ServantData.Stat.NOBLE_PHANTASM:
			return noble_phantasm_rank
	return 0


func is_valid() -> bool:
	return max_mana > 0.0 and command_spell_charges >= 0 and command_spell_charges <= MAX_COMMAND_SPELLS
