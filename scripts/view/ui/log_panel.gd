class_name UiLogPanel
extends UiPanel
## 左下消息日志：纸面半透明 + 最近 5 条（旧行淡墨）。

const KIND_COLORS := {
	"combat": Color("2B2620"), "warn": Color("B4652A"), "death": Color("C3272B"),
	"kill": Color("7A2E2E"), "loot": Color("8C5A3C"), "heal": Color("4A7C59"),
	"buff": Color("C9A662"), "levelup": Color("C9A662"), "info": Color("6E675C"),
	"summon": Color("3A5A6E"), "descend": Color("3A5A6E"),
}

var engine
var lines := 5


func setup(p_engine) -> void:
	engine = p_engine
	relayout(Vector2(1280, 768))


func relayout(view_size: Vector2) -> void:
	# 底部栈自下而上：技能栏(88) → 提示条(30) → 本日志；地图区居中
	var log_width: float = minf(680.0, view_size.x - 24.0)
	setup_ui(Rect2((view_size.x - log_width) / 2.0, view_size.y - 106 - 30 - 120 - 14.0, log_width, 120))


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if engine == null:
		return
	draw_rect(Rect2(panel_rect.position - Vector2(2, 2), panel_rect.size + Vector2(4, 4)), Color(PAPER, 0.82))
	draw_rect(panel_rect, INK, false, 1.5)
	var recent: Array = engine.messages.slice(maxi(0, engine.messages.size() - lines), engine.messages.size())
	var y := panel_rect.position.y + 22
	for i in range(recent.size()):
		var msg: Dictionary = recent[i]
		var color: Color = KIND_COLORS.get(String(msg["kind"]), INK)
		if i < recent.size() - 1:
			color = color.lerp(PAPER, 0.45)  # 旧行淡化
		draw_text_line(Vector2(panel_rect.position.x + 12, y), String(msg["text"]), color, 15)
		y += 22
