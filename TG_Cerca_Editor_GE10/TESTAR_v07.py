"""Testes automatizados da v0.7 sem executar FS25."""
import math
import tempfile
from pathlib import Path
import xml.etree.ElementTree as ET

from TG_Cerca_Geometria_v07 import aligned_segments
from TG_Cerca_Editor_v07 import build_fence_v07


def check_straight():
    samples=[(i*0.5,40.0,0.0) for i in range(1001)]
    for nominal in (3.8,4.0,6.7):
        parts,report=aligned_segments(samples,nominal,max_span=80.0)
        assert len(parts)<=8,(nominal,len(parts))
        assert parts[0][0] == samples[0]
        assert parts[-1][1] == samples[-1]
        assert all(math.hypot(b[0]-a[0],b[2]-a[2])<=80.001 for a,b in parts)
        assert report['panel_step_max']-report['panel_step_min']<1e-8
        for (a,b),(c,d) in zip(parts,parts[1:]):
            assert all(abs(b[j]-c[j])<1e-8 for j in range(3))
        print('OK reta 500m:',nominal,'m:',len(parts),'segmentos, passo:',round(report['panel_step_min'],4))
    pts=[(0.,0.,0.),(500.,0.,0.)]
    blocks,_=aligned_segments(pts,4.,80.)
    assert len(blocks)==7


def check_curves():
    curve=[(i*0.5,25.+2*math.sin(i*math.pi/100),
            20*math.sin(i*math.pi/100)) for i in range(201)]
    blocks,report=aligned_segments(curve,4.,max_span=80.,tolerance_xy=.35,tolerance_y=.18)
    assert report['corners']>2,report
    assert min(p[1] for a,b in blocks for p in (a,b))>=24
    assert max(p[1] for a,b in blocks for p in (a,b))>26
    assert max(p[2] for a,b in blocks for p in (a,b))>15
    print('OK curva e relevo:',len(blocks),'segmentos,',report['corners'],'vertices essenciais')


def check_mods():
    for i,nominal in enumerate((4.,6.7,4.,4.,3.8),1):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            mod=root/'FS25_BrazilianFences'
            (mod/'xml').mkdir(parents=True)
            name=f'xml/fencesFarmLevel0{i}.xml'
            (mod/'modDesc.xml').write_text(
                f'<modDesc><storeItems><storeItem xmlFilename="{name}"/></storeItems></modDesc>',
                encoding='utf-8')
            (mod/name).write_text(
                f'''<placeable type="newFence">
                 <storeData><canBeSold>true</canBeSold><category>fences</category></storeData>
                 <fence>
                   <segment id="SEGMENT" class="FenceSegment">
                     <panels><panel node="panel01" length="{nominal}"/></panels>
                     <poles><pole node="pole01" radius="0"/></poles>
                   </segment>
                   <segment id="GATE_10m" class="FenceGate"><gate node="gate1" length="5.4"/></segment>
                 </fence>
                 <i3dMappings><i3dMapping id="panel01" node="2|0"/><i3dMapping id="pole01" node="1|0"/></i3dMappings>
                 </placeable>''',encoding='utf-8')
            save=root/'placeables.xml'
            save.write_text('<placeables/>',encoding='utf-8')
            pts=[(float(j),50.,0.) for j in range(501)]
            tree,segments,reports,total,spec=build_fence_v07(
                pts,mod,name,save,max_span=80.,farm_id=1)
            assert total==500 and len(segments)<=8
            assert len(tree.findall('./placeable/newFence/segment'))==len(segments)
            assert tree.find('./placeable').get('farmId')=='1'
            assert spec['panel_length']==nominal
            gtree,gseg,grep,_,_=build_fence_v07(
                pts,mod,name,save,native_gate_id='GATE_10m',max_span=80.,farm_id=1)
            ids=[x.get('id') for x in gtree.findall('./placeable/newFence/segment')]
            assert ids.count('GATE_10m')==1
            assert ids.index('GATE_10m')>0 and ids.index('GATE_10m')<len(ids)-1
            assert len(gseg)<20
            print('OK novoFence modelo',i,'painel:',nominal,'m')
            

if __name__=='__main__':
    check_straight()
    check_curves()
    check_mods()
    print('TESTES GEOMETRIA E XML OK — validacao de espaco entre postes exige FS25')
