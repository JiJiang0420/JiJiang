extends Node3D

const Rules = preload("res://scripts/rules.gd")
const Player = preload("res://scripts/player.gd")
const Enemy = preload("res://scripts/enemy.gd")
const World = preload("res://scripts/world.gd")
const HUD = preload("res://scripts/hud.gd")
const Store = preload("res://scripts/progress_store.gd")
const CombatView = preload("res://scripts/combat_view.gd")

var state:String = "base"
var paused:bool = false
var player
var camera:Camera3D
var hud
var world
var enemies:Array = []
var cloak:int = 0
var hp:float = 100.0
var max_hp:float = 100.0
var cooldowns:Array[float] = [0.0,0.0,0.0]
var elapsed:float = 0.0
var duration:float = 480.0
var coins:int = 0
var stage:int = 0
var progress:Dictionary = {}
var upgrades:Array = []
var store = Store.new()
var kills:int = 0
var earned:int = 0
var phase_earned:int = 0
var spawn_clock:float = 0.0
var hurt_clock:float = 0.0
var switch_clock:float = 0.0
var boss_defeated:bool = false
var shop_buys:int = 0
var offers:Array = []
var yaw:float = 0.0
var drawing:bool = false
var rotating:bool = false
var draw_time:float = 0.0
var path:Array[Vector3] = []
var first_target
var pointer:Vector3 = Vector3.ZERO
var preview:MeshInstance3D
var link:Dictionary = {}
var boundary:Dictionary = {}
var visuals:Array = []
var projectiles:Array = []
var echo_events:Array = []
var collision_guards:Dictionary = {}
var effect_serial:int = 0
var message:String = ""
var help_visible:bool = false
var sound_players:Array = []
var sound_index:int = 0
var ambience:AudioStreamPlayer
var auto_play:bool = false
var auto_clock:float = 0.0
var capture_path:String = ""
var capture_clock:float = 0.0
var closing:bool = false
var combat_view
var aim:Dictionary = {}
var feedback_left:float = 0.0
var feedback_priority:int = 0
var hit_color:Color = Color.WHITE
var cast_kills:int = 0
var wave_serial:int = 0
var draw_clipped:bool = false

func _ready()->void:
 get_tree().auto_accept_quit = false
 get_window().close_requested.connect(_quit_cleanly)
 process_priority = 10
 progress = store.load_data()
 world = World.new()
 add_child(world)
 world.build()
 player = Player.new()
 add_child(player)
 player.setup(self)
 camera = Camera3D.new()
 camera.fov = 48
 camera.far = 120
 add_child(camera)
 camera.make_current()
 _update_camera(1.0)
 preview = MeshInstance3D.new()
 add_child(preview)
 hud = HUD.new()
 add_child(hud)
 hud.setup(self)
 combat_view = CombatView.new()
 add_child(combat_view)
 combat_view.setup(self)
 _setup_audio()
 return_to_base()
 for arg in OS.get_cmdline_user_args():
  if arg == "--autoplay": auto_play = true
  if arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
 if auto_play:
  start_run(true)

func is_running()->bool:
 return (state == "battle" or state == "training") and not paused

func _process(delta:float)->void:
 _update_camera(delta)
 if is_running():
  _sample_pointer(get_viewport().get_mouse_position())
  feedback_left = maxf(0,feedback_left-delta)
  if feedback_left<=0: message = ""
  if drawing:
   draw_time += delta
   if draw_time > 2.4:
    cancel_gesture()
    _set_feedback("绘制已取消：按住左键画线，松开才会攻击",2)
  if auto_play:
   auto_clock -= delta
   _auto_step(delta)
 _refresh_aim()
 _update_status()
 if not capture_path.is_empty():
  capture_clock += delta
  if capture_clock > 5.0:
   var shot = capture_path
   capture_path = ""
   await RenderingServer.frame_post_draw
   var img = get_viewport().get_texture().get_image()
   if img != null and not img.is_empty():
    img.save_png(shot)
    print("CAPTURE_SAVED ",shot)

func _physics_process(delta:float)->void:
 if not is_running(): return
 hurt_clock = maxf(0.0,hurt_clock-delta)
 switch_clock = maxf(0.0,switch_clock-delta)
 for i in range(3): cooldowns[i] = maxf(0,cooldowns[i]-delta)
 elapsed += delta
 _update_link(delta)
 _update_boundary(delta)
 _update_projectiles(delta)
 _update_collisions(delta)
 _update_echoes(delta)
 _update_visuals(delta)
 if state == "training":
  if enemies.is_empty():
   spawn_clock += delta
   if spawn_clock > 1.5: _training_wave()
  return
 if boss_defeated:
  _finish_run(true,"老厨子已被击败")
  return
 if hp <= 0:
  _finish_run(false,"承宴者倒下了")
  return
 if elapsed >= duration:
  _finish_run(false,"盛宴闭合 · 未能在时限内击败老厨子")
  return
 if stage < 3 and elapsed >= (stage+1)*duration/4.0:
  _open_shop()
  return
 spawn_clock -= delta
 if spawn_clock <= 0:
  _spawn_wave()
  spawn_clock = 2.4 if enemies.size()<5 else (4.0 if stage<2 else 3.2)

func _unhandled_input(event:InputEvent)->void:
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode == KEY_ESCAPE:
   toggle_pause()
   return
  if event.keycode == KEY_H:
   toggle_help()
   return
  if is_running():
   if event.keycode >= KEY_1 and event.keycode <= KEY_3:
    switch_cloak(event.keycode-KEY_1)
   if event.keycode == KEY_HOME and not drawing: yaw = 0
   if event.keycode == KEY_Q: toggle_training_branch()
 if not is_running(): return
 if event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_MIDDLE:
   rotating = event.pressed and not drawing
  if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
   if drawing: cancel_gesture()
   else: secondary_action()
  if event.button_index == MOUSE_BUTTON_LEFT:
   if event.pressed:
    _begin_gesture(event.position)
   elif drawing:
    _sample_pointer(event.position)
    _release_gesture()
 if event is InputEventMouseMotion:
  if drawing: _sample_pointer(event.position)
  elif rotating: yaw -= event.relative.x*0.006

func _ground_point(screen:Vector2):
 return Plane(Vector3.UP,0.08).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))

func _update_camera(delta:float)->void:
 if player == null: return
 var target = player.position + Vector3(0,0.65,0)
 var offset = Vector3(sin(yaw)*13.0,18.0,cos(yaw)*13.0)
 if state == "base":
  target = Vector3(0,0.9,0)
  offset = Vector3(4.5,6.5,10.5)
 camera.position = camera.position.lerp(target+offset,clampf(delta*8.0,0,1))
 camera.look_at(target,Vector3.UP)

func switch_cloak(index:int)->bool:
 if not is_running() or switch_clock > 0 or player.dodge_remaining > 0 or index == cloak: return false
 cancel_gesture()
 cloak = clampi(index,0,2)
 switch_clock = 0.22
 player.set_cloak(cloak)
 player.play_switch()
 flash(player.position+Vector3.UP*0.2,Rules.COLORS[cloak],0.9)
 _sound("switch")
 return true

func _sample_pointer(screen:Vector2)->void:
 var ground = _ground_point(screen)
 if ground == null: return
 pointer = ground
 if not drawing or path.is_empty(): return
 var offset:Vector3 = Rules.flat(pointer-player.position)
 draw_clipped = offset.length()>8.0
 if draw_clipped: pointer = player.position+offset.normalized()*8.0
 pointer.y = 0.08
 if cloak == 0:
  var budget:float = maxf(0,_stroke_limit(0)-_path_length(path))
  var step:Vector3 = pointer-path[-1]
  if step.length()>budget:
   pointer = path[-1]+step.normalized()*budget
   draw_clipped = true
  if path[-1].distance_to(pointer)>0.08: path.append(pointer)
 else:
  var step:Vector3 = pointer-path[0]
  if step.length()>_stroke_limit(cloak):
   pointer = path[0]+step.normalized()*_stroke_limit(cloak)
   draw_clipped = true

func _begin_gesture(screen:Vector2)->void:
 if switch_clock > 0 or player.dodge_remaining > 0: return
 if cooldowns[cloak] > 0:
  hud.toast("神权尚在恢复")
  return
 var ground = _ground_point(screen)
 if ground == null: return
 if Rules.flat(ground-player.position).length()>8.05:
  _set_feedback("起笔超出范围：从角色周围的圆圈内开始",2)
  return
 pointer = ground
 draw_clipped = false
 path.assign([pointer])
 first_target = _nearest_enemy(pointer,1.15)
 drawing = true
 rotating = false
 draw_time = 0
 _draw_preview()

func cancel_gesture()->void:
 drawing = false
 path.clear()
 first_target = null
 if is_instance_valid(preview): preview.mesh = null

func _release_gesture()->void:
 var pts:Array[Vector3] = _gesture_points()
 var a = first_target
 var b = _nearest_enemy(pointer,1.15) if cloak == 1 else null
 var check = get_cast_check(cloak,pts,a,b)
 cancel_gesture()
 if not check.valid:
  _set_feedback(check.reason,2)
  return
 if cast_spell(cloak,pts,a,b): player.play_cast(pts[-1])

func cast_spell(index:int,points:Array[Vector3],a=null,b=null)->bool:
 if index<0 or index>2 or not is_running() or cooldowns[index]>0: return false
 var check = get_cast_check(index,points,a,b)
 if not check.valid: return false
 cast_kills = 0
 var ok = false
 if index == 0: ok = _cast_red(check.points)
 if index == 1: ok = _cast_blue(check.points,a,b)
 if index == 2: ok = _cast_gold(check.points)
 if ok:
  cooldowns[index] = _spell_cooldown(index)
  if index==0 and upgrades.has("short_cut") and upgrades.has("short_rebate") and cast_kills>0:
   cooldowns[0] = maxf(0.45,cooldowns[0]-0.2)
   _set_feedback("短切击倒：下一刀提前 0.2 秒",1)
  effect_serial += 1
  _sound(["red","blue","gold_place"][index])
  if index==0: _set_feedback("切中 %d 个目标" % check.hits.size() if not check.hits.is_empty() else "这一刀挥空了：让攻击带穿过敌人",0)
  if index==1: _set_feedback("连线已拉紧 · 右键收线" if upgrades.has("snap_link") else "连接命中：持续拉近两端",0)
  if index==2: _set_feedback("边界已放置 · 右键沿箭头推出" if upgrades.has("moving_wall") else "边界已立起：接触后推开敌人",0)
 return ok

func _cast_red(points:Array[Vector3])->bool:
 var short_cut = upgrades.has("short_cut")
 var echo = _equipped("red_echo")
 _red_hit(points,18.0 if short_cut or echo else 24.0,12.0 if short_cut else (14.0 if echo else 20.0),true)
 if is_instance_valid(combat_view): combat_view.cast(points,Rules.COLORS[0],0.95 if upgrades.has("wide") else 0.7)
 if echo: echo_events.append({"left":0.35,"points":points.duplicate()})
 return true

func _red_hit(points:Array[Vector3],damage:float,structure:float,allow_bonus:bool)->void:
 hit_color = Rules.COLORS[0]
 var width = 0.475 if upgrades.has("wide") else 0.35
 var hit:Array = []
 var candidates:Array = []
 for i in range(points.size()-1):
  var segment_hits:Array = []
  var start:Vector3 = Rules.flat(points[i])
  var direction:Vector3 = Rules.flat(points[i+1]-points[i]).normalized()
  for e in enemies.duplicate():
   if not _live(e) or hit.has(e): continue
   if Rules.segment_distance(Rules.flat(e.position),start,Rules.flat(points[i+1])) < width+e.radius:
    segment_hits.append(e)
    hit.append(e)
  segment_hits.sort_custom(func(a,b): return (a.position-start).dot(direction)<(b.position-start).dot(direction))
  candidates.append_array(segment_hits)
 var bonus = false
 for e in candidates:
  if not _live(e): continue
  var before = e.armor
  var extra = 20.0 if bonus and before>0 else 0.0
  if extra>0: bonus = false
  var interrupted:bool = e.interrupt_charge() if structure+extra>0 else false
  if interrupted:
   _set_feedback("打断疯仆蓄力：现在可以接近",2)
   if is_instance_valid(combat_view): combat_view.hit(e.position,0,Rules.COLORS[0],"打断")
  e.take_hit(damage,structure+extra,true)
  if _live(e):
   e.crack_time = 9.0 if upgrades.has("crack") else 6.0
   if not e.charging and e.interrupt_charge(): _set_feedback("打断疯仆蓄力：现在可以接近",2)
  if allow_bonus and upgrades.has("shatter") and before>0 and (not _live(e) or e.armor<=0):
   bonus = true
   allow_bonus = false
  flash(e.position+Vector3.UP*0.7,Rules.COLORS[0],0.45)

func _cast_blue(points:Array[Vector3],a,b)->bool:
 if a != null and not _live(a): return false
 if b != null and not _live(b): return false
 if a == null and b == null: return false
 if a != null and a == b: return false
 var p:Vector3 = a.position if a != null else points[0]
 var q:Vector3 = b.position if b != null else points[-1]
 if Rules.flat(p-player.position).length()>8.05 or Rules.flat(q-player.position).length()>8.05: return false
 var limit = 10.0 if upgrades.has("reach") else 8.0
 if p.distance_to(q)>limit or p.distance_to(q)<0.3: return false
 var flow = _equipped("blue_flow")
 if flow and b == null: return false
 hit_color = Rules.COLORS[1]
 _clear_link()
 link = {"a":a,"b":b,"p":p,"q":q,"left":4.0,"age":0.0,"snap":upgrades.has("snap_link"),"flow":flow,"node":MeshInstance3D.new()}
 add_child(link.node)
 var damage = 14.0 if upgrades.has("snap_link") else (16.0 if flow else 20.0)
 var tidals:Array = []
 for e in [a,b]:
  if not _live(e): continue
  if progress.get("resonance",false) and e.crack_time>0:
   var toward:Vector3 = q if e == a else p
   e.apply_impulse((toward-e.position).normalized()*3.0)
  if upgrades.has("tide"):
   for other in enemies:
    if _live(other) and other != a and other != b and other.kind != "boss" and not tidals.has(other) and other.position.distance_to(e.position)<2:
     other.apply_impulse((e.position-other.position).normalized()*2.0)
     tidals.append(other)
     break
  e.take_hit(damage)
  flash(e.position,Rules.COLORS[1],0.7)
 if (a != null and not _live(a)) or (b != null and not _live(b)): _clear_link()
 return true

func _cast_gold(points:Array[Vector3])->bool:
 var a = points[0]
 var b = points[-1]
 _clear_boundary()
 var moving = upgrades.has("moving_wall")
 boundary = {"a":a,"b":b,"normal":Rules.boundary_normal(a,b),"left":3.0 if moving else (4.5 if upgrades.has("linger") else 3.0),"node":MeshInstance3D.new(),"seen":[],"batches":0,"extended":_equipped("gold_linger"),"active_id":effect_serial,"moving":moving,"launched":false,"travel":0.0,"travel_limit":4.0 if upgrades.has("wall_travel") else 2.5}
 add_child(boundary.node)
 _line(boundary.node,[a+Vector3.UP*0.12,b+Vector3.UP*0.12],Rules.COLORS[2],0.6)
 if not moving: _arrow((a+b)*0.5,boundary.normal,Rules.COLORS[2],1.0)
 return true

func _update_link(delta:float)->void:
 if link.is_empty(): return
 link.left -= delta
 link.age = float(link.get("age",0.0))+delta
 if link.left <= 0 or (link.a != null and not _live(link.a)) or (link.b != null and not _live(link.b)):
  _clear_link()
  return
 var p:Vector3 = link.a.position if link.a != null else link.p
 var q:Vector3 = link.b.position if link.b != null else link.q
 if p.distance_to(q)>(12 if upgrades.has("reach") else 10):
  _clear_link()
  return
 var force = (1.8 if link.get("snap",false) else 3.0)*(1.2 if upgrades.has("pull") else 1.0)
 if p.distance_to(q)>0.7:
  if _live(link.a) and not link.flow: link.a.set_pull_velocity((q-p).normalized()*force)
  if _live(link.b): link.b.set_pull_velocity((p-q).normalized()*force)
 _line(link.node,[p+Vector3.UP*0.5,(p+q)*0.5+Vector3.UP*0.9,q+Vector3.UP*0.5],Rules.COLORS[1],0.13)

func _update_boundary(delta:float)->void:
 if boundary.is_empty(): return
 var moving:bool = boundary.get("moving",false)
 if moving and boundary.get("launched",false):
  var distance:float = minf(6.0*delta,float(boundary.travel_limit)-float(boundary.travel))
  boundary.a += boundary.normal*distance
  boundary.b += boundary.normal*distance
  boundary.travel += distance
  if Rules.flat(boundary.a).length()>15.5 or Rules.flat(boundary.b).length()>15.5:
   _clear_boundary()
   return
  _line(boundary.node,[boundary.a+Vector3.UP*0.12,boundary.b+Vector3.UP*0.12],Rules.COLORS[2],0.6)
 boundary.left -= delta
 if boundary.left<=0:
  _clear_boundary()
  return
 if moving and not boundary.get("launched",false): return
 hit_color = Rules.COLORS[2]
 var hits:Array = []
 for e in enemies.duplicate():
  if not _live(e) or boundary.seen.has(e.get_instance_id()): continue
  if Rules.segment_distance(Rules.flat(e.position),Rules.flat(boundary.a),Rules.flat(boundary.b))<e.radius+0.3:
   hits.append(e)
 var touched = not hits.is_empty()
 for e in hits:
  boundary.seen.append(e.get_instance_id())
  if e.charging:
   e.redirect(boundary.normal)
   _set_feedback("冲锋已改向：沿箭头冲出",2)
   if is_instance_valid(combat_view): combat_view.hit(e.position,0,Rules.COLORS[2],"改向")
  else: e.apply_impulse(boundary.normal*10.0)
  e.take_hit(24.0 if moving else (14.0 if boundary.extended else 20.0))
  if _live(e) and upgrades.has("slow"): e.add_slow(1.0)
  flash(e.position,Rules.COLORS[2],0.65)
 for projectile in projectiles:
  if projectile.reflected: continue
  if Rules.segment_distance(Rules.flat(projectile.node.position),Rules.flat(boundary.a),Rules.flat(boundary.b))<0.5:
   projectile.direction = boundary.normal
   projectile.reflected = true
   projectile.node.material_override = _material(Rules.COLORS[2])
   touched = true
   _set_feedback("飞弹已偏转：可击中敌人",2)
 if touched:
  boundary.batches += 1
  _sound("gold")
  if boundary.extended and boundary.batches == 1:
   boundary.left = minf(boundary.left,1.2)
  else: _clear_boundary()
 if not boundary.is_empty() and moving and boundary.get("launched",false) and boundary.travel>=boundary.travel_limit:
  _clear_boundary()

func _update_collisions(delta:float)->void:
 for key in collision_guards.keys():
  collision_guards[key] -= delta
  if collision_guards[key]<=0: collision_guards.erase(key)
 var actors:Array = enemies.duplicate()
 for i in range(actors.size()):
  var a = actors[i]
  if not _live(a): continue
  for j in range(i+1,actors.size()):
   if not _live(a): break
   var b = actors[j]
   if not _live(b) or a.position.distance_to(b.position)>a.radius+b.radius: continue
   if not a.charging and not b.charging and a.forced_velocity.length()<0.5 and b.forced_velocity.length()<0.5 and a.pull_velocity.length()<0.5 and b.pull_velocity.length()<0.5: continue
   var key = "%s:%s" % [a.get_instance_id(),b.get_instance_id()]
   if collision_guards.has(key): continue
   var relative:Vector3 = a.velocity-b.velocity
   var separation:Vector3 = Rules.flat(b.position-a.position)
   if separation.length()<0.001 or relative.dot(separation.normalized())<4: continue
   collision_guards[key] = 0.5
   hit_color = Color("f2b37b")
   _set_feedback("撞击：额外伤害，并消耗裂痕破甲",2)
   for e in [a,b]:
    if not _live(e): continue
    var structure = 30.0 if e.crack_time>0 else 20.0
    e.crack_time = 0
    e.take_hit(10,structure)
   flash((a.position+b.position)*0.5,Color("f2b37b"),1.1)

func _update_echoes(delta:float)->void:
 for ev in echo_events.duplicate():
  ev.left -= delta
  if ev.left<=0:
   _red_hit(ev.points,18,14,false)
   _trace(ev.points,Rules.COLORS[0].lightened(0.2),0.09,0.3)
   echo_events.erase(ev)

func create_projectile(origin:Vector3,direction:Vector3,damage:float)->void:
 var node = MeshInstance3D.new()
 var mesh = SphereMesh.new()
 mesh.radius = 0.16
 mesh.height = 0.32
 node.mesh = mesh
 node.material_override = _material(Color("ed7359"))
 add_child(node)
 node.position = Vector3(origin.x,0.7,origin.z)
 projectiles.append({"node":node,"direction":Rules.flat(direction).normalized(),"damage":damage,"left":5.0,"reflected":false})

func _update_projectiles(delta:float)->void:
 for shot in projectiles.duplicate():
  shot.left -= delta
  shot.node.position += shot.direction*7.5*delta
  if shot.reflected:
   for e in enemies.duplicate():
    if _live(e) and Rules.flat(shot.node.position-e.position).length()<e.radius+0.2:
     e.take_hit(shot.damage)
     shot.left = -1
     break
  elif Rules.flat(shot.node.position-player.position).length()<0.55:
   damage_player(shot.damage)
   shot.left = -1
  if shot.left<=0 or shot.node.position.length()>30:
   shot.node.queue_free()
   projectiles.erase(shot)

func damage_player(amount:float)->void:
 if not is_running() or hurt_clock>0 or player.invulnerable: return
 if state == "training":
  hud.toast("训练场保护 · 注意敌方预警")
  hurt_clock = 0.5
  return
 hp = maxf(0,hp-amount)
 hurt_clock = 0.25
 flash(player.position,Color("ff725d"),0.6)
 _sound("hurt")

func enemy_died(enemy)->void:
 if not enemies.has(enemy): return
 cast_kills += 1
 if enemy.kind == "boss": boss_defeated = true
 if state == "battle":
  kills += 1
  if stage<3:
   var cap = [30,45,60][stage]
   var value = {"chaser":1,"charger":3,"armored":5}.get(enemy.kind,0)
   var reward = mini(value,cap-phase_earned)
   coins += reward
   phase_earned += reward
 flash(enemy.position,Rules.COLORS[cloak],0.8)
 enemies.erase(enemy)

func spawn_enemy(kind:String,at:Vector3):
 var e = Enemy.new()
 add_child(e)
 e.setup(self,kind,at)
 enemies.append(e)
 return e

func _spawn_wave()->void:
 var cap = [12,18,24,7][stage]
 if enemies.size()>=cap: return
 wave_serial += 1
 var count = mini(3 if stage<2 else 4,cap-enemies.size())
 var side = float(wave_serial%4)*PI*0.5+randf_range(-0.3,0.3)
 for n in range(count):
  var angle = side+float(n-1)*0.22
  var direction = Vector3(cos(angle),0,sin(angle))
  var at:Vector3 = player.position+direction*randf_range(7.0,8.5)
  if Rules.flat(at).length()>14.0: at = player.position-direction*7.0
  if Rules.flat(at).length()>14.0: at = direction*12.0
  var kind = "chaser"
  if stage<3 and n==0:
   if wave_serial%3==1: kind = "charger"
   elif wave_serial%3==2: kind = "armored"
  var e = spawn_enemy(kind,at)
  e.set_spawn_delay(0.8)
  spawn_warning(at,0.7,Color("df8b80"),0.8)

func start_run(short_run:bool=false)->void:
 _reset_combat()
 duration = 180.0 if short_run else 480.0
 state = "battle"
 hud.hide_panels()
 hud.toast("盛宴开启 · 左键绘制，1 / 2 / 3 切换神权 · H 查看帮助")
 for group in range(2):
  for i in range(3):
   var at = Vector3(-3.2 if group==0 else 3.2,0,-5.8)+Vector3(float(i-1)*1.1,0,float(i%2)*0.45)
   var e = spawn_enemy("chaser",at)
   e.set_spawn_delay(0.8)
   spawn_warning(at,0.7,Color("df8b80"),0.8)
 spawn_clock = 3.0

func start_training()->void:
 _reset_combat()
 state = "training"
 duration = 0
 hud.hide_panels()
 _training_wave()
 hud.toast("训练场 · 不会死亡，不产生货币 · Esc 暂停并选择返回基地")

func _training_wave()->void:
 spawn_clock = 0
 spawn_enemy("chaser",Vector3(-3,0,-3))
 spawn_enemy("chaser",Vector3(-1,0,-4))
 spawn_enemy("charger",Vector3(4,0,-3))
 spawn_enemy("armored",Vector3(2,0,-6))

func _reset_combat()->void:
 cancel_gesture()
 _clear_combat_objects()
 paused = false
 help_visible = false
 hp = 100
 max_hp = 100
 elapsed = 0
 coins = 0
 kills = 0
 earned = 0
 stage = 0
 phase_earned = 0
 upgrades.clear()
 cooldowns.assign([0.0,0.0,0.0])
 boss_defeated = false
 spawn_clock = 0.4
 wave_serial = 0
 message = ""
 feedback_left = 0
 aim.clear()
 hurt_clock = 0
 switch_clock = 0
 cloak = 0
 player.position = Vector3.ZERO
 player.set_cloak(0)
 player.dodge_cooldown = 0
 player.dodge_remaining = 0
 player.cancel_input()
 player.speed_multiplier = 1.0
 yaw = 0

func _clear_combat_objects()->void:
 _clear_link()
 _clear_boundary()
 for e in enemies:
  if is_instance_valid(e): e.queue_free()
 enemies.clear()
 for s in projectiles: s.node.queue_free()
 projectiles.clear()
 for v in visuals:
  if is_instance_valid(v.node): v.node.queue_free()
 visuals.clear()
 echo_events.clear()
 collision_guards.clear()
 if is_instance_valid(combat_view): combat_view.clear_feedback()

func _open_shop()->void:
 cancel_gesture()
 coins += 60
 _award(10)
 state = "shop"
 _clear_combat_objects()
 shop_buys = 0
 offers.clear()
 if stage==0:
  for item in Rules.BRANCHES: offers.append(item.duplicate())
 else:
  var supports:Array = []
  var branches:Array = []
  var commons:Array = []
  for item in Rules.BRANCH_SUPPORTS:
   if upgrades.has(item.requires) and not upgrades.has(item.id): supports.append(item)
  for item in Rules.BRANCHES:
   if not upgrades.has(item.id): branches.append(item)
  for item in Rules.UPGRADES:
   if upgrades.has(item.id): continue
   if item.id=="heal" and hp>=max_hp: continue
   if item.id=="shatter" and stage==2: continue
   if item.id=="linger" and upgrades.has("moving_wall"): continue
   commons.append(item)
  supports.shuffle()
  branches.shuffle()
  commons.shuffle()
  for category in [supports,branches,commons]:
   if not category.is_empty(): offers.append(category.pop_front().duplicate())
  for item in supports+branches+commons:
   if offers.size()>=3: break
   offers.append(item.duplicate())
 hud.show_shop(offers,coins,stage+1)

func buy_upgrade(id:String)->bool:
 if state != "shop" or shop_buys>=2 or coins<60 or upgrades.has(id): return false
 var selected = false
 for item in offers:
  if item.id == id: selected = true
 if not selected: return false
 coins -= 60
 shop_buys += 1
 upgrades.append(id)
 if id == "health":
  max_hp += 20
  hp = minf(max_hp,hp+20)
 if id == "heal": hp = minf(max_hp,hp+25)
 if id == "speed": player.speed_multiplier = 1.08
 for item in offers:
  if item.id == id: item["purchased"] = true
  if shop_buys>=2: item["disabled"] = true
 hud.show_shop(offers,coins,stage+1)
 _sound("buy")
 return true

func continue_from_shop()->void:
 if state != "shop": return
 stage += 1
 phase_earned = 0
 state = "battle"
 hud.hide_panels()
 if stage == 3:
  spawn_enemy("boss",Vector3(0,0,-8))
  hud.toast("老厨子降临 · 读懂预警，利用恢复窗口")
 else: hud.toast("第 %d 轮 · 敌人从侧面接近" % (stage+1))
 _spawn_wave()

func _finish_run(won:bool,reason:String)->void:
 if state != "battle": return
 state = "result"
 paused = false
 cancel_gesture()
 if won: _award(30)
 var next = progress.duplicate(true)
 next.total_runs = int(next.get("total_runs",0))+1
 if won: next.wins = int(next.get("wins",0))+1
 if store.save_data(next): progress = next
 else: hud.toast("保存失败：请检查存储空间，本次统计未写入")
 hud.show_result({"won":won,"reason":reason,"time":elapsed,"kills":kills,"earned":earned,"essence":progress.essence})
 coins = 0
 upgrades.clear()

func _award(amount:int)->bool:
 var next = progress.duplicate(true)
 next.essence = int(next.essence)+amount
 if not store.save_data(next):
  hud.toast("残纱保存失败，本次奖励尚未写入")
  return false
 progress = next
 earned += amount
 return true

func return_to_base()->void:
 if state == "battle":
  _finish_run(false,"主动离开盛宴")
 _reset_combat()
 state = "base"
 hud.show_base(progress)

func purchase_relic(id:String)->bool:
 if state != "base" or not Rules.RELICS.has(id) or progress.unlocked.has(id): return false
 var cost:int = Rules.RELICS[id]
 if progress.essence<cost:
  hud.toast("残纱不足 · 完成战斗阶段可获得残纱")
  return false
 var next = progress.duplicate(true)
 next.essence -= cost
 next.unlocked.append(id)
 if not store.save_data(next):
  hud.toast("保存失败，未扣除残纱")
  return false
 progress = next
 hud.show_base(progress)
 _sound("buy")
 return true

func toggle_relic(id:String)->void:
 if state != "base" or not progress.unlocked.has(id): return
 var next = progress.duplicate(true)
 if id == "tri_weave": next.resonance = not next.resonance
 else:
  var slot = ["red_echo","blue_flow","gold_linger"].find(id)
  if slot<0: return
  next.equipped[slot] = "" if next.equipped[slot] == id else id
 if store.save_data(next):
  progress = next
  hud.show_base(progress)
 else: hud.toast("装配保存失败")

func _equipped(id:String)->bool:
 var slot = ["red_echo","blue_flow","gold_linger"].find(id)
 if slot>=0 and upgrades.has(Rules.BRANCH_IDS[slot]): return false
 return progress.get("equipped",[]).has(id)

func toggle_pause()->void:
 if state == "base" and help_visible:
  help_visible = false
  hud.show_help(false)
  return
 if state != "battle" and state != "training": return
 cancel_gesture()
 rotating = false
 help_visible = false
 paused = not paused
 hud.show_help(false)
 hud.show_pause(paused)

func toggle_help()->void:
 if state == "base":
  help_visible = not help_visible
  hud.show_help(help_visible)
  return
 if state != "battle" and state != "training": return
 cancel_gesture()
 help_visible = not help_visible
 paused = help_visible
 hud.show_pause(false)
 hud.show_help(help_visible)

func _notification(what:int)->void:
 if what == NOTIFICATION_WM_CLOSE_REQUEST:
  _quit_cleanly()
 if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_running() and not auto_play:
  toggle_pause()

func _update_status()->void:
 if hud == null: return
 var boss_hp = -1.0
 for e in enemies:
  if _live(e) and e.kind == "boss": boss_hp = e.hp
 hud.update_status({"hp":hp,"max_hp":max_hp,"cloak":cloak,"cooldowns":cooldowns,"elapsed":elapsed,"duration":duration,"coins":coins,"stage":stage,"enemies":enemies.size(),"link_left":link.get("left",0.0),"boundary_left":boundary.get("left",0.0),"mode":state,"dodge_cooldown":player.dodge_cooldown,"message":message,"boss_hp":boss_hp,"aim":aim,"cooldown_totals":[_spell_cooldown(0),_spell_cooldown(1),_spell_cooldown(2)]})

func _live(e)->bool:
 return is_instance_valid(e) and not e.dead and not e.is_queued_for_deletion()

func _nearest_enemy(point:Vector3,limit:float):
 var result = null
 var best = limit
 for e in enemies:
  if not _live(e): continue
  var d = Rules.flat(e.position-point).length()
  if d<best+e.radius*0.3:
   best = d
   result = e
 return result

func _path_length(points:Array[Vector3])->float:
 var result = 0.0
 for i in range(points.size()-1): result += points[i].distance_to(points[i+1])
 return result

func _clear_link()->void:
 for key in ["a","b"]:
  if link.has(key) and _live(link[key]): link[key].set_pull_velocity(Vector3.ZERO)
 if link.has("node") and is_instance_valid(link.node): link.node.queue_free()
 link = {}

func _clear_boundary()->void:
 if boundary.has("node") and is_instance_valid(boundary.node): boundary.node.queue_free()
 boundary = {}

func _material(color:Color)->StandardMaterial3D:
 var m = StandardMaterial3D.new()
 m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 m.albedo_color = color
 m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 m.cull_mode = BaseMaterial3D.CULL_DISABLED
 m.no_depth_test = false
 return m

func _line(node:MeshInstance3D,points:Array,color:Color,width:float)->void:
 if points.size()<2: return
 var mesh = ImmediateMesh.new()
 mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in range(points.size()-1):
  var a:Vector3 = points[i]
  var b:Vector3 = points[i+1]
  var side = (b-a).cross(Vector3.UP).normalized()*width*0.5
  for p in [a-side,a+side,b+side,a-side,b+side,b-side]: mesh.surface_add_vertex(p)
 mesh.surface_end()
 node.mesh = mesh
 if node.material_override == null: node.material_override = _material(color)
 else: node.material_override.albedo_color = color

func _draw_preview()->void:
 _refresh_aim()

func _trace(points:Array,color:Color,width:float,life:float)->void:
 var node = MeshInstance3D.new()
 add_child(node)
 var raised:Array = []
 for p in points: raised.append(p+Vector3.UP*0.22)
 _line(node,raised,color,width)
 visuals.append({"node":node,"left":life,"total":life,"grow":false})

func _arrow(center:Vector3,direction:Vector3,color:Color,life:float)->void:
 _trace([center,center+direction*1.2],color,0.12,life)

func flash(at:Vector3,color:Color,size:float=1.0)->void:
 var node = MeshInstance3D.new()
 var mesh = TorusMesh.new()
 mesh.inner_radius = 0.75
 mesh.outer_radius = 1.0
 mesh.rings = 16
 mesh.ring_segments = 8
 node.mesh = mesh
 node.material_override = _material(color)
 add_child(node)
 node.position = Vector3(at.x,maxf(0.13,at.y),at.z)
 node.scale = Vector3.ONE*size*0.4
 visuals.append({"node":node,"left":0.32,"total":0.32,"grow":true})

func spawn_warning(at:Vector3,radius:float,color:Color,life:float)->void:
 var points:Array = []
 for i in range(49): points.append(at+Vector3(cos(i*TAU/48.0)*radius,0.1,sin(i*TAU/48.0)*radius))
 _trace(points,color,0.075,life)

func _update_visuals(delta:float)->void:
 for v in visuals.duplicate():
  v.left -= delta
  if not is_instance_valid(v.node):
   visuals.erase(v)
   continue
  if v.left<=0:
   v.node.queue_free()
   visuals.erase(v)
   continue
  if v.grow: v.node.scale += Vector3.ONE*delta*2.5
  if v.node.material_override != null:
   var c:Color = v.node.material_override.albedo_color
   c.a = clampf(v.left/v.total,0,1)
   v.node.material_override.albedo_color = c

func _setup_audio()->void:
 # Dedicated headless checks have no audible output or audio-playback contract.
 if DisplayServer.get_name() == "headless": return
 for i in range(8):
  var a = AudioStreamPlayer.new()
  a.volume_db = -16
  add_child(a)
  sound_players.append(a)
 if ResourceLoader.exists("res://assets/audio/ambience.wav"):
  ambience = AudioStreamPlayer.new()
  ambience.stream = load("res://assets/audio/ambience.wav")
  ambience.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
  ambience.stream.loop_end = ambience.stream.mix_rate*8
  ambience.volume_db = -29
  add_child(ambience)
  ambience.play()

func _sound(id:String)->void:
 var res = "res://assets/audio/%s.wav" % id
 if sound_players.is_empty() or not ResourceLoader.exists(res): return
 var a:AudioStreamPlayer = sound_players[sound_index%sound_players.size()]
 sound_index += 1
 a.stream = load(res)
 a.play()

func _quit_cleanly()->void:
 if closing: return
 closing = true
 paused = true
 cancel_gesture()
 _stop_audio()
 # Give the audio mixer time to release queued WAV playbacks before shutdown.
 await get_tree().create_timer(0.15).timeout
 get_tree().quit()

func _exit_tree()->void:
 _stop_audio()

func _stop_audio()->void:
 if is_instance_valid(ambience):
  ambience.stop()
  ambience.stream = null
 for a in sound_players:
  if is_instance_valid(a):
   a.stop()
   a.stream = null

func _auto_step(delta:float)->void:
 hp = max_hp
 if auto_clock>0 or enemies.is_empty(): return
 auto_clock = 0.6
 var target = enemies[0]
 if not _live(target): return
 var d:Vector3 = target.position-player.position
 if d.length()>6: player.position += d.normalized()*delta*20
 var pts:Array[Vector3] = [target.position+Vector3(-1,0,0),target.position+Vector3(1,0,0)]
 var which = int(elapsed*1.7)%3
 switch_cloak(which)
 if which == 1:
  pts.assign([target.position+Vector3(0,0,2),target.position])
  cast_spell(1,pts,null,target)
 else: cast_spell(which,pts)

func _stroke_limit(index:int)->float:
 if index==0: return 4.0 if upgrades.has("short_cut") else 8.0
 if index==1: return 10.0 if upgrades.has("reach") else 8.0
 return 8.0 if upgrades.has("length") else 6.0

func _spell_cooldown(index:int)->float:
 if upgrades.has(Rules.BRANCH_IDS[index]): return [0.65,2.0,2.2][index]
 return Rules.COOLDOWNS[index]

func _gesture_points()->Array[Vector3]:
 var points:Array[Vector3] = path.duplicate()
 if points.is_empty(): return points
 if cloak==0:
  if points[-1].distance_to(pointer)>0.001: points.append(pointer)
 else: points.assign([points[0],pointer])
 return points

func get_cast_check(index:int,points:Array[Vector3],a=null,b=null)->Dictionary:
 var result = {"valid":false,"reason":"请按住左键画出一条线","hits":[],"targets":[],"points":points.duplicate(),"width":0.7,"length":0.0,"limit":0.0,"normal":Vector3.ZERO}
 if index<0 or index>2: return result
 result.limit = _stroke_limit(index)
 result.width = (0.95 if upgrades.has("wide") else 0.7) if index==0 else (0.12 if index==1 else 0.6)
 if points.size()<2: return result
 var actual:Array[Vector3] = points.duplicate()
 if index==1:
  if (a!=null and not _live(a)) or (b!=null and not _live(b)):
   result.reason = "连接目标已经离开"
   return result
  if a==null and b==null:
   result.reason = "至少一端要落在敌人身上"
   return result
  if a!=null and a==b:
   result.reason = "不能把同一个敌人连到自己"
   return result
  if _equipped("blue_flow") and b==null:
   result.reason = "单向拉：从地面或敌人画向敌人"
   return result
  actual.assign([a.position if a!=null else points[0],b.position if b!=null else points[-1]])
 result.points = actual
 result.length = _path_length(actual) if index==0 else actual[0].distance_to(actual[-1])
 for point in actual:
  if Rules.flat(point-player.position).length()>8.05:
   result.reason = "超出施法圆圈：目标必须在 8 米内"
   return result
 var minimum:float = [0.35,0.3,0.5][index]
 if result.length<minimum:
  result.reason = "线太短：拖动鼠标后再松开"
  return result
 if result.length>result.limit+0.05:
  result.reason = "超过当前攻击的长度上限"
  return result
 result.valid = true
 result.reason = ""
 var hits:Array = []
 if index==1:
  if _live(a): hits.append(a)
  if _live(b): hits.append(b)
 else:
  if index==2: result.normal = Rules.boundary_normal(actual[0],actual[-1])
  if not (index==2 and upgrades.has("moving_wall")):
   for e in enemies:
    if not _live(e): continue
    for i in range(actual.size()-1):
     if Rules.segment_distance(Rules.flat(e.position),Rules.flat(actual[i]),Rules.flat(actual[i+1]))<e.radius+result.width*0.5:
      hits.append(e)
      break
 result.hits = hits
 result.targets = hits
 return result

func _refresh_aim()->void:
 if not is_instance_valid(combat_view): return
 var points:Array[Vector3] = []
 if drawing: points = _gesture_points()
 var b = _nearest_enemy(pointer,1.15) if cloak==1 else null
 var check = get_cast_check(cloak,points,first_target,b)
 var near = _nearest_enemy(pointer,0.9)
 var ready = cooldowns[cloak]<=0 and switch_clock<=0 and player.dodge_remaining<=0
 var valid:bool = check.valid if drawing else Rules.flat(pointer-player.position).length()<=8.05
 var reason:String = check.reason if drawing else ("" if valid else "从圆圈内开始画线")
 if drawing and valid and draw_clipped: reason = "已限制在有效长度内，松开释放"
 var targets:Array = check.hits if drawing else ([near] if _live(near) and valid else [])
 var title:String = Rules.CLOAKS[cloak]
 var secondary:String = ""
 var secondary_ready:bool = false
 var hints:Array = ["让攻击带穿过敌人，松开切割","至少连接一个敌人，松开拉近两端","沿箭头推开敌人；反向画线会反向推开"]
 if upgrades.has("short_cut") and cloak==0:
  title = "绯月 · 短切"
  hints[0] = "最长 4 米，伤害较低，0.65 秒可再切"
 if upgrades.has("snap_link") and cloak==1:
  title = "星汐 · 收线"
  hints[1] = "先连住敌人，再按右键收线造成第二次伤害"
  if not link.is_empty() and link.get("snap",false):
   reason = "右键收线已就绪" if float(link.get("age",0))>=0.25 else "连线正在拉紧"
   secondary = "收线"
   secondary_ready = float(link.get("age",0))>=0.25
 if upgrades.has("moving_wall") and cloak==2:
  title = "圣棘 · 推墙"
  hints[2] = "先画线布置，再按右键沿箭头推出"
  if drawing: reason = "布置时不伤害；右键推进后接触生效" if valid else reason
  elif not boundary.is_empty() and not boundary.get("launched",false):
   reason = "待发剩余 %.1f 秒 · 沿箭头推进后接触生效" % boundary.left
   secondary = "推出"
   secondary_ready = true
 if state=="training": hints[cloak] += " · Q 试用/退出分支"
 aim = {"title":title,"hint":hints[cloak],"valid":valid,"reason":reason,"targets":targets.size(),"target_name":Rules.ENEMY_NAMES.get(near.kind,"") if _live(near) else "","length":check.length,"limit":check.limit,"drawing":drawing,"feedback":message,"ready":ready}
 aim.secondary = secondary if not drawing else ""
 aim.secondary_ready = secondary_ready
 var pending_wall:Dictionary = {}
 if not boundary.is_empty() and boundary.get("moving",false) and not boundary.get("launched",false):
  pending_wall = {"points":[boundary.a,boundary.b],"normal":boundary.normal,"travel":boundary.travel_limit}
 combat_view.present({"active":state in ["battle","training"] and not paused,"range":8.0,"player":player.position,"pointer":pointer,"cloak":cloak,"drawing":drawing,"valid":valid and ready,"points":check.points,"width":check.width,"targets":targets,"normal":check.normal,"directed":_equipped("blue_flow"),"travel":(4.0 if upgrades.has("wall_travel") else 2.5) if upgrades.has("moving_wall") else 0.0,"pending_wall":pending_wall})

func _set_feedback(text:String,priority:int=0)->void:
 if feedback_left>0.8 and priority<feedback_priority: return
 message = text
 feedback_priority = priority
 feedback_left = 2.2

func hit_feedback(enemy,damage:float,armor_broken:bool,killed:bool)->void:
 if not is_running(): return
 var caption = "破甲" if armor_broken else ("击倒" if killed else "")
 if is_instance_valid(combat_view):
  combat_view.hit(enemy.position,damage,hit_color,caption)
  if killed or armor_broken: combat_view.burst(enemy.position,hit_color,1.0)
 if armor_broken: _set_feedback("%s的护甲碎了：现在更容易拉动" % Rules.ENEMY_NAMES.get(enemy.kind,"敌人"),2)
 elif killed: _set_feedback("击倒%s" % Rules.ENEMY_NAMES.get(enemy.kind,"敌人"),0)

func toggle_training_branch()->bool:
 if state!="training" or paused or drawing: return false
 var id:String = Rules.BRANCH_IDS[cloak]
 var support:String = ["short_rebate","snap_gather","wall_travel"][cloak]
 if upgrades.has(id):
  upgrades.erase(id)
  upgrades.erase(support)
  _set_feedback("当前斗篷恢复基地配置",1)
 else:
  upgrades.append(id)
  _set_feedback("试用%s：%s" % [Rules.BRANCHES[cloak].title,Rules.BRANCHES[cloak].description],1)
 if cloak==1: _clear_link()
 if cloak==2: _clear_boundary()
 _refresh_aim()
 return true

func secondary_action()->bool:
 if not is_running(): return false
 if drawing:
  cancel_gesture()
  return false
 if cloak==1 and not link.is_empty() and link.get("snap",false):
  if float(link.get("age",0))<0.25:
   _set_feedback("连线尚未拉紧，请稍后收线",1)
   return false
  var endpoints:Array = []
  for e in [link.a,link.b]:
   if _live(e): endpoints.append(e)
  var p:Vector3 = link.a.position if _live(link.a) else link.p
  var q:Vector3 = link.b.position if _live(link.b) else link.q
  var center:Vector3 = (p+q)*0.5
  var gathered:Array = []
  if upgrades.has("snap_gather"):
   for e in endpoints:
    var nearest = null
    var distance = 2.0
    for other in enemies:
     if not _live(other) or endpoints.has(other) or gathered.has(other): continue
     var d:float = other.position.distance_to(e.position)
     if d<distance:
      distance = d
      nearest = other
    if nearest!=null:
     nearest.apply_impulse((e.position-nearest.position).normalized()*3.5)
     gathered.append(nearest)
  _clear_link()
  hit_color = Rules.COLORS[1]
  for e in endpoints:
   if not _live(e): continue
   e.apply_impulse((center-e.position).normalized()*5.0)
   e.take_hit(24)
  if is_instance_valid(combat_view): combat_view.cast([p,q],Rules.COLORS[1],0.3)
  _set_feedback("收线命中 %d 个端点 · 连接已结束" % endpoints.size(),1)
  _sound("blue")
  player.play_cast(center)
  return true
 if cloak==2 and not boundary.is_empty() and boundary.get("moving",false) and not boundary.get("launched",false):
  boundary.launched = true
  boundary.left = float(boundary.travel_limit)/6.0+0.1
  _set_feedback("边界正在沿箭头推进：命中一批后消失",1)
  _sound("gold_launch")
  player.play_cast((boundary.a+boundary.b)*0.5+boundary.normal)
  return true
 return false
