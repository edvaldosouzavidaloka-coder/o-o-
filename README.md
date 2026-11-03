# Mods para Farming Simulator 25

## Transbordo Inteligente — versão de teste 0.4.0.0

[Baixar FS25_TransbordoInteligente.zip](FS25_TransbordoInteligente.zip) · [Instruções](transbordo-inteligente/LEIA-ME.md) · [Código Lua](transbordo-inteligente/TransbordoInteligente.lua)

Atende colheitadeiras com pelo menos 60% de grãos, com jogador ou funcionário nativo. Identifica a bazuca acoplada e usa a posição real do cano aberto e do receptor para alinhar o conjunto. Ao encher, procura a carreta ou caminhão com caçamba compatível mais próximo da borda do talhão, descarrega quando a engine confirmar o receptor e reinicia o ciclo.

**A versão 0.4 usa direção direta.** Foram retirados o planejador, os sensores de cultura/colisão e a espera por cálculo de rota. O comando é enviado diretamente ao controlador nativo do trator. Não há desvio automático de postes, árvores ou outros obstáculos; as colisões normais do jogo permanecem.

Para atravessar cultura sem dano de rodas, o módulo usa o bloqueio nativo `getBlockFoliageDestruction` no trator e nos implementos acoplados enquanto estiver ativo. Não ativa nem altera a opção global de destruição de cultura da partida. Ao desligar ou desacoplar, restaura o comportamento anterior. Trabalho de ferramentas, como arar ou colher, é independente desse bloqueio de rodas.

Feche o jogo, substitua o ZIP anterior pelo arquivo 0.4.0.0, ative na partida e entre no trator com a bazuca. **Ctrl+Alt+T** liga/desliga; a ação **Ligar/desligar Transbordo Inteligente** aparece em **Opções > Controles** e na ajuda **F1**. O HUD informa o alvo escolhido e sua distância.

**Versão experimental, single-player.** Testes simulados verificam direção imediata sem sensores, seleção de alvos, alinhamento dos nós, bloqueio local de dano e ciclo de descarga. Física, carregamento no FS25 e comportamento dos modelos escolhidos ainda precisam de confirmação no jogo.

### Desenvolvimento

As fontes, manifesto, registro, testes e empacotador estão em [`transbordo-inteligente/`](transbordo-inteligente/). O antigo `TINavegacao.lua` foi removido; use o ZIP completo atualizado.

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
