class_name VisualPlaytestExecutor
extends RefCounted

const SCRIPT_NAMES := ["full_action_sweep", "line_clear_flow", "hud_restart_flow"]
const ACTION_CATEGORY_MAP := {
	"move": "movement",
	"rotate": "rotation",
	"hold": "hold",
	"hard_drop": "hard_drop",
	"open_menu": "menu",
	"resume_menu": "menu",
	"press_drop_button": "hud_drop",
	"menu_new_run": "restart",
	"flip_view": "view_flip",
	"set_scenario": "scenario",
	"start_run": "restart"
}


static func default_fps() -> int:
	return 24


static func script_names() -> PackedStringArray:
	return PackedStringArray(SCRIPT_NAMES)


static func script_definition(name: String) -> Dictionary:
	match name:
		"full_action_sweep":
			return {
				"seed": 7,
				"steps": [
					{"type": "start_run", "seed": 7},
					{"type": "configure_board", "cells": []},
					{"type": "configure_piece", "piece": "T", "origin": Vector3i(4, 18, 4)},
					{"type": "capture", "label": "00_baseline"},
					{"type": "move", "delta": Vector3i(-1, 0, 0)},
					{"type": "capture", "label": "01_move_left"},
					{"type": "move", "delta": Vector3i(1, 0, 0)},
					{"type": "capture", "label": "02_move_right"},
					{"type": "move", "delta": Vector3i(0, 0, -1)},
					{"type": "capture", "label": "03_move_forward"},
					{"type": "move", "delta": Vector3i(0, 0, 1)},
					{"type": "capture", "label": "04_move_backward"},
					{"type": "rotate", "axis": "y", "direction": 1},
					{"type": "capture", "label": "05_rotate_y"},
					{"type": "rotate", "axis": "x", "direction": 1},
					{"type": "capture", "label": "06_rotate_x"},
					{"type": "rotate", "axis": "z", "direction": 1},
					{"type": "capture", "label": "07_rotate_z"},
					{"type": "hold"},
					{"type": "assert", "hold_piece_nonempty": true, "current_piece_nonempty": true},
					{"type": "capture", "label": "08_hold"},
					{"type": "hard_drop"},
					{"type": "capture", "label": "09_hard_drop"},
					{"type": "flip_view"},
					{"type": "assert", "view_flipped": true},
					{"type": "capture", "label": "10_flip_view"},
					{"type": "start_run", "seed": 7},
					{"type": "configure_board", "cells": []},
					{"type": "configure_piece", "piece": "L", "origin": Vector3i(4, 17, 4)},
					{"type": "open_menu"},
					{"type": "assert", "pause_board_open": true},
					{"type": "capture", "label": "11_menu_open"},
					{"type": "resume_menu"},
					{"type": "assert", "pause_board_open": false},
					{"type": "capture", "label": "12_menu_resume"},
					{"type": "press_drop_button"},
					{"type": "capture", "label": "13_drop_button"},
					{"type": "open_menu"},
					{"type": "assert", "pause_board_open": true},
					{"type": "capture", "label": "14_menu_open_restart"},
					{"type": "menu_new_run"},
					{"type": "assert", "score_equals": 0, "game_over": false, "pause_board_open": false},
					{"type": "capture", "label": "15_menu_new_run"},
					{"type": "set_scenario", "name": "line_clear_pause"},
					{"type": "assert", "is_clearing": true},
					{"type": "capture", "label": "16_line_clear_pause"},
					{"type": "resolve_clear"},
					{"type": "assert", "is_clearing": false, "current_piece_nonempty": true},
					{"type": "capture", "label": "17_post_clear"},
					{"type": "set_scenario", "name": "game_over"},
					{"type": "assert", "game_over": true},
					{"type": "capture", "label": "18_game_over"}
				]
			}
		"line_clear_flow":
			return {
				"seed": 11,
				"steps": [
					{"type": "set_scenario", "name": "line_clear_pause"},
					{"type": "assert", "is_clearing": true},
					{"type": "capture", "label": "00_line_clear_pause"},
					{"type": "resolve_clear"},
					{"type": "assert", "is_clearing": false, "current_piece_nonempty": true},
					{"type": "capture", "label": "01_post_clear"}
				]
			}
		"hud_restart_flow":
			return {
				"seed": 5,
				"steps": [
					{"type": "start_run", "seed": 5},
					{"type": "configure_board", "cells": []},
					{"type": "configure_piece", "piece": "T", "origin": Vector3i(4, 18, 4)},
					{"type": "capture", "label": "00_menu_idle"},
					{"type": "open_menu"},
					{"type": "assert", "pause_board_open": true},
					{"type": "capture", "label": "01_menu_open"},
					{"type": "resume_menu"},
					{"type": "assert", "pause_board_open": false},
					{"type": "capture", "label": "02_menu_resume"},
					{"type": "press_drop_button"},
					{"type": "capture", "label": "03_drop_button"},
					{"type": "open_menu"},
					{"type": "menu_new_run"},
					{"type": "assert", "score_equals": 0, "game_over": false, "pause_board_open": false},
					{"type": "capture", "label": "04_menu_new_run"}
				]
			}
		_:
			return {}


static func validate_script_definition(script: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if script.is_empty():
		issues.append("script definition is empty")
		return issues
	var steps: Array = script.get("steps", [])
	if steps.is_empty():
		issues.append("script has no steps")
	for index in range(steps.size()):
		var step: Dictionary = steps[index]
		if not step.has("type"):
			issues.append("step %d is missing type" % index)
			continue
		match step["type"]:
			"capture":
				if String(step.get("label", "")) == "":
					issues.append("capture step %d is missing label" % index)
			"move":
				if not step.has("delta"):
					issues.append("move step %d is missing delta" % index)
			"rotate":
				if String(step.get("axis", "")) == "" or not step.has("direction"):
					issues.append("rotate step %d is missing axis or direction" % index)
			"configure_piece":
				if String(step.get("piece", "")) == "" or not step.has("origin"):
					issues.append("configure_piece step %d is missing piece or origin" % index)
			"set_scenario":
				if String(step.get("name", "")) == "":
					issues.append("set_scenario step %d is missing name" % index)
	return issues


static func action_categories(script_name: String) -> Array[String]:
	var script := script_definition(script_name)
	var categories: Array[String] = []
	for step in script.get("steps", []):
		var category: String = ACTION_CATEGORY_MAP.get(step.get("type", ""), "")
		if category != "" and not categories.has(category):
			categories.append(category)
	return categories


func new_report(script_name: String, viewport_preset: String, fps: int, seed: int) -> Dictionary:
	return {
		"script_name": script_name,
		"viewport_preset": viewport_preset,
		"fps": fps,
		"seed": seed,
		"steps_executed": [],
		"captures": [],
		"failures": [],
		"action_categories": action_categories(script_name),
		"status": "pending"
	}


func execute_step(controller: Node, step: Dictionary, report: Dictionary) -> void:
	var step_type: String = step.get("type", "")
	report["steps_executed"].append(step.get("label", step_type))
	if controller.has_method("_dismiss_tutorial_for_automation"):
		controller._dismiss_tutorial_for_automation()
	match step_type:
		"start_run":
			controller._start_run_with_seed(int(step.get("seed", report["seed"])))
		"set_scenario":
			var scenario_name: String = step.get("name", "")
			if not controller.prepare_visual_scenario(scenario_name):
				_fail(report, "failed to load scenario %s" % scenario_name)
		"configure_board":
			controller.run_state.set_board_cells_for_test(step.get("cells", []))
			controller._refresh_view()
		"configure_piece":
			controller.run_state.set_active_piece_for_test(step.get("piece", ""), step.get("origin", Vector3i.ZERO), step.get("rotations", []))
			controller._refresh_view()
		"move":
			controller._request_move(step.get("delta", Vector3i.ZERO))
			controller._refresh_view()
		"rotate":
			controller._request_rotation(step.get("axis", ""), int(step.get("direction", 0)))
			controller._refresh_view()
		"hold":
			if not controller.run_state.hold_current():
				_fail(report, "hold action failed")
			controller._refresh_view()
		"open_menu":
			controller._open_pause_board()
		"resume_menu":
			controller._close_pause_board()
		"hard_drop":
			if controller.run_state.hard_drop() <= 0:
				_fail(report, "hard drop did not move the active piece")
			controller._refresh_view()
		"press_drop_button":
			controller._button_drop()
			controller._refresh_view()
		"menu_new_run":
			controller._button_new_run()
			controller._refresh_view()
		"flip_view":
			controller._toggle_view()
			controller._advance_camera_transition(controller.CAMERA_SWAP_DURATION)
			controller._refresh_view()
		"resolve_clear":
			controller.run_state.advance_clear(controller.run_state.CLEAR_PAUSE_DURATION)
			controller._refresh_view()
		"capture":
			report["captures"].append(step.get("label", "capture"))
		"assert":
			_assert_step(controller, step, report)
		_:
			_fail(report, "unknown step type %s" % step_type)


func finalize_report(report: Dictionary) -> Dictionary:
	report["status"] = "passed" if report["failures"].is_empty() else "failed"
	return report


func _assert_step(controller: Node, step: Dictionary, report: Dictionary) -> void:
	if step.has("hold_piece_nonempty"):
		var expected_hold: bool = step["hold_piece_nonempty"]
		var actual_hold: bool = controller.run_state.hold_piece != ""
		if actual_hold != expected_hold:
			_fail(report, "expected hold_piece_nonempty=%s, got %s" % [str(expected_hold), str(actual_hold)])
	if step.has("current_piece_nonempty"):
		var expected_piece: bool = step["current_piece_nonempty"]
		var actual_piece: bool = not controller.run_state.current_piece.is_empty()
		if actual_piece != expected_piece:
			_fail(report, "expected current_piece_nonempty=%s, got %s" % [str(expected_piece), str(actual_piece)])
	if step.has("view_flipped") and controller.view_flipped != step["view_flipped"]:
		_fail(report, "expected view_flipped=%s, got %s" % [str(step["view_flipped"]), str(controller.view_flipped)])
	if step.has("pause_board_open") and controller.pause_board_open != step["pause_board_open"]:
		_fail(report, "expected pause_board_open=%s, got %s" % [str(step["pause_board_open"]), str(controller.pause_board_open)])
	if step.has("is_clearing") and controller.run_state.is_clearing() != step["is_clearing"]:
		_fail(report, "expected is_clearing=%s, got %s" % [str(step["is_clearing"]), str(controller.run_state.is_clearing())])
	if step.has("game_over") and controller.run_state.game_over != step["game_over"]:
		_fail(report, "expected game_over=%s, got %s" % [str(step["game_over"]), str(controller.run_state.game_over)])
	if step.has("score_equals") and controller.run_state.score != step["score_equals"]:
		_fail(report, "expected score=%s, got %s" % [str(step["score_equals"]), str(controller.run_state.score)])


func _fail(report: Dictionary, message: String) -> void:
	report["failures"].append(message)
