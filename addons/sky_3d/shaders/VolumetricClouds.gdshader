// Copyright (c) 2023-2025 Cory Petkovsek and Contributors
// Volumetric Clouds

shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

// ============================================================================
// UNIFORMS
// ============================================================================

// Sky integration
uniform vec2 color_correction = vec2(0.0, 1.0);
uniform vec3 sun_direction = vec3(0.0, 0.5, 0.5);
uniform vec3 moon_direction = vec3(0.0, -0.5, 0.5);

// Cloud layer geometry
uniform float cloud_bottom : hint_range(0.01, 0.15) = 0.05;
uniform float cloud_top : hint_range(0.05, 0.5) = 0.4;

// Density
uniform float coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_type : hint_range(0.0, 1.0) = 0.5;  // 0=stratus, 0.5=cumulus, 1=cumulonimbus
uniform float density_mult : hint_range(0.1, 3.0) = 1.0;
uniform float absorption : hint_range(0.01, 0.3) = 0.06;

// Noise
uniform float base_scale : hint_range(1.0, 30.0) = 7.0;

// Animation
uniform float wind_direction : hint_range(-180.0, 180.0) = 0.0;
uniform float wind_speed : hint_range(0.0, 0.1) = 0.01;

// Quality
uniform int march_steps : hint_range(16, 128) = 64;
uniform int shadow_steps : hint_range(2, 16) = 6;

// Colors
uniform vec4 cloud_day_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_horizon_color : source_color = vec4(1.0, 0.9, 0.8, 1.0);
uniform vec4 cloud_night_color : source_color = vec4(0.06, 0.08, 0.14, 1.0);

// Future: 3D noise texture support
uniform sampler3D cloud_noise_texture : filter_linear_mipmap, repeat_enable;
uniform bool use_noise_texture = false;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

#include "res://addons/sky_3d/shaders/Common.gdshaderinc"

// ============================================================================
// NOISE FUNCTIONS
// ============================================================================

float hash13(vec3 p) {
	p = mod(p, 289.0); //cheap tiling
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(
			mix(hash13(i + vec3(0, 0, 0)), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x),
			f.y
		),
		mix(
			mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x),
			f.y
		),
		f.z
	);
}

float cloud_fbm(vec3 p) {
	float v = 0.0;
	v += 0.5 * value_noise(p);
	v += 0.25 * value_noise(p * 2.0);
	v += 0.125 * value_noise(p * 4.0);
	v += 0.0625 * value_noise(p * 8.0);
	return v;
}

// Future: sample from baked 3D texture
float sample_cloud_texture(vec3 p) {
	vec4 noise = texture(cloud_noise_texture, p);
	return noise.r * 0.625 + noise.g * 0.25 + noise.b * 0.125;
}

// ============================================================================
// HEIGHT GRADIENTS
// ============================================================================

float gradient_stratus(float h) {
	return smoothstep(0.0, 0.05, h) * smoothstep(0.2, 0.1, h);
}

float gradient_stratocumulus(float h) {
	return smoothstep(0.0, 0.1, h) * smoothstep(0.5, 0.25, h);
}

float gradient_cumulus(float h) {
	float base = smoothstep(0.0, 0.1, h);
	float top = smoothstep(1.0, 0.4, h);
	float body = pow(smoothstep(0.0, 0.35, h) * smoothstep(0.85, 0.25, h), 0.5);
	return base * top * body;
}

float gradient_cumulonimbus(float h) {
	float base = smoothstep(0.0, 0.05, h);
	float tower = smoothstep(1.0, 0.8, h);
	return base * tower * pow(h * 0.4 + 0.1, 0.25);
}

float sample_height_gradient(float h, float type) {
	float t = type * 3.0;
	if (t < 1.0) {
		return mix(gradient_stratus(h), gradient_stratocumulus(h), t);
	} else if (t < 2.0) {
		return mix(gradient_stratocumulus(h), gradient_cumulus(h), t - 1.0);
	} else {
		return mix(gradient_cumulus(h), gradient_cumulonimbus(h), t - 2.0);
}
}

// ============================================================================
// LIGHTING
// ============================================================================

float beer_lambert(float od) {
	return exp(-od);
}

// ============================================================================
// DENSITY SAMPLING
// ============================================================================

float sample_density(vec3 pos, vec3 wind_offset) {
	float h = (pos.y - cloud_bottom) / (cloud_top - cloud_bottom);
	h = clamp(h, 0.0, 1.0);

	float gradient = sample_height_gradient(h, cloud_type);

	vec3 sample_pos = pos * base_scale + wind_offset;

	float base;
	if (use_noise_texture) {
		base = sample_cloud_texture(sample_pos);
	} else {
		base = cloud_fbm(sample_pos);
}

	float threshold = 1.0 - coverage;
	float d = base - threshold;
	d = max(d, 0.0) * (1.0 / max(coverage, 0.01));
	d *= gradient;

	return max(d, 0.0) * density_mult;
}

// ============================================================================
// SHADOW RAY
// ============================================================================

float shadow_ray(vec3 pos, vec3 light_dir, vec3 wind_offset) {
	float od = 0.0;
	float layer_height = cloud_top - pos.y;

	if (layer_height <= 0.0) return 1.0;

		float step_size = layer_height / float(shadow_steps);

		for (int i = 1; i <= shadow_steps; i++) {
			vec3 p = pos + vec3(0.0, step_size * float(i), 0.0);
			float d = sample_density(p, wind_offset);
			od += d * 50.0;
		}
	return beer_lambert(od);
}

// ============================================================================
// RAY MARCH
// ============================================================================

vec4 march_clouds(vec3 rd, vec3 sun_dir, float time, vec2 screen_uv) {
	if (rd.y <= 0.001) return vec4(0.0);
		float t_min = cloud_bottom / rd.y;
		float t_max = cloud_top / rd.y;
		if (t_min >= t_max) return vec4(0.0);
		vec2 wind_dir = vec2(sin(wind_direction), cos(wind_direction));
		vec3 wind_offset = vec3(wind_dir.x, 0.0, wind_dir.y) * time * wind_speed;
		float step_size = (t_max - t_min) / float(march_steps);
		float t = t_min;

		// Jitter to reduce banding
		vec2 screen_pos = screen_uv * vec2(textureSize(DEPTH_TEXTURE, 0));
		float jitter = fract(52.9829189 * fract(dot(screen_pos, vec2(0.06711056, 0.00583715))));
		t += step_size * jitter;

		// Cloud color based on sun height
		float sun_height = sun_dir.y;
		float day_amount = smoothstep(-0.1, 0.3, sun_height);      // 1 when day
		float night_amount = smoothstep(0.1, -0.5, sun_height);    // 1 when night
		float horizon_amount = 1.0 - day_amount - night_amount;    // remainder is horizon
		horizon_amount = max(horizon_amount, 0.0);

		vec3 col = cloud_day_color.rgb * day_amount + cloud_horizon_color.rgb * horizon_amount + cloud_night_color.rgb * night_amount;
		
		float transmittance = 1.0;
		vec3 light = vec3(0.0);

	for (int i = 0; i < march_steps; i++) {
		if (t > t_max) break;
		if (transmittance < 0.01) break;

		vec3 pos = rd * t;
		float d = sample_density(pos, wind_offset);

		if (d > 0.001) {
			
			float od = d * absorption * 20.0;
			float beer = beer_lambert(od);
			
			//sun light
			float sun_factor = clamp(sun_dir.y + 0.3, 0.0, 1.0);
			float sun_shadow = shadow_ray(pos, sun_dir, wind_offset);
			
			//moon light
			float moon_factor = clamp(-sun_dir.y + 0.3, 0.0, 1.0) * 0.3;
			float moon_shadow = shadow_ray(pos,moon_direction , wind_offset);
			
			vec3 ambient = col * 0.3;
			vec3 sun_light = col * sun_shadow * sun_factor * 0.7;
			vec3 moon_light = col * moon_shadow * moon_factor;
			vec3 sample_light = (ambient + sun_light + moon_light) * (1.0 - beer);

			light += transmittance * sample_light;
			transmittance *= beer;
			}
		t += step_size;
	}
	return vec4(light, 1.0 - transmittance);
}

// ============================================================================
// VERTEX / FRAGMENT
// ============================================================================

varying mat4 camera_matrix;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	camera_matrix = INV_VIEW_MATRIX;
}

void fragment() {
	float depth_raw = textureLod(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
	

	// MSAA fix based on merge: https://github.com/Bonkahe/SunshineClouds2/pull/16
	vec2 texel = 1.0 / vec2(textureSize(DEPTH_TEXTURE, 0));
	float depth_l = textureLod(DEPTH_TEXTURE, SCREEN_UV + vec2(-texel.x, 0.0), 0.0).r;
	float depth_r = textureLod(DEPTH_TEXTURE, SCREEN_UV + vec2(texel.x, 0.0), 0.0).r;
	float depth_u = textureLod(DEPTH_TEXTURE, SCREEN_UV + vec2(0.0, texel.y), 0.0).r;
	float depth_d = textureLod(DEPTH_TEXTURE, SCREEN_UV + vec2(0.0, -texel.y), 0.0).r;

	// In reversed-Z: sky=0, objects>0. Max gives most conservative (object-favoring) value
	float depth_max = max(depth_raw, max(max(depth_l, depth_r), max(depth_u, depth_d)));

	float depth_fade = smoothstep(0.0001, 0.0, depth_max);
	
	// Only render on sky (reversed depth buffer) smoothed to prevent object outline
	if (depth_fade < 0.00001) {
		discard;
	}


	// Reconstruct view direction
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;

	vec4 world_view = camera_matrix * view;
	world_view.xyz /= world_view.w;
	world_view.xyz -= (camera_matrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	vec3 rd = normalize(world_view.xyz);

	// March clouds
	vec4 clouds = march_clouds(rd, sun_direction, TIME, SCREEN_UV);
	clouds.rgb = apply_photo_tonemap(clouds.rgb, color_correction.y, color_correction.x);

	ALBEDO = clouds.rgb;
	ALPHA = clouds.a * depth_fade;
}