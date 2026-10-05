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

	# 6. 怪物专属技能：存在性 + 校验拒绝（绑空 id / 绑职业技能）
	failed += _check(
		content.skills.has("m_leiyin_zhua") and String(content.skills["m_leiyin_zhua"].get("class", "")) == "",
		"怪物专属技能 m_leiyin_zhua 应存在且 class 为空"
	)
	var probe = load("res://scripts/core/content_db.gd").new()
	probe.load_all("res://data/content")
	probe.monsters["xingxing"]["skills"] = ["skill_not_exist_42"]
	var probe_errors := PackedStringArray()
	probe._validate(probe_errors)
	failed += _check(
		_probe_errors_has(probe_errors, "绑定了不存在的技能"),
		"绑定不存在技能应报错: %s" % str(probe_errors)
	)
	probe.monsters["xingxing"]["skills"] = ["s_leifa_1"]
	probe_errors.clear()
	probe._validate(probe_errors)
	failed += _check(
		_probe_errors_has(probe_errors, "绑定了职业技能"),
		"绑定职业技能应报错: %s" % str(probe_errors)
	)

	# 7. 地图模型：FOV 对称性冒烟
	var map = load("res://scripts/core/game_map.gd").new(21, 21, 8)
	for x in range(21):
		for y in range(21):
			map.set_tile(x, y, 0)
	map.set_tile(10, 7, GameMap.T_MOUNTAIN)  # 一座山
	map.compute_fov(10, 10)
	failed += _check(map.is_visible(10, 10), "FOV 应含原点")
	failed += _check(not map.is_visible(10, 5), "山后直线应被遮挡")
	failed += _check(map.is_visible(12, 12), "开阔处应可见")

	# 8. 装备品级与套装不变式
	failed += _check(content.sets.has("kuafu"), "示例套装 kuafu 应注册")
	failed += _check(content.set_piece_total("kuafu") == 3, "夸父套装应 3 件（实际 %d）" % content.set_piece_total("kuafu"))
	var set_slots := {}
	for iid in content.items:
		var idef: Dictionary = content.items[iid]
		if idef.has("equipment") and String(idef.get("set_id", "")) == "kuafu":
			set_slots[String(idef["equipment"]["slot"])] = true
	failed += _check(set_slots.size() == 3, "同套槽位不得重复（%s）" % str(set_slots.keys()))
	# 运行时透传：品级缺省 common；非白品与套装标记到位
	failed += _check(String(content.build_item("w_taomu")["rarity"]) == "common", "白装缺省品级 common")
	failed += _check(String(content.build_item("w_xuanyuan")["rarity"]) == "mythic", "轩辕剑应为神品(红)")
	failed += _check(String(content.build_item("p_denglin").get("set_id", "")) == "kuafu", "邓林佩应携带套装标记")
	failed += _check(content.set_name("kuafu") == "夸父", "套装显示名本地化")
	# 校验拒绝探针：非法品级 / 未注册套装 / 同套槽位重复 / 档位超件数
	var rarity_probe = load("res://scripts/core/content_db.gd").new()
	rarity_probe.load_all("res://data/content")
	rarity_probe.items["w_taomu"]["rarity"] = "divine"
	var rarity_errors := PackedStringArray()
	rarity_probe._validate(rarity_errors)
	failed += _check(_probe_errors_has(rarity_errors, "品级"), "非法品级应报错: %s" % str(rarity_errors))
	rarity_probe.items["w_taomu"]["rarity"] = "common"
	rarity_probe.items["w_taomu"]["set_id"] = "set_not_exist_42"
	rarity_errors.clear()
	rarity_probe._validate(rarity_errors)
	failed += _check(_probe_errors_has(rarity_errors, "不存在的套装"), "未注册套装应报错: %s" % str(rarity_errors))
	rarity_probe.items["w_taomu"].erase("set_id")
	rarity_probe.items["p_denglin"]["equipment"]["slot"] = "boots"  # 与逐日履同槽
	rarity_errors.clear()
	rarity_probe._validate(rarity_errors)
	failed += _check(_probe_errors_has(rarity_errors, "槽位"), "同套槽位重复应报错: %s" % str(rarity_errors))
	rarity_probe.items["p_denglin"]["equipment"]["slot"] = "amulet"
	rarity_probe.sets["kuafu"]["tiers"]["4"] = {"bonuses": {"power": 1}}  # 超过 3 件
	rarity_errors.clear()
	rarity_probe._validate(rarity_errors)
	failed += _check(_probe_errors_has(rarity_errors, "超过件数"), "档位超件数应报错: %s" % str(rarity_errors))

	# 9. 加权掉落：白装显著多于橙红；tier 门槛仍生效（低层不出高 tier 件）
	var drop_rng := RandomNumberGenerator.new()
	drop_rng.seed = 42
	var rarity_hits := {}
	for _i in range(600):
		var drop_id: String = content.random_equipment_id(20, drop_rng)
		var rarity := String(content.items[drop_id].get("rarity", "common"))
		rarity_hits[rarity] = int(rarity_hits.get(rarity, 0)) + 1
	failed += _check(int(rarity_hits.get("common", 0)) > int(rarity_hits.get("legendary", 0)),
		"白装应多于橙装（%s）" % str(rarity_hits))
	failed += _check(int(rarity_hits.get("common", 0)) + int(rarity_hits.get("magic", 0)) > int(rarity_hits.get("mythic", 0)) * 4,
		"红装应显著稀少（%s）" % str(rarity_hits))
	var low_tier_hit := false
	for _i in range(200):
		var low_id: String = content.random_equipment_id(1, drop_rng)
		if int(content.items[low_id].get("tier", 1)) > 2:
			low_tier_hit = true
	failed += _check(not low_tier_hit, "低层（cap=2）不得掉出高 tier 件")

	if failed > 0:
		print("FAIL 共 %d 项未过" % failed)
		quit(1)
	else:
		print("PASS 全部冒烟测试")
		quit(0)


func _probe_errors_has(errors: PackedStringArray, needle: String) -> bool:
	for e in errors:
		if e.contains(needle):
			return true
	return false


func _check(ok: bool, what: String) -> int:
	if ok:
		return 0
	print("FAIL %s" % what)
	return 1
