class_name UiSkillBar
extends UiPanel
## 底部技能栏（RPG 式）：16 个正方形图标槽平铺——1-8 主修、9-16 辅修（Shift+数字）。
## 槽内：汉字图标（元素色）/ 左上键位号 / 右上重数 / 格内底部耗尾；
## 未学 = 灰显细框，资源不足 = 图标压灰、耗字转朱。

const SLOT := 50.0          # 正方形边长
const GAP := 6.0
const GROUP_GAP := 14.0     # 主修/辅修两组之间的额外间隔
const HEADER := 16.0        # 顶部组标签行
const BAR_MARGIN := 10.0

var engine
var slot_origin := Vector2.ZERO  # 首槽左上角（点击命中用）


func setup(p_engine) -> void:
	engine = p_engine
	relayout(_viewport_size())


func total_width() -> float:
	return 16.0 * SLOT + 14.0 * GAP + GROUP_GAP


func relayout(view_size: Vector2) -> void:
	setup_ui(Rect2(
		(view_size.x - total_width()) / 2.0,
		view_size.y - HEADER - SLOT - BAR_MARGIN,
		total_width(), HEADER + SLOT))
	slot_origin = panel_rect.position + Vector2(0, HEADER)
	queue_redraw()


func refresh() -> void:
	queue_redraw()


## 槽位 -> [职业页索引, 页内槽位]：1-8 主修，9-16 辅修。
static func slot_page(slot: int) -> Array:
	return [0, slot] if slot <= 8 else [1, slot - 8]


## 汉字占位图标：技能名首字（素材期替换为贴图）。
static func icon_char(engine, skill: Dictionary) -> String:
	var skill_label: String = engine.content.localize(skill["name"])
	return String(skill_label.substr(0, 1)) if skill_label.length() > 0 else "？"


func slot_rect(slot: int) -> Rect2:
	var i := slot - 1
	var group_extra: float = GROUP_GAP if slot > 8 else 0.0
	return Rect2(slot_origin + Vector2(i * (SLOT + GAP) + group_extra, 0), Vector2(SLOT, SLOT))


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
	# 组标签：主修 / 辅修
	draw_string(font, panel_rect.position + Vector2(0, 12), "主修",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK_SOFT)
	draw_string(font, Vector2(slot_rect(9).position.x, panel_rect.position.y + 12), "辅修",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK_SOFT)
	for slot in range(1, 17):
		var pair := slot_page(slot)
		var class_id := String(player.class_ids[pair[0]])
		var skill: Dictionary = engine.content.skill_for_slot(class_id, pair[1])
		if skill.is_empty():
			continue
		var rect := slot_rect(slot)
		var learned: bool = player.skill_levels.has(skill["id"])
		var level: int = player.skill_levels.get(skill["id"], 0)
		var affordable: bool = player.fighter.mp() >= Skills.mp_cost(player, skill) and player.fighter.sp() >= Skills.sp_cost(player, skill)
		var active := learned and affordable

		draw_rect(rect, Color(PAPER, 0.92) if active or learned else Color(PAPER, 0.55))
		draw_rect(rect, INK if active else INK_SOFT, false, 1.6 if active else 1.0)

		var icon_color: Color = INK
		var element := Skills.skill_element(skill)
		if element != "":
			icon_color = ELEMENT_COLORS.get(element, INK)
		if not active:
			icon_color = icon_color.lerp(PAPER, 0.62)
		# 汉字图标（格内中上）
		draw_string(font, rect.position + Vector2(SLOT / 2.0 - 11.0, 30), icon_char(engine, skill),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, icon_color)
		# 左上键位号（主修纯数字；辅修 S 前缀表示 Shift）
		var key_label := str(pair[1]) if pair[0] == 0 else "S" + str(pair[1])
		draw_string(font, rect.position + Vector2(3, 12), key_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK_SOFT)
		# 右上重数
		if level > 1:
			draw_string(font, rect.position + Vector2(SLOT - 14, 12), str(level),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GOLD if active else INK_SOFT)
		# 格内底部耗气灵
		if learned:
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
