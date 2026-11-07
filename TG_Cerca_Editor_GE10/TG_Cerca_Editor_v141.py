"""TG + EDVALDO v1.4.1 — foco das janelas no Windows.

Ao abrir PC Objects, minimiza a janela principal. Após o seletor de arquivos
foca novamente PC Objects. Ao fechar PC Objects restaura a principal.
Não altera o gerador de cercas, lugar/rotação de objetos nem os registros XML.
"""
import tkinter as tk
from TG_Cerca_Editor_v14 import App as PreviousApp
from TG_Cerca_Editor_v14 import PCObjectsWindow as PreviousPCWindow


class PCObjectsWindow(PreviousPCWindow):
    def __init__(self, owner):
        super().__init__(owner)
        self.title("TG + EDVALDO | PC Objects v1.4.1 — I3D exportado")
        self.protocol("WM_DELETE_WINDOW", self.close_and_restore)

    def _front(self):
        if not self.winfo_exists():
            return
        self.deiconify()
        self.lift()
        try:
            self.focus_force()
        except tk.TclError:
            pass

    def close_and_restore(self):
        self.destroy()

    def destroy(self):
        """Também restaura janela principal se fechado sem clicar no X."""
        owner=self.owner
        if self.winfo_exists():
            super().destroy()
        try:
            if owner.winfo_exists() and owner.state() in ("iconic","withdrawn"):
                owner.deiconify()
                owner.lift()
                owner.focus_force()
        except tk.TclError:
            pass


class App(PreviousApp):
    def __init__(self):
        super().__init__()
        self.title("TG + EDVALDO | Cercas, Porteiras e PC Objects FS25 v1.4.1")
        self.log_message("v1.4.1: janela principal minimizada durante PC Objects; "
                         "seletores de arquivo pertencem à janela PC Objects.")

    def open_pcobjects(self):
        if self.pc_window is None or not self.pc_window.winfo_exists():
            # Minimizar ANTES de abrir PC Objects evita que a janela principal
            # seja escolhida pelo Windows como janela da frente.
            self.iconify()
            try:
                self.pc_window=PCObjectsWindow(self)
            except Exception:
                self.deiconify()
                raise
        else:
            if self.state()=="normal":
                self.iconify()
        self.pc_window._front()
        # Reforço para o gerenciador de janelas após mapear o novo Toplevel.
        self.pc_window.after_idle(self.pc_window._front)


if __name__=="__main__":
    App().mainloop()
