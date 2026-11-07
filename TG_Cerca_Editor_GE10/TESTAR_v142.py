"""Windows regression v1.4.2: fios, painel minimo, comprimento da porteira."""
import math
import tempfile
from pathlib import Path
from xml.etree import ElementTree as ET

import TG_Cerca_Editor_v09 as active
from TG_Cerca_Editor_v142 import App
from TG_Cerca_Geometria_Nativa_v142 import (
    build_fence_v08, gate_span, gate_on_spline,
    panel_segments, segment_profile)
from TG_Cerca_Segmentos_Originais_v091 import (
    build_fence_v08 as old_two_meter_builder)
from TG_Cerca_AntiDuplicatas_v09 import scan_overlapping_fences


def mod_fixture(folder, panel="4"):
    mod=folder/"FS25_RealPanelTest"
    (mod/"xml").mkdir(parents=True)
    (mod/"i3d").mkdir()
    xml="xml/fence.xml"
    (mod/"modDesc.xml").write_text(
        '<modDesc><storeItems><storeItem xmlFilename="xml/fence.xml" />'
        '</storeItems></modDesc>',encoding="utf-8")
    (mod/xml).write_text(f'''<placeable type="newFence">
    <storeData><showInStore>true</showInStore><canBeSold>true</canBeSold></storeData>
    <base><filename>i3d/fence.i3d</filename></base>
    <fence>
      <segment id="SEGMENT" class="FenceSegment">
        <poles><pole node="pole01" radius="0.0"/></poles>
        <panels maxScale="1.2"><panel node="panel01" length="{panel}"/></panels>
      </segment>
      <segment id="GATE_10m" class="FenceGate">
        <gate node="0>0" length="5.4"/></segment>
      <segment id="GATE_5m" class="FenceGate">
        <gate node="0>1" length="5.4"/></segment>
      <segment id="GATE_8m" class="FenceGate">
        <gate node="0>2" length="5.4"/></segment>
      <segment id="GATE_6m" class="FenceGate">
        <gate node="0>3" length="5.4"/></segment>
    </fence>
    <i3dMappings>
      <i3dMapping id="pole01" node="1>0"/>
      <i3dMapping id="panel01" node="2>0"/>
    </i3dMappings></placeable>''',encoding="utf-8")
    (mod/"i3d/fence.i3d").write_text('''<i3D><Scene>
    <TransformGroup name="gates">
      <TransformGroup name="gate10m">
        <Shape name="poste" translation="0.037476 0 0"/>
        <Shape name="poste" translation="10.3481 0 0"/></TransformGroup>
      <TransformGroup name="gate5m">
        <Shape name="poste" translation="0.037476 0 0"/>
        <Shape name="poste"/></TransformGroup>
      <TransformGroup name="gate8m">
        <Shape name="poste"/>
        <Shape name="poste" translation="8.33728 0 0"/></TransformGroup>
      <TransformGroup name="gate6m">
        <Shape name="poste" translation="0 0 0"/>
        <Shape name="poste" translation="5.32538 0 0"/></TransformGroup>
    </TransformGroup></Scene></i3D>''',encoding="utf-8")
    return mod,xml


def test_native_lengths(folder):
    for panel,total in ((4.,100.),(6.7,100.),(3.8,100.),(4.,500.)):
        pts=[(float(i)*total/1000.,65.,0.) for i in range(1001)]
        edges,report=panel_segments(pts,panel,1.2)
        assert report["min_chord"]>=panel-1e-6,report
        assert report["max_chord"]<=panel*1.2+1e-6,report
        assert len(edges)<total/2+1
        assert edges[0][0]==pts[0] and edges[-1][1]==pts[-1]
        assert all(math.dist(b,c)<1e-8 for (a,b),(c,d) in zip(edges,edges[1:]))
        print(f"OK {total:g} m com painel {panel:g} => {len(edges)} segmentos e fios.")
    for length in (2.,3.9,5.):
        try:
            panel_segments([(0.,0.,0.),(length,0.,0.)],4.,1.2)
        except ValueError:
            pass
        else:
            raise AssertionError(f"Trecho {length:g}m não podia passar com painel 4m")
    print("OK bloqueia segmentos de 2 m e trechos impossíveis para não perder fios.")


def test_gate_width(folder):
    mod,xml=mod_fixture(folder)
    assert math.isclose(gate_span(mod,xml,"GATE_10m")[0],10.310624,abs_tol=.001)
    assert math.isclose(gate_span(mod,xml,"GATE_8m")[0],8.33728,abs_tol=.001)  # outro poste na origem
    assert math.isclose(gate_span(mod,xml,"GATE_6m")[0],5.32538,abs_tol=.001)
    assert gate_span(mod,xml,"GATE_5m")==(5.4,"XML")
    pts=[(i*1.,65.,0.) for i in range(101)]
    lo,hi,a,b,total=gate_on_spline(pts,50.,10.310624,4.)
    assert math.isclose(lo,44.844688,abs_tol=.002)
    assert math.isclose(hi,55.155312,abs_tol=.002)
    assert math.isclose(math.dist(a,b),10.310624,abs_tol=.002)
    print("OK porteira real 10.31m em vez dos 5.4m incorretos do XML.")


def test_output_and_legacy(folder):
    mod,xml=mod_fixture(folder)
    save=folder/"placeables.xml"
    save.write_text('<placeables/>',encoding="utf-8")
    pts=[(i*1.,65.,0.) for i in range(101)]
    oldtree,oldrows,*_=old_two_meter_builder(
        pts,mod,xml,save,"GATE_10m",50.)
    assert any(math.dist(a,b)<3. for a,b,k in oldrows if k=="SEGMENT")
    oldtree.write(save,encoding="utf-8")
    assert active.build_fence_v08 is build_fence_v08
    newtree,rows,reports,total,spec=build_fence_v08(
        pts,mod,xml,save,"GATE_10m",50.,farm_id=1)
    assert len(rows)<len(oldrows)
    gate=[x for x in rows if x[2]=="GATE_10m"]
    assert len(gate)==1
    assert math.isclose(math.dist(gate[0][0],gate[0][1]),10.310624,abs_tol=.002)
    assert spec["gate_xml_length"]==5.4
    assert spec["gate_length_source"]=="I3D"
    assert all(math.dist(a,b)>=4.-1e-6 for a,b,kind in rows if kind=="SEGMENT")
    assert all(math.dist(a,b)<=4.8+1e-5 for a,b,kind in rows if kind=="SEGMENT")
    assert all(math.dist(a[1],b[0])<1e-9 for a,b in zip(rows,rows[1:]))
    tags=newtree.findall("./placeable/newFence/segment")
    assert len(tags)==len(oldrows)+len(rows), (len(tags),len(oldrows),len(rows))
    duplicates,conflicts=scan_overlapping_fences(newtree,newtree.getroot()[-1])
    assert len(duplicates)==1 and not conflicts,(duplicates,conflicts)
    assert ET.parse(save).findall("./placeable/newFence/segment")
    print("OK grava segmentos sem fios faltando, sem vão nos encontros, "
          "e detecção de cerca antiga preservada.")


def test_curved_gate(folder):
    mod,xml=mod_fixture(folder)
    bent=[(0.,65.,0.),(30.,65.,0.),(38.,65.,8.),(50.,65.,8.),
          (70.,65.,8.),(100.,65.,8.)]
    # Uma curva forte no centro precisa avisar em vez de encaixar porteira de lado.
    try:
        gate_on_spline(bent,34.,10.310624,4.)
    except ValueError:
        print("OK curva fechada: geração bloqueada (sem porta atravessada).")
    else:
        raise AssertionError("Porteira na curva deveria ser bloqueada.")
    smooth=[(i*.5,60.+0.1*math.sin(i/20),3.*math.sin(i/100))
            for i in range(401)]
    edges,report=panel_segments(smooth,4.,1.2)
    assert report["min_chord"]>=4.-1e-6,report
    print("OK curva suave preserva todos painéis.")


def test_gui(folder):
    mod,xml=mod_fixture(folder)
    app=App()
    try:
        app.update()
        app.mods={mod.name:mod}
        app.fencemod.set(mod.name)
        app.fencexml.set(xml)
        app.native_gate.set("GATE_10m")
        width,panel=app._gate_width()
        assert math.isclose(width,10.310624,abs_tol=.002)
        assert panel==4.
        app.open_pcobjects()
        app.update()
        assert app.state()=="iconic"
        app.pc_window.close_and_restore()
        app.update()
        assert app.state()=="normal"
        print("OK interface PC Objects e minimização v1.4.1 mantidas, "
              "prévia da porteira usa tamanho físico.")
    finally:
        app.destroy()


if __name__=="__main__":
    with tempfile.TemporaryDirectory() as t:
        folder=Path(t)
        test_native_lengths(folder)
        test_gate_width(folder)
        test_output_and_legacy(folder)
        test_curved_gate(folder)
        test_gui(folder)
    print("TODOS TESTES FS25 v1.4.2 PASSARAM; TESTAR VISUAL/ANIMACAO NO JOGO.")
