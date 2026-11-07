"""TG + EDVALDO v1.1: botão PC Objects sem mexer no criador de cercas.

Lê importações posicionadas no I3D do MAPA (não spline), associa cada
instância a um XML de placeable real e atualiza placeables.xml + storeItems.xml.
"""
from __future__ import annotations
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import xml.etree.ElementTree as ET

from TG_Cerca_Editor_v09 import App as FenceApp
import TG_PCObjects_Core_v11 as pc


class PCObjectsWindow(tk.Toplevel):
    def __init__(self, owner):
        super().__init__(owner)
        self.owner=owner
        self.title("TG + EDVALDO | Adicionar PC Objects no mapa FS25")
        self.geometry("1260x800")
        self.minsize(1000,700)
        self.map_i3d=tk.StringVar()
        self.maproot=tk.StringVar()
        self.placeables=tk.StringVar()
        self.storeitems=tk.StringVar()
        self.source=tk.StringVar()
        self.xml_choice=tk.StringVar()
        self.filter_text=tk.StringVar()
        self.entries=[]
        self.inventory=[]
        self.assignment={}
        self.shown={}
        self.source_options={}
        self.preview_data=None
        self.dryrun=tk.BooleanVar(value=True)
        self._build()
        self._refresh_source_options()
        self.protocol("WM_DELETE_WINDOW",self.destroy)

    def _pick(self,var,folder=False):
        if folder:
            value=filedialog.askdirectory(title="Selecione a pasta raiz do mapa")
        elif var is self.storeitems:
            value=filedialog.asksaveasfilename(title="Escolher/criar storeItems.xml",
                defaultextension=".xml",filetypes=[("XML","*.xml")])
        else:
            kinds=[("Arquivos XML","*.xml")] if var is not self.map_i3d else [
                ("Cena do mapa I3D","*.i3d")]
            value=filedialog.askopenfilename(filetypes=kinds)
        if value:
            var.set(value)
            if var is self.maproot:
                self.auto_destinations()

    def auto_destinations(self):
        try:
            place,store,main=pc.guess_map_xml_paths(self.maproot.get())
            if place and not self.placeables.get():
                self.placeables.set(place)
            if store and not self.storeitems.get():
                self.storeitems.set(store)
            if main:
                self._log("map.xml identificado: "+str(main))
            else:
                self._log("Não encontrei o map.xml no modDesc. Confira a pasta raiz.")
        except Exception as exc:
            self._log("Auto detectar: "+str(exc))

    def _line(self,parent,row,title,var,folder=False):
        ttk.Label(parent,text=title).grid(row=row,column=0,sticky="w",padx=5,pady=3)
        ttk.Entry(parent,textvariable=var).grid(row=row,column=1,sticky="ew",padx=5,pady=3)
        ttk.Button(parent,text="Selecionar",command=lambda:self._pick(var,folder)).grid(
            row=row,column=2,padx=5,pady=3)

    def _build(self):
        self.configure(bg="#13251e")
        frame=ttk.Frame(self,padding=12)
        frame.pack(fill="both",expand=True)
        frame.columnconfigure(1,weight=1)
        frame.rowconfigure(10,weight=1)
        ttk.Label(frame,text="TG + EDVALDO — PC OBJECTS",font=("Segoe UI",16,"bold")).grid(
            row=0,column=0,columnspan=3,sticky="w",pady=(0,8))
        self._line(frame,1,"I3D do mapa (sem spline)",self.map_i3d)
        self._line(frame,2,"Pasta raiz do mapa (modDesc.xml)",self.maproot,True)
        self._line(frame,3,"placeables.xml do MAPA",self.placeables)
        self._line(frame,4,"storeItems.xml do MAPA",self.storeitems)
        row=ttk.Frame(frame)
        row.grid(row=5,column=0,columnspan=3,sticky="ew",pady=5)
        ttk.Button(row,text="Localizar XMLs do mapa",command=self.auto_destinations).pack(side="left",padx=2)
        ttk.Button(row,text="Ler objetos do I3D",command=self.load_objects).pack(side="left",padx=2)
        ttk.Label(row,text="Origem dos XMLs:").pack(side="left",padx=(15,4))
        self.source_combo=ttk.Combobox(row,textvariable=self.source,state="readonly",width=34)
        self.source_combo.pack(side="left",padx=2)
        ttk.Button(row,text="Carregar XMLs da origem",command=self.load_catalog).pack(side="left",padx=3)
        ttk.Button(row,text="Associar automaticamente",command=self.autolink).pack(side="left",padx=3)
        tableframe=ttk.Frame(frame)
        tableframe.grid(row=10,column=0,columnspan=3,sticky="nsew",pady=6)
        tableframe.columnconfigure(0,weight=1)
        tableframe.rowconfigure(0,weight=1)
        self.table=ttk.Treeview(tableframe,columns=("name","where","type","xml","source"),
                                show="headings",selectmode="extended")
        for key,label,size in (("name","Objeto importado",210),
                               ("where","Posição X Y Z",230),("type","Origem no I3D",120),
                               ("xml","XML associado",320),("source","Arquivo I3D",270)):
            self.table.heading(key,text=label)
            self.table.column(key,width=size,stretch=key in ("name","xml","source"))
        self.table.grid(row=0,column=0,sticky="nsew")
        bar=ttk.Scrollbar(tableframe,orient="vertical",command=self.table.yview)
        bar.grid(row=0,column=1,sticky="ns")
        self.table.configure(yscrollcommand=bar.set)
        actions=ttk.Frame(frame)
        actions.grid(row=11,column=0,columnspan=3,sticky="ew",pady=6)
        ttk.Button(actions,text="Selecionar TODOS",command=self.select_all).pack(side="left",padx=3)
        ttk.Button(actions,text="Selecionar UM",command=self.select_one).pack(side="left",padx=3)
        ttk.Label(actions,text="XML do objeto:").pack(side="left",padx=(15,5))
        self.xml_combo=ttk.Combobox(actions,textvariable=self.xml_choice,state="readonly",width=52)
        self.xml_combo.pack(side="left",padx=4)
        ttk.Button(actions,text="Associar XML aos selecionados",command=self.link_selected).pack(side="left",padx=4)
        actions2=ttk.Frame(frame)
        actions2.grid(row=12,column=0,columnspan=3,sticky="ew",pady=8)
        ttk.Checkbutton(actions2,text="Somente conferir / prévia (não altera arquivos)",
                        variable=self.dryrun).pack(side="left",padx=4)
        ttk.Button(actions2,text="Conferir / Adicionar PC Objects",
                   command=self.register).pack(side="left",padx=20)
        ttk.Label(frame,text="O programa registra o XML real do placeable, não a malha I3D isolada. "
                  "Pasta do mod e caminhos precisam existir; use cópia do mapa.",
                  wraplength=1180).grid(row=13,column=0,columnspan=3,sticky="w",pady=(0,4))
        self.log=tk.Text(frame,height=6,bg="#091a13",fg="#e4f5e8",
                         font=("Consolas",10),wrap="word")
        self.log.grid(row=14,column=0,columnspan=3,sticky="ew",pady=4)
        self._log("Selecione o I3D do mapa e os dois arquivos XML. O botão seleciona um ou todos.")

    def _log(self,value):
        self.log.insert("end",str(value)+"\n")
        self.log.see("end")

    def _refresh_source_options(self):
        options={"[XMLs dentro da pasta do MAPA]":("map",None)}
        for name,path in sorted(self.owner.mods.items()):
            options[name]=("mod",path)
        self.source_options=options
        self.source_combo["values"]=list(options)
        if not self.source.get() or self.source.get() not in options:
            self.source.set(next(iter(options)))

    def _selected_objects(self):
        ids=set(self.table.selection())
        return [x for x in self.entries if x["id"] in ids]

    def _item_by_id(self):
        return {x["id"]:x for x in self.inventory}

    def _reload(self):
        prior=self.table.selection()
        self.table.delete(*self.table.get_children())
        catalog=self._item_by_id()
        for obj in self.entries:
            mapped=catalog.get(self.assignment.get(obj["id"],""))
            label=(mapped["mod"]+"/"+mapped["xml"]) if mapped else "PENDENTE: associar XML"
            self.table.insert("", "end",iid=obj["id"],
                    values=(obj["name"]," ".join("%.3f"%v for v in obj["position"]),
                            obj["kind"],label,obj.get("reference","")))
        self.table.selection_set([k for k in prior if self.table.exists(k)])

    def load_objects(self):
        try:
            self.entries=pc.scan_map_i3d(self.map_i3d.get())
            self.assignment={}
            self._reload()
            self._log(f"Encontrados {len(self.entries)} objetos importados/candidatos no I3D.")
            if not self.entries:
                self._log("Nenhum Reference ou grupo com nome de placeable encontrado. "
                          "Confira se os objetos foram importados no GE.")
        except Exception as exc:
            messagebox.showerror("PC Objects",str(exc),parent=self)

    def load_catalog(self):
        try:
            if not self.source_options:
                self._refresh_source_options()
            kind,source=self.source_options[self.source.get()]
            if kind=="map":
                source=self.maproot.get()
            if not source:
                raise ValueError("Selecione a pasta raiz do mapa.")
            found=pc.source_inventory(Path(source),kind)
            old={v["id"]:v for v in self.inventory}
            for item in found:
                old[item["id"]]=item
            self.inventory=list(old.values())
            values=sorted(self.inventory,key=lambda x:(x["mod"].casefold(),x["xml"]))
            self.xml_combo["values"]=[
                x["mod"]+" | "+x["xml"]+" ["+x["id"]+"]" for x in values]
            self._option_ids={x["mod"]+" | "+x["xml"]+" ["+x["id"]+"]":x["id"]
                              for x in values}
            self._log(f"{len(found)} XML(s) placeable válidos encontrados em {self.source.get()}.")
            self.autolink()
        except Exception as exc:
            messagebox.showerror("PC Objects",str(exc),parent=self)

    def autolink(self):
        matches=pc.auto_match(self.entries,self.inventory)
        fresh=0
        for k,v in matches.items():
            if k not in self.assignment:
                self.assignment[k]=v
                fresh+=1
        self._reload()
        self._log(f"{fresh} associação(ões) automáticas sem ambiguidade. "
                  "Associe manualmente os restantes.")

    def link_selected(self):
        selected=self._selected_objects()
        item_id=getattr(self,"_option_ids",{}).get(self.xml_choice.get())
        if not selected:
            messagebox.showwarning("PC Objects","Selecione um ou vários objetos na tabela.",parent=self)
            return
        if not item_id:
            messagebox.showwarning("PC Objects","Selecione um XML real do mod.",parent=self)
            return
        for obj in selected:
            self.assignment[obj["id"]]=item_id
        self._reload()
        self._log(f"XML associado a {len(selected)} objeto(s) selecionado(s).")

    def select_all(self):
        self.table.selection_set(self.table.get_children())
        self._log(f"Selecionados todos os {len(self.entries)} objetos.")

    def select_one(self):
        focus=self.table.focus()
        if not focus:
            kids=self.table.get_children()
            focus=kids[0] if kids else None
        if focus:
            self.table.selection_set((focus,))
            self.table.focus(focus)
        self._log("Apenas um objeto selecionado.")

    def register(self):
        try:
            selected=self._selected_objects()
            if not selected:
                raise ValueError("Selecione UM ou TODOS os objetos antes de registrar.")
            placeables=Path(self.placeables.get())
            stores=Path(self.storeitems.get())
            maproot=Path(self.maproot.get())
            if not (maproot/"modDesc.xml").is_file():
                raise ValueError("Selecione a pasta raiz do MAPA, com modDesc.xml.")
            if not placeables.resolve().is_relative_to(maproot.resolve()):
                raise ValueError("O placeables.xml precisa ficar dentro da pasta do mapa.")
            if not stores.resolve().is_relative_to(maproot.resolve()):
                raise ValueError("O storeItems.xml precisa ficar dentro da pasta do mapa.")
            a,b,summary=pc.make_map_updates(selected,self.assignment,self.inventory,
                                             placeables,stores)
            mapxml,config_tree,change_link=pc.prepare_map_config(maproot,stores)
            self._log(f"Prévia: {len(summary['inserted'])} objeto(s) novos, "
                      f"{len(summary['already'])} já registrados, "
                      f"{len(summary['stores'])} referência(s) novas na loja.")
            if change_link:
                self._log("map.xml: a referência StoreItems será corrigida automaticamente.")
            if self.dryrun.get():
                self._log("SOMENTE PRÉVIA: arquivos não foram alterados.")
                return
            if not (summary["inserted"] or summary["stores"] or change_link):
                self._log("Nada a atualizar: objetos e registros já estão presentes.")
                return
            if not messagebox.askyesno("Confirmar PC Objects",
                      f"Registrar {len(summary['inserted'])} objeto(s) no placeables.xml "
                      f"e {len(summary['stores'])} entrada(s) no storeItems.xml?\n"
                      +("Também corrigir a referência no map.xml.\n" if change_link else "")
                      +"Backups automáticos antes de gravar. Prosseguir?",
                      parent=self):
                return
            entries=[(placeables,a),(stores,b)]
            if change_link:
                entries.append((mapxml,config_tree))
            backups=pc.write_map_bundle(entries)
            self._log("Arquivos atualizados. Backups: "+", ".join(str(p) for p in backups))
            messagebox.showinfo("TG + EDVALDO",
                "Placeables e StoreItems gravados com backup. Teste o mapa no FS25.",
                parent=self)
        except Exception as exc:
            self._log("ERRO: "+str(exc))
            messagebox.showerror("PC Objects",str(exc),parent=self)


class App(FenceApp):
    def __init__(self):
        super().__init__()
        self.title("TG + EDVALDO | Cercas, Porteiras e PC Objects FS25 v1.1")
        frame=self.log.master
        ttk.Button(frame,text="ADICIONAR PC OBJECTS",
                   command=self.open_pcobjects).grid(row=1,column=1,sticky="ew",padx=6)
        self.pc_window=None
        self.log_message("v1.1: novo botão ADICIONAR PC OBJECTS. Cercas e porteiras preservadas.")

    def open_pcobjects(self):
        if self.pc_window is None or not self.pc_window.winfo_exists():
            self.pc_window=PCObjectsWindow(self)
        else:
            self.pc_window.lift()
            self.pc_window.focus_set()


if __name__=="__main__":
    App().mainloop()
