"""Original low-poly witch model, generated in Blender 4.3+.

Run: blender --background --python tools/build_models.py -- /path/to/game/assets/models
All meshes and materials are authored here; no external artwork is required.
"""
import bpy
import math
import sys
from pathlib import Path
from mathutils import Vector

out = Path(sys.argv[sys.argv.index('--') + 1]) if '--' in sys.argv else Path(__file__).resolve().parents[1] / 'game/assets/models'
out.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, metallic=0.0, roughness=0.65, glow=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Emission Color'].default_value = (*color, 1.0)
    bsdf.inputs['Emission Strength'].default_value = glow
    return mat

cloth = material('Cloak', (0.38, 0.025, 0.065), roughness=0.76)
hood = material('Hood', (0.28, 0.018, 0.045), roughness=0.74)
lining = material('CloakLining', (0.12, 0.025, 0.055), roughness=0.75)
gold = material('AntiqueGold', (0.72, 0.47, 0.17), metallic=0.65, roughness=0.38)
gold_glow = material('RuneGold', (0.96, 0.73, 0.34), metallic=0.35, roughness=0.42, glow=0.3)
black = material('ObsidianCloth', (0.022, 0.028, 0.045), roughness=0.72)
skin = material('Porcelain', (0.67, 0.62, 0.58), roughness=0.78)
leather = material('BookLeather', (0.11, 0.06, 0.085), roughness=0.73)
silver = material('MoonSilver', (0.51, 0.57, 0.66), metallic=0.7, roughness=0.35)
root = bpy.data.objects.new('WitchRoot', None)
bpy.context.collection.objects.link(root)

def finish(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    obj.parent = root
    return obj

def sphere(name, at, scale, mat, segments=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=at)
    o = bpy.context.object
    o.scale = scale
    return finish(o, name, mat)

def cone(name, at, bottom, top, depth, mat, vertices=12):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=bottom, radius2=top, depth=depth, location=at)
    return finish(bpy.context.object, name, mat)

def box(name, at, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    o = bpy.context.object
    o.scale = size
    return finish(o, name, mat)

def line(name, points, thickness, mat, cyclic=False):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = thickness
    cu.bevel_resolution = 0
    sp = cu.splines.new('POLY')
    sp.points.add(len(points) - 1)
    for p, v in zip(sp.points, points):
        p.co = (*v, 1.0)
    sp.use_cyclic_u = cyclic
    ob = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    ob.parent = root
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target='MESH')
    ob.select_set(False)
    return ob

# Slender body and boots face Blender +Y (glTF/Godot -Z).
cone('Dress', (0, 0.015, 0.67), 0.28, 0.20, 1.02, black)
sphere('Torso', (0, 0.025, 1.17), (0.22, 0.14, 0.28), black)
for side in [-1, 1]:
    box('Boot_' + str(side), (side * 0.10, 0.075, 0.105), (0.15, 0.28, 0.21), black)
    sphere('Shoulder_' + str(side), (side * 0.25, 0.015, 1.28), (0.15, 0.16, 0.10), gold)
    arm = cone('Sleeve_' + str(side), (side * 0.29, 0.075, 1.03), 0.08, 0.10, 0.46, black, 8)
    arm.rotation_euler[1] = side * 0.15
    sphere('Hand_' + str(side), (side * 0.32, 0.12, 0.79), (0.065, 0.055, 0.09), skin, 8, 6)

# Dense angular folds, open at the front. Gold seams make the broad cloak readable.
angles = [math.radians(135 + 270 * j / 16) for j in range(17)]
layers = [(1.37, 0.26), (1.19, 0.34), (0.95, 0.42), (0.70, 0.53), (0.45, 0.65), (0.20, 0.75)]
verts = []
for ring, (z, radius) in enumerate(layers):
    for j, a in enumerate(angles):
        fold = 1.0 + (0.07 if j % 2 else -0.035) * ring / 5
        r = radius * fold
        zz = z + (0.07 if j % 4 == 0 else -0.03) * ring / 5
        x = math.cos(a) * r
        y = math.sin(a) * r * 0.72 - 0.045 * ring / 5
        verts.append((x, y, zz))
faces = []
for i in range(len(layers)-1):
    for j in range(16):
        a = i*17+j
        faces.extend([(a, a+1, a+18), (a, a+18, a+17)])
mesh = bpy.data.meshes.new('CloakMesh')
mesh.from_pydata(verts, [], faces)
mesh.update()
obj = bpy.data.objects.new('Cloak', mesh)
bpy.context.collection.objects.link(obj)
finish(obj, 'Cloak', cloth)
obj.data.materials[0].surface_render_method = 'DITHERED'
# Duplicate reversed inner face for a closed-looking cloth surface.
inner_mesh = bpy.data.meshes.new('CloakLiningMesh')
inner_verts = [(x*.991, y*.991, z+.004) for x,y,z in verts]
inner_mesh.from_pydata(inner_verts, [], [tuple(reversed(f)) for f in faces])
inner_mesh.update()
inner = bpy.data.objects.new('CloakLining', inner_mesh)
bpy.context.collection.objects.link(inner)
finish(inner, 'CloakLining', lining)

for j in [0, 4, 8, 12, 16]:
    pts = [verts[i*17+j] for i in range(len(layers))]
    line('CloakSeam_' + str(j), pts, 0.008, gold)
line('CloakHem', verts[-17:], 0.016, gold)

# Deep hood and readable dark face opening with two tiny gold eyes.
sphere('Hood', (0, -0.005, 1.51), (0.29, 0.245, 0.35), hood)
sphere('FaceShadow', (0, 0.215, 1.51), (0.175, 0.040, 0.235), black)
opening = []
for i in range(17):
    a=2*math.pi*i/16
    opening.append((math.cos(a)*0.185, 0.225, 1.51+math.sin(a)*0.25))
line('HoodTrim', opening, .013, gold, True)
for x in [-.065,.065]:
    sphere('Eye', (x,.257,1.55), (.018,.010,.012), gold_glow, 8, 4)
cone('HoodPeak', (0,-.06,1.80), .12, 0, .24, hood, 8)

# Chest brooch, crescent shoulder chain and a grimoire.
brooch = sphere('MoonBrooch',(0,.18,1.28),(.08,.035,.10),gold_glow,8,6)
chain = [(-.21+.42*i/12, .16, 1.28-.10*math.sin(math.pi*i/12)) for i in range(13)]
line('ShoulderChain', chain, .011, gold)
book=box('Grimoire',(.24,.17,.66),(.19,.10,.29),leather)
book.rotation_euler[1]=-.12
box('BookPages',(.24,.227,.66),(.15,.012,.24),skin)
line('BookSigil',[(.24,.24,.75),(.30,.24,.66),(.24,.24,.57),(.18,.24,.66)],.009,gold,True)

# Thin gold radial glyphs on the back: authored mesh ornament, not a texture decal.
for side in [-1,1]:
    line('BackRune'+str(side),[(side*.07,-.28,1.12),(side*.15,-.38,.84),(side*.25,-.44,.61)],.012,gold_glow)
line('BackRuneCross',[(-.19,-.39,.84),(.19,-.39,.84)],.010,gold_glow)

# Apply dimensions for consistent interchange; preserve object names for runtime tint.
for ob in list(bpy.context.scene.objects):
    if ob.type=='MESH':
        bpy.context.view_layer.objects.active=ob
        ob.select_set(True)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        ob.select_set(False)

bpy.context.scene.world.color=(.03,.03,.05)
bpy.ops.wm.save_as_mainfile(filepath=str(out/'witch.blend'))
bpy.ops.export_scene.gltf(filepath=str(out/'player.glb'),export_format='GLB',export_yup=True,export_apply=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
print('Saved original witch source and glTF:',out)
