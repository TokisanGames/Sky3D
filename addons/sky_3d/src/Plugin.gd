# Copyright (c) 2023-2025 Cory Petkovsek and Contributors
# Copyright (c) 2021 J. Cuellar

@tool
extends EditorPlugin

const __sky3d_script: String = "res://addons/sky_3d/src/Sky3D.gd"
const __sky3d_icon: String = "res://addons/sky_3d/assets/textures/SkyIcon.png"
const __skydome_script: String = "res://addons/sky_3d/src/SkyDome.gd"
const __skydome_icon: String = "res://addons/sky_3d/assets/textures/SkyIcon.png"
const __time_of_day_script: String = "res://addons/sky_3d/src/TimeOfDay.gd"
const __time_of_day_icon: String = "res://addons/sky_3d/assets/textures/SkyIcon.png"


func _enter_tree() -> void:
	add_custom_type("Sky3D", "Node", load(__sky3d_script), load(__sky3d_icon))
	add_custom_type("SkyDome", "Node", load(__skydome_script), load(__skydome_icon))
	add_custom_type("TimeOfDay", "Node", load(__time_of_day_script), load(__time_of_day_icon))


func _exit_tree() -> void:
	remove_custom_type("Sky3D")
	remove_custom_type("SkyDome")
	remove_custom_type("TimeOfDay")
