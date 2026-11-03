# Transbordo Inteligente — versão de teste 0.7.0.0

Controlador single-player para Farming Simulator 25, adaptado do arquivo enviado pelo usuário. Usa direção direta e o fluxo de grãos do próprio jogo. Não depende de TG GPS ou Courseplay. A lógica foi testada em Lua 5.1 com contratos simulados da engine; esta versão ainda precisa ser confirmada no FS25.

## Entrada por trás, centralização e descarga da versão 0.7

A mira usa o `autoAimTarget` do compartimento de carga, quando disponível, com o centro da faixa móvel de enchimento. Se o modelo não informar essa mira, usa o `exactFillRootNode`. A primeira confirmação de recebimento não fixa mais uma posição anterior: o objetivo continua sendo centralizar a bazuca sob o cano. O HUD informa o erro longitudinal e lateral durante essa correção.

A aproximação final usa velocidade mínima de 1,3 km/h enquanto ainda houver correção, pois `AIVehicleUtil.driveToPoint` deixa de acelerar abaixo de 1 km/h. A linha paralela é seguida por um ponto à frente da projeção atual, evitando cruzar o alinhamento ao chegar de lado. A entrada na colheitadeira exige passar pela zona traseira do conjunto medido. Se chegar ao lado ou pela frente, busca um ponto recuado em pelo menos 50 m, começando o giro para fora da colheitadeira. Se já estiver alinhado atrás do limite traseiro, pode começar a avançar diretamente. Estar apenas perto do cano não elimina essa etapa. O trecho de recebimento avança para frente; se ultrapassar o centro com a colheitadeira parada, refaz a entrada por trás.

O destino é procurado assim que a bazuca enche, com novas buscas a cada 250 ms quando necessário. Primeiro considera receptores locais; se não houver um disponível, procura carretas compatíveis em toda a missão. **Ctrl+Alt+D** solicita levar a carga atual até a carreta mesmo sem a bazuca estar cheia. Usa a orientação da carreta, mesmo com a cabine virada, e escolhe entre os dois sentidos paralelos considerando o lado atual, o cano e a folga. No caminhão, uma pequena ultrapassagem pode ser corrigida em ré reta a 1,5 km/h, até 8 m. A saída perto de uma plataforma usa ré reta de 12 m; a saída do caminhão segue para frente e para fora. A proteção de proximidade considera o sentido do movimento.

Se a colheitadeira esvaziar e a bazuca ainda tiver espaço, permanece ligado aguardando a próxima carga ou atende outra colheitadeira elegível. Depois de esvaziar a bazuca no caminhão, libera a lateral e volta à busca. Uma falha temporária na leitura da carga aguarda nova leitura. A recuperação considera falta de progresso: mover pelo menos 25 cm ou variar a carga em pelo menos 1 litro reinicia o contador. Uma viagem longa não provoca pausa só por completar 120 segundos. Continua tentando automaticamente, sem exigir desligar e ligar o atalho.

## Proteção de proximidade

Mantém a direção direta, sem planejador, fila de busca, leitura de cultura ou biblioteca `coroutine`. Antes de enviar um comando positivo de velocidade, mede os conjuntos selecionados e verifica o movimento próximo:

- Corpo da colheitadeira e cada implemento acoplado, separadamente. A plataforma usa também seus pontos de trabalho (`start`, `width`, `height`) e marcadores de IA, quando informados pelo modelo. A largura considerada acompanha o implemento realmente engatado e sua orientação atual.
- Alcance lateral do cano, medido pelo nó de descarga aberto. Esse valor não é aumentado artificialmente para coincidir com a largura da plataforma.
- Trator e implementos próprios, incluindo uma previsão simplificada da articulação da bazuca. O conjunto receptor inclui a carreta selecionada e o veículo que a traciona; a cabine do caminhão também é considerada.

Uma aproximação por trás usa o limite traseiro do conjunto medido. A velocidade é reduzida e a frenagem é solicitada quando a previsão de movimento alcança o espaço de segurança da plataforma ou do veículo. Não exige recálculo de rota para funcionar.

O alvo de recebimento permanece no centro da bazuca. Na parte final paralela, a menos de 10 m do alinhamento, com erro lateral menor que 0,7 m e diferença de velocidade de até 3 km/h em relação à colheitadeira, a folga geométrica pode baixar de 0,75 m para 0,20 m. Isso evita parar antes do cano apenas por uma margem de viagem excessiva e permite acompanhar a máquina enquanto trabalha. A margem de viagem continua valendo numa aproximação rápida a uma máquina parada. Sobreposição real com a plataforma ou o corpo continua bloqueando o movimento. Se esse conjunto não permitir centralizar com folga, permanece freado e informa o motivo; não muda silenciosamente o objetivo para uma posição anterior. Reservar o caminhão durante a saída não remove a proteção da colheitadeira.

O HUD mostra **Plataforma: largura lateral** e **Alcance lateral do cano** separadamente. Se faltar largura nos dados e marcadores da plataforma, usa uma dimensão padrão conservadora e exibe “estimada”. Não transforma essa estimativa em um alcance fictício do cano.

A proteção cobre os conjuntos atualmente selecionados. Não faz desvio geral de árvores, postes, cercas ou todos os veículos do mapa. Se não houver espaço livre ou o cano não alcançar uma posição utilizável com esse conjunto, o trator pode aguardar parado. Se já estiver encostado, desligue e afaste manualmente antes de reativar. As colisões do jogo permanecem habilitadas.

O dano de rodas à lavoura é bloqueado localmente pelo método nativo `getBlockFoliageDestruction`, consultado por `Wheels:onUpdate`. Isso vale para o trator e seus implementos enquanto o módulo estiver ligado. A opção geral de destruição de cultura da partida não é ativada nem alterada. Ao desligar ou remover um implemento, o módulo restaura o callback anterior. Não recupera plantas já destruídas e não impede o trabalho de ferramentas, como arar, cultivar ou colher.

## Instalação e atalho

1. Feche o FS25. Substitua o ZIP antigo por **FS25_TransbordoInteligente.zip versão 0.7.0.0**, sem descompactar, na pasta `mods` usada pelo jogo. Remova outras cópias antigas deste mesmo mod, inclusive arquivos renomeados e pastas descompactadas.
2. Abra uma partida single-player, ative o mod e entre no trator com **uma bazuca** acoplada.
3. Use **Ctrl esquerdo + Alt esquerdo + T** para ligar/desligar. Se a tecla não responder, procure **Ligar/desligar Transbordo Inteligente** em **Opções > Controles**, atribua a combinação e confira a ajuda **F1**. A ação continua sendo `TI_TOGGLE_TRANSBORDO`.
4. Use **Ctrl esquerdo + Alt esquerdo + D** para solicitar descarga na carreta com a carga atual. Também pode ativar o controlador se estiver desligado. A bazuca deve conter grãos; a ação é **Levar carga da bazuca ate a carreta** (`TI_FORCE_UNLOAD`). Se houver conflito, atribua outra tecla em Controles.
5. O mod informa **TRANSBORDO 0.7.0.0** no painel e a versão carregada em `log.txt`. Se aparecer **“Pausado: confira o conjunto”** com **“Desligue e reposicione antes de reativar”**, a lógica antiga ainda está carregada. Feche o jogo e confira a pasta de mods usada pela partida antes de reabrir.

## Atendimento da colheitadeira

As máquinas devem pertencer à mesma fazenda. A partir de **60%** do compartimento de grãos, a colheitadeira pode ser escolhida, com funcionário nativo ou jogador. O controlador prioriza a mais cheia e, em empate, a mais próxima. Não usa o tanque de combustível no cálculo e reserva o alvo para evitar duas bazucas deste mod atendendo a mesma máquina.

A direção aponta primeiro para uma posição atrás do conjunto medido e, depois, alinha o receptor da bazuca com a descarga, respeitando o limite de proximidade. O lado vem do cano real, seja esquerdo ou direito. Não usa a largura genérica da plataforma como substituta da posição do cano. Aguarda o cano abrir antes de usar sua geometria. Aceleração e esterço seguem os comandos enviados a `AIVehicleUtil.driveToPoint`.

Ao encher **99,9%**, seleciona o caminhão e sai da lateral. Se a colheitadeira esvaziar antes disso, mantém a carga parcial, permanece ativo junto dela e verifica se outra máquina com grão compatível precisa de atendimento. Sem outra elegível, aguarda e acompanha a colheitadeira atual; retoma quando ela acumular grãos novamente, sem exigir mais 60% para o atendimento já iniciado. Se o alvo esvaziar antes de a bazuca chegar perto, volta à busca.

## Caminhão e descarga

Estacione a carreta ou caminhão com caçamba, de preferência na borda do talhão. O destino precisa estar parado, pertencer à mesma fazenda, aceitar o grão, ter espaço e informar um receptor de enchimento válido. A seleção inclui carretas e veículos com volume de carga; exclui a própria bazuca, outras máquinas com cano, colheitadeiras, misturadores e semeadoras. Sem receptor disponível, permanece ativo buscando e informa se não existe carreta compatível, se precisa parar o caminhão ou se os receptores estão ocupados.

Aproxima-se por trás no sentido paralelo escolhido e usa a mira do receptor, não apenas a cabine do caminhão. Aguarda a abertura completa do cano da bazuca antes de calcular o alinhamento. O HUD mostra o nome do alvo, a distância, a largura da plataforma e o alcance lateral do cano. A proteção considera também a cabine e os demais implementos do caminhão receptor. A bazuca só aciona `DISCHARGE_STATE_OBJECT` quando o jogo confirma exatamente o veículo e o compartimento selecionados sob o cano. Não programa descarga no chão e não transfere grãos alterando os níveis diretamente.

Se a carreta encher, procura outra e mantém o restante da carga. Se o destino começar a andar ou desaparecer, interrompe a descarga e procura um receptor disponível. Quando a bazuca esvazia, sai da lateral do caminhão e reinicia a busca por colheitadeiras, mantendo o automático ligado.

## Limites e parâmetros

- Não há planejamento de rotas, leitura de ruas ou desvio geral de obstáculos. Há redução e frenagem de proximidade dos conjuntos selecionados, direção direta e correções locais de ré reta. Não faz estacionamento complexo em ré. Os canos ajustáveis não têm regulagem automática de altura.
- O bloqueio de dano cobre o mecanismo nativo de destruição por rodas. Ao desligar o módulo, volta a valer o comportamento original e a configuração da partida. O efeito visual de dobrar plantas e o trabalho de outros implementos são mecanismos diferentes.
- Use uma bazuca por trator. Tratores articulados, esteiras, configurações especiais de direção, física de frenagem, alturas dos canos e desempenho real ainda não foram validados no FS25.
- O talhão vem do contorno original do mapa. Ao ativar fora do campo, tenta usar o campo da colheitadeira da mesma fazenda mais próxima, até 600 m. Reative ao trocar de talhão. Sem contorno, procura colheitadeiras até 600 m do trator. Na busca de destinos, 600 m da posição atual do cano é uma preferência local; sem receptor disponível nessa região, considera o restante da missão.
- Dentro do raio local, prioriza destinos até 60 m da borda original do campo. Sem contorno, prioriza até 200 m da posição inicial. Fora dessas preferências, escolhe o receptor disponível mais próximo. O destino precisa estar parado a menos de 1 km/h. Viaja até 15 km/h, aproxima-se a até 5 km/h e acompanha colheitadeiras a até 15 km/h.
- Sem progresso por 120 s numa manobra, interrompe e repete automaticamente após 2 s. No recebimento, 30 s sem fluxo só inicia recuperação quando já está centralizado; durante a aproximação, usa o contador de progresso. Na descarga sem fluxo, libera o receptor e busca outro, evitando o mesmo destino por 10 s. O comando Ctrl+Alt+D permite uma nova tentativa imediata. Não desativa por espera ou tempo excedido. Obstáculo persistente ou conjunto incompatível ainda pode exigir reposicionamento. Não contrata ajudante visual, não cobra salário e não persiste o estado ligado entre partidas.
- Desative outro piloto do trator antes de ligar. O funcionário da colheitadeira pode continuar trabalhando. Multiplayer não é suportado.

Os valores de chamada, carga, velocidade, raios e tempos ficam em `TransbordoInteligente.CONFIG`. As tolerâncias finais são 0,20 m longitudinal e 0,25 m lateral. A proteção fica em `TIProtecao.CONFIG`, com margem inicial de 0,75 m, margem de precisão de 0,20 m nas condições descritas acima, reação de 0,7 s, desaceleração estimada de 2 m/s², redução para até 5 e 2 km/h e previsão amostrada a cada 0,5 m. Se o modelo não informar dimensões, usa padrões de 4 x 8 m para veículos e 12 x 3 m para plataforma, ajustados pelos marcadores disponíveis.

A previsão é geométrica e simplificada. A massa da carga, frenagem real, declives, raio de giro, configurações especiais e dados incorretos de modelos podem exigir ajuste. Precisa ser validada no FS25; não é uma garantia física contra toda colisão nem controla a condução manual da outra máquina.

## Teste no jogo

Comece em campo plano, com uma colheitadeira, um trator com bazuca e uma carreta. Confira o atalho e o alvo no HUD. Teste 59% e 60%, os dois modos de condução da colheitadeira, o alinhamento e a entrada real de grãos. Observe o centro da bazuca, a espera depois de esvaziar a colheitadeira e a retomada sem apertar o atalho. Teste a carreta dos dois lados, com a cabine virada e com o trator vindo de lado; deixe espaço para alinhar o conjunto. Atravesse uma pequena faixa de cultura e confira que os estados das plantas não são destruídos pelas rodas enquanto o módulo está ativo. Observe as medidas do HUD com a plataforma realmente acoplada. Teste recebimento atrás da plataforma, frenagem próxima ao limite, saída em ré reta e descarregamento perto da carreta e da cabine. Se a geometria não permitir receber sem atingir a plataforma, confira que permanece parado. Depois teste bazuca cheia, carreta cheia durante a transferência e pelo menos dois ciclos completos, mantendo o automático ligado. Por fim, teste desligamento e desacoplamento.

A verificação local não substitui esse teste de física e integração. Se houver erro, confira `Documentos/My Games/FarmingSimulator2025/log.txt` ou a pasta de documentos configurada no seu jogo.

## Fontes e desenvolvimento

- `TransbordoInteligente.lua`: direção, estados, seleção, alinhamento e bloqueio local de dano por rodas.
- `TIProtecao.lua`: dimensões e marcadores dos conjuntos, previsão local de proximidade e limite de velocidade. Não contém planejador de rotas.
- `Bootstrap.lua` e `modDesc.xml`: especialização dos tipos de veículo e ação de entrada.
- `tests/`: 113 testes simulados de direção direta sem sensores, mira de carga, entrada pela traseira, descarga forçada, reservas, alvos, alinhamento, ré, espera, retomada por progresso, ciclos completos, dano local, restauração de callbacks e carregamento pelo manifesto. A convergência é exercitada em oito aproximações com movimento cinemático simplificado, sem simular física ou fluxo real de grãos. Inclui uma plataforma de 14,6 m com cano de 9,5 m para verificar a folga de precisão, parada e trabalhando a 8 km/h, sem liberar contato real.
- `package.py`: gera o ZIP do mod e um ZIP das fontes. O antigo `TINavegacao.lua` e o planejador continuam removidos. Os testes adicionais verificam plataformas largas e giradas, alcance do cano, recebimento confirmado, cabine do caminhão e frenagem em simulação cinemática.

Com Python 3 e `lupa==2.6`:

```bash
python -m unittest discover -s tests -v
python package.py
```

Nesta máquina, o interpretador preparado é `/workspace/.onboarding/o-o-/.venv/bin/python`.

Referência do bloqueio nativo: [Wheels:onUpdate](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/Wheels.md#onupdate). As chamadas de direção, cano e descarga também foram confrontadas com exemplos públicos do [Courseplay FS25](https://github.com/Courseplay/Courseplay_FS25). Nenhum desses mods é incluído como dependência do pacote.

As estruturas da plataforma foram confrontadas com as interfaces [WorkArea](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/WorkArea.md) e [AIImplement](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/AIImplement.md) do FS25. Nenhum script de referência é carregado como dependência.
