extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const VIEWPORT_PRESETS := {
	"phone_landscape": Vector2i(844, 390),
	"desktop_720p": Vector2i(1280, 720)
}

var scenario_name := ""
var output_path := ""
var viewport_preset := "phone_landscape"


func _initialize() -> void:
	call_deferred("_run")


static func viewport_preset_size(name: String) -> Vector2i:
	return VIEWPORT_PRESETS.get(name, Vector2i.ZERO)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		push_error("usage: godot4 --path . --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy -s res://tools/visual_capture_runner.gd -- <scenario> <output_path> [viewport_preset]")
		quit(2)
		return

	scenario_name = args[0]
	output_path = args[1]
	if args.size() == 3:
		viewport_preset = args[2]
	var viewport_size := viewport_preset_size(viewport_preset)
	if viewport_size == Vector2i.ZERO:
		push_error("unknown viewport preset: %s" % viewport_preset)
		quit(7)
		return
	_apply_viewport_size(viewport_size)

	var scene = MAIN_SCENE.instantiate()
	root.add_child(scene)
	call_deferred("_capture_scene", scene)


func _capture_scene(scene: Node) -> void:
	await _await_render_frames(4)
	if not scene.has_method("prepare_visual_scenario"):
		push_error("main scene does not expose prepare_visual_scenario")
		quit(3)
		return
	if not scene.prepare_visual_scenario(scenario_name):
		push_error("unknown visual scenario: %s" % scenario_name)
		quit(4)
		return
	await _await_render_frames(6)

	var absolute_output := ProjectSettings.globalize_path(output_path)
	var output_dir := absolute_output.get_base_dir()
	var mkdir_err := DirAccess.make_dir_recursive_absolute(output_dir)
	if mkdir_err != OK:
		push_error("failed to create output directory: %s" % output_dir)
		quit(5)
		return

	var image: Image = root.get_texture().get_image()
	var save_err := image.save_png(absolute_output)
	if save_err != OK:
		push_error("failed to save capture: %s" % absolute_output)
		quit(6)
		return

	print(absolute_output)
	quit(0)


func _apply_viewport_size(viewport_size: Vector2i) -> void:
	root.content_scale_size = viewport_size
	root.size = viewport_size
	DisplayServer.window_set_size(viewport_size)


func _await_render_frames(count: int) -> void:
	for _i in range(count):
		await process_frame
