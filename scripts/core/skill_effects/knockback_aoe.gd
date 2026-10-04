class_name EffectKnockbackAoe
extends SkillEffect
## 土系 AOE 震退：群敌沿远离施法者方向被推移（可带 power 伤害）。

const TYPE := "knockback_aoe"


func perform(engine, actor: Actor, skill: Dictionary, _target = null) -> String:
	var eff: Dictionary = skill["effect"]
	var targets: Array = engine.aoe_targets(actor, float(eff.get("radius", 1)))
	if targets.is_empty():
		return engine.content.text("no_enemy_sight")
	engine.emit_event("aoe_ring", actor.x, actor.y, {"radius": eff.get("radius", 1)})
	var damage := Skills.compute_damage(actor, skill) if float(eff.get("power", 0)) > 0 else 0
	var pushed := 0
	for enemy in targets:
		if damage > 0:
			engine.hit_actor(actor, enemy, damage, skill)
		if not enemy.is_alive():
			continue
		var dx := signi(enemy.x - actor.x)
		var dy := signi(enemy.y - actor.y)
		if engine.push_actor(enemy, dx, dy, int(eff.get("push", 1))) > 0:
			pushed += 1
	engine.log_message(engine.content.text("cast_knockback_aoe").format({
		"skill": engine.content.localize(skill["name"]), "count": pushed,
	}), "combat")
	return ""
