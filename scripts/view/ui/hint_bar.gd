class_name UiHintBar
extends UiPanel
## 上下文提示条：地图视口底部居中，只显示当前状态下有效的操作。
## 优先级：陨落 > 交互物（门/山径/物品）> 低血服丹 > 贴身敌 > 默认。

const BAR_WIDTH := 480.0
const BAR_HEIGHT := 30.0
const HEAL_HINT_RATIO := 0.45

var engine


func setup(p_engine) -> void:
	engine = p_engine
	relayout(_viewport_size())


func relayout(view_size: Vector2) -> void:
	# 底部栈：技能栏(88) 之上、消息日志之下，地图区居中
	setup_ui(Rect2(
		(view_size.x - minf(BAR_WIDTH, view_size.x - 24.0)) / 2.0,
		view_size.y - 76.0 - BAR_HEIGHT - 12.0,
		minf(BAR_WIDTH, view_size.x - 24.0), BAR_HEIGHT))
	queue_redraw()


func refresh() -> void:
	queue_redraw()


## 纯逻辑：当前情境提示文本（headless 可测）。
func current_hint() -> String:
	if engine == null:
		return ""
	var player = engine.player()
	if engine.game_over:
		return engine.content.text("hint_game_over")
	var xy := Vector2i(player.x, player.y)
	var map = engine.state.current
	# 脚下交互物
	if map.map_type == "world":
		var gate: Dictionary = map.gate_at(xy.x, xy.y)
		if not gate.is_empty():
			var realm_name: String = engine.content.localize(engine.content.realms[gate["realm_id"]]["name"])
			return "E " + engine.content.text("hint_enter_realm").format({"name": realm_name})
	else:
		if xy == map.downstairs_xy:
			return "E " + engine.content.text("hint_descend")
		if xy == map.upstairs_xy:
			return "Q " + (engine.content.text("hint_realm_exit") if map.realm_depth <= 1 else engine.content.text("hint_realm_ascend"))
	var item: Dictionary = map.item_at(xy.x, xy.y)
	if not item.is_empty():
		return "G " + engine.content.text("hint_pickup").format({"item": item["label"]})
	# 低气血且行囊有疗伤丹
	if float(player.fighter.hp()) / maxf(1.0, player.fighter.max_hp()) < HEAL_HINT_RATIO:
		for held in player.inventory.items:
			if String(held.get("consumable", {}).get("type", "")) == "heal":
				return "I " + engine.content.text("hint_heal")
	# 贴身可见敌
	for actor in map.actors:
		if actor.team != "player" and actor.is_alive() and maxi(absi(actor.x - xy.x), absi(actor.y - xy.y)) <= 1:
			if map.is_visible(actor.x, actor.y):
				return engine.content.text("hint_melee")
	return engine.content.text("hint_default")


func _draw() -> void:
	var hint := current_hint()
	if hint == "":
		return
	draw_rect(Rect2(panel_rect.position - Vector2(2, 2), panel_rect.size + Vector2(4, 4)), Color(PAPER, 0.88))
	draw_rect(panel_rect, INK, false, 1.2)
	draw_text_line(panel_rect.position + Vector2(14, 20), hint, INK_SOFT, 14)
