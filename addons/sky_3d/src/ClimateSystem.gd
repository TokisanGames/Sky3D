@tool
extends Node3D

class_name ClimateSystem

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var version: String = "1.0"

@export_group("Assigns")
@export var sky_3d: Sky3D
@export var target: Node3D

#@export_group("Testing Climate")
#@export var force_weather_type: WeatherType = WeatherType.CLEAR : set = _set_force_weather
#@export var force_intensity: float = 0.5 : set = _set_force_intensity

@export_group("Testing Effects")
@export var force_effect_type: EffectType = EffectType.NONE : set = _set_force_effect
@export var force_quantity: float = 0.8 : set = _set_force_quantity


#enum WeatherType { 
    #CLEAR, 
    #SANDSTORM,
    #LIGHTLY_WINDY,
    #WINDY,
    #SNOW,
    #RAIN
#}

enum EffectType { 
    NONE,
    WINDY,
    SNOW,
    RAIN,
    DEBRIS,
    CLOUDS_NIMBUS,
    CLOUDS_CUMULUS,
    FOG
}

#var weather_type: WeatherType
var effect_type: EffectType
var intensity: float = 1.0
var duration: float
var start_time: float


@onready var move_timer: Timer 
@onready var cloud_timer: Timer

#var current_weather_active: WeatherType = WeatherType.CLEAR
var weather_transition_in_progress: bool = false

## RAIN STUFF
@onready var rain_particle: GPUParticles3D 
@onready var ripple_particle: GPUParticles3D
@onready var raining_sound: AudioStreamPlayer3D
var should_rain = false

@export_group("Rain Particles Amount")
@export var rain_full_show_time: float = 25.0
@export var rain_particle_amount: int = 8000
@export var ripple_particle_amount: int = 6000

## SNOW STUFF
@onready var snow_particle: GPUParticles3D 
@onready var snow_ripple_particle: GPUParticles3D

@export_group("Snow Particles Amount")
@export var snow_full_show_time: float = 25.0
@export var snow_particle_amount: int = 8000

## CLOUD STUFF
@onready var clouds_options
var random_nimbus_coverage: float = 0.3
var random_cumulus_coverage: float = 0.5
@export_group("Cloud Options")
@export var cloud_cumulus_coverage_time: float = 20.0
@export var cloud_nimbus_coverage_time: float = 10.0

## WINDY STUFF
# For this work, volumetric fog will be enabled
@export_group("Windy-Sandstorm Options")
@onready var windy_volume: FogVolume

@export var windy_direction: Vector3 = Vector3(7.0, 0.0, 7.0) : set = _set_force_windy_direction
@export var windy_density: float = 0.25 : set = _set_force_windy_density
@export var windy_noise_scale: float = 0.5 : set = _set_force_windy_noise_scale
@export var windy_color: Color = Color(0.93, 0.80, 0.76) : set = _set_force_windy_color
    
## DEBRIS STUFF
@onready var debris_particle: GPUParticles3D 
var debris_particle_amount: float = 10000


func _ready():
    if Engine.is_editor_hint():
        call_deferred("_build_scene")
    sky_3d = get_node("..")
    clouds_options = sky_3d.get_node("Skydome")

func _setup_rain() -> Node3D:
    var rain_node = Node3D.new()
    rain_node.name = "Rain"
    
    rain_particle = GPUParticles3D.new()
    rain_particle.name = "RainParticles"
    
    var rain_material = load("res://addons/sky_3d/assets/resources/rain_material.tres")
    var rain_process_material = load("res://addons/sky_3d/assets/resources/rain_process_material.tres")
    rain_particle.process_material = rain_process_material
    rain_particle.lifetime = 0.3
    rain_particle.fixed_fps = 60.0
    rain_particle.trail_enabled = true
    rain_particle.trail_lifetime = 0.1
    rain_particle.collision_base_size = 0.3
    rain_particle.amount = 2000 # temp
    rain_particle.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
    
    # Rain Mesh
    var ribbon_mesh = RibbonTrailMesh.new()
    ribbon_mesh.shape = RibbonTrailMesh.SHAPE_CROSS
    ribbon_mesh.size = 0.05
    ribbon_mesh.sections = 5
    ribbon_mesh.section_length = 0.1
    ribbon_mesh.section_segments = 3
    rain_particle.draw_pass_1 = ribbon_mesh
    rain_particle.draw_pass_1.surface_set_material(0, rain_material)
    
    # Ripple
    var ripple_material = load("res://addons/sky_3d/assets/resources/ripple_material.tres")
    var ripple_process_material = load("res://addons/sky_3d/assets/resources/ripple_process_material.tres")
    
    ripple_particle = GPUParticles3D.new()
    ripple_particle.name = "RippleParticles"
    ripple_particle.process_material = ripple_process_material
    ripple_particle.lifetime = 0.6
    ripple_particle.fixed_fps = 60.0
    ripple_particle.collision_base_size = 0.05
    ripple_particle.amount = 2000 # temp
    ripple_particle.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
   
    
    # Ripple Mesh
    var quad_mesh = QuadMesh.new()
    quad_mesh.size = Vector2(1.0, 1.0)
    quad_mesh.orientation = PlaneMesh.FACE_Y
    ripple_particle.draw_pass_1 = quad_mesh
    ripple_particle.draw_pass_1.surface_set_material(0, ripple_material)
    
    rain_node.add_child(rain_particle)
    rain_node.add_child(ripple_particle)
        
    rain_particle.sub_emitter = NodePath("../RippleParticles")
    
    ripple_particle.emitting = false
    rain_particle.emitting = false
    
    return rain_node
    

func _setup_snow() -> Node3D:
    var snow_node: Node3D = Node3D.new()
    snow_node.name = "Snow"
    
    var snow_material = load("res://addons/sky_3d/assets/resources/snow_material.tres")
    var snow_ground_material = load("res://addons/sky_3d/assets/resources/snow_ripple_material.tres")
    
    var snow_process_material = load("res://addons/sky_3d/assets/resources/snow_process_material.tres")
    var snow_ground_process_material = load("res://addons/sky_3d/assets/resources/snow_ground_process_material.tres")
    
    snow_particle = GPUParticles3D.new()
    snow_particle.name = "SnowParticles"
    snow_particle.process_material = snow_process_material
    snow_particle.lifetime = 5.0
    snow_particle.fixed_fps = 60.0
    snow_particle.collision_base_size = 0.1
    snow_particle.amount = 8000 # temp
    snow_particle.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
    
    snow_ripple_particle = GPUParticles3D.new()
    snow_ripple_particle.name = "SnowGround"
    snow_ripple_particle.process_material = snow_ground_process_material
    snow_ripple_particle.lifetime = 60.0
    snow_ripple_particle.fixed_fps = 60.0
    snow_ripple_particle.collision_base_size = 0.1
    snow_ripple_particle.amount = 8000 # temp
    snow_ripple_particle.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
    
    var quad_mesh_snow = QuadMesh.new()
    quad_mesh_snow.size = Vector2(0.15, 0.15)
    quad_mesh_snow.orientation = PlaneMesh.FACE_Z
    snow_particle.draw_pass_1 = quad_mesh_snow
    snow_particle.draw_pass_1.surface_set_material(0, snow_material)
    
    var quad_mesh_ground = QuadMesh.new()
    quad_mesh_ground.size = Vector2(0.15, 0.15)
    quad_mesh_ground.orientation = PlaneMesh.FACE_Y
    snow_ripple_particle.draw_pass_1 = quad_mesh_ground
    snow_ripple_particle.draw_pass_1.surface_set_material(0, snow_ground_material)
    
    snow_node.add_child(snow_particle)
    snow_node.add_child(snow_ripple_particle)
    
    snow_particle.emitting = false
    snow_ripple_particle.emitting = false
    
    snow_particle.sub_emitter = NodePath("../SnowGround")
    
    return snow_node
    
    
func _setup_debris() -> Node3D:
    var debris_node: Node3D = Node3D.new()
    debris_node.name = "Debris"
    var debris_material = load("res://addons/sky_3d/assets/resources/debris_material.tres")
    var debris_process_material = load("res://addons/sky_3d/assets/resources/debris_process_material.tres")
    
    debris_particle = GPUParticles3D.new()
    debris_particle.name = "DebrisParticles"
    debris_particle.process_material = debris_process_material
    debris_particle.lifetime = 1.0
    debris_particle.fixed_fps = 60.0
    debris_particle.randomness = 0.3
    debris_particle.amount = 6000 # temp
    debris_particle.visibility_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 50, 50))
    
    var quad_mesh = QuadMesh.new()
    quad_mesh.size = Vector2(0.1, 0.1)
    quad_mesh.orientation = PlaneMesh.FACE_Z
    debris_particle.draw_pass_1 = quad_mesh
    debris_particle.draw_pass_1.surface_set_material(0, debris_material)
    
    debris_node.add_child(debris_particle)
    
    debris_particle.emitting = false
    
    return debris_node


func _setup_sandstorm() -> Node3D:
    var sandstorm_node = Node3D.new()
    sandstorm_node.name = "Sandstorm"
    
    var sandstorm_material = load("res://addons/sky_3d/assets/resources/sandstorm_material.tres")
    
    windy_volume = FogVolume.new()
    windy_volume.size = Vector3(100.0, 100.0, 100.0)
    windy_volume.name = "WindyVolume"
    windy_volume.material = ShaderMaterial.new()
    windy_volume.material = sandstorm_material
    #windy_volume.transform.origin.y = 50
    
    sandstorm_node.add_child(windy_volume)
    
    return sandstorm_node


func _build_scene() -> void:  
    var sandstorm_node: Node3D = _setup_sandstorm()
    
    # Collision Height
    var collision_height: GPUParticlesCollisionHeightField3D = GPUParticlesCollisionHeightField3D.new()
    collision_height.name = "CollisionField"
    collision_height.size = Vector3(20, 20, 20)
    collision_height.transform.origin.y = 10
    
    # Rain
    var rain_node: Node3D = _setup_rain()
    
    # Snow
    var snow_node: Node3D = _setup_snow()
    
    # Debris
    var debris_node: Node3D = _setup_debris()
    
    var sounds_node: Node3D = Node3D.new()
    sounds_node.name = "Sounds"
    
    # a timeout to move the particles to the player
    # instead of frame by frame
    var move_timer: Timer = Timer.new()
    move_timer.name = "MoveTimer"
    move_timer.wait_time = 2.0
    move_timer.autostart = true
    
    ## TODO: change clouds randomly
    var clouds_timer: Timer = Timer.new()
    clouds_timer.name = "CloudsTimer"
    clouds_timer.wait_time = 600.0
    clouds_timer.autostart = true
    
    add_child(collision_height)
    add_child(sandstorm_node)
    add_child(rain_node)
    add_child(debris_node)
    add_child(snow_node)
    add_child(sounds_node)
    add_child(move_timer)
    add_child(clouds_timer)
    
    var scene_root = get_tree().edited_scene_root
    if scene_root:
        collision_height.owner = scene_root
        sandstorm_node.owner = scene_root
        for child in sandstorm_node.get_children():
            child.owner = scene_root
            
        rain_node.owner = scene_root
        for child in rain_node.get_children():
            child.owner = scene_root

        debris_node.owner = scene_root
        for child in debris_node.get_children():
            child.owner = scene_root
            
        snow_node.owner = scene_root
        for child in snow_node.get_children():
            child.owner = scene_root
        sounds_node.owner = scene_root
        move_timer.owner = scene_root
        clouds_timer.owner = scene_root
        

func _kill_all_tweens() -> void:
    var tweens = get_tree().get_processed_tweens()
    _default_effects_status()
    if tweens == null:
        return
    for tween in tweens:
        tween.kill() 

func _default_effects_status() -> void:
    # Func to reset effect status
    ### Rain
    #should_rain = false
    #rain_sound()
    #raining_sound.volume_db = -15.0
    #
    rain_particle.emitting = false
    rain_particle.amount_ratio = 0
    rain_particle.amount = rain_particle_amount
    
    ripple_particle.emitting = false
    # ripple is subemmiter, no change on amount_ratio needed
    ripple_particle.amount = rain_particle_amount

    ### Snow
    snow_particle.emitting = false
    snow_particle.amount_ratio = 0
    snow_particle.amount = snow_particle_amount
    
    snow_ripple_particle.emitting = false
    # ripple is subemmiter, no change on amount_ratio needed
    snow_ripple_particle.amount = snow_particle_amount
    
    ### Clouds
    clouds_options.set_clouds_coverage(0.3)
    clouds_options.set_clouds_cumulus_coverage(0.5)# = 0.5
    
    ### Debris
    debris_particle.emitting = false
    debris_particle.amount_ratio = 0
    debris_particle.amount = debris_particle_amount
    
    ### Windy
    sky_3d.environment.volumetric_fog_enabled = false
    windy_volume.visible = false
    windy_direction = Vector3(7.0, 0.0, 7.0)
    windy_density = 0.25
    windy_noise_scale = 0.5
    windy_color = Color(0.93, 0.80, 0.76)
    
    
#func _apply_editor_weather():
    #"""Future implementation"""
    #if not Engine.is_editor_hint():
        #return
    #
    #print("Aplicando clima no editor: ", force_weather_type, " com intensidade: ", force_intensity)
    #
    #match force_weather_type:
        #WeatherType.CLEAR:
            #weather_clear(force_intensity)
        #WeatherType.LIGHTLY_WINDY:
            #weather_lightly(force_intensity)
        #WeatherType.WINDY:
            #weather_windy(force_intensity)
        #WeatherType.SANDSTORM:
            #weather_sandstorm(force_intensity)


func _apply_editor_effects():
    """Aplica o clima selecionado no editor"""
    if not Engine.is_editor_hint():
        return

    match force_effect_type:
        EffectType.NONE:
            _kill_all_tweens()
        EffectType.WINDY:
            effect_windy(force_quantity)
        EffectType.SNOW:
            effect_snow(force_quantity)
        EffectType.RAIN:
            effect_rain(force_quantity)
        EffectType.DEBRIS:
            effect_debris(force_quantity)
        EffectType.CLOUDS_NIMBUS:
            effect_clouds_nimbus(force_quantity)
        EffectType.CLOUDS_CUMULUS:
            effect_clouds_cumulus(force_quantity)
        EffectType.FOG:
            effect_fog(force_quantity)
            
## Effects
func _set_force_windy_density(value : float):
    windy_density = value
    windy_volume.material.set_shader_parameter("density_mult", windy_density)

func _set_force_windy_direction(value : Vector3) -> void:
    windy_direction = value
    windy_volume.material.set_shader_parameter("movement_dir", windy_direction)

func _set_force_windy_noise_scale(value : float) -> void:
    windy_noise_scale = value
    windy_volume.material.set_shader_parameter("noise_scale", windy_noise_scale)
    
func _set_force_windy_color(value: Color) -> void:
    windy_color = value
    windy_volume.material.set_shader_parameter("albedo_color", windy_color)

func effect_windy(quantity: float) -> void:
    if Engine.is_editor_hint():
        _kill_all_tweens()
    windy_volume.visible = true
    sky_3d.environment.volumetric_fog_enabled = true
    sky_3d.environment.volumetric_fog_density = 0.0
    

func effect_snow(quantity: float) -> void:
    print("Snow effect is now on with intensity: ", quantity)
    
    if Engine.is_editor_hint():
        _kill_all_tweens()
    
    snow_particle.emitting = true
    snow_particle.visible = true
    snow_particle.amount = rain_particle_amount
    snow_ripple_particle.emitting = true
    snow_ripple_particle.visible = true
    snow_ripple_particle.amount = ripple_particle_amount
    snow_ripple_particle.amount_ratio = 1.0
    
    var tween_snow = create_tween()
    tween_snow.tween_property(
        snow_particle,
        "amount_ratio",
        1.0 * quantity,
        snow_full_show_time
    ).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT) 

    while tween_snow.is_running():
        print("Current visible rain drops: ", snow_particle.amount_ratio * snow_particle.amount )
        await get_tree().create_timer(1.0).timeout
        

func effect_rain(quantity: float) -> void:
    print("Rain effect is now on with intensity: ", quantity)
    
    if Engine.is_editor_hint():
        _kill_all_tweens()
    
    rain_particle.emitting = true
    rain_particle.visible = true
    rain_particle.amount = rain_particle_amount
    ripple_particle.emitting = true
    ripple_particle.visible = true
    ripple_particle.amount = ripple_particle_amount
    ripple_particle.amount_ratio = 1.0
    
    should_rain = true
    rain_sound()
    
    var tween_rain = create_tween()
    tween_rain.tween_property(
        rain_particle,
        "amount_ratio",
        1.0 * quantity,
        rain_full_show_time
    ).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT) 

    while tween_rain.is_running():
        print("Current visible rain drops: ", rain_particle.amount_ratio * rain_particle.amount )
        await get_tree().create_timer(1.0).timeout


func effect_clouds_nimbus(quantity: float) -> void:
    if Engine.is_editor_hint():
        _kill_all_tweens()
    # Tween para suavizar a cobertura das nuvens nimbus
    var tween_clouds_nimbus = create_tween()
    tween_clouds_nimbus.tween_property(
        clouds_options,
        "clouds_coverage",
        1.0 * quantity,  # Valor final
        cloud_nimbus_coverage_time  # Duração
    ).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
    

func effect_clouds_cumulus(quantity: float) -> void:
    if Engine.is_editor_hint():
        _kill_all_tweens()
    var tween_clouds = create_tween()
    tween_clouds.tween_property(
        clouds_options,
        "clouds_cumulus_coverage",
        1.0 * quantity,  # Valor final
        cloud_cumulus_coverage_time  # Duração
    ).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)


func effect_debris(quantity: float) -> void:
    print("Debris effect is now on with intensity: ", quantity)
    
    if Engine.is_editor_hint():
        _kill_all_tweens()
    
    debris_particle.emitting = true
    debris_particle.visible = true
    debris_particle.amount = debris_particle_amount
    
    var tween_debris = create_tween()
    tween_debris.tween_property(
        debris_particle,
        "amount_ratio",
        1.0 * quantity,
        rain_full_show_time
    ).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT) 


func effect_fog(quantity: float) -> void:
    # Sky3d fog
    # needs implementation
    if Engine.is_editor_hint():
        _kill_all_tweens()
    

## Sounds
func rain_sound():
    return
    if should_rain and raining_sound.is_stopped:
        raining_sound.play()
        
        var rain_sound_tween = create_tween()
        rain_sound_tween.tween_property(
        raining_sound,
        "volume_db",
        0.0,
        rain_full_show_time
        ).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT) 
    
    else:
        raining_sound.stop()


### Weather Forecast
#func weather_clear(intesity: float) -> void:
    ## Few or no clouds, light or no wind
    #pass
#
#func weather_lightly(intesity: float) -> void:
    ## Few clouds, light wind, maybe rain or light snow
    ## little or no debris
    #pass
    #
#func weather_windy(intesity: float) -> void:
    ## Moderate to strong wind, maybe medium rain or snow
    ## Moderate debris
    #pass
    #
#func weather_sandstorm(intesity: float) -> void:
    ## Sandstorm, moderate to strong wind
    ## lots of debris
    #pass


## SETTERS EFFECTS EDITOR
func _set_force_effect(value: EffectType):
    force_effect_type = value
    print("force_effect_type: ", force_effect_type)
    if Engine.is_editor_hint():
        _apply_editor_effects()

func _set_force_quantity(value: float):
    force_quantity = clamp(value, 0.0, 1.0)
    print("force_quantity:", force_quantity)
    if Engine.is_editor_hint():
        _apply_editor_effects()





## SETTERS WEATHER EDITOR
#func _set_force_weather(value: WeatherType):
    #pass
#
#
#func _set_force_intensity(value: float):
    #force_intensity = clamp(value, 0.0, 1.0)
    #if Engine.is_editor_hint():
        #_apply_editor_weather()
