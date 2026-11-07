"""v1.3: regressões dos destinos independentes e da gravação por confirmação."""
from pathlib import Path
import tempfile
from unittest.mock import patch
from xml.etree import ElementTree as ET

from TESTAR_v11 import fixture
from TESTAR_v12 import build_scene
from TG_Cerca_Editor_v13 import App
from TG_PCObjects_Registros_v13 import (
    plan_selected_registration,catalog_item_from_xml)
from TG_PCObjects_Core_v11 import write_map_bundle


def configured_map(root):
    maproot,main_i3d,placeables,storeitems,mod=fixture(root)
    model=build_scene(maproot,main_i3d)
    xml=model.with_suffix(".xml")
    xml.write_text(
        '<placeable type="sellingStation"><base><filename>'
        'placeables/abatedouro1/abatedouro.i3d</filename></base>'
        '<storeData><showInStore>true</showInStore>'
        '<category>placeables</category></storeData></placeable>',
        encoding="utf-8")
    return maproot,main_i3d,placeables,storeitems,model,xml


def test_mode_none(root):
    maproot,scene,placeables,store,model,xml=configured_map(root)
    try:
        plan_selected_registration(maproot=maproot,object_xml=xml)
    except ValueError as e:
        assert "Marque" in str(e)
    else:
        raise AssertionError("Sem caixa marcada não pode registrar.")
    print("OK: nenhum registro habilitado por padrão.")


def test_only_store(root):
    maproot,scene,placeables,store,model,xml=configured_map(root)
    initial_placeables=placeables.read_bytes()
    mapxml=maproot/"maps/mapBR/mapBR.xml"
    entries,summary=plan_selected_registration(
        maproot=maproot,object_xml=xml,storeitems_path=store,
        do_store=True)
    assert summary["placeables_new"]==0 and summary["store_new"]==1,summary
    assert summary["map_link_changed"]
    assert {p.name for p,t in entries}=={"storeItems.xml","mapBR.xml"}
    assert not store.is_file() and placeables.read_bytes()==initial_placeables
    backups=write_map_bundle(entries)
    assert store.is_file() and placeables.read_bytes()==initial_placeables
    assert len(ET.parse(store).findall("storeItem"))==1
    assert ET.parse(mapxml).find("./storeItems").get("filename").endswith("storeItems.xml")
    assert any("mapBR.xml" in str(b) for b in backups),backups
    entries2,summary2=plan_selected_registration(
        maproot=maproot,object_xml=xml,storeitems_path=store,
        do_store=True)
    assert entries2==[] and summary2["store_existing"]==1
    print("OK só StoreItems sem I3D/placeables; registro idempotente e map.xml correto.")


def test_only_placeables(root):
    maproot,scene,placeables,store,model,xml=configured_map(root)
    mapxml=maproot/"maps/mapBR/mapBR.xml"
    old_map=mapxml.read_bytes()
    entries,summary=plan_selected_registration(
        maproot=maproot,object_xml=xml,placeables_path=placeables,
        map_i3d=scene,object_i3d=model,do_placeables=True)
    assert summary["placeables_new"]==2,summary
    assert summary["store_new"]==0
    assert len(entries)==1 and entries[0][0]==placeables.resolve()
    write_map_bundle(entries)
    assert mapxml.read_bytes()==old_map
    assert not store.is_file()
    assert len(ET.parse(placeables).findall("placeable"))==3
    newer,now=plan_selected_registration(
        maproot=maproot,object_xml=xml,placeables_path=placeables,
        map_i3d=scene,object_i3d=model,do_placeables=True)
    assert newer==[] and now["placeables_existing"]==2,now
    print("OK só placeables: 2 posições reais, nenhuma escrita na loja ou map.xml.")


def test_both(root):
    maproot,scene,placeables,store,model,xml=configured_map(root)
    entries,summary=plan_selected_registration(
        maproot=maproot,object_xml=xml,placeables_path=placeables,
        storeitems_path=store,map_i3d=scene,object_i3d=model,
        do_placeables=True,do_store=True)
    assert summary["placeables_new"]==2 and summary["store_new"]==1
    assert len(entries)==3
    assert store.is_file()==False
    write_map_bundle(entries)
    assert len(ET.parse(placeables).findall("placeable"))==3
    assert len(ET.parse(store).findall("storeItem"))==1
    print("OK ambos escolhidos: grava placeables + StoreItems + referência map.xml.")


def test_store_xml_validation(root):
    maproot,scene,placeables,store,model,xml=configured_map(root)
    vehicle=maproot/"vehicles/trator.xml"
    vehicle.parent.mkdir()
    vehicle.write_text(
        '<vehicle type="tractor"><storeData><showInStore>true</showInStore>'
        '</storeData></vehicle>',encoding="utf-8")
    catalog=catalog_item_from_xml(vehicle,maproot)
    assert catalog["tag"]=="vehicle" and catalog["store_ref"]=="vehicles/trator.xml"
    entries,summary=plan_selected_registration(
        maproot=maproot,object_xml=vehicle,storeitems_path=store,do_store=True)
    assert summary["store_new"]==1 and summary["placeables_new"]==0
    # Em contraste com loja, vehicles não são placeables de mapa.
    try:
        plan_selected_registration(
            maproot=maproot,object_xml=vehicle,placeables_path=placeables,
            map_i3d=scene,object_i3d=model,do_placeables=True)
    except ValueError as e:
        assert "placeable" in str(e).lower()
    else:
        raise AssertionError("Veículo não pode ser gravado como placeable.")
    foliage=maproot/"foliage/planta.xml"
    foliage.parent.mkdir()
    foliage.write_text('<foliage><fruitType name="potato"/></foliage>',encoding="utf-8")
    try:
        catalog_item_from_xml(foliage,maproot)
    except ValueError as e:
        assert "não é item de loja" in str(e)
    else:
        raise AssertionError("Foliage não deve virar storeItem indiscriminadamente.")
    print("OK: loja aceita XML comprável; não confunde vegetação comum com item.")


def test_gui(root):
    maproot,scene,placeables,store,model,xml=configured_map(root)
    app=App()
    try:
        app.update()
        app.open_pcobjects()
        win=app.pc_window
        win.update()
        assert not win.to_placeables.get() and not win.to_store.get()
        assert str(win.table.cget("selectmode")).lower() not in ("extended","browse")
        buttons=[]
        actions=win.log.master.grid_slaves(row=11)[0]
        for widget in actions.winfo_children():
            try: buttons.append(widget.cget("text"))
            except Exception: pass
        assert not any("Selecionar UM" in b or "Selecionar TODOS" in b for b in buttons)
        win.maproot.set(str(maproot))
        win.object_xml.set(str(xml))
        win.storeitems.set(str(store))
        # Registro sem a conferência deve avisar, e nunca criar o arquivo.
        notices=[]
        with patch("tkinter.messagebox.showwarning",
                   side_effect=lambda *args,**kwargs:notices.append(args)):
            win.register()
        assert notices and not store.is_file()
        win.to_store.set(True)
        result=win.preview_registration()
        assert result and result["store_new"]==1 and not store.is_file()
        # Nenhum I3D foi selecionado, mas somente StoreItems funciona.
        with patch("tkinter.messagebox.askyesno",return_value=True),\
             patch("tkinter.messagebox.showinfo"):
            win.register()
        assert store.is_file()
        assert len(ET.parse(placeables).findall("placeable"))==1
        win.destroy()
        print("OK GUI: sem UM/TODOS; marca Store e confere antes de registrar.")
    finally:
        app.destroy()


if __name__=="__main__":
    with tempfile.TemporaryDirectory() as t:
        test_mode_none(Path(t))
    with tempfile.TemporaryDirectory() as t:
        test_only_store(Path(t))
    with tempfile.TemporaryDirectory() as t:
        test_only_placeables(Path(t))
    with tempfile.TemporaryDirectory() as t:
        test_both(Path(t))
    with tempfile.TemporaryDirectory() as t:
        test_store_xml_validation(Path(t))
    with tempfile.TemporaryDirectory() as t:
        test_gui(Path(t))
    print("v1.3: TESTES PASSARAM. Verificar os tipos de objeto do mapa real no FS25.")
