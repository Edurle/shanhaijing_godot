class_name UiTargetInfo
extends UiPanel
## 瞄准信息板：目标名/气血/预计伤害 + 抗性与生克附注。

var engine
var skill: Dictionary = {}
var target: Actor


func setup(p_engine) -> void:
	engine = p_engine
	relayout(_viewport_size())


func relayout(view_size: Vector2) -> void:
	# 顶部居中于地图区（左上角是资源 HUD，不能重叠）
	var w := minf(560.0, view_size.x - 40.0)
	setup_ui(Rect2((view_size.x - w) / 2.0, 12.0, w, 74))


func show_target(p_skill: Dictionary, p_target: Actor) -> void:
	skill = p_skill
	target = p_target
	visible = true
	queue_redraw()


func hide_panel() -> void:
	visible = false


func _draw() -> void:
	if target == null or not target.is_alive():
		return
	draw_rect(Rect2(panel_rect.position - Vector2(2, 2), panel_rect.size + Vector2(4, 4)), Color(PAPER, 0.9))
	draw_rect(panel_rect, INK, false, 1.5)
	var player = engine.player()
	var raw: int = Skills.compute_damage(player, skill)
	var final_damage: int = target.fighter.mitigate_incoming(raw, skill.get("tags", []))
	var notes := _resist_note() + _counter_note()
	draw_text_line(Vector2(panel_rect.position.x + 12, panel_rect.position.y + 24),
		"%s（气血 %d/%d）· 预计伤害 %d%s" % [
			target.label, target.fighter.hp(), target.fighter.max_hp(), final_damage, notes,
		], INK, 16)
	draw_text_line(Vector2(panel_rect.position.x + 12, panel_rect.position.y + 52),
		"Enter 施放 · ↑↓/Tab 换目标 · Esc 取消", INK_SOFT, 13)


func _resist_note() -> String:
	var best_kind := ""
	var best_value := 0
	for kind in ContentDb.ELEMENTS:
		if skill.get("tags", []).has(kind):
			var value: int = target.fighter.resistance(kind)
			if value > best_value:
				best_kind = String(kind)
				best_value = value
	if best_kind == "":
		return ""
	return "·" + engine.content.text("resist_" + best_kind).format({"v": best_value})


func _counter_note() -> String:
	var mult: float = target.fighter.counter_multiplier(skill.get("tags", []))
	if mult > 1.0:
		return "·" + engine.content.text("counter_up")
	if mult < 1.0:
		return "·" + engine.content.text("counter_down")
	return ""
