# Copyright (c) 2023-2025 Cory Petkovsek and Contributors
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
	
