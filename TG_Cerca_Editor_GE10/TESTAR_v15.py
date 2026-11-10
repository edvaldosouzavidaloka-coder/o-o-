"""Regressões Windows da prévia 3D e inversão efetiva no XML do FS25."""
from __future__ import annotations
import math
import tempfile
from pathlib import Path
from unittest.mock import patch
import xml.etree.ElementTree as ET

from TG_Cerca_Editor_v15 import App
from TG_Cerca_Preview3D_v15 import (
    scene_geometry,project,nearest_position,invert_fence_direction)
from TG_Cerca_AntiDuplicatas_v09 import _route,scan_overlapping_fences
from TG_Cerca_Geometria_Nativa_v142 import build_fence_v08,gate_span
from TESTAR_v142 import mod_fixture


def points():
    return [(float(i),65.0,0.0) for i in range(101)]


def test_scene():
    pts=points()
    sc=scene_geometry(pts,center_percent=50,gate_width=10.310624,
                      panel=4.,window=58)
    assert sc and len(sc["poles"])>4 and len(sc["pieces"])>3
    assert sc["gap"] and not sc["warning"]
    assert math.isclose(sc["gap"][0],44.844688,abs_tol=.004)
    assert math.isclose(sc["gap"][1],55.155312,abs_tol=.004)
    assert math.isclose(sc["center"][0],50.,abs_tol=.001)
    assert all(not(a[0]<sc["gap"][0] and b[0]>sc["gap"][1])
               for a,b in sc["pieces"])
    for az in (0,30,90,180,270,359):
        result=project((65,66,3),sc["center"],az,50,1,(430,360),58)
        assert len(result)==3 and all(math.isfinite(v) for v in result)
    # Clique no centro do traçado projetado retorna posição ao longo da spline.
    screen=project(sc["center"],sc["center"],25,52,1,(430,360),58)
    arc,distance=nearest_position(sc,sc["center"],25,52,1,
                                  430,360,screen[0],screen[1])
    assert arc is not None and abs(arc-50)<1
    assert distance<3
    empty=scene_geometry([(0.,0.,0.)])
    assert empty is None
    print("OK prévia 3D: 3D perspectiva 360°, postes, arames, porteira, posição clicável.")


def test_reverse_native_gate(root):
    mod,xml=mod_fixture(root)
    save=root/"placeables.xml"
    save.write_text('<placeables/>',encoding='utf-8')
    tree,records,reports,total,spec=build_fence_v08(
        points(),mod,xml,save,'GATE_10m',gate_pct=50)
    candidate=tree.getroot()[-1]
    assert len(records)>12
    gate=next(x for x in candidate.find("newFence").findall("segment")
              if x.get("id")=="GATE_10m")
    x0=float(gate.get("start").split()[0])
    x1=float(gate.get("end").split()[0])
    assert x0<x1
    old=_route(candidate)
    assert old and math.isclose(old[2][0],0,abs_tol=1e-6)
    reversed_count=invert_fence_direction(candidate)
    assert reversed_count==len(records)
    gate=next(x for x in candidate.find("newFence").findall("segment")
              if x.get("id")=="GATE_10m")
    assert float(gate.get("start").split()[0])>float(gate.get("end").split()[0])
    after=_route(candidate)
    assert after and math.isclose(after[2][0],100,abs_tol=.001)
    assert math.isclose(after[3][0],0,abs_tol=.001)
    assert math.isclose(old[1],after[1],abs_tol=.01)
    # Dá pra detectar cerca igual mesmo com direção invertida.
    old_tree,*_=build_fence_v08(points(),mod,xml,save,'GATE_10m',gate_pct=50)
    old_tree.write(save)
    flipped,*_=build_fence_v08(points(),mod,xml,save,'GATE_10m',gate_pct=50)
    last=flipped.getroot()[-1]
    invert_fence_direction(last)
    d,c=scan_overlapping_fences(flipped,last)
    assert len(d)==1 and c==[],(d,c)
    print("OK: inversão 180° muda orientation real do GATE sem desconectar a cerca.")


def test_ui_and_save(root):
    mod,xml=mod_fixture(root)
    save=root/"placeables.xml"
    save.write_text('<placeables/>',encoding="utf-8")
    app=App()
    try:
        app.update()
        assert "v1.5" in app.title()
        app.mods={mod.name:mod}
        app.fencemod.set(mod.name)
        app.fencexml.set(xml)
        app.native_gate.set("GATE_10m")
        app.gate_pct.set(50)
        app.placeables.set(str(save))
        app._preview_points=points()
        app._preview_name="Teste 3D"
        app._scene_key=None
        app._render_preview()
        assert app._scene3d is not None
        initial=app._camera_yaw
        event=type("E",(),{"x":80,"y":100,"delta":120})()
        app._start_rotate(event)
        event2=type("E",(),{"x":140,"y":110})()
        app._drag_rotate(event2)
        assert app._camera_yaw!=initial
        app._end_rotate()
        before_zoom=app._camera_zoom
        app._wheel3d(event)
        assert app._camera_zoom>before_zoom
        app._view(25,52)
        app._camera_zoom=1.
        app._render_preview()
        sc=app._scene3d
        coords=project(sc["center"],sc["center"],25,52,1,
                       (max(320,app.preview_canvas.winfo_width()),
                        max(270,app.preview_canvas.winfo_height())),58)
        event3=type("E",(),{"x":round(coords[0]),"y":round(coords[1])})()
        with patch("tkinter.messagebox.showerror",side_effect=AssertionError):
            app._click_preview(event3)
        assert abs(float(app.gate_pct.get())-50)<2
        app.invert_gate_180.set(True)
        app.dryrun.set(False)
        with patch("TG_Cerca_Editor_v09.core.load_i3d_points",
                   return_value=(points(),"Teste 3D","linear")):
            with patch("tkinter.messagebox.showinfo"):
                app.generate()
        actual=ET.parse(save).find("./placeable/newFence")
        assert actual is not None
        gates=[x for x in actual.findall("segment") if x.get("id")=="GATE_10m"]
        assert len(gates)==1
        assert float(gates[0].get("start").split()[0])>float(gates[0].get("end").split()[0])
        assert _route(ET.parse(save).find("./placeable"))
        print("OK UI: arrastar câmera, zoom, clicar no traçado, "
              "inverter porteira 180° e gravar XML real.")
        app.open_pcobjects()
        app.update()
        assert app.state()=="iconic"
        app.pc_window.close_and_restore()
        app.update()
        assert app.state()=="normal"
        print("OK PC Objects: janela principal minimiza/restaura.")
    finally:
        app.destroy()


if __name__=="__main__":
    test_scene()
    with tempfile.TemporaryDirectory() as d:
        test_reverse_native_gate(Path(d))
    with tempfile.TemporaryDirectory() as d:
        test_ui_and_save(Path(d))
    print("TESTES v1.5 APROVADOS. Preview 3D é ilustrativa; "
          "validar malha/animação no FS25.")
