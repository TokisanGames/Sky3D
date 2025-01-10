# Copyright (c) 2023-2025 Cory Petkovsek and Contributors
# Copyright (c) 2021 J. Cuellar

@tool
class_name Sky3D
extends WorldEnvironment

signal environment_changed

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var tod: TimeOfDay
var sky: Skydome


func _enter_tree() -> void:
	initialize()


func _ready() -> void:
	# Reapply current settings once attached to the tree
	sky_enabled = sky_enabled
	lights_enabled = lights_enabled
	fog_enabled = fog_enabled
	clouds_enabled = clouds_enabled
	show_physical_sky = show_physical_sky
	current_time = current_time

	tod.time_changed.connect(_on_timeofday_updated)


## Visibility

@export var sky3d_enabled: bool = true : set = set_sky3d_enabled

@export_group("Visibility")
@export var sky_enabled: bool = true : set = set_sky_enabled
@export var lights_enabled: bool = true : set = set_lights_enabled
@export var fog_enabled: bool = true : set = set_fog_enabled
@export var clouds_enabled: bool = true : set = set_clouds_enabled
@export var show_physical_sky: bool = false : set = set_show_physical_sky
var _default_sun_energy: float
var _default_moon_energy: float


func set_sky3d_enabled(value: bool) -> void:
	sky3d_enabled = value
	sky_enabled = value
	fog_enabled = value
	clouds_enabled = value
	if value:
		resume()
	else:
		pause()


func set_sky_enabled(value: bool) -> void:
	sky_enabled = value
	if not sky:
		return
	sky.sky_visible = value
	sky.clouds_cumulus_visible = value
	sky.sun_light_energy = _default_sun_energy if value else 0
	sky.moon_light_energy = _default_moon_energy if value else 0


func set_lights_enabled(value: bool) -> void:
	lights_enabled = value
	if not sky:
		return
	sky.sun_light_enable = value
	sky.moon_light_enable = value
	sky.__sun_light_node.visible = value && sky.__sun_light_node.light_energy > 0
	sky.__moon_light_node.visible = ! value && sky.__moon_light_node.light_energy > 0


func set_fog_enabled(value: bool) -> void:
	fog_enabled = value
	if sky:
		sky.fog_visible = value


func set_clouds_enabled(value: bool) -> void:
	clouds_enabled = value
	if not sky:
		return
	sky.clouds_cumulus_visible = value
	sky.clouds_thickness = float(value) * 1.7


func set_show_physical_sky(value: bool) -> void:
	show_physical_sky = value
	if not sky:
		return
	sky.sky_visible = !value


## Time

@export_group("Time")
@export var enable_editor_time: bool = true : set = set_editor_time_enabled
@export var enable_game_time: bool = true : set = set_game_time_enabled
@export_range(0.0, 24.0) var current_time: float = 8.0 : set = set_current_time
@export_range(-1440,1440,1) var minutes_per_day: float = 15.0 : set = set_minutes_per_day
@export_range(0.016, 10.0) var update_interval: float = 0.1 : set = set_update_interval
@export var manual_time_management: bool = false : set = set_manual_time_management;
var _is_day: bool = true


func pause() -> void:
	$TimeOfDay.pause()


func resume() -> void:
	$TimeOfDay.resume()


func is_day() -> bool:
	return _is_day

	
func is_night() -> bool:
	return not _is_day


func set_editor_time_enabled(value:bool) -> void:
	enable_editor_time = value
	if tod:
		tod.update_in_editor = value


func set_game_time_enabled(value:bool) -> void:
	enable_game_time = value
	if tod:
		tod.update_in_game = value


func set_current_time(value:float) -> void:
	current_time = value
	if tod and tod.total_hours != current_time:
		tod.total_hours = value


func set_minutes_per_day(value):
	minutes_per_day = value
	if tod:
		tod.total_cycle_in_minutes = value


func set_update_interval(value:float) -> void:
	update_interval = value
	if tod:
		tod.update_interval = value

func set_manual_time_management(value:bool) -> void:
	manual_time_management = value
	if tod:
		tod._manual_time_management = value

func manual_time_update() -> void:
	if tod:
		tod.manual_time_update()

func _on_timeofday_updated(time: float) -> void:
	if tod and (Engine.is_editor_hint() or manual_time_management):
		minutes_per_day = tod.total_cycle_in_minutes
		current_time = tod.total_hours
		update_interval = tod.update_interval

	if night_ambient:
		if abs(sky.sun_altitude) > 87 and _is_day:
			_is_day = false
			var tween: Tween = get_tree().create_tween()
			tween.set_parallel(true)
			tween.tween_property(environment, "ambient_light_sky_contribution", minf(night_ambient_min, sky_contribution), 3)
			tween.tween_property(environment.sky.sky_material, "energy_multiplier", 1., 3)
		elif abs(sky.sun_altitude) <= 87 and not _is_day:
			_is_day = true
			var tween: Tween = get_tree().create_tween()
			tween.set_parallel(true)
			tween.tween_property(environment, "ambient_light_sky_contribution", sky_contribution, 3)
			tween.tween_property(environment.sky.sky_material, "energy_multiplier", reflected_energy, 3)


## Exposure

@export_group("Exposure")
@export_range(0,1,.005) var sky_contribution: float = 1.0: set = set_sky_contribution
@export_range(0,16,.005) var ambient_energy: float = 1.0: set = set_ambient_energy
@export var night_ambient: bool = true: set = set_night_ambient
@export_range(0,1,.005) var night_ambient_min: float = .7
@export_range(0,128,.005) var reflected_energy: float = 1.0: set = set_reflected_energy
@export_range(0,16,.005) var skydome_energy: float = 1.3: set = set_skydome_energy
@export_range(0,16,.005) var tonemap_exposure: float = 1.0: set = set_tonemap_exposure
@export_range(0,16,.005) var camera_exposure: float = 1.0: set = set_camera_exposure

@export_subgroup("Auto Exposure")
@export var auto_exposure: bool = false: set = set_auto_exposure_enabled
@export_range(0.01,16,.005) var auto_exposure_scale: float = 0.2: set = set_auto_exposure_scale
@export_range(0,1600,.5) var auto_exposure_min: float = 0.0: set = set_auto_exposure_min
@export_range(30,64000,.5) var auto_exposure_max: float = 800.0: set = set_auto_exposure_max
@export_range(0.1,64,.1) var auto_exposure_speed: float = 0.5: set = set_auto_exposure_speed


func set_sky_contribution(value:float) -> void:
	if environment:
		sky_contribution = value
		environment.ambient_light_sky_contribution = value


func set_ambient_energy(value:float) -> void:
	if environment:
		ambient_energy = value
		environment.ambient_light_energy = value


func set_night_ambient(value: bool) -> void:
	night_ambient = value
	if night_ambient:
		_on_timeofday_updated(tod.total_hours)
	else:
		set_sky_contribution(sky_contribution)


func set_reflected_energy(value:float) -> void:
	if environment:
		reflected_energy = value
		if environment.sky:
			environment.sky.sky_material.energy_multiplier = value


func set_skydome_energy(value:float) -> void:
	if sky:
		skydome_energy = value
		sky.exposure = value


func set_tonemap_exposure(value:float) -> void:
	if environment:
		tonemap_exposure = value
		environment.tonemap_exposure = value


func set_camera_exposure(value:float) -> void:
	if camera_attributes:
		camera_exposure = value
		camera_attributes.exposure_multiplier = value


func set_auto_exposure_enabled(value:bool) -> void:
	if camera_attributes:
		auto_exposure = value
		camera_attributes.auto_exposure_enabled = value


func set_auto_exposure_scale(value:float) -> void:
	if camera_attributes:
		auto_exposure_scale = value
		camera_attributes.auto_exposure_scale = value


func set_auto_exposure_min(value:float) -> void:
	if camera_attributes:
		auto_exposure_min = value
		camera_attributes.auto_exposure_min_sensitivity = value


func set_auto_exposure_max(value:float) -> void:
	if camera_attributes:
		auto_exposure_max = value
		camera_attributes.auto_exposure_max_sensitivity = value


func set_auto_exposure_speed(value:float) -> void:
	if camera_attributes:
		auto_exposure_speed = value
		camera_attributes.auto_exposure_speed = value


## Setup


func initialize() -> void:
	# Create default environment
	if environment == null:
		environment = Environment.new()
		environment.background_mode = Environment.BG_SKY
		environment.sky = Sky.new()
		environment.sky.sky_material = PhysicalSkyMaterial.new()
		environment.sky.sky_material.use_debanding = false
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = 0.7
		environment.ambient_light_energy = 1.0
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		environment.tonemap_white = 6
		emit_signal("environment_changed", environment)
	
	# Create default camera attributes
	if camera_attributes == null:
		camera_attributes = CameraAttributesPractical.new()

	# Create children nodes
	if get_child_count() > 0:
		tod = $TimeOfDay
		sky = $Skydome
		sky.environment = environment
		sun = $SunLight
		moon = $MoonLight
	else:
		sun = DirectionalLight3D.new()
		sun.name = "SunLight"
		add_child(sun, true)
		sun.owner = get_tree().edited_scene_root
		sun.shadow_enabled = true

		moon = DirectionalLight3D.new()
		moon.name = "MoonLight"
		add_child(moon, true)
		moon.owner = get_tree().edited_scene_root
		moon.shadow_enabled = true

		tod = TimeOfDay.new()
		tod.name = "TimeOfDay"
		add_child(tod, true)
		tod.owner = get_tree().edited_scene_root
		tod.dome_path = "../Skydome"
		
		sky = Skydome.new()
		sky.name = "Skydome"
		add_child(sky, true)
		sky.owner = get_tree().edited_scene_root
		sky.sun_light_path = "../SunLight"
		sky.moon_light_path = "../MoonLight"
		sky.environment = environment
		
	_default_sun_energy = $Skydome.sun_light_energy
	_default_moon_energy = $Skydome.moon_light_energy


func _set(property: StringName, value: Variant) -> bool:
	match property:
		"environment":
			sky.environment = value
			environment = value
			emit_signal("environment_changed", environment)
			return true
	return false


## Constants

# Node names
const SKY_INSTANCE:= "_SkyMeshI"
const FOG_INSTANCE:= "_FogMeshI"
const MOON_INSTANCE:= "MoonRender"
const CLOUDS_C_INSTANCE:= "_CloudsCumulusI"

# Shaders
const _sky_shader: Shader = preload("res://addons/sky_3d/shaders/Sky.gdshader")
const _pv_sky_shader: Shader = preload("res://addons/sky_3d/shaders/PerVertexSky.gdshader")
const _clouds_cumulus_shader: Shader = preload("res://addons/sky_3d/shaders/CloudsCumulus.gdshader")
const _fog_shader: Shader = preload("res://addons/sky_3d/shaders/AtmFog.gdshader")

# Scenes
const _moon_render: PackedScene = preload("res://addons/sky_3d/assets/resources/MoonRender.tscn")

# Textures
const _moon_texture: Texture2D = preload("res://addons/sky_3d/assets/thirdparty/textures/moon/MoonMap.png")
const _background_texture: Texture2D = preload("res://addons/sky_3d/assets/thirdparty/textures/milkyway/Milkyway.jpg")
const _stars_field_texture: Texture2D = preload("res://addons/sky_3d/assets/thirdparty/textures/milkyway/StarField.jpg")
const _sun_moon_curve_fade: Curve = preload("res://addons/sky_3d/assets/resources/SunMoonLightFade.tres")
const _stars_field_noise: Texture2D = preload("res://addons/sky_3d/assets/textures/noise.jpg")
const _clouds_texture: Texture2D = preload("res://addons/sky_3d/assets/resources/SNoise.tres")
const _clouds_cumulus_texture: Texture2D = preload("res://addons/sky_3d/assets/textures/noiseClouds.png")

# Skydome
const MAX_EXTRA_CULL_MARGIN: float = 16384.0
const DEFAULT_POSITION:= Vector3(0.0000001, 0.0000001, 0.0000001)

# Coords
const SUN_DIR_P:= "_sun_direction"
const MOON_DIR_P:= "_moon_direction"
const MOON_MATRIX:= "_moon_matrix"

# General
const TEXTURE_P:= "_texture"
const COLOR_CORRECTION_P:= "_color_correction_params"
const GROUND_COLOR_P:= "_ground_color"
const NOISE_TEX:= "_noise_tex"
const HORIZON_LEVEL = "_horizon_level"

# Atmosphere
const ATM_DARKNESS_P:= "_atm_darkness"
const ATM_BETA_RAY_P:= "_atm_beta_ray"
const ATM_SUN_INTENSITY_P:= "_atm_sun_intensity"
const ATM_DAY_TINT_P:= "_atm_day_tint"
const ATM_HORIZON_LIGHT_TINT_P:= "_atm_horizon_light_tint"

const ATM_NIGHT_TINT_P:= "_atm_night_tint"
const ATM_LEVEL_PARAMS_P:= "_atm_level_params"
const ATM_THICKNESS_P:= "_atm_thickness"
const ATM_BETA_MIE_P:= "_atm_beta_mie"

const ATM_SUN_MIE_TINT_P:= "_atm_sun_mie_tint"
const ATM_SUN_MIE_INTENSITY_P:= "_atm_sun_mie_intensity"
const ATM_SUN_PARTIAL_MIE_PHASE_P:= "_atm_sun_partial_mie_phase"

const ATM_MOON_MIE_TINT_P:= "_atm_moon_mie_tint"
const ATM_MOON_MIE_INTENSITY_P:= "_atm_moon_mie_intensity"
const ATM_MOON_PARTIAL_MIE_PHASE_P:= "_atm_moon_partial_mie_phase"

# Fog
const ATM_FOG_DENSITY_P:= "_fog_density"
const ATM_FOG_RAYLEIGH_DEPTH_P:= "_fog_rayleigh_depth"
const ATM_FOG_MIE_DEPTH_P:= "_fog_mie_depth"
const ATM_FOG_FALLOFF:= "_fog_falloff"
const ATM_FOG_START:= "_fog_start"
const ATM_FOG_END:= "_fog_end"

# Near Space
const SUN_DISK_COLOR_P:= "_sun_disk_color"
const SUN_DISK_INTENSITY_P:= "_sun_disk_intensity"
const SUN_DISK_SIZE_P:= "_sun_disk_size"
const MOON_COLOR_P:= "_moon_color"
const MOON_SIZE_P:= "_moon_size"
const MOON_TEXTURE_P:= "_moon_texture"

# Deep Space
const DEEP_SPACE_MATRIX_P:= "_deep_space_matrix"
const BG_COL_P:= "_background_color"
const BG_TEXTURE_P:= "_background_texture"
const STARS_COLOR_P:= "_stars_field_color"
const STARS_TEXTURE_P:= "_stars_field_texture"
const STARS_SC_P:= "_stars_scintillation"
const STARS_SC_SPEED_P:= "_stars_scintillation_speed"

# Clouds
const CLOUDS_THICKNESS:= "_clouds_thickness"
const CLOUDS_COVERAGE:= "_clouds_coverage"
const CLOUDS_ABSORPTION:= "_clouds_absorption"
const CLOUDS_SKY_TINT_FADE:= "_clouds_sky_tint_fade"
const CLOUDS_INTENSITY:= "_clouds_intensity"
const CLOUDS_SIZE:= "_clouds_size"
const CLOUDS_NOISE_FREQ:= "_clouds_noise_freq"

const CLOUDS_UV:= "_clouds_uv"
const CLOUDS_DIRECTION:= "_clouds_direction"
const CLOUDS_SPEED:= "_clouds_speed"
const CLOUDS_TEXTURE:= "_clouds_texture"

const CLOUDS_DAY_COLOR:= "_clouds_day_color"
const CLOUDS_HORIZON_LIGHT_COLOR:= "_clouds_horizon_light_color"
const CLOUDS_NIGHT_COLOR:= "_clouds_night_color"
const CLOUDS_MIE_INTENSITY:= "_clouds_mie_intensity"
const CLOUDS_PARTIAL_MIE_PHASE:= "_clouds_partial_mie_phase"
