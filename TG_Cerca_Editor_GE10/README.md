# TOP GAMERS — Cerca por spline no FS25 (protótipo v0.1)

**Versão de teste — não validada no GIANTS Editor 10.0.14 nem no jogo real.** Faça cópia do mapa e do savegame antes do primeiro teste.

## Como usar

1. Instale Python 3.10 ou superior no Windows (Tkinter vem normalmente com a instalação oficial).
2. No GIANTS Editor: **Window → Script Editor → User Scripts → Explore Folder**. Copie `TG_ExportarSpline.lua` para essa pasta e reinicie o Editor.
3. Abra o mapa no Editor, selecione **uma spline** no Scenegraph e execute `TG_ExportarSpline.lua`. Ele grava o CSV em `%TEMP%\TG_Cerca_Spline.csv`.
4. Execute `py TG_Cerca_Editor.py` no Prompt de Comando (na pasta onde está esse arquivo).
5. Selecione a pasta `mods`, o mod e o XML da cerca, opcionalmente uma porteira, e o `placeables.xml` do mapa ou savegame.
6. Primeiro deixe **Só conferir / prévia** marcado e clique em `Conferir / Gerar XML`. Depois confira o relatório, desmarque a prévia para gravar.
7. Teste em um novo save do FS25, verificando o `log.txt`. Para um save já existente, selecione o `placeables.xml` desse save.

## Limites importantes desta primeira versão

- Gera as **entradas newFence**, não uma malha visual permanente no Editor. Os painéis devem aparecer ao carregar no FS25, se o XML da cerca usa a especialização `newFence` e o mod está ativo.
- A ferramenta cria segmentos `id="SEGMENT"`; **venda por trechos** depende de a cerca ser um placeable nativo do FS25. Não é garantida para mods arbitrários.
- Porteira independente: abre uma lacuna na cerca e registra um placeable separado. A animação **não é reescrita**: precisa estar funcional no XML e no I3D originais do mod, e a posição/rotação talvez precise de ajuste. Porteiras que são `newFence` precisam de um modo integrado específico ainda não implementado.
- O campo de **XML de animação** apenas valida a leitura. Não modifica o arquivo do mod nem o I3D.
- O `storeItems.xml` do mapa é **validado, mas não alterado**: mods externos devem ter seus próprios itens registrados no `modDesc.xml`. Inserir o mod externo no `storeItems.xml` do mapa sem verificar o carregamento poderia gerar referências inválidas ou duplicadas.
- A spline é amostrada em intervalos aproximados de 2 m. É uma aproximação de curvas; ajuste `spacing` no Lua para curvas apertadas.
- **Não foi testado com um mod específico ainda.** Se der erro, envie o XML da cerca, o XML da porteira e o `log.txt` para adaptar os IDs reais.

## Segurança

- Modo prévia ativado por padrão.
- XML destino precisa ter raiz `<placeables>`.
- Na primeira gravação cria `placeables.xml.tg_backup` ao lado do XML original.
- Nunca altera os ZIPs dos mods. Não execute no mapa principal antes de testar.

Fontes de formato: documentação oficial do GIANTS FS25 `PlaceableNewFence`, `Fence`, `PlaceableSystem` e exemplos públicos de `placeables.xml` com `<newFence><segment start="..." end="..." id="SEGMENT"/>`.