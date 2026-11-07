"""TOP GAMERS - Protótipo v0.2: spline do GIANTS Editor -> newFence do FS25.
Python 3.10+; só biblioteca padrão. Execute no Windows: py TG_Cerca_Editor.py.
"""
from __future__ import annotations

import csv
import math
import os
from pathlib import Path
import shutil
import tempfile
import uuid
import xml.etree.ElementTree as ET
import zipfile
import tkinter as tk
from tkinter import ttk, filedialog, messagebox


def mods_default() -> Path:
    return Path.home() / 'Documents' / 'My Games' / 'FarmingSimulator2025' / 'mods'


def read_mod_file(mod: Path, inside: str) -> bytes:
    if mod.is_dir():
        file = (mod / inside).resolve()
        if not file.is_relative_to(mod.resolve()):
            raise ValueError('Caminho inseguro dentro do mod')
        return file.read_bytes()
    with zipfile.ZipFile(mod) as z:
        return z.read(inside)


def xml_files(mod: Path) -> list[str]:
    if mod.is_dir():
        return sorted(p.relative_to(mod).as_posix() for p in mod.rglob('*.xml'))
    with zipfile.ZipFile(mod) as z:
        return sorted(n for n in z.namelist() if n.lower().endswith('.xml'))


def modname(mod: Path) -> str:
    return mod.stem if mod.is_file() else mod.name


def as_network_filename(mod: Path, inside: str) -> str:
    return '$moddir$' + modname(mod) + '/' + inside.replace('\\', '/')


def spline_points(path: Path) -> list[tuple[float, float, float]]:
    with path.open('r', encoding='utf-8-sig', newline='') as f:
        rows = list(csv.DictReader(f))
    pts = [(float(row['x']), float(row['y']), float(row['z'])) for row in rows]
    if len(pts) < 2 or any(not all(map(math.isfinite, p)) for p in pts):
        raise ValueError('Spline CSV inválida: precisa de pelo menos 2 pontos XYZ válidos')
    pts2 = [pts[0]]
    for p in pts[1:]:
        if math.dist((p[0], p[2]), (pts2[-1][0], pts2[-1][2])) > 0.01:
            pts2.append(p)
    if len(pts2) < 2:
        raise ValueError('Spline sem comprimento útil')
    return pts2


def cumulative(pts):
    dist = [0.0]
    for a, b in zip(pts, pts[1:]):
        dist.append(dist[-1] + math.hypot(b[0] - a[0], b[2] - a[2]))
    return dist


def at_distance(pts, acc, d):
    d = max(0, min(d, acc[-1]))
    for i in range(len(acc) - 1):
        if d <= acc[i + 1] or i == len(acc) - 2:
            t = (d - acc[i]) / max(1e-9, acc[i + 1] - acc[i])
            a, b = pts[i], pts[i + 1]
            return tuple(a[j] + t * (b[j] - a[j]) for j in range(3))
    return pts[-1]


def between(pts, acc, lo, hi):
    if hi - lo <= 0.05:
        return []
    result = [at_distance(pts, acc, lo)]
    result += [pts[i] for i in range(1, len(pts) - 1) if lo < acc[i] < hi]
    result.append(at_distance(pts, acc, hi))
    return result


def reduce_polyline(points, tolerance_xy=0.35, tolerance_y=0.18, max_segment=18.0):
    """Reduz pontos intermediários mantendo curvas/relevo e tamanho máximo.

    tolerance_xy: desvio horizontal admitido, em metros.
    tolerance_y: desvio de altitude admitido, em metros.
    max_segment: comprimento máximo do trecho no XML; NÃO é a distância
    entre os postes, definida pelo XML/modelo de cerca no FS25.
    """
    if not 1.0 <= max_segment <= 100.0:
        raise ValueError('Trecho máximo: informe de 1 a 100 metros')
    if not 0.01 <= tolerance_xy <= 3 or not 0.01 <= tolerance_y <= 3:
        raise ValueError('Tolerâncias: informe de 0,01 a 3 metros')
    if len(points) < 3:
        return list(points)

    keep = {0, len(points)-1}
    pending = [(0, len(points)-1)]
    # Ramer-Douglas-Peucker com erro horizontal e vertical independentes.
    while pending:
        start, end = pending.pop()
        a, b = points[start], points[end]
        vx, vz = b[0]-a[0], b[2]-a[2]
        norm = vx*vx+vz*vz
        worst, index = 0, None
        for i in range(start+1, end):
            p = points[i]
            t = max(0.0, min(1.0, ((p[0]-a[0])*vx + (p[2]-a[2])*vz) / norm)) if norm > 1e-10 else 0.0
            x = a[0]+t*vx
            z = a[2]+t*vz
            y = a[1]+t*(b[1]-a[1])
            error = max(math.hypot(p[0]-x, p[2]-z)/tolerance_xy,
                        abs(p[1]-y)/tolerance_y)
            if error > worst:
                worst, index = error, i
        if worst > 1.0 and index is not None:
            keep.add(index)
            pending.extend(((start, index), (index, end)))

    result = []
    selected = sorted(keep)
    dist = cumulative(points)
    for k, index in enumerate(selected[:-1]):
        nxt = selected[k+1]
        if not result:
            result.append(points[index])
        # Divide trechos longos, sem aproximar por uma reta enorme.
        length = dist[nxt]-dist[index]
        divisions = max(1, math.ceil(length / max_segment))
        for j in range(1, divisions):
            result.append(at_distance(points, dist, dist[index] + length*j/divisions))
        result.append(points[nxt])
    return [p for i,p in enumerate(result) if i == 0 or math.dist(p, result[i-1]) >= 0.05]


def fence_diagnostics(root):
    """Diagnóstico informativo; o modelo I3D e suas colisões exigem teste no jogo."""
    fence = root.find('fence')
    if fence is None:
        return ['XML sem <fence>; pode não ser uma cerca nativa.']
    panels = fence.find('panels')
    poles = fence.find('poles')
    msgs = []
    if poles is None or not poles.get('node'):
        msgs.append('AVISO: <poles node> não encontrado; confira o modelo de postes.')
    if panels is None or not panels.get('node'):
        msgs.append('AVISO: <panels node> não encontrado. Isto pode explicar a falta de fios/paineis.')
    else:
        try:
            length = float(panels.get('length', '1'))
            fixed = panels.get('fixedLength', 'false')
            msgs.append(f'Painéis do MOD: {length:g} m; fixedLength={fixed}. A distância dos postes depende do MOD, não da spline.')
        except ValueError:
            msgs.append('AVISO: comprimento dos painéis no XML não é numérico.')
    msgs.append('DEMOLIÇÃO: a cerca deve usar newFence e ter painéis clicáveis/colisões; teste em terreno possuído pela sua fazenda.')
    return msgs


def pos(v):
    return ' '.join(f'{n:.3f}' for n in v)


def check_mod_xml(mod: Path, inside: str, expected: str):
    raw = read_mod_file(mod, inside)
    root = ET.fromstring(raw)
    if root.tag != 'placeable':
        raise ValueError(f'{inside}: raiz deve ser <placeable>')
    if expected == 'fence' and root.find('fence') is None:
        raise ValueError(f'{inside}: não possui <fence> nativa FS25')
    return root


def registered_in_mod(mod: Path, inside: str) -> bool:
    try:
        desc = ET.fromstring(read_mod_file(mod, 'modDesc.xml'))
    except (FileNotFoundError, KeyError, ET.ParseError):
        return False
    names = [x.get('xmlFilename', '').replace('\\', '/').lower().lstrip('./')
             for x in desc.findall('.//storeItems/storeItem')]
    return inside.lower().lstrip('./') in names


def backup_and_write(path: Path, tree: ET.ElementTree):
    backup = path.with_name(path.name + '.tg_backup')
    if not backup.exists():
        shutil.copy2(path, backup)
    fd, scratch = tempfile.mkstemp(prefix='tg_cerca_', suffix='.xml', dir=path.parent)
    os.close(fd)
    try:
        ET.indent(tree, space='    ')
        tree.write(scratch, encoding='utf-8', xml_declaration=True)
        ET.parse(scratch)
        os.replace(scratch, path)
    finally:
        if os.path.exists(scratch):
            os.unlink(scratch)
    return backup


def create_fence(pts, fence_mod, fence_inside, target, gate_mod=None, gate_inside='',
                 gate_pct=50.0, gate_width=4.0, max_span=18.0,
                 tolerance_xy=0.35, tolerance_y=0.18, gate_farm_id=1):
    """Gera entradas para CERCA NATIVA e, opcionalmente, porteira separada."""
    check_mod_xml(fence_mod, fence_inside, 'fence')
    if not 0 <= gate_farm_id <= 255:
        raise ValueError('ID da fazenda da porteira deve estar entre 0 e 255')
    if gate_mod and gate_inside:
        gate_root = check_mod_xml(gate_mod, gate_inside, 'gate')
        if gate_root.find('fence') is not None:
            raise ValueError('Porteira selecionada também é cerca newFence: precisa de ID de gate nativo. Não vou inserir XML errado.')
    else:
        gate_mod = None
    tree = ET.parse(target)
    root = tree.getroot()
    if root.tag != 'placeables':
        raise ValueError('Arquivo destino deve ter raiz <placeables>')
    acc = cumulative(pts)
    total = acc[-1]
    if gate_mod:
        if not 0 < gate_width < total:
            raise ValueError('Largura da porteira deve ser menor que a cerca')
        center_dist = total * (gate_pct / 100.0)
        start = center_dist - gate_width / 2
        end = center_dist + gate_width / 2
        if start < 0 or end > total:
            raise ValueError('Porteira fora dos limites da spline')
        pieces = [between(pts, acc, 0, start), between(pts, acc, end, total)]
    else:
        pieces = [pts]
    # Cada <segment> é um trecho de percurso, não cada poste individual.
    # O jogo gera postes/painéis pelo modelo e por <fence><panels length>.
    pieces = [reduce_polyline(piece, tolerance_xy, tolerance_y, max_span)
              for piece in pieces if len(piece) >= 2]
    fence = ET.SubElement(root, 'placeable', {
        'filename': as_network_filename(fence_mod, fence_inside),
        'modName': modname(fence_mod), 'uniqueId': 'placeable' + uuid.uuid4().hex,
        'position': '0.000 -151.000 0.000', 'rotation': '0.000 0.000 0.000',
        'age': '0.000000', 'price': '100.000000', 'farmId': '0'})
    newfence = ET.SubElement(fence, 'newFence')
    count = 0
    for piece in pieces:
        for a, b in zip(piece, piece[1:]):
            ET.SubElement(newfence, 'segment', {'start': pos(a), 'end': pos(b), 'id': 'SEGMENT'})
            count += 1
    if not count:
        raise ValueError('Nenhum segmento válido para exportar')
    if gate_mod:
        center = at_distance(pts, acc, center_dist)
        startp = at_distance(pts, acc, start)
        endp = at_distance(pts, acc, end)
        yaw = math.degrees(math.atan2(endp[0] - startp[0], endp[2] - startp[2]))
        ET.SubElement(root, 'placeable', {
            'filename': as_network_filename(gate_mod, gate_inside),
            'modName': modname(gate_mod), 'uniqueId': 'placeable' + uuid.uuid4().hex,
            'position': pos(center), 'rotation': f'0.000 {yaw:.3f} 0.000',
            'age': '0.000000', 'price': '100.000000', 'farmId': str(gate_farm_id)})
    return tree, count, total


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('TOP GAMERS - Cerca por Spline FS25 (teste v0.2)')
        self.geometry('860x750')
        self.minsize(750, 680)
        self.mods_dir = tk.StringVar(value=str(mods_default()))
        self.spline = tk.StringVar(value=str(Path(tempfile.gettempdir()) / 'TG_Cerca_Spline.csv'))
        self.placeables = tk.StringVar()
        self.storeitems = tk.StringVar()
        self.fencemod = tk.StringVar()
        self.fencexml = tk.StringVar()
        self.gatemod = tk.StringVar()
        self.gatexml = tk.StringVar()
        self.animxml = tk.StringVar()
        self.gate_pct = tk.DoubleVar(value=50)
        self.gate_width = tk.DoubleVar(value=4)
        self.max_span = tk.DoubleVar(value=18)
        self.tolerance_xy = tk.DoubleVar(value=0.35)
        self.tolerance_y = tk.DoubleVar(value=0.18)
        self.gate_farm_id = tk.IntVar(value=1)
        self.dryrun = tk.BooleanVar(value=True)
        self.mods = {}
        frm = ttk.Frame(self, padding=12)
        frm.pack(fill='both', expand=True)
        frm.columnconfigure(1, weight=1)
        def chooser(row, name, var, filetype, is_dir=False):
            ttk.Label(frm, text=name).grid(row=row, column=0, sticky='w', pady=4)
            ttk.Entry(frm, textvariable=var).grid(row=row, column=1, sticky='ew', pady=4)
            def pick():
                val = filedialog.askdirectory() if is_dir else filedialog.askopenfilename(filetypes=filetype)
                if val: var.set(val)
            ttk.Button(frm, text='Selecionar', command=pick).grid(row=row, column=2, padx=4)
        chooser(0, 'Pasta mods', self.mods_dir, [], True)
        ttk.Button(frm, text='Carregar mods', command=self.scan).grid(row=1, column=2)
        def selector(row, label, var, cbname, callback=None):
            ttk.Label(frm, text=label).grid(row=row, column=0, sticky='w', pady=4)
            box = ttk.Combobox(frm, textvariable=var, state='readonly')
            box.grid(row=row, column=1, columnspan=2, sticky='ew', pady=4)
            if callback: box.bind('<<ComboboxSelected>>', callback)
            setattr(self, cbname, box)
        selector(2, 'Mod da cerca', self.fencemod, 'fence_mod_box', self.update_fence)
        selector(3, 'XML da cerca', self.fencexml, 'fence_xml_box')
        selector(4, 'Mod da porteira (opcional)', self.gatemod, 'gate_mod_box', self.update_gate)
        selector(5, 'XML da porteira', self.gatexml, 'gate_xml_box')
        selector(6, 'XML da animação (conferir)', self.animxml, 'anim_xml_box')
        chooser(7, 'Spline CSV do Editor', self.spline, [('CSV', '*.csv')])
        chooser(8, 'placeables.xml do mapa', self.placeables, [('XML', '*.xml')])
        chooser(9, 'storeItems.xml (opcional)', self.storeitems, [('XML', '*.xml')])
        ttk.Label(frm, text='Posição porteira (%)').grid(row=10, column=0, sticky='w')
        ttk.Spinbox(frm, from_=1, to=99, textvariable=self.gate_pct, width=10).grid(row=10, column=1, sticky='w')
        ttk.Label(frm, text='Largura porteira (m)').grid(row=11, column=0, sticky='w')
        ttk.Spinbox(frm, from_=1, to=20, increment=0.5, textvariable=self.gate_width, width=10).grid(row=11, column=1, sticky='w')
        ttk.Label(frm, text='Trecho máximo no XML (m)').grid(row=12, column=0, sticky='w')
        ttk.Spinbox(frm, from_=2, to=80, increment=1, textvariable=self.max_span, width=10).grid(row=12, column=1, sticky='w')
        ttk.Label(frm, text='Tolerância da curva (m)').grid(row=13, column=0, sticky='w')
        ttk.Spinbox(frm, from_=0.05, to=2, increment=0.05, textvariable=self.tolerance_xy, width=10).grid(row=13, column=1, sticky='w')
        ttk.Label(frm, text='Tolerância do relevo (m)').grid(row=14, column=0, sticky='w')
        ttk.Spinbox(frm, from_=0.05, to=1, increment=0.05, textvariable=self.tolerance_y, width=10).grid(row=14, column=1, sticky='w')
        ttk.Label(frm, text='Farm ID da porteira (0-255)').grid(row=15, column=0, sticky='w')
        ttk.Spinbox(frm, from_=0, to=255, textvariable=self.gate_farm_id, width=10).grid(row=15, column=1, sticky='w')
        ttk.Checkbutton(frm, text='Só conferir / prévia (não altera arquivos)', variable=self.dryrun).grid(row=16, column=0, columnspan=3, sticky='w', pady=10)
        ttk.Button(frm, text='Conferir / Gerar XML', command=self.generate).grid(row=17, column=0, columnspan=3, sticky='ew')
        self.log = tk.Text(frm, height=8, wrap='word')
        self.log.grid(row=18, column=0, columnspan=3, sticky='nsew', pady=8)
        frm.rowconfigure(18, weight=1)
        self.scan()

    def scan(self):
        folder = Path(self.mods_dir.get())
        if not folder.is_dir():
            self.log_message('Pasta mods não encontrada. Selecione a pasta correta.')
            return
        files = list(folder.glob('*.zip')) + [p for p in folder.iterdir() if p.is_dir() and (p / 'modDesc.xml').exists()]
        self.mods = {modname(p): p for p in files}
        names = sorted(self.mods, key=str.casefold)
        self.fence_mod_box['values'] = names
        self.gate_mod_box['values'] = ['(sem porteira)'] + names
        self.log_message(f'Encontrados {len(names)} mods; escolha o da cerca e, se quiser, o da porteira.')

    def update_fence(self, _=None):
        try: self.fence_xml_box['values'] = xml_files(self.mods[self.fencemod.get()])
        except Exception as exc: self.log_message(str(exc))
        self.fencexml.set('')

    def update_gate(self, _=None):
        name = self.gatemod.get()
        if name == '(sem porteira)':
            self.gatexml.set('')
            self.animxml.set('')
            return
        try:
            options = xml_files(self.mods[name])
            self.gate_xml_box['values'] = options
            self.anim_xml_box['values'] = ['(no próprio XML)'] + options
        except Exception as exc: self.log_message(str(exc))
        self.gatexml.set('')

    def log_message(self, message):
        if hasattr(self, 'log'):
            self.log.insert('end', str(message) + '\n')
            self.log.see('end')

    def generate(self):
        try:
            fence_mod = self.mods[self.fencemod.get()]
            fxml = self.fencexml.get()
            if not fxml: raise ValueError('Selecione o XML da cerca')
            pts = spline_points(Path(self.spline.get()))
            placeable_file = Path(self.placeables.get())
            if not placeable_file.is_file(): raise ValueError('Selecione o placeables.xml válido')
            name = self.gatemod.get()
            gate_mod = self.mods.get(name)
            gate_xml = self.gatexml.get()
            if gate_mod and not gate_xml: raise ValueError('Selecione o XML da porteira')
            if gate_mod and self.animxml.get() not in ('', '(no próprio XML)'):
                ET.fromstring(read_mod_file(gate_mod, self.animxml.get()))
            tree, count, distance = create_fence(pts, fence_mod, fxml, placeable_file,
                gate_mod, gate_xml, self.gate_pct.get(), self.gate_width.get(),
                self.max_span.get(), self.tolerance_xy.get(), self.tolerance_y.get(),
                self.gate_farm_id.get())
            self.log_message(f'Prévia OK: {count} segmentos no XML, {distance:.1f} metros (entrada: {len(pts)-1} trechos).')
            for diagnostic in fence_diagnostics(check_mod_xml(fence_mod, fxml, 'fence')):
                self.log_message(diagnostic)
            if count > 1000:
                self.log_message('AVISO: muitos segmentos. Experimente 20 m de trecho máximo e tolerância da curva de 0,5 m.')
            if not registered_in_mod(fence_mod, fxml):
                self.log_message('AVISO: XML da cerca não encontrado em <storeItems> do modDesc. A loja pode não registrar.')
            if gate_mod and not registered_in_mod(gate_mod, gate_xml):
                self.log_message('AVISO: porteira não registrada no modDesc; pode não carregar no FS25.')
            if self.storeitems.get().strip():
                s = Path(self.storeitems.get())
                if s.is_file() and ET.parse(s).getroot().tag == 'storeItems':
                    self.log_message('storeItems.xml validado. Para mods externos, o cadastro na loja é feito pelo modDesc.xml do próprio mod; não adicionei registro duplicado.')
                else:
                    raise ValueError('storeItems.xml inválido')
            if self.dryrun.get():
                self.log_message('MODO PRÉVIA: nenhum arquivo modificado. Desmarque a caixa para gravar.')
                return
            backup = backup_and_write(placeable_file, tree)
            self.log_message(f'GRAVADO: {placeable_file}\nBackup: {backup}')
            messagebox.showinfo('TOP GAMERS', 'Cerca salva no XML! Confira no jogo e no log.txt.')
        except Exception as exc:
            self.log_message('ERRO: ' + str(exc))
            messagebox.showerror('TOP GAMERS', str(exc))


if __name__ == '__main__':
    App().mainloop()
