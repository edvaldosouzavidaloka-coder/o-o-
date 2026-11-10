# TG + EDVALDO v0.9.1 — interface 0.9 + segmentos da PRIMEIRA versão

## Pedido atendido

O programa mantém a janela da versão 0.9 sem alterações: disposição, título, campos, tema escuro, porteira por clique, spline I3D, Gerar XML, proteção contra duplicatas, animação e demolição. Apenas a rotina de geração dos segmentos foi substituída.

## O que mudou

Na primeira versão, o exportador Lua do GIANTS Editor tinha espaçamento de 2,0 metros, gerando uma linha segment entre dois pontos consecutivos da spline. A v0.9.1 lê o I3D como antes e refaz internamente a amostragem de aproximadamente 2 metros. Não agrupa trechos de 80 metros.

- Uma cerca reta de 500m sem porteira terá aproximadamente 250 segmentos XML.
- A porteira nativa GATE_* divide a cerca antes e depois da abertura, sem fios gerados no vão correspondente.
- Anti-duplicatas e confirmação de substituição continuam iguais à v0.9.
- O campo existente Trecho máximo no XML permanece como está, porém não altera o passo no modo original: o gerador usa ~2m.
- As tolerâncias de curva/relevo continuam exibidas na janela, mas não simplificam os segmentos nesse modo.

## Teste seguro

1. Selecione a mesma spline .i3d e mantenha seu .i3d.shapes ao lado.
2. Selecione mod e XML da cerca, e a porteira nativa se desejar.
3. Selecione somente uma cópia do placeables.xml de um savegame.
4. Com Só conferir / prévia marcado, clique em Conferir / Gerar XML.
5. Verifique o número de segmentos e a detecção de duplicatas.
6. Desmarque prévia apenas depois de avaliar; confirme a substituição de cerca antiga se o aviso aparecer.
7. Confira postes, arames, porteira, animação e demolição no jogo.

A amostragem da versão inicial é reproduzida, mas o encaixe visual de todos os modelos ainda exige teste dentro do FS25. O ZIP do mod não foi alterado.
