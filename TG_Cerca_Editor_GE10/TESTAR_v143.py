"""FS25 v1.4.3 — regressão do erro real 247.29m com painel de 6.7m."""
from __future__ import annotations
import math
from pathlib import Path
import tempfile
from xml.etree import ElementTree as ET

import TG_Cerca_Editor as base
from TG_Cerca_Geometria_Nativa_v142 import panel_segments,build_fence_v08
from TG_Cerca_Editor_v143 import App
from TESTAR_v142 import mod_fixture


def _old_global_spacing_would_fail(points,panel,max_scale):
    """Replica somente a limitação do v1.4.2, para testar a regressão."""
    stations=base.cumulative(points)
    total=stations[-1]
    high=math.floor(total/panel+1e-7)
    for n in range(high,max(0,high-30),-1):
        if n<1:
            break
        if total/n>panel*max_scale+1e-5:
            break
        row=[base.at_distance(points,stations,total*i/n)
             for i in range(n+1)]
        chords=[math.hypot(b[0]-a[0],b[2]-a[2])
                for a,b in zip(row,row[1:])]
        if chords and min(chords)>=panel-1e-6 and max(chords)<=panel*max_scale+1e-5:
            return False
    return True


def test_247m_curve():
    # Um trecho com uma dobra de 90 graus; o algoritmo antigo distribuía
    # os vãos por distância de arco igual e não conseguia encaixar painéis.
    pts=[(0.,65.,0.),(125.,65.,0.),(125.,65.,122.29)]
    length=base.cumulative(pts)[-1]
    assert abs(length-247.29)<1e-6,length
    assert _old_global_spacing_would_fail(pts,6.7,1.2),(
        "O exemplo deixou de exercitar o erro de distribuição global.")
    edges,report=panel_segments(pts,6.7,1.2)
    assert 29<=len(edges)<=38,report
    assert report["adaptive"] and report["count"]==len(edges)
    assert min(math.hypot(b[0]-a[0],b[2]-a[2]) for a,b in edges)>=6.7-1e-5
    assert max(math.hypot(b[0]-a[0],b[2]-a[2]) for a,b in edges)<=8.04+1e-5
    assert edges[0][0]==pts[0] and edges[-1][1]==pts[-1]
    assert all(math.dist(a[1],b[0])<1e-8
               for a,b in zip(edges,edges[1:]))
    print("OK: trecho de 247.29m, curva de 90 graus, painel 6.7m; "
          f"sem erro e sem nenhum painel curto ({len(edges)} segmentos).")


def test_gate_xml(folder):
    mod,xml=mod_fixture(folder,panel="6.7")
    target=folder/"placeables.xml"
    target.write_text("<placeables/>",encoding="utf-8")
    pts=[(0.,65.,0.),(125.,65.,0.),(125.,65.,122.29)]
    tree,records,reports,total,spec=build_fence_v08(
        pts,mod,xml,target,"GATE_10m",gate_pct=80.,farm_id=1)
    assert math.isclose(total,247.29,abs_tol=1e-6)
    gates=[(a,b) for a,b,kind in records if kind=="GATE_10m"]
    assert len(gates)==1
    assert math.isclose(math.dist(gates[0][0],gates[0][1]),10.310624,abs_tol=.005)
    assert all(6.7-1e-5<=math.dist(a,b)<=8.04+1e-5
               for a,b,kind in records if kind=="SEGMENT")
    assert all(math.dist(a[1],b[0])<1e-8
               for a,b in zip(records,records[1:]))
    assert len(tree.findall("./placeable/newFence/segment"))==len(records)
    assert not ET.parse(target).findall("./placeable/newFence/segment"),(
        "Prévia modificou o arquivo antes do usuário confirmar.")
    print("OK: mesmo traçado com porteira real 10.31m e abertura sem fios.")


def test_hairpin_rejected():
    # Nem uma adaptação pode gerar um painel atravessando uma volta em U curta.
    pts=[(0.,65.,0.),(3.,65.,0.),(3.,65.,3.),
         (0.,65.,3.),(0.,65.,6.)]
    try:
        edges,report=panel_segments(pts,6.7,1.2)
    except ValueError:
        print("OK: curva impossível avisada sem criar postes soltos.")
    else:
        # Se encontrar solução física, deve verificar TODOS os painéis.
        assert all(6.7-1e-5<=math.dist(a,b)<=8.04+1e-5
                   for a,b in edges)
        assert all(math.dist(a[1],b[0])<1e-8
                   for a,b in zip(edges,edges[1:]))


def test_window():
    app=App()
    try:
        app.update()
        assert "v1.4.3" in app.title()
        app.open_pcobjects()
        app.update()
        assert app.state()=="iconic",app.state()
        app.pc_window.close_and_restore()
        app.update()
        assert app.state()=="normal"
        print("OK: janela principal e PC Objects v1.4.1 preservados.")
    finally:
        app.destroy()


if __name__=="__main__":
    test_247m_curve()
    with tempfile.TemporaryDirectory() as t:
        test_gate_xml(Path(t))
    test_hairpin_rejected()
    test_window()
    print("TODOS OS TESTES v1.4.3 OK — verificar visual no FS25.")
