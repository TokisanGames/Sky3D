# Copyright (c) 2023-2025 Cory Petkovsek and Contributors
# Copyright (c) 2021 J. Cuellar

## SkyDome is a component of [Sky3D].
##
## This class renders the sky shader, including the stars, clouds, sun and moon. See [Sky3D].

@tool
class_name SkyDome
extends Node

signal day_night_changed(value)

const FOG_SHADER: String = "res://addons/sky_3d/shaders/AtmFog.gdshader"
const MOON_TEXTURE: Texture2D = preload("res://addons/sky_3d/assets/thirdparty/textures/moon/MoonMap.png")
const STARMAP_TEXTURE: Texture2D = preload("res://addons/sky_3d/assets/thirdparty/textures/milkyway/Milkyway.jpg")
const STARFIELD_TEXTURE: Texture2D = preload("res://addons/sky_3d/assets/thirdparty/textures/milkyway/StarField.jpg")
const STARFIELD_NOISE: Texture2D = preload("res://addons/sky_3d/assets/textures/noise.jpg")
const CIRRUS_TEXTURE: Texture2D = preload("res://addons/sky_3d/assets/resources/SNoise.tres")
const CUMULUS_TEXTURE: Texture2D = preload("res://addons/sky_3d/assets/textures/noiseClouds.png")
const SUN_MOON_CURVE: Curve = preload("res://addons/sky_3d/assets/resources/SunMoonLightFade.tres")
const DAY_NIGHT_TRANSITION_ANGLE: float = deg_to_rad(90)  # Horizon

var is_scene_built: bool = false
var fog_mesh: MeshInstance3D
var sky_material: ShaderMaterial
var cumulus_material: Material
var fog_material: Material


#####################
## Setup 
#####################


var environment: Environment:
	set(value):
		environment = value
		_update_ambient_color()


func _update_ambient_color() -> void:
	if not environment or not _sun_light_node:
		return
	var factor: float = clampf(-_sun_transform.origin.y + 0.60, 0., 1.)
	var col: Color = _sun_light_node.light_color.lerp(atm_night_tint * _atm_night_intensity(), factor)
	col.a = 1.
	col.v = clamp(col.v, .35, 1.)
	environment.ambient_light_color = col


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_build_scene()
	_check_cloud_processing()


func _build_scene() -> void:
	if is_scene_built or not environment:
		return

	# Sky Material
	# Necessary for now until we can pull everything off the SkyDome node.
	sky_material = environment.sky.sky_material
	sky_material.set_shader_parameter("noise_tex", STARFIELD_NOISE)
	
	# Set cumulus cloud global to point to the sky material.
	# Necessary for now until we can pull everything off the SkyDome node.
	cumulus_material = sky_material
	
	fog_mesh = MeshInstance3D.new()
	fog_mesh.name = "_FogMeshI"
	var fog_screen_quad = QuadMesh.new()
	var size: Vector2
	size.x = 2.0
	size.y = 2.0
	fog_screen_quad.size = size
	fog_mesh.mesh = fog_screen_quad
	fog_material = ShaderMaterial.new()
	fog_material.shader = load(FOG_SHADER)
	fog_material.render_priority = fog_render_priority
	fog_mesh.material_override = fog_material
	fog_mesh.transform.origin = Vector3.ZERO
	fog_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog_mesh.custom_aabb = AABB(Vector3(-1e31, -1e31, -1e31), Vector3(2e31, 2e31, 2e31))
	add_child(fog_mesh)
	is_scene_built = true

	# Trigger all inline setters for exported variables
	var script: GDScript = get_script()
	for prop in script.get_script_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_EDITOR:
			var prop_name: String = prop.name
			set(prop_name, get(prop_name))  # Triggers setter with current value


#####################
## Processing 
#####################


func _physics_process(delta: float) -> void:
	process_tick(delta)


func _process(delta: float) -> void:
	process_tick(delta)


## If [method process_method] is set to manual, this function can be called with the number of 
## seconds passed to update the position of the clouds.
func process_tick(delta: float) -> void:
	if not (cirrus_visible or cumulus_visible):
		return
	var position_delta: Vector2 = _cloud_velocity * delta
	if cumulus_visible:
		_cumulus_position += position_delta
		sky_material.set_shader_parameter("cumulus_position", _cumulus_position)
	if cirrus_visible:
		position_delta *= cirrus_speed_reduction
		_cirrus_position1 = (_cirrus_position1 + position_delta).posmod(1.0)
		_cirrus_position2 = (_cirrus_position2 + position_delta).posmod(1.0)
		sky_material.set_shader_parameter("cirrus_position1", _cirrus_position1)
		sky_material.set_shader_parameter("cirrus_position2", _cirrus_position2)


#####################
## General 
#####################

@export_group("Sky")


## Controls the amount of tone mapping applied to bright areas of the sky. Higher values compress bright regions and increase contrast.
@export_range(0.0, 1.0, 0.001) var tonemap_level: float = 0.0 :
	set(value):
		tonemap_level = value
		_update_color_correction()


## Higher values make the sky brighter.
@export var exposure: float = 1.0 :
	set(value):
		exposure = value
		_update_color_correction()


## The color displayed below the horizon.
@export var ground_color := Color(0.3, 0.3, 0.3, 1.0) :
	set(value):
		ground_color = value
		if is_scene_built:
			sky_material.set_shader_parameter("ground_color", ground_color)


## Vertically shifts the horizon line up or down.
@export var horizon_offset: float = 0.0 :
	set(value):
		horizon_offset = value
		if is_scene_built:
			sky_material.set_shader_parameter("horizon_offset", horizon_offset)


func _update_color_correction() -> void:
	if is_scene_built:
		var correction_params := Vector2(tonemap_level, exposure)
		sky_material.set_shader_parameter("color_correction", correction_params)
		fog_material.set_shader_parameter("color_correction", correction_params)


#####################
## Sun
#####################

@export_group("Sun")


## Size of the sun disk.
@export_range(0.0, 0.5, 0.001) var sun_disk_size: float = 0.02 :
	set(value):
		sun_disk_size = value
		if is_scene_built:
			sky_material.set_shader_parameter("sun_disk_size", sun_disk_size)


## Controls the horizontal direction of the sun in degrees. 0° is north, 90° is east, 180° is south, -90° is west.
@export_range(-180.0, 180.0, 0.00001, "radians_as_degrees") var sun_azimuth: float = deg_to_rad(0.) :
	set(value):
		sun_azimuth = value
		_update_sun_coords()


## Controls the vertical angle of the sun in degrees. 0° is zenith (straight up), 90° is horizon, 180° is nadir (straight down).
@export_range(-180.0, 180.0, 0.00001, "radians_as_degrees") var sun_altitude: float = deg_to_rad(-27.387) :
	set(value):
		sun_altitude = value
		_update_sun_coords()


## The color of the sun disk when visible in the sky.
@export var sun_disk_color := Color(0.996094, 0.541334, 0.140076) :
	set(value):
		sun_disk_color = value
		if is_scene_built:
			sky_material.set_shader_parameter("sun_disk_color", sun_disk_color)


## Higher values make the sun brighter.
@export_range(0.0, 100.0) var sun_disk_intensity: float = 30.0 :
	set(value):
		sun_disk_intensity = value
		if is_scene_built:
			sky_material.set_shader_parameter("sun_disk_intensity", sun_disk_intensity)


var _day: bool = true
var _sun_transform: Transform3D

var sun_light_enabled: bool = true :
	set(value):
		sun_light_enabled = value
		if value:
			_update_sun_coords()
		else:
			_sun_light_node.light_energy = 0.0
			_sun_light_node.shadow_enabled = false


## The day-night state
func is_day() -> bool:
	return _day


## Signals when day has changed to night and vice versa.
func _set_day_state(v: float, threshold: float = DAY_NIGHT_TRANSITION_ANGLE) -> void:
	if _day == true and abs(v) > threshold:
		_day = false
		emit_signal("day_night_changed", _day)
	elif _day == false and abs(v) <= threshold:
		_day = true
		emit_signal("day_night_changed", _day)


## Updates sun position and lighting calculations
func _update_sun_coords() -> void:
	if !is_scene_built:
		return
	
	if _sun_light_node:
		_sun_light_node.visible = true
	
	# Position the sun on a unit sphere, orienting the light to the origin, mimicking a star orbiting a planet.
	_sun_transform.origin = TOD_Math.spherical_to_cartesian(sun_altitude, sun_azimuth)
	_sun_transform = _sun_transform.looking_at(Vector3.ZERO, Vector3.LEFT)
	
	fog_material.set_shader_parameter("sun_direction", _sun_transform.origin)
	if _sun_light_node:
		_sun_light_node.transform = _sun_transform
	
	_set_day_state(sun_altitude)
	_update_night_intensity()
	_update_sun_light_color()
	_update_sun_light_energy()
	_update_moon_light_energy()
	_update_ambient_color()


#####################
## SunLight
#####################

# Original sun light (0.984314, 0.843137, 0.788235)
# Original sun horizon (1.0, 0.384314, 0.243137, 1.0)

var _sun_light_node: DirectionalLight3D


## Color of the sun DirectionalLight3D during midday
@export var sun_light_color := Color.WHITE :
	set(value):
		sun_light_color = value
		_update_sun_light_color()


## Color of the sun DirectionalLight3D during sunrise and sunset
@export var sun_horizon_light_color := Color(.98, 0.523, 0.294, 1.0) :
	set(value):
		sun_horizon_light_color = value
		_update_sun_light_color()


## Maximum light energy of the sun DirectionalLight3D
@export var sun_light_energy: float = 1.0 :
	set(value):
		sun_light_energy = value
		_update_sun_light_energy()


## NodePath to the sun DirectionalLight3D node
@export_node_path("DirectionalLight3D") var sun_light_path := NodePath("../SunLight") :
	set(value):
		sun_light_path = value
		if sun_light_path:
			_sun_light_node = get_node_or_null(sun_light_path) as DirectionalLight3D
		_update_sun_coords()


func _update_sun_light_color() -> void:
	if not _sun_light_node:
		return
	var sun_light_altitude_mult: float = clampf(_sun_transform.origin.y * 2.0, 0., 1.)
	_sun_light_node.light_color = sun_horizon_light_color.lerp(sun_light_color, sun_light_altitude_mult)


func _update_sun_light_energy() -> void:
	if not _sun_light_node or not sun_light_enabled:
		return
	
	# Light energy should depend on how much of the sun disk is visible.
	var y: float = _sun_transform.origin.y
	var sun_light_factor: float = clampf((y + sun_disk_size) / (2.0 * sun_disk_size), 0., 1.);
	_sun_light_node.light_energy = lerpf(0.0, sun_light_energy, sun_light_factor)
	
	if is_equal_approx(_sun_light_node.light_energy, 0.0) and _sun_light_node.shadow_enabled:
		_sun_light_node.shadow_enabled = false
	elif _sun_light_node.light_energy > 0.0 and not _sun_light_node.shadow_enabled:
		_sun_light_node.shadow_enabled = true


#####################
## Moon
#####################

@export_group("Moon")


## Horizontal angle of the moon
@export_range(-180.0, 180.0, 0.00001, "radians_as_degrees") var moon_azimuth: float = deg_to_rad(5.) :
	set(value):
		moon_azimuth = value
		update_moon_coords()


## Vertical angle of the moon
@export_range(-180.0, 180.0, 0.00001, "radians_as_degrees") var moon_altitude: float = deg_to_rad(-80.) :
	set(value):
		moon_altitude = value
		update_moon_coords()


## Color tint applied to the moon surface texture.
@export var moon_color := Color.WHITE :
	set(value):
		moon_color = value
		if is_scene_built:
			sky_material.set_shader_parameter("moon_color", moon_color)


## Larger values create a bigger moon.
@export_range(0., .999) var moon_size: float = 0.07 :
	set(value):
		moon_size = value
		if is_scene_built:
			sky_material.set_shader_parameter("moon_size", moon_size)


## The moon's surface texture
@export var moon_texture: Texture2D = MOON_TEXTURE :
	set(value):
		moon_texture = value
		_update_moon_texture()


## XYZ rotation angles for orienting the moon surface features
@export_custom(PROPERTY_HINT_RANGE, "-180,180,0.1,radians_as_degrees") var moon_texture_alignment := Vector3(7.0, 1.4, 4.8) :
	set(value):
		moon_texture_alignment = value
		_update_moon_texture()


## Horizontally flips the moon texture
@export var flip_moon_texture_u: bool = false :
	set(value):
		flip_moon_texture_u = value
		_update_moon_texture()


## Vertically flips the moon texture
@export var flip_moon_texture_v: bool = false :
	set(value):
		flip_moon_texture_v = value
		_update_moon_texture()


## The moon's Transform3D
var _moon_transform: Transform3D
## We disable the moon DirectionalLight3D by setting [member DirectionalLight3D.shadow_enabled] 
## and [member DirectionalLight3D.light_energy] to false and zero respectively
var moon_light_enabled: bool = true:
	set(value):
		moon_light_enabled = value
		if value:
			update_moon_coords()
		else:
			_moon_light_node.light_energy = 0.0
			_moon_light_node.shadow_enabled = false


## Updates moon position and lighting calculations
func update_moon_coords() -> void:
	if !is_scene_built:
		return
	
	if _moon_light_node:
		_moon_light_node.visible = true
	
	_moon_transform.origin = TOD_Math.spherical_to_cartesian(moon_altitude, moon_azimuth)
	_moon_transform = _moon_transform.looking_at(Vector3.ZERO, Vector3.LEFT)
	
	var moon_basis: Basis = get_parent().moon.get_global_transform().basis.inverse()
	sky_material.set_shader_parameter("moon_matrix", moon_basis)
	fog_material.set_shader_parameter("moon_direction", _moon_transform.origin)
	if _moon_light_node:
		_moon_light_node.transform = _moon_transform
	
	_moon_light_altitude_mult = clampf(_moon_transform.origin.y, 0.0, 1.0)
	
	_update_night_intensity()
	_update_moon_light_color()
	_update_moon_light_energy()
	_update_ambient_color()


## Applies moon texture and alignment to shader
func _update_moon_texture() -> void:
	if is_scene_built:
		sky_material.set_shader_parameter("moon_texture", moon_texture)
		sky_material.set_shader_parameter("moon_texture_alignment", moon_texture_alignment)
		sky_material.set_shader_parameter("moon_texture_flip_u", flip_moon_texture_u)
		sky_material.set_shader_parameter("moon_texture_flip_v", flip_moon_texture_v)


#####################
## MoonLight
#####################


## Color of the moon DirectionalLight3D
@export var moon_light_color := Color(0.572549, 0.776471, 0.956863, 1.0) :
	set(value):
		moon_light_color = value
		_update_moon_light_color()


## Maximum light energy of the moon DirectionalLight3D
@export var moon_light_energy: float = 0.3 :
	set(value):
		moon_light_energy = value
		_update_moon_light_energy()


## Reference to the moon DirectionalLight3D
var _moon_light_node: DirectionalLight3D
## Used to fade moon light energy from zero at horizon to maximum at zenith. 
## This value is clamped in the range [0..1].
var _moon_light_altitude_mult: float = 0.0


func _update_moon_light_color() -> void:
	if not _moon_light_node:
		return
	_moon_light_node.light_color = moon_light_color


func _update_moon_light_energy() -> void:
	if not _moon_light_node or not moon_light_enabled:
		return
	
	var l: float = lerpf(0.0, moon_light_energy, _moon_light_altitude_mult)
	l *= _atm_moon_phases_mult()
	
	var fade: float = (1.0 - _sun_transform.origin.y) * 0.5
	_moon_light_node.light_energy = l * SUN_MOON_CURVE.sample_baked(fade)
	
	if is_equal_approx(_moon_light_node.light_energy, 0.0) and _moon_light_node.shadow_enabled:
		_moon_light_node.shadow_enabled = false
	elif _moon_light_node.light_energy > 0.0 and not _moon_light_node.shadow_enabled:
		_moon_light_node.shadow_enabled = true


## NodePath to the moon DirectionalLight3D node
@export_node_path("DirectionalLight3D") var moon_light_path := NodePath("../MoonLight") :
	set(value):
		moon_light_path = value
		if moon_light_path:
			_moon_light_node = get_node_or_null(moon_light_path) as DirectionalLight3D
		update_moon_coords()


#####################
## Atmosphere
#####################

@export_group("Atmosphere")


## Affects the overall color of the sky and fog.
@export var atm_wavelengths := Vector3(680.0, 550.0, 440.0) :
	set(value):
		atm_wavelengths = value
		if is_scene_built:
			var wll: Vector3 = ScatterLib.compute_wavelenghts_lambda(atm_wavelengths)
			var wls: Vector3 = ScatterLib.compute_wavelenghts(wll)
			var betaRay: Vector3 = ScatterLib.compute_beta_ray(wls)
			sky_material.set_shader_parameter("atm_beta_ray", betaRay)
			fog_material.set_shader_parameter("atm_beta_ray", betaRay)


## Higher values darken the atmosphere.
@export_range(0.0, 1.0, 0.01) var atm_darkness: float = 0.5 :
	set(value):
		atm_darkness = value
		if is_scene_built:
			sky_material.set_shader_parameter("atm_darkness", atm_darkness)
			fog_material.set_shader_parameter("atm_darkness", atm_darkness)


## Higher values increase the sun's contribution to the atmosphere.
@export var atm_sun_intensity: float = 18.0 :
	set(value):
		atm_sun_intensity = value
		if is_scene_built:
			sky_material.set_shader_parameter("atm_sun_intensity", atm_sun_intensity)
			fog_material.set_shader_parameter("atm_sun_intensity", atm_sun_intensity)


## Color tint applied to the daytime sky atmosphere.
@export var atm_day_tint := Color(0.807843, 0.909804, 1.0) :
	set(value):
		atm_day_tint = value
		if is_scene_built:
			sky_material.set_shader_parameter("atm_day_tint", atm_day_tint)
			fog_material.set_shader_parameter("atm_day_tint", atm_day_tint)


## Color tint applied to atmosphere during sunrise and sunset.
@export var atm_horizon_light_tint := Color(0.980392, 0.635294, 0.462745, 1.0) :
	set(value):
		atm_horizon_light_tint = value
		if is_scene_built:
			sky_material.set_shader_parameter("atm_horizon_light_tint", atm_horizon_light_tint)
			fog_material.set_shader_parameter("atm_horizon_light_tint", atm_horizon_light_tint)


## Use moon phase angle for night-time Mie scattering intensity instead of the sun position.
## Enabling this will prevent the moon from scattering light into the fog and sky atmosphere.
@export var atm_enable_moon_scatter_mode: bool = false :
	set(value):
		atm_enable_moon_scatter_mode = value
		_update_night_intensity()


## Color tint applied to the nighttime atmosphere
@export var atm_night_tint := Color(0.168627, 0.2, 0.25098, 1.0) :
	set(value):
		atm_night_tint = value
		_update_night_intensity()


## Higher values create stronger atmospheric effects.
@export_range(0.0, 100.0, 0.01) var atm_thickness: float = 0.7 :
	set(value):
		atm_thickness = value
		if is_scene_built:
			sky_material.set_shader_parameter("atm_thickness", atm_thickness)
			fog_material.set_shader_parameter("atm_thickness", atm_thickness)


## Sets the Mie scattering: the haze and white light diffusion around the sun.
@export var atm_mie: float = 0.07 :
	set(value):
		atm_mie = value
		_update_beta_mie()


## Sets the multiplier for [member atm_mie].
@export var atm_turbidity: float = 0.001 :
	set(value):
		atm_turbidity = value
		_update_beta_mie()


## Color tint of the Mie scattering around the sun.
@export var atm_sun_mie_tint := Color(1.0, 1.0, 1.0, 1.0) :
	set(value):
		atm_sun_mie_tint = value
		if is_scene_built:
			sky_material.set_shader_parameter("atm_sun_mie_tint", atm_sun_mie_tint)
			fog_material.set_shader_parameter("atm_sun_mie_tint", atm_sun_mie_tint)


## Sets the intensity of the Mie scattering around the sun.
@export var atm_sun_mie_intensity: float = 1.0 :
	set(value):
		atm_sun_mie_intensity = value
		if is_scene_built:
			sky_material.set_shader_parameter("atm_sun_mie_intensity", atm_sun_mie_intensity)
			fog_material.set_shader_parameter("atm_sun_mie_intensity", atm_sun_mie_intensity)


## Controls the directional bias (shape) of the Mie scattering around the sun.
@export_range(0.0, 0.9999999, 0.0000001) var atm_sun_mie_anisotropy: float = 0.8 :
	set(value):
		atm_sun_mie_anisotropy = value
		if is_scene_built:
			var partial: Vector3 = ScatterLib.get_partial_mie_phase(atm_sun_mie_anisotropy)
			sky_material.set_shader_parameter("atm_sun_partial_mie_phase", partial)
			fog_material.set_shader_parameter("atm_sun_partial_mie_phase", partial)


## Color tint for Mie scattering around the moon.
@export var atm_moon_mie_tint := Color(0.137255, 0.184314, 0.292196) :
	set(value):
		atm_moon_mie_tint = value
		if is_scene_built:
			sky_material.set_shader_parameter("atm_moon_mie_tint", atm_moon_mie_tint)
			fog_material.set_shader_parameter("atm_moon_mie_tint", atm_moon_mie_tint)


## Sets the intensity of the Mie scattering around the moon.
@export var atm_moon_mie_intensity: float = 0.7 :
	set(value):
		atm_moon_mie_intensity = value
		if is_scene_built:
			sky_material.set_shader_parameter("atm_moon_mie_intensity", atm_moon_mie_intensity * _atm_moon_phases_mult())
			fog_material.set_shader_parameter("atm_moon_mie_intensity", atm_moon_mie_intensity * _atm_moon_phases_mult())


## Controls the directional bias (shape) of the Mie scattering around the moon.
@export_range(0.0, 0.9999999, 0.0000001) var atm_moon_mie_anisotropy: float = 0.8 : 
	set(value):
		atm_moon_mie_anisotropy = value
		if is_scene_built:
			var partial: Vector3 = ScatterLib.get_partial_mie_phase(atm_moon_mie_anisotropy)
			sky_material.set_shader_parameter("atm_moon_partial_mie_phase", partial)
			fog_material.set_shader_parameter("atm_moon_partial_mie_phase", partial)


## These parameters fine-tune the vertical distribution of atmospheric scattering in the shader.
## X scales the height of Mie scattering layers (haze closer to the ground)
## Y scales Rayleigh scattering layers (bluer sky higher up)
## Z acts as a ground-level offset to adjust where the atmosphere "starts" relative to the horizon.
@export var atm_level_params := Vector3(1.0, 0.0, 0.0) :
	set(value):
		atm_level_params = value
		if is_scene_built:
			sky_material.set_shader_parameter("atm_level_params", atm_level_params)
			fog_material.set_shader_parameter("atm_level_params", atm_level_params + fog_atm_level_params_offset)


func _atm_moon_phases_mult() -> float:
	if not atm_enable_moon_scatter_mode:
		return _atm_night_intensity()
	return clampf(-_sun_transform.origin.dot(_moon_transform.origin) + 0.60, 0., 1.)


func _atm_night_intensity() -> float:
	if not atm_enable_moon_scatter_mode:
		return clampf(-_sun_transform.origin.y + 0.30, 0., 1.)
	return clampf(_moon_transform.origin.y, 0., 1.) * _atm_moon_phases_mult()


func _fog_atm_night_intensity() -> float:
	if not atm_enable_moon_scatter_mode:
		return clampf(-_sun_transform.origin.y + 0.70, 0., 1.)
	return clampf(-_sun_transform.origin.y, 0., 1.) * _atm_moon_phases_mult()


func _update_night_intensity() -> void:
	if is_scene_built:
		sky_material.set_shader_parameter("atm_night_tint", atm_night_tint * _atm_night_intensity())
		fog_material.set_shader_parameter("atm_night_tint", atm_night_tint * _fog_atm_night_intensity())


func _update_beta_mie() -> void:
	if is_scene_built:
		var bm: Vector3 = ScatterLib.compute_beta_mie(atm_mie, atm_turbidity)
		sky_material.set_shader_parameter("atm_beta_mie", bm)
		fog_material.set_shader_parameter("atm_beta_mie", bm)


#####################
## Fog
#####################

@export_group("Fog")


## Set the fog's visibility
@export var fog_visible: bool = true: 
	set(value):
		fog_visible = value
		if is_scene_built:
			fog_mesh.visible = fog_visible


## Applies an exponential decay to fog density along the view ray, softening the transition from clear to foggy areas—lower values create sharp cutoffs for localized mist, higher for gradual blending into the distance.
@export_range(0.0, 50.0, .01, "or_greater") var fog_falloff: float = 3.0 :
	set(value):
		fog_falloff = value
		if is_scene_built:
			fog_material.set_shader_parameter("fog_falloff", fog_falloff)


## Set the fog's density
@export_exp_easing() var fog_density: float = 0.0007 :
	set(value):
		fog_density = value
		if is_scene_built:
			fog_material.set_shader_parameter("fog_density", fog_density)


## Distance from the camera where fog begins to appear.
@export_range(0.0, 5000.0) var fog_start: float = 0.0 :
	set(value):
		fog_start = value
		if is_scene_built:
			fog_material.set_shader_parameter("fog_start", fog_start)


## Distance from the camera where fog reaches maximum thickness.
@export_range(0.0, 5000.0) var fog_end: float = 1000.0 :
	set(value):
		fog_end = value
		if is_scene_built:
			fog_material.set_shader_parameter("fog_end", fog_end)


## Scales the Rayleigh (blue sky) component in fog's optical depth calculation, controlling how much
## scattering accumulates in distant fog.
@export_exp_easing() var fog_rayleigh_depth: float = 0.115 :
	set(value):
		fog_rayleigh_depth = value
		if is_scene_built:
			fog_material.set_shader_parameter("fog_rayleigh_depth", fog_rayleigh_depth)


## Adjusts the Mie (hazy around the sun/moon) depth in the fog.
@export_exp_easing() var fog_mie_depth: float = 0.0001 :
	set(value):
		fog_mie_depth = value
		if is_scene_built:
			fog_material.set_shader_parameter("fog_mie_depth", fog_mie_depth)


## Similar to [member atm_level_params] but for the fog shader.
@export var fog_atm_level_params_offset := Vector3(0.0, 0.0, -1.0) :
	set(value):
		fog_atm_level_params_offset = value
		if is_scene_built:
			fog_material.set_shader_parameter("atm_level_params", atm_level_params + fog_atm_level_params_offset)


## Sets the rendering layers the screen space fog mesh renders on. See [VisualInstance3D.layers].
@export_flags_3d_render var fog_layers: int = 524288 :
	set(value):
		fog_layers = value
		if is_scene_built:
			fog_mesh.layers = fog_layers


## Set the fog's render priority
@export var fog_render_priority: int = 100 :
	set(value):
		fog_render_priority = value
		if is_scene_built:
			fog_material.render_priority = fog_render_priority


#####################
## Clouds
#####################

@export_group("Clouds")


#####################
## Wind
#####################

@export_subgroup("Wind")

var _cloud_speed: float = 0.01
var _cloud_direction := Vector2(0.25, 0.25)
var _cloud_velocity := Vector2.ZERO
var _cirrus_position1 := Vector2.ZERO
var _cirrus_position2 := Vector2.ZERO
var _cumulus_position := Vector2.ZERO

@export_subgroup("Wind")


# Converts the wind speed from m/s to "shader units" to get clouds moving at a "realistic" speed.
# Note that "realistic" is an estimate as there is no such thing as an altitude for these clouds.
const WIND_SPEED_FACTOR: float = 0.01
## Sets the wind speed.
@export_custom(PROPERTY_HINT_RANGE, "0,120,0.1,or_greater,or_less,suffix:m/s") var wind_speed: float = 1.0 :
	set(value):
		_cloud_speed = value * WIND_SPEED_FACTOR
		_check_cloud_processing()
	get:
		return _cloud_speed / WIND_SPEED_FACTOR


# Zero degrees means the wind is coming from the north, but the shader uses the +X axis as zero, so
# we need to convert between the two with this offset.
const WIND_DIRECTION_OFFSET: float = deg_to_rad(-90)
## Sets the wind direction. Zero means the wind is coming from the north, 90 from the east,
## 180 from the south and 270 (or -90) from the west.
@export_custom(PROPERTY_HINT_RANGE, "-180,180,0.1,radians_as_degrees") var wind_direction: float = 0.0 :
	set(value):
		wind_direction = value
		_cloud_direction = Vector2.from_angle(value + WIND_DIRECTION_OFFSET)
		# We set this value here explicitly to prevent it from "wrapping around" at the edges.
		# That would otherwise happen with a non-zero WIND_DIRECTION_OFFSET on either end of the
		# slider (depending on the sign of that offset). We hold on to it here make sure the
		# slider stays at the same edge. See also the 'get' function below.
		_check_cloud_processing()
	get:
		# We fetch the real wind direction by taking the angle from the clouds direction
		# vector and correcting it for the offset again.
		var real_wind_direction = _cloud_direction.angle() - WIND_DIRECTION_OFFSET
		# What we do here is see if the wind direction we've stored in the property, as
		# explained in 'set' above, is approximately equal to the direction we've just
		# retrieved from the sky dome. This will be the case if we were the last to set it
		# but it won't be if someone else directly changed it in the sky dome, so only
		# use the value from the sky dome if it's different.
		return wind_direction if is_zero_approx(wrapf(wind_direction - real_wind_direction, 0, TAU)) else real_wind_direction


## * Set [0, <1] to make the cirrus clouds appear higher than the cummulus clouds via a parallax effect.[br]
## * Set >= 1 to make them appear at the same level or lower.[br]
## * Set negative to make the cirrus clouds move backwards, which is a real phenomenon called wind shear.[br]
## Finally, you can adjust [member cirrus_size] and [member cumulus_size] to adjust the scale of the 
## cloud noise map UVs, which has the effect of changing apparent height and speed. 
@export_range(0.,1.,.01, "or_greater","or_less") var cirrus_speed_reduction: float = 0.2


enum { PHYSICS_PROCESS, PROCESS, MANUAL }
## Sky3D is updated in two parts. The sky, sun, moon, and stars are updated by the
## [member TimeOfDay.update_interval] timer. Cloud movement is updated by this method: your choice of
## _physics_process(), _process(), or by manually calling [method process_tick].
@export_enum("Physics Process", "Process", "Manual") var process_method: int = PHYSICS_PROCESS :
	set(value):
		process_method = value
		_check_cloud_processing()


func _check_cloud_processing() -> void:
	var enable: bool = (cirrus_visible or cumulus_visible) and wind_speed != 0.0
	_cloud_velocity = _cloud_direction * _cloud_speed
	match process_method:
		PHYSICS_PROCESS:
			set_physics_process(enable)
			set_process(!enable)
		PROCESS:
			set_physics_process(!enable)
			set_process(enable)
		MANUAL, _:
			set_physics_process(false)
			set_process(false)


#####################
## Cirrus Clouds
#####################

@export_subgroup("Cirrus")


## Toggles visibility of high-altitude cirrus clouds.
@export var cirrus_visible: bool = true :
	set(value):
		cirrus_visible = value
		if is_scene_built:
			sky_material.set_shader_parameter("cirrus_visible", value)
			_check_cloud_processing()


## Set density for cirrus clouds.
@export var cirrus_thickness: float = 1.7 :
	set(value):
		cirrus_thickness = value
		if is_scene_built:
			sky_material.set_shader_parameter("cirrus_thickness", cirrus_thickness)


## How much of the sky is covered by cirrus clouds.
@export_range(0.0, 1.0, 0.001) var cirrus_coverage: float = 0.5 :
	set(value):
		cirrus_coverage = value
		if is_scene_built:
			sky_material.set_shader_parameter("cirrus_coverage", cirrus_coverage)


## Higher values create more opaque clouds.
@export var cirrus_absorption: float = 2.0 :
	set(value):
		cirrus_absorption = value
		if is_scene_built:
			sky_material.set_shader_parameter("cirrus_absorption", cirrus_absorption)


## Blends the sky's atmospheric color into cirrus clouds.
@export_range(0.0, 1.0, 0.001) var cirrus_sky_tint_fade: float = 0.5 :
	set(value):
		cirrus_sky_tint_fade = value
		if is_scene_built:
			sky_material.set_shader_parameter("cirrus_sky_tint_fade", cirrus_sky_tint_fade)


## Adjusts the brightness of cirrus clouds. If covering the sky, this has a dramatic affect on lighting.
@export var cirrus_intensity: float = 10.0 :
	set(value):
		cirrus_intensity = value
		if is_scene_built:
			sky_material.set_shader_parameter("cirrus_intensity", cirrus_intensity)


## The noise texture used for generating cirrus cloud patterns.
@export var cirrus_texture: Texture2D = CIRRUS_TEXTURE :
	set(value):
		cirrus_texture = value
		if is_scene_built:
			sky_material.set_shader_parameter("cirrus_texture", cirrus_texture)


## Sets the aspect ratio of the cirrus texture used for the clouds.
@export var cirrus_uv := Vector2(0.16, 0.11) :
	set(value):
		cirrus_uv = value
		if is_scene_built:
			sky_material.set_shader_parameter("cirrus_uv", cirrus_uv)


## Adjusts the scale of the noise texture, which indirectly affects the apparent height and 
## speed of the clouds. Use it with [member cirrus_speed_reduction] to refine cirrus speed and height.
@export var cirrus_size: float = 1.0 :
	set(value):
		cirrus_size = value
		if is_scene_built:
			sky_material.set_shader_parameter("cirrus_size", cirrus_size)


#####################
## Cumulus Clouds
#####################

@export_subgroup("Cumulus")


## Toggles visibility of the low-altitude cumulus clouds.
@export var cumulus_visible: bool = true :
	set(value):
		cumulus_visible = value
		if is_scene_built:
			sky_material.set_shader_parameter("cumulus_visible", value)
			_check_cloud_processing()


## The daytime color tint for the cumulus clouds.
@export var cumulus_day_color := Color(0.823529, 0.87451, 1.0, 1.0) :
	set(value):
		cumulus_day_color = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_day_color", cumulus_day_color)
			sky_material.set_shader_parameter("cumulus_day_color", cumulus_day_color)


## The warm color tint for the cumulus clouds during sunrise and sunset.
@export var cumulus_horizon_light_color := Color(.98, 0.43, 0.15, 1.0) :
	set(value):
		cumulus_horizon_light_color = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_horizon_light_color", cumulus_horizon_light_color)
			sky_material.set_shader_parameter("cumulus_horizon_light_color", cumulus_horizon_light_color)


## The nighttime color tint for the cumulus clouds.
@export var cumulus_night_color := Color(0.090196, 0.094118, 0.129412, 1.0) :
	set(value):
		cumulus_night_color = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_night_color", cumulus_night_color)
			sky_material.set_shader_parameter("cumulus_night_color", cumulus_night_color)


## Controls the vertical depth and layering thickness of the cumulus clouds.
@export var cumulus_thickness: float = 0.0243 :
	set(value):
		cumulus_thickness = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_thickness", cumulus_thickness)


## Sets how much of the sky is covered by the cumulus clouds.
@export_range(0.0, 1.0, 0.001) var cumulus_coverage: float = 0.55 :
	set(value):
		cumulus_coverage = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_coverage", cumulus_coverage)


## Adjusts light absorption inside the cumulus clouds, increasing opacity and internal shadows for denser, more realistic volumes.
@export var cumulus_absorption: float = 2.0 :
	set(value):
		cumulus_absorption = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_absorption", cumulus_absorption)


## Changes the frequency of noise in the cumulus cloud generation; higher values create clouds with more detail.
@export_range(0.0, 3.0, 0.001) var cumulus_noise_freq: float = 2.7 :
	set(value):
		cumulus_noise_freq = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_noise_freq", cumulus_noise_freq)


## Adjusts the brightness of cumulus clouds. If covering the sky, this has a dramatic affect on lighting.
@export_range(0, 16, 0.005) var cumulus_intensity: float = 0.6 :
	set(value):
		cumulus_intensity = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_intensity", cumulus_intensity)


## Controls the strength of hazy light scattering around the cumulus clouds from the sun and moon, enhancing glow and diffusion near edges.
@export var cumulus_mie_intensity: float = 1.0 :
	set(value):
		cumulus_mie_intensity = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_mie_intensity", cumulus_mie_intensity)


## Sets the directionality of Mie scattering in cumulus clouds; low values spread light evenly (like fog),
## while high values focus it forward (like sharp haze beams through gaps).
@export_range(0.0, 0.9999999, 0.0000001) var cumulus_mie_anisotropy: float = 0.206 :
	set(value):
		cumulus_mie_anisotropy = value
		if is_scene_built:
			var partial: Vector3 = ScatterLib.get_partial_mie_phase(cumulus_mie_anisotropy)
			cumulus_material.set_shader_parameter("cumulus_partial_mie_phase", partial)


## The noise texture used for generating cumulus cloud patterns.
@export var cumulus_texture: Texture2D = CUMULUS_TEXTURE :
	set(value):
		cumulus_texture = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_texture", cumulus_texture)


## This parameter adjusts the scale of the noise texture, which indirectly affects the apparent height and 
## speed of the clouds.
@export var cumulus_size: float = 0.5 :
	set(value):
		cumulus_size = value
		if is_scene_built:
			cumulus_material.set_shader_parameter("cumulus_size", cumulus_size)


#####################
## Stars
#####################

@export_group("Stars")


## For aligning the star map texture map to known reference points. See [annotation SkyDome.show_alignment_lasers].
@export var starmap_alignment := Vector3(2.68288, -0.25891, 0.40101) :
	set(value):
		starmap_alignment = value
		if sky_material:
			sky_material.set_shader_parameter("starmap_alignment", value)


## Offset value for realigning the sky's rotation if using a datetime too many years off from the "epoch" of 20 March 2025.[br][br]
## [b]Temporary; will eventually be removed in a future update.[/b]
@export var star_rotation_offset: float = 9.38899 :
	set(value):
		star_rotation_offset = value
		if sky_material:
			sky_material.set_shader_parameter("star_rotation_offset", value)


## Flips the star map texture's U. Useful if the imported texture is backwards or upside down.
@export var starmap_flip_u: bool = false :
	set(value):
		starmap_flip_u = value
		sky_material.set_shader_parameter("starmap_flip_u", value)


## Flips the star map texture's V. Useful if the imported texture is backwards or upside down.
@export var starmap_flip_v: bool = false :
	set(value):
		starmap_flip_v = value
		sky_material.set_shader_parameter("starmap_flip_v", value)


## Color tint applied to the background starmap
@export var starmap_color := Color(0.709804, 0.709804, 0.709804, 0.854902) :
	set(value):
		starmap_color = value
		if is_scene_built:
			sky_material.set_shader_parameter("starmap_color", starmap_color)


## The panoramic texture for the stars and constellation background.
@export var starmap_texture: Texture2D = STARMAP_TEXTURE :
	set(value):
		starmap_texture = value
		if is_scene_built:
			sky_material.set_shader_parameter("starmap_texture", starmap_texture)


## The color tint for scattered individual stars.
@export var star_field_color := Color.WHITE :
	set(value):
		star_field_color = value
		if is_scene_built:
			sky_material.set_shader_parameter("star_field_color", star_field_color)


## The texture for rendering stars that will scintillate.
@export var star_field_texture: Texture2D = STARFIELD_TEXTURE :
	set(value):
		star_field_texture = value
		if is_scene_built:
			sky_material.set_shader_parameter("star_field_texture", star_field_texture)


## Controls the intensity of the simulated star "twinkling".
@export_range(0.0, 1.0, 0.001) var star_scintillation: float = 0.75 :
	set(value):
		star_scintillation = value
		if is_scene_built:
			sky_material.set_shader_parameter("star_scintillation", star_scintillation)


## Adjusts the speed at which the texture used for star "twinkling" moves across the star map textures.
@export var star_scintillation_speed: float = 0.01 :
	set(value):
		star_scintillation_speed = value
		if is_scene_built:
			sky_material.set_shader_parameter("star_scintillation_speed", star_scintillation_speed)


#####################
## Overlays
#####################

@export_group("Overlays")


## Overlays a grid aligned to the horizon and the sky zenith.
@export var show_azimuthal_grid: bool = false :
	set(value):
		if is_scene_built:
			show_azimuthal_grid = value
			sky_material.set_shader_parameter("show_azimuthal_grid", value)


## Color for azimuthal coordinate grid lines.
@export var azimuthal_grid_color := Color.BURLYWOOD:
	set(value):
		if is_scene_built:
			azimuthal_grid_color = value
			sky_material.set_shader_parameter("azimuthal_grid_color", value)


## Rotation offset for azimuthal grid.
@export_range(0.0, 1.0, 0.001) var azimuthal_grid_rotation_offset: float = 0.03 :
	set(value):
		azimuthal_grid_rotation_offset = value
		if sky_material:
			sky_material.set_shader_parameter("azimuthal_grid_rotation_offset", value)


## Overlays a grid aligned to the celestial equator and the north celestial pole (near Polaris).
@export var show_equatorial_grid: bool = false :
	set(value):
		if is_scene_built:
			show_equatorial_grid = value
			sky_material.set_shader_parameter("show_equatorial_grid", value)


## Color for equatorial coordinate grid lines.
@export var equatorial_grid_color := Color(.0, .75, 1.) :
	set(value):
		if is_scene_built:
			equatorial_grid_color = value
			sky_material.set_shader_parameter("equatorial_grid_color", value)


## Rotation offset for equatorial grid.
@export_range(0.0, 1.0, 0.001) var equatorial_grid_rotation_offset: float = 0.03 :
	set(value):
		equatorial_grid_rotation_offset = value
		if sky_material:
			sky_material.set_shader_parameter("equatorial_grid_rotation_offset", value)


# Astronomical horizontal coordinates are measured starting from the north with positive going clockwise.
# This is counter to traditional math where "azimuth" would increase going counter-clockwise.
# When inputting a star's known azimuth, it should be subtracted from 360 to map it to Godot's coordinates
# and avoid negative angles. 
const POLARIS_LASER_ALIGNMENT := Vector3(89.3707, 48.2213, 0.0)  # Real-world azimuth is 311.7787.
const VEGA_LASER_ALIGNMENT := Vector3(38.8, 281.666, 0.0)  # Real-world azimuth is 78.334.
const LASER_COLOR := Color(1.0, 0.0, 0.0, 1.0)
var _polaris_laser: MeshInstance3D
var _vega_laser: MeshInstance3D
var _laser_material: StandardMaterial3D

## Displays two red lines in 3D space aligned with Polaris and Vega if standing at the North Pole on the Vernal Equinox, 20 March 2025 at midnight.[br][br]
## [b][u]Usage[/u][/b][br]
## 1. Set the date and time in [TimeOfDay] to 20 March 2025 at midnight (0 hours), and the UTC to zero (0).[br]
## 2. Set the location in TimeOfDay to 90° North Latitude and 0° Longitude.[br]
## 3. In SkyDome, check [param show_alignment_lasers]. Two red lines will appear in 3D space to indicate the location of Polaris (North) and Vega (East).[br]
## 4. Adjust [param starmap_alignment] to align the correct stars to their respective lasers.[br][br]
## [b][u]Tips[/u][/b][br]
## · Use a photo editor to mark known stars on the texture for easy identification in the editor.[br]
## · On the viewport toolbar, set View / Settings / Perspective VFOV to a low value (5-15) to zoom in on the sky.[br]
## · Use View / 2 Viewports to see both lasers simultaneously.[br]
## · Position the editor cameras near the origin point as perspective may throw off adjustments.[br]
## · Not all texture maps are created equal. Distortions may result in alignments being slightly off no matter what.
@export var show_alignment_lasers: bool = false :
	set(value):
		show_alignment_lasers = value
		
		if _laser_material == null:
			_laser_material = StandardMaterial3D.new()
			_laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_laser_material.vertex_color_use_as_albedo = true
		
		if show_alignment_lasers:
			if not is_instance_valid(_polaris_laser):
				_polaris_laser = _create_alignment_laser("__polaris_laser", POLARIS_LASER_ALIGNMENT)
				add_child(_polaris_laser, true)
			if not is_instance_valid(_vega_laser):
				_vega_laser = _create_alignment_laser("__vega_laser", VEGA_LASER_ALIGNMENT)
				add_child(_vega_laser, true)
		else:
			if is_instance_valid(_polaris_laser):
				_polaris_laser.queue_free()
			if is_instance_valid(_vega_laser):
				_vega_laser.queue_free()
			_polaris_laser = null
			_vega_laser = null
			_laser_material = null


func _create_alignment_laser(name_hint: String, rot_deg: Vector3) -> MeshInstance3D:
	var immediate_mesh := ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_set_color(LASER_COLOR)
	immediate_mesh.surface_add_vertex(Vector3(0, 0, 0))
	immediate_mesh.surface_set_color(LASER_COLOR)
	immediate_mesh.surface_add_vertex(Vector3(0, 0, -1_000_000))
	immediate_mesh.surface_end()

	var laser_mesh := MeshInstance3D.new()
	laser_mesh.name = name_hint
	laser_mesh.mesh = immediate_mesh
	laser_mesh.material_override = _laser_material
	laser_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser_mesh.rotation_degrees = rot_deg
	return laser_mesh
