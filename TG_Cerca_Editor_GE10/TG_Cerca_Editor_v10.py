"""TG + EDVALDO - Criador de Cercas e Porteiras FS25 v1.0 (I3D).

Corrige cercas onde a redução agressiva para 80 m deformava painéis/postes.
Mantém prévia por clique, animação, demolição e proteção contra duplicatas.
"""
from __future__ import annotations
from pathlib import Path
from xml.etree import ElementTree as ET
from tkinter import ttk,messagebox
import tkinter as tk
import uuid

import TG_Cerca_Editor as base
import TG_Cerca_Editor_v05 as core
from TG_Cerca_Editor_v08 import gate_interval,model_details
from TG_Cerca_Editor_v09 import App as PreviousApp
from TG_Cerca_AntiDuplicatas_v09 import (
    scan_overlapping_fences,remove_confirmed_duplicates)
from TG_Cerca_Geometria_Precisa_v10 import exact_fence_edges


def build_fence_v10(points, mod, xml, target, gate_id='', gate_pct=50.,
                    grouping=1, farm_id=1):
    """Um painel = um segmento por padrão; sem esticar trechos até 80m."""
    spec=model_details(mod,xml)
    panel=spec['panel_length']
    if gate_id and gate_id not in spec['gates']:
        raise ValueError('Essa porteira não consta no XML da cerca escolhida.')
    if not isinstance(farm_id,int) or not 0<=farm_id<=255:
        raise ValueError('Farm ID fora de 0 a 255.')
    acc=base.cumulative(points)
    total=acc[-1]
    if total<=panel:
        raise ValueError('Spline curta para este painel.')
    if gate_id:
        gate_width=spec['gates'][gate_id]
        start,center,end,total=gate_interval(points,gate_pct,gate_width,margin=panel)
        pieces=[
            (base.between(points,acc,0,start),'SEGMENT'),
            ([base.at_distance(points,acc,start),base.at_distance(points,acc,end)],gate_id),
            (base.between(points,acc,end,total),'SEGMENT')
        ]
    else:
        pieces=[(points,'SEGMENT')]
    rows=[]
    reports=[]
    for line,kind in pieces:
        if kind=='SEGMENT':
            edges,report=exact_fence_edges(line,panel,grouping=grouping)
            rows.extend((a,b,kind) for a,b in edges)
            reports.append(report)
        else:
            rows.append((line[0],line[1],kind))
    if not rows:
        raise ValueError('Nenhum painel válido encontrado.')
    tree=ET.parse(target)
    root=tree.getroot()
    if root.tag!='placeables':
        raise ValueError('O arquivo selecionado não contém raiz <placeables>.')
    obj=ET.SubElement(root,'placeable',{
        'filename':base.as_network_filename(mod,xml),
        'modName':base.modname(mod),
        'uniqueId':'placeable'+uuid.uuid4().hex,
        'position':'0.000 -151.000 0.000',
        'rotation':'0.000 0.000 0.000',
        'age':'0.000000',
        'price':'100.000000',
        'farmId':str(farm_id)
    })
    newfence=ET.SubElement(obj,'newFence')
    for start,end,kind in rows:
        ET.SubElement(newfence,'segment',{
            'start':base.pos(start),'end':base.pos(end),'id':kind})
    return tree,rows,reports,total,spec


class App(PreviousApp):
    def __init__(self):
        super().__init__()
        self.title('TG + EDVALDO | Cercas e Porteiras FS25 v1.0 - Segmentos Precisos I3D')
        frame=self.log.master
        # O campo antigo "Trecho máximo = 80m" causava o desalinhamento.
        for widget in frame.grid_slaves(row=12):
            widget.grid_remove()
        self.group_mode=tk.StringVar(value='PRECISO: 1 painel por segmento')
        ttk.Label(frame,text='Precisão dos segmentos').grid(
            row=12,column=0,sticky='w',pady=4)
        self.group_box=ttk.Combobox(frame,textvariable=self.group_mode,
            state='readonly',values=(
              'PRECISO: 1 painel por segmento',
              'EXPERIMENTAL: 2 painéis só nas retas'
            ))
        self.group_box.grid(row=12,column=1,columnspan=2,sticky='ew',pady=4)
        self.log.delete('1.0','end')
        self.log_message('v1.0: removida a redução de 80m; agora respeita os painéis reais.')
        self.log_message('Padrão PRECISO: 1 segmento XML por painel de 3,8 / 4 / 6,7 m conforme o mod.')
        self.log_message('A porteira continua na mesma spline I3D, sem mexer em animação/demolição.')
        self.log_message('Se o XML tiver cerca antiga do mesmo traçado, confirmará substituição.')

    def generate(self):
        try:
            mod=self.mods.get(self.fencemod.get())
            xml=self.fencexml.get()
            if mod is None or not xml:
                raise ValueError('Escolha o mod e o XML da cerca.')
            pts,name,curve_kind=core.load_i3d_points(Path(self.spline.get()))
            path=Path(self.placeables.get())
            if not path.is_file():
                raise ValueError('Selecione placeables.xml de uma CÓPIA do savegame.')
            gate=self.native_gate.get()
            if gate=='(sem porteira)' or not gate:
                gate=''
                if not messagebox.askyesno('Sem porteira',
                    'Nenhuma porteira selecionada. Deseja criar apenas a cerca?'):
                    return
            group=1 if self.group_mode.get().startswith('PRECISO') else 2
            tree,rows,reports,total,spec=build_fence_v10(
                pts,mod,xml,path,gate,float(self.gate_pct.get()),
                grouping=group,farm_id=int(self.farm_id.get()))
            candidate=tree.getroot()[-1]
            duplicates,conflicts=scan_overlapping_fences(tree,candidate)
            count=sum(r['count'] for r in reports)
            self.log_message(
                f'Spline {name}: {total:.1f} m, {count} painéis da cerca, '
                f'{len(rows)} linhas XML; painel {spec["panel_length"]:g} m.')
            if gate:
                self.log_message(f'Porteira {gate} com abertura {spec["gates"][gate]:g} m; '
                                 f'posição: {float(self.gate_pct.get()):.2f}%.')
            if curve_kind=='cubic':
                self.log_message('Aviso: spline cúbica aproximada; inspecione as curvas no FS25.')
            if not spec['registered']:
                self.log_message('AVISO: XML não consta em modDesc/storeItems.')
            if not spec['can_sell']:
                self.log_message('AVISO: canBeSold=false no XML.')
            if self.storeitems.get().strip():
                if ET.parse(self.storeitems.get()).getroot().tag!='storeItems':
                    raise ValueError('storeItems.xml inválido.')
            if conflicts:
                self.log_message(f'BLOQUEADO: {len(conflicts)} cercas parcialmente sobrepostas.')
                messagebox.showwarning('Cerca sobreposta',
                  'Já existem cercas parcialmente sobrepostas ou de outro modelo. '
                  'Não alterei nada. Confira o placeables.xml antes de substituir.')
                return
            if self.dryrun.get():
                self.log_message(f'MODO PRÉVIA: {len(duplicates)} cerca(s) antiga(s) '
                                 'do mesmo modelo e traçado detectada(s); sem gravação.')
                return
            if duplicates:
                if not messagebox.askyesno('Substituir cerca antiga?',
                    f'Encontradas {len(duplicates)} cerca(s) anteriores do mesmo modelo '
                    'e traçado. Quer substituí-las pela cerca de segmentos precisos?\n'
                    'Será salvo backup; outras cercas não serão removidas.'):
                    self.log_message('Cancelado; nenhuma cerca alterada.')
                    return
                remove_confirmed_duplicates(tree,candidate,duplicates)
            backup=base.backup_and_write(path,tree)
            self.log_message('Gravado com backup em '+str(backup))
            messagebox.showinfo('TG + EDVALDO',
                'Cerca registrada com segmentos precisos. Teste no FS25.')
        except Exception as exc:
            self.log_message('ERRO: '+str(exc))
            messagebox.showerror('TG + EDVALDO',str(exc))


if __name__=='__main__':
    App().mainloop()
