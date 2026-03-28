extends Node3D

const GameRulesScript = preload("res://scripts/core/game_rules.gd")
const RunStateScript = preload("res://scripts/core/run_state.gd")
const InputActionMapScript = preload("res://scripts/core/input_action_map.gd")

const CELL_SCALE := 0.92
const BOARD_BOUNDS_MIN := Vector3(-0.5, -0.5, -0.5)
const BOARD_BOUNDS_MAX := Vector3(9.5, 19.5, 9.5)
const CAMERA_LOOK_TARGET := Vector3(4.5, 9.5, 4.5)
const CAMERA_NEAR_CORNER := Vector3(22.0, 26.0, 22.0)
const CAMERA_FAR_CORNER := Vector3(-13.0, 26.0, -13.0)
const CAMERA_SWAP_DURATION := 0.22
const CAMERA_FIT_PADDING := 0.85
const CAMERA_SWAP_WORLD_YAW_MAX := 0.18
const NEXT_STAGE_HORIZONTAL_OFFSET := 11.8
const NEXT_STAGE_VERTICAL_OFFSET := -2.2
const NEXT_STAGE_DEPTH_OFFSET := -0.4
const NEXT_STAGE_BOUNDS_EXTENTS := Vector3(2.8, 2.6, 2.8)
const TAP_MAX_DISTANCE := 24.0
const DOUBLE_TAP_MAX_INTERVAL_MS := 320
const CLEAR_FLASH_CYCLES := 3.0
const COLOR_BG := Color("#060815")
const COLOR_BG_DEEP := Color("#02030a")
const COLOR_STAGE := Color("#09112a")
const COLOR_STAGE_STRIPE := Color("#101b46")
const COLOR_PANEL := Color("#0a1130")
const COLOR_PANEL_SOFT := Color("#121a49")
const COLOR_PANEL_EDGE := Color("#40f5ff")
const COLOR_PANEL_ACCENT := Color("#ff4fd8")
const COLOR_TEXT_PRIMARY := Color("#ddfcff")
const COLOR_TEXT_MUTED := Color("#8fb6ff")
const COLOR_TEXT_STATUS := Color("#8cff59")
const COLOR_TEXT_ACTION := Color("#071123")
const COLOR_ACCENT := Color("#5bf8ff")
const COLOR_ACCENT_SOFT := Color("#3b6bff")
const COLOR_CLEAR := Color("#d0ff59")
const COLOR_WELL := Color("#05091c")
const COLOR_WELL_EDGE := Color("#56f4ff")
const COLOR_WELL_GRID := Color("#1f57d0")
const HUD_DEBUG_ENABLED := false
const STARTUP_STATUS_LOADING := "LOADING"
const STARTUP_STATUS_RENDER := "PREPARING RENDER"
const STARTUP_STATUS_SCENE := "BUILDING STAGE"
const STARTUP_STATUS_RUN := "STARTING RUN"
const TUTORIAL_STEP_COUNT := 13
var run_state: RefCounted
var fall_accumulator: float = 0.0
var touch_start := Vector2.ZERO
var touch_peak_delta := Vector2.ZERO
var touch_active := false
var touch_region := ""
var pointer_captured_by_ui := false
var swipe_blockers: Array[Control] = []
var pause_board_open := false
var tutorial_active := false
var tutorial_completed := false
var tutorial_step := 0
var tutorial_finishing := false
var tutorial_snapshots := {}
var view_flipped := false
var last_tap_time_ms := -1000
var last_tap_position := Vector2.ZERO
var camera_transition_active := false
var camera_transition_elapsed := 0.0
var camera_transition_from := CAMERA_NEAR_CORNER
var camera_transition_to := CAMERA_NEAR_CORNER
var camera_transition_target_flipped := false
var current_camera_position := CAMERA_NEAR_CORNER
var board_transition_yaw := 0.0

var world_root: Node3D
var board_root: Node3D
var floor_guide_root: Node3D
var locked_root: Node3D
var active_root: Node3D
var ghost_root: Node3D
var next_preview_root: Node3D
var next_preview_piece_root: Node3D
var hud_labels := {}
var camera_node: Camera3D
var hud_root: Control
var startup_phase := -1
var startup_complete := false
var startup_layer: CanvasLayer
var startup_status_label: Label
var display_filter_material: ShaderMaterial

var cube_mesh := BoxMesh.new()
var locked_material := StandardMaterial3D.new()
var frame_material := StandardMaterial3D.new()
var floor_grid_material := StandardMaterial3D.new()
var shadow_material := StandardMaterial3D.new()
var well_panel_material := StandardMaterial3D.new()


func _ready() -> void:
	InputActionMapScript.ensure_default_actions()
	_build_startup_shell()
	_begin_startup()


func _process(delta: float) -> void:
	if not startup_complete:
		return
	if run_state == null:
		return
	_advance_camera_transition(delta)
	if camera_transition_active:
		touch_active = false
		pointer_captured_by_ui = false
		_refresh_view()
		return
	if run_state.is_clearing():
		touch_active = false
		pointer_captured_by_ui = false
		run_state.advance_clear(delta)
		_refresh_view()
		return
	if pause_board_open:
		touch_active = false
		pointer_captured_by_ui = false
		_refresh_view()
		return
	if tutorial_active:
		_refresh_view()
		return
	_handle_continuous_input()
	if not run_state.game_over:
		fall_accumulator += delta
		var interval: float = run_state.current_fall_interval()
		while fall_accumulator >= interval:
			fall_accumulator -= interval
			run_state.tick()
			if run_state.game_over:
				break
	_refresh_view()


func _input(event: InputEvent) -> void:
	if not startup_complete:
		touch_active = false
		pointer_captured_by_ui = false
		return
	if camera_transition_active:
		touch_active = false
		pointer_captured_by_ui = false
		return
	if run_state != null and run_state.is_clearing():
		if event.is_action_pressed(InputActionMapScript.RESTART):
			_start_run()
		touch_active = false
		pointer_captured_by_ui = false
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			pointer_captured_by_ui = _is_over_swipe_blocker(event.position)
			if pointer_captured_by_ui:
				_set_swipe_debug("Touch start blocked by button")
				return
			touch_start = event.position
			touch_peak_delta = Vector2.ZERO
			touch_active = true
			touch_region = _swipe_region_for_position(event.position)
			_set_swipe_debug("Touch start %s %s" % [touch_region, _format_vector(event.position)])
		elif touch_active:
			touch_active = false
			_handle_touch_release(event.position)
		else:
			pointer_captured_by_ui = false
	elif event is InputEventScreenDrag:
		if touch_active:
			var drag_delta: Vector2 = event.position - touch_start
			_update_touch_peak_delta(drag_delta)
			_set_swipe_debug("Touch drag %s %s peak %s" % [touch_region, _format_vector(drag_delta), _format_vector(touch_peak_delta)])
		return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pointer_captured_by_ui = _is_over_swipe_blocker(event.position)
		if pointer_captured_by_ui:
			_set_swipe_debug("Mouse start blocked by button")
			return
		touch_start = event.position
		touch_peak_delta = Vector2.ZERO
		touch_active = true
		touch_region = _swipe_region_for_position(event.position)
		_set_swipe_debug("Mouse start %s %s" % [touch_region, _format_vector(event.position)])
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if touch_active:
			touch_active = false
			_handle_touch_release(event.position)
		pointer_captured_by_ui = false
	elif event is InputEventMouseMotion and touch_active:
		var drag_delta: Vector2 = event.position - touch_start
		_update_touch_peak_delta(drag_delta)
		_set_swipe_debug("Mouse drag %s %s peak %s" % [touch_region, _format_vector(drag_delta), _format_vector(touch_peak_delta)])
	elif tutorial_active:
		return
	elif pause_board_open:
		return
	elif event.is_action_pressed(InputActionMapScript.HARD_DROP):
		_button_drop()
	elif event.is_action_pressed(InputActionMapScript.RESTART):
		_start_run()
	elif event.is_action_pressed(InputActionMapScript.ROTATE_Y_CW):
		_request_rotation("y", 1)
	elif event.is_action_pressed(InputActionMapScript.ROTATE_Y_CCW):
		_request_rotation("y", -1)
	elif event.is_action_pressed(InputActionMapScript.ROTATE_X_CW):
		_request_rotation("x", 1)
	elif event.is_action_pressed(InputActionMapScript.ROTATE_X_CCW):
		_request_rotation("x", -1)
	elif event.is_action_pressed(InputActionMapScript.ROTATE_Z_CW):
		_request_rotation("z", 1)
	elif event.is_action_pressed(InputActionMapScript.ROTATE_Z_CCW):
		_request_rotation("z", -1)


func _handle_continuous_input() -> void:
	if run_state == null or run_state.game_over or camera_transition_active:
		return
	if pause_board_open:
		return
	if Input.is_action_just_pressed(InputActionMapScript.MOVE_LEFT):
		_request_move(Vector3i(-1, 0, 0))
	if Input.is_action_just_pressed(InputActionMapScript.MOVE_RIGHT):
		_request_move(Vector3i(1, 0, 0))
	if Input.is_action_just_pressed(InputActionMapScript.MOVE_FORWARD):
		_request_move(Vector3i(0, 0, -1))
	if Input.is_action_just_pressed(InputActionMapScript.MOVE_BACKWARD):
		_request_move(Vector3i(0, 0, 1))


func _handle_touch_release(position: Vector2) -> void:
	var release_delta := position - touch_start
	var swipe_delta := strongest_swipe_delta(release_delta, touch_peak_delta)
	if tutorial_active:
		if _is_double_tap(position, release_delta):
			_handle_tutorial_double_tap()
			return
		_set_swipe_debug("Tutorial release %s final %s peak %s" % [touch_region, _format_vector(release_delta), _format_vector(swipe_delta)])
		_handle_tutorial_swipe(swipe_delta, touch_region)
		return
	if _gameplay_locked():
		return
	if _is_double_tap(position, release_delta):
		_toggle_view()
		_set_swipe_debug("Double tap -> swap view")
		return
	_set_swipe_debug("Release %s final %s peak %s" % [touch_region, _format_vector(release_delta), _format_vector(swipe_delta)])
	_handle_swipe(swipe_delta, touch_region)


func _handle_swipe(delta: Vector2, region: String) -> void:
	if region == "left":
		var action: String = InputActionMapScript.action_for_swipe(delta)
		_set_swipe_debug("Swipe %s %s -> %s" % [region, _format_vector(delta), _describe_swipe_action(action)])
		match action:
			InputActionMapScript.ROTATE_Y_CW:
				_request_rotation("y", 1)
			InputActionMapScript.ROTATE_Y_CCW:
				_request_rotation("y", -1)
			InputActionMapScript.ROTATE_X_CW:
				_request_rotation("x", 1)
			InputActionMapScript.ROTATE_X_CCW:
				_request_rotation("x", -1)
			InputActionMapScript.ROTATE_Z_CW:
				_request_rotation("z", 1)
			InputActionMapScript.ROTATE_Z_CCW:
				_request_rotation("z", -1)
		return

	var movement: Vector3i = _movement_delta_for_swipe(delta)
	_set_swipe_debug("Swipe %s %s -> %s" % [region, _format_vector(delta), _describe_movement_delta(movement)])
	if movement != Vector3i.ZERO:
		_request_move(movement)


func _start_run() -> void:
	_start_run_with_seed(0)


func _start_run_with_seed(seed: int) -> void:
	var rules := GameRulesScript.new()
	run_state = RunStateScript.new(rules) if seed == 0 else RunStateScript.new(rules, seed)
	fall_accumulator = 0.0
	pause_board_open = false
	camera_transition_active = false
	camera_transition_elapsed = 0.0
	camera_transition_target_flipped = view_flipped
	board_transition_yaw = 0.0
	_refresh_view()


func _begin_intro_tutorial() -> void:
	tutorial_active = true
	tutorial_completed = false
	tutorial_finishing = false
	tutorial_step = 0
	_prepare_tutorial_snapshots()
	_restore_tutorial_snapshot("movement")
	pause_board_open = false
	touch_active = false
	pointer_captured_by_ui = false
	_reset_tap_tracking()
	_refresh_view()


func _advance_intro_tutorial() -> void:
	var completed_step := tutorial_step
	tutorial_step += 1
	touch_active = false
	pointer_captured_by_ui = false
	_reset_tap_tracking()
	if tutorial_step >= TUTORIAL_STEP_COUNT:
		_complete_intro_tutorial()
		return
	match completed_step:
		3:
			_restore_tutorial_snapshot("rotation")
		9:
			_restore_tutorial_snapshot("final_clean")
		10:
			_restore_tutorial_snapshot("final_clean")
	_refresh_view()


func _complete_intro_tutorial() -> void:
	tutorial_step = TUTORIAL_STEP_COUNT - 1
	pause_board_open = false
	touch_active = false
	pointer_captured_by_ui = false
	_reset_tap_tracking()
	if view_flipped:
		tutorial_finishing = true
		_toggle_view()
	else:
		_finalize_intro_tutorial()
	_refresh_view()


func _dismiss_tutorial_for_automation() -> void:
	if not tutorial_active and not tutorial_finishing:
		return
	tutorial_active = false
	tutorial_completed = true
	tutorial_finishing = false
	tutorial_step = TUTORIAL_STEP_COUNT - 1
	pause_board_open = false
	touch_active = false
	pointer_captured_by_ui = false
	tutorial_snapshots.clear()
	_reset_tap_tracking()
	_set_camera_view_immediate(false)
	_refresh_view()


func _finalize_intro_tutorial() -> void:
	tutorial_active = false
	tutorial_completed = true
	tutorial_finishing = false
	tutorial_step = TUTORIAL_STEP_COUNT - 1
	pause_board_open = false
	touch_active = false
	pointer_captured_by_ui = false
	tutorial_snapshots.clear()
	_reset_tap_tracking()
	_set_camera_view_immediate(false)
	_refresh_view()


func _prepare_tutorial_snapshots() -> void:
	if run_state == null:
		return
	tutorial_snapshots.clear()
	run_state.set_board_cells_for_test([])
	run_state.set_active_piece_for_test("T", Vector3i(4, 18, 4))
	tutorial_snapshots["movement"] = run_state.snapshot_for_test()
	run_state.set_board_cells_for_test([])
	run_state.set_active_piece_for_test("L", Vector3i(4, 18, 4))
	tutorial_snapshots["rotation"] = run_state.snapshot_for_test()
	run_state.set_board_cells_for_test([])
	run_state.set_active_piece_for_test("T", Vector3i(4, 18, 4))
	tutorial_snapshots["final_clean"] = run_state.snapshot_for_test()


func _restore_tutorial_snapshot(key: String) -> void:
	if run_state == null or not tutorial_snapshots.has(key):
		return
	run_state.load_snapshot_for_test(tutorial_snapshots[key])


func _tutorial_step_data(step_index: int = tutorial_step) -> Dictionary:
	var steps: Array[Dictionary] = [
		{
			"kind": "move",
			"expected_move": Vector3i(1, 0, 0),
			"region": "right",
			"instruction": "MOVE DOWN-RIGHT",
			"helper": "RIGHT HALF",
			"hint": "↘"
		},
		{
			"kind": "move",
			"expected_move": Vector3i(-1, 0, 0),
			"region": "right",
			"instruction": "MOVE UP-LEFT",
			"helper": "RIGHT HALF",
			"hint": "↖"
		},
		{
			"kind": "move",
			"expected_move": Vector3i(0, 0, 1),
			"region": "right",
			"instruction": "MOVE DOWN-LEFT",
			"helper": "RIGHT HALF",
			"hint": "↙"
		},
		{
			"kind": "move",
			"expected_move": Vector3i(0, 0, -1),
			"region": "right",
			"instruction": "MOVE UP-RIGHT",
			"helper": "RIGHT HALF",
			"hint": "↗"
		},
		{
			"kind": "rotate",
			"expected_action": InputActionMapScript.ROTATE_X_CW,
			"region": "left",
			"instruction": "SWIPE DOWN-LEFT",
			"helper": "LEFT HALF",
			"hint": "↙"
		},
		{
			"kind": "rotate",
			"expected_action": InputActionMapScript.ROTATE_X_CCW,
			"region": "left",
			"instruction": "SWIPE UP-RIGHT",
			"helper": "LEFT HALF",
			"hint": "↗"
		},
		{
			"kind": "rotate",
			"expected_action": InputActionMapScript.ROTATE_Z_CW,
			"region": "left",
			"instruction": "SWIPE UP-LEFT",
			"helper": "LEFT HALF",
			"hint": "↖"
		},
		{
			"kind": "rotate",
			"expected_action": InputActionMapScript.ROTATE_Z_CCW,
			"region": "left",
			"instruction": "SWIPE DOWN-RIGHT",
			"helper": "LEFT HALF",
			"hint": "↘"
		},
		{
			"kind": "rotate",
			"expected_action": InputActionMapScript.ROTATE_Y_CW,
			"region": "left",
			"instruction": "ROTATE RIGHT",
			"helper": "LEFT HALF",
			"hint": "→"
		},
		{
			"kind": "rotate",
			"expected_action": InputActionMapScript.ROTATE_Y_CCW,
			"region": "left",
			"instruction": "ROTATE LEFT",
			"helper": "LEFT HALF",
			"hint": "←"
		},
		{
			"kind": "drop",
			"instruction": "TAP DROP",
			"helper": "",
			"hint": "TAP"
		},
		{
			"kind": "camera",
			"instruction": "DOUBLE TAP TO SWAP",
			"helper": "",
			"hint": "TAP x2"
		},
		{
			"kind": "start",
			"instruction": "DOUBLE TAP TO START",
			"helper": "",
			"hint": "TAP x2"
		}
	]
	if step_index < 0 or step_index >= steps.size():
		return {}
	return steps[step_index]


func _tutorial_instruction_text() -> String:
	var data := _tutorial_step_data()
	return String(data.get("instruction", ""))


func _tutorial_helper_text() -> String:
	var data := _tutorial_step_data()
	return String(data.get("helper", ""))


func _tutorial_hint_text() -> String:
	var data := _tutorial_step_data()
	return String(data.get("hint", ""))


func _tutorial_hint_font_size() -> int:
	var kind: String = String(_tutorial_step_data().get("kind", ""))
	match kind:
		"drop":
			return 22
		"camera", "start":
			return 28
		_:
			return 70


func _tutorial_progress_text() -> String:
	return "%d/%d" % [tutorial_step + 1, TUTORIAL_STEP_COUNT]


func _handle_tutorial_swipe(delta: Vector2, region: String) -> void:
	var data := _tutorial_step_data()
	var kind: String = data.get("kind", "")
	var expected_region: String = data.get("region", "")
	if expected_region != "" and region != expected_region:
		return
	if kind == "move":
		var movement: Vector3i = _movement_delta_for_swipe(delta)
		if movement == data.get("expected_move", Vector3i.ZERO) and _apply_tutorial_move(movement):
			_set_swipe_debug("Tutorial move complete")
			_advance_intro_tutorial()
		return
	if kind == "rotate":
		var action: String = InputActionMapScript.action_for_swipe(delta)
		if action == data.get("expected_action", "") and _apply_tutorial_rotation(action):
			_set_swipe_debug("Tutorial rotate complete")
			_advance_intro_tutorial()


func _apply_tutorial_move(delta: Vector3i) -> bool:
	if run_state == null:
		return false
	return run_state.move_active(view_relative_movement(delta))


func _apply_tutorial_rotation(action: String) -> bool:
	if run_state == null:
		return false
	match action:
		InputActionMapScript.ROTATE_X_CW:
			return run_state.rotate_active("x", view_relative_rotation_direction("x", 1))
		InputActionMapScript.ROTATE_X_CCW:
			return run_state.rotate_active("x", view_relative_rotation_direction("x", -1))
		InputActionMapScript.ROTATE_Z_CW:
			return run_state.rotate_active("z", view_relative_rotation_direction("z", 1))
		InputActionMapScript.ROTATE_Z_CCW:
			return run_state.rotate_active("z", view_relative_rotation_direction("z", -1))
		InputActionMapScript.ROTATE_Y_CW:
			return run_state.rotate_active("y", view_relative_rotation_direction("y", 1))
		InputActionMapScript.ROTATE_Y_CCW:
			return run_state.rotate_active("y", view_relative_rotation_direction("y", -1))
	return false


func _handle_tutorial_double_tap() -> void:
	match _tutorial_step_data().get("kind", ""):
		"camera":
			_set_swipe_debug("Tutorial camera swap complete")
			_toggle_view()
			_advance_intro_tutorial()
		"start":
			_set_swipe_debug("Tutorial start complete")
			_complete_intro_tutorial()


func _set_camera_view_immediate(is_flipped: bool) -> void:
	view_flipped = is_flipped
	camera_transition_active = false
	camera_transition_elapsed = 0.0
	camera_transition_target_flipped = is_flipped
	board_transition_yaw = 0.0
	current_camera_position = _camera_position_for_view(view_flipped)
	camera_transition_from = current_camera_position
	camera_transition_to = current_camera_position
	_apply_camera_view(current_camera_position)


func _reset_tap_tracking() -> void:
	last_tap_time_ms = -1000
	last_tap_position = Vector2.ZERO


func _build_startup_shell() -> void:
	if startup_layer != null:
		return
	startup_layer = CanvasLayer.new()
	startup_layer.name = "StartupShell"
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	startup_layer.add_child(root)

	var card := Panel.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.position = Vector2(-110.0, -44.0)
	card.size = Vector2(220.0, 88.0)
	card.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL_SOFT, COLOR_PANEL_EDGE, 3))
	root.add_child(card)

	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 10.0)
	title.size = Vector2(card.size.x, 24.0)
	title.text = "PENTRIS"
	title.modulate = COLOR_PANEL_EDGE
	title.add_theme_font_size_override("font_size", 18)
	card.add_child(title)

	var status := Label.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.position = Vector2(12.0, 44.0)
	status.size = Vector2(card.size.x - 24.0, 18.0)
	status.text = STARTUP_STATUS_LOADING
	status.modulate = COLOR_TEXT_PRIMARY
	status.add_theme_font_size_override("font_size", 12)
	card.add_child(status)
	startup_status_label = status

	add_child(startup_layer)


func _begin_startup() -> void:
	startup_phase = 0
	startup_complete = false
	call_deferred("_run_startup_phase")


func _run_startup_phase() -> void:
	if startup_complete:
		return
	match startup_phase:
		0:
			_set_startup_status(STARTUP_STATUS_RENDER)
			_configure_materials()
			startup_phase = 1
			call_deferred("_run_startup_phase")
		1:
			_set_startup_status(STARTUP_STATUS_SCENE)
			_build_scene()
			startup_phase = 2
			call_deferred("_run_startup_phase")
		2:
			_set_startup_status(STARTUP_STATUS_RUN)
			_start_run()
			_begin_intro_tutorial()
			startup_complete = true
			startup_phase = 3
			_refresh_view()
			_hide_startup_shell()


func _finish_startup() -> void:
	if startup_layer == null:
		_build_startup_shell()
	if startup_phase < 0:
		_begin_startup()
	while not startup_complete:
		_run_startup_phase()


func _set_startup_status(text: String) -> void:
	if startup_status_label != null:
		startup_status_label.text = text


func _hide_startup_shell() -> void:
	if startup_layer != null:
		startup_layer.visible = false


func prepare_visual_scenario(name: String) -> bool:
	_finish_startup()
	_dismiss_tutorial_for_automation()
	_start_run_with_seed(1)
	_set_camera_view_immediate(false)
	_set_swipe_debug("Visual scenario %s" % name)
	match name:
		"default":
			pass
		"active_piece":
			run_state.set_board_cells_for_test([])
			run_state.set_active_piece_for_test("T", Vector3i(4, 18, 4))
		"ghost":
			run_state.set_board_cells_for_test(_cells_for_positions([
				Vector3i(4, 0, 4), Vector3i(4, 1, 4), Vector3i(5, 0, 4),
				Vector3i(6, 0, 4), Vector3i(6, 1, 4), Vector3i(6, 2, 4)
			]))
			run_state.set_active_piece_for_test("T", Vector3i(4, 12, 4))
		"line_clear_pause":
			run_state.set_board_cells_for_test(_cells_for_positions([
				Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i(4, 0, 0),
				Vector3i(5, 0, 0), Vector3i(6, 0, 0), Vector3i(7, 0, 0), Vector3i(8, 0, 0), Vector3i(0, 1, 0)
			]))
			run_state.current_piece = _single_block_piece(Vector3i(9, 5, 0), Color("#ffe27a"))
			run_state.hard_drop()
		"flipped_camera":
			run_state.set_board_cells_for_test(_cells_for_positions([
				Vector3i(4, 0, 4), Vector3i(4, 1, 4), Vector3i(5, 0, 4), Vector3i(6, 0, 4)
			], Color("#7cd9ff")))
			run_state.set_active_piece_for_test("L", Vector3i(4, 14, 4))
			_set_camera_view_immediate(true)
		"game_over":
			run_state.set_board_cells_for_test(_cells_for_positions([
				Vector3i(3, 19, 4), Vector3i(4, 19, 4), Vector3i(5, 19, 4),
				Vector3i(3, 18, 4), Vector3i(4, 18, 4), Vector3i(5, 18, 4)
			], Color("#7cd9ff")))
			run_state.current_piece = {}
			run_state.game_over = true
		"tutorial_move":
			_begin_intro_tutorial()
		"tutorial_rotate":
			_begin_intro_tutorial()
			tutorial_step = 5
		"tutorial_drop":
			_begin_intro_tutorial()
			tutorial_step = 10
		"tutorial_start":
			_begin_intro_tutorial()
			tutorial_step = TUTORIAL_STEP_COUNT - 1
			_set_camera_view_immediate(true)
		_:
			return false
	_refresh_view()
	return true


func _set_camera_flipped_for_capture(is_flipped: bool) -> void:
	_set_camera_view_immediate(is_flipped)


func _single_block_piece(origin: Vector3i, color: Color) -> Dictionary:
	return {
		"name": "Dot",
		"blocks": [Vector3i.ZERO],
		"color": color,
		"origin": origin
	}


func _cells_for_positions(positions: Array[Vector3i], color: Color = Color.WHITE) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for position in positions:
		cells.append({
			"position": position,
			"color": color
		})
	return cells


func _configure_materials() -> void:
	cube_mesh.size = Vector3.ONE * CELL_SCALE

	locked_material.roughness = 0.6
	locked_material.metallic = 0.0
	locked_material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX

	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.albedo_color = Color("#01040d", 0.5)
	shadow_material.roughness = 1.0

	frame_material.albedo_color = COLOR_WELL_EDGE
	frame_material.emission_enabled = true
	frame_material.emission = COLOR_WELL_EDGE
	frame_material.emission_energy_multiplier = 0.78
	frame_material.roughness = 0.92

	floor_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_grid_material.albedo_color = Color(COLOR_WELL_GRID, 0.74)
	floor_grid_material.emission_enabled = true
	floor_grid_material.emission = COLOR_WELL_GRID
	floor_grid_material.emission_energy_multiplier = 0.24
	floor_grid_material.roughness = 1.0

	well_panel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	well_panel_material.albedo_color = Color(COLOR_WELL, 0.9)
	well_panel_material.emission_enabled = true
	well_panel_material.emission = Color("#0a173d")
	well_panel_material.emission_energy_multiplier = 0.18
	well_panel_material.roughness = 1.0


func _build_scene() -> void:
	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)

	camera_node = Camera3D.new()
	camera_node.name = "Camera3D"
	camera_node.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_node.keep_aspect = Camera3D.KEEP_HEIGHT
	world_root.add_child(camera_node)
	current_camera_position = _camera_position_for_view(view_flipped)
	camera_transition_from = current_camera_position
	camera_transition_to = current_camera_position
	_apply_camera_view(current_camera_position)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -36.0, 0.0)
	sun.light_energy = 1.35
	world_root.add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(4.5, 10.0, 4.5)
	fill.light_energy = 0.48
	fill.omni_range = 48.0
	world_root.add_child(fill)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COLOR_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#2b62d0")
	env.ambient_light_energy = 0.38
	env.glow_enabled = false
	environment.environment = env
	add_child(environment)

	board_root = Node3D.new()
	board_root.name = "BoardRoot"
	world_root.add_child(board_root)

	floor_guide_root = Node3D.new()
	floor_guide_root.name = "FloorGuide"
	board_root.add_child(floor_guide_root)

	locked_root = Node3D.new()
	locked_root.name = "LockedCells"
	board_root.add_child(locked_root)

	ghost_root = Node3D.new()
	ghost_root.name = "GhostCells"
	board_root.add_child(ghost_root)

	active_root = Node3D.new()
	active_root.name = "ActiveCells"
	board_root.add_child(active_root)

	board_root.add_child(_build_board_frame())
	next_preview_root = _build_next_preview_stage()
	world_root.add_child(next_preview_root)
	add_child(_build_hud())


func _build_board_frame() -> Node3D:
	var frame_root := Node3D.new()
	frame_root.name = "BoardFrame"
	var size := Vector3(10.0, 20.0, 10.0)
	var center := Vector3((size.x - 1.0) * 0.5, (size.y - 1.0) * 0.5, (size.z - 1.0) * 0.5)
	var beam_size := 0.14

	var wall_specs := [
		["wall_back", Vector3(center.x, center.y, -0.5), Vector3(size.x, size.y, 0.12)],
		["wall_front", Vector3(center.x, center.y, size.z - 0.5), Vector3(size.x, size.y, 0.12)],
		["wall_left", Vector3(-0.5, center.y, center.z), Vector3(0.12, size.y, size.z)],
		["wall_right", Vector3(size.x - 0.5, center.y, center.z), Vector3(0.12, size.y, size.z)],
		["wall_floor", Vector3(center.x, -0.5, center.z), Vector3(size.x, 0.12, size.z)]
	]
	for spec in wall_specs:
		var wall := MeshInstance3D.new()
		wall.name = spec[0]
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = spec[2]
		wall.mesh = wall_mesh
		wall.position = spec[1]
		wall.material_override = well_panel_material
		frame_root.add_child(wall)

	var edge_positions := [
		["edge_back_left", Vector3(-0.5, center.y, -0.5), Vector3(beam_size, size.y, beam_size)],
		["edge_back_right", Vector3(size.x - 0.5, center.y, -0.5), Vector3(beam_size, size.y, beam_size)],
		["edge_front_left", Vector3(-0.5, center.y, size.z - 0.5), Vector3(beam_size, size.y, beam_size)],
		["edge_front_right", Vector3(size.x - 0.5, center.y, size.z - 0.5), Vector3(beam_size, size.y, beam_size)],
		["edge_back_bottom", Vector3(center.x, -0.5, -0.5), Vector3(size.x, beam_size, beam_size)],
		["edge_front_bottom", Vector3(center.x, -0.5, size.z - 0.5), Vector3(size.x, beam_size, beam_size)],
		["edge_back_top", Vector3(center.x, size.y - 0.5, -0.5), Vector3(size.x, beam_size, beam_size)],
		["edge_front_top", Vector3(center.x, size.y - 0.5, size.z - 0.5), Vector3(size.x, beam_size, beam_size)],
		["edge_left_bottom", Vector3(-0.5, -0.5, center.z), Vector3(beam_size, beam_size, size.z)],
		["edge_right_bottom", Vector3(size.x - 0.5, -0.5, center.z), Vector3(beam_size, beam_size, size.z)],
		["edge_left_top", Vector3(-0.5, size.y - 0.5, center.z), Vector3(beam_size, beam_size, size.z)],
		["edge_right_top", Vector3(size.x - 0.5, size.y - 0.5, center.z), Vector3(beam_size, beam_size, size.z)]
	]

	for entry in edge_positions:
		var mesh := MeshInstance3D.new()
		mesh.name = entry[0]
		var box := BoxMesh.new()
		box.size = entry[2]
		mesh.mesh = box
		mesh.position = entry[1]
		mesh.material_override = frame_material
		frame_root.add_child(mesh)

	var grid_line_size := 0.05
	for x in range(int(size.x) + 1):
		var line_x := MeshInstance3D.new()
		var line_box_x := BoxMesh.new()
		line_box_x.size = Vector3(grid_line_size, grid_line_size, size.z)
		line_x.mesh = line_box_x
		line_x.position = Vector3(x - 0.5, -0.49, center.z)
		line_x.material_override = floor_grid_material
		frame_root.add_child(line_x)

	for z in range(int(size.z) + 1):
		var line_z := MeshInstance3D.new()
		var line_box_z := BoxMesh.new()
		line_box_z.size = Vector3(size.x, grid_line_size, grid_line_size)
		line_z.mesh = line_box_z
		line_z.position = Vector3(center.x, -0.49, z - 0.5)
		line_z.material_override = floor_grid_material
		frame_root.add_child(line_z)

	return frame_root


func _build_hud() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "Hud"

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	hud_root = root

	var status_panel := _build_hud_panel(Rect2(), true)
	root.add_child(status_panel)
	hud_labels["status_panel"] = status_panel
	var title_panel := _build_hud_panel(Rect2())
	root.add_child(title_panel)
	hud_labels["title_panel"] = title_panel
	var stats_panel := _build_hud_panel(Rect2())
	root.add_child(stats_panel)
	hud_labels["stats_panel"] = stats_panel
	var queue_panel := _build_outline_frame(COLOR_PANEL_EDGE, 3)
	root.add_child(queue_panel)
	hud_labels["queue_panel"] = queue_panel
	var queue_preview_frame := _build_outline_frame(COLOR_PANEL_ACCENT, 2)
	root.add_child(queue_preview_frame)
	hud_labels["queue_preview_frame"] = queue_preview_frame
	var button_dock := _build_button_dock()
	root.add_child(button_dock)
	hud_labels["button_dock"] = button_dock

	var pause_board := _build_pause_board()
	root.add_child(pause_board)
	hud_labels["pause_board"] = pause_board
	var pause_inner := Panel.new()
	pause_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_inner.visible = false
	pause_inner.add_theme_stylebox_override("panel", _pause_board_inner_style())
	root.add_child(pause_inner)
	hud_labels["pause_inner"] = pause_inner
	var pause_divider := ColorRect.new()
	pause_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_divider.visible = false
	pause_divider.color = COLOR_PANEL_ACCENT
	root.add_child(pause_divider)
	hud_labels["pause_divider"] = pause_divider

	for key in ["top", "bottom", "left", "right"]:
		var dim_rect := ColorRect.new()
		dim_rect.name = "tutorial_dim_%s" % key
		dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim_rect.visible = false
		dim_rect.color = _tutorial_dim_color()
		root.add_child(dim_rect)
		hud_labels["tutorial_dim_%s" % key] = dim_rect

	var tutorial_focus_frame := _build_outline_frame(COLOR_TEXT_STATUS, 2)
	root.add_child(tutorial_focus_frame)
	hud_labels["tutorial_focus_frame"] = tutorial_focus_frame

	var tutorial_caption := Panel.new()
	tutorial_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_caption.visible = false
	tutorial_caption.add_theme_stylebox_override("panel", _tutorial_caption_style())
	root.add_child(tutorial_caption)
	hud_labels["tutorial_caption"] = tutorial_caption

	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.modulate = COLOR_TEXT_PRIMARY
	title.text = "PENTRIS"
	root.add_child(title)
	hud_labels["title"] = title

	var info := Label.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.modulate = COLOR_TEXT_PRIMARY
	root.add_child(info)
	hud_labels["info"] = info
	info.visible = false

	for key in ["score", "level", "lines"]:
		var header := Label.new()
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.modulate = COLOR_TEXT_MUTED
		header.text = key.to_upper()
		root.add_child(header)
		hud_labels["%s_header" % key] = header

		var value := Label.new()
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		value.modulate = COLOR_TEXT_PRIMARY
		root.add_child(value)
		hud_labels["%s_value" % key] = value

	var queue_title := Label.new()
	queue_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	queue_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_title.modulate = COLOR_TEXT_MUTED
	queue_title.text = "NEXT"
	root.add_child(queue_title)
	hud_labels["queue_title"] = queue_title

	var queue_preview := Control.new()
	queue_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(queue_preview)
	hud_labels["queue_preview"] = queue_preview

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.modulate = COLOR_TEXT_STATUS
	root.add_child(status)
	hud_labels["status"] = status

	var debug := Label.new()
	debug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug.modulate = COLOR_TEXT_MUTED
	debug.text = ""
	root.add_child(debug)
	hud_labels["debug"] = debug

	var button_specs := [
		{"key": "drop", "label": "DROP", "callback": func(): _button_drop()}
	]
	for spec in button_specs:
		var button := Button.new()
		button.text = spec["label"]
		_style_hud_button(button)
		button.pressed.connect(spec["callback"])
		root.add_child(button)
		swipe_blockers.append(button)
		hud_labels["button_%s" % spec["key"]] = button

	var menu_button := Button.new()
	menu_button.text = "MENU"
	_style_menu_trigger(menu_button)
	menu_button.pressed.connect(func(): _toggle_pause_board())
	root.add_child(menu_button)
	swipe_blockers.append(menu_button)
	hud_labels["button_menu"] = menu_button

	var pause_title := Label.new()
	pause_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_title.modulate = COLOR_TEXT_STATUS
	pause_title.text = "PAUSE"
	root.add_child(pause_title)
	hud_labels["pause_title"] = pause_title

	var pause_subtitle := Label.new()
	pause_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_subtitle.modulate = COLOR_TEXT_MUTED
	pause_subtitle.text = "OPTIONS"
	root.add_child(pause_subtitle)
	hud_labels["pause_subtitle"] = pause_subtitle

	var tutorial_title := Label.new()
	tutorial_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tutorial_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_title.modulate = COLOR_TEXT_STATUS
	tutorial_title.text = "TUTORIAL"
	root.add_child(tutorial_title)
	hud_labels["tutorial_title"] = tutorial_title

	var tutorial_instruction := Label.new()
	tutorial_instruction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tutorial_instruction.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_instruction.modulate = COLOR_TEXT_PRIMARY
	tutorial_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(tutorial_instruction)
	hud_labels["tutorial_instruction"] = tutorial_instruction

	var tutorial_hint := Label.new()
	tutorial_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_hint.modulate = COLOR_PANEL_EDGE
	root.add_child(tutorial_hint)
	hud_labels["tutorial_hint"] = tutorial_hint

	var tutorial_helper := Label.new()
	tutorial_helper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_helper.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tutorial_helper.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_helper.modulate = COLOR_TEXT_MUTED
	tutorial_helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(tutorial_helper)
	hud_labels["tutorial_helper"] = tutorial_helper

	var tutorial_progress := Label.new()
	tutorial_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tutorial_progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_progress.modulate = COLOR_PANEL_EDGE
	root.add_child(tutorial_progress)
	hud_labels["tutorial_progress"] = tutorial_progress

	var pause_button_specs := [
		{"key": "resume", "label": "RESUME", "callback": func(): _close_pause_board()},
		{"key": "new_run", "label": "NEW RUN", "callback": func(): _button_new_run()}
	]
	for spec in pause_button_specs:
		var button := Button.new()
		button.text = spec["label"]
		_style_pause_board_button(button)
		button.pressed.connect(spec["callback"])
		root.add_child(button)
		swipe_blockers.append(button)
		hud_labels["pause_button_%s" % spec["key"]] = button

	var display_filter := ColorRect.new()
	display_filter.set_anchors_preset(Control.PRESET_FULL_RECT)
	display_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display_filter.color = Color.WHITE
	display_filter.material = _build_display_filter_material()
	root.add_child(display_filter)
	hud_labels["display_filter"] = display_filter

	_apply_hud_layout()

	return layer

func left_swipe_boundary_degrees() -> float:
	return rad_to_deg(atan(1.0 / InputActionMapScript.ROTATE_Y_SWIPE_AXIS_RATIO))


func hud_layout_metrics(viewport_size: Vector2) -> Dictionary:
	var width: float = viewport_size.x
	var height: float = viewport_size.y
	var short_side: float = minf(width, height)
	var margin: float = clampf(short_side * 0.025, 8.0, 14.0)
	var gap: float = clampf(short_side * 0.02, 6.0, 10.0)
	var rail_width: float = clampf(width * 0.165, 118.0, 150.0)
	var top_strip_height: float = clampf(height * 0.095, 30.0, 40.0)
	var title_height: float = clampf(height * 0.1, 32.0, 40.0)
	var stats_height: float = clampf(height * 0.48, 150.0, 182.0)
	var button_height: float = clampf(height * 0.095, 32.0, 40.0)
	var button_gap: float = maxf(6.0, gap)
	var button_dock_padding: float = 8.0
	var button_dock_height: float = button_height + button_dock_padding * 2.0
	var queue_height: float = maxf(126.0, height - margin * 2.0 - button_dock_height - gap)
	var left_x: float = margin
	var right_x: float = width - margin - rail_width
	var center_x: float = width * 0.5
	var title_rect := Rect2(left_x, margin, rail_width, title_height)
	var title_padding := clampf(title_rect.size.y * 0.2, 7.0, 9.0)
	var title_content_gap := clampf(gap, 6.0, 8.0)
	var menu_width := clampf(rail_width * 0.31, 42.0, 48.0)
	var menu_height := clampf(title_rect.size.y - title_padding * 1.55, 20.0, 26.0)
	var menu_rect := Rect2(
		title_rect.position.x + title_rect.size.x - title_padding - menu_width,
		title_rect.position.y + (title_rect.size.y - menu_height) * 0.5,
		menu_width,
		menu_height
	)
	var title_text_rect := Rect2(
		title_rect.position.x + title_padding,
		title_rect.position.y,
		maxf(0.0, menu_rect.position.x - title_content_gap - (title_rect.position.x + title_padding)),
		title_rect.size.y
	)
	var stats_rect := Rect2(left_x, title_rect.end.y + gap, rail_width, stats_height)
	var queue_rect := Rect2(right_x, margin, rail_width, queue_height)
	var button_dock_rect := Rect2(right_x, height - margin - button_dock_height, rail_width, button_dock_height)
	var pause_board_width := clampf(width * 0.42, 320.0, 410.0)
	var pause_board_height := clampf(height * 0.7, 250.0, 330.0)
	var pause_board_rect := Rect2(
		center_x - pause_board_width * 0.5,
		height * 0.5 - pause_board_height * 0.5,
		pause_board_width,
		pause_board_height
	)
	var status_width: float = clampf(width * 0.26, 180.0, 250.0)
	var status_rect := Rect2(center_x - status_width * 0.5, margin, status_width, top_strip_height)
	var debug_rect := Rect2(margin, height - margin - 16.0, width - margin * 2.0, 14.0)
	var queue_title_rect := Rect2(queue_rect.position + Vector2(8, 8), Vector2(queue_rect.size.x - 16, 18))
	var queue_frame_width := queue_rect.size.x - 20.0
	var queue_frame_y := queue_title_rect.end.y + 8.0
	var queue_frame_height := maxf(140.0, queue_rect.end.y - queue_frame_y - 10.0)
	var queue_preview_frame_rect := Rect2(
		queue_rect.position.x + 10.0,
		queue_frame_y,
		queue_frame_width,
		queue_frame_height
	)
	var queue_preview_rect := queue_preview_frame_rect.grow_individual(-8.0, -8.0, -8.0, -8.0)
	var play_top: float = margin + 4.0
	var play_bottom: float = height - margin - 4.0
	var play_rect := Rect2(
		left_x + rail_width + gap,
		play_top,
		right_x - (left_x + rail_width + gap) - gap,
		max(0.0, play_bottom - play_top)
	)
	var tutorial_focus_rect := Rect2(Vector2(width * 0.5, margin), Vector2(width * 0.5 - margin, height - margin * 2.0))
	var tutorial_caption_rect := Rect2(
		width * 0.14,
		height * 0.36,
		clampf(width * 0.22, 150.0, 196.0),
		clampf(height * 0.24, 82.0, 102.0)
	)
	var tutorial_glyph_rect := Rect2(
		tutorial_focus_rect.position.x + tutorial_focus_rect.size.x * 0.5 - 52.0,
		tutorial_focus_rect.position.y + tutorial_focus_rect.size.y * 0.5 - 52.0,
		104.0,
		104.0
	)
	var tutorial_caption_padding := 12.0
	var tutorial_caption_header_height := 14.0
	var tutorial_caption_progress_width := 42.0
	var tutorial_kind: String = String(_tutorial_step_data().get("kind", ""))
	var tutorial_region: String = String(_tutorial_step_data().get("region", ""))
	var tutorial_caption_title_rect := Rect2(
		tutorial_caption_rect.position.x + tutorial_caption_padding,
		tutorial_caption_rect.position.y + 8.0,
		72.0,
		tutorial_caption_header_height
	)
	var tutorial_progress_rect := Rect2(
		tutorial_caption_rect.end.x - tutorial_caption_padding - tutorial_caption_progress_width,
		tutorial_caption_title_rect.position.y,
		tutorial_caption_progress_width,
		tutorial_caption_header_height
	)
	var tutorial_instruction_rect := Rect2(
		tutorial_caption_rect.position.x + tutorial_caption_padding,
		tutorial_caption_title_rect.end.y + 8.0,
		tutorial_caption_rect.size.x - tutorial_caption_padding * 2.0,
		42.0 if tutorial_kind == "camera" or tutorial_kind == "start" else 30.0
	)
	var tutorial_helper_rect := Rect2(
		tutorial_instruction_rect.position.x,
		tutorial_caption_rect.end.y - 24.0,
		tutorial_instruction_rect.size.x,
		16.0
	)
	var tutorial_title_rect := tutorial_caption_title_rect
	var tutorial_dim_top_rect := Rect2(0.0, 0.0, width, tutorial_focus_rect.position.y)
	var tutorial_dim_bottom_rect := Rect2(0.0, tutorial_focus_rect.end.y, width, maxf(0.0, height - tutorial_focus_rect.end.y))
	var tutorial_dim_left_rect := Rect2(0.0, tutorial_focus_rect.position.y, tutorial_focus_rect.position.x, tutorial_focus_rect.size.y)
	var tutorial_dim_right_rect := Rect2(tutorial_focus_rect.end.x, tutorial_focus_rect.position.y, maxf(0.0, width - tutorial_focus_rect.end.x), tutorial_focus_rect.size.y)
	if tutorial_kind == "rotate":
		tutorial_focus_rect = Rect2(Vector2(0.0, margin), Vector2(width * 0.5, height - margin * 2.0))
		tutorial_caption_rect.position = Vector2(
			minf(play_rect.end.x - tutorial_caption_rect.size.x - 10.0, width * 0.62),
			height * 0.36
		)
		tutorial_glyph_rect = Rect2(
			tutorial_focus_rect.position.x + tutorial_focus_rect.size.x * 0.34,
			tutorial_focus_rect.position.y + tutorial_focus_rect.size.y * 0.5 - 52.0,
			104.0,
			104.0
		)
	elif tutorial_kind == "move" and tutorial_region == "right":
		tutorial_caption_rect.position = Vector2(
			maxf(24.0, width * 0.17 - tutorial_caption_rect.size.x * 0.5),
			height * 0.36
		)
		tutorial_glyph_rect = Rect2(
			tutorial_focus_rect.position.x + tutorial_focus_rect.size.x * 0.57,
			tutorial_focus_rect.position.y + tutorial_focus_rect.size.y * 0.5 - 52.0,
			104.0,
			104.0
		)
	elif tutorial_kind == "drop":
		tutorial_focus_rect = button_dock_rect.grow(8.0)
		tutorial_caption_rect.position = Vector2(
			maxf(play_rect.position.x - tutorial_caption_rect.size.x - 20.0, margin + 12.0),
			play_rect.position.y + 28.0
		)
		tutorial_glyph_rect = Rect2(
			tutorial_focus_rect.get_center().x - 40.0,
			tutorial_focus_rect.position.y + 2.0,
			80.0,
			32.0
		)
	elif tutorial_kind == "camera" or tutorial_kind == "start":
		tutorial_focus_rect = play_rect.grow(-6.0)
		tutorial_caption_rect.position = Vector2(
			maxf(play_rect.position.x - tutorial_caption_rect.size.x - 20.0, margin + 12.0),
			play_rect.position.y + 24.0
		)
		tutorial_glyph_rect = Rect2(
			tutorial_focus_rect.get_center().x - 74.0,
			tutorial_focus_rect.position.y + tutorial_focus_rect.size.y * 0.2,
			148.0,
			48.0
		)
	tutorial_title_rect.position = tutorial_caption_rect.position + Vector2(tutorial_caption_padding, 8.0)
	tutorial_progress_rect.position = Vector2(
		tutorial_caption_rect.end.x - tutorial_caption_padding - tutorial_caption_progress_width,
		tutorial_title_rect.position.y
	)
	tutorial_instruction_rect.position = Vector2(
		tutorial_caption_rect.position.x + tutorial_caption_padding,
		tutorial_title_rect.end.y + 8.0
	)
	tutorial_instruction_rect.size.x = tutorial_caption_rect.size.x - tutorial_caption_padding * 2.0
	tutorial_helper_rect.position = Vector2(
		tutorial_instruction_rect.position.x,
		tutorial_caption_rect.end.y - 24.0
	)
	tutorial_helper_rect.size.x = tutorial_instruction_rect.size.x
	tutorial_dim_top_rect = Rect2(0.0, 0.0, width, tutorial_focus_rect.position.y)
	tutorial_dim_bottom_rect = Rect2(0.0, tutorial_focus_rect.end.y, width, maxf(0.0, height - tutorial_focus_rect.end.y))
	tutorial_dim_left_rect = Rect2(0.0, tutorial_focus_rect.position.y, tutorial_focus_rect.position.x, tutorial_focus_rect.size.y)
	tutorial_dim_right_rect = Rect2(tutorial_focus_rect.end.x, tutorial_focus_rect.position.y, maxf(0.0, width - tutorial_focus_rect.end.x), tutorial_focus_rect.size.y)
	var pause_inner_rect := pause_board_rect.grow(-14.0)
	var pause_side_padding := clampf(pause_inner_rect.size.x * 0.11, 24.0, 34.0)
	var pause_top_padding := clampf(pause_inner_rect.size.y * 0.12, 20.0, 30.0)
	var pause_title_height := clampf(pause_inner_rect.size.y * 0.18, 34.0, 48.0)
	var pause_subtitle_height := clampf(pause_inner_rect.size.y * 0.1, 16.0, 24.0)
	var pause_button_height := clampf(pause_inner_rect.size.y * 0.19, 44.0, 58.0)
	var pause_row_gap := clampf(pause_inner_rect.size.y * 0.06, 10.0, 16.0)
	var pause_section_gap := clampf(pause_inner_rect.size.y * 0.09, 14.0, 22.0)
	var pause_divider_margin := clampf(pause_inner_rect.size.x * 0.12, 24.0, 36.0)
	var pause_title_rect := Rect2(
		pause_inner_rect.position.x + pause_side_padding,
		pause_inner_rect.position.y + pause_top_padding,
		pause_inner_rect.size.x - pause_side_padding * 2.0,
		pause_title_height
	)
	var pause_subtitle_rect := Rect2(
		pause_title_rect.position.x,
		pause_title_rect.end.y + 2.0,
		pause_title_rect.size.x,
		pause_subtitle_height
	)
	var pause_divider_rect := Rect2(
		pause_inner_rect.position.x + pause_divider_margin,
		pause_subtitle_rect.end.y + pause_row_gap,
		pause_inner_rect.size.x - pause_divider_margin * 2.0,
		2.0
	)
	var pause_button_resume_rect := Rect2(
		pause_inner_rect.position.x + pause_side_padding,
		pause_divider_rect.end.y + pause_section_gap,
		pause_inner_rect.size.x - pause_side_padding * 2.0,
		pause_button_height
	)
	var pause_button_new_run_rect := Rect2(
		pause_button_resume_rect.position.x,
		pause_button_resume_rect.end.y + pause_row_gap,
		pause_button_resume_rect.size.x,
		pause_button_height
	)
	var pause_required_bottom := pause_button_new_run_rect.end.y + pause_top_padding
	if pause_required_bottom > pause_inner_rect.end.y:
		var pause_overflow := pause_required_bottom - pause_inner_rect.end.y
		pause_board_rect.size.y += pause_overflow
		pause_inner_rect.size.y += pause_overflow
	var centered_pause_y := height * 0.5 - pause_board_rect.size.y * 0.5
	var pause_y_delta := centered_pause_y - pause_board_rect.position.y
	pause_board_rect.position.y = centered_pause_y
	pause_inner_rect.position.y += pause_y_delta
	pause_title_rect.position.y += pause_y_delta
	pause_subtitle_rect.position.y += pause_y_delta
	pause_divider_rect.position.y += pause_y_delta
	pause_button_resume_rect.position.y += pause_y_delta
	pause_button_new_run_rect.position.y += pause_y_delta
	return {
		"margin": margin,
		"gap": gap,
		"title_rect": title_rect,
		"title_text_rect": title_text_rect,
		"menu_rect": menu_rect,
		"pause_board_rect": pause_board_rect,
		"stats_rect": stats_rect,
		"queue_rect": queue_rect,
		"queue_title_rect": queue_title_rect,
		"queue_preview_frame_rect": queue_preview_frame_rect,
		"queue_preview_rect": queue_preview_rect,
		"tutorial_focus_rect": tutorial_focus_rect,
		"tutorial_caption_rect": tutorial_caption_rect,
		"tutorial_title_rect": tutorial_title_rect,
		"tutorial_instruction_rect": tutorial_instruction_rect,
		"tutorial_hint_rect": tutorial_glyph_rect,
		"tutorial_helper_rect": tutorial_helper_rect,
		"tutorial_progress_rect": tutorial_progress_rect,
		"tutorial_dim_top_rect": tutorial_dim_top_rect,
		"tutorial_dim_bottom_rect": tutorial_dim_bottom_rect,
		"tutorial_dim_left_rect": tutorial_dim_left_rect,
		"tutorial_dim_right_rect": tutorial_dim_right_rect,
		"button_dock_rect": button_dock_rect,
		"status_rect": status_rect,
		"debug_rect": debug_rect,
		"pause_inner_rect": pause_inner_rect,
		"pause_title_rect": pause_title_rect,
		"pause_subtitle_rect": pause_subtitle_rect,
		"pause_divider_rect": pause_divider_rect,
		"pause_button_resume_rect": pause_button_resume_rect,
		"pause_button_new_run_rect": pause_button_new_run_rect,
		"play_rect": play_rect,
		"button_height": button_height,
		"button_gap": button_gap,
		"button_dock_padding": button_dock_padding,
		"title_font_size": int(clamp(height * 0.042, 16.0, 20.0)),
		"stats_header_font_size": int(clamp(height * 0.027, 10.0, 12.0)),
		"stats_value_font_size": int(clamp(height * 0.05, 18.0, 24.0)),
		"queue_title_font_size": int(clamp(height * 0.032, 11.0, 14.0)),
		"status_font_size": int(clamp(height * 0.047, 15.0, 18.0)),
		"tutorial_title_font_size": int(clamp(height * 0.026, 10.0, 12.0)),
		"tutorial_instruction_font_size": int(clamp(height * 0.042, 15.0, 19.0)),
		"tutorial_hint_font_size": int(clamp(height * 0.18, 50.0, 70.0)),
		"tutorial_helper_font_size": int(clamp(height * 0.026, 10.0, 12.0)),
		"tutorial_progress_font_size": int(clamp(height * 0.028, 10.0, 12.0)),
		"debug_font_size": 10
	}


func projected_board_spans(camera_position: Vector3) -> Dictionary:
	var axes := _camera_axes(camera_position)
	var right: Vector3 = axes["right"]
	var up: Vector3 = axes["up"]
	var forward := (CAMERA_LOOK_TARGET - camera_position).normalized()
	var min_horizontal := INF
	var max_horizontal := -INF
	var min_vertical := INF
	var max_vertical := -INF
	for x in [BOARD_BOUNDS_MIN.x, BOARD_BOUNDS_MAX.x]:
		for y in [BOARD_BOUNDS_MIN.y, BOARD_BOUNDS_MAX.y]:
			for z in [BOARD_BOUNDS_MIN.z, BOARD_BOUNDS_MAX.z]:
				var offset := Vector3(x, y, z) - CAMERA_LOOK_TARGET
				var horizontal := offset.dot(right)
				var vertical := offset.dot(up)
				min_horizontal = min(min_horizontal, horizontal)
				max_horizontal = max(max_horizontal, horizontal)
				min_vertical = min(min_vertical, vertical)
				max_vertical = max(max_vertical, vertical)
	for corner in _next_preview_stage_bounds(camera_position):
		var offset := corner - CAMERA_LOOK_TARGET
		var horizontal := offset.dot(right)
		var vertical := offset.dot(up)
		min_horizontal = min(min_horizontal, horizontal)
		max_horizontal = max(max_horizontal, horizontal)
		min_vertical = min(min_vertical, vertical)
		max_vertical = max(max_vertical, vertical)
	return {
		"width": max_horizontal - min_horizontal,
		"height": max_vertical - min_vertical
	}


func camera_size_for_viewport(viewport_size: Vector2, camera_position: Vector3) -> float:
	var safe_aspect: float = maxf(viewport_size.x / maxf(viewport_size.y, 1.0), 0.1)
	var spans: Dictionary = projected_board_spans(camera_position)
	var padded_height: float = spans["height"] + CAMERA_FIT_PADDING * 2.0
	var padded_width: float = spans["width"] + CAMERA_FIT_PADDING * 2.0
	return max(padded_height, padded_width / safe_aspect)


func _build_hud_panel(rect: Rect2, marquee: bool = false) -> Control:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override(
		"panel",
		_panel_style(
			COLOR_PANEL_SOFT if not marquee else Color("#322167"),
			COLOR_PANEL_EDGE if not marquee else COLOR_TEXT_STATUS,
			3
		)
	)
	return panel


func _build_outline_frame(border_color: Color, border_width: int) -> Control:
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_meta("border_color", border_color)
	frame.set_meta("border_width", border_width)
	for edge in ["top", "bottom", "left", "right"]:
		var line := ColorRect.new()
		line.name = edge
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.color = border_color
		frame.add_child(line)
	return frame


func _build_button_dock() -> Control:
	var dock := Panel.new()
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_theme_stylebox_override("panel", _panel_style(Color("#100d2d"), COLOR_PANEL_ACCENT, 3))
	return dock


func _build_pause_board() -> Control:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _pause_board_style())
	return panel


func _build_next_preview_stage() -> Node3D:
	var stage_root := Node3D.new()
	stage_root.name = "NextPreviewStage"
	var preview_fill := OmniLight3D.new()
	preview_fill.position = Vector3(0.0, 2.8, 0.8)
	preview_fill.light_energy = 1.5
	preview_fill.light_color = Color("#9ce6ff")
	preview_fill.omni_range = 10.0
	stage_root.add_child(preview_fill)

	var piece_root := Node3D.new()
	piece_root.name = "NextPreviewPiece"
	stage_root.add_child(piece_root)
	next_preview_piece_root = piece_root

	return stage_root


func _panel_style(fill_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_right = 0
	style.corner_radius_bottom_left = 0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 5
	style.shadow_offset = Vector2(2, 2)
	style.expand_margin_left = 2
	style.expand_margin_top = 2
	style.expand_margin_right = 2
	style.expand_margin_bottom = 2
	return style


func _build_display_filter_material() -> ShaderMaterial:
	if display_filter_material != null:
		return display_filter_material
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float pixel_size = 2.0;
uniform float scanline_strength : hint_range(0.0, 0.25) = 0.07;
uniform float vignette_strength : hint_range(0.0, 0.25) = 0.07;
uniform vec4 tint_color : source_color = vec4(0.12, 0.98, 1.0, 0.08);

void fragment() {
	vec2 pixel_uv = SCREEN_PIXEL_SIZE * pixel_size;
	vec2 snapped_uv = floor(SCREEN_UV / pixel_uv) * pixel_uv + pixel_uv * 0.5;
	vec4 scene_color = textureLod(screen_tex, snapped_uv, 0.0);
	float scanline = 1.0 - scanline_strength * (0.5 + 0.5 * sin(SCREEN_UV.y * (1.0 / SCREEN_PIXEL_SIZE.y) * 3.14159265));
	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float vignette = 1.0 - vignette_strength * dot(centered, centered);
	scene_color.rgb *= scanline * vignette;
	scene_color.rgb = mix(scene_color.rgb, scene_color.rgb * tint_color.rgb, tint_color.a);
	COLOR = scene_color;
}
"""
	display_filter_material = ShaderMaterial.new()
	display_filter_material.shader = shader
	return display_filter_material


func _style_hud_button(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT_ACTION)
	button.add_theme_stylebox_override("normal", _panel_style(Color("#0c1739"), COLOR_PANEL_EDGE, 3))
	button.add_theme_stylebox_override("hover", _panel_style(Color("#162760"), COLOR_PANEL_ACCENT, 3))
	button.add_theme_stylebox_override("pressed", _panel_style(COLOR_TEXT_STATUS, COLOR_PANEL_EDGE, 3))


func _style_menu_trigger(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_STATUS)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT_ACTION)
	button.add_theme_stylebox_override("normal", _panel_style(Color("#111a44"), COLOR_TEXT_STATUS, 2))
	button.add_theme_stylebox_override("hover", _panel_style(Color("#182761"), COLOR_PANEL_EDGE, 2))
	button.add_theme_stylebox_override("pressed", _panel_style(COLOR_TEXT_STATUS, COLOR_PANEL_EDGE, 2))


func _style_pause_board_button(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_STATUS)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT_ACTION)
	button.add_theme_stylebox_override("normal", _panel_style(Color("#0d1738"), COLOR_PANEL_EDGE, 2))
	button.add_theme_stylebox_override("hover", _panel_style(Color("#182864"), COLOR_PANEL_ACCENT, 2))
	button.add_theme_stylebox_override("pressed", _panel_style(COLOR_TEXT_STATUS, COLOR_PANEL_EDGE, 2))


func _pause_board_style() -> StyleBoxFlat:
	var style := _panel_style(Color("#09112d"), COLOR_PANEL_ACCENT, 4)
	style.shadow_size = 7
	style.shadow_offset = Vector2(3, 4)
	return style


func _pause_board_inner_style() -> StyleBoxFlat:
	var style := _panel_style(Color("#101847"), COLOR_PANEL_EDGE, 1)
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	style.expand_margin_left = 0
	style.expand_margin_top = 0
	style.expand_margin_right = 0
	style.expand_margin_bottom = 0
	return style


func _tutorial_dim_color() -> Color:
	return Color(0.02, 0.03, 0.08, 0.62)


func _tutorial_caption_style() -> StyleBoxFlat:
	var style := _panel_style(Color("#081128", 0.92), COLOR_TEXT_STATUS, 3)
	style.shadow_size = 6
	style.shadow_offset = Vector2(2, 3)
	return style


func _tutorial_focus_frame_style() -> StyleBoxFlat:
	var style := _panel_style(Color(0.0, 0.0, 0.0, 0.0), COLOR_TEXT_STATUS, 2)
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	style.expand_margin_left = 0
	style.expand_margin_top = 0
	style.expand_margin_right = 0
	style.expand_margin_bottom = 0
	return style


func _queue_preview_frame_style() -> StyleBoxFlat:
	var style := _panel_style(Color(0.07, 0.05, 0.18, 0.0), COLOR_PANEL_ACCENT, 2)
	style.shadow_size = 3
	style.shadow_offset = Vector2(1, 2)
	return style


func _queue_panel_style() -> StyleBoxFlat:
	var style := _panel_style(Color(0.07, 0.05, 0.18, 0.0), COLOR_PANEL_EDGE, 3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(2, 2)
	return style


func _apply_hud_layout() -> void:
	if hud_root == null:
		return
	var metrics := hud_layout_metrics(_viewport_size())
	_position_control(hud_labels["title_panel"], metrics["title_rect"])
	_position_control(hud_labels["stats_panel"], metrics["stats_rect"])
	_position_control(hud_labels["queue_panel"], metrics["queue_rect"])
	_position_control(hud_labels["queue_preview_frame"], metrics["queue_preview_frame_rect"])
	_layout_outline_frame(hud_labels["queue_panel"])
	_layout_outline_frame(hud_labels["queue_preview_frame"])
	_position_control(hud_labels["status_panel"], metrics["status_rect"])
	_position_control(hud_labels["button_dock"], metrics["button_dock_rect"])
	_position_control(hud_labels["pause_board"], metrics["pause_board_rect"])
	_position_control(hud_labels["pause_inner"], metrics["pause_inner_rect"])
	_position_control(hud_labels["pause_divider"], metrics["pause_divider_rect"])
	for key in ["top", "bottom", "left", "right"]:
		_position_control(hud_labels["tutorial_dim_%s" % key], metrics["tutorial_dim_%s_rect" % key])
	_position_control(hud_labels["tutorial_focus_frame"], metrics["tutorial_focus_rect"])
	_layout_outline_frame(hud_labels["tutorial_focus_frame"])
	_position_control(hud_labels["tutorial_caption"], metrics["tutorial_caption_rect"])
	_position_label(hud_labels["title"], metrics["title_text_rect"], metrics["title_font_size"])
	_position_control(hud_labels["button_menu"], metrics["menu_rect"])
	_position_stats_labels(metrics)
	_position_label(hud_labels["queue_title"], metrics["queue_title_rect"], metrics["queue_title_font_size"])
	_position_control(hud_labels["queue_preview"], metrics["queue_preview_rect"])
	_position_label(hud_labels["status"], metrics["status_rect"], metrics["status_font_size"])
	_position_label(hud_labels["tutorial_title"], metrics["tutorial_title_rect"], metrics["tutorial_title_font_size"])
	_position_label(hud_labels["tutorial_instruction"], metrics["tutorial_instruction_rect"], metrics["tutorial_instruction_font_size"])
	_position_label(hud_labels["tutorial_hint"], metrics["tutorial_hint_rect"], _tutorial_hint_font_size())
	_position_label(hud_labels["tutorial_helper"], metrics["tutorial_helper_rect"], metrics["tutorial_helper_font_size"])
	_position_label(hud_labels["tutorial_progress"], metrics["tutorial_progress_rect"], metrics["tutorial_progress_font_size"])
	_position_label(hud_labels["debug"], metrics["debug_rect"], metrics["debug_font_size"])
	hud_labels["debug"].visible = HUD_DEBUG_ENABLED and hud_labels["debug"].text != ""

	var dock_rect: Rect2 = metrics["button_dock_rect"]
	var button_height: float = metrics["button_height"]
	var inner_padding: float = metrics["button_dock_padding"]
	var button_width := dock_rect.size.x - inner_padding * 2.0
	var button_rect := Rect2(
		dock_rect.position + Vector2(inner_padding, inner_padding),
		Vector2(button_width, button_height)
	)
	_position_control(hud_labels["button_drop"], button_rect)
	_position_pause_board_contents(metrics)
	hud_labels["button_menu"].visible = not tutorial_active
	hud_labels["pause_board"].visible = pause_board_open
	hud_labels["pause_inner"].visible = pause_board_open
	hud_labels["pause_divider"].visible = pause_board_open
	hud_labels["pause_title"].visible = pause_board_open
	hud_labels["pause_subtitle"].visible = pause_board_open
	hud_labels["pause_button_resume"].visible = pause_board_open
	hud_labels["pause_button_new_run"].visible = pause_board_open
	for key in ["top", "bottom", "left", "right"]:
		hud_labels["tutorial_dim_%s" % key].visible = tutorial_active
	var tutorial_kind: String = String(_tutorial_step_data().get("kind", ""))
	hud_labels["tutorial_focus_frame"].visible = tutorial_active and tutorial_kind == "drop"
	hud_labels["tutorial_caption"].visible = tutorial_active
	hud_labels["tutorial_title"].visible = tutorial_active
	hud_labels["tutorial_instruction"].visible = tutorial_active
	hud_labels["tutorial_hint"].visible = tutorial_active
	hud_labels["tutorial_helper"].visible = tutorial_active and hud_labels["tutorial_helper"].text != ""
	hud_labels["tutorial_progress"].visible = tutorial_active
	var tutorial_overlay_active := tutorial_active
	hud_labels["title_panel"].visible = not tutorial_overlay_active
	hud_labels["title"].visible = not tutorial_overlay_active
	hud_labels["stats_panel"].visible = not tutorial_overlay_active
	for key in ["score", "level", "lines"]:
		hud_labels["%s_header" % key].visible = not tutorial_overlay_active
		hud_labels["%s_value" % key].visible = not tutorial_overlay_active
	hud_labels["queue_panel"].visible = not tutorial_overlay_active
	hud_labels["queue_preview_frame"].visible = not tutorial_overlay_active
	hud_labels["queue_title"].visible = not tutorial_overlay_active
	hud_labels["queue_preview"].visible = not tutorial_overlay_active


func _layout_outline_frame(frame: Control) -> void:
	if frame == null:
		return
	var border_width: float = float(frame.get_meta("border_width", 2))
	var border_color: Color = frame.get_meta("border_color", Color.WHITE)
	for child in frame.get_children():
		if child is ColorRect:
			child.color = border_color
	var top_line := frame.get_node_or_null("top")
	if top_line is ColorRect:
		top_line.position = Vector2.ZERO
		top_line.size = Vector2(frame.size.x, border_width)
	var bottom_line := frame.get_node_or_null("bottom")
	if bottom_line is ColorRect:
		bottom_line.position = Vector2(0.0, maxf(0.0, frame.size.y - border_width))
		bottom_line.size = Vector2(frame.size.x, border_width)
	var left_line := frame.get_node_or_null("left")
	if left_line is ColorRect:
		left_line.position = Vector2.ZERO
		left_line.size = Vector2(border_width, frame.size.y)
	var right_line := frame.get_node_or_null("right")
	if right_line is ColorRect:
		right_line.position = Vector2(maxf(0.0, frame.size.x - border_width), 0.0)
		right_line.size = Vector2(border_width, frame.size.y)


func _position_control(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _position_label(label: Label, rect: Rect2, font_size: int) -> void:
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)


func _position_pause_board_contents(metrics: Dictionary) -> void:
	var inner_rect: Rect2 = metrics["pause_inner_rect"]
	_position_label(hud_labels["pause_title"], metrics["pause_title_rect"], int(clamp(inner_rect.size.y * 0.16, 24.0, 34.0)))
	_position_label(hud_labels["pause_subtitle"], metrics["pause_subtitle_rect"], int(clamp(inner_rect.size.y * 0.07, 12.0, 18.0)))
	var pause_button_font_size := int(clamp(inner_rect.size.y * 0.095, 16.0, 22.0))
	hud_labels["pause_button_resume"].add_theme_font_size_override("font_size", pause_button_font_size)
	hud_labels["pause_button_new_run"].add_theme_font_size_override("font_size", pause_button_font_size)
	_position_control(hud_labels["pause_button_resume"], metrics["pause_button_resume_rect"])
	_position_control(hud_labels["pause_button_new_run"], metrics["pause_button_new_run_rect"])


func _position_stats_labels(metrics: Dictionary) -> void:
	var stats_rect: Rect2 = metrics["stats_rect"]
	var top_padding: float = clampf(stats_rect.size.y * 0.08, 10.0, 14.0)
	var bottom_padding: float = clampf(stats_rect.size.y * 0.08, 10.0, 14.0)
	var side_padding: float = clampf(stats_rect.size.x * 0.09, 10.0, 14.0)
	var available_height := maxf(60.0, stats_rect.size.y - top_padding - bottom_padding)
	var group_gap := clampf(available_height * 0.05, 6.0, 12.0)
	var block_height := maxf(20.0, (available_height - group_gap * 2.0) / 3.0)
	var row_gap := clampf(block_height * 0.12, 4.0, 8.0)
	var header_height := clampf(block_height * 0.22, 10.0, 14.0)
	var value_height := maxf(18.0, block_height - header_height - row_gap)
	var y := stats_rect.position.y + top_padding
	var content_width := stats_rect.size.x - side_padding * 2.0
	for key in ["score", "level", "lines"]:
		var header_rect := Rect2(stats_rect.position.x + side_padding, y, content_width, header_height)
		_position_label(hud_labels["%s_header" % key], header_rect, metrics["stats_header_font_size"])
		y += header_height + row_gap
		var value_rect := Rect2(stats_rect.position.x + side_padding, y, content_width, value_height)
		_position_label(hud_labels["%s_value" % key], value_rect, metrics["stats_value_font_size"])
		y += value_height + group_gap


func queue_preview_layout(item_count: int, rect_size: Vector2) -> Array[Rect2]:
	var layouts: Array[Rect2] = []
	if item_count <= 0:
		return layouts
	var gap := clampf(rect_size.y * 0.03, 4.0, 8.0)
	var card_height := (rect_size.y - gap * float(item_count - 1)) / float(item_count)
	for index in range(item_count):
		layouts.append(Rect2(0.0, float(index) * (card_height + gap), rect_size.x, card_height))
	return layouts


func queue_piece_block_rects(blocks: Array, rect: Rect2) -> Array[Rect2]:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for block in blocks:
		min_x = minf(min_x, block.x)
		max_x = maxf(max_x, block.x)
		min_z = minf(min_z, block.z)
		max_z = maxf(max_z, block.z)
	var cols := max_x - min_x + 1.0
	var rows := max_z - min_z + 1.0
	var inner_padding := clampf(minf(rect.size.x, rect.size.y) * 0.1, 4.0, 8.0)
	var usable_width := maxf(8.0, rect.size.x - inner_padding * 2.0)
	var usable_height := maxf(8.0, rect.size.y - inner_padding * 2.0)
	var cell_size := floorf(minf(usable_width / cols, usable_height / rows))
	cell_size = maxf(6.0, cell_size)
	var shape_width := cols * cell_size
	var shape_height := rows * cell_size
	var origin := rect.position + Vector2((rect.size.x - shape_width) * 0.5, (rect.size.y - shape_height) * 0.5)
	var block_rects: Array[Rect2] = []
	for block in blocks:
		block_rects.append(
			Rect2(
				origin + Vector2((block.x - min_x) * cell_size, (block.z - min_z) * cell_size),
				Vector2.ONE * cell_size
			)
		)
	return block_rects


func _rebuild_piece_preview(preview_key: String, piece_names: Array[String], compact: bool = false) -> void:
	if not hud_labels.has(preview_key):
		return
	var preview_root: Control = hud_labels[preview_key]
	for child in preview_root.get_children():
		child.queue_free()
	if run_state == null or piece_names.is_empty():
		return
	var defs: Dictionary = run_state.rules.piece_defs()
	var layouts := [Rect2(Vector2.ZERO, preview_root.size)] if compact else queue_preview_layout(piece_names.size(), preview_root.size)
	for index in range(layouts.size()):
		var name: String = piece_names[index]
		if not defs.has(name):
			continue
		var card := Control.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.position = layouts[index].position
		card.size = layouts[index].size
		preview_root.add_child(card)
		var card_panel := Panel.new()
		card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_panel.position = Vector2.ZERO
		card_panel.size = card.size
		card_panel.add_theme_stylebox_override("panel", _panel_style(Color("#0f0c2a"), COLOR_PANEL_EDGE, 2))
		card.add_child(card_panel)
		var piece: Dictionary = defs[name]
		for block_rect in queue_piece_block_rects(piece["blocks"], Rect2(Vector2(4, 4), card.size - Vector2(8, 8))):
			var shadow := ColorRect.new()
			shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			shadow.position = block_rect.position + Vector2(1, 2)
			shadow.size = block_rect.size
			shadow.color = Color(0.0, 0.0, 0.0, 0.35)
			card.add_child(shadow)
			var block_panel := Panel.new()
			block_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			block_panel.position = block_rect.position
			block_panel.size = block_rect.size
			block_panel.add_theme_stylebox_override(
				"panel",
				_panel_style(piece["color"], piece["color"].lightened(0.28), 2)
			)
			card.add_child(block_panel)


func _rebuild_queue_preview() -> void:
	_rebuild_queue_preview_stage(run_state.preview_queue())


func _rebuild_queue_preview_stage(piece_names: Array[String]) -> void:
	if next_preview_piece_root == null or run_state == null:
		return
	for child in next_preview_piece_root.get_children():
		child.queue_free()
	if tutorial_active:
		if next_preview_root != null:
			next_preview_root.visible = false
		return
	if piece_names.is_empty():
		if next_preview_root != null:
			next_preview_root.visible = false
		return
	if next_preview_root != null:
		next_preview_root.visible = true
	var defs: Dictionary = run_state.rules.piece_defs()
	var name: String = piece_names[0]
	if not defs.has(name):
		return
	var piece: Dictionary = defs[name]
	var blocks: Array = piece["blocks"]
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for block in blocks:
		min_x = minf(min_x, block.x)
		max_x = maxf(max_x, block.x)
		min_z = minf(min_z, block.z)
		max_z = maxf(max_z, block.z)
	var center_x := (min_x + max_x) * 0.5
	var center_z := (min_z + max_z) * 0.5
	for block in blocks:
		var mesh := MeshInstance3D.new()
		mesh.mesh = cube_mesh
		mesh.position = Vector3(block.x - center_x, 0.0, block.z - center_z)
		var material := locked_material.duplicate()
		material.albedo_color = piece["color"]
		mesh.material_override = material
		next_preview_piece_root.add_child(mesh)
	next_preview_piece_root.position = Vector3(0.0, 0.22, 0.0)
	_sync_next_preview_stage()


func _button_drop() -> void:
	if tutorial_active:
		if _tutorial_step_data().get("kind", "") == "drop":
			run_state.hard_drop()
			_set_swipe_debug("Tutorial drop complete")
			_advance_intro_tutorial()
		return
	if _gameplay_locked():
		return
	run_state.hard_drop()


func _toggle_pause_board() -> void:
	if pause_board_open:
		_close_pause_board()
		return
	_open_pause_board()


func _open_pause_board() -> void:
	if tutorial_active or tutorial_finishing:
		return
	pause_board_open = true
	touch_active = false
	pointer_captured_by_ui = false
	_refresh_view()


func _close_pause_board() -> void:
	pause_board_open = false
	touch_active = false
	pointer_captured_by_ui = false
	_refresh_view()


func _button_new_run() -> void:
	_start_run()
	_close_pause_board()


func _viewport_size() -> Vector2:
	var viewport := get_viewport()
	if viewport != null:
		return viewport.get_visible_rect().size
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 844),
		ProjectSettings.get_setting("display/window/size/viewport_height", 390)
	)


func _refresh_view() -> void:
	if not startup_complete or run_state == null:
		return
	_apply_hud_layout()
	_sync_board_dimensions()
	_sync_next_preview_stage()
	var landing_cells: Array[Dictionary] = run_state.active_cells(run_state.ghost_origin())
	_rebuild_locked_cells(locked_root, _dict_to_array(run_state.board.occupied_cells()), landing_support_cells(landing_cells))
	_rebuild_cells(active_root, run_state.active_cells(), false)
	_rebuild_landing_guide(landing_cells)
	_rebuild_queue_preview()
	_refresh_labels()


func _sync_board_dimensions() -> void:
	if board_root != null:
		board_root.rotation.y = board_transition_yaw
	var frame := board_root.get_node_or_null("BoardFrame") if board_root != null else null
	if frame != null:
		frame.scale = Vector3.ONE
		_sync_board_wall_visibility(frame)


func _sync_board_wall_visibility(frame: Node3D) -> void:
	var show_front_wall := current_camera_position.z < CAMERA_LOOK_TARGET.z
	var show_right_wall := current_camera_position.x < CAMERA_LOOK_TARGET.x
	var nearest_x := "left" if current_camera_position.x < CAMERA_LOOK_TARGET.x else "right"
	var nearest_z := "back" if current_camera_position.z < CAMERA_LOOK_TARGET.z else "front"
	var wall_back := frame.get_node_or_null("wall_back")
	var wall_front := frame.get_node_or_null("wall_front")
	var wall_left := frame.get_node_or_null("wall_left")
	var wall_right := frame.get_node_or_null("wall_right")
	var edge_back_left := frame.get_node_or_null("edge_back_left")
	var edge_back_right := frame.get_node_or_null("edge_back_right")
	var edge_front_left := frame.get_node_or_null("edge_front_left")
	var edge_front_right := frame.get_node_or_null("edge_front_right")
	var edge_back_top := frame.get_node_or_null("edge_back_top")
	var edge_front_top := frame.get_node_or_null("edge_front_top")
	var edge_left_top := frame.get_node_or_null("edge_left_top")
	var edge_right_top := frame.get_node_or_null("edge_right_top")
	if wall_back != null:
		wall_back.visible = not show_front_wall
	if wall_front != null:
		wall_front.visible = show_front_wall
	if wall_left != null:
		wall_left.visible = not show_right_wall
	if wall_right != null:
		wall_right.visible = show_right_wall
	if edge_back_left != null:
		edge_back_left.visible = true
	if edge_back_right != null:
		edge_back_right.visible = true
	if edge_front_left != null:
		edge_front_left.visible = true
	if edge_front_right != null:
		edge_front_right.visible = true
	if edge_back_top != null:
		edge_back_top.visible = true
	if edge_front_top != null:
		edge_front_top.visible = true
	if edge_left_top != null:
		edge_left_top.visible = true
	if edge_right_top != null:
		edge_right_top.visible = true
	if nearest_x == "right" and nearest_z == "front":
		if edge_front_right != null:
			edge_front_right.visible = false
		if edge_front_top != null:
			edge_front_top.visible = false
		if edge_right_top != null:
			edge_right_top.visible = false
	elif nearest_x == "left" and nearest_z == "back":
		if edge_back_left != null:
			edge_back_left.visible = false
		if edge_back_top != null:
			edge_back_top.visible = false
		if edge_left_top != null:
			edge_left_top.visible = false
	elif nearest_x == "left" and nearest_z == "front":
		if edge_front_left != null:
			edge_front_left.visible = false
		if edge_front_top != null:
			edge_front_top.visible = false
		if edge_left_top != null:
			edge_left_top.visible = false
	else:
		if edge_back_right != null:
			edge_back_right.visible = false
		if edge_back_top != null:
			edge_back_top.visible = false
		if edge_right_top != null:
			edge_right_top.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
	elif what == NOTIFICATION_WM_SIZE_CHANGED:
		_apply_hud_layout()
		_apply_camera_view(current_camera_position)


func _dict_to_array(cells: Dictionary) -> Array[Dictionary]:
	var array: Array[Dictionary] = []
	for entry in cells.values():
		array.append(entry)
	return array


func _rebuild_cells(parent: Node3D, cells: Array[Dictionary], use_ghost_material: bool) -> void:
	for child in parent.get_children():
		child.queue_free()
	if use_ghost_material:
		return
	var pending_clear_keys := _pending_clear_key_lookup()
	var flash_strength := _clear_flash_strength()
	for cell in cells:
		var mesh := MeshInstance3D.new()
		mesh.mesh = cube_mesh
		mesh.position = _to_world(cell["position"])
		var material := locked_material.duplicate()
		if pending_clear_keys.has(_cell_key(cell["position"])):
			material.albedo_color = COLOR_CLEAR.lerp(cell["color"], 1.0 - flash_strength * 0.7)
			material.emission_enabled = true
			material.emission = COLOR_CLEAR
			material.emission_energy_multiplier = 1.0 + flash_strength * 1.6
		elif cell.get("is_pivot", false):
			material.albedo_color = Color("#fff7b2")
			material.emission_enabled = true
			material.emission = Color("#fff7b2")
			material.emission_energy_multiplier = 1.5
		else:
			material.albedo_color = cell["color"]
		mesh.material_override = material
		parent.add_child(mesh)


func _rebuild_locked_cells(parent: Node3D, cells: Array[Dictionary], support_cells: Array[Vector3i]) -> void:
	var support_lookup := {}
	for support_cell in support_cells:
		support_lookup[_cell_key(support_cell)] = true
	for child in parent.get_children():
		child.queue_free()
	var pending_clear_keys := _pending_clear_key_lookup()
	var flash_strength := _clear_flash_strength()
	for cell in cells:
		var mesh := MeshInstance3D.new()
		mesh.mesh = cube_mesh
		mesh.position = _to_world(cell["position"])
		var material := locked_material.duplicate()
		if pending_clear_keys.has(_cell_key(cell["position"])):
			material.albedo_color = COLOR_CLEAR.lerp(cell["color"], 1.0 - flash_strength * 0.7)
			material.emission_enabled = true
			material.emission = COLOR_CLEAR
			material.emission_energy_multiplier = 1.0 + flash_strength * 1.6
		elif cell.get("is_pivot", false):
			material.albedo_color = Color("#fff7b2")
			material.emission_enabled = true
			material.emission = Color("#fff7b2")
			material.emission_energy_multiplier = 1.5
		else:
			material.albedo_color = cell["color"]
		mesh.material_override = material
		if support_lookup.has(_cell_key(cell["position"])):
			mesh.add_child(_build_support_face_overlay())
		parent.add_child(mesh)


func _to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell.x, cell.y, cell.z)


func landing_support_cells(cells: Array[Dictionary]) -> Array[Vector3i]:
	var projected := {}
	for cell in cells:
		var position: Vector3i = cell["position"]
		var footprint_key := "%s,%s" % [position.x, position.z]
		if not projected.has(footprint_key) or position.y < projected[footprint_key].y:
			projected[footprint_key] = position
	var support_cells: Array[Vector3i] = []
	for footprint in projected.values():
		var support_y: int = footprint.y - 1
		if support_y >= 0:
			support_cells.append(Vector3i(footprint.x, support_y, footprint.z))
	return support_cells


func landing_floor_faces(cells: Array[Dictionary]) -> Array[Dictionary]:
	var projected := {}
	for cell in cells:
		var position: Vector3i = cell["position"]
		var footprint_key := "%s,%s" % [position.x, position.z]
		if not projected.has(footprint_key) or position.y < projected[footprint_key].y:
			projected[footprint_key] = position
	var receiver_faces: Array[Dictionary] = []
	for footprint in projected.values():
		receiver_faces.append({
			"x": footprint.x,
			"z": footprint.z,
			"face_y": -0.5 + 0.06 + 0.003,
			"receiver": "floor"
		})
	return receiver_faces


func _rebuild_landing_guide(cells: Array[Dictionary]) -> void:
	for child in floor_guide_root.get_children():
		child.queue_free()
	for child in ghost_root.get_children():
		child.queue_free()
	for receiver_face in landing_floor_faces(cells):
		floor_guide_root.add_child(_build_receiver_face_overlay(receiver_face))


func _build_support_face_overlay() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (CELL_SCALE * 0.72)
	mesh.mesh = quad
	mesh.position = Vector3(0.0, CELL_SCALE * 0.5 + 0.004, 0.0)
	mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var material := shadow_material.duplicate()
	material.albedo_color = Color("#fff085", 0.78)
	material.emission_enabled = true
	material.emission = Color("#fff085")
	material.emission_energy_multiplier = 0.8
	mesh.material_override = material
	return mesh


func _build_receiver_face_overlay(receiver_face: Dictionary) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var is_floor: bool = receiver_face.get("receiver", "") == "floor"
	var material := shadow_material.duplicate()
	if is_floor:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * (CELL_SCALE * 0.98)
		mesh.mesh = quad
		mesh.position = Vector3(receiver_face["x"], receiver_face["face_y"], receiver_face["z"])
		mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	else:
		var cap := BoxMesh.new()
		cap.size = Vector3(CELL_SCALE * 0.66, 0.04, CELL_SCALE * 0.66)
		mesh.mesh = cap
		mesh.position = Vector3(receiver_face["x"], receiver_face["face_y"] - 0.017, receiver_face["z"])
	material.albedo_color = Color("#5be8ff", 0.58) if is_floor else Color("#fff085", 0.78)
	material.emission_enabled = true
	material.emission = Color("#5be8ff") if is_floor else Color("#fff085")
	material.emission_energy_multiplier = 0.55 if is_floor else 0.8
	material.render_priority = 1 if is_floor else 0
	mesh.material_override = material
	return mesh


func _refresh_labels() -> void:
	hud_labels["score_value"].text = "%06d" % run_state.score
	hud_labels["level_value"].text = "%02d" % run_state.level
	hud_labels["lines_value"].text = "%03d" % run_state.cleared_rows_total
	hud_labels["status"].text = "LINE CLEAR" if run_state.is_clearing() else "GAME OVER" if run_state.game_over else ""
	hud_labels["tutorial_instruction"].text = _tutorial_instruction_text() if tutorial_active else ""
	hud_labels["tutorial_hint"].text = _tutorial_hint_text() if tutorial_active else ""
	hud_labels["tutorial_helper"].text = _tutorial_helper_text() if tutorial_active else ""
	hud_labels["tutorial_progress"].text = _tutorial_progress_text() if tutorial_active else ""
	if hud_labels.has("status_panel"):
		hud_labels["status_panel"].visible = hud_labels["status"].text != ""
	if hud_labels.has("debug"):
		hud_labels["debug"].visible = HUD_DEBUG_ENABLED and hud_labels["debug"].text != ""


func _is_over_swipe_blocker(screen_position: Vector2) -> bool:
	for control in swipe_blockers:
		if control.visible and control.get_global_rect().has_point(screen_position):
			return true
	return false


func _set_swipe_debug(text: String) -> void:
	if hud_labels.has("debug"):
		hud_labels["debug"].text = text


func _pending_clear_key_lookup() -> Dictionary:
	var keys := {}
	if run_state == null or not run_state.is_clearing():
		return keys
	for position in run_state.pending_clear_cells():
		keys[_cell_key(position)] = true
	return keys


func _clear_flash_strength() -> float:
	if run_state == null or not run_state.is_clearing():
		return 0.0
	var progress: float = run_state.clear_pause_progress()
	return 0.35 + 0.65 * absf(sin(progress * PI * CLEAR_FLASH_CYCLES))


func _update_touch_peak_delta(delta: Vector2) -> void:
	if delta.length_squared() > touch_peak_delta.length_squared():
		touch_peak_delta = delta


func strongest_swipe_delta(release_delta: Vector2, peak_delta: Vector2) -> Vector2:
	return peak_delta if peak_delta.length_squared() > release_delta.length_squared() else release_delta


func _request_move(delta: Vector3i) -> void:
	if run_state == null or _gameplay_locked():
		return
	run_state.move_active(view_relative_movement(delta))


func _request_rotation(axis: String, direction: int) -> void:
	if run_state == null or _gameplay_locked():
		return
	run_state.rotate_active(axis, view_relative_rotation_direction(axis, direction))


func _toggle_view() -> void:
	if camera_transition_active:
		return
	camera_transition_active = true
	camera_transition_elapsed = 0.0
	camera_transition_from = current_camera_position
	camera_transition_target_flipped = not view_flipped
	camera_transition_to = _camera_position_for_view(camera_transition_target_flipped)
	board_transition_yaw = 0.0
	_apply_camera_view(current_camera_position)


func _advance_camera_transition(delta: float) -> void:
	if not camera_transition_active:
		return
	camera_transition_elapsed = min(camera_transition_elapsed + delta, CAMERA_SWAP_DURATION)
	var progress := camera_transition_elapsed / CAMERA_SWAP_DURATION
	var eased := _ease_camera_swap(progress)
	current_camera_position = _orbit_camera_position(camera_transition_from, eased)
	board_transition_yaw = _transition_board_yaw(eased)
	_apply_camera_view(current_camera_position)
	if progress >= 1.0:
		camera_transition_active = false
		current_camera_position = camera_transition_to
		board_transition_yaw = 0.0
		view_flipped = camera_transition_target_flipped
		_apply_camera_view(current_camera_position)
		if tutorial_finishing:
			_finalize_intro_tutorial()


func _apply_camera_view(camera_position: Vector3) -> void:
	if camera_node == null:
		return
	camera_node.size = camera_size_for_viewport(_viewport_size(), camera_position)
	camera_node.look_at_from_position(camera_position, CAMERA_LOOK_TARGET, Vector3.UP)
	_sync_board_dimensions()
	_sync_next_preview_stage()


func _camera_axes(camera_position: Vector3) -> Dictionary:
	var forward := (CAMERA_LOOK_TARGET - camera_position).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	return {
		"forward": forward,
		"right": right,
		"up": up
	}


func _next_preview_stage_anchor_fallback(camera_position: Vector3) -> Vector3:
	var axes := _camera_axes(camera_position)
	var right: Vector3 = axes["right"]
	var up: Vector3 = axes["up"]
	var forward: Vector3 = axes["forward"]
	return CAMERA_LOOK_TARGET + right * NEXT_STAGE_HORIZONTAL_OFFSET + up * NEXT_STAGE_VERTICAL_OFFSET + forward * NEXT_STAGE_DEPTH_OFFSET


func _next_preview_stage_bounds(camera_position: Vector3) -> Array[Vector3]:
	var axes := _camera_axes(camera_position)
	var anchor := _next_preview_stage_anchor_fallback(camera_position)
	var corners: Array[Vector3] = []
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				corners.append(
					anchor
					+ axes["right"] * NEXT_STAGE_BOUNDS_EXTENTS.x * x_sign
					+ axes["up"] * NEXT_STAGE_BOUNDS_EXTENTS.y * y_sign
					+ axes["forward"] * NEXT_STAGE_BOUNDS_EXTENTS.z * z_sign
				)
	return corners


func _sync_next_preview_stage() -> void:
	if next_preview_root == null:
		return
	if camera_node == null or not is_inside_tree():
		next_preview_root.position = _next_preview_stage_anchor_fallback(current_camera_position)
		return
	var metrics := hud_layout_metrics(_viewport_size())
	var frame_rect: Rect2 = metrics["queue_preview_rect"]
	var stage_center := camera_node.project_position(frame_rect.get_center(), current_camera_position.distance_to(CAMERA_LOOK_TARGET))
	next_preview_root.position = stage_center


func _camera_position_for_view(is_flipped: bool) -> Vector3:
	return CAMERA_FAR_CORNER if is_flipped else CAMERA_NEAR_CORNER


func _orbit_camera_position(from_position: Vector3, progress: float) -> Vector3:
	var offset := from_position - CAMERA_LOOK_TARGET
	return CAMERA_LOOK_TARGET + offset.rotated(Vector3.UP, PI * progress)


func _transition_board_yaw(progress: float) -> float:
	var direction := -1.0 if camera_transition_target_flipped else 1.0
	return sin(progress * PI) * CAMERA_SWAP_WORLD_YAW_MAX * direction


func _ease_camera_swap(progress: float) -> float:
	return progress * progress * (3.0 - 2.0 * progress)


func _gameplay_locked() -> bool:
	return not startup_complete or camera_transition_active or pause_board_open or tutorial_active or tutorial_finishing or run_state == null or run_state.game_over or run_state.is_clearing()


func _is_double_tap(position: Vector2, swipe_delta: Vector2) -> bool:
	var now_ms := Time.get_ticks_msec()
	var is_tap := swipe_delta.length() <= TAP_MAX_DISTANCE
	var within_interval := now_ms - last_tap_time_ms <= DOUBLE_TAP_MAX_INTERVAL_MS
	var nearby := position.distance_to(last_tap_position) <= TAP_MAX_DISTANCE
	var is_double := is_tap and within_interval and nearby
	if is_tap:
		last_tap_time_ms = now_ms
		last_tap_position = position
	else:
		last_tap_time_ms = -1000
	return is_double


func view_relative_movement(delta: Vector3i) -> Vector3i:
	if not view_flipped:
		return delta
	return Vector3i(-delta.x, delta.y, -delta.z)


func view_relative_rotation_direction(axis: String, direction: int) -> int:
	if axis == "y":
		return -direction
	if view_flipped and (axis == "x" or axis == "z"):
		return -direction
	return direction


func _describe_swipe_action(action: String) -> String:
	match action:
		InputActionMapScript.ROTATE_Y_CW:
			return "rotate Y +"
		InputActionMapScript.ROTATE_Y_CCW:
			return "rotate Y -"
		InputActionMapScript.ROTATE_X_CW:
			return "rotate X +"
		InputActionMapScript.ROTATE_X_CCW:
			return "rotate X -"
		InputActionMapScript.ROTATE_Z_CW:
			return "rotate Z +"
		InputActionMapScript.ROTATE_Z_CCW:
			return "rotate Z -"
	return "below threshold"


func _format_vector(value: Vector2) -> String:
	return "(%d, %d)" % [int(value.x), int(value.y)]


func _cell_key(cell: Vector3i) -> String:
	return "%s,%s,%s" % [cell.x, cell.y, cell.z]


func _vector_key(value: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [value.x, value.y, value.z]


func _swipe_region_for_position(screen_position: Vector2) -> String:
	return "left" if screen_position.x < _viewport_size().x * 0.5 else "right"


func _movement_delta_for_swipe(delta: Vector2) -> Vector3i:
	if delta.length() < 36.0:
		return Vector3i.ZERO
	if delta.x >= 0.0 and delta.y <= 0.0:
		return Vector3i(0, 0, -1)
	if delta.x <= 0.0 and delta.y >= 0.0:
		return Vector3i(0, 0, 1)
	if delta.x >= 0.0 and delta.y >= 0.0:
		return Vector3i(1, 0, 0)
	return Vector3i(-1, 0, 0)


func _describe_movement_delta(delta: Vector3i) -> String:
	if delta == Vector3i(1, 0, 0):
		return "move X +"
	if delta == Vector3i(-1, 0, 0):
		return "move X -"
	if delta == Vector3i(0, 0, 1):
		return "move Z +"
	if delta == Vector3i(0, 0, -1):
		return "move Z -"
	return "below threshold"
