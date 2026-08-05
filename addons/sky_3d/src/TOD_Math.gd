# Copyright (c) 2023-2026 Cory Petkovsek and Contributors
# Copyright (c) 2021 J. Cuellar

class_name TOD_Math


static func rev(val: float) -> float:
	return val - int(floor(val / 360.0)) * 360.0


static func spherical_to_cartesian(theta: float, azimuth: float, radius: float = 1.0) -> Vector3:
	var ret: Vector3
	var sinTheta:  float = sin(theta)
	ret.x = sinTheta * sin(azimuth)
	ret.y = cos(theta)
	ret.z = sinTheta * cos(azimuth)
	return ret * radius


## A faithful GDScript transcription of the sky shader's create_rotation_matrix(), including
## its transposed axis columns (the GLSL mat3() constructor takes columns, Basis takes rows)
## and its ZYX composition order. Rebuilding it "cleanly" from Basis(axis, angle) produces a
## matrix that looks right and orients the sky wrongly — transcribe, don't improve.
static func rotation_matrix(r: Vector3) -> Basis:
	var c1: float = cos(r.x)
	var s1: float = sin(r.x)
	var c2: float = cos(r.y)
	var s2: float = sin(r.y)
	var c3: float = cos(r.z)
	var s3: float = sin(r.z)

	var rot_x := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, c1, -s1), Vector3(0.0, s1, c1))
	var rot_y := Basis(Vector3(c2, 0.0, s2), Vector3(0.0, 1.0, 0.0), Vector3(-s2, 0.0, c2))
	var rot_z := Basis(Vector3(c3, -s3, 0.0), Vector3(s3, c3, 0.0), Vector3(0.0, 0.0, 1.0))

	return rot_z * rot_y * rot_x  # Combine rotations in ZYX order
