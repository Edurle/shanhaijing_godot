class_name AIAllied
extends RefCounted
## 契约兽 AI——Python 版 ai.py AlliedAI 的移植：追击最近异兽，无敌待命。

var perception := 8
var owner: Actor


func _init(p_perception := 8) -> void:
	perception = p_perception


func hostile_target(engine) -> Actor:
	var best: Actor = null
	var best_d := 0.0
	for actor in engine.map().actors:
		if actor.team == owner.team or not actor.is_alive():
			continue
		if not engine.map().is_visible(actor.x, actor.y):
			continue
		var distance := owner.distance_to(actor)
		if distance > perception:
			continue
		if best == null or distance < best_d:
			best = actor
			best_d = distance
	return best


func perform(engine) -> void:
	var target := hostile_target(engine)
	if target == null:
		return
	var dx := signi(target.x - owner.x)
	var dy := signi(target.y - owner.y)
	if maxi(absi(dx), absi(dy)) <= 1:
		engine.melee_attack(owner, target)
		return
	var step = AIHostile.new(perception).path_step(engine, Vector2i(target.x, target.y))
	if step == Vector2i(-1, -1):
		return
	var map = engine.map()
	if step == Vector2i(target.x, target.y):
		engine.melee_attack(owner, target)
		return
	if map.actor_at(step.x, step.y) != null:
		return
	engine.move_actor(owner, step.x - owner.x, step.y - owner.y)
