# Mods para Farming Simulator 25

## Transbordo Inteligente — versão de teste 0.11.0.0

[Baixar FS25_TransbordoInteligente.zip](FS25_TransbordoInteligente.zip) · [Instruções](transbordo-inteligente/LEIA-ME.md) · [Código Lua](transbordo-inteligente/TransbordoInteligente.lua)

Atende colheitadeiras com pelo menos 60% de grãos, com jogador ou funcionário nativo. Identifica a bazuca acoplada e usa a posição real do cano aberto e do receptor para alinhar o conjunto. Ao encher, procura a carreta ou caminhão com caçamba compatível mais próximo da borda do talhão, descarrega quando a engine confirmar o receptor e reinicia o ciclo.

**A versão 0.11 tenta outras entradas quando o ajuste curto não encontra passagem.** Primeiro procura uma sequência pequena de frente e ré. Se ela falhar, amplia a busca de esterço e espaço interno; por último, testa curvas até uma entrada alinhada antes da caçamba. A tentativa maior só ocorre depois de esgotar a menor e confere o conjunto inteiro dentro do mesmo talhão. Não volta ao recuo fixo de 50 m para o caminhão.

O mapeamento mede a largura e o comprimento da carreta, a largura da bazuca, o alcance lateral real do cano, o engate e a cabine do caminhão. Compara posições de descarga nos dois sentidos e descarta as que sobrepõem carrocerias ou ultrapassam o talhão. O HUD mostra as medidas, as posições livres e a folga lateral mapeada. Usa a faixa útil da caçamba informada pelo modelo; sem essa faixa, usa somente o ponto de enchimento conhecido. A largura externa não cria uma abertura de carga fictícia. A engine continua precisando confirmar exatamente a carreta e o compartimento corretos.

As tentativas são limitadas em área, percurso, processamento e trocas de marcha. A maior pode precisar de mais espaço interno; se nenhuma tentativa encontrar passagem, permanece freado e ligado. Não sai do campo para completar uma manobra nem amplia artificialmente o cano.

**O limite do talhão continua ativo.** Ative com trator e bazuca dentro do campo: o contorno fica fixo até desligar. A previsão verifica o conjunto inteiro, inclusive a traseira da bazuca em ré, antecipa giros para dentro e solicita frenagem antes da borda. Sem um contorno válido, aguarda parado. Se detectar o conjunto já fora, interrompe a condução e informa para reposicioná-lo dentro; não muda de campo nem tenta voltar pela rodovia.

A captura percorre veículos e implementos sem duplicá-los, ignora leituras inválidas e procura outro receptor de enchimento quando a mira está ausente ou removida. Com o cano aberto, prioriza colheitadeiras com posição de atendimento e entrada traseira utilizáveis, mantendo a preferência pela mais cheia entre candidatas equivalentes. Uma falha breve de leitura da colheitadeira preserva a reserva por até 2 s.

Durante uma curva da colheitadeira, aguarda a direção estabilizar em vez de perseguir o cano em movimento. Chegar ao ponto traseiro atravessado não conclui mais a entrada: alinha a direção antes de avançar. O cálculo usa deslocamentos horizontais medidos do cano e da caçamba, com direção normalizada, e o painel identifica **o veículo selecionado e o campo fixado**.

**Ctrl+Alt+D solicita levar a carga atual para a carreta**, mesmo parcialmente cheia. A busca se repete a cada 250 ms e só aceita receptores no campo ou na borda alcançável pelo cano, com espaço para manter trator e bazuca dentro. Continua exigindo mesma fazenda, grão aceito, capacidade livre, caminhão parado e confirmação exata do receptor pelo jogo. A descarga local só é liberada com o cano próximo da faixa útil de recebimento.

O acompanhamento da colheitadeira mantém tolerâncias de **10 cm longitudinal e 15 cm lateral**. A chegada permite até **25 km/h** quando o trecho está alinhado, a colheitadeira está a mais de 40 m e a mira a mais de 20 m. Reduz para até 15 km/h ao se aproximar ou mudar de direção; as proteções podem reduzir mais. Na carreta, o ajuste final e a ré usam **1,5 km/h**; uma reentrada para frente distante da carga pode usar **3 km/h**. A descarga exige o cano a menos de 45 cm da faixa útil e confirmação nativa do receptor. A viagem ao caminhão continua limitada a 15 km/h.

Se a colheitadeira esvaziar antes da bazuca, aguarda a próxima carga ou atende outra máquina elegível do mesmo campo. Depois de descarregar no caminhão, libera a lateral e reinicia o ciclo. A recuperação considera falta de progresso. A entrada sob o cano continua sendo por trás e para frente; quando já chega paralelo ao lado da máquina, pode recuar em linha reta a até 3 km/h para se posicionar atrás, respeitando a borda. Não exige reativar entre ciclos.

A proteção mede separadamente o corpo da colheitadeira e a plataforma engatada. Na centralização final e no reposicionamento reto em baixa velocidade relativa, pode reduzir a folga entre máquinas de 0,75 m para 0,20 m. A folga do limite do campo permanece em 0,35 m. Contato previsto com a plataforma ou com o caminhão continua bloqueando o avanço. Reservar o caminhão não remove a proteção da colheitadeira durante a saída.

Não calcula rotas de viagem nem lê cultura. As sequências de estacionamento são locais, junto da carreta parada, sem buscar caminhos em ruas. O limite usa o contorno original do campo informado pelo mapa, sem acompanhar automaticamente alterações por arado ou edição de terreno. A proteção não é um detector geral de postes e árvores dentro do talhão. Se não houver espaço para manobrar, receber ou descarregar dentro do campo, aguarda reposicionamento.

Para atravessar cultura sem dano de rodas, o módulo usa o bloqueio nativo `getBlockFoliageDestruction` no trator e nos implementos acoplados enquanto estiver ativo. Não ativa nem altera a opção global de destruição de cultura da partida. Ao desligar ou desacoplar, restaura o comportamento anterior. Trabalho de ferramentas, como arar ou colher, é independente desse bloqueio de rodas.

Feche o jogo, substitua o ZIP pelo arquivo **0.11.0.0** e remova cópias antigas deste mod. Posicione o conjunto inteiro dentro do talhão e deixe o caminhão em uma borda alcançável por dentro. **Ctrl+Alt+T** liga/desliga; **Ctrl+Alt+D** solicita descarga. As ações aparecem em **Opções > Controles** e na ajuda **F1**. O painel deve mostrar **TRANSBORDO 0.11.0.0**. Desligue e reative ao trocar de campo.

**Versão experimental, single-player.** Os 183 testes simulados incluem falha do ajuste curto seguida de chegada por outra entrada dentro do campo, reentrada até um ponto exato sem faixa de carga, canos de 4,2 e 4,7 m, mapeamento de dimensões e cabine, campo sem espaço, orçamento de cálculo, HUD e chegada mais rápida com redução próxima. Mantêm os testes de movimento articulado, pausas a 60 quadros por segundo, talhão, plataforma, captura e ciclos. A física, o contorno do seu mapa e os modelos escolhidos ainda precisam de confirmação no FS25.

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
