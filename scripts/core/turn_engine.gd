class_name TurnEngine
extends RefCounted
## 回合引擎——Python 版 engine.py 战斗部分的移植（模型层）。
## 行者动作成功 → 行者侧状态结算（DOT/buff/缠绕/契约兽）→ 敌我单位依次行动 → 刷新视野。
## events 数组是给视图层的演出清单（命中/治疗/特效位），消费后由视图清空。

const NOISE_RADIUS_MELEE := 7
const NOISE_RADIUS_SKILL := 9

var state: WorldState
var content: ContentDb
var messages: Array = []  # [{text, kind}]
var events: Array = []  # 演出事件，视图层消费
var game_over := false
var turn_count := 0
var smoke_turns := 0  # 烟障余威：期间敌怪感知不到玩家（贴身除外）
## 绑定技能入槽：未参悟的技能禁止绑定（返回错误串，成功返回 ""）。
func bind_skill(slot: int, sid: String) -> String:
	if slot < 1 or slot > 16:
		return ""
	if not player().skill_levels.has(sid):
		return content.text("not_learned")
	player().skill_bar[slot - 1] = sid
	return ""


## 按技能栏绑定施放：槽位 1-16 → player.skill_bar；未绑定/未学返回错误串。
func execute_bound_skill(slot: int, target = null) -> String:
	if game_over:
		return ""
	if slot < 1 or slot > 16:
		return ""
	var skill_id := String(player().skill_bar[slot - 1])
	if skill_id == "":
		return content.text("slot_empty_skill")
	if not player().skill_levels.has(skill_id):
		return content.text("not_learned")
	var skill: Dictionary = content.skill_by_id(skill_id)
	if target == null:
		var enemies := visible_enemies(player())
		if not enemies.is_empty():
			target = enemies[0]
	var error: String = Skills.cast(self, player(), skill, target)
	if not error.is_empty():
		return error
	end_turn()
	return ""


func _init(p_state: WorldState, p_content: ContentDb) -> void:
	state = p_state
	content = p_content
	if state.player.level != null:
		state.player.level.on_level_up = func(lv): log_message(
			content.text("level_up").format({"level": lv}), "levelup"
		)


# ---- 查询 ----

func map() -> GameMap:
	return state.current


func player() -> Actor:
	return state.player


func rng() -> RandomNumberGenerator:
	return state.rng


## 视野内敌对 actor，按距离排序（瞄准候选）。
func visible_enemies(actor: Actor) -> Array:
	var result: Array = []
	for other in map().actors:
		if other.team == actor.team or not other.is_alive():
			continue
		if map().is_visible(other.x, other.y):
			result.append(other)
	result.sort_custom(func(a, b): return actor.distance_to(a) < actor.distance_to(b))
	return result


## 以 actor 为中心、radius 半径内的敌对存活单位。
func aoe_targets(actor: Actor, radius: float) -> Array:
	var result: Array = []
	for other in map().actors:
		if other.team == actor.team or not other.is_alive():
			continue
		if Vector2(other.x - actor.x, other.y - actor.y).length() <= radius + 1e-9:
			result.append(other)
	return result


# ---- 演出与消息 ----

func log_message(text: String, kind := "info") -> void:
	messages.append({"text": text, "kind": kind})
	if messages.size() > 60:
		messages.pop_front()


func emit_event(etype: String, x: int, y: int, data: Dictionary = {}) -> void:
	events.append({"type": etype, "x": x, "y": y, "data": data})


## 战斗躁动穿墙传播：近战兵刃 vs 技能轰鸣。
func emit_noise(x: int, y: int, radius: int) -> void:
	for actor in map().actors:
		var ai = actor.ai
		if actor.is_alive() and ai is AIHostile:
			if Vector2(actor.x - x, actor.y - y).length() <= radius:
				ai.hear_noise(self, x, y)


# ---- 行者动作 ----

## 走向一格：有敌则攻击，可走则移动（缠绕被拒）；返回是否消耗回合。
func player_step(delta: Vector2i) -> bool:
	if game_over:
		return false
	var dest: Vector2i = state.player_xy() + delta
	var victim = map().actor_at(dest.x, dest.y)
	if victim != null and victim.is_alive() and victim.team != "player":
		melee_attack(player(), victim)
		end_turn()
		return true
	if not map().is_walkable(dest.x, dest.y):
		return false
	if player().fighter.rooted_turns > 0:
		log_message(content.text("root_blocked").format({"name": player().label}), "warn")
		return false
	move_actor(player(), delta.x, delta.y)
	end_turn()
	return true




# ---- 行囊与装备动作（成功即消耗回合） ----

## 拾取脚下物品。
func player_pickup() -> bool:
	var item: Dictionary = map().item_at(player().x, player().y)
	if item.is_empty():
		log_message(content.text("no_item_here"), "warn")
		return false
	map().items.erase(item)
	item["x"] = -1
	item["y"] = -1
	player().inventory.add(item)
	log_message(content.text("pickup").format({"item": item["label"]}), "loot")
	emit_event("pickup", player().x, player().y, {})
	end_turn()
	return true


## 使用消耗品。
func player_use_item(item: Dictionary) -> String:
	var error := Consumables.activate(self, item)
	if not error.is_empty():
		return error
	player().inventory.remove(item)
	end_turn()
	return ""


## 装备行囊中的一件（被顶替的旧件回行囊）。
func player_equip(item: Dictionary) -> String:
	if not item.has("slot"):
		return content.text("no_item_here")
	var replaced: Dictionary = player().equipment.equip(item)
	player().inventory.remove(item)
	if not replaced.is_empty():
		player().inventory.add(replaced)
	player().fighter.clamp_vitals()
	log_message(content.text("equip_on").format({"item": item["label"]}), "loot")
	end_turn()
	return ""


## 卸下指定槽位。
func player_unequip(slot: String) -> String:
	var item: Dictionary = player().equipment.unequip_slot(slot)
	if item.is_empty():
		return content.text("no_item_here")
	player().inventory.add(item)
	player().fighter.clamp_vitals()
	log_message(content.text("equip_off").format({"item": item["label"]}), "loot")
	end_turn()
	return ""


## 参悟/修习技能（不消耗回合）：前置 + 技能点 + 材料门槛。
func learn_skill(sid: String) -> String:
	var player_actor = player()
	if not content.skills.has(sid):
		return content.text("not_learned")
	var skill: Dictionary = content.skill_by_id(sid)
	var level := int(player_actor.skill_levels.get(sid, 0))
	if level >= Skills.SKILL_MAX_LEVEL:
		return content.text("learn_max")
	var cost := 1
	if level == 0:
		var missing: Array = []
		for req in skill.get("requires", []):
			if not player_actor.skill_levels.has(req):
				missing.append(content.localize(content.skills[req]["name"]))
		if not missing.is_empty():
			return content.text("learn_locked").format({"missing": "、".join(missing)})
		cost = int(skill.get("cost", 1))
	if player_actor.skill_points < cost:
		return content.text("learn_no_points")
	var needs := _skill_material_cost(skill, level + 1)
	var lacking: Array = []
	for pair in needs:
		var have: int = player_actor.inventory.count_material(pair[0])
		if have < pair[1]:
			lacking.append("%s×%d" % [content.localize(content.items[pair[0]]["name"]), pair[1] - have])
	if not lacking.is_empty():
		return content.text("learn_need_materials").format({"materials": "、".join(lacking)})
	player_actor.skill_points -= cost
	for pair in needs:
		player_actor.inventory.take_material(pair[0], pair[1])
	player_actor.skill_levels[sid] = level + 1
	log_message(content.text("learn_ok").format({
		"skill": content.localize(skill["name"]), "level": level + 1,
	}), "levelup")
	emit_event("levelup", player_actor.x, player_actor.y, {})
	return ""


## 修习材料门槛：大招初学耗魔核×1；5 重耗精魄×1；10 重耗精魄×1+魔核×1。
func _skill_material_cost(skill: Dictionary, target_level: int) -> Array:
	var needs: Array = []
	if target_level == 1 and int(skill.get("cost", 1)) >= 2:
		needs.append(["mat_demon_core", 1])
	if target_level == 5:
		needs.append(["mat_elite_essence", 1])
	if target_level == Skills.SKILL_MAX_LEVEL:
		needs.append(["mat_elite_essence", 1])
		needs.append(["mat_demon_core", 1])
	return needs


# ---- 战斗结算 ----

## 普攻（武器伤害）：攻 + 武器物理 − 防 + 浮动；元素来源 = attack_tags + 武器属性，整段折算。
func melee_attack(attacker: Actor, target: Actor) -> void:
	var damage: int = attacker.fighter.power() - target.fighter.defense() + state.rng.randi_range(-1, 2)
	var element_tags: Array = []
	for t in attacker.attack_tags:
		if ContentDb.ELEMENTS.has(t):
			element_tags.append(String(t))
	if attacker.equipment != null:
		var weapon = attacker.equipment.weapon_damage()
		damage += int(weapon[0])
		if ContentDb.ELEMENTS.has(weapon[1]):
			element_tags.append(String(weapon[1]))
	emit_noise(target.x, target.y, NOISE_RADIUS_MELEE)
	if element_tags.size() > 0:
		damage = target.fighter.mitigate_incoming(damage, element_tags)
	if damage > 0:
		log_message(content.text("attack_hits").format({
			"attacker": attacker.label, "target": target.label, "damage": damage,
		}), "combat")
		emit_event("hit", target.x, target.y, {"amount": damage})
		# 元素命中玩家且玩家有对应抗性：装备构筑的正反馈提示
		if target == player() and element_tags.size() > 0:
			var resisted := 0
			for t in element_tags:
				resisted = maxi(resisted, target.fighter.resistance(t))
			if resisted > 0:
				log_message(content.text("attack_element_notice").format({
					"attacker": attacker.label,
					"element": content.text("element_" + element_tags[0]),
				}), "combat_blocked")
		_apply_damage(attacker, target, damage)
	else:
		log_message(content.text("attack_blocked").format({
			"attacker": attacker.label, "target": target.label,
		}), "combat_blocked")


## 技能伤害：先按技能元素 tags 吃目标抗性+生克折算，再落伤。
func hit_actor(caster: Actor, target: Actor, damage: int, skill: Dictionary) -> void:
	var final_damage: int = target.fighter.mitigate_incoming(damage, skill.get("tags", []))
	emit_noise(target.x, target.y, NOISE_RADIUS_SKILL)
	emit_event("hit", target.x, target.y, {"amount": final_damage})
	_apply_damage(caster, target, final_damage)


func log_hit_message(actor: Actor, target: Actor, skill: Dictionary, damage: int, hits: int) -> void:
	var key := "cast_hits" if hits > 1 else "cast_hit"
	log_message(content.text(key).format({
		"skill": content.localize(skill["name"]), "hits": hits,
		"target": target.label, "damage": damage * hits,
	}), "combat")


## 落伤与死亡结算（经验/弑回血/掉落/移除）。
## 语义对齐 Python：经验与掉落跟随任何原因的异兽死亡（含 DOT）；弑回血仅玩家直接击杀。
func _apply_damage(killer: Actor, victim: Actor, damage: int) -> void:
	var ratio_before := float(victim.fighter.hp()) / maxf(1.0, victim.fighter.max_hp())
	var died := victim.fighter.hurt(damage)
	if not died:
		if victim == player() and ratio_before > 0.3 and float(player().fighter.hp()) / player().fighter.max_hp() < 0.3:
			log_message(content.text("player_hurt_warn"), "warn")  # 跨过三成线才提示
		return
	if victim == player():
		log_message(content.text("player_dies"), "death")
		game_over = true
		return
	if victim.summon_ttl >= 0:
		# 契约兽力竭：化光消散，不留尸骸不掉落
		log_message(content.text("summon_fade").format({"name": victim.label}), "summon")
		emit_event("summon", victim.x, victim.y, {})
		map().actors.erase(victim)
		victim.fighter = null
		return
	log_message(content.text("monster_dies").format({"name": victim.label}), "kill")
	emit_event("kill", victim.x, victim.y, {})
	var x := victim.x
	var y := victim.y
	# 经验：任何原因击杀异兽都归玩家（DOT/召唤兽代杀同理）
	if player().is_alive() and player().level != null:
		player().level.add_xp(victim.fighter.xp_reward, true)
	# 弑回血词条：仅玩家直接击杀（普攻/技能）
	if killer == player() and player().is_alive() and player().equipment != null:
		var heal_amount := player().equipment.affix("kill_heal")
		if heal_amount > 0:
			var healed: int = player().fighter.heal(heal_amount)
			if healed > 0:
				emit_event("heal", player().x, player().y, {"amount": healed})
	# 掉落：22% 装备（按层难度 tier 门槛）+ 按 tags 的炼材（BOSS 额外必掉魔核）
	_roll_equipment_drop(victim, x, y)
	_roll_material_drop(victim, x, y)
	map().actors.erase(victim)
	victim.fighter = null


const MONSTER_DROP_CHANCE := 0.22

func _roll_equipment_drop(victim: Actor, x: int, y: int) -> void:
	if state.rng.randf() >= MONSTER_DROP_CHANCE:
		return
	var item_id := content.random_equipment_id(map().floor_number, state.rng)
	if item_id == "":
		return
	var item: Dictionary = content.build_item(item_id, x, y)
	map().items.append(item)
	log_message(content.text("monster_drop").format({
		"monster": victim.label, "item": item["label"],
	}), "loot")


func _roll_material_drop(victim: Actor, x: int, y: int) -> void:
	var drops: Array = []
	if victim.tags.has("boss"):
		drops.append("mat_demon_core")
	var material_id := content.roll_material_drop(victim.tags, state.rng)
	if material_id != "":
		drops.append(material_id)
	for mid in drops:
		var item: Dictionary = content.build_item(mid, x, y)
		map().items.append(item)
		log_message(content.text("material_drop").format({
			"monster": victim.label, "item": item["label"],
		}), "loot")


## 击退：沿 (dx,dy) 推 actor 至多 push 格，遇墙/越界/实体截停；返回实际格数。
func push_actor(actor: Actor, dx: int, dy: int, push: int) -> int:
	var moved := 0
	var x := actor.x
	var y := actor.y
	for _i in range(push):
		var nx := x + dx
		var ny := y + dy
		if not map().in_bounds(nx, ny):
			break
		if not map().is_walkable(nx, ny):
			break
		if map().actor_at(nx, ny) != null:
			break
		x = nx
		y = ny
		moved += 1
	if moved > 0:
		emit_event("trail", actor.x, actor.y, {"to_x": x, "to_y": y})
		actor.x = x
		actor.y = y
	return moved


## 移动（怪物 AI 用；缠绕单位在此被拒，异常语义改为静默）。
func move_actor(actor: Actor, dx: int, dy: int) -> void:
	if actor.fighter != null and actor.fighter.rooted_turns > 0:
		return
	actor.x += dx
	actor.y += dy
	if actor == player():
		update_fov()


func update_fov() -> void:
	map().compute_fov(player().x, player().y)


# ---- 回合推进 ----

func end_turn() -> void:
	if game_over:
		return
	turn_count += 1
	end_player_turn()
	if not game_over:
		enemy_turns()
	update_fov()


## 行者回合结束：元素 DOT、buff 递减、缠绕递减、契约兽时限。
func end_player_turn() -> void:
	var fighter := player().fighter
	if fighter.has_dot():
		_tick_actor_dots(player())
		if game_over:
			return
	if fighter.tick_buffs():
		log_message(content.text("buff_fade"), "info")
	if fighter.rooted_turns > 0:
		fighter.rooted_turns -= 1
	if smoke_turns > 0:
		smoke_turns -= 1
		emit_event("smoke", player().x, player().y, {})
		if smoke_turns == 0:
			log_message(content.text("smoke_fade"), "info")
	for actor in map().actors.duplicate():
		if actor.summon_ttl >= 0 and actor != player():
			actor.summon_ttl -= 1
			if actor.summon_ttl <= 0:
				log_message(content.text("summon_fade").format({"name": actor.label}), "summon")
				emit_event("summon", actor.x, actor.y, {})
				map().actors.erase(actor)
				actor.fighter = null


## 敌我单位行动前结算 DOT 与减益，再执行 AI；行动后递减缠绕。
func enemy_turns() -> void:
	for actor in map().actors.duplicate():
		if actor == player() or not actor.is_alive() or actor.ai == null:
			continue
		if game_over:
			return
		_settle_actor_turn(actor)


func _settle_actor_turn(actor: Actor) -> void:
	var fighter = actor.fighter
	if fighter == null:
		return
	if fighter.has_dot():
		_tick_actor_dots(actor)
		if not actor.is_alive():
			return
	fighter.tick_buffs()  # 破甲/挫锐等减益按怪回合递减
	if fighter.stun_turns > 0:
		fighter.stun_turns -= 1
		if fighter.rooted_turns > 0:
			fighter.rooted_turns -= 1
		emit_event("stun", actor.x, actor.y, {})
		log_message(content.text("stunned_tick").format({"name": actor.label}), "info")
		return  # 眩晕：跳过本回合
	actor.ai.perform(self)
	# 缠绕在本回合行动窗口内生效（AI 移动被拒），行动后递减
	if fighter.rooted_turns > 0:
		fighter.rooted_turns -= 1
		emit_event("root", actor.x, actor.y, {})


## 结算 actor 身上全部元素 DOT（消息按元素出）。
func _tick_actor_dots(actor: Actor) -> void:
	for entry in actor.fighter.tick_dots():
		var kind: String = entry[0]
		var damage: int = entry[1]
		var expired: bool = entry[2]
		emit_event("dot_tick", actor.x, actor.y, {"kind": kind, "amount": damage})
		log_message(content.text("dot_tick_" + kind).format({
			"name": actor.label, "damage": damage,
		}), "warn")
		_apply_damage(actor, actor, damage)  # DOT 无击杀者
		if not actor.is_alive():
			return
		if expired:
			log_message(content.text("dot_fade").format({
				"name": actor.label, "state": content.text("dot_name_" + kind),
			}), "info")
