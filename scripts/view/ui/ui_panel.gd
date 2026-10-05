class_name UiPanel
extends Control
## 水墨 UI 面板基类：宣纸底 + 墨框 + 标题的自绘统一入口。
## 所有菜单/侧栏共用，保证界面风格与棋盘一致（AI 素材期一并换肤）。

const PAPER := Color("EFE8D6")
const PAPER_SHADOW := Color("D8CFBA")
const INK := Color("2B2620")
const INK_SOFT := Color("6E675C")
const VERMILION := Color("C3272B")
const GOLD := Color("C9A662")

## 五行元素 → 图标用色（技能栏/技能树共用；素材期换贴图后仍作描边色）。
const ELEMENT_COLORS := {
	"metal": Color("C9A662"),
	"wood": Color("4A7C59"),
	"water": Color("2E5977"),
	"fire": Color("C3272B"),
	"earth": Color("8C5A3C"),
}

## 装备品级 → 名称/图标色（白=common 不入表，即不着色；全 UI 单一色源）。
const RARITY_COLORS := {
	"magic": Color("3465A4"),
	"rare": Color("B8860B"),
	"legendary": Color("D2691E"),
	"mythic": Color("C3272B"),
}
## 套装显示色（绿），优先于品级色。
const SET_COLOR := Color("3E8E58")

var panel_rect := Rect2(0, 0, 400, 300)
var title := ""


func setup_ui(rect: Rect2, panel_title := "") -> void:
	## Control 固定在原点：panel_rect 即屏幕绝对坐标，_draw 与点击命中共用一套。
	## （若把 position 也设为 rect.position，绘制坐标会被叠加两次、面板飞出屏幕。）
	panel_rect = rect
	title = panel_title
	position = Vector2.ZERO
	custom_minimum_size = rect.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 点击统一由主场景路由
	queue_redraw()


## 视口尺寸变化时重排（子类按锚点策略重算 panel_rect）。
func relayout(_view_size: Vector2) -> void:
	pass


## 纸面 + 墨框 + 标题章。
func draw_paper() -> void:
	draw_rect(panel_rect, PAPER_SHADOW, false, 3.0)  # 底衬
	draw_rect(Rect2(panel_rect.position - Vector2(3, 3), panel_rect.size + Vector2(6, 6)), PAPER)
	draw_rect(panel_rect, INK, false, 2.0)
	if title != "":
		var font := get_theme_default_font()
		var size := get_theme_default_font_size()
		# 标题嵌进上边框（朱印风格）
		draw_rect(Rect2(panel_rect.position + Vector2(14, -12), Vector2(title.length() * size * 0.62 + 16, 24)), PAPER)
		draw_string(font, panel_rect.position + Vector2(22, 6), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK)


func draw_text_line(pos: Vector2, text: String, color := INK, size := 0) -> void:
	var font := get_theme_default_font()
	var font_size := size if size > 0 else get_theme_default_font_size()
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func draw_bar(pos: Vector2, width: float, ratio: float, fill: Color, height := 10.0) -> void:
	draw_rect(Rect2(pos, Vector2(width, height)), PAPER_SHADOW)
	draw_rect(Rect2(pos, Vector2(width * clampf(ratio, 0.0, 1.0), height)), fill)
	draw_rect(Rect2(pos, Vector2(width, height)), INK, false, 1.0)


## 当前视口尺寸；headless/异常小视口（<200px，如无窗口时的 64×64）回退基准尺寸，
## 避免布局计算出负宽高面板。
func _viewport_size() -> Vector2:
	var vp := get_viewport()
	var size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2.ZERO
	if size.x < 200.0 or size.y < 200.0:
		return Vector2(1280, 768)
	return size


## 物品显示色：套装绿 > 品级色 > fallback（白装/非装备回落调用方默认色）。
static func rarity_color(item: Dictionary, fallback := INK) -> Color:
	if String(item.get("set_id", "")) != "":
		return SET_COLOR
	return RARITY_COLORS.get(String(item.get("rarity", "common")), fallback)


## 是否有品级/套装专属色（白装无，回落调用方既有配色）。
static func has_rarity_color(item: Dictionary) -> bool:
	return String(item.get("set_id", "")) != "" or RARITY_COLORS.has(String(item.get("rarity", "common")))
