extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const CaptureRunnerScript = preload("res://tools/visual_capture_runner.gd")
const PlaytestExecutorScript = preload("res://scripts/ui/visual_playtest_executor.gd")

var script_name := ""
var output_dir := ""
var viewport_preset := "phone_landscape"
var seed_override := -1
var fps := 24
var capture_stride_frames := 3


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 5:
		push_error("usage: godot4 --path . --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy -s res://tools/visual_playtest_runner.gd -- <script_name> <output_dir> [viewport_preset] [seed] [fps]")
		quit(2)
		return
	script_name = args[0]
	output_dir = args[1]
	if args.size() >= 3:
		viewport_preset = args[2]
	if args.size() >= 4:
		seed_override = int(args[3])
	if args.size() >= 5:
		fps = max(1, int(args[4]))
	capture_stride_frames = max(1, int(round(60.0 / float(fps))))

	var viewport_size := CaptureRunnerScript.viewport_preset_size(viewport_preset)
	if viewport_size == Vector2i.ZERO:
		push_error("unknown viewport preset: %s" % viewport_preset)
		quit(7)
		return

	var executor: RefCounted = PlaytestExecutorScript.new()
	var script: Dictionary = executor.script_definition(script_name)
	if script.is_empty():
		push_error("unknown playtest script: %s" % script_name)
		quit(8)
		return
	var issues: Array[String] = executor.validate_script_definition(script)
	if not issues.is_empty():
		push_error("invalid playtest script: %s" % ", ".join(PackedStringArray(issues)))
		quit(9)
		return

	_apply_viewport_size(viewport_size)

	var scene = MAIN_SCENE.instantiate()
	root.add_child(scene)
	call_deferred("_run_playtest", scene, executor, script)


func _run_playtest(scene: Node, executor: RefCounted, script: Dictionary) -> void:
	await _await_render_frames(4)

	var run_seed: int = seed_override if seed_override >= 0 else int(script.get("seed", 1))
	var report: Dictionary = executor.new_report(script_name, viewport_preset, fps, run_seed)
	var steps: Array = script.get("steps", [])
	for index in range(steps.size()):
		var step: Dictionary = steps[index].duplicate(true)
		if step.get("type", "") == "start_run" and seed_override >= 0:
			step["seed"] = seed_override
		executor.execute_step(scene, step, report)
		if not report["failures"].is_empty():
			break
		if step.get("type", "") == "capture":
			await _await_render_frames(capture_stride_frames)
			var capture_path := _capture_path_for_step(index, step.get("label", "capture"))
			var capture_error := _save_frame(capture_path)
			if capture_error != OK:
				report["failures"].append("failed to save capture %s" % capture_path)
				break
			report["captures"][report["captures"].size() - 1] = capture_path
		else:
			await _await_render_frames(1)

	executor.finalize_report(report)
	var save_error := _save_report(report)
	if save_error != OK:
		push_error("failed to save playtest report under %s" % output_dir)
		quit(6)
		return
	if report["status"] != "passed":
		push_error("playtest failed: %s" % ", ".join(PackedStringArray(report["failures"])))
		quit(10)
		return
	print(ProjectSettings.globalize_path(output_dir))
	quit(0)


func _capture_path_for_step(index: int, label: String) -> String:
	return ProjectSettings.globalize_path(output_dir.path_join("%02d_%s.png" % [index, _safe_slug(label)]))


func _save_frame(absolute_path: String) -> int:
	var output_dir_path := absolute_path.get_base_dir()
	var mkdir_err := DirAccess.make_dir_recursive_absolute(output_dir_path)
	if mkdir_err != OK:
		return mkdir_err
	var image: Image = root.get_texture().get_image()
	return image.save_png(absolute_path)


func _save_report(report: Dictionary) -> int:
	var absolute_output_dir := ProjectSettings.globalize_path(output_dir)
	var mkdir_err := DirAccess.make_dir_recursive_absolute(absolute_output_dir)
	if mkdir_err != OK:
		return mkdir_err
	var json_path := absolute_output_dir.path_join("report.json")
	var text_path := absolute_output_dir.path_join("report.txt")
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	if json_file == null:
		return FileAccess.get_open_error()
	json_file.store_string(JSON.stringify(report, "\t"))
	json_file.close()
	var text_file := FileAccess.open(text_path, FileAccess.WRITE)
	if text_file == null:
		return FileAccess.get_open_error()
	text_file.store_string(_report_text(report))
	text_file.close()
	return OK


func _report_text(report: Dictionary) -> String:
	var lines := [
		"Visual Playtest Report",
		"script: %s" % report["script_name"],
		"viewport: %s" % report["viewport_preset"],
		"seed: %s" % report["seed"],
		"fps: %s" % report["fps"],
		"status: %s" % report["status"],
		"steps: %s" % ", ".join(PackedStringArray(report["steps_executed"])),
		"captures:"
	]
	for capture in report["captures"]:
		lines.append("- %s" % capture)
	if not report["failures"].is_empty():
		lines.append("failures:")
		for failure in report["failures"]:
			lines.append("- %s" % failure)
	return "\n".join(lines) + "\n"


func _apply_viewport_size(viewport_size: Vector2i) -> void:
	root.content_scale_size = viewport_size
	root.size = viewport_size
	DisplayServer.window_set_size(viewport_size)


func _await_render_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _safe_slug(value: String) -> String:
	var sanitized := value.to_lower().strip_edges()
	for character in [" ", "/", "\\", ":", ".", ","]:
		sanitized = sanitized.replace(character, "_")
	while sanitized.contains("__"):
		sanitized = sanitized.replace("__", "_")
	return sanitized
