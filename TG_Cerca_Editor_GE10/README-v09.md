# TG + EDVALDO — Cercas e Porteiras FS25 v0.9 I3D (BETA)

## Novidade: evitar cercas e segmentos antigos duplicados

A v0.9 mantém o programa **sem foto de fundo**, a spline **I3D + I3D.shapes** e a **prévia clicável da porteira** da v0.8. A mudança é no momento de adicionar a cerca ao \`placeables.xml\`.

**Se já houver uma cerca do mesmo modelo no mesmo traçado:** o programa reconhece as cercas existentes pelo \`newFence\`, compara posições dos pontos, percurso, extremos e o \`filename\` do XML. Na prévia, informa quantas cercas antigas encontrou, sem alterar arquivos. Ao gravar, **pergunta se você autoriza substituir** a(s) cerca(s) anterior(es). Se confirmar, remove somente essas instâncias e insere uma nova.

**Se houver cerca parcialmente sobreposta ou de outro modelo:** a geração é **bloqueada** com aviso. Isso evita apagar cercas existentes que podem ter sido colocadas intencionalmente. Para resolver, retire manualmente a antiga do savegame de teste ou envie o \`placeables.xml\` para inspeção.

**Se não houver sobreposição:** adiciona a cerca normalmente, sem duplicatas.

A verificação é **conservadora**, especialmente em relação a cercas próximas ou modificadas. Ela não corrige qualquer duplicação do mapa automaticamente e não substitui a avaliação visual dentro do FS25.

## Como usar

1. Inicie \`TG_EDVALDO_Cercas_FS25_v09_I3D.exe\` fora da pasta mods.
2. Carregue a pasta mods, selecione o mod brasileiro e seu XML nativo de cerca.
3. Selecione a mesma spline \`.i3d\` (com \`.i3d.shapes\` ao lado). **Não é preciso criar outra spline** para a porteira.
4. Escolha a porteira nativa e clique no local desejado na prévia 2D.
5. Selecione o \`placeables.xml\` de **uma cópia do savegame**.
6. Deixe **Só conferir/prévia** marcado e clique **Conferir/Gerar XML**. Leia quantas cercas iguais ou parcialmente sobrepostas foram identificadas.
7. Desmarque a prévia e clique novamente. Se encontrar cercas iguais no mesmo traçado, **confirme ou cancele** a substituição.
8. O programa grava o XML com backup \`placeables.xml.tg_backup\`. Confira no jogo os arames, alinhamento da porteira e demolição.

## O que NÃO muda

- A **animação da porteira** e os parâmetros de **demolição** do mod continuam intocados.
- Não edita o \`FS25_Brazilian_fences.zip\`, a \`storeItems.xml\` nem os \`.i3d\`/ \`.i3d.shapes\`.
- A posição da porteira continua sendo definida pela spline e pelo ID \`GATE_*\` nativo do XML.
- A prévia 2D não representa com exatidão a renderização, colisão ou orientação das dobradiças no FS25.

## Limitações

- A detecção funciona com cercas contíguas armazenadas em \`newFence/segment\` e coordenadas \`start\`/\`end\`. Instâncias antigas com pontos muito diferentes, múltiplos grupos desconectados ou outros formatos podem exigir limpeza manual.
- Uma cerca de outro tipo **não será apagada**; o aplicativo bloqueia a gravação para evitar danos.
- A v0.9 **não garante** que uma porteira se alinhe visualmente ao painel ou elimine fios dentro do vão se o problema estiver na geometria do mod. É preciso testar no FS25.
- \`farmId\` e opções de demolição existentes não são alterados por essa correção.
- **Versão beta**. Testar em cópia do savegame, nunca na única versão do mapa.
