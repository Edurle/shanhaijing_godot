shader_type canvas_item;
// 水墨地形场（方案C）：像素级连续的地形渲染——格子只存在于数据纹理里，
// 画面里只有"场与笔"。覆盖全图的 quad，Board 自绘层（皴笔/楼梯/门/单位）叠在其上。
//
// 数据纹理（每格1px，RGBA8）：R=地形id，G=雾态（0未探索/1记忆/2可见）。
// 水面：双层水纹贴图错向慢滚 + 噪声域扭曲（线有机摆动）+ 整域呼吸（一片水一条命）。
// 湿边：像素到岸距离的渗带（四邻水陆判定），替代格子边的三段条。

uniform sampler2D data_tex : filter_nearest;
uniform sampler2D paper_tex : repeat_enable;
uniform sampler2D water_a : repeat_enable;
uniform sampler2D water_b : repeat_enable;
uniform vec2 map_size = vec2(240.0, 150.0);
uniform float cell_px = 32.0;
uniform float time = 0.0;
uniform vec4 terrain_colors[12];
uniform float wash_alpha[12];
uniform vec4 fog_color = vec4(0.725, 0.698, 0.635, 1.0);
uniform float fog_lerp = 0.45;
uniform float grain_strength = 0.05;

const int WATER = 6;
const int RIVER = 7;
const int ABYSS = 9;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


float cell_kind(vec2 cell) {
	return texture(data_tex, (cell + 0.5) / map_size).r * 255.0;
}


bool is_shore(vec2 cell) {
	// 图外界当岸（地图边缘有渗边）；渊不算岸（水连渊不渗）
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= map_size.x || cell.y >= map_size.y) {
		return true;
	}
	float k = cell_kind(cell);
	return k != float(WATER) && k != float(RIVER) && k != float(ABYSS);
}


void fragment() {
	vec2 world_px = UV * map_size * cell_px;
	vec2 cell_f = world_px / cell_px;
	vec2 cell = floor(cell_f);
	vec2 in_cell = fract(cell_f);
	vec4 field = texture(data_tex, (cell + 0.5) / map_size);
	int k = int(field.r * 255.0 + 0.5);
	float fog = field.g * 255.0;

	// 整幅宣纸：留白即未探索（纸纹四方连续）
	vec3 col = texture(paper_tex, world_px / 256.0).rgb;

	if (fog > 0.5) {
		vec3 base = terrain_colors[k].rgb;
		float alpha = wash_alpha[k];

		// 连续明度颗粒（像素尺度双倍频，色斑跨格——消瓷砖感的关键）
		float grain = (vnoise(world_px * 0.13) - 0.5) + (vnoise(world_px * 0.031) - 0.5) * 0.7;
		base *= 1.0 + grain * grain_strength;

		if (k == WATER || k == RIVER) {
			// 域扭曲：线随噪声有机摆动，不是机械平移
			vec2 warp = vec2(
				vnoise(world_px * 0.008 + vec2(time * 0.05, 0.0)),
				vnoise(world_px * 0.008 + vec2(0.0, 27.0 - time * 0.04))
			) - 0.5;
			// 双层错向慢滚（2.5px/s 与 1.2px/s：墨迹未干的时间感）
			vec2 uv_a = (world_px + warp * 24.0 + vec2(time * 2.5, time * 0.3)) / 512.0;
			vec2 uv_b = (world_px + warp * 18.0 + vec2(-time * 1.2, time * 0.15)) / 512.0;
			float lines = texture(water_a, uv_a).a * 0.65 + texture(water_b, uv_b).a * 0.45;
			base *= 1.0 - clamp(lines, 0.0, 1.0) * 0.38;
			// 整域呼吸（无世界项=全域同相：一片水是一个整体）
			alpha *= 1.0 + 0.05 * sin(time * 0.35);

			// 湿边：像素到岸距离的渗带
			float edge = 0.0;
			if (is_shore(cell + vec2(1.0, 0.0))) {
				edge = max(edge, 1.0 - (1.0 - in_cell.x) * cell_px / 6.0);
			}
			if (is_shore(cell + vec2(-1.0, 0.0))) {
				edge = max(edge, 1.0 - in_cell.x * cell_px / 6.0);
			}
			if (is_shore(cell + vec2(0.0, 1.0))) {
				edge = max(edge, 1.0 - (1.0 - in_cell.y) * cell_px / 6.0);
			}
			if (is_shore(cell + vec2(0.0, -1.0))) {
				edge = max(edge, 1.0 - in_cell.y * cell_px / 6.0);
			}
			base *= 1.0 - clamp(edge, 0.0, 1.0) * 0.22;
		}

		col = mix(col, base, clamp(alpha, 0.0, 1.0));
		if (fog < 1.5) {
			col = mix(col, fog_color.rgb, fog_lerp);  // 记忆态罩灰墨
		}
	}
	COLOR = vec4(col, 1.0);
}
