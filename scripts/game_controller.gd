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
const TAP_MAX_DISTANCE := 24.0
const DOUBLE_TAP_MAX_INTERVAL_MS := 320
const CLEAR_FLASH_CYCLES := 3.0
const COLOR_BG := Color("#120a2d")
const COLOR_BG_DEEP := Color("#070318")
const COLOR_STAGE := Color("#241c66")
const COLOR_STAGE_STRIPE := Color("#2f257d")
const COLOR_PANEL := Color("#120f32")
const COLOR_PANEL_SOFT := Color("#1a1646")
const COLOR_PANEL_EDGE := Color("#f0d88b")
const COLOR_PANEL_ACCENT := Color("#67d7ff")
const COLOR_TEXT_PRIMARY := Color("#fff7d6")
const COLOR_TEXT_MUTED := Color("#9dc7ff")
const COLOR_TEXT_STATUS := Color("#ffd85e")
const COLOR_TEXT_ACTION := Color("#1d1637")
const COLOR_ACCENT := Color("#78e6ff")
const COLOR_ACCENT_SOFT := Color("#438dff")
const COLOR_CLEAR := Color("#fff3a0")
const COLOR_WELL := Color("#0c0a24")
const COLOR_WELL_EDGE := Color("#86d7ff")
const COLOR_WELL_GRID := Color("#314f96")
const HUD_DEBUG_ENABLED := false

var run_state: RefCounted
var fall_accumulator: float = 0.0
var touch_start := Vector2.ZERO
var touch_peak_delta := Vector2.ZERO
var touch_active := false
var touch_region := ""
var pointer_captured_by_ui := false
var swipe_blockers: Array[Control] = []
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
var hud_labels := {}
var camera_node: Camera3D
var hud_root: Control

var cube_mesh := BoxMesh.new()
var locked_material := StandardMaterial3D.new()
var frame_material := StandardMaterial3D.new()
var floor_grid_material := StandardMaterial3D.new()
var shadow_material := StandardMaterial3D.new()
var well_panel_material := StandardMaterial3D.new()


func _ready() -> void:
	InputActionMapScript.ensure_default_actions()
	_configure_materials()
	_build_scene()
	_start_run()


func _process(delta: float) -> void:
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
	elif event.is_action_pressed(InputActionMapScript.HARD_DROP):
		run_state.hard_drop()
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
	camera_transition_active = false
	camera_transition_elapsed = 0.0
	camera_transition_target_flipped = view_flipped
	board_transition_yaw = 0.0
	_refresh_view()


func prepare_visual_scenario(name: String) -> bool:
	_start_run_with_seed(1)
	_set_camera_flipped_for_capture(false)
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
			_set_camera_flipped_for_capture(true)
		"game_over":
			run_state.set_board_cells_for_test(_cells_for_positions([
				Vector3i(3, 19, 4), Vector3i(4, 19, 4), Vector3i(5, 19, 4),
				Vector3i(3, 18, 4), Vector3i(4, 18, 4), Vector3i(5, 18, 4)
			], Color("#7cd9ff")))
			run_state.current_piece = {}
			run_state.game_over = true
		_:
			return false
	_refresh_view()
	return true


func _set_camera_flipped_for_capture(is_flipped: bool) -> void:
	view_flipped = is_flipped
	camera_transition_active = false
	camera_transition_elapsed = 0.0
	camera_transition_target_flipped = is_flipped
	board_transition_yaw = 0.0
	current_camera_position = _camera_position_for_view(view_flipped)
	camera_transition_from = current_camera_position
	camera_transition_to = current_camera_position
	_apply_camera_view(current_camera_position)


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
	shadow_material.albedo_color = Color("#05040f", 0.42)
	shadow_material.roughness = 1.0

	frame_material.albedo_color = COLOR_WELL_EDGE
	frame_material.emission_enabled = true
	frame_material.emission = COLOR_WELL_EDGE
	frame_material.emission_energy_multiplier = 0.4
	frame_material.roughness = 1.0

	floor_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_grid_material.albedo_color = Color(COLOR_WELL_GRID, 0.6)
	floor_grid_material.emission_enabled = true
	floor_grid_material.emission = COLOR_WELL_GRID
	floor_grid_material.emission_energy_multiplier = 0.08
	floor_grid_material.roughness = 1.0

	well_panel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	well_panel_material.albedo_color = Color(COLOR_WELL, 0.9)
	well_panel_material.emission_enabled = true
	well_panel_material.emission = Color("#0e0a2f")
	well_panel_material.emission_energy_multiplier = 0.08
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
	env.ambient_light_color = Color("#6279c7")
	env.ambient_light_energy = 0.32
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
	var queue_panel := _build_hud_panel(Rect2())
	root.add_child(queue_panel)
	hud_labels["queue_panel"] = queue_panel
	var button_dock := _build_button_dock()
	root.add_child(button_dock)
	hud_labels["button_dock"] = button_dock

	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		{"key": "drop", "label": "DROP", "callback": func(): _button_drop()},
		{"key": "new_run", "label": "NEW RUN", "callback": func(): _start_run()}
	]
	for spec in button_specs:
		var button := Button.new()
		button.text = spec["label"]
		_style_hud_button(button)
		button.pressed.connect(spec["callback"])
		root.add_child(button)
		swipe_blockers.append(button)
		hud_labels["button_%s" % spec["key"]] = button

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
	var button_dock_height: float = button_height * 2.0 + button_gap + button_dock_padding * 2.0
	var queue_height: float = maxf(126.0, height - margin * 2.0 - button_dock_height - gap)
	var left_x: float = margin
	var right_x: float = width - margin - rail_width
	var center_x: float = width * 0.5
	var title_rect := Rect2(left_x, margin, rail_width, title_height)
	var stats_rect := Rect2(left_x, title_rect.end.y + gap, rail_width, stats_height)
	var queue_rect := Rect2(right_x, margin, rail_width, queue_height)
	var button_dock_rect := Rect2(right_x, height - margin - button_dock_height, rail_width, button_dock_height)
	var status_width: float = clampf(width * 0.26, 180.0, 250.0)
	var status_rect := Rect2(center_x - status_width * 0.5, margin, status_width, top_strip_height)
	var debug_rect := Rect2(margin, height - margin - 16.0, width - margin * 2.0, 14.0)
	var play_top: float = margin + 4.0
	var play_bottom: float = height - margin - 4.0
	var play_rect := Rect2(
		left_x + rail_width + gap,
		play_top,
		right_x - (left_x + rail_width + gap) - gap,
		max(0.0, play_bottom - play_top)
	)
	return {
		"margin": margin,
		"gap": gap,
		"title_rect": title_rect,
		"stats_rect": stats_rect,
		"queue_rect": queue_rect,
		"button_dock_rect": button_dock_rect,
		"status_rect": status_rect,
		"debug_rect": debug_rect,
		"play_rect": play_rect,
		"button_height": button_height,
		"button_gap": button_gap,
		"button_dock_padding": button_dock_padding,
		"title_font_size": int(clamp(height * 0.042, 16.0, 20.0)),
		"info_font_size": int(clamp(height * 0.03, 10.0, 13.0)),
		"queue_title_font_size": int(clamp(height * 0.032, 11.0, 14.0)),
		"status_font_size": int(clamp(height * 0.047, 15.0, 18.0)),
		"debug_font_size": 10
	}


func projected_board_spans(camera_position: Vector3) -> Dictionary:
	var forward := (CAMERA_LOOK_TARGET - camera_position).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
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


func _build_button_dock() -> Control:
	var dock := Panel.new()
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_theme_stylebox_override("panel", _panel_style(Color("#100d2d"), COLOR_PANEL_ACCENT, 3))
	return dock


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


func _style_hud_button(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT_ACTION)
	button.add_theme_stylebox_override("normal", _panel_style(Color("#17123d"), COLOR_PANEL_EDGE, 3))
	button.add_theme_stylebox_override("hover", _panel_style(Color("#272063"), COLOR_PANEL_ACCENT, 3))
	button.add_theme_stylebox_override("pressed", _panel_style(COLOR_TEXT_STATUS, COLOR_PANEL_EDGE, 3))


func _apply_hud_layout() -> void:
	if hud_root == null:
		return
	var metrics := hud_layout_metrics(_viewport_size())
	_position_control(hud_labels["title_panel"], metrics["title_rect"])
	_position_control(hud_labels["stats_panel"], metrics["stats_rect"])
	_position_control(hud_labels["queue_panel"], metrics["queue_rect"])
	_position_control(hud_labels["status_panel"], metrics["status_rect"])
	_position_control(hud_labels["button_dock"], metrics["button_dock_rect"])
	_position_label(hud_labels["title"], metrics["title_rect"], metrics["title_font_size"])
	_position_label(hud_labels["info"], Rect2(metrics["stats_rect"].position + Vector2(10, 10), metrics["stats_rect"].size - Vector2(20, 16)), metrics["info_font_size"])
	_position_label(hud_labels["queue_title"], Rect2(metrics["queue_rect"].position + Vector2(8, 8), Vector2(metrics["queue_rect"].size.x - 16, 16)), metrics["queue_title_font_size"])
	_position_control(hud_labels["queue_preview"], Rect2(metrics["queue_rect"].position + Vector2(10, 28), Vector2(metrics["queue_rect"].size.x - 20, metrics["queue_rect"].size.y - 38)))
	_position_label(hud_labels["status"], metrics["status_rect"], metrics["status_font_size"])
	_position_label(hud_labels["debug"], metrics["debug_rect"], metrics["debug_font_size"])
	hud_labels["debug"].visible = HUD_DEBUG_ENABLED and hud_labels["debug"].text != ""

	var dock_rect: Rect2 = metrics["button_dock_rect"]
	var button_height: float = metrics["button_height"]
	var button_gap: float = metrics["button_gap"]
	var inner_padding: float = metrics["button_dock_padding"]
	var button_width := dock_rect.size.x - inner_padding * 2.0
	var button_names := ["drop", "new_run"]
	for index in range(button_names.size()):
		var button_rect := Rect2(
			dock_rect.position + Vector2(inner_padding, inner_padding + index * (button_height + button_gap)),
			Vector2(button_width, button_height)
		)
		_position_control(hud_labels["button_%s" % button_names[index]], button_rect)


func _position_control(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _position_label(label: Label, rect: Rect2, font_size: int) -> void:
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)


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
	var inner_padding := clampf(minf(rect.size.x, rect.size.y) * 0.16, 4.0, 10.0)
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
	_rebuild_piece_preview("queue_preview", run_state.preview_queue())


func _button_drop() -> void:
	if _gameplay_locked():
		return
	run_state.hard_drop()


func _viewport_size() -> Vector2:
	var viewport := get_viewport()
	if viewport != null:
		return viewport.get_visible_rect().size
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 844),
		ProjectSettings.get_setting("display/window/size/viewport_height", 390)
	)


func _refresh_view() -> void:
	if run_state == null:
		return
	_apply_hud_layout()
	_sync_board_dimensions()
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
	var active_name: String = "-" if run_state.current_piece.is_empty() else run_state.current_piece["name"]
	hud_labels["info"].text = "SCORE\n%06d\nLEVEL\n%02d\nLINES\n%03d\nPIECE\n%s" % [
		run_state.score,
		run_state.level,
		run_state.cleared_rows_total,
		active_name
	]
	hud_labels["status"].text = "LINE CLEAR" if run_state.is_clearing() else "BLOCKED SPAWN / GAME OVER" if run_state.game_over else ""
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


func _apply_camera_view(camera_position: Vector3) -> void:
	if camera_node == null:
		return
	camera_node.size = camera_size_for_viewport(_viewport_size(), camera_position)
	camera_node.look_at_from_position(camera_position, CAMERA_LOOK_TARGET, Vector3.UP)
	_sync_board_dimensions()


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
	return camera_transition_active or run_state == null or run_state.game_over or run_state.is_clearing()


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
	return "left" if screen_position.x < get_viewport().get_visible_rect().size.x * 0.5 else "right"


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
