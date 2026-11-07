# TG + EDVALDO FS25 v1.4.3 — AUTOAJUSTE de segmentos nas curvas (BETA)

## Erro corrigido

A versão v1.4.2 poderia mostrar o aviso:

> A curva/trecho de 247.29 m não permite painéis de 6.7 m (escala máxima 1.2). Ajuste a spline ou a posição da porteira no GE, em vez de gerar postes sem fios.

Isso podia acontecer **mesmo quando havia uma solução**, porque o programa tentava dividir a curva inteira em painéis com o mesmo comprimento de caminho. Ao atravessar uma curva, a distância reta entre os postes fica menor que a distância percorrida, e o painel pode ficar curto demais para aparecer.

### Novo modo adaptativo (automático)

A v1.4.3 **reposiciona os vãos individualmente ao longo da mesma spline I3D**, sem exigir que o usuário desenhe outra spline nem altere o arquivo original:

- Lê o tamanho do painel e o limite `maxScale` do XML do mod. No Brazilian Fences fornecido, 4 m (modelos 01, 03, 04), 6,7 m (02) e 3,8 m (05), com `maxScale=1.2`.
- Procura uma sequência contínua de postes que respeite o comprimento mínimo e máximo dos painéis e **distribua o resto ao longo do percurso**, inclusive em curvas.
- Preserva as extremidades originais da spline, inclusive as pontas onde é encaixada a porteira.
- Evita atalhos muito grandes nas curvas ao limitar a distância lateral entre cada painel reto e o percurso original.
- Se o traçado for de fato fechado demais para esses painéis, bloqueia a gravação e mostra mensagem mais precisa, em vez de criar somente postes sem fios.

### Teste específico do erro de 247,29 metros

Foi acrescentado um teste de 247,29 m com curva de 90° e painel de 6,7 m: o cálculo de v1.4.2 não encontrava vãos uniformes válidos, mas o novo ajuste adaptativo encontra uma sequência de vãos dentro de 6,7–8,04 m, mantendo começo e fim do trecho. Os testes também conferem o encaixe da porteira nativa.

## Como testar

1. Abra o `TG_EDVALDO_FS25_v143_PCObjects.exe`.
2. Escolha o **mesmo mod de cerca**, modelo XML e a **mesma spline I3D** usada na v1.4.2.
3. Selecione uma parte preferencialmente reta da spline para posicionar a porteira, usando a prévia por clique.
4. Escolha uma **CÓPIA** do `placeables.xml` do savegame.
5. Com **Só conferir / prévia** marcado, clique em `Conferir / Gerar XML` e confira o log.
6. Se não aparecer erro, desmarque a prévia e gere. Quando detectar cerca antiga sobreposta do mesmo modelo e mesmo percurso, **confirme a substituição** para não deixar a cerca velha por cima.
7. Confira no FS25 se aparecem **postes e fios**, se a **porteira segue a cerca**, se a **animação** e a **demolição** continuam funcionando.

## Recursos preservados

- A interface e os botões de cercas/porteiras não foram reorganizados.
- A parte **PC Objects** e a minimização da janela principal da v1.4.1 foram mantidas.
- A porteira continua usando largura física derivada do modelo I3D quando disponível.
- Não há edição do ZIP de origem, do I3D ou das animações do mod.
- Backup e proteção contra cercas duplicadas permanecem ativos.

**Versão BETA.** O algoritmo foi validado com testes automatizados, inclusive um caso de curva que reproduz a falha, mas não recebeu o seu arquivo de spline real de 247,29 m. Pode haver geometrias excepcionalmente fechadas sem solução. O resultado 3D precisa ser testado no FS25.
