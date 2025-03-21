// Copyright (c) 2023-2025 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar

shader_type sky;
render_mode use_debanding;

uniform bool _sky_visible = true;

// Color correction
group_uniforms General;
uniform vec2 _color_correction_params = vec2(0.0, 1.3);
uniform vec4 _ground_color: source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float _horizon_level = 0.0;
uniform float _reflected_energy: hint_range(0.0, 128.0, 0.1) = 1.0;

// Moon and Deep Space

// Atmospheric Scattering
group_uniforms Atmospheric_Scattering_and_Colors;
uniform float _atm_darkness = 0.5;
uniform float _atm_sun_intensity = 18.0;
uniform vec4 _atm_day_tint: source_color = vec4(0.808, 0.91, 1.0, 1.0);
uniform vec4 _atm_horizon_light_tint: source_color = vec4(0.98, 0.635, 0.463, 1.0);
uniform vec4 _atm_night_tint: source_color = vec4 (0.041, 0.049, 0.061, 0.245);
uniform vec3 _atm_level_params = vec3(1.0, 0.0, 0.0);
uniform float _atm_thickness = 0.7;
uniform vec3 _atm_beta_ray = vec3(0.00001, 0.00001, 0.00003);
uniform vec3 _atm_beta_mie = vec3(0.00000003038); // Value computed by multiplying Mie, turbidity, and 0.000434.

// Sun disk
group_uniforms Sun_Disk;
uniform vec4 _sun_disk_color: source_color = vec4(0.996, 0.541, 0.14, 1.0);
uniform float _sun_disk_intensity = 2.0;
uniform float _sun_disk_size = 0.015;

// Sun mie phase
group_uniforms Sun_Mie_Scattering;
uniform vec4 _atm_sun_mie_tint: source_color = vec4(1.0);
uniform float _atm_sun_mie_intensity = 1.0;
uniform vec3 _atm_sun_partial_mie_phase = vec3(0.36, 1.64, 1.6);

group_uniforms Moon;
uniform vec4 _moon_color: source_color = vec4(1.0);
uniform sampler2D _moon_texture: source_color, repeat_disable;
uniform float _moon_size = 0.07;

group_uniforms Moon_Mie_Scattering;
uniform vec4 _atm_moon_mie_tint: source_color = vec4(0.137, 0.184, 0.292, 1.0);
uniform float _atm_moon_mie_intensity = 0.17152;
uniform vec3 _atm_moon_partial_mie_phase = vec3(0.36, 1.64, 1.6);

// Background
group_uniforms Background_Texture;
uniform sampler2D _background_texture: source_color;
uniform vec4 _background_color: source_color = vec4(0.71, 0.71, 0.71, 0.855);

// Stars Field
group_uniforms Starfield;
uniform vec4 _stars_field_color: source_color = vec4(1.0);
uniform sampler2D _stars_field_texture: source_color;
uniform float _stars_scintillation = 0.75;
uniform float _stars_scintillation_speed = 0.01;
uniform sampler2D _noise_tex: source_color;

// Clouds
group_uniforms Clouds;
uniform bool _clouds_visible = true;
uniform float _clouds_coverage = 0.5;
uniform float _clouds_thickness = 10.0;
uniform float _clouds_absorption = 2.0;
uniform float _clouds_sky_tint_fade = 0.5;
uniform float _clouds_intensity = 10.0;
uniform float _clouds_size = 2.0;
uniform vec2 _clouds_uv = vec2(0.16, 0.11);
uniform float _clouds_speed = 0.07;
uniform vec2 _clouds_direction = vec2(0.25);
uniform vec4 _clouds_day_color: source_color = vec4(0.824, 0.875, 1.0, 1.0);
uniform vec4 _clouds_horizon_light_color: source_color = vec4(0.98, 0.43, 0.15, 1.0);
uniform vec4 _clouds_night_color: source_color = vec4(0.09, 0.094, 0.129, 1.0);
uniform sampler2D _clouds_texture;

group_uniforms Cumulus_Clouds;
uniform bool _cumulus_clouds_visible = true;
uniform float _cumulus_clouds_coverage = 0.55;
uniform float _cumulus_clouds_thickness = 0.0243;
uniform float _cumulus_clouds_absorption = 2.0;
uniform float _cumulus_clouds_noise_freq = 2.7;
uniform float _cumulus_clouds_sky_tint_fade = 0.0;
uniform float _cumulus_clouds_intensity = 1.0;
uniform float _cumulus_clouds_size = 0.5;
uniform float _cumulus_clouds_speed = 0.05;
uniform vec3 _cumulus_clouds_direction = vec3(0.25, 0.1, 0.25);
uniform sampler2D _cumulus_clouds_texture;
uniform vec4 _cumulus_clouds_day_color: source_color = vec4(0.824, 0.875, 1.0, 1.0);
uniform vec4 _cumulus_clouds_horizon_light_color: source_color = vec4(0.98, 0.443, 0.15, 1.0);
uniform vec4 _cumulus_clouds_night_color: source_color = vec4(0.09, 0.094, 0.129, 1.0);
uniform vec3 _cumulus_clouds_partial_mie_phase = vec3(0.95756, 1.04244, 0.412);
uniform float _cumulus_clouds_mie_intensity = 1.0;

group_uniforms Transform_Matrices;
uniform mat3 _moon_matrix; // Set externally via GDScript.
uniform mat3 _deep_space_matrix; // Set externally via GDScript for star map rotation.


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


vec3 tonemapPhoto(vec3 color, float exposure, float level){
	color.rgb *= exposure;
	return mix(color.rgb, 1.0 - exp(-color.rgb), level);
}


vec2 equirectUV(vec3 norm) {
	vec2 ret;
	ret.x = (atan(norm.x, norm.z) + PI) * (1.0 / TAU);
	ret.y = acos(norm.y) * (1.0/PI);
	return ret;
}


vec3 get_moon_texture_equirectUV(vec3 dir)
{
    dir = _moon_matrix * dir;
	dir.x = -dir.x;
	dir.z = -dir.z;
    float u = 0.5 + atan(dir.z, dir.x) / (2.0 * 3.141592653589793);  // Longitude
    float v = 0.5 - asin(dir.y) / 3.141592653589793;                   // Latitude
    return texture(_moon_texture, vec2(u, v)).rgb;
}


float disk(vec3 norm, vec3 coords, lowp float size) {
	float dist = length(norm - coords);
	return 1.0 - step(size, dist);
}


float remap(float value, float fromMin, float fromMax, float toMin, float toMax){
	return toMin + (value - fromMin) * (toMax - toMin) / (fromMax - fromMin);
}


bool IntersectSphere(float r, vec3 origin, vec3 dir, out float t, out vec3 nrm)
{
	origin += vec3(0.0, 450.0, 0.0);
	float a = dot(dir, dir);
	float b = 2.0 * dot(origin, dir);
	float c = dot(origin, origin) - r * r;
	float d = b * b - 4.0 * a * c;
	if(d < 0.0) return false;
	
	d = sqrt(d);
	a *= 2.0;
	float t1 = 0.5 * (-b + d);
	float t2 = 0.5 * (-b - d);
	
	if(t1<0.0) t1 = t2;
	if(t2 < 0.0) t2 = t1;
	t1 = min(t1, t2);
	
	if(t1 < 0.0) return false;
	nrm = origin + t1 * dir;
	t = t1;
	
	return true;
}


// For rendering the moon. This function courtesy of Kelvin van Hoorn.
// https://kelvinvanhoorn.com/2024/12/07/skybox-tutorial-godot/
float sphere_intersect(vec3 ray_dir, vec3 sphere_pos, float radius)
{
    vec3 oc = -sphere_pos;
    float b = dot(oc, ray_dir);
    float c = dot(oc, oc) - radius * radius;
    float h = b * b - c;
    if(h < 0.0) return -1.0;
    h = sqrt(h);
    return -b - h;
}


// Atmosphere Inc
//------------------------------------------------------------------------------
const float RAYLEIGH_ZENITH_LENGTH = 8.4e3;
const float MIE_ZENITH_LENGTH = 1.25e3;

float rayleighPhase(float mu){
	return k3PI8 * (1.0 + mu * mu);
}


float miePhase(float mu, vec3 partial){
	return (4.0 * PI) * (partial.x) * (pow(partial.y - partial.z * mu, -1.5));
}


// Simplifield for more performance
void simpleOpticalDepth(float y, out float sr, out float sm) {
	y = max(0.03, y + 0.03) + _atm_level_params.y;
	y = 1.0 / (y * _atm_level_params.x);
	sr = y * RAYLEIGH_ZENITH_LENGTH;
	sm = y * MIE_ZENITH_LENGTH;
}


// Paper based
void opticalDepth(float y, out float sr, out float sm) {
	y = max(0.0, y);
	y = saturate(y * _atm_level_params.x);

	float zenith = acos(y);
	zenith = cos(zenith) + 0.15 * pow(93.885 - ((zenith * 180.0) / PI), -1.253);
	zenith = 1.0 / (zenith + _atm_level_params.y);

	sr = zenith * RAYLEIGH_ZENITH_LENGTH;
	sm = zenith * MIE_ZENITH_LENGTH;
}


vec3 atmosphericScattering(float sr, float sm, vec2 mu, vec3 mult) {
	vec3 betaMie = _atm_beta_mie;
	vec3 betaRay = _atm_beta_ray * _atm_thickness;

	vec3 extcFactor = saturateRGB(exp(-(betaRay * sr + betaMie * sm)));

	float extcFF = mix(saturate(_atm_thickness * 0.5), 1.0, mult.x);
	vec3 finalExtcFactor = mix(1.0 - extcFactor, (1.0 - extcFactor) * extcFactor, extcFF);
	float rayleighPhase = rayleighPhase(mu.x);
	vec3 BRT = betaRay * rayleighPhase;
	vec3 BMT = betaMie * miePhase(mu.x, _atm_sun_partial_mie_phase);
	BMT *= _atm_sun_mie_intensity * _atm_sun_mie_tint.rgb;

	vec3 BRMT = (BRT + BMT) / (betaRay + betaMie);
	vec3 scatter = _atm_sun_intensity * (BRMT * finalExtcFactor) * _atm_day_tint.rgb * mult.y;
	scatter = mix(scatter, scatter * (1.0 - extcFactor), _atm_darkness);

	vec3 lcol =  mix(_atm_day_tint.rgb, _atm_horizon_light_tint.rgb, mult.x);
	vec3 nscatter = (1.0 - extcFactor) * _atm_night_tint.rgb;
	nscatter += miePhase(mu.y, _atm_moon_partial_mie_phase) *
		_atm_moon_mie_tint.rgb * _atm_moon_mie_intensity * 0.005;

	return (scatter * lcol) + nscatter;
}


// Clouds
//------------------------------------------------------------------------------
float noiseClouds(vec2 coords, vec2 offset) {
	float speed = TIME * _clouds_speed * .5; // .5 matches cumulus clouds
	vec2 wind = offset * speed;
	vec2 wind2 = (offset + offset) * speed;
	float a = textureLod(_clouds_texture, coords.xy * _clouds_uv - wind, 0.0).r;
	float b = textureLod(_clouds_texture, coords.xy * _clouds_uv - wind2, 0.0).r;
	return ((a + b) * 0.5);
}


float noiseCloudsCumulus(vec3 p){
	vec3 pos = vec3(p * 0.01);
	pos.z *= 256.0;
	vec2 offset = vec2(0.317, 0.123);
	vec4 uv = vec4(0.0);
	uv.xy = pos.xy + offset * floor(pos.z);
	uv.zw = uv.xy + offset;
	float x1 = textureLod(_cumulus_clouds_texture, uv.xy, 0.0).r;
	float x2 = textureLod(_cumulus_clouds_texture, uv.zw, 0.0).r;
	return mix(x1, x2, fract(pos.z));
}


float cloudsFBM(vec3 p, float l){
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


float cloudsDensity(vec2 p, vec2 offset) {
	float d = noiseClouds(p, offset);
	float c = 1.0 - _clouds_coverage;
	d = d - c;
	//d += d;
	return saturate(d);
}


float cloudsDensityCumulus(vec3 p, vec3 offset, float t){
	vec3 pos = p * 0.0212242 - offset;
	float dens = cloudsFBM(pos, _cumulus_clouds_noise_freq);
	dens += dens;
	
	float cov = 1.0-_cumulus_clouds_coverage;
	cov = smoothstep(0.00, (cov * 3.5) + t, dens);
	dens *= cov;
	dens = remap(dens, 1.0-cov, 1.0, 0.0, 1.0); 
	
	return saturate(dens);
}


vec4 renderClouds(vec3 pos) {
	pos.xy = pos.xz / pos.y;
	pos *= _clouds_size;
	float density = cloudsDensity(pos.xy, _clouds_direction);
	float sh = saturate(exp(-_clouds_absorption * density));
	float a = saturate(density * _clouds_thickness);
	return vec4(vec3(density*sh) * _clouds_intensity, a);
}


vec4 renderCloudsCumulus(vec3 ro, vec3 rd, float tm, float am, vec3 sunPosition, vec3 moonPosition){
	vec4 ret = vec4(0, 0, 0, 0);
	vec3 wind = _cumulus_clouds_direction * (tm * _cumulus_clouds_speed);
	float a = 0.0;
	
	// n and tt doesnt need to be initialized since it would be set by IntersectSphere
	vec3 n; float tt;
    if(IntersectSphere(500, ro, rd, tt, n))
	{
		float marchStep = float(kCUMULUS_CLOUDS_STEP) * _cumulus_clouds_thickness;
		vec3 dirStep = rd / rd.y * marchStep;
		vec3 pos = n * _cumulus_clouds_size;
		
		vec2 mu = vec2(dot(sunPosition, rd), dot(moonPosition, rd));
		vec3 mph = ((miePhase(mu.x, _cumulus_clouds_partial_mie_phase) * _atm_sun_mie_tint.rgb) +
		miePhase(mu.y, _cumulus_clouds_partial_mie_phase) * am);
		
		vec4 t = vec4(1.0);
		t.rgb += (mph.rgb * _cumulus_clouds_mie_intensity);
		
		for(int i = 0; i < kCUMULUS_CLOUDS_STEP; i++)
		{
			float h = float(i) * 0.1; // / float(kCLOUDS_STEP);
			
			float density = cloudsDensityCumulus(pos, wind, h);
			float sh = saturate(exp(-_cumulus_clouds_absorption * density * marchStep));
			t *= sh;
			ret += (t * (exp(h) * 0.571428571) * density * marchStep);
			a += (1.0 - sh) * (1.0 - a);
			pos += dirStep;
		}
		return vec4(ret.rgb * _cumulus_clouds_intensity, a);
	}
	return vec4(ret.rgb * _cumulus_clouds_intensity, a);
}


vec3 render_sky(vec3 worldPos, vec3 cloudsPos, vec3 sunPosition, vec3 moonPosition, vec3 deep_space_coords) {
	vec3 col = vec3(0.0);
	
	vec4 angle_mult;
	angle_mult.x = saturate(1.0 - sunPosition.y);
	angle_mult.y = saturate(sunPosition.y + 0.45);
	angle_mult.z = saturate(-sunPosition.y + 0.30);
	angle_mult.w = saturate(-sunPosition.y + 0.60);

	// Atmosphere
	vec2 mu = vec2(dot(sunPosition, worldPos), dot(moonPosition, worldPos));
	float sr, sm;
	simpleOpticalDepth(worldPos.y + _atm_level_params.z + _horizon_level, sr, sm);

	worldPos.y += _horizon_level;
	float horizonBlend = saturate((worldPos.y - 0.03) * 3.0);
	float horizonBlendCumulus = saturate((worldPos.y + 0.01) * 50.0);

	vec3 scatter = atmosphericScattering(sr, sm, mu.xy, angle_mult.xyz);
	col.rgb += scatter.rgb;

	// Near Space
	vec3 nearSpace = vec3(0.0);
	vec3 sunDisk = disk(worldPos, sunPosition, _sun_disk_size) * _sun_disk_color.rgb * scatter.rgb;
	sunDisk *= _sun_disk_intensity;

	// Moon-Moon
	float moon_intersect = sphere_intersect(worldPos, moonPosition, _moon_size);
	float moon_mask = moon_intersect > -0.999 ? 1.0 : 0.0;
	vec3 moon_normal = normalize(worldPos * moon_intersect - moonPosition);
	
	float moon_ndotl = clamp(dot(moon_normal, sunPosition), 0.0, 1.0);
	vec3 moon_texture = get_moon_texture_equirectUV(moon_normal);
	vec3 moon_output = moon_mask * moon_ndotl * exp2(0.0) * moon_texture;
	float moonMask = (1.0 - moon_mask);

	vec3 deepSpace = vec3(0.0);
	vec2 deepSpaceUV = equirectUV(normalize(deep_space_coords));

	// Background
	vec3 deepSpaceBackground = textureLod(_background_texture, deepSpaceUV, 0.0).rgb;
	deepSpaceBackground *= _background_color.rgb;
	deepSpaceBackground = contrastLevel(deepSpaceBackground, _background_color.a);
	deepSpace.rgb += deepSpaceBackground.rgb * moonMask + moon_output;

	// Stars Field
	float starsScintillation = textureLod(_noise_tex, deepSpaceUV + (TIME * _stars_scintillation_speed), 0.0).r;
	starsScintillation = mix(1.0, starsScintillation * 1.5, _stars_scintillation);

	vec3 starsField = textureLod(_stars_field_texture, deepSpaceUV, 0.0).rgb * _stars_field_color.rgb;
	starsField = saturateRGB(mix(starsField.rgb, starsField.rgb * starsScintillation, _stars_scintillation));
	starsField = saturateRGB(starsField.rgb);
	//deepSpace.rgb -= saturate(starsField.r * 10.0);
	deepSpace.rgb += starsField.rgb * moonMask;
	deepSpace.rgb *= angle_mult.z;
	col.rgb += sunDisk.rgb + deepSpace.rgb * horizonBlend;

	// Clouds
	if (_clouds_visible) {
		vec4 clouds = renderClouds(cloudsPos);
		clouds.a = saturate(clouds.a);
		clouds.rgb *= mix(mix(_clouds_day_color.rgb, _clouds_horizon_light_color.rgb, angle_mult.x), _clouds_night_color.rgb, angle_mult.w);

		clouds.a = mix(0.0, clouds.a, horizonBlend);
		col.rgb = mix(col.rgb, clouds.rgb + mix(vec3(0.0), scatter, _clouds_sky_tint_fade), clouds.a);
	}
	
	if (_cumulus_clouds_visible) {
		vec4 cumulusClouds = renderCloudsCumulus(vec3(0.0), cloudsPos, TIME, angle_mult.z, sunPosition, moonPosition);
		cumulusClouds.a = saturate(cumulusClouds.a);
		cumulusClouds.rgb *= mix(mix(_cumulus_clouds_day_color.rgb, _cumulus_clouds_horizon_light_color.rgb, angle_mult.x), 
			_cumulus_clouds_night_color.rgb, angle_mult.w);
		cumulusClouds.a = mix(0.0, cumulusClouds.a, horizonBlend);
		col.rgb = mix(col.rgb, cumulusClouds.rgb + mix(vec3(0.0), scatter, _cumulus_clouds_sky_tint_fade), cumulusClouds.a);
	}
	
	col.rgb = mix(col.rgb, _ground_color.rgb * scatter, saturate((-worldPos.y - _atm_level_params.z) * 100.0));
	col.rgb = tonemapPhoto(col.rgb, _color_correction_params.y, _color_correction_params.x);
	col.rgb *= _reflected_energy;
	return col;
}


void sky() {
	vec3 col = vec3(0.0); // Set up the initial sky color which will be added to later to produce the final result.
	vec3 worldPos = EYEDIR; // Original shader set this up in the vertex() function. For sky shaders the overall equivalent is EYEDIR.
	vec3 cloudsPos = EYEDIR; // The same is used for cloud rendering.
	vec3 sunPosition = LIGHT0_DIRECTION; // Redefined from now-deprecated _sun_direction.
	vec3 moonPosition = LIGHT1_DIRECTION; // Redefined from now-deprecated _moon_direction.
	vec3 deep_space_coords = (_deep_space_matrix * EYEDIR).xyz;
	
	if (_sky_visible) {
		col = render_sky(worldPos, cloudsPos, sunPosition, moonPosition, deep_space_coords);
	}
	
	COLOR = col.rgb;
}