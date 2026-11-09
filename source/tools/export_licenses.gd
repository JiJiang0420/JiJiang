extends SceneTree

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Usage: godot --headless --script export_licenses.gd -- OUTPUT.txt")
		quit(2)
		return
	var output = FileAccess.open(args[0], FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string("Godot Engine\n\n" + Engine.get_license_text())
	output.store_string("\n\nThird-party copyright notices\n\n")
	output.store_string(JSON.stringify(Engine.get_copyright_info(), "  "))
	for name in Engine.get_license_info():
		output.store_string("\n\n" + name + "\n" + Engine.get_license_info()[name])
	output.close()
	quit()
