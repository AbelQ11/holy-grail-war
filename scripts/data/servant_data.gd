class_name ServantData
extends Resource
## Static, designer-authored definition of a summoned Servant.
##
## Runtime state (current Mana, cooldowns, position) lives on
## [ServantController]; this resource describes the class chassis, its kit
## tuning values, and the costs used by the authoritative simulation.

enum ServantClass {
	SABER,
	ARCHER,
	LANCER,
	RIDER,
	CASTER,
	ASSASSIN,
	BERSERKER,
	RULER,
	AVENGER,
}

enum Stat {
	STRENGTH,
	ENDURANCE,
	AGILITY,
	MANA,
	LUCK,
	NOBLE_PHANTASM,
}

enum AttackStyle {
	PROJECTILE,
	SLASH,
}

enum SkillStyle {
	BARRAGE,
	TRAP,
	STEALTH,
	DASH,
	BUFF,
	SCAN,
	HEAL,
	AOE,
}

enum NoblePhantasmStyle {
	BEAM,
	REALITY_MARBLE,
	DASH,
	NOVA,
	BARRAGE,
	SUPPORT,
	REFLECT,
}

const STAT_LABELS: Array = ["STR", "END", "AGI", "MANA", "LCK", "NP"]

@export var servant_id: String = ""
@export var display_name: String = "Unknown Servant"
@export var servant_class: ServantClass = ServantClass.SABER
@export_multiline var description: String = ""
@export_range(100.0, 2000.0, 10.0) var vision_radius: float = 520.0

@export_group("Parameters")
@export_range(1, 100, 1) var strength: int = 10
@export_range(1, 100, 1) var endurance: int = 10
@export_range(1, 100, 1) var agility: int = 10
@export_range(1, 100, 1) var mana_rank: int = 10
@export_range(1, 100, 1) var luck: int = 10
@export_range(1, 100, 1) var noble_phantasm_rank: int = 10

@export_group("Mana")
@export_range(0.0, 1000.0, 1.0) var max_mana: float = 100.0
@export_range(0.0, 100.0, 0.1) var mana_regeneration: float = 6.0
@export_range(0.0, 100.0, 0.1) var mana_upkeep_per_second: float = 1.5
@export_range(0.0, 500.0, 1.0) var noble_phantasm_cost: float = 60.0

@export_group("Primary Attack")
@export var attack_style: AttackStyle = AttackStyle.PROJECTILE
@export_range(1.0, 300.0, 0.5) var attack_damage: float = 18.0
@export_range(0.0, 100.0, 0.5) var attack_mana_cost: float = 8.0
@export_range(0.05, 5.0, 0.01) var attack_cooldown: float = 0.35
@export_range(20.0, 1000.0, 5.0) var attack_range: float = 620.0
@export_range(100.0, 2000.0, 10.0) var projectile_speed: float = 720.0
@export_range(20.0, 360.0, 5.0) var melee_arc_degrees: float = 110.0
@export_range(0.5, 4.0, 0.05) var critical_multiplier: float = 1.5
@export_range(0.0, 1.0, 0.01) var critical_chance: float = 0.0

@export_group("Skills")
@export_range(0.0, 200.0, 0.5) var skill_1_cost: float = 18.0
@export_range(0.0, 200.0, 0.5) var skill_2_cost: float = 28.0
@export_range(0.0, 100.0, 0.1) var skill_1_cooldown: float = 2.0
@export_range(0.0, 100.0, 0.1) var skill_2_cooldown: float = 4.0
@export var skill_1_style: SkillStyle = SkillStyle.BUFF
@export var skill_2_style: SkillStyle = SkillStyle.AOE
@export_multiline var skill_1_desc: String = ""
@export_multiline var skill_2_desc: String = ""
@export_range(20.0, 600.0, 5.0) var skill_dash_distance: float = 180.0
@export_range(20.0, 500.0, 5.0) var skill_aoe_radius: float = 170.0
@export_range(0.0, 200.0, 1.0) var skill_heal_amount: float = 45.0
@export_range(50.0, 2000.0, 10.0) var skill_scan_radius: float = 650.0
@export_range(0.5, 20.0, 0.5) var skill_buff_duration: float = 5.0
@export_range(1.0, 3.0, 0.05) var skill_buff_damage_multiplier: float = 1.3
@export_range(1.0, 3.0, 0.05) var skill_buff_speed_multiplier: float = 1.25

@export_group("Archer - Blade Barrage")
@export_range(0, 20, 1) var barrage_projectiles: int = 0
@export_range(0.02, 1.0, 0.01) var barrage_interval: float = 0.08
@export_range(0.0, 45.0, 1.0) var barrage_spread_degrees: float = 8.0

@export_group("Caster - Territory Creation")
@export_range(0.0, 100.0, 0.5) var spell_damage_multiplier: float = 1.0
@export_range(0.0, 100.0, 0.5) var territory_mana_bonus: float = 0.0
@export_range(0.0, 5.0, 0.05) var territory_spell_bonus: float = 0.0
@export_range(0.0, 500.0, 5.0) var trap_cast_range: float = 0.0
@export_range(10.0, 200.0, 1.0) var trap_radius: float = 55.0
@export_range(0.0, 100.0, 0.5) var trap_damage: float = 0.0
@export_range(1.0, 60.0, 0.5) var trap_duration: float = 10.0
@export_range(0.2, 5.0, 0.1) var trap_pulse_interval: float = 1.0

@export_group("Assassin - Presence Concealment")
@export_range(0.0, 30.0, 0.5) var stealth_duration: float = 0.0

@export_group("Noble Phantasm")
@export var noble_phantasm_name: String = ""
@export var noble_phantasm_style: NoblePhantasmStyle = NoblePhantasmStyle.BEAM
@export_multiline var noble_phantasm_desc: String = ""
@export_multiline var np_desc: String = ""
@export_multiline var passive_desc: String = ""
@export var noble_phantasm_color: Color = Color(1.0, 0.85, 0.4)
@export_range(0.0, 500.0, 1.0) var noble_phantasm_damage: float = 0.0
@export_range(0.0, 2000.0, 10.0) var noble_phantasm_range: float = 0.0
@export_range(0.0, 30.0, 0.5) var noble_phantasm_duration: float = 4.0
@export_range(0.0, 100.0, 0.5) var reality_marble_drain_per_second: float = 14.0
@export_range(0.0, 1.0, 0.01) var reality_marble_haste: float = 0.0
@export var reality_marble_auto_barrage: bool = false
@export_range(0.2, 5.0, 0.1) var reality_marble_barrage_interval: float = 0.8

@export_group("Signature Mechanics")
@export var strips_buffs_on_np: bool = false
@export_range(0.0, 30.0, 0.5) var anti_heal_duration: float = 0.0
@export var projectile_appropriation: bool = false
@export var identity_mask: bool = false

@export_group("Class Skills")
@export var class_skills: PackedStringArray = PackedStringArray()
@export var active_skills: PackedStringArray = PackedStringArray()


func get_stat(stat: Stat) -> int:
	match stat:
		Stat.STRENGTH:
			return strength
		Stat.ENDURANCE:
			return endurance
		Stat.AGILITY:
			return agility
		Stat.MANA:
			return mana_rank
		Stat.LUCK:
			return luck
		Stat.NOBLE_PHANTASM:
			return noble_phantasm_rank
	return 0


## Mana drained per second from the Master contract. Reality Marbles tax the
## link heavily until they collapse.
func get_effective_upkeep(reality_marble_active: bool = false) -> float:
	var multiplier: float = 1.75 if reality_marble_active else 1.0
	return mana_upkeep_per_second * multiplier


func get_class_name_text() -> String:
	var names: Array = ServantClass.keys()
	return String(names[servant_class]).capitalize()


func is_valid() -> bool:
	return max_mana > 0.0 and strength > 0 and endurance > 0 and agility > 0
