"""TG + EDVALDO | Geometria de cercas FS25 v0.7.

Uma linha XML nao representa necessariamente um poste: o FS25 cria paineis entre
os pontos. Gera trechos longos com divisao por NUMERO INTEIRO de paineis, de
forma que as emendas nao alterem o passo nominal de forma arbitraria.
"""
from __future__ import annotations
import math


def _planar(a, b):
    return math.hypot(b[0]-a[0], b[2]-a[2])


def simplify_spline(points, tolerance_xy=0.35, tolerance_y=0.18):
    if not (0.01 <= tolerance_xy <= 3.0 and 0.01 <= tolerance_y <= 3.0):
        raise ValueError('Tolerancias de curva/relevo: use de 0.01 a 3 metros.')
    if len(points) < 2:
        raise ValueError('Spline sem pelo menos dois pontos.')
    cleaned = []
    for p in points:
        if len(p) != 3 or not all(math.isfinite(v) for v in p):
            raise ValueError('Spline possui coordenadas invalidas.')
        if not cleaned or _planar(cleaned[-1],p) > 0.01:
            cleaned.append(tuple(p))
    if len(cleaned) < 2:
        raise ValueError('Spline sem comprimento horizontal.')
    if len(cleaned) <= 2:
        return cleaned

    # Ramer-Douglas-Peucker com erros de curva e de altitude independentes.
    keep = {0, len(cleaned)-1}
    pending = [(0, len(cleaned)-1)]
    while pending:
        first, last = pending.pop()
        a, b = cleaned[first], cleaned[last]
        dx, dz = b[0]-a[0], b[2]-a[2]
        d2 = dx*dx + dz*dz
        worst, pivot = 0.0, None
        for i in range(first+1,last):
            p = cleaned[i]
            t = max(0.0,min(1.0,((p[0]-a[0])*dx+(p[2]-a[2])*dz)/d2)) if d2 > 1e-9 else 0.0
            qx, qy, qz = (a[j]+(b[j]-a[j])*t for j in range(3))
            error = max(math.hypot(p[0]-qx,p[2]-qz)/tolerance_xy,
                        abs(p[1]-qy)/tolerance_y)
            if error > worst:
                worst, pivot = error, i
        if pivot is not None and worst > 1.0:
            keep.add(pivot)
            pending.extend(((first,pivot),(pivot,last)))
    return [cleaned[k] for k in sorted(keep)]


def aligned_segments(points, panel_length, max_span=80.0,
                     tolerance_xy=0.35, tolerance_y=0.18):
    """(segments, info).

    Os paineis dentro de um mesmo trecho reto tem passo comum: comprimento
    da aresta / numero inteiro de paineis. Divisao em segmentos respeita
    esse passo; o espacamento real e calculado pelo FS25 (nao pelo XML).
    """
    if not (math.isfinite(panel_length) and 0.5 <= panel_length <= 30.0):
        raise ValueError('Comprimento de painel invalido no XML do mod.')
    if not (math.isfinite(max_span) and panel_length <= max_span <= 200.0):
        raise ValueError(f'Trecho maximo deve estar entre {panel_length:g} m e 200 m.')
    simplified = simplify_spline(points,tolerance_xy,tolerance_y)
    capacity = max(1,math.floor(max_span/panel_length))
    segments = []
    steps = []
    short_parts = 0
    for a,b in zip(simplified,simplified[1:]):
        distance = _planar(a,b)
        if distance <= 0.02:
            continue
        # ceil() evita que o jogo tenha de esticar o painel para caber.
        panels = max(1, math.ceil(distance/panel_length - 1e-10))
        step = distance/panels
        if step < panel_length*0.65:
            short_parts += 1
        # Divide a aresta apenas apos um NUMERO INTEIRO de paineis.
        blocks = max(1,math.ceil(panels/capacity))
        for i in range(blocks):
            j0 = (i*panels)//blocks
            j1 = ((i+1)*panels)//blocks
            if j1 <= j0:
                continue
            t0, t1 = j0/panels, j1/panels
            p0 = tuple(a[k]+(b[k]-a[k])*t0 for k in range(3))
            p1 = tuple(a[k]+(b[k]-a[k])*t1 for k in range(3))
            segments.append((p0,p1))
        steps.append(step)
    if not segments:
        raise ValueError('Nenhum segmento gerado da spline.')
    info = dict(
        original_points=len(points), corners=len(simplified),
        segments=len(segments), short_edges=short_parts,
        panel_step_min=min(steps), panel_step_max=max(steps),
        nominal_panel=panel_length,
    )
    return segments, info
