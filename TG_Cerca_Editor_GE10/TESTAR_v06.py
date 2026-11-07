"""Testes sem janela real e sem carregar o FS25."""
from __future__ import annotations
import base64
import io
import tempfile
from pathlib import Path
from PIL import Image
import TG_Cerca_Editor_v06 as v06
import TG_Cerca_Editor_v05 as v05
from tg_brand_photo_v06 import BG_JPEG_B64

blob=base64.b64decode(BG_JPEG_B64,validate=True)
image=Image.open(io.BytesIO(blob))
image.verify()
print('OK: fundo do trator decodificado:',len(blob),'bytes')

assert v05.run_compaction_tests()[0]==20
print('OK: 500m reta agrupados em 20 trechos XML')

for i, panel_length in enumerate((4.0,6.7,4.0,4.0,3.8),1):
    with tempfile.TemporaryDirectory() as t:
        mod=Path(t)/f'FS25_BrazilianFences{i}'
        mod.mkdir()
        xml=f'xml/fencesFarmLevel0{i}.xml'
        (mod/'xml').mkdir()
        (mod/'modDesc.xml').write_text(
            f'<modDesc><storeItems><storeItem xmlFilename="{xml}"/></storeItems></modDesc>',
            encoding='utf-8')
        (mod/xml).write_text(
            f'''<placeable type="newFence">
            <storeData><canBeSold>true</canBeSold><category>fences</category>
            <brush><type>newFence</type></brush></storeData>
            <fence>
              <segment id="SEGMENT" class="FenceSegment">
                <panels><panel node="panel01" length="{panel_length}"/></panels>
                <poles><pole node="pole01" radius="0"/></poles>
              </segment>
              <segment id="GATE_10m" class="FenceGate"><gate node="0>0" length="5.4"/></segment>
            </fence>
            <i3dMappings>
              <i3dMapping id="panel01" node="1|0"/>
              <i3dMapping id="pole01" node="2|0"/>
            </i3dMappings>
            </placeable>''',encoding='utf-8')
        spec=v06.model_details(mod, xml)
        assert spec['panel_length']==panel_length and spec['registered'] and spec['can_sell']
        assert spec['gates']['GATE_10m']==5.4
        dst=Path(t)/'placeables.xml'
        dst.write_text('<placeables/>',encoding='utf-8')
        pts=[(float(j),50.0,0.0) for j in range(501)]
        tree,count,total,length=v05.create_fence_v03(
            pts,mod,xml,dst,panel_max_length=25.0)
        assert count==20,(i,count)
        assert total==500.0 and length==panel_length
        assert tree.find('./placeable/newFence') is not None
        print('OK:',xml,'painel:',panel_length,'m, segmentos:',count)

print('TODOS OS TESTES OK - aguardando testes reais de demolição no FS25')
