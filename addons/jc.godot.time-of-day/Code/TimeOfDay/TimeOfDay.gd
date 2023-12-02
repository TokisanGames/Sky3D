tool
class_name TimeOfDay extends Node
"""========================================================
°                         TimeOfDay.
°                   ======================
°
°   Category: TimeOfDay
°   -----------------------------------------------------
°   Description:
°       Time of Day manager.
°   -----------------------------------------------------
°   Copyright:
°               J. Cuellar 2021. MIT License.
°                   See: LICENSE File.
========================================================"""

# Target
#----------------------------------------------------------
var __dome: Skydome = null
var __dome_found: bool = false

var dome_path: NodePath setget set_dome_path
func set_dome_path(value: NodePath) -> void:
	dome_path = value
	if value != null:
		__dome = get_node_or_null(value) as Skydome
	
	__dome_found = false if __dome == null else true
	__set_celestial_coords()

# DateTime
#----------------------------------------------------------
var system_sync: bool = false
var total_cycle_in_minutes: float = 15.0

var total_hours: float = 7.0 setget set_total_hours
func set_total_hours(value: float) -> void:
	total_hours = value
	emit_signal("total_hours_changed", value)
	if Engine.editor_hint:
		__set_celestial_coords()

var day: int = 12 setget set_day
func set_day(value: int) -> void:
	day = value 
	emit_signal("day_changed", value)
	if Engine.editor_hint:
		__set_celestial_coords()

var month: int = 2 setget set_month
func set_month(value: int) -> void:
	month = value 
	emit_signal("month_changed", value)
	if Engine.editor_hint:
		__set_celestial_coords()

var year: int = 2021 setget set_year
func set_year(value: int) -> void:
	year = value 
	emit_signal("year_changed", value)
	if Engine.editor_hint:
		__set_celestial_coords()

func is_learp_year() -> bool:
	return DateTimeUtil.compute_leap_year(year)

func max_days_per_month() -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		2:
			return 29 if is_learp_year() else 28
	
	return 30

func time_cycle_duration() -> float:
	return total_cycle_in_minutes * 60.0

func is_begin_of_time() -> bool:
	return year == 1 && month == 1 && day == 1

func is_end_of_time() -> bool:
	return year == 9999 && month == 12 && day == 31

var date_time_os: Dictionary
signal total_hours_changed(value)
signal day_changed(value)
signal month_changed(value)
signal year_changed(value)

# Planetary
#----------------------------------------------------------
enum CelestialCalculationsMode{
	Simple = 0,
	Realistic
}

var celestials_calculations: int = 0 setget set_celestials_calculations
func set_celestials_calculations(value: int) -> void:
	celestials_calculations = value
	if Engine.editor_hint:
		__set_celestial_coords()
	
	property_list_changed_notify()

var latitude: float = 0.0 setget set_latitude
func set_latitude(value: float) -> void:
	latitude = value
	if Engine.editor_hint:
		__set_celestial_coords()

var longitude: float = 0.0 setget set_longitude
func set_longitude(value: float) -> void:
	longitude = value
	if Engine.editor_hint:
		__set_celestial_coords()

var utc: float = 0.0 setget set_utc
func set_utc(value: float) -> void:
	utc = value
	if Engine.editor_hint:
		__set_celestial_coords()

var celestials_update_time: float = 0.0
var __celestials_update_timer: float = 0.0

var compute_moon_coords: bool = false setget set_compute_moon_coords
func set_compute_moon_coords(value: bool) -> void:
	compute_moon_coords = value
	if Engine.editor_hint:
		__set_celestial_coords()
	
	property_list_changed_notify()

var compute_deep_space_coords: bool = false setget set_compute_deep_space_coords
func set_compute_deep_space_coords(value: bool) -> void:
	compute_deep_space_coords = value
	if Engine.editor_hint:
		__set_celestial_coords()

var moon_coords_offset := Vector2(0.0, 0.0) setget set_moon_coords_offset
func set_moon_coords_offset(value: Vector2) -> void:
	moon_coords_offset = value
	if Engine.editor_hint:
		__set_celestial_coords()

func __get_latitude_rad() -> float:
	return latitude * TOD_Math.DEG_TO_RAD

func __get_total_hours_utc() -> float:
	return total_hours - utc

func __get_time_scale() -> float:
	return (367.0 * year - (7.0 * (year + ((month + 9.0) / 12.0))) / 4.0 +\
		(275.0 * month) / 9.0 + day - 730530.0) + total_hours / 24.0

func __get_oblecl() -> float:
	return (23.4393 - 2.563e-7 * __get_time_scale()) * TOD_Math.DEG_TO_RAD

var __sun_coords:= Vector2.ZERO
var __moon_coords:= Vector2.ZERO
var __sun_distance: float
var __true_sun_longitude: float 
var __mean_sun_longitude: float
var __sideral_time: float
var __local_sideral_time: float

var __sun_orbital_elements:= OrbitalElements.new()
var __moon_orbital_elements:= OrbitalElements.new()


# Override
#----------------------------------------------------------
func _init() -> void:
	set_total_hours(total_hours)
	set_day(day)
	set_month(month)
	set_year(year)
	set_latitude(latitude)
	set_longitude(longitude)
	set_utc(utc)

signal time_update(TimeOfDay)
export var update_interval: float = 0.1
var _last_update: int = 0


func _ready() -> void:
	set_dome_path(dome_path)

	var timer := Timer.new()
	timer.name = "Timer"
	add_child(timer)
	timer.connect("timeout", self, "_on_timeout")
	timer.wait_time = update_interval
	timer.stop()
	_last_update = OS.get_ticks_msec()


func _on_timeout() -> void:
	if Engine.editor_hint:
		return
	
	var delta: float = .001 * (OS.get_ticks_msec() - _last_update)

	if not system_sync:
		__time_process(delta)
		__repeat_full_cycle()
		__check_cycle()
	else:
		__get_date_time_os()
	
	__celestials_update_timer += delta;
	if __celestials_update_timer > celestials_update_time:
		__set_celestial_coords()
		__celestials_update_timer = 0.0

	emit_signal("time_update", self)
	_last_update = OS.get_ticks_msec()
	

func pause() -> void:
	$Timer.stop()


func resume() -> void:
	_last_update = OS.get_ticks_msec() - update_interval
	$Timer.start()
	


# DateTime
#----------------------------------------------------------
func set_time(hour: int, minute: int, second: int) -> void:
	set_total_hours(DateTimeUtil.hours_to_total_hours(hour, minute, second))

func __time_process(delta: float) -> void:
	if time_cycle_duration() != 0.0:
		set_total_hours(total_hours + delta / time_cycle_duration() * DateTimeUtil.TOTAL_HOURS)

func __get_date_time_os() -> void:
	date_time_os = OS.get_datetime()
	set_time(date_time_os.hour, date_time_os.minute, date_time_os.second)
	set_day(date_time_os.day)
	set_month(date_time_os.month)
	set_year(date_time_os.year)

func __repeat_full_cycle() -> void:
	if is_end_of_time() && total_hours >= 23.9999:
		set_year(1); set_month(1); set_day(1)
		set_total_hours(0.0)
		
	if is_begin_of_time() && total_hours < 0.0:
		set_year(9999); set_month(12); set_day(31)
		set_total_hours(23.9999)

func __check_cycle() -> void:
	if total_hours > 23.9999:
		set_day(day + 1)
		set_total_hours(0.0)
	if total_hours < 0.0000:
		set_day(day - 1)
		set_total_hours(23.9999)
	
	if day > max_days_per_month():
		set_month(month + 1)
		set_day(1)
	
	if day < 1:
		set_month(month - 1)
		set_day(31)
	
	if month > 12:
		set_year(year + 1)
		set_month(1)
	
	if month < 1:
		set_year(year - 1)
		set_month(12)

# Planetary
#----------------------------------------------------------
func __set_celestial_coords() -> void:
	if not __dome_found:
		return

	match celestials_calculations:
		CelestialCalculationsMode.Simple:
			__compute_simple_sun_coords()
			__dome.sun_altitude = __sun_coords.y
			__dome.sun_azimuth = __sun_coords.x
			if compute_moon_coords:
				__compute_simple_moon_coords()
				__dome.moon_altitude = __moon_coords.y
				__dome.moon_azimuth = __moon_coords.x
			
			if compute_deep_space_coords:
				var x = Quat(Vector3( (90 + latitude) * TOD_Math.DEG_TO_RAD, 0.0, 0.0))
				var y = Quat(Vector3(0.0, 0.0, __sun_coords.y * TOD_Math.DEG_TO_RAD))
				__dome.deep_space_quat = x * y
		
		CelestialCalculationsMode.Realistic:
			__compute_realistic_sun_coords()
			__dome.sun_altitude = __sun_coords.y * TOD_Math.RAD_TO_DEG
			__dome.sun_azimuth = __sun_coords.x * TOD_Math.RAD_TO_DEG
			if compute_moon_coords:
				__compute_realistic_moon_coords()
				__dome.moon_altitude = __moon_coords.y * TOD_Math.RAD_TO_DEG
				__dome.moon_azimuth = __moon_coords.x * TOD_Math.RAD_TO_DEG
			
			if compute_deep_space_coords:
				var x = Quat(Vector3( (90 + latitude) * TOD_Math.DEG_TO_RAD, 0.0, 0.0) )
				var y = Quat(Vector3(0.0, 0.0,  (180.0 - __local_sideral_time * TOD_Math.RAD_TO_DEG) * TOD_Math.DEG_TO_RAD)) 
				__dome.deep_space_quat = x * y

func __compute_simple_sun_coords() -> void:
	var altitude = (__get_total_hours_utc() + (TOD_Math.DEG_TO_RAD * longitude)) * (360/24)
	__sun_coords.y = (180.0 - altitude)
	__sun_coords.x = latitude

func __compute_simple_moon_coords() -> void:
	__moon_coords.y = (180.0 - __sun_coords.y) + moon_coords_offset.y
	__moon_coords.x = (180.0 + __sun_coords.x) + moon_coords_offset.x


func __compute_realistic_sun_coords() -> void:
	## Orbital Elements.
	__sun_orbital_elements.get_orbital_elements(0, __get_time_scale())
	__sun_orbital_elements.M = TOD_Math.rev(__sun_orbital_elements.M)
	
	# Mean anomaly in radians.
	var MRad: float = TOD_Math.DEG_TO_RAD * __sun_orbital_elements.M
	
	## Eccentric Anomaly
	var E: float = __sun_orbital_elements.M + TOD_Math.RAD_TO_DEG * __sun_orbital_elements.e *\
		sin(MRad) * (1 + __sun_orbital_elements.e * cos(MRad))
	
	var ERad: float = E * TOD_Math.DEG_TO_RAD
	
	## Rectangular coordinates.
	# Rectangular coordinates of the sun in the plane of the ecliptic.
	var xv: float = cos(ERad) - __sun_orbital_elements.e
	var yv: float = sin(ERad) * sqrt(1 - __sun_orbital_elements.e * __sun_orbital_elements.e)
	
	## Distance and true anomaly.
	# Convert to distance and true anomaly(r = radians, v = degrees).
	var r: float = sqrt(xv * xv + yv * yv)
	var v: float = TOD_Math.RAD_TO_DEG * atan2(yv, xv)
	__sun_distance = r
	
	## True longitude.
	var lonSun: float = v + __sun_orbital_elements.w
	lonSun = TOD_Math.rev(lonSun)
	
	var lonSunRad = TOD_Math.DEG_TO_RAD * lonSun
	__true_sun_longitude = lonSunRad
	
	## Ecliptic and ecuatorial coords.
	
	# Ecliptic rectangular coords.
	var xs: float = r * cos(lonSunRad)
	var ys: float = r * sin(lonSunRad)
	
	# Ecliptic rectangular coordinates rotate these to equatorial coordinates
	var obleclCos: float = cos(__get_oblecl())
	var obleclSin: float = sin(__get_oblecl())
	
	var xe: float = xs 
	var ye: float = ys * obleclCos - 0.0 * obleclSin
	var ze: float = ys * obleclSin + 0.0 * obleclCos
	
	## Ascencion and declination.
	var RA: float = TOD_Math.RAD_TO_DEG * atan2(ye, xe) / 15 # right ascension.
	var decl: float = atan2(ze, sqrt(xe * xe + ye * ye)) # declination
	
	# Mean longitude.
	var L: float = __sun_orbital_elements.w + __sun_orbital_elements.M
	L = TOD_Math.rev(L)
	
	__mean_sun_longitude = L
	
	## Sideral time and hour angle.
	var GMST0: float = ((L/15) + 12)
	__sideral_time = GMST0 + __get_total_hours_utc() + longitude / 15 # +15/15
	__local_sideral_time = TOD_Math.DEG_TO_RAD * __sideral_time * 15
	
	var HA: float = (__sideral_time - RA) * 15
	var HARAD: float = TOD_Math.DEG_TO_RAD * HA
	
	## Hour angle and declination in rectangular coords
	# HA and Decl in rectangular coords.
	var declCos: float = cos(decl)
	var x = cos(HARAD) * declCos # X Axis points to the celestial equator in the south.
	var y = sin(HARAD) * declCos # Y axis points to the horizon in the west.
	var z = sin(decl) # Z axis points to the north celestial pole.
	
	# Rotate the rectangualar coordinates system along of the Y axis.
	var sinLat: float = sin(latitude * TOD_Math.DEG_TO_RAD)
	var cosLat: float = cos(latitude * TOD_Math.DEG_TO_RAD)
	var xhor: float = x * sinLat - z * cosLat
	var yhor: float = y 
	var zhor: float = x * cosLat + z * sinLat
	
	## Azimuth and altitude.
	__sun_coords.x = atan2(yhor, xhor) + PI
	__sun_coords.y = (PI * 0.5) - asin(zhor) # atan2(zhor, sqrt(xhor * xhor + yhor * yhor))
	

func __compute_realistic_moon_coords() -> void:
	## Orbital Elements.
	__moon_orbital_elements.get_orbital_elements(1, __get_time_scale())
	__moon_orbital_elements.N = TOD_Math.rev(__moon_orbital_elements.N)
	__moon_orbital_elements.w = TOD_Math.rev(__moon_orbital_elements.w)
	__moon_orbital_elements.M = TOD_Math.rev(__moon_orbital_elements.M)
	
	var NRad: float = TOD_Math.DEG_TO_RAD * __moon_orbital_elements.N
	var IRad: float = TOD_Math.DEG_TO_RAD * __moon_orbital_elements.i
	var MRad: float = TOD_Math.DEG_TO_RAD * __moon_orbital_elements.M
	
	## Eccentric anomaly.
	var E: float = __moon_orbital_elements.M + TOD_Math.RAD_TO_DEG * __moon_orbital_elements.e * sin(MRad) *\
		(1 + __sun_orbital_elements.e * cos(MRad))
	
	var ERad = TOD_Math.DEG_TO_RAD * E
	
	## Rectangular coords and true anomaly
	# Rectangular coordinates of the sun in the plane of the ecliptic
	var xv: float = __moon_orbital_elements.a * (cos(ERad) - __moon_orbital_elements.e)
	var yv: float = __moon_orbital_elements.a * (sin(ERad) * sqrt(1 - __moon_orbital_elements.e * \
		__moon_orbital_elements.e)) * sin(ERad)
		
	# Convert to distance and true anomaly(r = radians, v = degrees)
	var r: float = sqrt(xv * xv + yv * yv)
	var v: float = TOD_Math.RAD_TO_DEG * atan2(yv, xv)
	v = TOD_Math.rev(v)
	
	var l: float = TOD_Math.DEG_TO_RAD * v + __moon_orbital_elements.w
	
	var cosL: float = cos(l)
	var sinL: float = sin(l)
	var cosNRad: float = cos(NRad)
	var sinNRad: float = sin(NRad)
	var cosIRad: float = cos(IRad)
	
	var xeclip: float = r * (cosNRad * cosL - sinNRad * sinL * cosIRad)
	var yeclip: float = r * (sinNRad * cosL + cosNRad * sinL * cosIRad)
	var zeclip: float = r * (sinL * sin(IRad))
	
	## Geocentric coords.
	# Geocentric position for the moon and Heliocentric position for the planets
	var lonecl: float = TOD_Math.RAD_TO_DEG * atan2(yeclip, xeclip)
	lonecl = TOD_Math.rev(lonecl)
	
	var latecl: float = TOD_Math.RAD_TO_DEG * atan2(zeclip, sqrt(xeclip * xeclip + yeclip * yeclip))
	
	# Get true sun longitude.
	var lonsun: float = __true_sun_longitude
	
	# Ecliptic longitude and latitude in radians
	var loneclRad: float = TOD_Math.DEG_TO_RAD * lonecl
	var lateclRad: float = TOD_Math.DEG_TO_RAD * latecl
	
	var nr: float = 1.0
	var xh: float = nr * cos(loneclRad) * cos(lateclRad)
	var yh: float = nr * sin(loneclRad) * cos(lateclRad)
	var zh: float = nr * sin(lateclRad)
	
	# Geocentric coords.
	var xs: float = 0.0
	var ys: float = 0.0
	
	# Convert the geocentric position to heliocentric position.
	var xg: float = xh + xs
	var yg: float = yh + ys
	var zg: float = zh
	
	## Ecuatorial coords.
	# Cobert xg, yg un equatorial coords.
	var obleclCos: float = cos(__get_oblecl())
	var obleclSin: float = sin(__get_oblecl())
	
	var xe: float = xg 
	var ye: float = yg * obleclCos - zg * obleclSin
	var ze: float = yg * obleclSin + zg * obleclCos
	
	# Right ascention.
	var RA: float = TOD_Math.RAD_TO_DEG * atan2(ye, xe)
	RA = TOD_Math.rev(RA)
	
	# Declination.
	var decl: float = TOD_Math.RAD_TO_DEG * atan2(ze, sqrt(xe * xe + ye * ye))
	var declRad: float = TOD_Math.DEG_TO_RAD * decl
	
	## Sideral time and hour angle.
	# Hour angle.
	var HA: float = ((__sideral_time * 15) - RA)
	HA = TOD_Math.rev(HA)
	var HARAD: float = TOD_Math.DEG_TO_RAD * HA
	
	# HA y Decl in rectangular coordinates.
	var declCos: float = cos(declRad)
	var xr: float = cos(HARAD) * declCos
	var yr: float = sin(HARAD) * declCos
	var zr: float = sin(declRad)
	
	# Rotate the rectangualar coordinates system along of the Y axis(radians).
	var sinLat: float = sin(__get_latitude_rad())
	var cosLat: float = cos(__get_latitude_rad())
	
	var xhor: float = xr * sinLat - zr * cosLat
	var yhor: float = yr 
	var zhor: float = xr * cosLat + zr * sinLat
	
	## Azimuth and altitude
	__moon_coords.x = atan2(yhor, xhor) + PI
	__moon_coords.y = (PI *0.5) - atan2(zhor, sqrt(xhor * xhor + yhor * yhor)) # Mathf.Asin(zhor)


func _get_property_list() -> Array:
	var ret: Array 
	ret.push_back({name = "Time Of Day", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY})
	
	ret.push_back({name = "Target", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP})
	ret.push_back({name = "dome_path", type=TYPE_NODE_PATH})
	
	ret.push_back({name = "DateTime", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP})
	ret.push_back({name = "system_sync", type=TYPE_BOOL})
		
	ret.push_back({name = "total_cycle_in_minutes", type=TYPE_REAL})
	ret.push_back({name = "total_hours", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0.0, 24.0"})
	ret.push_back({name = "day", type=TYPE_INT, hint=PROPERTY_HINT_RANGE, hint_string="0, 31"})
	ret.push_back({name = "month", type=TYPE_INT, hint=PROPERTY_HINT_RANGE, hint_string="0, 12"})
	ret.push_back({name = "year", type=TYPE_INT, hint=PROPERTY_HINT_RANGE, hint_string="-9999, 9999"})

	ret.push_back({name = "Planetary And Location", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP})
	ret.push_back({name = "celestials_calculations", type=TYPE_INT, hint=PROPERTY_HINT_ENUM, hint_string="Simple, Realistic"})
	ret.push_back({name = "compute_moon_coords", type=TYPE_BOOL})

	if celestials_calculations == 0 && compute_moon_coords:
		ret.push_back({name = "moon_coords_offset", type=TYPE_VECTOR2})
		
	ret.push_back({name = "compute_deep_space_coords", type=TYPE_BOOL})
	ret.push_back({name = "latitude", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="-90.0, 90.0"})
	ret.push_back({name = "longitude", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="-180.0, 180.0"})
	ret.push_back({name = "utc", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="-12.0, 12.0"})
	ret.push_back({name = "celestials_update_time", type=TYPE_REAL})
	
	return ret
