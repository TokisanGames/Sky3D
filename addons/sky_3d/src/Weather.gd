@tool
extends Node3D

class_name Weather

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var version: String = "1.0"

@export_group("Assigns")
@export var sky_3d: Sky3D
@export var target: Node3D

@export_group("Testing Effects")
@export var force_effect_type: EffectType = EffectType.NONE : set = _set_force_effect
@export var force_quantity: float = 0.8 : set = _set_force_quantity

var affected_surfaces = []

enum EffectType { 
    NONE,
    RAIN,
    SNOW,
    DEBRIS
}

# Estrutura de dados para configurar cada tipo de partícula
class ParticleConfig:
    var name: String
    var material_path: String
    var process_material_path: String
    var lifetime: float
    var amount: int
    var mesh_size: Vector2
    var mesh_orientation: int
    var visibility_aabb: AABB
    var collision_base_size: float
    var has_trails: bool = false
    var trail_lifetime: float = 0.0
    var has_sub_emitter: bool = false
    var sub_emitter_config: ParticleConfig = null
    var fixed_fps: float = 60.0
    var randomness: float = 0.0
    
    func _init(
        p_name: String,
        p_material: String, 
        p_process_material: String,
        p_lifetime: float,
        p_amount: int,
        p_mesh_size: Vector2,
        p_mesh_orientation: int,
        p_visibility_aabb: AABB,
        p_collision_base_size: float
    ):
        name = p_name
        material_path = p_material
        process_material_path = p_process_material
        lifetime = p_lifetime
        amount = p_amount
        mesh_size = p_mesh_size
        mesh_orientation = p_mesh_orientation
        visibility_aabb = p_visibility_aabb
        collision_base_size = p_collision_base_size

var effect_type: EffectType
var intensity: float = 1.0
var duration: float
var start_time: float

var weather_transition_in_progress: bool = false
var should_rain = false

@export_group("Rain Particles Amount")
@export var surface_wetness: float = 0.3
@export var rain_full_show_time: float = 25.0
@export var rain_particle_amount: int = 8000
@export var ripple_particle_amount: int = 6000

@export_group("Snow Particles Amount")
@export var snow_full_show_time: float = 25.0
@export var snow_particle_amount: int = 8000

@export_group("Debris Particles Amount")
@export var debris_particle_amount: int = 6000

# Cache para nós de partículas criados dinamicamente
var particle_nodes: Dictionary = {}
var particle_configs: Dictionary = {}

# Referências para compatibilidade (criadas dinamicamente)
var rain_particle: GPUParticles3D 
var ripple_particle: GPUParticles3D
var snow_particle: GPUParticles3D 
var snow_ripple_particle: GPUParticles3D
var debris_particle: GPUParticles3D


func _ready():
    if Engine.is_editor_hint():
        call_deferred("_setup_base_scene")
   
    _setup_particle_configs()
    sky_3d = get_node("..")
    

func _setup_particle_configs():
    """Configura todas as definições de partículas"""
    
    # Raain
    var rain_config = ParticleConfig.new(
        "RainParticles",
        "res://addons/sky_3d/assets/resources/rain_material.tres",
        "res://addons/sky_3d/assets/resources/rain_process_material.tres",
        0.3,
        rain_particle_amount,
        Vector2(0.05, 0.05),
        PlaneMesh.FACE_Z,
        AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20)),
        0.3
    )
    rain_config.has_trails = true
    rain_config.trail_lifetime = 0.1
    rain_config.has_sub_emitter = true
    
    # Rain ripple(sub-emitter)
    var ripple_config = ParticleConfig.new(
        "RippleParticles",
        "res://addons/sky_3d/assets/resources/ripple_material.tres",
        "res://addons/sky_3d/assets/resources/ripple_process_material.tres",
        0.6,
        ripple_particle_amount,
        Vector2(1.0, 1.0),
        PlaneMesh.FACE_Y,
        AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20)),
        0.05
    )
    
    rain_config.sub_emitter_config = ripple_config
    
    # Snow
    var snow_config = ParticleConfig.new(
        "SnowParticles",
        "res://addons/sky_3d/assets/resources/snow_material.tres",
        "res://addons/sky_3d/assets/resources/snow_process_material.tres",
        5.0,
        snow_particle_amount,
        Vector2(0.15, 0.15),
        PlaneMesh.FACE_Z,
        AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20)),
        0.1
    )
    snow_config.has_sub_emitter = true
    
    # Snow ripple (sub-emitter)
    var snow_ground_config = ParticleConfig.new(
        "SnowGround",
        "res://addons/sky_3d/assets/resources/snow_ripple_material.tres",
        "res://addons/sky_3d/assets/resources/snow_ground_process_material.tres",
        60.0,
        snow_particle_amount,
        Vector2(0.15, 0.15),
        PlaneMesh.FACE_Y,
        AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20)),
        0.1
    )
    
    snow_config.sub_emitter_config = snow_ground_config
    
    # Custom Texture
    var debris_config = ParticleConfig.new(
        "DebrisParticles",
        "res://addons/sky_3d/assets/resources/debris_material.tres",
        "res://addons/sky_3d/assets/resources/debris_process_material.tres",
        1.0,
        debris_particle_amount,
        Vector2(0.1, 0.1),
        PlaneMesh.FACE_Z,
        AABB(Vector3(-25, -25, -25), Vector3(50, 50, 50)),
        0.1
    )
    debris_config.randomness = 0.3
    
    # Armazena as configurações
    particle_configs["rain"] = rain_config
    particle_configs["snow"] = snow_config
    particle_configs["debris"] = debris_config


func _create_particle_system(config: ParticleConfig) -> GPUParticles3D:
    """Cria um sistema de partículas baseado na configuração"""
    var particle = GPUParticles3D.new()
    particle.name = config.name
    
    # Carrega materiais
    if ResourceLoader.exists(config.material_path):
        var material = load(config.material_path)
        var process_material = load(config.process_material_path)
        
        particle.process_material = process_material
        particle.lifetime = config.lifetime
        particle.fixed_fps = config.fixed_fps
        particle.collision_base_size = config.collision_base_size
        particle.amount = config.amount
        particle.visibility_aabb = config.visibility_aabb
        particle.emitting = false
        particle.amount_ratio = 0.0
        
        if config.randomness > 0:
            particle.randomness = config.randomness
        
        # Configurações específicas
        if config.has_trails:
            particle.trail_enabled = true
            particle.trail_lifetime = config.trail_lifetime
        
        # Cria a mesh
        var mesh = _create_mesh_for_particle(config)
        particle.draw_pass_1 = mesh
        particle.draw_pass_1.surface_set_material(0, material)
    
    return particle


func _create_mesh_for_particle(config: ParticleConfig) -> Mesh:
    """Cria a mesh apropriada baseada na configuração"""
    if config.has_trails:
        var ribbon_mesh = RibbonTrailMesh.new()
        ribbon_mesh.shape = RibbonTrailMesh.SHAPE_CROSS
        ribbon_mesh.size = config.mesh_size.x
        ribbon_mesh.sections = 5
        ribbon_mesh.section_length = 0.1
        ribbon_mesh.section_segments = 3
        return ribbon_mesh
    else:
        var quad_mesh = QuadMesh.new()
        quad_mesh.size = config.mesh_size
        quad_mesh.orientation = config.mesh_orientation
        return quad_mesh


func _create_and_play_effect(effect_name: String, intensity: float, duration: float = 25.0):
    """Create the effect in runtime"""
    
    # Remove efeito anterior se existir
    if particle_nodes.has(effect_name):
        var old_node = particle_nodes[effect_name]
        old_node.queue_free()
        particle_nodes.erase(effect_name)
    
    if not particle_configs.has(effect_name):
        push_error("Configuração não encontrada para: " + effect_name)
        return
    
    var config = particle_configs[effect_name]
    var container_node = Node3D.new()
    container_node.name = effect_name.capitalize()
    
    # Cria partícula principal
    var main_particle = _create_particle_system(config)
    container_node.add_child(main_particle)
    
    # Cria sub-emitter se necessário
    if config.has_sub_emitter and config.sub_emitter_config:
        var sub_particle = _create_particle_system(config.sub_emitter_config)
        container_node.add_child(sub_particle)
        main_particle.sub_emitter = NodePath("../" + config.sub_emitter_config.name)
    
    # Adiciona ao nó weather
    add_child(container_node)
    
    # Se estiver no editor, define owner
    if Engine.is_editor_hint():
        var scene_root = get_tree().edited_scene_root
        if scene_root:
            container_node.owner = scene_root
            for child in container_node.get_children():
                child.owner = scene_root
    
    # Atualiza referências para compatibilidade
    _update_particle_references(effect_name, container_node)
    
    particle_nodes[effect_name] = container_node
    
    print(effect_name.capitalize() + " effect created and playing with intensity: ", intensity)
    
    # INICIA O EFEITO IMEDIATAMENTE
    _start_particle_effect(container_node, intensity, duration)


func _start_particle_effect(container_node: Node3D, intensity: float, duration: float):
    """Inicia o efeito de partículas imediatamente após criar"""
    
    # Ativa todas as partículas do container
    for child in container_node.get_children():
        if child is GPUParticles3D:
            child.emitting = true
            child.visible = true
            child.amount_ratio = intensity
    
    # Anima a partícula principal
    var main_particle = container_node.get_child(0) as GPUParticles3D
    if main_particle:
        var tween = create_tween()
        tween.tween_property(
            main_particle,
            "amount_ratio",
            intensity,
            duration
        ).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)

    #_apply_wet_shader_to_surfaces(container_node.name.to_lower(), intensity)
    _apply_wet_effect_simple(container_node.name.to_lower(), intensity)


func _find_mesh_instances(node: Node, mesh_instances: Array):
    if node is MeshInstance3D:
        mesh_instances.append(node)
    for child in node.get_children():
        _find_mesh_instances(child, mesh_instances)


func _get_material(mesh_instance: MeshInstance3D, surface_idx: int) -> Material:
    # 1. Surface override 
    var mat: Material = mesh_instance.get_surface_override_material(surface_idx)
    if mat != null:
        return mat
    
    # 2. Mesh
    if mesh_instance.mesh:
        mat = mesh_instance.mesh.surface_get_material(surface_idx)
        if mat != null:
            return mat
    
    # 3. override GeometryInstance3D
    mat = mesh_instance.material_override
    if mat != null:
        return mat
    
    return null


func _apply_wet_effect_simple(effect_name: String, intensity: float):
    if effect_name != "rain":
        return
    
    if not affected_surfaces is Dictionary:
        affected_surfaces = {}
    
    var mesh_instances: Array = []
    var nodes = get_tree().get_nodes_in_group("wet_surfaces")
    _find_mesh_instances(self, mesh_instances)
    
    for node in nodes:
        _find_mesh_instances(node, mesh_instances)

    for mesh_instance in mesh_instances:
        if mesh_instance is MeshInstance3D and mesh_instance.mesh:
            var surface_count = mesh_instance.mesh.get_surface_count()
            
            if not mesh_instance in affected_surfaces:
                affected_surfaces[mesh_instance] = []
            
            for surface_idx in range(surface_count):
                var mat: Material = _get_material(mesh_instance, surface_idx)
                
                affected_surfaces[mesh_instance].append(mat.roughness)
                mat.roughness = surface_wetness
                print("affected_surfaces: ", affected_surfaces)
                print("mat.roughness: ", mat.roughness)



func _restore_original_materials():
    for mesh_instance in affected_surfaces.keys():
        if not is_instance_valid(mesh_instance):
            continue
        
        var original_roughness_array: Array = affected_surfaces[mesh_instance]
        var surface_count = mesh_instance.mesh.get_surface_count()
        
        for surface_idx in range(surface_count):
            var mat: Material = _get_material(mesh_instance, surface_idx)
            if mat == null:
                continue
            
            if mat is StandardMaterial3D or mat is ORMMaterial3D:
                if surface_idx < original_roughness_array.size():
                    mat.roughness = original_roughness_array[surface_idx]

    affected_surfaces.clear()



func _update_particle_references(effect_name: String, container_node: Node3D):
    """Atualiza as referências para manter compatibilidade com código existente"""
    match effect_name:
        "rain":
            rain_particle = container_node.get_node("RainParticles")
            ripple_particle = container_node.get_node("RippleParticles")
        "snow":
            snow_particle = container_node.get_node("SnowParticles")
            snow_ripple_particle = container_node.get_node("SnowGround")
        "debris":
            debris_particle = container_node.get_node("DebrisParticles")


func _setup_base_scene() -> void:  
    """Cria apenas a estrutura base - partículas serão criadas sob demanda"""
    
    # Collision Height para partículas
    var collision_height: GPUParticlesCollisionHeightField3D = GPUParticlesCollisionHeightField3D.new()
    collision_height.name = "CollisionField"
    collision_height.size = Vector3(20, 20, 20)
    collision_height.transform.origin.y = 10
    
    var sounds_node: Node3D = Node3D.new()
    sounds_node.name = "Sounds"
    
    add_child(collision_height)
    add_child(sounds_node)
    
    var scene_root = get_tree().edited_scene_root
    if scene_root:
        collision_height.owner = scene_root
        sounds_node.owner = scene_root


func _clear_all_effects():
    """Remove todos os efeitos ativos"""
    for effect_name in particle_nodes.keys():
        var node = particle_nodes[effect_name]
        if is_instance_valid(node):
            node.queue_free()
    
    particle_nodes.clear()
    
    # Limpa referências
    rain_particle = null
    ripple_particle = null
    snow_particle = null
    snow_ripple_particle = null
    debris_particle = null


func _apply_editor_effects():
    """Aplica o clima selecionado no editor - CRIA E TOCA NA HORA"""
    if not Engine.is_editor_hint():
        return

    _clear_all_effects()
    _restore_original_materials()

    match force_effect_type:
        EffectType.NONE:
            pass # Já limpou tudo
        EffectType.RAIN:
            effect_rain(force_quantity)
        EffectType.SNOW:
            effect_snow(force_quantity)
        EffectType.DEBRIS:
            effect_debris(force_quantity)


## Funções de efeitos simplificadas - CRIAM E TOCAM IMEDIATAMENTE
func effect_rain(quantity: float) -> void:
    _create_and_play_effect("rain", quantity, rain_full_show_time)
    should_rain = true

func effect_snow(quantity: float) -> void:
    _create_and_play_effect("snow", quantity, snow_full_show_time)

func effect_debris(quantity: float) -> void:
    _create_and_play_effect("debris", quantity, rain_full_show_time)

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
