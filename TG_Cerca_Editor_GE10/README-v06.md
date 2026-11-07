# TG + EDVALDO | Criador de Cercas FS25 v0.6 BETA

Interface do Windows 11 com **a imagem enviada do trator ao fundo, escurecida para manter legibilidade**. Versão 0.6 incorpora uma miniatura otimizada; o botão “Escolher foto em alta resolução…” permite selecionar o arquivo JPG original para melhorar a qualidade do fundo, que também é escurecido automaticamente.

## Como usar

1. Exporte a spline no **GIANTS Editor 10.0.14** como `.i3d`, deixando o `.i3d.shapes` na mesma pasta.
2. Execute `TG_EDVALDO_Cercas_FS25_v06_I3D.exe`. **Não colocar o EXE dentro da pasta mods**.
3. Aponte a pasta `mods`, clique **Carregar mods**, escolha o mod `FS25_Brazilian_fences`.
4. Escolha um dos **modelos de cerca nativa** listados em “XML da cerca”. A caixa da direita mostrará tipo, distância do painel, IDs de poste/painel, porteiras, registro e capacidade de venda.
5. Selecione o `.i3d` e o `placeables.xml` **de um savegame de teste, nunca do único save original**.
6. Deixe “Só conferir / prévia” marcado e clique **Conferir / Gerar XML**. Veja a quantidade de trechos no log antes de gravar.
7. Se estiver correto, desmarque prévia, gere de novo e teste no FS25 com o mod ativo.

## Redução de segmentos e porteiras

O tamanho padrão máximo de um trecho no XML é **25 m**. Uma cerca reta de 500 m pode gerar cerca de 20 registros `<segment>`; nas curvas e declives adiciona divisões para acompanhar o relevo. O **espaçamento entre postes** segue o XML do mod escolhido. Os cinco tipos encontrados no Brazilian Fences usam painéis de 4, 6,7, 4, 4 e 3,8 m. O programa não altera o ZIP do mod. Porteiras nativas são selecionadas por ID no XML, sem editar a animação.

## Demolição no paisagismo

A versão 0.6 identifica explicitamente `type="newFence"`, exige segmento `FenceSegment`, e verifica `modDesc.xml` e `canBeSold` do modelo, exibindo avisos no programa. Também permite indicar `farmId` no `placeables.xml` para testar o savegame: **0 = mapa**, **1 = fazenda 1**, etc.

**Isso NÃO garante demolição**: depende da propriedade real do terreno, colisões, seleção do painel, da especialização nativa e de o jogo registrar o objeto. Trocar `farmId` pode ser inadequado para cercas pertencentes ao mapa; use somente em save de testes. Para cada tipo que não permitir demolir, registre o XML, o terreno usado e o `log.txt` do FS25.

## Limitações

- Spline I3D cúbica é **aproximada** a partir dos pontos de controle; precisa de verificação visual.
- `storeItems.xml` apenas validado, não editado.
- Usa o leitor de `.i3d.shapes` experimental da v0.2; formatos não suportados mostram erro.
- Sempre cria backup antes de modificar o XML; o modo prévia vem ativado.
- Foto original enviada foi reduzida para o EXE: é possível escolher a foto de alta resolução no computador para manter a imagem nítida.
- Esta é uma **versão beta não validada no jogo FS25**; o teste automatizado verifica apenas parsing, geração de XML e criação do EXE.

Licenças: usa Pillow e PyInstaller para compilar o programa Windows; a rotina I3D adaptada é documentada no MIT_TERCEIROS.txt do arquivo de origem v0.2.
