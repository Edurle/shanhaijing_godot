class_name UiDragGhost
extends UiPanel
## 拖拽幽灵：按住技能图标拖动时跟随鼠标的半透明汉字图标。


var skill: Dictionary = {}
var engine


func setup(p_engine) -> void:
	engine = p_engine


func begin_drag(p_skill: Dictionary) -> void:
	skill = p_skill
	visible = true
	queue_redraw()


func end_drag() -> void:
	visible = false
	skill = {}


func _draw() -> void:
	if skill.is_empty():
		return
	var mouse := get_viewport().get_mouse_position() if get_viewport() != null else Vector2.ZERO
	var rect := Rect2(mouse - Vector2(25, 25), Vector2(50, 50))
	draw_rect(rect, Color(InkPalette.PAPER_UI, 0.85))
	draw_rect(rect, InkPalette.INK, false, 1.6)
	var icon_color: Color = InkPalette.INK
	var element := Skills.skill_element(skill)
	if element != "":
		icon_color = _element_color(element)
	var font := get_theme_default_font()
	draw_string(font, rect.position + Vector2(14, 32), UiSkillBar.icon_char(engine, skill),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, icon_color)


func _element_color(element: String) -> Color:
	return InkPalette.ELEMENT_COLORS.get(element, InkPalette.INK)
