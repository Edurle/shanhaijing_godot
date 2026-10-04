class_name Skills
extends RefCounted
## 技能系统——Python 版 skills.py 的移植：效果类注册表 + 统一施放入口。
## 伤害公式：power + 修为等级 × scale + 装备词条加成（按技能 tags 匹配五行）。
## 无异常机制：cast/perform 返回错误串（空 = 成功），"need_target"/"need_direction"
## 为控制流信号由调用方（引擎/输入层）接管。

# 技能 tag -> 装备词条 id（五行各一条元素加伤）
const TAG_AFFIX_MAP := {
	"metal": "metal_damage", "wood": "wood_damage", "water": "water_damage",
	"fire": "fire_damage", "earth": "earth_damage",
	"aoe": "aoe_damage", "heal": "heal_power",
}
# 效果强度字段（等级成长 +20%/级，只放大强度不变结构）
const GROWTH_FIELDS: PackedStringArray = [
	"power", "scale", "damage", "amount", "aoe_power", "beast_hp", "beast_power", "duration",
]
const SKILL_MAX_LEVEL := 10
const LEVEL_GROWTH := 0.2

static var EFFECTS := {}  # type -> SkillEffect 单例（首次使用时注册）


static func _ensure_registry() -> void:
	if not EFFECTS.is_empty():
		return
	for script in [
		preload("res://scripts/core/skill_effects/damage_nearest.gd"),
		preload("res://scripts/core/skill_effects/damage_aoe_self.gd"),
		preload("res://scripts/core/skill_effects/buff_defense.gd"),
		preload("res://scripts/core/skill_effects/buff_power.gd"),
		preload("res://scripts/core/skill_effects/teleport_step.gd"),
		preload("res://scripts/core/skill_effects/heal_self.gd"),
		preload("res://scripts/core/skill_effects/element_dot.gd"),
		preload("res://scripts/core/skill_effects/summon.gd"),
		preload("res://scripts/core/skill_effects/stun_aoe.gd"),
		preload("res://scripts/core/skill_effects/knockback_aoe.gd"),
		preload("res://scripts/core/skill_effects/mp_restore.gd"),
	]:
		var effect = script.new()
		EFFECTS[effect.TYPE] = effect


# ---- 数值 ----

static func skill_element(skill: Dictionary) -> String:
	## 技能的主五行：tags 中第一个五行 tag（数据排列顺序即主元素）。
	for t in skill.get("tags", []):
		if ContentDb.ELEMENTS.has(t):
			return String(t)
	return ""


static func skill_level(actor: Actor) -> int:
	return actor.level.current_level if actor.level != null else 1


static func affix_bonus(actor: Actor, skill: Dictionary, extra_tags: Array = []) -> int:
	var equip = actor.equipment
	if equip == null:
		return 0
	var tags: Array = skill.get("tags", []) + extra_tags
	var total := 0
	for tag in TAG_AFFIX_MAP:
		if tags.has(tag):
			total += equip.affix(TAG_AFFIX_MAP[tag])
	return total


## 技能直伤：power + 等级×scale + 词条加成。
static func compute_damage(actor: Actor, skill: Dictionary) -> int:
	var eff: Dictionary = skill["effect"]
	var raw: float = float(eff.get("power", 0)) + skill_level(actor) * float(eff.get("scale", 0))
	raw += affix_bonus(actor, skill)
	return maxi(0, int(round(raw)))


## 元素 DOT：(每回合伤害, 回合数)，伤害吃 power/scale + 元素加伤词条。
static func compute_dot(actor: Actor, skill: Dictionary) -> Array:
	var eff: Dictionary = skill["effect"]
	var raw: float = float(eff.get("damage", 0)) + skill_level(actor) * float(eff.get("scale", 0))
	raw += affix_bonus(actor, skill)
	return [maxi(0, int(round(raw))), int(eff.get("turns", 0))]


## 耗气：装备「耗气-N」词条减免，减免后最低 1；0 耗技能保持 0。
static func mp_cost(actor: Actor, skill: Dictionary) -> int:
	var base := int(skill.get("mp", 0))
	if base <= 0:
		return 0
	var reduce := actor.equipment.affix("mp_cost_reduce") if actor.equipment != null else 0
	return maxi(1, base - reduce)


## 耗灵力：暂无减免词条。
static func sp_cost(_actor: Actor, skill: Dictionary) -> int:
	return maxi(0, int(skill.get("sp", 0)))


## 按技能等级缩放效果强度字段（deep-copy 后处理，mp/radius/turns 等不变）。
static func skill_effect_scaled(skill: Dictionary, level: int) -> Dictionary:
	if level <= 1:
		return skill
	var mult := 1.0 + LEVEL_GROWTH * (level - 1)
	var scaled: Dictionary = skill.duplicate(true)
	scaled["effect"] = _walk_scale(skill["effect"], mult)
	return scaled


static func _walk_scale(node, mult: float):
	if node is Dictionary:
		var out := {}
		for key in node:
			if GROWTH_FIELDS.has(key) and node[key] is float:
				out[key] = maxi(1, int(round(node[key] * mult)))
			else:
				out[key] = _walk_scale(node[key], mult)
		return out
	if node is Array:
		var arr: Array = []
		for item in node:
			arr.append(_walk_scale(item, mult))
		return arr
	return node


# ---- 施放 ----

## 统一入口：真气/灵力/气血检查 → 效果执行（按技能等级缩放）→ 扣耗。
## 返回错误串（空 = 成功）；"need_target"/"need_direction" 为控制流信号。
static func cast(engine, actor: Actor, skill: Dictionary, target = null) -> String:
	_ensure_registry()
	var cost := mp_cost(actor, skill)
	if actor.fighter.mp() < cost:
		return engine.content.text("mp_low")
	var spirit := sp_cost(actor, skill)
	if actor.fighter.sp() < spirit:
		return engine.content.text("sp_low")
	var hp_cost := int(skill["effect"].get("hp_cost", 0))
	if hp_cost > 0 and actor.fighter.hp() <= hp_cost:
		return engine.content.text("hp_low")
	var level := int(actor.skill_levels.get(skill.get("id", ""), 1))
	var error: String = EFFECTS[skill["effect"]["type"]].perform(engine, actor, skill_effect_scaled(skill, level), target)
	if not error.is_empty():
		return error
	actor.fighter.spend_mp(cost)
	actor.fighter.spend_sp(spirit)
	if hp_cost > 0:
		actor.fighter.hurt(hp_cost)
		engine.emit_event("hit", actor.x, actor.y, {"amount": hp_cost, "victim": "self"})
	return ""


# ---- 公共结算（效果类与引擎共用） ----

## 按技能主五行施加 DOT（override = 直传 [伤害, 回合]，跳过等级/词条折算）。
static func apply_skill_dot(engine, actor: Actor, target: Actor, skill: Dictionary, override: Array = []) -> Array:
	var kind := skill_element(skill)
	if kind == "":
		return [0, 0]
	var pair := override if not override.is_empty() else compute_dot(actor, skill)
	var damage: int = pair[0]
	var turns: int = pair[1]
	if damage > 0 and turns > 0:
		target.fighter.apply_dot(kind, damage, turns)
		engine.emit_event("dot_mark", target.x, target.y, {"kind": kind})
	return pair


## 伤害技能的附带控制：破甲(金)/挫锐(火)/缠绕(木)/震退(土)。
static func apply_attached_controls(engine, caster: Actor, actor: Actor, skill: Dictionary) -> void:
	var eff: Dictionary = skill["effect"]
	if eff.has("sunder"):
		var cfg: Dictionary = eff["sunder"]
		var amount := int(cfg["amount"])
		var turns := int(cfg["turns"])
		actor.fighter.apply_buff("defense", -amount, turns)
		engine.emit_event("sunder", actor.x, actor.y, {})
		engine.log(engine.content.text("sunder_note").format({"name": actor.label, "amount": amount, "turns": turns}), "combat")
	if eff.has("daunt"):
		var cfg: Dictionary = eff["daunt"]
		var amount := int(cfg["amount"])
		var turns := int(cfg["turns"])
		actor.fighter.apply_buff("power", -amount, turns)
		engine.emit_event("daunt", actor.x, actor.y, {})
		engine.log(engine.content.text("daunt_note").format({"name": actor.label, "amount": amount, "turns": turns}), "combat")
	if eff.has("root"):
		actor.fighter.apply_root(int(eff["root"]))
		engine.emit_event("root", actor.x, actor.y, {})
		engine.log(engine.content.text("root_note").format({"name": actor.label}), "combat")
	if eff.has("knockback"):
		var dx := signi(actor.x - caster.x)
		var dy := signi(actor.y - caster.y)
		if engine.push_actor(actor, dx, dy, int(eff["knockback"])) > 0:
			engine.log(engine.content.text("knockback_note").format({"name": actor.label}), "combat")


## 技能效果短摘要（侧栏用）；伤害按当前修为与装备词条折算。
static func summary(engine, actor: Actor, skill: Dictionary) -> String:
	var eff: Dictionary = skill["effect"]
	var etype := String(eff.get("type", ""))
	if etype == "damage_nearest":
		return engine.content.text("summ_damage").format({"v": compute_damage(actor, skill)})
	if etype == "damage_aoe_self":
		return engine.content.text("summ_aoe").format({"v": compute_damage(actor, skill), "r": eff.get("radius", 1)})
	if etype == "heal_self":
		var amount: float = float(eff.get("amount", 0)) + skill_level(actor) * float(eff.get("scale", 0))
		return engine.content.text("summ_heal").format({"v": int(round(amount))})
	if etype == "mp_restore":
		return engine.content.text("summ_heal_mp").format({"v": int(eff.get("amount", 0))})
	if etype == "buff_defense":
		return engine.content.text("summ_buff_def").format({"v": int(eff.get("amount", 0))})
	if etype == "buff_power":
		return engine.content.text("summ_buff_pow").format({"v": int(eff.get("amount", 0))})
	if etype == "teleport_step":
		return engine.content.text("summ_teleport").format({"v": int(eff.get("range", 3))})
	if etype == "element_dot":
		var pair := compute_dot(actor, skill)
		var kind := skill_element(skill)
		kind = kind if kind != "" else "wood"
		return engine.content.text("summ_dot").format({"state": engine.content.text("dot_name_" + kind), "v": pair[0], "t": pair[1]})
	if etype == "summon":
		return engine.content.text("summ_summon")
	if etype == "stun_aoe":
		return engine.content.text("summ_stun").format({"v": int(eff.get("turns", 1))})
	if etype == "knockback_aoe":
		return engine.content.text("summ_knockback_aoe").format({"d": int(eff.get("push", 1))})
	return ""
