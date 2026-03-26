extends SceneTree

const TestHarnessScript = preload("res://tests/test_harness.gd")
const ControllerInputSuiteScript = preload("res://tests/controller_input_suite.gd")
const GhostDropSuiteScript = preload("res://tests/ghost_drop_suite.gd")


func _initialize() -> void:
	var harness: RefCounted = TestHarnessScript.new()
	ControllerInputSuiteScript.run(harness)
	GhostDropSuiteScript.run(harness)
	harness.finish(self)
