# Copyright (c) 2023-2025 Cory Petkovsek and Contributors
# Copyright (c) 2021 J. Cuellar

## TimeOfDay is a component of [Sky3D].
##
## This class tracks the progress of time, as well as the planetary calculations. See [Sky3D].

@tool
class_name TimeOfDay
extends Node


signal time_changed(value)
signal day_changed(value)
signal month_changed(value)
signal year_changed(value)

const HOURS_PER_DAY: int = 24
const RADIANS_PER_HOUR: float = PI / 12.0
const HALFPI : float = PI / 2.0


func _init() -> void:
	set_current_time(current_time)
	set_day(day)
	set_month(month)
	set_year(year)
	set_latitude(latitude)
	set_longitude(longitude)
	set_utc(utc)


func _ready() -> void:
	dome_path = dome_path

	_update_timer = Timer.new()
	_update_timer.name = "Timer"
	add_child(_update_timer)
	_update_timer.timeout.connect(_on_timeout)
	_update_timer.wait_time = update_interval
	resume()


func _on_timeout() -> void:
	if system_sync:
		_update_time_from_os()
	else:
		var delta: float = 0.001 * (Time.get_ticks_msec() - _last_update)
		_progress_time(delta)
	_update_celestial_coords()
	_last_update = Time.get_ticks_msec()


func pause() -> void:
	if is_instance_valid(_update_timer):
		_update_timer.stop()


func resume() -> void:
	if is_instance_valid(_update_timer):
		# Assume resuming from a pause, so timer only gets one tick
		_last_update = Time.get_ticks_msec() - update_interval
		if (Engine.is_editor_hint() and editor_time_enabled) or \
				(not Engine.is_editor_hint() and game_time_enabled):
			_update_timer.start()


#####################
## General 
#####################

var _update_timer: Timer
var _last_update: int = 0
var _sky_dome: SkyDome

@export_group("General")

## Allows time to progress in the editor. 
@export var editor_time_enabled: bool = true :
	set(value):
		editor_time_enabled = value
		if Engine.is_editor_hint():
			if editor_time_enabled:
				resume()
			else:
				pause()


## Allows time to progress in game. 
@export var game_time_enabled: bool = true :
	set(value):
		game_time_enabled = value
		if not Engine.is_editor_hint():
			if game_time_enabled:
				resume()
			else:
				pause()


@export var dome_path: NodePath:
	set(value):
		dome_path = value
		if dome_path:
			# DEPRECATED - Remove 2.2
			if dome_path == NodePath("../Skydome"):
				dome_path = NodePath("../SkyDome")
			_sky_dome = get_node_or_null(dome_path)
		_update_celestial_coords()


## The total length of time for a complete day and night cycle in real world minutes. Setting this to
## [param 15] means a full in-game day takes 15 real-world minutes. [member game_time_enabled] must be
## enabled for this to work. Negative values moves time backwards. The Witcher 3 uses a 96 minute cycle. 
## Adjust [member update_interval] to match. Shorter days needs more updates. Longer days need less.
@export var minutes_per_day: float = 15.0

## Celestial coordinates are updated based upon a timer, which continuously fires based on
## this interval: [0.016, 10s]. Set to the lowest, 0.016 (60fps) if your [member minutes_per_day] is short,
## such as less than 15 minutes. The Witcher 3 uses a 96 minute day cycle, so 0.1 (10fps) is adequate.
@export_range(0.016, 10) var update_interval: float = 0.016 :
	set(value):
		update_interval = clamp(value, .016, 10)
		if is_instance_valid(_update_timer):
			_update_timer.wait_time = update_interval
		resume()


#####################
## DateTime
#####################

@export_group("Current Time")

## Syncronize all of Sky3D with your system clock for a realtime sky, time, and date.
@export var system_sync: bool = false
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var game_date: String = "":
	get():
		return "%04d-%02d-%02d" % [ year, month, day ]


@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) 
var game_time: String = "":
	get():
		return "%02d:%02d:%02d" % [ floor(current_time), floor(fmod(current_time, 1.0) * 60.0), 
			floor(fmod(current_time * 60.0, 1.0) * 60.0) ]


@export_range(0.,23.9998) var current_time: float = 8.0 : set = set_current_time
@export_range(0,31) var day: int = 1: set = set_day
@export_range(0,12) var month: int = 1: set = set_month
@export_range(-9999,9999) var year: int = 2025: set = set_year


func set_current_time(value: float) -> void:
	if current_time != value:
		current_time = value
		while current_time > 23.9999:
			current_time -= 24
			day += 1
		while current_time < 0.0000:
			current_time += 24
			day -= 1
		emit_signal("time_changed", current_time)
		_update_celestial_coords()


func set_day(value: int) -> void:
	if day != value:
		day = value
		while day > max_days_per_month():
			day -= max_days_per_month()
			month += 1
		while day < 1:
			month -= 1
			day += max_days_per_month()
		emit_signal("day_changed", day)
		_update_celestial_coords()


func set_month(value: int) -> void:
	if month != value:
		month = value
		while month > 12:
			month -= 12
			year += 1
		while month < 1:
			month += 12
			year -= 1
		emit_signal("month_changed", month)
		_update_celestial_coords()


func set_year(value: int) -> void:
	if year != value:
		year = value
		emit_signal("year_changed", year)
		_update_celestial_coords()


func is_leap_year() -> bool:
	return (year % 4 == 0) && (year % 100 != 0) || (year % 400 == 0)


func max_days_per_month() -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		2:
			return 29 if is_leap_year() else 28
	return 30
	

func time_cycle_duration() -> float:
	return minutes_per_day * 60.0


func set_time(hour: int, minute: int, second: int) -> void: 
	set_current_time(float(hour) + float(minute) / 60.0 + float(second) / 3600.0)


func set_from_datetime_dict(datetime_dict: Dictionary) -> void:
	set_year(datetime_dict.year)
	set_month(datetime_dict.month)
	set_day(datetime_dict.day)
	set_time(datetime_dict.hour, datetime_dict.minute, datetime_dict.second)


func get_datetime_dict() -> Dictionary:
	var datetime_dict: Dictionary = {
		"year": year,
		"month": month,
		"day": day,
		"hour": floor(current_time),
		"minute": floor(fmod(current_time, 1.0) * 60.0),
		"second": floor(fmod(current_time * 60.0, 1.0) * 60.0)
	}
	return datetime_dict


func set_from_unix_timestamp(timestamp: int) -> void:
	set_from_datetime_dict(Time.get_datetime_dict_from_unix_time(timestamp))


func get_unix_timestamp() -> int:
	return Time.get_unix_time_from_datetime_dict(get_datetime_dict())


func _progress_time(delta: float) -> void:
	if not is_zero_approx(time_cycle_duration()):
		set_current_time(current_time + delta / time_cycle_duration() * HOURS_PER_DAY)


func _update_time_from_os() -> void:
	var date_time_os: Dictionary = Time.get_datetime_dict_from_system()
	set_time(date_time_os.hour, date_time_os.minute, date_time_os.second)
	set_day(date_time_os.day)
	set_month(date_time_os.month)
	set_year(date_time_os.year)


#####################
## Planetary
#####################

@export_group("Geographic Coordinates")

@export var calculate_moon: bool = true: set = set_calculate_moon
@export var calculate_stars: bool = true: set = set_calculate_stars
enum CelestialMode { SIMPLE, REALISTIC }
@export var celestials_calculations: CelestialMode = CelestialMode.REALISTIC: set = set_celestials_calculations

var latitude: float = deg_to_rad(16.): set = set_latitude
var longitude: float = deg_to_rad(108.): set = set_longitude
var utc: float = 7.0: set = set_utc
## Set the radial distance between the moon and the sun along the shared path of their orbit.[br]
## Example values:[br]
## * 180 degrees away from the sun on the opposite side of the sky.[br]
## * 90 degrees in front of the sun.[br]
## * -90 degrees behind the sun.[br]
var moon_altitude_offset: float = deg_to_rad(90.):
	set(value):
		moon_altitude_offset = value
		_update_celestial_coords()


var _sun_coords: Vector2 = Vector2.ZERO
var _moon_coords: Vector2 = Vector2.ZERO
var _sun_distance: float
var _true_sun_longitude: float
var _mean_sun_longitude: float
var _sideral_time: float
var _local_sideral_time: float
var _sun_orbital_elements := OrbitalElements.new()
var _moon_orbital_elements := OrbitalElements.new()


func _property_can_revert(property: StringName) -> bool:
	return property in [ &"latitude", &"longitude", &"utc", &"moon_altitude_offset" ]


func _property_get_revert(property: StringName) -> Variant:
	match property:
		&"latitude": return deg_to_rad(16.)
		&"longitude": return deg_to_rad(108.)
		&"utc": return 7.
		&"moon_altitude_offset": return deg_to_rad(90.)
	return null


func _get_property_list() -> Array:
	var arr: Array = []
	var dict: Dictionary = {
		"type": TYPE_FLOAT,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_RANGE,
	}
	if celestials_calculations == CelestialMode.REALISTIC:
		dict.name = &"latitude"
		dict.hint_string = "-180.,180.,0.00001,radians_as_degrees"
		arr.append(dict.duplicate())
	dict.name = &"longitude"
	dict.hint_string = "-180.,180.,0.00001,radians_as_degrees"
	arr.append(dict.duplicate())
	dict.name = &"utc"
	dict.hint_string = "-12,14,.25"
	arr.append(dict.duplicate())
	if celestials_calculations == CelestialMode.SIMPLE:
		dict.name = &"moon_altitude_offset"
		dict.hint_string = "-180.,180.,0.001,radians_as_degrees"
		arr.append(dict.duplicate())
	return arr


func set_celestials_calculations(value: int) -> void:
	celestials_calculations = value
	_update_celestial_coords()
	notify_property_list_changed()
	

func set_latitude(value: float) -> void:
	latitude = value
	_update_celestial_coords()


func set_longitude(value: float) -> void:
	longitude = value
	_update_celestial_coords()


func set_utc(value: float) -> void:
	utc = value
	_update_celestial_coords()


func set_calculate_moon(value: bool) -> void:
	calculate_moon = value
	_update_celestial_coords()
	notify_property_list_changed()
	

func set_calculate_stars(value: bool) -> void:
	calculate_stars = value
	_update_celestial_coords()


## Returns the current time at UTC 0
func get_current_time_utc0() -> float:
	return current_time - utc


func _get_time_scale() -> float:
	return (367.0 * year - (7.0 * (year + ((month + 9.0) / 12.0))) / 4.0 +\
		(275.0 * month) / 9.0 + day - 730530.0) + current_time / 24.0


func _get_oblecl() -> float:
	return deg_to_rad(23.4393 - 2.563e-7 * _get_time_scale())


func _update_celestial_coords() -> void:
	if not (is_instance_valid(_sky_dome) and _sky_dome.is_scene_built):
		return

	#TODO Remove double indent before merge
	if celestials_calculations == CelestialMode.SIMPLE:
			_compute_simple_sun_coords()
			_sky_dome.sun_altitude = _sun_coords.y
			_sky_dome.sun_azimuth = _sun_coords.x
			if calculate_moon:
				_compute_simple_moon_coords()
				_sky_dome.moon_altitude = _moon_coords.y
				_sky_dome.moon_azimuth = _moon_coords.x
			if calculate_stars:
				var simple_sideral_time := get_current_time_utc0() * RADIANS_PER_HOUR + longitude
				if _sky_dome.sky_material:
					_sky_dome.sky_material.set_shader_parameter("star_tilt", -HALFPI)
					_sky_dome.sky_material.set_shader_parameter("star_rotation", HALFPI - simple_sideral_time)
	else:
			_compute_realistic_sun_coords()
			_sky_dome.sun_altitude = -_sun_coords.y
			_sky_dome.sun_azimuth = -_sun_coords.x
			if calculate_moon:
				_compute_realistic_moon_coords()
				_sky_dome.moon_altitude = -_moon_coords.y
				_sky_dome.moon_azimuth = -_moon_coords.x
			if calculate_stars:
				_sky_dome.sky_material.set_shader_parameter("star_tilt", latitude - HALFPI)
				_sky_dome.sky_material.set_shader_parameter("star_rotation", -_local_sideral_time)
	_sky_dome.update_moon_coords()


func _compute_simple_sun_coords() -> void:
	var azimuthal_progress: float = get_current_time_utc0() * RADIANS_PER_HOUR + longitude
	_sun_coords.y = fmod(PI - azimuthal_progress + TAU, TAU) # Altitude, Equator at zenith, poles at horizon
	_sun_coords.x = HALFPI # Azimuth, east-west progression
	# Optional: Simple declination approx for seasons 
	# _sun_coords.x += sin(2*PI*(day_of_year/365)) * deg_to_rad(23.5))


func _compute_simple_moon_coords() -> void:
	_moon_coords.y = fmod(moon_altitude_offset - _sun_coords.y + TAU, TAU)  # Altitude
	_moon_coords.x = PI + _sun_coords.x  # Azimuth

	
func _compute_realistic_sun_coords() -> void:
	# Orbital Elements
	_sun_orbital_elements.get_orbital_elements(0, _get_time_scale())
	_sun_orbital_elements.M = TOD_Math.rev(_sun_orbital_elements.M)
	
	# Mean anomaly in radians
	var MRad: float = deg_to_rad(_sun_orbital_elements.M)
	
	# Eccentric Anomaly
	var E: float = _sun_orbital_elements.M + rad_to_deg(_sun_orbital_elements.e * sin(MRad) * (1 + _sun_orbital_elements.e * cos(MRad)))
	
	var ERad: float = deg_to_rad(E)
	
	# Rectangular coordinates of the sun in the plane of the ecliptic
	var xv: float = cos(ERad) - _sun_orbital_elements.e
	var yv: float = sin(ERad) * sqrt(1 - _sun_orbital_elements.e * _sun_orbital_elements.e)
	
	# Distance and true anomaly
	# Convert to distance and true anomaly(r = radians, v = degrees)
	var r: float = sqrt(xv * xv + yv * yv)
	var v: float = rad_to_deg(atan2(yv, xv))
	_sun_distance = r
	
	# True longitude
	var lonSun: float = v + _sun_orbital_elements.w
	lonSun = TOD_Math.rev(lonSun)
	
	var lonSunRad: float = deg_to_rad(lonSun)
	_true_sun_longitude = lonSunRad
	
	## Ecliptic and ecuatorial coords
	
	# Ecliptic rectangular coords
	var xs: float = r * cos(lonSunRad)
	var ys: float = r * sin(lonSunRad)
	
	# Ecliptic rectangular coordinates rotate these to equatorial coordinates
	var obleclCos: float = cos(_get_oblecl())
	var obleclSin: float = sin(_get_oblecl())
	
	var xe: float = xs 
	var ye: float = ys * obleclCos - 0.0 * obleclSin
	var ze: float = ys * obleclSin + 0.0 * obleclCos
	
	# Ascencion and declination
	var RA: float = rad_to_deg(atan2(ye, xe)) / 15  # right ascension.
	var decl: float = atan2(ze, sqrt(xe * xe + ye * ye))  # declination
	
	# Mean longitude
	var L: float = _sun_orbital_elements.w + _sun_orbital_elements.M
	L = TOD_Math.rev(L)
	
	_mean_sun_longitude = L
	
	# Sideral time and hour angle
	# TODO: We need to convert this math to radians
	# TODO: 15 is degrees per hour, we will need to convert to RADIANS_PER_HOUR
	var GMST0: float = ((L/15) + 12)
	_sideral_time = GMST0 + get_current_time_utc0() + rad_to_deg(longitude) / 15  # +15/15
	_local_sideral_time = deg_to_rad(_sideral_time * 15)
	
	var HA: float = (_sideral_time - RA) * 15
	var HARAD: float = deg_to_rad(HA)
	
	# Hour angle and declination in rectangular coords
	# HA and Decl in rectangular coords
	var declCos: float = cos(decl)
	var x: float = cos(HARAD) * declCos # X Axis points to the celestial equator in the south.
	var y: float = sin(HARAD) * declCos # Y axis points to the horizon in the west.
	var z: float = sin(decl) # Z axis points to the north celestial pole.
	
	# Rotate the rectangualar coordinates system along of the Y axis
	var sinLat: float = sin(latitude)
	var cosLat: float = cos(latitude)
	var xhor: float = x * sinLat - z * cosLat
	var yhor: float = y 
	var zhor: float = x * cosLat + z * sinLat
	
	# Azimuth and altitude
	# TODO: Another likely mistake here, _sun_coords is typically in degrees, but PI is a unit in radians
	_sun_coords.x = atan2(yhor, xhor) + PI
	_sun_coords.y = (PI * 0.5) - asin(zhor) # atan2(zhor, sqrt(xhor * xhor + yhor * yhor))


func _compute_realistic_moon_coords() -> void:
	# Orbital Elements
	_moon_orbital_elements.get_orbital_elements(1, _get_time_scale())
	_moon_orbital_elements.N = TOD_Math.rev(_moon_orbital_elements.N)
	_moon_orbital_elements.w = TOD_Math.rev(_moon_orbital_elements.w)
	_moon_orbital_elements.M = TOD_Math.rev(_moon_orbital_elements.M)
	
	var NRad: float = deg_to_rad(_moon_orbital_elements.N)
	var IRad: float = deg_to_rad(_moon_orbital_elements.i)
	var MRad: float = deg_to_rad(_moon_orbital_elements.M)
	
	# Eccentric anomaly
	var E: float = _moon_orbital_elements.M + rad_to_deg(_moon_orbital_elements.e * sin(MRad) * (1 + _sun_orbital_elements.e * cos(MRad)))
	
	var ERad: float = deg_to_rad(E)
	
	# Rectangular coords and true anomaly
	# Rectangular coordinates of the sun in the plane of the ecliptic
	var xv: float = _moon_orbital_elements.a * (cos(ERad) - _moon_orbital_elements.e)
	var yv: float = _moon_orbital_elements.a * (sin(ERad) * sqrt(1 - _moon_orbital_elements.e * \
		_moon_orbital_elements.e)) * sin(ERad)
		
	# Convert to distance and true anomaly(r = radians, v = degrees)
	var r: float = sqrt(xv * xv + yv * yv)
	var v: float = rad_to_deg(atan2(yv, xv))
	v = TOD_Math.rev(v)
	
	var l: float = deg_to_rad(v) + _moon_orbital_elements.w
	
	var cosL: float = cos(l)
	var sinL: float = sin(l)
	var cosNRad: float = cos(NRad)
	var sinNRad: float = sin(NRad)
	var cosIRad: float = cos(IRad)
	
	var xeclip: float = r * (cosNRad * cosL - sinNRad * sinL * cosIRad)
	var yeclip: float = r * (sinNRad * cosL + cosNRad * sinL * cosIRad)
	var zeclip: float = r * (sinL * sin(IRad))
	
	# Geocentric coords
	# Geocentric position for the moon and Heliocentric position for the planets
	var lonecl: float = rad_to_deg(atan2(yeclip, xeclip))
	lonecl = TOD_Math.rev(lonecl)
	
	var latecl: float = rad_to_deg(atan2(zeclip, sqrt(xeclip * xeclip + yeclip * yeclip)))
	
	# Get true sun longitude
	var lonsun: float = _true_sun_longitude
	
	# Ecliptic longitude and latitude in radians
	var loneclRad: float = deg_to_rad(lonecl)
	var lateclRad: float = deg_to_rad(latecl)
	
	var nr: float = 1.0
	var xh: float = nr * cos(loneclRad) * cos(lateclRad)
	var yh: float = nr * sin(loneclRad) * cos(lateclRad)
	var zh: float = nr * sin(lateclRad)
	
	# Geocentric coords
	var xs: float = 0.0
	var ys: float = 0.0
	
	# Convert the geocentric position to heliocentric position
	var xg: float = xh + xs
	var yg: float = yh + ys
	var zg: float = zh
	
	# Ecuatorial coords
	# Cobert xg, yg un equatorial coords
	var obleclCos: float = cos(_get_oblecl())
	var obleclSin: float = sin(_get_oblecl())
	
	var xe: float = xg 
	var ye: float = yg * obleclCos - zg * obleclSin
	var ze: float = yg * obleclSin + zg * obleclCos
	
	# Right ascention
	var RA: float = rad_to_deg(atan2(ye, xe))
	RA = TOD_Math.rev(RA)
	
	# Declination
	var decl: float = rad_to_deg(atan2(ze, sqrt(xe * xe + ye * ye)))
	var declRad: float = deg_to_rad(decl)
	
	# Sideral time and hour angle
	var HA: float = ((_sideral_time * 15) - RA)
	HA = TOD_Math.rev(HA)
	var HARAD: float = deg_to_rad(HA)
	
	# HA y Decl in rectangular coordinates
	var declCos: float = cos(declRad)
	var xr: float = cos(HARAD) * declCos
	var yr: float = sin(HARAD) * declCos
	var zr: float = sin(declRad)
	
	# Rotate the rectangualar coordinates system along of the Y axis(radians)
	var sinLat: float = sin(latitude)
	var cosLat: float = cos(latitude)
	
	var xhor: float = xr * sinLat - zr * cosLat
	var yhor: float = yr 
	var zhor: float = xr * cosLat + zr * sinLat
	
	# Azimuth and altitude
	_moon_coords.x = atan2(yhor, xhor) + PI
	_moon_coords.y = (PI *0.5) - atan2(zhor, sqrt(xhor * xhor + yhor * yhor)) # Mathf.Asin(zhor)
