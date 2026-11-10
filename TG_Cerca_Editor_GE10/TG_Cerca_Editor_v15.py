"""TG + EDVALDO v1.5 — prévia 3D interativa na área direita.

Cerca e porteira em 3D esquemático, câmera orbital e zoom, posição por clique,
inversão real 180° do sentido da cerca/porteira no XML nativo (endpoints).
As malhas binárias do mod .i3d.shapes NÃO são decodificadas neste programa.
"""
from __future__ import annotations
import math
from pathlib import Path
import tkinter as tk
from tkinter import messagebox,ttk

import TG_Cerca_Editor as base
from TG_Cerca_Editor_v08 import gate_interval
from TG_Cerca_Editor_v143 import App as PreviousApp
from TG_Cerca_Geometria_Nativa_v142 import gate_span, segment_profile
import TG_Cerca_Preview3D_v15 as viewer


class App(PreviousApp):
    def __init__(self):
        # A janela herdada chama _render_preview já durante __init__.
        self._camera_yaw=25.
        self._camera_pitch=52.
        self._camera_zoom=1.
        self._drag3d=None
        self._scene3d=None
        self._scene_key=None
        self._gate_cache_key=None
        self._gate_cache_value=(None,4.)
        super().__init__()
        self.title("TG + EDVALDO | Cercas, Porteiras e PC Objects FS25 v1.5 — Prévia 3D")
        side=self.preview_canvas.master
        self.preview_canvas.configure(height=380,bg="#081811",cursor="crosshair")
        self.preview_canvas.unbind("<Button-1>")
        self.preview_canvas.bind("<Button-1>",self._click_preview)
        self.preview_canvas.bind("<ButtonPress-3>",self._start_rotate)
        self.preview_canvas.bind("<B3-Motion>",self._drag_rotate)
        self.preview_canvas.bind("<ButtonRelease-3>",self._end_rotate)
        self.preview_canvas.bind("<MouseWheel>",self._wheel3d)
        self.preview_canvas.bind("<Button-4>",lambda e:self._zoom_by(1.13))
        self.preview_canvas.bind("<Button-5>",lambda e:self._zoom_by(1/1.13))
        for child in side.winfo_children():
            if not isinstance(child,tk.Label):
                continue
            txt=child.cget("text")
            if txt.startswith("POSICIONE SUA PORTEIRA"):
                child.configure(text="VISUALIZE SUA CERCA E PORTEIRA EM 3D")
            elif txt.startswith("Vista superior"):
                child.configure(text="Visualização 3D aproximada. "
                                "Arraste com o botão direito para girar.")
            elif "A prévia mostra a posição, não o modelo 3D" in txt:
                child.configure(text="A imagem 3D é ilustrativa; os modelos do mod "
                                "têm geometria e animação próprias no FS25.\n"
                                "Sem alterações no mapa até clicar GERAR XML.")
            elif txt.startswith("Verde = cerca"):
                child.configure(text="Postes e arames = cerca  •  Madeira = porteira")
        controls=tk.Frame(side,bg="#11241f")
        controls.pack(before=self.preview_status,fill="x",padx=16,pady=(1,5))
        tk.Button(controls,text="Frente",command=lambda:self._view(25,52),
                  bg="#236548",fg="white",font=("Segoe UI",9,"bold"),
                  relief="flat").pack(side="left",padx=(0,3))
        tk.Button(controls,text="Cima",command=lambda:self._view(0,84),
                  bg="#236548",fg="white",font=("Segoe UI",9,"bold"),
                  relief="flat").pack(side="left",padx=3)
        tk.Button(controls,text="↶ 45°",command=lambda:self._view(self._camera_yaw-45,self._camera_pitch),
                  bg="#236548",fg="white",font=("Segoe UI",9,"bold"),
                  relief="flat").pack(side="left",padx=3)
        tk.Button(controls,text="↷ 45°",command=lambda:self._view(self._camera_yaw+45,self._camera_pitch),
                  bg="#236548",fg="white",font=("Segoe UI",9,"bold"),
                  relief="flat").pack(side="left",padx=3)
        tk.Button(controls,text="+",command=lambda:self._zoom_by(1.18),
                  bg="#236548",fg="white",font=("Segoe UI",9,"bold"),
                  relief="flat",width=3).pack(side="left",padx=3)
        tk.Button(controls,text="−",command=lambda:self._zoom_by(1/1.18),
                  bg="#236548",fg="white",font=("Segoe UI",9,"bold"),
                  relief="flat",width=3).pack(side="left",padx=3)
        self.invert_gate_180=tk.BooleanVar(value=False)
        tk.Checkbutton(side,text="Inverter sentido 180° (porteira e cerca no XML)",
                       variable=self.invert_gate_180,command=self._render_preview,
                       font=("Segoe UI",10,"bold"),fg="#ffcf8b",bg="#11241f",
                       selectcolor="#233c2d",activebackground="#11241f",
                       activeforeground="#ffcf8b").pack(
                           before=self.preview_status,anchor="w",padx=16,pady=(0,2))
        self.log_message("v1.5: prévia em perspectiva 3D de postes, arames, "
                         "porteira e posição do traçado.")
        self.log_message("Botão direito: gira câmera 360° | roda: zoom | "
                         "clique: posição da porteira.")
        self.log_message("Inverter sentido 180° muda a direção do newFence "
                         "no XML, inclusive os painéis, para preservar conexões.")
        self.log_message("A prévia NÃO importa as malhas .i3d.shapes: "
                         "modelo 3D ilustrativo, não renderizador GIANTS.")
        self._render_preview()

    def _gate_width(self):
        # Reaproveitar cache: a prévia pode ser desenhada dezenas de vezes
        # durante o arraste da câmera; não abrir ZIP em cada movimento.
        mod=self.mods.get(self.fencemod.get())
        xml=self.fencexml.get()
        gate=self.native_gate.get()
        key=(str(mod) if mod is not None else None,xml,gate)
        if key==self._gate_cache_key:
            return self._gate_cache_value
        self._gate_cache_key=key
        if mod is None or not xml or not gate or gate=="(sem porteira)":
            self._gate_cache_value=(None,4.)
        else:
            try:
                width,_=gate_span(Path(mod),xml,gate)
                panel,scale,_=segment_profile(Path(mod),xml)
                self._gate_cache_value=(width,panel)
            except Exception:
                self._gate_cache_value=(None,4.)
        return self._gate_cache_value

    def _view(self,yaw,pitch):
        self._camera_yaw=float(yaw)%360.
        self._camera_pitch=max(15.,min(86.,float(pitch)))
        self._render_preview()

    def _zoom_by(self,factor):
        self._camera_zoom=max(.55,min(4.0,self._camera_zoom*factor))
        self._render_preview()

    def _wheel3d(self,event):
        self._zoom_by(1.12 if event.delta>0 else 1/1.12)

    def _start_rotate(self,event):
        self._drag3d=(event.x,event.y,self._camera_yaw,self._camera_pitch)

    def _drag_rotate(self,event):
        if self._drag3d:
            x,y,yaw,pitch=self._drag3d
            self._view(yaw+(event.x-x)*.65,pitch+(event.y-y)*.34)

    def _end_rotate(self,event=None):
        self._drag3d=None

    def _render_preview(self):
        if not hasattr(self,"preview_canvas"):
            return
        # Se nem todos os widgets do construtor herdado existem ainda,
        # desenhar só a mensagem inicial da classe Scene3D.
        pts=getattr(self,"_preview_points",None)
        if not pts or len(pts)<2:
            self._scene3d=None
            viewer.draw_scene(self.preview_canvas,None,self._camera_yaw,
                              self._camera_pitch,self._camera_zoom)
            return
        try:
            width,panel=self._gate_width()
            percent=float(self.gate_pct.get())
            key=(id(pts),round(percent,5),width,panel)
            if key!=self._scene_key:
                self._scene3d=viewer.scene_geometry(
                    pts,center_percent=percent,gate_width=width,
                    panel=panel,window=58.)
                self._scene_key=key
            flip=bool(getattr(self,"invert_gate_180",None) and
                      self.invert_gate_180.get())
            viewer.draw_scene(self.preview_canvas,self._scene3d,
                              self._camera_yaw,self._camera_pitch,
                              self._camera_zoom,flipped=flip)
            if not hasattr(self,"preview_status"):
                return
            scene=self._scene3d
            x,y,z=scene["center"]
            txt=(f'Localização no MAPA (spline): '
                 f'X {x:.2f}  Y {y:.2f}  Z {z:.2f}\n'
                 f'Traçado: {scene["total"]:.1f} m. '
                 f'Porteira: {width:.2f} m.' if width is not None else
                 f'Localização X {x:.2f}, Y {y:.2f}, Z {z:.2f}\n'
                 'Selecione uma porteira nativa no XML à esquerda.')
            if width is not None:
                txt+=("\nOrientação da porteira: invertida 180°." if flip else
                      "\nOrientação da porteira: segue a spline.")
            if scene["warning"]:
                txt+="\nATENÇÃO: "+scene["warning"]
            self.preview_status.configure(text=txt)
        except Exception as exc:
            viewer.draw_scene(self.preview_canvas,None,self._camera_yaw,
                              self._camera_pitch,self._camera_zoom)
            if hasattr(self,"preview_status"):
                self.preview_status.configure(text="Erro na prévia 3D: "+str(exc))

    def _click_preview(self,event):
        if not self._scene3d or not self._preview_points:
            return
        try:
            width,panel=self._gate_width()
            if width is None:
                raise ValueError("Selecione uma porteira nativa no XML da cerca.")
            canvas=self.preview_canvas
            arc,screen_gap=viewer.nearest_position(
                self._scene3d,self._scene3d["center"],
                self._camera_yaw,self._camera_pitch,self._camera_zoom,
                max(320,canvas.winfo_width()),max(270,canvas.winfo_height()),
                event.x,event.y)
            if arc is None or screen_gap>22.:
                return
            total=self._scene3d["total"]
            margin=panel+width/2.
            if total<2*margin:
                raise ValueError("Spline curta para esta porteira e seus painéis.")
            arc=max(margin,min(total-margin,arc))
            self.gate_pct.set(round(arc/total*100.,3))
            self.log_message(f"Porteira selecionada em 3D: {arc:.2f}m "
                             f"({float(self.gate_pct.get()):.3f}%).")
            self._render_preview()
        except Exception as exc:
            self.log_message("Prévia 3D: "+str(exc))
            messagebox.showerror("TG + EDVALDO",str(exc))


if __name__=="__main__":
    App().mainloop()
