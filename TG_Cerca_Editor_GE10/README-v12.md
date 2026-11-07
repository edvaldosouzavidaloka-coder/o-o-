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
