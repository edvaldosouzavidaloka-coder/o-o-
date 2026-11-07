"""TG + EDVALDO v1.3 — registrar independentemente no placeables ou storeItems.

Escolher um XML não registra nada. As caixas de destino e o botão explícito
Registrar selecionados são obrigatórios. Não confunde item de loja com objeto
posicionado no mapa. Faz preview, validação, backup e rollback.
"""
from __future__ import annotations

from pathlib import Path
import xml.etree.ElementTree as ET
import TG_PCObjects_Core_v11 as pc
import TG_PCObjects_Localizador_v12 as locator


def catalog_item_from_xml(xml_path, maproot, mods=None):
    path=Path(xml_path).resolve()
    if not path.is_file() or path.suffix.lower()!=".xml":
        raise ValueError("Selecione o XML real do item, não o arquivo I3D.")
    root=ET.parse(path).getroot()
    if root.tag not in ("placeable","vehicle","handTool","pallet"):
        raise ValueError(
            f"O XML é do tipo <{root.tag}>, não é item de loja reconhecido. "
            "Plantas/foliage do mapa não viram itens da loja só com storeItem; "
            "use um XML de objeto comercializável (placeable, veículo etc.).")
    if not root.get("type"):
        raise ValueError("O XML precisa de type para ser registrado como item do FS25.")
    if root.find("storeData") is None:
        raise ValueError("XML sem <storeData>. Sem configuração de loja, "
                         "registrar em storeItems.xml não basta para aparecer na loja.")
    if (root.findtext("./storeData/showInStore","true") or "true").strip().lower()=="false":
        raise ValueError("O próprio XML define showInStore=false; ajuste o item antes "
                         "de registrá-lo na loja.")
    maproot=Path(maproot).resolve()
    if path.is_relative_to(maproot):
        rel=path.relative_to(maproot).as_posix()
        return dict(filename="$mapdir$/"+rel,store_ref=rel,xml=rel,
                    type=root.get("type"),tag=root.tag,origin="map")
    modroot=None
    for source in (mods or {}).values():
        source=Path(source).resolve()
        if source.is_dir() and path.is_relative_to(source):
            modroot=source
            break
    if modroot is None:
        for parent in path.parents:
            if (parent/"modDesc.xml").is_file():
                modroot=parent
                break
    if modroot is None:
        raise ValueError("O XML deve ficar dentro da pasta do mapa ou de um mod "
                         "descompactado com modDesc.xml para gerar o caminho correto.")
    rel=path.relative_to(modroot).as_posix()
    pathref="$moddir$"+modroot.name+"/"+rel
    return dict(filename=pathref,store_ref=pathref,xml=rel,
                type=root.get("type"),tag=root.tag,origin="mod")


def plan_selected_registration(*,maproot,object_xml,placeables_path=None,
                               storeitems_path=None,map_i3d=None,
                               object_i3d=None,do_placeables=False,
                               do_store=False,mods=None):
    """Retorna (entries_para_escrita,summary); NÃO grava arquivos.

    Cada destino é completamente independente. Placeables exige posição no
    mapa; StoreItems exige somente XML de item com storeData. Se ambos forem
    escolhidos, prepara ambos antes de qualquer escrita.
    """
    if not do_placeables and not do_store:
        raise ValueError("Marque ao menos um destino: placeables.xml ou storeItems.xml.")
    maproot=Path(maproot).resolve()
    if not (maproot/"modDesc.xml").is_file():
        raise ValueError("Selecione a pasta raiz do mapa (onde fica modDesc.xml).")
    item=catalog_item_from_xml(object_xml,maproot,mods=mods) if do_store else None
    summary=dict(placeables_new=0,placeables_existing=0,
                 store_new=0,store_existing=0,map_link_changed=False,
                 positions=[],item_xml=str(object_xml))
    entries=[]
    if do_placeables:
        if not placeables_path:
            raise ValueError("Escolha o placeables.xml para registrar posição no mapa.")
        if not map_i3d or not object_i3d:
            raise ValueError("Para placeables.xml informe I3D do MAPA e I3D do OBJETO. "
                             "Somente storeItems.xml não exige esses arquivos.")
        if not Path(map_i3d).is_file() or not Path(object_i3d).is_file():
            raise ValueError("I3D do mapa ou do objeto não encontrado.")
        path=Path(placeables_path).resolve()
        if not path.is_file() or not path.is_relative_to(maproot):
            raise ValueError("O placeables.xml deve existir dentro da pasta do mapa.")
        cfg=ET.parse(Path(object_xml)).getroot()
        if cfg.tag!="placeable" or not cfg.get("type"):
            raise ValueError("Para placeables.xml o XML precisa ter raiz "
                             "<placeable type='...'>; plantas/foliage não são placeables.")
        if item is None:
            item=pc.placeable_item_from_xml(object_xml,maproot,mods)
        scene=Path(map_i3d).resolve()
        if not scene.is_relative_to(maproot):
            raise ValueError("O I3D principal deve estar dentro da pasta do mapa.")
        if scene==Path(object_i3d).resolve():
            raise ValueError("O I3D do MAPA e o I3D do OBJETO são arquivos diferentes.")
        found=locator.find_model_in_scene(scene,object_i3d)
        if not found:
            raise ValueError("Objeto não localizado no I3D do mapa. "
                             "Selecione só StoreItems se deseja apenas a loja, "
                             "ou importe e posicione o modelo no GIANTS Editor.")
        tree=ET.parse(path)
        root=tree.getroot()
        if root.tag!="placeables":
            raise ValueError("O arquivo escolhido não contém a raiz <placeables>.")
        for obj in found:
            attrs=dict(filename=item["filename"],
                       position=pc._posstring(obj["position"]),
                       rotation=pc._posstring(obj["rotation"]),farmId="0")
            candidate=ET.Element("placeable",attrs)
            if any(pc._same_placement(candidate,old)
                   for old in root.findall("placeable")):
                summary["placeables_existing"]+=1
            else:
                ET.SubElement(root,"placeable",attrs)
                summary["placeables_new"]+=1
            summary["positions"].append(
                (obj["name"],attrs["position"],attrs["rotation"]))
        entries.append((path,tree))
    if do_store:
        if not storeitems_path:
            raise ValueError("Escolha o storeItems.xml para registrar na loja.")
        path=Path(storeitems_path).resolve()
        if not path.is_relative_to(maproot):
            raise ValueError("O storeItems.xml deve ficar dentro da pasta do mapa.")
        if path.exists():
            tree=ET.parse(path)
        else:
            if not path.parent.is_dir():
                raise ValueError("Pasta de storeItems.xml não encontrada.")
            tree=ET.ElementTree(ET.Element("storeItems"))
        root=tree.getroot()
        if root.tag!="storeItems":
            raise ValueError("O arquivo escolhido não tem raiz <storeItems>.")
        refs={pc.norm(x.get("xmlFilename")) for x in root.findall("storeItem")}
        if pc.norm(item["store_ref"]) in refs:
            summary["store_existing"]=1
        else:
            ET.SubElement(root,"storeItem",{"xmlFilename":item["store_ref"]})
            summary["store_new"]=1
        entries.append((path,tree))
        mapxml,config_tree,changed=pc.prepare_map_config(maproot,path)
        summary["map_link_changed"]=bool(changed)
        if changed:
            entries.append((mapxml,config_tree))
    summary["changed"]=bool(summary["placeables_new"] or summary["store_new"]
                            or summary["map_link_changed"])
    # Arquivos sem mudança não devem ser reformatados nem receber backup.
    kept=[]
    for path,tree in entries:
        if (do_placeables and Path(path)==Path(placeables_path).resolve()
                and not summary["placeables_new"]):
            continue
        if (do_store and Path(path)==Path(storeitems_path).resolve()
                and not summary["store_new"]):
            continue
        kept.append((path,tree))
    return kept,summary
