"""Testes v1.4: I3D exportado, XYZ/rotacao, registro sem cena do mapa."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from xml.etree import ElementTree as ET

from TESTAR_v11 import fixture
from TG_PCObjects_Export_v14 import (
    export_transform, coordinate_values, generated_decorative_xml,
    build_xml_entries,write_mixed_bundle)
from TG_Cerca_Editor_v14 import App


def setup(root):
    maproot,scene,placeables,store,mod=fixture(root)
    model=maproot/"placeables/galpao/galpao.i3d"
    model.parent.mkdir(parents=True)
    model.write_text('''<?xml version="1.0" encoding="UTF-8"?>
<i3D><Scene>
<TransformGroup name="Galpao" translation="310 72 -240" rotation="0 35 0">
 <Shape name="Telhado" shapeId="1"/>
</TransformGroup>
</Scene></i3D>''',encoding="utf-8")
    return maproot,model,placeables,store,scene


def test_transforms(root):
    maproot,model,placeables,store,scene=setup(root)
    info=export_transform(model)
    assert info["name"]=="Galpao"
    assert info["position"]==(310.,72.,-240.)
    assert info["rotation"]==(0.,35.,0.)
    values=coordinate_values(["310","72","-240"],["0","35","0"])
    assert values[0]==info["position"]
    assert values[1]==info["rotation"]
    invalid=root/"invalid.i3d"
    invalid.write_text('<i3D><Scene><TransformGroup name="galpao">'
                       '<Shape name="x"/></TransformGroup></Scene></i3D>',encoding="utf-8")
    assert export_transform(invalid)["position"] is None
    try:
        coordinate_values(["","",""],["0","0","0"])
    except ValueError:
        pass
    else:
        raise AssertionError("Nao inventar posição zero.")
    print("OK: extrai translation/rotation exportado e exige XYZ manual se ausente.")


def test_generated_only_placeables(root):
    maproot,model,placeables,store,scene=setup(root)
    oldplace=placeables.read_bytes()
    oldmap=(maproot/"maps/mapBR/mapBR.xml").read_bytes()
    entries,summary=build_xml_entries(
        maproot=maproot,object_i3d=model,object_xml="",
        placeables_path=placeables,storeitems_path=store,
        position=["310","72","-240"],rotation=["0","35","0"],
        do_placeables=True,do_store=False)
    assert summary["placeables_new"]==1 and summary["store_new"]==0
    assert summary["generated_decorative"]
    assert len(entries)==3,[(p.name,type(t).__name__) for p,t in entries]
    assert not (model.parent/"tg_galpao_decorativo.xml").exists()
    assert placeables.read_bytes()==oldplace
    backups=write_mixed_bundle(entries)
    assert len(backups)==1,backups
    assert not store.exists()
    assert (maproot/"maps/mapBR/mapBR.xml").read_bytes()==oldmap
    candidate=ET.parse(placeables).findall("placeable")[-1]
    assert candidate.get("filename")=="$mapdir$/placeables/galpao/tg_galpao_decorativo.xml"
    assert candidate.get("position")=="310.0000 72.0000 -240.0000"
    assert candidate.get("rotation")=="0.0000 35.0000 0.0000"
    config=ET.parse(model.parent/"tg_galpao_decorativo.xml").getroot()
    assert config.get("type")=="simplePlaceable"
    assert config.findtext("./base/filename")=="galpao.i3d"
    assert config.findtext("./storeData/image")=="tg_galpao_loja.png"
    assert (model.parent/"tg_galpao_loja.png").read_bytes().startswith(b"\x89PNG")
    second,summary2=build_xml_entries(
        maproot=maproot,object_i3d=model,object_xml="",
        placeables_path=placeables,
        position=["310","72","-240"],rotation=["0","35","0"],
        do_placeables=True,do_store=False)
    assert second==[] and summary2["placeables_existing"]==1
    print("OK: export I3D -> gera XML decorativo+PNG+placeables, sem loja; sem duplicata.")


def test_store_only_no_scene(root):
    maproot,model,placeables,store,scene=setup(root)
    original=placeables.read_bytes()
    entries,summary=build_xml_entries(
        maproot=maproot,object_i3d=model,object_xml="",
        placeables_path="",storeitems_path=store,
        position=["","",""],rotation=["","",""],
        do_placeables=False,do_store=True)
    assert summary["store_new"]==1 and summary["placeables_new"]==0
    assert summary["map_link_changed"]
    assert len(entries)==4,[(p.name,type(t).__name__) for p,t in entries]
    assert placeables.read_bytes()==original and not store.exists()
    write_mixed_bundle(entries)
    assert len(ET.parse(store).getroot().findall("storeItem"))==1
    assert placeables.read_bytes()==original
    assert ET.parse(maproot/"maps/mapBR/mapBR.xml").find("storeItems").get("filename").endswith(
        "storeItems.xml")
    print("OK: loja apenas com I3D exportado, sem I3D de mapa nem localização.")


def test_full_and_existing(root):
    maproot,model,placeables,store,scene=setup(root)
    config=model.with_suffix(".xml")
    config.write_text(
        '<placeable type="silo"><storeData><name>Silo Pro</name>'
        '<image>icon.png</image><price>10000</price><showInStore>true</showInStore>'
        '</storeData><base><filename>galpao.i3d</filename></base></placeable>',encoding="utf-8")
    (model.parent/"icon.png").write_bytes(b"testfakeimage")
    entries,summary=build_xml_entries(
        maproot=maproot,object_i3d=model,object_xml=config,
        placeables_path=placeables,storeitems_path=store,
        position=["320","75","-244"],rotation=["0","145","0"],
        do_placeables=True,do_store=True)
    assert summary["placeables_new"]==1 and summary["store_new"]==1
    assert not summary["generated_decorative"]
    assert len(entries)==3
    write_mixed_bundle(entries)
    assert ET.parse(placeables).findall("placeable")[-1].get("rotation")=="0.0000 145.0000 0.0000"
    assert len(ET.parse(store).findall("storeItem"))==1
    assert not (model.parent/"tg_galpao_decorativo.xml").exists()
    print("OK: XML funcional existente respeitado, XYZ/rota manual, ambos destinos.")


def test_outside_fails(root):
    maproot,model,placeables,store,scene=setup(root)
    external=root/"externo.i3d"
    external.write_text(model.read_text(encoding="utf-8"),encoding="utf-8")
    try:
        generated_decorative_xml(external,maproot)
    except ValueError as e:
        assert "dentro" in str(e)
    else:
        raise AssertionError("Modelo fora do mapa necessita copiar dependências.")
    print("OK: não registra modelo fora da raiz sem os recursos I3D.")


def test_gui(root):
    maproot,model,placeables,store,scene=setup(root)
    app=App()
    try:
        app.update()
        app.open_pcobjects()
        w=app.pc_window
        w.maproot.set(str(maproot))
        w.object_i3d.set(str(model))
        w.placeables.set(str(placeables))
        assert w.read_export_position()
        assert [v.get() for v in w.pos_vars]==["310","72","-240"]
        assert [v.get() for v in w.rot_vars]==["0","35","0"]
        w.to_placeables.set(True)
        summary=w.preview_registration()
        assert summary and summary["placeables_new"]==1
        assert len(ET.parse(placeables).findall("placeable"))==1
        assert not (model.parent/"tg_galpao_decorativo.xml").exists()
        with patch("tkinter.messagebox.askyesno",return_value=True),\
             patch("tkinter.messagebox.showinfo"):
            w.register()
        assert len(ET.parse(placeables).findall("placeable"))==2
        assert not store.is_file()
        # Se mudar a rotação após conferir, bloquear até nova prévia.
        w.rot_vars[1].set("80")
        with patch("tkinter.messagebox.showwarning") as m:
            w.register()
            assert m.called
        assert len(ET.parse(placeables).findall("placeable"))==2
        w.destroy()
        print("OK interface: sem cena principal, position XYZ/editável, preview e confirmação.")
    finally:
        app.destroy()


if __name__=="__main__":
    for fun in (test_transforms,test_generated_only_placeables,
                test_store_only_no_scene,test_full_and_existing,
                test_outside_fails,test_gui):
        with TemporaryDirectory() as t:
            fun(Path(t))
    print("v1.4 TESTES OK — validar no FS25 a origem, rotação e loja real.")
