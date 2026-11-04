# Adaptação do monitor e minimapa — TG GPS 0.9

Referência analisada: `FS25_CurveGPS.zip` enviado pelo usuário, versão `1.29.3.21`, com autoria de André Girotto no manifesto. A prioridade escolhida pelo usuário foi **monitor e minimapa**, mantendo o terminal verde e bege do TG GPS.

| Lógica observada na referência | Adaptação no TG GPS |
| --- | --- |
| O HUD usa a imagem e as coordenadas do PDA do jogo; calcula uma projeção com a máquina apontada para cima. | `TGGPSMapFrame.lua` centraliza posição, orientação, escala, projeção e transformação inversa. `TGGPSPDA.lua` calcula os quatro cantos UV nessa mesma projeção. |
| O monitor físico e o HUD consultam o mesmo estado de trabalho. | O painel e o LCD usam o mesmo enquadramento local e histórico de cobertura. A proporção do mapa é mantida com margens ajustadas a cada tela. |
| A pintura gravada fica fixa no mundo ao girar a câmera do mapa. | A grade original permanece intacta. Só a visualização é reprojetada e recortada em faixas dentro do mapa; sobreposições continuam destacadas. |
| O LCD usa atualização de 250 ms, pools de primitivas e limites de desenho. | O enquadramento usa esse intervalo, com filtro de vibrações quando parado. O cálculo da pintura é reutilizado enquanto a grade e a projeção forem iguais. O limite do TG permanece em 650 primitivas físicas e 130 faixas visuais de pintura. |
| O ícone acompanha a escala do mapa e há representação do implemento. | Os ícones de trator e colheitadeira acompanham o zoom com limites de legibilidade. Ferramentas levantadas continuam visíveis, sem criar cobertura. Áreas ativas reais têm prioridade sobre a representação estimada. |

A aba **MONITOR** permite escolher **MÁQUINA PARA CIMA** ou **NORTE PARA CIMA**. A preferência é salva com zoom e brilho em `modSettings/FS25_TG_GPS/hud.xml`. Configurações antigas usam máquina para cima como padrão.

A superfície base do LCD foi escurecida e a área útil foi ajustada às dimensões indicadas no renderer de referência para reduzir a borda clara. A intensidade dos materiais continua controlada pelo ajuste de brilho do TG GPS.

A implementação usa os módulos e controles existentes do TG GPS. O ZIP de referência é material de comparação e não é incluído no pacote distribuído.

Na correção 0.9.1, o carregamento do fundo aceita referências PNG atendidas por DDS e arquivos virtuais do jogo. `fileExists` não é usado como prova de indisponibilidade de um recurso `$data/` ou `$dataS/`. Para mapas personalizados, um overlay nativo já carregado também pode fornecer a referência. Arquivos personalizados ausentes continuam com aviso único e recuperação quando o arquivo ou DDS fica disponível.

Validação: **82 testes em Lua 5.1 simulada**, incluindo a resolução de texturas descrita acima, um ponto conhecido do mapa para verificar textura e orientação, recorte igual no painel e na cabine, pintura fixa durante curvas, limites de desenho e ícones, persistência da orientação e implemento levantado. XML, dependências e ZIP são conferidos pelo empacotador. Brilho, shaders, renderização, desempenho e colocação na cabine precisam de confirmação dentro do FS25. A pintura continua limitada à sessão atual, conforme as versões anteriores do TG GPS. Os avisos sobre malhas I3D não binárias permanecem até a conversão em GIANTS Editor.
