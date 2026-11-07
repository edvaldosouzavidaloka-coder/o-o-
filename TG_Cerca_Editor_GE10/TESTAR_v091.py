"""Testes do espaçamento original da v0.1 com interface v0.9 inalterada."""
import math
import tempfile
from pathlib import Path
import xml.etree.ElementTree as ET

from TG_Cerca_Segmentos_Originais_v091 import original_points,build_fence_v08
from TG_Cerca_Editor_v09 import App,build_fence_v08 as active_builder
from TG_Cerca_Editor_v08 import build_fence_v08 as compressed_builder
from TG_Cerca_AntiDuplicatas_v09 import scan_overlapping_fences
from TESTAR_v08 import build_test_mod


def run():
    assert active_builder is build_fence_v08
    line=[(float(i),45.,0.) for i in range(501)]
    original=original_points(line)
    assert len(original)==251,(len(original))
    assert original[0]==line[0] and original[-1]==line[-1]
    assert max(math.dist(a,b) for a,b in zip(original,original[1:]))<=2.00000001
    assert all(math.isclose(math.dist(a,b),2.,abs_tol=1e-9)
               for a,b in zip(original,original[1:]))
    print('OK: spline reta de 500m = 250 segmentos do exportador original, ~2m.')

    curved=[(i*.25,40+math.sin(i/50),6*math.sin(i/100)) for i in range(1001)]
    pp=original_points(curved)
    assert max(abs(p[2]) for p in pp)>5.8
    assert max(abs(p[1]-40) for p in pp)>.9
    assert all(math.hypot(b[0]-a[0],b[2]-a[2])<=2.000001
               for a,b in zip(pp,pp[1:]))
    print('OK: curvas e elevações sem compactação para 80m.')

    with tempfile.TemporaryDirectory() as tmp:
        root=Path(tmp)
        mod,xml=build_test_mod(root)
        target=root/'placeables.xml'
        target.write_text('<placeables><placeable uniqueId="KEEP"/></placeables>',encoding='utf-8')
        tree,records,reports,total,spec=build_fence_v08(
            line,mod,xml,target,'GATE_5m',gate_pct=50,max_span=80,
            tolerance_xy=.35,tolerance_y=.18,farm_id=1)
        assert spec['panel_length']==4
        assert total==500
        assert len(records)==249,(len(records))
        ids=[node.get('id') for node in tree.findall('./placeable/newFence/segment')]
        assert ids.count('GATE_5m')==1 and ids.count('SEGMENT')==248
        i=ids.index('GATE_5m')
        assert i>0 and i<len(ids)-1
        gate=tree.findall('./placeable/newFence/segment')[i]
        start=float(gate.get('start').split()[0])
        end=float(gate.get('end').split()[0])
        assert abs(start-247.5)<.001 and abs(end-252.5)<.001
        assert target.read_text(encoding='utf-8')=='<placeables><placeable uniqueId="KEEP"/></placeables>'
        print('OK: mesmo XML GATE_5m, abertura contínua e nenhuma escrita na prévia.')

        # Cercas geradas pela v0.9 antiga em trechos de até 80m devem ser
        # identificadas antes de escrever a versão com passo de 2m.
        old,*_=compressed_builder(line,mod,xml,target,'GATE_5m',gate_pct=50,max_span=80,farm_id=1)
        old.write(target,encoding='utf-8')
        proposal,*_=build_fence_v08(line,mod,xml,target,'GATE_5m',gate_pct=50,farm_id=1)
        duplicate,conflicts=scan_overlapping_fences(proposal,proposal.getroot()[-1])
        assert len(duplicate)==1 and not conflicts,(len(duplicate),len(conflicts))
        print('OK: anti-duplicatas v0.9 continua reconhecendo a cerca antiga.')

    app=App()
    try:
        app.update()
        assert 'v0.9' in app.title()
        assert app.max_span.get()==80
        assert app.preview_canvas.winfo_width()>200
        assert app.dryrun.get()
        assert not hasattr(app,'_image_src')
        assert app.native_gate_combo.grid_info()['row']==4
        print('OK: mesma interface v0.9, mesmos campos e prévia sem foto.')
    finally:
        app.destroy()

if __name__=='__main__':
    run()
    print('TODOS TESTES v0.9.1 OK - visual do FS25 exige teste in-game')
