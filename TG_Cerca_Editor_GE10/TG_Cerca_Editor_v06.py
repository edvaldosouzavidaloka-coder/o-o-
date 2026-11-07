"""TG + EDVALDO — Criador de Cercas FS25 v0.6 (beta).
Interface com foto original escurecida. Spline I3D; nenhuma dependencia de CSV.
Somente XML de savegame de teste, backup antes de gravar.
"""
from __future__ import annotations

import base64
import io
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import xml.etree.ElementTree as ET

from PIL import Image, ImageEnhance, ImageOps, ImageTk

import TG_Cerca_Editor_v05 as core
import TG_Cerca_Editor as base
from tg_brand_photo_v06 import BG_JPEG_B64


def model_details(mod_path: Path, xml_path: str) -> dict:
    """Valida tipo da cerca, painel, poste e identificadores da loja."""
    root = base.check_mod_xml(mod_path, xml_path, 'fence')
    if root.get('type') != 'newFence':
        raise ValueError('Este arquivo não declara placeable type="newFence".')
    length, gates = core.fence_spec(mod_path, xml_path)
    seg = root.find("./fence/segment[@id='SEGMENT']")
    if seg is None or seg.get('class') != 'FenceSegment':
        raise ValueError('Segmento padrão não usa a classe nativa FenceSegment.')
    panel = seg.find('./panels/panel')
    pole = seg.find('./poles/pole')
    if panel is None or pole is None:
        raise ValueError('Modelo não possui painel e poste nativos.')
    flags = {
        'xml': xml_path,
        'name': Path(xml_path).stem,
        'panel_length': length,
        'panel_node': panel.get('node'),
        'pole_node': pole.get('node'),
        'gates': gates,
        'registered': base.registered_in_mod(mod_path, xml_path),
        'can_sell': (root.findtext('./storeData/canBeSold', 'true').strip().lower() == 'true'),
        'category': root.findtext('./storeData/category', '(não informada)').strip(),
        'newfence': root.find('./storeData/brush/type') is not None and
                    root.findtext('./storeData/brush/type', '').strip() == 'newFence',
    }
    return flags


class App(core.App):
    def __init__(self):
        super().__init__()
        self.title('TG + EDVALDO | Criador de Cercas FS25 v0.6 I3D BETA')
        self.geometry('1240x800')
        self.minsize(1120, 720)
        self.farm_id = tk.StringVar(value='0')
        self._image_src = None
        self._bg_bitmap = None
        self._last_size = (-1, -1)
        self._configure_theme()
        frame = self.log.master
        frame.columnconfigure(3, minsize=320, weight=0)
        self._canvas = tk.Canvas(frame, bd=0, highlightthickness=0, bg='#071411')
        self._canvas.place(x=0, y=0, relwidth=1, relheight=1)
        tk.Misc.lower(self._canvas)
        frame.bind('<Configure>', self._redraw, add='+')
        self._set_background()

        title = ttk.Label(frame, text='TG + EDVALDO', style='Brand.TLabel')
        title.grid(row=0, column=3, sticky='nw', padx=(18, 10), pady=(24, 5))
        ttk.Label(frame, text='CRIADOR DE CERCAS FS25\nVERSÃO 0.6 • I3D', style='BrandSmall.TLabel',
                  justify='left').grid(row=1, column=3, sticky='nw', padx=18, pady=4)
        ttk.Label(frame, text='MODELO SELECIONADO', style='BrandCaption.TLabel').grid(
            row=3, column=3, sticky='nw', padx=18, pady=(18, 2))
        self._details = tk.Label(frame, text='Selecione o XML do mod da cerca.',
                                 font=('Segoe UI', 10), fg='#e2f1e9', bg='#142920',
                                 anchor='nw', justify='left', wraplength=260,
                                 padx=12, pady=12)
        self._details.grid(row=4, column=3, rowspan=4, sticky='nsew', padx=18, pady=(0, 12))
        ttk.Label(frame, text='PROPRIEDADE / DEMOLIÇÃO', style='BrandCaption.TLabel').grid(
            row=8, column=3, sticky='nw', padx=18, pady=(14, 1))
        ttk.Label(frame, text='Farm ID no placeables.xml', style='BrandSmall.TLabel').grid(
            row=9, column=3, sticky='nw', padx=18)
        farm = ttk.Combobox(frame, textvariable=self.farm_id, values=('0', '1', '2', '3', '4', '5'),
                            width=12)
        farm.grid(row=10, column=3, sticky='nw', padx=18, pady=(2, 7))
        ttk.Label(frame, text='0 = mapa / 1 = fazenda 1.\n'
                               'O terreno precisa pertencer à fazenda.\n'
                               'Demolição depende do sistema nativo\n'
                               'e das colisões do modelo.',
                  style='BrandSmall.TLabel', justify='left').grid(
            row=11, column=3, rowspan=2, sticky='nw', padx=18, pady=(3, 10))
        ttk.Button(frame, text='Escolher foto em alta resolução…',
                   command=self._choose_background).grid(
            row=14, column=3, sticky='ew', padx=18, pady=6)
        ttk.Label(frame, text='Fundo original escurecido para\n'
                               'facilitar a leitura dos campos.',
                  style='BrandSmall.TLabel', justify='left').grid(
            row=15, column=3, sticky='nw', padx=18, pady=3)

        self.fence_mod_box.bind('<<ComboboxSelected>>', self._model_changed, add='+')
        self.fence_xml_box.bind('<<ComboboxSelected>>', self._model_changed, add='+')
        self.log.configure(bg='#0b1b18', fg='#ecf5ef', insertbackground='white',
                           selectbackground='#23614d', relief='flat')
        self.log_message('v0.6: foto TG escurecida; XML newFence verificado por modelo.')
        self.log_message('Demolição por trechos só pode ser confirmada no FS25, em terreno da fazenda.')

    def _configure_theme(self):
        style = ttk.Style(self)
        if 'clam' in style.theme_names():
            style.theme_use('clam')
        style.configure('TFrame', background='#10211b')
        style.configure('TLabel', background='#15271f', foreground='#eef6ed', font=('Segoe UI', 10))
        style.configure('TCheckbutton', background='#15271f', foreground='#eef6ed',
                        font=('Segoe UI', 10))
        style.map('TCheckbutton', background=[('active', '#1e392c')])
        style.configure('TEntry', foreground='#0f221a', fieldbackground='#e9f1eb')
        style.configure('TCombobox', foreground='#0f221a', fieldbackground='#e9f1eb')
        style.configure('TSpinbox', foreground='#0f221a', fieldbackground='#e9f1eb')
        style.configure('TButton', background='#206345', foreground='#f5fff8',
                        font=('Segoe UI', 10, 'bold'), padding=6)
        style.map('TButton', background=[('active', '#2c8060')])
        style.configure('Brand.TLabel', background='#0b261b', foreground='#9ffa9f',
                        font=('Segoe UI', 22, 'bold'))
        style.configure('BrandSmall.TLabel', background='#112b21', foreground='#eef4e9',
                        font=('Segoe UI', 10))
        style.configure('BrandCaption.TLabel', background='#0b261b', foreground='#9decc0',
                        font=('Segoe UI', 10, 'bold'))
        self.option_add('*TCombobox*Listbox.background', '#e9f1eb')

    def _set_background(self, path=None):
        try:
            if path is None:
                photo = Image.open(io.BytesIO(base64.b64decode(BG_JPEG_B64))).convert('RGB')
                # Já escurecida e redimensionada, incorporada no EXE.
            else:
                photo = Image.open(path).convert('RGB')
                photo = ImageEnhance.Brightness(photo).enhance(.35)
            self._image_src = photo
            self._last_size = (-1, -1)
            self._redraw()
        except Exception as exc:
            self.log_message('Não foi possível carregar o fundo; usando tema escuro: ' + str(exc))

    def _choose_background(self):
        path = filedialog.askopenfilename(
            title='Selecione a imagem do trator',
            filetypes=[('Imagem', '*.jpg *.jpeg *.png *.webp')])
        if path:
            self._set_background(path)
            self.log_message('Imagem de fundo alterada: ' + Path(path).name)

    def _redraw(self, _=None):
        if self._image_src is None:
            return
        w = max(1, self._canvas.winfo_width())
        h = max(1, self._canvas.winfo_height())
        if w < 4 or h < 4 or self._last_size == (w, h):
            return
        self._last_size = (w, h)
        fill = ImageOps.fit(self._image_src, (w, h),
                            method=Image.Resampling.BILINEAR, centering=(.5, .5))
        self._bg_bitmap = ImageTk.PhotoImage(fill)
        self._canvas.delete('all')
        self._canvas.create_image(0, 0, image=self._bg_bitmap, anchor='nw')
        self._canvas.create_rectangle(0, 0, w-330, h,
                                     fill='#0b1b17', stipple='gray50', outline='')
        tk.Misc.lower(self._canvas)

    def update_fence(self, _=None):
        # Na lista, apenas XMLs realmente configurados como cercas nativas FS25.
        super().update_fence(_)
        mod = self.mods.get(self.fencemod.get())
        if mod is None:
            return
        results = []
        for path in base.xml_files(mod):
            if not path.lower().endswith('.xml'):
                continue
            try:
                root = ET.fromstring(base.read_mod_file(mod, path))
            except (ValueError, ET.ParseError, KeyError, OSError):
                continue
            if root.get('type') == 'newFence' and root.find("./fence/segment[@id='SEGMENT']") is not None:
                results.append(path)
        self.fence_xml_box['values'] = results
        self.log_message(f'{len(results)} modelos newFence encontrados no mod selecionado.')
        if hasattr(self, '_details'):
            self._details.config(text='Selecione um dos modelos disponíveis.')

    def _model_changed(self, _=None):
        mod = self.mods.get(self.fencemod.get())
        path = self.fencexml.get()
        if not mod or not path:
            return
        try:
            spec = model_details(mod, path)
            text = ('Modelo: ' + spec['name'] + '\n'
                    + f"Tipo: newFence\nPainel: {spec['panel_length']:g} metros\n"
                    + f"Poste: {spec['pole_node']}\nPainel: {spec['panel_node']}\n"
                    + f"Porteiras: {len(spec['gates'])}\n"
                    + 'Registrado no modDesc: ' + ('SIM' if spec['registered'] else 'NÃO') + '\n'
                    + 'Pode vender (XML): ' + ('SIM' if spec['can_sell'] else 'NÃO') + '\n'
                    + 'Categoria: ' + spec['category'])
            self._details.config(text=text)
            self.log_message('Modelo reconhecido: ' + spec['name'])
        except Exception as exc:
            self._details.config(text='XML incompatível: ' + str(exc))
            self.log_message('ERRO de compatibilidade: ' + str(exc))

    def generate(self):
        try:
            mod = self.mods.get(self.fencemod.get())
            xml = self.fencexml.get()
            if mod is None or not xml:
                raise ValueError('Selecione um mod e um XML de cerca.')
            spec = model_details(mod, xml)
            farm_id = int(self.farm_id.get())
            if not 0 <= farm_id <= 255:
                raise ValueError('Farm ID deve ser entre 0 e 255.')
            pts, name, kind = core.load_i3d_points(Path(self.spline.get()))
            target = Path(self.placeables.get())
            if not target.is_file():
                raise ValueError('Selecione placeables.xml de uma CÓPIA do savegame.')
            native = self.native_gate.get()
            if native == '(sem porteira)':
                native = ''
            if self.gatemod.get() not in ('', '(sem porteira)'):
                raise ValueError('Escolha porteira nativa no XML, sem mod de porteira separado.')
            tree, count, distance, panel = core.create_fence_v03(
                pts, mod, xml, target, native, self.gate_pct.get(), self.max_span.get(),
                self.tolerance_xy.get(), self.tolerance_y.get())
            new_obj = tree.getroot()[-1]
            if new_obj.tag != 'placeable' or new_obj.find('newFence') is None:
                raise ValueError('Falha de integridade: XML não gerou cercas nativas.')
            new_obj.set('farmId', str(farm_id))
            self.log_message(
                f'Prévia: {spec["name"]}, {count} segmentos em {distance:.1f} m; '
                f'painel do mod {panel:g} m; farmId={farm_id}.')
            if kind == 'cubic':
                self.log_message('ATENÇÃO: spline I3D cúbica aproximada pelos pontos de controle.')
            if not spec['registered']:
                self.log_message('AVISO: modDesc não registra esse XML, o jogo pode ignorar.')
            if not spec['can_sell']:
                self.log_message('AVISO: o XML do mod contém <canBeSold>false</canBeSold>.')
            if self.storeitems.get().strip():
                if ET.parse(self.storeitems.get()).getroot().tag != 'storeItems':
                    raise ValueError('storeItems.xml inválido.')
                self.log_message('storeItems.xml validado, sem alteração.')
            self.log_message('Demolição no FS25: exige terreno da fazenda, painel selecionável e modelo compatível.')
            if self.dryrun.get():
                self.log_message('MODO PRÉVIA: nada foi modificado.')
                return
            backup = base.backup_and_write(target, tree)
            self.log_message(f'GRAVADO em {target} | Backup: {backup}')
            messagebox.showinfo('TG + EDVALDO', 'XML salvo com backup. Teste no FS25 e confira o log.txt.')
        except Exception as exc:
            self.log_message('ERRO: ' + str(exc))
            messagebox.showerror('TG + EDVALDO', str(exc))


if __name__ == '__main__':
    App().mainloop()
