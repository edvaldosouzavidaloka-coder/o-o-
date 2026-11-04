"""Build original, scalable vehicle artwork for the TG GPS map.

Requires Pillow 13. DDS sprites have a full BC3 mip chain. The cab uses the
same artwork as coplanar vector meshes: hidden surfaces are cut away here, so
small colored details never fight over depth thousands of metres from origin.
"""
from collections import defaultdict
from io import BytesIO
from math import cos, sin, pi
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PALETTE = {
    'outline': '#13221b', 'tire': '#182126', 'tread': '#3c484d',
    'rim': '#e4b932', 'rimShadow': '#9c7924', 'green': '#327e43',
    'greenDark': '#205931', 'greenLight': '#66a853', 'yellow': '#f1ce4c',
    'glass': '#275765', 'glassLight': '#72a4a9', 'glint': '#c5dfd9',
    'steel': '#7c8d87', 'vent': '#173a2b', 'white': '#eef1dc',
}


def area(p):
    return sum(a[0]*b[1]-a[1]*b[0] for a, b in zip(p, p[1:]+p[:1]))/2


def clip(p, a, b, inside=True):
    if not p:
        return []
    result=[]
    def distance(q):
        d=(b[0]-a[0])*(q[1]-a[1])-(b[1]-a[1])*(q[0]-a[0])
        return d if inside else -d
    q=p[-1];dq=distance(q)
    for r in p:
        dr=distance(r)
        if (dq>=-1e-8)!=(dr>=-1e-8):
            t=dq/(dq-dr)
            result.append((q[0]+(r[0]-q[0])*t,q[1]+(r[1]-q[1])*t))
        if dr>=-1e-8:
            result.append(r)
        q,dq=r,dr
    return result if len(result)>=3 and abs(area(result))>1e-6 else []


def bounds(p):
    return min(x for x,y in p),min(y for x,y in p),max(x for x,y in p),max(y for x,y in p)


def subtract(p, cutter):
    ax,ay,bx,by=bounds(p);cx,cy,dx,dy=bounds(cutter)
    if bx<=cx or dx<=ax or by<=cy or dy<=ay:
        return [p]
    outside=[];remaining=p
    for a,b in zip(cutter,cutter[1:]+cutter[:1]):
        fragment=clip(remaining,a,b,False)
        if fragment:
            outside.append(fragment)
        remaining=clip(remaining,a,b)
        if not remaining:
            break
    return outside


def rounded(x,y,w,h,r=0):
    if not r:
        return [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]
    r=min(r,w/2,h/2)
    points=[]
    for cx,cy,start in [(x+w-r,y+r,-pi/2),(x+w-r,y+h-r,0),
                        (x+r,y+h-r,pi/2),(x+r,y+r,pi)]:
        for i in range(9):
            angle=start+i*pi/16
            points.append((cx+cos(angle)*r,cy+sin(angle)*r))
    return points


def artwork(kind):
    parts=[]
    def add(color,points):
        if area(points)<0:
            points=list(reversed(points))
        parts.append((color,points))
    def rect(color,x,y,w,h,r=0):
        add(color,rounded(x,y,w,h,r))
    def wheel(x,y,w,h):
        rect('tire',x,y,w,h,7)
        for i in range(4):
            yy=y+7+i*(h-16)/4
            add('tread',[(x+3,yy+3),(x+w/2,yy+7),(x+w/2,yy+11),(x+3,yy+7)])
            add('tread',[(x+w/2,yy+7),(x+w-3,yy+3),(x+w-3,yy+7),(x+w/2,yy+11)])
        rect('rimShadow',x+w*.34,y+h*.29,w*.32,h*.42,4)
        rect('rim',x+w*.40,y+h*.34,w*.23,h*.32,3)

    if kind=='tractor':
        rect('outline',93,38,70,181,15)
        rect('greenDark',98,43,60,172,11)
        wheel(58,148,38,73);wheel(160,148,38,73)
        wheel(73,45,27,48);wheel(156,45,27,48)
        rect('steel',99,185,58,12,4)
        rect('green',105,36,46,114,12)
        rect('greenLight',112,41,33,87,10)
        rect('yellow',106,80,44,5,2)
        rect('vent',116,49,24,20,5)
        for y in range(53,68,4):rect('greenDark',119,y,18,1.5)
        rect('white',110,37,8,5,2);rect('white',138,37,8,5,2)
        rect('outline',91,122,74,63,12)
        rect('glass',96,127,64,51,9)
        rect('glassLight',102,131,52,35,6)
        add('glint',[(105,133),(125,133),(110,159),(103,159)])
        rect('green',95,163,66,21,5)
        rect('greenLight',102,166,52,9,3)
        rect('steel',121,207,14,17,3)
        rect('yellow',116,216,24,6,2)
    else:
        rect('outline',87,43,82,179,16)
        wheel(62,67,34,69);wheel(160,67,34,69)
        wheel(76,181,27,42);wheel(153,181,27,42)
        rect('greenDark',91,49,74,168,12)
        rect('green',96,91,64,117,12)
        rect('greenLight',102,100,52,66,9)
        rect('outline',96,60,64,48,10)
        rect('glass',101,65,54,38,7)
        rect('glassLight',106,69,44,23,5)
        add('glint',[(109,71),(128,71),(113,89),(106,89)])
        rect('greenLight',100,53,56,13,4)
        rect('yellow',98,110,60,5,2)
        rect('greenDark',111,124,34,40,6)
        rect('vent',109,176,38,20,5)
        for x in range(114,145,5):rect('steel',x,179,2,14)
        rect('greenLight',155,116,15,73,6)
        rect('steel',161,119,5,59,2)
        rect('green',113,31,30,32,6)
        if kind=='combine_cutter':
            rect('outline',32,25,192,28,6)
            rect('greenDark',35,28,186,22,4)
            rect('greenLight',40,29,176,6,2)
            rect('steel',40,40,176,3)
            for x in range(45,219,12):rect('green',x,35,3,12)
            rect('yellow',39,47,178,3,1)
    return parts


def dds_with_mips(im, path):
    levels=[]
    while True:
        out=BytesIO();im.save(out,format='DDS',pixel_format='DXT5')
        levels.append(out.getvalue())
        if im.width==1 and im.height==1:
            break
        im=im.resize((max(1,im.width//2),max(1,im.height//2)),Image.Resampling.LANCZOS)
    header=bytearray(levels[0][:128])
    struct.pack_into('<I',header,8,struct.unpack_from('<I',header,8)[0]|0x20000)
    struct.pack_into('<I',header,20,len(levels[0])-128)
    struct.pack_into('<I',header,28,len(levels))
    struct.pack_into('<I',header,108,0x1000|0x8|0x400000)
    path.write_bytes(header+b''.join(level[128:] for level in levels))


def main():
    model=ET.Element('i3D',name='TGVehicleSymbols',version='1.6')
    ET.SubElement(model,'Asset')
    files=ET.SubElement(model,'Files')
    ET.SubElement(files,'File',fileId='1',filename='../shaders/tgGpsLcdShader.xml')
    materials=ET.SubElement(model,'Materials')
    ids={name:i+1 for i,name in enumerate(PALETTE)}
    for name,color in PALETTE.items():
        m=ET.SubElement(materials,'Material',name=name,materialId=str(ids[name]),
            diffuseColor='1 1 1 1',specularColor='0 0 0',customShaderId='1')
        rgb=[int(color[i:i+2],16)/255 for i in (1,3,5)]
        ET.SubElement(m,'CustomParameter',name='lcdTint',value=' '.join(f'{v:.6f}' for v in rgb)+' 1')
        ET.SubElement(m,'CustomParameter',name='lcdBrightness',value='0.05 0 0 0')
    shapes=ET.SubElement(model,'Shapes');scene=ET.SubElement(model,'Scene')
    serial=1
    target=ROOT/'models/textures';target.mkdir(exist_ok=True)
    for kind in ['tractor','combine','combine_cutter']:
        parts=artwork(kind)
        image=Image.new('RGBA',(2048,2048))
        draw=ImageDraw.Draw(image)
        for color,points in parts:draw.polygon([(x*8,y*8) for x,y in points],fill=PALETTE[color])
        image=image.resize((1024,1024),Image.Resampling.LANCZOS)
        dds_with_mips(image,target/(kind+'.dds'))
        # Non-overlapping convex fragments keep every color at one depth plane.
        meshes=defaultdict(list)
        for index,(color,polygon) in enumerate(parts):
            fragments=[polygon]
            for _,cutter in parts[index+1:]:
                fragments=[p for f in fragments for p in subtract(f,cutter)]
                if not fragments:break
            meshes[color].extend(fragments)
        group=ET.SubElement(scene,'TransformGroup',name='symbol_'+kind,nodeId=str(serial));serial+=1
        for color,polygons in meshes.items():
            vertices=[];triangles=[]
            for polygon in polygons:
                p=[(x/256-.5,.5-y/256) for x,y in polygon]
                if area(p)<0:p.reverse()
                first=len(vertices);vertices.extend(p)
                for i in range(1,len(p)-1):
                    a,b,c=p[0],p[i],p[i+1]
                    if abs(area([a,b,c]))>1e-12:triangles.append((first,first+i,first+i+1))
            shape=ET.SubElement(shapes,'IndexedTriangleSet',name=kind+'_'+color,shapeId=str(serial),
                meshUsage='0',bvCenter='0 0 0',bvRadius='0.708',isOptimized='true')
            vs=ET.SubElement(shape,'Vertices',count=str(len(vertices)),normal='true')
            for x,y in vertices:ET.SubElement(vs,'v',p=f'{x:.8f} {y:.8f} 0',n='0 0 1')
            ts=ET.SubElement(shape,'Triangles',count=str(len(triangles)))
            for tri in triangles:ET.SubElement(ts,'t',vi=' '.join(map(str,tri)))
            subset=ET.SubElement(shape,'Subsets',count='1')
            ET.SubElement(subset,'Subset',firstVertex='0',numVertices=str(len(vertices)),firstIndex='0',numIndices=str(len(triangles)*3))
            ET.SubElement(group,'Shape',name=kind+'_'+color,shapeId=str(serial),nodeId=str(serial),
                materialIds=str(ids[color]),castsShadows='false',receiveShadows='false')
            serial+=1
    ET.indent(model)
    ET.ElementTree(model).write(ROOT/'models/tgGPSVehicleSymbols.i3d',encoding='utf-8',xml_declaration=True)
    print('Generated three 1024px mipmapped DDS icons and matching flat vector meshes.')


if __name__=='__main__':main()
