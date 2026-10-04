extends SceneTree
## Headless 冒烟测试：godot --headless -s tests/test_content.gd --path <工程>
## 校验内容加载、五行/武器/职业灵力等核心不变式（Python 版 260 测试契约的首批移植）。


func _init() -> void:
	var failed := 0
	var content = load("res://scripts/core/content_db.gd").new()

	# 1. 内容全量加载+校验
	var errors: PackedStringArray = content.load_all("res://data/content")
	if not errors.is_empty():
		print("FAIL 内容校验 %d 项:" % errors.size())
		for e in errors:
			print("  - " + e)
		quit(1)
		return
	print("PASS 内容加载与校验（职业 %d / 技能 %d / 怪物 %d / 物品 %d）" % [
		content.classes.size(), content.skills.size(),
		content.monsters.size(), content.items.size(),
	])

	# 2. 五行不变式
	failed += _check(content.ELEMENTS.size() == 5, "五行应为 5 种")
	failed += _check(
		content.ELEMENT_BEATS["metal"] == "wood" and content.ELEMENT_BEATS["fire"] == "metal",
		"生克链：金克木 / 火克金"
	)
	var with_element := 0
	for mid in content.monsters:
		if String(content.monsters[mid].get("element", "")) != "":
			with_element += 1
	failed += _check(with_element == content.monsters.size(), "全部怪物应有本命五行")

	# 3. 武器伤害面不变式
	var weapons := 0
	for iid in content.items:
		var gear = content.items[iid].get("equipment")
		if gear == null or String(gear.get("slot", "")) != "weapon":
			continue
		weapons += 1
		var damage: Dictionary = gear.get("damage", {})
		failed += _check(
			damage.get("physical", 0) is float and damage["physical"] > 0,
			"武器 %s 物理伤害必须为正" % iid
		)
		failed += _check(
			gear.get("bonuses", {}).is_empty() and gear.get("affixes", []).is_empty(),
			"武器 %s 不得带加成/词条" % iid
		)
	failed += _check(weapons >= 10, "武器应 ≥10 把")

	# 4. 职业灵力 + 技能结构
	for cid in content.classes:
		failed += _check(content.classes[cid].get("sp") is float, "职业 %s 应有灵力字段" % cid)
	var skill_count := {}
	for sid in content.skills:
		var owner: String = content.skills[sid]["class"]
		skill_count[owner] = skill_count.get(owner, 0) + 1
	for cid in content.classes:
		failed += _check(skill_count.get(cid, 0) == 8, "职业 %s 应有 8 技能" % cid)

	# 5. 文案关键键存在
	for key in ["hud_sp", "counter_up", "weapon_summary_element", "element_metal"]:
		failed += _check(content.strings.has(key), "文案缺少 %s" % key)

	# 6. 地图模型：FOV 对称性冒烟
	var map = load("res://scripts/core/game_map.gd").new(21, 21, 8)
	for x in range(21):
		for y in range(21):
			map.set_tile(x, y, 0)
	map.set_tile(10, 7, GameMap.T_MOUNTAIN)  # 一座山
	map.compute_fov(10, 10)
	failed += _check(map.is_visible(10, 10), "FOV 应含原点")
	failed += _check(not map.is_visible(10, 5), "山后直线应被遮挡")
	failed += _check(map.is_visible(12, 12), "开阔处应可见")

	if failed > 0:
		print("FAIL 共 %d 项未过" % failed)
		quit(1)
	else:
		print("PASS 全部冒烟测试")
		quit(0)


func _check(ok: bool, what: String) -> int:
	if ok:
		return 0
	print("FAIL %s" % what)
	return 1
