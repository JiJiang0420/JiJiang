extends SceneTree
## v0.2 integration checks against the real prediction, spell and economy APIs.
## Enemy AI and automatic scene ticks are disabled; explicit ticks execute the
## production simulation. This is not a renderer or human-playtesting suite.

const BRANCHES = ["short_cut", "snap_link", "moving_wall"]
const RELICS = ["red_echo", "blue_flow", "gold_linger"]

var game
var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	var save_root: String = ProjectSettings.globalize_path("user://")
	if OS.get_environment("WITCHES_FEAST_TEST") != "1" or not data_root.contains("wf2-smoke"):
		printerr("REFUSED: set WITCHES_FEAST_TEST=1 and a disposable wf2-smoke XDG_DATA_HOME")
		quit(2)
		return
	if not save_root.begins_with(data_root) or FileAccess.file_exists("user://progress.json"):
		printerr("REFUSED: user:// must be inside a fresh isolated test directory")
		quit(2)
		return
	print("COMBAT_V02_START isolated_user_dir=", save_root)
	var scene = load("res://main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	game.auto_play = false
	game._stop_audio()
	game.sound_players.clear()
	var ready: bool = game.has_method("get_cast_check") and game.has_method("secondary_action") and game.has_method("toggle_training_branch")
	_check(ready, "v0.2 prediction, secondary action and training APIs exist")
	if ready:
		_test_prediction_matches_hits()
		_test_invalid_prediction_preserves_structure()
		_test_short_cut()
		_test_short_rebate()
		_test_snap_delay_and_pause()
		_test_snap_gather()
		_test_wall_arming_and_single_batch()
		_test_wall_pause_and_travel()
		_test_training_isolation()
		_test_shop_choices()
	game._stop_audio()
	game._clear_combat_objects()
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("COMBAT_V02_RESULT passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		printerr("FAIL ", label)


func _fresh(mode: String = "battle") -> void:
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


func _select(index: int) -> void:
	game.switch_clock = 0.0
	if game.cloak != index:
		game.switch_cloak(index)
	game.switch_clock = 0.0


func _health_snapshot(targets: Array) -> Dictionary:
	var result: Dictionary = {}
	for target in targets:
		result[target.get_instance_id()] = target.hp
	return result


func _damaged_ids(targets: Array, before: Dictionary) -> Array:
	var ids: Array = []
	for target in targets:
		if target.hp < float(before[target.get_instance_id()]):
			ids.append(target.get_instance_id())
	ids.sort()
	return ids


func _hit_ids(check: Dictionary) -> Array:
	var ids: Array = []
	for target in check.get("hits", []):
		ids.append(target.get_instance_id())
	ids.sort()
	return ids


func _test_prediction_matches_hits() -> void:
	_fresh()
	var center = _enemy("chaser", Vector3(0, 0, -3))
	var edge = _enemy("chaser", Vector3(0, 0, -2.25))
	var outside = _enemy("chaser", Vector3(0, 0, -1.6))
	var targets: Array = [center, edge, outside]
	var before: Dictionary = _health_snapshot(targets)
	var stroke: Array[Vector3] = [Vector3(-2, 0, -3), Vector3(2, 0, -3), Vector3(-2, 0, -3)]
	var check: Dictionary = game.get_cast_check(0, stroke)
	_check(check.get("valid", false) and check.hits.has(center) and check.hits.has(edge) and not check.hits.has(outside), "red preview includes its damage width and excludes a nearby miss")
	_check(_health_snapshot(targets) == before and game.cooldowns[0] == 0.0 and game.echo_events.is_empty(), "preview query does not damage, start cooldown or schedule attacks")
	_check(game.cast_spell(0, stroke), "predicted red stroke is accepted by actual casting")
	_check(_hit_ids(check) == _damaged_ids(targets, before), "red prediction exactly matches damaged enemies without duplicate backtrack hits")

	_fresh()
	var left = _enemy("charger", Vector3(-1, 0, -3))
	var right = _enemy("charger", Vector3(1, 0, -3))
	var bystander = _enemy("chaser", Vector3(0, 0, -3))
	targets = [left, right, bystander]
	before = _health_snapshot(targets)
	stroke = _points(left.position, right.position)
	check = game.get_cast_check(1, stroke, left, right)
	_check(check.get("valid", false) and check.hits.size() == 2 and not check.hits.has(bystander), "blue prediction identifies endpoints rather than enemies along the line")
	_check(game.cast_spell(1, stroke, left, right), "predicted blue link is accepted")
	_check(_hit_ids(check) == _damaged_ids(targets, before), "blue preview and establishment pulse damage the same endpoints")

	_fresh()
	center = _enemy("chaser", Vector3(0, 0, -3))
	outside = _enemy("chaser", Vector3(0, 0, -1.5))
	targets = [center, outside]
	before = _health_snapshot(targets)
	stroke = _points(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	check = game.get_cast_check(2, stroke)
	_check(check.get("valid", false) and check.hits.has(center) and not check.hits.has(outside), "base gold preview identifies the current contact batch")
	_check(game.cast_spell(2, stroke), "predicted gold boundary is accepted")
	game._physics_process(1.0 / 60.0)
	_check(_hit_ids(check) == _damaged_ids(targets, before), "gold prediction matches the next real physics contact batch")


func _test_invalid_prediction_preserves_structure() -> void:
	_fresh()
	var stroke: Array[Vector3] = _points(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	game.cast_spell(2, stroke)
	var old_id: int = game.boundary.node.get_instance_id()
	game.cooldowns[2] = 0.0
	var invalid: Array[Vector3] = _points(Vector3(9, 0, 0), Vector3(11, 0, 0))
	var check: Dictionary = game.get_cast_check(2, invalid)
	_check(not check.get("valid", true) and not str(check.get("reason", "")).is_empty(), "out-of-range preview explains its invalidity")
	_check(not game.cast_spell(2, invalid) and game.cooldowns[2] == 0.0 and game.boundary.node.get_instance_id() == old_id, "invalid cast agrees with preview and preserves the existing boundary and cooldown")
	check = game.get_cast_check(1, stroke)
	_check(not check.get("valid", true) and not str(check.get("reason", "")).is_empty() and not game.cast_spell(1, stroke), "blue ground-to-ground preview and cast both reject missing enemy endpoints")
	var distant = _enemy("charger", Vector3(10, 0, -3))
	check = game.get_cast_check(1, stroke, null, distant)
	_check(not check.get("valid", true) and not str(check.get("reason", "")).is_empty() and not game.cast_spell(1, stroke, null, distant), "blue range check uses actual enemy position even when drawn points are in range")


func _test_short_cut() -> void:
	_fresh()
	game.upgrades.append("short_cut")
	game.progress.unlocked = ["red_echo"]
	game.progress.equipped = ["red_echo", "", ""]
	var normal = _enemy("chaser", Vector3(0, 0, -3))
	var armored = _enemy("armored", Vector3(1.5, 0, -3))
	var before_armor: float = armored.armor
	var stroke: Array[Vector3] = _points(Vector3(-1, 0, -3), Vector3(2, 0, -3))
	var check: Dictionary = game.get_cast_check(0, stroke)
	_check(check.get("valid", false) and game.cast_spell(0, stroke), "short-cut branch casts a valid short stroke")
	_check(is_equal_approx(normal.hp, 18.0) and is_equal_approx(before_armor - armored.armor, 12.0), "short cut delivers its own health and armor damage to real targets")
	_check(is_equal_approx(game.cooldowns[0], 0.65) and game.echo_events.is_empty(), "short cut uses its branch cooldown and overrides equipped echo")
	var hp_after: float = normal.hp
	game._physics_process(0.4)
	_check(is_equal_approx(normal.hp, hp_after), "equipped echo cannot add a delayed strike to short cut")
	game.cooldowns[0] = 0.0
	stroke = _points(Vector3(-2.3, 0, -3), Vector3(2.3, 0, -3))
	check = game.get_cast_check(0, stroke)
	_check(not check.get("valid", true) and not str(check.get("reason", "")).is_empty() and not game.cast_spell(0, stroke), "short-cut preview and casting reject a stroke beyond the four-metre branch limit")
	game.upgrades.erase("short_cut")
	_check(game.get_cast_check(0, stroke).get("valid", false), "the same longer stroke remains available to the base red route")


func _test_short_rebate() -> void:
	_fresh()
	game.upgrades.assign(["short_cut", "short_rebate"])
	var survivor = _enemy("chaser", Vector3(0, 0, -3))
	var stroke: Array[Vector3] = _points(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	game.cast_spell(0, stroke)
	_check(game._live(survivor) and is_equal_approx(game.cooldowns[0], 0.65), "short rebate does not reward a nonlethal hit")
	game.cooldowns[0] = 0.0
	game.cast_spell(0, stroke)
	_check(not game._live(survivor) and is_equal_approx(game.cooldowns[0], 0.45), "an actual short-cut kill refunds cooldown on that cast")
	game.cooldowns[0] = 0.0
	var a = _enemy("chaser", Vector3(-0.5, 0, -3))
	var b = _enemy("chaser", Vector3(0.5, 0, -3))
	a.hp = 10.0
	b.hp = 10.0
	game.cast_spell(0, stroke)
	_check(not game._live(a) and not game._live(b) and is_equal_approx(game.cooldowns[0], 0.45), "multiple kills cannot refund below the short-cut cooldown floor")


func _test_snap_delay_and_pause() -> void:
	_fresh()
	game.upgrades.append("snap_link")
	game.progress.unlocked = ["blue_flow"]
	game.progress.equipped = ["", "blue_flow", ""]
	_select(1)
	var target = _enemy("charger", Vector3(0, 0, -3))
	var stroke: Array[Vector3] = _points(target.position, Vector3(-2, 0, -3))
	_check(game.cast_spell(1, stroke, target, null), "snap branch overrides flow and allows an enemy-to-ground link")
	_check(is_equal_approx(target.hp, 46.0) and is_equal_approx(game.cooldowns[1], 2.0), "snap establishment deals only its initial pulse and starts its own cooldown")
	_check(not game.secondary_action(), "snap rejects early right-click without queuing an automatic attack")
	game.paused = true
	var before_age: float = game.link.age
	var before_time: float = game.elapsed
	var before_cooldown: float = game.cooldowns[1]
	game._physics_process(0.7)
	_check(is_equal_approx(target.hp, 46.0) and not game.link.is_empty() and game.elapsed == before_time and game.cooldowns[1] == before_cooldown, "pause freezes snap preparation and its cooldown")
	_check(is_equal_approx(game.link.age, before_age), "paused time cannot prepare a snap")
	game.paused = false
	game._physics_process(0.24)
	_check(is_equal_approx(target.hp, 46.0) and not game.link.is_empty(), "snap remains a telegraph before the quarter-second delay")
	game._physics_process(0.02)
	_check(is_equal_approx(target.hp, 46.0), "ready snap waits for a new secondary input")
	_check(game.secondary_action(), "prepared link accepts the player secondary input")
	_check(is_equal_approx(target.hp, 22.0) and game.link.is_empty(), "accepted snap resolves one pulse and consumes the link")
	game.secondary_action()
	game._physics_process(0.4)
	_check(is_equal_approx(target.hp, 22.0), "repeated secondary input cannot duplicate a snap pulse")


func _test_snap_gather() -> void:
	_fresh()
	game.upgrades.assign(["snap_link", "snap_gather"])
	_select(1)
	var endpoint = _enemy("charger", Vector3(0, 0, -3))
	var neighbor = _enemy("chaser", Vector3(1.6, 0, -3))
	neighbor._phase = "recover"
	neighbor._phase_time = 100.0
	var before: Vector3 = neighbor.position
	game.cast_spell(1, _points(Vector3(-2, 0, -3), endpoint.position), null, endpoint)
	game._physics_process(0.26)
	game.secondary_action()
	neighbor._physics_process(0.1)
	_check(neighbor.position.distance_to(endpoint.position) < before.distance_to(endpoint.position) and is_equal_approx(neighbor.hp, 36.0), "snap gather physically pulls a nearby bystander without applying extra damage")


func _test_wall_arming_and_single_batch() -> void:
	_fresh()
	game.upgrades.append("moving_wall")
	game.progress.unlocked = ["gold_linger"]
	game.progress.equipped = ["", "", "gold_linger"]
	_select(2)
	var target = _enemy("chaser", Vector3(0, 0, -3))
	game.create_projectile(Vector3(0.5, 0, -3), Vector3(0, 0, -1), 14.0)
	var stroke: Array[Vector3] = _points(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	var check: Dictionary = game.get_cast_check(2, stroke)
	_check(check.get("valid", false) and check.hits.is_empty() and game.cast_spell(2, stroke), "moving-wall placement previews no immediate damage and creates a pending boundary")
	game._update_boundary(0.3)
	_check(is_equal_approx(target.hp, 36.0) and not game.projectiles[0].reflected and not game.boundary.is_empty(), "stationary moving wall neither damages contacts nor redirects projectiles")
	_check(is_equal_approx(game.cooldowns[2], 2.2), "moving wall uses its own placement cooldown")
	game.secondary_action()
	game.secondary_action()
	game._update_boundary(1.0 / 60.0)
	_check(is_equal_approx(target.hp, 12.0) and game.projectiles[0].reflected, "activated wall damages and redirects its first actual contact batch")
	_check(game.boundary.is_empty(), "moving wall consumes its first batch even with the old linger relic equipped")
	game.secondary_action()
	game._update_boundary(0.3)
	_check(is_equal_approx(target.hp, 12.0), "a consumed moving wall cannot be activated again")


func _test_wall_pause_and_travel() -> void:
	_fresh()
	game.upgrades.append("moving_wall")
	_select(2)
	var stroke: Array[Vector3] = _points(Vector3(-1, 0, -3), Vector3(1, 0, -3))
	game.cast_spell(2, stroke)
	game.secondary_action()
	var start: Vector3 = (game.boundary.a + game.boundary.b) * 0.5
	game.paused = true
	var cd: float = game.cooldowns[2]
	game._physics_process(0.4)
	_check(game.boundary.a.is_equal_approx(stroke[0]) and is_equal_approx(game.cooldowns[2], cd), "pause freezes an advancing wall and its cooldown")
	game.paused = false
	game._physics_process(0.1)
	var middle: Vector3 = (game.boundary.a + game.boundary.b) * 0.5
	_check(is_equal_approx(middle.distance_to(start), 0.6), "unpaused wall advances through the actual simulation at six metres per second")
	game.secondary_action()
	for tick in range(25):
		game._physics_process(0.02)
	_check(game.boundary.is_empty(), "extra secondary presses do not restart the wall travel budget")

	var base_hit: bool = _wall_reaches_distant_target(false)
	var upgraded_hit: bool = _wall_reaches_distant_target(true)
	_check(not base_hit and upgraded_hit, "wall-travel upgrade reaches a real target beyond the base travel range")


func _wall_reaches_distant_target(extended: bool) -> bool:
	_fresh()
	game.upgrades.append("moving_wall")
	if extended:
		game.upgrades.append("wall_travel")
	_select(2)
	var target = _enemy("chaser", Vector3(0, 0, 0.6))
	var second = _enemy("chaser", Vector3(0, 0, 1.4))
	game.cast_spell(2, _points(Vector3(-1, 0, -3), Vector3(1, 0, -3)))
	game.secondary_action()
	for tick in range(45):
		game._physics_process(0.02)
	if extended:
		_check(is_equal_approx(target.hp, 12.0) and is_equal_approx(second.hp, 36.0) and game.boundary.is_empty(), "extended travel still ends on its first batch and cannot damage a later target")
	return target.hp < 36.0


func _test_training_isolation() -> void:
	_fresh()
	game.progress.unlocked = RELICS.duplicate()
	game.progress.equipped = RELICS.duplicate()
	game.progress.essence = 120
	_check(game.store.save_data(game.progress), "training test creates a real isolated permanent save")
	var before: Dictionary = game.progress.duplicate(true)
	var disk_before: String = FileAccess.get_file_as_string("user://progress.json")
	game.start_training()
	game._clear_combat_objects()
	_check(game.upgrades.is_empty(), "training starts without any new attack branch")
	for index in range(3):
		_select(index)
		game.cooldowns[index] = 0.3
		game.toggle_training_branch()
		_check(game.upgrades.has(BRANCHES[index]), "training toggle enables the current cloak branch: " + BRANCHES[index])
		_check(is_equal_approx(game.cooldowns[index], 0.3), "training branch activation preserves the current cooldown")
		_check(not game._equipped(RELICS[index]), "training branch is mutually exclusive with its old permanent relic: " + BRANCHES[index])
		for other in range(3):
			if other != index:
				_check(not game.upgrades.has(BRANCHES[other]), "training toggle leaves other cloak routes unchanged")
		game.cooldowns[index] = 0.0
		var target = _enemy("charger", Vector3(0, 0, -3))
		var stroke: Array[Vector3] = _points(Vector3(-1, 0, -3), Vector3(1, 0, -3))
		if index == 1:
			stroke = _points(Vector3(-2, 0, -3), target.position)
		game.cast_spell(index, stroke, null, target if index == 1 else null)
		var cd: float = game.cooldowns[index]
		game.toggle_training_branch()
		_check(not game.upgrades.has(BRANCHES[index]), "second training toggle restores the current base route")
		_check(cd > 0.0 and is_equal_approx(game.cooldowns[index], cd), "training branch removal cannot bypass a spell cooldown")
		if index == 1:
			_check(game.link.is_empty(), "leaving the training snap branch clears its live link")
		elif index == 2:
			_check(game.boundary.is_empty(), "leaving the training moving-wall branch clears its pending boundary")
		game._clear_combat_objects()
	_check(game.progress == before and FileAccess.get_file_as_string("user://progress.json") == disk_before, "training route changes leave in-memory and on-disk permanent progress untouched")
	game.return_to_base()
	game.start_training()
	game._clear_combat_objects()
	_check(game.upgrades.is_empty() and game.progress == before, "re-entering training resets branch practice without changing permanent equipment")


func _test_shop_choices() -> void:
	for branch in BRANCHES:
		_fresh()
		game.elapsed = 120.0
		game._physics_process(0.001)
		var offered: Array = []
		for item in game.offers:
			offered.append(item.id)
		offered.sort()
		var expected: Array = BRANCHES.duplicate()
		expected.sort()
		_check(game.state == "shop" and offered == expected, "first shop exposes all three attack branches: " + branch)
		var before: int = game.coins
		_check(game.buy_upgrade(branch) and game.upgrades.has(branch) and game.coins < before, "first-shop branch is actually purchasable: " + branch)
		var after: int = game.coins
		_check(not game.buy_upgrade(branch) and game.coins == after, "duplicate branch purchase cannot charge twice: " + branch)
		game.continue_from_shop()
		game._clear_combat_objects()
		game.spawn_clock = 999.0
		_check(game.state == "battle" and game.upgrades.has(branch), "purchased branch remains equipped after the shop: " + branch)
