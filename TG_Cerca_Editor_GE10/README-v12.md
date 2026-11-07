# TG + EDVALDO v1.2 — corrigido o botão Selecionar UM (PC Objects)

## Erro corrigido

Na v1.1, clicar em **Selecionar UM** quando a tabela de objetos estava vazia registrava um aviso incorreto de seleção e, na hora de gravar, a mensagem "Selecione UM ou TODOS os objetos antes de registrar" aparecia. A imagem de teste mostrou o caminho de **um modelo individual**, em placeables/abatedouro1/abatedouro.i3d, no lugar da cena principal do mapa.

## Comportamento da v1.2

- **Selecionar UM** e **Selecionar TODOS** tentam ler o I3D automaticamente quando a tabela está vazia; selecionam objetos somente depois de uma leitura bem-sucedida.
- Se for um I3D de modelo individual, o programa procura o nome/arquivo do modelo como `Reference` nos I3Ds principais do mapa e recupera posição X/Y/Z e rotação na cena.
- Se houver duas ou mais instâncias do mesmo objeto, cada instância aparece separadamente, e você poderá selecionar **uma** ou **todas**.
- Se não encontrar a posição real, o programa avisa que o I3D do modelo não guarda posição de mundo e orienta a escolher a cena principal do mapa. **Não inventa posição 0,0,0** e não grava XML vazio.
- Novo botão **Encontrar I3D principal do mapa** para facilitar a escolha de arquivos em mapas com pastas complexas.
- Mantém o botão **ADICIONAR PC OBJECTS**, XML do mapa, storeItems.xml, associação manual, prévia, backups, e **a interface de cercas e porteiras da v0.9.1**.

## Como usar com seu abatedouro

1. Escolha a pasta raiz do mapa onde está o modDesc.xml.
2. Em **I3D do mapa ou objeto**, pode apontar para o abatedouro.i3d.
3. Clique **Selecionar UM**. A v1.2 procurará referências ao abatedouro no I3D principal do mapa.
4. Se aparecer na tabela, marque a instância desejada e escolha o XML de configuração do abatedouro do mod ou do mapa. Os caminhos precisam ser reais.
5. Se não aparecer, clique **Encontrar I3D principal do mapa** e escolha os objetos a partir da cena do mapa. O I3D individual não garante a posição de mundo.
6. Use **Conferir / Adicionar PC Objects** com **Somente conferir/prévia** marcado primeiro. Ao confirmar, registre os dados nos arquivos placeables.xml, storeItems.xml e na referência no map.xml.

## Limites

- A busca só encontra instâncias presentes nas cenas I3D do mapa como referências ou grupos reconhecíveis. Se o abatedouro não tiver sido importado/posicionado no mapa, não é possível recuperar coordenadas apenas do arquivo do modelo.
- O programa não consegue transformar uma malha 3D isolada num placeable com todas as funcionalidades sem um **XML real do objeto**, com configuração FS25.
- A presença do objeto como malha estática no I3D pode causar sobreposição quando registrado como placeable; teste sempre em cópia completa do mapa.
- A v1.2 tem testes automatizados com mapa e referências sintéticas, mas o resultado precisa ser validado no seu mapa real do FS25.

## Atualização: três caminhos separados

A janela PC Objects da v1.2 agora possui três campos **independentes**:

1. **I3D do MAPA (posição do objeto)** — o arquivo de cena principal (por exemplo, mapUS.i3d ou mapBR.i3d), onde o GIANTS Editor guarda as coordenadas da importação.
2. **I3D do OBJETO** — o modelo placeables/abatedouro1/abatedouro.i3d, ou o de uma casa/barracão/silo.
3. **XML do OBJETO** — o XML de configuração real do abatedouro, com raiz placeable e atributo type. Pode estar dentro da pasta do mapa ou de uma pasta de mod reconhecida.

O botão **Ler objetos do MAPA** cruza a cena principal com o I3D do objeto, inclusive quando a importação está num grupo chamado abatedouro. Se o modelo aparecer várias vezes no mapa, cada posição será uma linha independente.

O botão **Usar XML do OBJETO** lê o XML informado diretamente, sem depender de Carregar XMLs da origem. Se o catálogo ficar vazio, selecione o XML do OBJETO explicitamente e use o botão próprio. Quando existe um I3D específico selecionado, o XML pode ser associado a todas as instâncias dele.

O programa registra no placeables.xml e storeItems.xml e prepara a referência da loja no map.xml, fazendo backup antes de gravar. O modo Somente conferir/prévia não escreve arquivos.

**Limite:** se o objeto não estiver importado na cena do mapa, o I3D individual não fornece sua posição global. Coloque o objeto no GE e salve o mapa antes de executar o programa. 
