# Vertical slice implementation contract

Godot 4.6.3, GDScript, Compatibility renderer. Ground XZ, Y up, walkable radius 15. Main creates all nodes at runtime. Avoid global class_name dependencies. Preload scripts. Dynamic `var game`; avoid inferred := on dynamic calls.

## Ownership
- Root: project.godot, main.tscn, scripts/main.gd, scripts/rules.gd, effects, tests/exports.
- Actors: scripts/player.gd and scripts/enemy.gd.
- Presentation: scripts/world.gd, assets/models/*, ../tools/build_models.py.
- Interface: scripts/hud.gd, scripts/progress_store.gd.

## Main shared API
Fields: state:String (base,battle,training,shop,result), paused:bool, player:Node3D, enemies:Array, camera:Camera3D, cloak:int (0/1/2), hp:float, max_hp:float, cooldowns:Array[float], elapsed:float, coins:int, stage:int, progress:Dictionary, upgrades:Array.
Methods for actors: is_running()->bool, damage_player(amount:float), enemy_died(enemy), create_projectile(origin:Vector3,direction:Vector3,damage:float), spawn_warning(position:Vector3,radius:float,color:Color,duration:float), flash(position:Vector3,color:Color,size:float=1.0), cancel_gesture().

## Player
player.gd extends Node3D. setup(owner_game) after add_child. Controls WASD camera-relative, radius15 clamp and space dodge. Fields dodge_remaining:float, dodge_cooldown:float, invulnerable:bool. Methods set_cloak(index:int), play_cast(), play_switch(), cancel_input(). Health is main.hp. Dodge cancels gesture through main.cancel_gesture(). All movement checks game.is_running(); menu can animate character. Model path assets/models/player.glb if present; otherwise low-poly fallback. Root handles 1/2/3 switching.

## Enemy
enemy.gd extends Node3D. setup(owner_game,kind:String,at:Vector3), kinds chaser/charger/armored/boss. Fields kind:String,hp:float,armor:float,dead:bool,velocity:Vector3,forced_velocity:Vector3,crack_time:float,charging:bool,radius:float. Methods take_hit(damage:float,structure_damage:float=0.0,apply_crack:bool=false), apply_impulse(v:Vector3), redirect(direction:Vector3), interrupt_charge(), add_slow(seconds:float). Handles AI, visual, melee and boss3 moves; reports death via game.enemy_died(self) exactly once before queue_free; set dead before callback. _physics_process checks game.is_running(). Main handles spell interaction.

## World
world.gd extends Node3D. build() after added; set_threat(value:float) optional. Creates polished dark gothic arena +/-18, walkable radius15, ruins/candles/ritual floor, WorldEnvironment and lights. No camera/colliders. Optional player.glb: feet origin, height1.8m, Y up in glTF. Communicate mesh names for cloak recoloring.

## HUD
hud.gd extends CanvasLayer. setup(owner_game), show_base(progress:Dictionary), show_shop(offers:Array,coins:int,stage:int), show_result(info:Dictionary), show_pause(visible:bool), update_status(data:Dictionary), toast(text:String), hide_panels().
status dictionary: hp,max_hp,cloak,cooldowns,elapsed,duration,coins,stage,enemies,link_left,boundary_left,mode,dodge_cooldown,message.
offers: {id,title,description,cost}; result: {won,reason,time,kills,earned,essence}.
Buttons call main.start_run(short_run:bool=false),start_training(),return_to_base(),buy_upgrade(id:String),continue_from_shop(),purchase_relic(id:String),toggle_relic(id:String),toggle_pause(),toggle_help(). Chinese UI. Main updates every frame; do not rebuild controls per frame. Font assets/fonts/ui.ttf supplied by root.

## Persistence
progress_store.gd extends RefCounted. load_data()->Dictionary; save_data(data:Dictionary)->bool. Defaults {version:1,essence:0,unlocked:[],equipped:["","",""],resonance:false,total_runs:0,wins:0,settings:{sound:true}}. IDs red_echo/blue_flow/gold_linger/tri_weave, costs30/30/30/60. Atomic temp write + backup; preserve corrupt files, try backup. No mid-run save. Root manages transactions.
