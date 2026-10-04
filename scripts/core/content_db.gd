class_name ContentDb
extends RefCounted
## 内容数据库：加载 data/content 下全部 JSON 并校验（Python 版 content_loader.py 的移植）。
## 模型层组件——不接触节点树；校验失败收集错误清单由调用方决定中止。

const ELEMENTS: PackedStringArray = ["metal", "wood", "water", "fire", "earth"]
const ELEMENT_BEATS := {
	"metal": "wood",
	"wood": "earth",
	"earth": "water",
	"water": "fire",
	"fire": "metal",
}
const RESIST_KINDS: PackedStringArray = ["metal", "wood", "water", "fire", "earth", "stun"]
const SKILL_EFFECT_TYPES: PackedStringArray = [
	"damage_nearest", "damage_aoe_self", "buff_defense", "buff_power",
	"teleport_step", "heal_self", "element_dot", "summon",
	"stun_aoe", "knockback_aoe", "mp_restore",
]
const VALID_BONUS_KEYS: PackedStringArray = ["power", "defense", "max_hp", "max_mp", "max_sp"]
const VALID_AFFIX_IDS: PackedStringArray = [
	"metal_damage", "wood_damage", "water_damage", "fire_damage", "earth_damage",
	"aoe_damage", "heal_power", "mp_cost_reduce", "kill_heal",
	"resist_metal", "resist_wood", "resist_water", "resist_fire", "resist_earth", "resist_stun",
]
const SLOT_ORDER: PackedStringArray = ["weapon", "armor", "boots", "amulet", "helm"]
const SUPPORTED_LANGS: PackedStringArray = ["zh_CN", "en_US"]

var monsters: Dictionary = {}
var items: Dictionary = {}
var classes: Dictionary = {}
var skills: Dictionary = {}
var spawn_monsters: Array = []
var spawn_items: Array = []
var regions: Array = []
var realms: Dictionary = {}
var recipes: Array = []
var player_def: Dictionary = {}
var theme: Dictionary = {}
var strings: Dictionary = {}
var lang := "zh_CN"


## 加载目录下全部内容；返回错误清单（空 = 通过）。
## dir_path 约定指向 data/content 目录本身。
func load_all(dir_path: String, p_lang := "zh_CN") -> PackedStringArray:
	lang = p_lang
	var errors := PackedStringArray()
	_load_json_or_error(dir_path.path_join("monsters.json"), "monsters", errors)
	_load_json_or_error(dir_path.path_join("items.json"), "items", errors)
	_load_json_or_error(dir_path.path_join("classes.json"), "classes", errors)
	_load_json_or_error(dir_path.path_join("skills.json"), "skills", errors)
	_load_json_or_error(dir_path.path_join("player.json"), "player_def", errors)
	_load_json_or_error(dir_path.path_join("theme.json"), "theme", errors)
	_load_json_or_error(dir_path.path_join("regions.json"), "regions_root", errors)
	_load_json_or_error(dir_path.path_join("realms.json"), "realms_root", errors)
	_load_json_or_error(dir_path.path_join("crafting.json"), "crafting_root", errors)
	_load_json_or_error(dir_path.path_join("spawn_tables.json"), "spawn_root", errors)
	if not errors.is_empty():
		return errors
	regions = regions_root.get("regions", [])
	realms = {}
	for realm in realms_root.get("realms", []):
		realms[realm["id"]] = realm
	recipes = crafting_root.get("recipes", [])
	spawn_monsters = spawn_root.get("monsters", [])
	spawn_items = spawn_root.get("items", [])
	_load_strings(dir_path.path_join("strings"), errors)
	if errors.is_empty():
		_validate(errors)
	return errors

var regions_root := {}
var realms_root := {}
var crafting_root := {}
var spawn_root := {}


func _load_json_or_error(path: String, target: String, errors: PackedStringArray) -> void:
	if not FileAccess.file_exists(path):
		errors.append("缺少文件: %s" % path)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or not (parsed is Dictionary):
		errors.append("JSON 解析失败: %s" % path)
		return
	# 去掉 _schema 说明键
	var filtered := {}
	for key in parsed:
		if not String(key).begins_with("_"):
			filtered[key] = parsed[key]
	set(target, filtered)


func _load_strings(dir_path: String, errors: PackedStringArray) -> void:
	# zh_CN 为基底，主语言覆盖其上（与 Python 版回退顺序一致）
	var merged := {}
	var base_parsed = JSON.parse_string(FileAccess.get_file_as_string(dir_path.path_join("zh_CN.json")))
	if base_parsed is Dictionary:
		for key in base_parsed:
			if not String(key).begins_with("_"):
				merged[String(key)] = String(base_parsed[key])
	else:
		errors.append("文案 JSON 解析失败: zh_CN.json")
	var lang_path := dir_path.path_join("%s.json" % lang)
	if FileAccess.file_exists(lang_path):
		var lang_parsed = JSON.parse_string(FileAccess.get_file_as_string(lang_path))
		if lang_parsed is Dictionary:
			for key in lang_parsed:
				if not String(key).begins_with("_"):
					merged[String(key)] = String(lang_parsed[key])
		else:
			errors.append("文案 JSON 解析失败: %s.json" % lang)
	strings = merged


## 双语文案查询（无则回退 key 本身，便于发现缺漏）。
func text(key: String) -> String:
	return strings.get(key, key)


## 本地化字段解析：str=全语言同值；dict=按语言取缺则 zh_CN。
func localize(value) -> String:
	if value is Dictionary:
		if value.has(lang):
			return String(value[lang])
		if value.has("zh_CN"):
			return String(value["zh_CN"])
		return String(value.values()[0])
	return String(value)


# ---- 校验（Python 版核心不变式的移植） ----

func _validate(errors: PackedStringArray) -> void:
	_validate_classes(errors)
	_validate_skills(errors)
	_validate_monsters(errors)
	_validate_items(errors)
	_validate_spawn(errors)


func _validate_classes(errors: PackedStringArray) -> void:
	if classes.size() < 2:
		errors.append("classes.json 至少需要 2 个职业")
	for cid in classes:
		var cdef: Dictionary = classes[cid]
		if not cdef.has("name"):
			errors.append("职业 %s 缺少 name" % cid)
		for field_name in ["hp", "power", "defense", "mp", "sp"]:
			var value = cdef.get(field_name)
			if value == null or not (value is float) or value < 0:
				errors.append("职业 %s 的 %s 必须是非负数" % [cid, field_name])


func _validate_skills(errors: PackedStringArray) -> void:
	var by_class := {}
	for sid in skills:
		var sdef: Dictionary = skills[sid]
		var owner: String = sdef.get("class", "")
		if not classes.has(owner):
			errors.append("技能 %s 引用了不存在的职业 %s" % [sid, owner])
			continue
		var slot = sdef.get("slot")
		if not (slot is float) or slot < 1 or slot > 8:
			errors.append("技能 %s 的 slot 必须是 1-8" % sid)
		var eff_type: String = sdef.get("effect", {}).get("type", "")
		if not SKILL_EFFECT_TYPES.has(eff_type):
			errors.append("技能 %s 的效果类型 %s 未注册" % [sid, eff_type])
		var cost = sdef.get("cost", 1)
		if not (cost == 1 or cost == 2):
			errors.append("技能 %s 的 cost 必须是 1 或 2" % sid)
		for req in sdef.get("requires", []):
			if not skills.has(req):
				errors.append("技能 %s 的前置 %s 不存在" % [sid, req])
		if not by_class.has(owner):
			by_class[owner] = {}
		by_class[owner][int(slot) if slot is float else 0] = sid
	for cid in by_class:
		var slots: Dictionary = by_class[cid]
		for i in range(1, 9):
			if not slots.has(i):
				errors.append("职业 %s 缺少 slot %d 的技能" % [cid, i])


func _validate_monsters(errors: PackedStringArray) -> void:
	for mid in monsters:
		var mdef: Dictionary = monsters[mid]
		for field_name in ["name", "char", "color"]:
			if not mdef.has(field_name):
				errors.append("怪物 %s 缺少 %s" % [mid, field_name])
		var element: String = mdef.get("element", "")
		if element != "" and not ELEMENTS.has(element):
			errors.append("怪物 %s 的 element %s 非法" % [mid, element])
		for tag in mdef.get("attack_tags", []):
			if not ELEMENTS.has(tag):
				errors.append("怪物 %s 的 attack_tags %s 非法" % [mid, tag])
		for kind in mdef.get("resistances", {}):
			if not RESIST_KINDS.has(kind):
				errors.append("怪物 %s 的抗性类型 %s 非法" % [mid, kind])


func _validate_items(errors: PackedStringArray) -> void:
	for iid in items:
		var idef: Dictionary = items[iid]
		var gear = idef.get("equipment")
		if gear == null:
			continue
		var slot: String = gear.get("slot", "")
		if not SLOT_ORDER.has(slot):
			errors.append("物品 %s 的装备槽 %s 非法" % [iid, slot])
			continue
		if slot == "weapon":
			var damage = gear.get("damage")
			if damage == null or not (damage is Dictionary):
				errors.append("武器 %s 缺少 damage 伤害面" % iid)
			else:
				var physical = damage.get("physical")
				if not (physical is float) or physical <= 0:
					errors.append("武器 %s 的 physical 必须为正" % iid)
				var element: String = damage.get("element", "")
				if element != "" and not ELEMENTS.has(element):
					errors.append("武器 %s 的 element %s 非法" % [iid, element])
			if gear.get("bonuses", {}).size() > 0 or gear.get("affixes", []).size() > 0:
				errors.append("武器 %s 不得携带 bonuses/affixes" % iid)
		else:
			if gear.has("damage"):
				errors.append("非武器 %s 不得携带 damage" % iid)
			for key in gear.get("bonuses", {}):
				if not VALID_BONUS_KEYS.has(key):
					errors.append("物品 %s 的加成键 %s 非法" % [iid, key])
			for affix in gear.get("affixes", []):
				if not VALID_AFFIX_IDS.has(affix.get("id", "")):
					errors.append("物品 %s 的词条 %s 非法" % [iid, affix.get("id", "")])


func _validate_spawn(errors: PackedStringArray) -> void:
	for entry in spawn_monsters:
		if not monsters.has(entry.get("id", "")):
			errors.append("投放表引用了不存在的怪物 %s" % entry.get("id", ""))
	for entry in spawn_items:
		if not items.has(entry.get("id", "")):
			errors.append("投放表引用了不存在的物品 %s" % entry.get("id", ""))
