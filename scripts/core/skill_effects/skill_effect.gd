class_name SkillEffect
extends RefCounted
## 技能效果基类：perform 内完成结算，返回错误串（空 = 成功）。
## 不处理耗气/灵力（Skills.cast 统一扣）；"need_target"/"need_direction" 为控制流信号。

var needs_target := false
var needs_direction := false


func perform(_engine, _actor: Actor, _skill: Dictionary, _target = null) -> String:
	return "not_implemented"
