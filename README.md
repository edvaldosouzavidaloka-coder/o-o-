# Mods para Farming Simulator 25

## Transbordo Inteligente — versão de teste 0.3.0.3

[Baixar FS25_TransbordoInteligente.zip](FS25_TransbordoInteligente.zip) · [Instruções de uso](transbordo-inteligente/LEIA-ME.md) · [Código Lua](transbordo-inteligente/TransbordoInteligente.lua)

**Correção 0.3.0.3:** remove a dependência de `coroutine`, ausente no ambiente do FS25 observado no log enviado. Essa dependência causava `TINavegacao.lua:264: attempt to index nil with 'create'` ao iniciar o planejamento. O progresso da busca agora fica em tabelas e avança por chamadas com orçamento limitado por quadro. Criação e avanço da busca são protegidos: uma falha solicita frenagem, limita novas tentativas e registra o diagnóstico sem repetir a mesma exceção a cada quadro. Os testes executam sem a biblioteca `coroutine`.

**Correção 0.3.0.2:** resolve o bloqueio `Leitura de cultura indisponivel` causado pela dependência da tabela antiga `g_currentMission.fruits`. A leitura usa `FruitTypeDesc:getDataPlaneInfo()` ou os dados do próprio descritor no FS25. Os estados colhidos são identificados por `getIsCut`/`cutStates`, sem deslocar sua numeração. A proteção continua ativa para cultura em crescimento e pronta para colher; dados ausentes ainda interrompem o movimento com diagnóstico específico.

**Correção 0.3.0.1:** remove a verificação incorreta que emitia `Especializacao nao encontrada: FS25_TransbordoInteligente.transbordoInteligente` e impedia a instalação da especialização nos veículos. O carregador usa a classe Lua definida pelo `modDesc.xml`, sem tratar os dados do registro como a própria classe. Os testes cobrem o carregamento pelo manifesto, a instalação no veículo e o callback do atalho; a confirmação no jogo continua necessária.

O controlador atende colheitadeiras com pelo menos 60% de grãos, com funcionário nativo ou jogador, e identifica a bazuca acoplada ao trator. Ao encher, procura uma carreta compatível estacionada na borda do talhão. Só aciona a descarga quando o jogo confirma o veículo receptor e seu compartimento. Depois de esvaziar, reinicia a busca.

A versão 0.3 planeja desvios de cultura em pé, postes, veículos e árvores com colisão. Considera o trator e a bazuca, acompanha o lado do cano aberto e usa direção nativa direta. Se não encontrar passagem ou se os sensores falharem, permanece parada. Vegetação decorativa sem colisão não é reconhecida como mata.

Copie o ZIP, sem descompactar, para a pasta `mods` do FS25 e ative na partida. No trator com a bazuca, **Ctrl+Alt+T** liga/desliga o controlador. Os veículos precisam pertencer à mesma fazenda.

**Atalho corrigido:** a ação agora é `TI_TOGGLE_TRANSBORDO`. Substitua a versão antiga com o jogo fechado e confira **Ligar/desligar Transbordo Inteligente** em **Opções > Controles** e na ajuda **F1**. Se estiver sem tecla, atribua a combinação nessa linha. O mod informa o carregamento e registra diagnósticos no `log.txt`. Veja o [passo a passo do atalho](transbordo-inteligente/LEIA-ME.md#atalho-que-não-aparece-ou-não-responde).

**Versão experimental, single-player.** Validada por testes com contratos simulados da engine em Lua 5.1, incluindo navegação e atalho, mas ainda não executada no FS25. Não planeja marcha à ré nem interpreta ruas. Física, frenagem, desempenho dos sensores, carregamento real do atalho, curvas e alcance dos canos precisam ser validados no jogo. Consulte os limites e o roteiro de teste no manual.

### Desenvolvimento

As fontes, o registro da especialização, o manifesto, os testes e o empacotador estão em [`transbordo-inteligente/`](transbordo-inteligente/).

Com Python 3 e `lupa==2.6` instalados:

```bash
cd transbordo-inteligente
python -m unittest discover -s tests -v
python package.py
```

O empacotador gera os ZIPs dentro dessa pasta. Para atualizar o pacote distribuído na raiz do repositório após validar mudanças:

```bash
cp FS25_TransbordoInteligente.zip ../FS25_TransbordoInteligente.zip
```

## Outros pacotes existentes

- [`FS25_TG_GPS.zip`](FS25_TG_GPS.zip): TG GPS PRO, com monitor e guias dentro do jogo.
- [`TG_GPS_SIM_Dashboard.zip`](TG_GPS_SIM_Dashboard.zip): referências de configuração dos botões do SIM Dashboard. Não é um preset importável e inclui uma versão anterior do mod GPS.

Os pacotes existentes de TG GPS foram preservados.
