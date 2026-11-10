"""TG + EDVALDO — Prévia 3D ilustrativa de cerca/porteira FS25 (Tk Canvas).

Projeção 3D com órbita e zoom, postes e fios com medidas do modelo XML,
vão da porteira calculado pela mesma spline, e orientação reversível 180°.

Este visualizador NÃO decodifica as malhas binárias .i3d.shapes; a prévia é
um modelo 3D REPRESENTATIVO para conferir alinhamento e posição, não a
textura/colisão/animação exata do mod dentro do motor GIANTS.
"""
from __future__ import annotations
import math

import TG_Cerca_Editor as base
from TG_Cerca_Geometria_Nativa_v142 import gate_on_spline, _sample


def invert_fence_direction(placeable):
    """Inverte a orientação de TODOS os segmentos preservando continuidade.

    No newFence nativo a direção é dada pelos endpoints start/end, não
    existe no arquivo um yaw independente e seguro para a porteira.
    A inversão de todo o trajeto aplica 180º à orientação da porteira
    sem produzir um XML de segmentos desconectados.
    """
    fence=placeable.find("newFence")
    if fence is None:
        raise ValueError("Objeto não tem newFence.")
    pieces=list(fence.findall("segment"))
    if not pieces:
        raise ValueError("Cerca sem segmentos.")
    for node in pieces:
        start,end=node.get("start"),node.get("end")
        if not start or not end:
            raise ValueError("Segmento sem start/end.")
        node.set("start",end)
        node.set("end",start)
    for node in pieces:
        fence.remove(node)
    fence.extend(reversed(pieces))
    return len(pieces)


def scene_geometry(points,center_percent=50.0,gate_width=None,panel=4.0,
                   window=42.0):
    """Geometria para o canvas; não toca no XML nem tenta renderizar shapes.

    Amostra somente o trecho local à posição da porteira, com postes de
    comprimento nominal do painel. A operação de geração final continua
    sendo validada pela rotina de segmentos nativos adaptativos.
    """
    if len(points)<2:
        return None
    acc=base.cumulative(points)
    total=acc[-1]
    if total<=0:
        return None
    center=max(0.,min(total,center_percent*total/100.))
    window=min(max(14.,float(window)),max(14.,total))
    low=max(0.,center-window/2.)
    high=min(total,center+window/2.)
    if high-low<2.:
        low,high=0.,total
    gap=None
    warning=""
    if gate_width:
        try:
            from TG_Cerca_Geometria_Nativa_v142 import gate_on_spline
            lo,hi,a,b,_=gate_on_spline(points,center_percent,gate_width,panel)
            gap=(lo,hi,a,b)
        except ValueError as exc:
            # A prévia avisa o problema, mas não inventa um ajuste aplicável.
            warning=str(exc)
            lo=max(0.,center-gate_width/2.)
            hi=min(total,center+gate_width/2.)
            if hi>lo:
                gap=(lo,hi,_sample(points,acc,lo),_sample(points,acc,hi))
    stations={low,high,center}
    if gap is not None:
        stations.update((gap[0],gap[1]))
    # Amostra o caminho para a seleção por clique, inclusive curvas.
    sample_count=max(10,min(240,math.ceil((high-low)/.8)))
    for k in range(sample_count+1):
        stations.add(low+(high-low)*k/sample_count)
    path=[(d,_sample(points,acc,d)) for d in sorted(stations)]
    # Postes e painéis exemplificativos no passo nominal do XML.
    pieces=[]
    poles={}
    d=low
    count=0
    while d<high-1e-5 and count<200:
        e=min(high,d+panel)
        a=_sample(points,acc,d)
        b=_sample(points,acc,e)
        if gap and d<gap[1] and e>gap[0]:
            if d<gap[0]-.05:
                b=_sample(points,acc,gap[0])
                pieces.append((a,b))
                poles[round(d,3)]=a
                poles[round(gap[0],3)]=b
            if e>gap[1]+.05:
                a=_sample(points,acc,gap[1])
                pieces.append((a,_sample(points,acc,e)))
                poles[round(gap[1],3)]=a
                poles[round(e,3)]=_sample(points,acc,e)
        else:
            pieces.append((a,b))
            poles[round(d,3)]=a
            poles[round(e,3)]=b
        d=e
        count+=1
    return dict(points=path,pieces=pieces,poles=list(poles.values()),
                gap=gap,total=total,center=_sample(points,acc,center),
                center_arc=center,warning=warning,panel=panel,
                gate_width=gate_width,window=(low,high))


def project(point,origin,azimuth=25.,pitch=50.,zoom=1.,canvas=(430,360),
            visible_distance=43.):
    """Projeção de câmera orbital sem dependência de GPU; y aponta para cima."""
    a=math.radians(float(azimuth))
    p=math.radians(float(pitch))
    dx=point[0]-origin[0]
    dy=point[1]-origin[1]
    dz=point[2]-origin[2]
    sideways=dx*math.cos(a)-dz*math.sin(a)
    depth=dx*math.sin(a)+dz*math.cos(a)
    vertical=dy*math.cos(p)-depth*math.sin(p)
    camera_depth=depth*math.cos(p)+dy*math.sin(p)
    focal=max(15.,visible_distance*1.6)
    perspective=max(.55,min(1.85,focal/(focal+camera_depth)))
    width,height=canvas
    pixels=width/(max(20.,visible_distance)*1.55)*float(zoom)
    sx=width/2+sideways*pixels*perspective
    sy=height*.56-vertical*pixels*perspective
    return sx,sy,camera_depth


def nearest_position(scene,origin,azimuth,pitch,zoom,width,height,mousex,mousey):
    """Seleciona ponto da spline com clique no traçado projetado 3D."""
    if not scene:
        return None,None
    projections=[(d,project(x,origin,azimuth,pitch,zoom,(width,height),
                            visible_distance=max(25.,scene["window"][1]-scene["window"][0])))
                 for d,x in scene["points"]]
    best=(float("inf"),None)
    for (da,a),(db,b) in zip(projections,projections[1:]):
        ux,uy=b[0]-a[0],b[1]-a[1]
        n=ux*ux+uy*uy
        if n<1e-10:
            continue
        t=max(0.,min(1.,((mousex-a[0])*ux+(mousey-a[1])*uy)/n))
        off=(mousex-a[0]-t*ux)**2+(mousey-a[1]-t*uy)**2
        if off<best[0]:
            best=(off,da+t*(db-da))
    return best[1],math.sqrt(best[0])


def draw_scene(canvas,scene,azimuth,pitch,zoom,flipped=False):
    """Desenha em Tk Canvas linhas 3D ordenadas pela profundidade."""
    canvas.delete("all")
    w=max(320,canvas.winfo_width())
    h=max(270,canvas.winfo_height())
    if not scene:
        canvas.create_text(w/2,h/2,text="Selecione a spline I3D\npara ver cerca e porteira em 3D",
                           fill="#d8eee1",font=("Segoe UI",12),justify="center")
        return
    center=scene["center"]
    dist=max(25.,scene["window"][1]-scene["window"][0])
    origin=center
    draw=[]
    def line(a,b,color,width=2,priority=0):
        px,py,pz=project(a,origin,azimuth,pitch,zoom,(w,h),dist)
        qx,qy,qz=project(b,origin,azimuth,pitch,zoom,(w,h),dist)
        draw.append(((pz+qz)/2.+priority,a,b,(px,py,qx,qy),color,width))
    # grade do terreno para orientar o usuário espacialmente
    ground_y=center[1]-.13
    spacing=5
    xmin=math.floor(center[0]/spacing)*spacing-25
    zmin=math.floor(center[2]/spacing)*spacing-25
    for i in range(11):
        gx=xmin+i*spacing
        gz=zmin+i*spacing
        line((gx,ground_y,zmin),(gx,ground_y,zmin+50),"#254b3a",1,priority=-3)
        line((xmin,ground_y,gz),(xmin+50,ground_y,gz),"#254b3a",1,priority=-3)
    # sombra da linha da cerca no chão (opcional)
    for a,b in scene["pieces"]:
        line(a,b,"#347c5b",2)
        for height,color,size in ((.42,"#d3e3d5",1.4),
                                  (.85,"#e6ece4",1.4),
                                  (1.28,"#f5f0e1",1.5)):
            line((a[0],a[1]+height,a[2]),
                 (b[0],b[1]+height,b[2]),color,size)
    for p in scene["poles"]:
        line(p,(p[0],p[1]+1.65,p[2]),"#c69b60",5,priority=0.2)
        line((p[0]-.035,p[1]+1.65,p[2]),(p[0]+.035,p[1]+1.65,p[2]),
             "#f0d09e",3,priority=.21)
    gap=scene["gap"]
    if gap:
        start,end=gap[2],gap[3]
        # Inverter a orientação real da porteira troca os endpoints do XML.
        if flipped:
            start,end=end,start
        for p in (start,end):
            line(p,(p[0],p[1]+1.85,p[2]),"#e6b878",7,priority=.3)
        # Estrutura esquemática de uma porteira de madeira com 3 travessas
        for height in (.35,.9,1.43):
            line((start[0],start[1]+height,start[2]),
                 (end[0],end[1]+height,end[2]),"#efbb71",4,priority=.35)
        line((start[0],start[1]+.25,start[2]),
             (end[0],end[1]+1.48,end[2]),"#d18d4c",3,priority=.4)
        line((start[0],start[1]+1.48,start[2]),
             (end[0],end[1]+.25,end[2]),"#b07643",2,priority=.4)
        # Marca no poste da dobradiça
        line((start[0],start[1]+.40,start[2]),
             (start[0],start[1]+1.35,start[2]),"#5eaaff",5,priority=.6)
    # Painéis ao fundo primeiro; linhas próximas sobrepõem as distantes.
    for depth,a,b,coords,color,thickness in sorted(draw,key=lambda x:x[0],reverse=True):
        canvas.create_line(*coords,fill=color,width=thickness,capstyle="round")
    canvas.create_rectangle(8,8,min(w-10,295),70,fill="#0b1b15",
                            outline="#417c59")
    canvas.create_text(18,17,text="VISÃO 3D — SIMULAÇÃO",anchor="nw",
                       font=("Segoe UI",10,"bold"),fill="#9cf3b7")
    canvas.create_text(18,37,
        text=f'Porteira: {scene["gate_width"]:.2f} m' if gap else 'Somente cerca',
        anchor="nw",font=("Segoe UI",9),fill="#f6d39b" if gap else "#d1e6d6")
    canvas.create_text(18,54,text=f'Câmera {azimuth:.0f}° | {zoom:.1f}x | '
                     +("Sentido invertido" if flipped else "Sentido normal"),
                     anchor="nw",font=("Segoe UI",8),fill="#c3d7ca")
    if scene["warning"]:
        canvas.create_rectangle(5,h-60,w-5,h-5,
                               fill="#3b2418",outline="#dc9159")
        canvas.create_text(15,h-49,text="Atenção: a porteira pode não encaixar:",
                           fill="#ffd39a",anchor="nw",font=("Segoe UI",9,"bold"))
        canvas.create_text(15,h-32,text=scene["warning"][:84],
                           fill="#ffddd0",anchor="nw",font=("Segoe UI",8))
    canvas.create_text(w-10,h-8,anchor="se",
        text="Arraste botão direito: girar | Roda: zoom | Clique na cerca: posicionar",
        fill="#aac4b5",font=("Segoe UI",8))
