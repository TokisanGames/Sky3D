// Copyright (c) 2023-2025 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar

shader_type sky;
render_mode use_debanding;

uniform bool sky_visible = true;
uniform bool show_azimuthal_grid = false;
uniform vec4 azimuthal_grid_color = vec4(.871, .722, .529, 1.);
uniform bool show_equatorial_grid = false;
uniform vec4 equatorial_grid_color = vec4(0., .75, 1., 1.);

// Color correction
group_uniforms General;
uniform vec2 color_correction_params = vec2(0.0, 1.0);
uniform vec4 ground_color: source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float horizon_level = 0.0;

// Moon and Deep Space

// Atmospheric Scattering
group_uniforms Atmospheric_Scattering_and_Colors;
uniform float atm_darkness = 0.5;
uniform float atm_sun_intensity = 18.0;
uniform vec4 atm_day_tint: source_color = vec4(0.808, 0.91, 1.0, 1.0);
uniform vec4 atm_horizon_light_tint: source_color = vec4(0.98, 0.635, 0.463, 1.0);
uniform vec4 atm_night_tint: source_color = vec4 (0.041, 0.049, 0.061, 0.245);
uniform vec3 atm_level_params = vec3(1.0, 0.0, 0.0);
uniform float atm_thickness = 0.7;
uniform vec3 atm_beta_ray = vec3(0.00001, 0.00001, 0.00003);
uniform vec3 atm_beta_mie = vec3(0.00000003038); // Value computed by multiplying Mie, turbidity, and 0.000434.

// Sun disk
group_uniforms Sun_Disk;
uniform vec4 sun_disk_color: source_color = vec4(0.996, 0.541, 0.14, 1.0);
uniform float sun_disk_intensity = 2.0;
uniform float sun_disk_size = 0.015;

// Sun mie phase
group_uniforms Sun_Mie_Scattering;
uniform vec4 atm_sun_mie_tint: source_color = vec4(1.0);
uniform float atm_sun_mie_intensity = 1.0;
uniform vec3 atm_sun_partial_mie_phase = vec3(0.36, 1.64, 1.6);

group_uniforms Moon;
uniform vec4 moon_color: source_color = vec4(1.0);
uniform sampler2D moon_texture: source_color, repeat_disable;
uniform vec3 moon_texture_alignment = vec3(7.0, 1.4, 4.8);
uniform bool moon_texture_flip_u;
uniform bool moon_texture_flip_v;
uniform float moon_size = 0.07;

group_uniforms Moon_Mie_Scattering;
uniform vec4 atm_moon_mie_tint: source_color = vec4(0.137, 0.184, 0.292, 1.0);
uniform float atm_moon_mie_intensity = 0.17152;
uniform vec3 atm_moon_partial_mie_phase = vec3(0.36, 1.64, 1.6);

// Background
group_uniforms Background_Texture;
uniform sampler2D background_texture: source_color;
uniform vec4 background_color: source_color = vec4(0.71, 0.71, 0.71, 0.855);

// Stars Field
group_uniforms Starfield;
uniform vec4 stars_field_color: source_color = vec4(1.0);
uniform sampler2D stars_field_texture: source_color;
uniform vec3 sky_alignment = vec3(2.6555, -0.23935, 0.4505);
uniform float sky_rotation = 0.0; // For simulating Earth rotation.
uniform float sky_tilt = 0.0; // For tilting the sky according to observer latitude in radians. (90° - latitude)
uniform float stars_scintillation = 0.75;
uniform float stars_scintillation_speed = 0.01;
uniform sampler2D noise_tex: source_color;

/* Sky alignment values for a star map that is in galactic coordinates. Works for most star maps.
X: 2.6555
Y: -0.23935
Z: 0.4505

These alignment values are consistent with a sky view from the North Pole (latitude zero)
at midnight. The positions of Polaris, Vega, Rigel, and Alpha Centauri confirmed
through various sources and calculations.
*/

// Clouds
group_uniforms Clouds;
uniform bool clouds_visible = true;
uniform float clouds_coverage = 0.5;
uniform float clouds_thickness = 10.0;
uniform float clouds_absorption = 2.0;
uniform float clouds_sky_tint_fade = 0.5;
uniform float clouds_intensity = 10.0;
uniform float clouds_size = 2.0;
uniform vec2 clouds_uv = vec2(0.16, 0.11);
uniform float clouds_speed = 0.07;
uniform vec2 clouds_direction = vec2(0.25);
uniform vec4 clouds_day_color: source_color = vec4(0.824, 0.875, 1.0, 1.0);
uniform vec4 clouds_horizon_light_color: source_color = vec4(0.98, 0.43, 0.15, 1.0);
uniform vec4 clouds_night_color: source_color = vec4(0.09, 0.094, 0.129, 1.0);
uniform sampler2D clouds_texture;

group_uniforms Cumulus_Clouds;
uniform bool cumulus_clouds_visible = true;
uniform float cumulus_clouds_coverage = 0.55;
uniform float cumulus_clouds_thickness = 0.0243;
uniform float cumulus_clouds_absorption = 2.0;
uniform float cumulus_clouds_noise_freq = 2.7;
uniform float cumulus_clouds_sky_tint_fade = 0.0;
uniform float cumulus_clouds_intensity = 1.0;
uniform float cumulus_clouds_size = 0.5;
uniform float cumulus_clouds_speed = 0.05;
uniform vec3 cumulus_clouds_direction = vec3(0.25, 0.1, 0.25);
uniform sampler2D cumulus_clouds_texture;
uniform vec4 cumulus_clouds_day_color: source_color = vec4(0.824, 0.875, 1.0, 1.0);
uniform vec4 cumulus_clouds_horizon_light_color: source_color = vec4(0.98, 0.443, 0.15, 1.0);
uniform vec4 cumulus_clouds_night_color: source_color = vec4(0.09, 0.094, 0.129, 1.0);
uniform vec3 cumulus_clouds_partial_mie_phase = vec3(0.95756, 1.04244, 0.412);
uniform float cumulus_clouds_mie_intensity = 1.0;

group_uniforms Transform_Matrices;
uniform mat3 moon_matrix; // Set externally via GDScript.
uniform mat3 deep_space_matrix; // Set externally via GDScript for star map rotation.

const int kCUMULUS_CLOUDS_STEP = 10;
const float k3PI8 = 3.0 / (8.0 * PI);

float saturate(float value) {
	return clamp(value, 0.0, 1.0);
}

vec3 saturateRGB(vec3 value) {
	return clamp(value.rgb, 0.0, 1.0);
}

// pow3
vec3 contrastLevel(vec3 vec, float level) {
	return mix(vec, vec * vec * vec, level);
}

vec3 tonemapPhoto(vec3 color, float exposure, float level) {
	color.rgb *= exposure;
	return mix(color.rgb, 1.0 - exp(-color.rgb), level);
}

// Provides a transformation matrix when passed a vec3.
mat3 rotationMatrix(vec3 r) {
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

vec2 equirectUV(vec3 norm) {
	float u = (atan(norm.y, norm.x) + PI) / TAU; // 0 to 1 horizontally
    float v = acos(norm.z) / PI; // 0 (north pole) to 1 (south pole)
    return vec2(u, v);
}

vec3 get_moon_texture_equirectUV(vec3 dir) {
    dir = moon_matrix * dir * rotationMatrix(moon_texture_alignment);
	dir.x = -dir.x;
	dir.z = -dir.z;
	float u = 0.0; // Longitude
	float v = 0.0; // Latitude
	if (moon_texture_flip_u) {
    	u = 0.5 + atan(dir.z, dir.x) / (2.0 * 3.141592653589793);
	} else {
    	u = 0.5 - atan(dir.z, dir.x) / (2.0 * 3.141592653589793);
	}

	if (moon_texture_flip_v) {
    	v = 0.5 + asin(dir.y) / 3.141592653589793;
	} else {
    	v = 0.5 - asin(dir.y) / 3.141592653589793;
	}
    return texture(moon_texture, vec2(u, v)).rgb;
}

float disk(vec3 norm, vec3 coords, lowp float size) {
	float dist = length(norm - coords);
	return 1.0 - step(size, dist);
}

float remap(float value, float fromMin, float fromMax, float toMin, float toMax) {
	return toMin + (value - fromMin) * (toMax - toMin) / (fromMax - fromMin);
}

bool IntersectSphere(float r, vec3 origin, vec3 dir, out float t, out vec3 nrm) {
	origin += vec3(0.0, 450.0, 0.0);
	float a = dot(dir, dir);
	float b = 2.0 * dot(origin, dir);
	float c = dot(origin, origin) - r * r;
	float d = b * b - 4.0 * a * c;
	if (d < 0.0) return false;

	d = sqrt(d);
	a *= 2.0;
	float t1 = 0.5 * (-b + d);
	float t2 = 0.5 * (-b - d);

	if (t1 < 0.0) t1 = t2;
	if (t2 < 0.0) t2 = t1;
	t1 = min(t1, t2);

	if (t1 < 0.0) return false;
	nrm = origin + t1 * dir;
	t = t1;

	return true;
}

// For rendering the moon. This function courtesy of Kelvin van Hoorn.
// https://kelvinvanhoorn.com/2024/12/07/skybox-tutorial-godot/
float sphere_intersect(vec3 ray_dir, vec3 sphere_pos, float radius) {
    vec3 oc = -sphere_pos;
    float b = dot(oc, ray_dir);
    float c = dot(oc, oc) - radius * radius;
    float h = b * b - c;
    if (h < 0.0) return -1.0;
    h = sqrt(h);
    return -b - h;
}

// Atmosphere Inc
//------------------------------------------------------------------------------
const float RAYLEIGH_ZENITH_LENGTH = 8.4e3;
const float MIE_ZENITH_LENGTH = 1.25e3;

float rayleighPhase(float mu) {
	return k3PI8 * (1.0 + mu * mu);
}

float miePhase(float mu, vec3 partial) {
	return (4.0 * PI) * (partial.x) * (pow(partial.y - partial.z * mu, -1.5));
}

// Simplifield for more performance
void simpleOpticalDepth(float y, out float sr, out float sm) {
	y = max(0.03, y + 0.03) + atm_level_params.y;
	y = 1.0 / (y * atm_level_params.x);
	sr = y * RAYLEIGH_ZENITH_LENGTH;
	sm = y * MIE_ZENITH_LENGTH;
}

// Paper based
void opticalDepth(float y, out float sr, out float sm) {
	y = max(0.0, y);
	y = saturate(y * atm_level_params.x);

	float zenith = acos(y);
	zenith = cos(zenith) + 0.15 * pow(93.885 - ((zenith * 180.0) / PI), -1.253);
	zenith = 1.0 / (zenith + atm_level_params.y);

	sr = zenith * RAYLEIGH_ZENITH_LENGTH;
	sm = zenith * MIE_ZENITH_LENGTH;
}

vec3 atmosphericScattering(float sr, float sm, vec2 mu, vec3 mult) {
	vec3 betaMie = atm_beta_mie;
	vec3 betaRay = atm_beta_ray * atm_thickness;

	vec3 extcFactor = saturateRGB(exp(-(betaRay * sr + betaMie * sm)));

	float extcFF = mix(saturate(atm_thickness * 0.5), 1.0, mult.x);
	vec3 finalExtcFactor = mix(1.0 - extcFactor, (1.0 - extcFactor) * extcFactor, extcFF);
	float rayleighPhase = rayleighPhase(mu.x);
	vec3 BRT = betaRay * rayleighPhase;
	vec3 BMT = betaMie * miePhase(mu.x, atm_sun_partial_mie_phase);
	BMT *= atm_sun_mie_intensity * atm_sun_mie_tint.rgb;

	vec3 BRMT = (BRT + BMT) / (betaRay + betaMie);
	vec3 scatter = atm_sun_intensity * (BRMT * finalExtcFactor) * atm_day_tint.rgb * mult.y;
	scatter = mix(scatter, scatter * (1.0 - extcFactor), atm_darkness);

	vec3 lcol =  mix(atm_day_tint.rgb, atm_horizon_light_tint.rgb, mult.x);
	vec3 nscatter = (1.0 - extcFactor) * atm_night_tint.rgb;
	nscatter += miePhase(mu.y, atm_moon_partial_mie_phase) *
		atm_moon_mie_tint.rgb * atm_moon_mie_intensity * 0.005;

	return (scatter * lcol) + nscatter;
}

// Clouds
//------------------------------------------------------------------------------
float noiseClouds(vec2 coords, vec2 offset, float p_time) {
	float speed = p_time * clouds_speed * .5; // .5 matches cumulus clouds
	vec2 wind = offset * speed;
	vec2 wind2 = (offset + offset) * speed;
	float a = textureLod(clouds_texture, coords.xy * clouds_uv - wind, 0.0).r;
	float b = textureLod(clouds_texture, coords.xy * clouds_uv - wind2, 0.0).r;
	return ((a + b) * 0.5);
}

float noiseCloudsCumulus(vec3 p) {
	vec3 pos = vec3(p * 0.01);
	pos.z *= 256.0;
	vec2 offset = vec2(0.317, 0.123);
	vec4 uv = vec4(0.0);
	uv.xy = pos.xy + offset * floor(pos.z);
	uv.zw = uv.xy + offset;
	float x1 = textureLod(cumulus_clouds_texture, uv.xy, 0.0).r;
	float x2 = textureLod(cumulus_clouds_texture, uv.zw, 0.0).r;
	return mix(x1, x2, fract(pos.z));
}

float cloudsFBM(vec3 p, float l) {
	float ret;
	ret = 0.51749673 * noiseCloudsCumulus(p);
	p *= l;
	ret += 0.25584929 * noiseCloudsCumulus(p);
	p *= l;
	ret += 0.12527603 * noiseCloudsCumulus(p);
	p *= l;
	ret += 0.06255931 * noiseCloudsCumulus(p);
	return ret;
}

float cloudsDensity(vec2 p, vec2 offset, float p_time) {
	float d = noiseClouds(p, offset, p_time);
	float c = 1.0 - clouds_coverage;
	d = d - c;
	//d += d;
	return saturate(d);
}

float cloudsDensityCumulus(vec3 p, vec3 offset, float t) {
	vec3 pos = p * 0.0212242 - offset;
	float dens = cloudsFBM(pos, cumulus_clouds_noise_freq);
	dens += dens;

	float cov = 1.0-cumulus_clouds_coverage;
	cov = smoothstep(0.00, (cov * 3.5) + t, dens);
	dens *= cov;
	dens = remap(dens, 1.0-cov, 1.0, 0.0, 1.0);

	return saturate(dens);
}

vec4 renderClouds(vec3 pos, float p_time) {
	pos.xy = pos.xz / pos.y;
	pos *= clouds_size;
	float density = cloudsDensity(pos.xy, clouds_direction, p_time);
	float sh = saturate(exp(-clouds_absorption * density));
	float a = saturate(density * clouds_thickness);
	return vec4(vec3(density*sh) * clouds_intensity, a);
}

vec4 renderCloudsCumulus(vec3 ro, vec3 rd, float am, vec3 sunPosition, vec3 moonPosition, float p_time) {
	vec4 ret = vec4(0, 0, 0, 0);
	vec3 wind = cumulus_clouds_direction * (p_time * cumulus_clouds_speed);
	float a = 0.0;

	// n and tt doesnt need to be initialized since it would be set by IntersectSphere
	vec3 n; float tt;
    if (IntersectSphere(500, ro, rd, tt, n)) {
		float marchStep = float(kCUMULUS_CLOUDS_STEP) * cumulus_clouds_thickness;
		vec3 dirStep = rd / rd.y * marchStep;
		vec3 pos = n * cumulus_clouds_size;

		vec2 mu = vec2(dot(sunPosition, rd), dot(moonPosition, rd));
		vec3 mph = ((miePhase(mu.x, cumulus_clouds_partial_mie_phase) * atm_sun_mie_tint.rgb) +
		miePhase(mu.y, cumulus_clouds_partial_mie_phase) * am);

		vec4 t = vec4(1.0);
		t.rgb += (mph.rgb * cumulus_clouds_mie_intensity);

		for(int i = 0; i < kCUMULUS_CLOUDS_STEP; i++) {
			float h = float(i) * 0.1; // / float(kCLOUDS_STEP);

			float density = cloudsDensityCumulus(pos, wind, h);
			float sh = saturate(exp(-cumulus_clouds_absorption * density * marchStep));
			t *= sh;
			ret += (t * (exp(h) * 0.571428571) * density * marchStep);
			a += (1.0 - sh) * (1.0 - a);
			pos += dirStep;
		}
		return vec4(ret.rgb * cumulus_clouds_intensity, a);
	}
	return vec4(ret.rgb * cumulus_clouds_intensity, a);
}

vec3 render_sky(vec3 worldPos, vec3 cloudsPos, vec3 sunPosition, vec3 moonPosition, vec3 deep_space_coords, float p_time) {
	vec3 col = vec3(0.0);

	vec4 angle_mult;
	angle_mult.x = saturate(1.0 - sunPosition.y);
	angle_mult.y = saturate(sunPosition.y + 0.45);
	angle_mult.z = saturate(-sunPosition.y + 0.30);
	angle_mult.w = saturate(-sunPosition.y + 0.60);

	// Atmosphere
	vec2 mu = vec2(dot(sunPosition, worldPos), dot(moonPosition, worldPos));
	float sr, sm;
	simpleOpticalDepth(worldPos.y + atm_level_params.z + horizon_level, sr, sm);

	worldPos.y += horizon_level;
	float horizonBlend = saturate((worldPos.y - 0.03) * 3.0);
	float horizonBlendCumulus = saturate((worldPos.y + 0.01) * 50.0);

	vec3 scatter = atmosphericScattering(sr, sm, mu.xy, angle_mult.xyz);
	col.rgb += scatter.rgb;

	// Near Space
	vec3 nearSpace = vec3(0.0);
	vec3 sunDisk = disk(worldPos, sunPosition, sun_disk_size) * sun_disk_color.rgb * scatter.rgb;
	sunDisk *= sun_disk_intensity;

	// Moon-Moon
	float moon_intersect = sphere_intersect(worldPos, moonPosition, moon_size);
	float moon_mask = moon_intersect > (-1. + sqrt(moon_size)) ? 1.0 : 0.0;
	vec3 moon_normal = normalize(worldPos * moon_intersect - moonPosition);

	float moon_ndotl = clamp(dot(moon_normal, sunPosition), 0.0, 1.0);
	vec3 _moon_texture = get_moon_texture_equirectUV(moon_normal);
	vec3 moon_output = moon_mask * moon_ndotl * exp2(1.0) * _moon_texture * moon_color.rgb;
	float moonMask = (1.0 - moon_mask);

	vec3 deepSpace = vec3(0.0);

	// Tilt the sky along the X-axis.
	mat3 tilt = rotationMatrix(vec3(sky_tilt, 0.0, 0.0));

    // Rotation around Y-axis. For simulating Earth's rotation.
    mat3 rotation = rotationMatrix(vec3(0.0, sky_rotation, 0.0));

    // Initial XYZ rotation for alignment.
    mat3 alignment_xyz = rotationMatrix(sky_alignment);

	// Combine everything together to get the desired alignment.
	vec3 final_alignment = normalize(alignment_xyz * rotation * tilt * worldPos);

	// Now generate UV coordinates for the texture.
	vec2 deepSpaceUV = equirectUV(normalize(final_alignment));

	// Background
	vec3 deepSpaceBackground = textureLod(background_texture, deepSpaceUV, 0.0).rgb;
	deepSpaceBackground *= background_color.rgb;
	deepSpaceBackground = contrastLevel(deepSpaceBackground, background_color.a);
	deepSpace.rgb += deepSpaceBackground.rgb * moonMask + moon_output;

	// Stars Field
	float starsScintillation = textureLod(noise_tex, deepSpaceUV + (p_time * stars_scintillation_speed), 0.0).r;
	starsScintillation = mix(1.0, starsScintillation * 1.5, stars_scintillation);

	vec3 starsField = textureLod(stars_field_texture, deepSpaceUV, 0.0).rgb * stars_field_color.rgb;
	starsField = saturateRGB(mix(starsField.rgb, starsField.rgb * starsScintillation, stars_scintillation));
	starsField = saturateRGB(starsField.rgb);
	//deepSpace.rgb -= saturate(starsField.r * 10.0);
	deepSpace.rgb += starsField.rgb * moonMask;
	deepSpace.rgb *= angle_mult.z;
	col.rgb += sunDisk.rgb + deepSpace.rgb * horizonBlend;

	// Clouds
	if (clouds_visible) {
		vec4 clouds = renderClouds(cloudsPos, p_time);
		clouds.a = saturate(clouds.a);
		clouds.rgb *= mix(mix(clouds_day_color.rgb, clouds_horizon_light_color.rgb, angle_mult.x), clouds_night_color.rgb, angle_mult.w);

		clouds.a = mix(0.0, clouds.a, horizonBlend);
		col.rgb = mix(col.rgb, clouds.rgb + mix(vec3(0.0), scatter, clouds_sky_tint_fade), clouds.a);
	}

	if (cumulus_clouds_visible) {
		vec4 cumulusClouds = renderCloudsCumulus(vec3(0.0), cloudsPos, angle_mult.z, sunPosition, moonPosition, p_time);
		cumulusClouds.a = saturate(cumulusClouds.a);
		cumulusClouds.rgb *= mix(mix(cumulus_clouds_day_color.rgb, cumulus_clouds_horizon_light_color.rgb, angle_mult.x),
			cumulus_clouds_night_color.rgb, angle_mult.w);
		cumulusClouds.a = mix(0.0, cumulusClouds.a, horizonBlend);
		col.rgb = mix(col.rgb, cumulusClouds.rgb + mix(vec3(0.0), scatter, cumulus_clouds_sky_tint_fade), cumulusClouds.a);
	}

	col.rgb = mix(col.rgb, ground_color.rgb * scatter, saturate((-worldPos.y - atm_level_params.z) * 100.0));
	col.rgb = tonemapPhoto(col.rgb, color_correction_params.y, color_correction_params.x);
	return col;
}

float fwidth_custom(float p) {
	return length(vec2(dFdx(p), dFdy(p)));
}

vec4 quaternion_from_axis_angle(vec3 axis, float angle) {
	float s = sin(angle * 0.5);
	return vec4(axis * s, cos(angle * 0.5));
}

vec3 rotate_vector(vec3 v, vec4 q) {
	vec3 t = 2.0 * cross(q.xyz, v);
	return v + q.w * t + cross(q.xyz, t);
}

vec3 align_and_rotate(vec3 dir, vec3 target, float rotation_angle) {
	vec3 z_axis = vec3(0.0, 0.0, 1.0); // Original grid alignment

	// First, align Z-axis with target (Polaris)
	target = normalize(target);
	vec3 axis = cross(z_axis, target);
	float angle = acos(dot(z_axis, target));
	if (length(axis) >= 0.0001) {
		axis = normalize(axis);
		vec4 align_quat = quaternion_from_axis_angle(axis, angle);
		dir = rotate_vector(dir, align_quat);

		// Rotate around the new Z-axis (which is now aligned with Polaris)
		vec4 rot_quat = quaternion_from_axis_angle(vec3(0.0, 0.0, 1.0), rotation_angle);
		dir = rotate_vector(dir, rot_quat);
	}
	return dir;
}

void draw_grid(vec3 dir, vec3 pole_dir, float rotation_angle, vec4 line_color, float grid_spacing, float line_thickness, inout vec3 color) {
	float spacing = max(grid_spacing, 0.001);
	float thickness = max(line_thickness, 0.0001);

	// Rotate dir with sidereal motion and align with pole_dir
	dir = align_and_rotate(dir, pole_dir, rotation_angle);

	// Latitude / Circles / Theta Spherical coordinates
	float theta = acos(dir.z);
	float theta_deriv = fwidth_custom(theta);
	float circle_thickness = max(thickness, theta_deriv);
	float circle = mod(theta, spacing);
	float circle_line = 1.0 - smoothstep(0.0, circle_thickness * 1.5, abs(circle - circle_thickness * 0.5));
	circle_line *= saturate(thickness / circle_thickness);

	// Add poles
	float pole_thickness = circle_thickness;
	float north_pole = 1.0 - smoothstep(0.0, pole_thickness, theta);
	float south_pole = 1.0 - smoothstep(0.0, pole_thickness, abs(theta - 3.14159));
	circle_line = max(circle_line, max(north_pole, south_pole));

	// Darken Lat at poles
	float circle_adjust = sin(theta);
	circle_line *= clamp(circle_adjust, 0.2, 1.0);

	// Longitude / Radial lines / Phi Spherical coordinates
	float phi = atan(dir.y, dir.x);
	float phi_deriv = fwidth_custom(phi);
	float radial_thickness = max(thickness, phi_deriv);
	float radial = mod(phi + 3.14, spacing); // PI w/ less precision to remove moire
	float radial_line = 1.0 - smoothstep(0.0, radial_thickness * 1.5, abs(radial - radial_thickness));
	radial_line *= saturate(thickness / radial_thickness);

	float grid = max(radial_line, circle_line);
	color += line_color.rgb * line_color.a * grid;
}

void sky() {
	float current_time = TIME;
	vec3 col = vec3(0.0); // Set up the initial sky color which will be added to later to produce the final result.
	vec3 worldPos = EYEDIR; // Original shader set this up in the vertex() function. For sky shaders the overall equivalent is EYEDIR.
	vec3 cloudsPos = EYEDIR; // The same is used for cloud rendering.
	vec3 sunPosition = LIGHT0_DIRECTION; // Redefined from now-deprecated _sun_direction.
	vec3 moonPosition = LIGHT1_DIRECTION; // Redefined from now-deprecated _moon_direction.
	vec3 deep_space_coords = (deep_space_matrix * EYEDIR).xyz;

	if (sky_visible) {
		col = render_sky(worldPos, cloudsPos, sunPosition, moonPosition, deep_space_coords, current_time);
	}

	// Draw overlay grids
	{
		float grid_thickness = 0.0002;
		float grid_spacing = 0.261799; // 15 degrees
		vec3 zenith_dir = vec3(0.0, 1.0, 0.0); // Y-axis aligned azimuthal
		vec3 polaris_dir = normalize(vec3(0.001, 0.0, 1.0)); // TODO Update with position of polaris
		float sidereal_rate = -TAU / 24.0; // Sidereal rotation: ~15 degrees/hour (2π/24 radians/hour)
		float rotation_angle = .05 * TIME * sidereal_rate; // TOOD update rotation w/ sky rotation
		if (show_azimuthal_grid) {
			draw_grid(EYEDIR, zenith_dir, 0.0, azimuthal_grid_color, grid_spacing, grid_thickness, col);
		}
		if (show_equatorial_grid) {
			draw_grid(EYEDIR, polaris_dir, rotation_angle, equatorial_grid_color, grid_spacing, grid_thickness, col);
		}
	}

	COLOR = col.rgb;
}
