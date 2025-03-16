// Copyright (c) 2023-2025 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar

shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec2 _color_correction_params;

uniform float _fog_density = .0001;
uniform float _fog_rayleigh_depth = .115;
uniform float _fog_mie_depth = 0.;
uniform float _fog_falloff = 3.;
uniform float _fog_start = 0.;
uniform float _fog_end = 1000.;
uniform vec3 _sun_direction = vec3(.25, -.25, .25);
uniform vec3 _moon_direction = vec3(.45, -.25, .45);

uniform float _atm_darkness = .5;
uniform float _atm_sun_intensity = 30.;
uniform vec4 _atm_day_tint: source_color = vec4(.78, .85, .98, 1.);
uniform vec4 _atm_horizon_light_tint: source_color = vec4(.98, .73, .49, 1.);
uniform vec4 _atm_night_tint: source_color = vec4(.16, .2, .25, 1.);
uniform vec3 _atm_level_params = vec3(1., 0., 0.);
uniform float _atm_thickness = .7;

uniform vec3 _atm_beta_ray;
uniform vec3 _atm_beta_mie;

uniform vec3 _atm_sun_partial_mie_phase;
uniform vec4 _atm_sun_mie_tint: source_color = vec4(1.);
uniform float _atm_sun_mie_intensity = 1.;

uniform vec3 _atm_moon_partial_mie_phase;
uniform vec4 _atm_moon_mie_tint: source_color = vec4(.13, .18, .29, 1.);
uniform float _atm_moon_mie_intensity = .7;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// Inc
//------------------------------------------------------------------------------
const float kPI          = 3.1415927f;
const float kINV_PI      = 0.3183098f;
const float kHALF_PI     = 1.5707963f;
const float kINV_HALF_PI = 0.6366198f;
const float kQRT_PI      = 0.7853982f;
const float kINV_QRT_PI  = 1.2732395f;
const float kPI4         = 12.5663706f;
const float kINV_PI4     = 0.0795775f;
const float k3PI16       = 0.1193662f;
const float kTAU         = 6.2831853f;
const float kINV_TAU     = 0.1591549f;
const float kE           = 2.7182818f;

float saturate(float value){
	return clamp(value, 0.0, 1.0);
}

vec3 saturateRGB(vec3 value){
	return clamp(value.rgb, 0.0, 1.0);
}

// pow3
vec3 contrastLevel(vec3 vec, float level){
	return mix(vec, vec * vec * vec, level);
}

vec3 tonemapPhoto(vec3 color, float exposure, float level){
	color.rgb *= exposure;
	return mix(color.rgb, 1.0 - exp(-color.rgb), level);
}

vec2 equirectUV(vec3 norm){
	vec2 ret;
	ret.x = (atan(norm.x, norm.z) + kPI) * kINV_TAU;
	ret.y = acos(norm.y) * kINV_PI;
	return ret;
}

// Atmosphere Inc
//------------------------------------------------------------------------------
const float RAYLEIGH_ZENITH_LENGTH = 8.4e3;
const float MIE_ZENITH_LENGTH = 1.25e3;

float rayleighPhase(float mu){
	return k3PI16 * (1.0 + mu * mu);
}

float miePhase(float mu, vec3 partial){
	return kPI4 * (partial.x) * (pow(partial.y - partial.z * mu, -1.5));
}

// Simplifield for more performance
void simpleOpticalDepth(float y, out float sr, out float sm){
	y = max(0.03, y + 0.03) + _atm_level_params.y;
	y = 1.0 / (y * _atm_level_params.x);
	sr = y * RAYLEIGH_ZENITH_LENGTH;
	sm = y * MIE_ZENITH_LENGTH;
}

// Paper based
void opticalDepth(float y, out float sr, out float sm){
	y = max(0.0, y);
	y = saturate(y * _atm_level_params.x);

	float zenith = acos(y);
	zenith = cos(zenith) + 0.15 * pow(93.885 - ((zenith * 180.0) / kPI), -1.253);
	zenith = 1.0 / (zenith + _atm_level_params.y);

	sr = zenith * RAYLEIGH_ZENITH_LENGTH;
	sm = zenith * MIE_ZENITH_LENGTH;
}

vec3 atmosphericScattering(float sr, float sm, vec2 mu, vec3 mult, float depth){
	vec3 betaMie = _atm_beta_mie;
	vec3 betaRay = _atm_beta_ray * _atm_thickness;

	vec3 extcFactor = saturateRGB(exp(-(betaRay * sr + betaMie * sm)));

	float extcFF = mix(saturate(_atm_thickness * 0.5), 1.0, mult.x);
	vec3 finalExtcFactor = mix(1.0 - extcFactor, (1.0 - extcFactor) * extcFactor, extcFF);

	float rayleighPhase = rayleighPhase(mu.x);
	vec3 BRT = betaRay * rayleighPhase * saturate(depth * _fog_rayleigh_depth);
	vec3 BMT = betaMie * miePhase(mu.x, _atm_sun_partial_mie_phase);
	BMT *= _atm_sun_mie_intensity * _atm_sun_mie_tint.rgb * saturate(depth * _fog_mie_depth);

	vec3 BRMT = (BRT + BMT) / (betaRay + betaMie);
	vec3 scatter = _atm_sun_intensity * (BRMT * finalExtcFactor) * _atm_day_tint.rgb * mult.y;
	scatter = mix(scatter, scatter * (1.0 - extcFactor), _atm_darkness);

	vec3 lcol = mix(_atm_day_tint.rgb, _atm_horizon_light_tint.rgb, mult.x);
	vec3 nscatter = (1.0 - extcFactor) * _atm_night_tint.rgb * saturate(depth * _fog_rayleigh_depth);
	nscatter += miePhase(mu.y, _atm_moon_partial_mie_phase) *
		_atm_moon_mie_tint.rgb * _atm_moon_mie_intensity * 0.005 * saturate(depth * _fog_mie_depth);

	return (scatter * lcol) + nscatter;
}

// Fog
//------------------------------------------------------------------------------
float fogExp(float depth, float density){
	return 1.0 - saturate(exp2(-depth * density));
}

float fogFalloff(float y, float zeroLevel, float falloff){
	return saturate(exp(-(y + zeroLevel) * falloff));
}

float fogDistance(float depth){
	float d = depth;
	d = (_fog_end - d) / (_fog_end - _fog_start);
	return saturate(1.0 - d);
}

void computeCoords(vec2 uv, float depth, mat4 camMat, mat4 invProjMat,
	out vec3 viewDir, out vec3 worldPos){

	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);

	// ViewDir
	vec4 view = invProjMat * vec4(ndc, 1.0);
	viewDir = view.xyz / view.w;

	// worldPos
	view = camMat * view;
	view.xyz /= view.w;
	view.xyz -= (camMat * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	worldPos = view.xyz;
}

// Varyings
//------------------------------------------------------------------------------
varying mat4 camera_matrix;
varying vec4 angle_mult;
varying flat int angle;

void vertex(){
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	angle = 0; //ignore; without this the line below errors in 4.3-stable
	angle_mult.x = saturate(1.0 - _sun_direction.y);
	angle_mult.y = saturate(_sun_direction.y + 0.45);
	angle_mult.z = saturate(-_sun_direction.y + 0.30);
	angle_mult.w = saturate(-_sun_direction.y + 0.60);
	camera_matrix = INV_VIEW_MATRIX;
}

void fragment(){
	float depthRaw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    #ifndef CURRENT_RENDERER
    // For 4.3 or earlier, will break if far plane is less than 1m.
    depthRaw = PROJECTION_MATRIX[3][2] > PROJECTION_MATRIX[2][2] ? depthRaw : depthRaw * 2.0 - 1.0;
    #else
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    depthRaw = depthRaw * 2.0 - 1.0;
    #endif
    #endif
	
	vec3 view; vec3 worldPos;
	computeCoords(SCREEN_UV, depthRaw, camera_matrix, INV_PROJECTION_MATRIX, view, worldPos);
	worldPos = normalize(worldPos);

	float linearDepth = -view.z;
	float fogFactor = fogExp(linearDepth, _fog_density);
	fogFactor *= fogFalloff(worldPos.y, 0.0, _fog_falloff);
	fogFactor *= fogDistance(linearDepth);

	vec2 mu = vec2(dot(_sun_direction, worldPos), dot(_moon_direction, worldPos));
	float sr; float sm; simpleOpticalDepth(worldPos.y + _atm_level_params.z, sr, sm);
	vec3 scatter = atmosphericScattering(sr, sm, mu.xy, angle_mult.xyz, linearDepth);

	vec3 tint =  scatter;
	vec4 fogColor = vec4(tint.rgb, fogFactor);
	fogColor = vec4((fogColor.rgb), saturate(fogColor.a));
	fogColor.rgb = tonemapPhoto(fogColor.rgb, _color_correction_params.y, _color_correction_params.x);

	ALBEDO = fogColor.rgb;
	ALPHA = fogColor.a;
	//ALPHA = (depthRaw) < 0.999999999999 ? fogColor.a: 0.0; // Exclude sky.
}