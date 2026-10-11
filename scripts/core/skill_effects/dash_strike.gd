class_name EffectDashStrike
extends SkillEffect
## 冲锋斩：沿指定方向冲出至多 range 格，撞上首个敌对单位则停于其前并出剑（伤 power+scale）；
## 一路无敌则停在最后可走格（纯位移）；贴身有敌亦可发动（原地出剑）。冲程不吃等级成长（只涨伤害）。

const TYPE := "dash_strike"


func _init() -> void:
	needs_direction = true


func perform(engine, actor: Actor, skill: Dictionary, target = null) -> String:
	if target == null:
		return "need_direction"
	var delta: Vector2i = target
	var eff: Dictionary = skill["effect"]
	var reach := int(eff.get("range", 3))
	var start := Vector2i(actor.x, actor.y)
	var last := start
	var victim = null
	for step in range(1, reach + 1):
		var nx: int = actor.x + delta.x * step
		var ny: int = actor.y + delta.y * step
		if not engine.map().in_bounds(nx, ny):
			break
		if not engine.map().is_walkable(nx, ny):
			break
		var blocker = engine.map().actor_at(nx, ny)
		if blocker != null:
			# 撞上敌对单位：停在其前一格出剑；同伴/召唤兽占位则截停
			if blocker.is_alive() and blocker.team != actor.team:
				victim = blocker
			break
		last = Vector2i(nx, ny)
	if last != start:
		engine.emit_event("trail", actor.x, actor.y, {"to_x": last.x, "to_y": last.y})
		actor.x = last.x
		actor.y = last.y
		engine.update_fov()
	if victim == null:
		if last == start:
			return engine.content.text("dash_blocked")  # 起步即被堵死
		engine.log_message(engine.content.text("cast_dash").format({
			"skill": engine.content.localize(skill["name"]),
		}), "buff")
		return ""
	var damage := Skills.compute_damage(actor, skill)
	engine.hit_actor(actor, victim, damage, skill)
	if victim.is_alive():
		engine.log_hit_message(actor, victim, skill, damage, 1)
	return ""
