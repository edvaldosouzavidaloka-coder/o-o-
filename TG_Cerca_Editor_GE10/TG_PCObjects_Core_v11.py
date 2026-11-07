"""TG + EDVALDO v1.1: PC Objects I3D -> mapa placeables + storeItems.

Não interpreta malhas I3D como XMLs de placeable. Usa o XML de configuração
real de cada objeto, com <base><filename> e classe placeable. Caminhos
devem apontar para a raiz do mapa ou mod instalado.
"""
from __future__ import annotations

import math
import os
from pathlib import Path, PurePosixPath
import shutil
import tempfile
import uuid
import xml.etree.ElementTree as ET
import zipfile


def norm(value):
    return (value or "").strip().replace("\\", "/").casefold()


def parts3(value, defaults=(0., 0., 0.)):
    if not value:
        return defaults
    try:
        out=tuple(float(x) for x in value.split())
    except (TypeError, ValueError):
        raise ValueError("Coordenadas I3D inválidas: "+str(value))
    if len(out)!=3 or not all(math.isfinite(x) for x in out):
        raise ValueError("São necessárias 3 coordenadas I3D válidas: "+str(value))
    return out


def yaw_world(parent_pos, parent_yaw, child_pos, child_yaw, parent_scale=(1.,1.,1.)):
    """Transformação acumulada: translada e roda em Y os pais no GE.

    O objeto com parent inclinado em X ou Z deve ser corrigido no Editor,
    não receber um valor de rotação silenciosamente errado no XML.
    """
    x,y,z=(child_pos[i]*parent_scale[i] for i in range(3))
    c,s=math.cos(math.radians(parent_yaw)),math.sin(math.radians(parent_yaw))
    xyz=(parent_pos[0]+x*c+z*s,parent_pos[1]+y,parent_pos[2]-x*s+z*c)
    return xyz,(parent_yaw+child_yaw)%360


HINTS=("placeable","placeables","barrac","barracão","galp","shed",
       "silo","casa","house","home","barn","stable","building","garage",
       "armaz","warehouse","pig","cow","sheep","chicken","production",
       "fabrica","fábrica","solar","greenhouse","oficina","estacion")


def scan_map_i3d(path):
    """Retorna candidatos de objeto importado com coordenadas de mundo.

    Inclui Reference externo e TransformGroup importado nomeado. Não importa
    terrain, shapes ou splines. Há correspondência obrigatória com XML real.
    """
    path=Path(path)
    if path.suffix.lower()!=".i3d":
        raise ValueError("Selecione o mapa .i3d, não CSV ou arquivo .shapes.")
    root=ET.parse(path).getroot()
    scene=root.find("Scene")
    if scene is None:
        raise ValueError("I3D sem elemento <Scene>.")
    files={e.get("fileId"):e.get("filename","") for e in root.findall("./Files/File")}
    results=[]
    used=set()
    skip={"terrain","map","foliage","fielddimensions","water","splines",
          "sounds","lights","traffic","pedestrian","navmesh"}
    def walk(element,parent_pos,parent_yaw,parent_scale,context,route,level):
        if element.tag not in ("TransformGroup","Reference","Shape"):
            for j,ch in enumerate(element):
                walk(ch,parent_pos,parent_yaw,parent_scale,context,route+(j,),level+1)
            return
        if element.tag=="Shape":
            return
        name=element.get("name") or element.get("nodeId") or element.tag
        local=parts3(element.get("translation"))
        rot=parts3(element.get("rotation"))
        scl=parts3(element.get("scale"),(1.,1.,1.))
        tilted=(abs(rot[0])>.01 or abs(rot[2])>.01)
        pos,yaw=yaw_world(parent_pos,parent_yaw,local,rot[1],parent_scale)
        new_scale=tuple(parent_scale[i]*scl[i] for i in range(3))
        label=norm(name)
        ref=files.get(element.get("fileId"),element.get("filename",""))
        is_ref=(element.tag=="Reference" and (ref or element.get("fileId")))
        is_group=(element.tag=="TransformGroup" and level<=2
                  and any(h in label for h in HINTS)
                  and not any(k==label for k in skip))
        # Se um grupo representa somente a embalagem de uma Reference,
        # registre a Reference verdadeira, não as duas.
        nested_ref=any(n.tag=="Reference" for n in element.iter() if n is not element)
        if (is_ref or (is_group and not nested_ref)) and not tilted:
            key="/".join(str(j) for j in route)
            if key not in used:
                used.add(key)
                results.append(dict(id=key,name=name,position=pos,
                                    rotation=(0.,yaw,0.),reference=ref or "",
                                    kind="referência I3D" if is_ref else "grupo I3D"))
        for j,ch in enumerate(element):
            walk(ch,pos,yaw,new_scale,context or "placeables" in label,
                 route+(j,),level+1)
    for j,ch in enumerate(scene):
        walk(ch,(0.,0.,0.),0.,(1.,1.,1.),False,(j,),0)
    if len(results)>10000:
        raise ValueError("I3D contém candidatos demais; selecione apenas o grupo de placeables no GE.")
    return results


def _mod_files(mod):
    if mod.is_dir():
        return [(x.relative_to(mod).as_posix(),x.read_bytes)
                for x in mod.rglob("*.xml")]
    with zipfile.ZipFile(mod) as z:
        names=[n for n in z.namelist() if n.lower().endswith(".xml")]
        payload=[(name,z.read(name)) for name in names]
    return [(name,lambda data=data: data) for name,data in payload]


def source_inventory(source, kind, root=None):
    """kind = 'mod' (zip/pasta em mods) ou 'map' (raiz do mod-map)."""
    source=Path(source)
    if kind not in ("mod","map"):
        raise ValueError("Origem inválida.")
    if kind=="map" and not (source/"modDesc.xml").is_file():
        raise ValueError("Selecione a pasta raiz do mapa, com modDesc.xml.")
    if kind=="mod" and not source.exists():
        raise ValueError("Mod não encontrado.")
    items=[]
    for rel,read in _mod_files(source):
        try:
            doc=ET.fromstring(read())
        except (ET.ParseError,UnicodeError,OSError,ValueError):
            continue
        if doc.tag!="placeable" or not doc.get("type"):
            continue
        i3d=(doc.findtext("./base/filename") or "").strip()
        if not i3d.lower().endswith(".i3d"):
            continue
        if kind=="mod":
            full="$moddir$"+(source.stem if source.is_file() else source.name)+"/"+rel
        else:
            full="$mapdir$/"+rel
        sale=(doc.findtext("./storeData/showInStore","true") or "true").strip().lower()
        item=dict(id=kind+":"+str(source)+":"+rel,label=rel,
                  mod=source.stem if source.is_file() else source.name,
                  origin=kind,xml=rel,
                  i3d=i3d,basename=PurePosixPath(i3d.replace("\\","/")).stem.casefold(),
                  filename=full,store_ref=full if kind=="mod" else rel,
                  show_in_store=sale!="false",
                  type=doc.get("type"))
        items.append(item)
    return items


def auto_match(objects, inventory):
    """Liga automaticamente somente quando arquivo/modelo é não ambíguo."""
    matches={}
    for obj in objects:
        ref=norm(obj.get("reference"))
        stem=PurePosixPath(ref).stem
        hint=norm(obj.get("name",""))
        options=[item for item in inventory if item["basename"]==stem] if stem else []
        if not options and hint:
            options=[item for item in inventory if item["basename"]==hint]
        if len(options)==1:
            matches[obj["id"]]=options[0]["id"]
    return matches


def _posstring(position):
    return " ".join(f"{v:.4f}" for v in position)


def _same_placement(a,b,tolerance=0.15):
    try:
        p=parts3(a.get("position"))
        q=parts3(b.get("position"))
        return math.dist(p,q)<=tolerance and norm(a.get("filename"))==norm(b.get("filename"))
    except ValueError:
        return False


def make_map_updates(selected, assignments, inventory, placeables, storeitems):
    """Valida TODOS os itens antes de alterar qualquer arquivo."""
    a=ET.parse(placeables)
    b=ET.parse(storeitems) if Path(storeitems).is_file() else ET.ElementTree(ET.Element("storeItems"))
    if a.getroot().tag!="placeables":
        raise ValueError("Destino dos objetos deve ser placeables.xml com raiz <placeables>.")
    if b.getroot().tag!="storeItems":
        raise ValueError("Destino da loja deve ser storeItems.xml com raiz <storeItems>.")
    byid={v["id"]:v for v in inventory}
    if not selected:
        raise ValueError("Selecione um ou todos os objetos I3D.")
    missing=[o["name"] for o in selected if assignments.get(o["id"]) not in byid]
    if missing:
        raise ValueError("Associe um XML de placeable a cada objeto: "+", ".join(missing[:8]))
    existing={norm(x.get("xmlFilename")) for x in b.getroot().findall("storeItem")}
    inserted=[]
    already=[]
    stores=[]
    # Clone árvores em memória antes de modificar: rollback permanece simples.
    for obj in selected:
        item=byid[assignments[obj["id"]]]
        attrs={"filename":item["filename"],
               "position":_posstring(obj["position"]),
               "rotation":_posstring(obj["rotation"]),
               "farmId":"0"}
        candidate=ET.Element("placeable",attrs)
        if any(_same_placement(candidate,old) for old in a.getroot().findall("placeable")):
            already.append(obj["name"])
        else:
            a.getroot().append(candidate)
            inserted.append(obj["name"])
        ref=norm(item["store_ref"])
        if ref not in existing:
            ET.SubElement(b.getroot(),"storeItem",{"xmlFilename":item["store_ref"]})
            stores.append(item["store_ref"])
            existing.add(ref)
    return a,b,dict(inserted=inserted,already=already,stores=stores)


def map_config_file(maproot):
    """Pega mapa principal a partir de modDesc, se houver."""
    desc=Path(maproot)/"modDesc.xml"
    if not desc.is_file():
        return None
    tree=ET.parse(desc)
    for entry in tree.findall(".//maps/map"):
        rel=entry.get("configFilename","").replace("\\","/")
        if not rel or rel.startswith("$") or rel.startswith("/") or ".." in PurePosixPath(rel).parts:
            continue
        path=(Path(maproot)/rel).resolve()
        if path.is_file() and path.is_relative_to(Path(maproot).resolve()):
            return path
    return None


def check_storeitems_reference(maproot,storeitems):
    """Confirma que a configuração principal usa StoreItems escolhido.

    NÃO muda map.xml silenciosamente. Se estiver errado, impede gravação
    para não prometer loja funcional sem referência.
    """
    config=map_config_file(maproot)
    if config is None:
        return "Não foi possível validar map.xml; confira a referência StoreItems."
    root=ET.parse(config).getroot()
    target=root.find("storeItems")
    if target is None:
        return "O map.xml não declara <storeItems filename=...>."
    rel=(target.get("filename") or "").replace("\\","/")
    prefix="$mapdir$/"
    if rel.startswith(prefix):
        rel=rel[len(prefix):]
    if rel.startswith("$data"):
        return "O map.xml aponta para StoreItems base do jogo, não para o arquivo do mapa."
    intended=(Path(maproot)/rel).resolve()
    if intended!=Path(storeitems).resolve():
        return "O map.xml aponta para "+(target.get("filename") or "(vazio)")+", diferente do StoreItems selecionado."
    return ""


def write_two_with_backups(placeables,storeitems,tree_a,tree_b):
    """Grava ambos após validação, com backup por execução e rollback."""
    paths=[Path(placeables),Path(storeitems)]
    if paths[0].resolve()==paths[1].resolve():
        raise ValueError("placeables e storeItems devem ser arquivos diferentes.")
    for path in paths:
        if not path.is_file():
            raise ValueError("Arquivo não encontrado: "+str(path))
    texts=[]
    for tree in (tree_a,tree_b):
        ET.indent(tree,space="    ")
        data=ET.tostring(tree.getroot(),encoding="utf-8",xml_declaration=True)
        ET.fromstring(data)
        texts.append(data)
    original=[p.read_bytes() for p in paths]
    backups=[]
    temps=[]
    replaced=[]
    try:
        for path,blob in zip(paths,original):
            backup=path.with_name(path.name+".tg_pc_backup_"+uuid.uuid4().hex[:8])
            backup.write_bytes(blob)
            backups.append(backup)
        for path,blob in zip(paths,texts):
            fd,tmp=tempfile.mkstemp(prefix="tg_pc_",suffix=".xml",dir=path.parent)
            with os.fdopen(fd,"wb") as stream:
                stream.write(blob)
            temps.append(Path(tmp))
        for i,path in enumerate(paths):
            os.replace(temps[i],path)
            replaced.append(i)
    except Exception:
        for i in replaced:
            paths[i].write_bytes(original[i])
        raise
    finally:
        for t in temps:
            if t.exists():
                t.unlink()
    return backups


def guess_map_xml_paths(maproot):
    """Sugere arquivos do mapa sem sobrescrever escolhas feitas pelo usuário."""
    root=Path(maproot)
    main=map_config_file(root)
    place=""
    store=""
    if (root/"modDesc.xml").is_file():
        desc=ET.parse(root/"modDesc.xml").getroot()
        for elem in desc.findall(".//maps/map"):
            rel=elem.get("defaultPlaceablesXMLFilename","").replace("\\","/")
            if rel and not rel.startswith(("$","/")) and ".." not in PurePosixPath(rel).parts:
                target=root/rel
                if target.is_file():
                    place=str(target)
                    break
    if main:
        doc=ET.parse(main).getroot()
        elem=doc.find("storeItems")
        rel=(elem.get("filename","") if elem is not None else "").replace("\\","/")
        if rel.startswith("$mapdir$/"):
            rel=rel[len("$mapdir$/"):]
        if rel and not rel.startswith(("$","/")) and ".." not in PurePosixPath(rel).parts:
            store=str(root/rel)
    if not store:
        if place:
            store=str(Path(place).with_name("storeItems.xml"))
        elif main:
            store=str(main.with_name("storeItems.xml"))
    if not place and main:
        maybe=main.parent/"config"/"placeables.xml"
        if maybe.is_file():
            place=str(maybe)
    return place,store,main


def prepare_map_config(maproot,storeitems):
    """Prepara registro automático do StoreItems no mapa principal."""
    path=map_config_file(maproot)
    if path is None:
        raise ValueError("Não localizei o map.xml declarado no modDesc.xml. "
                         "Sem ele não dá para garantir o registro da loja.")
    main=ET.parse(path)
    root=main.getroot()
    if root.tag!="map":
        raise ValueError("Arquivo principal do mapa não tem raiz <map>.")
    store=Path(storeitems).resolve()
    base=Path(maproot).resolve()
    if not store.is_relative_to(base):
        raise ValueError("StoreItems precisa ficar dentro da pasta raiz do mapa.")
    rel=store.relative_to(base).as_posix()
    tag=root.find("storeItems")
    if tag is None:
        tag=ET.SubElement(root,"storeItems")
    original=(tag.get("filename") or "").replace("\\","/")
    tag.set("filename",rel)
    return path,main,original!=rel


def write_map_bundle(entries):
    """Transação com backup e rollback para 2 ou 3 arquivos XML.

    entries = [(path, ElementTree), ...], incluindo map.xml se necessário.
    """
    if not entries:
        raise ValueError("Nenhum arquivo para gravar.")
    unique=set()
    originals=[]
    backups=[]
    tmp_paths=[]
    replaced=[]
    pending=[]
    for path,tree in entries:
        path=Path(path)
        if path.resolve() in unique:
            raise ValueError("Arquivos XML de destino devem ser diferentes.")
        unique.add(path.resolve())
        if not path.parent.is_dir():
            raise ValueError("Pasta de destino não encontrada: "+str(path.parent))
        data=path.read_bytes() if path.is_file() else None
        if data is None and path.suffix.lower()!=".xml":
            raise ValueError("Só cria arquivos .xml.")
        ET.indent(tree,space="    ")
        blob=ET.tostring(tree.getroot(),encoding="utf-8",xml_declaration=True)
        ET.fromstring(blob)
        pending.append((path,blob))
        originals.append(data)
    try:
        for (path,_),old in zip(pending,originals):
            if old is not None:
                back=path.with_name(path.name+".tg_pc_backup_"+uuid.uuid4().hex[:8])
                back.write_bytes(old)
                backups.append(back)
        for path,blob in pending:
            fd,tmp=tempfile.mkstemp(dir=path.parent,prefix="tg_pc_",suffix=".xml")
            with os.fdopen(fd,"wb") as stream:
                stream.write(blob)
            tmp_paths.append(Path(tmp))
        for i,(path,_) in enumerate(pending):
            os.replace(tmp_paths[i],path)
            replaced.append(i)
    except Exception:
        for i in reversed(replaced):
            path=pending[i][0]
            if originals[i] is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(originals[i])
        raise
    finally:
        for path in tmp_paths:
            path.unlink(missing_ok=True)
    return backups
