class_name UiTooltip
extends UiPanel
## 全局技能悬浮说明：名称/重数/耗气灵/效果摘要/五行/绑定键位/描述（自动折行）。
## 由主场景在技能栏或编排面板上悬停时驱动；贴锚点显示并夹在视口内。

const WIDTH := 300.0

var engine
var anchor := Vector2.ZERO
var lines: Array = []  # [{text, color, size}]
var _view_size := Vector2(1280, 768)


func setup(p_engine) -> void:
	engine = p_engine


## 组装某技能的说明行（headless 可测）。
func build_lines(skill: Dictionary, player: Actor, bound_label := "") -> Array:
	var out: Array = []
	var level: int = player.skill_levels.get(String(skill.get("id", "")), 0)
	var title: String = engine.content.localize(skill["name"])
	if level > 1:
		title += " · %d 重" % level
	out.append({"text": title, "color": INK, "size": 17})
	# 耗与摘要
	var cost := ""
	var mp_need := Skills.mp_cost(player, skill)
	if mp_need > 0:
		cost += "%d气 " % mp_need
	var sp_need := Skills.sp_cost(player, skill)
	if sp_need > 0:
		cost += "%d灵" % sp_need
	var summary := Skills.summary(engine, player, skill)
	var meta := summary
	if cost != "":
		meta = (summary + "  " if summary != "" else "") + cost
	if meta != "":
		out.append({"text": meta, "color": GOLD, "size": 13})
	# 五行与绑定
	var element := Skills.skill_element(skill)
	var tags_line := ""
	if element != "":
		tags_line += "五行·" + engine.content.text("element_" + element)
	if bound_label != "":
		tags_line += ("  " if tags_line != "" else "") + "已绑 " + bound_label
	if tags_line != "":
		out.append({"text": tags_line, "color": INK_SOFT, "size": 12})
	# 未学技能：前置链提示
	var skill_id := String(skill.get("id", ""))
	if not player.skill_levels.has(skill_id) and skill.has("requires"):
		var names: Array = []
		for req in skill["requires"]:
			if not player.skill_levels.has(String(req)) and engine.content.skills.has(String(req)):
				names.append(engine.content.localize(engine.content.skills[String(req)]["name"]))
		if not names.is_empty():
			out.append({"text": "前置：" + "、".join(names), "color": VERMILION, "size": 12})
	# 描述折行（CJK 按字符宽折）
	var desc: String = engine.content.localize(skill.get("desc", ""))
	for line in _wrap_cjk(desc, 20):
		out.append({"text": line, "color": INK, "size": 13})
	return out


func show_skill(skill: Dictionary, player: Actor, pos: Vector2, bound_label := "") -> void:
	lines = build_lines(skill, player, bound_label)
	anchor = pos
	visible = true
	queue_redraw()


func hide_panel() -> void:
	visible = false


func set_view_size(size: Vector2) -> void:
	_view_size = size
	queue_redraw()


func panel_height() -> float:
	return 26.0 + lines.size() * 22.0 + 10.0


func _draw() -> void:
	if lines.is_empty():
		return
	var height := panel_height()
	var x: float = clampf(anchor.x + 18.0, 8.0, _view_size.x - WIDTH - 8.0)
	var y: float = clampf(anchor.y - 6.0, 8.0, _view_size.y - height - 8.0)
	var rect := Rect2(x, y, WIDTH, height)
	draw_rect(Rect2(rect.position - Vector2(2, 2), rect.size + Vector2(4, 4)), Color(INK, 0.35))
	draw_rect(rect, PAPER)
	draw_rect(rect, INK, false, 1.4)
	var font := get_theme_default_font()
	var ly := y + 24.0
	for line in lines:
		draw_string(font, Vector2(x + 12, ly), String(line["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(line["size"]), line["color"])
		ly += 22.0


## CJK 按字符数折行（20 字/行，兼顾标点不断裂的最简实现）。
func _wrap_cjk(text: String, per_line: int) -> Array:
	var out: Array = []
	if text == "":
		return out
	while text.length() > per_line:
		out.append(text.substr(0, per_line))
		text = text.substr(per_line)
	if text != "":
		out.append(text)
	return out
