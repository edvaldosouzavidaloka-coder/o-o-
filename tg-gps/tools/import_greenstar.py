"""Import the user-supplied GPS folder without re-encoding its DDS or shapes.

Usage: python tools/import_greenstar.py /path/to/extracted/GPS
The uploaded GIANTS 10 model is kept behind a separate normalization pivot.
Only scene names, local paths, LCD materials and initial visibility are adapted.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def quad(shapes, scene, shape_id, name, material, box, source_size=1024, z=0.0075):
    x, y, w, h = box
    # Pixel rectangles refer to the supplied image, with its origin at the top.
    left, right = x/source_size, (x+w)/source_size
    bottom, top = 1-(y+h)/source_size, 1-y/source_size
    mesh = ET.SubElement(shapes, 'IndexedTriangleSet', name=name, shapeId=str(shape_id),
                         meshUsage='0', bvCenter='0 0 0', bvRadius='0.708')
    vertices = ET.SubElement(mesh, 'Vertices', count='4', normal='true', uv0='true')
    for u, v in ((left, bottom), (right, bottom), (right, top), (left, top)):
        ET.SubElement(vertices, 'v', p=f'{u-.5:.9f} {v-.5:.9f} 0', n='0 0 1', t0=f'{u:.9f} {v:.9f}')
    triangles = ET.SubElement(mesh, 'Triangles', count='2')
    for vi in ('0 1 2', '0 2 3'): ET.SubElement(triangles, 't', vi=vi)
    subsets = ET.SubElement(mesh, 'Subsets', count='1')
    ET.SubElement(subsets, 'Subset', firstVertex='0', numVertices='4', firstIndex='0', numIndices='6', uvDensity0='1')
    return ET.SubElement(scene, 'Shape', name=name, nodeId=str(shape_id), shapeId=str(shape_id),
                         materialIds=str(material), castsShadows='false', receiveShadows='false',
                         translation=f'0 0 {z}')


def write(path, root):
    ET.indent(root, space='    ')
    ET.ElementTree(root).write(path, encoding='utf-8', xml_declaration=True)


def main(source):
    dest = ROOT/'models/greenstar'
    dest.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for path in sorted(source.rglob('*')):
        if not path.is_file() or path.suffix == '.i3d' or path.name == 'GPS3000-supplied.dds': continue
        rel = path.relative_to(source)
        target = dest/rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        hashes[rel.as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    model = ET.parse(source/'GPS.i3d').getroot()
    model.set('name', 'TG_GreenStar3')
    files = model.find('Files')
    for ref in files:
        if not ref.get('filename').startswith('$'):
            ref.set('filename', 'greenstar/'+ref.get('filename'))
    ET.SubElement(files, 'File', fileId='900', filename='../shaders/tgGpsGreenStarShader.xml')
    for material in model.find('Materials'):
        if material.get('materialId') in {'47', '49', '168'}:
            material.set('customShaderId', '900')
            for child in list(material):
                if child.tag not in {'Texture', 'Emissivemap'}: material.remove(child)
            texture = material.find('Texture').get('fileId')
            if material.find('Emissivemap') is None: ET.SubElement(material, 'Emissivemap', fileId=texture)
            ET.SubElement(material, 'CustomParameter', name='lcdBrightness', value='0.05 0 0 0')
    model.find('Shapes').set('externalShapesFile', 'greenstar/GPS.i3d.shapes')
    scene = model.find('Scene')
    children = list(scene)
    for child in children: scene.remove(child)
    root = ET.SubElement(scene, 'TransformGroup', name='MonitorRoot', nodeId='9001')
    pivot = ET.SubElement(root, 'TransformGroup', name='GreenStarModel', nodeId='9002')
    for child in children: pivot.append(child)
    for node in pivot.iter():
        if node.tag == 'Shape':
            node.set('materialIds', ' '.join(node.get('materialIds').replace(',', ' ').split()))
        if node.get('nodeId') == '1299': node.set('name', 'MonitorScreen')
        if node.get('nodeId') == '1300': node.set('name', 'GreenStarBoot');node.set('visibility', 'false')
        if node.get('nodeId') in {'1302', '1303'}: node.set('visibility', 'false')
        if node.tag == 'Light': node.set('castShadowMap', 'false');node.set('visibility', 'false')
    write(ROOT/'models/curveGPSMonitor.i3d', model)

    overlay = ET.Element('i3D', name='TG_GreenStarOverlay', version='1.6')
    f = ET.SubElement(overlay, 'Files')
    for fid, filename in ((1, '../shaders/tgGpsGreenStarShader.xml'), (2, 'greenstar/Textures/GPS3000.dds'),
                          (3, 'greenstar/Textures/animated.dds'), (4, '../shaders/tgGpsLcdShader.xml'),
                          (5, 'textures/orientationShell.dds')):
        ET.SubElement(f, 'File', fileId=str(fid), filename=filename)
    materials = ET.SubElement(overlay, 'Materials')
    for mid, texture in ((1, 2), (2, 3), (5, 5)):
        m = ET.SubElement(materials, 'Material', name=f'originalTexture{mid}', materialId=str(mid),
                          customShaderId='1', alphaBlending='true')
        ET.SubElement(m, 'Texture', fileId=str(texture));ET.SubElement(m, 'Emissivemap', fileId=str(texture))
        ET.SubElement(m, 'CustomParameter', name='lcdBrightness', value='0.05 0 0 0')
    for mid, color in ((3, '0 0 0 1'), (4, '1 0.85 0 1')):
        m = ET.SubElement(materials, 'Material', name=f'bootProgress{mid}', materialId=str(mid), customShaderId='4')
        ET.SubElement(m, 'CustomParameter', name='lcdTint', value=color)
        ET.SubElement(m, 'CustomParameter', name='lcdBrightness', value='0.05 0 0 0')
    shapes, scene = ET.SubElement(overlay, 'Shapes'), ET.SubElement(overlay, 'Scene')
    controls = ET.SubElement(scene, 'TransformGroup', name='GreenStarOriginalControls', nodeId='1001')
    # Restore the supplied arrows/zoom/camera icons over the live map. Labels,
    # letters A..J and menus outside the map remain on the original binary mesh.
    boxes = [(14,244,124,43), (348,244,84,52), (16,430,85,55), (672,430,83,55),
             (16,643,168,58), (348,644,84,57), (586,643,171,58), (672,587,83,55)]
    for i, box in enumerate(boxes, 1): quad(shapes, controls, i, 'originalControl'+str(i), 1, box)
    ring = quad(shapes, controls, 20, 'GreenStarWorkRing', 2, (0,0,1024,1024), z=0.008)
    ring.set('translation', '0.08203125 -0.25 0.008')
    ring.set('scale', '0.029296875 0.029296875 1')
    menu = ET.SubElement(controls, 'TransformGroup', name='GreenStarMenuAnimation', nodeId='1003')
    for i,(name,box) in enumerate([
        ('mapping',(800,38,75,80)),('guidance',(794,193,84,83)),
        ('resources',(925,198,84,84)),('equipment',(934,369,77,91)),
        ('water',(804,533,62,82)),('document',(930,543,72,77)),
        ('totals',(915,736,92,70))],30):
        quad(shapes,menu,i,'menu_'+name,1,box,z=0.008)
    boot = ET.SubElement(scene, 'TransformGroup', name='GreenStarBootProgress', nodeId='1002')
    quad(shapes, boot, 21, 'BootProgressMask', 3, (155,263,222,30), source_size=512)
    fill = quad(shapes, boot, 22, 'BootProgressFill', 4, (0,0,1024,1024), z=0.008)
    fill.set('translation', '-0.197265625 -0.04296875 0.008')
    fill.set('scale', '0.00001 0.05859375 1')
    spin = quad(shapes, boot, 23, 'GreenStarBootRing', 2, (0,0,1024,1024), z=0.008)
    spin.set('translation', '0.326171875 -0.04296875 0.008')
    spin.set('scale', '0.03515625 0.03515625 1')
    orientation=ET.SubElement(scene,'TransformGroup',name='OrientationShellRoot',nodeId='3000',visibility='false')
    quad(shapes,orientation,100,'OrientationShell',5,(0,0,1024,1024),z=.0044)
    for i,name in enumerate(['settings','mapping','guidance','resources','ab','iso','equipment','water','power','totals']):
        quad(shapes,orientation,101+i,'ori_'+name,5,
             (i*44/440*1024,295/330*1024,44/440*1024,34/330*1024),z=.008)
    write(ROOT/'models/tgGreenStarOverlay.i3d', overlay)
    (ROOT/'models/greenstar/source-hashes.json').write_text(json.dumps(hashes, indent=2)+'\n')
    print(f'Imported {len(hashes)} original assets without binary changes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    main(parser.parse_args().source)
