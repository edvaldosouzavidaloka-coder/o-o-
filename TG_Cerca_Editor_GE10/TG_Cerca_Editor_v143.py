"""TG + EDVALDO FS25 v1.4.3 — ajuste automático dos segmentos em curva.

Preserva completamente a janela v1.4.2, porteira, demolição e PC Objects.
A distribuição dos postes deixa de dividir toda a curva igualmente e
passa a ajustar cada vão individualmente, respeitando maxScale do mod.
"""
from TG_Cerca_Editor_v142 import App as PreviousApp


class App(PreviousApp):
    def __init__(self):
        super().__init__()
        self.title("TG + EDVALDO | Cercas, Porteiras e PC Objects FS25 v1.4.3")
        self.log_message("v1.4.3: AUTOAJUSTE de segmentos na curva — "
                         "não precisa dividir a spline manualmente.")
        self.log_message("Os postes são distribuídos em vãos de tamanho real "
                         "do painel do mod (3,8 / 4 / 6,7m), "
                         "respeitando o limite maxScale.")
        self.log_message("Em curva muito fechada, avisa sem gravar XML. "
                         "Porteira, animação, demolição e PC Objects preservados.")


if __name__=="__main__":
    App().mainloop()
