shader_type canvas_item;
// 水墨地形场：像素级连续的地形渲染——格子只存在于数据纹理里，画面里只有"场与笔"。
// 覆盖全图的 quad，Board 自绘层（皴笔/楼梯/门/单位）叠在其上。
//
// 数据纹理（每格1px，RGBA8）：R=地形id，G=雾态（0未探索/1记忆/2可见）。
// 消棱角三件套：
//   1) 域扭曲——采样位置沿低频噪声扭动（±7px），水岸彻底离开格线；
//   2) 四角双线性+锐化——相邻地形颜色 8px 有机曲线过渡，无阶梯；
//   3) 雾态连续化——未探索/记忆的边界也变成晕开的软边。
// 水面：AI 水纹贴图双层错向慢滚 + 噪声域扭曲 + 整域呼吸；湿边随双线性水性权重走。

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
const float WARP_AMP = 7.0;   // 域扭曲幅度（px，小于半格：视觉不越出逻辑格）
const float SHARPEN = 4.0;    // 过渡带收窄（过渡宽 ≈ cell_px/SHARPEN ≈ 8px）


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


vec3 kind_color(vec4 d) {
	return terrain_colors[int(d.r * 255.0 + 0.5)].rgb;
}


float kind_alpha(vec4 d) {
	return wash_alpha[int(d.r * 255.0 + 0.5)];
}


float water_flag(vec4 d) {
	float k = d.r * 255.0;
	return (k == float(WATER) || k == float(RIVER)) ? 1.0 : 0.0;
}


void fragment() {
	vec2 world_px = UV * map_size * cell_px;

	// 域扭曲：边界沿低频噪声扭动——水岸彻底离开格线
	vec2 warp = (vec2(
		vnoise(world_px * 0.045),
		vnoise(world_px * 0.045 + vec2(37.0, 11.0))
	) - 0.5) * WARP_AMP;
	vec2 pos = world_px + warp;
	vec2 cell = floor(pos / cell_px);
	vec2 f = fract(pos / cell_px);

	// 四角采样 + 锐化双线性：地形/雾/水性全走连续场
	vec2 fs = clamp((f - 0.5) * SHARPEN + 0.5, 0.0, 1.0);
	vec4 d00 = texture(data_tex, (cell + vec2(0.5, 0.5)) / map_size);
	vec4 d10 = texture(data_tex, (cell + vec2(1.5, 0.5)) / map_size);
	vec4 d01 = texture(data_tex, (cell + vec2(0.5, 1.5)) / map_size);
	vec4 d11 = texture(data_tex, (cell + vec2(1.5, 1.5)) / map_size);
	float fog_f = mix(mix(d00.g, d10.g, fs.x), mix(d01.g, d11.g, fs.x), fs.y) * 255.0;
	float waterness = mix(mix(water_flag(d00), water_flag(d10), fs.x),
		mix(water_flag(d01), water_flag(d11), fs.x), fs.y);

	// 整幅宣纸：留白即未探索（纸纹四方连续）
	vec3 col = texture(paper_tex, world_px / 256.0).rgb;

	// 洗染：四角颜色双线性，明度颗粒像素尺度（消瓷砖感）
	vec3 base = mix(mix(kind_color(d00), kind_color(d10), fs.x),
		mix(kind_color(d01), kind_color(d11), fs.x), fs.y);
	float alpha = mix(mix(kind_alpha(d00), kind_alpha(d10), fs.x),
		mix(kind_alpha(d01), kind_alpha(d11), fs.x), fs.y);
	float grain = (vnoise(world_px * 0.13) - 0.5) + (vnoise(world_px * 0.031) - 0.5) * 0.7;
	base *= 1.0 + grain * grain_strength;

	if (waterness > 0.02) {
		// 水纹：双层错向慢滚（2.5/1.2px每秒：墨迹未干的时间感）+ 噪声域扭曲
		vec2 wob = vec2(
			vnoise(world_px * 0.008 + vec2(time * 0.05, 0.0)),
			vnoise(world_px * 0.008 + vec2(0.0, 27.0 - time * 0.04))
		) - 0.5;
		vec2 uv_a = (world_px + wob * 24.0 + vec2(time * 2.5, time * 0.3)) / 512.0;
		vec2 uv_b = (world_px + wob * 18.0 + vec2(-time * 1.2, time * 0.15)) / 512.0;
		float lines = texture(water_a, uv_a).a * 0.65 + texture(water_b, uv_b).a * 0.45;
		base *= 1.0 - clamp(lines, 0.0, 1.0) * 0.38 * waterness;
		// 整域呼吸（无世界项=全域同相：一片水是一个整体）
		alpha *= 1.0 + 0.05 * sin(time * 0.35) * waterness;
		// 湿边：双线性水性权重 × 到（扭曲后）最近格边的距离——边界最深处一线沉积
		float dist_edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * cell_px;
		float edge = clamp(waterness * (1.0 - waterness) * 4.0, 0.0, 1.0)
			* clamp(1.0 - dist_edge / 6.0, 0.0, 1.0);
		base *= 1.0 - edge * 0.30;
	}

	// 雾态连续化：可见度把洗染淡出到纸（未探索=纯留白），记忆态罩灰墨
	alpha *= clamp(fog_f * 0.5, 0.0, 1.0);
	col = mix(col, base, clamp(alpha, 0.0, 1.0));
	float memory = clamp(2.0 - fog_f, 0.0, 1.0);
	col = mix(col, fog_color.rgb, memory * fog_lerp);

	COLOR = vec4(col, 1.0);
}
