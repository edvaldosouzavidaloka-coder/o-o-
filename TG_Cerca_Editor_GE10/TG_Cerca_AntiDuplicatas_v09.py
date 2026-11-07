"""TG + EDVALDO - deteccao conservadora de cercas sobrepostas no save FS25.

Nao altera o ZIP de mods nem objetos que nao sao newFence. Somente a instancia
especifica escolhida pelo usuario pode ser substituida, apos confirmacao.
"""
from __future__ import annotations
import math
from xml.etree import ElementTree as ET

def _xyz(raw):
    if not raw:
        return None
    try:
        p=tuple(float(t) for t in raw.split())
        if len(p)!=3 or not all(math.isfinite(v) for v in p):
            return None
        return (p[0],p[2])
    except (ValueError,TypeError):
        return None


def _route(placeable):
    """Retorna (edges, comprimento, começo, fim, bounding_box) ou None.

    Nunca interpreta um objeto desconhecido como uma cerca que pode ser apagada.
    """
    fence=placeable.find("newFence")
    if fence is None:
        return None
    edges=[]
    previous=None
    for seg in fence.findall("segment"):
        a,b=_xyz(seg.get("start")),_xyz(seg.get("end"))
        if a is None or b is None:
            return None
        length=math.dist(a,b)
        if length<0.025:
            continue
        if previous is not None and math.dist(previous,a)>1.0:
            # Cercas interrompidas ou grupos nao-contiguos nao sao substituidos.
            return None
        edges.append((a,b,length))
        previous=b
    if not edges:
        return None
    total=sum(e[2] for e in edges)
    xs=[coord[0] for a,b,_ in edges for coord in (a,b)]
    zs=[coord[1] for a,b,_ in edges for coord in (a,b)]
    return edges,total,edges[0][0],edges[-1][1],(min(xs),min(zs),max(xs),max(zs))


def _bbox_near(a,b,tolerance):
    return (a[0]<=b[2]+tolerance and b[0]<=a[2]+tolerance
            and a[1]<=b[3]+tolerance and b[1]<=a[3]+tolerance)


def _nearest_distance(point,edges):
    x,z=point
    distance_sq=float("inf")
    for a,b,_ in edges:
        dx,dz=b[0]-a[0],b[1]-a[1]
        norm=dx*dx+dz*dz
        if norm<1e-9:
            continue
        t=max(0.,min(1.,((x-a[0])*dx+(z-a[1])*dz)/norm))
        ex,ez=a[0]+t*dx,a[1]+t*dz
        distance_sq=min(distance_sq,(ex-x)**2+(ez-z)**2)
        if distance_sq<1e-8:
            break
    return math.sqrt(distance_sq)


def _samples(route):
    edges,total,_,_,_=route
    if total<=0:
        return []
    count=max(32,min(180,math.ceil(total/4)))
    samples=[]
    dist=0.
    j=0
    for i in range(count+1):
        target=total*i/count
        while j<len(edges)-1 and dist+edges[j][2]<target-1e-8:
            dist+=edges[j][2]
            j+=1
        a,b,length=edges[j]
        t=max(0.,min(1.,(target-dist)/length))
        samples.append((a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])))
    return samples


def _coverage(route_a,route_b,tolerance):
    samples=_samples(route_a)
    if not samples:
        return 0.
    found=sum(_nearest_distance(p,route_b[0])<=tolerance for p in samples)
    return found/len(samples)


def _same_ends(a,b,tolerance=0.35):
    return (math.dist(a[2],b[2])<=tolerance and math.dist(a[3],b[3])<=tolerance) or (
            math.dist(a[2],b[3])<=tolerance and math.dist(a[3],b[2])<=tolerance)


def _filename(placeable):
    return (placeable.get("filename") or "").replace("\\","/").lower().strip()


def scan_overlapping_fences(tree,candidate):
    """Procura duplicatas da proposta, sem mudar XML.

    duplicates: mesmo modelo e mesmo caminho, com alta confianca.
    conflicts: qualquer outra sobreposicao, parcial ou modelo diferente.
    """
    root=tree.getroot()
    current=_route(candidate)
    if current is None:
        raise ValueError("Cerca nova sem rota valida para comparacao.")
    duplicates=[]
    conflicts=[]
    for old in root.findall("placeable"):
        if old is candidate or old.find("newFence") is None:
            continue
        path=_route(old)
        if path is None:
            continue
        # Barato: exclui cercas de outra regiao.
        if not _bbox_near(current[4],path[4],1.0):
            continue
        overlap_old=_coverage(path,current,0.75)
        overlap_new=_coverage(current,path,0.75)
        same_model=_filename(old)==_filename(candidate) and bool(_filename(candidate))
        length_match=abs(path[1]-current[1])<=max(1.5,0.02*current[1])
        exact=(same_model and length_match and _same_ends(current,path)
               and min(overlap_old,overlap_new)>=0.96)
        if exact:
            duplicates.append(old)
        elif (max(overlap_old,overlap_new)>=0.65
              and min(overlap_old,overlap_new)>=0.33
              and min(path[1],current[1])>=8.0):
            conflicts.append((old,same_model,overlap_old,overlap_new))
    return duplicates,conflicts


def remove_confirmed_duplicates(tree,candidate,duplicates):
    """Apenas apos o usuario confirmar; mantem o candidato unico."""
    root=tree.getroot()
    if candidate not in list(root):
        raise ValueError("Cerca proposta nao esta no XML.")
    for old in duplicates:
        if old is candidate or old not in list(root):
            raise ValueError("Tentativa de remover objeto nao autorizado.")
        if old.find("newFence") is None:
            raise ValueError("Somente cercas newFence podem ser removidas.")
    for old in duplicates:
        root.remove(old)
    return len(duplicates)
