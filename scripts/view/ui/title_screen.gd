class_name UiTitleScreen
extends Control
## 开卷界面：一幅画卷自中央徐徐绽开——双轴分展、题字落印、菜单浮出。
## 素材优先（assets/art/paper/ 三图：卷面/轴端/背景，AI 生成 → 修板入库），缺图回退程序绘制。
## 完成态沿氏族菜单惯例：主场景轮询 done + action（"new"/"quit"）。

const GAME_TITLE := "山海行"  # 竖排题字（双语界面下均为汉字书法题签）
const UNROLL_TIME := 1.9     # 展卷
const INK_TIME := 0.85       # 题字落印
const MENU_TIME := 0.4       # 菜单浮出
const ROW_FONT := 20

const BODY_TEX_PATH := "res://assets/art/paper/scroll_body.png"   # 卷面（含上下装裱边）
const ROLL_TEX_PATH := "res://assets/art/paper/scroll_roll.png"   # 轴端（卷芯+杆头，透明底）
const BG_TEX_PATH := "res://assets/art/paper/title_bg.png"        # 全屏深色背景

var content: ContentDb
var done := false
var action := ""
var rows: Array = []  # {key, act, text, rect}

var _cursor := 0
var _t := 0.0
var _view := Vector2(1280, 768)
var _scroll := Rect2()
var _body_tex: Texture2D
var _roll_tex: Texture2D
var _bg_tex: Texture2D


func setup(p_content: ContentDb) -> void:
	content = p_content
	rows = [
		{"key": "title_menu_new", "act": "new"},
		{"key": "title_menu_quit", "act": "quit"},
	]
	_load_textures()


## 惰性装图：缺图回退程序绘制（ResourceLoader.exists 与 board 贴图同一惯例）。
func _load_textures() -> void:
	if _body_tex == null and ResourceLoader.exists(BODY_TEX_PATH):
		_body_tex = load(BODY_TEX_PATH)
	if _roll_tex == null and ResourceLoader.exists(ROLL_TEX_PATH):
		_roll_tex = load(ROLL_TEX_PATH)
	if _bg_tex == null and ResourceLoader.exists(BG_TEX_PATH):
		_bg_tex = load(BG_TEX_PATH)


func open() -> void:
	_t = 0.0
	done = false
	action = ""
	_cursor = 0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 点击统一由主场景路由
	relayout(_viewport_size())
	set_process(true)
	queue_redraw()


func total_time() -> float:
	return UNROLL_TIME + INK_TIME + MENU_TIME


## 动画未完时的任意输入 = 快进到完成帧（再按一次才导航/确认，防误触）。
func skip_animation() -> void:
	_t = total_time()
	set_process(false)
	queue_redraw()


func handle_key(keycode: int) -> void:
	if done:
		return
	if _t < total_time():
		skip_animation()
		return
	match keycode:
		KEY_UP, KEY_W:
			_cursor = (_cursor - 1 + rows.size()) % maxi(1, rows.size())
			queue_redraw()
		KEY_DOWN, KEY_S:
			_cursor = (_cursor + 1) % maxi(1, rows.size())
			queue_redraw()
		KEY_ENTER, KEY_KP_ENTER:
			_confirm(_cursor)


func click_at(pos: Vector2) -> bool:
	if done:
		return true
	if _t < total_time():
		skip_animation()
		return true
	for i in range(rows.size()):
		if (rows[i]["rect"] as Rect2).has_point(pos):
			_cursor = i
			_confirm(i)
			return true
	return true  # 背景点击吞掉（动画后防误触下层）


func _confirm(index: int) -> void:
	action = String(rows[index]["act"])
	done = true
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_t = minf(_t + delta, total_time())
	queue_redraw()
	if _t >= total_time():
		set_process(false)


func relayout(view_size: Vector2) -> void:
	_view = view_size
	var w := minf(view_size.x * 0.86, 1150.0)
	# 有卷面贴图按其纵横比定高；无图回退固定比例
	var h := minf(view_size.y * 0.6, 440.0)
	if _body_tex != null:
		h = clampf(w * _body_tex.get_height() / _body_tex.get_width(), 240.0, view_size.y * 0.55)
	_scroll = Rect2(
		(view_size.x - w) / 2.0,
		view_size.y * 0.40 - h / 2.0,
		w, h)
	var font := get_theme_default_font()
	var spacing := 40.0
	var cx := _scroll.get_center().x - minf(120.0, _scroll.size.x * 0.16)
	var y := _scroll.get_center().y + 12.0 - (rows.size() - 1) * spacing / 2.0
	for row in rows:
		row["text"] = content.text(String(row["key"]))
		var tw: float = font.get_string_size(String(row["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT).x
		row["rect"] = Rect2(cx - tw / 2.0 - 34.0, y - 24.0, tw + 68.0, 34.0)
		y += spacing
	queue_redraw()


# ---- 绘制 ----

func _draw() -> void:
	if content == null or _scroll.size == Vector2.ZERO:
		return
	var view := _view
	var open_ease := 1.0 - pow(1.0 - clampf(_t / UNROLL_TIME, 0.0, 1.0), 3.0)
	_draw_background(view, open_ease)
	if _body_tex != null:
		_draw_scroll_textured(open_ease)
	else:
		_draw_scroll(open_ease)
	if _t >= UNROLL_TIME:
		_draw_ink()
	# 展卷中的呼吸提示（题字起即隐，让位给菜单键提示）
	if not done and _t < UNROLL_TIME:
		var skip := content.text("title_menu_skip")
		var sw: float = get_theme_default_font().get_string_size(skip, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_draw_subtext(Vector2((view.x - sw) / 2.0, _scroll.end.y + 52.0), skip,
			0.5 + 0.25 * sin(_t * 4.0))


## 背景：贴图按 cover 取域铺满；无图回退宣纸底+远山+朱日。
func _draw_background(view: Vector2, appear: float) -> void:
	if _bg_tex != null:
		var region := Rect2(Vector2.ZERO, Vector2(_bg_tex.get_width(), _bg_tex.get_height()))
		var src_asp := _bg_tex.get_width() / float(_bg_tex.get_height())
		var dst_asp := view.x / view.y
		if src_asp > dst_asp:
			region.size.x = _bg_tex.get_height() * dst_asp
			region.position.x = (_bg_tex.get_width() - region.size.x) / 2.0
		else:
			region.size.y = _bg_tex.get_width() / dst_asp
			region.position.y = (_bg_tex.get_height() - region.size.y) / 2.0
		draw_texture_rect_region(_bg_tex, Rect2(Vector2.ZERO, view), region)
		_draw_vignette(view, 0.3)  # 贴图自带明暗，只留极轻聚焦晕
	else:
		draw_rect(Rect2(Vector2.ZERO, view), InkPalette.PAPER)
		_draw_mountains(view, appear)
		_draw_vignette(view, 1.0)


## 贴图版展卷：卷面取中央等比切片向两侧绽开（图永不拉伸），轴端随绽开沿纸缘滑动。
func _draw_scroll_textured(open_ease: float) -> void:
	var roll_w := 40.0
	if _roll_tex != null:
		var rh := _scroll.size.y * 1.16
		roll_w = rh * _roll_tex.get_width() / float(_roll_tex.get_height())
	var reveal_w := roll_w * 1.15 + (_scroll.size.x - roll_w * 1.15) * open_ease
	var dest := Rect2(_scroll.get_center().x - reveal_w / 2.0, _scroll.position.y, reveal_w, _scroll.size.y)
	# 纸下投影
	_quad(
		Vector2(dest.position.x + 12, dest.end.y + 8),
		Vector2(dest.end.x - 12, dest.end.y + 8),
		Vector2(dest.end.x - 2, dest.end.y + 24),
		Vector2(dest.position.x + 2, dest.end.y + 24),
		Color(InkPalette.INK, 0.28), Color(InkPalette.INK, 0.28), Color(InkPalette.INK, 0.0), Color(InkPalette.INK, 0.0))
	var src_w: float = _body_tex.get_width()
	var region := Rect2(
		src_w / 2.0 - reveal_w / _scroll.size.x * src_w / 2.0, 0.0,
		reveal_w / _scroll.size.x * src_w, _body_tex.get_height())
	draw_texture_rect_region(_body_tex, dest, region)
	# 轴侧暗部：纸自卷中而出的过渡
	_quad(
		Vector2(dest.position.x, dest.position.y), Vector2(dest.position.x + 26, dest.position.y),
		Vector2(dest.position.x + 26, dest.end.y), Vector2(dest.position.x, dest.end.y),
		Color(InkPalette.INK, 0.16), Color(InkPalette.INK, 0.0), Color(InkPalette.INK, 0.0), Color(InkPalette.INK, 0.16))
	_quad(
		Vector2(dest.end.x, dest.position.y), Vector2(dest.end.x - 26, dest.position.y),
		Vector2(dest.end.x - 26, dest.end.y), Vector2(dest.end.x, dest.end.y),
		Color(InkPalette.INK, 0.16), Color(InkPalette.INK, 0.0), Color(InkPalette.INK, 0.0), Color(InkPalette.INK, 0.16))
	if _roll_tex != null:
		var roll_h := _scroll.size.y * 1.16
		var roll_rw := roll_h * _roll_tex.get_width() / float(_roll_tex.get_height())
		draw_texture_rect(_roll_tex, Rect2(dest.position.x - roll_rw / 2.0,
			_scroll.get_center().y - roll_h / 2.0, roll_rw, roll_h), false)
		draw_texture_rect(_roll_tex, Rect2(dest.end.x - roll_rw / 2.0,
			_scroll.get_center().y - roll_h / 2.0, roll_rw, roll_h), false)
	else:
		_draw_rod(dest.position.x, dest.position.y, dest.size.y)
		_draw_rod(dest.end.x, dest.position.y, dest.size.y)


## 四缘墨晕（顶光底重，左右最轻）；strength 供贴图背景减弱复用。
func _draw_vignette(view: Vector2, strength := 1.0) -> void:
	var d := view.y * 0.2
	var z := Color(InkPalette.INK, 0.0)
	_quad(Vector2(0, 0), Vector2(view.x, 0), Vector2(view.x, d), Vector2(0, d),
		Color(InkPalette.INK, 0.06 * strength), Color(InkPalette.INK, 0.06 * strength), z, z)
	_quad(Vector2(0, view.y), Vector2(view.x, view.y), Vector2(view.x, view.y - d), Vector2(0, view.y - d),
		Color(InkPalette.INK, 0.10 * strength), Color(InkPalette.INK, 0.10 * strength), z, z)
	var w := view.x * 0.12
	_quad(Vector2(0, 0), Vector2(w, 0), Vector2(w, view.y), Vector2(0, view.y),
		Color(InkPalette.INK, 0.04 * strength), z, z, Color(InkPalette.INK, 0.04 * strength))
	_quad(Vector2(view.x, 0), Vector2(view.x - w, 0), Vector2(view.x - w, view.y), Vector2(view.x, view.y),
		Color(InkPalette.INK, 0.04 * strength), z, z, Color(InkPalette.INK, 0.04 * strength))


## 远山两叠 + 一点朱日：随展卷渐显，藏于画卷之后。
func _draw_mountains(view: Vector2, appear: float) -> void:
	if appear <= 0.0:
		return
	_ridge(view, view.y * 0.64, 56.0, 0.0, Color(InkPalette.INK, 0.05 * appear))
	_ridge(view, view.y * 0.71, 40.0, 430.0, Color(InkPalette.INK, 0.08 * appear))
	draw_circle(Vector2(view.x * 0.84, view.y * 0.15), 30.0, Color(InkPalette.VERMILION, 0.10 * appear))


func _ridge(view: Vector2, base_y: float, amp: float, phase: float, color: Color) -> void:
	var pts := PackedVector2Array([Vector2(0.0, view.y)])
	for x in range(0, int(view.x) + 48, 48):
		var y := base_y + sin((x + phase) * 0.010) * amp + sin((x + phase) * 0.027 + 2.0) * amp * 0.35
		pts.append(Vector2(x, y))
	pts.append(Vector2(view.x, view.y))
	var cols := PackedColorArray()
	for i in range(pts.size()):
		cols.append(color)
	draw_polygon(pts, cols)


## 画卷主体：纸面随双轴自中央向两侧绽开；轴侧卷曲暗部 + 裱边 + 天杆地杆。
func _draw_scroll(open_ease: float) -> void:
	var rod_w := 20.0
	var half := rod_w + (_scroll.size.x / 2.0 - rod_w) * open_ease
	var paper := Rect2(_scroll.get_center().x - half, _scroll.position.y, half * 2.0, _scroll.size.y)
	# 纸下投影
	_quad(
		Vector2(paper.position.x + 10, paper.end.y + 6),
		Vector2(paper.end.x - 10, paper.end.y + 6),
		Vector2(paper.end.x - 2, paper.end.y + 20),
		Vector2(paper.position.x + 2, paper.end.y + 20),
		Color(InkPalette.INK, 0.10), Color(InkPalette.INK, 0.10), Color(InkPalette.INK, 0.0), Color(InkPalette.INK, 0.0))
	draw_rect(paper, InkPalette.PAPER_UI)
	# 纸纤维（确定性伪随机，横向淡痕）
	for i in range(6):
		var fy := paper.position.y + paper.size.y * (0.14 + 0.12 * i) + sin(i * 2.7) * 5.0
		var fx0 := paper.position.x + 24.0 + sin(i * 1.9) * 30.0
		var fx1 := minf(fx0 + 90.0 + i * 18.0, paper.end.x - 20.0)
		if fx1 - fx0 > 8.0:
			draw_line(Vector2(fx0, fy), Vector2(fx1, fy), Color(InkPalette.PAPER_SHADOW, 0.22), 1.0)
	_draw_curl(paper, true)
	_draw_curl(paper, false)
	# 裱边：上下深墨镶条
	draw_rect(Rect2(paper.position.x, paper.position.y, paper.size.x, 7.0), InkPalette.INK_DEEP)
	draw_rect(Rect2(paper.position.x, paper.end.y - 7.0, paper.size.x, 7.0), InkPalette.INK_DEEP)
	draw_rect(paper, InkPalette.INK, false, 2.0)
	_draw_rod(paper.position.x, paper.position.y, paper.size.y)
	_draw_rod(paper.end.x, paper.position.y, paper.size.y)


## 轴侧纸面卷曲的暗部（自轴向内渐隐）。
func _draw_curl(paper: Rect2, left: bool) -> void:
	var w := minf(38.0, paper.size.x * 0.25)
	var c := Color(InkPalette.INK, 0.13)
	var z := Color(InkPalette.INK, 0.0)
	if left:
		_quad(Vector2(paper.position.x, paper.position.y), Vector2(paper.position.x + w, paper.position.y),
			Vector2(paper.position.x + w, paper.end.y), Vector2(paper.position.x, paper.end.y), c, z, z, c)
	else:
		_quad(Vector2(paper.end.x, paper.position.y), Vector2(paper.end.x - w, paper.position.y),
			Vector2(paper.end.x - w, paper.end.y), Vector2(paper.end.x, paper.end.y), c, z, z, c)


## 天杆/地杆：深墨杆身 + 杆高光 + 两端朱芯轴头。
func _draw_rod(edge_x: float, top: float, height: float) -> void:
	var over := 24.0
	var w := 20.0
	draw_rect(Rect2(edge_x - w / 2.0, top - over, w, height + over * 2.0), InkPalette.INK_DEEP)
	draw_rect(Rect2(edge_x - w / 2.0 + 3.0, top - over + 4.0, 3.0, height + over * 2.0 - 8.0),
		Color(InkPalette.PAPER_UI, 0.22))
	for ky in [top - over, top + height + over]:
		draw_circle(Vector2(edge_x, ky), 12.0, InkPalette.INK)
		draw_circle(Vector2(edge_x, ky), 6.0, InkPalette.VERMILION)


## 题字落印 + 菜单浮出：竖排「山海行」逐字落墨，朱印压脚，随后菜单/题记/键提示浮出。
func _draw_ink() -> void:
	var ink_t := clampf((_t - UNROLL_TIME) / INK_TIME, 0.0, 1.0)
	var menu_t := clampf((_t - UNROLL_TIME - INK_TIME) / MENU_TIME, 0.0, 1.0)
	var font := get_theme_default_font()
	# 竖排题字（右侧题签位）：素笺衬底 + 逐字落墨 + 朱印压脚
	var fsize := int(minf(_scroll.size.y * 0.205, 84.0))
	var col_x := _scroll.end.x - fsize * 1.30
	var y0 := _scroll.position.y + fsize * 0.85
	var chars_bottom := y0 + (GAME_TITLE.length() - 1) * fsize * 1.02
	var seal_center := Vector2(col_x + fsize * 0.5, chars_bottom + fsize * 0.10 + 52.0)
	var slip_a := clampf(ink_t / 0.42, 0.0, 1.0)
	var slip := Rect2(
		col_x - fsize * 0.22,
		_scroll.position.y + fsize * 0.28,
		fsize * 1.44,
		seal_center.y + fsize * 0.30 - (_scroll.position.y + fsize * 0.28))
	draw_rect(slip, Color(InkPalette.PAPER_UI, 0.78 * slip_a))
	draw_rect(slip, Color(InkPalette.INK, 0.35 * slip_a), false, 1.5)
	var y := y0
	for i in range(GAME_TITLE.length()):
		var li := clampf((ink_t - 0.22 * i) / 0.42, 0.0, 1.0)
		if li <= 0.0:
			break
		draw_string(font, Vector2(col_x, y + (1.0 - li) * 12.0), GAME_TITLE[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(InkPalette.INK, li))
		y += fsize * 1.02
	# 朱印压脚（缩放落下）
	var sp := clampf((ink_t - 0.72) / 0.28, 0.0, 1.0)
	if sp > 0.0:
		var seal_scale := 1.0 + (1.0 - sp) * 0.55
		draw_set_transform(seal_center, 0.0, Vector2(seal_scale, seal_scale))
		draw_rect(Rect2(-19, -19, 38, 38), Color(InkPalette.VERMILION, sp))
		draw_rect(Rect2(-19, -19, 38, 38), Color(InkPalette.PAPER_UI, sp), false, 1.5)
		draw_string(font, Vector2(-13, 9), "行",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(InkPalette.PAPER_UI, sp))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 菜单 / 题记 / 键提示
	if menu_t > 0.0:
		var rise := (1.0 - menu_t) * 10.0
		for i in range(rows.size()):
			var text := String(rows[i]["text"])
			var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT).x
			var center: Vector2 = rows[i]["rect"].get_center() if rows[i].has("rect") else _scroll.get_center()
			var by := center.y + 7.0 + rise
			if i == _cursor:
				# 选中项：金色底带 + 朱红►（与列表菜单惯例一致，墨字保对比）
				draw_rect(Rect2(center.x - tw / 2.0 - 30.0, by - 21.0, tw + 60.0, 30.0),
					Color(InkPalette.GOLD, 0.30 * menu_t))
				draw_string(font, Vector2(center.x - tw / 2.0 - 24.0, by), "►",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(InkPalette.VERMILION, menu_t))
			draw_string(font, Vector2(center.x - tw / 2.0, by), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, Color(InkPalette.INK, menu_t))
		var tag := content.text("title_menu_tagline")
		var tagw: float = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, Vector2(_scroll.get_center().x - tagw / 2.0 + 24.0, _scroll.end.y - 28.0), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(InkPalette.INK_SOFT, menu_t))
		var hint := content.text("title_menu_hint")
		var hintw: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_draw_subtext(Vector2((_view.x - hintw) / 2.0, _scroll.end.y + 52.0), hint, menu_t)


## 卷外提示字色：深色背景贴图上用亮纸色，程序宣纸底上用中墨。
func _subtext_color(alpha: float) -> Color:
	if _bg_tex != null:
		return Color(InkPalette.PAPER, alpha)
	var base: Color = InkPalette.INK_SOFT
	return Color(base, alpha)


## 卷外提示：深色投影 + 本色字，深背景上保可读。
func _draw_subtext(pos: Vector2, text: String, alpha: float) -> void:
	var font := get_theme_default_font()
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(InkPalette.INK, 0.55 * alpha))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _subtext_color(alpha))


func _quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	draw_polygon(PackedVector2Array([p0, p1, p2, p3]), PackedColorArray([c0, c1, c2, c3]))


func _viewport_size() -> Vector2:
	var vp := get_viewport()
	var size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2.ZERO
	if size.x < 200.0 or size.y < 200.0:
		return Vector2(1280, 768)
	return size
