# TG + EDVALDO v1.1 — Cercas, Porteiras e PC Objects FS25

A atualização **mantém o criador de cercas/porteiras da v0.9.1 e seus segmentos de 2 metros**. Foi acrescentado o botão **ADICIONAR PC OBJECTS**, com janela separada.

## O que faz

Lê o **I3D do mapa com os objetos importados no GIANTS Editor 10.0.14** — **não precisa de spline**. Localiza os objetos `Reference` importados e grupos com nomes de edifícios, extrai posição X/Y/Z e rotação Y considerando os grupos-pai, e permite escolher **UM** ou **TODOS**.

Cada objeto precisa estar associado ao **XML verdadeiro do placeable** do mapa ou do mod, como barracão, silo, casa, galpão, armazém, fábrica, estábulo etc. O arquivo I3D sozinho não contém as especializações, loja e comportamento do FS25. Por isso, o programa carrega XMLs `<placeable type=...><base><filename>...` de um mod ZIP/pasta ou da própria pasta do mapa e associa automaticamente quando o nome do I3D coincide sem ambiguidades. Para objetos sem associação, selecione o XML correspondente e clique **Associar XML aos selecionados**.

## Arquivos registrados automaticamente

1. **placeables.xml do mapa**: inclui `<placeable filename="..." position="X Y Z" rotation="0 Y 0" farmId="0" />` para cada objeto selecionado, usando o caminho real do XML do mod.
2. **storeItems.xml do mapa**: adiciona um único `<storeItem xmlFilename="..." />` por XML de objeto, evitando registros duplicados. Pode criar o `storeItems.xml` se estiver ausente.
3. **map.xml do mapa**: se a referência `<storeItems filename="..."/>` aponta para o arquivo original do jogo ou para outro arquivo, o programa a corrige automaticamente para o StoreItems do mapa.

Antes de gravar, os XMLs são validados. O programa cria backups dos existentes, grava o conjunto e tenta restaurar arquivos anteriores se houver erro de gravação. A opção **Só conferir / prévia** vem marcada inicialmente e não altera arquivos.

## Passo a passo

1. Abra o `TG_EDVALDO_FS25_v11_PCObjects.exe` no Windows. Não o coloque na pasta mods.
2. Na janela principal, clique **ADICIONAR PC OBJECTS**.
3. Selecione o **I3D do mapa**, não o I3D exportado de uma spline.
4. Selecione a **Pasta raiz do mapa** (a pasta com `modDesc.xml`). O programa tenta localizar `placeables.xml` e `storeItems.xml` automaticamente. Se necessário, use os botões Selecionar.
5. Clique **Ler objetos do I3D**.
6. Em **Origem dos XMLs**, escolha o mod com o objeto e clique **Carregar XMLs da origem**. Pode repetir para carregar XMLs de vários mods.
7. Use **Selecionar UM** ou **Selecionar TODOS**. O programa associa por nome do modelo I3D quando encontra uma opção única. Se aparecer PENDENTE, escolha o XML correto e clique **Associar XML aos selecionados**.
8. Com a **prévia** ligada, clique **Conferir / Adicionar PC Objects**. Veja quantos objetos e itens de loja serão registrados.
9. Desmarque a prévia e clique novamente para salvar. Confirme. Serão gerados os backups.
10. Abra o mapa no FS25 e verifique a presença, funcionamento e loja dos objetos.

## Cuidados importantes

- Um grupo 3D que **não é um placeable funcional** não vira automaticamente um silo/casa/venda. Ele precisa do XML de configuração do mod com a especialização correta.
- O programa não altera o ZIP de origem, as animações nem o I3D do mapa. Se o objeto importado **permanecer visível como malha estática no mapa**, pode sobrepor o placeable carregado pelo jogo. Use uma cópia do mapa para verificar isso e ajuste os placeholders no GIANTS Editor se necessário.
- Só transforma automaticamente rotações de grupos-pai no eixo **Y**. Objetos com grupos inclinados em X/Z podem exigir correção no Editor. Confira alturas e rotações no jogo.
- Um XML de outro mod precisa estar instalado e ativo no FS25. O programa não instala mods nem cria seus arquivos XML/I3D.
- O reconhecimento de objetos importados depende do `Reference` ou nome identificável no I3D do mapa; importações mescladas sem referência/nome podem precisar de ajuste ou associação manual.
- Se um objeto especial depende de scripts customizados, farmland, triggers ou especializações, a presença na loja depende também do próprio mod e da configuração do mapa.
- A loja do FS25 depende do registro do item, não apenas de um arquivo `placeables.xml` válido. <storeItems> e `map.xml` precisam estar conectados. Fonte: GIANTS Developer Network / documentação de placeables.

**Versão beta**: execute primeiro em uma **cópia completa do mapa**. Testes automáticos verificam arquivos e interface, mas não substituem teste dentro do jogo.
