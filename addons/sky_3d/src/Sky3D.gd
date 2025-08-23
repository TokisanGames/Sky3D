# Copyright (c) 2023-2025 Cory Petkovsek and Contributors
# Copyright (c) 2021 J. Cuellar

## Sky3D is an Atmosphereic Day/Night Cycle for Godot 4.
##
## It manages time, moving the sun, moon, and stars, and consolidates environmental lighting controls.
## To use it, remove any WorldEnvironment node from you scene, then add a new Sky3D node.
## Explore and configure the settings in the Sky3D, SunLight, MoonLight, TimeOfDay, and Skydome nodes.

@tool
class_name Sky3D
extends WorldEnvironment

## Emitted when the environment variable has changed.
signal environment_changed

# 90 degrees means the sun being exactly on the horizon, 0 degrees is up
const DAY_NIGHT_TRANSITION_ANGLE: float = deg_to_rad(87.0)

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var version: String = "2.1-dev"

const sky_shader: Shader = preload("res://addons/sky_3d/shaders/SkyMaterial.gdshader")
const fog_shader: Shader = preload("res://addons/sky_3d/shaders/AtmFog.gdshader")

const moon_texture: Texture2D = preload("res://addons/sky_3d/assets/thirdparty/textures/moon/MoonMap.png")
const background_texture: Texture2D = preload("res://addons/sky_3d/assets/thirdparty/textures/milkyway/Milkyway.jpg")
const stars_field_texture: Texture2D = preload("res://addons/sky_3d/assets/thirdparty/textures/milkyway/StarField.jpg")
const sun_moon_curve_fade: Curve = preload("res://addons/sky_3d/assets/resources/SunMoonLightFade.tres")
const stars_field_noise: Texture2D = preload("res://addons/sky_3d/assets/textures/noise.jpg")
const clouds_texture: Texture2D = preload("res://addons/sky_3d/assets/resources/SNoise.tres")
const clouds_cumulus_texture: Texture2D = preload("res://addons/sky_3d/assets/textures/noiseClouds.png")

## The Sun DirectionalLight.
var sun: DirectionalLight3D
## The Moon DirectionalLight.
var moon: DirectionalLight3D
## The TimeOfDay node.
var tod: TimeOfDay
## The Skydome node.
var sky: Skydome
## The Sky shader.
var sky_material: ShaderMaterial

## Enables all rendering and time tracking.
@export var sky3d_enabled: bool = true :
	set(value):
		sky3d_enabled = value
		if value:
			show_sky()
			resume()
		else:
			hide_sky()
			pause()


#####################
## Visibility
#####################

@export_group("Visibility")


## Enables the sky shader. Disable sky, lights, fog for a black sky or call hide_sky().
@export var sky_enabled: bool = true :
	set(value):
		sky_enabled = value
		if sky and sky_material:
			sky_material.set_shader_parameter("sky_visible", value)
			sky.clouds_cumulus_visible = clouds_enabled and value
			sky.clouds_visible = clouds_enabled and value


## Enables both 2D and cumulus cloud layers.
@export var clouds_enabled: bool = true :
	set(value):
		clouds_enabled = value
		if sky:
			sky.clouds_cumulus_visible = value
			sky.clouds_visible = value


## Enables the Sun and Moon DirectionalLights.
@export var lights_enabled: bool = true :
	set(value):
		lights_enabled = value
		if sky:
			sky.sun_light_enabled = value
			sky.moon_light_enabled = value
	

## Enables the screen space fog shader.
@export var fog_enabled: bool = true :
	set(value):
		fog_enabled = value
		if sky:
			sky.fog_visible = value


## Disables rendering of sky, fog, and lights
func hide_sky() -> void:
	sky_enabled = false
	lights_enabled = false
	fog_enabled = false
	clouds_enabled = false


## Enables rendering of sky, fog, and lights
func show_sky() -> void:
	sky_enabled = true
	lights_enabled = true
	fog_enabled = true
	clouds_enabled = true


#####################
## Time
#####################

@export_group("Time")


## Allows time to progress in the editor. Alias for TimeOfDay.update_in_editor.
@export var editor_time_enabled: bool = true :
	set(value):
		if tod:
			tod.update_in_editor = value
	get:
		return tod.update_in_editor if tod else editor_time_enabled


## Allows time to progress in game. Alias for TimeOfDay.update_in_game.
@export var game_time_enabled: bool = true :
	set(value):
		if tod:
			tod.update_in_game = value
	get:
		return tod.update_in_game if tod else game_time_enabled


## Readable game date string, eg. '2025-01-01'. Alias for TimeOfDay.game_date.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var game_date: String = "" :
	get:
		return tod.game_date if tod else game_date
		
		
## Readable game time string, e.g. '08:00:00'. Alias for TimeOfDay.game_time.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var game_time: String = "" :
	get:
		return tod.game_time if tod else game_time


## The current in-game time in hours from 0.0 to 23.99. Smaller or larger values than the range will wrap.
## Alias for TimeOfDay.total_hours.
@export_range(0.0, 23.99, 0.01) var current_time: float = 8.0 :
	set(value):
		if tod:
			tod.total_hours = value
	get:
		return tod.total_hours if tod else current_time


## The length of a full in-game day in real-world minutes.[br]
## For example, setting this to [param 15] means a full in-game day takes 15 real-world minutes.[br]
## Only valid if automatic time progression is enabled.[br]
## Negative values moves time backwards.
## Alias for TimeOfDay.total_cycle_in_minutes.
@export_range(-1440, 1440, 0.1) var minutes_per_day: float = 15.0 :
	set(value):
		if tod:
			tod.total_cycle_in_minutes = value
	get:
		return tod.total_cycle_in_minutes if tod else minutes_per_day


## Frequency of sky updates, per second. The smaller the number, the more frequent the updates and
## the smoother the animation. Set to [param 0.016] for 60fps, for example.[br][br]
## [b]Note:[/b] Setting this value too small may cause unwanted behavior. See [member Timer.wait_time].
## Alias for TimeOfDay.update_interval.
@export_range(0.016, 10.0) var update_interval: float = 0.1 :
	set(value):
		if tod:
			tod.update_interval = value
	get:
		return tod.update_interval if tod else update_interval


## Tracks if the sun is above the horizon.
var _is_day: bool = true


## Returns true if the sun is above the horizon.
func is_day() -> bool:
	return _is_day

	
## Returns true if the sun is below the horizon.
func is_night() -> bool:
	return not _is_day


## Pauses time calculation. Alias for TimeOfDay.pause().
func pause() -> void:
	if tod:
		tod.pause()


## Resumes time calculation. Alias for TimeOfDay.resume().
func resume() -> void:
	if tod:
		tod.resume()


func _on_timeofday_updated(time: float) -> void:
	update_day_night()


var _contrib_tween: Tween

## Recalculates if it's currently day or night. Adjusts night ambient light if changing state or forced.
func update_day_night(force: bool = false) -> void:
	if not (sky and environment and is_inside_tree()):
		return

	# If day transitioning to night
	if abs(sky.sun_altitude) > DAY_NIGHT_TRANSITION_ANGLE and (_is_day or force):
		_is_day = false
		if _contrib_tween:
			_contrib_tween.kill()
		_contrib_tween = get_tree().create_tween()
		_contrib_tween.set_parallel(true)
		var night_contrib: float = minf(night_sky_contribution, sky_contribution) if night_ambient_boost else sky_contribution
		_contrib_tween.tween_property(environment, "ambient_light_sky_contribution", night_contrib, contribution_tween_time)

	# Else if night transitioning to day
	elif abs(sky.sun_altitude) <= DAY_NIGHT_TRANSITION_ANGLE and (not _is_day or force):
		_is_day = true
		if _contrib_tween:
			_contrib_tween.kill()
		_contrib_tween = get_tree().create_tween()
		_contrib_tween.set_parallel(true)
		_contrib_tween.tween_property(environment, "ambient_light_sky_contribution", sky_contribution, contribution_tween_time)


#####################
## Lighting
#####################

@export_group("Lighting")


## Light intensity scaled before the tonemapper. Softer highlights.
## Alias for Environment.camera_attributes.
## Connect this same resource to your Camera3D.attributes.
@export_range(0, 16, 0.005) var camera_exposure: float = 1.0 :
	set(value):
		if camera_attributes:
			camera_attributes.exposure_multiplier = value
	get:
		return camera_attributes.exposure_multiplier if camera_attributes else camera_exposure


## Light intensity scaled in post processing. Hotter highlights.
## Alias for Environment.tonemap_exposure.
## Connect this same resource to your Camera3D.environment.
@export_range(0, 16, 0.005) var tonemap_exposure: float = 1.0 :
	set(value):
		if environment:
			environment.tonemap_exposure = value
	get:
		return environment.tonemap_exposure if environment else tonemap_exposure


## Light energy coming from the sky shader. Alias for Skydome.exposure.
@export_range(0, 16, 0.005) var skydome_energy: float = 1.0 :
	set(value):
		if sky:
			sky.exposure = value
	get:
		return sky.exposure if sky else skydome_energy


## Brightness of and light energy coming from the clouds. Alias for Skydome.clouds_cumulus_intensity.
@export_range(0, 16, 0.005) var cloud_intensity: float = 0.6 :
	set(value):
		if sky:
			sky.clouds_cumulus_intensity = value
	get:
		return sky.clouds_cumulus_intensity if sky else cloud_intensity


## Maximum brightness of the Sun DirectionalLight, visible during the day.
## Alias for Skydome.sun_light_energy.
@export_range(0, 16, 0.005) var sun_energy: float = 1.0 :
	set(value):
		if sky:
			sky.sun_light_energy = value
	get:
		return sky.sun_light_energy if sky else sun_energy


## Opacity of Sun DirectionalLight shadow. Alias for SunLight.shadow_opacity.
@export_range(0, 1, 0.005) var sun_shadow_opacity: float = 1.0 :
	set(value):
		if sun:
			sun.shadow_opacity = value
	get:	
		return sun.shadow_opacity if sun else sun_shadow_opacity


## Ratio of ambient light to sky light. Works when there are no Reflection Probes or GI.
## Sets the target for Environment.ambient_light_sky_contribution, which may change at night
## depending on night_ambient_boost and night_sky_contribution.
@export_range(0, 1, 0.005) var sky_contribution: float = 1.0 :
	set(value):
		if environment:
			sky_contribution = value
			environment.ambient_light_sky_contribution = value
			update_day_night(true)


## Strength of ambient light. Works when there are no Reflection Probes or GI, and
## sky_contribution < 1. Alias for Environment.ambient_light_energy.
@export_range(0, 16, 0.005) var ambient_energy: float = 1.0 :
	set(value):
		environment.ambient_light_energy = value
		update_day_night(true)
	get:
		return environment.ambient_light_energy if environment else ambient_energy


@export_subgroup("Night")


## Maximum strength of Moon DirectionalLight, visible at night. Alias for Skydome.moon_light_energy.
@export_range(0, 16, 0.005) var moon_energy: float = 0.3 :
	set(value):
		if sky:
			sky.moon_light_energy = value
	get:
		return sky.moon_light_energy if sky else moon_energy


## Opacity of Moon DirectionalLight shadow. Alias for MoonLight.shadow_opacity.
@export_range(0, 1, 0.005) var moon_shadow_opacity: float = 1.0 :
	set(value):
		if moon:
			moon.shadow_opacity = value
	get:
		return moon.shadow_opacity if moon else moon_shadow_opacity


## Enables a lower sky_contribution at night, which allows more ambient energy to show.
## To use, ensure there are no ReflectionProbes or GI. Set ambient_energy > 0.
## Set night_sky_contribution < sky_contribution.
## Then at night, Environment.ambient_light_sky_contribution will be set lower, which
## will show more ambient_energy.
@export var night_ambient_boost: bool = true :
	set(value):
		night_ambient_boost = value
		update_day_night(true)


## Sets Environment.ambient_light_sky_contribution at night if night_ambient_boost is enabled.
## See night_ambient_boost and sky_contribution.
@export_range(0, 1, 0.005) var night_sky_contribution: float = 0.7 :
	set(value):
		night_sky_contribution = value
		if night_ambient_boost:
			update_day_night(true)


## Transition time for changing sky contribution when shifting between day and night.
@export_range(0, 30, 0.05) var contribution_tween_time: float = 3.0


@export_subgroup("Auto Exposure")


## Alias for CameraAttributes.auto_exposure_enabled.
@export var auto_exposure: bool = false :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_enabled = value
	get:
		return camera_attributes.auto_exposure_enabled if camera_attributes else auto_exposure


## Alias for CameraAttributes.auto_exposure_scale.
@export_range(0.01, 16, 0.005) var auto_exposure_scale: float = 0.2 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_scale = value
	get:
		return camera_attributes.auto_exposure_scale if camera_attributes else auto_exposure_scale


## Alias for CameraAttributesPractical.auto_exposure_min_sensitivity.
@export_range(0, 1600, 0.5) var auto_exposure_min: float = 0.0 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_min_sensitivity = value
			if value > auto_exposure_max:
				auto_exposure_max = value
	get:
		return camera_attributes.auto_exposure_min_sensitivity if camera_attributes else auto_exposure_min


## Alias for CameraAttributesPractical.auto_exposure_max_sensitivity.
@export_range(30, 64000, 0.5) var auto_exposure_max: float = 800.0 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_max_sensitivity = value
			if value < auto_exposure_min:
				auto_exposure_min = value
	get:
		return camera_attributes.auto_exposure_max_sensitivity if camera_attributes else auto_exposure_max


## Alias for CameraAttributes.auto_exposure_speed.
@export_range(0.1, 64, 0.1) var auto_exposure_speed: float = 0.5 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_speed = value
	get:
		return camera_attributes.auto_exposure_speed if camera_attributes else auto_exposure_speed


#####################
## Overlays
#####################

@export_group("Overlays")


## Overlays a zenith aligned spherical grid. Change color in Skydome. Alias for Skydome.show_azimuthal_grid.
@export var show_azimuthal_grid: bool = false :
	set(value):
		if sky:
			sky.show_azimuthal_grid = value
	get:
		return sky.show_azimuthal_grid if sky else show_azimuthal_grid


## Overlays a zenith aligned with sky rotation. This is currently incorrect and should rotate around Polaris.
## Change color in Skydome. Alias for Skydome.show_equatorial_grid.
@export var show_equatorial_grid: bool = false :
	set(value):
		if sky:
			sky.show_equatorial_grid = value
	get:		
		return sky.show_equatorial_grid if sky else show_equatorial_grid


#####################
## Setup
#####################


func _notification(what: int) -> void:
	# Must be after _init and before _enter_tree to properly set vars like 'sky' for setters
	if what in [ NOTIFICATION_SCENE_INSTANTIATED, NOTIFICATION_ENTER_TREE ]:
		_initialize()


func _initialize() -> void:
	# Create default environment
	if environment == null:
		environment = Environment.new()
		environment.background_mode = Environment.BG_SKY
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = 0.7
		environment.ambient_light_energy = 1.0
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		environment.tonemap_white = 6
		emit_signal("environment_changed", environment)

	# Setup Sky material & Upgrade old
	if environment.sky == null or environment.sky.sky_material is PhysicalSkyMaterial:
		environment.sky = Sky.new()
		environment.sky.sky_material = ShaderMaterial.new()
		environment.sky.sky_material.shader = sky_shader
		
	# Set a reference to the sky material for easy access.
	sky_material = environment.sky.sky_material
		
	# Create default camera attributes
	if camera_attributes == null:
		camera_attributes = CameraAttributesPractical.new()

	# Assign children nodes
	
	if has_node("SunLight"):
		sun = $SunLight
	elif is_inside_tree():
		sun = DirectionalLight3D.new()
		sun.name = "SunLight"
		add_child(sun, true)
		sun.owner = get_tree().edited_scene_root
		sun.shadow_enabled = true
	
	if has_node("MoonLight"):
		moon = $MoonLight
	elif is_inside_tree():
		moon = DirectionalLight3D.new()
		moon.name = "MoonLight"
		add_child(moon, true)
		moon.owner = get_tree().edited_scene_root
		moon.shadow_enabled = true

	if has_node("Skydome"):
		sky = $Skydome
		sky.environment = environment
	elif is_inside_tree():
		sky = Skydome.new()
		sky.name = "Skydome"
		add_child(sky, true)
		sky.owner = get_tree().edited_scene_root
		sky.sun_light_path = "../SunLight"
		sky.moon_light_path = "../MoonLight"
		sky.environment = environment

	if has_node("TimeOfDay"):
		tod = $TimeOfDay
	elif is_inside_tree():
		tod = TimeOfDay.new()
		tod.name = "TimeOfDay"
		add_child(tod, true)
		tod.owner = get_tree().edited_scene_root
		tod.dome_path = "../Skydome"
	if tod and not tod.time_changed.is_connected(_on_timeofday_updated):
		tod.time_changed.connect(_on_timeofday_updated)


func _enter_tree() -> void:
	update_day_night(true)


func _set(property: StringName, value: Variant) -> bool:
	match property:
		"environment":
			sky.environment = value
			environment = value
			emit_signal("environment_changed", environment)
			return true
	return false
