"""TOP GAMERS Cercas FS25 v0.3 beta - compilar junto com TG_Cerca_Editor.py."""
from __future__ import annotations
import math
from pathlib import Path
import xml.etree.ElementTree as ET
import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from tg_i3d import scene_splines, resample_polyline
import uuid
import TG_Cerca_Editor as old

def load_i3d_points(path: Path):
    """Lê somente uma spline I3D exportada. Curvas cúbicas são aproximadas."""
    path = Path(path)
    if path.suffix.lower() != '.i3d' or not path.is_file():
        raise ValueError('Selecione um arquivo .i3d válido, não CSV.')
    candidates = scene_splines(path)
    if len(candidates) != 1:
        raise ValueError('Exporte uma única spline para o arquivo I3D.')
    name, controls, kind = candidates[0]
    pts = resample_polyline(controls, spacing=1.0)
    if len(pts) < 2:
        raise ValueError('Spline I3D sem pontos suficientes.')
    return pts, name, kind

def fence_spec(mod: Path, xml_path: str):
    root = old.check_mod_xml(mod, xml_path, 'fence')
    segment = root.find("./fence/segment[@id='SEGMENT']")
    if segment is None:
        raise ValueError('O XML não define o segmento padrão SEGMENT.')
    panel = segment.find('./panels/panel')
    pole = segment.find('./poles/pole')
    if panel is None or not panel.get('node') or not panel.get('length'):
        raise ValueError('Falta <fence><segment><panels><panel node=... length=...> no XML.')
    if pole is None or not pole.get('node'):
        raise ValueError('Falta <fence><segment><poles><pole node=...> no XML.')
    length = float(panel.get('length'))
    if not 0.5 <= length <= 30 or not math.isfinite(length):
        raise ValueError('Comprimento do painel inválido.')
    mappings = {el.get('id') for el in root.findall('./i3dMappings/i3dMapping')}
    if panel.get('node') not in mappings or pole.get('node') not in mappings:
        raise ValueError('IDs do painel/poste não encontrados em i3dMappings.')
    gates = {}
    for s in root.findall('./fence/segment'):
        gate = s.find('gate')
        if gate is not None and s.get('id') and s.get('class') == 'FenceGate':
            try:
                gl = float(gate.get('length', '0'))
            except ValueError:
                continue
            if 0.5 <= gl <= 30 and math.isfinite(gl):
                gates[s.get('id')] = gl
    return length, gates

def sample_fence(points, step):
    acc = old.cumulative(points)
    total = acc[-1]
    if total < 0.1:
        return []
    n = max(1, math.ceil(total / step))
    return [old.at_distance(points, acc, total*i/n) for i in range(n+1)]

def create_fence_v03(pts, fence_mod, fence_xml, target,
                     native_gate_id='', gate_pct=50, panel_max_length=25,
                     tolerance_xy=0.35, tolerance_y=0.18):
    """Gera cercas no XML do save, preserva os ZIPs dos mods."""
    panel_length, gates = fence_spec(fence_mod, fence_xml)
    if native_gate_id and native_gate_id not in gates:
        raise ValueError('Porteira nativa não encontrada no XML desta cerca.')
    if not panel_max_length >= panel_length:
        raise ValueError(f'O painel deste mod mede {panel_length:g} m; aumente o trecho máximo.')
    tree = ET.parse(target)
    root = tree.getroot()
    if root.tag != 'placeables':
        raise ValueError('Destino deve ter raiz XML <placeables>.')
    acc = old.cumulative(pts)
    total = acc[-1]
    if total < 0.1:
        raise ValueError('Spline sem comprimento suficiente.')
    if not 0 <= gate_pct <= 100:
        raise ValueError('Posição de porteira fora dos 0-100%.')
    if native_gate_id:
        width = gates[native_gate_id]
        center = total * gate_pct / 100
        start, end = center-width/2, center+width/2
        if start < 0.1 or end > total-0.1:
            raise ValueError('Porteira não cabe nesta posição da spline.')
        pieces = [(old.between(pts, acc, 0, start), 'SEGMENT'),
                  ([old.at_distance(pts, acc, start), old.at_distance(pts, acc, end)], native_gate_id),
                  (old.between(pts, acc, end, total), 'SEGMENT')]
    else:
        pieces = [(pts, 'SEGMENT')]
    records = []
    for coordinates, segment_id in pieces:
        if segment_id == 'SEGMENT':
            if len(coordinates) < 2:
                continue
            simplified = old.reduce_polyline(coordinates, tolerance_xy,
                                              tolerance_y, max_segment=panel_length)
            sampled = sample_fence(simplified, panel_length)
            for a,b in zip(sampled, sampled[1:]):
                records.append((a,b,segment_id))
        else:
            records.append((coordinates[0], coordinates[1], segment_id))
    if not records:
        raise ValueError('Nenhum painel gerado.')
    fence = ET.SubElement(root, 'placeable', {
        'filename':old.as_network_filename(fence_mod,fence_xml),
        'modName':old.modname(fence_mod),
        'uniqueId':'placeable'+uuid.uuid4().hex,
        'position':'0.000 -151.000 0.000',
        'rotation':'0.000 0.000 0.000',
        'age':'0.000000',
        'price':'100.000000',
        'farmId':'0'})
    nf = ET.SubElement(fence, 'newFence')
    for a,b,segment_id in records:
        ET.SubElement(nf,'segment',{'start':old.pos(a),'end':old.pos(b),'id':segment_id})
    return tree, len(records), total, panel_length

class App(old.App):
    def __init__(self):
        super().__init__()
        self.title('TOP GAMERS - Criador de Cercas FS25 v0.4 I3D BETA')
        self.geometry('940x850')
        panel = self.log.master
        for widget in panel.grid_slaves(row=7):
            widget.destroy()
        self.spline.set('')
        ttk.Label(panel, text='Spline exportada (.i3d)').grid(row=7, column=0, sticky='w')
        ttk.Entry(panel, textvariable=self.spline).grid(row=7, column=1, sticky='ew')
        ttk.Button(panel, text='Selecionar I3D', command=self.choose_i3d).grid(row=7, column=2, padx=4)
        frame = self.log.master
        frame.rowconfigure(18, weight=0)
        frame.rowconfigure(21, weight=1)
        self.log.grid_configure(row=21)
        self.native_gate = tk.StringVar(value='(sem porteira)')
        ttk.Label(frame,text='Porteira nativa do XML').grid(row=19,column=0,sticky='w')
        self.native_gate_combo = ttk.Combobox(frame,textvariable=self.native_gate,state='readonly')
        self.native_gate_combo.grid(row=19,column=1,columnspan=2,sticky='ew')
        self.native_gate_combo['values']=['(sem porteira)']
        ttk.Label(frame,text='Painéis do tamanho do mod; demolição depende da propriedade do terreno.').grid(
            row=20,column=0,columnspan=3,sticky='w')
        self.fence_xml_box.bind('<<ComboboxSelected>>',self.on_fence_xml)
        ttk.Button(frame,text='Analisar I3D',command=self.analyze_i3d).grid(
            row=18,column=0,columnspan=3,sticky='ew')
        self.log_message('Selecione um I3D com o .i3d.shapes na mesma pasta.')

    def choose_i3d(self):
        value = filedialog.askopenfilename(title='Spline exportada do GIANTS Editor',
            filetypes=[('GIANTS Editor I3D','*.i3d')])
        if value:
            self.spline.set(value)

    def analyze_i3d(self):
        try:
            pts,name,kind=load_i3d_points(Path(self.spline.get()))
            self.log_message(f'I3D OK: {name}, {old.cumulative(pts)[-1]:.1f} metros, tipo {kind}.')
            if kind=='cubic':
                self.log_message('Aviso: curva cúbica aproximada; confira no jogo.')
        except Exception as exc:
            self.log_message('ERRO I3D: '+str(exc))
            messagebox.showerror('TOP GAMERS I3D',str(exc))

    def on_fence_xml(self,_event=None):
        try:
            fm=self.mods[self.fencemod.get()]
            length,gates=fence_spec(fm,self.fencexml.get())
            self.native_gate_combo['values']=['(sem porteira)']+list(gates)
            self.native_gate.set('(sem porteira)')
            self.max_span.set(max(self.max_span.get(),math.ceil(length)))
            self.log_message(f'Mod: painel {length:g} m; porteiras: {", ".join(gates) or "nenhuma"}.')
        except Exception as exc:
            self.log_message('ERRO XML DA CERCA: '+str(exc))
            self.native_gate_combo['values']=['(sem porteira)']
            self.native_gate.set('(sem porteira)')

    def generate(self):
        try:
            fm=self.mods[self.fencemod.get()]
            fence_xml=self.fencexml.get()
            pts,spline_name,spline_kind=load_i3d_points(Path(self.spline.get()))
            target=Path(self.placeables.get())
            if not target.is_file():
                raise ValueError('Selecione o placeables.xml de um savegame de TESTE.')
            native=self.native_gate.get()
            if native=='(sem porteira)':
                native=''
            if self.gatemod.get() not in ('','(sem porteira)'):
                raise ValueError('Use a porteira integrada ao XML; desmarque o mod externo.')
            tree,count,total,panel=create_fence_v03(
                pts,fm,fence_xml,target,native,self.gate_pct.get(),
                self.max_span.get(),self.tolerance_xy.get(),self.tolerance_y.get())
            self.log_message(f'I3D {spline_name}: {count} segmentos para {total:.1f} m; painel {panel:g} m.')
            if spline_kind=='cubic':
                self.log_message('AVISO: spline cúbica aproximada pelos pontos de controle.')
            if native:
                self.log_message(f'Porteira: {native}; animação interna do próprio XML.')
            if not old.registered_in_mod(fm,fence_xml):
                self.log_message('AVISO: este XML não consta em storeItems do modDesc.')
            if self.storeitems.get().strip():
                if ET.parse(self.storeitems.get()).getroot().tag!='storeItems':
                    raise ValueError('storeItems.xml inválido.')
                self.log_message('storeItems.xml conferido, não alterado.')
            self.log_message('Demolição: testar na fazenda dona do terreno; farmId não garante venda.')
            if self.dryrun.get():
                self.log_message('MODO PRÉVIA: nenhum arquivo alterado.')
                return
            backup=old.backup_and_write(target,tree)
            self.log_message(f'Gravado: {target} | Backup: {backup}')
            messagebox.showinfo('TOP GAMERS','XML gravado. Teste no FS25 e confira o log.txt.')
        except Exception as exc:
            self.log_message('ERRO: '+str(exc))
            messagebox.showerror('TOP GAMERS',str(exc))

if __name__=='__main__':
    App().mainloop()
