# TG + EDVALDO — FS25 v1.4: PC Objects a partir de I3D exportado (BETA)

## Correção solicitada

Na v1.3, marcar placeables.xml exigia a referência do objeto no I3D **principal do mapa**. Isso bloqueava objetos que o usuário acabava de exportar pelo GIANTS Editor 10.0.14, com o aviso "Objeto não localizado no I3D do mapa".

Na v1.4, para registrar o objeto em placeables.xml **não precisa selecionar o I3D principal**. Selecione diretamente o **I3D exportado do OBJETO** (como fazia com uma spline, mas sem tratar o objeto como cerca).

## Tela PC Objects v1.4

- **I3D do MAPA:** opcional, não é necessário na geração a partir de um I3D exportado.
- **I3D EXPORTADO do OBJETO:** arquivo .i3d de casa, barracão, silo, galpão, abatedouro etc.
- **XML do OBJETO:** opcional. Quando ausente, o programa pode gerar o XML mínimo de um **simplePlaceable DECORATIVO**, com ícone PNG para a loja.
- **Posição X Y Z e Rotação RX RY RZ:** campos editáveis. Botão **Ler posição do I3D** traz o transform do grupo raiz se o I3D tiver translation/rotation explícitas.
- **Marcar no placeables.xml (posição):** usa o XYZ/rotação fornecidos, sem buscar uma instância no I3D principal.
- **Marcar no storeItems.xml (loja):** registra apenas o XML no catálogo do mapa; não exige coordenadas se só essa caixa estiver marcada.
- **Conferir (não grava)** e **Registrar nos XMLs marcados:** somente grava depois de selecionar os destinos, conferir e confirmar. Faz backup e rollback em caso de falha.

## Como usar o I3D exportado

1. Exporte o objeto pelo GIANTS Editor e salve o .i3d **dentro da pasta do seu mapa**, juntamente com .i3d.shapes, texturas e demais recursos.
2. Abra PC Objects e selecione a **pasta raiz do mapa** (modDesc.xml).
3. Escolha o **I3D EXPORTADO do OBJETO**.
4. Clique **Ler posição do I3D**. Confira os seis valores. Se o GE tiver exportado a malha com origem em 0 ou as coordenadas forem locais, digite a posição X/Y/Z **global** correta do mapa. O programa não consegue inferir coordenadas globais inexistentes.
5. Se o objeto já possui XML de configuração FS25, selecione-o no campo **XML do OBJETO**. Para silos/abatedouros/estações funcionais use sempre esse XML próprio.
6. Se é apenas uma **decoração estática**, pode deixar **XML do OBJETO** vazio: o app prepara `tg_<nome>_decorativo.xml` e `tg_<nome>_loja.png` na mesma pasta do I3D, sem sobrescrever outro XML.
7. Marque **No placeables.xml** para colocá-lo fisicamente no mapa, **No storeItems.xml** para cadastrá-lo na loja, ou ambas.
8. Clique **CONFERIR**, confirme as coordenadas e quais arquivos serão alterados. Esse botão não grava nada.
9. Clique **REGISTRAR**, confirme a gravação; serão criados backups dos arquivos existentes.

## Limitações técnicas

- **Um I3D sozinho não define funções de jogo.** O XML decorativo gerado tem `type="simplePlaceable"`: não cria capacidade de armazenamento, triggers de produção/venda, animações ou outras especializações. Para **silos funcionais, casas com recursos, abatedouros ou fábricas**, forneça o XML próprio do mod.
- Para aparecer na loja o FS25 precisa de campos válidos `storeData`, especialmente `image`. O programa cria ícone simples PNG para os itens decorativos. A aparência real e categoria devem ser testadas no FS25; é beta.
- Se o I3D foi exportado sem translation/rotation do objeto no mundo, a interface pede preenchimento **manual**. O arquivo exportado pode conter posição **local** em vez da global; confira no GIANTS Editor.
- Se o I3D ficar fora da pasta raiz do mapa, o programa **não copia automaticamente** modelos/texturas e não gera XML decorativo, para não criar referências quebradas. Exporte dentro do mapa.
- O programa **não move a malha** que já está colocada no I3D principal, nem elimina automaticamente geometria estática sobreposta com o placeable do mapa.
- Para StoreItems, um item de lavoura/foliage sem XML comercializável não vira produto por ser listado. XML de veículo ou placeable funcional pode ter formato próprio.
- A interface original do criador de cercas e porteiras da v0.9.1, segmento a cada 2m, animações e demolição foram preservados.

**Teste primeiro em uma cópia completa do mapa.** A compilação e os testes de XML não garantem a instalação visual ou funcional dentro do FS25.
