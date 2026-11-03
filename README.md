# Mods para Farming Simulator 25

## Transbordo Inteligente — versão de teste 0.8.0.0

[Baixar FS25_TransbordoInteligente.zip](FS25_TransbordoInteligente.zip) · [Instruções](transbordo-inteligente/LEIA-ME.md) · [Código Lua](transbordo-inteligente/TransbordoInteligente.lua)

Atende colheitadeiras com pelo menos 60% de grãos, com jogador ou funcionário nativo. Identifica a bazuca acoplada e usa a posição real do cano aberto e do receptor para alinhar o conjunto. Ao encher, procura a carreta ou caminhão com caçamba compatível mais próximo da borda do talhão, descarrega quando a engine confirmar o receptor e reinicia o ciclo.

**A versão 0.8 restringe o automático ao talhão atual.** Ative com trator e bazuca dentro do campo: o contorno fica fixo até desligar. A previsão verifica o conjunto inteiro, inclusive a traseira da bazuca em ré, antecipa giros para dentro e solicita frenagem antes da borda. Sem um contorno válido, aguarda parado. Não usa mais uma busca em outros campos para levar a bazuca até caminhões distantes.

**Ctrl+Alt+D solicita levar a carga atual para a carreta**, mesmo parcialmente cheia. A busca se repete a cada 250 ms e só aceita receptores no campo ou na borda alcançável pelo cano, com espaço para manter trator e bazuca dentro. Usa a caçamba e o sentido da carreta para alinhar. A primeira detecção na borda da caçamba não interrompe mais a aproximação: centraliza antes de iniciar a descarga. Continua exigindo mesma fazenda, grão aceito, capacidade livre, caminhão parado e confirmação exata do receptor pelo jogo.

As tolerâncias finais passaram para **10 cm longitudinal e 15 cm lateral**. A manobra em área livre subiu de **5 para 8 km/h**; perto das máquinas reduz para até 5 km/h, e o alinhamento final do caminhão para até 4 km/h. A proteção pode reduzir mais. A viagem continua a até 15 km/h.

Se a colheitadeira esvaziar antes da bazuca, aguarda a próxima carga ou atende outra máquina elegível do mesmo campo. Depois de descarregar no caminhão, libera a lateral e reinicia o ciclo. A recuperação considera falta de progresso. A entrada sob o cano continua sendo por trás e para frente; quando já chega paralelo ao lado da máquina, pode recuar em linha reta a até 3 km/h para se posicionar atrás, respeitando a borda. Não exige reativar entre ciclos.

A proteção mede separadamente o corpo da colheitadeira e a plataforma engatada. Na centralização final e no reposicionamento reto em baixa velocidade relativa, pode reduzir a folga entre máquinas de 0,75 m para 0,20 m. A folga do limite do campo permanece em 0,35 m. Contato previsto com a plataforma ou com o caminhão continua bloqueando o avanço. Reservar o caminhão não remove a proteção da colheitadeira durante a saída.

Não há planejador de rotas nem leitura de cultura. O limite usa o contorno original do campo informado pelo mapa, sem acompanhar automaticamente alterações por arado ou edição de terreno. A proteção não é um detector geral de postes e árvores dentro do talhão. Se não houver espaço para manobrar, receber ou descarregar dentro do campo, aguarda reposicionamento.

Para atravessar cultura sem dano de rodas, o módulo usa o bloqueio nativo `getBlockFoliageDestruction` no trator e nos implementos acoplados enquanto estiver ativo. Não ativa nem altera a opção global de destruição de cultura da partida. Ao desligar ou desacoplar, restaura o comportamento anterior. Trabalho de ferramentas, como arar ou colher, é independente desse bloqueio de rodas.

Feche o jogo, substitua o ZIP pelo arquivo **0.8.0.0** e remova cópias antigas deste mod. Posicione o conjunto inteiro dentro do talhão e deixe o caminhão em uma borda alcançável por dentro. **Ctrl+Alt+T** liga/desliga; **Ctrl+Alt+D** solicita descarga. As ações aparecem em **Opções > Controles** e na ajuda **F1**. O painel deve mostrar **TRANSBORDO 0.8.0.0**. Desligue e reative ao trocar de campo.

**Versão experimental, single-player.** Os 130 testes simulados incluem dez aproximações em movimento, frenagem nas bordas nos dois sentidos, recortes côncavos, giro interno antecipado, caminhão alcançável sem sair do campo, alinhamento antes da descarga, velocidade, plataforma, espera e ciclos completos. A física, o contorno do seu mapa e os modelos escolhidos ainda precisam de confirmação no FS25.

### Desenvolvimento

As fontes, manifesto, registro, testes e empacotador estão em [`transbordo-inteligente/`](transbordo-inteligente/). Os módulos `TIProtecao.lua` e `TITalhao.lua` acompanham as fontes. O antigo planejador `TINavegacao.lua` continua removido; use o ZIP completo atualizado.

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
