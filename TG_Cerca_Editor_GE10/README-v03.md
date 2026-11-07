# TOP GAMERS – Criador de Cercas FS25 v0.3 (BETA)

## Uso

1. No Windows 11, mantenha o ZIP de cerca original instalado na sua pasta `mods` do FS25; o programa não o modifica.
2. Execute `TOP_GAMERS_Cercas_FS25_v03.exe`.
3. Selecione a pasta mods personalizada, clique em **Carregar mods** e escolha `FS25_Brazilian_fences`.
4. Escolha `xml/fencesFarmLevel01.xml` a `05.xml`. O programa lê o comprimento real do painel (4 m, 6,7 m ou 3,8 m).
5. Escolha o CSV de pontos da spline (colunas `x,y,z`). **A leitura de `.i3d` ainda não foi integrada nesta versão.**
6. Se desejar, use **Porteira nativa do XML** e escolha `GATE_10m`, `GATE_5m`, `GATE_8m` ou `GATE_6m` conforme o modelo. O mod já inclui as animações; o programa não edita essas animações.
7. Escolha o `placeables.xml` de um savegame de TESTE. Deixe **Só conferir / prévia** marcado e clique em **Conferir / Gerar XML**.
8. Se a prévia estiver correta, desmarque a caixa para salvar. O programa cria backup `placeables.xml.tg_backup`.
9. Abra o jogo com o mesmo mod ativo, em terreno comprado pela fazenda, e confira **fios, espaçamento, porteiras e demolição**.

## Limites

- **BETA:** os fios e a demolição ainda não foram validados no jogo. Não grave no save original sem backup.
- A simplificação gera intervalos próximos ao comprimento de painel definido no XML. Nas curvas e trechos curtos, o comprimento pode variar.
- Uma cerca `newFence` é demolível conforme as regras do jogo; a propriedade vem do terreno. Trocar `farmId` no XML não libera venda automaticamente.
- `storeItems.xml` é validado, mas **não é modificado**. O mod enviado já registra seus 5 modelos no `modDesc.xml`.
- Porteiras nativas são inseridas com o identificador do segmento do próprio XML (`GATE_...`), sem criar outro placeable.
- Este EXE é uma ferramenta local de Windows, **não é um mod ZIP para colocar na pasta mods**.

Créditos do mod utilizado nos testes: `FS25_Brazilian_fences`, autor identificado no próprio `modDesc.xml` como `naimog mod`. O mod original não é redistribuído neste repositório.