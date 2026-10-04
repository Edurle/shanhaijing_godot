class_name EffectBuffDefense
extends SkillEffect
## 防御增益（fighter.buffs["defense"]）。

const TYPE := "buff_defense"


func perform(engine, actor: Actor, skill: Dictionary, _target = null) -> String:
	var eff: Dictionary = skill["effect"]
	actor.fighter.apply_buff("defense", int(eff["amount"]), int(eff["turns"]))
	engine.emit_event("buff", actor.x, actor.y, {})
	engine.log_message(engine.content.text("cast_buff_defense").format({
		"skill": engine.content.localize(skill["name"]), "amount": int(eff["amount"]), "turns": int(eff["turns"]),
	}), "buff")
	return ""
