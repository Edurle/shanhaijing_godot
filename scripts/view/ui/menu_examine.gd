class_name UiMenuExamine
extends UiPanel
## 查看卡：目标清单（左侧窄列）+ 属性卡（气血/威胁/五行/抗性/爪击元素）。

var engine
var targets: Array = []
var index := 0


func setup_menu(p_engine) -> void:
	engine = p_engine
	relayout(Vector2(1280, 768))


func relayout(view_size: Vector2) -> void:
	# 视口居中（同行囊/参悟菜单）。顶部避让左上资源 HUD（底衬236+标题章12→下限248）；
	# 高度收缩避让底部技能栏（其上沿 视口高-76，留 12 缝）；极矮窗口兜底完整入屏。
	# 矮窗口下与左下消息日志的交叠同其他大菜单（行囊/参悟），模态卡遮日志可接受。
	var w := minf(640.0, view_size.x - 60.0)
	var h := minf(480.0, view_size.y - 336.0)
	var y := (view_size.y - h) / 2.0
	y = maxf(y, 248.0)
	y = minf(y, view_size.y - h - 20.0)
	setup_ui(Rect2((view_size.x - w) / 2.0, y, w, h), "查看")


## 面板内点击：吞掉（棋盘点击换目标由主场景路由处理）。
func click_at(pos: Vector2) -> bool:
	return visible and panel_rect.has_point(pos)


func open() -> void:
	targets = engine.visible_enemies(engine.player())
	index = 0
	visible = not targets.is_empty()
	relayout(_viewport_size())
	queue_redraw()


func handle_key(keycode: int) -> bool:
	if targets.is_empty():
		return keycode == KEY_ESCAPE or keycode == KEY_X
	match keycode:
		KEY_UP, KEY_W, KEY_TAB:
			index = (index - 1 + targets.size()) % targets.size()
			queue_redraw()
			return true
		KEY_DOWN, KEY_S:
			index = (index + 1) % targets.size()
			queue_redraw()
			return true
		KEY_ESCAPE, KEY_X:
			close()
			return true
	return false


func current_target():
	return targets[index] if not targets.is_empty() else null


func close() -> void:
	visible = false


func _draw() -> void:
	if targets.is_empty():
		return
	draw_paper()
	var target = targets[index]
	var fighter = target.fighter
	var x := panel_rect.position.x + 28
	var y := panel_rect.position.y + 40

	draw_text_line(Vector2(x, y), "%d/%d  %s" % [index + 1, targets.size(), target.label], InkPalette.INK, 20)
	if target.elite:
		draw_text_line(Vector2(x + 300, y), "精英", InkPalette.GOLD, 15)
	y += 30
	# 气血条
	draw_bar(Vector2(x, y), 300, float(fighter.hp()) / maxf(1, fighter.max_hp()), InkPalette.VERMILION, 12)
	draw_text_line(Vector2(x + 320, y + 10), "%d/%d" % [fighter.hp(), fighter.max_hp()], InkPalette.INK_SOFT, 14)
	y += 28
	draw_text_line(Vector2(x, y), "气血 %d/%d · 攻 %d · 防 %d · 修为 %d" % [
		fighter.hp(), fighter.max_hp(), fighter.power(), fighter.defense(), fighter.xp_reward,
	], InkPalette.INK, 15)
	y += 24
	# 威胁 + 距离 + 本命五行
	var threat := _assess_threat()
	var threat_colors := {"凶": InkPalette.VERMILION, "慎": InkPalette.GOLD, "稳": InkPalette.SAFE}
	draw_text_line(Vector2(x, y), "威胁 %s   距离 %d   五行属 %s" % [
		threat, int(engine.player().distance_to(target)),
		engine.content.text("element_" + target.element) if target.element != "" else "—",
	], threat_colors.get(threat, InkPalette.INK), 16)
	y += 28
	# 抗性统一口径：点数经护甲式边际递减折算后显示（五行=减伤%，状态=免疫概率/效果折减%）
	var resists: Array = []
	for kind in ContentDb.RESIST_KINDS:
		var value: int = fighter.resistance(kind)
		if value > 0:
			var shown := int(round(Fighter.resist_reduction_percent(value)))
			var label: String = engine.content.text("resist_" + kind).format({"v": shown}).replace("+", "")
			resists.append(label)
	draw_text_line(Vector2(x, y), "抗性：" + (" ".join(resists) if not resists.is_empty() else "无"),
		InkPalette.SAFE if not resists.is_empty() else InkPalette.INK_SOFT, 15)
	y += 24
	# 爪击元素
	if target.attack_tags.size() > 0:
		var names: Array = []
		for t in target.attack_tags:
			names.append(engine.content.text("element_" + String(t)))
		draw_text_line(Vector2(x, y), "爪击附 " + "、".join(names) + " 之息", InkPalette.WARN, 15)
		y += 24
	# 目击位置提示由棋盘高亮框承担
	draw_text_line(Vector2(x, panel_rect.end.y - 18), "↑↓/Tab 换目标 · Esc/X 关闭", InkPalette.INK_SOFT, 13)


func _assess_threat() -> String:
	## 按双方攻防估算互换刀数：稳 / 慎 / 凶。
	var player = engine.player()
	var target = targets[index]
	var my_dmg := maxi(1, player.fighter.power() + int(player.equipment.weapon_damage()[0]) - target.fighter.defense())
	var its_dmg := maxi(0, target.fighter.power() - player.fighter.defense())
	var my_hits := ceili(float(target.fighter.hp()) / my_dmg)
	var its_hits := ceili(float(player.fighter.hp()) / its_dmg) if its_dmg > 0 else 99
	var ratio := float(its_hits) / maxf(1.0, my_hits)
	if ratio < 0.9:
		return "稳"
	if ratio < 1.4:
		return "慎"
	return "凶"
