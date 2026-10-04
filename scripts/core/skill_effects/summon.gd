class_name EffectSummon
extends SkillEffect
## 召唤契约兽：玩家近旁空位生成（时限由引擎递减，力竭化光消散）。

const TYPE := "summon"


func perform(engine, actor: Actor, skill: Dictionary, _target = null) -> String:
	var eff: Dictionary = skill["effect"]
	var spot := _free_spot(engine, actor)
	if spot == Vector2i(-1, -1):
		return engine.content.text("no_enemy_sight")
	var beast := Actor.new(spot.x, spot.y, engine.content.localize(eff.get("beast_name", {"zh_CN": "灵兽"})))
	beast.team = "player"
	beast.fighter = Fighter.new(
		int(eff.get("beast_hp", 8)), int(eff.get("beast_power", 4)), 0, 0
	)
	beast.fighter.owner = beast
	beast.ai = AIAllied.new()
	beast.ai.owner = beast
	beast.summon_ttl = int(eff.get("duration", 15))
	engine.map().actors.append(beast)
	engine.emit_event("summon", spot.x, spot.y, {})
	engine.log_message(engine.content.text("cast_summon").format({
		"skill": engine.content.localize(skill["name"]), "beast": beast.label,
	}), "summon")
	return ""


static func _free_spot(engine, actor: Actor) -> Vector2i:
	var map = engine.map()
	for radius in [1, 2]:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx == 0 and dy == 0:
					continue
				var x: int = actor.x + dx
				var y: int = actor.y + dy
				if map.in_bounds(x, y) and map.is_walkable(x, y) and map.actor_at(x, y) == null:
					return Vector2i(x, y)
	return Vector2i(-1, -1)
