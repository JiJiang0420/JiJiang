extends SceneTree
## Integration checks against the actual scene, actors, spells and save store.
## Must be launched with a disposable XDG_DATA_HOME containing "wf2-smoke".

var game
var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	if OS.get_environment("WITCHES_FEAST_TEST") != "1" or not data_root.contains("wf2-smoke"):
		printerr("REFUSED: use WITCHES_FEAST_TEST=1 and a disposable XDG_DATA_HOME containing wf2-smoke.")
		quit(2)
		return
	var save_root: String = ProjectSettings.globalize_path("user://")
	if not save_root.begins_with(data_root) or FileAccess.file_exists("user://progress.json"):
		printerr("REFUSED: user:// must be inside a fresh isolated data directory: ", save_root)
		quit(2)
		return
	print("SMOKE_START isolated_user_dir=", save_root)
	var scene = load("res://main.tscn")
	if scene == null or not scene.can_instantiate():
		printerr("FAIL: main scene cannot instantiate")
		quit(1)
		return
	game = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	game.auto_play = false
	# This suite does not exercise audio. Stop playback before the fast sequence
	# of simulated actions so the headless mixer has no queued playback at exit.
	if is_instance_valid(game.ambience):
		game.ambience.stop()
		game.ambience.stream = null
	for sound in game.sound_players:
		sound.stop()
		sound.stream = null
	game.sound_players.clear()
	_check(game.state == "base", "main scene boots into base")
	_test_red()
	_test_blue()
	_test_gold()
	_test_invalid_and_switch()
	_test_extended_boundary()
	_test_reflection()
	_test_pause()
	_test_collision_order()
	_test_shop_and_run_end()
	_test_permanent_progress()
	_test_store_recovery()
	game._clear_combat_objects()
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("SMOKE_RESULT passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)


func _fresh(mode: String = "training") -> void:
	game._reset_combat()
	game.state = mode
	game.duration = 480.0
	game.spawn_clock = 999.0
	game.progress = game.store.default_data()
	game.hud.hide_panels()


func _enemy(kind: String, at: Vector3):
	var enemy = game.spawn_enemy(kind, at)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	return enemy


func _points(a: Vector3, b: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = [a, b]
	return result


func _test_red() -> void:
	_fresh()
	var enemy = _enemy("chaser", Vector3(0, 0, -3))
	var stroke: Array[Vector3] = [Vector3(-1, 0, -3), Vector3(1, 0, -3), Vector3(-1, 0, -3)]
	_check(game.cast_spell(0, stroke), "red accepts a valid stroke")
	_check(is_equal_approx(enemy.hp, 12.0), "red repeated path hits a target only once")
	_check(enemy.crack_time > 0.0 and game.cooldowns[0] > 0.0, "red applies crack and starts cooldown")
	game.cooldowns[0] = 0.0
	game.cast_spell(0, stroke)
	_check(not game._live(enemy) and game.enemies.is_empty(), "red independently kills a normal enemy in two casts")


func _test_blue() -> void:
	_fresh()
	var enemy = _enemy("chaser", Vector3(0, 0, -3))
	var stroke: Array[Vector3] = _points(Vector3(2, 0, -3), enemy.position)
	_check(game.cast_spell(1, stroke, null, enemy), "blue supports one enemy and a ground anchor")
	_check(is_equal_approx(enemy.hp, 16.0) and not game.link.is_empty(), "blue creates link and applies one pulse")
	game._update_link(0.1)
	_check(enemy.pull_velocity.x > 0.0 and is_equal_approx(enemy.hp, 16.0), "blue establishes sustained anchor pull without per-frame pulse damage")
	var start_position: Vector3 = enemy.position
	enemy._phase = "recover"
	enemy._phase_time = 100.0
	for tick in range(12):
		game._update_link(1.0 / 30.0)
		enemy._physics_process(1.0 / 30.0)
	_check(enemy.position.x - start_position.x > 0.5, "continuous blue pull moves a resting enemy at least half a metre in 0.4 seconds")
	game.cooldowns[1] = 0.0
	game.cast_spell(1, stroke, null, enemy)
	_check(not game._live(enemy) and game.link.is_empty(), "blue independently kills a normal enemy and removes dead endpoint link")


func _test_gold() -> void:
	_fresh()
	var enemy = _enemy("chaser", Vector3(0, 0, -3))
	var stroke: Array[Vector3] = _points(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	_check(game.cast_spell(2, stroke), "gold accepts an active placement on an enemy")
	game._update_boundary(0.016)
	_check(is_equal_approx(enemy.hp, 16.0) and game.boundary.is_empty(), "gold first contact damages once and consumes base boundary")
	game.cooldowns[2] = 0.0
	game.cast_spell(2, stroke)
	game._update_boundary(0.016)
	_check(not game._live(enemy), "gold independently kills a normal enemy in two casts")


func _test_invalid_and_switch() -> void:
	_fresh()
	var enemy = _enemy("armored", Vector3(0, 0, -3))
	game.switch_cloak(1)
	game.switch_clock = 0.0
	var stroke: Array[Vector3] = _points(Vector3(2, 0, -3), enemy.position)
	game.cast_spell(1, stroke, null, enemy)
	var node_id: int = game.link.node.get_instance_id()
	var blue_cooldown: float = game.cooldowns[1]
	_check(game.switch_cloak(2), "switch succeeds while prior spell persists")
	_check(game.link.node.get_instance_id() == node_id and is_equal_approx(game.cooldowns[1], blue_cooldown), "switch preserves existing link and independent cooldown")
	game.cooldowns[1] = 0.0
	_check(not game.cast_spell(1, stroke, null, null), "blue rejects two ground endpoints")
	_check(game.link.node.get_instance_id() == node_id and game.cooldowns[1] == 0.0, "invalid blue cast preserves old structure without cooldown")
	var distant: Array[Vector3] = _points(Vector3(20, 0, 0), Vector3(21, 0, 0))
	_check(not game.cast_spell(0, distant) and game.cooldowns[0] == 0.0, "out-of-range stroke has no cooldown")
	var boundary_stroke: Array[Vector3] = _points(Vector3(-1, 0, 3), Vector3(1, 0, 3))
	game.cast_spell(2, boundary_stroke)
	var boundary_id: int = game.boundary.node.get_instance_id()
	game.cooldowns[2] = 0.0
	var tiny: Array[Vector3] = _points(Vector3.ZERO, Vector3(0.1, 0, 0))
	_check(not game.cast_spell(2, tiny), "gold rejects a too-short boundary")
	_check(game.boundary.node.get_instance_id() == boundary_id and game.cooldowns[2] == 0.0, "invalid gold cast preserves old boundary without cooldown")


func _test_extended_boundary() -> void:
	_fresh()
	game.progress.unlocked = ["gold_linger"]
	game.progress.equipped = ["", "", "gold_linger"]
	var enemy = _enemy("chaser", Vector3(0, 0, -3))
	var stroke: Array[Vector3] = _points(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	game.cast_spell(2, stroke)
	game._update_boundary(0.016)
	_check(is_equal_approx(enemy.hp, 22.0) and not game.boundary.is_empty(), "extended boundary uses reduced damage and remains after first batch")
	game._update_boundary(0.016)
	_check(is_equal_approx(enemy.hp, 22.0) and game.boundary.batches == 1, "extended boundary cannot repeatedly damage the same target")
	var newcomer = _enemy("chaser", Vector3(0.7, 0, -3))
	game._update_boundary(0.016)
	_check(is_equal_approx(newcomer.hp, 22.0) and game.boundary.is_empty(), "second new contact consumes extended boundary")


func _test_reflection() -> void:
	_fresh()
	var stroke: Array[Vector3] = _points(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	game.create_projectile(Vector3(0, 0, -3), Vector3(0, 0, 1), 14.0)
	game.cast_spell(2, stroke)
	game._update_boundary(0.016)
	_check(game.projectiles[0].reflected and game.boundary.is_empty(), "boundary redirects hostile projectile and consumes its batch")
	var direction: Vector3 = game.projectiles[0].direction
	game.cooldowns[2] = 0.0
	stroke.reverse()
	game.cast_spell(2, stroke)
	game._update_boundary(0.016)
	_check(game.projectiles[0].direction.is_equal_approx(direction) and not game.boundary.is_empty(), "already redirected projectile cannot trigger another boundary")


func _test_pause() -> void:
	_fresh("battle")
	game.cooldowns[0] = 1.0
	game.elapsed = 3.0
	game.paused = true
	game._physics_process(0.5)
	_check(game.elapsed == 3.0 and game.cooldowns[0] == 1.0, "pause freezes combat timer and spell cooldown")
	game.paused = false
	game._physics_process(0.1)
	_check(is_equal_approx(game.elapsed, 3.1) and is_equal_approx(game.cooldowns[0], 0.9), "resume advances simulation normally")


func _test_collision_order() -> void:
	_fresh()
	var stationary = _enemy("chaser", Vector3(0, 0, -3))
	var moving = _enemy("charger", Vector3(0.7, 0, -3))
	moving.charging = true
	moving.velocity = Vector3(-8, 0, 0)
	game._update_collisions(0.016)
	_check(stationary.hp < 36.0 and moving.hp < 60.0, "forced collision is detected when moving enemy has later spawn index")
	var previous: float = stationary.hp
	game._update_collisions(0.016)
	_check(is_equal_approx(stationary.hp, previous), "same collision pair cannot apply damage again immediately")


func _test_shop_and_run_end() -> void:
	_fresh("battle")
	game.elapsed = 120.0
	game._physics_process(0.001)
	_check(game.state == "shop" and game.coins == 60 and game.progress.essence == 10, "stage completion grants 60 run currency and 10 saved essence")
	_check(game.offers.size() == 3, "shop contains three purchasable upgrades")
	var chosen: String = game.offers[0].id
	_check(game.buy_upgrade(chosen), "real shop purchase succeeds")
	_check(game.coins == 0 and game.upgrades.has(chosen), "shop purchase deducts price and equips upgrade")
	_check(not game.buy_upgrade(chosen) and game.coins == 0, "duplicate purchase cannot charge or stack")
	game.cooldowns[1] = 0.75
	game.continue_from_shop()
	game._clear_combat_objects()
	game.spawn_clock = 999.0
	_check(game.state == "battle" and game.stage == 1, "continue shop enters the next battle phase")
	_check(is_equal_approx(game.cooldowns[1], 0.75), "leaving the shop preserves the remaining spell cooldown")
	game.elapsed = 240.0
	game._physics_process(0.001)
	_check(game.progress.essence == 20 and game.coins == 60, "next completed phase grants its reward once")
	game.continue_from_shop()
	game._clear_combat_objects()
	game.spawn_clock = 999.0
	game.elapsed = 360.0
	game._physics_process(0.001)
	_check(game.progress.essence == 30, "third phase completes permanent stage rewards")
	game.continue_from_shop()
	var boss_count: int = 0
	for enemy in game.enemies:
		if enemy.kind == "boss":
			boss_count += 1
	_check(game.stage == 3 and boss_count == 1, "last shop starts a battle with exactly one boss")
	game._finish_run(true, "test victory")
	_check(game.state == "result" and game.progress.essence == 60 and game.progress.wins == 1, "victory grants exactly 60 total essence and one win")
	_check(game.coins == 0 and game.upgrades.is_empty(), "result clears run-only currency and upgrades")
	game._finish_run(true, "duplicate end callback")
	_check(game.progress.essence == 60 and game.progress.total_runs == 1, "repeated terminal callback cannot duplicate rewards or statistics")


func _test_permanent_progress() -> void:
	game.return_to_base()
	_check(game.purchase_relic("red_echo"), "earned essence buys a permanent relic")
	_check(game.progress.essence == 30 and game.progress.unlocked.has("red_echo"), "relic purchase deducts permanent cost once")
	_check(not game.purchase_relic("red_echo") and game.progress.essence == 30, "duplicate permanent purchase is rejected")
	game.toggle_relic("red_echo")
	var store_script = load("res://scripts/progress_store.gd")
	var reloaded = store_script.new().load_data()
	_check(reloaded.essence == 30 and reloaded.equipped[0] == "red_echo" and reloaded.wins == 1, "new store instance restores currency, equipment and run statistics")


func _test_store_recovery() -> void:
	var store_script = load("res://scripts/progress_store.gd")
	var storage = store_script.new()
	var data: Dictionary = storage.load_data()
	data.essence = 31
	_check(storage.save_data(data), "atomic store accepts valid progress")
	data.essence = 32
	_check(storage.save_data(data), "second commit establishes previous valid backup")
	var file = FileAccess.open("user://progress.json", FileAccess.WRITE)
	file.store_string("{not valid json")
	file.close()
	var recovered: Dictionary = store_script.new().load_data()
	_check(recovered.essence == 31, "corrupt primary restores prior valid backup")
	var dir = DirAccess.open("user://")
	var archive_found: bool = false
	for name in dir.get_files():
		if name.begins_with("progress.json.corrupt-"):
			archive_found = true
	_check(archive_found, "corrupt save is preserved separately")
	var bad: Dictionary = recovered.duplicate(true)
	bad.essence = -1
	_check(not storage.save_data(bad), "invalid permanent balance is rejected")
