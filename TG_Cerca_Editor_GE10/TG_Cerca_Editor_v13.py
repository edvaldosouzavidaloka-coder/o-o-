"""TG + EDVALDO v1.3 — janelas de PC Objects com destino independente.

SEM botões UM/TODOS. Selecionar XML só prepara dados. O usuário marca
explicitamente placeables e/ou StoreItems, confere e confirma o registro.
O editor de cercas/porteiras v0.9.1 permanece herdado sem mudanças.
"""
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox
from xml.etree import ElementTree as ET

from TG_Cerca_Editor_v11 import App as PreviousApp, PCObjectsWindow as PreviousWindow
import TG_PCObjects_Registros_v13 as registry
import TG_PCObjects_Core_v11 as pc


class PCObjectsWindow(PreviousWindow):
    def __init__(self,owner):
        super().__init__(owner)
        self.title("TG + EDVALDO | PC Objects v1.3 — Registro independente")
        self.to_placeables=tk.BooleanVar(value=False)
        self.to_store=tk.BooleanVar(value=False)
        self.last_preview=None
        frame=self.log.master
        actions=frame.grid_slaves(row=11)[0]
        for child in actions.winfo_children():
            child.destroy()
        ttk.Label(actions,text="Escolha O QUE deseja registrar:").pack(side="left",padx=(3,12))
        ttk.Checkbutton(actions,text="No placeables.xml (posição no mapa)",
                        variable=self.to_placeables).pack(side="left",padx=6)
        ttk.Checkbutton(actions,text="No storeItems.xml (loja)",
                        variable=self.to_store).pack(side="left",padx=6)
        actions2=frame.grid_slaves(row=12)[0]
        for child in actions2.winfo_children():
            child.destroy()
        ttk.Button(actions2,text="1. CONFERIR (não grava)",
                   command=self.preview_registration).pack(side="left",padx=5,pady=5)
        ttk.Button(actions2,text="2. REGISTRAR nos XMLs MARCADOS",
                   command=self.register).pack(side="left",padx=12,pady=5)
        # Remover os botões que confundiam sem deletar outras funções do projeto.
        bar=frame.grid_slaves(row=7)[0]
        for child in bar.winfo_children():
            label=""
            try:
                label=child.cget("text")
            except tk.TclError:
                pass
            if label in ("Origem dos XMLs:","Carregar XMLs da origem",
                         "Associar automaticamente"):
                child.pack_forget()
            elif child is self.source_combo:
                child.pack_forget()
        self.table.configure(selectmode="none")
        ttk.Label(frame,text="Carregar o XML não registra nada. Marque só o destino "
                  "desejado. Para StoreItems sozinho NÃO precisa de I3D nem placeables.",
                  wraplength=1180).grid(row=9,column=0,columnspan=3,sticky="w",pady=(3,2))
        self._log("v1.3: registros INDEPENDENTES e MANUAIS.")
        self._log("Marque placeables, StoreItems ou ambos; clique CONFERIR e só depois REGISTRAR.")
        self._log("Plantas comuns de vegetação não são storeItems sem XML próprio de item comprável.")

    def _reload(self):
        self.table.delete(*self.table.get_children())
        chosen=Path(self.object_xml.get().strip()).name if self.object_xml.get().strip() else "(XML não escolhido)"
        for obj in self.entries:
            self.table.insert("","end",iid=obj["id"],
                 values=(obj["name"]," ".join("%.3f"%v for v in obj["position"]),
                         obj["kind"],chosen,obj.get("reference","")))

    def load_direct_xml(self,silent=False):
        """Apenas verifica e mostra XML escolhido; NÃO associa/grava nada."""
        chosen=self.object_xml.get().strip()
        if not chosen:
            if not silent:
                messagebox.showwarning("PC Objects","Selecione o XML do OBJETO.",parent=self)
            return None
        try:
            path=Path(chosen)
            if not path.is_file():
                raise ValueError("XML do OBJETO não encontrado.")
            root=ET.parse(path).getroot()
            if not root.get("type"):
                self._log(f"XML {path.name}: sem atributo type; talvez não seja item da loja.")
            else:
                self._log(f"XML carregado: {path.name} <{root.tag} type='{root.get('type')}'>. "
                          "Nenhum arquivo do mapa foi alterado.")
            self._reload()
            return root
        except Exception as exc:
            self._log("Erro ao conferir XML do objeto: "+str(exc))
            if not silent:
                messagebox.showerror("PC Objects",str(exc),parent=self)
            return None

    def autolink(self):
        # Somente para manter a compatibilidade com o leitor legado; sem escrita.
        self._log("v1.3: escolha XML do OBJETO e destino do registro. "
                  "Não há associação automática obrigatória.")

    def _selection_signature(self):
        return (self.maproot.get().strip(),self.object_xml.get().strip(),
                self.map_i3d.get().strip(),self.object_i3d.get().strip(),
                self.placeables.get().strip(),self.storeitems.get().strip(),
                self.to_placeables.get(),self.to_store.get())

    def _plan(self):
        return registry.plan_selected_registration(
            maproot=self.maproot.get().strip(),
            object_xml=self.object_xml.get().strip(),
            placeables_path=self.placeables.get().strip(),
            storeitems_path=self.storeitems.get().strip(),
            map_i3d=self.map_i3d.get().strip(),
            object_i3d=self.object_i3d.get().strip(),
            do_placeables=self.to_placeables.get(),
            do_store=self.to_store.get(),
            mods=self.owner.mods)

    def preview_registration(self):
        try:
            entries,summary=self._plan()
            self.last_preview=(self._selection_signature(),summary.copy())
            self._log("CONFERÊNCIA: placeables novos = "
                      f"{summary['placeables_new']}, já existentes = {summary['placeables_existing']}; "
                      f"StoreItems novos = {summary['store_new']}, já existentes = {summary['store_existing']}.")
            if self.to_placeables.get():
                self._log(f"Posições encontradas no mapa: {len(summary['positions'])}.")
            if summary["map_link_changed"]:
                self._log("StoreItems selecionado: também será corrigida a referência no map.xml.")
            if not summary["changed"]:
                self._log("Tudo já está cadastrado. Nenhuma gravação necessária.")
            else:
                self._log("MODO CONFERIR: não gravei nada. Para efetivar, clique REGISTRAR.")
            return summary
        except Exception as exc:
            self.last_preview=None
            self._log("CONFERÊNCIA INTERROMPIDA: "+str(exc))
            messagebox.showerror("TG + EDVALDO | PC Objects",str(exc),parent=self)
            return None

    def register(self):
        """Somente através do botão explícito com destinos marcados."""
        if self.last_preview is None or self._selection_signature()!=self.last_preview[0]:
            messagebox.showwarning("PC Objects",
                "Marque o(s) destino(s) e clique primeiro em "
                "CONFERIR. Alterações nas escolhas exigem uma nova conferência.",
                parent=self)
            return
        try:
            entries,summary=self._plan()
            previous=self.last_preview[1]
            if any(summary[k]!=previous[k] for k in
                   ("placeables_new","placeables_existing","store_new","store_existing",
                    "map_link_changed","positions")):
                self.last_preview=None
                raise ValueError("Os arquivos ou posições mudaram após a conferência. "
                                 "Clique CONFERIR novamente.")
            if not summary["changed"]:
                self._log("Nada a gravar: o(s) registro(s) já existem.")
                return
            destinations=[]
            if self.to_placeables.get():
                destinations.append(f"placeables.xml: {summary['placeables_new']} posição(ões) nova(s)")
            if self.to_store.get():
                destinations.append(f"storeItems.xml: {summary['store_new']} item(ns) novo(s)")
                if summary["map_link_changed"]:
                    destinations.append("map.xml: atualizar caminho do StoreItems")
            explanation="\n".join(destinations)
            if not messagebox.askyesno("CONFIRMAR REGISTRO",
                    "Gravar SOMENTE os destinos marcados?\n\n"+explanation+
                    "\n\nSerão feitos backups antes de modificar arquivos.",
                    parent=self):
                self._log("Gravação cancelada. Nenhum arquivo alterado.")
                return
            backups=pc.write_map_bundle(entries)
            self.last_preview=None
            self._log("REGISTRADO. Arquivos de backup: "+(", ".join(map(str,backups)) or "nenhum arquivo anterior"))
            messagebox.showinfo("TG + EDVALDO",
                "Registro concluído apenas nos XMLs escolhidos. Teste o mapa no FS25.",
                parent=self)
        except Exception as exc:
            self.last_preview=None
            self._log("ERRO AO REGISTRAR: "+str(exc))
            messagebox.showerror("TG + EDVALDO",str(exc),parent=self)


class App(PreviousApp):
    def __init__(self):
        super().__init__()
        self.title("TG + EDVALDO | Cercas, Porteiras e PC Objects FS25 v1.3")
        self.log_message("v1.3: PC Objects com placeables e StoreItems separados, "
                         "somente mediante seleção e confirmação.")

    def open_pcobjects(self):
        if self.pc_window is None or not self.pc_window.winfo_exists():
            self.pc_window=PCObjectsWindow(self)
        else:
            self.pc_window.lift()
            self.pc_window.focus_set()


if __name__=="__main__":
    App().mainloop()
