class_name EffectHealSelf
extends SkillEffect
## 自疗：可附小 AOE 伤害（青丘仙泽）。

const TYPE := "heal_self"


func perform(engine, actor: Actor, skill: Dictionary, _target = null) -> String:
	var eff: Dictionary = skill["effect"]
	var amount: float = float(eff.get("amount", 0)) + Skills.skill_level(actor) * float(eff.get("scale", 0))
	if actor.equipment != null:
		amount += actor.equipment.affix("heal_power")
	var healed := actor.fighter.heal(int(round(amount)))
	engine.emit_event("heal", actor.x, actor.y, {"amount": healed})
	engine.log_message(engine.content.text("cast_heal").format({
		"skill": engine.content.localize(skill["name"]), "amount": healed,
	}), "heal")
	if eff.has("aoe_radius") and eff.has("aoe_power"):
		var radius := float(eff["aoe_radius"])
		for enemy in engine.aoe_targets(actor, radius):
			engine.hit_actor(actor, enemy, int(eff["aoe_power"]), skill)
	return ""
