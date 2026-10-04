class_name EffectMpRestore
extends SkillEffect
## 回真气。

const TYPE := "mp_restore"


func perform(engine, actor: Actor, skill: Dictionary, _target = null) -> String:
	if actor.fighter.mp() >= actor.fighter.max_mp():
		return engine.content.text("mp_full")
	var eff: Dictionary = skill["effect"]
	var restored := actor.fighter.restore_mp(int(eff.get("amount", 0)))
	engine.emit_event("mp", actor.x, actor.y, {"amount": restored})
	engine.log_message(engine.content.text("cast_mp").format({
		"skill": engine.content.localize(skill["name"]), "amount": restored,
	}), "heal")
	return ""
