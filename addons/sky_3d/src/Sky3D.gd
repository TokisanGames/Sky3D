# Copyright (c) 2023-2025 Cory Petkovsek and Contributors
# Copyright (c) 2021 J. Cuellar

## Sky3D is an Atmosphereic Day/Night Cycle for Godot 4.
##
## This plugin manages time, moving the sun, moon, and stars, and consolidates environmental lighting controls.
## To use it, remove any WorldEnvironment node from you scene, then add a new Sky3D node.
## Explore and configure the settings in the Sky3D, SunLight, MoonLight, [SkyDome], and [TimeOfDay] nodes.

@tool
class_name Sky3D
extends WorldEnvironment

## Emitted when the environment has changed to a new resource.
signal environment_changed

const SKY_SHADER: String = "res://addons/sky_3d/shaders/SkyMaterial.gdshader"

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var version: String = "2.1-dev"

## The Sun DirectionalLight.
var sun: DirectionalLight3D
## The Moon DirectionalLight.
var moon: DirectionalLight3D
## The TimeOfDay node.
var tod: TimeOfDay
## The SkyDome node.
var sky: SkyDome
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


## Enables the sky shader. Disable sky, lights, fog for a black sky or call [method hide_sky].
@export var sky_enabled: bool = true :
	set(value):
		sky_enabled = value
		if sky and sky_material:
			sky_material.set_shader_parameter("sky_visible", value)
			sky.cumulus_visible = clouds_enabled and value
			sky.cirrus_visible = clouds_enabled and value


## Enables both 2D and cumulus cloud layers.
@export var clouds_enabled: bool = true :
	set(value):
		clouds_enabled = value
		if sky:
			sky.cumulus_visible = value
			sky.cirrus_visible = value


## Enables the Sun and Moon [DirectionalLight3D]s.
@export var lights_enabled: bool = true :
	set(value):
		lights_enabled = value
		if sky:
			sky.sun_light_enabled = value
			sky.moon_light_enabled = value


## Enables the screen space fog shader. Sky3D also works with the other two fog methods built into Godot.
@export var fog_enabled: bool = true :
	set(value):
		fog_enabled = value
		if sky:
			sky.fog_visible = value


## Disables rendering of sky, fog, and lights.
func hide_sky() -> void:
	sky_enabled = false
	lights_enabled = false
	fog_enabled = false
	clouds_enabled = false


## Enables rendering of sky, fog, and lights.
func show_sky() -> void:
	sky_enabled = true
	lights_enabled = true
	fog_enabled = true
	clouds_enabled = true


#####################
## Time
#####################

@export_group("Time")


## Allows time to progress in the editor. Alias for [member TimeOfDay.editor_time_enabled].
@export var editor_time_enabled: bool = true :
	set(value):
		if tod:
			tod.editor_time_enabled = value
	get:
		return tod.editor_time_enabled if tod else editor_time_enabled


## Allows time to progress in game. Alias for [member TimeOfDay.game_time_enabled].
@export var game_time_enabled: bool = true :
	set(value):
		if tod:
			tod.game_time_enabled = value
	get:
		return tod.game_time_enabled if tod else game_time_enabled


## A readable game date string, eg. '2025-01-01'. Alias for [member TimeOfDay.game_date].
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var game_date: String = "" :
	get:
		return tod.game_date if tod else game_date


## A readable game time string, e.g. '08:00:00'. Alias for [member TimeOfDay.game_time].
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var game_time: String = "" :
	get:
		return tod.game_time if tod else game_time


## The current in-game time in hours from 0.0 to 23.99. Smaller or larger values than the range will wrap.
## Alias for [member TimeOfDay.current_time].
@export_range(0.0, 23.9998, 0.01) var current_time: float = 8.0 :
	set(value):
		if tod:
			tod.current_time = value
	get:
		return tod.current_time if tod else current_time


## The total length of time for a complete day and night cycle in real world minutes. Setting this to
## [param 15] means a full in-game day takes 15 real-world minutes. [member game_time_enabled] must be
## enabled for this to work. Negative values moves time backwards. The Witcher 3 uses a 96 minute cycle. 
## Adjust [member update_interval] to match. Shorter days needs more updates. Longer days need less.
## Alias for [member TimeOfDay.minutes_per_day].
@export_range(-1440, 1440, 0.1) var minutes_per_day: float = 15.0 :
	set(value):
		if tod:
			tod.minutes_per_day = value
	get:
		return tod.minutes_per_day if tod else minutes_per_day


## Frequency of sky updates, per second. The smaller the number, the more frequent the updates and
## the smoother the animation. Set to [param 0.016] for 60fps, for example.[br][br]
## [b]Note:[/b] Setting this value too small may cause unwanted behavior. See [member Timer.wait_time].
## Alias for [member TimeOfDay.update_interval].
@export_range(0.016, 10.0) var update_interval: float = 0.016 :
	set(value):
		if tod:
			tod.update_interval = value
	get:
		return tod.update_interval if tod else update_interval


## Returns true if the sun is above the horizon.
func is_day() -> bool:
	return sky and sky.is_day()


## Returns true if the sun is below the horizon.
func is_night() -> bool:
	return sky and not sky.is_day()


## Pauses time calculation. Alias for [method TimeOfDay.pause].
func pause() -> void:
	if tod:
		tod.pause()


## Resumes time calculation. Alias for [method TimeOfDay.resume].
func resume() -> void:
	if tod:
		tod.resume()


var _contrib_tween: Tween

# Adjusts sky contribution if transitioning to day or night.
func _start_sky_contrib_tween(daytime: bool = is_day()) -> void:
	if not (sky and environment and is_inside_tree()):
		return

	if _contrib_tween:
		_contrib_tween.kill()
	_contrib_tween = get_tree().create_tween()
	_contrib_tween.set_parallel(true)
	
	if daytime:
		_contrib_tween.tween_property(environment, "ambient_light_sky_contribution", sky_contribution, contribution_tween_time)
	else:
		var night_contrib: float = minf(night_sky_contribution, sky_contribution) if night_ambient_boost else sky_contribution
		_contrib_tween.tween_property(environment, "ambient_light_sky_contribution", night_contrib, contribution_tween_time)


#####################
## Lighting
#####################

@export_group("Lighting")


## Light intensity scaled before the tonemapper. Softer highlights.
## Alias for [member Environment.camera_attributes].
## Connect this same resource to your [member Camera3D.attributes].
@export_range(0, 16, 0.005) var camera_exposure: float = 1.0 :
	set(value):
		if camera_attributes:
			camera_attributes.exposure_multiplier = value
	get:
		return camera_attributes.exposure_multiplier if camera_attributes else camera_exposure


## Light intensity scaled in post processing. Hotter highlights.
## Alias for [member Environment.tonemap_exposure].
## Connect this same resource to your [member Camera3D.environment].
@export_range(0, 16, 0.005) var tonemap_exposure: float = 1.0 :
	set(value):
		if environment:
			environment.tonemap_exposure = value
	get:
		return environment.tonemap_exposure if environment else tonemap_exposure


## Light energy coming from the sky shader. Alias for [member SkyDome.exposure].
@export_range(0, 16, 0.005) var skydome_energy: float = 1.0 :
	set(value):
		if sky:
			sky.exposure = value
	get:
		return sky.exposure if sky else skydome_energy


## Brightness of and light energy coming from the clouds. Alias for [member SkyDome.cumulus_intensity].
@export_range(0, 16, 0.005) var cloud_intensity: float = 0.6 :
	set(value):
		if sky:
			sky.cumulus_intensity = value
	get:
		return sky.cumulus_intensity if sky else cloud_intensity


## Maximum brightness of the Sun DirectionalLight, visible during the day.
## Alias for [member SkyDome.sun_light_energy].
@export_range(0, 16, 0.005) var sun_energy: float = 1.0 :
	set(value):
		if sky:
			sky.sun_light_energy = value
	get:
		return sky.sun_light_energy if sky else sun_energy


## Opacity of Sun DirectionalLight shadow. Alias for [member DirectionalLight3D.shadow_opacity].
@export_range(0, 1, 0.005) var sun_shadow_opacity: float = 1.0 :
	set(value):
		if sun:
			sun.shadow_opacity = value
	get:	
		return sun.shadow_opacity if sun else sun_shadow_opacity


## Ratio of ambient light to sky light. Works when there are no Reflection Probes or GI.
## Sets the target for [member Environment.ambient_light_sky_contribution], which may change at night
## depending on [member night_ambient_boost] and [member night_sky_contribution].
@export_range(0, 1, 0.005) var sky_contribution: float = 1.0 :
	set(value):
		if environment:
			sky_contribution = value
			environment.ambient_light_sky_contribution = value
			_start_sky_contrib_tween()


## Strength of ambient light. Works when there are no Reflection Probes or GI, and
## [member sky_contribution] < 1. Alias for [member Environment.ambient_light_energy].
@export_range(0, 16, 0.005) var ambient_energy: float = 1.0 :
	set(value):
		environment.ambient_light_energy = value
		_start_sky_contrib_tween()
	get:
		return environment.ambient_light_energy if environment else ambient_energy


@export_subgroup("Night")


## Maximum strength of Moon DirectionalLight, visible at night. Alias for [member SkyDome.moon_light_energy].
@export_range(0, 16, 0.005) var moon_energy: float = 0.3 :
	set(value):
		if sky:
			sky.moon_light_energy = value
	get:
		return sky.moon_light_energy if sky else moon_energy


## Opacity of Moon DirectionalLight shadow. Alias for [member DirectionalLight3D.shadow_opacity].
@export_range(0, 1, 0.005) var moon_shadow_opacity: float = 1.0 :
	set(value):
		if moon:
			moon.shadow_opacity = value
	get:
		return moon.shadow_opacity if moon else moon_shadow_opacity


## Enables a lower sky_contribution at night, which allows more ambient energy to show.
## To use, ensure there are no ReflectionProbes or GI. Set [member ambient_energy] > 0.
## Set [member night_sky_contribution] < [member sky_contribution].
## Then at night, [member Environment.ambient_light_sky_contribution] will be set lower, which
## will show more [member ambient_energy].
@export var night_ambient_boost: bool = true :
	set(value):
		night_ambient_boost = value
		_start_sky_contrib_tween()


## Sets [member Environment.ambient_light_sky_contribution] at night if [member night_ambient_boost] is enabled.
## See [member night_ambient_boost] and [member sky_contribution].
@export_range(0, 1, 0.005) var night_sky_contribution: float = 0.7 :
	set(value):
		night_sky_contribution = value
		if night_ambient_boost:
			_start_sky_contrib_tween()


## Transition time for changing sky contribution when shifting between day and night.
@export_range(0, 30, 0.05) var contribution_tween_time: float = 3.0


@export_subgroup("Auto Exposure")


## Alias for [member CameraAttributes.auto_exposure_enabled].
@export var auto_exposure: bool = false :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_enabled = value
	get:
		return camera_attributes.auto_exposure_enabled if camera_attributes else auto_exposure


## Alias for [member CameraAttributes.auto_exposure_scale].
@export_range(0.01, 16, 0.005) var auto_exposure_scale: float = 0.4 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_scale = value
	get:
		return camera_attributes.auto_exposure_scale if camera_attributes else auto_exposure_scale


## Alias for [member CameraAttributesPractical.auto_exposure_min_sensitivity].
@export_range(0, 1600, 0.5) var auto_exposure_min: float = 0.0 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_min_sensitivity = value
			if value > auto_exposure_max:
				auto_exposure_max = value
	get:
		return camera_attributes.auto_exposure_min_sensitivity if camera_attributes else auto_exposure_min


## Alias for [member CameraAttributesPractical.auto_exposure_max_sensitivity].
@export_range(30, 64000, 0.5) var auto_exposure_max: float = 800.0 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_max_sensitivity = value
			if value < auto_exposure_min:
				auto_exposure_min = value
	get:
		return camera_attributes.auto_exposure_max_sensitivity if camera_attributes else auto_exposure_max


## Alias for [member CameraAttributes.auto_exposure_speed].
@export_range(0.1, 64, 0.1) var auto_exposure_speed: float = 0.5 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_speed = value
	get:
		return camera_attributes.auto_exposure_speed if camera_attributes else auto_exposure_speed


#####################
## Weather
#####################

@export_group("Weather")

## Sets the wind speed. Alias for [member SkyDome.wind_speed].
@export_custom(PROPERTY_HINT_RANGE, "0,120,0.1,or_greater,or_less,suffix:m/s") var wind_speed: float = 1.0 :
	set(value):
		if sky:
			sky.wind_speed = value
	get:
		return sky.wind_speed if sky else wind_speed

## Sets the wind direction. Zero means the wind is coming from the north, 90 from the east,
## 180 from the south and 270 (or -90) from the west. Alias for [member SkyDome.wind_direction].
@export_custom(PROPERTY_HINT_RANGE, "-180,180,0.1,radians_as_degrees") var wind_direction: float = 0.0 :
	set(value):
		if sky:
			sky.wind_direction = value
	get:
		return sky.wind_direction if sky else wind_direction


#####################
## Overlays
#####################

@export_group("Overlays")


## Overlays a grid aligned to the horizon and the sky zenith.
## Change color in SkyDome. Alias for [member SkyDome.show_azimuthal_grid].
@export var show_azimuthal_grid: bool = false :
	set(value):
		if sky:
			sky.show_azimuthal_grid = value
	get:
		return sky.show_azimuthal_grid if sky else show_azimuthal_grid


## Overlays a grid aligned to the celestial equator and the north celestial pole (near Polaris).
## Change color in SkyDome. Alias for [member SkyDome.show_equatorial_grid].
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
		environment.sky.sky_material.shader = load(SKY_SHADER)
		
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

	# DEPRECATED - Remove 2.2
	if has_node("Skydome"):
		$Skydome.name = "SkyDome"
	if has_node("SkyDome"):
		sky = $SkyDome
		sky.environment = environment
	elif is_inside_tree():
		sky = SkyDome.new()
		sky.name = "SkyDome"
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
		tod.dome_path = "../SkyDome"
	if sky and not sky.day_night_changed.is_connected(_start_sky_contrib_tween):
		sky.day_night_changed.connect(_start_sky_contrib_tween)


func _enter_tree() -> void:
	_start_sky_contrib_tween()


func _set(property: StringName, value: Variant) -> bool:
	match property:
		"environment":
			sky.environment = value
			environment = value
			emit_signal("environment_changed", environment)
			return true
	return false
