class_name EffectDamageAoeSelf
extends SkillEffect
## 以自身为中心的 AOE：可附 DOT/破甲/挫锐/缠绕/震退/冰封(水系眩晕)。

const TYPE := "damage_aoe_self"


func perform(engine, actor: Actor, skill: Dictionary, _target = null) -> String:
	var eff: Dictionary = skill["effect"]
	var targets: Array = engine.aoe_targets(actor, float(eff.get("radius", 1)))
	if targets.is_empty():
		return engine.content.text("no_enemy_sight")
	var damage := Skills.compute_damage(actor, skill)
	engine.emit_event("aoe_ring", actor.x, actor.y, {"radius": eff.get("radius", 1)})
	for enemy in targets:
		engine.hit_actor(actor, enemy, damage, skill)
		if not enemy.is_alive():
			continue
		if eff.has("dot"):
			var d: Dictionary = eff["dot"]
			Skills.apply_skill_dot(engine, actor, enemy, skill, [int(d["damage"]), int(d["turns"])])
		Skills.apply_attached_controls(engine, actor, enemy, skill)
		if eff.has("stun"):
			enemy.fighter.apply_stun(int(eff["stun"]))
			if skill.get("tags", []).has("water"):
				engine.emit_event("freeze", enemy.x, enemy.y, {})
			else:
				engine.emit_event("stun", enemy.x, enemy.y, {})
	engine.log_message(engine.content.text("cast_aoe").format({
		"skill": engine.content.localize(skill["name"]), "count": targets.size(),
	}), "combat")
	return ""
