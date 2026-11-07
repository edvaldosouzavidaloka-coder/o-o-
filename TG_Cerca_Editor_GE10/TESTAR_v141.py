"""Teste Windows: PC Objects em primeiro plano, principal minimizada.

Inclui seletores de arquivo vinculado à janela PC Objects, sem modificar XMLs.
"""
from unittest.mock import patch
from TG_Cerca_Editor_v141 import App


def run():
    app=App()
    try:
        app.update()
        assert app.state()=="normal",(app.state(),app.winfo_geometry())
        app.open_pcobjects()
        w=app.pc_window
        app.update()
        assert w.winfo_exists()
        assert app.state()=="iconic",app.state()
        assert w.state()=="normal",(w.state(),app.state())
        assert w.winfo_viewable(),("PC Objects oculta!",w.state(),app.state())
        print("OK: principal minimizada, PC Objects visível em primeiro plano.")
        called=[]
        def ask(kind):
            def fake(*args,**kwargs):
                assert kwargs.get("parent") is w,kwargs
                assert app.state()=="iconic"
                called.append(kind)
                return ""
            return fake
        with patch("tkinter.filedialog.askdirectory",side_effect=ask("pasta")),\
             patch("tkinter.filedialog.askopenfilename",side_effect=ask("arquivo")),\
             patch("tkinter.filedialog.asksaveasfilename",side_effect=ask("salvar")):
            w._pick(w.maproot,folder=True)
            w._pick(w.object_i3d)
            w._pick(w.storeitems)
        assert called==["pasta","arquivo","salvar"],called
        assert app.state()=="iconic"
        assert w.winfo_exists()
        print("OK: os 3 seletores de arquivo têm PC Objects como pai e mantêm foco.")
        w.close_and_restore()
        app.update()
        assert app.state()=="normal",app.state()
        print("OK: ao fechar PC Objects a principal é restaurada.")
        app.open_pcobjects()
        app.update()
        assert app.state()=="iconic"
        app.pc_window.destroy()
        app.update()
        assert app.state()=="normal"
        print("OK: restaura até se PC Objects for destruída diretamente.")
    finally:
        app.destroy()

if __name__=="__main__":
    run()
    print("TODOS TESTES FOCO JANELAS v1.4.1 PASSARAM")
