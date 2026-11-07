"""Testes v1.0 de fidelidade ao tamanho dos paineis do FS25."""
from __future__ import annotations
import math
from pathlib import Path
import tempfile

from TG_Cerca_Geometria_Precisa_v10 import station_points,exact_fence_edges
from TG_Cerca_Editor_v10 import build_fence_v10,App
from TG_Cerca_Editor_v08 import build_fence_v08
from TG_Cerca_AntiDuplicatas_v09 import scan_overlapping_fences
from TESTAR_v08 import build_test_mod


def test_straights():
    samples=[(i*.5,30.,0.) for i in range(1001)]
    expected={4.0:125,6.7:75,3.8:132}
    for panel,count in expected.items():
        edges,report=exact_fence_edges(samples,panel,1)
        assert len(edges)==count and report['count']==count,(panel,report)
        assert all(math.dist(a,b)<=panel+1e-8 for a,b in edges)
        assert all(math.isclose(math.dist(a,b),report['nominal_step'],abs_tol=1e-8)
                   for a,b in edges)
        assert edges[0][0]==samples[0] and edges[-1][1]==samples[-1]
        assert max(math.dist(b,c) for (_,b),(c,_) in zip(edges,edges[1:]))<1e-7
        print('OK modelo',panel,'m:',len(edges),'segmentos; passo',round(report['nominal_step'],3))
    # Compactar somente uma reta PERFEITA, em pares (opcional).
    edges,report=exact_fence_edges(samples,4.,2)
    assert len(edges)==63 and report['count']==125

def test_curves():
    # Spline de curva: amostragem preserva curvatura local e a altimetria,
    # em vez de fazer uma reta entre extremidades distantes 80m.
    samples=[(i*.3,50+2*math.sin(i/40),10*math.sin(i/35)) for i in range(1001)]
    edges,report=exact_fence_edges(samples,4.,1)
    assert len(edges)>=75
    assert all(math.hypot(b[0]-a[0],b[2]-a[2])<=4.000001 for a,b in edges)
    assert max(abs(a[2]) for a,_ in edges)>9
    assert max(a[1] for a,_ in edges)>51.5
    print('OK curva:',len(edges),'paineis, max 4m')

def test_gates_and_duplicate():
    with tempfile.TemporaryDirectory() as t:
        mod,xml=build_test_mod(Path(t))
        save=Path(t)/'placeables.xml'
        save.write_text('<placeables/>',encoding='utf-8')
        pts=[(i*1.,65.,0.) for i in range(501)]
        result,rows,reports,total,spec=build_fence_v10(
            pts,mod,xml,save,'GATE_5m',70,grouping=1,farm_id=1)
        assert total==500
        assert len(rows)>100
        ids=[s.get('id') for s in result.findall('./placeable/newFence/segment')]
        assert ids.count('GATE_5m')==1
        i=ids.index('GATE_5m')
        assert all(k=='SEGMENT' for k in ids[:i]+ids[i+1:])
        gate=result.findall('./placeable/newFence/segment')[i]
        assert abs(float(gate.get('start').split()[0])-347.5)<.001
        assert abs(float(gate.get('end').split()[0])-352.5)<.001
        assert save.read_text(encoding='utf-8')=='<placeables/>'
        # Older version 0.8 created 80m sections, now replace with 4m sections.
        old,*_=build_fence_v08(pts,mod,xml,save,'GATE_5m',50,max_span=80,farm_id=1)
        old.write(save,encoding='utf-8')
        proposed, *_=build_fence_v10(pts,mod,xml,save,'GATE_5m',50,grouping=1,farm_id=1)
        prior,conflicts=scan_overlapping_fences(proposed,proposed.getroot()[-1])
        assert len(prior)==1 and not conflicts,(prior,conflicts)
        print('OK: porteira nativa de 5m, gap exato, detecta cerca antiga 80m')

def test_window():
    app=App()
    try:
        app.update()
        assert app.group_mode.get().startswith('PRECISO')
        assert app.group_box.grid_info()['row']==12
        assert not hasattr(app,'_image_src')
        assert app.dryrun.get() is True
    finally:
        app.destroy()
    print('OK janela escura, modo preciso default e backup mantidos')

if __name__=='__main__':
    test_straights()
    test_curves()
    test_gates_and_duplicate()
    test_window()
    print('TESTES FS25 v1.0: PASSOU. Inspecionar postes/fios no jogo antes do mapa principal.')
