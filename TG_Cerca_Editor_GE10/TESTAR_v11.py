"""Testes Windows TG + EDVALDO v1.1 para PC Objects I3D e 3 XMLs."""
from __future__ import annotations
import tempfile
from pathlib import Path
from zipfile import ZipFile
import xml.etree.ElementTree as ET
from unittest.mock import patch

import TG_PCObjects_Core_v11 as pc
from TG_Cerca_Editor_v11 import App,PCObjectsWindow
from TG_Cerca_Segmentos_Originais_v091 import original_points


def fixture(root):
    maproot=root/"FS25_MeuMapa"
    config=maproot/"maps/mapBR"
    (config/"config").mkdir(parents=True)
    (maproot/"modDesc.xml").write_text(
       '<modDesc><maps><map configFilename="maps/mapBR/mapBR.xml" '
       'defaultPlaceablesXMLFilename="maps/mapBR/config/placeables.xml"/></maps></modDesc>',
       encoding="utf-8")
    (config/"mapBR.xml").write_text(
        '<map><storeItems filename="$data/maps/mapUS/config/storeItems.xml"/></map>',
        encoding="utf-8")
    placeables=config/"config/placeables.xml"
    placeables.write_text('<placeables><placeable filename="$data/foo.xml" '
                          'position="0 0 0" rotation="0 0 0"/></placeables>',
                          encoding="utf-8")
    stores=config/"config/storeItems.xml"
    # Arquivo loja ainda nao existe, mas programa vai criar automaticamente.
    i3d=config/"mapBR.i3d"
    i3d.write_text('''<?xml version="1.0" encoding="utf-8"?>
<i3D><Files>
<File fileId="11" filename="../../../FS25_Barracoes/i3d/barn.i3d"/>
<File fileId="12" filename="../../../FS25_Barracoes/i3d/silo.i3d"/>
</Files><Scene>
<TransformGroup name="placeables" translation="100 50 -200" rotation="0 90 0">
<Reference name="barn" fileId="11" translation="10 0 0" rotation="0 0 0"/>
<Reference name="silo" fileId="12" translation="0 0 20" rotation="0 90 0"/>
</TransformGroup>
<Shape name="terreno" translation="0 0 0" shapeId="3"/>
</Scene></i3D>''',encoding="utf-8")
    mod=root/"FS25_Barracoes.zip"
    with ZipFile(mod,"w") as z:
        z.writestr("modDesc.xml",'<modDesc><storeItems>'
                   '<storeItem xmlFilename="placeables/barn.xml"/>'
                   '<storeItem xmlFilename="placeables/silo.xml"/>'
                   '</storeItems></modDesc>')
        for k in ("barn","silo"):
            z.writestr("placeables/"+k+".xml",
               f'<placeable type="silo"><base><filename>i3d/{k}.i3d</filename></base>'
               '<storeData><showInStore>true</showInStore>'
               '<canBeSold>true</canBeSold></storeData></placeable>')
    return maproot,i3d,placeables,stores,mod


def test_backend(root):
    maproot,i3d,placeables,stores,mod=fixture(root)
    found=pc.scan_map_i3d(i3d)
    assert len(found)==2,found
    assert sorted(x["name"] for x in found)==["barn","silo"]
    barn=next(x for x in found if x["name"]=="barn")
    assert all(abs(a-b)<.0001 for a,b in zip(barn["position"],(100,50,-210))),barn
    assert abs(barn["rotation"][1]-90)<1e-6,barn
    inventory=pc.source_inventory(mod,"mod")
    assert len(inventory)==2,inventory
    assigned=pc.auto_match(found,inventory)
    assert len(assigned)==2,assigned
    assert pc.map_config_file(maproot).name=="mapBR.xml"
    guessed=pc.guess_map_xml_paths(maproot)
    assert Path(guessed[0])==placeables
    assert Path(guessed[1])==stores
    a,b,summary=pc.make_map_updates(found,assigned,inventory,placeables,stores)
    assert len(summary["inserted"])==2,summary
    assert len(summary["stores"])==2,summary
    config,conf_tree,change=pc.prepare_map_config(maproot,stores)
    assert change
    assert conf_tree.getroot().find("storeItems").get("filename")=="maps/mapBR/config/storeItems.xml"
    assert not stores.exists()
    baks=pc.write_map_bundle([(placeables,a),(stores,b),(config,conf_tree)])
    assert len(baks)==2,baks
    assert stores.exists()
    assert len(ET.parse(placeables).getroot().findall("placeable"))==3
    assert len(ET.parse(stores).getroot().findall("storeItem"))==2
    assert ET.parse(config).getroot().find("storeItems").get("filename")=="maps/mapBR/config/storeItems.xml"
    assert not pc.check_storeitems_reference(maproot,stores)
    assert any(x.get("filename","").startswith("$moddir$FS25_Barracoes/") 
               for x in ET.parse(placeables).getroot().findall("placeable"))
    a2,b2,summary2=pc.make_map_updates(found,assigned,inventory,placeables,stores)
    assert summary2["inserted"]==[] and summary2["stores"]==[],summary2
    assert len(ET.parse(placeables).getroot().findall("placeable"))==3
    # Modo UM: selecionar somente uma instância gera uma linha.
    other=root/"only_one.xml"
    other.write_text('<placeables/>',encoding="utf-8")
    a3,b3,sm=pc.make_map_updates([found[0]],assigned,inventory,other,stores)
    assert len(sm["inserted"])==1 and sm["stores"]==[]
    # Sintaxe inválida jamais grava placeables/storeitems.
    invalid=root/"bad.xml"
    invalid.write_text('<other/>',encoding="utf-8")
    try:
        pc.make_map_updates(found,assigned,inventory,invalid,stores)
    except ValueError: pass
    else: raise AssertionError("Placeables root invalido deveria bloquear.")
    assert invalid.read_text(encoding="utf-8")=="<other/>"
    print("OK I3D importado: posições/rotacao, um/todos, caminhos e três XMLs com backups.")
    return maproot,i3d,placeables,stores,mod


def test_gui(locations):
    maproot,i3d,placeables,stores,mod=locations
    app=App()
    try:
        app.update()
        assert app.log.master.grid_slaves(row=1,column=1)
        assert original_points([(0.,0.,0.),(10.,0.,0.)])[1][0]==2.
        app.mods={"FS25_Barracoes":mod}
        app.open_pcobjects()
        win=app.pc_window
        win.maproot.set(str(maproot))
        win.auto_destinations()
        win.map_i3d.set(str(i3d))
        win.load_objects()
        assert len(win.entries)==2
        win._refresh_source_options()
        win.source.set("FS25_Barracoes")
        win.load_catalog()
        win.select_all()
        assert len(win._selected_objects())==2
        assert len(win.assignment)==2
        win.select_one()
        assert len(win._selected_objects())==1
        win.select_all()
        win.placeables.set(str(placeables))
        win.storeitems.set(str(stores))
        # Somente preview, sem alteração adicional.
        before=placeables.read_bytes()
        win.dryrun.set(True)
        with patch("tkinter.messagebox.showerror",side_effect=lambda *a,**k: (_ for _ in ()).throw(AssertionError(a))):
            win.register()
        assert placeables.read_bytes()==before
        print("OK interface principal intacta, botão PC Objects, um/todos e prévia.")
        win.destroy()
    finally:
        app.destroy()


if __name__=="__main__":
    with tempfile.TemporaryDirectory() as t:
        locations=test_backend(Path(t))
        test_gui(locations)
    print("TODOS OS TESTES PC OBJECTS v1.1 PASSARAM — testar com mapa real no FS25.")
