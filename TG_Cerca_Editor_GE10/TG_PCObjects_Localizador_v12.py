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
