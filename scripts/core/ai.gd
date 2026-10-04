class_name AIHostile
extends RefCounted
## 敌怪 AI——Python 版 ai.py HostileEnemy 的移植（警觉状态机）。
## 待命 → 追击（含目击记忆）→ 回巢；循声与受击皆可唤醒；离巢 leash 收心。

const CHASE_MEMORY_TURNS := 6
const LEASH_DISTANCE := 12.0
const STATE_IDLE := "idle"
const STATE_HUNTING := "hunting"
const STATE_RETURNING := "returning"

var perception := 6
var owner: Actor
var state := STATE_IDLE
var home := Vector2i(-1, -1)
var last_seen := Vector2i(-1, -1)
var chase_memory := 0


func _init(p_perception := 6) -> void:
	perception = p_perception


# ---- 唤醒入口（引擎侧调用） ----

## 循声：朝声源搜索；已在追击中不覆盖既有线索。
func hear_noise(engine, x: int, y: int) -> void:
	if state == STATE_HUNTING:
		return
	_alert(Vector2i(x, y))
	engine.emit_event("notice", owner.x, owner.y, {"char": "?"})


## 受击唤醒：就地扎根，朝伤害来向搜索。
func on_hurt(engine) -> void:
	home = Vector2i(owner.x, owner.y)
	_alert(Vector2i(engine.player().x, engine.player().y))


func _alert(target_xy: Vector2i) -> void:
	state = STATE_HUNTING
	last_seen = target_xy
	chase_memory = CHASE_MEMORY_TURNS


# ---- 回合行为 ----

func perform(engine) -> void:
	if home.x < 0:
		home = Vector2i(owner.x, owner.y)
	var target := hostile_target(engine)
	if target != null:
		if state == STATE_IDLE:
			engine.emit_event("notice", owner.x, owner.y, {"char": "!"})
		_alert(Vector2i(target.x, target.y))
		if Vector2(owner.x - home.x, owner.y - home.y).length() > LEASH_DISTANCE:
			state = STATE_RETURNING  # 离巢过远：纵然看见也收心回巢
			return
		if _try_skills(engine, target):
			return  # 已施法：本回合到此为止
		_step_to(engine, Vector2i(target.x, target.y), true)
		return
	if state == STATE_HUNTING:
		chase_memory -= 1
		if chase_memory <= 0 or Vector2i(owner.x, owner.y) == last_seen:
			state = STATE_RETURNING  # 线索耗尽/扑空：回巢
		elif last_seen.x >= 0:
			_step_to(engine, last_seen, false)
		return
	if state == STATE_RETURNING:
		if Vector2i(owner.x, owner.y) == home:
			state = STATE_IDLE
			return
		_step_to(engine, home, false)


## 依绑定顺序尝试技能（monsters.json skills）：冷却就绪 + 意愿门控 → 施法。
## 任一成功即返回 true（消耗本回合）；全败回落移动/普攻。
func _try_skills(engine, target: Actor) -> bool:
	if owner.skill_ids.is_empty():
		return false
	for sid in owner.skill_ids:
		var id_text := String(sid)
		if int(owner.skill_cooldowns.get(id_text, 0)) > 0:
			continue
		var skill: Dictionary = engine.content.skill_by_id(id_text)
		if skill.is_empty():
			continue
		if not _wants_cast(skill, target):
			continue
		if Skills.cast(engine, owner, skill, target).is_empty():
			engine.log_message(engine.content.text("monster_cast").format({
				"actor": owner.label,
				"skill": engine.content.localize(skill["name"]),
			}), "combat")
			return true
	return false


## 施法意愿门控：方向技能 AI 不用；自愈仅半血以下；cast_range 距离限制（缺省=感知半径）。
func _wants_cast(skill: Dictionary, target: Actor) -> bool:
	var effect_type := String(skill.get("effect", {}).get("type", ""))
	if Skills.effect_flags(effect_type).get("needs_direction", false):
		return false
	if effect_type == "heal_self" and owner.fighter.hp() > owner.fighter.max_hp() * 0.5:
		return false
	var cast_range: int = int(skill.get("cast_range", 0))
	if cast_range <= 0:
		cast_range = perception
	return owner.distance_to(target) <= cast_range


## 感知半径内、视线通畅的最近敌对存活 actor。
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
		# 烟障蔽目：贴身（≤1.5 格）之外的玩家不可感知
		if actor == engine.player() and engine.smoke_turns > 0 and distance > 1.5:
			continue
		if best == null or distance < best_d:
			best = actor
			best_d = distance
	return best


func _step_to(engine, dest: Vector2i, melee: bool) -> void:
	var step := path_step(engine, dest)
	if step == Vector2i(-1, -1):
		return  # 无路可走，待命
	if melee and step == dest:
		var victim = engine.map().actor_at(step.x, step.y)
		if victim != null and victim.team != owner.team:
			engine.melee_attack(owner, victim)
			return
	if engine.map().actor_at(step.x, step.y) != null:
		return  # 前路被同伴占据，等待
	engine.move_actor(owner, step.x - owner.x, step.y - owner.y)


## BFS 寻路下一格（限 400 展开防止大图全扫）；无路返回 (-1,-1)。
func path_step(engine, dest: Vector2i) -> Vector2i:
	var map = engine.map()
	if not map.in_bounds(dest.x, dest.y):
		return Vector2i(-1, -1)
	var came_from := {}
	var start := Vector2i(owner.x, owner.y)
	var queue: Array = [start]
	came_from[start] = start
	var expansions := 0
	while not queue.is_empty() and expansions < 400:
		expansions += 1
		var cell: Vector2i = queue.pop_front()
		if cell == dest:
			break
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nxt := Vector2i(cell.x + dx, cell.y + dy)
				if not map.in_bounds(nxt.x, nxt.y) or came_from.has(nxt):
					continue
				if not map.is_walkable(nxt.x, nxt.y):
					continue
				if map.actor_at(nxt.x, nxt.y) != null and nxt != dest:
					continue  # 同伴占位（目标格除外——melee 用）
				came_from[nxt] = cell
				queue.append(nxt)
	if not came_from.has(dest):
		return Vector2i(-1, -1)
	# 回溯到起点后一格
	var cur := dest
	while came_from[cur] != start:
		cur = came_from[cur]
		if cur == start:
			break
	return cur if cur != start else Vector2i(-1, -1)
