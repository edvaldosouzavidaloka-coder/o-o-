"""TG + EDVALDO: segmento estilo da primeira versao (v0.1) no FS25.

A primeira versao criava uma linha <segment> entre cada par de amostras.
O exportador original amostrava a spline a cada 2m. Reproduzimos isso
diretamente no arquivo I3D, sem compactacao e sem mexer em porteiras/UI.
"""
from __future__ import annotations

import math
import uuid
import xml.etree.ElementTree as ET

import TG_Cerca_Editor as base
from TG_Cerca_Editor_v08 import model_details, gate_interval

ORIGINAL_SAMPLE_METERS = 2.0


def original_points(points, spacing=ORIGINAL_SAMPLE_METERS):
    """Amostragem a cada 2m, como o Lua TG_ExportarSpline da v0.1."""
    if not math.isfinite(spacing) or spacing <= 0.05:
        raise ValueError('Distancia de amostragem invalida.')
    if len(points) < 2:
        raise ValueError('Spline precisa ter dois pontos.')
    cumulative = base.cumulative(points)
    length = cumulative[-1]
    if length <= 0.05:
        raise ValueError('Spline curta demais.')
    # O primeiro exportador calculava ceil(length / 2), resultando em
    # distancias levemente menores que 2m quando nao era divisivel.
    steps = max(1, math.ceil(length / spacing))
    if steps > 30000:
        raise ValueError('Spline longa demais para exportar. Divida a cerca.')
    return [base.at_distance(points, cumulative, length * i / steps)
            for i in range(steps + 1)]


def build_fence_v08(points, mod, xml, target, gate_id='', gate_pct=50.0,
                    max_span=80.0, tolerance_xy=0.35,
                    tolerance_y=0.18, farm_id=1):
    """Assinatura identica a v0.8 para preservar a tela e a logica da v0.9.

    max_span e tolerancias sao mantidos para compatibilidade da interface;
    na geracao por segmento original nao existe simplificacao de 80 metros.
    """
    spec = model_details(mod, xml)
    panel = spec['panel_length']
    if gate_id and gate_id not in spec['gates']:
        raise ValueError('Porteira não declarada neste XML.')
    if not isinstance(farm_id, int) or not 0 <= farm_id <= 255:
        raise ValueError('Farm ID fora do intervalo de 0 a 255.')
    acc = base.cumulative(points)
    total = acc[-1]
    if total <= panel:
        raise ValueError('Spline curta demais para este painel.')
    if gate_id:
        gate_width = spec['gates'][gate_id]
        lo,mid,hi,total = gate_interval(points, gate_pct, gate_width, margin=panel)
        pieces = [
            (base.between(points,acc,0,lo),'SEGMENT'),
            ([base.at_distance(points,acc,lo),base.at_distance(points,acc,hi)],gate_id),
            (base.between(points,acc,hi,total),'SEGMENT')
        ]
    else:
        pieces = [(points,'SEGMENT')]
    records=[]
    for part, segment_id in pieces:
        if segment_id=='SEGMENT':
            # Mesmo comportamento da primeira versao: linhas consecutivas
            # entre amostras da spline, nao um segmento de 80m.
            sample=original_points(part)
            records.extend((a,b,'SEGMENT') for a,b in zip(sample,sample[1:]))
        else:
            records.append((part[0],part[1],segment_id))
    if not records:
        raise ValueError('Nenhum segmento de cerca foi gerado.')
    tree = ET.parse(target)
    root = tree.getroot()
    if root.tag != 'placeables':
        raise ValueError('O XML de destino precisa ter raiz <placeables>.')
    obj = ET.SubElement(root, 'placeable', {
        'filename':base.as_network_filename(mod,xml),
        'modName':base.modname(mod),
        'uniqueId':'placeable'+uuid.uuid4().hex,
        'position':'0.000 -151.000 0.000',
        'rotation':'0.000 0.000 0.000',
        'age':'0.000000',
        'price':'100.000000',
        'farmId':str(farm_id)
    })
    fence = ET.SubElement(obj,'newFence')
    for a,b,segment_id in records:
        ET.SubElement(fence,'segment',{
            'start':base.pos(a),'end':base.pos(b),'id':segment_id
        })
    # reports nao era usado na v0.9; manter a assinatura para compatibilidade.
    return tree,records,[],total,spec
