class_name UiTooltip
extends UiPanel
## 全局悬浮说明：技能（名称/重数/耗气灵/效果摘要/五行/绑定键位/描述）与
## 物品（品级色标题/槽位品级/伤害面/加成词条/套装档位/同槽对比/典故）。
## 由主场景在技能栏、编排面板或角色面板上悬停时驱动；贴锚点显示并夹在视口内。

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
	out.append({"text": title, "color": InkPalette.INK, "size": 17})
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
		out.append({"text": meta, "color": InkPalette.GOLD, "size": 13})
	# 五行与绑定
	var element := Skills.skill_element(skill)
	var tags_line := ""
	if element != "":
		tags_line += "五行·" + engine.content.text("element_" + element)
	if bound_label != "":
		tags_line += ("  " if tags_line != "" else "") + "已绑 " + bound_label
	if tags_line != "":
		out.append({"text": tags_line, "color": InkPalette.INK_SOFT, "size": 12})
	# 未学技能：前置链提示
	var skill_id := String(skill.get("id", ""))
	if not player.skill_levels.has(skill_id) and skill.has("requires"):
		var names: Array = []
		for req in skill["requires"]:
			if not player.skill_levels.has(String(req)) and engine.content.skills.has(String(req)):
				names.append(engine.content.localize(engine.content.skills[String(req)]["name"]))
		if not names.is_empty():
			out.append({"text": "前置：" + "、".join(names), "color": InkPalette.VERMILION, "size": 12})
	# 描述折行（CJK 按字符宽折）
	var desc: String = engine.content.localize(skill.get("desc", ""))
	for line in _wrap_cjk(desc, 20):
		out.append({"text": line, "color": InkPalette.INK, "size": 13})
	return out


func show_skill(skill: Dictionary, player: Actor, pos: Vector2, bound_label := "") -> void:
	lines = build_lines(skill, player, bound_label)
	anchor = pos
	visible = true
	queue_redraw()


# ---- 物品悬浮 ----

## 组装某物品（装备/消耗品/材料）的悬浮行（headless 可测）。
func build_item_lines(item: Dictionary, player: Actor) -> Array:
	var out: Array = []
	var is_gear := item.has("slot")
	out.append({"text": String(item["label"]), "color": UiPanel.rarity_color(item, InkPalette.INK), "size": 17})
	if is_gear:
		var meta: String = engine.content.text("slot_" + String(item["slot"]))
		meta += " · " + String(UiPanel.RARITY_LABELS.get(String(item.get("rarity", "common")), ""))
		out.append({"text": meta, "color": InkPalette.GOLD, "size": 13})
	if item.has("damage"):
		out.append({"text": _item_brief(item), "color": InkPalette.GOLD, "size": 13})
	var bonus_parts: Array = []
	for key in ["power", "defense", "max_hp", "max_mp", "max_sp"]:
		var value := int(item.get("bonuses", {}).get(key, 0))
		if value > 0:
			bonus_parts.append(engine.content.text("bon_" + key).format({"v": value}))
	if not bonus_parts.is_empty():
		out.append({"text": " ".join(bonus_parts), "color": InkPalette.GOLD, "size": 13})
	var affix_parts: Array = []
	for affix in item.get("affixes", []):
		affix_parts.append(engine.content.text("aff_" + String(affix["id"])).format({"v": int(affix["value"])}))
	if not affix_parts.is_empty():
		out.append({"text": " · ".join(affix_parts), "color": InkPalette.GOLD, "size": 13})
	if item.has("consumable"):
		var summary := Consumables.summary(engine, item)
		if summary != "":
			out.append({"text": summary, "color": InkPalette.GOLD, "size": 13})
	# 同槽对比：行囊中悬停装备时提示身上现役
	if is_gear and not player.equipment.is_equipped(item):
		var worn = player.equipment.slots.get(String(item["slot"]))
		if worn != null:
			out.append({"text": "已装备：%s（%s）" % [String(worn["label"]), _item_brief(worn)],
				"color": InkPalette.INK_SOFT, "size": 12})
	# 套装块：名称 + 持有计数 + 各档位激活态（✓ 已激活 / · 未激活）
	var set_id := String(item.get("set_id", ""))
	if set_id != "" and engine.content.sets.has(set_id):
		var owned := _set_owned_count(player, set_id)
		out.append({"text": "%s套装 · %d/%d" % [
			engine.content.set_name(set_id), owned, engine.content.set_piece_total(set_id),
		], "color": InkPalette.SET_COLOR, "size": 13})
		var tiers: Dictionary = engine.content.sets[set_id].get("tiers", {})
		var threshold_texts: Array = tiers.keys()
		threshold_texts.sort_custom(func(a, b): return int(a) < int(b))
		for threshold_text in threshold_texts:
			var active := int(threshold_text) <= owned
			out.append({
				"text": "%s %d件：%s" % ["✓" if active else "·", int(threshold_text), _tier_brief(tiers[threshold_text])],
				"color": InkPalette.SET_COLOR if active else InkPalette.INK_SOFT, "size": 12,
			})
	# 典故折行（运行时 dict 不带 lore，按 id 回查定义）
	var idef: Dictionary = engine.content.items.get(String(item["id"]), {})
	if idef.has("lore"):
		for line in _wrap_cjk(engine.content.localize(idef["lore"]), 20):
			out.append({"text": line, "color": InkPalette.INK_SOFT, "size": 12})
	return out


func show_item(item: Dictionary, player: Actor, pos: Vector2) -> void:
	lines = build_item_lines(item, player)
	anchor = pos
	visible = true
	queue_redraw()


## 一句话物品概要（对比行用）：武器=伤害面，防具=加成，消耗品=摘要。
func _item_brief(item: Dictionary) -> String:
	if item.has("damage"):
		var d: Dictionary = item["damage"]
		var brief := "物%d" % int(d["physical"])
		if String(d.get("element", "")) != "":
			brief += "·" + engine.content.text("element_" + String(d["element"]))
		return brief
	var parts: Array = []
	for key in ["power", "defense", "max_hp", "max_mp", "max_sp"]:
		var value := int(item.get("bonuses", {}).get(key, 0))
		if value > 0:
			parts.append(engine.content.text("bon_" + key).format({"v": value}))
	return " ".join(parts)


## 套装档位加成描述（激活/未激活两态共用）。
func _tier_brief(tier: Dictionary) -> String:
	var parts: Array = []
	for key in tier.get("bonuses", {}):
		parts.append(engine.content.text("bon_" + String(key)).format({"v": int(tier["bonuses"][key])}))
	for affix in tier.get("affixes", []):
		parts.append(engine.content.text("aff_" + String(affix["id"])).format({"v": int(affix["value"])}))
	return "，".join(parts)


## 同套持有件数（行囊 + 已穿戴）。
func _set_owned_count(player: Actor, set_id: String) -> int:
	var count := 0
	for held in player.inventory.items:
		if String(held.get("set_id", "")) == set_id:
			count += 1
	for worn in player.equipment.equipped_items():
		if String(worn.get("set_id", "")) == set_id:
			count += 1
	return count


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
	draw_rect(Rect2(rect.position - Vector2(2, 2), rect.size + Vector2(4, 4)), Color(InkPalette.INK, 0.35))
	draw_rect(rect, InkPalette.PAPER_UI)
	draw_rect(rect, InkPalette.INK, false, 1.4)
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
