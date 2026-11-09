extends Node3D

## One body, three divine cloaks. Game owns health, spell state and progression.
const CLOAK_COLORS: Array[Color] = [Color("d44267"), Color("9170df"), Color("d5b979")]
const DODGE_DURATION: float = 0.22
const DODGE_DISTANCE: float = 2.6
const DODGE_RECOVERY: float = 1.4
const MOVE_SPEED: float = 5.2
const ARENA_RADIUS: float = 15.0
const CAST_DURATION: float = 0.24
const DODGE_TRAIL_INTERVAL: float = 0.045
const DODGE_TRAIL_DURATION: float = 0.18
const DODGE_TRAIL_COUNT: int = 6

var game
var dodge_remaining: float = 0.0
var dodge_cooldown: float = 0.0
var invulnerable: bool = false
var speed_multiplier: float = 1.0
var velocity: Vector3 = Vector3.ZERO

var _visual: Node3D
var _halo: MeshInstance3D
var _halo_material: StandardMaterial3D
var _cloak_materials: Array[StandardMaterial3D] = []
var _cloth_nodes: Array[Node3D] = []
var _cloth_rest: Array[Vector3] = []
var _cloth_scales: Array[Vector3] = []
var _cloak_index: int = 0
var _clock: float = 0.0
var _switch_time: float = 0.0
var _cast_time: float = 0.0
var _cast_facing_remaining: float = 0.0
var _target_yaw: float = 0.0
var _dodge_direction: Vector3 = Vector3.FORWARD
var _dodge_elapsed: float = 0.0
var _space_was_down: bool = false
var _ready_visual: bool = false
var _trail_root: Node3D
var _trails: Array[Dictionary] = []
var _trail_cursor: int = 0
var _trail_emit_time: float = 0.0
var _trail_emitted: int = 0


func setup(owner_game) -> void:
	game = owner_game
	if not _ready_visual:
		_build_visual()
	set_cloak(int(game.cloak))


func _physics_process(delta: float) -> void:
	var space_down: bool = Input.is_physical_key_pressed(KEY_SPACE)
	var dodge_pressed: bool = space_down and not _space_was_down
	_space_was_down = space_down
	if game == null or not game.is_running():
		velocity = Vector3.ZERO
		return

	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	_cast_facing_remaining = maxf(0.0, _cast_facing_remaining - delta)
	var axis: Vector2 = Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	if axis.length_squared() > 1.0:
		axis = axis.normalized()
	var right: Vector3 = Vector3.RIGHT
	var backwards: Vector3 = Vector3.BACK
	if is_instance_valid(game.camera):
		right = game.camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		backwards = game.camera.global_basis.z
		backwards.y = 0.0
		backwards = backwards.normalized()
	var move_direction: Vector3 = right * axis.x + backwards * axis.y
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()
	if move_direction.length_squared() > 0.01 and _cast_facing_remaining <= 0.0:
		_target_yaw = atan2(-move_direction.x, -move_direction.z)

	if dodge_pressed and dodge_cooldown <= 0.0 and dodge_remaining <= 0.0:
		game.cancel_gesture()
		_dodge_direction = move_direction.normalized()
		if _dodge_direction.length_squared() < 0.01:
			_dodge_direction = Vector3(-sin(_target_yaw), 0.0, -cos(_target_yaw))
		dodge_remaining = DODGE_DURATION
		_dodge_elapsed = 0.0
		dodge_cooldown = DODGE_RECOVERY
		_switch_time = 0.0
		_cast_time = 0.0
		_cast_facing_remaining = 0.0
		_target_yaw = atan2(-_dodge_direction.x, -_dodge_direction.z)
		_trail_emit_time = 0.0
		_trail_emitted = 0
		_emit_dodge_trail()

	var next_position: Vector3 = position
	var emit_trail: bool = false
	if dodge_remaining > 0.0:
		var active_delta: float = minf(delta, dodge_remaining)
		velocity = _dodge_direction * DODGE_DISTANCE / DODGE_DURATION
		next_position += velocity * active_delta
		_dodge_elapsed += active_delta
		_trail_emit_time += active_delta
		if _trail_emit_time >= DODGE_TRAIL_INTERVAL and _trail_emitted < DODGE_TRAIL_COUNT:
			_trail_emit_time = fmod(_trail_emit_time, DODGE_TRAIL_INTERVAL)
			emit_trail = true
		dodge_remaining = maxf(0.0, dodge_remaining - active_delta)
		invulnerable = _dodge_elapsed >= 0.04 and _dodge_elapsed <= 0.16
		if dodge_remaining <= 0.0:
			invulnerable = false
	else:
		invulnerable = false
		velocity = move_direction * MOVE_SPEED * speed_multiplier
		next_position += velocity * delta
		# Ordinary movement respects enemy bodies. Dodge can pass through them.
		for enemy in game.enemies:
			if not is_instance_valid(enemy) or enemy.dead:
				continue
			var separation: Vector3 = next_position - enemy.position
			separation.y = 0.0
			var clearance: float = float(enemy.radius) + 0.27
			var gap: float = separation.length()
			if gap < clearance and gap > 0.001:
				next_position += separation / gap * minf(clearance - gap, 0.24)

	var flat_position: Vector2 = Vector2(next_position.x, next_position.z)
	if flat_position.length() > ARENA_RADIUS:
		flat_position = flat_position.normalized() * ARENA_RADIUS
	next_position.x = flat_position.x
	next_position.z = flat_position.y
	next_position.y = 0.0
	position = next_position
	if emit_trail:
		_emit_dodge_trail()


func _process(delta: float) -> void:
	if not _ready_visual or game == null:
		return
	if not game.is_running():
		var mode: String = str(game.state)
		if mode == "base" or mode == "shop" or mode == "result":
			_clear_dodge_trails()
			_cast_time = 0.0
			_cast_facing_remaining = 0.0
		if mode != "base":
			return
	else:
		_tick_dodge_trails(delta)
	_clock += delta
	_switch_time = maxf(0.0, _switch_time - delta)
	_cast_time = maxf(0.0, _cast_time - delta)
	var moving: float = clampf(velocity.length() / MOVE_SPEED, 0.0, 1.0)
	var breathing: float = sin(_clock * 2.2) * 0.018
	var cast_wave: float = pow(clampf(_cast_time / CAST_DURATION, 0.0, 1.0), 1.35)
	var cast_twist: float = [0.22, -0.16, 0.08][_cloak_index]
	var facing: Vector3 = Vector3(-sin(_target_yaw), 0.0, -cos(_target_yaw))
	_visual.position = facing * cast_wave * 0.12
	_visual.position.y += breathing + absf(sin(_clock * 10.0)) * 0.035 * moving
	var turn_speed: float = 32.0 if _cast_facing_remaining > 0.0 else 15.0
	_visual.rotation.y = lerp_angle(_visual.rotation.y, _target_yaw + cast_twist * cast_wave, minf(1.0, delta * turn_speed))
	var lean: float = -0.28 if dodge_remaining > 0.0 else -0.24 * cast_wave
	_visual.rotation.x = lerpf(_visual.rotation.x, lean, minf(1.0, delta * 26.0))
	_visual.rotation.z = cast_twist * cast_wave * 0.45
	var switch_wave: float = sin(clampf(_switch_time / 0.35, 0.0, 1.0) * PI)
	for i in range(_cloth_nodes.size()):
		var cloth: Node3D = _cloth_nodes[i]
		if not is_instance_valid(cloth):
			continue
		var rest: Vector3 = _cloth_rest[i]
		cloth.rotation = rest + Vector3(
			sin(_clock * 2.9 + float(i)) * 0.025 + moving * 0.09 + cast_wave * 0.30,
			switch_wave * 0.32 + cast_twist * cast_wave,
			sin(_clock * 2.0 + float(i)) * 0.025 + cast_wave * 0.07
		)
		var silhouette: Vector3 = [Vector3(0.93,1.07,0.94), Vector3(1.18,0.94,1.08), Vector3(1.04,1.0,0.88)][_cloak_index]
		cloth.scale = _cloth_scales[i] * silhouette * Vector3(1.0 + switch_wave * 0.14 + cast_wave * 0.08, 1.0, 1.0 + switch_wave * 0.10)
	if is_instance_valid(_halo):
		_halo.rotation.y += delta * 0.35
		_halo.scale = Vector3.ONE * (1.0 + switch_wave * 0.55 + cast_wave * 0.30)
		var tint: Color = CLOAK_COLORS[_cloak_index]
		tint.a = 0.8 if invulnerable else 0.38 + switch_wave * 0.35 + cast_wave * 0.20
		_halo_material.albedo_color = tint


func set_cloak(index: int) -> void:
	_cloak_index = clampi(index, 0, 2)
	var tint: Color = CLOAK_COLORS[_cloak_index]
	for material in _cloak_materials:
		material.albedo_color = tint
		material.emission = tint * 0.17
	if _halo_material != null:
		_halo_material.emission = tint
		var ring_color: Color = tint
		ring_color.a = 0.45
		_halo_material.albedo_color = ring_color


func play_cast(target: Vector3 = Vector3.INF) -> void:
	_cast_time = CAST_DURATION
	_cast_facing_remaining = CAST_DURATION
	if target.is_finite():
		_face_point(target)
	else:
		_face_cursor()


func play_switch() -> void:
	_switch_time = 0.35


func cancel_input() -> void:
	_space_was_down = Input.is_physical_key_pressed(KEY_SPACE)
	velocity = Vector3.ZERO


func _face_cursor() -> void:
	if game == null or not is_instance_valid(game.camera):
		return
	var cursor: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = game.camera.project_ray_origin(cursor)
	var ray_direction: Vector3 = game.camera.project_ray_normal(cursor)
	if absf(ray_direction.y) < 0.001:
		return
	var distance: float = -ray_origin.y / ray_direction.y
	if distance <= 0.0:
		return
	_face_point(ray_origin + ray_direction * distance)


func _face_point(target: Vector3) -> void:
	var aim: Vector3 = target - global_position
	if Vector2(aim.x, aim.z).length_squared() > 0.02:
		_target_yaw = atan2(-aim.x, -aim.z)


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "WitchVisual"
	add_child(_visual)
	var model_path: String = "res://assets/models/player.glb"
	if ResourceLoader.exists(model_path):
		var scene = load(model_path)
		if scene is PackedScene:
			var model: Node3D = scene.instantiate()
			_visual.add_child(model)
			_collect_model_cloth(model)
		else:
			_build_fallback()
	else:
		_build_fallback()

	_halo_material = _material(Color(0.85, 0.32, 0.45, 0.45), true)
	_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo = MeshInstance3D.new()
	_halo.name = "DivineFootRing"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.505
	torus.rings = 48
	torus.ring_segments = 6
	_halo.mesh = torus
	_halo.material_override = _halo_material
	_halo.position.y = 0.035
	add_child(_halo)
	_build_dodge_trails()
	_ready_visual = true


func _build_dodge_trails() -> void:
	_trail_root = Node3D.new()
	_trail_root.name = "DodgeTrailPool"
	add_child(_trail_root)
	_trail_root.top_level = true
	var silhouette: ArrayMesh = _cloak_mesh()
	var sweep_mesh: BoxMesh = BoxMesh.new()
	sweep_mesh.size = Vector3(0.13, 0.018, 0.72)
	for i in range(DODGE_TRAIL_COUNT):
		var ghost: MeshInstance3D = MeshInstance3D.new()
		ghost.name = "Afterimage%d" % i
		ghost.mesh = silhouette
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material: StandardMaterial3D = _material(CLOAK_COLORS[_cloak_index], true)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		ghost.material_override = material
		_trail_root.add_child(ghost)
		var sweep: MeshInstance3D = MeshInstance3D.new()
		sweep.name = "GroundSweep"
		sweep.mesh = sweep_mesh
		sweep.material_override = material
		sweep.position = Vector3(0.0, 0.045, 0.20)
		sweep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(sweep)
		ghost.visible = false
		_trails.append({"node": ghost, "material": material, "left": 0.0})


func _emit_dodge_trail() -> void:
	if _trails.is_empty() or not is_instance_valid(_visual):
		return
	var trail: Dictionary = _trails[_trail_cursor]
	var ghost: MeshInstance3D = trail.node
	ghost.global_transform = Transform3D(Basis(Vector3.UP, _target_yaw), global_position)
	ghost.visible = true
	var material: StandardMaterial3D = trail.material
	var tint: Color = CLOAK_COLORS[_cloak_index]
	tint.a = 0.32
	material.albedo_color = tint
	material.emission = CLOAK_COLORS[_cloak_index] * 0.7
	trail.left = DODGE_TRAIL_DURATION
	_trail_cursor = (_trail_cursor + 1) % _trails.size()
	_trail_emitted += 1


func _tick_dodge_trails(delta: float) -> void:
	for trail in _trails:
		var left: float = maxf(0.0, float(trail.left) - delta)
		trail.left = left
		var ghost: MeshInstance3D = trail.node
		ghost.visible = left > 0.0
		if left > 0.0:
			var material: StandardMaterial3D = trail.material
			var tint: Color = material.albedo_color
			tint.a = 0.32 * left / DODGE_TRAIL_DURATION
			material.albedo_color = tint


func _clear_dodge_trails() -> void:
	for trail in _trails:
		trail.left = 0.0
		trail.node.visible = false


func _collect_model_cloth(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node
		var lower_name: String = str(mesh_node.name).to_lower()
		if "cloak" in lower_name or "hood" in lower_name or "cape" in lower_name:
			var material: StandardMaterial3D = _material(CLOAK_COLORS[_cloak_index])
			material.roughness = 0.82
			material.emission_enabled = true
			material.emission = CLOAK_COLORS[_cloak_index] * 0.17
			mesh_node.material_override = material
			_cloak_materials.append(material)
			if "hood" not in lower_name:
				_cloth_nodes.append(mesh_node)
				_cloth_rest.append(mesh_node.rotation)
				_cloth_scales.append(mesh_node.scale)
	for child in node.get_children():
		_collect_model_cloth(child)


func _material(color: Color, emission: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if emission:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = 0.6
	return material


func _mesh(mesh: Mesh, at: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	if parent == null:
		_visual.add_child(instance)
	else:
		parent.add_child(instance)
	return instance


func _cylinder(bottom: float, top: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.bottom_radius = bottom
	cylinder.top_radius = top
	cylinder.height = height
	cylinder.radial_segments = 12
	return _mesh(cylinder, at, material)


func _build_fallback() -> void:
	var dark: StandardMaterial3D = _material(Color("171a29"))
	var gold: StandardMaterial3D = _material(Color("c6aa6c"))
	gold.metallic = 0.65
	var skin: StandardMaterial3D = _material(Color("e3cfba"))
	var cloth: StandardMaterial3D = _material(CLOAK_COLORS[_cloak_index])
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloak_materials.append(cloth)
	_cylinder(0.38, 0.21, 0.82, Vector3(0.0, 0.56, 0.0), dark)
	_cylinder(0.215, 0.255, 0.44, Vector3(0.0, 1.10, 0.0), dark)
	_cylinder(0.233, 0.233, 0.065, Vector3(0.0, 0.94, 0.0), gold)
	var head: SphereMesh = SphereMesh.new()
	head.radius = 0.18
	head.height = 0.39
	head.radial_segments = 12
	head.rings = 6
	_mesh(head, Vector3(0.0, 1.52, -0.025), skin)
	_cylinder(0.48, 0.48, 0.045, Vector3(0.0, 1.68, 0.0), dark)
	var hat: MeshInstance3D = _cylinder(0.26, 0.015, 0.55, Vector3(0.0, 1.96, 0.025), dark)
	hat.rotation.z = -0.13
	_cylinder(0.265, 0.26, 0.06, Vector3(0.0, 1.73, 0.02), gold)
	for side in [-1.0, 1.0]:
		var arm: MeshInstance3D = _cylinder(0.075, 0.09, 0.53, Vector3(side * 0.29, 1.07, -0.01), dark)
		arm.rotation.z = side * 0.16
		var hand: SphereMesh = SphereMesh.new()
		hand.radius = 0.07
		hand.height = 0.14
		hand.radial_segments = 8
		hand.rings = 4
		_mesh(hand, Vector3(side * 0.34, 0.80, -0.01), skin)
	var cloak: MeshInstance3D = _mesh(_cloak_mesh(), Vector3.ZERO, cloth)
	cloak.name = "Cloak"
	_cloth_nodes.append(cloak)
	_cloth_rest.append(Vector3.ZERO)
	_cloth_scales.append(Vector3.ONE)
	var clasp: SphereMesh = SphereMesh.new()
	clasp.radius = 0.075
	clasp.height = 0.15
	clasp.radial_segments = 8
	clasp.rings = 4
	_mesh(clasp, Vector3(0.0, 1.30, -0.24), gold)


func _cloak_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pieces: int = 14
	for i in range(pieces):
		var a: float = lerpf(-2.35, 2.35, float(i) / float(pieces))
		var b: float = lerpf(-2.35, 2.35, float(i + 1) / float(pieces))
		var top_a: Vector3 = Vector3(sin(a) * 0.29, 1.33, cos(a) * 0.23)
		var top_b: Vector3 = Vector3(sin(b) * 0.29, 1.33, cos(b) * 0.23)
		var hem_a: Vector3 = Vector3(sin(a) * 0.56, 0.20 + 0.055 * cos(float(i) * PI), cos(a) * 0.50 + 0.07)
		var hem_b: Vector3 = Vector3(sin(b) * 0.56, 0.20 + 0.055 * cos(float(i + 1) * PI), cos(b) * 0.50 + 0.07)
		for vertex in [top_a, hem_a, top_b, top_b, hem_a, hem_b]:
			st.add_vertex(vertex)
	st.generate_normals()
	return st.commit()
