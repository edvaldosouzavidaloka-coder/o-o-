# TG + EDVALDO — Criador de Cercas e PORTEIRAS FS25 v0.8 (BETA I3D)

A v0.8 remove **completamente a foto de fundo** que provocou artefatos gráficos na v0.7. Tem fundo escuro liso e uma **prévia 2D clicável** para escolher a localização da porteira.

## Como colocar a PORTEIRA

1. Abra o EXE \`TG_EDVALDO_Cercas_FS25_v08_I3D.exe\` no Windows, **fora da pasta mods**.
2. Em \`Pasta mods\`, selecione a pasta que contém o \`FS25_Brazilian_fences.zip\` e clique **Carregar mods**.
3. Selecione o **mod da cerca** e depois o **XML da cerca** (um dos tipos \`newFence\` desse mod).
4. O campo **PORTEIRA nativa do XML** mostra os modelos disponíveis, por exemplo \`GATE_5m\`, \`GATE_6m\`, \`GATE_8m\` ou \`GATE_10m\`. Selecione a desejada. O comprimento real da abertura vem do XML, não do campo "largura" da v0.7, que foi retirado.
5. Em **Spline exportada (.i3d)**, escolha a spline exportada do GIANTS Editor 10.0.14. **Use a mesma spline da cerca, não crie outra.** Mantenha o \`.i3d.shapes\` correspondente na mesma pasta.
6. Clique **Visualizar I3D e porteira** (ou a prévia aparece ao selecionar o I3D). A linha verde mostra o traçado da cerca visto de cima, e a faixa laranja mostra onde a porteira ficará.
7. **Clique na linha verde exatamente na posição desejada para a porteira.** O campo \`Posição porteira (%)\` será atualizado automaticamente. Também é possível editar o percentual manualmente.
8. Escolha \`placeables.xml\` de uma **cópia de savegame**. Mantenha marcada a opção **Só conferir / prévia** e clique \`Conferir / Gerar XML\`. Confira o resumo no console do programa; nesse modo nenhum arquivo é gravado.
9. Depois de conferir, desmarque **Só conferir / prévia** e gere o XML. O app salva backup \`placeables.xml.tg_backup\` antes de alterar.
10. Abra o FS25 com o mod ativado e veja o resultado real da porteira, os fios e a demolição.

## Importante

- **A prévia é 2D, não uma renderização do jogo.** Ela indica a posição da porteira e do traçado; não prevê os modelos e animações.
- O posicionamento da porteira é definido pelo percentual do comprimento da spline. O programa mantém espaço para painéis nas duas extremidades. Se a spline for muito curta, haverá um aviso.
- Não edita arquivos \`.i3d\` nem o ZIP da cerca; adiciona um \`<placeable><newFence><segment ... id="GATE_*" />\` ao XML do savegame selecionado.
- O código é compilado sem importar a antiga foto do trator ou Pillow. O ícone TG + EDVALDO continua no EXE.
- Mantém o ajuste de trechos de 80 m da v0.7. Espaçamento dos postes, encaixe de arame, visual e **demolição** ainda dependem da engine e devem ser conferidos no FS25.
- O \`farmId\` do objeto no savegame não garante demolição: é preciso terreno pertencente à fazenda e modelo/collisions compatíveis.
- **Versão beta**: não usar como substituto único do mapa/savegame sem backup.
