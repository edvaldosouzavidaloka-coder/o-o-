# Mods para Farming Simulator 25

## Transbordo Inteligente — versão de teste 0.2.0.0

[Baixar FS25_TransbordoInteligente.zip](FS25_TransbordoInteligente.zip) · [Instruções de uso](transbordo-inteligente/LEIA-ME.md) · [Código Lua](transbordo-inteligente/TransbordoInteligente.lua)

O controlador atende colheitadeiras com pelo menos 60% de grãos, com funcionário nativo ou jogador, e identifica a bazuca acoplada ao trator. Ao encher, procura uma carreta compatível estacionada na borda do talhão. Só aciona a descarga quando o jogo confirma o veículo receptor e seu compartimento. Depois de esvaziar, reinicia a busca.

Copie o ZIP, sem descompactar, para a pasta `mods` do FS25 e ative na partida. No trator com a bazuca, **Ctrl+Alt+T** liga/desliga o controlador. Os veículos precisam pertencer à mesma fazenda.

**Versão experimental, single-player.** Passou em 30 testes com contratos simulados da engine em Lua 5.1, mas ainda não foi executada no FS25. Usa navegação direta em terreno livre; não calcula desvios de obstáculos, rotas por estradas ou manobras de ré. Física, frenagem, curvas e alcance dos canos precisam ser validados no jogo. Consulte os limites e o roteiro de teste no manual antes de usar.

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
