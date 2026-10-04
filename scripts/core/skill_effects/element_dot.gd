class_name EffectElementDot
extends SkillEffect
## 单体元素 DOT：按技能主五行施加持续状态（裂伤/蛊毒/寒侵/灼烧/尘蚀）。

const TYPE := "element_dot"


func _init() -> void:
	needs_target = true


func perform(engine, actor: Actor, skill: Dictionary, target = null) -> String:
	if target == null:
		return "need_target"
	var kind := Skills.skill_element(skill)
	if kind == "":
		kind = "wood"
	var pair := Skills.apply_skill_dot(engine, actor, target, skill)
	engine.log_message(engine.content.text("cast_dot").format({
		"skill": engine.content.localize(skill["name"]),
		"target": target.label,
		"state": engine.content.text("dot_name_" + kind),
		"damage": pair[0], "turns": pair[1],
	}), "combat")
	return ""
