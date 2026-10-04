class_name UiSkillBar
extends UiPanel
## 底部技能栏（RPG 动作条）：16 个正方形槽，绑定完全由玩家编排（B 键）。
## 槽内：汉字图标（元素色）/ 左上键位号 / 右上重数 / 格内底部耗尾；
## 未绑定 = 空槽虚框，资源不足 = 图标压灰、耗字转朱。

const SLOT := 50.0          # 正方形边长
const GAP := 6.0
const HEADER := 16.0        # 顶部提示行
const BAR_MARGIN := 10.0

var engine
var slot_origin := Vector2.ZERO  # 首槽左上角（点击命中用）


func setup(p_engine) -> void:
	engine = p_engine
	relayout(_viewport_size())


func total_width() -> float:
	return 16.0 * SLOT + 15.0 * GAP


func relayout(view_size: Vector2) -> void:
	setup_ui(Rect2(
		(view_size.x - total_width()) / 2.0,
		view_size.y - HEADER - SLOT - BAR_MARGIN,
		total_width(), HEADER + SLOT))
	slot_origin = panel_rect.position + Vector2(0, HEADER)
	queue_redraw()


func refresh() -> void:
	queue_redraw()


## 键位显示：1-8 / S1-S8（Shift 组）。
static func key_label(slot: int) -> String:
	return str(slot) if slot <= 8 else "S" + str(slot - 8)


## 汉字占位图标：技能名首字（素材期替换为贴图）。
static func icon_char(engine, skill: Dictionary) -> String:
	var skill_label: String = engine.content.localize(skill["name"])
	return String(skill_label.substr(0, 1)) if skill_label.length() > 0 else "？"


func slot_rect(slot: int) -> Rect2:
	return Rect2(slot_origin + Vector2((slot - 1) * (SLOT + GAP), 0), Vector2(SLOT, SLOT))


## 槽位命中检测（主场景点击路由）：返回 1-16，未命中 0。
func skill_slot_at(pos: Vector2) -> int:
	for slot in range(1, 17):
		if slot_rect(slot).grow(2.0).has_point(pos):
			return slot
	return 0


func _draw() -> void:
	if engine == null:
		return
	var player = engine.state.player
	var font := get_theme_default_font()
	draw_string(font, panel_rect.position + Vector2(0, 12), "B 编排",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK_SOFT)
	for slot in range(1, 17):
		var rect := slot_rect(slot)
		var skill_id := String(player.skill_bar[slot - 1])
		draw_rect(rect, Color(PAPER, 0.55))
		draw_rect(rect, INK_SOFT, false, 1.0)
		if skill_id == "":
			draw_string(font, rect.position + Vector2(SLOT / 2.0 - 3.0, 30), "·",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK_SOFT)
			continue
		var skill: Dictionary = engine.content.skill_by_id(skill_id)
		if skill.is_empty() or not player.skill_levels.has(skill_id):
			continue
		var learned := true
		var level: int = player.skill_levels.get(skill_id, 0)
		var affordable: bool = player.fighter.mp() >= Skills.mp_cost(player, skill) and player.fighter.sp() >= Skills.sp_cost(player, skill)
		var active := learned and affordable

		draw_rect(rect, Color(PAPER, 0.92))
		draw_rect(rect, INK if active else INK_SOFT, false, 1.6 if active else 1.0)

		var icon_color: Color = INK
		var element := Skills.skill_element(skill)
		if element != "":
			icon_color = ELEMENT_COLORS.get(element, INK)
		if not active:
			icon_color = icon_color.lerp(PAPER, 0.62)
		draw_string(font, rect.position + Vector2(SLOT / 2.0 - 11.0, 30), icon_char(engine, skill),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, icon_color)
		draw_string(font, rect.position + Vector2(3, 12), key_label(slot),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK_SOFT)
		if level > 1:
			draw_string(font, rect.position + Vector2(SLOT - 14, 12), str(level),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GOLD if active else INK_SOFT)
		var cost := ""
		var mp_need := Skills.mp_cost(player, skill)
		if mp_need > 0:
			cost += "%d气" % mp_need
		var sp_need := Skills.sp_cost(player, skill)
		if sp_need > 0:
			cost += "%d灵" % sp_need
		if cost != "":
			draw_string(font, rect.position + Vector2(SLOT / 2.0 - cost.length() * 4.5, SLOT - 3), cost,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK_SOFT if affordable else VERMILION)


const ELEMENT_COLORS := {
	"metal": Color("C9A662"),
	"wood": Color("4A7C59"),
	"water": Color("2E5977"),
	"fire": Color("C3272B"),
	"earth": Color("8C5A3C"),
}
