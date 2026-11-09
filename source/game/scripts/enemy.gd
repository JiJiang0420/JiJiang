extends Node3D

const DISPLAY_NAMES: Dictionary = {"chaser": "饿客", "charger": "疯仆", "armored": "背锅人", "boss": "老厨子"}

## Detached fragments share simulation pause semantics and clean up on phase exit.
class ArmorFragment:
	extends MeshInstance3D
	var game
	var motion: Vector3 = Vector3.ZERO
	var spin: Vector3 = Vector3.ZERO
	var remaining: float = 0.7
	var tint: StandardMaterial3D

	func _physics_process(delta: float) -> void:
		if not is_instance_valid(game) or str(game.state) not in ["battle", "training"]:
			queue_free()
			return
		if not game.is_running():
			return
		remaining -= delta
		if remaining <= 0.0:
			queue_free()
			return
		motion.y -= 12.0 * delta
		position += motion * delta
		rotation += spin * delta
		if position.y < 0.08:
			position.y = 0.08
			motion = Vector3(motion.x * 0.65, absf(motion.y) * 0.22, motion.z * 0.65)
		if remaining < 0.22:
			tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var fade: Color = tint.albedo_color
			fade.a = remaining / 0.22
			tint.albedo_color = fade

## All attack damage is event based. Moving into an enemy never deals contact DPS.
var game
var kind: String = "chaser"
var hp: float = 36.0
var max_hp: float = 36.0
var armor: float = 0.0
var dead: bool = false
var velocity: Vector3 = Vector3.ZERO
var forced_velocity: Vector3 = Vector3.ZERO
## Continuous movement is supplied once per simulation step, independently of impulses.
var pull_velocity: Vector3 = Vector3.ZERO
var spawn_delay: float = 0.0
var crack_time: float = 0.0
var charging: bool = false
var radius: float = 0.48

var _phase: String = "walk"
var _phase_time: float = 0.0
var _attack_cooldown: float = 0.5
var _move_speed: float = 3.15
var _attack_damage: float = 8.0
var _melee_range: float = 1.2
var _attack_position: Vector3 = Vector3.ZERO
var _charge_direction: Vector3 = Vector3.FORWARD
var _charge_hit: bool = false
var _boss_move: int = 0
var _boss_sequence: int = 0
var _slow_remaining: float = 0.0
var _hit_flash: float = 0.0
var _hit_stun_left: float = 0.0
var _hit_stun_gate: float = 0.0
var _hit_recoil_left: float = 0.0
var _name_reveal_left: float = 0.0
var _was_near: bool = false
var _age: float = 0.0
var _body: Node3D
var _shells: Array[MeshInstance3D] = []
var _cracks: Array[MeshInstance3D] = []
var _body_materials: Array[StandardMaterial3D] = []
var _original_colors: Array[Color] = []
var _telegraph: MeshInstance3D
var _health_root: Node3D
var _health_fill: MeshInstance3D
var _health_width: float = 0.9
var _spawn_duration: float = 0.0
var _spawn_materials: Array[StandardMaterial3D] = []
var _name_label: Label3D
var _cleaver: Node3D


func setup(owner_game, enemy_kind: String, at: Vector3) -> void:
	game = owner_game
	kind = enemy_kind
	position = at
	position.y = 0.0
	match kind:
		"charger":
			hp = 60.0
			_move_speed = 2.1
			_attack_damage = 18.0
			radius = 0.62
		"armored":
			hp = 100.0
			armor = 40.0
			_move_speed = 1.8
			_attack_damage = 16.0
			_melee_range = 1.65
			radius = 0.82
		"boss":
			hp = 720.0
			armor = 80.0
			_move_speed = 1.4
			_attack_damage = 24.0
			radius = 1.2
			_melee_range = 2.0
	max_hp = hp
	_attack_cooldown = 0.6 + randf() * 0.7
	_build_visual()
	_build_health_bar()
	_build_name_label()
	_collect_spawn_materials(_body)


func set_spawn_delay(seconds: float) -> void:
	if dead:
		return
	spawn_delay = maxf(0.0, seconds)
	_spawn_duration = spawn_delay
	velocity = Vector3.ZERO
	pull_velocity = Vector3.ZERO
	_set_spawn_opacity(0.0 if spawn_delay > 0.0 else 1.0)
	if is_instance_valid(_health_root) and spawn_delay > 0.0:
		_health_root.visible = false


func _physics_process(delta: float) -> void:
	if dead or game == null or not game.is_running():
		return
	if not is_instance_valid(game.player):
		return
	if spawn_delay > 0.0:
		spawn_delay = maxf(0.0, spawn_delay - delta)
		velocity = Vector3.ZERO
		pull_velocity = Vector3.ZERO
		_set_spawn_opacity(1.0 - spawn_delay / maxf(_spawn_duration, 0.001))
		return
	_age += delta
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_hit_recoil_left = maxf(0.0, _hit_recoil_left - delta)
	_name_reveal_left = maxf(0.0, _name_reveal_left - delta)
	_hit_stun_gate = maxf(0.0, _hit_stun_gate - delta)
	var locally_stunned: bool = _hit_stun_left > 0.0
	_hit_stun_left = maxf(0.0, _hit_stun_left - delta)
	crack_time = maxf(0.0, crack_time - delta)
	_slow_remaining = maxf(0.0, _slow_remaining - delta)
	if not locally_stunned:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var to_player: Vector3 = game.player.global_position - global_position
	to_player.y = 0.0
	var distance: float = to_player.length()
	var near_player: bool = distance < 4.2
	if near_player and not _was_near:
		_name_reveal_left = maxf(_name_reveal_left, 0.9)
	_was_near = near_player
	velocity = Vector3.ZERO
	if not locally_stunned:
		match _phase:
			"walk":
				_walk(delta, to_player, distance)
			"windup":
				_tick_windup(delta, to_player)
			"charge":
				_tick_charge(delta)
			"recover":
				_phase_time -= delta
				if _phase_time <= 0.0:
					_phase = "walk"
					_attack_cooldown = 0.65 if kind == "boss" else 0.8
	var speed_factor: float = 0.75 if _slow_remaining > 0.0 else 1.0
	if not charging:
		velocity *= speed_factor
	velocity += forced_velocity + pull_velocity
	pull_velocity = Vector3.ZERO
	velocity = velocity.limit_length(12.0)
	position += velocity * delta
	position.y = 0.0
	var planar: Vector2 = Vector2(position.x, position.z)
	if planar.length() > 15.0:
		planar = planar.normalized() * 15.0
		position.x = planar.x
		position.z = planar.y
		if charging:
			_finish_charge()
	forced_velocity = forced_velocity.move_toward(Vector3.ZERO, 24.0 * delta)
	_tick_visual(delta, to_player)


func _walk(_delta: float, to_player: Vector3, distance: float) -> void:
	if distance > 0.01:
		velocity = to_player.normalized() * _move_speed
	if kind == "boss" and distance < 5.0:
		velocity *= 0.25
	if kind != "boss" and distance < _melee_range * 0.9:
		velocity *= 0.25
	velocity += _separation()
	if _attack_cooldown > 0.0:
		return
	if kind == "boss":
		if distance < 12.5 and _can_start_threat():
			_begin_boss_move()
	elif kind == "charger":
		if distance < 9.0 and _can_start_threat():
			_begin_windup(1.0)
	else:
		if distance < _melee_range:
			_begin_windup(1.0 if kind == "armored" else 0.65)


func _separation() -> Vector3:
	var push: Vector3 = Vector3.ZERO
	for other in game.enemies:
		if not is_instance_valid(other) or other == self or other.dead:
			continue
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var dist: float = offset.length()
		var gap: float = radius + float(other.radius)
		if dist > 0.01 and dist < gap:
			push += offset / dist * (gap - dist) * 1.8
	return push.limit_length(2.0)


func _can_start_threat() -> bool:
	var active: int = 0
	for other in game.enemies:
		if not is_instance_valid(other) or other == self or other.dead:
			continue
		if other.has_method("is_high_threat") and other.is_high_threat():
			if other.kind == "boss" and kind != "boss":
				return false
			active += 1
	return active < 2


func is_high_threat() -> bool:
	return (kind == "charger" or kind == "boss") and (_phase == "windup" or charging)


func _begin_windup(seconds: float) -> void:
	_phase = "windup"
	_phase_time = seconds
	_attack_position = global_position
	_charge_direction = _direction_to_player()
	if kind == "charger" or (kind == "boss" and _boss_move == 0):
		_show_charge_telegraph()
	else:
		game.spawn_warning(_attack_position, _melee_range, Color(1.0, 0.22, 0.18, 0.65), seconds)


func _begin_boss_move() -> void:
	_boss_move = _boss_sequence % 3
	_boss_sequence += 1
	if _boss_move == 0:
		_begin_windup(1.2)
	elif _boss_move == 1:
		_phase = "windup"
		_phase_time = 0.9
		_attack_position = global_position
		_charge_direction = _direction_to_player()
		game.spawn_warning(global_position, 1.5, Color(1.0, 0.48, 0.25, 0.8), 0.9)
	else:
		_phase = "windup"
		_phase_time = 1.2
		_attack_position = global_position
		game.spawn_warning(_attack_position, 3.0, Color(0.94, 0.18, 0.30, 0.85), 1.2)


func _tick_windup(delta: float, to_player: Vector3) -> void:
	_phase_time -= delta
	if kind == "charger" or (kind == "boss" and _boss_move == 0):
		if _phase_time > 0.4 and to_player.length_squared() > 0.01:
			_charge_direction = to_player.normalized()
		_update_charge_telegraph()
	if _phase_time > 0.0:
		return
	_hide_telegraph()
	if kind == "charger" or (kind == "boss" and _boss_move == 0):
		_phase = "charge"
		charging = true
		_phase_time = 0.95 if kind == "charger" else 1.15
		_charge_hit = false
	elif kind == "boss" and _boss_move == 1:
		var forward: Vector3 = _charge_direction
		for angle in [-0.25, 0.0, 0.25]:
			game.create_projectile(global_position + Vector3.UP * 0.8 + forward * 1.3, forward.rotated(Vector3.UP, float(angle)), 14.0)
		_recover(1.8)
	elif kind == "boss":
		if game.player.global_position.distance_to(_attack_position) < 3.0:
			game.damage_player(22.0)
		game.flash(_attack_position + Vector3.UP * 0.08, Color(1.0, 0.25, 0.31), 3.0)
		_recover(2.2)
	else:
		var valid_distance: bool = global_position.distance_to(_attack_position) < 1.2
		if valid_distance and game.player.global_position.distance_to(_attack_position) < _melee_range + 0.2:
			game.damage_player(_attack_damage)
		game.flash(global_position + _direction_to_player() * 0.5 + Vector3.UP * 0.4, Color(0.85, 0.32, 0.25), 0.3)
		_recover(0.9 if kind == "armored" else 0.65)


func _tick_charge(delta: float) -> void:
	_phase_time -= delta
	var speed: float = 9.0 if kind == "boss" else 8.0
	velocity = _charge_direction * speed
	if not _charge_hit:
		var projected: Vector3 = global_position + velocity * delta
		var near: Vector3 = Geometry3D.get_closest_point_to_segment(game.player.global_position, global_position, projected)
		if near.distance_to(game.player.global_position) < radius + 0.38:
			_charge_hit = true
			game.damage_player(_attack_damage)
	if _phase_time <= 0.0:
		_finish_charge()


func _finish_charge() -> void:
	charging = false
	velocity = Vector3.ZERO
	_recover(2.0 if kind == "boss" else 1.2)


func _recover(seconds: float) -> void:
	_phase = "recover"
	_phase_time = seconds
	charging = false
	_hide_telegraph()


func _direction_to_player() -> Vector3:
	if game == null or not is_instance_valid(game.player):
		return Vector3.FORWARD
	var offset: Vector3 = game.player.global_position - global_position
	offset.y = 0.0
	return offset.normalized() if offset.length_squared() > 0.001 else Vector3.FORWARD


func take_hit(damage: float, structure_damage: float = 0.0, apply_crack: bool = false) -> void:
	if dead:
		return
	var previous_hp: float = hp
	var reduction: float = 0.65 if kind == "armored" and armor > 0.0 else 1.0
	hp = maxf(0.0, hp - maxf(0.0, damage) * reduction)
	var actual_damage: float = previous_hp - hp
	var had_armor: bool = armor > 0.0
	armor = maxf(0.0, armor - maxf(0.0, structure_damage))
	var armor_broken: bool = had_armor and armor <= 0.0
	if apply_crack:
		crack_time = 6.0
	if structure_damage > 0.0:
		interrupt_charge()
	if armor_broken:
		_spawn_armor_fragments()
		for shell in _shells:
			if is_instance_valid(shell):
				shell.visible = false
		game.flash(global_position + Vector3.UP * 0.7, Color(1.0, 0.76, 0.30), radius * 1.7)
	if actual_damage > 0.0 or structure_damage > 0.0:
		_hit_flash = 0.12
		_hit_recoil_left = 0.18
		_name_reveal_left = 1.15
		if _hit_stun_gate <= 0.0:
			# Freeze only this actor's AI, never the simulation or incoming forces.
			_hit_stun_left = 0.025 if kind == "boss" else (0.06 if kind == "armored" else 0.08)
			_hit_stun_gate = 0.8 if kind == "boss" else 0.18
	var killed: bool = hp <= 0.0
	if killed:
		dead = true
		charging = false
		_hide_telegraph()
	if game.has_method("hit_feedback") and (actual_damage > 0.0 or armor_broken):
		game.hit_feedback(self, actual_damage, armor_broken, killed)
	if killed:
		game.flash(global_position + Vector3.UP * 0.4, Color(0.68, 0.26, 0.46), radius)
		game.enemy_died(self)
		queue_free()


func movement_resistance() -> float:
	if kind == "boss":
		return 0.15 if armor > 0.0 else 0.3
	if kind == "armored" and armor > 0.0:
		return 0.25
	return 1.0


func apply_impulse(v: Vector3) -> void:
	if dead:
		return
	var flat: Vector3 = Vector3(v.x, 0.0, v.z)
	forced_velocity = (forced_velocity + flat * movement_resistance()).limit_length(12.0)


func set_pull_velocity(desired: Vector3) -> void:
	if dead or game == null or not game.is_running():
		return
	if spawn_delay > 0.0:
		pull_velocity = Vector3.ZERO
		return
	var flat: Vector3 = Vector3(desired.x, 0.0, desired.z).limit_length(4.0)
	var charge_resistance: float = 0.25 if charging else 1.0
	pull_velocity = flat * movement_resistance() * charge_resistance


func _collect_spawn_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var material = node.material_override
		if material is StandardMaterial3D and not _spawn_materials.has(material):
			_spawn_materials.append(material)
	for child in node.get_children():
		_collect_spawn_materials(child)


func _set_spawn_opacity(opacity: float) -> void:
	var alpha: float = clampf(opacity, 0.0, 1.0)
	for material in _spawn_materials:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		var tint: Color = material.albedo_color
		tint.a = alpha
		material.albedo_color = tint
	if is_instance_valid(_body):
		_body.scale = Vector3.ONE * lerpf(0.78, 1.0, alpha)


func redirect(direction: Vector3) -> void:
	if dead:
		return
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
	if flat.length_squared() < 0.01:
		return
	if charging:
		_charge_direction = flat
		velocity = flat * (9.0 if kind == "boss" else 8.0)
	else:
		apply_impulse(flat * 10.0)


func interrupt_charge() -> bool:
	if kind == "charger" and _phase == "windup":
		_recover(1.2)
		game.flash(global_position + Vector3.UP, Color(1.0, 0.45, 0.4), 0.6)
		return true
	return false


func add_slow(seconds: float) -> void:
	if kind != "boss":
		_slow_remaining = maxf(_slow_remaining, seconds)


func _build_visual() -> void:
	_body = Node3D.new()
	add_child(_body)
	var charcoal: StandardMaterial3D = _mat(Color("272433"))
	var bone: StandardMaterial3D = _mat(Color("cbb99a"))
	var blood: StandardMaterial3D = _mat(Color("6c3149"))
	var metal: StandardMaterial3D = _mat(Color("786c55"), false, 0.75)
	var glow: StandardMaterial3D = _mat(Color("ff7259"), true)
	if kind == "boss":
		_cylinder(_body, 0.85, 0.48, 2.3, Vector3(0, 1.15, 0), charcoal)
		_sphere(_body, Vector3(0.58, 0.55, 0.5), Vector3(0, 2.52, 0), bone)
		var linen: StandardMaterial3D = _mat(Color("c9c0a6"))
		# A worn kitchen apron, broad cleaver, and chef's hat anchor the silhouette.
		_box(_body, Vector3(1.22, 1.62, 0.09), Vector3(0, 1.12, -0.67), linen)
		_box(_body, Vector3(0.13, 0.72, 0.08), Vector3(-0.35, 2.04, -0.49), linen)
		_box(_body, Vector3(0.13, 0.72, 0.08), Vector3(0.35, 2.04, -0.49), linen)
		_box(_body, Vector3(0.36, 0.28, 0.025), Vector3(0.22, 1.03, -0.73), blood)
		_cylinder(_body, 0.61, 0.59, 0.20, Vector3(0, 3.06, 0), linen)
		for x in [-0.32, 0.0, 0.32]:
			_sphere(_body, Vector3(0.28, 0.28, 0.29), Vector3(float(x), 3.25, 0), linen)
		for side in [-1.0, 1.0]:
			var arm: MeshInstance3D = _box(_body, Vector3(0.45, 1.45, 0.5), Vector3(side * 0.9, 1.55, 0), charcoal)
			arm.rotation.z = side * -0.2
			_shells.append(_box(_body, Vector3(0.8, 0.36, 0.85), Vector3(side * 0.8, 2.12, 0), metal))
			_sphere(_body, Vector3(0.08, 0.08, 0.06), Vector3(side * 0.19, 2.55, -0.47), glow)
		_cleaver = Node3D.new()
		_cleaver.position = Vector3(1.04, 1.25, -0.28)
		_body.add_child(_cleaver)
		_box(_cleaver, Vector3(0.16, 0.7, 0.16), Vector3(0, 0.05, 0), blood)
		_box(_cleaver, Vector3(0.78, 1.0, 0.14), Vector3(0.23, 0.8, 0), metal)
		_box(_cleaver, Vector3(0.79, 0.065, 0.17), Vector3(0.23, 0.31, 0), bone)
	elif kind == "armored":
		_sphere(_body, Vector3(0.53, 0.75, 0.5), Vector3(0, 0.94, -0.16), blood)
		_shells.append(_sphere(_body, Vector3(0.90, 0.92, 0.45), Vector3(0, 1.16, 0.28), metal))
		var rim: MeshInstance3D = _torus(_body, 0.76, 0.88, Vector3(0, 1.16, 0.64), bone)
		rim.rotation.x = PI * 0.5
		_shells.append(rim)
		var knob: MeshInstance3D = _cylinder(_body, 0.16, 0.16, 0.16, Vector3(0, 1.16, 0.78), charcoal)
		knob.rotation.x = PI * 0.5
		_shells.append(knob)
		_sphere(_body, Vector3(0.34, 0.36, 0.32), Vector3(0, 1.8, -0.49), bone)
		for side in [-1.0, 1.0]:
			_box(_body, Vector3(0.3, 0.6, 0.38), Vector3(side * 0.39, 0.3, -0.07), charcoal)
			_box(_body, Vector3(0.18, 0.78, 0.20), Vector3(side * 0.61, 0.88, -0.27), blood)
			_box(_body, Vector3(0.12, 1.0, 0.1), Vector3(side * 0.32, 1.16, -0.60), charcoal)
			_sphere(_body, Vector3(0.05, 0.06, 0.06), Vector3(side * 0.12, 1.84, -0.79), glow)
	elif kind == "charger":
		var torso: MeshInstance3D = _cylinder(_body, 0.19, 0.29, 0.98, Vector3(0, 1.14, -0.12), blood)
		torso.rotation.x = -0.16
		_sphere(_body, Vector3(0.23, 0.37, 0.22), Vector3(0, 1.87, -0.38), bone)
		_box(_body, Vector3(0.29, 0.67, 0.045), Vector3(0, 0.99, -0.36), charcoal)
		for side in [-1.0, 1.0]:
			var leg: MeshInstance3D = _box(_body, Vector3(0.13, 0.83, 0.17), Vector3(side * 0.20, 0.43, 0.13), charcoal)
			leg.rotation.x = 0.12 * side
			var arm: MeshInstance3D = _box(_body, Vector3(0.12, 1.03, 0.13), Vector3(side * 0.35, 1.04, -0.34), blood)
			arm.rotation.x = -0.28
			_sphere(_body, Vector3(0.075, 0.12, 0.08), Vector3(side * 0.35, 0.5, -0.49), bone)
			_sphere(_body, Vector3(0.04, 0.06, 0.04), Vector3(side * 0.085, 1.9, -0.59), glow)
	else:
		_cylinder(_body, 0.43, 0.25, 1.05, Vector3(0, 0.65, 0), charcoal)
		_sphere(_body, Vector3(0.27, 0.34, 0.23), Vector3(0, 1.38, -0.02), bone)
		for side in [-1.0, 1.0]:
			var arm: MeshInstance3D = _box(_body, Vector3(0.14, 0.65, 0.14), Vector3(side * 0.43, 0.97, -0.08), blood)
			arm.rotation.z = side * 0.22
			_sphere(_body, Vector3(0.043, 0.06, 0.045), Vector3(side * 0.095, 1.42, -0.23), glow)
	var crack_mat: StandardMaterial3D = _mat(Color("ff2f66"), true)
	var size_factor: float = 1.6 if kind == "boss" else 1.0
	for i in range(3):
		var crack: MeshInstance3D = _box(_body, Vector3(0.045, 0.7 * size_factor, 0.045), Vector3((i - 1) * 0.2, 0.9 * size_factor, -radius * 0.85), crack_mat)
		crack.rotation.z = -0.3 + float(i) * 0.3
		crack.visible = false
		_cracks.append(crack)


func _build_health_bar() -> void:
	_health_width = 2.4 if kind == "boss" else 0.9
	_health_root = Node3D.new()
	_health_root.position.y = 3.85 if kind == "boss" else (2.5 if kind in ["armored", "charger"] else 1.9)
	add_child(_health_root)
	var back: MeshInstance3D = _box(_health_root, Vector3(_health_width, 0.075, 0.025), Vector3.ZERO, _mat(Color("211a27"), true))
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_health_fill = _box(_health_root, Vector3(_health_width - 0.025, 0.045, 0.035), Vector3(0, 0, 0.018), _mat(Color("e0af6a") if kind == "boss" else Color("df6175"), true))
	_health_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_health_root.visible = kind == "boss"


func get_display_name() -> String:
	return str(DISPLAY_NAMES.get(kind, "饿客"))


func _build_name_label() -> void:
	_name_label = Label3D.new()
	_name_label.name = "EnemyName"
	_name_label.text = get_display_name()
	_name_label.position.y = _health_root.position.y + 0.24
	_name_label.font_size = 44
	_name_label.pixel_size = 0.0075
	_name_label.outline_size = 8
	_name_label.modulate = Color("f5dfb9")
	_name_label.outline_modulate = Color("211b27")
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = false
	_name_label.shaded = false
	if ResourceLoader.exists("res://assets/fonts/ui.ttf"):
		_name_label.font = load("res://assets/fonts/ui.ttf")
	_name_label.visible = false
	add_child(_name_label)


func _can_show_name() -> bool:
	if _name_reveal_left <= 0.0 or spawn_delay > 0.0 or dead:
		return false
	var distance_squared: float = global_position.distance_squared_to(game.player.global_position)
	if distance_squared > 100.0:
		return false
	var closer_labels: int = 0
	for other in game.enemies:
		if not is_instance_valid(other) or other == self or other.dead:
			continue
		if float(other.get("_name_reveal_left")) <= 0.0 or float(other.spawn_delay) > 0.0:
			continue
		var other_distance: float = other.global_position.distance_squared_to(game.player.global_position)
		if other_distance < distance_squared or (is_equal_approx(other_distance, distance_squared) and other.get_instance_id() < get_instance_id()):
			closer_labels += 1
	return closer_labels < 3


func _spawn_armor_fragments() -> void:
	for i in range(8):
		var shard: ArmorFragment = ArmorFragment.new()
		shard.game = game
		var fragment_mesh: BoxMesh = BoxMesh.new()
		fragment_mesh.size = Vector3(0.16 + randf() * 0.13, 0.18 + randf() * 0.23, 0.08)
		shard.mesh = fragment_mesh
		shard.tint = StandardMaterial3D.new()
		shard.tint.albedo_color = Color("b9a47a")
		shard.tint.metallic = 0.7
		shard.tint.roughness = 0.4
		shard.material_override = shard.tint
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle: float = float(i) * TAU / 8.0
		var radial: Vector3 = Vector3(sin(angle), 0.0, cos(angle))
		shard.motion = radial * randf_range(2.0, 4.2) + Vector3.UP * randf_range(1.8, 3.2)
		shard.spin = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))
		get_parent().add_child(shard)
		shard.global_position = global_position + radial * radius * 0.65 + Vector3.UP * (1.0 if kind != "boss" else 1.8)


func _tick_visual(delta: float, to_player: Vector3) -> void:
	if not is_instance_valid(_body):
		return
	var face: Vector3 = _charge_direction if charging or _phase == "windup" else to_player
	if face.length_squared() > 0.001:
		var target_yaw: float = atan2(-face.x, -face.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, target_yaw, minf(1.0, delta * 10.0))
	var walking: bool = _phase == "walk" and velocity.length_squared() > 0.2
	_body.position.y = sin(_age * 8.0) * 0.045 if walking else sin(_age * 2.0) * 0.018
	var recoil: float = clampf(_hit_recoil_left / 0.18, 0.0, 1.0)
	var base_lean: float = -0.31 if charging else (-0.16 if kind == "charger" else 0.0)
	if _phase == "windup":
		base_lean += 0.07 * sin(_age * 20.0)
	_body.rotation.x = base_lean + recoil * (0.08 if kind == "boss" else 0.28)
	_body.rotation.z = recoil * 0.10 * (-1.0 if get_instance_id() % 2 == 0 else 1.0)
	for i in range(_body_materials.size()):
		var whiten: float = 0.92 * clampf(_hit_flash / 0.06, 0.0, 1.0)
		_body_materials[i].albedo_color = _original_colors[i].lerp(Color.WHITE, whiten)
	for crack in _cracks:
		crack.visible = crack_time > 0.0
	if is_instance_valid(_cleaver):
		var lift: float = -1.1 if _phase == "windup" else (0.55 if charging else 0.0)
		_cleaver.rotation.x = lerpf(_cleaver.rotation.x, lift, minf(delta * 14.0, 1.0))
	if is_instance_valid(_name_label):
		_name_label.visible = _can_show_name()
	if is_instance_valid(_health_root):
		_health_root.visible = hp < max_hp or kind == "boss"
		_health_fill.scale.x = maxf(0.001, hp / max_hp)
		_health_fill.position.x = -_health_width * (1.0 - hp / max_hp) * 0.5
		if is_instance_valid(game.camera):
			_health_root.global_rotation = game.camera.global_rotation


func _show_charge_telegraph() -> void:
	_hide_telegraph()
	_telegraph = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.65 if kind == "charger" else 1.3, 0.025, 9.5)
	_telegraph.mesh = mesh
	var material: StandardMaterial3D = _mat(Color(1.0, 0.27, 0.19, 0.3), true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph.material_override = material
	_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_telegraph)
	_update_charge_telegraph()


func _update_charge_telegraph() -> void:
	if not is_instance_valid(_telegraph):
		return
	_telegraph.position = _charge_direction * 4.75 + Vector3.UP * 0.05
	_telegraph.rotation.y = atan2(-_charge_direction.x, -_charge_direction.z)


func _hide_telegraph() -> void:
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null


func _mat(color: Color, luminous: bool = false, metallic: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	material.metallic = metallic
	if luminous:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = 1.4
	else:
		_body_materials.append(material)
		_original_colors.append(color)
	return material


func _box(parent: Node3D, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _sphere(parent: Node3D, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	instance.mesh = mesh
	instance.scale = dimensions
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _torus(parent: Node3D, inner: float, outer: float, at: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 6
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _cylinder(parent: Node3D, bottom: float, top: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 8
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance
