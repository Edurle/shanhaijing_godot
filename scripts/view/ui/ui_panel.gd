class_name UiPanel
extends Control
## 水墨 UI 面板基类：宣纸底 + 墨框 + 标题的自绘统一入口。
## 所有菜单/侧栏共用，保证界面风格与棋盘一致（AI 素材期一并换肤）。
## 颜色一律取自 InkPalette（唯一色源），本文件不持有颜色常量。

## 品级中文标签（编辑器 ENUM_LABELS 的游戏侧副本，悬浮卡等显示用）。
const RARITY_LABELS := {
	"common": "凡品(白)", "magic": "灵品(蓝)", "rare": "宝品(黄)",
	"legendary": "仙品(橙)", "mythic": "神品(红)",
}

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
	draw_rect(panel_rect, InkPalette.PAPER_SHADOW, false, 3.0)  # 底衬
	draw_rect(Rect2(panel_rect.position - Vector2(3, 3), panel_rect.size + Vector2(6, 6)), InkPalette.PAPER_UI)
	draw_rect(panel_rect, InkPalette.INK, false, 2.0)
	if title != "":
		var font := get_theme_default_font()
		var size := get_theme_default_font_size()
		# 标题嵌进上边框（朱印风格）
		draw_rect(Rect2(panel_rect.position + Vector2(14, -12), Vector2(title.length() * size * 0.62 + 16, 24)), InkPalette.PAPER_UI)
		draw_string(font, panel_rect.position + Vector2(22, 6), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, InkPalette.INK)


func draw_text_line(pos: Vector2, text: String, color: Color, size := 0) -> void:
	var font := get_theme_default_font()
	var font_size := size if size > 0 else get_theme_default_font_size()
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func draw_bar(pos: Vector2, width: float, ratio: float, fill: Color, height := 10.0) -> void:
	draw_rect(Rect2(pos, Vector2(width, height)), InkPalette.PAPER_SHADOW)
	draw_rect(Rect2(pos, Vector2(width * clampf(ratio, 0.0, 1.0), height)), fill)
	draw_rect(Rect2(pos, Vector2(width, height)), InkPalette.INK, false, 1.0)


## 当前视口尺寸；headless/异常小视口（<200px，如无窗口时的 64×64）回退基准尺寸，
## 避免布局计算出负宽高面板。
func _viewport_size() -> Vector2:
	var vp := get_viewport()
	var size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2.ZERO
	if size.x < 200.0 or size.y < 200.0:
		return Vector2(1280, 768)
	return size


## 物品显示色：套装绿 > 品级色 > fallback（白装/非装备回落调用方默认色）。
static func rarity_color(item: Dictionary, fallback := InkPalette.INK) -> Color:
	if String(item.get("set_id", "")) != "":
		return InkPalette.SET_COLOR
	return InkPalette.RARITY_COLORS.get(String(item.get("rarity", "common")), fallback)


## 是否有品级/套装专属色（白装无，回落调用方既有配色）。
static func has_rarity_color(item: Dictionary) -> bool:
	return String(item.get("set_id", "")) != "" or InkPalette.RARITY_COLORS.has(String(item.get("rarity", "common")))
