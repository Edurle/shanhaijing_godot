class_name EffectTeleportStep
extends SkillEffect
## 位移：沿指定八向掠出 range 格（遇阻即停）。缠绕不影响瞬移（闪现挣断）。

const TYPE := "teleport_step"


func _init() -> void:
	needs_direction = true


func perform(engine, actor: Actor, skill: Dictionary, target = null) -> String:
	if target == null:
		return "need_direction"
	var delta: Vector2i = target
	var eff: Dictionary = skill["effect"]
	var rng := int(eff.get("range", 3))
	var last := Vector2i(actor.x, actor.y)
	for step in range(1, rng + 1):
		var nx: int = actor.x + delta.x * step
		var ny: int = actor.y + delta.y * step
		if not engine.map().in_bounds(nx, ny):
			break
		if not engine.map().is_walkable(nx, ny):
			break
		if engine.map().actor_at(nx, ny) != null:
			break
		last = Vector2i(nx, ny)
	if last == Vector2i(actor.x, actor.y):
		return engine.content.text("no_enemy_sight")  # 此方向无处可去
	engine.emit_event("trail", actor.x, actor.y, {"to_x": last.x, "to_y": last.y})
	actor.x = last.x
	actor.y = last.y
	engine.log_message(engine.content.text("cast_teleport").format({
		"skill": engine.content.localize(skill["name"]), "range": rng,
	}), "buff")
	engine.update_fov()
	return ""
