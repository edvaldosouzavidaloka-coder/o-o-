"""TG + EDVALDO v1.4.2 — segmentos nativos FS25 com painel e porteira.

Não usar segmentos de ~2m para painéis de 3.8/4/6.7m: o FS25 não cria
os arames/ripas se o vão for menor que o painel. Só gera vãos que caibam
em [comprimento do painel, comprimento * maxScale do XML do mod].

A abertura da porteira segue a MESMA spline, e seu tamanho é estimado
pela distância entre os postes reais do I3D, não só pelo XML do mod.
"""
from __future__ import annotations
from bisect import bisect_right
from pathlib import Path
import math
import uuid
import xml.etree.ElementTree as ET

import TG_Cerca_Editor as base
from TG_Cerca_Editor_v08 import model_details


def _length(a,b):
    return math.hypot(b[0]-a[0], b[2]-a[2])


def _sample(points, stations, d):
    d=max(stations[0],min(stations[-1],d))
    i=min(len(points)-2,max(0,bisect_right(stations,d)-1))
    span=stations[i+1]-stations[i]
    t=0 if span<1e-10 else (d-stations[i])/span
    a,b=points[i],points[i+1]
    return tuple(a[k]+t*(b[k]-a[k]) for k in range(3))


def _angle(a,b,c,d):
    u=(b[0]-a[0],b[2]-a[2])
    v=(d[0]-c[0],d[2]-c[2])
    n=math.hypot(*u)*math.hypot(*v)
    if n<1e-6:
        return 180.
    cos=max(-1.,min(1.,(u[0]*v[0]+u[1]*v[1])/n))
    return math.degrees(math.acos(cos))


def segment_profile(mod, xml):
    root=base.check_mod_xml(mod,xml,"fence")
    panels=root.find("./fence/segment[@id='SEGMENT']/panels")
    panel=panels.find("panel") if panels is not None else None
    if panel is None:
        raise ValueError("O mod não tem painéis nativos; não é possível gerar fios.")
    length=float(panel.get("length","0"))
    max_scale=float(panels.get("maxScale","1.2"))
    if not (math.isfinite(length) and .5<=length<=30 and
            math.isfinite(max_scale) and 1.0<=max_scale<=3):
        raise ValueError("Comprimento de painel ou maxScale inválido no XML.")
    return length,max_scale,root


def _gate_node(root, gate_id, mod):
    gate=root.find("./fence/segment[@id='"+gate_id+"']/gate")
    if gate is None:
        return None
    filename=(root.findtext("./base/filename") or "").replace("\\","/")
    if not filename or filename.startswith(("/", "$")) or ".." in filename.split("/"):
        return None
    try:
        i3d=ET.fromstring(base.read_mod_file(mod,filename))
        node=i3d.find("Scene")
        if node is None:
            return None
        path=gate.get("node","")
        # Exemplo GIANTS: 0>0 = Scene[0] ("gates"), filho[0] (gate10m).
        for token in path.replace("|",">").split(">"):
            node=list(node)[int(token)]
        return node
    except (OSError,KeyError,IndexError,ET.ParseError,ValueError):
        return None


def gate_span(mod,xml,gate_id):
    """Largura real pela distância entre os postes do I3D.

    Não edita o arquivo ZIP. Se o modelo não expõe ambos os postes com
    coordenadas utilizáveis, mantém width da configuração do mod.
    """
    spec=model_details(mod,xml)
    configured=spec["gates"].get(gate_id)
    if configured is None:
        raise ValueError("Porteira não declarada neste XML de cerca.")
    root=base.check_mod_xml(mod,xml,"fence")
    node=_gate_node(root,gate_id,mod)
    if node is not None:
        positions=[]
        for part in node:
            if "poste" in (part.get("name") or "").casefold():
                # Em I3D GIANTS, nó sem "translation" fica na origem (0,0,0).
                raw=part.get("translation","0 0 0")
                try:
                    pos=tuple(float(x) for x in raw.split())
                    if len(pos)==3 and all(math.isfinite(x) for x in pos):
                        positions.append(pos)
                except ValueError:
                    pass
        if len(positions)>=2:
            physical=math.hypot(positions[-1][0]-positions[0][0],
                                positions[-1][2]-positions[0][2])
            if .5<=physical<=30:
                return physical,"I3D"
    return configured,"XML"


def panel_segments(points,panel,max_scale):
    """Alinha intervalos sucessivos SEM deixar vão menor que o painel.

    Começa em floor(total/panel) intervalos. Se a corda numa curva for
    menor que o painel, usa um intervalo a menos (vãos ligeiramente maiores).
    Só aceita se TODOS os vãos estiverem no limite do modelo. Senão aborta
    com mensagem em vez de gerar postes sem fios.
    """
    if len(points)<2:
        raise ValueError("Trecho de cerca sem dois pontos.")
    acc=base.cumulative(points)
    total=acc[-1]
    if total < panel-1e-6:
        raise ValueError(f"Trecho de {total:.2f} m é menor que o painel "
                         f"de {panel:g} m: produziria postes sem fios.")
    high=int(math.floor(total/panel+1e-7))
    if high>16000:
        raise ValueError("Cerca muito longa. Divida a spline em partes.")
    for n in range(high,max(0,high-30),-1):
        if n<1:
            break
        arc=total/n
        if arc>panel*max_scale+1e-5:
            break
        samples=[_sample(points,acc,total*i/n) for i in range(n+1)]
        distances=[_length(a,b) for a,b in zip(samples,samples[1:])]
        if distances and (min(distances)>=panel-1e-6 and
                          max(distances)<=panel*max_scale+1e-5):
            edges=list(zip(samples,samples[1:]))
            return edges,dict(count=n,min_chord=min(distances),
                              max_chord=max(distances),
                              panel=panel,maxScale=max_scale,total=total)
    raise ValueError(
        f"A curva/trecho de {total:.2f} m não permite painéis de {panel:g} m "
        f"(escala máxima {max_scale:g}). Ajuste a spline ou a posição da "
        "porteira no GE, em vez de gerar postes sem fios.")


def gate_on_spline(points,gate_pct,physical_width,panel):
    """Abertura COMPRIMENTO FÍSICO, contígua ao traçado, orientada na reta.

    Mede a corda entre extremidades, não um arco que deixaria um portão
    reto desalinhado. Bloqueia portas em curvas onde a tangente muda muito.
    """
    if not (0. <= gate_pct <= 100.):
        raise ValueError("Posição da porteira (%) fora de 0..100.")
    acc=base.cumulative(points)
    total=acc[-1]
    center=total*gate_pct/100.
    limit=min(center-panel,total-center-panel)
    if limit<physical_width/2.:
        raise ValueError("Porteira perto da ponta: é preciso um painel de cerca "
                         "antes e depois do vão. Mude a posição na prévia.")
    lo=physical_width/2.
    hi=limit
    def pair(half):
        return (_sample(points,acc,center-half),
                _sample(points,acc,center+half))
    if _length(*pair(hi))<physical_width-1e-4:
        raise ValueError("O traçado faz uma curva fechada demais para a largura "
                         "dessa porteira. Escolha um trecho mais reto.")
    # Ajusta o arco para que a corda reta seja igual à largura do modelo.
    for i in range(32):
        mid=(lo+hi)/2.
        if _length(*pair(mid))<physical_width:
            lo=mid
        else:
            hi=mid
    half=(lo+hi)/2.
    start,end=pair(half)
    if _length(start,end)<physical_width-.02:
        raise ValueError("Não foi possível acertar a abertura da porteira.")
    left=_sample(points,acc,center-half-min(1.5,panel/2.))
    right=_sample(points,acc,center+half+min(1.5,panel/2.))
    a=_angle(left,start,start,end)
    b=_angle(start,end,end,right)
    if max(a,b)>17.:
        raise ValueError(
            f"A porteira ficaria atravessada na curva (desvio "
            f"{max(a,b):.1f} graus). Escolha um trecho mais reto da spline "
            "na prévia para alinhá-la com a cerca.")
    return center-half,center+half,start,end,total


def build_fence_v08(points,mod,xml,target,gate_id="",gate_pct=50.,
                    max_span=80.,tolerance_xy=.35,tolerance_y=.18,farm_id=1):
    """Assinatura original preservada para a janela v0.9+ e backup."""
    spec=model_details(mod,xml)
    panel,max_scale,_=segment_profile(mod,xml)
    if not isinstance(farm_id,int) or not 0<=farm_id<=255:
        raise ValueError("Farm ID inválido (0..255).")
    acc=base.cumulative(points)
    total=acc[-1]
    if total<panel:
        raise ValueError("Spline curta demais para a cerca selecionada.")
    width=None
    source=""
    if gate_id:
        width,source=gate_span(mod,xml,gate_id)
        lo,hi,start,end,total=gate_on_spline(
            points,gate_pct,width,panel)
        pieces=[
            (base.between(points,acc,0,lo),"SEGMENT"),
            ([start,end],gate_id),
            (base.between(points,acc,hi,total),"SEGMENT")]
    else:
        pieces=[(points,"SEGMENT")]
    records=[]
    reports=[]
    for path,kind in pieces:
        if kind=="SEGMENT":
            edges,report=panel_segments(path,panel,max_scale)
            records.extend((a,b,kind) for a,b in edges)
            reports.append(report)
        else:
            records.append((path[0],path[1],kind))
    # Nunca deixa buraco entre as peças (exceto a PORTEIRA como vão deliberado).
    for left,right in zip(records,records[1:]):
        if _length(left[1],right[0])>.005:
            raise ValueError("Falha no encaixe: fim de um segmento diferente "
                             "do início do próximo. XML não foi gravado.")
    tree=ET.parse(target)
    root=tree.getroot()
    if root.tag!="placeables":
        raise ValueError("Selecione um placeables.xml de savegame válido.")
    obj=ET.SubElement(root,"placeable",{
        "filename":base.as_network_filename(mod,xml),
        "modName":base.modname(mod),
        "uniqueId":"placeable"+uuid.uuid4().hex,
        "position":"0.000 -151.000 0.000",
        "rotation":"0.000 0.000 0.000",
        "age":"0.000000",
        "price":"100.000000",
        "farmId":str(farm_id)})
    fence=ET.SubElement(obj,"newFence")
    for a,b,kind in records:
        ET.SubElement(fence,"segment",{
            "start":" ".join(f"{v:.5f}" for v in a),
            "end":" ".join(f"{v:.5f}" for v in b),
            "id":kind})
    result=dict(spec)
    if gate_id:
        result["gate_xml_length"]=spec["gates"][gate_id]
        result["gate_physical_length"]=width
        result["gate_length_source"]=source
        result["gates"]=dict(spec["gates"])
        result["gates"][gate_id]=width
    result["panel_max_scale"]=max_scale
    result["panel_length"]=panel
    return tree,records,reports,total,result
