"""TG + EDVALDO FS25 v1.4 — janela PC Objects com I3D exportado.

Posição e rotação digitáveis, sem obrigar o I3D principal. Novo XML
decorativo autogerado caso o arquivo do item não exista. Selecionar um
arquivo nunca registra automaticamente — marque destino, CONFERIR, REGISTRAR.
"""
from __future__ import annotations
from pathlib import Path
import tkinter as tk
from tkinter import ttk,messagebox

from TG_Cerca_Editor_v13 import App as PreviousApp,PCObjectsWindow as PreviousWindow
import TG_PCObjects_Export_v14 as export
import TG_PCObjects_Core_v11 as pc


class PCObjectsWindow(PreviousWindow):
    def __init__(self,owner):
        super().__init__(owner)
        self.title("TG + EDVALDO | PC Objects v1.4 — I3D exportado")
        self.geometry("1400x870")
        self.minsize(1080,760)
        self.last_preview=None
        self.pos_vars=[tk.StringVar() for _ in range(3)]
        self.rot_vars=[tk.StringVar() for _ in range(3)]
        self._last_i3d=""
        self._position_was_exported=False
        frame=self.log.master
        for widget in frame.grid_slaves(row=1,column=0):
            if isinstance(widget,ttk.Label):
                widget.configure(text="I3D do MAPA (opcional)")
        for widget in frame.grid_slaves(row=2,column=0):
            if isinstance(widget,ttk.Label):
                widget.configure(text="I3D EXPORTADO do OBJETO")
        for widget in frame.grid_slaves(row=3,column=0):
            if isinstance(widget,ttk.Label):
                widget.configure(text="XML do OBJETO (opcional — sem XML: decoração)")
        coords=ttk.Frame(frame,padding=(4,6))
        coords.grid(row=8,column=0,columnspan=3,sticky="ew",pady=4)
        ttk.Label(coords,text="Localização do objeto exportado:").pack(side="left",padx=(0,10))
        for title,var in zip(("X","Y","Z"),self.pos_vars):
            ttk.Label(coords,text=title).pack(side="left",padx=2)
            ttk.Entry(coords,textvariable=var,width=9).pack(side="left",padx=(0,7))
        ttk.Label(coords,text="Rotação (graus):").pack(side="left",padx=(7,7))
        for title,var in zip(("RX","RY","RZ"),self.rot_vars):
            ttk.Label(coords,text=title).pack(side="left",padx=2)
            ttk.Entry(coords,textvariable=var,width=8).pack(side="left",padx=(0,7))
        ttk.Button(coords,text="Ler posição do I3D",command=self.read_export_position).pack(
            side="left",padx=10)
        self.note=ttk.Label(frame,text=
            "I3D exportado: confira X/Y/Z e rotação. Se o GE zerou a origem, "
            "digite a localização correta. Sem XML, o objeto gerado é SOMENTE decorativo.",
            wraplength=1250)
        self.note.grid(row=9,column=0,columnspan=3,sticky="w",pady=(2,5))
        self._log("v1.4: NÃO exige I3D do mapa para placeables.")
        self._log("Preencha a posição/rotação do I3D exportado ou digite manualmente.")
        self._log("Sem XML de item, cria apenas um simplePlaceable DECORATIVO "
                  "e um ícone simples de loja; silo funcional exige XML próprio.")

    def _pick(self,var,folder=False):
        previous=var.get()
        super()._pick(var,folder)
        if var is self.object_i3d and var.get()!=previous:
            self._last_i3d=""
            self._position_was_exported=False
            for v in (*self.pos_vars,*self.rot_vars):
                v.set("")
            self.read_export_position(silent=True)

    def read_export_position(self,silent=False):
        try:
            model=self.object_i3d.get().strip()
            info=export.export_transform(model)
            self._last_i3d=str(Path(model).resolve())
            if info["position"] is not None:
                for var,val in zip(self.pos_vars,info["position"]):
                    var.set(f"{val:.5f}".rstrip("0").rstrip("."))
                for var,val in zip(self.rot_vars,info["rotation"] or (0.,0.,0.)):
                    var.set(f"{val:.5f}".rstrip("0").rstrip("."))
                self._position_was_exported=True
                self._log(f"I3D {Path(model).name}: XYZ "
                          f"{tuple(v.get() for v in self.pos_vars)}, rotação "
                          f"{tuple(v.get() for v in self.rot_vars)}.")
                self._log(info["warning"])
            else:
                self._position_was_exported=False
                self._log("I3D sem coordenadas explícitas no grupo raiz. "
                          "Preencha X/Y/Z e RX/RY/RZ conforme GE.")
                if not silent:
                    messagebox.showwarning("Objeto sem posição global",
                        "O I3D exportado não guarda a localização global no grupo raiz. "
                        "Preencha X, Y, Z e as rotações manualmente.",
                        parent=self)
            return info
        except Exception as exc:
            self._log("I3D exportado: "+str(exc))
            if not silent:
                messagebox.showerror("TG + EDVALDO",str(exc),parent=self)
            return None

    def load_objects(self):
        """Lê o próprio I3D exportado sem exigir que já esteja na cena do mapa."""
        chosen=self.object_i3d.get().strip()
        if not chosen:
            if self.map_i3d.get().strip():
                return super().load_objects()
            self._log("Selecione I3D do OBJETO exportado pelo GE.")
            messagebox.showwarning("TG + EDVALDO","Selecione o I3D exportado do objeto.",
                                   parent=self)
            return 0
        info=self.read_export_position(silent=True)
        if info is None:
            return 0
        xyz=info["position"]
        rot=info["rotation"]
        if xyz is None:
            self.entries=[]
            self._reload()
            self._log("I3D carregado. Localização manual necessária para registrar no mapa.")
            return 1
        self.entries=[dict(id="exportado",name=info["name"],position=xyz,
                           rotation=rot,kind="I3D exportado",reference=chosen)]
        self._reload()
        self._log("Objeto exportado carregado; posição e rotação editáveis acima.")
        return 1

    def _selection_signature(self):
        return super()._selection_signature()+(
            tuple(v.get().strip() for v in self.pos_vars),
            tuple(v.get().strip() for v in self.rot_vars))

    def _plan(self):
        model=self.object_i3d.get().strip()
        if self.to_placeables.get():
            # Permite inserir posição manual mesmo se o i3d não trouxe translation.
            if not all(v.get().strip() for v in self.pos_vars):
                if not model:
                    raise ValueError("Selecione o I3D exportado do objeto.")
                info=export.export_transform(model)
                if info["position"] is not None:
                    for var,val in zip(self.pos_vars,info["position"]):
                        if not var.get().strip():
                            var.set(str(val))
                    for var,val in zip(self.rot_vars,info["rotation"] or (0,0,0)):
                        if not var.get().strip():
                            var.set(str(val))
                else:
                    raise ValueError("O I3D não contém posição global. "
                                     "Preencha X, Y, Z e RX/RY/RZ manualmente.")
            if not all(v.get().strip() for v in self.rot_vars):
                raise ValueError("Preencha as rotações RX, RY, RZ em graus.")
        return export.build_xml_entries(
            maproot=self.maproot.get().strip(),
            object_i3d=model,
            object_xml=self.object_xml.get().strip(),
            placeables_path=self.placeables.get().strip(),
            storeitems_path=self.storeitems.get().strip(),
            position=[v.get().strip() for v in self.pos_vars],
            rotation=[v.get().strip() for v in self.rot_vars],
            do_placeables=self.to_placeables.get(),
            do_store=self.to_store.get(),mods=self.owner.mods)

    def preview_registration(self):
        try:
            entries,summary=self._plan()
            self.last_preview=(self._selection_signature(),summary.copy())
            self._log(f"CONFERÊNCIA: placeables novos {summary['placeables_new']} "
                      f"(existentes {summary['placeables_existing']}); "
                      f"StoreItems novos {summary['store_new']} "
                      f"(existentes {summary['store_existing']}).")
            if self.to_placeables.get():
                for name,pos,rot in summary["positions"]:
                    self._log(f"POSIÇÃO {name}: X Y Z = {pos}; Rot X Y Z = {rot}")
            if summary["generated_decorative"]:
                self._log("ATENÇÃO: XML decorativo será criado junto ao I3D, "
                          "com ícone PNG. Não cria silo funcional, animações ou triggers.")
            if summary["map_link_changed"]:
                self._log("map.xml será ajustado para apontar ao StoreItems escolhido.")
            if summary["changed"]:
                self._log("Somente PRÉVIA, nenhum arquivo alterado. "
                          "Clique REGISTRAR para efetivar após confirmar.")
            else:
                self._log("Itens já registrados; nenhuma alteração necessária.")
            return summary
        except Exception as exc:
            self.last_preview=None
            self._log("CONFERÊNCIA INTERROMPIDA: "+str(exc))
            messagebox.showerror("TG + EDVALDO",str(exc),parent=self)
            return None

    def register(self):
        if self.last_preview is None or self._selection_signature()!=self.last_preview[0]:
            messagebox.showwarning("TG + EDVALDO","Primeiro clique em CONFERIR. "
                "Se você alterou posição, rotação, caminho ou destino, confira novamente.",
                parent=self)
            return
        try:
            entries,summary=self._plan()
            previous=self.last_preview[1]
            keys=("placeables_new","placeables_existing","store_new",
                  "store_existing","map_link_changed","positions",
                  "generated_decorative")
            if any(summary[k]!=previous[k] for k in keys):
                self.last_preview=None
                raise ValueError("Dados do mapa mudaram depois da prévia. "
                                 "Clique CONFERIR novamente.")
            if not summary["changed"]:
                self._log("Sem alterações; registro já existente.")
                return
            dest=[]
            if self.to_placeables.get():
                dest.append(f"placeables.xml: {summary['placeables_new']} novo(s)")
                dest.append("Posição/rotação: "+str(summary["positions"]))
            if self.to_store.get():
                dest.append(f"storeItems.xml: {summary['store_new']} novo(s)")
            if summary["generated_decorative"]:
                dest.append("GERAR XML DECORATIVO + ícone simples (sem funções de silo!)")
            if summary["map_link_changed"]:
                dest.append("map.xml: referência da loja")
            if not messagebox.askyesno("CONFIRMAR ALTERAÇÃO NO MAPA",
                 "Gravar somente o(s) destino(s) marcados?\n\n"+"\n".join(dest)+
                 "\n\nBackups são criados antes de modificar arquivos existentes.",
                 parent=self):
                self._log("Cancelado; arquivos preservados.")
                return
            backs=export.write_mixed_bundle(entries)
            self.last_preview=None
            self._log("REGISTRADO. Backups: "+(", ".join(map(str,backs)) or
                      "arquivos novos criados, sem originais para backup"))
            messagebox.showinfo("TG + EDVALDO",
                "Registro concluído. Teste o resultado em uma CÓPIA do mapa FS25.",
                parent=self)
        except Exception as exc:
            self.last_preview=None
            self._log("ERRO: "+str(exc))
            messagebox.showerror("TG + EDVALDO",str(exc),parent=self)


class App(PreviousApp):
    def __init__(self):
        super().__init__()
        self.title("TG + EDVALDO | Cercas, Porteiras e PC Objects FS25 v1.4")
        self.log_message("v1.4: PC Objects pode registrar I3D exportado pelo GE "
                         "com posição e rotação editáveis.")

    def open_pcobjects(self):
        if self.pc_window is None or not self.pc_window.winfo_exists():
            self.pc_window=PCObjectsWindow(self)
        else:
            self.pc_window.lift()
            self.pc_window.focus_set()


if __name__=="__main__":
    App().mainloop()
