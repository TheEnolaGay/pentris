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
	_test_staged_startup(harness)
	_test_intro_tutorial_activation(harness)
	_test_intro_tutorial_progression(harness)
	_test_intro_tutorial_swipe_input_events(harness)
	_test_next_preview_stage(harness)
	_test_button_layout_metrics(harness)
	_test_hud_menu_actions(harness)
	_test_hud_menu_layout(harness)
	_test_pause_board_blocks_gameplay(harness)
	_test_scoreboard_labels(harness)
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
	harness.assert_true(absf(near_spans["width"] - far_spans["width"]) < 0.001, "mirrored camera corners should keep equivalent projected board width")
	harness.assert_true(absf(near_spans["height"] - far_spans["height"]) < 0.001, "mirrored camera corners should keep equivalent projected board height")
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


static func _test_staged_startup(harness: RefCounted) -> void:
	harness.case("staged startup")
	var controller = ControllerScript.new()
	controller._ready()
	harness.assert_true(not controller.startup_complete, "controller should not finish startup synchronously")
	harness.assert_true(controller.run_state == null, "run state should not exist before startup completes")
	harness.assert_true(controller.startup_layer != null, "startup shell should exist during staged startup")
	harness.assert_equal(controller.startup_status_label.text, controller.STARTUP_STATUS_LOADING, "startup shell should expose the initial loading label")
	controller._finish_startup()
	harness.assert_true(controller.startup_complete, "startup helper should complete initialization")
	harness.assert_true(controller.run_state != null, "run state should exist once startup completes")
	harness.assert_true(controller.startup_layer != null and not controller.startup_layer.visible, "startup shell should hide after initialization")
	harness.assert_true(controller.tutorial_active, "startup should hand off into the intro tutorial before gameplay begins")
	controller.free()


static func _test_intro_tutorial_activation(harness: RefCounted) -> void:
	harness.case("intro tutorial activation")
	var controller = ControllerScript.new()
	controller._ready()
	controller._finish_startup()
	harness.assert_true(controller.tutorial_active, "intro tutorial should activate on launch")
	harness.assert_true(not controller.tutorial_completed, "tutorial should not be marked complete on activation")
	harness.assert_equal(controller.tutorial_step, 0, "tutorial should begin on the first movement step")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "MOVE DOWN-RIGHT", "tutorial should begin with the first X movement prompt")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "↘", "tutorial should show a large directional hint for the first swipe")
	harness.assert_equal(controller.hud_labels["tutorial_progress"].text, "1/13", "tutorial should expose granular progress for the full checklist")
	harness.assert_true(not controller.hud_labels["button_menu"].visible, "menu trigger should stay hidden during the tutorial")
	controller._open_pause_board()
	harness.assert_true(not controller.pause_board_open, "pause menu should stay unavailable during the tutorial")
	harness.assert_true(controller._gameplay_locked(), "tutorial should lock gameplay while active")
	controller.free()


static func _test_intro_tutorial_progression(harness: RefCounted) -> void:
	harness.case("intro tutorial progression")
	var controller = ControllerScript.new()
	controller._ready()
	controller._finish_startup()
	var origin_before: Vector3i = controller.run_state.current_piece["origin"]
	var movement_blocks_before = controller.run_state.current_piece["blocks"].duplicate(true)

	controller._handle_tutorial_swipe(Vector2(-48, -48), "right")
	harness.assert_equal(controller.tutorial_step, 0, "wrong first movement direction should not advance the tutorial")

	controller._handle_tutorial_swipe(Vector2(48, 48), "right")
	harness.assert_equal(controller.tutorial_step, 1, "movement tutorial should advance after the first X swipe")
	harness.assert_equal(controller.run_state.current_piece["origin"], origin_before + Vector3i(1, 0, 0), "tutorial movement step should move the live piece for feedback")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "MOVE UP-LEFT", "tutorial should move to the opposite X direction next")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "↖", "tutorial should flip the hint arrow for the second X swipe")

	controller._handle_tutorial_swipe(Vector2(-48, 48), "right")
	harness.assert_equal(controller.tutorial_step, 1, "wrong movement axis should not advance the tutorial")

	controller._handle_tutorial_swipe(Vector2(-48, -48), "right")
	harness.assert_equal(controller.tutorial_step, 2, "movement tutorial should require the opposite X swipe")
	harness.assert_equal(controller.run_state.current_piece["origin"], origin_before, "opposite movement should bring the live piece back across the X axis")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "MOVE DOWN-LEFT", "tutorial should then teach the first Z movement")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "↙", "tutorial should show the correct diagonal for moving back")

	controller._handle_tutorial_swipe(Vector2(-48, 48), "right")
	harness.assert_equal(controller.tutorial_step, 3, "movement tutorial should advance on the back swipe")
	harness.assert_equal(controller.run_state.current_piece["origin"], origin_before + Vector3i(0, 0, 1), "tutorial should move the live piece along Z during the movement lesson")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "MOVE UP-RIGHT", "tutorial should then teach the opposite Z movement")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "↗", "tutorial should show the correct diagonal for moving forward")

	controller._handle_tutorial_swipe(Vector2(48, -48), "right")
	harness.assert_equal(controller.tutorial_step, 4, "movement tutorial should require the forward swipe before rotations")
	harness.assert_equal(controller.run_state.current_piece["name"], "L", "tutorial should reset to the rotation baseline before the first rotation step")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "SWIPE DOWN-LEFT", "tutorial should begin the X rotation pair next")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "↙", "tutorial should show the first X rotation swipe")
	harness.assert_true(controller.run_state.current_piece["blocks"] != movement_blocks_before, "rotation baseline should restore a distinct piece state before rotation lessons")

	controller._handle_tutorial_swipe(Vector2(48, -48), "left")
	harness.assert_equal(controller.tutorial_step, 4, "wrong X rotation direction should not advance the tutorial")

	var rotation_blocks_before = controller.run_state.current_piece["blocks"].duplicate(true)
	controller._handle_tutorial_swipe(Vector2(-48, 48), "left")
	harness.assert_equal(controller.tutorial_step, 5, "tutorial should advance after the first X rotation swipe")
	harness.assert_true(controller.run_state.current_piece["blocks"] != rotation_blocks_before, "tutorial rotation should visibly change the live piece")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "SWIPE UP-RIGHT", "tutorial should require the opposite X rotation next")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "↗", "tutorial should flip the X rotation arrow")

	controller._handle_tutorial_swipe(Vector2(48, -48), "left")
	harness.assert_equal(controller.tutorial_step, 6, "tutorial should require both X rotation directions")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "SWIPE UP-LEFT", "tutorial should move on to Z rotation")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "↖", "tutorial should show the first Z rotation swipe")

	controller._handle_tutorial_swipe(Vector2(-48, -48), "left")
	harness.assert_equal(controller.tutorial_step, 7, "tutorial should advance after the first Z rotation swipe")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "SWIPE DOWN-RIGHT", "tutorial should require the opposite Z rotation next")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "↘", "tutorial should flip the Z rotation arrow")

	controller._handle_tutorial_swipe(Vector2(48, 48), "left")
	harness.assert_equal(controller.tutorial_step, 8, "tutorial should require both Z rotation directions")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "ROTATE RIGHT", "tutorial should move on to Y rotation")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "→", "tutorial should show the first Y rotation swipe")

	controller._handle_tutorial_swipe(Vector2(72, 0), "left")
	harness.assert_equal(controller.tutorial_step, 9, "tutorial should advance after the first Y rotation swipe")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "ROTATE LEFT", "tutorial should require the opposite Y rotation next")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "←", "tutorial should flip the Y rotation arrow")

	controller._handle_tutorial_swipe(Vector2(-72, 0), "left")
	harness.assert_equal(controller.tutorial_step, 10, "tutorial should require both Y rotation directions")
	harness.assert_equal(controller.run_state.current_piece["name"], "T", "tutorial should reset to the clean baseline before the drop lesson")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "TAP DROP", "tutorial should then move to the drop button")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "TAP", "tutorial should replace the arrow with a drop cue")

	controller._handle_tutorial_double_tap()
	harness.assert_equal(controller.tutorial_step, 10, "double tap should not bypass the drop tutorial step")

	controller._button_drop()
	harness.assert_equal(controller.tutorial_step, 11, "drop tutorial should advance from the drop button")
	harness.assert_equal(controller.run_state.current_piece["name"], "T", "tutorial should restore the clean baseline after demonstrating the drop")
	harness.assert_equal(controller.run_state.current_piece["origin"], origin_before, "tutorial should reset to the clean board before the camera lesson")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "DOUBLE TAP TO SWAP", "tutorial should then teach the camera swap")
	harness.assert_equal(controller.hud_labels["tutorial_hint"].text, "TAP x2", "tutorial should show a compact double-tap cue for tap steps")

	controller._handle_tutorial_double_tap()
	harness.assert_equal(controller.tutorial_step, 12, "camera tutorial should advance to the start prompt after a double tap")
	harness.assert_true(controller.camera_transition_active, "camera tutorial should trigger the swap animation")
	controller._advance_camera_transition(controller.CAMERA_SWAP_DURATION)
	harness.assert_true(controller.view_flipped, "camera tutorial should leave the view flipped before the start prompt")
	harness.assert_equal(controller.hud_labels["tutorial_instruction"].text, "DOUBLE TAP TO START", "tutorial should end on the separate start gate")
	harness.assert_equal(controller.hud_labels["tutorial_progress"].text, "13/13", "tutorial should reach the final progress step before completing")

	controller._handle_tutorial_double_tap()
	harness.assert_true(controller.camera_transition_active, "final tutorial start should animate back to the front view")
	harness.assert_true(controller.tutorial_finishing, "tutorial should stay in a finishing state while the return animation runs")
	harness.assert_true(controller._gameplay_locked(), "gameplay should stay locked until the return animation finishes")
	controller._advance_camera_transition(controller.CAMERA_SWAP_DURATION)
	harness.assert_true(not controller.tutorial_active, "tutorial overlay should be gone after the return animation completes")
	harness.assert_true(controller.tutorial_completed, "tutorial should be marked complete after the animated start handoff")
	harness.assert_true(not controller.tutorial_finishing, "tutorial finishing state should clear once the camera settles")
	harness.assert_true(not controller.view_flipped, "final tutorial start should return the camera to the front view")
	controller.free()


static func _test_intro_tutorial_swipe_input_events(harness: RefCounted) -> void:
	harness.case("intro tutorial swipe input events")
	var controller = ControllerScript.new()
	controller._ready()
	controller._finish_startup()

	var right_press := InputEventScreenTouch.new()
	right_press.pressed = true
	right_press.position = Vector2(700, 180)
	controller._input(right_press)

	var right_drag := InputEventScreenDrag.new()
	right_drag.position = Vector2(748, 228)
	controller._input(right_drag)
	controller._process(0.016)

	var right_release := InputEventScreenTouch.new()
	right_release.pressed = false
	right_release.position = Vector2(748, 228)
	controller._input(right_release)

	harness.assert_equal(controller.tutorial_step, 1, "tutorial should advance from the first movement step on a real right-side swipe")
	harness.assert_true(not controller.touch_active, "touch capture should end after the swipe release is processed")

	controller.tutorial_step = 4
	controller._refresh_view()

	var left_press := InputEventScreenTouch.new()
	left_press.pressed = true
	left_press.position = Vector2(120, 180)
	controller._input(left_press)

	var left_drag := InputEventScreenDrag.new()
	left_drag.position = Vector2(72, 228)
	controller._input(left_drag)
	controller._process(0.016)

	var left_release := InputEventScreenTouch.new()
	left_release.pressed = false
	left_release.position = Vector2(72, 228)
	controller._input(left_release)

	harness.assert_equal(controller.tutorial_step, 5, "tutorial should advance from the first X rotation step on a real left-side swipe")
	controller.free()


static func _test_next_preview_stage(harness: RefCounted) -> void:
	harness.case("next preview stage")
	var controller = ControllerScript.new()
	var anchor: Vector3 = controller._next_preview_stage_anchor_fallback(controller.CAMERA_NEAR_CORNER)
	harness.assert_true(anchor.x > controller.BOARD_BOUNDS_MAX.x, "next preview stage should sit to the right of the board bounds")
	controller._ready()
	controller._finish_startup()
	controller._dismiss_tutorial_for_automation()
	harness.assert_true(controller.next_preview_root != null, "next preview stage root should exist in the main scene")
	harness.assert_true(controller.next_preview_piece_root.get_child_count() > 0, "next preview stage should render the upcoming piece in the main scene")
	controller.free()


static func _test_button_layout_metrics(harness: RefCounted) -> void:
	harness.case("button layout metrics")
	var controller = ControllerScript.new()
	var metrics := controller.hud_layout_metrics(Vector2(844, 390))
	var dock_rect: Rect2 = metrics["button_dock_rect"]
	var button_height: float = metrics["button_height"]
	var button_padding: float = metrics["button_dock_padding"]
	var button_width := dock_rect.size.x - button_padding * 2.0
	harness.assert_true(button_width >= 120.0, "full-width button layout should give labels enough horizontal room")
	harness.assert_true(
		absf(dock_rect.size.y - (button_height + button_padding * 2.0)) < 0.01,
		"button dock should reserve space for the single drop action"
	)
	controller.free()


static func _test_hud_menu_actions(harness: RefCounted) -> void:
	harness.case("hud menu actions")
	var controller = ControllerScript.new()
	controller._ready()
	controller._finish_startup()
	controller._dismiss_tutorial_for_automation()
	var menu_button: Button = controller.hud_labels["button_menu"]
	harness.assert_equal(menu_button.text, "MENU", "hud should expose a menu button for secondary actions")
	controller._open_pause_board()
	harness.assert_true(controller.pause_board_open, "opening the menu should show the pause board")
	harness.assert_true(controller._gameplay_locked(), "pause board should block gameplay while open")
	controller.run_state.score = 123
	controller._close_pause_board()
	harness.assert_true(not controller.pause_board_open, "resume should close the pause board")
	harness.assert_equal(controller.run_state.score, 123, "resume should preserve run state")
	controller._open_pause_board()
	harness.assert_true(controller.pause_board_open, "menu should reopen after resume")
	controller.run_state.score = 123
	controller._button_new_run()
	harness.assert_equal(controller.run_state.score, 0, "new run menu action should reset the run")
	harness.assert_true(not controller.pause_board_open, "new run should close the pause board")
	controller.free()


static func _test_hud_menu_layout(harness: RefCounted) -> void:
	harness.case("hud menu layout")
	var controller = ControllerScript.new()
	var metrics := controller.hud_layout_metrics(Vector2(844, 390))
	var title_rect: Rect2 = metrics["title_rect"]
	var title_text_rect: Rect2 = metrics["title_text_rect"]
	var menu_rect: Rect2 = metrics["menu_rect"]
	var stats_rect: Rect2 = metrics["stats_rect"]
	var queue_rect: Rect2 = metrics["queue_rect"]
	var queue_title_rect: Rect2 = metrics["queue_title_rect"]
	var queue_preview_frame_rect: Rect2 = metrics["queue_preview_frame_rect"]
	var queue_preview_rect: Rect2 = metrics["queue_preview_rect"]
	var pause_board_rect: Rect2 = metrics["pause_board_rect"]
	var pause_inner_rect: Rect2 = metrics["pause_inner_rect"]
	var pause_subtitle_rect: Rect2 = metrics["pause_subtitle_rect"]
	var pause_divider_rect: Rect2 = metrics["pause_divider_rect"]
	var pause_button_resume_rect: Rect2 = metrics["pause_button_resume_rect"]
	var pause_button_new_run_rect: Rect2 = metrics["pause_button_new_run_rect"]
	var tutorial_focus_rect: Rect2 = metrics["tutorial_focus_rect"]
	var tutorial_caption_rect: Rect2 = metrics["tutorial_caption_rect"]
	var tutorial_instruction_rect: Rect2 = metrics["tutorial_instruction_rect"]
	var tutorial_hint_rect: Rect2 = metrics["tutorial_hint_rect"]
	var tutorial_helper_rect: Rect2 = metrics["tutorial_helper_rect"]
	var tutorial_progress_rect: Rect2 = metrics["tutorial_progress_rect"]
	var tutorial_dim_left_rect: Rect2 = metrics["tutorial_dim_left_rect"]
	var tutorial_dim_right_rect: Rect2 = metrics["tutorial_dim_right_rect"]
	var tutorial_dim_top_rect: Rect2 = metrics["tutorial_dim_top_rect"]
	var tutorial_dim_bottom_rect: Rect2 = metrics["tutorial_dim_bottom_rect"]
	var play_rect: Rect2 = metrics["play_rect"]
	var dock_rect: Rect2 = metrics["button_dock_rect"]
	harness.assert_true(menu_rect.intersects(title_rect), "menu trigger should live within the title rail")
	harness.assert_true(not menu_rect.intersects(title_text_rect), "menu trigger should not overlap the title text")
	harness.assert_true(menu_rect.position.x >= title_text_rect.end.x, "menu trigger should sit to the right of the title")
	harness.assert_true(menu_rect.size.x <= 48.0, "menu trigger should stay compact relative to the title rail")
	harness.assert_true(title_text_rect.size.x > menu_rect.size.x, "title text should remain more prominent than the menu trigger")
	harness.assert_true(menu_rect.end.y <= stats_rect.position.y, "menu trigger should clear the stats panel")
	harness.assert_true(absf(queue_rect.size.x - dock_rect.size.x) < 0.01, "next rail should match the drop dock width")
	harness.assert_true(not queue_title_rect.intersects(queue_preview_frame_rect), "next title should have its own row above the featured preview frame")
	harness.assert_true(queue_rect.encloses(queue_preview_frame_rect), "featured next-piece frame should stay inside the queue rail")
	harness.assert_true(queue_preview_frame_rect.encloses(queue_preview_rect), "next-piece blocks should stay inside the featured preview frame")
	harness.assert_true(queue_preview_frame_rect.size.y > queue_rect.size.y * 0.7, "next preview should use most of the top-right rail height")
	harness.assert_true(absf(pause_board_rect.get_center().x - 422.0) < 1.0, "pause board should remain horizontally centered on the phone baseline")
	harness.assert_true(absf(pause_board_rect.get_center().y - 195.0) < 1.0, "pause board should remain vertically centered on the phone baseline")
	harness.assert_true(pause_board_rect.size.x >= 320.0, "pause board should be much wider for mobile taps")
	harness.assert_true(pause_board_rect.size.y >= 250.0, "pause board should be much taller for mobile taps")
	harness.assert_true(pause_board_rect.encloses(pause_inner_rect), "pause board should maintain an inner frame for retro framing")
	harness.assert_true(not pause_subtitle_rect.intersects(pause_divider_rect), "pause subtitle should keep a dedicated lane above the divider")
	harness.assert_true(pause_divider_rect.end.y <= pause_button_resume_rect.position.y, "pause divider should sit above the first button with explicit clearance")
	harness.assert_true(pause_inner_rect.encloses(pause_button_resume_rect), "pause inner frame should fully contain the resume button")
	harness.assert_true(pause_inner_rect.encloses(pause_button_new_run_rect), "pause inner frame should fully contain the new run button")
	harness.assert_true(pause_button_resume_rect.size.y >= 44.0, "resume button should become a finger-friendly touch target")
	harness.assert_true(pause_button_new_run_rect.size.y >= 44.0, "new run button should become a finger-friendly touch target")
	harness.assert_true(tutorial_focus_rect.position.x >= 422.0, "movement tutorial should highlight the right side by default")
	harness.assert_true(tutorial_caption_rect.end.x <= tutorial_focus_rect.position.x, "tutorial caption should stay in the dimmed area opposite the focus zone")
	harness.assert_true(tutorial_focus_rect.encloses(tutorial_hint_rect), "tutorial glyph should stay inside the highlighted focus zone")
	harness.assert_true(not tutorial_caption_rect.intersects(tutorial_focus_rect), "tutorial caption should not overlap the highlighted focus zone")
	harness.assert_true(not tutorial_instruction_rect.intersects(tutorial_progress_rect), "tutorial prompt should clear the progress lane inside the caption")
	harness.assert_true(tutorial_dim_left_rect.size.x > 0.0, "tutorial should dim the unfocused left side during right-side steps")
	harness.assert_true(tutorial_dim_right_rect.size.x <= 14.0, "tutorial should only leave the outer edge margin dimmed on the active side")
	harness.assert_true(tutorial_dim_top_rect.size.y >= 0.0 and tutorial_dim_bottom_rect.size.y >= 0.0, "tutorial should expose top and bottom dim bands as needed")
	controller.tutorial_step = 10
	var drop_metrics := controller.hud_layout_metrics(Vector2(844, 390))
	var drop_focus_rect: Rect2 = drop_metrics["tutorial_focus_rect"]
	harness.assert_true(drop_focus_rect.intersects(dock_rect), "drop tutorial should spotlight the drop dock")
	controller.tutorial_step = 11
	var tap_metrics := controller.hud_layout_metrics(Vector2(844, 390))
	var tap_focus_rect: Rect2 = tap_metrics["tutorial_focus_rect"]
	harness.assert_true(play_rect.encloses(tap_focus_rect), "double-tap tutorial should spotlight only the play area")
	controller.free()


static func _test_pause_board_blocks_gameplay(harness: RefCounted) -> void:
	harness.case("pause board blocks gameplay")
	var controller = ControllerScript.new()
	controller._ready()
	controller._finish_startup()
	controller._dismiss_tutorial_for_automation()
	controller.run_state.set_board_cells_for_test([])
	controller.run_state.set_active_piece_for_test("T", Vector3i(4, 18, 4))
	var origin_before: Vector3i = controller.run_state.current_piece["origin"]
	controller._open_pause_board()
	controller._request_move(Vector3i(-1, 0, 0))
	controller._button_drop()
	harness.assert_equal(controller.run_state.current_piece["origin"], origin_before, "pause board should block movement and drop actions")
	controller.free()


static func _test_scoreboard_labels(harness: RefCounted) -> void:
	harness.case("scoreboard labels")
	var controller = ControllerScript.new()
	controller._ready()
	controller._finish_startup()
	controller._dismiss_tutorial_for_automation()
	controller.run_state.score = 42
	controller.run_state.level = 3
	controller.run_state.cleared_rows_total = 7
	controller._refresh_labels()

	harness.assert_true(not controller.hud_labels["info"].visible, "legacy multiline info label should stay hidden")
	harness.assert_equal(controller.hud_labels["score_header"].text, "SCORE", "scoreboard should render a score header")
	harness.assert_equal(controller.hud_labels["score_value"].text, "000042", "scoreboard should zero-pad score values")
	harness.assert_equal(controller.hud_labels["level_value"].text, "03", "scoreboard should zero-pad level values")
	harness.assert_equal(controller.hud_labels["lines_value"].text, "007", "scoreboard should zero-pad line totals")
	controller.free()


static func _test_visual_scenarios(harness: RefCounted) -> void:
	harness.case("visual scenarios")
	var controller = ControllerScript.new()
	controller._ready()
	controller._finish_startup()

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

	harness.assert_true(controller.prepare_visual_scenario("tutorial_move"), "tutorial move scenario should load")
	harness.assert_true(controller.tutorial_active, "tutorial move scenario should restore the tutorial overlay")
	harness.assert_equal(controller.tutorial_step, 0, "tutorial move scenario should land on the first tutorial step")

	harness.assert_true(controller.prepare_visual_scenario("tutorial_rotate"), "tutorial rotate scenario should load")
	harness.assert_true(controller.tutorial_active, "tutorial rotate scenario should keep the tutorial visible")
	harness.assert_equal(controller.tutorial_step, 5, "tutorial rotate scenario should land on a mid-rotation step")

	harness.assert_true(controller.prepare_visual_scenario("tutorial_drop"), "tutorial drop scenario should load")
	harness.assert_true(controller.tutorial_active, "tutorial drop scenario should keep the tutorial visible")
	harness.assert_equal(controller.tutorial_step, 10, "tutorial drop scenario should land on the drop step")

	harness.assert_true(controller.prepare_visual_scenario("tutorial_start"), "tutorial start scenario should load")
	harness.assert_true(controller.tutorial_active, "tutorial start scenario should keep the tutorial visible")
	harness.assert_true(controller.view_flipped, "tutorial start scenario should stage the final start step from the flipped view")
	harness.assert_equal(controller.tutorial_step, controller.TUTORIAL_STEP_COUNT - 1, "tutorial start scenario should land on the final tutorial step")

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
		InputActionMapScript.action_for_swipe(Vector2(70, 34)),
		InputActionMapScript.ROTATE_Z_CCW,
		"moderate diagonals near the old boundary should now prefer Z over accidental Y"
	)
	harness.assert_equal(
		InputActionMapScript.action_for_swipe(Vector2(88, 30)),
		InputActionMapScript.ROTATE_Y_CW,
		"clearly flatter swipes should still remain on Y after the threshold change"
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
