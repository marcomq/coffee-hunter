class_name InputResolver
extends RefCounted

const DEADZONE := 0.32
const RELEASE_ZONE := 0.20
var _latched_direction := Vector2i.ZERO


func direction_from_vector(value: Vector2) -> Vector2i:
	var magnitude := value.length()
	if magnitude < RELEASE_ZONE:
		_latched_direction = Vector2i.ZERO
		return _latched_direction
	if magnitude < DEADZONE and _latched_direction == Vector2i.ZERO:
		return Vector2i.ZERO

	if absf(value.x) > absf(value.y):
		_latched_direction = Vector2i(signf(value.x), 0)
	else:
		_latched_direction = Vector2i(0, signf(value.y))
	return _latched_direction


func combined_vector(virtual_tilt: Vector2) -> Vector2:
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if keyboard.length_squared() > 0.0:
		return keyboard

	var gravity := Input.get_gravity()
	var device_tilt := Vector2(gravity.x, -gravity.y) / 9.81
	if device_tilt.length() >= DEADZONE:
		return device_tilt.limit_length(1.0)
	return virtual_tilt.limit_length(1.0)

