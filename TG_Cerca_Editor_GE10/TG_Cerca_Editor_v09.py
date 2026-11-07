"""TG + EDVALDO | Criador de Cercas e Porteiras FS25 v0.9.

Mantem a tela sem foto e a posicao de porteira por clique da v0.8.
Antes de gravar, identifica cercas no mesmo caminho e oferece substituicao
somente apos confirmacao. Nunca apaga automatico outros modelos do mapa.
"""
from pathlib import Path
import tkinter as tk
from tkinter import messagebox
from xml.etree import ElementTree as ET

from TG_Cerca_Editor_v08 import App as PreviousApp
from TG_Cerca_Segmentos_Originais_v091 import build_fence_v08
from TG_Cerca_AntiDuplicatas_v09 import (
    scan_overlapping_fences, remove_confirmed_duplicates)
import TG_Cerca_Editor_v05 as core
import TG_Cerca_Editor as base


class App(PreviousApp):
    def __init__(self):
        super().__init__()
        self.title('TG + EDVALDO | Cercas e Porteiras FS25 v0.9 I3D - Anti-duplicatas')
        side=self.preview_canvas.master
        tk.Label(side,text='PROTECAO CONTRA CERCAS DUPLICADAS',
                 fg='#a9f8bb',bg='#11241f',font=('Segoe UI',10,'bold')).pack(
                     anchor='w',padx=16,pady=(6,0))
        tk.Label(side,text='Se ja existir cerca no mesmo lugar, o programa '
                          'pede confirmacao antes de substituir. '
                          'Outros modelos e trechos parciais nao sao apagados.',
                 fg='#d4e7dc',bg='#11241f',font=('Segoe UI',9),
                 wraplength=420,justify='left').pack(anchor='w',padx=16,pady=(1,10))
        self.log_message('v0.9: evita segmentos antigos duplicados e nao apaga cercas sem confirmacao.')

    def generate(self):
        try:
            mod=self.mods.get(self.fencemod.get())
            xml=self.fencexml.get()
            if mod is None or not xml:
                raise ValueError('Selecione o mod e o XML da cerca.')
            points, name, kind=core.load_i3d_points(Path(self.spline.get()))
            destination=Path(self.placeables.get())
            if not destination.is_file():
                raise ValueError('Selecione o placeables.xml de uma COPIA do savegame.')
            gate=self.native_gate.get()
            if not gate or gate=='(sem porteira)':
                gate=''
                if not messagebox.askyesno('Sem porteira',
                     'Nenhuma porteira escolhida. Quer criar apenas a cerca?'):
                    return
            tree,records,reports,distance,spec=build_fence_v08(
                points,mod,xml,destination,gate,float(self.gate_pct.get()),
                float(self.max_span.get()),float(self.tolerance_xy.get()),
                float(self.tolerance_y.get()),int(self.farm_id.get()))
            candidate=tree.getroot()[-1]
            duplicates, conflicts=scan_overlapping_fences(tree,candidate)
            self.log_message(
                f'I3D {name}: {distance:.1f} metros, {len(records)} segmentos; '
                f'{len(duplicates)} cerca(s) anterior(es) no mesmo caminho.')
            if gate:
                self.log_message(
                    f'Porteira: {gate}, a {float(self.gate_pct.get()):.1f}% da spline. '
                    'Animação do XML mantida.')
            if kind=='cubic':
                self.log_message('Aviso: curva cúbica do I3D é aproximada.')
            if not spec['registered']:
                self.log_message('AVISO: o XML da cerca não consta no modDesc.')
            if not spec['can_sell']:
                self.log_message('AVISO: canBeSold=false; verifique demolição no jogo.')
            if self.storeitems.get().strip():
                if ET.parse(self.storeitems.get()).getroot().tag!='storeItems':
                    raise ValueError('storeItems.xml inválido.')
            if conflicts:
                names=sorted({
                    (obj.get('filename') or obj.get('modName') or '(desconhecido)')
                    for obj,*_ in conflicts})
                description=', '.join(names[:3])
                self.log_message(
                    f'BLOQUEADO: {len(conflicts)} cerca(s) sobrepostas parcialmente '
                    f'ou de outros modelos. Exemplos: {description}.')
                messagebox.showwarning('Cercas sobrepostas detectadas',
                    f'Encontrei {len(conflicts)} cerca(s) conflitantes no mesmo local.\n'
                    'Não vou sobrescrever nem apagar essas cercas.\n'
                    'Confira o savegame ou retire manualmente a antiga antes de gerar.')
                return
            if self.dryrun.get():
                if duplicates:
                    self.log_message(
                        f'PRÉVIA: {len(duplicates)} cerca(s) iguais seriam substituídas '
                        'APÓS confirmação. Nada foi gravado.')
                else:
                    self.log_message('PRÉVIA: nenhuma cerca duplicada. Nada foi gravado.')
                return
            if duplicates:
                answer=messagebox.askyesno('Substituir cercas antigas?',
                    f'Foram encontradas {len(duplicates)} cerca(s) do MESMO modelo '
                    'e praticamente do MESMO traçado.\n\n'
                    'Deseja retirar essas instâncias antigas e gravar a nova?\n\n'
                    'O programa fará backup do XML antes de salvar.\n'
                    'Nenhum outro modelo será removido.')
                if not answer:
                    self.log_message('Cancelado: as cercas antigas foram preservadas.')
                    return
                removed=remove_confirmed_duplicates(tree,candidate,duplicates)
                self.log_message(f'Substituindo {removed} cerca(s) anterior(es) confirmadas.')
            backup=base.backup_and_write(destination,tree)
            self.log_message('SALVO COM BACKUP: '+str(destination))
            self.log_message('Backup original: '+str(backup))
            messagebox.showinfo('TG + EDVALDO',
                'Cerca atualizada sem duplicar o mesmo traçado. '
                'Confira a porteira e a demolição no FS25.')
        except Exception as exc:
            self.log_message('ERRO: '+str(exc))
            messagebox.showerror('TG + EDVALDO',str(exc))


if __name__=='__main__':
    App().mainloop()
