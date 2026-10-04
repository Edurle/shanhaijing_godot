extends RefCounted
## 字段注册表：每种实体的表单字段描述符 + 技能/消耗品效果参数表 + 跨文件引用扫描。
## 新增属性 = 在对应 SPEC 里加一行描述符 + 在消费端写逻辑，表单/表格自动跟进。
## 枚举值一律引用 ContentDb 常量（单一事实来源）；中文显示标签见 ENUM_LABELS。

const ContentDbScript := preload("res://scripts/core/content_db.gd")

## 实体类型（物品按 equipment/consumable/material 分三个子型）。
const TYPES: PackedStringArray = [
	"monster", "class", "player", "skill",
	"item_weapon", "item_gear", "item_consumable", "item_material",
]

## 枚举值的中文显示标签（缺省回退原值）。
const ENUM_LABELS := {
	"metal": "金", "wood": "木", "water": "水", "fire": "火", "earth": "土",
	"stun": "眩晕", "root": "缠绕", "sunder": "破甲", "daunt": "挫志", "knockback": "击退",
	"weapon": "武器", "armor": "护甲", "boots": "靴履", "amulet": "玉佩", "helm": "冠帽",
	"hostile": "敌对",
	"damage_nearest": "单体伤害", "damage_aoe_self": "自身周围",
	"buff_defense": "御守", "buff_power": "蓄力", "teleport_step": "疾步",
	"heal_self": "自愈", "element_dot": "持续伤", "summon": "召唤",
	"stun_aoe": "眩晕阵", "knockback_aoe": "击退阵", "mp_restore": "回气",
	"heal": "疗伤", "heal_mp": "回气", "cleanse": "解毒", "buff_item": "药力",
	"lightning": "天雷", "stun_area": "定身", "smoke": "烟障", "tianshu": "天书",
	"metal_damage": "金系伤害", "wood_damage": "木系伤害", "water_damage": "水系伤害",
	"fire_damage": "火系伤害", "earth_damage": "土系伤害", "aoe_damage": "范围伤害",
	"heal_power": "疗效加成", "mp_cost_reduce": "技能省气", "kill_heal": "击杀回血",
	"resist_metal": "金抗", "resist_wood": "木抗", "resist_water": "水抗",
	"resist_fire": "火抗", "resist_earth": "土抗", "resist_stun": "眩晕抗",
	"resist_root": "缠绕抗", "resist_sunder": "破甲抗", "resist_daunt": "挫志抗",
	"resist_knockback": "击退抗",
	"alchemy": "炼丹", "forge": "炼器", "talisman": "炼符",
}


# ---- 字段描述符简写 ----
# key=点路径 label=中文 kind=控件类型 group=分组标题
# 可选标记: optional=可缺省 / omit_zero=0 不落盘 / omit_empty=空串不落盘 / omit_equals=等于该值不落盘
# shape=true 表示该字段变更后表单需整体重建（类型/槽位切换）
static func f(key: String, label: String, kind: String, group: String, extra := {}) -> Dictionary:
	var field := {"key": key, "label": label, "kind": kind, "group": group}
	field.merge(extra, true)
	return field


static func fields_for(entity_type: String) -> Array:
	match entity_type:
		"monster":
			return monster_fields()
		"class":
			return class_fields()
		"player":
			return player_fields()
		"skill":
			return skill_fields()
		"item_weapon":
			return item_common_fields(true) + item_weapon_fields()
		"item_gear":
			return item_common_fields(true) + item_gear_fields()
		"item_consumable":
			return item_common_fields(false) + item_consumable_fields()
		"item_material":
			return item_common_fields(false)
	return []


# ---- 怪物 ----
static func monster_fields() -> Array:
	var fields: Array = [
		f("name", "名称", "localized", "基础"),
		f("char", "地图字符", "string", "基础"),
		f("color", "颜色(R,G,B)", "color", "基础"),
		f("lore", "典故", "localized", "基础"),
		f("tags", "标签(逗号分隔)", "tags", "基础"),
		f("components.fighter.hp", "气血", "int", "战斗", {"min": 1, "max": 9999}),
		f("components.fighter.power", "攻击", "int", "战斗", {"min": 0, "max": 999}),
		f("components.fighter.defense", "防御", "int", "战斗", {"min": 0, "max": 99}),
		f("components.fighter.xp_reward", "经验奖励", "int", "战斗", {"min": 0, "max": 9999, "optional": true, "omit_zero": true}),
		f("components.ai.type", "AI 行为", "enum", "战斗", {"enum_values": ["hostile"]}),
		f("components.ai.perception", "感知半径", "int", "战斗", {"min": 1, "max": 20, "optional": true, "omit_equals": 6}),
	]
	fields.append_array(element_fields())
	return fields


## 五行 + 抗性分组（怪物专用）。
static func element_fields() -> Array:
	var values: Array = Array(ContentDbScript.ELEMENTS).duplicate()
	values.append("")
	var fields: Array = [
		f("element", "本命五行", "enum", "五行", {"enum_values": values, "optional": true, "omit_empty": true}),
		f("attack_tags", "普攻附带元素(逗号分隔)", "elements", "五行", {"optional": true, "omit_empty": true}),
	]
	var resist_labels := {"metal": "金抗", "wood": "木抗", "water": "水抗", "fire": "火抗", "earth": "土抗"}
	for kind in ContentDbScript.RESIST_KINDS:
		var label: String = resist_labels.get(kind, "%s抗" % ENUM_LABELS.get(kind, kind))
		fields.append(f("resistances.%s" % kind, label, "int", "抗性", {
			"min": 0, "max": 80, "optional": true, "omit_zero": true,
		}))
	return fields


# ---- 职业 / 玩家 ----
static func class_fields() -> Array:
	return [
		f("name", "名称", "localized", "基础"),
		f("desc", "描述", "localized", "基础"),
		f("hp", "气血", "int", "数值", {"min": 1, "max": 999}),
		f("power", "攻击", "int", "数值", {"min": 0, "max": 99}),
		f("defense", "防御", "int", "数值", {"min": 0, "max": 99}),
		f("mp", "真气", "int", "数值", {"min": 0, "max": 999}),
		f("sp", "灵力", "int", "数值", {"min": 0, "max": 999}),
	]


static func player_fields() -> Array:
	return [
		f("name", "名称", "localized", "基础"),
		f("char", "地图字符", "string", "基础"),
		f("color", "颜色(R,G,B)", "color", "基础"),
		f("tags", "标签(逗号分隔)", "tags", "基础"),
		f("fighter.hp", "气血", "int", "战斗", {"min": 1, "max": 999}),
		f("fighter.power", "攻击", "int", "战斗", {"min": 0, "max": 99}),
		f("fighter.defense", "防御", "int", "战斗", {"min": 0, "max": 99}),
		f("level.base_xp", "基础经验", "int", "升级", {"min": 1, "max": 9999}),
		f("level.step_xp", "每级递增", "int", "升级", {"min": 1, "max": 9999}),
		f("level.per_level.max_hp", "每级气血", "int", "升级", {"min": 0, "max": 99}),
		f("level.per_level.max_mp", "每级真气", "int", "升级", {"min": 0, "max": 99}),
		f("level.per_level.max_sp", "每级灵力", "int", "升级", {"min": 0, "max": 99}),
		f("level.per_level.power", "每级攻击", "int", "升级", {"min": 0, "max": 99}),
		f("level.per_level.defense", "每级防御", "int", "升级", {"min": 0, "max": 99}),
		f("level.per_level.skill_points", "每级技能点", "int", "升级", {"min": 0, "max": 99}),
	]


# ---- 技能 ----
static func skill_fields() -> Array:
	return [
		f("class", "职业", "ref", "基础", {"ref": "classes", "shape": true}),
		f("slot", "槽位(1-8)", "int", "基础", {"min": 1, "max": 8}),
		f("name", "名称", "localized", "基础"),
		f("desc", "描述", "localized", "基础"),
		f("tags", "标签(逗号分隔)", "tags", "基础", {"optional": true, "omit_empty": true}),
		f("mp", "耗气", "int", "消耗", {"min": 0, "max": 999}),
		f("cost", "行动点(1/2)", "int", "消耗", {"min": 1, "max": 2}),
		f("requires", "前置技能(逗号分隔id)", "tags", "消耗", {"optional": true, "omit_empty": true, "ref": "skills"}),
		f("effect.type", "效果类型", "enum", "效果", {"enum_values": Array(ContentDbScript.SKILL_EFFECT_TYPES).duplicate(), "shape": true}),
	]


## 技能效果参数表：key=效果类型，值为 effect.* 下的字段描述符。
## 参数消费点见 scripts/core/skills.gd 与 skill_effects/*；改动效果实现时同步此表。
const EFFECT_PARAMS := {
	"damage_nearest": [
		{"key": "power", "label": "主强度", "kind": "int", "min": 1, "max": 99},
		{"key": "scale", "label": "强度系数", "kind": "float", "min": 0.0, "max": 10.0, "step": 0.1},
		{"key": "hits", "label": "段数", "kind": "int", "min": 1, "max": 9},
		{"key": "hp_cost", "label": "血耗", "kind": "int", "min": 0, "max": 99, "optional": true, "omit_zero": true},
		{"key": "dot", "label": "附带持续伤", "kind": "subdict", "children": [
			{"key": "damage", "label": "每回合", "kind": "int", "min": 1, "max": 99},
			{"key": "turns", "label": "回合数", "kind": "int", "min": 1, "max": 30},
		]},
		{"key": "sunder", "label": "附带破甲", "kind": "subdict", "children": [
			{"key": "amount", "label": "削防", "kind": "int", "min": 1, "max": 99},
			{"key": "turns", "label": "回合数", "kind": "int", "min": 1, "max": 30},
		]},
		{"key": "daunt", "label": "附带挫志", "kind": "subdict", "children": [
			{"key": "amount", "label": "削攻", "kind": "int", "min": 1, "max": 99},
			{"key": "turns", "label": "回合数", "kind": "int", "min": 1, "max": 30},
		]},
		{"key": "root", "label": "缠绕回合", "kind": "int", "min": 0, "max": 9, "optional": true, "omit_zero": true},
		{"key": "knockback", "label": "击退格数", "kind": "int", "min": 0, "max": 9, "optional": true, "omit_zero": true},
	],
	"damage_aoe_self": [
		{"key": "radius", "label": "半径", "kind": "int", "min": 1, "max": 5},
		{"key": "power", "label": "主强度", "kind": "int", "min": 1, "max": 99},
		{"key": "scale", "label": "强度系数", "kind": "float", "min": 0.0, "max": 10.0, "step": 0.1},
		{"key": "stun", "label": "眩晕回合", "kind": "int", "min": 0, "max": 9, "optional": true, "omit_zero": true},
		{"key": "dot", "label": "附带持续伤", "kind": "subdict", "children": [
			{"key": "damage", "label": "每回合", "kind": "int", "min": 1, "max": 99},
			{"key": "turns", "label": "回合数", "kind": "int", "min": 1, "max": 30},
		]},
		{"key": "sunder", "label": "附带破甲", "kind": "subdict", "children": [
			{"key": "amount", "label": "削防", "kind": "int", "min": 1, "max": 99},
			{"key": "turns", "label": "回合数", "kind": "int", "min": 1, "max": 30},
		]},
		{"key": "daunt", "label": "附带挫志", "kind": "subdict", "children": [
			{"key": "amount", "label": "削攻", "kind": "int", "min": 1, "max": 99},
			{"key": "turns", "label": "回合数", "kind": "int", "min": 1, "max": 30},
		]},
	],
	"buff_defense": [
		{"key": "amount", "label": "加防", "kind": "int", "min": 1, "max": 99},
		{"key": "turns", "label": "回合数", "kind": "int", "min": 1, "max": 30},
	],
	"buff_power": [
		{"key": "amount", "label": "加攻", "kind": "int", "min": 1, "max": 99},
		{"key": "turns", "label": "回合数", "kind": "int", "min": 1, "max": 30},
	],
	"teleport_step": [
		{"key": "range", "label": "位移格数", "kind": "int", "min": 1, "max": 9},
	],
	"heal_self": [
		{"key": "amount", "label": "基础治疗", "kind": "int", "min": 1, "max": 999},
		{"key": "scale", "label": "成长系数", "kind": "float", "min": 0.0, "max": 10.0, "step": 0.1},
		{"key": "aoe_radius", "label": "群体半径", "kind": "int", "min": 0, "max": 5, "optional": true, "omit_zero": true},
		{"key": "aoe_power", "label": "群体强度", "kind": "int", "min": 0, "max": 99, "optional": true, "omit_zero": true},
	],
	"element_dot": [
		{"key": "damage", "label": "每回合", "kind": "int", "min": 1, "max": 99},
		{"key": "scale", "label": "成长系数", "kind": "float", "min": 0.0, "max": 10.0, "step": 0.1},
		{"key": "turns", "label": "回合数", "kind": "int", "min": 1, "max": 30},
	],
	"summon": [
		{"key": "beast_name", "label": "召唤兽名", "kind": "string", "ref": "monsters"},
		{"key": "beast_hp", "label": "兽气血", "kind": "int", "min": 1, "max": 999},
		{"key": "beast_power", "label": "兽攻击", "kind": "int", "min": 1, "max": 99},
		{"key": "duration", "label": "存在回合", "kind": "int", "min": 1, "max": 99},
	],
	"stun_aoe": [
		{"key": "radius", "label": "半径", "kind": "int", "min": 1, "max": 5},
		{"key": "turns", "label": "眩晕回合", "kind": "int", "min": 1, "max": 9},
		{"key": "power", "label": "主强度", "kind": "int", "min": 1, "max": 99},
		{"key": "scale", "label": "强度系数", "kind": "float", "min": 0.0, "max": 10.0, "step": 0.1},
	],
	"knockback_aoe": [
		{"key": "radius", "label": "半径", "kind": "int", "min": 1, "max": 5},
		{"key": "push", "label": "推离格数", "kind": "int", "min": 1, "max": 5},
		{"key": "power", "label": "主强度", "kind": "int", "min": 1, "max": 99},
		{"key": "scale", "label": "强度系数", "kind": "float", "min": 0.0, "max": 10.0, "step": 0.1},
	],
	"mp_restore": [
		{"key": "amount", "label": "回气量", "kind": "int", "min": 1, "max": 99},
	],
}


## 消耗品效果参数表：key=type，值为 consumable.* 下的字段描述符（消费点见 consumables.gd）。
const CONSUMABLE_PARAMS := {
	"heal": [
		{"key": "amount", "label": "治疗量", "kind": "int", "min": 1, "max": 999},
	],
	"heal_mp": [
		{"key": "amount", "label": "回气量", "kind": "int", "min": 1, "max": 999},
	],
	"cleanse": [],
	"buff_item": [
		{"key": "stat", "label": "药力属性", "kind": "enum", "enum_values": ["power", "defense"]},
		{"key": "amount", "label": "加值", "kind": "int", "min": 1, "max": 99},
		{"key": "turns", "label": "回合数", "kind": "int", "min": 1, "max": 30},
	],
	"lightning": [
		{"key": "damage", "label": "雷伤", "kind": "int", "min": 1, "max": 999},
		{"key": "max_range", "label": "射程", "kind": "int", "min": 1, "max": 20},
	],
	"knockback": [
		{"key": "damage", "label": "震伤", "kind": "int", "min": 1, "max": 999},
		{"key": "max_range", "label": "射程", "kind": "int", "min": 1, "max": 20},
		{"key": "push", "label": "推离格数", "kind": "int", "min": 1, "max": 9},
		{"key": "stun", "label": "撞壁眩晕", "kind": "int", "min": 0, "max": 9},
	],
	"stun_area": [
		{"key": "turns", "label": "眩晕回合", "kind": "int", "min": 1, "max": 9},
		{"key": "radius", "label": "半径", "kind": "int", "min": 1, "max": 20},
	],
	"smoke": [
		{"key": "turns", "label": "持续回合", "kind": "int", "min": 1, "max": 30},
	],
	"tianshu": [],
}


## 技能/消耗品的动态参数字段（前缀到 effect./consumable.，供表单追加）。
static func effect_param_fields(prefix: String, effect_type: String) -> Array:
	var table := EFFECT_PARAMS if prefix == "effect" else CONSUMABLE_PARAMS
	var raw: Array = table.get(effect_type, [])
	var out: Array = []
	for field in raw:
		var copy: Dictionary = (field as Dictionary).duplicate(true)
		copy["key"] = "%s.%s" % [prefix, copy["key"]]
		if copy.has("children"):
			for child in copy["children"]:
				child["key"] = "%s.%s" % [copy["key"], child["key"]]
		out.append(copy)
	return out


# ---- 物品 ----
static func item_common_fields(with_tier: bool) -> Array:
	var fields: Array = [
		f("name", "名称", "localized", "基础"),
		f("char", "地图字符", "string", "基础"),
		f("color", "颜色(R,G,B)", "color", "基础"),
		f("lore", "典故", "localized", "基础"),
		f("tags", "标签(逗号分隔)", "tags", "基础"),
	]
	if with_tier:
		fields.append(f("tier", "品阶(掉落门槛)", "int", "基础", {"min": 1, "max": 9}))
	return fields


static func item_weapon_fields() -> Array:
	var values: Array = Array(ContentDbScript.SLOT_ORDER).duplicate()
	var elements: Array = Array(ContentDbScript.ELEMENTS).duplicate()
	elements.append("")
	return [
		f("equipment.slot", "装备槽", "enum", "装备", {"enum_values": values, "shape": true}),
		f("equipment.damage.physical", "物理伤害", "int", "武器", {"min": 1, "max": 99}),
		f("equipment.damage.element", "属性元素", "enum", "武器", {"enum_values": elements, "optional": true, "omit_empty": true}),
	]


static func item_gear_fields() -> Array:
	var values: Array = Array(ContentDbScript.SLOT_ORDER).duplicate()
	var fields: Array = [
		f("equipment.slot", "装备槽", "enum", "装备", {"enum_values": values, "shape": true}),
	]
	for bonus_key in ContentDbScript.VALID_BONUS_KEYS:
		fields.append(f("equipment.bonuses.%s" % bonus_key, "加成·%s" % bonus_key, "int", "加成", {
			"min": 0, "max": 99, "optional": true, "omit_zero": true,
		}))
	fields.append(f("equipment.affixes", "词条列表", "struct_list", "词条", {
		"item_fields": [
			{"key": "id", "label": "词条", "kind": "enum", "enum_values": Array(ContentDbScript.VALID_AFFIX_IDS).duplicate()},
			{"key": "value", "label": "数值", "kind": "int", "min": 1, "max": 99},
		],
	}))
	return fields


static func item_consumable_fields() -> Array:
	return [
		f("consumable.type", "效果类型", "enum", "效果", {"enum_values": Array(CONSUMABLE_PARAMS.keys()).duplicate(), "shape": true}),
	]


## 物品子型判定：按 equipment/consumable/tags 判，与数据约定一致。
static func item_kind(item_data: Dictionary) -> String:
	if item_data.has("equipment"):
		if String(item_data["equipment"].get("slot", "")) == "weapon":
			return "item_weapon"
		return "item_gear"
	if item_data.has("consumable"):
		return "item_consumable"
	return "item_material"


# ---- 路径读写（点路径，只走字典层；数组由 struct_list 直接操作） ----

static func read_path(source: Dictionary, path: String):
	var node: Dictionary = source
	var parts := path.split(".")
	for i in range(parts.size() - 1):
		if not node.has(parts[i]) or not (node[parts[i]] is Dictionary):
			return null
		node = node[parts[i]]
	return node.get(parts[parts.size() - 1])


static func has_path(source: Dictionary, path: String) -> bool:
	var node: Dictionary = source
	var parts := path.split(".")
	for i in range(parts.size() - 1):
		if not node.has(parts[i]) or not (node[parts[i]] is Dictionary):
			return false
		node = node[parts[i]]
	return node.has(parts[parts.size() - 1])


static func write_path(target: Dictionary, path: String, value) -> void:
	var node: Dictionary = target
	var parts := path.split(".")
	for i in range(parts.size() - 1):
		if not node.has(parts[i]):
			node[parts[i]] = {}
		node = node[parts[i]]
	node[parts[parts.size() - 1]] = value


static func erase_path(target: Dictionary, path: String) -> void:
	var node: Dictionary = target
	var parts := path.split(".")
	for i in range(parts.size() - 1):
		if not node.has(parts[i]) or not (node[parts[i]] is Dictionary):
			return
		node = node[parts[i]]
	node.erase(parts[parts.size() - 1])


# ---- 显示辅助 ----

static func enum_label(value: String) -> String:
	return String(ENUM_LABELS.get(value, value))


## 实体显示名（zh_CN 优先）。
static func display_name(entity: Dictionary) -> String:
	var name_value = entity.get("name", "")
	if name_value is Dictionary:
		return String(name_value.get("zh_CN", name_value.values()[0] if name_value.size() > 0 else ""))
	return String(name_value)


static func valid_id(candidate: String) -> bool:
	if candidate.is_empty() or not (candidate[0] >= "a" and candidate[0] <= "z"):
		return false
	for c in candidate:
		var is_lower := c >= "a" and c <= "z"
		var is_digit := c >= "0" and c <= "9"
		if not (is_lower or is_digit or c == "_"):
			return false
	return true


# ---- 跨文件引用扫描（删除守卫） ----

## 返回所有引用该 id 的位置说明；空 = 无引用，可安全删除。
static func find_references(all_data: Dictionary, entity_id: String) -> PackedStringArray:
	var refs := PackedStringArray()
	var spawn: Dictionary = all_data.get("spawn_tables", {})
	for entry in spawn.get("monsters", []):
		if String(entry.get("id", "")) == entity_id:
			refs.append("投放表(monsters) 难度 %s-%s" % [entry.get("min_difficulty", "?"), entry.get("max_difficulty", "∞")])
	for entry in spawn.get("items", []):
		if String(entry.get("id", "")) == entity_id:
			refs.append("投放表(items) 难度 %s-%s" % [entry.get("min_difficulty", "?"), entry.get("max_difficulty", "∞")])
	var crafting: Dictionary = all_data.get("crafting", {})
	for recipe in crafting.get("recipes", []):
		if String(recipe.get("output", {}).get("id", "")) == entity_id:
			refs.append("配方 %s 的产物" % recipe.get("id", "?"))
		for input_entry in recipe.get("inputs", []):
			if String(input_entry.get("id", "")) == entity_id:
				refs.append("配方 %s 的原料" % recipe.get("id", "?"))
	for tag in crafting.get("drops", {}):
		if String(crafting["drops"][tag].get("id", "")) == entity_id:
			refs.append("材料掉落[%s] 的产物" % tag)
	var skills: Dictionary = all_data.get("skills", {})
	for sid in skills:
		if String(sid).begins_with("_"):
			continue
		var sdef: Dictionary = skills[sid]
		if String(sdef.get("class", "")) == entity_id:
			refs.append("技能 %s 属于该职业" % sid)
		for req in sdef.get("requires", []):
			if String(req) == entity_id:
				refs.append("技能 %s 的前置" % sid)
	return refs


# ---- 切换清理（shape 字段变更后保持数据结构合法） ----

## 技能/消耗品效果类型切换：丢弃新参数表不认识的键（嵌套子字典同样清理）。
static func normalize_effect_params(entity: Dictionary, prefix: String) -> void:
	var block: Dictionary = entity.get(prefix, {})
	var eff_type := String(block.get("type", ""))
	var params: Array = (EFFECT_PARAMS if prefix == "effect" else CONSUMABLE_PARAMS).get(eff_type, [])
	var allowed := {"type": true}
	var allowed_sub := {}
	for field in params:
		if String(field.get("kind", "")) == "subdict":
			allowed_sub[String(field["key"])] = true
			for child in field.get("children", []):
				allowed_sub["%s.%s" % [String(field["key"]), String(child["key"])]] = true
		else:
			allowed[String(field["key"])] = true
	var cleaned := {}
	for key in block:
		var key_text := String(key)
		if allowed_sub.has(key_text) and block[key] is Dictionary:
			var sub_cleaned := {}
			for sub_key in block[key]:
				if allowed_sub.has("%s.%s" % [key_text, String(sub_key)]):
					sub_cleaned[sub_key] = block[key][sub_key]
			if not sub_cleaned.is_empty():
				cleaned[key] = sub_cleaned
		elif allowed.has(key_text):
			cleaned[key] = block[key]
	entity[prefix] = cleaned


## 装备槽切换：武器不带 bonuses/affixes、非武器不带 damage（与 ContentDb 校验一致）。
static func normalize_item_equipment(item: Dictionary) -> void:
	if not item.has("equipment"):
		return
	var gear: Dictionary = item["equipment"]
	if String(gear.get("slot", "")) == "weapon":
		gear.erase("bonuses")
		gear.erase("affixes")
		if not gear.has("damage"):
			gear["damage"] = {"physical": 3}
	else:
		gear.erase("damage")
		if not gear.has("bonuses"):
			gear["bonuses"] = {}
		if not gear.has("affixes"):
			gear["affixes"] = []


# ---- 新建模板 ----

## 最小合法新实体；ctx 可携带上下文（技能需 class_id）。
static func new_entity_template(entity_type: String, ctx := {}) -> Dictionary:
	var blank_name := {"zh_CN": "", "en_US": ""}
	match entity_type:
		"monster":
			return {
				"name": {"zh_CN": "新异兽", "en_US": "New Beast"},
				"char": "?", "color": [200, 200, 200], "tags": ["shanhaijing"],
				"lore": blank_name.duplicate(),
				"components": {
					"fighter": {"hp": 10, "power": 3, "defense": 0, "xp_reward": 20},
					"ai": {"type": "hostile"},
				},
				"element": "", "attack_tags": [],
			}
		"class":
			return {
				"name": {"zh_CN": "新职业", "en_US": ""}, "desc": blank_name.duplicate(),
				"hp": 30, "power": 5, "defense": 1, "mp": 10, "sp": 8,
			}
		"skill":
			return {
				"class": ctx.get("class_id", ""), "slot": ctx.get("slot", 1),
				"name": {"zh_CN": "新技能", "en_US": ""}, "desc": blank_name.duplicate(),
				"tags": [], "mp": 4, "cost": 1, "requires": [],
				"effect": {"type": "damage_nearest", "power": 5, "scale": 1.5, "hits": 1},
			}
		"item_weapon":
			return _item_blank({
				"tier": 1, "equipment": {"slot": "weapon", "damage": {"physical": 3}},
			})
		"item_gear":
			return _item_blank({
				"tier": 1, "equipment": {"slot": "armor", "bonuses": {"defense": 1}, "affixes": []},
			})
		"item_consumable":
			return _item_blank({
				"consumable": {"type": "heal", "amount": 10},
			})
		"item_material":
			return _item_blank({"tags": ["material"]})
	return {}


static func _item_blank(extra: Dictionary) -> Dictionary:
	var base := {
		"name": {"zh_CN": "新物品", "en_US": ""}, "char": "\"",
		"color": [200, 200, 200], "tags": [], "lore": {"zh_CN": "", "en_US": ""},
	}
	base.merge(extra, true)
	return base
