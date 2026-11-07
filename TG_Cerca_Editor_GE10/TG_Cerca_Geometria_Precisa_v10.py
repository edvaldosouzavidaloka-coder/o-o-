"""TG + EDVALDO FS25 v1.0 - geometria de painéis fiéis à spline I3D.

O FS25 posiciona postes/painéis de acordo com a classe FenceSegment do mod;
reduzir centenas de pontos a um trecho de 80m provoca distribuição inesperada
nos trechos curvos. Padrão: um registro XML por vão nominal do mod.
"""
from __future__ import annotations
from bisect import bisect_right
import math


def _xz_dist(a,b):
    return math.hypot(b[0]-a[0],b[2]-a[2])


def _interp(a,b,factor):
    return tuple(a[j]+(b[j]-a[j])*factor for j in range(3))


def station_points(points, panel_length):
    """Retorna amostras XYZ com passo constante ao longo da spline, vista XZ.

    N = ceil(L/tamanho_do_painel), com o resto distribuído igualmente,
    inclusive perto das extremidades da porteira, sem um último painel minúsculo.
    Nunca transforma uma curva longa numa reta de 80 metros.
    """
    if not (math.isfinite(panel_length) and 0.5 <= panel_length <= 30):
        raise ValueError('Comprimento do painel inválido.')
    cleaned=[]
    for point in points:
        if len(point)!=3 or not all(math.isfinite(float(v)) for v in point):
            raise ValueError('A spline possui coordenadas inválidas.')
        p=tuple(float(v) for v in point)
        if not cleaned or _xz_dist(cleaned[-1],p)>0.0001:
            cleaned.append(p)
    if len(cleaned)<2:
        raise ValueError('A spline não tem pelo menos dois pontos diferentes.')
    cumulative=[0.]
    for a,b in zip(cleaned,cleaned[1:]):
        cumulative.append(cumulative[-1]+_xz_dist(a,b))
    total=cumulative[-1]
    if total<=0.05:
        raise ValueError('Spline muito curta.')
    count=max(1,math.ceil(total/panel_length - 1e-9))
    if count>20000:
        raise ValueError('Essa cerca tem mais de 20 mil painéis. Divida a spline em partes.')
    spacing=total/count
    samples=[cleaned[0]]
    for i in range(1,count):
        distance=i*spacing
        k=min(len(cumulative)-2,max(0,bisect_right(cumulative,distance)-1))
        t=(distance-cumulative[k])/(cumulative[k+1]-cumulative[k])
        samples.append(_interp(cleaned[k],cleaned[k+1],t))
    samples.append(cleaned[-1])
    return samples,dict(count=count,total=total,panel_length=panel_length,
                        nominal_step=spacing,percentage_of_original=100*spacing/panel_length)


def _straight_enough(path, start, end):
    a,b=path[start],path[end]
    x=b[0]-a[0]
    z=b[2]-a[2]
    d2=x*x+z*z
    if d2<0.01:
        return False
    # Só permite dois vãos agrupados quando o ponto intermediário está
    # quase perfeitamente alinhado em X/Z e na altitude.
    for p in path[start+1:end]:
        t=max(0.,min(1.,((p[0]-a[0])*x+(p[2]-a[2])*z)/d2))
        q=_interp(a,b,t)
        if _xz_dist(q,p)>0.03 or abs(q[1]-p[1])>0.04:
            return False
    return True


def exact_fence_edges(points, panel_length, grouping=1):
    """Gera [(start_xyz, end_xyz)] para o XML do save.

    grouping=1: fidelidade máxima, N segmentos para N painéis.
    grouping=2: modo experimental, reúne até dois vãos somente em retas.
    """
    if grouping not in (1,2):
        raise ValueError('Agrupamento permitido: 1 (preciso) ou 2 (retas).')
    sampled, report=station_points(points,panel_length)
    edges=[]
    idx=0
    while idx<len(sampled)-1:
        next_idx=idx+1
        if grouping==2 and idx+2<len(sampled) and _straight_enough(sampled,idx,idx+2):
            next_idx=idx+2
        edges.append((sampled[idx],sampled[next_idx]))
        idx=next_idx
    report=dict(report,records=len(edges),grouping=grouping)
    return edges,report
