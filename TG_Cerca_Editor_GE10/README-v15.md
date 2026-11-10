# TG + EDVALDO — Cercas, Porteiras e PC Objects FS25 v1.5 (BETA)

## Prévia 3D interativa no painel direito

A área que antes mostrava apenas uma **linha verde 2D de cima** agora apresenta uma **visualização tridimensional em perspectiva** do local da spline, com solo, postes, fios, abertura e estrutura aproximada da porteira. Não precisa abrir outro programa ou criar outra spline.

### Controles da prévia

- **Botão direito do mouse + arrastar**: girar a câmera livremente (360°), com inclinação ajustável.
- **Roda do mouse**, ou botões **+ / −**: aproximar e afastar.
- **Frente** / **Cima**: alternar perspectiva frontal e superior.
- **↶ 45° / ↷ 45°**: girar a câmera em incrementos de 45°.
- **Clique sobre a cerca na prévia**: reposicionar a porteira ao longo da mesma spline I3D. A posição percentual à esquerda é atualizada e usada ao gerar o XML.
- **Inverter sentido 180° (porteira e cerca no XML)**: muda a direção do traçado nativo `newFence` ao gravar, invertendo os `start/end` de TODOS os segmentos em ordem oposta. Essa é uma inversão **real** do sentido da porteira e da cerca; o sistema nativo do FS25 não fornece um campo seguro de giro livre para uma porteira independente.

Abaixo do desenho, a prévia apresenta as coordenadas **X/Y/Z da spline no lugar escolhido**, comprimento do percurso e largura física da porteira do mod quando disponível.

### Importante: representação 3D aproximada, não malha 3D real

O Farming Simulator 25 usa malhas proprietárias `.i3d.shapes`, materiais/shaders e animações executadas pelo motor GIANTS. **Este visualizador não decodifica e renderiza essas malhas**. Ele desenha uma **maquete 3D esquemática** em perspectiva com postes, fios, travessas da porteira e terreno com a altura estimada da spline, respeitando as dimensões do modelo no XML. A aparência, texturas, dobradiças, abertura animada e colisão **não serão idênticas ao jogo**.

A função de inverter 180° altera o sentido de montagem completo para não deixar segmentos desconectados. **Não oferece giro arbitrário de 15/30/90° da porteira isolada**, porque isso a desalinharia da cerca nativa. A orientação física da porteira é definida pelos pontos de início/fim dos segmentos `newFence` e pelo modelo original.

### Como testar com o mod Brazilian Fences

1. Abra o novo `TG_EDVALDO_FS25_v15_PCObjects.exe`.
2. Selecione o mod de cerca, seu XML, a porteira e a spline `.i3d` (com `.i3d.shapes` ao lado).
3. A prévia 3D aparecerá automaticamente. Gire a câmera com o botão direito e dê zoom com a roda.
4. Clique no lugar da cerca onde quer a porteira. Veja o **X/Y/Z** informado. Evite curvas muito fechadas.
5. Se precisar que o lado da porteira seja invertido, marque **Inverter sentido 180°**. Observe a orientação da dobradiça na prévia.
6. Escolha o `placeables.xml` de **uma cópia do savegame**. Deixe `Só conferir/prévia` marcado e clique em `Conferir/Gerar XML`.
7. Quando tudo estiver certo, desmarque a prévia, confirme a substituição de cercas anteriores exatamente no mesmo traçado e grave. O programa gera backup.
8. Confira no FS25 a posição, o lado de abertura da porteira, a animação e a demolição.

### Mantido sem mudanças

O ajuste adaptativo dos painéis de cerca da versão v1.4.3, o cálculo da largura das porteiras com os I3Ds, a proteção contra duplicatas e a interface **ADICIONAR PC OBJECTS** (com minimização correta da janela principal) permanecem presentes.

**BETA** — os testes automáticos verificam projeção, interação da prévia, inversão correta de segmentos no XML e geração, mas o resultado da porta/fios deve ser confirmado dentro do FS25.
