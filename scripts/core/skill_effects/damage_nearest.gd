class_name EffectDamageNearest
extends SkillEffect
## 单体伤害：瞄准指定目标，可多段（hits）、附 DOT/破甲/挫锐/缠绕/震退。

const TYPE := "damage_nearest"


func _init() -> void:
	needs_target = true


func perform(engine, actor: Actor, skill: Dictionary, target = null) -> String:
	if target == null:
		return "need_target"
	var eff: Dictionary = skill["effect"]
	var damage := Skills.compute_damage(actor, skill)
	var hits := int(eff.get("hits", 1))
	for _i in range(hits):
		if not target.is_alive():
			break
		engine.hit_actor(actor, target, damage, skill)
	if not target.is_alive():
		return ""
	engine.log_hit_message(actor, target, skill, damage, hits)
	if eff.has("dot"):
		var d: Dictionary = eff["dot"]
		Skills.apply_skill_dot(engine, actor, target, skill, [int(d["damage"]), int(d["turns"])])
	Skills.apply_attached_controls(engine, actor, target, skill)
	return ""
