"""Testa deteccao conservadora de cercas FS25 duplicadas da versao v0.9."""
from __future__ import annotations
import math
import tempfile
from pathlib import Path
from xml.etree import ElementTree as ET

from TESTAR_v08 import build_test_mod
from TG_Cerca_Editor_v08 import build_fence_v08
from TG_Cerca_AntiDuplicatas_v09 import (
    scan_overlapping_fences,remove_confirmed_duplicates)
from TG_Cerca_Editor_v09 import App

def sample_points(start=0,stop=200,shift=0):
    return [(float(i),65.,float(shift)) for i in range(start,stop+1)]

def write(path,tree):
    tree.write(path,encoding="utf-8",xml_declaration=True)

def test_exact_replacement(folder,mod,xml):
    target=folder/'placeables.xml'
    target.write_text('<placeables><placeable uniqueId="KEEP"/><note>manter</note></placeables>',encoding="utf-8")
    old,*_=build_fence_v08(sample_points(),mod,xml,target,'GATE_5m',50,max_span=80,farm_id=1)
    write(target,old)
    proposed,*_=build_fence_v08(sample_points(),mod,xml,target,'GATE_5m',70,max_span=80,farm_id=1)
    new=proposed.getroot()[-1]
    duplicates,conflicts=scan_overlapping_fences(proposed,new)
    assert len(duplicates)==1,(duplicates,conflicts)
    assert not conflicts
    # A busca não pode alterar o arquivo nem o XML na memória.
    assert len(proposed.findall('./placeable/newFence'))==2
    assert len(ET.parse(target).findall('./placeable/newFence'))==1
    count=remove_confirmed_duplicates(proposed,new,duplicates)
    assert count==1 and len(proposed.findall('./placeable/newFence'))==1
    assert proposed.find('./placeable[@uniqueId="KEEP"]') is not None
    assert proposed.find('./note') is not None
    assert proposed.find('./placeable/newFence/segment[@id="GATE_5m"]') is not None
    write(target,proposed)
    new2,*_=build_fence_v08(sample_points(),mod,xml,target,'GATE_5m',80,max_span=80,farm_id=1)
    copy=new2.getroot()[-1]
    assert len(scan_overlapping_fences(new2,copy)[0])==1
    print('OK: substitui antiga por nova apos confirmar, preserva outros objetos e previne repetir.')

def test_multiple(folder,mod,xml):
    target=folder/'multiplas.xml'
    target.write_text('<placeables/>',encoding='utf-8')
    old,*_=build_fence_v08(sample_points(),mod,xml,target,'GATE_5m',50,max_span=80,farm_id=1)
    write(target,old)
    second,*_=build_fence_v08(sample_points(),mod,xml,target,'GATE_10m',50,max_span=80,farm_id=1)
    write(target,second)
    proposed,*_=build_fence_v08(sample_points(),mod,xml,target,'GATE_5m',65,max_span=80,farm_id=1)
    candidate=proposed.getroot()[-1]
    duplicate,conflicts=scan_overlapping_fences(proposed,candidate)
    assert len(duplicate)==2 and not conflicts,(duplicate,conflicts)
    removed=remove_confirmed_duplicates(proposed,candidate,duplicate)
    assert removed==2 and len(proposed.findall('./placeable/newFence'))==1
    print('OK: detecta e remove apenas apos confirmacao duas cercas anteriores coincidentes.')

def test_partial_and_other(folder,mod,xml):
    target=folder/'parcial.xml'
    target.write_text('<placeables/>',encoding='utf-8')
    old,*_=build_fence_v08(sample_points(0,130),mod,xml,target,'GATE_5m',50,max_span=80,farm_id=1)
    write(target,old)
    new,*_=build_fence_v08(sample_points(),mod,xml,target,'GATE_5m',70,max_span=80,farm_id=1)
    ds,cs=scan_overlapping_fences(new,new.getroot()[-1])
    assert not ds and len(cs)==1,(ds,cs)
    # Outras cercas em outro trecho do mapa devem continuar intocadas.
    far,*_=build_fence_v08(sample_points(0,200,shift=35),mod,xml,target,'GATE_5m',70,max_span=80,farm_id=1)
    assert not any(scan_overlapping_fences(far,far.getroot()[-1]))
    # Modelo diferente no mesmo trajeto precisa bloquear, e nao apagar.
    separate=folder/'othermodel.xml'
    separate.write_text('<placeables/>',encoding='utf-8')
    old,*_=build_fence_v08(sample_points(),mod,xml,separate,'GATE_5m',70,max_span=80,farm_id=1)
    old.getroot()[-1].set('filename','$moddir$FS25_OutroMod/xml/outraCerca.xml')
    write(separate,old)
    proposed,*_=build_fence_v08(sample_points(),mod,xml,separate,'GATE_5m',70,max_span=80,farm_id=1)
    ds,cs=scan_overlapping_fences(proposed,proposed.getroot()[-1])
    assert not ds and len(cs)==1,(ds,cs)
    print('OK: impede sobreposicao parcial e modelos diferentes sem apaga-los.')

def test_not_fence_and_invalid(folder,mod,xml):
    target=folder/'invalid.xml'
    target.write_text('''<placeables>
      <placeable filename="foo.xml" uniqueId="normal"><position>dummy</position></placeable>
      <placeable filename="other.xml"><newFence><segment start="invalido" end="0 0 0" id="SEGMENT"/></newFence></placeable>
    </placeables>''',encoding='utf-8')
    proposed,*_=build_fence_v08(sample_points(),mod,xml,target,'GATE_5m',50,max_span=80,farm_id=1)
    d,c=scan_overlapping_fences(proposed,proposed.getroot()[-1])
    assert d==[] and c==[]
    print('OK: nao apaga outros placeables nem XMLs de cerca incompletos.')

def test_gui():
    app=App()
    try:
        app.update_idletasks()
        app.update()
        assert 'v0.9' in app.title()
        assert not hasattr(app,'_image_src')
        assert app.native_gate_combo.grid_info()['row']==4
        assert app.dryrun.get()
        assert app.preview_canvas.winfo_width()>200
    finally:
        app.destroy()
    print('OK: janela v0.9 sem foto, porteira por clique e previa ativada.')

if __name__=='__main__':
    with tempfile.TemporaryDirectory() as d:
        folder=Path(d)
        mod,xml=build_test_mod(folder)
        test_exact_replacement(folder,mod,xml)
        test_multiple(folder,mod,xml)
        test_partial_and_other(folder,mod,xml)
        test_not_fence_and_invalid(folder,mod,xml)
    test_gui()
    print('TODOS OS TESTES V0.9 OK; testar no FS25 com copia de savegame')
