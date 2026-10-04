class_name UiMenuLearn
extends UiListMenu
## 参悟：双职业页（Tab），前置/技能点/材料门槛实时标注，Enter 修习（不耗回合）。

var engine


func setup_menu(p_engine) -> void:
	engine = p_engine
	title = "参悟"
	confirmed.connect(_on_confirm)
	cancelled.connect(func(): close())


func _rebuild() -> void:
	page_count = 2
	var player = engine.player()
	var class_id := String(player.class_ids[page])
	var essence: int = player.inventory.count_material("mat_elite_essence")
	var core: int = player.inventory.count_material("mat_demon_core")
	header_extra = "%s · 技能点 %d · 精魄×%d 魔核×%d" % [
		engine.content.class_display_name(class_id), player.skill_points, essence, core,
	]
	rows.clear()
	for skill in engine.content.skills_for_class(class_id):
		var sid: String = skill["id"]
		var level: int = player.skill_levels.get(sid, 0)
		var state := ""
		var color: Color = Color(150, 145, 135)
		if level > 0:
			state = "%d 重" % level
			color = INK
		else:
			var missing: Array = []
			for req in skill.get("requires", []):
				if not player.skill_levels.has(req):
					missing.append(engine.content.localize(engine.content.skills[req]["name"]))
			if missing.is_empty():
				state = "·"  # 可学
				color = INK_SOFT
			else:
				state = "×需 " + "、".join(missing)
		var tail := state
		if level == 0 and int(skill.get("cost", 1)) >= 2:
			tail += " 魔核×1"
		rows.append({
			"text": engine.content.localize(skill["name"]),
			"tail": tail, "color": color, "meta": sid,
		})


func _on_confirm(meta) -> void:
	var error: String = engine.learn_skill(String(meta))
	if not error.is_empty():
		engine.log_message(error, "warn")
	_rebuild()
	queue_redraw()
