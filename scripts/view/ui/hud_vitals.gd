class_name UiHudVitals
extends UiPanel
## 左上角资源 HUD（RPG 式）：行者名 / 气血 / 真气 / 灵力 / 修为+经验。
## 行距宽松（32px/行），纸面半透明底，不遮挡地图主体。

const BAR_WIDTH := 190.0
const BAR_HEIGHT := 11.0
const ROW_STEP := 34.0

var engine


func setup(p_engine) -> void:
	engine = p_engine
	relayout(_viewport_size())


func relayout(view_size: Vector2) -> void:
	setup_ui(Rect2(16, 14, minf(330.0, view_size.x - 340.0), 196))
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if engine == null:
		return
	var player = engine.player()
	var fighter = player.fighter
	draw_rect(Rect2(panel_rect.position - Vector2(4, 4), panel_rect.size + Vector2(8, 8)), Color(PAPER, 0.86))
	draw_rect(Rect2(panel_rect.position - Vector2(4, 4), panel_rect.size + Vector2(8, 8)), INK, false, 1.2)

	var x := panel_rect.position.x + 6
	var y := panel_rect.position.y + 24

	# 行者名
	draw_text_line(Vector2(x, y), player.label, INK, 22)
	y += 38

	# 气血（朱砂）
	_draw_resource_row(Vector2(x, y), engine.content.text("hud_hp").format({
		"hp": fighter.hp(), "max_hp": fighter.max_hp(),
	}), float(fighter.hp()) / maxf(1.0, fighter.max_hp()), VERMILION)
	y += ROW_STEP
	# 真气（石青）
	_draw_resource_row(Vector2(x, y), engine.content.text("hud_mp").format({
		"mp": fighter.mp(), "max_mp": fighter.max_mp(),
	}), float(fighter.mp()) / maxf(1.0, fighter.max_mp()), Color("2E5977"))
	y += ROW_STEP
	# 灵力（紫；无灵力池的职业不占行）
	if fighter.max_sp() > 0:
		_draw_resource_row(Vector2(x, y), engine.content.text("hud_sp").format({
			"sp": fighter.sp(), "max_sp": fighter.max_sp(),
		}), float(fighter.sp()) / maxf(1.0, fighter.max_sp()), Color("7B5EA7"))
		y += ROW_STEP

	# 修为 + 技能点 + 经验细条（鎏金）
	var level = player.level
	if level != null:
		draw_text_line(Vector2(x, y + 8), engine.content.text("hud_level").format({
			"level": level.current_level, "xp": level.current_xp, "next": level.experience_to_next(),
		}), INK, 14)
		if player.skill_points > 0:
			draw_text_line(Vector2(x + 196, y + 8),
				engine.content.text("hud_skills_points").format({"points": player.skill_points}), GOLD, 13)
		var xp_ratio := float(level.current_xp) / maxf(1.0, level.experience_to_next())
		draw_rect(Rect2(x, y + 16, BAR_WIDTH + 60, 4), PAPER_SHADOW)
		draw_rect(Rect2(x, y + 16, (BAR_WIDTH + 60) * clampf(xp_ratio, 0.0, 1.0), 4), GOLD)


## 一行资源：标签+数值（左）、条（右侧对齐），行内留白充足。
func _draw_resource_row(pos: Vector2, label: String, ratio: float, fill: Color) -> void:
	draw_text_line(pos + Vector2(0, 9), label, INK, 15)
	var bar_pos := pos + Vector2(96, 0)
	draw_rect(Rect2(bar_pos, Vector2(BAR_WIDTH, BAR_HEIGHT)), PAPER_SHADOW)
	draw_rect(Rect2(bar_pos, Vector2(BAR_WIDTH * clampf(ratio, 0.0, 1.0), BAR_HEIGHT)), fill)
	draw_rect(Rect2(bar_pos, Vector2(BAR_WIDTH, BAR_HEIGHT)), INK, false, 1.0)
