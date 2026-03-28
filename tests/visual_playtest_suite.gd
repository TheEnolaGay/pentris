extends RefCounted

const ControllerScript = preload("res://scripts/game_controller.gd")
const VisualPlaytestExecutorScript = preload("res://scripts/ui/visual_playtest_executor.gd")


static func run(harness: RefCounted) -> void:
	harness.suite("VisualPlaytest")
	_test_script_definitions(harness)
	_test_action_coverage(harness)
	_test_full_action_sweep_smoke(harness)


static func _test_script_definitions(harness: RefCounted) -> void:
	harness.case("script definitions")
	var executor: RefCounted = VisualPlaytestExecutorScript.new()
	for script_name in executor.script_names():
		var script: Dictionary = executor.script_definition(script_name)
		harness.assert_true(not script.is_empty(), "%s should resolve to a script definition" % script_name)
		harness.assert_true(
			executor.validate_script_definition(script).is_empty(),
			"%s should validate without structural errors" % script_name
		)


static func _test_action_coverage(harness: RefCounted) -> void:
	harness.case("action coverage")
	var executor: RefCounted = VisualPlaytestExecutorScript.new()
	var categories: Array[String] = executor.action_categories("full_action_sweep")
	for required in ["movement", "rotation", "hold", "hard_drop", "hud_drop", "restart", "view_flip", "scenario"]:
		harness.assert_true(categories.has(required), "full_action_sweep should cover %s" % required)


static func _test_full_action_sweep_smoke(harness: RefCounted) -> void:
	harness.case("full action sweep smoke")
	var executor: RefCounted = VisualPlaytestExecutorScript.new()
	var controller = ControllerScript.new()
	controller._ready()
	controller._finish_startup()
	var report: Dictionary = executor.new_report("full_action_sweep", "phone_landscape", executor.default_fps(), 7)
	var script: Dictionary = executor.script_definition("full_action_sweep")
	for step in script.get("steps", []):
		executor.execute_step(controller, step, report)
	executor.finalize_report(report)
	harness.assert_equal(report["status"], "passed", "full action sweep should execute without playtest failures")
	harness.assert_true(report["captures"].size() >= 10, "full action sweep should emit multiple checkpoint captures")
	harness.assert_true(controller.run_state.game_over, "full action sweep should end in the scripted game-over state")
	controller.free()
