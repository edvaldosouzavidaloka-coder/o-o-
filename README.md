# Mods para Farming Simulator 25

## Transbordo Inteligente — versão de teste 0.7.0.0

[Baixar FS25_TransbordoInteligente.zip](FS25_TransbordoInteligente.zip) · [Instruções](transbordo-inteligente/LEIA-ME.md) · [Código Lua](transbordo-inteligente/TransbordoInteligente.lua)

Atende colheitadeiras com pelo menos 60% de grãos, com jogador ou funcionário nativo. Identifica a bazuca acoplada e usa a posição real do cano aberto e do receptor para alinhar o conjunto. Ao encher, procura a carreta ou caminhão com caçamba compatível mais próximo da borda do talhão, descarrega quando a engine confirmar o receptor e reinicia o ciclo.

**A versão 0.7 exige entrada por trás da colheitadeira e mantém o centro da bazuca como objetivo.** Chegando ao lado ou pela frente, volta para a região traseira e avança em direção ao cano. A primeira confirmação de descarga não fixa mais uma posição anterior. O painel mostra os erros de alinhamento e a versão carregada.

**Ctrl+Alt+D solicita levar a carga atual para a carreta**, mesmo com a bazuca parcialmente cheia. A busca se repete a cada 250 ms, prioriza receptores locais e, sem destino disponível nessa região, considera carretas compatíveis em toda a missão. Continua exigindo mesma fazenda, grão aceito, capacidade livre, caminhão parado e confirmação exata do receptor pelo jogo.

Se a colheitadeira esvaziar antes da bazuca, aguarda a próxima carga ou atende outra máquina elegível. Depois de descarregar no caminhão, libera a lateral e reinicia o ciclo. A recuperação considera falta de progresso, evitando pausa apenas pelo tempo total de viagem. A aproximação ao cano da colheitadeira é para frente; se ultrapassar o centro com ela parada, refaz a entrada por trás. Correções curtas de ré ficam no caminhão e na saída perto da plataforma. Não exige desligar e ligar o atalho entre ciclos.

A proteção mede separadamente o corpo da colheitadeira e a plataforma engatada, usando dimensões e pontos de trabalho/marcadores do implemento. Na centralização final paralela e com baixa diferença de velocidade entre as máquinas, pode reduzir a folga de 0,75 m para 0,20 m, evitando uma parada antecipada por excesso de margem. Contato previsto com a plataforma ou com o caminhão continua bloqueando o avanço. Reservar o caminhão não remove a proteção da colheitadeira durante a saída.

Não há cálculo de rotas nem leitura de cultura. A proteção cobre os conjuntos atualmente selecionados, com uma previsão geométrica de frenagem; não é um detector geral de postes, árvores ou todos os veículos do mapa. Se não houver folga suficiente para receber ou descarregar, aguarda reposicionamento.

Para atravessar cultura sem dano de rodas, o módulo usa o bloqueio nativo `getBlockFoliageDestruction` no trator e nos implementos acoplados enquanto estiver ativo. Não ativa nem altera a opção global de destruição de cultura da partida. Ao desligar ou desacoplar, restaura o comportamento anterior. Trabalho de ferramentas, como arar ou colher, é independente desse bloqueio de rodas.

Feche o jogo, substitua o ZIP anterior pelo arquivo 0.7.0.0 e remova cópias antigas renomeadas ou descompactadas deste mod. Ative na partida e entre no trator com a bazuca. **Ctrl+Alt+T** liga/desliga; **Ctrl+Alt+D** solicita descarga. As duas ações aparecem em **Opções > Controles** e na ajuda **F1**. O painel deve mostrar **TRANSBORDO 0.7.0.0**. A mensagem “Pausado: confira o conjunto / Desligue e reposicione antes de reativar” é da lógica antiga.

**Versão experimental, single-player.** Os 113 testes simulados incluem oito aproximações com movimento cinemático, entrada por trás, mira central, plataforma de 14,6 m com cano de 9,5 m parada e trabalhando, busca global de carreta, descarga forçada, frenagem em ré, espera, progresso e dois ciclos completos sem reativar. Física, carregamento no FS25 e comportamento dos modelos escolhidos ainda precisam de confirmação no jogo.

### Desenvolvimento

As fontes, manifesto, registro, testes e empacotador estão em [`transbordo-inteligente/`](transbordo-inteligente/). O módulo local `TIProtecao.lua` deve acompanhar as fontes. O antigo planejador `TINavegacao.lua` continua removido; use o ZIP completo atualizado.

Com Python 3 e `lupa==2.6`:

```bash
cd transbordo-inteligente
python -m unittest discover -s tests -v
python package.py
cp FS25_TransbordoInteligente.zip ../FS25_TransbordoInteligente.zip
```

## Outros pacotes existentes

- [`FS25_TG_GPS.zip`](FS25_TG_GPS.zip): TG GPS PRO, com monitor e guias dentro do jogo.
- [`TG_GPS_SIM_Dashboard.zip`](TG_GPS_SIM_Dashboard.zip): referências dos botões do SIM Dashboard, sem preset importável e com uma versão anterior do GPS.

Os pacotes de TG GPS foram preservados.
