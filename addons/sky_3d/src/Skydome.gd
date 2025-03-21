# Copyright (c) 2023-2025 Cory Petkovsek and Contributors
# Copyright (c) 2021 J. Cuellar

@tool
class_name Skydome
extends Node

signal sun_direction_changed(value)
signal sun_transform_changed(value)
signal moon_direction_changed(value)
signal moon_transform_changed(value)
signal day_night_changed(value)
signal lights_changed

var is_scene_built: bool

var moon_render: Node

var fog_mesh: MeshInstance3D

var sky_material: ShaderMaterial
var moon_material: Material
var clouds_cumulus_material: Material
var fog_material: Material


func _ready() -> void:
	build_scene()

	# Update properties
	# General
	update_color_correction_params()
	update_ground_color()
	update_horizon_level()
	
	# Coords
	update_sun_coords()
	update_moon_coords()
	
	# Atmosphere
	update_atm_quality()
	update_beta_ray()
	update_atm_darkness()
	update_atm_sun_intensity()
	update_atm_day_tint()
	update_atm_horizon_light_tint()
	update_night_intensity()
	update_atm_level_params()
	update_atm_thickness()
	update_beta_mie()
	update_atm_sun_mie_tint()
	update_atm_sun_mie_intensity()
	update_atm_sun_mie_anisotropy()
	update_atm_moon_mie_tint()
	update_atm_moon_mie_intensity()
	update_atm_moon_mie_anisotropy()
	
	# Fog
	update_fog_visible()
	update_fog_atm_level_params_offset()
	update_fog_density()
	update_fog_start()
	update_fog_end()
	update_fog_rayleigh_depth()
	update_fog_mie_depth()
	update_fog_falloff()
	update_fog_layers()
	update_fog_render_priority()
	
	# Near space
	update_sun_light_path()
	update_sun_disk_color()
	update_sun_disk_intensity()
	update_sun_disk_size()
	update_moon_color()
	update_moon_light_path()
	update_moon_size()
	update_moon_texture()

	# Near space lighting
	update_sun_light_color()
	update_sun_light_energy()
	update_moon_light_color()
	update_moon_light_energy()
	
	# Deep space
	update_deep_space_basis()
	update_background_color()
	update_background_texture()
	update_stars_field_color()
	update_stars_field_texture()
	update_stars_scintillation()
	update_stars_scintillation_speed()
	
	# Clouds
	update_clouds_thickness()
	update_clouds_coverage()
	update_clouds_absorption()
	update_clouds_sky_tint_fade()
	update_clouds_intensity()
	update_clouds_size()
	update_clouds_uv()
	update_clouds_direction()
	update_clouds_speed()
	update_clouds_texture()
	
	# Clouds cumulus
	update_clouds_cumulus_day_color()
	update_clouds_cumulus_horizon_light_color()
	update_clouds_cumulus_night_color()
	update_clouds_cumulus_thickness()
	update_clouds_cumulus_coverage()
	update_clouds_cumulus_absorption()
	update_clouds_cumulus_noise_freq()
	update_clouds_cumulus_intensity()
	update_clouds_cumulus_mie_intensity()
	update_clouds_cumulus_mie_anisotropy()
	update_clouds_cumulus_size()
	update_clouds_cumulus_direction()
	update_clouds_cumulus_speed()
	update_clouds_cumulus_texture()
	
	# Environment
	__update_environment()


func build_scene() -> void:
	if is_scene_built:
		return

	# Sky Material
	# Necessary for now until we can pull everything off the Skydome node.
	sky_material = get_parent().environment.sky.sky_material
	sky_material.set_shader_parameter(Sky3D.NOISE_TEX, Sky3D._stars_field_noise)
	
	# Set cumulus cloud global to point to the sky material.
	# Necessary for now until we can pull everything off the Skydome node.
	clouds_cumulus_material = sky_material
	
	fog_mesh = MeshInstance3D.new()
	fog_mesh.name = Sky3D.FOG_INSTANCE
	var fog_screen_quad = QuadMesh.new()
	var size: Vector2
	size.x = 2.0
	size.y = 2.0
	fog_screen_quad.size = size
	fog_mesh.mesh = fog_screen_quad
	fog_material = ShaderMaterial.new()
	fog_material.shader = Sky3D._fog_shader
	fog_material.render_priority = 127
	fog_mesh.material_override = fog_material
	__setup_mesh_instance(fog_mesh, Vector3.ZERO)
	add_child(fog_mesh)

	is_scene_built = true
	
	
func __setup_mesh_instance(target: MeshInstance3D, origin: Vector3) -> void:
	target.transform.origin = origin
	target.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.custom_aabb = AABB(Vector3(-1e31, -1e31, -1e31), Vector3(2e31, 2e31, 2e31))
	

#####################
## Global 
#####################

@export_group("Global")
@export_range(0.0, 1.0, 0.001) var tonemap_level: float = 0.0: set = set_tonemap_level
@export var exposure: float = 1.3: set = set_exposure
@export var ground_color: Color = Color(0.3, 0.3, 0.3, 1.0): set = set_ground_color
@export var horizon_level: float = 0.0: set = set_horizon_level

func set_tonemap_level(value: float) -> void:
	if value == tonemap_level:
		return
	tonemap_level = value
	update_color_correction_params()

	
func set_exposure(value: float) -> void:
	if value == exposure:
		return
	exposure = value
	update_color_correction_params()
		
		
func update_color_correction_params() -> void:
	if !is_scene_built:
		return
	var p: Vector2
	p.x = tonemap_level
	p.y = exposure
	sky_material.set_shader_parameter(Sky3D.COLOR_CORRECTION_P, p)
	fog_material.set_shader_parameter(Sky3D.COLOR_CORRECTION_P, p)

func set_ground_color(value: Color) -> void:
	if value == ground_color:
		return
	ground_color = value
	update_ground_color()


func update_ground_color() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.GROUND_COLOR_P, ground_color)
	

func set_horizon_level(value: float) -> void:
	if value == horizon_level:
		return
	horizon_level = value
	update_horizon_level()


func update_horizon_level() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.HORIZON_LEVEL, horizon_level)


#####################
## Sun Coords
#####################

@export_group("Sun")
@export_node_path("DirectionalLight3D") var sun_light_path: NodePath = NodePath("../SunLight"): set = set_sun_light_path
@export var sun_light_energy: float = 1.0: set = set_sun_light_energy
@export var sun_disk_color: Color = Color(0.996094, 0.541334, 0.140076): set = set_sun_disk_color
@export_range(0.0, 100.0) var sun_disk_intensity: float = 2.0: set = set_sun_disk_intensity
@export_range(0.0, 0.5, 0.001) var sun_disk_size: float = 0.015: set = set_sun_disk_size
@export var sun_light_color: Color = Color.WHITE : set = set_sun_light_color 
@export var sun_horizon_light_color: Color = Color(.98, 0.523, 0.294, 1.0): set = set_sun_horizon_light_color
@export_range(-180.0, 180.0, 0.00001) var sun_azimuth: float = 0.0: set = set_sun_azimuth
@export_range(-180.0, 180.0, 0.00001) var sun_altitude: float = -27.387: set = set_sun_altitude

var __finish_set_sun_pos: bool = false
var __sun_transform: Transform3D = Transform3D()

func set_sun_azimuth(value: float) -> void:
	if value == sun_azimuth:
		return
	sun_azimuth = value
	update_sun_coords()
	

func set_sun_altitude(value: float) -> void:
	if value == sun_altitude:
		return
	sun_altitude = value
	update_sun_coords()


func get_sun_transform() -> Transform3D:
	return __sun_transform


func sun_direction() -> Vector3:
	return __sun_transform.origin


func update_sun_coords() -> void:
	if !is_scene_built:
		return
		
	var azimuth: float = sun_azimuth * TOD_Math.DEG_TO_RAD
	var altitude: float = sun_altitude * TOD_Math.DEG_TO_RAD
	
	__finish_set_sun_pos = false
	if not __finish_set_sun_pos:
		__sun_transform.origin = TOD_Math.to_orbit(altitude, azimuth)
		__finish_set_sun_pos = true
	
	if __finish_set_sun_pos:
		__sun_transform = __sun_transform.looking_at(Vector3.ZERO, Vector3.LEFT)
	
	__set_day_state(altitude)
	emit_signal("sun_transform_changed", __sun_transform)
	emit_signal("sun_transform_changed", sun_direction())
	
	fog_material.set_shader_parameter(Sky3D.SUN_DIR_P, sun_direction())
	
	if __sun_light_node != null:
		__sun_light_node.transform = __sun_transform
	
	update_night_intensity()
	update_sun_light_color()
	update_sun_light_energy()
	update_moon_light_energy()
	__update_environment()


#####################
## Moon Coords
#####################

@export_group("Moon")
@export var moon_texture: Texture2D = Sky3D._moon_texture: set = set_moon_texture
@export_node_path("DirectionalLight3D") var moon_light_path: NodePath = NodePath("../MoonLight"): set = set_moon_light_path
@export var moon_light_energy: float = 0.3: set = set_moon_light_energy
@export var moon_color: Color = Color.WHITE: set = set_moon_color
@export var moon_size: float = 0.07: set = set_moon_size
@export var moon_light_color: Color = Color(0.572549, 0.776471, 0.956863, 1.0): set = set_moon_light_color
@export_range(-180.0, 180.0, 0.00001) var moon_azimuth: float = 5.0: set = set_moon_azimuth
@export_range(-180.0, 180.0, 0.00001) var moon_altitude: float = -80.0: set = set_moon_altitude

var __finish_set_moon_pos: bool = false
var __moon_transform: Transform3D = Transform3D()


func set_moon_azimuth(value: float) -> void:
	if value == moon_azimuth:
		return
	moon_azimuth = value
	update_moon_coords()
	

func set_moon_altitude(value: float) -> void:
	if value == moon_altitude:
		return
	moon_altitude = value
	update_moon_coords()
	

func get_moon_transform() -> Transform3D:
	return __moon_transform


func moon_direction() -> Vector3:
	return __moon_transform.origin


func update_moon_coords() -> void:
	if !is_scene_built:
		return
		
	var azimuth: float = moon_azimuth * TOD_Math.DEG_TO_RAD
	var altitude: float = moon_altitude * TOD_Math.DEG_TO_RAD
	
	__finish_set_moon_pos = false
	if not __finish_set_moon_pos:
		__moon_transform.origin = TOD_Math.to_orbit(altitude, azimuth)
		__finish_set_moon_pos = true
	
	if __finish_set_moon_pos:
		__moon_transform = __moon_transform.looking_at(Vector3.ZERO, Vector3.LEFT)
		pass
	
	emit_signal("moon_transform_changed", __moon_transform)
	emit_signal("moon_direction_changed", moon_direction())
	
	var moon_basis: Basis = get_parent().moon.get_global_transform().basis.inverse()
	sky_material.set_shader_parameter(Sky3D.MOON_MATRIX, moon_basis)
	fog_material.set_shader_parameter(Sky3D.MOON_DIR_P, moon_direction())
	
	if __moon_light_node != null:
		__moon_light_node.transform = __moon_transform
	
	__moon_light_altitude_mult = TOD_Math.saturate(moon_direction().y)
	
	update_night_intensity()
	set_moon_light_color(moon_light_color)
	update_moon_light_energy()
	__update_environment()


#####################
## Atmosphere
#####################

@export_group("Atmosphere")
@export var atm_wavelengths: Vector3 = Vector3(680.0, 550.0, 440.0): set = set_atm_wavelengths
@export_range(0.0, 1.0, 0.01) var atm_darkness: float = 0.5: set = set_atm_darkness
@export var atm_sun_intensity: float = 18.0: set = set_atm_sun_intensity
@export var atm_day_tint: Color = Color(0.807843, 0.909804, 1.0): set = set_atm_day_tint
@export var atm_horizon_light_tint: Color = Color(0.980392, 0.635294, 0.462745, 1.0): set = set_atm_horizon_light_tint
@export var atm_enable_moon_scatter_mode: bool = false: set = set_atm_enable_moon_scatter_mode
@export var atm_night_tint: Color = Color(0.168627, 0.2, 0.25098, 1.0): set = set_atm_night_tint
@export var atm_level_params: Vector3 = Vector3(1.0, 0.0, 0.0): set = set_atm_level_params
@export_range(0.0, 100.0, 0.01) var atm_thickness: float = 0.7: set = set_atm_thickness
@export var atm_mie: float = 0.07: set = set_atm_mie
@export var atm_turbidity: float = 0.001: set = set_atm_turbidity
@export var atm_sun_mie_tint: Color = Color(1.0, 1.0, 1.0, 1.0): set = set_atm_sun_mie_tint
@export var atm_sun_mie_intensity: float = 1.0: set = set_atm_sun_mie_intensity
@export_range(0.0, 0.9999999, 0.0000001) var atm_sun_mie_anisotropy: float = 0.8: set = set_atm_sun_mie_anisotropy
@export var atm_moon_mie_tint: Color = Color(0.137255, 0.184314, 0.292196): set = set_atm_moon_mie_tint
@export var atm_moon_mie_intensity: float = 0.7: set = set_atm_moon_mie_intensity
@export_range(0.0, 0.9999999, 0.0000001) var atm_moon_mie_anisotropy: float = 0.8: set = set_atm_moon_mie_anisotropy

func update_atm_quality() -> void:
	if !is_scene_built:
		return
	sky_material.shader = Sky3D._new_sky_shader


func set_atm_wavelengths(value : Vector3) -> void:
	if value == atm_wavelengths:
		return
	atm_wavelengths = value
	update_beta_ray()
	

func update_beta_ray() -> void:
	if !is_scene_built:
		return

	var wll: Vector3 = ScatterLib.compute_wavelenghts_lambda(atm_wavelengths)
	var wls: Vector3 = ScatterLib.compute_wavlenghts(wll)
	var betaRay: Vector3 = ScatterLib.compute_beta_ray(wls)
	sky_material.set_shader_parameter(Sky3D.ATM_BETA_RAY_P, betaRay)
	fog_material.set_shader_parameter(Sky3D.ATM_BETA_RAY_P, betaRay)

	
func set_atm_darkness(value: float) -> void:
	if value == atm_darkness:
		return
	atm_darkness = value
	update_atm_darkness()

	
func update_atm_darkness() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.ATM_DARKNESS_P, atm_darkness)
	fog_material.set_shader_parameter(Sky3D.ATM_DARKNESS_P, atm_darkness)


func set_atm_sun_intensity(value: float) -> void:
	if value == atm_sun_intensity:
		return
	atm_sun_intensity = value
	update_atm_sun_intensity()

	
func update_atm_sun_intensity() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.ATM_SUN_INTENSITY_P, atm_sun_intensity)
	fog_material.set_shader_parameter(Sky3D.ATM_SUN_INTENSITY_P, atm_sun_intensity)


func set_atm_day_tint(value: Color) -> void:
	if value == atm_day_tint:
		return
	atm_day_tint = value
	update_atm_day_tint()

	
func update_atm_day_tint() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.ATM_DAY_TINT_P, atm_day_tint)
	fog_material.set_shader_parameter(Sky3D.ATM_DAY_TINT_P, atm_day_tint)


func set_atm_horizon_light_tint(value: Color) -> void:
	if value == atm_horizon_light_tint:
		return
	atm_horizon_light_tint = value
	update_atm_horizon_light_tint()


func update_atm_horizon_light_tint() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.ATM_HORIZON_LIGHT_TINT_P, atm_horizon_light_tint)
	fog_material.set_shader_parameter(Sky3D.ATM_HORIZON_LIGHT_TINT_P, atm_horizon_light_tint)


func set_atm_enable_moon_scatter_mode(value: bool) -> void:
	if value == atm_enable_moon_scatter_mode:
		return
	atm_enable_moon_scatter_mode = value
	update_night_intensity()


func set_atm_night_tint(value: Color) -> void:
	if value == atm_night_tint:
		return
	atm_night_tint = value
	update_night_intensity()


func update_night_intensity() -> void:
	if !is_scene_built:
		return

	var tint: Color = atm_night_tint * atm_night_intensity()
	sky_material.set_shader_parameter(Sky3D.ATM_NIGHT_TINT_P, tint)
	fog_material.set_shader_parameter(Sky3D.ATM_NIGHT_TINT_P, atm_night_tint * fog_atm_night_intensity())
	set_atm_moon_mie_intensity(atm_moon_mie_intensity)


func set_atm_level_params(value: Vector3) -> void:
	if value == atm_level_params:
		return
	atm_level_params = value
	update_atm_level_params()

	
func update_atm_level_params() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.ATM_LEVEL_PARAMS_P, atm_level_params)
	fog_material.set_shader_parameter(Sky3D.ATM_LEVEL_PARAMS_P, atm_level_params + fog_atm_level_params_offset)


func set_atm_thickness(value: float) -> void:
	if value == atm_thickness:
		return
	atm_thickness = value
	update_atm_thickness()


func update_atm_thickness() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.ATM_THICKNESS_P, atm_thickness)
	fog_material.set_shader_parameter(Sky3D.ATM_THICKNESS_P, atm_thickness)


func set_atm_mie(value: float) -> void:
	if value == atm_mie:
		return
	atm_mie = value
	update_beta_mie()


func set_atm_turbidity(value: float) -> void:
	if value == atm_turbidity:
		return
	atm_turbidity = value
	update_beta_mie()


func update_beta_mie() -> void:
	if !is_scene_built:
		return

	var bm: Vector3 = ScatterLib.compute_beta_mie(atm_mie, atm_turbidity)
	sky_material.set_shader_parameter(Sky3D.ATM_BETA_MIE_P, bm)
	fog_material.set_shader_parameter(Sky3D.ATM_BETA_MIE_P, bm)


func set_atm_sun_mie_tint(value: Color) -> void:
	if value == atm_sun_mie_tint:
		return
	atm_sun_mie_tint = value
	update_atm_sun_mie_tint()


func update_atm_sun_mie_tint() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.ATM_SUN_MIE_TINT_P, atm_sun_mie_tint)
	fog_material.set_shader_parameter(Sky3D.ATM_SUN_MIE_TINT_P, atm_sun_mie_tint)


func set_atm_sun_mie_intensity(value: float) -> void:
	if value == atm_sun_mie_intensity:
		return
	atm_sun_mie_intensity = value
	update_atm_sun_mie_intensity()


func update_atm_sun_mie_intensity() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.ATM_SUN_MIE_INTENSITY_P, atm_sun_mie_intensity)
	fog_material.set_shader_parameter(Sky3D.ATM_SUN_MIE_INTENSITY_P, atm_sun_mie_intensity)


func set_atm_sun_mie_anisotropy(value: float) -> void:
	if value == atm_sun_mie_anisotropy:
		return
	atm_sun_mie_anisotropy = value
	update_atm_sun_mie_anisotropy()

	
func update_atm_sun_mie_anisotropy() -> void:
	if !is_scene_built:
		return
	var partial: Vector3 = ScatterLib.get_partial_mie_phase(atm_sun_mie_anisotropy)
	sky_material.set_shader_parameter(Sky3D.ATM_SUN_PARTIAL_MIE_PHASE_P, partial)
	fog_material.set_shader_parameter(Sky3D.ATM_SUN_PARTIAL_MIE_PHASE_P, partial)


func set_atm_moon_mie_tint(value: Color) -> void:
	if value == atm_moon_mie_tint:
		return
	atm_moon_mie_tint = value
	update_atm_moon_mie_tint()

	
func update_atm_moon_mie_tint() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.ATM_MOON_MIE_TINT_P, atm_moon_mie_tint)
	fog_material.set_shader_parameter(Sky3D.ATM_MOON_MIE_TINT_P, atm_moon_mie_tint)


func set_atm_moon_mie_intensity(value: float) -> void:
	if value == atm_moon_mie_intensity:
		return
	atm_moon_mie_intensity = value
	update_atm_sun_mie_intensity()

	
func update_atm_moon_mie_intensity() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.ATM_MOON_MIE_INTENSITY_P, atm_moon_mie_intensity * atm_moon_phases_mult())
	fog_material.set_shader_parameter(Sky3D.ATM_MOON_MIE_INTENSITY_P, atm_moon_mie_intensity * atm_moon_phases_mult())


func set_atm_moon_mie_anisotropy(value: float) -> void:
	if value == atm_moon_mie_anisotropy:
		return
	atm_moon_mie_anisotropy = value
	update_atm_moon_mie_anisotropy()
	

func update_atm_moon_mie_anisotropy() -> void:
	if !is_scene_built:
		return
	var partial: Vector3 = ScatterLib.get_partial_mie_phase(atm_moon_mie_anisotropy)
	sky_material.set_shader_parameter(Sky3D.ATM_MOON_PARTIAL_MIE_PHASE_P, partial)
	fog_material.set_shader_parameter(Sky3D.ATM_MOON_PARTIAL_MIE_PHASE_P, partial)


func atm_moon_phases_mult() -> float:
	if not atm_enable_moon_scatter_mode:
		return atm_night_intensity()
	return TOD_Math.saturate(-sun_direction().dot(moon_direction()) + 0.60)


func atm_night_intensity() -> float:
	if not atm_enable_moon_scatter_mode:
		return TOD_Math.saturate(-sun_direction().y + 0.30)
	return TOD_Math.saturate(moon_direction().y) * atm_moon_phases_mult()


func fog_atm_night_intensity() -> float:
	if not atm_enable_moon_scatter_mode:
		return TOD_Math.saturate(-sun_direction().y + 0.70)
	return TOD_Math.saturate(-sun_direction().y) * atm_moon_phases_mult()
	
	
#####################
## Fog
#####################

@export_group("Screen Space Fog")

@export var fog_visible: bool = true: set = set_fog_visible
@export var fog_atm_level_params_offset: Vector3 = Vector3(0.0, 0.0, -1.0): set = set_fog_atm_level_params_offset
@export_exp_easing() var fog_density: float = 0.0007: set = set_fog_density
@export_range(0.0, 5000.0) var fog_start: float = 0.0: set = set_fog_start
@export_range(0.0, 5000.0)  var fog_end: float = 1000: set = set_fog_end
@export_exp_easing() var fog_rayleigh_depth: float = 0.115: set = set_fog_rayleigh_depth
@export_exp_easing() var fog_mie_depth: float = 0.0001: set = set_fog_mie_depth
@export_range(0.0, 5000.0) var fog_falloff: float = 3.0: set = set_fog_falloff
@export_flags_3d_render var fog_layers: int = 524288: set = set_fog_layers
@export var fog_render_priority: int = 123: set = set_fog_render_priority

func set_fog_visible(value: bool) -> void:
	if value == fog_visible:
		return
	fog_visible = value
	update_fog_visible()
	
	
func update_fog_visible() -> void:
	if !is_scene_built:
		return
	fog_mesh.visible = fog_visible
	
	
func set_fog_atm_level_params_offset(value: Vector3) -> void:
	if value == fog_atm_level_params_offset:
		return
	fog_atm_level_params_offset = value
	update_fog_atm_level_params_offset()
	

func update_fog_atm_level_params_offset() -> void:
	if !is_scene_built:
		return
	fog_material.set_shader_parameter(Sky3D.ATM_LEVEL_PARAMS_P, atm_level_params + fog_atm_level_params_offset)


func set_fog_density(value: float) -> void:
	if value == fog_density:
		return
	fog_density = value
	update_fog_density()
	

func update_fog_density() -> void:
	if !is_scene_built:
		return
	fog_material.set_shader_parameter(Sky3D.ATM_FOG_DENSITY_P, fog_density)


func set_fog_start(value: float) -> void:
	if value == fog_start:
		return
	fog_start = value
	update_fog_start()


func update_fog_start() -> void:
	if !is_scene_built:
		return
	fog_material.set_shader_parameter(Sky3D.ATM_FOG_START, fog_start)
	

func set_fog_end(value: float) -> void:
	if value == fog_end:
		return
	fog_end = value
	update_fog_end()
	

func update_fog_end() -> void:
	if !is_scene_built:
		return
	fog_material.set_shader_parameter(Sky3D.ATM_FOG_END, fog_end)


func set_fog_rayleigh_depth(value: float) -> void:
	if value == fog_rayleigh_depth:
		return
	fog_rayleigh_depth = value
	update_fog_rayleigh_depth()
	

func update_fog_rayleigh_depth() -> void:
	if !is_scene_built:
		return
	fog_material.set_shader_parameter(Sky3D.ATM_FOG_RAYLEIGH_DEPTH_P, fog_rayleigh_depth)


func set_fog_mie_depth(value: float) -> void:
	if value == fog_mie_depth:
		return
	fog_mie_depth = value
	update_fog_mie_depth()
	

func update_fog_mie_depth() -> void:
	if !is_scene_built:
		return
	fog_material.set_shader_parameter(Sky3D.ATM_FOG_MIE_DEPTH_P, fog_mie_depth)


func set_fog_falloff(value: float) -> void:
	if value == fog_falloff:
		return
	fog_falloff = value
	update_fog_falloff()
	

func update_fog_falloff() -> void:
	if !is_scene_built:
		return
	fog_material.set_shader_parameter(Sky3D.ATM_FOG_FALLOFF, fog_falloff)


func set_fog_layers(value: int) -> void:
	if value == fog_layers:
		return
	fog_layers = value
	update_fog_layers()
	

func update_fog_layers() -> void:
	if !is_scene_built:
		return
	fog_mesh.layers = fog_layers


func set_fog_render_priority(value: int) -> void:
	if value == fog_render_priority:
		return
	fog_render_priority = value
	update_fog_render_priority()
	

func update_fog_render_priority() -> void:
	if !is_scene_built:
		return
	fog_material.render_priority = fog_render_priority

#####################
## Near space
#####################

func set_sun_disk_color(value: Color) -> void:
	if value == sun_disk_color:
		return
	sun_disk_color = value
	update_sun_disk_color()
	

func update_sun_disk_color() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.SUN_DISK_COLOR_P, sun_disk_color)


func set_sun_disk_intensity(value: float) -> void:
	if value == sun_disk_intensity:
		return
	sun_disk_intensity = value
	update_sun_disk_intensity()
	

func update_sun_disk_intensity() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.SUN_DISK_INTENSITY_P, sun_disk_intensity)


func set_sun_disk_size(value: float) -> void:
	if value == sun_disk_size:
		return
	sun_disk_size = value
	update_sun_disk_size()
	

func update_sun_disk_size() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.SUN_DISK_SIZE_P, sun_disk_size)


func set_moon_color(value: Color) -> void:
	if value == moon_color:
		return
	moon_color = value
	update_moon_color()
	

func update_moon_color() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.MOON_COLOR_P, moon_color)


func set_moon_size(value: float) -> void:
	if value == moon_size:
		return
	moon_size = value
	update_moon_size()
	
	
func update_moon_size() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.MOON_SIZE_P, moon_size)


func set_moon_texture(value: Texture2D) -> void:
	if value == moon_texture:
		return
	moon_texture = value
	update_moon_texture()
	

func update_moon_texture() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.MOON_TEXTURE_P, moon_texture)

	
#####################
## Sun
#####################

# Original sun light (0.984314, 0.843137, 0.788235)
# Original sun horizon (1.0, 0.384314, 0.243137, 1.0)

var __sun_light_node: DirectionalLight3D = null


func set_sun_light_color(value: Color) -> void:
	if value == sun_light_color:
		return
	sun_light_color = value
	update_sun_light_color()
	

func update_sun_light_color() -> void:
	if __sun_light_node == null:
		return
	var sun_light_altitude_mult: float = TOD_Math.saturate(sun_direction().y * 2)
	__sun_light_node.light_color = TOD_Math.plerp_color(sun_horizon_light_color, sun_light_color, sun_light_altitude_mult)


func set_sun_horizon_light_color(value: Color) -> void:
	if value == sun_horizon_light_color:
		return
	sun_horizon_light_color = value
	update_sun_light_color()
	

func set_sun_light_energy(value: float) -> void:
	if value == sun_light_energy:
		return
	sun_light_energy = value
	update_sun_light_energy()
	

func update_sun_light_energy() -> void:
	if __sun_light_node != null:
		# Light energy should depend on how much of the sun disk is visible.
		var y: float = sun_direction().y
		var sun_light_factor: float = TOD_Math.saturate((y + sun_disk_size) / (2 * sun_disk_size));
		__sun_light_node.light_energy = TOD_Math.lerp_f(0.0, sun_light_energy, sun_light_factor)


func set_sun_light_path(value: NodePath) -> void:
	sun_light_path = value
	update_sun_light_path()
	update_sun_coords()

	
func update_sun_light_path() -> void:
	if sun_light_path != null:
		__sun_light_node = get_node_or_null(sun_light_path) as DirectionalLight3D
	else:
		__sun_light_node = null


#####################
## Moon
#####################

var __moon_light_node: DirectionalLight3D
var __moon_light_altitude_mult: float = 0.0


func set_moon_light_color(value: Color) -> void:
	if value == moon_light_color:
		return
	moon_light_color = value
	update_moon_light_color()
	

func update_moon_light_color() -> void:
	if __moon_light_node == null:
		return
	__moon_light_node.light_color = moon_light_color
		

func set_moon_light_energy(value: float) -> void:
	moon_light_energy = value
	update_moon_light_energy()


func update_moon_light_energy() -> void:
	if __moon_light_node == null:
		return
	
	var l: float = TOD_Math.lerp_f(0.0, moon_light_energy, __moon_light_altitude_mult)
	l*= atm_moon_phases_mult()
	
	var fade: float = (1.0 - sun_direction().y) * 0.5
	__moon_light_node.light_energy = l * Sky3D._sun_moon_curve_fade.sample_baked(fade)


func set_moon_light_path(value: NodePath) -> void:
	moon_light_path = value
	update_moon_light_path()
	update_moon_coords()


func update_moon_light_path() -> void:
	if moon_light_path != null:
		__moon_light_node = get_node_or_null(moon_light_path) as DirectionalLight3D
	else:
		__moon_light_node = null


#####################
## Deep space
#####################

@export_group("Deep Space")
@export var deep_space_euler: Vector3 = Vector3(-0.752, 2.56, 0.0): set = set_deep_space_euler
@export var background_color: Color = Color(0.709804, 0.709804, 0.709804, 0.854902): set = set_background_color
@export var background_texture: Texture2D = Sky3D._background_texture: set = _set_background_texture
@export var stars_field_color: Color = Color.WHITE: set = set_stars_field_color
@export var stars_field_texture: Texture2D = Sky3D._stars_field_texture: set = _set_stars_field_texture
@export_range(0.0, 1.0, 0.001) var stars_scintillation: float = 0.75: set = set_stars_scintillation
@export var stars_scintillation_speed: float = 0.01: set = set_stars_scintillation_speed

var deep_space_quat: Quaternion = Quaternion.IDENTITY: set = set_deep_space_quat
var __deep_space_basis: Basis


func set_deep_space_euler(value: Vector3) -> void:
	deep_space_euler = value
	__deep_space_basis = Basis.from_euler(value)
	update_deep_space_basis()
	var quat: Quaternion = __deep_space_basis.get_rotation_quaternion()
	if deep_space_quat.angle_to(quat) < 0.01:
		return
	deep_space_quat = quat


func set_deep_space_quat(value: Quaternion) -> void:
	deep_space_quat = value
	__deep_space_basis = Basis(value)
	update_deep_space_basis()
	var euler: Vector3 = __deep_space_basis.get_euler()
	if deep_space_euler.angle_to(euler) < 0.01:
		return
	deep_space_euler = euler


func update_deep_space_basis() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.DEEP_SPACE_MATRIX_P, __deep_space_basis)


func set_background_color(value: Color) -> void:
	if value == background_color:
		return
	background_color = value
	update_background_color()


func update_background_color() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.BG_COL_P, background_color)


func update_background_texture() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.BG_TEXTURE_P, background_texture)


func _set_background_texture(value: Texture2D) -> void:
	if value == background_texture:
		return
	background_texture = value
	update_background_texture()
	

func update_stars_field_color() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.STARS_COLOR_P, stars_field_color)


func set_stars_field_color(value: Color) -> void:
	if value == stars_field_color:
		return
	stars_field_color = value
	update_stars_field_color()
	

func update_stars_field_texture() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.STARS_TEXTURE_P, stars_field_texture)


func _set_stars_field_texture(value: Texture2D) -> void:
	if value == stars_field_texture:
		return
	stars_field_texture = value
	update_stars_field_texture()


func update_stars_scintillation() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.STARS_SC_P, stars_scintillation)


func set_stars_scintillation(value: float) -> void:
	if value == stars_scintillation:
		return
	stars_scintillation = value
	update_stars_scintillation()


func update_stars_scintillation_speed() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.STARS_SC_SPEED_P, stars_scintillation_speed)


func set_stars_scintillation_speed(value: float) -> void:
	if value == stars_scintillation_speed:
		return
	stars_scintillation_speed = value
	update_stars_scintillation_speed()


#####################
## 2D Clouds
#####################

@export_group("2D Clouds")
@export var clouds_visible: bool = true: set = set_clouds_visible
@export var clouds_thickness: float = 1.7: set = set_clouds_thickness
@export_range(0.0, 1.0, 0.001) var clouds_coverage: float = 0.5: set = set_clouds_coverage
@export var clouds_absorption: float = 2.0: set = set_clouds_absorption
@export_range(0.0, 1.0, 0.001) var clouds_sky_tint_fade: float = 0.5: set = set_clouds_sky_tint_fade
@export var clouds_intensity: float = 10.0: set = set_clouds_intensity
@export var clouds_size: float = 2.0: set = set_clouds_size
@export var clouds_uv: Vector2 = Vector2(0.16, 0.11): set = set_clouds_uv
@export var clouds_direction: Vector2 = Vector2(0.25, 0.25): set = set_clouds_direction
@export var clouds_speed: float = 0.07: set = set_clouds_speed
@export var clouds_texture: Texture2D = Sky3D._clouds_texture: set = _set_clouds_texture

func set_clouds_visible(value: bool) -> void:
	if value == clouds_visible:
		return
	clouds_visible = value
	sky_material.set_shader_parameter(Sky3D.CLOUDS_VISIBLE, value)

func set_clouds_thickness(value: float) -> void:
	if value == clouds_thickness:
		return
	clouds_thickness = value
	update_clouds_thickness()


func update_clouds_thickness() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.CLOUDS_THICKNESS, clouds_thickness)


func set_clouds_coverage(value: float) -> void:
	if value == clouds_coverage:
		return
	clouds_coverage = value
	update_clouds_coverage()


func update_clouds_coverage() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.CLOUDS_COVERAGE, clouds_coverage)


func set_clouds_absorption(value: float) -> void:
	if value == clouds_absorption:
		return
	clouds_absorption = value
	update_clouds_absorption()


func update_clouds_absorption() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.CLOUDS_ABSORPTION, clouds_absorption)


func set_clouds_sky_tint_fade(value: float) -> void:
	if value == clouds_sky_tint_fade:
		return
	clouds_sky_tint_fade = value
	update_clouds_sky_tint_fade()


func update_clouds_sky_tint_fade() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.CLOUDS_SKY_TINT_FADE, clouds_sky_tint_fade)


func set_clouds_intensity(value: float) -> void:
	if value == clouds_intensity:
		return
	clouds_intensity = value
	update_clouds_intensity()
	

func update_clouds_intensity() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.CLOUDS_INTENSITY, clouds_intensity)


func set_clouds_size(value: float) -> void:
	if value == clouds_size:
		return
	clouds_size = value
	update_clouds_size()
	

func update_clouds_size() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.CLOUDS_SIZE, clouds_size)


func set_clouds_uv(value: Vector2) -> void:
	if value == clouds_uv:
		return
	clouds_uv = value
	update_clouds_uv()


func update_clouds_uv() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.CLOUDS_UV, clouds_uv)


func set_clouds_direction(value: Vector2) -> void:
	if value == clouds_direction:
		return
	clouds_direction = value
	update_clouds_direction()
	

func update_clouds_direction() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.CLOUDS_DIRECTION, clouds_direction)


func set_clouds_speed(value: float) -> void:
	if value == clouds_speed:
		return
	clouds_speed = value
	update_clouds_speed()
	

func update_clouds_speed() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.CLOUDS_SPEED, clouds_speed)


func _set_clouds_texture(value: Texture2D) -> void:
	if value == clouds_texture:
		return
	clouds_texture = value
	update_clouds_texture()


func update_clouds_texture() -> void:
	if !is_scene_built:
		return
	sky_material.set_shader_parameter(Sky3D.CLOUDS_TEXTURE, clouds_texture)


#####################
## Cumulus Clouds
#####################

@export_group("Cumulus Clouds")
@export var clouds_cumulus_visible: bool = true: set = set_clouds_cumulus_visible
@export var clouds_cumulus_day_color: Color = Color(0.823529, 0.87451, 1.0, 1.0): set = set_clouds_cumulus_day_color
@export var clouds_cumulus_horizon_light_color: Color = Color(.98, 0.43, 0.15, 1.0): set = set_clouds_cumulus_horizon_light_color
@export var clouds_cumulus_night_color: Color = Color(0.090196, 0.094118, 0.129412, 1.0): set = set_clouds_cumulus_night_color
@export var clouds_cumulus_thickness: float = 0.0243: set = set_clouds_cumulus_thickness
@export_range(0.0, 1.0, 0.001) var clouds_cumulus_coverage: float = 0.55: set = set_clouds_cumulus_coverage
@export var clouds_cumulus_absorption: float = 2.0: set = set_clouds_cumulus_absorption
@export_range(0.0, 3.0, 0.001) var clouds_cumulus_noise_freq: float = 2.7: set = set_clouds_cumulus_noise_freq
@export var clouds_cumulus_intensity: float = 1.0: set = set_clouds_cumulus_intensity
@export var clouds_cumulus_mie_intensity: float = 1.0: set = set_clouds_cumulus_mie_intensity
@export_range(0.0, 0.9999999, 0.0000001) var clouds_cumulus_mie_anisotropy: float = 0.206: set = set_clouds_cumulus_mie_anisotropy
@export var clouds_cumulus_size: float = 0.5: set = set_clouds_cumulus_size
@export var clouds_cumulus_direction: Vector3 = Vector3(0.25, 0.1, 0.25): set = set_clouds_cumulus_direction
@export var clouds_cumulus_speed: float = 0.05: set = set_clouds_cumulus_speed
@export var clouds_cumulus_texture: Texture2D = Sky3D._clouds_cumulus_texture: set = _set_clouds_cumulus_texture


func set_clouds_cumulus_visible(value: bool) -> void:
	if value == clouds_cumulus_visible:
		return
	clouds_cumulus_visible = value
	sky_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_VISIBLE, value)
	

func set_clouds_cumulus_day_color(value: Color) -> void:
	if value == clouds_cumulus_day_color:
		return
	clouds_cumulus_day_color = value
	update_clouds_cumulus_day_color()
	

func update_clouds_cumulus_day_color() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_DAY_COLOR, clouds_cumulus_day_color)
	sky_material.set_shader_parameter(Sky3D.CLOUDS_DAY_COLOR, clouds_cumulus_day_color)


func set_clouds_cumulus_horizon_light_color(value: Color) -> void:
	if value == clouds_cumulus_horizon_light_color:
		return
	clouds_cumulus_horizon_light_color = value
	update_clouds_cumulus_horizon_light_color()


func update_clouds_cumulus_horizon_light_color() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_HORIZON_LIGHT_COLOR, clouds_cumulus_horizon_light_color)
	sky_material.set_shader_parameter(Sky3D.CLOUDS_HORIZON_LIGHT_COLOR, clouds_cumulus_horizon_light_color)


func set_clouds_cumulus_night_color(value: Color) -> void:
	if value == clouds_cumulus_night_color:
		return
	clouds_cumulus_night_color = value
	update_clouds_cumulus_night_color()


func update_clouds_cumulus_night_color() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_NIGHT_COLOR, clouds_cumulus_night_color)
	sky_material.set_shader_parameter(Sky3D.CLOUDS_NIGHT_COLOR, clouds_cumulus_night_color)


func set_clouds_cumulus_thickness(value: float) -> void:
	if value == clouds_cumulus_thickness:
		return
	clouds_cumulus_thickness = value
	update_clouds_cumulus_thickness()


func update_clouds_cumulus_thickness() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_THICKNESS, clouds_cumulus_thickness)


func set_clouds_cumulus_coverage(value: float) -> void:
	if value == clouds_cumulus_coverage:
		return
	clouds_cumulus_coverage = value
	update_clouds_cumulus_coverage()


func update_clouds_cumulus_coverage() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_COVERAGE, clouds_cumulus_coverage)


func set_clouds_cumulus_absorption(value: float) -> void:
	if value == clouds_cumulus_absorption:
		return
	clouds_cumulus_absorption = value
	update_clouds_cumulus_absorption()


func update_clouds_cumulus_absorption() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_ABSORPTION, clouds_cumulus_absorption)


func set_clouds_cumulus_noise_freq(value: float) -> void:
	if value == clouds_cumulus_noise_freq:
		return
	clouds_cumulus_noise_freq = value
	update_clouds_cumulus_noise_freq()


func update_clouds_cumulus_noise_freq() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_NOISE_FREQ, clouds_cumulus_noise_freq)


func set_clouds_cumulus_intensity(value: float) -> void:
	if value == clouds_cumulus_intensity:
		return
	clouds_cumulus_intensity = value
	update_clouds_cumulus_intensity()


func update_clouds_cumulus_intensity() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_INTENSITY, clouds_cumulus_intensity)


func set_clouds_cumulus_mie_intensity(value: float) -> void:
	if value == clouds_cumulus_mie_intensity:
		return
	clouds_cumulus_mie_intensity = value
	update_clouds_cumulus_mie_intensity()


func update_clouds_cumulus_mie_intensity() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_MIE_INTENSITY, clouds_cumulus_mie_intensity)


func set_clouds_cumulus_mie_anisotropy(value: float) -> void:
	if value == clouds_cumulus_mie_anisotropy:
		return
	clouds_cumulus_mie_anisotropy = value
	update_clouds_cumulus_mie_anisotropy()


func update_clouds_cumulus_mie_anisotropy() -> void:
	if !is_scene_built:
		return
	var partial: Vector3 = ScatterLib.get_partial_mie_phase(clouds_cumulus_mie_anisotropy)
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_PARTIAL_MIE_PHASE, partial)


func set_clouds_cumulus_size(value: float) -> void:
	if value == clouds_cumulus_size:
		return
	clouds_cumulus_size = value
	update_clouds_cumulus_size()


func update_clouds_cumulus_size() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_SIZE, clouds_cumulus_size)


func set_clouds_cumulus_direction(value: Vector3) -> void:
	if value == clouds_cumulus_direction:
		return
	clouds_cumulus_direction = value
	update_clouds_cumulus_direction()


func update_clouds_cumulus_direction() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_DIRECTION, clouds_cumulus_direction)


func set_clouds_cumulus_speed(value: float) -> void:
	if value == clouds_cumulus_speed:
		return
	clouds_cumulus_speed = value
	update_clouds_cumulus_speed()


func update_clouds_cumulus_speed() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_SPEED, clouds_cumulus_speed)


func _set_clouds_cumulus_texture(value: Texture2D) -> void:
	if value == clouds_cumulus_texture:
		return
	clouds_cumulus_texture = value
	update_clouds_cumulus_texture()
	

func update_clouds_cumulus_texture() -> void:
	if !is_scene_built:
		return
	clouds_cumulus_material.set_shader_parameter(Sky3D.CUMULUS_CLOUDS_TEXTURE, clouds_cumulus_texture)


#####################
## Environment
#####################

var __enable_environment: bool = false
var environment: Environment = null: set = set_environment


func set_environment(value: Environment) -> void:
	environment = value
	__enable_environment = true if environment != null else false
	if __enable_environment:
		__update_environment()


func __update_environment() -> void:
	if not __enable_environment or not __sun_light_node:
		return
	var factor: float = TOD_Math.saturate(-sun_direction().y + 0.60)
	var col: Color = TOD_Math.plerp_color(__sun_light_node.light_color, atm_night_tint * atm_night_intensity(), factor)
	col.a = 1.
	col.v = clamp(col.v, .35, 1.)
	environment.ambient_light_color = col
	


#####################
## Lighting
#####################

var __day: bool: get = is_day


func is_day() -> bool:
	return __day == true


func __set_day_state(v: float, threshold: float = 1.80) -> void:
	# Signal when day has changed to night and vice versa.
	if __day == true and abs(v) > threshold:
		__day = false
		emit_signal("day_night_changed", __day)
	elif __day == false and abs(v) <= threshold:
		__day = true
		emit_signal("day_night_changed", __day)
