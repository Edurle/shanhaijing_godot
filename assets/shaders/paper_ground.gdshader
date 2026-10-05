shader_type canvas_item;
// 水墨地形场：像素级连续的地形渲染——格子只存在于数据纹理里，画面里只有"场与笔"。
// 覆盖全图的 quad，Board 自绘层（皴笔/楼梯/门/单位）叠在其上。
//
// 数据纹理（每格1px，RGBA8）：R=地形id，G=雾态（0未探索/1记忆/2可见）。
// 曲线化三件套：
//   1) 两尺度域扭曲——大弯（±11px 低频：湖岸走势）+ 细摆（±4px 高频：岸边波纹），
//      边界彻底离开格线且有"走势+波纹"两级节奏；
//   2) 4×4 邻域十字软化——角点值掺入四邻均值，磨掉四格交角的"角感"；
//   3) smoothstep 过渡——锐化收窄（~8px）后两端润化，无锯齿无硬折。
// 雾态连续化：未探索/记忆边界晕开成软边。水面：AI 水纹双层错向慢滚 + 整域呼吸。

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


vec4 field_at(vec2 cell) {
	return texture(data_tex, (cell + 0.5) / map_size);
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


// 十字软化：角点 0.5 + 四邻各 0.125（磨四格交角）
float soft5(float a[16], int i) {
	return a[i] * 0.5 + (a[i + 1] + a[i - 1] + a[i + 4] + a[i - 4]) * 0.125;
}


vec3 soft5v(vec3 a[16], int i) {
	return a[i] * 0.5 + (a[i + 1] + a[i - 1] + a[i + 4] + a[i - 4]) * 0.125;
}


void fragment() {
	vec2 world_px = UV * map_size * cell_px;

	// 两尺度域扭曲：大弯定走势，细摆生波纹
	vec2 warp = (vec2(
		vnoise(world_px * 0.008),
		vnoise(world_px * 0.008 + vec2(37.0, 11.0))
	) - 0.5) * 11.0;
	warp += (vec2(
		vnoise(world_px * 0.05),
		vnoise(world_px * 0.05 + vec2(113.0, 71.0))
	) - 0.5) * 4.0;
	vec2 pos = world_px + warp;
	vec2 cell = floor(pos / cell_px);
	vec2 f = fract(pos / cell_px);

	// 4×4 邻域一次采样解码（四角格及其四邻），角点十字软化
	vec3 bc[16];
	float ba[16];
	float bf[16];
	float bw[16];
	for (int i = 0; i < 16; i++) {
		vec4 d = field_at(cell + vec2(float(i % 4) - 1.0, float(i / 4) - 1.0));
		bc[i] = kind_color(d);
		ba[i] = kind_alpha(d);
		bf[i] = d.g * 255.0;
		bw[i] = water_flag(d);
	}

	// smoothstep 过渡：锐化收窄 + 两端润化
	vec2 fs = clamp((f - 0.5) * SHARPEN + 0.5, 0.0, 1.0);
	fs = fs * fs * (3.0 - 2.0 * fs);

	// 四角 = 邻域块中心 2×2（块内下标 5/6/9/10）
	float fog_f = mix(mix(soft5(bf, 5), soft5(bf, 6), fs.x),
		mix(soft5(bf, 9), soft5(bf, 10), fs.x), fs.y);
	float waterness = mix(mix(soft5(bw, 5), soft5(bw, 6), fs.x),
		mix(soft5(bw, 9), soft5(bw, 10), fs.x), fs.y);

	// 整幅宣纸：留白即未探索（纸纹四方连续）
	vec3 col = texture(paper_tex, world_px / 256.0).rgb;

	// 洗染：软化角点颜色双线性，明度颗粒像素尺度（消瓷砖感）
	vec3 base = mix(mix(soft5v(bc, 5), soft5v(bc, 6), fs.x),
		mix(soft5v(bc, 9), soft5v(bc, 10), fs.x), fs.y);
	float alpha = mix(mix(soft5(ba, 5), soft5(ba, 6), fs.x),
		mix(soft5(ba, 9), soft5(ba, 10), fs.x), fs.y);
	float grain = (vnoise(world_px * 0.13) - 0.5) + (vnoise(world_px * 0.031) - 0.5) * 0.7;
	base *= 1.0 + grain * grain_strength;

	if (waterness > 0.02) {
		// 水纹三重动势（克制但可感知）：
		// 1) 域摆动——线身随时间起伏（长横线的上下波动最可见，顺线平移不可见）
		vec2 wob = vec2(
			vnoise(world_px * 0.008 + vec2(time * 0.12, 0.0)),
			vnoise(world_px * 0.008 + vec2(0.0, 27.0 - time * 0.09))
		) - 0.5;
		// 2) 双层错向漂移（纵向分量给足：跨线运动才被看见）
		vec2 uv_a = (world_px + wob * 36.0 + vec2(time * 2.0, time * 1.2)) / 512.0;
		vec2 uv_b = (world_px + wob * 28.0 + vec2(-time * 1.5, time * 0.8)) / 512.0;
		float lines = texture(water_a, uv_a).a * 0.65 + texture(water_b, uv_b).a * 0.45;
		base *= 1.0 - clamp(lines, 0.0, 1.0) * 0.38 * waterness;
		// 3) 流光——低幅行波（约 10px/s 横移的明暗起伏，墨面的"活"）
		float shimmer = vnoise(world_px * 0.012 + vec2(time * 0.12, time * 0.03)) - 0.5;
		base *= 1.0 + shimmer * 0.06 * waterness;
		// 整域呼吸（无世界项=全域同相：一片水是一个整体）
		alpha *= 1.0 + 0.05 * sin(time * 0.5) * waterness;
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
