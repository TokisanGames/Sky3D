// Copyright (c) 2023-2025 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar

shader_type sky;
render_mode use_debanding;

group_uniforms general;
uniform bool sky_visible = true;
uniform vec2 color_correction = vec2(0.0, 1.0);
uniform vec4 ground_color: source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float horizon_offset = 0.0;

group_uniforms atmosphere;
uniform float atm_darkness = 0.5;
uniform float atm_sun_intensity = 18.0;
uniform vec4 atm_day_tint: source_color = vec4(0.808, 0.91, 1.0, 1.0);
uniform vec4 atm_horizon_light_tint: source_color = vec4(0.98, 0.635, 0.463, 1.0);
uniform vec4 atm_night_tint: source_color = vec4 (0.041, 0.049, 0.061, 0.245);
uniform vec3 atm_level_params = vec3(1.0, 0.0, 0.0);
uniform float atm_thickness = 0.7;
uniform vec3 atm_beta_ray = vec3(0.00001, 0.00001, 0.00003);
uniform vec3 atm_beta_mie = vec3(0.00000003038); // Value computed by multiplying Mie, turbidity, and 0.000434.

group_uniforms sun_disk;
uniform vec4 sun_disk_color: source_color = vec4(0.996, 0.541, 0.14, 1.0);
uniform float sun_disk_intensity = 2.0;
uniform float sun_disk_size = 0.015;

group_uniforms sun_mie;
uniform vec4 atm_sun_mie_tint: source_color = vec4(1.0);
uniform float atm_sun_mie_intensity = 1.0;
uniform vec3 atm_sun_partial_mie_phase = vec3(0.36, 1.64, 1.6);

group_uniforms moon;
uniform vec4 moon_color: source_color = vec4(1.0);
uniform sampler2D moon_texture: source_color, repeat_disable;
uniform vec3 moon_texture_alignment = vec3(7.0, 1.4, 4.8);
uniform bool moon_texture_flip_u;
uniform bool moon_texture_flip_v;
uniform float moon_size = 0.07;

group_uniforms moon_mie;
uniform vec4 atm_moon_mie_tint: source_color = vec4(0.137, 0.184, 0.292, 1.0);
uniform float atm_moon_mie_intensity = 0.17152;
uniform vec3 atm_moon_partial_mie_phase = vec3(0.36, 1.64, 1.6);

group_uniforms star_map;
uniform vec4 starmap_color: source_color = vec4(0.71, 0.71, 0.71, 0.855);
uniform sampler2D starmap_texture: source_color;
uniform bool starmap_flip_u = false;
uniform bool starmap_flip_v = false;
uniform vec3 starmap_alignment = vec3(2.68288, -0.25891, 0.40101);
uniform float star_rotation_offset = 9.38899;
uniform float star_rotation = 0.0; // For simulating Earth rotation.
uniform float star_tilt = 0.0; // For tilting the sky according to observer latitude in radians. (90° - latitude)

group_uniforms star_field;
uniform vec4 star_field_color: source_color = vec4(1.0);
uniform sampler2D star_field_texture: source_color;
uniform float star_scintillation = 0.75;
uniform float star_scintillation_speed = 0.01;
uniform sampler2D noise_tex: source_color;

/* Sky alignment values for a star map that is in galactic coordinates. Works for most star maps.
X: 2.6555
Y: -0.23935
Z: 0.4505

These alignment values are consistent with a sky view from the North Pole (latitude zero)
at midnight. The positions of Polaris, Vega, Rigel, and Alpha Centauri confirmed
through various sources and calculations.
*/

group_uniforms cirrus_clouds;
uniform bool cirrus_visible = true;
uniform float cirrus_coverage = 0.5;
uniform float cirrus_thickness = 10.0;
uniform float cirrus_absorption = 2.0;
uniform float cirrus_sky_tint_fade = 0.5;
uniform float cirrus_intensity = 10.0;
uniform float cirrus_size = 1.0;
uniform vec2 cirrus_uv = vec2(0.16, 0.11);
uniform vec2 cirrus_position1 = vec2(0.0);
uniform vec2 cirrus_position2 = vec2(0.0);
uniform vec4 cirrus_day_color: source_color = vec4(0.824, 0.875, 1.0, 1.0);
uniform vec4 cirrus_horizon_light_color: source_color = vec4(0.98, 0.43, 0.15, 1.0);
uniform vec4 cirrus_night_color: source_color = vec4(0.09, 0.094, 0.129, 1.0);
uniform sampler2D cirrus_texture;

group_uniforms cumulus_clouds;
uniform bool cumulus_visible = true;
uniform float cumulus_coverage = 0.55;
uniform float cumulus_thickness = 0.0243;
uniform float cumulus_absorption = 2.0;
uniform float cumulus_noise_freq = 2.7;
uniform float cumulus_sky_tint_fade = 0.0;
uniform float cumulus_intensity = 1.0;
uniform float cumulus_size = 0.5;
uniform vec2 cumulus_position = vec2(0.0);
uniform sampler2D cumulus_texture;
uniform vec4 cumulus_day_color: source_color = vec4(0.824, 0.875, 1.0, 1.0);
uniform vec4 cumulus_horizon_light_color: source_color = vec4(0.98, 0.443, 0.15, 1.0);
uniform vec4 cumulus_night_color: source_color = vec4(0.09, 0.094, 0.129, 1.0);
uniform vec3 cumulus_partial_mie_phase = vec3(0.95756, 1.04244, 0.412);
uniform float cumulus_mie_intensity = 1.0;

group_uniforms overlays;
uniform bool show_azimuthal_grid = false;
uniform vec4 azimuthal_grid_color : source_color = vec4(.871, .722, .529, 1.);
uniform float azimuthal_grid_rotation_offset = 0.03;
uniform bool show_equatorial_grid = false;
uniform vec4 equatorial_grid_color : source_color = vec4(0., .75, 1., 1.);
uniform float equatorial_grid_rotation_offset = 0.03;

group_uniforms transform_matrices;
uniform mat3 moon_matrix; // Calculated externally via GDScript.

#include "Common.gdshaderinc"

// Provides a transformation matrix when passed a vec3.
mat3 create_rotation_matrix(vec3 r) {
	float c1 = cos(r.x), s1 = sin(r.x);
	float c2 = cos(r.y), s2 = sin(r.y);
	float c3 = cos(r.z), s3 = sin(r.z);

	mat3 rotX = mat3(
		vec3(1.0, 0.0, 0.0),
		vec3(0.0, c1, -s1),
		vec3(0.0, s1, c1)
	);

	mat3 rotY = mat3(
		vec3(c2, 0.0, s2),
		vec3(0.0, 1.0, 0.0),
		vec3(-s2, 0.0, c2)
	);

	mat3 rotZ = mat3(
		vec3(c3, -s3, 0.0),
		vec3(s3, c3, 0.0),
		vec3(0.0, 0.0, 1.0)
	);

	return rotZ * rotY * rotX; // Combine rotations in ZYX order
}

vec2 calc_equirect_uv(vec3 norm) {
	float flipu = starmap_flip_u ? -1.0 : 1.0;
	float flipv = starmap_flip_v ? -1.0 : 1.0;
	float u = flipu * ((atan(norm.y, norm.x) + PI) * INV_TAU); // 0 to 1 horizontally
	float v = -flipv * (acos(norm.z) * INV_PI); // 0 (north pole) to 1 (south pole)
	return vec2(u, v);
}

vec3 sample_moon_texture(vec3 dir) {
	dir = moon_matrix * dir * create_rotation_matrix(moon_texture_alignment);
	dir.x = -dir.x;
	dir.z = -dir.z;
	float flipu = moon_texture_flip_u ? 1.0 : -1.0;
	float flipv = moon_texture_flip_v ? 1.0 : -1.0;
	float u = 0.5 + flipu * atan(dir.z, dir.x) * INV_TAU; // Longitude
	float v = 0.5 + flipv * asin(dir.y) * INV_PI; // Latitude
	return texture(moon_texture, vec2(u, v)).rgb;
}

float calc_disk_mask(vec3 norm, vec3 coords, lowp float size) {
	float dist = length(norm - coords);
	return 1.0 - step(size, dist);
}

float map_range(float value, float from_min, float from_max, float to_min, float to_max) {
	return to_min + (value - from_min) * (to_max - to_min) / (from_max - from_min);
}

bool ray_sphere_intersect(float r, vec3 origin, vec3 dir, out float t, out vec3 nrm) {
	origin += vec3(0.0, 450.0, 0.0);
	float a = dot(dir, dir);
	float b = 2.0 * dot(origin, dir);
	float c = dot(origin, origin) - r * r;
	float d = b * b - 4.0 * a * c;
	float valid = step(0.0, d); // 1.0 if d >= 0.0, else 0.0
	d = sqrt(max(d, 0.0)); // Prevent sqrt of negative numbers
	a *= 2.0;
	float t1 = 0.5 * (-b + d);
	float t2 = 0.5 * (-b - d);
	float t_min = min(t1, t2); // Select the smallest intersection
	t = mix(t2, t1, step(t2, t1) * step(0.0, t1)); // Use t1 if t2 < t1 and t1 >= 0, else t2
	t = mix(0.0, t, step(0.0, t) * valid); // Invalidate if t < 0 or d < 0
	nrm = mix(vec3(0.0), origin + t * dir, step(0.0, t) * valid); // Set nrm only if valid
	return bool(step(0.0, t) * valid);
}

// For rendering the moon. This function courtesy of Kelvin van Hoorn.
// https://kelvinvanhoorn.com/2024/12/07/skybox-tutorial-godot/
float simple_sphere_intersect(vec3 ray_dir, vec3 sphere_pos, float radius) {
	vec3 oc = -sphere_pos;
	float b = dot(oc, ray_dir);
	float c = dot(oc, oc) - radius * radius;
	float h = b * b - c;
	float valid = step(0.0, h); // 1.0 if h >= 0.0, else 0.0
	h = sqrt(max(h, 0.0)); // Ensure sqrt is non-negative
	return mix(-1.0, -b - h, valid);
}

// Atmosphere
//------------------------------------------------------------------------------

vec3 calc_atmospheric_scatter(float sr, float sm, vec2 mu, vec3 mult) {
	vec3 beta_mie = atm_beta_mie;
	vec3 beta_ray = atm_beta_ray * atm_thickness;

	vec3 extc_factor = clamp_rgb_to_unit(exp(-(beta_ray * sr + beta_mie * sm)));

	float extc_ff = mix(clamp_to_unit(atm_thickness * 0.5), 1.0, mult.x);
	vec3 final_extc_factor = mix(1.0 - extc_factor, (1.0 - extc_factor) * extc_factor, extc_ff);
	float rayleigh_phase = calc_rayleigh_phase(mu.x);
	vec3 BRT = beta_ray * rayleigh_phase;
	vec3 BMT = beta_mie * calc_mie_phase(mu.x, atm_sun_partial_mie_phase);
	BMT *= atm_sun_mie_intensity * atm_sun_mie_tint.rgb;

	vec3 BRMT = (BRT + BMT) / (beta_ray + beta_mie);
	vec3 scatter = atm_sun_intensity * (BRMT * final_extc_factor) * atm_day_tint.rgb * mult.y;
	scatter = mix(scatter, scatter * (1.0 - extc_factor), atm_darkness);

	vec3 lcol =  mix(atm_day_tint.rgb, atm_horizon_light_tint.rgb, mult.x);
	vec3 nscatter = (1.0 - extc_factor) * atm_night_tint.rgb;
	nscatter += calc_mie_phase(mu.y, atm_moon_partial_mie_phase) *
		atm_moon_mie_tint.rgb * atm_moon_mie_intensity * 0.005;

	return (scatter * lcol) + nscatter;
}

// Clouds
//------------------------------------------------------------------------------
const int CUMULUS_STEP = 10;

float sample_cirrus_noise(vec2 coords) {
	float a = textureLod(cirrus_texture, coords.xy * cirrus_uv + cirrus_position1, 0.0).r;
	float b = textureLod(cirrus_texture, coords.xy * cirrus_uv + cirrus_position2, 0.0).r;
	return ((a + b) * 0.5);
}

float sample_cumulus_noise(vec3 p) {
	vec3 pos = vec3(p * 0.01);
	pos.z *= 256.0;
	vec2 offset = vec2(0.317, 0.123);
	vec4 uv = vec4(0.0);
	uv.xy = pos.xy + offset * floor(pos.z);
	uv.zw = uv.xy + offset;
	float x1 = textureLod(cumulus_texture, uv.xy, 0.0).r;
	float x2 = textureLod(cumulus_texture, uv.zw, 0.0).r;
	return mix(x1, x2, fract(pos.z));
}

float calc_cumulus_fbm(vec3 p, float l) {
	float ret;
	ret = 0.51749673 * sample_cumulus_noise(p);
	p *= l;
	ret += 0.25584929 * sample_cumulus_noise(p);
	p *= l;
	ret += 0.12527603 * sample_cumulus_noise(p);
	p *= l;
	ret += 0.06255931 * sample_cumulus_noise(p);
	return ret;
}

float calc_cirrus_density(vec2 p) {
	float d = sample_cirrus_noise(p);
	float c = 1.0 - cirrus_coverage;
	d = d - c;
	return clamp_to_unit(d);
}

float calc_cumulus_density(vec3 p, vec3 offset, float t) {
	vec3 pos = p * 0.0212242 - offset;
	float dens = calc_cumulus_fbm(pos, cumulus_noise_freq);
	dens += dens;

	float cov = 1.0 - cumulus_coverage;
	cov = smoothstep(0.00, (cov * 3.5) + t, dens);
	dens *= cov;
	dens = map_range(dens, 1.0 - cov, 1.0, 0.0, 1.0);

	return clamp_to_unit(dens);
}

vec4 render_cirrus_clouds(vec3 pos) {
	pos.xy = pos.xz / pos.y;
	pos *= cirrus_size;
	float density = calc_cirrus_density(pos.xy);
	float sh = clamp_to_unit(exp(-cirrus_absorption * density));
	float a = clamp_to_unit(density * cirrus_thickness);
	return vec4(vec3(density*sh) * cirrus_intensity, a);
}

vec4 render_cumulus_clouds(vec3 ro, vec3 rd, float am, vec3 sun_pos, vec3 moon_pos) {
	vec4 ret = vec4(0.);
	vec3 wind = -vec3(cumulus_position.x, 0.0, cumulus_position.y);
	float a = 0.0;

	// n and tt doesnt need to be initialized since it would be set by ray_sphere_intersect
	vec3 n; float tt;
	if (ray_sphere_intersect(500., ro, rd, tt, n)) {
		float march_step = float(CUMULUS_STEP) * cumulus_thickness;
		vec3 dir_step = rd / rd.y * march_step;
		vec3 pos = n * cumulus_size;

		vec2 mu = vec2(dot(sun_pos, rd), dot(moon_pos, rd));
		vec3 mph = ((calc_mie_phase(mu.x, cumulus_partial_mie_phase) * atm_sun_mie_tint.rgb) +
			calc_mie_phase(mu.y, cumulus_partial_mie_phase) * am);

		vec4 t = vec4(1.0);
		t.rgb += (mph.rgb * cumulus_mie_intensity);

		for(int i = 0; i < CUMULUS_STEP; i++) {
			float h = float(i) * 0.1; // / float(kCLOUDS_STEP);
			float density = calc_cumulus_density(pos, wind, h);
			float sh = clamp_to_unit(exp(-cumulus_absorption * density * march_step));
			t *= sh;
			ret += (t * (exp(h) * 0.571428571) * density * march_step);
			a += (1.0 - sh) * (1.0 - a);
			pos += dir_step;
		}
		return vec4(ret.rgb * cumulus_intensity, a);
	}
	return vec4(ret.rgb * cumulus_intensity, a);
}

// Main
//------------------------------------------------------------------------------

vec3 render_sky(vec3 world_pos, vec3 clouds_pos, vec3 sun_pos, vec3 moon_pos, float p_time) {
	vec3 col = vec3(0.0);

	vec4 angle_mult;
	angle_mult.x = clamp_to_unit(1.0 - sun_pos.y);
	angle_mult.y = clamp_to_unit(sun_pos.y + 0.45);
	angle_mult.z = clamp_to_unit(-sun_pos.y + 0.30);
	angle_mult.w = clamp_to_unit(-sun_pos.y + 0.60);

	// Atmosphere
	vec2 mu = vec2(dot(sun_pos, world_pos), dot(moon_pos, world_pos));
	float sr, sm;
	calc_simple_optical_depth(world_pos.y + atm_level_params.z - horizon_offset, sr, sm, atm_level_params.xy);

	world_pos.y -= horizon_offset;
	float horizonBlend = clamp_to_unit((world_pos.y - 0.03) * 3.0);
	float horizonBlendCumulus = clamp_to_unit((world_pos.y + 0.01) * 50.0);

	vec3 scatter = calc_atmospheric_scatter(sr, sm, mu.xy, angle_mult.xyz);
	col.rgb += scatter.rgb;

	// Sun
	vec3 sun_disk = calc_disk_mask(world_pos, sun_pos, sun_disk_size) * sun_disk_color.rgb * scatter.rgb;
	sun_disk *= sun_disk_intensity;

	// Moon
	float moon_intersect = simple_sphere_intersect(world_pos, moon_pos, moon_size);
	float moon_mask = moon_intersect > (-1. + sqrt(moon_size)) ? 1.0 : 0.0;
	vec3 moon_normal = normalize(world_pos * moon_intersect - moon_pos);

	float moon_ndotl = clamp(dot(moon_normal, sun_pos), 0.0, 1.0);
	vec3 moon_tex = sample_moon_texture(moon_normal);
	vec3 moon_output = moon_mask * moon_ndotl * exp2(1.0) * moon_tex * moon_color.rgb;
	float moonMask = (1.0 - moon_mask);

	// Deep space

	// Tilt the sky along the X-axis.
	mat3 tilt = create_rotation_matrix(vec3(star_tilt, 0.0, 0.0));

	// Rotation around Y-axis. For simulating Earth's rotation.
	mat3 rotation = create_rotation_matrix(vec3(0.0, star_rotation + star_rotation_offset, 0.0));

	// Initial XYZ rotation for alignment.
	mat3 alignment_xyz = create_rotation_matrix(starmap_alignment);

	// Combine everything together to get the desired alignment.
	vec3 final_alignment = normalize(alignment_xyz * rotation * tilt * world_pos);

	// Now generate UV coordinates for the texture.
	vec2 deep_space_uv = calc_equirect_uv(normalize(final_alignment));

	// Star map
	vec3 deep_space_background = textureLod(starmap_texture, deep_space_uv, 0.0).rgb;
	deep_space_background *= starmap_color.rgb;
	deep_space_background = adjust_contrast(deep_space_background, starmap_color.a);
	vec3 deep_space = deep_space_background.rgb * moonMask + moon_output;

	// Star Field
	float star_scint = textureLod(noise_tex, deep_space_uv + (p_time * star_scintillation_speed), 0.0).r;
	star_scint = mix(1.0, star_scint * 1.5, star_scintillation);

	vec3 star_field = textureLod(star_field_texture, deep_space_uv, 0.0).rgb * star_field_color.rgb;
	star_field = clamp_rgb_to_unit(mix(star_field.rgb, star_field.rgb * star_scint, star_scintillation));
	star_field = clamp_rgb_to_unit(star_field.rgb);
	//deep_space.rgb -= clamp_to_unit(star_field.r * 10.0);
	deep_space.rgb += star_field.rgb * moonMask;
	deep_space.rgb *= angle_mult.z;
	col.rgb += sun_disk.rgb + deep_space.rgb * horizonBlend;

	// Clouds
	if (cirrus_visible) {
		vec4 cirrus_clouds = render_cirrus_clouds(clouds_pos);
		cirrus_clouds.a = clamp_to_unit(cirrus_clouds.a);
		cirrus_clouds.rgb *= mix(mix(cirrus_day_color.rgb, cirrus_horizon_light_color.rgb, angle_mult.x), cirrus_night_color.rgb, angle_mult.w);

		cirrus_clouds.a = mix(0.0, cirrus_clouds.a, horizonBlend);
		col.rgb = mix(col.rgb, cirrus_clouds.rgb + mix(vec3(0.0), scatter, cirrus_sky_tint_fade), cirrus_clouds.a);
	}

	if (cumulus_visible) {
		vec4 cumulus_clouds = render_cumulus_clouds(vec3(0.0), clouds_pos, angle_mult.z, sun_pos, moon_pos);
		cumulus_clouds.a = clamp_to_unit(cumulus_clouds.a);
		cumulus_clouds.rgb *= mix(mix(cumulus_day_color.rgb, cumulus_horizon_light_color.rgb, angle_mult.x),
			cumulus_night_color.rgb, angle_mult.w);
		cumulus_clouds.a = mix(0.0, cumulus_clouds.a, horizonBlend);
		col.rgb = mix(col.rgb, cumulus_clouds.rgb + mix(vec3(0.0), scatter, cumulus_sky_tint_fade), cumulus_clouds.a);
	}

	col.rgb = mix(col.rgb, ground_color.rgb * scatter, clamp_to_unit((-world_pos.y - atm_level_params.z) * 100.0));
	col.rgb = apply_photo_tonemap(col.rgb, color_correction.y, color_correction.x);
	return col;
}

vec4 create_axis_angle_quat(vec3 axis, float angle) {
	float s = sin(angle * 0.5);
	return vec4(axis * s, cos(angle * 0.5));
}

vec3 rotate_vector_by_quat(vec3 v, vec4 q) {
	vec3 t = 2.0 * cross(q.xyz, v);
	return v + q.w * t + cross(q.xyz, t);
}

vec3 align_and_rotate_vector(vec3 dir, vec3 target, float rotation_angle) {
	vec3 z_axis = vec3(0.0, 0.0, 1.0); // Original grid alignment

	// First, align Z-axis with target (Polaris)
	target = normalize(target);
	vec3 axis = cross(z_axis, target);
	float angle = acos(dot(z_axis, target));
	float valid = step(0.0001, length(axis)); // 1.0 if length(axis) >= 0.0001
	axis = normalize(axis);
	vec4 align_quat = create_axis_angle_quat(axis, angle);
	dir = mix(dir, rotate_vector_by_quat(dir, align_quat), valid);
	vec4 rot_quat = create_axis_angle_quat(vec3(0.0, 0.0, 1.0), rotation_angle);
	dir = mix(dir, rotate_vector_by_quat(dir, rot_quat), valid);
	return dir;
}

void render_grid(vec3 dir, vec3 pole_dir, float rotation_angle, vec4 line_color, float grid_spacing, float line_thickness, inout vec3 color) {
	float spacing = max(grid_spacing, 0.001);
	float thickness = max(line_thickness, 0.0001);

	// Rotate dir with sidereal motion and align with pole_dir
	dir = align_and_rotate_vector(dir, pole_dir, rotation_angle);

	// Latitude / Circles / Theta Spherical coordinates
	float theta = acos(dir.z);
	float theta_deriv = fwidth(theta);
	float circle_thickness = max(thickness, theta_deriv);
	float circle = mod(theta, spacing);
	float circle_line = 1.0 - smoothstep(0.0, circle_thickness * 1.5, abs(circle - circle_thickness * 0.5));
	circle_line *= clamp_to_unit(thickness / circle_thickness);

	// Add poles
	float pole_thickness = circle_thickness;
	float north_pole = 1.0 - smoothstep(0.0, pole_thickness, theta);
	float south_pole = 1.0 - smoothstep(0.0, pole_thickness, abs(theta - PI));
	circle_line = max(circle_line, max(north_pole, south_pole));

	// Darken Lat at poles
	float circle_adjust = sin(theta);
	circle_line *= clamp(circle_adjust, 0.2, 1.0);

	// Longitude / Radial lines / Phi Spherical coordinates
	float phi = atan(dir.y, dir.x);
	float phi_deriv = fwidth(phi);
	float radial_thickness = max(thickness, phi_deriv);
	float radial = mod(phi + PI, spacing); // PI w/ less precision to remove moire
	float radial_line = 1.0 - smoothstep(0.0, radial_thickness * 1.5, abs(radial - radial_thickness));
	radial_line *= clamp_to_unit(thickness / radial_thickness);

	float grid = max(radial_line, circle_line);
	color += line_color.rgb * line_color.a * grid;
}

void sky() {
	float current_time = TIME;
	vec3 col = vec3(0.0); // Set up the initial sky color which will be added to later to produce the final result.
	vec3 world_pos = EYEDIR; // Original shader set this up in the vertex() function. For sky shaders the overall equivalent is EYEDIR.
	vec3 clouds_pos = EYEDIR; // The same is used for cloud rendering.
	vec3 sun_pos = LIGHT0_DIRECTION; // Redefined from now-deprecated _sun_direction.
	vec3 moon_pos = LIGHT1_DIRECTION; // Redefined from now-deprecated _moon_direction.

	if (sky_visible) {
		col = render_sky(world_pos, clouds_pos, sun_pos, moon_pos, current_time);
	}

	// Draw overlay grids
	{
		float grid_thickness = 0.0002;
		float grid_spacing = 0.261799; // 15 degrees
		vec3 zenith_dir = vec3(0.0, 1.0, 0.0); // Y-axis aligned azimuthal
		vec3 north_celestial_pole = create_rotation_matrix(vec3(star_tilt, 0.0, 0.0)) * zenith_dir;
		float rotation_angle = star_rotation + star_rotation_offset;
		if (show_azimuthal_grid) {
			render_grid(EYEDIR, zenith_dir, azimuthal_grid_rotation_offset, azimuthal_grid_color, grid_spacing, grid_thickness, col);
		}
		if (show_equatorial_grid) {
			render_grid(EYEDIR, north_celestial_pole, rotation_angle + equatorial_grid_rotation_offset, equatorial_grid_color, grid_spacing, grid_thickness, col);
		}
	}

	COLOR = col.rgb;
}
