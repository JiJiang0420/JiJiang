extends Node3D
## Original procedural architecture. Decorative geometry stays outside radius 15.

var _built:bool = false
var _clock:float = 0.0
var _threat:float = 0.0
var _flames:Array = []
var _embers:Array = []
var _hovering:Array = []
var _lanterns:Array = []
var _ritual_material:StandardMaterial3D

func build()->void:
 if _built: return
 _built = true
 name = "TheBanquetCourt"
 var stone = _mat(Color("343440"),0.0,0.94)
 var dark_stone = _mat(Color("242631"),0.05,0.94)
 var edge = _mat(Color("656070"),0.1,0.78)
 var metal = _mat(Color("8c7959"),0.5,0.56)
 var dark_metal = _mat(Color("494450"),0.6,0.62)
 var inlay = _mat(Color("686053"),0.26,0.8)
 var pale_inlay = _mat(Color("807262"),0.3,0.82)
 var void_floor = _mat(Color("171c29"),0.0,1.0)
 _lighting()
 _box(Vector3(0,-0.54,0),Vector3(90,0.25,90),void_floor)
 _cylinder(Vector3(0,-0.27,0),16.9,16.9,0.5,dark_stone,64)
 _cylinder(Vector3(0,-0.02,0),16.15,16.15,0.18,stone,64)
 _floor_tiles()
 _ring(16.38,0.03,0.13,metal,96)
 _ring(15.9,0.08,0.08,pale_inlay,96)
 _ring(15.05,0.085,0.055,inlay,96)
 _ring(14.85,0.087,0.025,inlay,96)
 _ring(9.2,0.085,0.035,inlay,96)
 _ring(4.75,0.085,0.035,inlay,72)
 _ring(4.45,0.086,0.018,inlay,72)
 _center_seal(inlay,pale_inlay)
 for i in range(24):
  var a = float(i)*TAU/24.0
  var p = _radial(a,15.2)
  var q = _radial(a,15.68)
  _ground_line(p,q,0.045,0.09,metal)
  if i%2 == 0:
   _ground_line(_radial(a,9.3),_radial(a,14.65),0.026,0.086,inlay)
 for i in range(12):
  var angle = float(i)*TAU/12.0
  var at = _radial(angle,17.05)
  var height = 3.4 if i%4 != 1 else 1.8
  _pillar(at,height,stone,dark_stone,edge,metal)
  if i%4 != 1:
   _finial(at+Vector3.UP*(height+0.45),metal)
 for side in [-1,1]:
  _pointed_gate(Vector3(0,0,side*18.0),side,stone,edge,metal)
  for step in range(4):
   _box(Vector3(0,-0.12-float(step)*0.085,side*(16.9+float(step)*0.48)),Vector3(4.8+float(step)*0.3,0.22,0.55),dark_stone)
 # Three independent relic stations, with differing material and glyph language.
 var relic_colors = [Color("b64d69"),Color("8276bd"),Color("c8a766")]
 for i in range(3):
  var a = -PI*0.5+float(i)*TAU/3.0
  _shrine(_radial(a,17.5),a,relic_colors[i],i,stone,metal)
 # Warm points at the perimeter illuminate scenery without washing out spell colors.
 for i in range(8):
  var angle = (float(i)+0.5)*TAU/8.0
  var at = _radial(angle,15.85)
  _brazier(at,dark_metal,metal,i%2==0)
 # Fallen masonry beyond the playable rim makes the court feel excavated.
 for i in range(16):
  var angle = float(i)*TAU/16.0+0.17
  var at = _radial(angle,18.8+float(i%3)*0.45)
  var piece = _box(at+Vector3(0,0.16,0),Vector3(0.65+float(i%2)*0.35,0.35,1.1),dark_stone)
  piece.rotation = Vector3(0.1*float(i%3),angle+0.5,0.15)
 for i in range(9):
  var angle = float(i)*TAU/9.0+0.28
  var at = _radial(angle,19.4)+Vector3.UP*(1.6+float(i%3)*0.8)
  var shard = _diamond(at,0.13+float(i%3)*0.025,0.55+float(i%3)*0.15,dark_stone)
  shard.rotation = Vector3(0.2,float(i),0.15)
  _hovering.append({"node":shard,"origin":at,"phase":float(i)*1.3})

func _lighting()->void:
 var environment = Environment.new()
 environment.background_mode = Environment.BG_COLOR
 environment.background_color = Color("141927")
 environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color = Color("8890b5")
 environment.ambient_light_energy = 0.45
 environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 environment.fog_enabled = true
 environment.fog_light_color = Color("232538")
 environment.fog_light_energy = 0.5
 environment.fog_density = 0.003
 var we = WorldEnvironment.new()
 we.environment = environment
 add_child(we)
 var moon = DirectionalLight3D.new()
 moon.name = "Moonlight"
 moon.rotation_degrees = Vector3(-62,-28,0)
 moon.light_color = Color("c4c8e0")
 moon.light_energy = 0.85
 moon.shadow_enabled = true
 moon.directional_shadow_max_distance = 65
 moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
 add_child(moon)
 var fill = DirectionalLight3D.new()
 fill.rotation_degrees = Vector3(-35,155,0)
 fill.light_color = Color("d5ac8a")
 fill.light_energy = 0.25
 fill.shadow_enabled = false
 add_child(fill)

func _floor_tiles()->void:
 # Four radial stone courses. Slight deterministic variations remain low contrast.
 var vertices = PackedVector3Array()
 var normals = PackedVector3Array()
 var colors = PackedColorArray()
 var base = Color("3c3c49")
 var radii = [0.0,4.7,9.15,12.0,15.8]
 for ring in range(4):
  for section in range(32):
   var a = float(section)*TAU/32.0
   var b = float(section+1)*TAU/32.0
   var inner:float = radii[ring]+0.025
   var outer:float = radii[ring+1]-0.025
   var corners = [_radial(a+0.0015,inner),_radial(b-0.0015,inner),_radial(b-0.0015,outer),_radial(a+0.0015,outer)]
   var shade = 0.94+float((section*7+ring*11)%9)*0.014
   for idx in [0,2,1,0,3,2]:
    vertices.append(corners[idx]+Vector3.UP*0.079)
    normals.append(Vector3.UP)
    colors.append(Color(base.r*shade,base.g*shade,base.b*shade,1))
 var arrays:Array = []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = vertices
 arrays[Mesh.ARRAY_NORMAL] = normals
 arrays[Mesh.ARRAY_COLOR] = colors
 var mesh = ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var m = _mat(Color.WHITE,0.04,0.95)
 m.vertex_color_use_as_albedo = true
 m.cull_mode = BaseMaterial3D.CULL_DISABLED
 _mesh(mesh,Vector3.ZERO,m)

func _center_seal(inlay:Material,pale:Material)->void:
 _ring(1.05,0.089,0.027,pale,64)
 _ring(0.84,0.09,0.015,inlay,48)
 for i in range(3):
  var a = -PI*0.5+float(i)*TAU/3.0
  var b = -PI*0.5+float(i+1)*TAU/3.0
  _ground_line(_radial(a,3.8),_radial(b,3.8),0.035,0.088,inlay)
  var c = _radial(a,3.8)
  _circle(c,0.32,0.03,0.09,pale,20)
  _ground_line(_radial(a,1.15),_radial(a,3.35),0.028,0.089,inlay)
 for i in range(18):
  var a = float(i)*TAU/18.0
  _ground_line(_radial(a,4.1),_radial(a,4.3),0.025,0.09,inlay)
 # A quiet center emblem rather than a bright competing spell effect.
 for i in range(6):
  var a = float(i)*TAU/6.0
  _ground_line(Vector3.ZERO,_radial(a,0.58),0.023,0.091,pale)

func _pillar(at:Vector3,height:float,stone:Material,dark:Material,edge:Material,gold:Material)->void:
 _box(at+Vector3.UP*0.16,Vector3(1.2,0.32,1.2),dark)
 _box(at+Vector3.UP*0.37,Vector3(0.98,0.16,0.98),edge)
 _cylinder(at+Vector3.UP*(0.5+height*0.5),0.37,0.43,height,stone,8)
 for side in [-1,1]:
  _box(at+Vector3(side*0.30,0.5+height*0.5,0),Vector3(0.06,height,0.065),edge)
  _box(at+Vector3(0,0.5+height*0.5,side*0.30),Vector3(0.065,height,0.06),edge)
 _cylinder(at+Vector3.UP*(height+0.48),0.52,0.4,0.18,edge,8)
 _cylinder(at+Vector3.UP*(height+0.62),0.48,0.52,0.10,gold,8)

func _finial(at:Vector3,metal:Material)->void:
 _cylinder(at+Vector3.UP*0.45,0.0,0.18,0.9,metal,6)

func _pointed_gate(at:Vector3,side:int,stone:Material,edge:Material,gold:Material)->void:
 var left = at+Vector3(-2.5,0,0)
 var right = at+Vector3(2.5,0,0)
 _pillar(left,3.6,stone,stone,edge,gold)
 _pillar(right,3.6,stone,stone,edge,gold)
 var arch = [left+Vector3.UP*3.9,at+Vector3(-1.7,5.1,0),at+Vector3(0,6.25,0),at+Vector3(1.7,5.1,0),right+Vector3.UP*3.9]
 for i in range(arch.size()-1):
  _beam(arch[i],arch[i+1],0.42,stone)
  _beam(arch[i]+Vector3(0,0.08,-side*0.25),arch[i+1]+Vector3(0,0.08,-side*0.25),0.065,gold)
 _diamond(at+Vector3(0,4.55,0),0.28,0.7,gold)
 _beam(at+Vector3(0,4.95,0),at+Vector3(0,5.75,0),0.025,gold)

func _shrine(at:Vector3,angle:float,color:Color,index:int,stone:Material,gold:Material)->void:
 _cylinder(at+Vector3.UP*0.2,0.9,1.15,0.4,stone,8)
 _cylinder(at+Vector3.UP*0.48,0.64,0.88,0.16,gold,8)
 _cylinder(at+Vector3.UP*0.85,0.40,0.58,0.65,stone,8)
 var sigil = _mat(color,0.3,0.55)
 sigil.emission_enabled = true
 sigil.emission = color*0.25
 var relic = _diamond(at+Vector3.UP*1.85,0.38,1.0,sigil)
 relic.rotation.y = angle
 _hovering.append({"node":relic,"origin":relic.position,"phase":float(index)*2.1})
 var lantern = OmniLight3D.new()
 lantern.position = at+Vector3.UP*2.0
 lantern.light_color = color
 lantern.light_energy = 1.0
 lantern.omni_range = 4.0
 lantern.shadow_enabled = false
 add_child(lantern)
 _lanterns.append(lantern)
 # Small standing ribs evoke a reliquary without obscuring the arena center.
 for sign_value in [-1,1]:
  var tangent = Vector3(-sin(angle),0,cos(angle))
  var p = at+tangent*float(sign_value)*0.78
  _beam(p+Vector3.UP*0.5,p+Vector3.UP*2.5,0.1,gold)
  _beam(p+Vector3.UP*2.5,at+Vector3.UP*3.05,0.1,gold)

func _brazier(at:Vector3,dark:Material,gold:Material,with_light:bool)->void:
 _cylinder(at+Vector3.UP*0.15,0.32,0.42,0.3,dark,8)
 _cylinder(at+Vector3.UP*0.6,0.075,0.13,0.75,gold,8)
 _cylinder(at+Vector3.UP*1.05,0.32,0.11,0.18,dark,8)
 var flame_mat = _mat(Color("edb66f"),0.0,0.8)
 flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 var flame = _diamond(at+Vector3.UP*1.35,0.12,0.5,flame_mat)
 _flames.append({"node":flame,"phase":float(_flames.size())*1.41})
 if with_light:
  var lamp = OmniLight3D.new()
  lamp.position = at+Vector3.UP*1.55
  lamp.light_color = Color("e4a573")
  lamp.light_energy = 1.1
  lamp.omni_range = 5.5
  lamp.omni_attenuation = 1.6
  lamp.shadow_enabled = false
  add_child(lamp)
 for i in range(3):
  var mote = _diamond(at+Vector3(float(i-1)*0.12,1.7+float(i)*0.25,0),0.018,0.07,flame_mat)
  _embers.append({"node":mote,"origin":at,"phase":float(i)*1.4+float(_embers.size())})

func set_threat(value:float)->void:
 _threat = clampf(value,0,1)

func _process(delta:float)->void:
 _clock += delta
 for flame in _flames:
  var wave = sin(_clock*7.0+flame.phase)*0.10+sin(_clock*11.0+flame.phase)*0.04
  flame.node.scale = Vector3(1.0-wave,1.0+wave,1.0-wave)
 for mote in _embers:
  var t = fmod(_clock*0.4+mote.phase,1.0)
  mote.node.position = mote.origin+Vector3(sin(_clock+mote.phase)*0.18,1.35+t*1.2,cos(_clock*0.8+mote.phase)*0.12)
  mote.node.scale = Vector3.ONE*(1.0-t)
 for item in _hovering:
  item.node.position.y = item.origin.y+sin(_clock*0.7+item.phase)*0.13
  item.node.rotation.y += delta*0.13
 for lamp in _lanterns:
  lamp.light_energy = 1.0+_threat*0.4

func _mat(color:Color,metallic:float=0.0,roughness:float=0.8)->StandardMaterial3D:
 var material = StandardMaterial3D.new()
 material.albedo_color = color
 material.metallic = metallic
 material.roughness = roughness
 return material

func _mesh(mesh:Mesh,at:Vector3,material:Material)->MeshInstance3D:
 var node = MeshInstance3D.new()
 node.mesh = mesh
 node.material_override = material
 node.position = at
 add_child(node)
 return node

func _box(at:Vector3,size:Vector3,material:Material)->MeshInstance3D:
 var mesh = BoxMesh.new()
 mesh.size = size
 return _mesh(mesh,at,material)

func _cylinder(at:Vector3,top:float,bottom:float,height:float,material:Material,segments:int=12)->MeshInstance3D:
 var mesh = CylinderMesh.new()
 mesh.top_radius = top
 mesh.bottom_radius = bottom
 mesh.height = height
 mesh.radial_segments = segments
 mesh.rings = 1
 return _mesh(mesh,at,material)

func _diamond(at:Vector3,radius:float,height:float,material:Material)->Node3D:
 var root = Node3D.new()
 root.position = at
 add_child(root)
 var upper = CylinderMesh.new()
 upper.top_radius = 0
 upper.bottom_radius = radius
 upper.height = height*0.65
 upper.radial_segments = 4
 upper.rings = 1
 var lower = CylinderMesh.new()
 lower.top_radius = radius
 lower.bottom_radius = 0
 lower.height = height*0.35
 lower.radial_segments = 4
 lower.rings = 1
 for pair in [[upper,height*0.175],[lower,-height*0.325]]:
  var node = MeshInstance3D.new()
  node.mesh = pair[0]
  node.material_override = material
  node.position.y = pair[1]
  root.add_child(node)
 return root

func _beam(a:Vector3,b:Vector3,width:float,material:Material)->MeshInstance3D:
 var length = a.distance_to(b)
 var node = _box((a+b)*0.5,Vector3(width,length,width),material)
 node.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
 return node

func _radial(angle:float,radius:float)->Vector3:
 return Vector3(cos(angle)*radius,0,sin(angle)*radius)

func _ground_line(a:Vector3,b:Vector3,width:float,y:float,material:Material)->void:
 var mesh = ImmediateMesh.new()
 var side = (b-a).normalized().cross(Vector3.UP)*width*0.5
 a.y = y
 b.y = y
 mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
 for p in [a-side,b+side,a+side,a-side,b-side,b+side]:
  mesh.surface_set_normal(Vector3.UP)
  mesh.surface_add_vertex(p)
 mesh.surface_end()
 var node = _mesh(mesh,Vector3.ZERO,material)
 node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ring(radius:float,y:float,width:float,material:Material,segments:int)->void:
 _circle(Vector3.ZERO,radius,width,y,material,segments)

func _circle(center:Vector3,radius:float,width:float,y:float,material:Material,segments:int)->void:
 var mesh = ImmediateMesh.new()
 mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in range(segments):
  var a = float(i)*TAU/float(segments)
  var b = float(i+1)*TAU/float(segments)
  var p = center+_radial(a,radius-width*0.5)+Vector3.UP*y
  var q = center+_radial(a,radius+width*0.5)+Vector3.UP*y
  var r = center+_radial(b,radius+width*0.5)+Vector3.UP*y
  var s = center+_radial(b,radius-width*0.5)+Vector3.UP*y
  for point in [p,r,q,p,s,r]:
   mesh.surface_set_normal(Vector3.UP)
   mesh.surface_add_vertex(point)
 mesh.surface_end()
 var node = _mesh(mesh,Vector3.ZERO,material)
 node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
