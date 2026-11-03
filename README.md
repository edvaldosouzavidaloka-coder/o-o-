# Mods para Farming Simulator 25

## Transbordo Inteligente — versão de teste 0.5.0.0

[Baixar FS25_TransbordoInteligente.zip](FS25_TransbordoInteligente.zip) · [Instruções](transbordo-inteligente/LEIA-ME.md) · [Código Lua](transbordo-inteligente/TransbordoInteligente.lua)

Atende colheitadeiras com pelo menos 60% de grãos, com jogador ou funcionário nativo. Identifica a bazuca acoplada e usa a posição real do cano aberto e do receptor para alinhar o conjunto. Ao encher, procura a carreta ou caminhão com caçamba compatível mais próximo da borda do talhão, descarrega quando a engine confirmar o receptor e reinicia o ciclo.

**A versão 0.5 mantém direção direta e acrescenta proteção de proximidade.** Mede separadamente o corpo da colheitadeira e a plataforma engatada, usando dimensões e pontos de trabalho/marcadores do implemento. O alcance lateral vem do ponto real de descarga do cano. Reduz a velocidade e solicita frenagem antes do contato previsto com a plataforma, a colheitadeira e o conjunto completo do caminhão, incluindo a cabine. O HUD mostra a largura da plataforma e o alcance lateral do cano.

Não há cálculo de rotas nem leitura de cultura. A proteção cobre os conjuntos atualmente selecionados, com uma previsão geométrica de frenagem; não é um detector geral de postes, árvores ou todos os veículos do mapa. Se não houver folga suficiente para receber ou descarregar, aguarda reposicionamento.

Para atravessar cultura sem dano de rodas, o módulo usa o bloqueio nativo `getBlockFoliageDestruction` no trator e nos implementos acoplados enquanto estiver ativo. Não ativa nem altera a opção global de destruição de cultura da partida. Ao desligar ou desacoplar, restaura o comportamento anterior. Trabalho de ferramentas, como arar ou colher, é independente desse bloqueio de rodas.

Feche o jogo, substitua o ZIP anterior pelo arquivo 0.5.0.0, ative na partida e entre no trator com a bazuca. **Ctrl+Alt+T** liga/desliga; a ação **Ligar/desligar Transbordo Inteligente** aparece em **Opções > Controles** e na ajuda **F1**. O HUD informa o alvo escolhido e sua distância.

**Versão experimental, single-player.** Testes simulados verificam direção direta sem leitura de cultura, medição da plataforma, frenagem antes de contato, cabine do caminhão, manutenção de uma posição de recebimento confirmada, seleção de alvos, bloqueio de dano e descarga. Física, carregamento no FS25 e comportamento dos modelos escolhidos ainda precisam de confirmação no jogo.

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
