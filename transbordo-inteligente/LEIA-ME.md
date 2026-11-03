# Transbordo Inteligente PRO — versão de teste 0.12.0.0

Controlador single-player para Farming Simulator 25. Usa direção nativa e o fluxo de grãos do próprio jogo, sem depender de TG GPS ou Courseplay. A lógica foi verificada em Lua 5.1 com contratos simulados; a física, a interface nativa e os modelos ainda precisam de confirmação no FS25.

## Instalação e atalhos

1. Feche o FS25 e substitua o ZIP antigo por **FS25_TransbordoInteligente.zip 0.12.0.0**, sem descompactar, na pasta `mods` usada pela partida. Remova cópias antigas deste mesmo mod, incluindo arquivos renomeados e pastas descompactadas.
2. Abra uma partida single-player, ative o mod e entre no trator com **uma bazuca** acoplada. Posicione o conjunto inteiro dentro do talhão antes de ligar.
3. Confira **TRANSBORDO PRO** e **0.12.0.0** no painel lateral. A versão também é registrada em `log.txt`. Se mostrar outro número, confira a pasta de mods antes de reabrir o jogo.

| Atalho | Ação |
| --- | --- |
| Ctrl esquerdo + Alt esquerdo + T | Ligar/desligar o automático |
| Ctrl esquerdo + Alt esquerdo + D | Levar a carga atual até a carreta, mesmo parcial |
| Ctrl esquerdo + Alt esquerdo + H | Abrir/recolher o painel PRO |
| Ctrl esquerdo + Alt esquerdo + M | Liberar/recolher o mouse do painel |

As ações aparecem em **Opções > Controles** e na ajuda **F1**, com os nomes `TI_TOGGLE_TRANSBORDO`, `TI_FORCE_UNLOAD`, `TI_HUD_TOGGLE` e `TI_HUD_CURSOR`. Se houver conflito ou uma combinação não responder, atribua outra tecla. O automático também pode ser comandado pelos botões.

## HUD PRO e ajustes por trator

Os textos de condução saem do centro da tela e passam para um painel lateral escuro com quatro abas. O botão `::` permite arrastar o painel e `-` recolhe a janela. Ctrl+Alt+M permite clicar nos controles. Ao recolher, sair do veículo ou abrir o menu, o mod devolve o cursor e as permissões anteriores de rotação da câmera. Escape também recolhe o cursor.

| Aba | Controles |
| --- | --- |
| Controle | Iniciar/parar, descarregar, buscar colheitadeiras em 360°, próxima colheitadeira, geometria do conjunto e rotas ligadas/desligadas |
| Velocidades | Chegada à colheitadeira, viagem à carreta, manobra em área livre, entrada/alinhamento, ré e reposicionamento por trás |
| Ajustes | Laterais separadas da colheitadeira/carreta, avanço sob o cano, recuos de entrada e percentual automático de chamada |
| Campo | Mapear/recalcular, visualizar contorno/trator/alvo/rota e ativar rotas internas opcionais |

Os botões `-` e `+` alteram somente este trator. Os ajustes e a posição do HUD são salvos no XML do veículo ao salvar a partida. O automático permanece desligado ao carregar. **Restaurar ajustes padrão** restaura os valores numéricos de velocidades e posicionamento; não altera outros tratores, a opção de rotas ou a posição do painel.

Os valores são limites pedidos e continuam sujeitos à proteção de proximidade e ao talhão. Os padrões são 25 km/h para chegada distante e alinhada à colheitadeira, 15 km/h para viagem à carreta, 8 km/h para manobra aberta, 4 km/h para entrada, 1,5 km/h para ré e 3 km/h para reposicionamento. O ajuste curto junto da carreta conserva baixa velocidade e a recuperação de entrada junto da plataforma limita o avanço a 3 km/h. Curvas e proximidade podem reduzir mais.

O deslocamento lateral positivo aponta para a **direita da máquina atendida**, considerando a direção dela; o negativo aponta para a esquerda. **Avanço sob o cano** desloca o objetivo no sentido de trabalho da colheitadeira. Comece com mudanças de 0,10 m e observe a entrada real de grãos. O ajuste não estende o cano, não ignora colisões e não força transferência. Se for alterado durante a descarga, interrompe o fluxo antes de realinhar.

A prévia das quatro abas está em `docs/hud-pro.png` nas fontes do repositório. Ela é gerada pelos comandos de desenho do Lua; não é uma captura dentro do FS25.

## Busca 360° e atendimento da colheitadeira

A busca percorre veículos e implementos da missão em todas as direções, sem duplicar objetos. Uma leitura inválida não interrompe a captura das outras máquinas. A direção para a qual o trator está olhando não limita a busca.

**Buscar colheitadeira 360** pode antecipar o atendimento quando houver grãos, mesmo antes do percentual automático. **Próxima colheitadeira** exclui o alvo atual dessa tentativa. Conserva fazenda, compatibilidade de grão, capacidade, reserva e talhão. Perto de uma máquina, primeiro libera a lateral e depois procura outro alvo. Com a bazuca cheia, conduz à descarga na carreta. Não teleporta nem movimenta a outra máquina.

Na busca automática, o padrão é **60%** do compartimento de grãos, ajustável no painel. Pode atender funcionário nativo ou jogador. Prioriza posições de atendimento e entrada traseira utilizáveis; entre candidatas equivalentes, a mais cheia e depois a mais próxima. O cano fechado permite seleção, mas a geometria é conferida depois de abrir. Não usa combustível no cálculo e reserva o alvo para evitar duas bazucas deste mod na mesma máquina.

O receptor tenta `autoAimTarget`, `exactFillRootNode` e `fillRootNode`, descartando nós removidos. A mira usa o centro da faixa de enchimento quando disponível. O cálculo projeta o receptor com trator e bazuca alinhados e considera o engate medido: a articulação atual não desloca artificialmente o objetivo final. A primeira confirmação de recebimento não fixa uma posição anterior. Mantém o objetivo corrigido pelo usuário até centralizar.

A entrada procura primeiro uma posição atrás do conjunto medido, depois avança sob o cano. O lado vem do cano aberto, esquerdo ou direito, sem substituir seu alcance pela largura da plataforma. O recuo padrão de 50 m é reduzido quando necessário para caber no campo. Se já estiver paralelo e houver espaço atrás, pode recuar reto antes de avançar. O recebimento é para frente; se ultrapassar o centro com a colheitadeira parada, refaz a entrada.

Se ficar bloqueado por mais de 1 s a menos de 35 m de uma colheitadeira parada, tenta uma sequência de entrada com previsão articulada, carrocerias e talhão. Primeiro alinha atrás da plataforma; depois avança sob o cano. Mudança do alvo invalida a entrada prevista. Uma posição já sobreposta ou sem espaço permanece bloqueada.

Uma curva de pelo menos 8 graus inicia espera de estabilização de 1,2 s, renovada enquanto a direção muda. Uma falha temporária de leitura conserva o alvo por até 2 s; remoção, troca de fazenda ou saída do campo liberam a seleção. As direções são normalizadas no plano horizontal para não confundir inclinação com curva.

Se a colheitadeira esvaziar antes da bazuca, mantém a carga parcial e permanece ligado aguardando a próxima carga ou atendendo outra elegível. No atendimento já iniciado, retoma o recebimento sem exigir novamente 60%. Ao encher **99,9%**, seleciona a carreta e libera a lateral. Depois de esvaziar a bazuca no caminhão, sai da lateral e reinicia a busca, sem exigir reativar o atalho.

## Talhão fixo e rotas internas opcionais

Ative com o conjunto inteiro dentro do campo. O módulo fixa o polígono desse talhão até desligar. Propriedade rural ou raio de busca não substituem o contorno. Sem polígono válido, aguarda parado. Se detectar uma carroceria já fora, interrompe a condução: desligue e reposicione dentro. Ao trocar de campo, desligue e ative novamente.

A previsão verifica trator e implementos, inclusive a traseira da bazuca em ré, com folga de **0,35 m** da borda. Considera arestas e recortes côncavos. Antes de um giro, antecipa o limite e pode procurar uma direção interna. Não garante passagem em todo formato de campo. O contorno é o original do mapa, sem acompanhar automaticamente alterações por arado ou edição de terreno.

As rotas vêm **desligadas**. Abra Campo, use **Mapear / recalcular campo** e ative **Rotas internas**. Pode mapear antes de ligar; nesse caso, usa o campo da posição atual. Com o automático ligado, conserva o campo fixado. O desenho mostra contorno, trator em branco e alvo/rota em amarelo. O progresso aparece durante o cálculo, dividido entre atualizações.

O mapa deriva do polígono e da folga do conjunto acoplado. Procura corredores internos e evita as carrocerias das máquinas selecionadas. Os segmentos conferem recortes côncavos. A rota guia a viagem até a entrada; a centralização continua pelo controle de proximidade. Cada ordem passa pela previsão articulada e pelo mesmo bloqueio do talhão. Curvas na rota reduzem a velocidade.

A malha é limitada a 60 x 60 células, com tamanho mínimo de 6 m e um raio conservador do conjunto. Verifica até 80 células por atualização e expande até 32 nós por chamada de busca. Não usa `coroutine`, ruas, navegação entre campos, leitura de cultura ou sensores de árvores/postes. Não calcula todas as rotas fisicamente possíveis e pode recusar corredores em que a condução manual caberia. Sem rota reconhecida, aguarda; pode desligar Rotas e continuar pela direção direta, mantendo o bloqueio do campo. Recalcule após mudar o conjunto ou a posição de entrada.

## Caminhão, geometria e descarga

Estacione a carreta no campo ou numa borda alcançável, permitindo manter trator e bazuca dentro. O receptor deve estar parado a menos de 1 km/h, pertencer à mesma fazenda, aceitar o grão, ter capacidade e um ponto de enchimento válido. Exclui a própria bazuca, outras máquinas com cano, colheitadeiras, misturadores e semeadoras. Prefere receptores internos e, em cada grupo, os mais próximos. A busca se repete a cada 250 ms quando necessário. Não procura carretas em outros campos ou rodovias distantes. A faixa inicial externa é de até 12 m da borda; o cano e as carrocerias limitam o alcance realmente utilizável.

Aguarda o cano abrir e usa a orientação da carreta, inclusive com a cabine virada. Mede caçamba, largura da bazuca, alcance lateral real do cano, engate e cabine. Avalia posições de descarga nos dois sentidos e em ângulos intermediários, descartando sobreposição e saída do talhão. O HUD informa medidas, posições livres e folga lateral. Posições livres ainda precisam de uma sequência válida de chegada.

A faixa útil vem dos limites do `autoAimTarget`, com folga de até 0,60 m nas pontas. Sem esses limites, usa somente o ponto conhecido, sem inventar uma abertura com o comprimento externo da caçamba. Não move os nós da mira. Pode descarregar parado em ângulo quando o cano estiver a menos de 0,45 m da faixa corrigida e o jogo confirmar exatamente o veículo e o compartimento selecionados. A bazuca só aciona `DISCHARGE_STATE_OBJECT`; não descarrega no chão e não transfere grãos alterando níveis diretamente.

A chegada não usa recuo fixo de 50 m para o caminhão. Segue a lateral e tenta primeiro uma sequência curta de frente e ré. Se falhar, tenta mais estercos e espaço interno. Por último, também avalia curvas até uma entrada alinhada, com trecho final reto para estabilizar a bazuca. Só amplia depois de esgotar a tentativa menor.

As tentativas usam raios de 22, 36 e 60 m e percursos planejados máximos de 36, 66 e 150 m. O deslocamento total é limitado a 150 m, com até quatro recálculos por divergência ou bloqueio. As buscas permitem quatro, seis e oito trocas de sentido. Cada amostra confere carrocerias, cabine, articulação e polígono, sem dispensar o bloqueio do campo. Uma posição atravessada pode exigir mais percurso interno. Se esgotar as alternativas, fica freado e ligado com uma mensagem.

A busca local processa até 60 nós ou amostras de curva por chamada, com limites de 5.000/14.000/20.000 nós e até 600 curvas candidatas na última alternativa. Não usa `coroutine`. Movimento lento é acumulado entre quadros para evitar falsas pausas a 60 FPS. Sem movimento por 3 s, para e confere a geometria novamente. Mudança do caminhão acima de 0,50 m ou 5 graus invalida o ajuste.

Ao chegar sem confirmação nativa por 30 s, retoma a busca. Se perder o recebimento durante a descarga, pode tentar outro ponto na faixa útil, deslocando até 1,5 m, com até seis tentativas. Se a carreta encher, procura outra mantendo o restante da carga. Se ela andar ou desaparecer, interrompe a transferência e procura um destino disponível. A saída perto da plataforma usa ré reta; a saída do caminhão procura espaço para frente e para dentro do campo.

## Proteções e limites

A proteção mede separadamente corpo e implementos da colheitadeira. Na plataforma, usa dimensões, pontos de trabalho e marcadores de IA disponíveis. O cano é medido pelo nó de descarga aberto e não é aumentado para acompanhar a largura da plataforma. Sem largura válida, usa uma estimativa conservadora. O receptor inclui cabine e implementos do caminhão.

A margem de viagem entre carrocerias é 0,75 m. Em correções de baixa velocidade relativa, pode baixar para **0,20 m**; a margem do campo continua **0,35 m**. Sobreposição prevista com plataforma ou corpo permanece bloqueada. Reservar a carreta durante a saída não remove a proteção da colheitadeira. Não é um detector geral de postes, árvores, cercas ou todos os veículos do mapa. As colisões do jogo permanecem habilitadas.

O dano por rodas é bloqueado localmente por `getBlockFoliageDestruction`, consultado por `Wheels:onUpdate`, para o trator e os implementos enquanto o módulo estiver ativo. Não ativa nem altera a destruição global da partida. Ao desligar ou desacoplar, restaura o callback anterior. Não recupera plantas já destruídas e não impede trabalho de ferramentas, como arar ou colher.

Use uma bazuca por trator e desative outro piloto do trator antes de ligar. O funcionário da colheitadeira pode continuar. Multiplayer não é suportado. Não contrata ajudante visual nem cobra salário. Canos ajustáveis não têm controle automático de altura. Tratores articulados, esteiras, configurações especiais de direção, massa, declives e frenagem real ainda precisam de validação no FS25.

As tolerâncias para centralizar na colheitadeira são **0,10 m longitudinal e 0,15 m lateral** em relação ao objetivo corrigido. A aproximação final conserva no mínimo 1,3 km/h enquanto houver correção, pois o controlador nativo não acelera abaixo de 1 km/h. A proteção usa reação estimada de 0,7 s, desaceleração de 2 m/s² e amostras de 0,5 m. Em manobras, verifica até 12 m além para antecipar o limite. Sem dados, usa padrões de 4 x 8 m para veículos e 12 x 3 m para plataforma, ajustados por marcadores disponíveis.

A recuperação considera falta de progresso, não tempo total da viagem: mover 25 cm ou variar a carga em 1 litro reinicia o contador. O mecanismo geral pode repetir uma manobra sem progresso após 120 s, com 2 s de espera. No recebimento, 30 s sem fluxo só inicia recuperação quando já está centralizado. Na descarga sem fluxo, evita o receptor por 10 s. Ctrl+Alt+D permite nova tentativa. Obstáculo persistente ou conjunto incompatível pode exigir reposicionamento. A previsão geométrica não é garantia física contra toda colisão nem controla a condução manual da outra máquina.

## Verificação no jogo

Comece em campo plano com um trator/bazuca, uma colheitadeira e uma carreta. Confira os quatro atalhos, mouse, câmera e abas. Altere velocidades e laterais em pequenos passos; salve e recarregue para conferir os ajustes. Teste busca automática em 59%/60%, busca 360° com a máquina atrás, troca de alvo e entrada atrás da plataforma. Observe o centro da bazuca, a entrada real de grãos, a espera da próxima carga e dois ciclos completos sem reativar.

Teste a carreta dos dois lados, com cabine virada, chegada oblíqua e mudança do ponto de recebimento. Ative o mapa num campo com recorte e acompanhe o conjunto inteiro perto da borda, nos dois sentidos. Confira que sem passagem fica freado. Teste uma faixa de cultura, desligamento e desacoplamento. A verificação local não substitui física e integração. Se houver erro, consulte `Documentos/My Games/FarmingSimulator2025/log.txt` ou a pasta de documentos da sua instalação.

## Fontes e desenvolvimento

- `TransbordoInteligente.lua`: estados, seleção, alinhamento, comandos nativos e bloqueio local de dano por rodas.
- `TIHUD.lua`: painel lateral, botões, abas, arraste, cursor e devolução da câmera.
- `TIConfiguracao.lua`: ajustes por trator, limites de valores e XML do savegame.
- `TIRotasCampo.lua`: mapa e rotas internas incrementais, restritos ao campo.
- `TIManobraCarreta.lua`: geometria de descarga, alternativas locais e recuperação da entrada da colheitadeira.
- `TIProtecao.lua` e `TITalhao.lua`: carrocerias, previsão articulada, proximidade e contorno fixado.
- `Bootstrap.lua` e `modDesc.xml`: especialização dos veículos e quatro ações de entrada.
- `tests/`: 209 testes simulados. Incluem HUD, mouse/câmera, atalhos, XML por trator, busca atrás, mapa antes de reativar em outro campo, rota acompanhada em campo côncavo e recuperação junto de plataforma de 14,6 m/cano de 9,5 m. Mantêm carga, ciclos, reservas e dano local. Não simulam física ou fluxo real de grãos.
- `package.py`: valida manifesto/ações/versão e gera ZIP do mod e das fontes. O antigo `TINavegacao.lua` continua removido; as rotas opcionais ficam no novo `TIRotasCampo.lua`.

Com Python 3 e `lupa==2.6`:

```bash
python -m unittest discover -s tests -v
python package.py
```

Nesta máquina: `/workspace/.onboarding/o-o-/.venv/bin/python`. A prévia de desenho não faz parte do executável nem é necessária para os testes.

Referências públicas das interfaces nativas: [Wheels:onUpdate](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/Wheels.md#onupdate), [WorkArea](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/WorkArea.md), [AIImplement](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/AIImplement.md) e [API Lua FS25](https://github.com/MyGameSteamOfficial/fs25-lua-api). A integração de cursor/câmera também foi confrontada com o [Courseplay FS25](https://github.com/Courseplay/Courseplay_FS25). Nenhum desses projetos é dependência do pacote.
