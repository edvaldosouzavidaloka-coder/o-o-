"""TG + EDVALDO | Criador de Cercas FS25 v0.7 — I3D, fundo fixo.

Versao BETA. Testar num savegame copia antes de usar no mapa principal.
"""
from __future__ import annotations
import math
import uuid
from pathlib import Path
import xml.etree.ElementTree as ET
from tkinter import messagebox

import TG_Cerca_Editor as base
import TG_Cerca_Editor_v06 as previous
import TG_Cerca_Editor_v05 as core
from TG_Cerca_Geometria_v07 import aligned_segments


def build_fence_v07(points, fence_mod, fence_xml, target,
                    native_gate_id='', gate_pct=50.0, max_span=80.0,
                    tolerance_xy=0.35, tolerance_y=0.18, farm_id=0):
    """Gera uma entrada newFence com trecho alinhado a multiplos de paineis.

    O jogo FS25 continua sendo responsavel pelos postes e arames.
    """
    spec = previous.model_details(fence_mod,fence_xml)
    panel_length = spec['panel_length']
    if native_gate_id and native_gate_id not in spec['gates']:
        raise ValueError('A porteira escolhida nao existe neste XML.')
    if not isinstance(farm_id,int) or not 0 <= farm_id <= 255:
        raise ValueError('farmId deve ser um inteiro entre 0 e 255.')
    if not (0 <= gate_pct <= 100):
        raise ValueError('Posicao da porteira deve ser de 0 a 100%.')
    tree = ET.parse(target)
    root = tree.getroot()
    if root.tag != 'placeables':
        raise ValueError('O XML de destino precisa de raiz <placeables>.')
    distances = base.cumulative(points)
    total = distances[-1]
    if total <= panel_length:
        raise ValueError('Spline curta demais para este modelo de cerca.')
    if native_gate_id:
        opening = spec['gates'][native_gate_id]
        center = total * gate_pct / 100
        lo,hi = center-opening/2,center+opening/2
        if lo < panel_length or hi > total-panel_length:
            raise ValueError('Falta espaco para paineis dos dois lados da porteira.')
        pieces = [
            (base.between(points,distances,0,lo),'SEGMENT'),
            ([base.at_distance(points,distances,lo),
              base.at_distance(points,distances,hi)],native_gate_id),
            (base.between(points,distances,hi,total),'SEGMENT')
        ]
    else:
        pieces = [(points,'SEGMENT')]
    outputs = []
    reports = []
    for part,template_id in pieces:
        if template_id == 'SEGMENT':
            edges,report = aligned_segments(
                part,panel_length,max_span,tolerance_xy,tolerance_y)
            reports.append(report)
            for p0,p1 in edges:
                outputs.append((p0,p1,template_id))
        else:
            outputs.append((part[0],part[1],template_id))
    if not outputs:
        raise ValueError('Nao foram encontrados segmentos validos.')
    fence = ET.SubElement(root,'placeable',{
        'filename':base.as_network_filename(fence_mod,fence_xml),
        'modName':base.modname(fence_mod),
        'uniqueId':'placeable'+uuid.uuid4().hex,
        'position':'0.000 -151.000 0.000',
        'rotation':'0.000 0.000 0.000',
        'age':'0.000000',
        'price':'100.000000',
        'farmId':str(farm_id),
    })
    newfence=ET.SubElement(fence,'newFence')
    for p0,p1,template_id in outputs:
        ET.SubElement(newfence,'segment',{
            'start':base.pos(p0),
            'end':base.pos(p1),
            'id':template_id,
        })
    return tree, outputs, reports, total, spec


class App(previous.App):
    def __init__(self):
        super().__init__()
        self.title('TG + EDVALDO | Criador de Cercas FS25 v0.7 I3D')
        frame=self.log.master
        # Retira permanentemente as opcoes para escolher ou trocar a foto.
        for row in (14,15):
            for widget in frame.grid_slaves(row=row,column=3):
                widget.destroy()
        for widget in frame.grid_slaves(row=1,column=3):
            if hasattr(widget,'configure'):
                widget.configure(text='CRIADOR DE CERCAS FS25\nVERSAO 0.7 • I3D')
        self.max_span.set(80.0)
        self.log_message('Foto fixa no fundo (sem botao de troca).')
        self.log_message('Espacamento melhorado: junta trechos retos e distribui segmentos por paineis inteiros.')
        self.log_message('Trecho maximo no XML = 80 m. O intervalo entre postes vem do mod.')

    def _choose_background(self):
        # Sem seletor de imagem nesta versao.
        return

    def generate(self):
        try:
            fence_mod=self.mods.get(self.fencemod.get())
            fence_xml=self.fencexml.get()
            if fence_mod is None or not fence_xml:
                raise ValueError('Selecione um mod e seu XML de cerca.')
            pts,spline_name,kind=core.load_i3d_points(Path(self.spline.get()))
            target=Path(self.placeables.get())
            if not target.is_file():
                raise ValueError('Selecione placeables.xml de uma COPIA do savegame.')
            native=self.native_gate.get()
            if native=='(sem porteira)':
                native=''
            if self.gatemod.get() not in ('','(sem porteira)'):
                raise ValueError('Selecione somente uma porteira nativa do mesmo XML.')
            farm_id=int(self.farm_id.get())
            tree,segments,reports,total,spec=build_fence_v07(
                pts,fence_mod,fence_xml,target,native,self.gate_pct.get(),
                self.max_span.get(),self.tolerance_xy.get(),self.tolerance_y.get(),
                farm_id)
            self.log_message(
                f'I3D {spline_name}: {total:.1f} m, {len(segments)} segmentos no XML, '
                f'painel nominal {spec["panel_length"]:g} m, limite de trecho {self.max_span.get():g} m.')
            if reports:
                mini=min(x['panel_step_min'] for x in reports)
                maxi=max(x['panel_step_max'] for x in reports)
                self.log_message(f'Passo estimado entre postes por reta: {mini:.2f}–{maxi:.2f} m.')
                short=sum(x['short_edges'] for x in reports)
                if short:
                    self.log_message(
                        f'ATENCAO: {short} trechos curtos em curvas/desnivel; '
                        'podem manter postes proximos. Ajuste a spline no GE.')
            if kind=='cubic':
                self.log_message('AVISO: spline cubica aproximada; confira no jogo.')
            if not spec['registered']:
                self.log_message('AVISO: XML de cerca nao registrado no modDesc.')
            if not spec['can_sell']:
                self.log_message('AVISO: canBeSold=false no XML da cerca.')
            if self.storeitems.get().strip():
                if ET.parse(self.storeitems.get()).getroot().tag!='storeItems':
                    raise ValueError('storeItems.xml invalido.')
                self.log_message('storeItems.xml validado sem alteracoes.')
            self.log_message('Demolicao exige terreno da fazenda e suporte de painel do FS25.')
            if self.dryrun.get():
                self.log_message('MODO PREVIA: nenhum XML foi alterado.')
                return
            backup=base.backup_and_write(target,tree)
            self.log_message('SALVO: '+str(target)+'; backup: '+str(backup))
            messagebox.showinfo('TG + EDVALDO',
                'Cerca registrada no XML com backup. Confira postes e demolicao no FS25.')
        except Exception as exc:
            self.log_message('ERRO: '+str(exc))
            messagebox.showerror('TG + EDVALDO',str(exc))

if __name__=='__main__':
    App().mainloop()
