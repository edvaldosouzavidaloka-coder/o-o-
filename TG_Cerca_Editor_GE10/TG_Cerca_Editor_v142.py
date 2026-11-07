"""TG + EDVALDO v1.4.2 — fios e porteira alinhados.

Herda toda a interface v1.4.1: cercas, PC Objects, loja, janela minimizada,
porteira por clique, backup, demolição. Altera SOMENTE o cálculo da cerca.
"""
from pathlib import Path

from TG_Cerca_Editor_v141 import App as PreviousApp
from TG_Cerca_Geometria_Nativa_v142 import gate_span,segment_profile


class App(PreviousApp):
    def __init__(self):
        super().__init__()
        self.title("TG + EDVALDO | Cercas, Porteiras e PC Objects FS25 v1.4.2")
        self.log_message("v1.4.2: segmento da cerca com comprimento REAL do painel "
                         "(3,8 / 4 / 6,7m conforme o XML).")
        self.log_message("Não cria segmentos de 2m quando o painel é maior: "
                         "evita postes sem fios.")
        self.log_message("Abertura da porteira usa a largura física do I3D quando "
                         "o mod a informa incorretamente. Em curva fechada, "
                         "a geração é bloqueada para evitar porta atravessada.")
        self.log_message("O campo 'Trecho máximo (80m)' permanece visualmente "
                         "igual, mas o gerador respeita somente a escala do painel.")

    def _gate_width(self):
        """Prévia 2D usa mesmo comprimento que será gerado no XML."""
        mod=self.mods.get(self.fencemod.get())
        xml=self.fencexml.get()
        gate=self.native_gate.get()
        if mod is None or not xml or not gate or gate=="(sem porteira)":
            return None,None
        width,source=gate_span(Path(mod),xml,gate)
        panel,scale,_=segment_profile(Path(mod),xml)
        return width,panel


if __name__=="__main__":
    App().mainloop()
