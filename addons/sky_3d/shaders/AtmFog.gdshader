// Copyright (c) 2023-2025 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar

shader_type spatial;
render_mode blend_mix, cull_front, unshaded, fog_disabled;


uniform vec2 color_correction;

uniform float sea_level: hint_range(-2048,2048,.01) = 0.0;
uniform float fog_density = .0001;
uniform float fog_rayleigh_depth = .115;
uniform float fog_mie_depth = 0.;
uniform float fog_falloff = 3.;
uniform float fog_start = 0.;
uniform float fog_end = 1000.;
uniform vec3 sun_direction = vec3(.25, -.25, .25);
uniform vec3 moon_direction = vec3(.45, -.25, .45);

uniform float atm_darkness = .5;
uniform float atm_sun_intensity = 30.;
uniform vec4 atm_day_tint: source_color = vec4(.78, .85, .98, 1.);
uniform vec4 atm_horizon_light_tint: source_color = vec4(.98, .73, .49, 1.);
uniform vec4 atm_night_tint: source_color = vec4(.16, .2, .25, 1.);
uniform vec3 atm_level_params = vec3(1., 0., 0.);
uniform float atm_thickness = .7;

uniform vec3 atm_beta_ray;
uniform vec3 atm_beta_mie;

uniform vec3 atm_sun_partial_mie_phase;
uniform vec4 atm_sun_mie_tint: source_color = vec4(1.);
uniform float atm_sun_mie_intensity = 1.;

uniform vec3 atm_moon_partial_mie_phase;
uniform vec4 atm_moon_mie_tint: source_color = vec4(.13, .18, .29, 1.);
uniform float atm_moon_mie_intensity = .7;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

varying vec4 v_angle_mult;

#include "Common.gdshaderinc"

// Atmosphere
vec3 calc_atmospheric_scatter(float sr, float sm, vec2 mu, vec3 mult, float depth) {
	vec3 beta_mie = atm_beta_mie;
	vec3 beta_ray = atm_beta_ray * atm_thickness;

	vec3 extc_factor = clamp_rgb_to_unit(exp(-(beta_ray * sr + beta_mie * sm)));

	float extc_ff = mix(clamp_to_unit(atm_thickness * 0.5), 1.0, mult.x);
	vec3 final_extc_factor = mix(1.0 - extc_factor, (1.0 - extc_factor) * extc_factor, extc_ff);

	float rayleigh_phase = calc_rayleigh_phase(mu.x);
	vec3 BRT = beta_ray * rayleigh_phase * clamp_to_unit(depth * fog_rayleigh_depth);
	vec3 BMT = beta_mie * calc_mie_phase(mu.x, atm_sun_partial_mie_phase);
	BMT *= atm_sun_mie_intensity * atm_sun_mie_tint.rgb * clamp_to_unit(depth * fog_mie_depth);

	vec3 BRMT = (BRT + BMT) / (beta_ray + beta_mie);
	vec3 scatter = atm_sun_intensity * (BRMT * final_extc_factor) * atm_day_tint.rgb * mult.y;
	scatter = mix(scatter, scatter * (1.0 - extc_factor), atm_darkness);

	vec3 lcol = mix(atm_day_tint.rgb, atm_horizon_light_tint.rgb, mult.x);
	vec3 nscatter = (1.0 - extc_factor) * atm_night_tint.rgb * clamp_to_unit(depth * fog_rayleigh_depth);
	nscatter += calc_mie_phase(mu.y, atm_moon_partial_mie_phase) *
		atm_moon_mie_tint.rgb * atm_moon_mie_intensity * 0.005 * clamp_to_unit(depth * fog_mie_depth);

	return (scatter * lcol) + nscatter;
}

// Fog
float calc_fog_exp(float depth, float density) {
	return 1.0 - clamp_to_unit(exp2(-depth * density));
}

float calc_fog_falloff(float y, float zeroLevel, float falloff) {
	return clamp_to_unit(exp(-(y + zeroLevel) * falloff));
}

float calc_fog_distance(float depth) {
	float d = depth;
	d = (fog_end - d) / (fog_end - fog_start);
	return clamp_to_unit(1.0 - d);
}


// Main

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	v_angle_mult = vec4(
		clamp_to_unit(1.0 - sun_direction.y),
		clamp_to_unit(sun_direction.y + 0.45),
		clamp_to_unit(-sun_direction.y + 0.30),
		clamp_to_unit(-sun_direction.y + 0.60));
}

void fragment() {
	// Calculate world pixel position from depth
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	#ifndef CURRENT_RENDERER
		// For 4.3 or earlier, will break if far plane is less than 1m.
		depth_raw = PROJECTION_MATRIX[3][2] > PROJECTION_MATRIX[2][2] ? depth_raw : depth_raw * 2.0 - 1.0;
	#else
		#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
			depth_raw = depth_raw * 2.0 - 1.0;
		#endif
	#endif
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 clip_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 view_pos = clip_pos.xyz / clip_pos.w;
	vec4 world_pos_hom = INV_VIEW_MATRIX * vec4(view_pos, 1.0);
	vec3 world_position = world_pos_hom.xyz / world_pos_hom.w;
	
	// Ray from camera to world intersection point
	vec3 intersection_ray = world_position - CAMERA_POSITION_WORLD;
	// Unit ray direction
	vec3 ray_direction = normalize(intersection_ray);
	//float linear_depth = -view_pos.z; // Approximate ray distance
	//float ray_distance = length(intersection_ray); // Exact ray distance

	// Cap ray if there's a sea_level plane intersection
	float original_distance = length(intersection_ray);
	// Y difference from camera to sea_level
	float dy = sea_level - CAMERA_POSITION_WORLD.y;
	// Distance along ray to sea_level plane
	float plane_distance = dy / (ray_direction.y + 1e-6 * sign(ray_direction.y));  // avoid divide by zero
	float plane_hit = float(ray_direction.y < 0.) *
					  float(plane_distance > 0.) *
					  float(plane_distance < original_distance);
	
	// Use final distance or t_plane distance Final distance: mix original vs plane distance
	float ray_distance = mix(original_distance, plane_distance, plane_hit);
	
	// Capped world position
	//world_position = CAMERA_POSITION_WORLD + ray_distance * ray_direction;

	float fog_factor = calc_fog_exp(ray_distance, fog_density);
	fog_factor *= calc_fog_falloff(ray_direction.y, 0.0, fog_falloff);
	fog_factor *= calc_fog_distance(ray_distance);

	vec2 mu = vec2(
		dot(sun_direction, ray_direction),
		dot(moon_direction, ray_direction)
	);
	float sr, sm;
	calc_simple_optical_depth(ray_direction.y + atm_level_params.z, sr, sm, atm_level_params.xy);
	vec3 scatter = calc_atmospheric_scatter(sr, sm, mu, v_angle_mult.xyz, ray_distance);

	vec4 fog_color = vec4(scatter, fog_factor);
	fog_color.a = clamp(fog_color.a, 0.0, 1.0);
	fog_color.rgb = apply_photo_tonemap(fog_color.rgb, color_correction.y, color_correction.x);

	ALBEDO = fog_color.rgb;
	ALPHA = fog_color.a;

	// View depth map
	//ALPHA = 1.;
	//ALBEDO = vec3(ray_distance*.0001);
}
