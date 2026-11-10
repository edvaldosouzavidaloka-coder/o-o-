# TG + EDVALDO FS25 v1.4.2 — FIOS E PORTEIRA (BETA)

## Correção da cerca sem fios

A v0.9.1 gerava um `<segment>` a cada **2 metros**, enquanto o mod `FS25_Brazilian_fences` utiliza painéis de **4 m** (modelos 01, 03, 04), **6,7 m** (02) e **3,8 m** (05). No FS25, segmentos menores que os painéis podem renderizar **somente postes sem fios**, especialmente após atualizações do jogo.

Na v1.4.2, o programa lê o **comprimento do painel e o limite maxScale** diretamente do XML do modelo e gera segmentos com comprimento útil para o painel completo. Não volta a compactar em 80 metros. Em curvas fortes ou trechos curtos que não admitem um painel inteiro, **mostra erro e não grava o XML**, em vez de montar uma cerca sem fios.

## Porteira atravessada/desencaixada

O mod brasileiro fornecido declara **length=5.4** em todas as quatro opções de porteira, apesar de seus modelos 3D terem larguras diferentes. A leitura dos postes na cena I3D identificou, por exemplo:

- `GATE_10m`: postes com distância aproximada **10,31 m**.
- `GATE_8m`: **8,34 m**.
- `GATE_6m`: **5,33 m**.
- `GATE_5m`: mantém a largura indicada no XML (5,4 m) quando os nós de postes não revelam a medida real.

A v1.4.2 usa a dimensão física detectada para reservar a abertura no `placeables.xml`. A **mesma spline I3D** define os pontos de início e fim da cerca, e a porteira entra **entre os trechos**, com extremidades coincidentes. A abertura é posicionada pela distância reta entre os postes, não pela distância percorrida em curva. Se o trecho tem curvatura muito forte (desvio maior que 17 graus nas extremidades), o programa pede para escolher uma parte mais reta da spline, evitando uma porteira atravessada.

**Não modifica o ZIP original do mod, suas animações nem as configurações de demolição.** O modo prévia e a detecção/substituição confirmada das cercas antigas continuam ativos.

## Como testar

1. Abra `TG_EDVALDO_FS25_v142_PCObjects.exe`.
2. Use o mesmo arquivo de spline `.i3d`, mantendo seu `.i3d.shapes`.
3. Escolha o mod **Brazilian Fences**, o XML do tipo de cerca e a porteira nativa no campo `PORTEIRA nativa do XML`.
4. Na prévia, selecione uma parte **reta** da spline para a porteira.
5. Selecione o `placeables.xml` de **uma cópia do savegame** e deixe `Só conferir/prévia` marcado. Clique em `Conferir/Gerar XML`.
6. Confira o log. Se o programa detectar impossibilidade de um painel completo ou de alinhamento da porteira, ajuste a posição da porteira ou a spline no GE. **Não force trechos de 2m.**
7. Desmarque prévia, confirme substituição de cercas antigas **do mesmo modelo e trajeto** quando solicitado, e gere o novo XML (backup automático).
8. Entre no FS25 e confira os fios, postes, encaixe, abertura, animação e demolição.

## Atenção

- O programa não remove todas as cercas antigas de outros modelos ou traçados: elas podem continuar aparecendo no mapa. Um aviso de sobreposição exige conferência manual.
- A largura estimada por postes I3D pode diferir de colisões e detalhes da malha, sobretudo `GATE_5m`; o teste no jogo continua obrigatório.
- O comprimento mínimo de painel e `maxScale` são validados. Em splines muito sinuosas alguns trechos não poderão ser preenchidos sem editar a curva; nesse caso o programa bloqueia a gravação.
- A opção antiga `Trecho máximo (80m)` permanece na interface para manter a aparência, mas o gerador usa as medidas reais do XML.
- A interface PC Objects da v1.4.1, incluindo a janela principal minimizada, leitura I3D, posicionamento XYZ, StoreItems, backups e ícone decorativo, permanece preservada.

**BETA — testar em cópia do savegame/mapa.** Os testes de software não demonstram por si só que o motor do FS25 renderizará corretamente os painéis ou a animação.
