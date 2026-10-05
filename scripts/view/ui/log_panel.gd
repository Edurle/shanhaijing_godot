class_name UiLogPanel
extends UiPanel
## 左下消息日志：无底透明，最近 5 条直接浮在地图上（旧行淡墨）。

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
	# 贴最左侧（与左上资源 HUD 同列）；纵向仍在底部居中栈（技能栏→提示条）之上
	var log_width: float = minf(680.0, view_size.x - 32.0)
	setup_ui(Rect2(16.0, view_size.y - 106 - 30 - 120 - 14.0, log_width, 120))


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if engine == null:
		return
	var recent: Array = engine.messages.slice(maxi(0, engine.messages.size() - lines), engine.messages.size())
	var font := get_theme_default_font()
	var y := panel_rect.position.y + 22
	for i in range(recent.size()):
		var msg: Dictionary = recent[i]
		var faded := i < recent.size() - 1
		if msg.has("segments"):
			# 物品名按品级着色（段色由模型层 rarity 标记解析），逐段拼接绘制
			var x := panel_rect.position.x + 12
			for segment in msg["segments"]:
				var seg_text := String(segment["text"])
				var color := UiPanel.rarity_color(segment, KIND_COLORS.get(String(msg["kind"]), INK))
				if faded:
					color = color.lerp(PAPER, 0.45)  # 旧行淡化
				draw_string(font, Vector2(x, y), seg_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
				x += font.get_string_size(seg_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		else:
			var color: Color = KIND_COLORS.get(String(msg["kind"]), INK)
			if faded:
				color = color.lerp(PAPER, 0.45)  # 旧行淡化
			draw_text_line(Vector2(panel_rect.position.x + 12, y), String(msg["text"]), color, 15)
		y += 22
