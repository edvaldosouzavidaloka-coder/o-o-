# TOP GAMERS — Cercas FS25 v0.5 (I3D e XML compacto) — BETA

Esta versão usa a spline **I3D** exportada do GIANTS Editor 10.0.14, acompanhada do arquivo `.i3d.shapes`. **Não usa CSV.**

## Ajuste para reduzir linhas `<segment>` no placeables.xml

Na janela do aplicativo, o campo **Trecho máximo no XML (m)** vem com **25 metros**.

- Trechos retos são agrupados: uma cerca reta de 500 m, por exemplo, gera por volta de 20 elementos `<segment>` no XML, em vez de 125 para um painel de 4 m.
- Curvas, mudanças de direção e desníveis usam divisões adicionais para não aproximar o traçado por uma reta indevida.
- O comprimento real do **painel/poste** é determinado pelo XML do `FS25_Brazilian_fences`, e não pela quantidade de linhas `<segment>`.
- Tolerância horizontal padrão: 0,35 m; de altura: 0,18 m. Ajuste com cuidado.
- Recomendo 20–30 m para o máximo no XML ao começar. Se houver curvas fechadas, diminua para 10–15 m.

## Como testar

1. Exporte **apenas a spline selecionada** para `.i3d` pelo GIANTS Editor. Deixe `.i3d.shapes` ao lado.
2. Abra `TOP_GAMERS_Cercas_FS25_v05_I3D.exe` fora da pasta mods.
3. Selecione a pasta mods, o ZIP do Brazilian Fences e seu XML nativo de cerca.
4. Selecione o arquivo I3D e o `placeables.xml` **de uma cópia de savegame**.
5. Mantenha **Só conferir/prévia** selecionado e clique **Conferir/Gerar XML**.
6. Compare o número de segmentos gerados. Desmarque a prévia apenas depois de avaliar.
7. Abra o FS25 com o mod ativo e verifique fios, porteiras e demolição em terreno comprado.

## Atenção

- Diminuir os registros XML não significa reduzir na mesma proporção a quantidade de painéis desenhados pelo jogo.
- O sistema de cerca FS25 faz os painéis conforme o modelo nativo. Visual, arames e colisões dependem do ZIP do mod.
- O FS25 usa destruição por nó para cercas nativas, mas remoção/venda por trechos ainda precisa ser testada no mapa e depende da propriedade do terreno.
- Splines cúbicas extraídas de I3D são interpoladas por aproximação dos pontos de controle; curvas podem diferir do GE.
- O executável não modifica o ZIP do mod, nem o `storeItems.xml`; ele oferece prévia e backup antes de gravar o `placeables.xml`.
- **Versão beta**: testar no FS25 antes de qualquer uso no mapa principal.
