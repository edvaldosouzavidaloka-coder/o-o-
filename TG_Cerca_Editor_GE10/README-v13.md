# TG + EDVALDO — PC Objects FS25 v1.3 (BETA)

## Mudança solicitada — registros independentes e somente sob confirmação

A janela **ADICIONAR PC OBJECTS** mantém os três campos separados: I3D do MAPA, I3D do OBJETO e XML do OBJETO. Os botões **Selecionar UM** e **Selecionar TODOS** foram removidos porque não são necessários para registrar um objeto já identificado pelo XML do próprio item.

A escolha do XML não altera nenhum arquivo do mapa. Você precisa marcar explicitamente um ou ambos os destinos:

- **No placeables.xml (posição no mapa):** usa a localização real do modelo referenciado no I3D do MAPA; exige I3D do MAPA, I3D do OBJETO, XML do OBJETO e placeables.xml. Não toca em StoreItems nem em map.xml.
- **No storeItems.xml (loja):** registra a referência ao XML do objeto, sem exigir I3D do mapa, I3D do objeto ou placeables.xml. Atualiza a referência à loja no map.xml apenas quando este destino for selecionado e houver divergência. Para registrar, exige um XML de item comprável do FS25 com storeData.
- **Ambos:** realiza os dois registros, com suas validações, no mesmo comando e com backups.

As caixas começam **desmarcadas**. O procedimento é: **marcar destino → CONFERIR (não grava) → REGISTRAR nos XMLs MARCADOS → confirmar**. Alterou um caminho ou uma opção? É necessário conferir novamente. O aplicativo não cadastra nada automaticamente ao selecionar o XML.

## Exemplo prático com o abatedouro

Se quiser que o abatedouro apareça **no mapa**: informe o I3D principal do mapa, o abatedouro.i3d, o XML do abatedouro e o placeables.xml; marque somente **No placeables.xml**. O programa recupera do mapa a transformação da referência importada. Se o modelo não estiver posicionado no I3D principal, ele bloqueia a gravação, sem criar coordenadas artificiais.

Se quiser apenas cadastrar **na loja**: informe a pasta raiz do mapa, o XML válido do item e o caminho de storeItems.xml. Marque somente **No storeItems.xml**. Não precisa selecionar a spline nem carregar modelos I3D.

Se quiser as duas coisas, marque as duas caixas e informe os arquivos necessários.

## Plantas, vegetação e outros itens

Nem todo XML é um item de loja. Plantas de lavoura e foliage/fruitTypes geralmente são configurados em outros arquivos do mapa, não no storeItems.xml. Um item comercializável — por exemplo, uma árvore decorativa vendida como placeable, ou uma máquina/veículo — pode ter configuração de loja no seu próprio XML. A v1.3 verifica a raiz, type e storeData antes de registrar. Para suporte a sistemas de vegetação, seriam necessárias outras ferramentas e formatos.

## Segurança e compatibilidade

- O programa não altera o ZIP dos mods nem o I3D. Os caminhos do XML do item precisam estar dentro da raiz do mapa ou de uma pasta de mod descompactado com modDesc.xml.
- A geração de cercas, porteiras, animação, demolição, prévia e proteção contra duplicatas da v0.9.1 permanece inalterada.
- Os registros repetidos no mesmo lugar/modelo são evitados; storeItems não recebe entradas duplicadas.
- Backups são realizados somente para os arquivos selecionados que realmente sofrerem mudanças (além de map.xml quando necessário).
- **Versão beta:** os testes automatizados verificam registros/GUI, mas você deve testar numa CÓPIA COMPLETA do mapa FS25 antes de usar na versão principal.
