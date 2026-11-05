"""Build bold, full-height vector glyphs for the physical LCD (Pillow)."""
from pathlib import Path
import xml.etree.ElementTree as E
from PIL import Image,ImageDraw,ImageFont
import shutil

ROOT=Path(__file__).resolve().parents[1]
path=ROOT/'models/tgGPSMonitorPrimitives.i3d'
root=E.parse(path).getroot()
regular=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',96)
bold=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',96)
font=regular
cap=font.getbbox('H');cap_height=cap[3]-cap[1]
em_width=font.getlength('M')
extra=[176,193,195,201,211,199,225,224,227,226,233,234,237,243,244,245,250,231]
shapes=root.find('Shapes');scene=root.find('./Scene/TransformGroup')
advances={32:font.getlength(' ')/cap_height*.92}
for code in list(range(33,127))+extra:
    char=chr(code);font=bold if char.isdigit() else regular;bbox=font.getbbox(char)
    advances[code]=font.getlength(char)/cap_height*.92
    image=Image.new('L',(max(1,bbox[2]-bbox[0]),max(1,bbox[3]-bbox[1])))
    ImageDraw.Draw(image).text((-bbox[0],-bbox[1]),char,font=font,fill=255)
    # One rectangle for each continuous vertical run; exact edge coordinates
    # are shared so glyph strokes cannot z-fight with one another.
    runs=[];previous={}
    for y in range(image.height):
        spans=[];start=None
        for x in range(image.width+1):
            on=x<image.width and image.getpixel((x,y))>=100
            if on and start is None:start=x
            if not on and start is not None:spans.append((start,x));start=None
        current={}
        for a,b in spans:
            if (a,b) in previous:
                item=previous[(a,b)];item[3]=y+1
            else:item=[a,b,y,y+1];runs.append(item)
            current[(a,b)]=item
        previous=current
    # Use the same 0.64-em advance as the Lua renderer, with a small gutter.
    nodes=[root.find('.//Scene//Shape[@name="'+prefix+str(code)+'"]') for prefix in ('text_','textWhite_')]
    existing=nodes[0]
    if existing is not None:
        sid=existing.get('shapeId');old=root.find('./Shapes/IndexedTriangleSet[@shapeId="'+sid+'"]');shapes.remove(old)
    else:
        sid=str(max(int(s.get('shapeId')) for s in shapes)+1)
        for prefix,material in [('text_',14),('textWhite_',20)]:
            E.SubElement(scene,'Shape',name=prefix+str(code),shapeId=sid,nodeId=str(10000+code*2+(material==20)),materialIds=str(material),castsShadows='false',receiveShadows='false')
    mesh=E.SubElement(shapes,'IndexedTriangleSet',name='boldGlyph'+str(code),shapeId=sid,meshUsage='0',bvCenter=f'{(bbox[0]+bbox[2])*.46/cap_height} {(2*cap[3]-bbox[1]-bbox[3])*.46/cap_height} 0',bvRadius=str(((bbox[2]-bbox[0])**2+(bbox[3]-bbox[1])**2)**.5*.46/cap_height+.002))
    vertices=E.SubElement(mesh,'Vertices',count=str(len(runs)*4),normal='true',uv0='true')
    triangles=E.SubElement(mesh,'Triangles',count=str(len(runs)*2))
    for index,(x1,x2,y1,y2) in enumerate(runs):
        left,right=(x1+bbox[0])/cap_height*.92,(x2+bbox[0])/cap_height*.92
        bottom,top=(cap[3]-y2-bbox[1])/cap_height*.92,(cap[3]-y1-bbox[1])/cap_height*.92
        for x,y in ((left,bottom),(right,bottom),(right,top),(left,top)):
            E.SubElement(vertices,'v',p=f'{x:.8f} {y:.8f} 0',n='0 0 1',t0='0 0')
        for ids in ((0,1,2),(0,2,3)):
            E.SubElement(triangles,'t',vi=' '.join(str(index*4+i) for i in ids))
    subsets=E.SubElement(mesh,'Subsets',count='1')
    E.SubElement(subsets,'Subset',firstVertex='0',numVertices=str(len(runs)*4),firstIndex='0',numIndices=str(len(runs)*6),uvDensity0='1')
E.ElementTree(root).write(path,encoding='utf-8',xml_declaration=True)
(ROOT/'scripts/TGGPSGlyphs.lua').write_text('TGGPSGlyphs={'+','.join(f'[{code}]={value:.8f}' for code,value in sorted(advances.items()))+'}\n')
license=Path('/usr/share/doc/fonts-dejavu-core/copyright')
if license.exists():(ROOT/'licenses/DejaVu-fonts.txt').write_text('\n'.join(line.rstrip() for line in license.read_text().splitlines())+'\n')
print('Bold vector glyphs: ASCII + Portuguese accents, original DDS untouched')
