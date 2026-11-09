extends Node3D
## Presentation only: never decides hits, damage, target eligibility or range.
## `width` is the full mechanical width, not a radius. Geometry depth-tests normally.

const COLORS = [Color("e14b79"),Color("9c86f5"),Color("efcc7d")]
const INVALID = Color("ed786f")
const MAX_FEEDBACK:int = 32
const MAX_TARGETS:int = 16
const FLOOR_Y:float = 0.125
const INK_Y:float = 0.145

var game
var _ready_view:bool = false
var _range_node:MeshInstance3D
var _fill_node:MeshInstance3D
var _ink_node:MeshInstance3D
var _range_mesh:ImmediateMesh
var _fill_mesh:ImmediateMesh
var _ink_mesh:ImmediateMesh
var _font:Font
var _travel_label:Label3D
var _feedback:Array = []
var _sequence:int = 0
var _range_value:float = -1.0
var _range_color:Color = Color.TRANSPARENT
var _clock:float = 0.0

func setup(owner_game)->void:
 game = owner_game
 if _ready_view: return
 _ready_view = true
 name = "CombatReadability"
 _range_mesh = ImmediateMesh.new()
 _fill_mesh = ImmediateMesh.new()
 _ink_mesh = ImmediateMesh.new()
 _range_node = _preview_node("CastRange",_range_mesh)
 _fill_node = _preview_node("Coverage",_fill_mesh)
 _ink_node = _preview_node("EdgesAndDirections",_ink_mesh)
 if ResourceLoader.exists("res://assets/fonts/ui.ttf"):
  _font = load("res://assets/fonts/ui.ttf")
 _travel_label = Label3D.new()
 _travel_label.name = "TravelDestination"
 if _font != null: _travel_label.font = _font
 _travel_label.font_size = 32
 _travel_label.pixel_size = 0.011
 _travel_label.outline_size = 5
 _travel_label.modulate = COLORS[2].lightened(0.15)
 _travel_label.outline_modulate = Color(0.035,0.025,0.055,0.9)
 _travel_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 _travel_label.no_depth_test = false
 _travel_label.shaded = false
 _travel_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 _travel_label.hide()
 add_child(_travel_label)

func present(data:Dictionary)->void:
 if not _ready_view: setup(game)
 var active:bool = bool(data.get("active",false))
 _range_node.visible = active
 _fill_node.visible = active
 _ink_node.visible = active
 _travel_label.hide()
 if not active: return
 var player_at:Vector3 = data.get("player",Vector3.ZERO)
 var pointer_at:Vector3 = data.get("pointer",player_at)
 var cloak:int = clampi(int(data.get("cloak",0)),0,2)
 var drawing:bool = bool(data.get("drawing",false))
 var valid:bool = bool(data.get("valid",true))
 var radius:float = maxf(0.1,float(data.get("range",8.0)))
 var width:float = clampf(float(data.get("width",0.7)),0.03,2.0)
 var color:Color = COLORS[cloak]
 var points:Array[Vector3] = []
 for point in data.get("points",[]):
  if point is Vector3: points.append(_floor(point,FLOOR_Y))

 _update_range(player_at,radius,_alpha(color,0.25 if drawing else 0.15))
 var fill_vertices = PackedVector3Array()
 var fill_colors = PackedColorArray()
 var ink_vertices = PackedVector3Array()
 var ink_colors = PackedColorArray()
 var pointer_in_range:bool = Vector2(pointer_at.x-player_at.x,pointer_at.z-player_at.z).length()<=radius
 var pointer_color:Color = color if valid and pointer_in_range else INVALID
 _reticle(ink_vertices,ink_colors,pointer_at,_alpha(pointer_color,0.88),valid and pointer_in_range)

 if drawing and points.size()>=2:
  if not valid: color = INVALID
  if cloak == 1:
   _blue_preview(points,color,valid,bool(data.get("directed",false)),fill_vertices,fill_colors,ink_vertices,ink_colors)
  else:
   _ribbon(fill_vertices,fill_colors,ink_vertices,ink_colors,points,width,color,valid)
   if cloak == 2 and valid:
    _wall_guide(points,data.get("normal",Vector3.ZERO),width,float(data.get("travel",0.0)),color,ink_vertices,ink_colors)
  if not valid:
   _cross(ink_vertices,ink_colors,points[-1],0.25,_alpha(INVALID,0.95))

 # Placed walls retain their direction and destination until launch or expiry,
 # including after switching cloaks. A newly drawn gold line takes visual priority.
 var pending:Dictionary = data.get("pending_wall",{})
 if not pending.is_empty() and not (drawing and cloak==2):
  var placed:Array[Vector3] = []
  for point in pending.get("points",[]):
   if point is Vector3: placed.append(_floor(point,FLOOR_Y))
  if placed.size()>=2:
   _wall_guide(placed,pending.get("normal",Vector3.ZERO),0.6,float(pending.get("travel",0.0)),COLORS[2],ink_vertices,ink_colors)

 var marked:int = 0
 for target in data.get("targets",[]):
  if marked>=MAX_TARGETS: break
  if not is_instance_valid(target) or not target is Node3D or target.is_queued_for_deletion(): continue
  var target_radius:float = 0.45
  var raw_radius = target.get("radius")
  if raw_radius is float or raw_radius is int:
   target_radius = clampf(float(raw_radius),0.25,1.6)
  var target_at:Vector3 = target.global_position
  var target_color:Color = color if valid else INVALID
  _ring(ink_vertices,ink_colors,target_at,target_radius+0.12,0.045,_alpha(target_color,0.92),not valid,28)
  if valid:
   # Four short inward marks distinguish a confirmed target from a floor endpoint.
   for i in range(4):
    var direction = Vector3(cos(i*PI*0.5),0,sin(i*PI*0.5))
    _segment(ink_vertices,ink_colors,target_at+direction*(target_radius+0.13),target_at+direction*(target_radius+0.30),0.042,_alpha(target_color,0.92),INK_Y)
  else:
   _cross(ink_vertices,ink_colors,target_at,target_radius*0.4,_alpha(INVALID,0.8))
  marked += 1
 _upload(_fill_mesh,fill_vertices,fill_colors)
 _upload(_ink_mesh,ink_vertices,ink_colors)

func _wall_guide(points:Array[Vector3],normal:Vector3,width:float,travel:float,color:Color,ink_vertices:PackedVector3Array,ink_colors:PackedColorArray)->void:
 normal = Vector3(normal.x,0,normal.z).normalized()
 if normal.length_squared()>0.5:
  var line_length:float = points[0].distance_to(points[-1])
  var arrows:int = clampi(int(ceil(line_length/1.3)),1,7)
  for i in range(arrows):
   var t:float = (float(i)+0.5)/float(arrows)
   var center:Vector3 = points[0].lerp(points[-1],t)
   _arrow(ink_vertices,ink_colors,center+normal*(width*0.5+0.08),normal,0.68,_alpha(color,0.78))
  # Advancing walls show a destination and travel guide, never a filled swept hit area.
  travel = clampf(travel,0.0,8.0)
  if travel>0.01:
   var end_a:Vector3 = points[0]+normal*travel
   var end_b:Vector3 = points[-1]+normal*travel
   var origin:Vector3 = points[0].lerp(points[-1],0.5)
   var destination:Vector3 = origin+normal*travel
   _path_segments(ink_vertices,ink_colors,[end_a,end_b],0.032,_alpha(color,0.48),true)
   _path_segments(ink_vertices,ink_colors,[origin+normal*(width*0.5+0.2),destination],0.021,_alpha(color,0.36),true)
   _arrow(ink_vertices,ink_colors,destination-normal*0.55,normal,0.48,_alpha(color,0.68))
   for end in [end_a,end_b]:
    _segment(ink_vertices,ink_colors,end-normal*0.12,end+normal*0.12,0.03,_alpha(color,0.55),INK_Y)
   _travel_label.text = "推进终点 %.1f m" % travel
   _travel_label.position = _floor(destination+normal*0.4,0.45)
   _travel_label.show()

func hit(at:Vector3,amount:float,color:Color,caption:String="")->void:
 if not _ready_view: setup(game)
 if amount<=0 and caption.is_empty(): return
 # Rapid same-position hits share a label instead of covering one another.
 for entry in _feedback:
  if entry.kind != "number" or entry.total-entry.left>0.075: continue
  if entry.origin.distance_to(at)>0.45 or entry.caption!=caption: continue
  entry.amount += amount
  entry.node.text = _hit_text(entry.amount,caption)
  return
 _reserve_feedback()
 var label = Label3D.new()
 label.name = "HitFeedback"
 label.text = _hit_text(amount,caption)
 if _font != null: label.font = _font
 label.font_size = 48 if caption.is_empty() else 42
 label.outline_size = 7
 label.pixel_size = 0.012
 label.modulate = color.lightened(0.25)
 label.outline_modulate = Color(0.035,0.025,0.055,0.95)
 label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 label.no_depth_test = false
 label.shaded = false
 label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(label)
 var side:float = float((_sequence%3)-1)*0.19
 label.position = at+Vector3(side,1.75+float(_sequence%2)*0.16,0)
 _sequence += 1
 _feedback.append({"kind":"number","node":label,"left":0.76,"total":0.76,"origin":at,"amount":amount,"caption":caption,"color":label.modulate,"velocity":Vector3(side*0.5,0.74,0)})

func burst(at:Vector3,color:Color,size:float=1.0)->void:
 if not _ready_view: setup(game)
 _reserve_feedback()
 size = clampf(size,0.25,1.8)
 var vertices = PackedVector3Array()
 var colors = PackedColorArray()
 # Five tiny radial fragments share one mesh and one lifetime; no screen flash.
 for i in range(5):
  var angle:float = float(i)*TAU/5.0+float(_sequence)*0.73
  var direction = Vector3(cos(angle),0,sin(angle))
  var tangent = direction.cross(Vector3.UP)
  var center = direction*size*0.17+Vector3.UP*(0.05+float(i%3)*0.06)
  var tip = center+direction*size*0.10+Vector3.UP*size*0.08
  var left = center-tangent*size*0.025
  var right = center+tangent*size*0.025
  _triangle(vertices,colors,tip,left,right,_alpha(color,0.88))
  _triangle(vertices,colors,center-direction*size*0.07,right,left,_alpha(color.lightened(0.25),0.75))
 var mesh = ImmediateMesh.new()
 _upload(mesh,vertices,colors)
 var node = MeshInstance3D.new()
 node.mesh = mesh
 node.material_override = _vertex_material()
 node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(node)
 node.position = at+Vector3.UP*0.25
 _feedback.append({"kind":"burst","node":node,"left":0.28,"total":0.28,"velocity":Vector3(0,0.35,0),"scale":1.0})
 _sequence += 1

func cast(points:Array,color:Color,width:float)->void:
 if not _ready_view: setup(game)
 var clean:Array[Vector3] = []
 for point in points:
  if point is Vector3: clean.append(_floor(point,FLOOR_Y))
 if clean.size()<2: return
 _reserve_feedback()
 var vertices = PackedVector3Array()
 var colors = PackedColorArray()
 var ink_vertices = PackedVector3Array()
 var ink_colors = PackedColorArray()
 _ribbon(vertices,colors,ink_vertices,ink_colors,clean,clampf(width,0.03,2.0),color,true)
 vertices.append_array(ink_vertices)
 colors.append_array(ink_colors)
 var mesh = ImmediateMesh.new()
 _upload(mesh,vertices,colors)
 var node = MeshInstance3D.new()
 node.mesh = mesh
 node.material_override = _vertex_material()
 node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(node)
 _feedback.append({"kind":"cast","node":node,"left":0.24,"total":0.24,"velocity":Vector3.ZERO})

func clear_feedback()->void:
 for entry in _feedback:
  if is_instance_valid(entry.node):
   entry.node.hide()
   entry.node.queue_free()
 _feedback.clear()
 if _ready_view:
  _fill_mesh.clear_surfaces()
  _ink_mesh.clear_surfaces()
  _range_node.hide()
  _fill_node.hide()
  _ink_node.hide()
  _travel_label.hide()

func feedback_count()->int:
 return _feedback.size()

func _process(delta:float)->void:
 if game == null or not is_instance_valid(game) or not game.is_running(): return
 _clock += delta
 for entry in _feedback.duplicate():
  if not is_instance_valid(entry.node):
   _feedback.erase(entry)
   continue
  entry.left -= delta
  if entry.left<=0:
   entry.node.hide()
   entry.node.queue_free()
   _feedback.erase(entry)
   continue
  var fraction:float = clampf(entry.left/entry.total,0.0,1.0)
  entry.node.position += entry.velocity*delta
  if entry.kind == "number":
   var tint:Color = entry.color
   tint.a *= minf(1.0,fraction*2.2)
   entry.node.modulate = tint
   entry.node.outline_modulate = Color(0.035,0.025,0.055,0.95*minf(1.0,fraction*2.2))
  else:
   var material:StandardMaterial3D = entry.node.material_override
   material.albedo_color.a = fraction
   if entry.kind == "burst":
    entry.node.scale = Vector3.ONE*(1.0+(1.0-fraction)*2.2)

func _reserve_feedback()->void:
 while _feedback.size()>=MAX_FEEDBACK:
  var oldest:Dictionary = _feedback.pop_front()
  if is_instance_valid(oldest.node):
   oldest.node.hide()
   oldest.node.queue_free()

func _hit_text(amount:float,caption:String)->String:
 var value:String = str(maxi(1,roundi(amount))) if amount>0 else ""
 if caption.is_empty(): return value
 if value.is_empty(): return caption
 return value+"  "+caption

func _preview_node(node_name:String,mesh:ImmediateMesh)->MeshInstance3D:
 var node = MeshInstance3D.new()
 node.name = node_name
 node.mesh = mesh
 node.material_override = _vertex_material()
 node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(node)
 return node

func _vertex_material()->StandardMaterial3D:
 var material = StandardMaterial3D.new()
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 material.vertex_color_use_as_albedo = true
 material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 material.cull_mode = BaseMaterial3D.CULL_DISABLED
 material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
 material.no_depth_test = false
 material.albedo_color = Color.WHITE
 return material

func _update_range(at:Vector3,radius:float,color:Color)->void:
 _range_node.position = Vector3(at.x,0,at.z)
 if is_equal_approx(radius,_range_value) and color.is_equal_approx(_range_color): return
 _range_value = radius
 _range_color = color
 var vertices = PackedVector3Array()
 var colors = PackedColorArray()
 _ring(vertices,colors,Vector3.ZERO,radius,0.026,color,false,96)
 for i in range(8):
  var direction = Vector3(cos(i*TAU/8.0),0,sin(i*TAU/8.0))
  _segment(vertices,colors,direction*(radius-0.13),direction*(radius+0.13),0.03,_alpha(color,0.28),INK_Y)
 _upload(_range_mesh,vertices,colors)

func _reticle(vertices:PackedVector3Array,colors:PackedColorArray,at:Vector3,color:Color,valid:bool)->void:
 _ring(vertices,colors,at,0.18,0.027,color,not valid,24)
 if not valid:
  _cross(vertices,colors,at,0.16,color)
  return
 for i in range(4):
  var direction = Vector3(cos(i*PI*0.5),0,sin(i*PI*0.5))
  _segment(vertices,colors,at+direction*0.23,at+direction*0.34,0.025,color,INK_Y)

func _blue_preview(points:Array[Vector3],color:Color,valid:bool,directed:bool,fv:PackedVector3Array,fc:PackedColorArray,iv:PackedVector3Array,ic:PackedColorArray)->void:
 var a:Vector3 = points[0]
 var b:Vector3 = points[-1]
 var direction:Vector3 = (b-a).normalized()
 _path_segments(iv,ic,[a,b],0.06,_alpha(color,0.82),not valid)
 for at in [a,b]:
  _disc(fv,fc,at,0.28,_alpha(color,0.12),20)
  _ring(iv,ic,at,0.31,0.045,_alpha(color,0.95),not valid,28)
  _ring(iv,ic,at,0.43,0.018,_alpha(color,0.45),not valid,28)
 if not valid or a.distance_to(b)<1.0: return
 if directed:
  _arrow(iv,ic,a.lerp(b,0.68),-direction,0.42,_alpha(color,0.92))
  _arrow(iv,ic,a.lerp(b,0.40),-direction,0.42,_alpha(color,0.92))
 else:
  _arrow(iv,ic,a.lerp(b,0.25),direction,0.42,_alpha(color,0.92))
  _arrow(iv,ic,a.lerp(b,0.75),-direction,0.42,_alpha(color,0.92))

func _ribbon(fv:PackedVector3Array,fc:PackedColorArray,iv:PackedVector3Array,ic:PackedColorArray,points:Array[Vector3],width:float,color:Color,valid:bool)->void:
 var coverage:Color = _alpha(color,0.16 if valid else 0.055)
 var outline:Color = _alpha(color,0.86 if valid else 0.75)
 for i in range(points.size()-1):
  var a:Vector3 = points[i]
  var b:Vector3 = points[i+1]
  if a.distance_to(b)<0.006: continue
  var side:Vector3 = (b-a).normalized().cross(Vector3.UP)*width*0.5
  _segment(fv,fc,a,b,width,coverage,FLOOR_Y)
  _path_segments(iv,ic,[a+side,b+side],0.03,outline,not valid)
  _path_segments(iv,ic,[a-side,b-side],0.03,outline,not valid)
 _ring(iv,ic,points[0],width*0.5,0.025,outline,not valid,24)
 _ring(iv,ic,points[-1],width*0.5,0.025,outline,not valid,24)
 _disc(fv,fc,points[0],width*0.5,coverage,20)
 _disc(fv,fc,points[-1],width*0.5,coverage,20)
 # Segment collision uses rounded caps; cover inner polyline joints at the same radius.
 for i in range(1,points.size()-1):
  _disc(fv,fc,points[i],width*0.5,coverage,16)
 if not valid:
  var center:Vector3 = points[0].lerp(points[-1],0.5)
  _cross(iv,ic,center,minf(0.22,width*0.35),_alpha(INVALID,0.92))

func _path_segments(vertices:PackedVector3Array,colors:PackedColorArray,points:Array,width:float,color:Color,dashed:bool)->void:
 for i in range(points.size()-1):
  var a:Vector3 = points[i]
  var b:Vector3 = points[i+1]
  var length:float = a.distance_to(b)
  if length<0.001: continue
  if not dashed:
   _segment(vertices,colors,a,b,width,color,INK_Y)
   continue
  var direction:Vector3 = (b-a)/length
  var distance:float = 0.0
  while distance<length:
   _segment(vertices,colors,a+direction*distance,a+direction*minf(distance+0.18,length),width,color,INK_Y)
   distance += 0.31

func _arrow(vertices:PackedVector3Array,colors:PackedColorArray,at:Vector3,direction:Vector3,length:float,color:Color)->void:
 var normal:Vector3 = Vector3(direction.x,0,direction.z).normalized()
 if normal.length_squared()<0.5: return
 var side:Vector3 = normal.cross(Vector3.UP)
 var start:Vector3 = _floor(at,INK_Y)
 var tip:Vector3 = start+normal*length
 _segment(vertices,colors,start,tip-normal*0.14,0.036,color,INK_Y)
 _triangle(vertices,colors,tip,tip-normal*0.21+side*0.13,tip-normal*0.21-side*0.13,color)

func _cross(vertices:PackedVector3Array,colors:PackedColorArray,at:Vector3,radius:float,color:Color)->void:
 _segment(vertices,colors,at+Vector3(-radius,0,-radius),at+Vector3(radius,0,radius),0.045,color,INK_Y+0.005)
 _segment(vertices,colors,at+Vector3(-radius,0,radius),at+Vector3(radius,0,-radius),0.045,color,INK_Y+0.005)

func _ring(vertices:PackedVector3Array,colors:PackedColorArray,at:Vector3,radius:float,width:float,color:Color,dashed:bool,segments:int)->void:
 for i in range(segments):
  if dashed and i%4>=2: continue
  var a:float = float(i)*TAU/float(segments)
  var b:float = float(i+1)*TAU/float(segments)
  var p:Vector3 = at+Vector3(cos(a),0,sin(a))*radius
  var q:Vector3 = at+Vector3(cos(b),0,sin(b))*radius
  _segment(vertices,colors,p,q,width,color,INK_Y)

func _disc(vertices:PackedVector3Array,colors:PackedColorArray,at:Vector3,radius:float,color:Color,segments:int)->void:
 var center:Vector3 = _floor(at,FLOOR_Y)
 for i in range(segments):
  var a:float = float(i)*TAU/float(segments)
  var b:float = float(i+1)*TAU/float(segments)
  _triangle(vertices,colors,center,center+Vector3(cos(a),0,sin(a))*radius,center+Vector3(cos(b),0,sin(b))*radius,color)

func _segment(vertices:PackedVector3Array,colors:PackedColorArray,a:Vector3,b:Vector3,width:float,color:Color,y:float)->void:
 a = _floor(a,y)
 b = _floor(b,y)
 if a.distance_squared_to(b)<0.000001: return
 var side:Vector3 = (b-a).normalized().cross(Vector3.UP)*width*0.5
 _triangle(vertices,colors,a-side,a+side,b+side,color)
 _triangle(vertices,colors,a-side,b+side,b-side,color)

func _triangle(vertices:PackedVector3Array,colors:PackedColorArray,a:Vector3,b:Vector3,c:Vector3,color:Color)->void:
 vertices.append(a)
 vertices.append(b)
 vertices.append(c)
 colors.append(color)
 colors.append(color)
 colors.append(color)

func _upload(mesh:ImmediateMesh,vertices:PackedVector3Array,colors:PackedColorArray)->void:
 mesh.clear_surfaces()
 if vertices.is_empty(): return
 mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in range(vertices.size()):
  mesh.surface_set_color(colors[i])
  mesh.surface_add_vertex(vertices[i])
 mesh.surface_end()

func _alpha(color:Color,value:float)->Color:
 return Color(color.r,color.g,color.b,value)

func _floor(point:Vector3,y:float)->Vector3:
 return Vector3(point.x,y,point.z)
