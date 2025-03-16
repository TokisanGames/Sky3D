// Copyright (c) 2023-2025 Cory Petkovsek and Contributors
// Copyright (c) 2021 J. Cuellar
// This shader is based on DanilS clouds shader with MIT License
// See https://github.com/danilw/godot-utils-and-other/tree/master/Dynamic%20sky%20and%20reflection

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front, skip_vertex_transform;

uniform vec3 _sun_direction;
uniform vec3 _moon_direction;
uniform float _clouds_coverage;
uniform float _clouds_thickness;
uniform float _clouds_absorption;
uniform float _clouds_noise_freq;
uniform float _clouds_sky_tint_fade;
uniform float _clouds_intensity;
uniform float _clouds_size;
uniform float _clouds_speed;
uniform vec3 _clouds_direction;
uniform sampler2D _clouds_texture;

uniform vec4 _clouds_day_color: source_color;
uniform vec4 _clouds_horizon_light_color: source_color;
uniform vec4 _clouds_night_color: source_color;

const int kCLOUDS_STEP = 10;

uniform vec3 _clouds_partial_mie_phase;
uniform float _clouds_mie_intensity;
uniform vec4 _atm_sun_mie_tint;
uniform vec4 _atm_moon_mie_tint: source_color;

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

float pow3(float real){
	return real * real * real;
}

float noiseClouds(vec3 p){
	vec3 pos = vec3(p * 0.01);
	pos.z *= 256.0;
	vec2 offset = vec2(0.317, 0.123);
	vec4 uv= vec4(0.0);
	uv.xy = pos.xy + offset * floor(pos.z);
	uv.zw = uv.xy + offset;
	float x1 = textureLod(_clouds_texture, uv.xy, 0.0).r;
	float x2 = textureLod(_clouds_texture, uv.zw, 0.0).r;
	return mix(x1, x2, fract(pos.z));
}

float cloudsFBM(vec3 p, float l){
	float ret;
	ret = 0.51749673 * noiseClouds(p);  
	p *= l;
	ret += 0.25584929 * noiseClouds(p); 
	p *= l; 
	ret += 0.12527603 * noiseClouds(p); 
	p *= l;
	ret += 0.06255931 * noiseClouds(p);
	return ret;
}

float noiseCloudsFBM(vec3 p, float freq){
	return cloudsFBM(p, freq);
}

float remap(float value, float fromMin, float fromMax, float toMin, float toMax){
	return toMin + (value - fromMin) * (toMax - toMin) / (fromMax - fromMin);
}

float cloudsDensity(vec3 p, vec3 offset, float t){
	vec3 pos = p * 0.0212242 - offset;
	float dens = noiseCloudsFBM(pos, _clouds_noise_freq);
	dens += dens;
	
	float cov = 1.0-_clouds_coverage;
	cov = smoothstep(0.00, (cov * 3.5) + t, dens);
	dens *= cov;
	dens = remap(dens, 1.0-cov, 1.0, 0.0, 1.0); 
	
	return saturate(dens);
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

float miePhase(float mu, vec3 partial){
	return kPI4 * (partial.x) * (pow(partial.y - partial.z * mu, -1.5));
}

vec4 renderClouds2(vec3 ro, vec3 rd, float tm, float am){
	vec4 ret = vec4(0, 0, 0, 0);
	vec3 wind = _clouds_direction * (tm * _clouds_speed);
	float a = 0.0;
	
	// n and tt doesnt need to be initialized since it would be set by IntersectSphere
	vec3 n; float tt;
    if(IntersectSphere(500, ro, rd, tt, n))
	{
		float marchStep = float(kCLOUDS_STEP) * _clouds_thickness;
		vec3 dirStep = rd / rd.y * marchStep;
		vec3 pos = n * _clouds_size;
		
		vec2 mu = vec2(dot(_sun_direction, rd), dot(_moon_direction, rd));
		vec3 mph = ((miePhase(mu.x, _clouds_partial_mie_phase) * _atm_sun_mie_tint.rgb) +
		miePhase(mu.y, _clouds_partial_mie_phase) * am);
		
		vec4 t = vec4(1.0);
		t.rgb += (mph.rgb * _clouds_mie_intensity);
		
		for(int i = 0; i < kCLOUDS_STEP; i++)
		{
			float h = float(i) * 0.1; // / float(kCLOUDS_STEP);
			
			float density = cloudsDensity(pos, wind, h);
			float sh = saturate(exp(-_clouds_absorption * density * marchStep));
			t *= sh;
			ret += (t * (exp(h) * 0.571428571) * density * marchStep);
			a += (1.0 - sh) * (1.0 - a);
			pos += dirStep;
		}
		return vec4(ret.rgb * _clouds_intensity, a);
	}
	return vec4(ret.rgb * _clouds_intensity, a);
}


varying vec4 world_pos;
varying vec4 moon_coords;
varying vec3 deep_space_coords;
varying vec4 angle_mult;

void vertex(){
	vec4 vert = vec4(VERTEX, 0.0);
    POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vert;
    POSITION.z = 0.0000001;
	
	world_pos = (MODEL_MATRIX * vert);
	angle_mult.x = saturate(1.0 - _sun_direction.y);
	angle_mult.y = saturate(_sun_direction.y + 0.45);
	angle_mult.z = saturate(-_sun_direction.y + 0.30);
	angle_mult.w = saturate(-_sun_direction.y + 0.60);
}

void fragment(){
	vec3 ray = normalize(world_pos).xyz;
	float horizonBlend = saturate((ray.y+0.01) * 50.0);
	
	vec4 clouds = renderClouds2(vec3(0.0, 0.0, 0.0), ray, TIME, angle_mult.z);
	clouds.a = saturate(clouds.a);
	clouds.rgb *= mix(mix(_clouds_day_color.rgb, _clouds_horizon_light_color.rgb, angle_mult.x), 
		_clouds_night_color.rgb, angle_mult.w);
	clouds.a = mix(0.0, clouds.a, horizonBlend);
	
	ALBEDO = clouds.rgb;
	ALPHA = pow3(clouds.a);
	DEPTH = 0.0;
}
