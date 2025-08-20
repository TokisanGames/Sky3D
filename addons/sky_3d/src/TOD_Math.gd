# Copyright (c) 2023-2025 Cory Petkovsek and Contributors
# Copyright (c) 2021 J. Cuellar

class_name TOD_Math


const RAD_TO_DEG: float = 57.2957795
const DEG_TO_RAD: float = 0.0174533


static func saturate(value: float) -> float:
	return 0.0 if value < 0.0 else 1.0 if value > 1.0 else value


static func saturate_vec3(value: Vector3) -> Vector3:
	var ret: Vector3
	ret.x = 0.0 if value.x < 0.0 else 1.0 if value.x > 1.0 else value.x
	ret.y = 0.0 if value.y < 0.0 else 1.0 if value.y > 1.0 else value.y
	ret.z = 0.0 if value.z < 0.0 else 1.0 if value.z > 1.0 else value.z
	return ret


static func saturate_color(value: Color) -> Color:
	var ret: Color 
	ret.r = 0.0 if value.r < 0.0 else 1.0 if value.r > 1.0 else value.r
	ret.g = 0.0 if value.g < 0.0 else 1.0 if value.g > 1.0 else value.g
	ret.b = 0.0 if value.b < 0.0 else 1.0 if value.b > 1.0 else value.b
	ret.a = 0.0 if value.a < 0.0 else 1.0 if value.a > 1.0 else value.a
	return ret


static func rev(val: float) -> float:
	return val - int(floor(val / 360.0)) * 360.0


static func plerp_vec3(from: Vector3, to: Vector3, t: float) -> Vector3:
	var ret: Vector3 
	ret.x = (1 - t) * from.x + t * to.x
	ret.y = (1 - t) * from.y + t * to.y
	ret.z = (1 - t) * from.z + t * to.z
	return ret


static func plerp_color(from: Color, to: Color, t: float) -> Color:
	var ret: Color
	ret.r = (1 - t) * from.r + t * to.r
	ret.g = (1 - t) * from.g + t * to.g
	ret.b = (1 - t) * from.b + t * to.b
	ret.a = (1 - t) * from.a + t * to.a	
	return ret


static func distance(a: Vector3, b: Vector3) -> float:
	var ret: float
	var x: float = a.x - b.x
	var y: float = a.y - b.y
	var z: float = a.z - b.z 
	ret = x * x + y * y + z * z
	return sqrt(ret)


static func to_orbit(theta: float, pi: float, radius: float = 1.0) -> Vector3:
	var ret: Vector3 
	var sinTheta:  float = sin(theta)
	var cosTheta:  float = cos(theta)
	var sinPI:     float = sin(pi)
	var cosPI:     float = cos(pi)

	ret.x = sinTheta * sinPI
	ret.y = cosTheta
	ret.z = sinTheta * cosPI
	return ret * radius
	
