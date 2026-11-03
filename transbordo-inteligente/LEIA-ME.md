# Transbordo Inteligente — versão de teste 0.4.0.0

Controlador single-player para Farming Simulator 25, adaptado do arquivo enviado pelo usuário. Usa direção direta e o fluxo de grãos do próprio jogo. Não depende de TG GPS ou Courseplay. A lógica foi testada em Lua 5.1 com contratos simulados da engine; esta versão ainda precisa ser confirmada no FS25.

## O que mudou

Foram removidos o planejador e os sensores de cultura/colisão. O trator recebe imediatamente o ponto para onde deve dirigir, sem esperar por uma rota, faixa colhida ou dados de cultura. A mensagem “Calculando rota sem pisar na cultura” deixa de existir nesta versão. Não há desvio automático de obstáculos; as colisões normais do jogo continuam funcionando.

O dano de rodas à lavoura é bloqueado localmente pelo método nativo `getBlockFoliageDestruction`, consultado por `Wheels:onUpdate`. Isso vale para o trator e seus implementos enquanto o módulo estiver ligado. A opção geral de destruição de cultura da partida não é ativada nem alterada. Ao desligar ou remover um implemento, o módulo restaura o callback anterior. Não recupera plantas já destruídas e não impede o trabalho de ferramentas, como arar, cultivar ou colher.

## Instalação e atalho

1. Feche o FS25. Substitua o ZIP antigo por **FS25_TransbordoInteligente.zip versão 0.4.0.0**, sem descompactar, na pasta `mods` usada pelo jogo. Remova outra cópia antiga deste mesmo mod.
2. Abra uma partida single-player, ative o mod e entre no trator com **uma bazuca** acoplada.
3. Use **Ctrl esquerdo + Alt esquerdo + T** para ligar/desligar. Se a tecla não responder, procure **Ligar/desligar Transbordo Inteligente** em **Opções > Controles**, atribua a combinação e confira a ajuda **F1**. A ação continua sendo `TI_TOGGLE_TRANSBORDO`.
4. O mod informa a versão carregada em `log.txt`. Se ainda aparecer mensagem de cálculo de rota, confira se a partida foi reaberta e se o ZIP ativo é o 0.4.0.0.

## Atendimento da colheitadeira

As máquinas devem pertencer à mesma fazenda. A partir de **60%** do compartimento de grãos, a colheitadeira pode ser escolhida, com funcionário nativo ou jogador. O controlador prioriza a mais cheia e, em empate, a mais próxima. Não usa o tanque de combustível no cálculo e reserva o alvo para evitar duas bazucas deste mod atendendo a mesma máquina.

A direção aponta primeiro para uma posição atrás do cano e, depois, alinha o receptor da bazuca com a descarga. O lado vem do cano real, seja esquerdo ou direito. Não usa a largura genérica da plataforma como substituta da posição do cano. Aguarda o cano abrir antes de usar sua geometria. Aceleração e esterço seguem os comandos enviados a `AIVehicleUtil.driveToPoint`.

Ao encher **99,9%**, o conjunto tenta sair da lateral e procura o caminhão. Se a colheitadeira esvaziar antes disso, mantém a carga parcial e procura outra com cultura compatível. Sem colheitadeira elegível, espera onde estiver.

## Caminhão e descarga

Estacione a carreta ou caminhão com caçamba na borda do talhão. O destino precisa estar parado, pertencer à mesma fazenda, aceitar o grão, ter espaço e informar um receptor de enchimento válido. A seleção inclui carretas e veículos com volume de carga; exclui a própria bazuca, outras máquinas com cano, colheitadeiras, misturadores e semeadoras.

Aproxima-se por trás da posição de alinhamento e usa o ponto real do receptor, não apenas a cabine do caminhão. O HUD mostra o nome do alvo e a distância. A bazuca só aciona `DISCHARGE_STATE_OBJECT` quando o jogo confirma exatamente o veículo e o compartimento selecionados sob o cano. Não programa descarga no chão e não transfere grãos alterando os níveis diretamente.

Se a carreta encher, procura outra e mantém o restante da carga. Se o destino começar a andar ou desaparecer, interrompe a descarga e procura um receptor disponível. Quando a bazuca esvazia, reinicia a busca por colheitadeiras.

## Limites e parâmetros

- Não há planejamento de rotas, leitura de ruas, desvio de obstáculos ou manobra automática de ré. Há direção direta aos pontos de aproximação e alinhamento. Os canos ajustáveis não têm regulagem automática de altura.
- O bloqueio de dano cobre o mecanismo nativo de destruição por rodas. Ao desligar o módulo, volta a valer o comportamento original e a configuração da partida. O efeito visual de dobrar plantas e o trabalho de outros implementos são mecanismos diferentes.
- Use uma bazuca por trator. Tratores articulados, esteiras, configurações especiais de direção, física de frenagem, alturas dos canos e desempenho real ainda não foram validados no FS25.
- O talhão vem do contorno original do mapa. Ao ativar fora do campo, tenta usar o campo da colheitadeira da mesma fazenda mais próxima, até 600 m. Reative ao trocar de talhão. Sem contorno, procura colheitadeiras até 600 m do trator e destinos até 200 m da posição inicial. Esses raios não garantem que todos estejam no mesmo campo.
- Por padrão, aceita destinos até 60 m da borda original do campo e parados a menos de 1 km/h. Viaja até 15 km/h, faz a aproximação final a até 5 km/h e acompanha colheitadeiras a até 15 km/h.
- Sem fluxo por 30 s ou sem terminar uma aproximação por 120 s, pausa e mostra o motivo. Desligue, reposicione e reative. Não contrata ajudante visual, não cobra salário e não persiste o estado ligado entre partidas.
- Desative outro piloto do trator antes de ligar. O funcionário da colheitadeira pode continuar trabalhando. Multiplayer não é suportado.

Os valores de chamada, carga, velocidade, raios e tempos ficam em `TransbordoInteligente.CONFIG` no início do Lua.

## Teste no jogo

Comece em campo plano, com uma colheitadeira, um trator com bazuca e uma carreta. Confira o atalho e o alvo no HUD. Teste 59% e 60%, os dois modos de condução da colheitadeira, o alinhamento e a entrada real de grãos. Atravesse uma pequena faixa de cultura e confira que os estados das plantas não são destruídos pelas rodas enquanto o módulo está ativo. Depois teste bazuca cheia, caminhão escolhido, descarga, carreta cheia durante a transferência, novo ciclo, desligamento e desacoplamento.

A verificação local não substitui esse teste de física e integração. Se houver erro, confira `Documentos/My Games/FarmingSimulator2025/log.txt` ou a pasta de documentos configurada no seu jogo.

## Fontes e desenvolvimento

- `TransbordoInteligente.lua`: direção, estados, seleção, alinhamento e bloqueio local de dano por rodas.
- `Bootstrap.lua` e `modDesc.xml`: especialização dos tipos de veículo e ação de entrada.
- `tests/`: testes simulados de direção direta sem sensores, carga, reservas, alvos, alinhamento, descarga, dano local, restauração de callbacks e carregamento pelo manifesto.
- `package.py`: gera o ZIP do mod e um ZIP das fontes. O antigo `TINavegacao.lua` e os testes do planejador foram removidos porque essa funcionalidade não faz mais parte da versão 0.4.

Com Python 3 e `lupa==2.6`:

```bash
python -m unittest discover -s tests -v
python package.py
```

Nesta máquina, o interpretador preparado é `/workspace/.onboarding/o-o-/.venv/bin/python`.

Referência do bloqueio nativo: [Wheels:onUpdate](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Specializations/Wheels.md#onupdate). As chamadas de direção, cano e descarga também foram confrontadas com exemplos públicos do [Courseplay FS25](https://github.com/Courseplay/Courseplay_FS25). Nenhum desses mods é incluído como dependência do pacote.
