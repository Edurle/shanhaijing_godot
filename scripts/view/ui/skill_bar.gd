class_name UiSkillBar
extends UiPanel
## 底部技能栏（RPG 式）：8 个图标槽，汉字占位（素材期换贴图）。
## 槽内：汉字图标（元素色）/ 左上槽位号 / 右下重数 / 底部耗气灵；
## 未学 = 灰显虚框，资源不足 = 整槽压灰。

const SLOT := 56.0
const GAP := 6.0
const BAR_HEIGHT := 78.0

var engine
var slot_origin := Vector2.ZERO  # 首槽左上角（点击命中用）


func setup(p_engine) -> void:
	engine = p_engine
	relayout(_viewport_size())


func relayout(view_size: Vector2) -> void:
	var map_width: float = view_size.x - 300.0
	var total := 8.0 * SLOT + 7.0 * GAP
	setup_ui(Rect2((map_width - total) / 2.0, view_size.y - BAR_HEIGHT - 10.0, total, BAR_HEIGHT))
	slot_origin = panel_rect.position
	queue_redraw()


func refresh() -> void:
	queue_redraw()


## 汉字占位图标：技能名首字（素材期替换为贴图）。
static func icon_char(engine, skill: Dictionary) -> String:
	var skill_label: String = engine.content.localize(skill["name"])
	return String(skill_label.substr(0, 1)) if skill_label.length() > 0 else "？"


func slot_rect(slot: int) -> Rect2:
	var i := slot - 1
	return Rect2(slot_origin + Vector2(i * (SLOT + GAP), 0), Vector2(SLOT, SLOT + 20))


## 槽位命中检测（主场景点击路由）：返回 1-8，未命中 0。
func skill_slot_at(pos: Vector2) -> int:
	for slot in range(1, 9):
		if slot_rect(slot).grow(2.0).has_point(pos):
			return slot
	return 0


func _draw() -> void:
	if engine == null:
		return
	var player = engine.state.player
	var class_id := String(player.class_ids[engine.active_page])
	for slot in range(1, 9):
		var skill: Dictionary = engine.content.skill_for_slot(class_id, slot)
		if skill.is_empty():
			continue
		var rect := slot_rect(slot)
		var learned: bool = player.skill_levels.has(skill["id"])
		var level: int = player.skill_levels.get(skill["id"], 0)
		var affordable: bool = player.fighter.mp() >= Skills.mp_cost(player, skill) and player.fighter.sp() >= Skills.sp_cost(player, skill)
		var active := learned and affordable

		# 槽底
		draw_rect(rect, Color(PAPER, 0.92) if active or learned else Color(PAPER, 0.55))
		draw_rect(rect, INK if active else INK_SOFT, false, 1.6 if active else 1.0)

		# 汉字图标（元素色；未学/乏力压灰）
		var icon_color: Color = INK
		var element := Skills.skill_element(skill)
		if element != "":
			icon_color = ELEMENT_COLORS.get(element, INK)
		if not active:
			icon_color = icon_color.lerp(PAPER, 0.62)
		var font := get_theme_default_font()
		var icon_char := icon_char(engine, skill)
		draw_string(font, rect.position + Vector2(SLOT / 2.0 - 12.0, 34), icon_char,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, icon_color)

		# 左上槽位号 / 右下重数
		draw_string(font, rect.position + Vector2(5, 14), str(slot),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK_SOFT)
		if level > 1:
			draw_string(font, rect.position + Vector2(SLOT - 18, SLOT + 6), str(level),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOLD if active else INK_SOFT)

		# 底部耗气灵
		if learned:
			var cost := ""
			var mp_need := Skills.mp_cost(player, skill)
			if mp_need > 0:
				cost += "%d气" % mp_need
			var sp_need := Skills.sp_cost(player, skill)
			if sp_need > 0:
				cost += "%d灵" % sp_need
			if cost != "":
				draw_string(font, rect.position + Vector2(SLOT / 2.0 - cost.length() * 5.0, SLOT + 16), cost,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK_SOFT if affordable else VERMILION)


const ELEMENT_COLORS := {
	"metal": Color("C9A662"),
	"wood": Color("4A7C59"),
	"water": Color("2E5977"),
	"fire": Color("C3272B"),
	"earth": Color("8C5A3C"),
}
