"""TG + EDVALDO FS25 v1.4 — I3D exportado: transformaçao e XML decorativo.

Le um objeto que foi exportado do GIANTS Editor, sem procurar a instancia
na cena principal do mapa. As posicoes XYZ e rotacoes XYZ podem ser
informadas manualmente; uma cena sem transform nao fornece coordenadas
globais confiaveis, e nao é substituida silenciosamente por 0 0 0.

Sem XML do item: gera somente um simplePlaceable DECORATIVO basico.
Nao cria silos funcionais, triggers, animacao ou fabrícas.
"""
from __future__ import annotations
from pathlib import Path
import io
import math
import os
import re
import xml.etree.ElementTree as ET

import TG_PCObjects_Core_v11 as pc


def _vector(value):
    if value is None or not str(value).strip():
        return None
    items=str(value).strip().replace(",",".").split()
    if len(items)!=3:
        return None
    try:
        result=tuple(float(x) for x in items)
    except ValueError:
        return None
    return result if all(math.isfinite(x) for x in result) else None


def export_transform(i3d_file):
    """Lê posição e rotação do nó raiz único exportado no I3D.

    A informação pode ser coordenada LOCAL do GE, não posição global.
    Por isso a UI precisa deixar esses números editáveis e conferíveis.
    """
    path=Path(i3d_file)
    if not path.is_file() or path.suffix.lower()!=".i3d":
        raise ValueError("Selecione um arquivo de OBJETO .i3d exportado pelo GIANTS Editor.")
    scene=ET.parse(path).getroot().find("Scene")
    if scene is None:
        raise ValueError("I3D exportado sem <Scene>.")
    roots=[node for node in scene
           if node.tag in ("TransformGroup","Reference","Shape")]
    if not roots:
        raise ValueError("Nenhum nó raiz de objeto foi encontrado na cena I3D.")
    if len(roots)==1:
        node=roots[0]
    else:
        match=[n for n in roots
               if (n.get("name") or "").casefold()==path.stem.casefold()]
        if len(match)!=1:
            raise ValueError("O I3D contém vários objetos raiz. Exporte apenas o grupo "
                             "do objeto no GE, ou informe a posição manualmente.")
        node=match[0]
    position=_vector(node.get("translation"))
    rotation=_vector(node.get("rotation"))
    # Translation omitida NÃO equivale a coordenada global zero.
    # A rotação sem atributo pode ser zero, mas só assumimos isso
    # depois que a posição explícita foi encontrada.
    if position is not None and rotation is None:
        rotation=(0.,0.,0.)
    return dict(name=node.get("name") or path.stem,
                position=position,rotation=rotation,
                has_explicit_position=node.get("translation") is not None,
                warning=("Confira se a transformação do grupo exportado é a "
                         "coordenada GLOBAL do mapa. Se o GE zerou a origem "
                         "na exportação, digite XYZ e rotação manualmente."))


def coordinate_values(pos,rot):
    """Aceita campos XYZ e graus da UI, exigindo escolha explícita."""
    try:
        x=tuple(float(v.replace(",",".")) for v in pos)
        r=tuple(float(v.replace(",",".")) for v in rot)
    except (ValueError,AttributeError):
        raise ValueError("Preencha X, Y, Z e Rot X, Rot Y, Rot Z com números. "
                         "Use o botão 'Ler posição do I3D' ou digite os valores.")
    if len(x)!=3 or len(r)!=3 or not all(math.isfinite(v) for v in (*x,*r)):
        raise ValueError("As coordenadas XYZ e rotações XYZ devem ser números finitos.")
    if any(abs(v)>1_000_000 for v in x):
        raise ValueError("Coordenadas fora do tamanho esperado do mapa.")
    return x,r


def _shop_icon(title):
    """Ícone básico gerado localmente para o item estático decorativo."""
    from PIL import Image,ImageDraw
    img=Image.new("RGB",(256,256),(18,36,30))
    draw=ImageDraw.Draw(img)
    draw.rounded_rectangle((8,8,248,248),radius=18,fill=(29,70,52),
                           outline=(101,181,126),width=5)
    draw.polygon([(44,117),(128,54),(213,117)],fill=(168,201,170))
    draw.rectangle((58,117,200,209),fill=(92,135,104))
    draw.rectangle((105,153,151,209),fill=(28,59,43))
    draw.text((20,222),"TG + EDVALDO",fill=(235,248,228))
    out=io.BytesIO()
    img.save(out,format="PNG")
    return out.getvalue()


def generated_decorative_xml(i3d_file,maproot):
    """Cria em memória um simplePlaceable, sem mudar o I3D nem a pasta do mapa.

    Retorna (PathXML, ElementTreeXML, imagem_path, imagem_bytes, metadata).
    """
    model=Path(i3d_file).resolve()
    root=Path(maproot).resolve()
    if not (root/"modDesc.xml").is_file():
        raise ValueError("Escolha a pasta raiz do mapa que contém modDesc.xml.")
    if not model.is_file() or model.suffix.lower()!=".i3d":
        raise ValueError("Escolha um I3D de objeto existente.")
    if not model.is_relative_to(root):
        raise ValueError("Para criar XML decorativo automaticamente, o I3D precisa "
                         "estar dentro da pasta raiz do mapa. Não posso copiar o "
                         "modelo sem suas texturas, i3d.shapes e dependências.")
    slug=re.sub(r"[^a-z0-9_-]+","_",model.stem.casefold()).strip("_") or "objeto"
    xml=model.parent/("tg_"+slug+"_decorativo.xml")
    icon=model.parent/("tg_"+slug+"_loja.png")
    if xml.is_file():
        tree=ET.parse(xml)
        current=tree.getroot()
        expected=model.name
        if (current.tag!="placeable" or
            current.get("type")!="simplePlaceable" or
            (current.findtext("./base/filename") or "").replace("\\","/")!=expected or
            current.findtext("./annotation")!="TG EDVALDO DECORATIVO AUTO"):
            raise ValueError("Já existe "+xml.name+
                             " com conteúdo diferente. Não vou sobrescrever XML de outro mod.")
        xml_data=None
    else:
        node=ET.Element("placeable",{"type":"simplePlaceable"})
        ET.SubElement(node,"annotation").text="TG EDVALDO DECORATIVO AUTO"
        store=ET.SubElement(node,"storeData")
        ET.SubElement(store,"name").text=model.stem.replace("_"," ").strip() or "Objeto decorativo"
        functions=ET.SubElement(store,"functions")
        ET.SubElement(functions,"function").text="Decoração"
        ET.SubElement(store,"image").text=icon.name
        ET.SubElement(store,"price").text="1000"
        ET.SubElement(store,"dailyUpkeep").text="0"
        ET.SubElement(store,"lifetime").text="600"
        ET.SubElement(store,"brand").text="NONE"
        ET.SubElement(store,"species").text="placeable"
        ET.SubElement(store,"category").text="placeableMisc"
        ET.SubElement(store,"canBeSold").text="true"
        ET.SubElement(store,"showInStore").text="true"
        # A ausência de brush usa a categoria de construção padrão do jogo.
        base=ET.SubElement(node,"base")
        ET.SubElement(base,"filename").text=model.name
        ET.SubElement(base,"canBeDeleted").text="true"
        tree=ET.ElementTree(node)
        xml_data=tree
    item={"filename":"$mapdir$/"+xml.relative_to(root).as_posix(),
          "store_ref":xml.relative_to(root).as_posix(),
          "xml":xml.relative_to(root).as_posix(),"origin":"map",
          "type":"simplePlaceable","tag":"placeable"}
    assets=[]
    if xml_data is not None:
        assets.append((xml,xml_data))
    if not icon.is_file():
        assets.append((icon,_shop_icon(model.stem)))
    return item,assets


def build_xml_entries(*,maproot,object_i3d,object_xml,placeables_path,
                      storeitems_path,position,rotation,do_placeables,do_store,
                      mods=None):
    """Plano sem gravar: (arquivos a escrever, sumário).

    Placeables usa EXCLUSIVAMENTE coordenadas do usuário/exportado,
    sem exigir I3D principal do mapa; loja independente.
    """
    if not do_placeables and not do_store:
        raise ValueError("Marque 'placeables.xml', 'storeItems.xml' ou os dois.")
    root=Path(maproot).resolve()
    if not (root/"modDesc.xml").is_file():
        raise ValueError("Escolha a pasta raiz do mapa com modDesc.xml.")
    raw=str(object_xml or "").strip()
    generated=False
    asset_entries=[]
    if raw:
        if do_store:
            # Faz validação de storeData ao registrar na loja.
            from TG_PCObjects_Registros_v13 import catalog_item_from_xml
            item=catalog_item_from_xml(raw,root,mods)
        else:
            item=pc.placeable_item_from_xml(raw,root,mods)
    else:
        if not object_i3d:
            raise ValueError("Selecione I3D do OBJETO ou informe o XML do item.")
        item,asset_entries=generated_decorative_xml(object_i3d,root)
        generated=True
    if do_placeables and item["tag"]!="placeable":
        raise ValueError("Somente XML <placeable> pode ser registrado em placeables.xml.")
    summary={"placeables_new":0,"placeables_existing":0,
             "store_new":0,"store_existing":0,"map_link_changed":False,
             "positions":[],"item_xml":item["filename"],
             "generated_decorative":generated}
    entries=[]
    if do_placeables:
        if not placeables_path:
            raise ValueError("Selecione placeables.xml do mapa.")
        if not object_i3d or not Path(object_i3d).is_file():
            raise ValueError("Selecione o I3D exportado do OBJETO, sem precisar "
                             "do I3D principal do mapa.")
        x,rot=coordinate_values(position,rotation)
        dest=Path(placeables_path).resolve()
        if not dest.is_file() or not dest.is_relative_to(root):
            raise ValueError("O placeables.xml deve existir dentro da pasta do mapa.")
        tree=ET.parse(dest)
        if tree.getroot().tag!="placeables":
            raise ValueError("O arquivo escolhido não é um <placeables> válido.")
        obj=ET.Element("placeable",{
            "filename":item["filename"],
            "position":pc._posstring(x),
            "rotation":pc._posstring(rot),
            "farmId":"0"})
        if any(pc._same_placement(obj,old) for old in tree.getroot().findall("placeable")):
            summary["placeables_existing"]=1
        else:
            tree.getroot().append(obj)
            summary["placeables_new"]=1
            entries.append((dest,tree))
        summary["positions"].append((Path(object_i3d).stem,
                                      obj.get("position"),obj.get("rotation")))
    if do_store:
        if not storeitems_path:
            raise ValueError("Selecione storeItems.xml do mapa.")
        dest=Path(storeitems_path).resolve()
        if not dest.is_relative_to(root):
            raise ValueError("O storeItems.xml deve ficar dentro da pasta do mapa.")
        tree=ET.parse(dest) if dest.is_file() else ET.ElementTree(ET.Element("storeItems"))
        if tree.getroot().tag!="storeItems":
            raise ValueError("Arquivo de destino não tem raiz <storeItems>.")
        prior={pc.norm(n.get("xmlFilename")) for n in tree.getroot().findall("storeItem")}
        if pc.norm(item["store_ref"]) in prior:
            summary["store_existing"]=1
        else:
            ET.SubElement(tree.getroot(),"storeItem",{"xmlFilename":item["store_ref"]})
            summary["store_new"]=1
            entries.append((dest,tree))
        mapxml,config,changed=pc.prepare_map_config(root,dest)
        summary["map_link_changed"]=changed
        if changed:
            entries.append((mapxml,config))
    entries=asset_entries+entries
    summary["changed"]=bool(entries)
    return entries,summary


def write_mixed_bundle(entries):
    """Transação XML + imagem PNG com backups e rollback.

    Entrada (path, ElementTree) ou (path, bytes).
    Grava somente após o usuário marcar destinos, CONFERIR e confirmar.
    """
    import tempfile,uuid
    paths=[]
    originals=[]
    pending=[]
    seen=set()
    for path,payload in entries:
        path=Path(path).resolve()
        if path in seen:
            raise ValueError("Mesmo arquivo XML/PNG selecionado mais de uma vez.")
        seen.add(path)
        if not path.parent.is_dir():
            raise ValueError("Pasta de destino não existe: "+str(path.parent))
        old=path.read_bytes() if path.is_file() else None
        if isinstance(payload,ET.ElementTree):
            ET.indent(payload,space="    ")
            blob=ET.tostring(payload.getroot(),encoding="utf-8",xml_declaration=True)
            ET.fromstring(blob)
        elif isinstance(payload,bytes) and path.suffix.lower()==".png":
            if not payload.startswith(b"\x89PNG\r\n\x1a\n"):
                raise ValueError("Imagem da loja não é PNG válido.")
            blob=payload
        else:
            raise ValueError("Só XML validado ou imagem PNG podem ser gravados.")
        paths.append(path)
        originals.append(old)
        pending.append(blob)
    temps=[]
    replaced=[]
    backups=[]
    try:
        for path,old in zip(paths,originals):
            if old is not None:
                backup=path.with_name(path.name+".tg_pc_backup_"+uuid.uuid4().hex[:8])
                backup.write_bytes(old)
                backups.append(backup)
        for path,blob in zip(paths,pending):
            fd,tmp=tempfile.mkstemp(dir=path.parent,prefix="tg_pc_",suffix=path.suffix)
            with os.fdopen(fd,"wb") as fdstream:
                fdstream.write(blob)
            temps.append(Path(tmp))
        for j,(path,tmp) in enumerate(zip(paths,temps)):
            os.replace(tmp,path)
            replaced.append(j)
    except Exception:
        for j in reversed(replaced):
            if originals[j] is None:
                paths[j].unlink(missing_ok=True)
            else:
                paths[j].write_bytes(originals[j])
        raise
    finally:
        for tmp in temps:
            tmp.unlink(missing_ok=True)
    return backups
