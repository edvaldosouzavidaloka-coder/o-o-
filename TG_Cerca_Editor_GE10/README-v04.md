# TOP GAMERS – Criador de Cercas FS25 v0.4 (BETA I3D)

**Esta versão usa arquivos `.i3d`, não CSV.** A versão 0.3 usava CSV e foi substituída para este teste.

## Como testar

1. No GIANTS Editor 10.0.14, selecione a spline e faça `File > Export Selection`, gerando um arquivo `.i3d`.
2. Mantenha o `.i3d.shapes` que acompanha a exportação junto do `.i3d`, na mesma pasta.
3. Abra `TOP_GAMERS_Cercas_FS25_v04_I3D.exe` no Windows, fora da pasta `mods`.
4. Selecione a pasta dos mods e clique **Carregar mods**. Escolha `FS25_Brazilian_fences` e o XML de uma cerca (ex.: `xml/fencesFarmLevel01.xml`).
5. Clique em **Selecionar I3D** e escolha a spline. Clique em **Analisar arquivo I3D**.
6. Selecione o `placeables.xml` de uma CÓPIA do savegame. Escolha, se quiser, a porteira nativa do mesmo XML.
7. Deixe marcada a opção **Só conferir / prévia** e clique **Conferir / Gerar XML**. Confira os números.
8. Quando estiver correto, desmarque a opção de prévia e gere. Abra o save de teste no FS25 e confira o `log.txt`.

## Limitações importantes

- Formato `.i3d.shapes` deve ser compatível com o leitor experimental. Em algumas versões/sementes, pode exigir acesso à internet para buscar uma tabela de chaves MIT; nem todos os arquivos I3D são garantidos.
- Spline **cúbica** é aproximada conectando pontos de controle: curvas apertadas podem não coincidir exatamente com o Editor.
- A geração utiliza os comprimentos de painéis definidos no XML do mod; **os fios/colisões e a demolição não foram validados dentro do jogo**.
- `storeItems.xml` é apenas verificado e não é modificado; `animatedObjects.xml` do mod não é reescrito.
- O `placeables.xml` do save é salvo com backup `.tg_backup`. Faça também backup manual antes de qualquer teste.
- O mod `FS25_Brazilian_fences.zip` não está incluído no executável.

## Créditos

O parser `tg_i3d.py` já havia sido publicado no protótipo I3D v0.2 com crédito à implementação MIT da cifra I3D de Donkie / I3DShapesTool via BrewingCoder / giants-fs-codecs (MIT). Consulte o arquivo `MIT_TERCEIROS.txt` no pacote do ZIP v0.2.