class_name TouchControls
extends Control

# On-screen controls for touch devices. Movement comes from a joystick that
# anchors wherever the left thumb lands; every menu key gets a round button on
# the right.
#
# A tap queues its action name instead of calling Input.action_press. The engine
# stamps an injected press with the frame it happened on, and a touch is parsed
# outside the physics tick, so is_action_just_pressed could miss it entirely -
# which is exactly how PLAY came to do nothing. main.gd drains the queue once per
# physics frame, so a tap is seen on the very next one, whenever it landed.
#
# Screen touches are read raw rather than through the emulated mouse: emulation
# only follows the first finger, which would make holding the joystick and
# tapping THROW mutually exclusive.
#
# They are read in _input, not _unhandled_input: the menu overlay lays a
# full-screen ColorRect over the viewport, and a Control that stops the mouse
# swallows the touch with it, so nothing below the GUI ever saw a tap while a
# menu was up. Reading early means claiming carefully - an event is consumed
# only when it actually lands on the pad, so the name and address fields keep
# taking taps of their own.

signal pressed(id: StringName)

# Full tilt at 90px from the origin - the same span as the mouse drag.
const TILT_SPAN := 90.0
const RING_RADIUS := 58.0
const KNOB_RADIUS := 24.0
# Where the thumb is invited to land before it has ever landed.
const STICK_HOME := Vector2(150.0, 402.0)
# Everything sits on a dark disc first: the board underneath runs from pale sand
# to near black, and a plain translucent white washes out over the light half.
const BACKING := Color(0.05, 0.03, 0.02, 0.62)
const EDGE := Color("ffd27a")
const FACE := Color(1, 1, 1, 0.18)
const LABEL := Color("fff3df")
# The joystick only claims the half of the screen the board sits under, so a
# stray tap near the buttons never drags the hero.
const JOYSTICK_ZONE := 0.55
const PLACES := {
	&"primary": {"center": Vector2(886, 462), "radius": 52.0},
	&"secondary": {"center": Vector2(770, 486), "radius": 38.0},
	&"corner": {"center": Vector2(44, 44), "radius": 30.0},
}

var tilt := Vector2.ZERO
# Set by main while a run is on screen. The hint retires once the stick has been
# used, so it teaches without becoming clutter.
# The stick listens only while a run is on screen. In the menus the same half of
# the display is covered by text fields, and a drag there must reach them.
var stick_live := false:
	set(value):
		stick_live = value
		if not value:
			_move_finger = -1
			tilt = Vector2.ZERO
		queue_redraw()

var _stick_used := false

var _buttons: Array[Dictionary] = []
var _fired: Array[StringName] = []
var _move_finger := -1
var _move_origin := Vector2.ZERO
# Finger index -> index into _buttons, so several buttons can be held at once.
var _held: Dictionary[int, int] = {}


var _mouse_stands_in := false


static func wanted() -> bool:
	return _has_touchscreen() or OS.get_cmdline_user_args().has("--touch-ui")


static func _has_touchscreen() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


func _ready() -> void:
	# Godot reads emulate_touch_from_mouse once at startup, so a desktop run of
	# --touch-ui never sees a screen touch. The mouse takes the place of finger 0
	# there, which is what makes the pad checkable without a phone.
	_mouse_stands_in = not _has_touchscreen()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The lobby's text fields still ride on the emulated mouse, so this layer
	# never takes it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = wanted()


func set_buttons(specs: Array) -> void:
	_release_all()
	_buttons.clear()
	for spec: Dictionary in specs:
		var place: StringName = spec.get("place", &"primary")
		var geometry: Dictionary = PLACES[place]
		_buttons.append({
			"id": spec.get("id", &""),
			"label": String(spec.get("label", "")),
			"action": spec.get("action", &""),
			"center": geometry["center"],
			"radius": geometry["radius"],
		})
	queue_redraw()


# Visibility is the single switch: no listening while the pad is not shown.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process_input(visible)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all()
		_move_finger = -1
		tilt = Vector2.ZERO
		queue_redraw()


func _input(event: InputEvent) -> void:
	var consumed := false
	if event is InputEventScreenTouch:
		# A real finger retires the stand-in for good, or the emulated mouse that
		# trails it would fire every button a second time.
		_mouse_stands_in = false
		consumed = _begin_touch(event.index, event.position) if event.pressed else _end_touch(event.index)
	elif event is InputEventScreenDrag:
		consumed = _drag(event.index, event.position)
	elif _mouse_stands_in and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		consumed = _begin_touch(0, event.position) if event.pressed else _end_touch(0)
	elif _mouse_stands_in and event is InputEventMouseMotion:
		consumed = _drag(0, event.position)
	if consumed:
		get_viewport().set_input_as_handled()


func _drag(index: int, position: Vector2) -> bool:
	if index != _move_finger:
		return false
	tilt = ((position - _move_origin) / TILT_SPAN).limit_length(1.0)
	queue_redraw()
	return true


func _begin_touch(index: int, position: Vector2) -> bool:
	var hit := _button_at(position)
	if hit >= 0:
		_held[index] = hit
		var action: StringName = _buttons[hit]["action"]
		if action != &"":
			_fired.append(action)
		pressed.emit(_buttons[hit]["id"])
		queue_redraw()
		return true
	if stick_live and _move_finger == -1 and position.x < size.x * JOYSTICK_ZONE:
		_move_finger = index
		_move_origin = position
		_stick_used = true
		tilt = Vector2.ZERO
		queue_redraw()
		return true
	return false


func _end_touch(index: int) -> bool:
	if _held.has(index):
		_held.erase(index)
		queue_redraw()
		return true
	if index == _move_finger:
		_move_finger = -1
		tilt = Vector2.ZERO
		queue_redraw()
		return true
	return false


func _button_at(position: Vector2) -> int:
	for index in range(_buttons.size()):
		var button := _buttons[index]
		# A little slack around the circle: fingers are wider than the drawing.
		if position.distance_to(button["center"]) <= float(button["radius"]) + 8.0:
			return index
	return -1


# Everything a tap triggers since the last physics frame, handed over once.
func take_fired() -> Array[StringName]:
	if _fired.is_empty():
		return _fired
	var taken := _fired
	_fired = []
	return taken


# Only the lit-up look is held; swapping the button set mid-press must not leave
# a stale index pointing into the new array.
func _release_all() -> void:
	_held.clear()


func _draw() -> void:
	if _move_finger != -1:
		_draw_stick(_move_origin, tilt, 1.0)
	elif stick_live and not _stick_used:
		_draw_stick(STICK_HOME, Vector2.ZERO, 0.55)
	var down := _held.values()
	for index in range(_buttons.size()):
		_draw_button(_buttons[index], down.has(index))


func _draw_stick(center: Vector2, offset: Vector2, strength: float) -> void:
	draw_circle(center, RING_RADIUS, Color(BACKING, BACKING.a * strength))
	draw_arc(center, RING_RADIUS, 0.0, TAU, 64, Color(EDGE, 0.75 * strength), 3.0, true)
	# A second, dimmer ring reads as a rim and keeps the disc from disappearing
	# into a dark tunnel.
	draw_arc(center, RING_RADIUS - 4.0, 0.0, TAU, 64, Color(0, 0, 0, 0.35 * strength), 2.0, true)
	var knob := center + offset * (RING_RADIUS - KNOB_RADIUS * 0.5)
	draw_circle(knob, KNOB_RADIUS, Color(EDGE, 0.92 * strength))
	draw_arc(knob, KNOB_RADIUS, 0.0, TAU, 32, Color(0.16, 0.09, 0.05, 0.85 * strength), 2.0, true)


func _draw_button(button: Dictionary, is_down: bool) -> void:
	var center: Vector2 = button["center"]
	var radius: float = button["radius"]
	draw_circle(center, radius, BACKING)
	draw_circle(center, radius, Color(EDGE, 0.85) if is_down else FACE)
	draw_arc(center, radius, 0.0, TAU, 64, Color(EDGE, 0.95 if is_down else 0.8), 3.0, true)
	draw_arc(center, radius - 4.0, 0.0, TAU, 64, Color(0, 0, 0, 0.3), 2.0, true)
	var font := ThemeDB.fallback_font
	var label: String = button["label"]
	var font_size := 15
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := center + Vector2(-width * 0.5, 5.0)
	var ink := Color("2a1a12") if is_down else LABEL
	if not is_down:
		draw_string(font, origin + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
	draw_string(font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
