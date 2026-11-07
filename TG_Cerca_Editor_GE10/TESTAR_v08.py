"""Regressoes v0.8: porteira posicionada por clique, fundo removido, XML certo."""
import math
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace
import xml.etree.ElementTree as ET

from TG_Cerca_Editor_v08 import (App,closest_distance_along_path,
                                  gate_interval,build_fence_v08)

def test_geometry():
    points=[(0.,50.,0.),(100.,50.,0.),(100.,50.,100.)]
    assert math.isclose(closest_distance_along_path(points,51,3),51,abs_tol=.01)
    assert math.isclose(closest_distance_along_path(points,102,70),170,abs_tol=.01)
    a,c,b,total=gate_interval(points,75,10,margin=4)
    assert (a,c,b,total)==(145,150,155,200)
    try:
        gate_interval(points,99,10,margin=4)
    except ValueError: pass
    else: raise AssertionError('Porteira fora da spline nao bloqueada')
    print('OK projeção de clique e limites da porteira')

def build_test_mod(root):
    mod=root/'FS25_PorteiraTeste'
    (mod/'xml').mkdir(parents=True)
    xml='xml/cercaComPorteira.xml'
    (mod/'modDesc.xml').write_text(
        f'<modDesc><storeItems><storeItem xmlFilename="{xml}"/></storeItems></modDesc>',
        encoding='utf-8')
    (mod/xml).write_text('''<placeable type="newFence">
      <storeData><canBeSold>true</canBeSold><category>fences</category></storeData>
      <fence>
        <segment id="SEGMENT" class="FenceSegment">
          <panels><panel node="panel01" length="4"/></panels>
          <poles><pole node="pole01" radius="0"/></poles>
        </segment>
        <segment id="GATE_5m" class="FenceGate"><gate node="gate" length="5.0"/></segment>
        <segment id="GATE_10m" class="FenceGate"><gate node="gate" length="10.0"/></segment>
      </fence>
      <i3dMappings><i3dMapping id="panel01" node="1|0"/>
        <i3dMapping id="pole01" node="2|0"/></i3dMappings>
    </placeable>''',encoding='utf-8')
    return mod,xml

def test_generation(root):
    mod,xml=build_test_mod(root)
    target=root/'placeables.xml'
    target.write_text('<placeables/>',encoding='utf-8')
    points=[(float(i),65.,0.) for i in range(201)]
    tree,records,reports,distance,spec=build_fence_v08(
        points,mod,xml,target,'GATE_5m',70,max_span=80,farm_id=1)
    assert distance==200
    assert spec['registered'] and spec['panel_length']==4
    fences=tree.findall('./placeable/newFence/segment')
    assert len(fences)==len(records)
    gate=[elem for elem in fences if elem.get('id')=='GATE_5m']
    assert len(gate)==1
    first=tuple(float(v) for v in gate[0].get('start').split())
    last=tuple(float(v) for v in gate[0].get('end').split())
    assert math.isclose(first[0],137.5,abs_tol=.01),first
    assert math.isclose(last[0],142.5,abs_tol=.01),last
    assert tree.find('./placeable').get('farmId')=='1'
    assert '<placeables/>' == target.read_text(encoding='utf-8')
    print('OK porteira GATE_5m em 70% e arquivo inalterado em prévia')
    return mod,xml

def test_gui(mod,xml,i3d_path):
    assert 'PIL' not in sys.modules, 'V08 nao deve importar imagem de fundo'
    app=App()
    try:
        app.update_idletasks()
        assert not hasattr(app,'_image_src')
        assert not hasattr(app,'_bg_bitmap')
        assert app.preview_canvas.winfo_width()>=400
        assert app.native_gate_combo.grid_info()['row']==4
        app.mods={mod.name: mod}
        app.fencemod.set(mod.name)
        app.update_fence()
        assert xml in app.fence_xml_box['values']
        app.fencexml.set(xml)
        app._chosen_fence_xml()
        assert app.native_gate.get()=='GATE_5m'
        app.spline.set(str(i3d_path))
        app.show_preview()
        assert app._preview_points and app._transform
        assert 'Porteira' in app.preview_status.cget('text')
        x0,z0,ox,oz,scale=app._transform
        pts=app._preview_points
        offset=closest_distance_along_path(pts,pts[len(pts)//2][0],pts[len(pts)//2][2])
        evt=SimpleNamespace(x=int(ox+(pts[len(pts)//2][0]-x0)*scale),
                            y=int(oz+(pts[len(pts)//2][2]-z0)*scale))
        app._click_preview(evt)
        assert 1<app.gate_pct.get()<99
        assert 'm do início' in app.preview_status.cget('text')
        print('OK interface preta sem foto, porteira escolhida e clique na prévia')
    finally:
        app.destroy()

if __name__=='__main__':
    test_geometry()
    with tempfile.TemporaryDirectory() as tmp:
        mod,xml=test_generation(Path(tmp))
        i3d=Path('..')/'leitor-i3d'/'TG_Cerca_Editor_GE10_v0.2'/'EXEMPLO'/'sa.i3d'
        assert i3d.is_file(),i3d
        test_gui(mod,xml,i3d)
    print('TODOS OS TESTES DA V08 PASSARAM; TESTAR MODELO 3D E DEMOLICAO DENTRO DO FS25')
