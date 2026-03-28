class_name InputActionMap
extends RefCounted

const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"
const MOVE_FORWARD := "move_forward"
const MOVE_BACKWARD := "move_backward"
const HARD_DROP := "hard_drop"
const RESTART := "restart_run"
const ROTATE_Y_CW := "rotate_y_cw"
const ROTATE_Y_CCW := "rotate_y_ccw"
const ROTATE_X_CW := "rotate_x_cw"
const ROTATE_X_CCW := "rotate_x_ccw"
const ROTATE_Z_CW := "rotate_z_cw"
const ROTATE_Z_CCW := "rotate_z_ccw"
const ROTATE_Y_SWIPE_AXIS_RATIO := 2.1


static func ensure_default_actions() -> void:
	_add_action(MOVE_LEFT, [KEY_A, KEY_LEFT])
	_add_action(MOVE_RIGHT, [KEY_D, KEY_RIGHT])
	_add_action(MOVE_FORWARD, [KEY_W, KEY_UP])
	_add_action(MOVE_BACKWARD, [KEY_S, KEY_DOWN])
	_add_action(HARD_DROP, [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER])
	_add_action(RESTART, [KEY_R])
	_add_action(ROTATE_Y_CW, [KEY_E])
	_add_action(ROTATE_Y_CCW, [KEY_Q])
	_add_action(ROTATE_X_CW, [KEY_I])
	_add_action(ROTATE_X_CCW, [KEY_K])
	_add_action(ROTATE_Z_CW, [KEY_O])
	_add_action(ROTATE_Z_CCW, [KEY_U])


static func action_for_swipe(delta: Vector2) -> String:
	if delta.length() < 36.0:
		return ""
	var abs_x := absf(delta.x)
	var abs_y := absf(delta.y)
	if abs_x > abs_y * ROTATE_Y_SWIPE_AXIS_RATIO:
		return ROTATE_Y_CW if delta.x > 0.0 else ROTATE_Y_CCW
	if delta.x >= 0.0 and delta.y <= 0.0:
		return ROTATE_X_CCW
	if delta.x <= 0.0 and delta.y >= 0.0:
		return ROTATE_X_CW
	if delta.x >= 0.0 and delta.y >= 0.0:
		return ROTATE_Z_CCW
	return ROTATE_Z_CW


static func _add_action(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	else:
		InputMap.action_erase_events(action_name)
	for keycode in keys:
		var event := InputEventKey.new()
		if keycode == KEY_SHIFT:
			event.keycode = keycode
		else:
			event.physical_keycode = keycode
		if not InputMap.action_has_event(action_name, event):
			InputMap.action_add_event(action_name, event)
