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
import TG_PCObjects_Localizador_v12 as locator


class PCObjectsWindow(tk.Toplevel):
    def __init__(self, owner):
        super().__init__(owner)
        self.owner=owner
        self.title("TG + EDVALDO | Adicionar PC Objects no mapa FS25 v1.2")
        self.geometry("1260x800")
        self.minsize(1000,700)
        self.map_i3d=tk.StringVar()
        self.object_i3d=tk.StringVar()
        self.object_xml=tk.StringVar()
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
            kinds=[("Arquivo I3D","*.i3d")] if var in (self.map_i3d,self.object_i3d) else [
                ("Arquivos XML","*.xml")]
            value=filedialog.askopenfilename(filetypes=kinds)
        if value:
            var.set(value)
            if var is self.maproot:
                self.auto_destinations()
            elif var is self.object_xml:
                self.load_direct_xml()

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
        self._line(frame,1,"I3D do MAPA (posição do objeto)",self.map_i3d)
        self._line(frame,2,"I3D do OBJETO (abatedouro/casa/silo)",self.object_i3d)
        self._line(frame,3,"XML do OBJETO (arquivo de configuração)",self.object_xml)
        self._line(frame,4,"Pasta raiz do mapa (modDesc.xml)",self.maproot,True)
        self._line(frame,5,"placeables.xml do MAPA",self.placeables)
        self._line(frame,6,"storeItems.xml do MAPA",self.storeitems)
        row=ttk.Frame(frame)
        row.grid(row=7,column=0,columnspan=3,sticky="ew",pady=5)
        ttk.Button(row,text="Localizar XMLs do mapa",command=self.auto_destinations).pack(side="left",padx=2)
        ttk.Button(row,text="Ler objetos do MAPA",command=self.load_objects).pack(side="left",padx=2)
        ttk.Button(row,text="Encontrar I3D principal do mapa",
                   command=self.load_main_map).pack(side="left",padx=2)
        ttk.Label(row,text="Origem dos XMLs:").pack(side="left",padx=(15,4))
        self.source_combo=ttk.Combobox(row,textvariable=self.source,state="readonly",width=34)
        self.source_combo.pack(side="left",padx=2)
        ttk.Button(row,text="Carregar XMLs da origem",command=self.load_catalog).pack(side="left",padx=3)
        ttk.Button(row,text="Usar XML do OBJETO",command=self.load_direct_xml).pack(side="left",padx=3)
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
        self._log("v1.2: use I3D do MAPA + I3D do OBJETO + XML do OBJETO em campos separados.")
        self._log("Selecionar UM/TODOS carrega a cena se estiver vazia. Só grava com posição encontrada no mapa.")

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

    def load_main_map(self):
        try:
            selected=self.object_i3d.get() or self.map_i3d.get()
            scenes=locator.main_map_scenes(self.maproot.get(),exclude=selected or None)
            if not scenes:
                raise ValueError("Não encontrei I3D principal na pasta do mapa. "
                                 "Selecione manualmente o I3D da cena do mapa.")
            if (self.map_i3d.get() and not self.object_i3d.get()
                    and locator.is_model_i3d(self.map_i3d.get(),self.maproot.get())):
                self.object_i3d.set(self.map_i3d.get())
            self.map_i3d.set(str(scenes[0]))
            self._log("I3D do MAPA escolhido: "+str(scenes[0]))
            return self.load_objects()
        except Exception as exc:
            self._log("Não consegui localizar a cena principal: "+str(exc))
            messagebox.showwarning("PC Objects",str(exc),parent=self)
            return 0

    def load_objects(self):
        try:
            mapfile=Path(self.map_i3d.get().strip()) if self.map_i3d.get().strip() else None
            itemfile=Path(self.object_i3d.get().strip()) if self.object_i3d.get().strip() else None
            # Compatibilidade com usuário que colocou I3D do item no campo do mapa.
            if (mapfile and mapfile.is_file() and itemfile is None
                    and locator.is_model_i3d(mapfile,self.maproot.get())):
                itemfile=mapfile
                self.object_i3d.set(str(itemfile))
                mapfile=None
                self.map_i3d.set("")
                self._log("I3D do objeto reconhecido; procurando I3D principal do mapa.")
            if itemfile and not itemfile.is_file():
                raise ValueError("I3D do OBJETO não encontrado: "+str(itemfile))
            if mapfile is None and itemfile is not None:
                scenes=locator.main_map_scenes(self.maproot.get(),exclude=itemfile)
                if not scenes:
                    raise ValueError("Não localizei a cena principal do mapa. "
                                     "Escolha o I3D do MAPA no primeiro campo.")
                mapfile=scenes[0]
                self.map_i3d.set(str(mapfile))
                self._log("Cena principal do mapa identificada: "+str(mapfile))
            if mapfile is None or not mapfile.is_file():
                raise ValueError("Informe o I3D do MAPA no primeiro campo. "
                                 "O I3D do objeto sozinho não contém sua localização no mapa.")
            if itemfile is not None:
                self.entries=locator.find_model_in_scene(mapfile,itemfile)
                if not self.entries:
                    self.assignment={}
                    self._reload()
                    self._log(f"Não achei a importação de {itemfile.name} em {mapfile.name}.")
                    messagebox.showwarning("PC Objects — localização não encontrada",
                        "Não achei referência ou grupo correspondente ao I3D do OBJETO "
                        "dentro do I3D do MAPA. Confira se ele foi importado e "
                        "posicionado no GIANTS Editor. Não vou inventar coordenadas.",
                        parent=self)
                    return 0
                self._log(f"Encontrei {len(self.entries)} instância(s) de "
                          f"{itemfile.name} posicionada(s) em {mapfile.name}.")
            else:
                self.entries=pc.scan_map_i3d(mapfile)
                if not self.entries:
                    self.assignment={}
                    self._reload()
                    self._log("Nenhuma Reference/grupo de placeable foi encontrado no I3D do MAPA.")
                    messagebox.showwarning("PC Objects — lista vazia",
                        "Não encontrei objetos importados nesse I3D do mapa. "
                        "Se você quer adicionar um abatedouro, preencha também "
                        "I3D do OBJETO e clique Ler objetos do MAPA.",
                        parent=self)
                    return 0
            self.assignment={}
            self._reload()
            self._log(f"Objetos disponíveis: {len(self.entries)}.")
            if self.object_xml.get().strip():
                self.load_direct_xml(silent=True)
            else:
                self.autolink()
            return len(self.entries)
        except Exception as exc:
            self.entries=[]
            self.assignment={}
            self._reload()
            self._log("ERRO ao ler I3D: "+str(exc))
            messagebox.showerror("PC Objects",str(exc),parent=self)
            return 0

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
            byid={v["id"]:v for v in self.inventory}
            for item in found:
                byid[item["id"]]=item
            self.inventory=list(byid.values())
            self._update_xml_options()
            self._log(f"{len(found)} XML(s) placeable com modelo I3D encontrados em {self.source.get()}.")
            if not found:
                self._log("Se o XML do abatedouro não apareceu, selecione-o no campo "
                          "'XML do OBJETO' e clique 'Usar XML do OBJETO'.")
            self.autolink()
        except Exception as exc:
            self._log("ERRO catálogo XML: "+str(exc))
            messagebox.showerror("PC Objects",str(exc),parent=self)

    def _update_xml_options(self):
        values=sorted(self.inventory,key=lambda x:(x["mod"].casefold(),x["xml"]))
        options=[x["mod"]+" | "+x["xml"]+" ["+x["id"]+"]" for x in values]
        self._option_ids={options[i]:item["id"] for i,item in enumerate(values)}
        self.xml_combo["values"]=options

    def load_direct_xml(self,silent=False):
        try:
            chosen=self.object_xml.get().strip()
            if not chosen:
                if not silent:
                    raise ValueError("Escolha o XML de configuração do OBJETO (abatedouro, casa, silo).")
                return None
            item=pc.placeable_item_from_xml(chosen,self.maproot.get(),self.owner.mods)
            current={i["id"]:i for i in self.inventory}
            current[item["id"]]=item
            self.inventory=list(current.values())
            self._update_xml_options()
            option=next(k for k,v in self._option_ids.items() if v==item["id"])
            self.xml_choice.set(option)
            chosen_ids={x["id"] for x in self._selected_objects()}
            if not chosen_ids and self.object_i3d.get().strip():
                chosen_ids={x["id"] for x in self.entries
                            if x.get("object_i3d","")==str(Path(self.object_i3d.get()).resolve())}
            if not chosen_ids and len(self.entries)==1:
                chosen_ids={self.entries[0]["id"]}
            if chosen_ids:
                for ident in chosen_ids:
                    self.assignment[ident]=item["id"]
            self._reload()
            self._log(f"XML do OBJETO carregado: {item['xml']} "
                      f"({item['type']}); associado a {len(chosen_ids)} instância(s).")
            if not chosen_ids:
                self._log("Agora selecione UM ou TODOS e clique Associar XML aos selecionados.")
            return item
        except Exception as exc:
            self._log("ERRO no XML do objeto: "+str(exc))
            if not silent:
                messagebox.showerror("PC Objects",str(exc),parent=self)
            return None

    def autolink(self):
        if self.object_xml.get().strip():
            direct=self.load_direct_xml(silent=True)
            if direct is not None:
                return
        if not self.inventory:
            self._log("Nenhum XML de objeto carregado. Escolha 'XML do OBJETO' "
                      "ou carregue XMLs da pasta do mapa/mod.")
            return
        matches=pc.auto_match(self.entries,self.inventory)
        fresh=0
        for k,v in matches.items():
            if k not in self.assignment:
                self.assignment[k]=v
                fresh+=1
        self._reload()
        self._log(f"{fresh} associação(ões) automáticas. "
                  "Se encontrou zero, escolha o XML do objeto diretamente.")

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
        if not self.entries and not self.load_objects():
            return
        self.table.selection_set(self.table.get_children())
        self._log(f"Selecionados todos os {len(self.entries)} objetos.")

    def select_one(self):
        if not self.entries and not self.load_objects():
            return
        kids=self.table.get_children()
        if not kids:
            self._log("Não há objetos na lista. Selecione o I3D principal do mapa.")
            return
        selected=self.table.selection()
        focus=self.table.focus()
        if not focus or focus not in kids:
            focus=selected[0] if selected else kids[0]
        self.table.selection_set((focus,))
        self.table.focus(focus)
        self.table.see(focus)
        self._log("Selecionado UM objeto: "+str(self.table.item(focus,"values")[0]))

    def register(self):
        try:
            selected=self._selected_objects()
            if not selected:
                if not self.entries:
                    self.load_objects()
                raise ValueError("Não há objeto selecionado. Primeiro carregue a cena "
                                 "com o botão 'Ler objetos do I3D' ou "
                                 "'Encontrar I3D principal do mapa'; em seguida "
                                 "use Selecionar UM ou TODOS.")
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
