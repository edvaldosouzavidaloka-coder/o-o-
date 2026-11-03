# Mods para Farming Simulator 25

## Transbordo Inteligente — versão de teste 0.6.0.0

[Baixar FS25_TransbordoInteligente.zip](FS25_TransbordoInteligente.zip) · [Instruções](transbordo-inteligente/LEIA-ME.md) · [Código Lua](transbordo-inteligente/TransbordoInteligente.lua)

Atende colheitadeiras com pelo menos 60% de grãos, com jogador ou funcionário nativo. Identifica a bazuca acoplada e usa a posição real do cano aberto e do receptor para alinhar o conjunto. Ao encher, procura a carreta ou caminhão com caçamba compatível mais próximo da borda do talhão, descarrega quando a engine confirmar o receptor e reinicia o ciclo.

**A versão 0.6 melhora o alinhamento e mantém o automático ligado entre as cargas.** Usa a mira central da caçamba, corrige a parada antecipada na colheitadeira e segue uma linha paralela ao cano. No caminhão, usa a orientação da carreta e escolhe o sentido de aproximação considerando o lado do conjunto. A busca pelo destino começa ao encher e se repete a cada 250 ms quando necessário, com alcance de até 600 m e preferência pela borda do talhão.

Se a colheitadeira esvaziar antes da bazuca, aguarda a próxima carga ou atende outra máquina elegível. Depois de descarregar no caminhão, libera a lateral e reinicia o ciclo. Tempo excedido e ausência temporária de fluxo provocam nova tentativa automática. Pequenas ultrapassagens podem ser corrigidas em ré reta; a saída perto da plataforma também considera a ré. Não exige desligar e ligar o atalho entre ciclos.

A proteção mede separadamente o corpo da colheitadeira e a plataforma engatada, usando dimensões e pontos de trabalho/marcadores do implemento. Reduz a velocidade e solicita frenagem antes do contato previsto com a plataforma e com o caminhão completo, incluindo a cabine. Quando o centro estiver livre, continua até ele; se centralizar atingiria a plataforma, mantém uma posição anterior de recebimento confirmada pelo jogo. Reservar o caminhão não remove a proteção da colheitadeira durante a saída.

Não há cálculo de rotas nem leitura de cultura. A proteção cobre os conjuntos atualmente selecionados, com uma previsão geométrica de frenagem; não é um detector geral de postes, árvores ou todos os veículos do mapa. Se não houver folga suficiente para receber ou descarregar, aguarda reposicionamento.

Para atravessar cultura sem dano de rodas, o módulo usa o bloqueio nativo `getBlockFoliageDestruction` no trator e nos implementos acoplados enquanto estiver ativo. Não ativa nem altera a opção global de destruição de cultura da partida. Ao desligar ou desacoplar, restaura o comportamento anterior. Trabalho de ferramentas, como arar ou colher, é independente desse bloqueio de rodas.

Feche o jogo, substitua o ZIP anterior pelo arquivo 0.6.0.0, ative na partida e entre no trator com a bazuca. **Ctrl+Alt+T** liga/desliga; a ação **Ligar/desligar Transbordo Inteligente** aparece em **Opções > Controles** e na ajuda **F1**. O HUD informa o alvo escolhido, a distância e quando está aguardando a próxima carga com o automático ligado.

**Versão experimental, single-player.** Os 95 testes simulados incluem seis aproximações com movimento cinemático, mira central, direção nos dois sentidos, frenagem em ré, plataforma, cabine, espera, retomada e dois ciclos completos sem reativar. Física, carregamento no FS25 e comportamento dos modelos escolhidos ainda precisam de confirmação no jogo.

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
