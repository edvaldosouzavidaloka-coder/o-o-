"""TG + EDVALDO v1.2 — localizar instância no mapa ao receber I3D do modelo.

Um I3D de objeto (ex. placeables/abatedouro1/abatedouro.i3d) não contém
sua transformação de mundo. É preciso procurar uma Reference ao modelo
dentro do I3D principal do mapa. Nunca inventa coordenadas (0,0,0).
"""
from __future__ import annotations

from pathlib import Path
import re
import xml.etree.ElementTree as ET
import TG_PCObjects_Core_v11 as core


def is_model_i3d(i3d,maproot):
    """Reconhece I3D separado sob pasta de placeables ou objetos."""
    file=Path(i3d).resolve()
    root=Path(maproot).resolve()
    if not file.is_file() or file.suffix.lower()!=".i3d" or not root.is_dir():
        return False
    if not file.is_relative_to(root):
        return False
    folders={p.lower() for p in file.relative_to(root).parts[:-1]}
    return bool(folders & {"placeables","placeable","pcobjects","objects","buildings"})


def main_map_scenes(maproot,exclude=None,limit=15):
    """Procura cenas principais dentro de maps/; nunca varre modelos isolados."""
    root=Path(maproot).resolve()
    if not (root/"modDesc.xml").is_file():
        raise ValueError("Selecione a pasta raiz do mapa que contém modDesc.xml.")
    config=core.map_config_file(root)
    paths=[]
    if config is not None:
        paths.extend(config.parent.glob("*.i3d"))
        paths.extend((config.parent/"config").glob("*.i3d"))
    paths.extend(root.glob("*.i3d"))
    maps=root/"maps"
    if maps.is_dir():
        paths.extend(maps.glob("*.i3d"))
        paths.extend(maps.glob("*/*.i3d"))
        paths.extend(maps.glob("*/*/*.i3d"))
    if not paths:
        # Faz pesquisa ampla somente se mapas não seguem estrutura padrão.
        for p in root.rglob("*.i3d"):
            rel=p.relative_to(root).parts
            if any(part.lower() in ("placeables","objects","buildings","pcobjects","vehicles")
                   for part in rel[:-1]):
                continue
            paths.append(p)
            if len(paths)>200:
                break
    excluded=Path(exclude).resolve() if exclude else None
    unique=[]
    seen=set()
    for file in paths:
        try:
            resolved=file.resolve()
            if resolved==excluded or resolved in seen or file.stat().st_size>150_000_000:
                continue
            seen.add(resolved)
            unique.append(file)
        except (OSError,ValueError):
            continue
    def sort_key(file):
        name=file.stem.casefold()
        near_config=bool(config and file.parent==config.parent)
        rank=0 if name in ("map","mapus","mapbr","mapde","main","scene") else 1
        return (rank,not near_config,len(file.parts),str(file).casefold())
    return sorted(unique,key=sort_key)[:limit]


def find_imported_model_in_map(model_i3d,maproot,limit=15):
    """Encontra transformações verdadeiras do modelo ao longo da cena principal.

    Retorna instâncias do mesmo modelo (uma ou várias), nomeando a cena fonte.
    """
    model=Path(model_i3d).resolve()
    root=Path(maproot).resolve()
    if not model.is_file():
        raise ValueError("Arquivo I3D não encontrado: "+str(model))
    if model.suffix.lower()!=".i3d":
        raise ValueError("Escolha um arquivo I3D.")
    target=model.stem.casefold()
    found=[]
    scenes=main_map_scenes(root,exclude=model,limit=limit)
    errors=[]
    for scene in scenes:
        try:
            candidates=core.scan_map_i3d(scene)
        except (OSError,ET.ParseError,ValueError) as exc:
            errors.append(scene.name+": "+str(exc))
            continue
        for item in candidates:
            ref=Path((item.get("reference") or "").replace("\\","/")).stem.casefold()
            name=re.sub(r"[\s_.-]*(\d+|copy\d*)$","",(item.get("name") or "").casefold())
            if ref != target and name != target:
                continue
            if ref != target and item.get("kind")=="referência I3D":
                continue
            place=dict(item)
            place["id"]=str(scene.relative_to(root).as_posix())+":"+str(item["id"])
            place["kind"]="instância importada no mapa"
            place["map_scene"]=str(scene)
            place["object_i3d"]=str(model)
            found.append(place)
    return found,scenes,errors


def _canonical_name(value):
    """Remove número de cópia do GE e normaliza o nome sem confundir outros objetos."""
    name=Path((value or "").replace("\\","/")).stem.casefold()
    return re.sub(r"[\s_.-]*(?:copy[\s_.-]*)?\d+$","",name)


def find_model_in_scene(map_i3d,model_i3d):
    """Procura objetos realmente POSICIONADOS na cena do mapa, mesmo se o nome
    do TransformGroup não estiver na lista de barracões/silos/casas.

    Não usa as coordenadas do I3D isolado como posição global. Só retorna
    nós cujo fileId aponta ao modelo ou cujo nome é igual ao modelo.
    """
    scene_path=Path(map_i3d).resolve()
    model_path=Path(model_i3d).resolve()
    if not scene_path.is_file() or not model_path.is_file():
        raise ValueError("Informe dois arquivos I3D existentes: mapa e objeto.")
    if scene_path==model_path:
        raise ValueError("I3D do mapa e I3D do objeto não podem ser o mesmo arquivo.")
    root=ET.parse(scene_path).getroot()
    scene=root.find("Scene")
    if scene is None:
        raise ValueError("O I3D do mapa selecionado não contém <Scene>.")
    file_table={}
    for node in root.findall("./Files/File"):
        val=node.get("filename","")
        file_table[node.get("fileId")]=val
    answer=[]
    target=_canonical_name(model_path.name)
    def visit(element,xyz,yaw,scale,route):
        if element.tag not in ("TransformGroup","Reference","Shape"):
            for i,ch in enumerate(element):
                visit(ch,xyz,yaw,scale,route+(i,))
            return
        if element.tag=="Shape":
            return
        loc=core.parts3(element.get("translation"))
        rot=core.parts3(element.get("rotation"))
        size=core.parts3(element.get("scale"),(1.,1.,1.))
        if abs(rot[0])>.01 or abs(rot[2])>.01:
            return  # Inclinação complexa: nunca gravar posição aproximada.
        position,heading=core.yaw_world(xyz,yaw,loc,rot[1],scale)
        worldscale=tuple(scale[j]*size[j] for j in range(3))
        filename=file_table.get(element.get("fileId"),element.get("filename",""))
        reference_is_model=False
        if element.tag=="Reference" and filename:
            reference=(scene_path.parent/filename.replace("\\","/")).resolve()
            reference_is_model=(reference==model_path or
                (reference.name.casefold()==model_path.name.casefold()
                 and _canonical_name(reference.name)==target))
        label=_canonical_name(element.get("name",""))
        name_matches=(label==target and bool(label))
        # Dá prioridade a referência exata em relação a wrapper.
        has_descendant_reference=any(
            c.tag=="Reference" and _canonical_name(file_table.get(c.get("fileId"),""))==target
            for c in element.iter() if c is not element)
        match=reference_is_model or (
            name_matches and not has_descendant_reference)
        if match:
            key="ref:"+"/".join(str(i) for i in route)
            answer.append(dict(id=key,name=element.get("name") or model_path.stem,
                 position=position,rotation=(0.,heading,0.),
                 reference=filename,kind="objeto posicionado no I3D do mapa",
                 map_scene=str(scene_path),object_i3d=str(model_path)))
        for i,ch in enumerate(element):
            visit(ch,position,heading,worldscale,route+(i,))
    for i,ch in enumerate(scene):
        visit(ch,(0.,0.,0.),0.,(1.,1.,1.),(i,))
    return answer
