# Transbordo Inteligente — versão de teste 0.5.0.0

Controlador single-player para Farming Simulator 25, adaptado do arquivo enviado pelo usuário. Usa direção direta e o fluxo de grãos do próprio jogo. Não depende de TG GPS ou Courseplay. A lógica foi testada em Lua 5.1 com contratos simulados da engine; esta versão ainda precisa ser confirmada no FS25.

## Proteção de proximidade da versão 0.5

Mantém a direção direta, sem planejador, fila de busca, leitura de cultura ou biblioteca `coroutine`. Antes de enviar um comando positivo de velocidade, mede os conjuntos selecionados e verifica o movimento próximo:

- Corpo da colheitadeira e cada implemento acoplado, separadamente. A plataforma usa também seus pontos de trabalho (`start`, `width`, `height`) e marcadores de IA, quando informados pelo modelo. A largura considerada acompanha o implemento realmente engatado e sua orientação atual.
- Alcance lateral do cano, medido pelo nó de descarga aberto. Esse valor não é aumentado artificialmente para coincidir com a largura da plataforma.
- Trator e implementos próprios, incluindo uma previsão simplificada da articulação da bazuca. O conjunto receptor inclui a carreta selecionada e o veículo que a traciona; a cabine do caminhão também é considerada.

Uma aproximação por trás usa o limite traseiro do conjunto medido. A velocidade é reduzida e a frenagem é solicitada quando a previsão de movimento alcança o espaço de segurança da plataforma ou do veículo. Não exige recálculo de rota para funcionar.

Quando a engine confirma que o cano da colheitadeira já pode descarregar na bazuca correta, e a posição está livre, o controlador mantém aquela posição longitudinal relativa à colheitadeira. Assim não tenta avançar até o centro exato da bazuca quando isso levaria a frente do trator contra a plataforma. Ajustes automáticos do cano também não puxam essa posição para frente.

O HUD mostra **Plataforma: largura lateral** e **Alcance lateral do cano** separadamente. Se faltar largura nos dados e marcadores da plataforma, usa uma dimensão padrão conservadora e exibe “estimada”. Não transforma essa estimativa em um alcance fictício do cano.

A proteção cobre os conjuntos atualmente selecionados. Não faz desvio geral de árvores, postes, cercas ou todos os veículos do mapa. Se não houver espaço livre ou o cano não alcançar uma posição utilizável com esse conjunto, o trator pode aguardar parado. Se já estiver encostado, desligue e afaste manualmente antes de reativar. As colisões do jogo permanecem habilitadas.

O dano de rodas à lavoura é bloqueado localmente pelo método nativo `getBlockFoliageDestruction`, consultado por `Wheels:onUpdate`. Isso vale para o trator e seus implementos enquanto o módulo estiver ligado. A opção geral de destruição de cultura da partida não é ativada nem alterada. Ao desligar ou remover um implemento, o módulo restaura o callback anterior. Não recupera plantas já destruídas e não impede o trabalho de ferramentas, como arar, cultivar ou colher.

## Instalação e atalho

1. Feche o FS25. Substitua o ZIP antigo por **FS25_TransbordoInteligente.zip versão 0.5.0.0**, sem descompactar, na pasta `mods` usada pelo jogo. Remova outra cópia antiga deste mesmo mod.
2. Abra uma partida single-player, ative o mod e entre no trator com **uma bazuca** acoplada.
3. Use **Ctrl esquerdo + Alt esquerdo + T** para ligar/desligar. Se a tecla não responder, procure **Ligar/desligar Transbordo Inteligente** em **Opções > Controles**, atribua a combinação e confira a ajuda **F1**. A ação continua sendo `TI_TOGGLE_TRANSBORDO`.
4. O mod informa a versão carregada em `log.txt`. Se ainda aparecer mensagem de cálculo de rota, confira se a partida foi reaberta e se o ZIP ativo é o 0.5.0.0.

## Atendimento da colheitadeira

As máquinas devem pertencer à mesma fazenda. A partir de **60%** do compartimento de grãos, a colheitadeira pode ser escolhida, com funcionário nativo ou jogador. O controlador prioriza a mais cheia e, em empate, a mais próxima. Não usa o tanque de combustível no cálculo e reserva o alvo para evitar duas bazucas deste mod atendendo a mesma máquina.

A direção aponta primeiro para uma posição atrás do conjunto medido e, depois, alinha o receptor da bazuca com a descarga, respeitando o limite de proximidade. O lado vem do cano real, seja esquerdo ou direito. Não usa a largura genérica da plataforma como substituta da posição do cano. Aguarda o cano abrir antes de usar sua geometria. Aceleração e esterço seguem os comandos enviados a `AIVehicleUtil.driveToPoint`.

Ao encher **99,9%**, o conjunto tenta sair da lateral e procura o caminhão. Se a colheitadeira esvaziar antes disso, mantém a carga parcial e procura outra com cultura compatível. Sem colheitadeira elegível, espera onde estiver.

## Caminhão e descarga

Estacione a carreta ou caminhão com caçamba na borda do talhão. O destino precisa estar parado, pertencer à mesma fazenda, aceitar o grão, ter espaço e informar um receptor de enchimento válido. A seleção inclui carretas e veículos com volume de carga; exclui a própria bazuca, outras máquinas com cano, colheitadeiras, misturadores e semeadoras.

Aproxima-se por trás da posição de alinhamento e usa o ponto real do receptor, não apenas a cabine do caminhão. O HUD mostra o nome do alvo, a distância, a largura da plataforma e o alcance lateral do cano. A proteção considera também a cabine e os demais implementos do caminhão receptor. A bazuca só aciona `DISCHARGE_STATE_OBJECT` quando o jogo confirma exatamente o veículo e o compartimento selecionados sob o cano. Não programa descarga no chão e não transfere grãos alterando os níveis diretamente.

Se a carreta encher, procura outra e mantém o restante da carga. Se o destino começar a andar ou desaparecer, interrompe a descarga e procura um receptor disponível. Quando a bazuca esvazia, reinicia a busca por colheitadeiras.

## Limites e parâmetros

- Não há planejamento de rotas, leitura de ruas, desvio geral de obstáculos ou manobra automática de ré. Há redução e frenagem de proximidade dos conjuntos selecionados. Há direção direta aos pontos de aproximação e alinhamento. Os canos ajustáveis não têm regulagem automática de altura.
- O bloqueio de dano cobre o mecanismo nativo de destruição por rodas. Ao desligar o módulo, volta a valer o comportamento original e a configuração da partida. O efeito visual de dobrar plantas e o trabalho de outros implementos são mecanismos diferentes.
- Use uma bazuca por trator. Tratores articulados, esteiras, configurações especiais de direção, física de frenagem, alturas dos canos e desempenho real ainda não foram validados no FS25.
- O talhão vem do contorno original do mapa. Ao ativar fora do campo, tenta usar o campo da colheitadeira da mesma fazenda mais próxima, até 600 m. Reative ao trocar de talhão. Sem contorno, procura colheitadeiras até 600 m do trator e destinos até 200 m da posição inicial. Esses raios não garantem que todos estejam no mesmo campo.
- Por padrão, aceita destinos até 60 m da borda original do campo e parados a menos de 1 km/h. Viaja até 15 km/h, faz a aproximação final a até 5 km/h e acompanha colheitadeiras a até 15 km/h.
- Sem fluxo por 30 s ou sem terminar uma aproximação por 120 s, pausa e mostra o motivo. Desligue, reposicione e reative. Não contrata ajudante visual, não cobra salário e não persiste o estado ligado entre partidas.
- Desative outro piloto do trator antes de ligar. O funcionário da colheitadeira pode continuar trabalhando. Multiplayer não é suportado.

Os valores de chamada, carga, velocidade, raios e tempos ficam em `TransbordoInteligente.CONFIG`. A proteção fica em `TIProtecao.CONFIG`, com margem inicial de 0,75 m, reação de 0,7 s, desaceleração estimada de 2 m/s², redução para até 5 e 2 km/h e previsão amostrada a cada 0,5 m. Se o modelo não informar dimensões, usa padrões de 4 x 8 m para veículos e 12 x 3 m para plataforma, ajustados pelos marcadores disponíveis.

A previsão é geométrica e simplificada. A massa da carga, frenagem real, declives, raio de giro, configurações especiais e dados incorretos de modelos podem exigir ajuste. Precisa ser validada no FS25; não é uma garantia física contra toda colisão nem controla a condução manual da outra máquina.

## Teste no jogo

Comece em campo plano, com uma colheitadeira, um trator com bazuca e uma carreta. Confira o atalho e o alvo no HUD. Teste 59% e 60%, os dois modos de condução da colheitadeira, o alinhamento e a entrada real de grãos. Atravesse uma pequena faixa de cultura e confira que os estados das plantas não são destruídos pelas rodas enquanto o módulo está ativo. Observe as medidas do HUD com a plataforma realmente acoplada. Teste aproximação por trás, recebimento com a frente atrás da plataforma, frenagem próxima ao limite e descarregamento perto da carreta e da cabine. Se a geometria não permitir receber sem atingir a plataforma, confira que permanece parado. Depois teste bazuca cheia, caminhão escolhido, descarga, carreta cheia durante a transferência, novo ciclo, desligamento e desacoplamento.

A verificação local não substitui esse teste de física e integração. Se houver erro, confira `Documentos/My Games/FarmingSimulator2025/log.txt` ou a pasta de documentos configurada no seu jogo.

## Fontes e desenvolvimento

- `TransbordoInteligente.lua`: direção, estados, seleção, alinhamento e bloqueio local de dano por rodas.
- `TIProtecao.lua`: dimensões e marcadores dos conjuntos, previsão local de proximidade e limite de velocidade. Não contém planejador de rotas.
- `Bootstrap.lua` e `modDesc.xml`: especialização dos tipos de veículo e ação de entrada.
- `tests/`: testes simulados de direção direta sem sensores, carga, reservas, alvos, alinhamento, descarga, dano local, restauração de callbacks e carregamento pelo manifesto.
- `package.py`: gera o ZIP do mod e um ZIP das fontes. O antigo `TINavegacao.lua` e o planejador continuam removidos. Os testes adicionais verificam plataformas largas e giradas, alcance do cano, recebimento confirmado, cabine do caminhão e frenagem em simulação cinemática.

Com Python 3 e `lupa==2.6`:

```bash
python -m unittest discover -s tests -v
python package.py
```

Nesta máquina, o interpretador preparado é `/workspace/.onboarding/o-o-/.venv/bin/python`.

Referência do bloqueio nativo: [Wheels:onUpdate](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/Wheels.md#onupdate). As chamadas de direção, cano e descarga também foram confrontadas com exemplos públicos do [Courseplay FS25](https://github.com/Courseplay/Courseplay_FS25). Nenhum desses mods é incluído como dependência do pacote.

As estruturas da plataforma foram confrontadas com as interfaces [WorkArea](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/WorkArea.md) e [AIImplement](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/AIImplement.md) do FS25. Nenhum script de referência é carregado como dependência.
