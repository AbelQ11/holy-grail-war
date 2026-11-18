extends SceneTree
## One-off roster generator. Writes all named Servant and Master resources.
## Run: godot --headless --path . --script res://tools/generate_roster.gd

const SERVANT_DIR: String = "res://resources/servants"
const MASTER_DIR: String = "res://resources/masters"


func _init() -> void:
	var servants: Array = _servant_table()
	for entry: Dictionary in servants:
		_save_servant(entry)
	var masters: Array = _master_table()
	for entry: Dictionary in masters:
		_save_master(entry)
	print("Generated %d Servants and %d Masters." % [servants.size(), masters.size()])
	quit()


func _servant_table() -> Array:
	return [
		# Fate/stay night
		{"id": "artoria_pendragon", "name": "Artoria Pendragon", "class": ServantData.ServantClass.SABER,
		 "stats": [45, 42, 38, 35, 32, 60], "mana": [130.0, 7.0], "upkeep": 3.0, "attack": 32.0,
		 "np": "Excalibur", "np_style": ServantData.NoblePhantasmStyle.BEAM, "np_damage": 120.0,
		 "np_range": 950.0, "np_color": Color(1.0, 0.86, 0.35),
		 "skills": ["Mana Burst", "Instinct", "Excalibur"],
		 "desc": "King of Knights. Balanced high STR/END, Mana Burst, and the anti-fortress Excalibur."},
		{"id": "emiya", "name": "EMIYA", "class": ServantData.ServantClass.ARCHER,
		 "stats": [25, 28, 52, 30, 30, 48], "mana": [110.0, 8.0], "upkeep": 1.8, "attack": 17.0,
		 "np": "Unlimited Blade Works", "np_style": ServantData.NoblePhantasmStyle.REALITY_MARBLE,
		 "np_damage": 0.0, "np_range": 0.0, "np_color": Color(0.4, 0.85, 1.0), "np_duration": 12.0,
		 "rm_haste": 0.4, "rm_drain": 8.0, "skills": ["Blade Barrage", "Clairvoyance", "Unlimited Blade Works"],
		 "desc": "Nameless Guardian. Rapid blade barrage and a Reality Marble that accelerates projection fire."},
		{"id": "gilgamesh", "name": "Gilgamesh", "class": ServantData.ServantClass.ARCHER,
		 "stats": [35, 30, 45, 40, 25, 70], "mana": [180.0, 9.0], "upkeep": 4.5, "attack": 20.0,
		 "np": "Enuma Elish", "np_style": ServantData.NoblePhantasmStyle.BEAM, "np_damage": 145.0,
		 "np_range": 1100.0, "np_color": Color(1.0, 0.75, 0.25), "skills": ["Gate of Babylon", "Charisma", "Enuma Elish"],
		 "desc": "King of Heroes. A Mana-hungry powerhouse with overwhelming beam Noble Phantasm."},
		{"id": "cu_chulainn", "name": "Cú Chulainn", "class": ServantData.ServantClass.LANCER,
		 "stats": [32, 30, 45, 25, 35, 50], "mana": [110.0, 8.0], "upkeep": 1.8, "attack": 24.0,
		 "np": "Gae Bolg", "np_style": ServantData.NoblePhantasmStyle.DASH, "np_damage": 100.0,
		 "np_range": 360.0, "np_color": Color(0.9, 0.2, 0.25), "skills": ["Disengage", "Battle Continuation", "Gae Bolg"],
		 "desc": "Hound of Ulster. High AGI lancer with a causal piercing dash."},
		{"id": "medusa", "name": "Medusa", "class": ServantData.ServantClass.RIDER,
		 "stats": [30, 28, 42, 30, 30, 45], "mana": [120.0, 8.0], "upkeep": 2.0, "attack": 21.0,
		 "np": "Bellerophon", "np_style": ServantData.NoblePhantasmStyle.DASH, "np_damage": 95.0,
		 "np_range": 380.0, "np_color": Color(0.7, 0.45, 1.0), "skills": ["Blood Fort Andromeda", "Mystic Eyes", "Bellerophon"],
		 "desc": "Gorgon Rider. Mobile charger with a Pegasus-driven dash."},
		{"id": "medea", "name": "Medea", "class": ServantData.ServantClass.CASTER,
		 "stats": [12, 18, 22, 60, 25, 40], "mana": [210.0, 12.0], "upkeep": 3.0, "attack": 15.0,
		 "np": "Rule Breaker", "np_style": ServantData.NoblePhantasmStyle.NOVA, "np_damage": 85.0,
		 "np_range": 300.0, "np_color": Color(0.7, 0.4, 1.0), "skills": ["Magic Circle Trap", "Argos", "Rule Breaker"],
		 "desc": "Witch of Colchis. Territory Creation, persistent traps, and high Mana reserves."},
		{"id": "sasaki_kojiro", "name": "Sasaki Kojirou", "class": ServantData.ServantClass.ASSASSIN,
		 "stats": [28, 20, 50, 15, 40, 35], "mana": [90.0, 7.0], "upkeep": 1.2, "attack": 21.0,
		 "np": "Tsubame Gaeshi", "np_style": ServantData.NoblePhantasmStyle.NOVA, "np_damage": 100.0,
		 "np_range": 220.0, "np_color": Color(0.75, 0.85, 0.95), "stealth": 3.0,
		 "skills": ["Presence Concealment", "Tsubame Gaeshi"],
		 "desc": "Nameless swordsman. Short-range stealth assassin with a multi-slash finisher."},
		{"id": "heracles", "name": "Heracles", "class": ServantData.ServantClass.BERSERKER,
		 "stats": [55, 50, 30, 20, 15, 55], "mana": [160.0, 6.0], "upkeep": 5.0, "attack": 34.0,
		 "np": "Nine Lives", "np_style": ServantData.NoblePhantasmStyle.NOVA, "np_damage": 125.0,
		 "np_range": 260.0, "np_color": Color(0.9, 0.25, 0.2), "skills": ["Battle Continuation", "Nine Lives"],
		 "desc": "Greatest hero of Greece. Extreme upkeep, raw damage, and an area-clearing Nine Lives."},
		{"id": "angra_mainyu", "name": "Angra Mainyu", "class": ServantData.ServantClass.AVENGER,
		 "stats": [20, 25, 35, 25, 10, 40], "mana": [100.0, 7.0], "upkeep": 1.5, "attack": 18.0,
		 "np": "Verg Avesta", "np_style": ServantData.NoblePhantasmStyle.REFLECT, "np_damage": 30.0,
		 "np_range": 300.0, "np_duration": 5.0, "np_color": Color(0.45, 0.1, 0.15),
		 "skills": ["Cursed Arm", "Verg Avesta"], "desc": "All the World's Evils. Reflects damage and punishes Rulers."},

		# Fate/Apocrypha
		{"id": "mordred", "name": "Mordred", "class": ServantData.ServantClass.SABER,
		 "stats": [44, 40, 40, 30, 28, 58], "mana": [130.0, 7.0], "upkeep": 3.0, "attack": 31.0,
		 "np": "Clarent Blood Arthur", "np_style": ServantData.NoblePhantasmStyle.BEAM, "np_damage": 115.0,
		 "np_range": 900.0, "np_color": Color(0.95, 0.2, 0.3), "skills": ["Mana Burst", "Instinct", "Clarent Blood Arthur"],
		 "desc": "Knight of Treachery. Aggressive Saber with a red beam Noble Phantasm."},
		{"id": "siegfried", "name": "Siegfried", "class": ServantData.ServantClass.SABER,
		 "stats": [42, 48, 32, 25, 25, 55], "mana": [140.0, 6.0], "upkeep": 3.2, "attack": 29.0,
		 "np": "Balmung", "np_style": ServantData.NoblePhantasmStyle.BEAM, "np_damage": 105.0,
		 "np_range": 800.0, "np_color": Color(0.35, 0.65, 1.0), "skills": ["Golden Rule", "Dragon Slayer", "Balmung"],
		 "desc": "Dragon-blooded knight. High END and a broad dragon-slaying beam."},
		{"id": "atalanta", "name": "Atalanta", "class": ServantData.ServantClass.ARCHER,
		 "stats": [24, 26, 55, 25, 35, 45], "mana": [110.0, 9.0], "upkeep": 1.6, "attack": 15.0,
		 "np": "Phoebus Catastrophe", "np_style": ServantData.NoblePhantasmStyle.BARRAGE, "np_damage": 45.0,
		 "np_range": 900.0, "np_color": Color(0.45, 0.9, 0.55), "barrage": 10,
		 "skills": ["Blade Barrage", "Clairvoyance", "Phoebus Catastrophe"],
		 "desc": "Huntress of Arcadia. Fastest archer, raining a wide arrow barrage."},
		{"id": "chiron", "name": "Chiron", "class": ServantData.ServantClass.ARCHER,
		 "stats": [30, 30, 46, 35, 30, 50], "mana": [130.0, 8.0], "upkeep": 2.2, "attack": 18.0,
		 "np": "Antares Snipe", "np_style": ServantData.NoblePhantasmStyle.BEAM, "np_damage": 110.0,
		 "np_range": 1200.0, "np_color": Color(0.4, 0.85, 0.85), "skills": ["Blade Barrage", "Clairvoyance", "Antares Snipe"],
		 "desc": "Centaur sage. Longest-range beam sniper with excellent vision."},
		{"id": "karna", "name": "Karna", "class": ServantData.ServantClass.LANCER,
		 "stats": [48, 42, 46, 40, 20, 65], "mana": [190.0, 9.0], "upkeep": 4.8, "attack": 29.0,
		 "np": "Vasavi Shakti", "np_style": ServantData.NoblePhantasmStyle.BEAM, "np_damage": 145.0,
		 "np_range": 1000.0, "np_color": Color(1.0, 0.55, 0.2), "skills": ["Mana Burst", "Battle Continuation", "Vasavi Shakti"],
		 "desc": "Hero of Charity. Enormous upkeep and a god-slaying anti-army beam."},
		{"id": "vlad_iii", "name": "Vlad III", "class": ServantData.ServantClass.LANCER,
		 "stats": [38, 44, 30, 30, 20, 50], "mana": [140.0, 7.0], "upkeep": 3.2, "attack": 25.0,
		 "np": "Kazikli Bey", "np_style": ServantData.NoblePhantasmStyle.NOVA, "np_damage": 110.0,
		 "np_range": 300.0, "np_color": Color(0.75, 0.15, 0.2), "skills": ["Protection of the Faith", "Battle Continuation", "Kazikli Bey"],
		 "desc": "Impaler of Wallachia. Durable Lancer with a field of blood stakes."},
		{"id": "achilles", "name": "Achilles", "class": ServantData.ServantClass.RIDER,
		 "stats": [42, 40, 54, 30, 25, 55], "mana": [130.0, 8.0], "upkeep": 3.0, "attack": 27.0,
		 "np": "Troias Tragoidia", "np_style": ServantData.NoblePhantasmStyle.DASH, "np_damage": 110.0,
		 "np_range": 420.0, "np_color": Color(0.5, 0.85, 0.35), "skills": ["Andreias Amarantos", "Dromeus Cometes", "Troias Tragoidia"],
		 "desc": "Swift-footed hero. Extremely mobile Rider with a chariot dash."},
		{"id": "astolfo", "name": "Astolfo", "class": ServantData.ServantClass.RIDER,
		 "stats": [26, 28, 52, 22, 60, 40], "mana": [110.0, 8.0], "upkeep": 1.5, "attack": 18.0,
		 "np": "Hippogriff", "np_style": ServantData.NoblePhantasmStyle.DASH, "np_damage": 70.0,
		 "np_range": 360.0, "np_color": Color(0.95, 0.55, 0.8), "skills": ["Evaporation of Sanity", "Riding", "Hippogriff"],
		 "desc": "Paladin of Charlemagne. High LCK, cheap upkeep, and a hit-and-run Hippogriff."},
		{"id": "william_shakespeare", "name": "William Shakespeare", "class": ServantData.ServantClass.CASTER,
		 "stats": [8, 12, 20, 50, 30, 30], "mana": [170.0, 11.0], "upkeep": 1.0, "attack": 10.0,
		 "np": "First Folio", "np_style": ServantData.NoblePhantasmStyle.SUPPORT, "np_damage": 70.0,
		 "np_range": 260.0, "np_duration": 4.0, "np_color": Color(1.0, 0.9, 0.6),
		 "skills": ["Enchant", "Clairvoyance", "First Folio"],
		 "desc": "Playwright Caster. Cheap upkeep, traps, and a supportive First Folio."},
		{"id": "avicebron", "name": "Avicebron", "class": ServantData.ServantClass.CASTER,
		 "stats": [14, 20, 18, 55, 20, 42], "mana": [200.0, 11.0], "upkeep": 2.8, "attack": 13.0,
		 "np": "Golem Keter Malkuth", "np_style": ServantData.NoblePhantasmStyle.SUPPORT, "np_damage": 50.0,
		 "np_range": 280.0, "np_duration": 6.0, "np_color": Color(0.7, 0.55, 0.35),
		 "skills": ["Golem Transmutation", "Clairvoyance", "Golem Keter Malkuth"],
		 "desc": "Golem sculptor. Heavy Caster scaling with a durable territorial support NP."},
		{"id": "semiramis", "name": "Semiramis", "class": ServantData.ServantClass.ASSASSIN,
		 "stats": [22, 25, 40, 50, 25, 55], "mana": [180.0, 10.0], "upkeep": 3.8, "attack": 17.0,
		 "np": "Hanging Gardens of Babylon", "np_style": ServantData.NoblePhantasmStyle.NOVA, "np_damage": 115.0,
		 "np_range": 340.0, "np_color": Color(0.6, 0.35, 0.8), "stealth": 4.0,
		 "skills": ["Presence Concealment", "Familiar Scouting", "Hanging Gardens"],
		 "desc": "Assassin of Red. High-Mana assassin who turns the battlefield into her garden."},
		{"id": "jack_the_ripper", "name": "Jack the Ripper", "class": ServantData.ServantClass.ASSASSIN,
		 "stats": [26, 22, 58, 18, 45, 45], "mana": [95.0, 7.0], "upkeep": 1.3, "attack": 23.0,
		 "np": "Maria the Ripper", "np_style": ServantData.NoblePhantasmStyle.DASH, "np_damage": 105.0,
		 "np_range": 330.0, "np_color": Color(0.55, 0.15, 0.2), "stealth": 5.0,
		 "skills": ["Presence Concealment", "Information Erasure", "Maria the Ripper"],
		 "desc": "Black Assassin. Fast stealth killer with a high-crit dash execution."},
		{"id": "spartacus", "name": "Spartacus", "class": ServantData.ServantClass.BERSERKER,
		 "stats": [43, 45, 28, 15, 10, 45], "mana": [130.0, 5.0], "upkeep": 3.8, "attack": 29.0,
		 "np": "Crying Warmonger", "np_style": ServantData.NoblePhantasmStyle.NOVA, "np_damage": 125.0,
		 "np_range": 280.0, "np_color": Color(0.9, 0.35, 0.25), "skills": ["Mad Enhancement", "Crying Warmonger"],
		 "desc": "Rebel gladiator. Grows dangerous as he is wounded and detonates in a wide roar."},
		{"id": "frankenstein", "name": "Frankenstein", "class": ServantData.ServantClass.BERSERKER,
		 "stats": [38, 40, 32, 25, 15, 50], "mana": [140.0, 6.0], "upkeep": 3.5, "attack": 27.0,
		 "np": "Blasted Tree", "np_style": ServantData.NoblePhantasmStyle.BEAM, "np_damage": 130.0,
		 "np_range": 700.0, "np_color": Color(0.4, 0.65, 1.0), "skills": ["Mad Enhancement", "Galvanism", "Blasted Tree"],
		 "desc": "Synthetic Berserker. A lightning beam fueled by her own instability."},
		{"id": "jeanne_darc", "name": "Jeanne d'Arc", "class": ServantData.ServantClass.RULER,
		 "stats": [25, 45, 30, 55, 40, 60], "mana": [220.0, 12.0], "upkeep": 3.5, "attack": 14.0,
		 "np": "Luminosite Eternelle", "np_style": ServantData.NoblePhantasmStyle.SUPPORT, "np_damage": 80.0,
		 "np_range": 320.0, "np_duration": 5.0, "np_color": Color(1.0, 0.92, 0.55),
		 "skills": ["Revelation", "True Name Discernment", "Luminosite Eternelle"],
		 "desc": "Holy Maiden. Neutral arbiter with exceptional defense and a team saving NP."},
		{"id": "amakusa_shirou", "name": "Amakusa Shirou", "class": ServantData.ServantClass.RULER,
		 "stats": [30, 35, 38, 45, 30, 52], "mana": [180.0, 10.0], "upkeep": 3.0, "attack": 18.0,
		 "np": "Twin Arm Crise", "np_style": ServantData.NoblePhantasmStyle.NOVA, "np_damage": 95.0,
		 "np_range": 300.0, "np_color": Color(0.85, 0.85, 1.0),
		 "skills": ["Revelation", "True Name Discernment", "Twin Arm Crise"],
		 "desc": "Ruler of the Great Holy Grail War. Reveals enemies and purges formations."},

		# Fate/Zero
		{"id": "diarmuid_ua_duibhne", "name": "Diarmuid Ua Duibhne", "class": ServantData.ServantClass.LANCER,
		 "stats": [32, 30, 46, 25, 30, 50], "mana": [110.0, 8.0], "upkeep": 1.8, "attack": 23.0,
		 "np": "Gae Buidhe & Gae Dearg", "np_style": ServantData.NoblePhantasmStyle.DASH, "np_damage": 98.0,
		 "np_range": 380.0, "np_color": Color(0.95, 0.75, 0.25),
		 "strips_buffs": true, "anti_heal": 6.0,
		 "skills": ["Gae Dearg", "Gae Buidhe", "Two Spears of the Twin Decrees"],
		 "desc": "Lancer of the Fourth War. Strips enchantments and inflicts anti-heal with his twin spears."},
		{"id": "iskandar", "name": "Iskandar", "class": ServantData.ServantClass.RIDER,
		 "stats": [44, 42, 38, 30, 28, 62], "mana": [160.0, 8.0], "upkeep": 3.8, "attack": 29.0,
		 "np": "Ionioi Hetairoi", "np_style": ServantData.NoblePhantasmStyle.REALITY_MARBLE, "np_damage": 0.0,
		 "np_range": 0.0, "np_color": Color(0.95, 0.62, 0.25), "np_duration": 12.0,
		 "rm_haste": 0.7, "rm_drain": 10.0, "rm_barrage": true, "rm_interval": 0.75,
		 "skills": ["Charisma", "Military Tactics", "Ionioi Hetairoi"],
		 "desc": "King of Conquerors. A chariot charge leads into the phalanx Reality Marble of his army."},
		{"id": "gilles_de_rais", "name": "Gilles de Rais", "class": ServantData.ServantClass.CASTER,
		 "stats": [10, 16, 18, 55, 20, 45], "mana": [180.0, 11.0], "upkeep": 2.0, "attack": 12.0,
		 "np": "Prelati's Spellbook", "np_style": ServantData.NoblePhantasmStyle.NOVA, "np_damage": 90.0,
		 "np_range": 300.0, "np_color": Color(0.35, 0.5, 0.55), "barrage": 8,
		 "skill_1_style": ServantData.SkillStyle.BARRAGE, "skill_1_cost": 0.0, "skill_1_cooldown": 3.0,
		 "skill_2_style": ServantData.SkillStyle.SCAN, "skill_2_cost": 10.0,
		 "skills": ["Sea Demon Summons", "Prelati's Spellbook", "Cthulhu Ritual"],
		 "desc": "Caster of the Fourth War. Zero-Mana Sea Demon waves and a grotesque spellbook ritual."},
		{"id": "hassan_hundred_personas", "name": "Hassan of the Hundred Personas", "class": ServantData.ServantClass.ASSASSIN,
		 "stats": [25, 22, 52, 18, 40, 42], "mana": [95.0, 8.0], "upkeep": 1.3, "attack": 21.0,
		 "np": "Hundred Personas", "np_style": ServantData.NoblePhantasmStyle.NOVA, "np_damage": 90.0,
		 "np_range": 230.0, "np_color": Color(0.55, 0.45, 0.65), "stealth": 4.0,
		 "skill_2_style": ServantData.SkillStyle.SCAN, "skill_2_cost": 12.0, "skill_2_cooldown": 3.0,
		 "skills": ["Presence Concealment", "Hundred Personas", "Delusional Heartbeat"],
		 "desc": "Assassin of the Fourth War. Splits into many bodies to scout, decoy, and strike."},
		{"id": "lancelot", "name": "Lancelot", "class": ServantData.ServantClass.BERSERKER,
		 "stats": [46, 42, 38, 20, 20, 56], "mana": [140.0, 6.0], "upkeep": 4.0, "attack": 31.0,
		 "np": "Arondight Overload", "np_style": ServantData.NoblePhantasmStyle.NOVA, "np_damage": 112.0,
		 "np_range": 250.0, "np_color": Color(0.35, 0.15, 0.45),
		 "projectile_appropriation": true, "identity_mask": true,
		 "skills": ["Knight of Owner", "For Someone's Glory", "Arondight Overload"],
		 "desc": "Berserker of the Fourth War. Appropriates projectiles and masks his identity until revealed."},
	]


func _master_table() -> Array:
	return [
		{"id": "rin_tohsaka", "name": "Rin Tohsaka", "mana": [180.0, 9.0], "vision": 560.0,
		 "stats": [8, 8, 10, 25, 30, 0], "affinity": 1.25,
		 "skills": ["Jewel Burst", MasterData.MasterSkillStyle.BURST, 35.0, 7.0,
			"Mana Transfer", MasterData.MasterSkillStyle.HEAL_SERVANT, 40.0, 12.0],
		 "desc": "Tohsaka heir. Jewel magecraft burst and a direct Mana transfer to her Servant."},
		{"id": "shirou_emiya", "name": "Shirou Emiya", "mana": [120.0, 6.0], "vision": 460.0,
		 "stats": [8, 9, 7, 12, 40, 0], "affinity": 1.0,
		 "skills": ["Trace Reinforcement", MasterData.MasterSkillStyle.SHIELD_SERVANT, 30.0, 10.0,
			"Projection", MasterData.MasterSkillStyle.BURST, 25.0, 6.0],
		 "desc": "Novice Master. Low Mana bottleneck; reinforcement shield and projected blades."},
		{"id": "illyasviel_von_einzbern", "name": "Illyasviel von Einzbern", "mana": [260.0, 12.0], "vision": 620.0,
		 "stats": [5, 6, 8, 45, 20, 0], "affinity": 1.5,
		 "skills": ["Wishcraft", MasterData.MasterSkillStyle.HEAL_SERVANT, 50.0, 12.0,
			"Dress of Heaven", MasterData.MasterSkillStyle.SHIELD_SERVANT, 60.0, 15.0],
		 "desc": "Holy Grail vessel. Enormous Mana reserves, healing wishcraft, and a protective dress."},
		{"id": "kirei_kotomine", "name": "Kirei Kotomine", "mana": [160.0, 8.0], "vision": 520.0,
		 "stats": [12, 14, 9, 18, 25, 0], "affinity": 1.1,
		 "skills": ["Spiritual Surgery", MasterData.MasterSkillStyle.HEAL_SERVANT, 35.0, 10.0,
			"Baptism Rite", MasterData.MasterSkillStyle.BURST, 35.0, 8.0],
		 "desc": "Executor. Restores his Servant with spiritual surgery and purges with baptism rites."},
		{"id": "kiritsugu_emiya", "name": "Kiritsugu Emiya", "mana": [140.0, 7.0], "vision": 680.0,
		 "stats": [10, 11, 14, 15, 20, 0], "affinity": 1.0,
		 "skills": ["Time Alter", MasterData.MasterSkillStyle.HASTE_SELF, 30.0, 9.0,
			"Origin Bullet", MasterData.MasterSkillStyle.BURST, 45.0, 12.0],
		 "desc": "Mage Killer. Time Alter mobility and a devastating Origin Bullet burst."},
		{"id": "kairi_sisigou", "name": "Kairi Sisigou", "mana": [170.0, 8.0], "vision": 560.0,
		 "stats": [14, 13, 10, 16, 30, 0], "affinity": 1.15,
		 "skills": ["Magecraft Bullet", MasterData.MasterSkillStyle.BURST, 30.0, 6.0,
			"Necromancy", MasterData.MasterSkillStyle.HEAL_SERVANT, 40.0, 12.0],
		 "desc": "Necromancer freelancer. Steady offense and Servant restoration."},
		{"id": "darnic_yggdmillennia", "name": "Darnic Yggdmillennia", "mana": [220.0, 10.0], "vision": 560.0,
		 "stats": [10, 12, 7, 30, 20, 0], "affinity": 1.4,
		 "skills": ["Yggdmillennia Command", MasterData.MasterSkillStyle.SHIELD_SERVANT, 45.0, 12.0,
			"Spiritual Evocation", MasterData.MasterSkillStyle.DRAIN, 40.0, 14.0],
		 "desc": "Black Faction patriarch. Shields his Servant and drains enemy Mana."},
		{"id": "fiore_yggdmillennia", "name": "Fiore Yggdmillennia", "mana": [200.0, 11.0], "vision": 620.0,
		 "stats": [6, 8, 9, 28, 25, 0], "affinity": 1.3,
		 "skills": ["Homunculus Recon", MasterData.MasterSkillStyle.REVEAL, 30.0, 10.0,
			"Golem Transmutation", MasterData.MasterSkillStyle.SHIELD_SERVANT, 45.0, 12.0],
		 "desc": "Golem Master. Scouting recon and a golem shield for her Servant."},

		# Fate/Zero
		{"id": "tokiomi_tohsaka", "name": "Tokiomi Tohsaka", "mana": [210.0, 9.0], "vision": 560.0,
		 "stats": [9, 9, 10, 28, 25, 0], "affinity": 1.3,
		 "skills": ["Jewel Magecraft", MasterData.MasterSkillStyle.BURST, 30.0, 6.0,
			"Tohsaka Command", MasterData.MasterSkillStyle.SHIELD_SERVANT, 40.0, 11.0],
		 "desc": "Tohsaka patriarch. Jewel magecraft, a jeweled blade, and formal command authority."},
		{"id": "kayneth_el_melloi", "name": "Kayneth El-Melloi Archibald", "mana": [240.0, 10.0], "vision": 580.0,
		 "stats": [10, 11, 9, 32, 20, 0], "affinity": 1.35,
		 "skills": ["Volumen Hydrargyrum", MasterData.MasterSkillStyle.SHIELD_SERVANT, 40.0, 8.0,
			"Mercury Lash", MasterData.MasterSkillStyle.BURST, 35.0, 7.0],
		 "desc": "Lord El-Melloi. Liquid mercury auto-parry and a storm of mystic-code construct blades."},
		{"id": "waver_velvet", "name": "Waver Velvet", "mana": [140.0, 7.0], "vision": 660.0,
		 "stats": [5, 7, 8, 18, 30, 0], "affinity": 1.0,
		 "skills": ["Grand Strategy", MasterData.MasterSkillStyle.REVEAL, 25.0, 9.0,
			"Tactical Support", MasterData.MasterSkillStyle.HEAL_SERVANT, 35.0, 12.0],
		 "desc": "Future Lord El-Melloi II. Global scouting and tactical support for his Servant."},
		{"id": "ryuunosuke_uryuu", "name": "Ryuunosuke Uryuu", "mana": [100.0, 6.0], "vision": 500.0,
		 "stats": [7, 8, 10, 10, 45, 0], "affinity": 0.9,
		 "skills": ["Blood Offering", MasterData.MasterSkillStyle.DRAIN, 20.0, 8.0,
			"Carnival Frenzy", MasterData.MasterSkillStyle.BURST, 25.0, 6.0],
		 "desc": "Serial killer Master. Sacrifices blood and Mana for chaotic bursts."},
		{"id": "kariya_matou", "name": "Kariya Matou", "mana": [130.0, 8.0], "vision": 540.0,
		 "stats": [8, 7, 12, 14, 25, 0], "affinity": 1.0,
		 "skills": ["Crest Worm Surge", MasterData.MasterSkillStyle.HASTE_SELF, 20.0, 8.0,
			"Berserker Command", MasterData.MasterSkillStyle.SHIELD_SERVANT, 35.0, 12.0],
		 "desc": "Matou Master sustained by Crest Worms. Converts HP into power for Berserker."},
		{"id": "gordes_musik", "name": "Gordes Musik Yggdmillennia", "mana": [210.0, 9.0], "vision": 560.0,
		 "stats": [9, 12, 7, 24, 20, 0], "affinity": 1.2,
		 "skills": ["Golem Fortification", MasterData.MasterSkillStyle.SHIELD_SERVANT, 40.0, 10.0,
			"Alchemy Burst", MasterData.MasterSkillStyle.BURST, 30.0, 8.0],
		 "desc": "Yggdmillennia alchemist. Golem fortifications and volatile alchemical bursts."},
		{"id": "caules_forvedge", "name": "Caules Forvedge Yggdmillennia", "mana": [180.0, 9.0], "vision": 600.0,
		 "stats": [6, 8, 9, 22, 28, 0], "affinity": 1.15,
		 "skills": ["Familiar Network", MasterData.MasterSkillStyle.REVEAL, 25.0, 9.0,
			"Familiar Restoration", MasterData.MasterSkillStyle.HEAL_SERVANT, 35.0, 11.0],
		 "desc": "Forvedge heir. Familiar scouting and restoration support."},
	]


func _save_servant(entry: Dictionary) -> void:
	var class_id: int = int(entry["class"])
	var defaults: Dictionary = _servant_defaults(class_id)
	var stats: Array = entry["stats"]
	var mana: Array = entry["mana"]
	var s: ServantData = ServantData.new()
	s.servant_id = String(entry["id"])
	s.display_name = String(entry["name"])
	s.servant_class = class_id
	s.description = String(entry.get("desc", ""))
	s.strength = int(stats[0])
	s.endurance = int(stats[1])
	s.agility = int(stats[2])
	s.mana_rank = int(stats[3])
	s.luck = int(stats[4])
	s.noble_phantasm_rank = int(stats[5])
	s.max_mana = float(mana[0])
	s.mana_regeneration = float(mana[1])
	s.mana_upkeep_per_second = float(entry["upkeep"])
	s.noble_phantasm_cost = float(entry.get("np_cost", clampf(55.0 + float(stats[5]) * 0.55, 55.0, 100.0)))
	s.vision_radius = float(entry.get("vision", defaults["vision"]))
	s.attack_style = defaults["attack_style"]
	s.attack_damage = float(entry["attack"])
	s.attack_mana_cost = float(defaults["attack_cost"])
	s.attack_cooldown = float(entry.get("attack_cd", defaults["attack_cd"]))
	s.attack_range = float(entry.get("attack_range", defaults["range"]))
	s.projectile_speed = float(defaults["projectile_speed"])
	s.melee_arc_degrees = float(defaults["arc"])
	s.critical_chance = float(entry.get("crit", defaults["crit"]))
	s.critical_multiplier = float(entry.get("crit_mult", defaults["crit_mult"]))
	s.spell_damage_multiplier = float(entry.get("spell_mult", defaults["spell_mult"]))
	s.skill_1_style = entry.get("skill_1_style", defaults["skill_1_style"])
	s.skill_2_style = entry.get("skill_2_style", defaults["skill_2_style"])
	s.skill_1_cost = float(entry.get("skill_1_cost", defaults["skill_1_cost"]))
	s.skill_2_cost = float(entry.get("skill_2_cost", defaults["skill_2_cost"]))
	s.skill_1_cooldown = float(defaults["skill_1_cooldown"])
	s.skill_2_cooldown = float(defaults["skill_2_cooldown"])
	s.barrage_projectiles = int(entry.get("barrage", defaults["barrage"]))
	s.barrage_interval = float(defaults["barrage_interval"])
	s.barrage_spread_degrees = float(defaults["barrage_spread"])
	s.stealth_duration = float(entry.get("stealth", defaults["stealth"]))
	s.skill_dash_distance = float(defaults["dash"])
	s.skill_aoe_radius = float(defaults["aoe"])
	s.skill_heal_amount = float(defaults["heal"])
	s.skill_scan_radius = float(defaults["scan"])
	s.skill_buff_duration = float(defaults["buff_duration"])
	s.skill_buff_damage_multiplier = float(defaults["buff_damage"])
	s.skill_buff_speed_multiplier = float(defaults["buff_speed"])
	s.territory_mana_bonus = float(defaults["territory_mana"])
	s.territory_spell_bonus = float(defaults["territory_spell"])
	s.trap_cast_range = float(defaults["trap_cast"])
	s.trap_radius = float(defaults["trap_radius"])
	s.trap_damage = float(defaults["trap_damage"])
	s.trap_duration = float(defaults["trap_duration"])
	s.trap_pulse_interval = float(defaults["trap_pulse"])
	s.noble_phantasm_name = String(entry["np"])
	s.noble_phantasm_style = entry["np_style"]
	s.noble_phantasm_damage = float(entry.get("np_damage", 0.0))
	s.noble_phantasm_range = float(entry.get("np_range", 0.0))
	s.noble_phantasm_duration = float(entry.get("np_duration", 4.0))
	s.noble_phantasm_color = entry.get("np_color", Color.WHITE)
	s.reality_marble_haste = float(entry.get("rm_haste", 0.0))
	s.reality_marble_drain_per_second = float(entry.get("rm_drain", 14.0))
	s.reality_marble_auto_barrage = bool(entry.get("rm_barrage", false))
	s.reality_marble_barrage_interval = float(entry.get("rm_interval", 0.8))
	s.strips_buffs_on_np = bool(entry.get("strips_buffs", false))
	s.anti_heal_duration = float(entry.get("anti_heal", 0.0))
	s.projectile_appropriation = bool(entry.get("projectile_appropriation", false))
	s.identity_mask = bool(entry.get("identity_mask", false))
	s.class_skills = _class_skills(class_id)
	var active: PackedStringArray = PackedStringArray()
	for skill_name: String in entry["skills"]:
		active.append(skill_name)
	s.active_skills = active
	s.skill_1_desc = _servant_skill_desc(String(active[0]) if active.size() > 0 else "Skill 1", s.skill_1_style, s.skill_1_cost, s.skill_1_cooldown)
	s.skill_2_desc = _servant_skill_desc(String(active[1]) if active.size() > 1 else "Skill 2", s.skill_2_style, s.skill_2_cost, s.skill_2_cooldown)
	s.noble_phantasm_desc = _np_desc(s.noble_phantasm_name, s.noble_phantasm_style, s.noble_phantasm_damage, s.noble_phantasm_range, s.noble_phantasm_cost, s.noble_phantasm_duration)
	s.np_desc = s.noble_phantasm_desc
	s.passive_desc = _servant_passive_desc(s)
	var path: String = "%s/%s.tres" % [SERVANT_DIR, s.servant_id]
	var err: Error = ResourceSaver.save(s, path)
	if err != OK:
		push_error("Failed to save %s (%d)" % [path, err])


func _save_master(entry: Dictionary) -> void:
	var mana: Array = entry["mana"]
	var stats: Array = entry["stats"]
	var skills: Array = entry["skills"]
	var m: MasterData = MasterData.new()
	m.master_id = String(entry["id"])
	m.display_name = String(entry["name"])
	m.description = String(entry.get("desc", ""))
	m.max_mana = float(mana[0])
	m.mana_regeneration = float(mana[1])
	m.mana_upkeep_cost = 2.0
	m.vision_radius = float(entry.get("vision", 520.0))
	m.strength = int(stats[0])
	m.endurance = int(stats[1])
	m.agility = int(stats[2])
	m.mana_rank = int(stats[3])
	m.luck = int(stats[4])
	m.noble_phantasm_rank = int(stats[5])
	m.leyline_affinity = float(entry.get("affinity", 1.0))
	m.leyline_linked = true
	m.skill_1_name = String(skills[0])
	m.skill_1_style = skills[1]
	m.skill_1_cost = float(skills[2])
	m.skill_1_cooldown = float(skills[3])
	m.skill_2_name = String(skills[4])
	m.skill_2_style = skills[5]
	m.skill_2_cost = float(skills[6])
	m.skill_2_cooldown = float(skills[7])
	m.active_skills = PackedStringArray([m.skill_1_name, m.skill_2_name])
	m.command_spell_charges = MasterData.MAX_COMMAND_SPELLS
	m.skill_1_desc = _master_skill_desc(m.skill_1_name, m.skill_1_style, m.skill_1_cost, m.skill_1_cooldown)
	m.skill_2_desc = _master_skill_desc(m.skill_2_name, m.skill_2_style, m.skill_2_cost, m.skill_2_cooldown)
	m.command_spell_desc = "3 Command Spells per match. Warp the Servant to the Master and trigger an emergency HP/Mana surge."
	m.np_desc = m.command_spell_desc
	m.passive_desc = "Master Mana %d, regeneration %.1f/s, vision %d. Mana upkeep from the contract is paid by this Master." % [int(m.max_mana), m.mana_regeneration, int(m.vision_radius)]
	var signature: Dictionary = _signature_data(m.master_id)
	m.signature_command_spell = String(signature.get("name", "Command Spell Decree"))
	m.signature_command_spell_desc = String(signature.get("desc", "A bespoke Command Spell decree."))
	m.signature_style = signature.get("style", MasterData.SignatureStyle.DECREE_WARP)
	var trump: Dictionary = _trump_data(m.master_id)
	m.master_trump_card = String(trump.get("name", "Mystic Code Ultimate"))
	m.trump_card_desc = String(trump.get("desc", "A Master's ultimate Mystic Code effect."))
	m.trump_style = trump.get("style", MasterData.TrumpStyle.HEAL_SHIELD)
	m.trump_card_cooldown = float(trump.get("cooldown", 60.0))
	m.trump_card_mana_cost = float(trump.get("cost", 0.0))
	var path: String = "%s/%s.tres" % [MASTER_DIR, m.master_id]
	var err: Error = ResourceSaver.save(m, path)
	if err != OK:
		push_error("Failed to save %s (%d)" % [path, err])


func _servant_defaults(class_id: int) -> Dictionary:
	var data: Dictionary = {
		"attack_style": ServantData.AttackStyle.PROJECTILE,
		"attack_cost": 7.0,
		"attack_cd": 0.4,
		"range": 800.0,
		"arc": 90.0,
		"projectile_speed": 700.0,
		"vision": 540.0,
		"crit": 0.08,
		"crit_mult": 1.5,
		"spell_mult": 1.0,
		"skill_1_style": ServantData.SkillStyle.BUFF,
		"skill_2_style": ServantData.SkillStyle.AOE,
		"skill_1_cost": 20.0,
		"skill_2_cost": 30.0,
		"skill_1_cooldown": 4.0,
		"skill_2_cooldown": 7.0,
		"barrage": 0,
		"barrage_interval": 0.07,
		"barrage_spread": 12.0,
		"stealth": 0.0,
		"dash": 180.0,
		"aoe": 180.0,
		"heal": 45.0,
		"scan": 650.0,
		"buff_duration": 5.0,
		"buff_damage": 1.3,
		"buff_speed": 1.25,
		"territory_mana": 0.0,
		"territory_spell": 0.0,
		"trap_cast": 0.0,
		"trap_radius": 55.0,
		"trap_damage": 0.0,
		"trap_duration": 10.0,
		"trap_pulse": 1.0,
	}

	match class_id:
		ServantData.ServantClass.SABER:
			data["attack_style"] = ServantData.AttackStyle.SLASH
			data["attack_cost"] = 6.0
			data["attack_cd"] = 0.45
			data["range"] = 112.0
			data["arc"] = 120.0
			data["vision"] = 520.0
			data["crit"] = 0.10
			data["skill_1_style"] = ServantData.SkillStyle.BUFF
			data["skill_2_style"] = ServantData.SkillStyle.AOE
		ServantData.ServantClass.ARCHER:
			data["attack_cd"] = 0.3
			data["range"] = 900.0
			data["projectile_speed"] = 880.0
			data["vision"] = 650.0
			data["crit"] = 0.14
			data["barrage"] = 6
			data["skill_1_style"] = ServantData.SkillStyle.BARRAGE
			data["skill_2_style"] = ServantData.SkillStyle.SCAN
			data["skill_1_cost"] = 24.0
			data["skill_1_cooldown"] = 3.5
		ServantData.ServantClass.LANCER:
			data["attack_style"] = ServantData.AttackStyle.SLASH
			data["attack_cost"] = 6.0
			data["attack_cd"] = 0.4
			data["range"] = 150.0
			data["arc"] = 80.0
			data["vision"] = 540.0
			data["crit"] = 0.15
			data["dash"] = 220.0
			data["skill_1_style"] = ServantData.SkillStyle.DASH
			data["skill_2_style"] = ServantData.SkillStyle.BUFF
		ServantData.ServantClass.RIDER:
			data["attack_style"] = ServantData.AttackStyle.SLASH
			data["attack_cost"] = 6.0
			data["attack_cd"] = 0.38
			data["range"] = 120.0
			data["arc"] = 100.0
			data["vision"] = 560.0
			data["dash"] = 240.0
			data["skill_1_style"] = ServantData.SkillStyle.DASH
			data["skill_2_style"] = ServantData.SkillStyle.BUFF
			data["buff_speed"] = 1.4
		ServantData.ServantClass.CASTER:
			data["attack_cd"] = 0.5
			data["range"] = 800.0
			data["projectile_speed"] = 620.0
			data["vision"] = 600.0
			data["crit"] = 0.05
			data["spell_mult"] = 1.3
			data["skill_1_style"] = ServantData.SkillStyle.TRAP
			data["skill_2_style"] = ServantData.SkillStyle.SCAN
			data["skill_1_cost"] = 30.0
			data["skill_1_cooldown"] = 2.5
			data["territory_mana"] = 15.0
			data["territory_spell"] = 0.5
			data["trap_cast"] = 230.0
			data["trap_radius"] = 65.0
			data["trap_damage"] = 20.0
			data["trap_duration"] = 12.0
			data["trap_pulse"] = 0.9
		ServantData.ServantClass.ASSASSIN:
			data["attack_style"] = ServantData.AttackStyle.SLASH
			data["attack_cost"] = 4.0
			data["attack_cd"] = 0.32
			data["range"] = 100.0
			data["arc"] = 90.0
			data["vision"] = 550.0
			data["crit"] = 0.38
			data["crit_mult"] = 2.2
			data["stealth"] = 4.0
			data["dash"] = 200.0
			data["skill_1_style"] = ServantData.SkillStyle.STEALTH
			data["skill_2_style"] = ServantData.SkillStyle.DASH
			data["skill_1_cost"] = 15.0
			data["skill_1_cooldown"] = 9.0
		ServantData.ServantClass.BERSERKER:
			data["attack_style"] = ServantData.AttackStyle.SLASH
			data["attack_cost"] = 6.0
			data["attack_cd"] = 0.5
			data["range"] = 120.0
			data["arc"] = 140.0
			data["vision"] = 500.0
			data["crit"] = 0.05
			data["aoe"] = 210.0
			data["skill_1_style"] = ServantData.SkillStyle.BUFF
			data["skill_2_style"] = ServantData.SkillStyle.AOE
		ServantData.ServantClass.RULER:
			data["attack_cd"] = 0.45
			data["range"] = 700.0
			data["projectile_speed"] = 650.0
			data["vision"] = 600.0
			data["spell_mult"] = 1.1
			data["skill_1_style"] = ServantData.SkillStyle.SCAN
			data["skill_2_style"] = ServantData.SkillStyle.HEAL
			data["heal"] = 60.0
		ServantData.ServantClass.AVENGER:
			data["attack_style"] = ServantData.AttackStyle.SLASH
			data["attack_cost"] = 5.0
			data["attack_cd"] = 0.4
			data["range"] = 110.0
			data["arc"] = 100.0
			data["vision"] = 520.0
			data["crit"] = 0.15
			data["skill_1_style"] = ServantData.SkillStyle.BUFF
			data["skill_2_style"] = ServantData.SkillStyle.AOE
	return data


func _class_skills(class_id: int) -> PackedStringArray:
	match class_id:
		ServantData.ServantClass.SABER:
			return PackedStringArray(["Magic Resistance", "Riding"])
		ServantData.ServantClass.ARCHER:
			return PackedStringArray(["Independent Action", "Magic Resistance"])
		ServantData.ServantClass.LANCER:
			return PackedStringArray(["Magic Resistance", "Battle Continuation"])
		ServantData.ServantClass.RIDER:
			return PackedStringArray(["Riding", "Magic Resistance"])
		ServantData.ServantClass.CASTER:
			return PackedStringArray(["Territory Creation", "Item Construction"])
		ServantData.ServantClass.ASSASSIN:
			return PackedStringArray(["Presence Concealment", "Independent Action"])
		ServantData.ServantClass.BERSERKER:
			return PackedStringArray(["Mad Enhancement"])
		ServantData.ServantClass.RULER:
			return PackedStringArray(["Magic Resistance", "True Name Discernment"])
		ServantData.ServantClass.AVENGER:
			return PackedStringArray(["Avenger", "Oblivion Correction"])
	return PackedStringArray()


func _servant_skill_desc(skill_name: String, style: int, cost: float, cooldown: float) -> String:
	var effect: String = ""
	match style:
		ServantData.SkillStyle.BARRAGE:
			effect = "Fires a rapid multi-projectile barrage."
		ServantData.SkillStyle.TRAP:
			effect = "Places a persistent magic-circle trap that pulses damage."
		ServantData.SkillStyle.STEALTH:
			effect = "Enters Presence Concealment, fading from sight until attacking."
		ServantData.SkillStyle.DASH:
			effect = "Dashes forward, damaging enemies along the path."
		ServantData.SkillStyle.BUFF:
			effect = "Temporarily boosts damage and movement speed."
		ServantData.SkillStyle.SCAN:
			effect = "Scouting pulse that reveals enemy true names in range."
		ServantData.SkillStyle.HEAL:
			effect = "Restores HP to the Servant and linked Master."
		ServantData.SkillStyle.AOE:
			effect = "Detonates an area attack around the Servant."
	return "%s: %s Mana %d, cooldown %.1fs." % [skill_name, effect, int(cost), cooldown]


func _np_desc(np_name: String, style: int, damage: float, np_range: float, cost: float, duration: float) -> String:
	var effect: String = ""
	match style:
		ServantData.NoblePhantasmStyle.BEAM:
			effect = "Fires a high-damage directional beam."
		ServantData.NoblePhantasmStyle.REALITY_MARBLE:
			effect = "Deploys a Reality Marble arena override that accelerates projectile attacks."
		ServantData.NoblePhantasmStyle.DASH:
			effect = "Performs a high-speed dash strike with critical damage."
		ServantData.NoblePhantasmStyle.NOVA:
			effect = "Detonates a large-area Noble Phantasm burst."
		ServantData.NoblePhantasmStyle.BARRAGE:
			effect = "Unleashes a wide barrage of Noble Phantasm projectiles."
		ServantData.NoblePhantasmStyle.SUPPORT:
			effect = "Heals and shields allied units within range."
		ServantData.NoblePhantasmStyle.REFLECT:
			effect = "Curses the Servant to reflect incoming damage for a short duration."
	return "%s: %s Power %d, range %d, Mana %d, duration %.1fs." % [np_name, effect, int(damage), int(np_range), int(cost), duration]


func _servant_passive_desc(servant: ServantData) -> String:
	var skills: String = ", ".join(servant.class_skills)
	return "Passive class skills: %s. STR %d / END %d / AGI %d / MANA %d / LCK %d / NP %d. Upkeep %.1f Mana/s." % [
		skills, servant.strength, servant.endurance, servant.agility,
		servant.mana_rank, servant.luck, servant.noble_phantasm_rank, servant.mana_upkeep_per_second,
	]


func _master_skill_desc(skill_name: String, style: int, cost: float, cooldown: float) -> String:
	var effect: String = ""
	match style:
		MasterData.MasterSkillStyle.BURST:
			effect = "Unleashes a radial magecraft burst."
		MasterData.MasterSkillStyle.HEAL_SERVANT:
			effect = "Restores the linked Servant's HP and Mana."
		MasterData.MasterSkillStyle.HASTE_SELF:
			effect = "Greatly increases the Master's movement speed."
		MasterData.MasterSkillStyle.REVEAL:
			effect = "Scouting magecraft that reveals enemy true names."
		MasterData.MasterSkillStyle.DRAIN:
			effect = "Drains Mana from the nearest enemy Servant."
		MasterData.MasterSkillStyle.SHIELD_SERVANT:
			effect = "Places a protective shield on the linked Servant."
	return "%s: %s Mana %d, cooldown %.1fs." % [skill_name, effect, int(cost), cooldown]


func _signature_data(master_id: String) -> Dictionary:
	match master_id:
		"rin_tohsaka":
			return {"name": "Tohsaka Decree: Overclock", "desc": "Overclocks the Servant's Mana core, restoring Mana and temporarily empowering its next strikes. Also overrides Servant autonomy.", "style": MasterData.SignatureStyle.OVERDRIVE}
		"shirou_emiya":
			return {"name": "I Command You: Protect Everyone", "desc": "Binds the Servant to a protective decree, shielding the duo and restoring HP. Also overrides Servant autonomy.", "style": MasterData.SignatureStyle.BIND}
		"illyasviel_von_einzbern":
			return {"name": "Einzbern Decree: Wishcraft", "desc": "A wishcraft surge that refills the Servant's Mana and coats it in a shield. Overrides Servant autonomy.", "style": MasterData.SignatureStyle.SURGE}
		"kirei_kotomine":
			return {"name": "Executor's Decree: Submit", "desc": "A binding rite that reveals nearby enemies and shields the Servant. Overrides Servant autonomy.", "style": MasterData.SignatureStyle.REVEAL}
		"kiritsugu_emiya":
			return {"name": "Mage Killer's Decree", "desc": "Forces a lethal tempo: hastes and empowers the Servant while overriding its autonomy.", "style": MasterData.SignatureStyle.RAMPAGE}
		"tokiomi_tohsaka":
			return {"name": "Tohsaka Decree: Jeweled Order", "desc": "A formal jeweled decree that restores Mana and empowers the Servant. Overrides Servant autonomy.", "style": MasterData.SignatureStyle.OVERDRIVE}
		"kayneth_el_melloi":
			return {"name": "Archibald Decree: Volumen", "desc": "Orders the Servant under the protection of Volumen Hydrargyrum, shielding it and forcing compliance.", "style": MasterData.SignatureStyle.BIND}
		"waver_velvet":
			return {"name": "Velvet Decree: Grand Strategy", "desc": "A strategic command that reveals enemy positions and restores the Servant. Overrides Servant autonomy.", "style": MasterData.SignatureStyle.REVEAL}
		"ryuunosuke_uryuu":
			return {"name": "Carnival Decree", "desc": "A maddening decree that drives the Servant into a damage frenzy. Overrides Servant autonomy.", "style": MasterData.SignatureStyle.RAMPAGE}
		"kariya_matou":
			return {"name": "Matou Decree: Consume", "desc": "The Crest Worms surge, empowering the Servant at a painful cost. Overrides Servant autonomy.", "style": MasterData.SignatureStyle.RAMPAGE}
		"kairi_sisigou":
			return {"name": "Sisigou Decree: Hunter's Mark", "desc": "Marks and reveals enemy Servants while restoring the Servant's Mana. Overrides Servant autonomy.", "style": MasterData.SignatureStyle.REVEAL}
		"darnic_yggdmillennia":
			return {"name": "Yggdmillennia Decree", "desc": "A patriarch's command that shields the Servant and forces absolute compliance.", "style": MasterData.SignatureStyle.BIND}
		"fiore_yggdmillennia":
			return {"name": "Forvedge Decree: Recon", "desc": "Scouting recon reveals nearby enemies and restores the Servant. Overrides Servant autonomy.", "style": MasterData.SignatureStyle.REVEAL}
		"gordes_musik":
			return {"name": "Gordes Decree: Fortify", "desc": "A stubborn alchemical decree that shields the Servant and restores HP. Overrides autonomy.", "style": MasterData.SignatureStyle.BIND}
		"caules_forvedge":
			return {"name": "Caules Decree: Familiar Network", "desc": "Familiar scouts reveal enemies and restore the Servant. Overrides Servant autonomy.", "style": MasterData.SignatureStyle.REVEAL}
	return {"name": "Command Spell Decree", "desc": "A bespoke decree that overrides Servant autonomy.", "style": MasterData.SignatureStyle.DECREE_WARP}


func _trump_data(master_id: String) -> Dictionary:
	match master_id:
		"rin_tohsaka":
			return {"name": "Zelretch Jeweled Sword", "desc": "Unleashes a concentrated jeweled-sword beam that pierces enemy lines.", "style": MasterData.TrumpStyle.JEWELED_SWORD, "cooldown": 55.0, "cost": 40.0}
		"shirou_emiya":
			return {"name": "Rho Aias", "desc": "Projects the seven-petal shield, protecting the Master and Servant from damage.", "style": MasterData.TrumpStyle.RHO_AIAS, "cooldown": 60.0, "cost": 35.0}
		"illyasviel_von_einzbern":
			return {"name": "Dress of Heaven", "desc": "The Holy Grail vessel's dress restores and shields the Servant.", "style": MasterData.TrumpStyle.HEAL_SHIELD, "cooldown": 55.0, "cost": 45.0}
		"kirei_kotomine":
			return {"name": "Baptism Rite", "desc": "A purifying rite that burns nearby enemies and restores the Servant.", "style": MasterData.TrumpStyle.DRAIN_NOVA, "cooldown": 50.0, "cost": 35.0}
		"kiritsugu_emiya":
			return {"name": "Square Accel + Origin Bullet", "desc": "Accelerates time and fires an Origin Round that tears through a target line.", "style": MasterData.TrumpStyle.ORIGIN_BULLET, "cooldown": 60.0, "cost": 45.0}
		"tokiomi_tohsaka":
			return {"name": "Tohsaka Jeweled Blade", "desc": "Channels the Tohsaka jewel line into a searing blade of Mana.", "style": MasterData.TrumpStyle.JEWELED_SWORD, "cooldown": 60.0, "cost": 40.0}
		"kayneth_el_melloi":
			return {"name": "Volumen Hydrargyrum: Suchen & Schneiden", "desc": "Mercury blades storm the battlefield, shielding the Servant and cutting enemies.", "style": MasterData.TrumpStyle.MERCURY_STORM, "cooldown": 65.0, "cost": 50.0}
		"waver_velvet":
			return {"name": "Grand Strategist's Decree", "desc": "Reveals the entire enemy order of battle and restores tactical Mana.", "style": MasterData.TrumpStyle.GLOBAL_REVEAL, "cooldown": 50.0, "cost": 25.0}
		"ryuunosuke_uryuu":
			return {"name": "The Bloody Carnival", "desc": "A rain of gore and blades erupts around the battlefield.", "style": MasterData.TrumpStyle.BLOOD_CARNIVAL, "cooldown": 45.0, "cost": 30.0}
		"kariya_matou":
			return {"name": "Zouken's Crest Worm Rupture", "desc": "Sacrifices Master HP to instantly fill the Servant's Mana and NP charge.", "style": MasterData.TrumpStyle.NP_CHARGE_HP_COST, "cooldown": 70.0, "cost": 0.0}
		"kairi_sisigou":
			return {"name": "Necromantic Origin Shot", "desc": "A cursed origin round that punches through the target line.", "style": MasterData.TrumpStyle.ORIGIN_BULLET, "cooldown": 55.0, "cost": 35.0}
		"darnic_yggdmillennia":
			return {"name": "Spiritual Evocation: Dracula's Legacy", "desc": "Drains the life and Mana of nearby enemies to restore the Servant.", "style": MasterData.TrumpStyle.DRAIN_NOVA, "cooldown": 60.0, "cost": 40.0}
		"fiore_yggdmillennia":
			return {"name": "Golem Keter Malkuth", "desc": "A golem's aegis shields and restores the Servant.", "style": MasterData.TrumpStyle.HEAL_SHIELD, "cooldown": 60.0, "cost": 45.0}
		"gordes_musik":
			return {"name": "Golem Fortress", "desc": "A fortress of alchemical earth protects the Servant and heals its wounds.", "style": MasterData.TrumpStyle.HEAL_SHIELD, "cooldown": 60.0, "cost": 40.0}
		"caules_forvedge":
			return {"name": "Familiar Network Restoration", "desc": "The familiar network restores and shields the Servant.", "style": MasterData.TrumpStyle.HEAL_SHIELD, "cooldown": 55.0, "cost": 35.0}
	return {"name": "Mystic Code Ultimate", "desc": "A Master's ultimate Mystic Code effect.", "style": MasterData.TrumpStyle.HEAL_SHIELD, "cooldown": 60.0, "cost": 0.0}
