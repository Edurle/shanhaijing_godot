class_name Consumables
extends RefCounted
## 物品效果——Python 版 consumable.py 的移植（tianshu 通关符待通关系统接入）。
## 返回错误串（空 = 成功并消耗回合）。


## 使用物品主入口。
static func activate(engine, item: Dictionary) -> String:
	var cfg: Dictionary = item.get("consumable", {})
	match String(cfg.get("type", "")):
		"heal":
			return _heal(engine, int(cfg.get("amount", 0)))
		"heal_mp":
			return _heal_mp(engine, int(cfg.get("amount", 0)))
		"cleanse":
			return _cleanse(engine)
		"buff_item":
			return _buff_item(engine, cfg)
		"lightning":
			return _lightning(engine, int(cfg.get("damage", 0)), int(cfg.get("max_range", 6)))
		"knockback":
			return _knockback(engine, cfg)
		"stun_area":
			return _stun_area(engine, int(cfg.get("turns", 1)), int(cfg.get("radius", 12)))
		"smoke":
			return _smoke(engine, int(cfg.get("turns", 4)))
		"tianshu":
			return engine.content.text("tianshu_pending")  # 通关系统阶段 6 接入
	return "未知物品效果"


static func _heal(engine, amount: int) -> String:
	var player = engine.player()
	if player.fighter.hp() >= player.fighter.max_hp():
		return engine.content.text("heal_full")
	var healed: int = player.fighter.heal(amount)
	engine.log_message(engine.content.text("heal_used").format({"amount": healed}), "heal")
	engine.emit_event("heal", player.x, player.y, {"amount": healed})
	return ""


static func _heal_mp(engine, amount: int) -> String:
	var player = engine.player()
	if player.fighter.mp() >= player.fighter.max_mp():
		return engine.content.text("mp_full")
	var restored: int = player.fighter.restore_mp(amount)
	engine.log_message(engine.content.text("heal_mp_used").format({"amount": restored}), "heal")
	engine.emit_event("mp", player.x, player.y, {"amount": restored})
	return ""


static func _cleanse(engine) -> String:
	var player = engine.player()
	if not player.fighter.has_dot():
		return engine.content.text("cleanse_no_poison")
	player.fighter.clear_dots()
	engine.log_message(engine.content.text("cleanse_used"), "heal")
	engine.emit_event("heal", player.x, player.y, {"amount": 0})
	return ""


static func _buff_item(engine, cfg: Dictionary) -> String:
	var player = engine.player()
	var stat := String(cfg.get("stat", "power"))
	player.fighter.apply_buff(stat, int(cfg.get("amount", 2)), int(cfg.get("turns", 10)))
	var key := "buff_item_power" if stat == "power" else "buff_item_defense"
	engine.log_message(engine.content.text(key).format({
		"amount": int(cfg.get("amount", 2)), "turns": int(cfg.get("turns", 10)),
	}), "buff")
	engine.emit_event("buff", player.x, player.y, {})
	return ""


## 五雷符：视野内最近敌，金系天雷（吃金抗+生克）。
static func _lightning(engine, damage: int, max_range: int) -> String:
	var player = engine.player()
	var target = _nearest_visible(engine, player, max_range)
	if target == null:
		return engine.content.text("lightning_no_target")
	var final_damage: int = target.fighter.mitigate_incoming(damage, ["metal"])
	engine.log_message(engine.content.text("lightning_used").format({
		"target": target.label, "damage": final_damage,
	}), "lightning")
	engine.emit_event("lightning", target.x, target.y, {"amount": final_damage})
	engine.emit_noise(target.x, target.y, 9)
	engine._apply_damage(player, target, final_damage)
	return ""


## 震退符：最近敌受震伤并被推离，撞壁附眩晕——近身解围。
static func _knockback(engine, cfg: Dictionary) -> String:
	var player = engine.player()
	var target = _nearest_visible(engine, player, int(cfg.get("max_range", 6)))
	if target == null:
		return engine.content.text("lightning_no_target")
	var damage := int(cfg.get("damage", 5))
	var push := int(cfg.get("push", 3))
	var stun := int(cfg.get("stun", 2))
	engine.emit_event("hit", target.x, target.y, {"amount": damage})
	engine._apply_damage(player, target, damage)
	engine.log_message(engine.content.text("knockback_used").format({"target": target.label}), "combat")
	if not target.is_alive():
		return ""
	var dx := signi(target.x - player.x)
	var dy := signi(target.y - player.y)
	var moved: int = engine.push_actor(target, dx, dy, push)
	if moved < push and stun > 0:
		target.fighter.apply_stun(stun)
		engine.emit_event("stun", target.x, target.y, {})
		engine.log_message(engine.content.text("knockback_wall").format({"target": target.label}), "combat")
	return ""


## 定身符：视野内全体敌人神魂受震。
static func _stun_area(engine, turns: int, radius: int) -> String:
	var player = engine.player()
	var targets: Array = []
	for actor in engine.map().actors:
		if actor.team == "wild" and actor.is_alive() and engine.map().is_visible(actor.x, actor.y):
			if player.distance_to(actor) <= radius:
				targets.append(actor)
	if targets.is_empty():
		return engine.content.text("lightning_no_target")
	for target in targets:
		target.fighter.apply_stun(turns)
		engine.emit_event("stun", target.x, target.y, {})
	engine.log_message(engine.content.text("talisman_stun").format({"count": targets.size()}), "lightning")
	return ""


## 烟雾符：烟障蔽目，期间敌怪感知不到玩家（贴身除外）——脱战核心。
static func _smoke(engine, turns: int) -> String:
	engine.smoke_turns = maxi(engine.smoke_turns, turns)
	engine.emit_event("smoke", engine.player().x, engine.player().y, {})
	engine.log_message(engine.content.text("smoke_used").format({"turns": turns}), "buff")
	return ""


static func _nearest_visible(engine, player: Actor, max_range: int) -> Actor:
	var best: Actor = null
	var best_d := float(max_range) + 0.5
	for actor in engine.map().actors:
		if actor.team == "player" or not actor.is_alive():
			continue
		if not engine.map().is_visible(actor.x, actor.y):
			continue
		var distance := player.distance_to(actor)
		if distance <= max_range and distance < best_d:
			best = actor
			best_d = distance
	return best


## 物品效果短摘要（行囊行尾）。
static func summary(engine, item: Dictionary) -> String:
	var cfg: Dictionary = item.get("consumable", {})
	var kind := String(cfg.get("type", ""))
	if kind == "heal":
		return engine.content.text("summ_heal").format({"v": int(cfg.get("amount", 0))})
	if kind == "heal_mp":
		return engine.content.text("summ_heal_mp").format({"v": int(cfg.get("amount", 0))})
	if kind == "cleanse":
		return engine.content.text("summ_cleanse")
	if kind == "buff_item":
		var stat := String(cfg.get("stat", "power"))
		var key := "summ_buff_pow" if stat == "power" else "summ_buff_def"
		return engine.content.text(key).format({"v": int(cfg.get("amount", 0))})
	if kind == "lightning":
		return engine.content.text("summ_damage").format({"v": int(cfg.get("damage", 0))})
	if kind == "knockback":
		return engine.content.text("summ_knockback").format({
			"v": int(cfg.get("damage", 5)), "d": int(cfg.get("push", 3)),
		})
	if kind == "stun_area":
		return engine.content.text("summ_stun").format({"v": int(cfg.get("turns", 1))})
	if kind == "smoke":
		return engine.content.text("summ_smoke").format({"v": int(cfg.get("turns", 4))})
	if kind == "tianshu":
		return engine.content.text("summ_tianshu")
	return ""
