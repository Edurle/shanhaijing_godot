class_name EffectBuffPower
extends SkillEffect
## 攻击增益（fighter.buffs["power"]）。

const TYPE := "buff_power"


func perform(engine, actor: Actor, skill: Dictionary, _target = null) -> String:
	var eff: Dictionary = skill["effect"]
	actor.fighter.apply_buff("power", int(eff["amount"]), int(eff["turns"]))
	engine.emit_event("buff", actor.x, actor.y, {})
	engine.log_message(engine.content.text("cast_buff_power").format({
		"skill": engine.content.localize(skill["name"]), "amount": int(eff["amount"]), "turns": int(eff["turns"]),
	}), "buff")
	return ""
