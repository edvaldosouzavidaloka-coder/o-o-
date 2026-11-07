"""Regressão do bug: Selecionar UM com tabela vazia e abatedouro.i3d isolado."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from xml.etree import ElementTree as ET

from TESTAR_v11 import fixture
from TG_Cerca_Editor_v11 import App
from TG_PCObjects_Localizador_v12 import (
    find_imported_model_in_map,main_map_scenes,is_model_i3d)


def build_scene(maproot,i3d):
    model=maproot/"placeables/abatedouro1/abatedouro.i3d"
    model.parent.mkdir(parents=True)
    model.write_text("""<i3D><Scene><TransformGroup name="Abatedouro">
        <Shape name="paredes" shapeId="1"/></TransformGroup></Scene></i3D>""",
        encoding="utf-8")
    tree=ET.parse(i3d)
    files=tree.find("./Files")
    ET.SubElement(files,"File",{"fileId":"17",
        "filename":"../../placeables/abatedouro1/abatedouro.i3d"})
    scene=tree.find("Scene")
    placeables=scene.find("TransformGroup")
    ET.SubElement(placeables,"Reference",{
        "name":"abatedouro",
        "fileId":"17",
        "translation":"30 0 0",
        "rotation":"0 0 0"})
    ET.SubElement(placeables,"Reference",{
        "name":"abatedouro",
        "fileId":"17",
        "translation":"80 0 0",
        "rotation":"0 0 0"})
    tree.write(i3d,encoding="utf-8")
    return model


def test_locator(maproot,i3d,model):
    assert is_model_i3d(model,maproot)
    assert not is_model_i3d(i3d,maproot)
    scenes=main_map_scenes(maproot,exclude=model)
    assert any(p.resolve()==i3d.resolve() for p in scenes),(str(i3d.resolve()),[str(p.resolve()) for p in scenes])
    found, scenes, errors=find_imported_model_in_map(model,maproot)
    assert len(found)==2,found
    assert all(Path(x["map_scene"]).resolve()==i3d.resolve() for x in found)
    assert all(x["kind"]=="instância importada no mapa" for x in found)
    assert len({x["id"] for x in found})==2
    assert abs(found[0]["position"][0]-100)<.001
    assert abs(found[1]["position"][0]-100)<.001
    assert abs(found[0]["position"][2]+230)<.001
    assert abs(found[1]["position"][2]+280)<.001
    print("OK: abatedouro.i3d não contém posição; encontrou duas instâncias no mapa.")


def test_gui(maproot,i3d,model):
    app=App()
    try:
        app.update()
        app.open_pcobjects()
        win=app.pc_window
        win.maproot.set(str(maproot))
        win.map_i3d.set(str(model))
        assert not win.entries and not win.table.get_children()
        # O botão UM deve carregar a cena/mapa automaticamente antes de selecionar.
        with patch("tkinter.messagebox.showwarning",side_effect=AssertionError):
            win.select_one()
        assert len(win.entries)==2
        assert len(win.table.selection())==1
        assert len(win._selected_objects())==1
        assert win.table.focus() in win.table.get_children()
        win.select_all()
        assert len(win._selected_objects())==2
        # Busca I3D principal do mapa mesmo depois de selecionar o modelo.
        loaded=win.load_main_map()
        assert loaded>=2
        assert Path(win.map_i3d.get())==i3d
        # Ao selecionar um com lista previamente carregada, não reler I3D.
        with patch.object(win,"load_objects",side_effect=AssertionError("Recarregou ao escolher UM")):
            win.select_one()
        assert len(win._selected_objects())==1
        print("OK: selecionar UM/TODOS com tabela vazia carrega modelos; escolha muda seleção.")
        win.destroy()
    finally:
        app.destroy()


def test_missing_reference(maproot,model,i3d):
    tree=ET.parse(i3d)
    scene=tree.find("Scene")
    placeables=scene.find("TransformGroup")
    for item in list(placeables):
        if item.tag=="Reference" and item.get("fileId")=="17":
            placeables.remove(item)
    tree.write(i3d,encoding="utf-8")
    found,_,_=find_imported_model_in_map(model,maproot)
    assert not found
    app=App()
    try:
        app.update()
        app.open_pcobjects()
        win=app.pc_window
        win.maproot.set(str(maproot))
        win.map_i3d.set(str(model))
        warnings=[]
        with patch("tkinter.messagebox.showwarning",side_effect=lambda *a,**kw:warnings.append((a,kw))):
            win.select_one()
        assert len(warnings)==1,warnings
        assert "posição" in (warnings[0][0][0]+" "+warnings[0][0][1]).lower()
        assert not win.entries and not win.table.selection()
        assert "Apenas um objeto selecionado." not in win.log.get("1.0","end")
        print("OK: falta de posição mostra aviso claro, não inventa coordenadas.")
        win.destroy()
    finally:
        app.destroy()




def test_separate_map_and_object_and_xml(root):
    maproot,i3d,placeables,stores,mod=fixture(root)
    model=build_scene(maproot,i3d)
    directxml=model.with_suffix(".xml")
    directxml.write_text(
        '<placeable type="sellingStation"><base><filename>'
        'placeables/abatedouro1/abatedouro.i3d</filename></base>'
        '<storeData><showInStore>true</showInStore></storeData></placeable>',
        encoding="utf-8")
    # O grupo pode ter nome "abatedouro", mesmo sem ser uma das categorias
    # clássicas do leitor inicial.
    tree=ET.parse(i3d)
    scene=tree.find("Scene")
    root_group=scene.find("TransformGroup")
    ET.SubElement(root_group,"TransformGroup",{
        "name":"abatedouro","translation":"30 0 20","rotation":"0 0 0"})
    tree.write(i3d,encoding="utf-8")
    from TG_PCObjects_Localizador_v12 import find_model_in_scene
    found=find_model_in_scene(i3d,model)
    assert len(found)==3,found
    item=__import__("TG_PCObjects_Core_v11").placeable_item_from_xml(
        directxml,maproot,{})
    assert item["type"]=="sellingStation"
    assert item["filename"].endswith("/placeables/abatedouro1/abatedouro.xml")
    assert item["origin"]=="map"

    app=App()
    try:
        app.update()
        app.open_pcobjects()
        win=app.pc_window
        win.maproot.set(str(maproot))
        win.map_i3d.set(str(i3d))
        win.object_i3d.set(str(model))
        win.object_xml.set(str(directxml))
        assert win.load_objects()==3
        assert len(win.assignment)==3
        assert len(win.inventory)==1
        win.select_one()
        assert len(win._selected_objects())==1
        win.select_all()
        assert len(win._selected_objects())==3
        win.placeables.set(str(placeables))
        win.storeitems.set(str(stores))
        a,b,changes=__import__("TG_PCObjects_Core_v11").make_map_updates(
            win._selected_objects(),win.assignment,win.inventory,placeables,stores)
        assert len(changes["inserted"])==3,changes
        assert len(changes["stores"])==1,changes
        assert a.getroot().findall("placeable")[0].get("filename")=="$data/foo.xml"
        assert all(x.get("filename").endswith("/placeables/abatedouro1/abatedouro.xml")
                   for x in a.getroot().findall("placeable")[1:])
        assert not stores.exists(), "Prévia não pode escrever arquivos"
        print("OK três campos MAPA/I3D ITEM/XML ITEM, grupo abatedouro, UM/TODOS e registros.")
        win.destroy()
    finally:
        app.destroy()

if __name__=="__main__":
    with TemporaryDirectory() as t:
        root=Path(t)
        maproot,i3d,placeables,stores,mod=fixture(root)
        model=build_scene(maproot,i3d)
        test_locator(maproot,i3d,model)
        test_gui(maproot,i3d,model)
        test_missing_reference(maproot,model,i3d)
    with TemporaryDirectory() as t:
        test_separate_map_and_object_and_xml(Path(t))
    print("TESTES v1.2: PASSOU. Fazer prova no mapa real.")
