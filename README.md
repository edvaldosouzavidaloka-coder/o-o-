# Mods para Farming Simulator 25

## Transbordo Inteligente — versão de teste 0.10.0.0

[Baixar FS25_TransbordoInteligente.zip](FS25_TransbordoInteligente.zip) · [Instruções](transbordo-inteligente/LEIA-ME.md) · [Código Lua](transbordo-inteligente/TransbordoInteligente.lua)

Atende colheitadeiras com pelo menos 60% de grãos, com jogador ou funcionário nativo. Identifica a bazuca acoplada e usa a posição real do cano aberto e do receptor para alinhar o conjunto. Ao encher, procura a carreta ou caminhão com caçamba compatível mais próximo da borda do talhão, descarrega quando a engine confirmar o receptor e reinicia o ciclo.

**A versão 0.10 retira o recuo fixo de 50 m usado na chegada ao caminhão.** A aproximação acompanha a lateral e, perto da carreta, usa movimentos locais de frente e ré em trechos de 1,5 m. Mede o cano em relação à própria bazuca e usa o ponto de engate real, quando informado, evitando que a articulação do trator altere artificialmente o alcance calculado.

O ajuste considera a faixa útil da caçamba informada pelo modelo, com folga das extremidades. Sem essa faixa, usa o ponto de enchimento conhecido. Pode descarregar com o conjunto inclinado em relação ao caminhão parado quando houver folga e o cano estiver numa posição válida; não exige uma volta grande apenas para deixar os dois paralelos. A engine continua precisando confirmar exatamente a carreta e o compartimento corretos. A sequência local é limitada em percurso, área e trocas de marcha; sem espaço, aguarda reposicionamento.

**O limite do talhão continua ativo.** Ative com trator e bazuca dentro do campo: o contorno fica fixo até desligar. A previsão verifica o conjunto inteiro, inclusive a traseira da bazuca em ré, antecipa giros para dentro e solicita frenagem antes da borda. Sem um contorno válido, aguarda parado. Se detectar o conjunto já fora, interrompe a condução e informa para reposicioná-lo dentro; não muda de campo nem tenta voltar pela rodovia.

A captura percorre veículos e implementos sem duplicá-los, ignora leituras inválidas e procura outro receptor de enchimento quando a mira está ausente ou removida. Com o cano aberto, prioriza colheitadeiras com posição de atendimento e entrada traseira utilizáveis, mantendo a preferência pela mais cheia entre candidatas equivalentes. Uma falha breve de leitura da colheitadeira preserva a reserva por até 2 s.

Durante uma curva da colheitadeira, aguarda a direção estabilizar em vez de perseguir o cano em movimento. Chegar ao ponto traseiro atravessado não conclui mais a entrada: alinha a direção antes de avançar. O cálculo usa deslocamentos horizontais medidos do cano e da caçamba, com direção normalizada, e o painel identifica **o veículo selecionado e o campo fixado**.

**Ctrl+Alt+D solicita levar a carga atual para a carreta**, mesmo parcialmente cheia. A busca se repete a cada 250 ms e só aceita receptores no campo ou na borda alcançável pelo cano, com espaço para manter trator e bazuca dentro. Continua exigindo mesma fazenda, grão aceito, capacidade livre, caminhão parado e confirmação exata do receptor pelo jogo. A descarga local só é liberada com o cano próximo da faixa útil de recebimento.

O acompanhamento da colheitadeira mantém tolerâncias de **10 cm longitudinal e 15 cm lateral**. O ajuste local na carreta usa **1,5 km/h** e permite iniciar a descarga a menos de 45 cm da faixa útil, com confirmação nativa do receptor. Em área livre, manobra até 8 km/h; a viagem continua a até 15 km/h. A proteção pode reduzir mais.

Se a colheitadeira esvaziar antes da bazuca, aguarda a próxima carga ou atende outra máquina elegível do mesmo campo. Depois de descarregar no caminhão, libera a lateral e reinicia o ciclo. A recuperação considera falta de progresso. A entrada sob o cano continua sendo por trás e para frente; quando já chega paralelo ao lado da máquina, pode recuar em linha reta a até 3 km/h para se posicionar atrás, respeitando a borda. Não exige reativar entre ciclos.

A proteção mede separadamente o corpo da colheitadeira e a plataforma engatada. Na centralização final e no reposicionamento reto em baixa velocidade relativa, pode reduzir a folga entre máquinas de 0,75 m para 0,20 m. A folga do limite do campo permanece em 0,35 m. Contato previsto com a plataforma ou com o caminhão continua bloqueando o avanço. Reservar o caminhão não remove a proteção da colheitadeira durante a saída.

Não calcula rotas de viagem nem lê cultura. As sequências de estacionamento são locais, junto da carreta parada, sem buscar caminhos em ruas. O limite usa o contorno original do campo informado pelo mapa, sem acompanhar automaticamente alterações por arado ou edição de terreno. A proteção não é um detector geral de postes e árvores dentro do talhão. Se não houver espaço para manobrar, receber ou descarregar dentro do campo, aguarda reposicionamento.

Para atravessar cultura sem dano de rodas, o módulo usa o bloqueio nativo `getBlockFoliageDestruction` no trator e nos implementos acoplados enquanto estiver ativo. Não ativa nem altera a opção global de destruição de cultura da partida. Ao desligar ou desacoplar, restaura o comportamento anterior. Trabalho de ferramentas, como arar ou colher, é independente desse bloqueio de rodas.

Feche o jogo, substitua o ZIP pelo arquivo **0.10.0.0** e remova cópias antigas deste mod. Posicione o conjunto inteiro dentro do talhão e deixe o caminhão em uma borda alcançável por dentro. **Ctrl+Alt+T** liga/desliga; **Ctrl+Alt+D** solicita descarga. As ações aparecem em **Opções > Controles** e na ajuda **F1**. O painel deve mostrar **TRANSBORDO 0.10.0.0**. Desligue e reative ao trocar de campo.

**Versão experimental, single-player.** Os 170 testes simulados incluem aproximações com movimento articulado, cano de 4,2 m junto de um semirreboque longo, sequência de frente e ré, movimento lento a 60 quadros por segundo, ausência de contato nas carrocerias medidas, campo apertado, limite de processamento e confirmação nativa de descarga. Mantém os testes anteriores de talhão, plataforma, captura e ciclos. A física, o contorno do seu mapa e os modelos escolhidos ainda precisam de confirmação no FS25.

### Desenvolvimento

As fontes, manifesto, registro, testes e empacotador estão em [`transbordo-inteligente/`](transbordo-inteligente/). `TIManobraCarreta.lua` calcula e acompanha os ajustes locais; `TIProtecao.lua` e `TITalhao.lua` conferem a geometria e o limite do campo. O antigo planejador de viagem `TINavegacao.lua` continua removido; use o ZIP completo atualizado.

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
