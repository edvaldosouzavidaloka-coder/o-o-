# Transbordo Inteligente — versão de teste 0.10.0.0

Controlador single-player para Farming Simulator 25, adaptado do arquivo enviado pelo usuário. Usa direção direta e o fluxo de grãos do próprio jogo. Não depende de TG GPS ou Courseplay. A lógica foi testada em Lua 5.1 com contratos simulados da engine; esta versão ainda precisa ser confirmada no FS25.

## Ajustes junto da carreta na versão 0.10

A chegada ao caminhão deixa de usar o recuo fixo de 50 m. Em vez de buscar um ponto distante, acompanha a linha lateral com uma mira à frente da projeção atual. Perto da carreta, calcula uma sequência local de frente e ré em trechos de 1,5 m, executados a 1,5 km/h. O painel identifica o trecho, o sentido e a distância entre o cano e a caçamba.

O cálculo mede o cano no referencial da bazuca e considera seu engate real e o raio de giro nativo do trator, quando informados. Assim, a articulação entre trator e bazuca não altera artificialmente o alcance lateral do cano. A faixa útil de recebimento vem dos limites do `autoAimTarget`, com folga de até 0,60 m nas pontas; sem esses limites, usa somente o ponto de recebimento conhecido, sem inventar o comprimento da caçamba. Não move os nós da mira do jogo.

O ajuste fica limitado a 22 m do centro da faixa, 36 m de deslocamento acumulado e quatro trocas de sentido por sequência, com até duas novas tentativas de cálculo. Confere as carrocerias, a cabine e o limite do talhão a cada amostra. Calcula até 60 nós por atualização e 5.000 por tentativa, sem `coroutine`. Sem espaço para uma sequência curta, para e informa o motivo; não substitui a tentativa por uma volta grande fora do campo.

Movimento lento é acumulado entre quadros para não provocar falsas pausas em taxas altas de quadros. Se realmente não observar movimento por 3 s, freia e confere a geometria novamente. Mudança do caminhão acima de 0,50 m ou 5 graus também invalida o ajuste. Ao chegar à caçamba sem confirmação do receptor por 30 s, retoma a busca. Se perder o recebimento durante a descarga, pode tentar outro ponto dentro da faixa útil, deslocando até 1,5 m, com no máximo seis tentativas.

## Captura de veículos

A busca reúne veículos e implementos das listas disponíveis da missão sem duplicar os objetos. Uma máquina com leitura inválida não interrompe a captura das outras. O receptor tenta a mira automática, o ponto exato e, por último, o ponto de enchimento normal, descartando nós removidos. Compartimentos também podem ser lidos pelo método `getFillUnits`. Um nó de descarga removido não fica preso no cache.

Com o cano aberto, a escolha da colheitadeira confere se a posição de atendimento cabe no talhão e prioriza centro livre e entrada traseira utilizável. Entre candidatas equivalentes, mantém a preferência pela mais cheia e depois pela mais próxima. O cano fechado ainda permite seleção; a geometria é conferida depois de abrir. A avaliação de outra máquina não muda os dados do alvo já selecionado.

Uma variação de direção de 8 graus na colheitadeira inicia uma espera de estabilização de 1,2 s, renovada enquanto a direção continua mudando. O trator permanece ligado e conserva a reserva. Uma falha temporária na leitura da carga conserva o alvo por até 2 s; remoção, troca de fazenda ou saída do talhão liberam a seleção imediatamente. As direções são normalizadas no plano horizontal para não confundir inclinação com curva.

Chegar ao ponto traseiro atravessado não conclui a aproximação: primeiro segue a linha de entrada até alinhar a direção. O posicionamento do cano e do receptor usa seus deslocamentos horizontais reais. O painel mostra sempre a versão e, com alvo selecionado, seu nome, distância e o campo fixado.

## Talhão fixo

Ative com o trator e a bazuca dentro do campo. O módulo fixa o polígono desse talhão e usa o mesmo limite até ser desligado. A propriedade rural e um raio de busca não substituem o contorno do campo. Sem um polígono válido, aguarda parado; não tenta sair à procura de outro campo. Uma conferência antes da condução também interrompe o automático se detectar uma carroceria já fora: desligue e reposicione manualmente para dentro. Ao trocar de talhão, desligue e ative novamente dentro dele.

A previsão confere as carrocerias do trator e dos implementos, incluindo a traseira da bazuca em ré, com folga de 0,35 m da borda. Considera as arestas do conjunto e recortes côncavos do campo. Antes de um giro, antecipa o limite para procurar uma direção interna; sem espaço, solicita frenagem. Isso não garante uma rota em todo formato de campo: cantos estreitos e conjuntos grandes podem exigir reposicionamento. O contorno é o original do mapa e não acompanha automaticamente alterações feitas com arado ou edição de terreno.

A mira usa o `autoAimTarget` do compartimento de carga, quando disponível, com o centro da faixa móvel de enchimento. Sem essa mira, usa o `exactFillRootNode` e depois o `fillRootNode`. A primeira confirmação de recebimento não fixa mais uma posição anterior: o objetivo continua sendo centralizar a bazuca sob o cano. O HUD informa o erro longitudinal e lateral durante essa correção.

A aproximação final usa velocidade mínima de 1,3 km/h enquanto ainda houver correção, pois `AIVehicleUtil.driveToPoint` deixa de acelerar abaixo de 1 km/h. A linha paralela é seguida por um ponto à frente da projeção atual. A entrada na colheitadeira exige passar pela zona traseira do conjunto medido. Procura um ponto recuado de até 50 m, reduzindo o recuo quando necessário para caber no campo. Se já estiver paralelo ao lado da máquina e houver espaço atrás, pode recuar em linha reta a até 3 km/h para se posicionar; depois avança até o cano. Se já estiver atrás do limite traseiro, avança diretamente. O trecho de recebimento é para frente; se ultrapassar o centro com a colheitadeira parada, refaz a entrada por trás.

O destino é procurado assim que a bazuca enche, com novas buscas a cada 250 ms quando necessário. Considera apenas receptores no talhão atual ou na borda alcançável pelo cano, exigindo espaço para manter trator e bazuca dentro do campo. Não busca mais carretas em outros campos ou rodovias distantes. A faixa inicial de seleção externa é de até 12 m da borda; a posição real do cano e a carroceria limitam o alcance utilizável. **Ctrl+Alt+D** solicita levar a carga atual até a carreta mesmo sem a bazuca estar cheia e respeita o mesmo limite do campo.

Usa a orientação da carreta, mesmo com a cabine virada, e escolhe entre os dois sentidos considerando o lado atual, o cano, a folga e o limite do talhão. O ajuste local também aceita descarregar parado em ângulo, desde que o cano fique a menos de 0,45 m da faixa útil e o jogo confirme o receptor exato. Isso evita exigir que todo o conjunto fique perfeitamente paralelo quando o cano já está na caçamba. Uma pequena ultrapassagem na chegada paralela ainda pode ser corrigida em ré reta a 1,5 km/h, até 8 m. A saída perto de uma plataforma usa ré reta de 12 m; a saída do caminhão busca espaço para frente e para dentro do campo.

Manobra em área livre a até **8 km/h**, reduz para até **5 km/h** nos giros e saídas próximos das máquinas e para até **4 km/h** no alinhamento final do caminhão. A proteção pode reduzir mais. A viagem continua limitada a 15 km/h.

Se a colheitadeira esvaziar e a bazuca ainda tiver espaço, permanece ligado aguardando a próxima carga ou atende outra colheitadeira elegível. Depois de esvaziar a bazuca no caminhão, libera a lateral e volta à busca. Uma falha temporária na leitura da carga aguarda nova leitura. A recuperação considera falta de progresso: mover pelo menos 25 cm ou variar a carga em pelo menos 1 litro reinicia o contador. Uma viagem longa não provoca pausa só por completar 120 segundos. Continua tentando automaticamente, sem exigir desligar e ligar o atalho.

## Proteção de proximidade

Mantém a direção direta nas viagens, sem planejamento de ruas, leitura de cultura ou biblioteca `coroutine`. A busca limitada de movimentos de estacionamento atua somente perto da carreta. Antes de enviar um comando positivo de velocidade, mede os conjuntos selecionados e verifica o movimento próximo:

- Corpo da colheitadeira e cada implemento acoplado, separadamente. A plataforma usa também seus pontos de trabalho (`start`, `width`, `height`) e marcadores de IA, quando informados pelo modelo. A largura considerada acompanha o implemento realmente engatado e sua orientação atual.
- Alcance lateral do cano, medido pelo nó de descarga aberto. Esse valor não é aumentado artificialmente para coincidir com a largura da plataforma.
- Trator e implementos próprios, incluindo uma previsão simplificada da articulação da bazuca. O conjunto receptor inclui a carreta selecionada e o veículo que a traciona; a cabine do caminhão também é considerada.

Uma aproximação por trás usa o limite traseiro do conjunto medido. A velocidade é reduzida e a frenagem é solicitada quando a previsão de movimento alcança o espaço de segurança da plataforma ou do veículo. Não exige recálculo de rota para funcionar.

O alvo de recebimento permanece no centro da bazuca. Na parte final paralela, a menos de 10 m do alinhamento, com erro lateral menor que 0,7 m e diferença de velocidade de até 3 km/h em relação ao alvo, a folga entre veículos pode baixar de 0,75 m para 0,20 m. Isso também vale no reposicionamento reto em ré da colheitadeira, na correção final do caminhão e no ajuste local de baixa velocidade. A margem da borda do campo continua sendo 0,35 m. Uma aproximação rápida mantém a margem de viagem. Sobreposição com a plataforma ou o corpo continua bloqueando o movimento. Se não permitir centralizar com folga e dentro do campo, permanece freado e informa o motivo. Reservar o caminhão durante a saída não remove a proteção da colheitadeira.

O HUD mostra **Plataforma: largura lateral** e **Alcance lateral do cano** separadamente. Se faltar largura nos dados e marcadores da plataforma, usa uma dimensão padrão conservadora e exibe “estimada”. Não transforma essa estimativa em um alcance fictício do cano.

A proteção cobre os conjuntos atualmente selecionados. Não faz desvio geral de árvores, postes, cercas ou todos os veículos do mapa. Se não houver espaço livre ou o cano não alcançar uma posição utilizável com esse conjunto, o trator pode aguardar parado. Se já estiver encostado, desligue e afaste manualmente antes de reativar. As colisões do jogo permanecem habilitadas.

O dano de rodas à lavoura é bloqueado localmente pelo método nativo `getBlockFoliageDestruction`, consultado por `Wheels:onUpdate`. Isso vale para o trator e seus implementos enquanto o módulo estiver ligado. A opção geral de destruição de cultura da partida não é ativada nem alterada. Ao desligar ou remover um implemento, o módulo restaura o callback anterior. Não recupera plantas já destruídas e não impede o trabalho de ferramentas, como arar, cultivar ou colher.

## Instalação e atalho

1. Feche o FS25. Substitua o ZIP antigo por **FS25_TransbordoInteligente.zip versão 0.10.0.0**, sem descompactar, na pasta `mods` usada pelo jogo. Remova outras cópias antigas deste mesmo mod, inclusive arquivos renomeados e pastas descompactadas.
2. Abra uma partida single-player, ative o mod e entre no trator com **uma bazuca** acoplada. Posicione o conjunto inteiro dentro do talhão antes de ligar o controlador.
3. Use **Ctrl esquerdo + Alt esquerdo + T** para ligar/desligar. Se a tecla não responder, procure **Ligar/desligar Transbordo Inteligente** em **Opções > Controles**, atribua a combinação e confira a ajuda **F1**. A ação continua sendo `TI_TOGGLE_TRANSBORDO`.
4. Use **Ctrl esquerdo + Alt esquerdo + D** para solicitar descarga na carreta com a carga atual. Também pode ativar o controlador se estiver desligado. A bazuca deve conter grãos; a ação é **Levar carga da bazuca ate a carreta** (`TI_FORCE_UNLOAD`). Se houver conflito, atribua outra tecla em Controles.
5. O mod informa **TRANSBORDO 0.10.0.0** no painel e a versão carregada em `log.txt`. Se o cabeçalho mostrar outro número, feche o jogo e confira a pasta de mods usada pela partida antes de reabrir.

## Atendimento da colheitadeira

As máquinas devem pertencer à mesma fazenda e estar no talhão fixado. A partir de **60%** do compartimento de grãos, a colheitadeira pode ser escolhida, com funcionário nativo ou jogador. Entre candidatas com a mesma condição de atendimento, prioriza a mais cheia e, em empate, a mais próxima. Uma posição de recebimento confirmadamente fora do talhão não pode ser selecionada. Não usa o tanque de combustível no cálculo e reserva o alvo para evitar duas bazucas deste mod atendendo a mesma máquina.

A direção aponta primeiro para uma posição atrás do conjunto medido e, depois, alinha o receptor da bazuca com a descarga, respeitando o limite de proximidade. O lado vem do cano real, seja esquerdo ou direito. Não usa a largura genérica da plataforma como substituta da posição do cano. Aguarda o cano abrir antes de usar sua geometria. Aceleração e esterço seguem os comandos enviados a `AIVehicleUtil.driveToPoint`.

Ao encher **99,9%**, seleciona o caminhão e sai da lateral. Se a colheitadeira esvaziar antes disso, mantém a carga parcial, permanece ativo junto dela e verifica se outra máquina com grão compatível precisa de atendimento. Sem outra elegível, aguarda e acompanha a colheitadeira atual; retoma quando ela acumular grãos novamente, sem exigir mais 60% para o atendimento já iniciado. Se o alvo esvaziar antes de a bazuca chegar perto, volta à busca.

## Caminhão e descarga

Estacione a carreta ou caminhão com caçamba no campo ou na borda, permitindo que a bazuca permaneça dentro. O destino precisa estar parado, pertencer à mesma fazenda, aceitar o grão, ter espaço e informar um receptor de enchimento válido. A seleção inclui carretas e veículos com volume de carga; exclui a própria bazuca, outras máquinas com cano, colheitadeiras, misturadores e semeadoras. Sem receptor disponível, permanece ativo buscando e informa se não existe carreta compatível neste talhão, se precisa parar o caminhão ou se os receptores estão ocupados.

Aproxima-se pela lateral no sentido escolhido, com ajustes locais de frente e ré quando necessário, e usa a mira do receptor, não apenas a cabine do caminhão. Aguarda a abertura completa do cano da bazuca antes de calcular o alinhamento. O HUD mostra o nome do alvo, a distância, a largura da plataforma e o alcance lateral do cano. A proteção considera também a cabine e os demais implementos do caminhão receptor. A bazuca só aciona `DISCHARGE_STATE_OBJECT` quando o jogo confirma exatamente o veículo e o compartimento selecionados sob o cano. Não programa descarga no chão e não transfere grãos alterando os níveis diretamente.

Se a carreta encher, procura outra e mantém o restante da carga. Se o destino começar a andar ou desaparecer, interrompe a descarga e procura um receptor disponível. Quando a bazuca esvazia, sai da lateral do caminhão e reinicia a busca por colheitadeiras, mantendo o automático ligado.

## Limites e parâmetros

- Não há planejamento de rotas de viagem, leitura de ruas ou desvio geral de obstáculos. Há direção direta, frenagem de proximidade e busca limitada de movimentos de estacionamento junto da carreta. Espaços sem manobra curta livre exigem reposicionamento. Os canos ajustáveis não têm regulagem automática de altura.
- O bloqueio de dano cobre o mecanismo nativo de destruição por rodas. Ao desligar o módulo, volta a valer o comportamento original e a configuração da partida. O efeito visual de dobrar plantas e o trabalho de outros implementos são mecanismos diferentes.
- Use uma bazuca por trator. Tratores articulados, esteiras, configurações especiais de direção, física de frenagem, alturas dos canos e desempenho real ainda não foram validados no FS25.
- O talhão vem do contorno original do mapa. Sem um contorno reconhecido na posição do trator, o automático aguarda parado. Reative ao trocar de campo. Uma carroceria já fora do campo exige reposicionamento manual para dentro antes de continuar.
- Os destinos precisam permitir alinhamento dentro do talhão e estar parados a menos de 1 km/h. Receptores internos têm preferência sobre os externos alcançáveis pela borda. Em cada grupo, escolhe o mais próximo. Acompanha colheitadeiras a até 15 km/h.
- Sem progresso por 120 s numa manobra, interrompe e repete automaticamente após 2 s. No recebimento, 30 s sem fluxo só inicia recuperação quando já está centralizado; durante a aproximação, usa o contador de progresso. Na descarga sem fluxo, libera o receptor e busca outro, evitando o mesmo destino por 10 s. O comando Ctrl+Alt+D permite uma nova tentativa imediata. Não desativa por espera ou tempo excedido. Obstáculo persistente ou conjunto incompatível ainda pode exigir reposicionamento. Não contrata ajudante visual, não cobra salário e não persiste o estado ligado entre partidas.
- Desative outro piloto do trator antes de ligar. O funcionário da colheitadeira pode continuar trabalhando. Multiplayer não é suportado.

Os valores ficam em `TransbordoInteligente.CONFIG`. As tolerâncias finais para centralizar na colheitadeira são **0,10 m longitudinal e 0,15 m lateral**. Na carreta, o ajuste local aceita o cano a menos de **0,45 m da faixa útil**, sempre com confirmação nativa do receptor. Os limites do ajuste ficam em `TIManobraCarreta.CONFIG`. A proteção fica em `TIProtecao.CONFIG`: margem entre veículos de 0,75 m, precisão de 0,20 m, folga da borda de 0,35 m, reação de 0,7 s, desaceleração estimada de 2 m/s² e previsão amostrada a cada 0,5 m. Em manobras, verifica até 12 m à frente para antecipar o giro junto ao limite do campo. Se o modelo não informar dimensões, usa padrões de 4 x 8 m para veículos e 12 x 3 m para plataforma, ajustados pelos marcadores disponíveis.

A previsão é geométrica e simplificada. A massa da carga, frenagem real, declives, raio de giro, configurações especiais e dados incorretos de modelos podem exigir ajuste. Precisa ser validada no FS25; não é uma garantia física contra toda colisão nem controla a condução manual da outra máquina.

## Teste no jogo

Comece em campo plano, com uma colheitadeira, um trator com bazuca e uma carreta. Confira o atalho e o alvo no HUD. Teste 59% e 60%, os dois modos de condução da colheitadeira, o alinhamento e a entrada real de grãos. Observe o centro da bazuca, a espera depois de esvaziar a colheitadeira e a retomada sem apertar o atalho. Teste a carreta dos dois lados, com a cabine virada e com o trator vindo de lado; deixe espaço para alinhar o conjunto. Atravesse uma pequena faixa de cultura e confira que os estados das plantas não são destruídos pelas rodas enquanto o módulo está ativo. Observe as medidas do HUD com a plataforma realmente acoplada. Teste recebimento atrás da plataforma, frenagem próxima ao limite, saída em ré reta e descarregamento perto da carreta e da cabine. Se a geometria não permitir receber sem atingir a plataforma, confira que permanece parado. Depois teste bazuca cheia, carreta cheia durante a transferência e pelo menos dois ciclos completos, mantendo o automático ligado. Por fim, teste desligamento e desacoplamento.

A verificação local não substitui esse teste de física e integração. Se houver erro, confira `Documentos/My Games/FarmingSimulator2025/log.txt` ou a pasta de documentos configurada no seu jogo.

## Fontes e desenvolvimento

- `TransbordoInteligente.lua`: direção, estados, seleção, alinhamento e bloqueio local de dano por rodas.
- `TIProtecao.lua`: dimensões e marcadores dos conjuntos, previsão local de proximidade e limite de velocidade. Não contém planejador de rotas.
- `TITalhao.lua`: contorno fixo, pontos e segmentos internos, carrocerias em campos côncavos e ajuste de pontos de manobra para dentro.
- `TIManobraCarreta.lua`: busca e execução limitada de movimentos locais de frente e ré junto da caçamba, usando a previsão articulada e as mesmas proteções.
- `Bootstrap.lua` e `modDesc.xml`: especialização dos tipos de veículo e ação de entrada.
- `tests/`: 170 testes simulados. Incluem cano curto de 4,2 m junto de um semirreboque longo, movimento articulado, ajustes de frente e ré, engate real, campo apertado, ausência de contato nas carrocerias medidas, limite de processamento e movimento lento a 60 quadros por segundo. Mantêm os testes de talhão fixo, seleção, carga, reservas, ciclos, dano local, registro e plataforma de 14,6 m com cano de 9,5 m. Não simulam física ou fluxo real de grãos.
- `package.py`: gera o ZIP do mod e um ZIP das fontes. O antigo planejador de viagem `TINavegacao.lua` continua removido; o novo módulo de estacionamento é incluído no pacote.

Com Python 3 e `lupa==2.6`:

```bash
python -m unittest discover -s tests -v
python package.py
```

Nesta máquina, o interpretador preparado é `/workspace/.onboarding/o-o-/.venv/bin/python`.

Referência do bloqueio nativo: [Wheels:onUpdate](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/Wheels.md#onupdate). As chamadas de direção, cano e descarga também foram confrontadas com exemplos públicos do [Courseplay FS25](https://github.com/Courseplay/Courseplay_FS25). Nenhum desses mods é incluído como dependência do pacote.

As estruturas da plataforma foram confrontadas com as interfaces [WorkArea](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/WorkArea.md) e [AIImplement](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/AIImplement.md) do FS25. Nenhum script de referência é carregado como dependência.
