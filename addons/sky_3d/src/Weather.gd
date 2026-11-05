@tool
extends Node3D

class_name Weather

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var version: String = "1.0"

@export_group("Assigns")
## Sky3D plugin
@export var sky_3d: Sky3D
## The effect box will follow your player.
@export var target: Node3D

enum EffectType {
	CLEAR,
	RAIN,
	SNOW,
	CUSTOM
}

class ParticleConfig:
	var name: String
	var material_path: StandardMaterial3D
	var process_material_path: ParticleProcessMaterial
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
		p_material: StandardMaterial3D, 
		p_process_material: ParticleProcessMaterial,
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

@export_group("Rain Particles Config")
@export var rain_full_show_time: float = 25.0
@export var rain_particle_amount: int = 10000
@export var ripple_particle_amount: int = 10000

@export var rain_material: StandardMaterial3D = preload("res://addons/sky_3d/assets/resources/rain_material.tres")
@export var rain_process_material: ParticleProcessMaterial = preload("res://addons/sky_3d/assets/resources/rain_process_material.tres")
@export var ripple_material: StandardMaterial3D = preload("res://addons/sky_3d/assets/resources/ripple_material.tres")
@export var ripple_process_material: ParticleProcessMaterial = preload("res://addons/sky_3d/assets/resources/ripple_process_material.tres")
@export var rain_sound: AudioStream = preload("res://addons/sky_3d/assets/thirdparty/sounds/rain_loop.ogg")
## Straight down. Restored into rain_process_material.direction when the weather is cleared.
var default_rain_direction : Vector3 = Vector3(0.0, -1.0, 0.0)

@export_group("Lightning Config")
@export var lightning_enabled: bool = true
@export var lightning_min_interval: float = 30.0
@export var lightning_max_interval: float = 60.0
@export var lightning_flash_duration: float = 0.1
@export var lightning_fade_duration: float = 0.4
@export var lightning_intensity: float = 16.0
@export var lightning_sound: AudioStream = preload("res://addons/sky_3d/assets/thirdparty/sounds/lightning.mp3")

var lightning_timer: Timer
var original_exposure: float
# Everything below has to be reachable from _stop_lightning(), or a strike already in flight
# outlives the effect that spawned it.
var _lightning_delay_timer: Timer
var _lightning_tween: Tween
var _lightning_property: String = ""
var _lightning_audio_players: Array[AudioStreamPlayer3D] = []

@export_group("Snow Particles Config")
@export var snow_full_show_time: float = 25.0
@export var snow_particle_amount: int = 10000
@export var snow_material: StandardMaterial3D = preload("res://addons/sky_3d/assets/resources/snow_material.tres")
@export var snow_process_material: ParticleProcessMaterial = preload("res://addons/sky_3d/assets/resources/snow_process_material.tres")

@onready var snow_ground_material: StandardMaterial3D = preload("res://addons/sky_3d/assets/resources/snow_ripple_material.tres")
@onready var snow_p_ground_material: ParticleProcessMaterial = preload("res://addons/sky_3d/assets/resources/snow_ground_process_material.tres")
@export var snow_sound: AudioStream = preload("res://addons/sky_3d/assets/thirdparty/sounds/windy.mp3")
## Snow is wind-driven through gravity, not direction, so this restores gravity when cleared.
var default_snow_gravity : Vector3 = Vector3(0.0, -9.8, 0.0)

@export_group("Custom Particles Config")
@export var custom_particle_amount: int = 6000

@export var custom_material: StandardMaterial3D = preload("res://addons/sky_3d/assets/resources/debris_material.tres")
@export var custom_process_material: ParticleProcessMaterial = preload("res://addons/sky_3d/assets/resources/debris_process_material.tres")
@export var custom_sound: AudioStream = null
## Straight down. The debris material's own gravity of (1,1,1) is left untouched.
var default_custom_direction : Vector3 = Vector3(0.0, -1.0, 0.0)

@export_group("General")
## Size of the volume particles spawn in, always centred on this node. Drives the emission box of
## every effect and the size of the ground collision field.[br][br]
## [b]Note:[/b] density is particle count divided by volume, and volume grows with the cube of this.
## Doubling it needs roughly 8x the particle count to look the same.
@export var effect_box_size: Vector3 = Vector3(20, 20, 20) :
	set(value):
		effect_box_size = value.abs()
		# Guarded because property setters also fire during construction and scene load, in
		# declaration order, when the other members and the child nodes don't exist yet.
		if is_node_ready():
			_apply_effect_box()

## Culling box size, as a multiple of [member effect_box_size]. This only controls when Godot skips
## drawing a system entirely -- it never changes which particles exist. Since the effect follows the
## player it is rarely off-screen anyway, so prefer too large: too small makes the whole effect pop
## out of view when the box leaves the frustum.
@export_range(1.0, 4.0, 0.1) var visibility_margin: float = 2.0 :
	set(value):
		visibility_margin = maxf(value, 1.0)
		if is_node_ready():
			_apply_effect_box()

## Shifts the ground collision field downward, as a fraction of [member effect_box_size].y.[br][br]
## The effect box is centred on the target, but the ground is always [i]below[/i] it, so a centred
## collision field wastes half its height on empty air above the player and stops finding ground as
## soon as the drop exceeds half the box. At the default 0.25 with a 20-unit box the field spans
## 15 units below the target and 5 above. Use 0.5 to put it entirely below; 0.0 to centre it.
@export_range(0.0, 0.5, 0.05) var collision_field_bias: float = 0.25 :
	set(value):
		collision_field_bias = clampf(value, 0.0, 0.5)
		if is_node_ready():
			_apply_effect_box()

## Update interval to move the effect to follow the player
@export_range(0.016, 1.0) var update_interval: float = 0.1

@export_group("Debug")
## Prints particle counts as effects are built, and warns about GPUParticles3D nodes that were
## saved into the scene rather than created at runtime.
@export var debug_particles: bool = false

var particle_nodes: Dictionary = {}
var particle_configs: Dictionary = {}
var audio_players: Dictionary = {}

var rain_particle: GPUParticles3D 
var ripple_particle: GPUParticles3D
var snow_particle: GPUParticles3D 
var snow_ripple_particle: GPUParticles3D
var custom_particle: GPUParticles3D

# Signals
## Emitted when an effect starts. 'effect_name' is the string key ("rain", "snow", "custom"),
## matching what _create_and_play_effect() emits -- not the EffectType enum.
signal weather_changed(effect_name: String, intensity: float)


func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("_setup_base_scene")

	_setup_timers()
	_setup_particle_configs()
	_setup_lightning_timer()
	# The only place this runs during startup: by now every member and child node exists.
	_apply_effect_box()

	# Only fall back to the parent if the export wasn't assigned in the inspector.
	if sky_3d == null:
		sky_3d = get_parent() as Sky3D

	weather_changed.connect(_on_weather_changed)
	
	# Debug: 
	#print("Rain Process Material: ", rain_process_material)
	#print("Snow Process Material: ", snow_process_material)
	#print("Custom Process Material: ", custom_process_material)
	# Debug: Test
	#change_weather("rain", 25.0, 1.0, 35.0, true)


func _debug(msg: String) -> void:
	if debug_particles:
		print("[Weather] ", msg)


## Prints the live particle count of every GPUParticles3D under this node, whether it was created at
## runtime or saved into the scene. 'effective' is what actually spawns: amount * amount_ratio.
## Call this from anywhere, e.g. from the remote scene tree or a debug key.
func debug_report_particles() -> void:
	var runtime_containers: Array = particle_nodes.values()
	print("[Weather] --- particle report ---")
	for container in get_children():
		for particle in container.get_children():
			if not particle is GPUParticles3D:
				continue
			# Runtime effects are tracked in particle_nodes; anything else under this node came from
			# the .tscn, which means a preview effect got saved into the scene.
			var origin: String = "runtime" if runtime_containers.has(container) else "SCENE-BAKED"
			print("[Weather]   %-14s %-16s amount=%-7d ratio=%.2f effective=%-7d emitting=%s [%s]" % [
				container.name, particle.name, particle.amount, particle.amount_ratio,
				int(particle.amount * particle.amount_ratio), str(particle.emitting), origin
			])
	print("[Weather] --- end report ---")


func _update_position():
	if target != null:
		self.global_position = target.global_position


func _setup_timers():
	# Reuse an existing timer so repeat calls don't stack up duplicates all driving _update_position.
	var move_timer: Timer = get_node_or_null("MoveTimer")
	if move_timer == null:
		move_timer = Timer.new()
		move_timer.name = "MoveTimer"
		add_child(move_timer)

	move_timer.wait_time = update_interval
	move_timer.one_shot = false
	if not move_timer.timeout.is_connected(_update_position):
		move_timer.timeout.connect(_update_position)
	move_timer.start()


## The culling box: the spawn volume grown by [member visibility_margin], centred on this node.
func get_visibility_aabb() -> AABB:
	var padded: Vector3 = effect_box_size * visibility_margin
	return AABB(-padded * 0.5, padded)


# Pushes the box size onto everything derived from it. Call only once the node is ready -- the
# property setters that also call this are guarded on is_node_ready() for that reason.
func _apply_effect_box() -> void:
	# emission_box_extents are half-extents, so a 20-unit box is extents of 10. Getting this wrong
	# is what made rain spawn into 8x the volume of snow at the same particle count.
	var extents: Vector3 = effect_box_size * 0.5
	for material in [rain_process_material, snow_process_material, custom_process_material]:
		if material:
			material.emission_box_extents = extents
			# The .tres used to carry a separate scale factor that multiplied on top of the extents.
			material.emission_shape_scale = Vector3.ONE

	# Sub-emitters spawn at their parent's collision point, so their emission shape is unused.

	var collision_field: GPUParticlesCollisionHeightField3D = get_node_or_null("CollisionField")
	if collision_field:
		collision_field.size = effect_box_size
		# Local offset, so it survives the node following the target every update_interval.
		collision_field.position.y = -effect_box_size.y * collision_field_bias

	var culling_box: AABB = get_visibility_aabb()
	for container in get_children():
		for particle in container.get_children():
			if particle is GPUParticles3D:
				particle.visibility_aabb = culling_box


func _setup_particle_configs() -> void:
	# Rain
	var rain_config = ParticleConfig.new(
		"RainParticles",
		rain_material,
		rain_process_material,
		0.3,
		rain_particle_amount,
		Vector2(0.05, 0.05),
		PlaneMesh.FACE_Z,
		get_visibility_aabb(),
		0.3
	)
	rain_config.has_trails = true
	rain_config.trail_lifetime = 0.1
	rain_config.has_sub_emitter = true
	
	# Rain ripple(sub-emitter)
	var ripple_config = ParticleConfig.new(
		"RippleParticles",
		ripple_material,
		ripple_process_material,
		0.25,
		ripple_particle_amount,
		Vector2(1.0, 1.0),
		PlaneMesh.FACE_Y,
		get_visibility_aabb(),
		0.05
	)
	
	rain_config.sub_emitter_config = ripple_config
	
	# Snow
	var snow_config = ParticleConfig.new(
		"SnowParticles",
		snow_material,
		snow_process_material,
		5.0,
		snow_particle_amount,
		Vector2(0.05, 0.05),
		PlaneMesh.FACE_Z,
		get_visibility_aabb(),
		0.1
	)
	snow_config.has_sub_emitter = true
	
	# Snow ripple (sub-emitter)
	var snow_ground_config = ParticleConfig.new(
		"SnowGround",
		snow_ground_material,
		snow_p_ground_material,
		60.0,
		snow_particle_amount,
		Vector2(0.1, 0.1),
		PlaneMesh.FACE_Y,
		get_visibility_aabb(),
		0.1
	)
	
	snow_config.sub_emitter_config = snow_ground_config
	
	# Custom Texture
	var custom_config = ParticleConfig.new(
		"CustomParticles",
		custom_material,
		custom_process_material,
		1.0,
		custom_particle_amount,
		Vector2(0.1, 0.1),
		PlaneMesh.FACE_Z,
		get_visibility_aabb(),
		0.1
	)
	custom_config.randomness = 0.3
	
	particle_configs["rain"] = rain_config
	particle_configs["snow"] = snow_config
	particle_configs["custom"] = custom_config

	_debug("export values -> rain=%d ripple=%d snow=%d custom=%d" % [
		rain_particle_amount, ripple_particle_amount, snow_particle_amount, custom_particle_amount
	])


func _create_particle_system(config: ParticleConfig) -> GPUParticles3D:
	var particle = GPUParticles3D.new()
	particle.name = config.name

	var material = config.material_path
	var process_material = config.process_material_path
	  
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
	
	if config.has_trails:
		particle.trail_enabled = true
		particle.trail_lifetime = config.trail_lifetime
	
	var mesh = _create_mesh_for_particle(config)
	particle.draw_pass_1 = mesh
	particle.draw_pass_1.surface_set_material(0, material)

	_debug("built '%s' -> amount=%d (from config.amount=%d)" % [config.name, particle.amount, config.amount])

	return particle


func _create_mesh_for_particle(config: ParticleConfig) -> Mesh:
	if config.has_trails:
		var ribbon_mesh = RibbonTrailMesh.new()
		ribbon_mesh.shape = RibbonTrailMesh.SHAPE_CROSS
		ribbon_mesh.size = config.mesh_size.x
		ribbon_mesh.sections = 2
		ribbon_mesh.section_length = 0.05
		ribbon_mesh.section_segments = 1
		return ribbon_mesh
	else:
		var quad_mesh = QuadMesh.new()
		quad_mesh.size = config.mesh_size
		quad_mesh.orientation = config.mesh_orientation
		return quad_mesh


func _create_and_play_effect(effect_name: String, intensity: float, lightning_enabled: bool, t_full_effect: float = 25.0, duration: float = 0) -> void:
	"""Create the effect in runtime"""
	if particle_nodes.has(effect_name):
		var old_node = particle_nodes[effect_name]
		old_node.queue_free()
		particle_nodes.erase(effect_name)
	
	if audio_players.has(effect_name):
		var old_audio = audio_players[effect_name]
		if is_instance_valid(old_audio):
			old_audio.queue_free()
		audio_players.erase(effect_name)
	
	if not particle_configs.has(effect_name):
		push_error("No config found for the effect: " + effect_name)
		return
	
	_setup_particle_configs()
	
	var config = particle_configs[effect_name]
	var container_node = Node3D.new()
	container_node.name = effect_name.capitalize()
	
	var main_particle = _create_particle_system(config)
	container_node.add_child(main_particle)
	
	if config.has_sub_emitter and config.sub_emitter_config:
		var sub_particle = _create_particle_system(config.sub_emitter_config)
		container_node.add_child(sub_particle)
		main_particle.sub_emitter = NodePath("../" + config.sub_emitter_config.name)
	
	add_child(container_node)
	
	var audio_stream = _get_audio_for_effect(effect_name)
	if audio_stream:
		var audio_player = _create_audio_player(effect_name, audio_stream)
		if audio_player:
			audio_players[effect_name] = audio_player
	
	# Deliberately no owner assignment: an owned node gets serialized into the .tscn when the user
	# saves, so editor previews used to be baked into the scene and then respawned alongside the
	# runtime ones. Unowned nodes still render in the viewport, they just aren't saved.

	if effect_name == "rain":
		should_rain = true
		if lightning_enabled:
			# Held in a member so _stop_lightning() can cancel it. As a local it survived the effect
			# being stopped and then started lightning with no rain in the scene.
			if _lightning_delay_timer and is_instance_valid(_lightning_delay_timer):
				_lightning_delay_timer.queue_free()
			_lightning_delay_timer = Timer.new()
			_lightning_delay_timer.name = "LightningDelayTimer"
			_lightning_delay_timer.wait_time = 2.0
			_lightning_delay_timer.one_shot = true
			_lightning_delay_timer.timeout.connect(_start_lightning)
			add_child(_lightning_delay_timer)
			_lightning_delay_timer.start()
	
	_update_particle_references(effect_name, container_node)
	
	particle_nodes[effect_name] = container_node
	
	weather_changed.emit(effect_name, intensity)

	_start_particle_effect(container_node, intensity, t_full_effect, duration)

	if debug_particles:
		debug_report_particles()


func _start_particle_effect(container_node: Node3D, intensity: float, t_full_effect: float, duration: float = 0) -> void:
	var particles: Array[GPUParticles3D] = []
	for child in container_node.get_children():
		if child is GPUParticles3D:
			child.emitting = true
			child.visible = true

	var main_particle = container_node.get_child(0) as GPUParticles3D
	if main_particle:
		var tween = create_tween()
		tween.tween_property(
			main_particle,
			"amount_ratio",
			intensity,
			t_full_effect
		).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
		particles.append(main_particle)

	# 'custom' has no sub-emitter, so get_child(1) would be out of bounds.
	var sub_emmiter = container_node.get_child(1) if container_node.get_child_count() > 1 else null
	if sub_emmiter is GPUParticles3D:
		var tween_sub = create_tween()
		tween_sub.tween_property(
			sub_emmiter,
			"amount_ratio",
			intensity,
			t_full_effect
		).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
		particles.append(sub_emmiter)
		
	var effect_name = container_node.name.to_lower()
	if audio_players.has(effect_name):
		var audio_player = audio_players[effect_name]
		audio_player.play()
		
		var audio_tween = create_tween()
		audio_tween.tween_property(
			audio_player,
			"volume_db",
			0.0,
			t_full_effect * 0.3 
		).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	if duration > 0:
		if duration < t_full_effect:
			duration = t_full_effect
		var effect_duration = Timer.new()
		effect_duration.name = "effect_duration"
		add_child(effect_duration)
		effect_duration.wait_time = duration
		effect_duration.one_shot = true
		effect_duration.timeout.connect(
			Callable(self, "_on_timeout_fade_effects").bind(particles, t_full_effect)
		)
		effect_duration.start()


func _on_timeout_fade_effects(particles: Array[GPUParticles3D], t_full_effect:float) -> void:
	for particle in particles:
		if particle:
			var new_tween = create_tween()
			new_tween.tween_property(
				particle,
				"amount_ratio",
				0.0,
				t_full_effect 
			).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	
	var timer = get_node_or_null("effect_duration") 
	if timer:
		timer.queue_free()
	
	await get_tree().create_timer(t_full_effect).timeout
	_clear_all_effects()
	_stop_lightning()


func _update_particle_references(effect_name: String, container_node: Node3D) -> void:
	match effect_name:
		"rain":
			rain_particle = container_node.get_node("RainParticles")
			ripple_particle = container_node.get_node("RippleParticles")
		"snow":
			snow_particle = container_node.get_node("SnowParticles")
			snow_ripple_particle = container_node.get_node("SnowGround")
		"custom":
			custom_particle = container_node.get_node("CustomParticles")


func _setup_base_scene() -> void:
	if has_node("CollisionField"):
		return


	var collision_height: GPUParticlesCollisionHeightField3D = GPUParticlesCollisionHeightField3D.new()
	collision_height.name = "CollisionField"

	var sounds_node: Node3D = Node3D.new()
	sounds_node.name = "Sounds"

	add_child(collision_height)
	add_child(sounds_node)

	var scene_root = get_tree().edited_scene_root
	if scene_root:
		collision_height.owner = scene_root
		sounds_node.owner = scene_root

	# This runs deferred, after _ready() already applied the box, so size and bias have to be
	# pushed again now that the field exists.
	_apply_effect_box()

# Lightning
func _setup_lightning_timer() -> void:
	# Clear existing time if exists
	if lightning_timer and is_instance_valid(lightning_timer):
		lightning_timer.queue_free()
	
	lightning_timer = Timer.new()
	lightning_timer.name = "LightningTimer"
	lightning_timer.one_shot = false
	lightning_timer.autostart = false
	add_child(lightning_timer)


func _trigger_lightning() -> void:
	if not lightning_enabled:
		_stop_lightning()
		return

	# The authoritative guard: lightning only exists as part of the rain effect, so if rain is gone
	# it must stop, whatever left this timer running.
	if not particle_nodes.has("rain"):
		_stop_lightning()
		return

	if not sky_3d or not is_instance_valid(sky_3d):
		_stop_lightning()
		return

	if lightning_sound:
		_play_lightning_sound()
	
	var is_daytime = false
	if sky_3d.has_method("is_day"):
		is_daytime = sky_3d.is_day()
		#print("  is_day() return: ", is_daytime)
	else:
		# Fallback
		is_daytime = sky_3d.sun_energy > sky_3d.moon_energy
		#print("  Fallback: sun_energy=", sky_3d.sun_energy, " moon_energy=", sky_3d.moon_energy)
	
	original_exposure = sky_3d.sun_energy if is_daytime else sky_3d.moon_energy
	var lightning_source = 'sun_energy' if is_daytime else 'moon_energy'
		
	# Kept in a member so _stop_lightning() can kill it and restore the exposure it was driving.
	_lightning_property = lightning_source
	_lightning_tween = create_tween()
	_lightning_tween.tween_property(
		sky_3d,
		lightning_source,
		lightning_intensity,
		lightning_flash_duration
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

	# Fade out
	_lightning_tween.tween_property(
		sky_3d,
		lightning_source,
		original_exposure,
		lightning_fade_duration
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)

	# Next lighting effect in
	_lightning_tween.finished.connect(_schedule_next_lightning)


func _schedule_next_lightning() -> void:
	if not lightning_enabled:
		return
	# A flash already in flight when the effect stopped would otherwise land here and restart the
	# timer, resurrecting lightning after the rain was cleared.
	if not particle_nodes.has("rain"):
		return
	if lightning_timer and is_instance_valid(lightning_timer):
		lightning_timer.wait_time = randf_range(lightning_min_interval, lightning_max_interval)
		lightning_timer.start()


func _play_lightning_sound() -> void:
	if not lightning_sound:
		return
		
	var lightning_audio_player = _create_audio_player("lightning", lightning_sound)
	if lightning_audio_player:
		lightning_audio_player.volume_db = -5.0
		lightning_audio_player.play()
		# Tracked separately from audio_players, which is keyed by effect name and would collide
		# when two claps overlap. Without this, _clear_all_effects() couldn't silence thunder.
		_lightning_audio_players.append(lightning_audio_player)

		var sound_duration = lightning_sound.get_length()
		var cleanup_timer = Timer.new()
		cleanup_timer.name = "CleanupTimer"
		cleanup_timer.wait_time = sound_duration + 0.5
		cleanup_timer.timeout.connect(func():
			_lightning_audio_players.erase(lightning_audio_player)
			if is_instance_valid(lightning_audio_player):
				lightning_audio_player.queue_free()
			cleanup_timer.queue_free()
		)
		add_child(cleanup_timer)
		cleanup_timer.start()


func _start_lightning() -> void:
	if not lightning_enabled:
		return

	if not sky_3d or not is_instance_valid(sky_3d):
		push_warning("Weather: cannot start lightning, sky_3d is not assigned.")
		return

	if not lightning_timer or not is_instance_valid(lightning_timer):
		_setup_lightning_timer()
		if not lightning_timer:
			push_warning("Weather: failed to create the lightning timer.")
			return
	
	lightning_timer.wait_time = randf_range(lightning_min_interval, lightning_max_interval)
	
	# Disconnects if already connected
	if lightning_timer.timeout.is_connected(_trigger_lightning):
		lightning_timer.timeout.disconnect(_trigger_lightning)
	
	lightning_timer.timeout.connect(_trigger_lightning)
	lightning_timer.start()


func _stop_lightning() -> void:
	# Cancel a strike that hasn't started yet.
	if _lightning_delay_timer and is_instance_valid(_lightning_delay_timer):
		_lightning_delay_timer.stop()
		_lightning_delay_timer.queue_free()
	_lightning_delay_timer = null

	# Kill a flash mid-tween and put the light back where it was, or the sky stays blown out.
	if _lightning_tween and _lightning_tween.is_valid():
		_lightning_tween.kill()
		if sky_3d and is_instance_valid(sky_3d) and _lightning_property != "":
			sky_3d.set(_lightning_property, original_exposure)
	_lightning_tween = null
	_lightning_property = ""

	# Silence thunder that's still playing.
	for audio_player in _lightning_audio_players:
		if is_instance_valid(audio_player):
			audio_player.stop()
			audio_player.queue_free()
	_lightning_audio_players.clear()

	if lightning_timer and is_instance_valid(lightning_timer):
		if lightning_timer.timeout.is_connected(_trigger_lightning):
			lightning_timer.timeout.disconnect(_trigger_lightning)
		lightning_timer.stop()


# Cleaners
func _clear_all_effects() -> void:
	_stop_lightning()
	
	for effect_name in particle_nodes.keys():
		var node = particle_nodes[effect_name]
		if is_instance_valid(node):
			for child in node.get_children():
				if child is GPUParticles3D:
					child.emitting = false
			node.queue_free()
	
	for effect_name in audio_players.keys():
		var audio_player = audio_players[effect_name]
		if is_instance_valid(audio_player):
			audio_player.stop()
			audio_player.queue_free()
	
	particle_nodes.clear()
	audio_players.clear()
	should_rain = false

	rain_particle = null
	ripple_particle = null
	snow_particle = null
	snow_ripple_particle = null
	custom_particle = null


func _exit_tree() -> void:
	_clear_all_effects()
	_stop_lightning()

## Sounds
func _create_audio_player(effect_name: String, audio_stream: AudioStream) -> AudioStreamPlayer3D:
	if not audio_stream:
		return null
		
	var audio_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	audio_player.name = effect_name.capitalize() + "Audio"
	audio_player.stream = audio_stream
	audio_player.autoplay = false
	audio_player.volume_db = -20.0  
	
	var sounds_node: Node3D = get_node("Sounds")
	if sounds_node:
		# Left unowned on purpose, same reason as the effect containers: it must not be saved.
		sounds_node.add_child(audio_player)

	return audio_player


func _get_audio_for_effect(effect_name: String) -> AudioStream:
	match effect_name:
		"rain":
			return rain_sound
		"snow":
			return snow_sound
		"custom":
			return custom_sound
		_:
			return null


func change_weather(effect: String, t_full_effect: float, intensity: float, duration: float, lightning_enabled: bool) -> void:
	match effect:
		"rain":
			_create_and_play_effect("rain", intensity, lightning_enabled, rain_full_show_time, duration)
		"snow":
			# lightning_enabled is ignored for non-rain effects, but it has to be passed explicitly
			# or t_full_effect/duration silently shift one slot to the left.
			_create_and_play_effect("snow", intensity, false, snow_full_show_time, duration)
		"custom":
			_create_and_play_effect("custom", intensity, false, snow_full_show_time, duration)


func _reset_effect_direction():
	# Must restore exactly the channels set_effect_direction() writes: 'direction' for rain and
	# custom, 'gravity' for snow. Resetting the other channel left the modified one dirty.
	rain_process_material.direction = default_rain_direction
	snow_process_material.gravity = default_snow_gravity
	custom_process_material.direction = default_custom_direction


## SETTERS EFFECTS EDITOR
func set_effect_type(effect_type: EffectType, intensity: float = 0.8) -> void:   
	_clear_all_effects()
	if not Engine.is_editor_hint():
		await get_tree().process_frame
	
	match effect_type:
		EffectType.CLEAR:
			_reset_effect_direction() 
		EffectType.RAIN:
			_create_and_play_effect("rain", intensity, lightning_enabled, rain_full_show_time, duration)
		EffectType.SNOW:
			_create_and_play_effect("snow", intensity, false, snow_full_show_time, duration)
		EffectType.CUSTOM:
			_create_and_play_effect("custom", intensity, false, snow_full_show_time, duration)


func set_effect_direction(new_direction: Vector3):
	rain_process_material.direction = new_direction
	snow_process_material.gravity = Vector3(new_direction.x * 20, -9.8, new_direction.z * 20)
	custom_process_material.direction = new_direction


func _on_weather_changed(effect_name: String, intensity: float) -> void:
	_debug("weather_changed -> %s @ %.2f" % [effect_name, intensity])


func get_current_effect_type() -> EffectType:
	if particle_nodes.has("rain"):
		return EffectType.RAIN
	elif particle_nodes.has("snow"):
		return EffectType.SNOW
	elif particle_nodes.has("custom"):
		return EffectType.CUSTOM
	else:
		return EffectType.CLEAR


func stop_all_effects() -> void:
	_clear_all_effects()


func is_effect_active(effect_type: EffectType) -> bool:
	match effect_type:
		EffectType.RAIN:
			return particle_nodes.has("rain")
		EffectType.SNOW:
			return particle_nodes.has("snow")
		EffectType.CUSTOM:
			return particle_nodes.has("custom")
		_:
			return false


func degrees_to_vector3(angle_degrees: float) -> Vector3:
	var angle_radians = deg_to_rad(angle_degrees)
	var direction = Vector3.ZERO
	direction.x = cos(angle_radians)
	direction.z = sin(angle_radians)
	direction.y = -1.0 # Default vector
	return direction
