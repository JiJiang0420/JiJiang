extends SceneTree
## Graphical integration check. Inputs go through the real Window/Viewport.
## Controlled enemy fixtures isolate input routing from combat difficulty.

var game
var passed: int = 0
var failed: int = 0
var last_mouse: Vector2 = Vector2.ZERO
var output_dir: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	output_dir = OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("WITCHES_FEAST_TEST") != "1" or not output_dir.contains("wf2-smoke"):
		printerr("REFUSED: provide WITCHES_FEAST_TEST=1 and disposable wf2-smoke XDG_DATA_HOME")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("REFUSED: graphical input test requires an actual display (for example DISPLAY=:99)")
		quit(2)
		return
	if not ProjectSettings.globalize_path("user://").begins_with(output_dir) or FileAccess.file_exists("user://progress.json"):
		printerr("REFUSED: user data must be fresh and isolated")
		quit(2)
		return
	root.size = Vector2i(1280, 800)
	root.position = Vector2i(30, 30)
	root.title = "Witches Feast · Automated graphical input checks"
	print("INPUT_SMOKE_START display=", DisplayServer.get_name(), " data=", output_dir)
	var scene = load("res://main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	root.grab_focus()
	await _wait(0.7)
	_stop_audio()
	_check(game.state == "base" and root.is_visible(), "actual game window opens in base")
	await _click_button("操作指南")
	_check(game.help_visible and game.hud.help_layer.visible, "base help button opens the actual guide overlay")
	await _click_button("明白了")
	_check(not game.help_visible and not game.hud.help_layer.visible, "guide close button restores base")
	await _click_training()
	_check(game.state == "training" and not game.paused, "training button enters playable scene")
	_fixture_enemy()
	await _wait(0.4)
	await _test_movement()
	await _test_cloaks()
	await _test_drawn_spells()
	await _test_branch_inputs()
	await _test_previews()
	await _test_pause()
	await _test_camera()
	await _capture()
	await _tap_key(KEY_ESCAPE)
	await _click_button("结束本局并返回基地")
	_check(game.state == "base", "pause exit button returns to base")
	_stop_audio()
	game._clear_combat_objects()
	game.queue_free()
	await _wait(0.2)
	print("INPUT_SMOKE_RESULT passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _stop_audio() -> void:
	if is_instance_valid(game.ambience):
		game.ambience.stop()
		game.ambience.stream = null
	for sound in game.sound_players:
		sound.stop()
		sound.stream = null
	game.sound_players.clear()


func _visible_button(text: String, node: Node = null) -> Button:
	if node == null:
		node = root
	if node is Button and node.is_visible_in_tree() and not node.disabled and node.text == text:
		return node
	for child in node.get_children():
		var found: Button = _visible_button(text, child)
		if found != null:
			return found
	return null


func _click_button(text: String) -> void:
	var button: Button = _visible_button(text)
	if button == null:
		_check(false, "visible button exists: " + text)
		return
	var point: Vector2 = button.get_global_rect().get_center()
	await _move_mouse(point)
	_mouse_button(MOUSE_BUTTON_LEFT, true, point)
	await _wait(0.04)
	_mouse_button(MOUSE_BUTTON_LEFT, false, point)
	await _wait(0.12)


func _click_training() -> void:
	var buttons: Array[Node] = root.find_children("*", "Button", true, false)
	for candidate in buttons:
		var button: Button = candidate as Button
		if button.is_visible_in_tree() and (button.text.contains("训练") or button.text.contains("试炼")):
			await _click_button(button.text)
			return
	_check(false, "visible training button exists")


func _mouse_button(index: int, pressed: bool, point: Vector2) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = point
	event.global_position = point
	event.button_mask = (1 << (index - 1)) if pressed else 0
	root.push_input(event, true)


func _move_mouse(point: Vector2, held: int = 0) -> void:
	Input.warp_mouse(point)
	_send_mouse_motion(point, held)
	await process_frame
	await process_frame


func _send_mouse_motion(point: Vector2, held: int = 0) -> void:
	var event = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - last_mouse
	event.button_mask = held
	last_mouse = point
	root.push_input(event, true)


func _key(code: int, pressed: bool) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap_key(code: int) -> void:
	_key(code, true)
	await _wait(0.035)
	_key(code, false)
	await _wait(0.1)


func _fixture_enemy():
	game._clear_combat_objects()
	game.player.position = Vector3.ZERO
	game.yaw = 0.0
	var enemy = game.spawn_enemy("chaser", Vector3(0, 0, -3))
	enemy.set_process(false)
	enemy.set_physics_process(false)
	return enemy


func _test_movement() -> void:
	# Keep the test target away from collision while checking all four keys.
	game.enemies[0].position = Vector3(0, 0, -10)
	for code in [KEY_W, KEY_S, KEY_A, KEY_D]:
		var before: Vector3 = game.player.position
		_key(code, true)
		await _wait(0.2)
		_key(code, false)
		await _wait(0.04)
		_check(game.player.position.distance_to(before) > 0.5, "physical key moves player: " + OS.get_keycode_string(code))


func _test_cloaks() -> void:
	for index in [1, 2, 0]:
		await _tap_key(KEY_1 + index)
		await _wait(0.15)
		_check(game.cloak == index, "number key changes active cloak: " + str(index + 1))


func _drag_world(a: Vector3, b: Vector3) -> void:
	await _wait(0.35)
	var start: Vector2 = game.camera.unproject_position(a + Vector3.UP * 0.08)
	var finish: Vector2 = game.camera.unproject_position(b + Vector3.UP * 0.08)
	await _move_mouse(start)
	_mouse_button(MOUSE_BUTTON_LEFT, true, start)
	_check(game.drawing, "left press begins a real drawing gesture")
	# Deliver one short gesture as an input batch. Waiting for every sample to
	# render exceeds the game's gesture time limit on software-rendered Xorg.
	# This also verifies same-frame press/motion/release use event coordinates.
	for step in range(1, 7):
		_send_mouse_motion(start.lerp(finish, float(step) / 6.0), MOUSE_BUTTON_MASK_LEFT)
	_check(game.drawing and game.pointer.distance_to(b + Vector3.UP * 0.08) < 0.1,
		"short mouse gesture samples its final world endpoint before rendering")
	_mouse_button(MOUSE_BUTTON_LEFT, false, finish)
	Input.warp_mouse(finish)
	print("INPUT_GESTURE cloak=", game.cloak, " hp=", game.enemies[0].hp, " cooldowns=", game.cooldowns)


func _test_drawn_spells() -> void:
	var target = _fixture_enemy()
	await _tap_key(KEY_1)
	game.cooldowns[0] = 0.0
	await _drag_world(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	_check(is_equal_approx(target.hp, 12.0) and game.cooldowns[0] > 0.0, "projected mouse drag casts red through the real input path")
	target = _fixture_enemy()
	await _tap_key(KEY_2)
	game.cooldowns[1] = 0.0
	await _drag_world(Vector3(-2, 0, -3), Vector3(0, 0, -3))
	_check(is_equal_approx(target.hp, 16.0) and not game.link.is_empty(), "projected mouse drag casts an enemy-to-ground blue link")
	target = _fixture_enemy()
	await _tap_key(KEY_3)
	game.cooldowns[2] = 0.0
	await _drag_world(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	# Gold placement is immediate; its collision contact resolves in physics.
	await physics_frame
	await physics_frame
	_check(is_equal_approx(target.hp, 16.0) and game.cooldowns[2] > 0.0, "projected mouse drag places a damaging gold boundary")


func _test_pause() -> void:
	await _tap_key(KEY_ESCAPE)
	_check(game.paused and game.hud.pause_layer.visible, "Escape opens pause through input")
	var before_time: float = game.elapsed
	var before_cooldown: float = game.cooldowns[2]
	var before_position: Vector3 = game.player.position
	_key(KEY_D, true)
	await _wait(0.25)
	_key(KEY_D, false)
	_check(is_equal_approx(game.elapsed, before_time) and is_equal_approx(game.cooldowns[2], before_cooldown), "actual pause freezes simulation and cooldown")
	_check(game.player.position.is_equal_approx(before_position), "physical movement keys do not move player while paused")
	await _click_button("继续盛宴")
	_check(not game.paused and not game.hud.pause_layer.visible, "resume button restores the running scene")
	_check(game.elapsed > before_time, "simulation advances after button-based resume")


func _test_camera() -> void:
	var before_yaw: float = game.yaw
	var center = Vector2(640, 340)
	await _move_mouse(center)
	_mouse_button(MOUSE_BUTTON_MIDDLE, true, center)
	await _move_mouse(center + Vector2(60, 0), MOUSE_BUTTON_MASK_MIDDLE)
	_mouse_button(MOUSE_BUTTON_MIDDLE, false, center + Vector2(60, 0))
	await _wait(0.1)
	_check(absf(game.yaw - before_yaw) > 0.1, "middle mouse drag rotates the actual camera controller")
	await _tap_key(KEY_HOME)
	_check(is_zero_approx(game.yaw), "Home returns camera yaw to default")


func _capture() -> void:
	await _wait(0.3)
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	var path: String = output_dir.path_join("input-smoke.png")
	var ok: bool = frame != null and not frame.is_empty()
	if ok:
		ok = frame.get_width() >= 1000 and frame.save_png(path) == OK
	_check(ok, "graphical viewport produces a full-size rendered frame")
	if ok:
		print("INPUT_SMOKE_CAPTURE ", path)


func _test_branch_inputs() -> void:
	var target = _fixture_enemy()
	await _tap_key(KEY_1)
	await _tap_key(KEY_Q)
	_check(game.upgrades.has("short_cut"), "Q activates short cut through the real input path")
	game.cooldowns[0] = 0.0
	await _drag_world(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	_check(is_equal_approx(target.hp, 18.0), "short-cut input uses its branch damage")
	await _tap_key(KEY_Q)
	_check(not game.upgrades.has("short_cut"), "Q returns the current cloak to its original mode")

	target = _fixture_enemy()
	await _tap_key(KEY_2)
	await _tap_key(KEY_Q)
	game.cooldowns[1] = 0.0
	await _drag_world(Vector3(-2, 0, -3), Vector3(0, 0, -3))
	_check(is_equal_approx(target.hp, 22.0), "snap branch input establishes the weaker first pulse")
	await _wait(0.3)
	_mouse_button(MOUSE_BUTTON_RIGHT, true, last_mouse)
	_mouse_button(MOUSE_BUTTON_RIGHT, false, last_mouse)
	_check(not game._live(target) and game.link.is_empty(), "right-click finishes a prepared snap and defeats a lone enemy")
	await _tap_key(KEY_Q)

	target = _fixture_enemy()
	await _tap_key(KEY_3)
	await _tap_key(KEY_Q)
	game.cooldowns[2] = 0.0
	await _drag_world(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	await physics_frame
	_check(is_equal_approx(target.hp, 36.0) and not game.boundary.is_empty(), "moving-wall input places an inactive boundary")
	await RenderingServer.frame_post_draw
	_check(game.cooldowns[2] > 0.0 and game.hud.aim_detail_text.text.begins_with("右键推出就绪"), "pending wall HUD separates ready right-click from left-click cooldown")
	await _wait(1.1)
	_check(game.combat_view._travel_label.visible, "placed wall keeps its travel guide after the initial cast effect expires")
	await _tap_key(KEY_1)
	_check(game.combat_view._travel_label.visible, "pending wall guide survives switching away from gold")
	await _tap_key(KEY_3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join("pending-wall.png"))
	_mouse_button(MOUSE_BUTTON_RIGHT, true, last_mouse)
	_mouse_button(MOUSE_BUTTON_RIGHT, false, last_mouse)
	await physics_frame
	await physics_frame
	_check(is_equal_approx(target.hp, 12.0) and game.boundary.is_empty(), "right-click launches the wall and resolves one contact batch")
	await RenderingServer.frame_post_draw
	_check(not game.combat_view._travel_label.visible, "consumed wall removes its pending travel guide")
	await _tap_key(KEY_Q)


func _test_previews() -> void:
	for index in [0, 1, 2]:
		_fixture_enemy()
		var other = game.spawn_enemy("chaser", Vector3(2, 0, -3))
		other.set_physics_process(false)
		await _tap_key(KEY_1 + index)
		if index == 2:
			await _tap_key(KEY_Q)
		game.cooldowns[index] = 0.0
		await _wait(0.35)
		var a = Vector3(0, 0, -3) if index == 1 else Vector3(-1, 0, -3)
		var b = Vector3(2, 0, -3)
		var screen_a: Vector2 = game.camera.unproject_position(a + Vector3.UP * 0.08)
		var screen_b: Vector2 = game.camera.unproject_position(b + Vector3.UP * 0.08)
		await _move_mouse(screen_a)
		_mouse_button(MOUSE_BUTTON_LEFT, true, screen_a)
		_send_mouse_motion(screen_b, MOUSE_BUTTON_MASK_LEFT)
		Input.warp_mouse(screen_b)
		await process_frame
		await process_frame
		_check(game.drawing and game.aim.valid, "live preview shows a valid drawn action for cloak " + str(index + 1))
		await RenderingServer.frame_post_draw
		var frame = root.get_texture().get_image()
		frame.save_png(output_dir.path_join("preview-%d.png" % index))
		_mouse_button(MOUSE_BUTTON_RIGHT, true, screen_b)
		_mouse_button(MOUSE_BUTTON_RIGHT, false, screen_b)
		_mouse_button(MOUSE_BUTTON_LEFT, false, screen_b)
		_check(not game.drawing and game.cooldowns[index] == 0.0, "right-click cancels the drawn preview without firing")
		if index == 2:
			await _tap_key(KEY_Q)
