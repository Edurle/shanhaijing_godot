class_name Passives
extends RefCounted
## 被动系统：氏族被动 + 职业被动（各一，build_player 收集到 actor.passives）。
## 三类效果：stat_aura 常驻（开局并入基础值）/ melee_lifesteal 普攻吸血 / kill_rally 击杀增益。
## 触发型由回合引擎挂钩调用；怪物无被动（passives 空 = 全部空转）。

## 收集玩家的双被动（氏族与职业自由组合）：[职业被动, 氏族被动]（缺失的跳过）。
## clan_id 为空 = 未择氏族（仅职业被动；兼容旧调用）。
static func collect(content: ContentDb, class_id: String, clan_id := "") -> Array:
	var result: Array = []
	var cdef: Dictionary = content.classes.get(class_id, {})
	if cdef.has("passive"):
		result.append(cdef["passive"])
	if content.clans.has(clan_id) and content.clans[clan_id].has("passive"):
		result.append(content.clans[clan_id]["passive"])
	return result


## 常驻被动开局并入：直接改写 Fighter 基础值（含抗性）；资源池随上限补满。
## 仅 build_player 时调用一次（被动不可变，无中途变更）。
static func apply_permanent(actor: Actor) -> void:
	var fighter = actor.fighter
	if fighter == null:
		return
	for passive in actor.passives:
		var eff: Dictionary = passive.get("effect", {})
		if String(eff.get("type", "")) != "stat_aura":
			continue
		var stats: Dictionary = eff.get("stats", {})
		fighter.base_power += int(stats.get("power", 0))
		fighter.base_defense += int(stats.get("defense", 0))
		fighter.base_max_hp += int(stats.get("max_hp", 0))
		fighter.base_max_mp += int(stats.get("max_mp", 0))
		fighter.base_max_sp += int(stats.get("max_sp", 0))
		for key in stats:
			var key_text := String(key)
			if key_text.begins_with("resist_"):
				var kind := key_text.substr("resist_".length())
				fighter.base_resistances[kind] = int(fighter.base_resistances.get(kind, 0)) + int(stats[key])
	# 开局即满状态：池随上限同涨（调用点仅在初始满血构造后）
	fighter.heal(fighter.base_max_hp)
	fighter.restore_mp(fighter.base_max_mp)
	fighter.restore_sp(fighter.base_max_sp)


## 普攻命中且造成伤害后（引擎 melee_attack 调用）：吸血回血不出日志（heal 演出可见），满血不触发演出。
static func on_melee_hit(engine, attacker: Actor, _target: Actor) -> void:
	if attacker.passives.is_empty() or attacker.fighter == null:
		return
	for passive in attacker.passives:
		var eff: Dictionary = passive.get("effect", {})
		if String(eff.get("type", "")) != "melee_lifesteal":
			continue
		var healed: int = attacker.fighter.heal(int(eff.get("amount", 0)))
		if healed > 0:
			engine.emit_event("heal", attacker.x, attacker.y, {"amount": healed})


## 玩家直接击杀异兽后（引擎 _apply_damage 调用）：施加增益 buff（同属性叠加、时长刷新）。
static func on_kill(engine, killer: Actor, _victim: Actor) -> void:
	if killer.passives.is_empty() or not killer.is_alive() or killer.fighter == null:
		return
	for passive in killer.passives:
		var eff: Dictionary = passive.get("effect", {})
		if String(eff.get("type", "")) != "kill_rally":
			continue
		var stat := String(eff.get("stat", "power"))
		var amount := int(eff.get("amount", 0))
		var turns := int(eff.get("turns", 0))
		if amount <= 0 or turns <= 0:
			continue
		killer.fighter.apply_buff(stat, amount, turns)
		engine.log_message(engine.content.text("passive_rally_log").format({
			"passive": engine.content.localize(passive["name"]),
			"bonus": engine.content.text("bon_" + stat).format({"v": amount}),
			"turns": turns,
		}), "buff")
		engine.emit_event("buff", killer.x, killer.y, {})


## 被动数值摘要（选职界面/角色面板用）：stat_aura 复用 bon_*/aff_resist_* 文案键。
static func summary(content: ContentDb, passive: Dictionary) -> String:
	var eff: Dictionary = passive.get("effect", {})
	match String(eff.get("type", "")):
		"stat_aura":
			var parts: Array = []
			for key in eff.get("stats", {}):
				var key_text := String(key)
				var label := ("aff_" + key_text) if key_text.begins_with("resist_") else ("bon_" + key_text)
				parts.append(content.text(label).format({"v": int(eff["stats"][key])}))
			return "，".join(parts)
		"melee_lifesteal":
			return content.text("passive_sum_lifesteal").format({"v": int(eff.get("amount", 0))})
		"kill_rally":
			return content.text("passive_sum_rally").format({
				"bonus": content.text("bon_" + String(eff.get("stat", "power"))).format({"v": int(eff.get("amount", 0))}),
				"turns": int(eff.get("turns", 0)),
			})
	return ""
