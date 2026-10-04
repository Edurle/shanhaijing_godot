class_name EffectStunAoe
extends SkillEffect
## AOE 眩晕（可带伤害：power>0）；水系 tag 表现为冰封视觉。

const TYPE := "stun_aoe"


func perform(engine, actor: Actor, skill: Dictionary, _target = null) -> String:
	var eff: Dictionary = skill["effect"]
	var targets: Array = engine.aoe_targets(actor, float(eff.get("radius", 1)))
	if targets.is_empty():
		return engine.content.text("no_enemy_sight")
	engine.emit_event("aoe_ring", actor.x, actor.y, {"radius": eff.get("radius", 1)})
	var damage := Skills.compute_damage(actor, skill) if float(eff.get("power", 0)) > 0 else 0
	var landed := 0
	for enemy in targets:
		if damage > 0:
			engine.hit_actor(actor, enemy, damage, skill)
		if enemy.is_alive():
			if enemy.fighter.apply_stun(int(eff.get("turns", 1)), engine.state.rng):
				landed += 1
				if skill.get("tags", []).has("water"):
					engine.emit_event("freeze", enemy.x, enemy.y, {})
				else:
					engine.emit_event("stun", enemy.x, enemy.y, {})
			else:
				Skills.log_status_resisted(engine, enemy, "stun")
	engine.log_message(engine.content.text("cast_stun").format({
		"skill": engine.content.localize(skill["name"]), "count": landed,
	}), "combat")
	return ""
