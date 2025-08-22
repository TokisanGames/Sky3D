# Copyright (c) 2023-2025 Cory Petkovsek and Contributors
# Copyright (c) 2021 J. Cuellar

class_name ScatterLib

# Atmospheric Scattering Lib.
# References:
# - Preetham and Hoffman Paper:
# See: https://developer.amd.com/wordpress/media/2012/10/ATI-LightScattering.pdf

const n: float = 1.0003 # Index of the air refraction
const n2: float = 1.00060009 # Index of the air refraction ˆ 2
const N: float = 2.545e25 # Molecular Density
const pn: float = 0.035 # Depolatization factor for standard air.


static func compute_wavelenghts_lambda(value: Vector3) -> Vector3:
	return value * 1e-9


static func compute_wavelenghts(lambda: Vector3) -> Vector3:
	var k = 4.0
	var ret: Vector3 = lambda
	ret.x = pow(lambda.x, k)
	ret.y = pow(lambda.y, k)
	ret.z = pow(lambda.z, k)
	return ret


static func compute_beta_ray(wavelenghts: Vector3) -> Vector3:
	var kr: float = (8.0 * pow(PI, 3.0) * pow(n2 - 1.0, 2.0) * (6.0 + 3.0 * pn))
	var ret: Vector3 = 3.0 * N * wavelenghts * (6.0 - 7.0 * pn)
	ret.x = kr / ret.x
	ret.y = kr / ret.y
	ret.z = kr / ret.z
	return ret


static func compute_beta_mie(mie: float, turbidity: float) -> Vector3:
	var k: float = 434e-6
	return Vector3.ONE * mie * turbidity * k


static func get_partial_mie_phase(g: float) -> Vector3:
	var g2: float = g * g
	var ret: Vector3
	ret.x = 1.0 - g2
	ret.y = 1.0 + g2
	ret.z = 2.0 * g
	return ret
