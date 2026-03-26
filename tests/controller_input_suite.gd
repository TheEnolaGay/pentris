extends RefCounted

const ControllerScript = preload("res://scripts/game_controller.gd")
const InputActionMapScript = preload("res://scripts/core/input_action_map.gd")
const CaptureRunnerScript = preload("res://tools/visual_capture_runner.gd")


static func run(harness: RefCounted) -> void:
	harness.suite("ControllerInput")
	_test_view_relative_movement(harness)
	_test_camera_swap_transition(harness)
	_test_visual_capture_presets(harness)
	_test_camera_fit(harness)
	_test_queue_preview_helpers(harness)
	_test_button_layout_metrics(harness)
	_test_visual_scenarios(harness)
	_test_open_face_edges(harness)
	_test_ghost_shadow_projection(harness)
	_test_view_relative_rotation(harness)
	_test_left_swipe_angle_threshold(harness)
	_test_right_swipe_angle_threshold(harness)
	_test_swipe_peak_excursion(harness)
	_test_double_tap_detection(harness)


static func _test_view_relative_movement(harness: RefCounted) -> void:
	harness.case("view-relative movement")
	var controller = ControllerScript.new()

	controller.view_flipped = false
	harness.assert_equal(
		controller.view_relative_movement(Vector3i(1, 0, -1)),
		Vector3i(1, 0, -1),
		"default view should keep X/Z movement unchanged"
	)

	controller.view_flipped = true
	harness.assert_equal(
		controller.view_relative_movement(Vector3i(1, 0, -1)),
		Vector3i(-1, 0, 1),
		"flipped view should invert X/Z movement"
	)
	harness.assert_equal(
		controller.view_relative_movement(Vector3i(0, -1, 0)),
		Vector3i(0, -1, 0),
		"flipped view should not affect vertical movement"
	)
	controller.free()


static func _test_camera_swap_transition(harness: RefCounted) -> void:
	harness.case("camera swap transition")
	var controller = ControllerScript.new()

	controller.view_flipped = false
	controller.current_camera_position = controller.CAMERA_NEAR_CORNER
	controller.camera_transition_from = controller.CAMERA_NEAR_CORNER
	controller.camera_transition_to = controller.CAMERA_NEAR_CORNER
	controller._toggle_view()
	harness.assert_true(controller.camera_transition_active, "toggle should begin a camera transition")
	harness.assert_true(controller.camera_transition_target_flipped, "toggle should target the flipped view")
	harness.assert_true(not controller.view_flipped, "logical orientation should stay unchanged until the transition ends")
	harness.assert_equal(
		controller.view_relative_movement(Vector3i(1, 0, 0)),
		Vector3i(1, 0, 0),
		"movement should stay on the current view until the transition completes"
	)
	var transition_target: Vector3 = controller.camera_transition_to
	controller._toggle_view()
	harness.assert_equal(
		controller.camera_transition_to,
		transition_target,
		"extra toggles during transition should be ignored"
	)

	controller._advance_camera_transition(controller.CAMERA_SWAP_DURATION * 0.5)
	harness.assert_true(controller.camera_transition_active, "transition should still be active halfway through")
	harness.assert_true(
		controller.current_camera_position.distance_to(controller.CAMERA_NEAR_CORNER) > 0.01,
		"camera position should move away from the starting corner during transition"
	)
	harness.assert_true(
		controller.current_camera_position.distance_to(controller.CAMERA_FAR_CORNER) > 0.01,
		"camera position should not reach the final corner before completion"
	)
	harness.assert_true(
		absf(controller.board_transition_yaw) > 0.01,
		"board yaw should animate during the swap"
	)
	harness.assert_true(
		controller._gameplay_locked(),
		"gameplay should stay locked during the swap"
	)
	harness.assert_equal(
		controller.view_relative_movement(Vector3i(1, 0, 0)),
		Vector3i(1, 0, 0),
		"movement should still use the starting orientation halfway through"
	)

	controller._advance_camera_transition(controller.CAMERA_SWAP_DURATION)
	harness.assert_true(not controller.camera_transition_active, "transition should finish at full duration")
	harness.assert_equal(controller.current_camera_position, controller.CAMERA_FAR_CORNER, "camera should land on the flipped corner")
	harness.assert_true(controller.view_flipped, "logical orientation should flip at the end of the transition")
	harness.assert_equal(controller.board_transition_yaw, 0.0, "board yaw should settle back to neutral at the end")
	harness.assert_equal(
		controller.view_relative_movement(Vector3i(1, 0, 0)),
		Vector3i(-1, 0, 0),
		"movement should use the flipped orientation once the transition completes"
	)
	controller.free()


static func _test_visual_capture_presets(harness: RefCounted) -> void:
	harness.case("visual capture presets")
	harness.assert_equal(
		CaptureRunnerScript.viewport_preset_size("phone_landscape"),
		Vector2i(844, 390),
		"phone landscape preset should resolve to the mobile baseline"
	)
	harness.assert_equal(
		CaptureRunnerScript.viewport_preset_size("desktop_720p"),
		Vector2i(1280, 720),
		"desktop preset should remain available for comparison captures"
	)
	harness.assert_equal(
		CaptureRunnerScript.viewport_preset_size("unknown"),
		Vector2i.ZERO,
		"unknown capture presets should fail cleanly"
	)


static func _test_camera_fit(harness: RefCounted) -> void:
	harness.case("camera fit")
	var controller = ControllerScript.new()
	var near_spans: Dictionary = controller.projected_board_spans(controller.CAMERA_NEAR_CORNER)
	var far_spans: Dictionary = controller.projected_board_spans(controller.CAMERA_FAR_CORNER)
	harness.assert_equal(
		near_spans,
		far_spans,
		"mirrored camera corners should project the board to identical spans"
	)
	var phone_size := controller.camera_size_for_viewport(Vector2(844, 390), controller.CAMERA_NEAR_CORNER)
	harness.assert_true(
		phone_size >= near_spans["height"] + controller.CAMERA_FIT_PADDING * 2.0,
		"camera fit should cover the full projected board height plus padding on the phone baseline"
	)
	var narrower_size := controller.camera_size_for_viewport(Vector2(390, 844), controller.CAMERA_NEAR_CORNER)
	harness.assert_true(
		narrower_size > phone_size,
		"narrower viewports should require a larger orthographic size"
	)
	controller.free()


static func _test_queue_preview_helpers(harness: RefCounted) -> void:
	harness.case("queue preview helpers")
	var controller = ControllerScript.new()
	var layouts := controller.queue_preview_layout(4, Vector2(120, 200))
	harness.assert_equal(layouts.size(), 4, "queue preview should create one slot per visible piece")
	harness.assert_true(layouts[1].position.y > layouts[0].position.y, "queue slots should stack vertically")
	var block_rects := controller.queue_piece_block_rects([
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(1, 0, 1), Vector3i(1, 0, 2)
	], Rect2(Vector2.ZERO, Vector2(96, 52)))
	harness.assert_equal(block_rects.size(), 5, "piece preview should emit one rect per block")
	harness.assert_true(block_rects[0].size.x >= 6.0, "piece preview blocks should stay visible at mobile sizes")
	harness.assert_true(block_rects[0].position.x >= 0.0 and block_rects[0].position.y >= 0.0, "piece preview should stay inside its slot")
	controller.free()


static func _test_button_layout_metrics(harness: RefCounted) -> void:
	harness.case("button layout metrics")
	var controller = ControllerScript.new()
	var metrics := controller.hud_layout_metrics(Vector2(844, 390))
	var dock_rect: Rect2 = metrics["button_dock_rect"]
	var button_height: float = metrics["button_height"]
	var button_gap: float = metrics["button_gap"]
	var button_padding: float = metrics["button_dock_padding"]
	var button_width := dock_rect.size.x - button_padding * 2.0
	harness.assert_true(button_width >= 120.0, "full-width button layout should give labels enough horizontal room")
	harness.assert_true(
		dock_rect.size.y >= button_height * 2.0 + button_gap + button_padding * 2.0,
		"button dock should reserve enough height for two stacked buttons"
	)
	controller.free()


static func _test_visual_scenarios(harness: RefCounted) -> void:
	harness.case("visual scenarios")
	var controller = ControllerScript.new()
	controller._ready()

	harness.assert_true(controller.prepare_visual_scenario("default"), "default scenario should load")
	harness.assert_true(not controller.run_state.current_piece.is_empty(), "default scenario should have an active piece")

	harness.assert_true(controller.prepare_visual_scenario("ghost"), "ghost scenario should load")
	harness.assert_true(not controller.run_state.current_piece.is_empty(), "ghost scenario should keep an active piece")
	harness.assert_true(
		controller.run_state.ghost_origin().y < controller.run_state.current_piece["origin"].y,
		"ghost scenario should place the ghost below the active piece"
	)

	harness.assert_true(controller.prepare_visual_scenario("line_clear_pause"), "line clear pause scenario should load")
	harness.assert_true(controller.run_state.is_clearing(), "line clear pause scenario should enter clearing state")
	harness.assert_true(controller.run_state.current_piece.is_empty(), "line clear pause scenario should hide the active piece")

	harness.assert_true(controller.prepare_visual_scenario("flipped_camera"), "flipped camera scenario should load")
	harness.assert_true(controller.view_flipped, "flipped camera scenario should force the flipped view")

	harness.assert_true(controller.prepare_visual_scenario("game_over"), "game over scenario should load")
	harness.assert_true(controller.run_state.game_over, "game over scenario should mark the run as over")

	harness.assert_true(not controller.prepare_visual_scenario("unknown"), "unknown visual scenarios should fail cleanly")
	controller.free()


static func _test_open_face_edges(harness: RefCounted) -> void:
	harness.case("open-face edges")
	var controller = ControllerScript.new()
	var frame := controller._build_board_frame()

	controller.current_camera_position = controller.CAMERA_NEAR_CORNER
	controller._sync_board_wall_visibility(frame)
	harness.assert_true(frame.get_node("edge_front_left").visible, "front-left edge should remain visible in the default view")
	harness.assert_true(not frame.get_node("edge_front_right").visible, "front-right nearest-corner edge should be hidden in the default view")
	harness.assert_true(not frame.get_node("edge_front_top").visible, "front-top nearest-corner edge should be hidden in the default view")
	harness.assert_true(not frame.get_node("edge_right_top").visible, "right-top nearest-corner edge should be hidden in the default view")

	controller.current_camera_position = controller.CAMERA_FAR_CORNER
	controller._sync_board_wall_visibility(frame)
	harness.assert_true(not frame.get_node("edge_back_left").visible, "back-left open-face edge should be hidden in the flipped view")
	harness.assert_true(not frame.get_node("edge_back_top").visible, "back-top open-face edge should be hidden in the flipped view")
	harness.assert_true(not frame.get_node("edge_left_top").visible, "left-top nearest-corner edge should be hidden in the flipped view")
	harness.assert_true(frame.get_node("edge_back_right").visible, "back-right edge should remain visible in the flipped view")
	frame.free()
	controller.free()


static func _test_ghost_shadow_projection(harness: RefCounted) -> void:
	harness.case("ghost shadow projection")
	var controller = ControllerScript.new()

	var support_cells := controller.landing_support_cells([
		{"position": Vector3i(4, 8, 4)},
		{"position": Vector3i(4, 9, 4)},
		{"position": Vector3i(5, 8, 4)},
		{"position": Vector3i(5, 7, 5)}
	])
	harness.assert_equal(
		support_cells.size(),
		3,
		"landing guide should identify one supporting block per X/Z footprint"
	)
	var floor_faces := controller.landing_floor_faces([
		{"position": Vector3i(4, 8, 4)},
		{"position": Vector3i(4, 9, 4)},
		{"position": Vector3i(5, 8, 4)},
		{"position": Vector3i(5, 7, 5)}
	])
	harness.assert_equal(
		floor_faces.size(),
		3,
		"landing guide should emit one floor face per X/Z footprint"
	)
	var single_column_support_cells := controller.landing_support_cells([
		{"position": Vector3i(4, 2, 5)}
	])
	var single_column_floor_faces := controller.landing_floor_faces([
		{"position": Vector3i(4, 2, 5)}
	])
	var support_overlay := controller._build_support_face_overlay()
	var floor_face := single_column_floor_faces[0]
	var floor_overlay := controller._build_receiver_face_overlay(floor_face)
	harness.assert_equal(single_column_support_cells[0], Vector3i(4, 1, 5), "support guide should target the supporting block directly below the landing cell")
	harness.assert_equal(support_overlay.position, Vector3(0.0, 0.464, 0.0), "support overlay should sit on top of its supporting block")
	harness.assert_true(support_overlay.mesh.size.x < floor_overlay.mesh.size.x, "support overlay should be inset relative to the floor guide")
	harness.assert_equal(floor_overlay.position, Vector3(4, -0.437, 5), "floor overlay should sit flush on the well floor face")
	support_overlay.free()
	floor_overlay.free()
	controller.free()


static func _test_view_relative_rotation(harness: RefCounted) -> void:
	harness.case("view-relative rotation")
	var controller = ControllerScript.new()

	controller.view_flipped = false
	harness.assert_equal(controller.view_relative_rotation_direction("x", 1), 1, "default view should keep positive X rotation")
	harness.assert_equal(controller.view_relative_rotation_direction("z", -1), -1, "default view should keep negative Z rotation")
	harness.assert_equal(controller.view_relative_rotation_direction("y", 1), -1, "default view should invert positive Y rotation")
	harness.assert_equal(controller.view_relative_rotation_direction("y", -1), 1, "default view should invert negative Y rotation")

	controller.view_flipped = true
	harness.assert_equal(controller.view_relative_rotation_direction("x", 1), -1, "flipped view should invert positive X rotation")
	harness.assert_equal(controller.view_relative_rotation_direction("x", -1), 1, "flipped view should invert negative X rotation")
	harness.assert_equal(controller.view_relative_rotation_direction("z", 1), -1, "flipped view should invert positive Z rotation")
	harness.assert_equal(controller.view_relative_rotation_direction("z", -1), 1, "flipped view should invert negative Z rotation")
	harness.assert_equal(controller.view_relative_rotation_direction("y", 1), -1, "flipped view should also invert positive Y rotation")
	harness.assert_equal(controller.view_relative_rotation_direction("y", -1), 1, "flipped view should also invert negative Y rotation")
	controller.free()


static func _test_left_swipe_angle_threshold(harness: RefCounted) -> void:
	harness.case("left swipe angle threshold")

	harness.assert_equal(
		InputActionMapScript.action_for_swipe(Vector2(70, 20)),
		InputActionMapScript.ROTATE_Y_CW,
		"strongly horizontal left-side swipes should still rotate around Y"
	)
	harness.assert_equal(
		InputActionMapScript.action_for_swipe(Vector2(60, 35)),
		InputActionMapScript.ROTATE_Z_CCW,
		"shallower diagonals should now fall through to the diagonal rotation mapping"
	)
	harness.assert_equal(
		InputActionMapScript.action_for_swipe(Vector2(-60, -35)),
		InputActionMapScript.ROTATE_Z_CW,
		"mirrored shallower diagonals should also avoid accidental Y rotation"
	)


static func _test_right_swipe_angle_threshold(harness: RefCounted) -> void:
	harness.case("right swipe angle threshold")
	var controller = ControllerScript.new()

	harness.assert_equal(
		controller._movement_delta_for_swipe(Vector2(60, 35)),
		Vector3i(1, 0, 0),
		"flatter diagonal right-side swipes should still register as movement"
	)
	harness.assert_equal(
		controller._movement_delta_for_swipe(Vector2(35, -60)),
		Vector3i(0, 0, -1),
		"flatter forward diagonals should still register as movement"
	)
	harness.assert_equal(
		controller._movement_delta_for_swipe(Vector2(80, 20)),
		Vector3i(1, 0, 0),
		"off-axis swipes should continue to register as movement"
	)
	harness.assert_equal(
		controller._movement_delta_for_swipe(Vector2(140, 12)),
		Vector3i(1, 0, 0),
		"extremely axis-aligned swipes should now resolve to the nearest movement direction"
	)
	harness.assert_equal(
		controller._movement_delta_for_swipe(Vector2(12, -140)),
		Vector3i(0, 0, -1),
		"near-vertical swipes should also resolve to movement once they clear the tap guard"
	)
	harness.assert_equal(
		controller._movement_delta_for_swipe(Vector2(20, 8)),
		Vector3i.ZERO,
		"tap-sized swipes should still be ignored"
	)
	controller.free()


static func _test_swipe_peak_excursion(harness: RefCounted) -> void:
	harness.case("swipe peak excursion")
	var controller = ControllerScript.new()

	harness.assert_equal(
		controller.strongest_swipe_delta(Vector2(10, 4), Vector2(48, 18)),
		Vector2(48, 18),
		"peak excursion should win when the release delta shrinks below it"
	)
	harness.assert_equal(
		controller.strongest_swipe_delta(Vector2(60, 0), Vector2(48, 18)),
		Vector2(60, 0),
		"release delta should still win when it is the largest excursion"
	)

	controller.touch_peak_delta = Vector2.ZERO
	controller._update_touch_peak_delta(Vector2(20, 5))
	controller._update_touch_peak_delta(Vector2(12, 3))
	harness.assert_equal(
		controller.touch_peak_delta,
		Vector2(20, 5),
		"smaller later drags should not replace the recorded peak excursion"
	)
	controller._update_touch_peak_delta(Vector2(42, -8))
	harness.assert_equal(
		controller.touch_peak_delta,
		Vector2(42, -8),
		"larger later drags should replace the recorded peak excursion"
	)
	controller.free()


static func _test_double_tap_detection(harness: RefCounted) -> void:
	harness.case("double tap detection")
	var controller = ControllerScript.new()
	var now_ms := Time.get_ticks_msec()

	controller.last_tap_time_ms = now_ms - 100
	controller.last_tap_position = Vector2(200, 300)
	harness.assert_true(
		controller._is_double_tap(Vector2(210, 308), Vector2(4, -3)),
		"nearby taps within the interval should count as a double tap"
	)

	controller.last_tap_time_ms = now_ms - 500
	controller.last_tap_position = Vector2(200, 300)
	harness.assert_true(
		not controller._is_double_tap(Vector2(205, 305), Vector2(3, 3)),
		"taps outside the interval should not count as a double tap"
	)

	controller.last_tap_time_ms = now_ms - 100
	controller.last_tap_position = Vector2(200, 300)
	harness.assert_true(
		not controller._is_double_tap(Vector2(205, 305), Vector2(40, 0)),
		"swipe-sized motion should not count as a double tap"
	)
	controller.free()
