# TG + EDVALDO — Criador de Cercas FS25 v1.0 I3D BETA

## Por que a cerca ficava errada

Na v0.7–v0.9 o programa agrupava muitos painéis em um único registro \`<segment>\` (até 80 metros). No FS25, isso pode alterar a distribuição visual dos postes e das ripas/arames, sobretudo nas curvas e nas emendas. **A prioridade agora é a fidelidade ao modelo, não minimizar o tamanho do XML.**

### Correção v1.0

- **PRECISO (padrão): um painel = um segmento XML.** O programa lê \`length\` no XML do modelo de cerca: modelos 01, 03, 04 = **4 m**, 02 = **6,7 m**, 05 = **3,8 m**.
- A spline I3D é amostrada ao longo do percurso com o comprimento real do painel. O resto é distribuído igualmente para não criar um último vão muito pequeno.
- A **porteira nativa** permanece na mesma spline, com abertura do tamanho declarado no XML do próprio mod. No ZIP Brazilian Fences fornecido, todos os quatro IDs \`GATE_10m\`, \`GATE_5m\`, \`GATE_8m\` e \`GATE_6m\` declaram \`length="5.4"\` — os nomes não correspondem ao vão real da configuração.
- **EXPERIMENTAL: 2 painéis só nas retas** é uma opção. Não use até a opção PRECISO estar aprovada em testes no FS25.
- Mantém a interface sem foto, visualização da spline I3D e posição de porteira por clique, detecção de cercas duplicadas da v0.9, modo prévia e backup.
- **Animação e demolição não foram modificadas**; o mod ZIP continua intacto.

### Comprimento do XML é maior por segurança

Exemplo: cerca reta de 500 metros, sem porteira:
- Painel de 4 m → **125 segmentos** XML.
- Painel de 3,8 m → **132 segmentos**.
- Painel de 6,7 m → **75 segmentos**.

As linhas não representam necessariamente mais objetos no mundo do jogo: são as instruções de traçado do sistema de cerca nativo. Tentar gerar só 7 linhas para 500 m foi o erro.

### Como testar

1. Use a **mesma spline** \`.i3d\` exportada pelo GIANTS Editor 10.0.14, com \`.i3d.shapes\` ao lado.
2. Abra o EXE fora da pasta mods; escolha \`FS25_Brazilian_fences\` e o XML da cerca.
3. Escolha a porteira nativa, clique no lugar desejado na prévia 2D (se precisar) e selecione uma **cópia** do \`placeables.xml\` do savegame.
4. Mantenha selecionado **PRECISO: 1 painel por segmento**. Não use compactação experimental nesta etapa.
5. Marque **Só conferir/prévia** e clique em **Conferir/Gerar XML**.
6. Para gravar, desmarque prévia. Se o arquivo contiver uma cerca antiga **do mesmo modelo e mesmo traçado**, a v1.0 perguntará se deseja substituí-la. Outras sobreposições bloqueiam a geração por segurança.
7. Teste no FS25: verifique distância dos postes, fios e encaixe da porteira. **Demolição/animação devem continuar funcionando** porque nenhuma lógica desses recursos foi alterada.

### Observações

- O programa não corrige automaticamente colisões, rotação ou orientação física da porteira no mod. Esses casos exigem análise específica do I3D e da geometria dentro do jogo.
- Uma spline com curvas muito fechadas pode precisar de ajustes no Editor para que os postes sejam bem distribuídos.
- A detecção de cercas duplicadas é conservadora; se um traçado antigo diferir demais do novo, o programa bloqueia ou exige inspeção manual.
- É uma **versão beta**. Não teste no único savegame que você possui.
