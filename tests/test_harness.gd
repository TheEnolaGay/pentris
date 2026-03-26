class_name TestHarness
extends RefCounted

var failures: Array[String] = []
var passes := 0
var current_suite := ""
var current_case := ""


func suite(name: String) -> void:
	current_suite = name


func case(name: String) -> void:
	current_case = name


func assert_true(condition: bool, message: String) -> void:
	if condition:
		passes += 1
		return
	failures.append(_context_prefix() + message)


func assert_equal(actual, expected, message: String) -> void:
	if actual == expected:
		passes += 1
		return
	failures.append("%s%s\nexpected: %s\nactual: %s" % [_context_prefix(), message, var_to_str(expected), var_to_str(actual)])


func finish(tree: SceneTree) -> void:
	if failures.is_empty():
		print("All Pentris tests passed. %d assertions." % passes)
		tree.quit(0)
		return

	for failure in failures:
		push_error(failure)
	tree.quit(1)


func _context_prefix() -> String:
	return "[%s / %s] " % [current_suite, current_case]
