"""TG + EDVALDO | Criador de Cercas FS25 v0.8 — PORTEIRA POR CLIQUE.

Janela sem imagem de fundo; selecao direta de porteira nativa e posicao na spline I3D.
A previa e uma vista superior de coordenadas: NAO e renderizacao 3D da cerca.
"""
from __future__ import annotations
import math
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox
import xml.etree.ElementTree as ET

import TG_Cerca_Editor as base
import TG_Cerca_Editor_v05 as core
import TG_Cerca_Editor_v07 as engine


def closest_distance_along_path(points, px, pz):
    """Distancia percorrida no ponto mais perto de (px,pz), usando somente XZ."""
    if len(points) < 2:
        raise ValueError('Spline sem pelo menos dois pontos.')
    acc = base.cumulative(points)
    best = (float('inf'), 0.0)
    for i, (a, b) in enumerate(zip(points, points[1:])):
        dx, dz = b[0] - a[0], b[2] - a[2]
        d2 = dx*dx + dz*dz
        if d2 < 1e-12:
            continue
        t = max(0.0, min(1.0, ((px-a[0])*dx+(pz-a[2])*dz)/d2))
        x, z = a[0] + t*dx, a[2] + t*dz
        candidate = ((px-x)**2+(pz-z)**2, acc[i]+t*(acc[i+1]-acc[i]))
        if candidate[0] < best[0]:
            best = candidate
    return best[1]


def gate_interval(points, position_pct, gate_length, margin=0):
    acc = base.cumulative(points)
    total = acc[-1]
    if not (0 <= position_pct <= 100) or gate_length <= 0 or total <= 0:
        raise ValueError('Posicao ou tamanho de porteira invalido.')
    center = total * position_pct / 100
    lo, hi = center - gate_length/2, center + gate_length/2
    if lo < margin or hi > total-margin:
        raise ValueError('Porteira muito perto da extremidade. Mude o percentual.')
    return lo, center, hi, total


class App(core.App):
    def __init__(self):
        super().__init__()
        self.title('TG + EDVALDO | Criador de Cercas e Porteiras FS25 v0.8 I3D')
        self.geometry('1390x870')
        self.minsize(1130, 760)
        self.farm_id = self.gate_farm_id
        self.max_span.set(80)
        self._preview_points = None
        self._preview_file = None
        self._preview_name = ''
        self._preview_kind = ''
        self._transform = None
        self._configure_dark_style()
        frame = self.log.master
        frame.columnconfigure(3, minsize=485, weight=0)
        frame.configure(style='TFrame')

        # Os controles antigos selecionavam uma porteira EXTERNA, que nao entra
        # no newFence. Ocultamos sem destruir porque o scan original os acessa.
        for row in (4,5,6,11,19,20):
            for widget in frame.grid_slaves(row=row):
                widget.grid_remove()
        self.gatemod.set('(sem porteira)')
        self.gatexml.set('')
        self.animxml.set('')

        # Move o combobox de porteira nativa para a parte principal e deixa claro.
        ttk.Label(frame, text='PORTEIRA nativa do XML').grid(row=4,column=0,sticky='w',pady=5)
        self.native_gate_combo.grid(row=4,column=1,columnspan=2,sticky='ew',pady=5)
        ttk.Label(frame,text='Escolha GATE_5m, GATE_6m etc. do XML da cerca.').grid(
            row=5,column=0,columnspan=3,sticky='w',pady=4)
        ttk.Label(frame,text='Clique no traçado à direita para colocar a porteira.').grid(
            row=6,column=0,columnspan=3,sticky='w',pady=4)
        ttk.Button(frame,text='Atualizar a prévia da porteira',
                   command=self.show_preview).grid(row=11,column=0,columnspan=3,sticky='ew',pady=5)
        for widget in frame.grid_slaves(row=15,column=0):
            if isinstance(widget,ttk.Label):
                widget.configure(text='Farm ID da cerca e da porteira')
        # A linha 18 do modelo inicial era o botão Analisar I3D.
        for widget in frame.grid_slaves(row=18):
            if isinstance(widget,ttk.Button):
                widget.configure(text='Visualizar I3D e porteira',command=self.show_preview)

        side=tk.Frame(frame,bg='#11241f',highlightbackground='#37664e',highlightthickness=1)
        side.grid(row=0,column=3,rowspan=22,sticky='nsew',padx=(18,2),pady=6)
        tk.Label(side,text='TG + EDVALDO',font=('Segoe UI',19,'bold'),
                 fg='#8cf5ab',bg='#11241f').pack(anchor='w',padx=16,pady=(15,0))
        tk.Label(side,text='POSICIONE SUA PORTEIRA',font=('Segoe UI',11,'bold'),
                 fg='#e8f5e9',bg='#11241f').pack(anchor='w',padx=16,pady=(7,3))
        tk.Label(side,text='Vista superior (X/Z). Clique sobre a linha verde.',
                 fg='#c6dacf',bg='#11241f',font=('Segoe UI',10)).pack(anchor='w',padx=16,pady=(0,6))
        self.preview_canvas=tk.Canvas(side,width=430,height=360,
                                      bg='#071511',highlightthickness=1,
                                      highlightbackground='#3e6557',cursor='crosshair')
        self.preview_canvas.pack(fill='x',padx=16,pady=6)
        self.preview_canvas.bind('<Button-1>',self._click_preview)
        self.preview_canvas.bind('<Configure>',lambda _event: self._render_preview())
        self.preview_status=tk.Label(side,text='Selecione o I3D para visualizar o traçado.',
                          fg='#e7f6ed',bg='#11241f',wraplength=420,
                          justify='left',font=('Segoe UI',10))
        self.preview_status.pack(anchor='w',padx=16,pady=(8,12))
        tk.Label(side,text='Verde = cerca  •  Laranja = porteira',
                 fg='#c5e0ce',bg='#11241f',font=('Segoe UI',10,'bold')).pack(
                 anchor='w',padx=16,pady=(0,7))
        tk.Label(side,text='A prévia mostra a posição, não o modelo 3D.\n'
                          'Não cria outra spline e não modifica o mapa.',
                 fg='#abbeaf',bg='#11241f',font=('Segoe UI',10),
                 justify='left').pack(anchor='w',padx=16,pady=(0,12))

        # Quando muda o XML, atualizar lista de porteiras e prévia.
        self.fence_mod_box.bind('<<ComboboxSelected>>',self._changed_mod,add='+')
        self.fence_xml_box.bind('<<ComboboxSelected>>',self._chosen_fence_xml,add='+')
        self.native_gate_combo.bind('<<ComboboxSelected>>',lambda _ : self._render_preview(),add='+')
        self.gate_pct.trace_add('write',lambda *_: self._render_preview())
        self.log.configure(bg='#081a14',fg='#e7f6ec',insertbackground='white',
                           relief='flat',font=('Consolas',10))
        self.log_message('v0.8 sem imagem de fundo. PORTEIRA nativa acima, posição por clique na prévia.')
        self.log_message('Use a MESMA spline I3D, salvo se quiser mudar todo o traçado.')

    def _configure_dark_style(self):
        style=ttk.Style(self)
        if 'clam' in style.theme_names():
            style.theme_use('clam')
        style.configure('TFrame',background='#101d19')
        style.configure('TLabel',background='#101d19',foreground='#edf7ef',
                        font=('Segoe UI',10))
        style.configure('TCheckbutton',background='#101d19',foreground='#e8f6ee',
                        font=('Segoe UI',10))
        style.map('TCheckbutton',background=[('active','#192c22')])
        style.configure('TButton',background='#236548',foreground='white',
                        padding=(12,7),font=('Segoe UI',10,'bold'))
        style.map('TButton',background=[('active','#38805c')])
        style.configure('TCombobox',fieldbackground='#f5faf6',foreground='#102d21')
        style.configure('TSpinbox',fieldbackground='#f5faf6',foreground='#102d21')
        style.configure('TEntry',fieldbackground='#f5faf6',foreground='#102d21')
        self.option_add('*TCombobox*Listbox.background','#eaf4ec')

    def _changed_mod(self,_=None):
        self.native_gate.set('(sem porteira)')
        self._render_preview()

    def update_fence(self, _=None):
        mod = self.mods.get(self.fencemod.get())
        self.fencexml.set('')
        self.native_gate.set('(sem porteira)')
        options=[]
        if mod is not None:
            try:
                for xml in base.xml_files(mod):
                    try:
                        root=ET.fromstring(base.read_mod_file(mod,xml))
                        if root.tag=='placeable' and root.get('type')=='newFence' and \
                           root.find("./fence/segment[@id='SEGMENT']") is not None:
                            options.append(xml)
                    except (OSError,KeyError,ValueError,ET.ParseError):
                        pass
            except Exception as exc:
                self.log_message('Erro ao verificar mod: '+str(exc))
        self.fence_xml_box['values']=options
        self.log_message(f'{len(options)} cercas nativas disponíveis nesse mod.')

    def _chosen_fence_xml(self,_=None):
        # Carrega o GATE_* e outros IDs declarados no XML selecionado.
        core.App.on_fence_xml(self)
        mod=self.mods.get(self.fencemod.get())
        path=self.fencexml.get()
        if mod is not None and path:
            try:
                length,gates=core.fence_spec(mod,path)
                if gates:
                    self.native_gate.set(next(iter(gates)))
                    self.log_message('Porteira selecionada: '+self.native_gate.get()+
                                     f' (painéis da cerca: {length:g} m)')
                else:
                    self.log_message('Esse XML não possui porteira nativa.')
            except Exception as exc:
                self.log_message('Porteira: '+str(exc))
        self._render_preview()

    def choose_i3d(self):
        super().choose_i3d()
        if Path(self.spline.get()).is_file():
            self.show_preview(silent=True)

    def show_preview(self,silent=False):
        try:
            filename=Path(self.spline.get())
            pts,name,kind=core.load_i3d_points(filename)
            self._preview_file=str(filename.resolve())
            self._preview_points=pts
            self._preview_name=name
            self._preview_kind=kind
            self.log_message(f'I3D {name}: {len(pts)} amostras; '
                             f'{base.cumulative(pts)[-1]:.1f} metros.')
            self._render_preview()
        except Exception as exc:
            if not silent:
                self.log_message('Prévia: '+str(exc))
                messagebox.showerror('TG + EDVALDO','Não consegui visualizar I3D: '+str(exc))

    def _gate_width(self):
        mod=self.mods.get(self.fencemod.get())
        xml=self.fencexml.get()
        chosen=self.native_gate.get()
        if mod is None or not xml or chosen=='(sem porteira)' or not chosen:
            return None,None
        length,gates=core.fence_spec(mod,xml)
        return gates.get(chosen),length

    def _render_preview(self):
        if not hasattr(self,'preview_canvas'):
            return
        c=self.preview_canvas
        c.delete('all')
        width=max(320,c.winfo_width())
        height=max(260,c.winfo_height())
        points=self._preview_points
        if not points or len(points)<2:
            c.create_text(width/2,height/2,text='Selecione a spline I3D\npara visualizar a porteira',
                          fill='#d3e8da',font=('Segoe UI',12),justify='center')
            return
        xx=[p[0] for p in points]
        zz=[p[2] for p in points]
        x0,x1=min(xx),max(xx)
        z0,z1=min(zz),max(zz)
        pad=28
        scale=min((width-2*pad)/max(x1-x0,1),
                  (height-2*pad)/max(z1-z0,1))
        # Centraliza o traçado mesmo se ele for quase horizontal ou vertical.
        ox=(width-(x1-x0)*scale)/2
        oz=(height-(z1-z0)*scale)/2
        def to_screen(p):
            return (ox+(p[0]-x0)*scale,oz+(p[2]-z0)*scale)
        self._transform=(x0,z0,ox,oz,scale)
        coords=[]
        for p in points:
            coords.extend(to_screen(p))
        c.create_line(*coords,fill='#50d58c',width=3,smooth=False)
        c.create_oval(coords[0]-4,coords[1]-4,coords[0]+4,coords[1]+4,
                      fill='#90ffa8',outline='')
        c.create_text(coords[0]+8,coords[1]-10,text='INÍCIO',anchor='w',
                      fill='#b9fbd0',font=('Segoe UI',9,'bold'))
        c.create_oval(coords[-2]-4,coords[-1]-4,coords[-2]+4,coords[-1]+4,
                      fill='#90ffa8',outline='')
        c.create_text(coords[-2]+7,coords[-1]-10,text='FIM',anchor='w',
                      fill='#b9fbd0',font=('Segoe UI',9,'bold'))
        total=base.cumulative(points)[-1]
        try:
            gate_width,panel_length=self._gate_width()
            percent=float(self.gate_pct.get())
            if gate_width is None:
                self.preview_status.config(text=f'I3D: {self._preview_name} • {total:.1f} m\n'
                                   'Escolha uma porteira nativa no campo à esquerda.')
                return
            lo,center,hi,total=gate_interval(points,percent,gate_width,
                                               margin=panel_length)
            acc=base.cumulative(points)
            gate_pts=base.between(points,acc,lo,hi)
            gate_coords=[]
            for p in gate_pts:
                gate_coords.extend(to_screen(p))
            c.create_line(*gate_coords,fill='#101b17',width=9)
            c.create_line(*gate_coords,fill='#ffb252',width=5)
            for d in (lo,hi):
                sx,sy=to_screen(base.at_distance(points,acc,d))
                c.create_oval(sx-5,sy-5,sx+5,sy+5,fill='#ffcf82',outline='#1b211c')
            sx,sy=to_screen(base.at_distance(points,acc,center))
            c.create_text(sx,sy-15,text='PORTEIRA',fill='#ffd189',
                          font=('Segoe UI',9,'bold'))
            self.preview_status.config(
                text=f'{self._preview_name}: {total:.1f} m de spline\n'
                     f'Porteira {self.native_gate.get()}: {gate_width:g} m, '
                     f'a {center:.1f} m do início ({percent:.1f}%).\n'
                     'Clique no traçado para mudar a posição.')
        except Exception as exc:
            self.preview_status.config(text='Não foi possível posicionar a porteira: '+str(exc))

    def _click_preview(self,event):
        if not self._preview_points or self._transform is None:
            return
        try:
            width,panel = self._gate_width()
            if width is None:
                raise ValueError('Selecione uma porteira no campo "Porteira nativa do XML".')
            x0,z0,ox,oz,scale=self._transform
            world_x=x0+(event.x-ox)/scale
            world_z=z0+(event.y-oz)/scale
            total=base.cumulative(self._preview_points)[-1]
            offset=closest_distance_along_path(self._preview_points,world_x,world_z)
            minimum=panel+width/2
            if total < 2*minimum:
                raise ValueError('A spline é curta para esta porteira e os painéis laterais.')
            offset=max(minimum,min(total-minimum,offset))
            self.gate_pct.set(round(offset/total*100,2))
            self.log_message(f'Porteira posicionada a {offset:.1f} metros do início '
                             f'({self.gate_pct.get():.2f}%).')
            self._render_preview()
        except Exception as exc:
            self.log_message('Prévia porteira: '+str(exc))
            messagebox.showerror('TG + EDVALDO',str(exc))

    def generate(self):
        if not self.fencexml.get():
            messagebox.showerror('TG + EDVALDO','Escolha o XML da cerca primeiro.')
            return
        if self.native_gate.get() == '(sem porteira)':
            self.log_message('Atenção: nenhuma porteira selecionada; gerar criaria somente a cerca.')
            if not messagebox.askyesno('Sem porteira',
                    'Nenhuma porteira foi escolhida. Quer gerar somente a cerca?'):
                return
        if self._preview_file!=str(Path(self.spline.get()).resolve()):
            self.show_preview(silent=True)
        # Mesma lógica validada de geração e backup da versão 0.7.
        return engine.App.generate(self)


if __name__=='__main__':
    App().mainloop()
