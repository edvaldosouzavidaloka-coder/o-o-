# Transbordo Inteligente — versão de teste 0.2.0.0

Adaptação do `TransbordoInteligente.lua` enviado pelo usuário para Farming Simulator 25, single-player. A lógica foi testada com contratos simulados da engine em Lua 5.1; ainda não foi executada no FS25. O pacote não depende do TG GPS nem do Courseplay.

## Instalar e usar

1. Copie **FS25_TransbordoInteligente.zip**, sem descompactar, para `Documentos/My Games/FarmingSimulator2025/mods` no computador do jogo. Remova a versão anterior deste mesmo mod e evite carregar outra cópia do script ao mesmo tempo.
2. Ative o mod ao abrir uma partida single-player. Acople **uma bazuca** ao trator. Este arquivo controla o trator e identifica o compartimento de grãos da bazuca; não usa o tanque de combustível como carga.
3. Estacione o caminhão com uma carreta de grãos na borda do talhão, com espaço livre para aproximação por trás e pelo lado do cano. A carreta deve pertencer à mesma fazenda, aceitar a cultura e ter capacidade livre. Deixe a combinação parada e, para o primeiro teste, paralela ao sentido de aproximação do trator.
4. Posicione o trator com a bazuca no talhão ou junto à borda. Desative o funcionário ou outro piloto **desse trator**. Pressione **Ctrl+Alt+T** para ligar; a mesma tecla desliga. O atalho pode ser alterado em Opções > Controles.
5. As colheitadeiras podem estar com funcionário nativo ou com jogador. O controlador atende a partir de **60%** de grãos, prioriza a mais cheia e, em empate, a mais próxima. O mesmo alvo não é reservado simultaneamente por duas bazucas deste mod.
6. A bazuca se aproxima por trás da posição do cano e tenta colocar seu receptor sob ele. O cano da colheitadeira recebe o comando de abertura ao chegar perto; o fluxo de grãos continua sendo o do jogo.
7. Ao atingir **99,9%**, a bazuca tenta sair da lateral da colheitadeira, procura a carreta receptora compatível mais próxima da borda e alinha seu cano com o receptor dela. A descarga só é acionada se a engine confirmar **aquele veículo e aquele compartimento** sob o cano. Não há descarga programada no chão nem criação/transferência artificial de grãos.
8. Se a carreta encher antes de a bazuca esvaziar, o controlador interrompe a descarga e procura outra. Ao esvaziar, volta a procurar colheitadeiras a partir de 60%. Se a colheitadeira esvaziar antes da bazuca encher, a carga parcial é mantida para atender outra colheitadeira compatível; isso não força uma viagem ao caminhão.

Sem colheitadeira elegível, o trator para onde está; não há retorno automático ao ponto inicial. Sem carreta compatível, a bazuca espera parada. Se um alvo for removido, se a bazuca for desacoplada ou se outra IA assumir o trator, o controlador libera os alvos e interrompe seu controle.

## Limites desta implementação

- **Navegação direta em terreno livre.** Não implementa pathfinding, leitura de ruas, planejamento de cabeceiras, marcha à ré ou detecção/desvio geral de obstáculos. Não é equivalente ao navegador completo do Courseplay/AutoDrive. Valas, cercas, árvores, canteiros e aproximações apertadas exigem reposicionamento manual.
- Alinhamento, frenagem real, curvas, orientação dos nós e alcance/altura dos canos precisam de teste no FS25 com os modelos de trator, bazuca e carreta escolhidos. Canos ajustáveis não têm ajuste automático de altura nesta versão. Tratores articulados, esteiras e configurações especiais não foram validados.
- Use apenas uma bazuca por trator. A seleção automática da carreta é limitada a implementos com especialização de trailer, sem cano próprio. Outros transbordos, tanques, colheitadeiras, o próprio conjunto e implementos de outra fazenda são excluídos.
- O contorno é o campo original informado pelo mapa. Campos unidos ou alterados com arado não são reconhecidos como novo contorno. Ao ativar fora do campo, usa o campo da colheitadeira da mesma fazenda mais próxima, até 600 m. Reative ao mudar de talhão.
- Se o mapa não fornecer contorno, usa busca de colheitadeiras até 600 m do trator e carretas até 200 m do ponto em que foi ativado. Esse fallback não garante que todos os veículos estejam no mesmo talhão.
- Sem progresso no recebimento/descarga por 30 s, ou manobra de aproximação/saída por mais de 120 s, a versão pausa e mostra o motivo. Desligue, reposicione e reative. Não tenta resolver uma manobra impossível rodando indefinidamente.
- Single-player. Não há eventos de rede, sincronização multiplayer, contratação de funcionário visual, cobrança de salário ou persistência do estado ativo entre partidas. A versão original alterava flags internas da IA sem criar um job; esta não faz isso.

Os parâmetros ficam em `TransbordoInteligente.CONFIG` no início do Lua. Por padrão: chamada 60%, cheio 99,9%, velocidade de viagem 15 km/h, manobra 5 km/h, colheitadeira até 15 km/h e carreta até 60 m da borda original do campo. São valores iniciais para ajuste durante os testes.

## Validar no jogo

Comece com uma colheitadeira, uma bazuca e uma carreta, num campo plano e livre. Confira que 59% não chama e 60% chama; observe a aproximação e confirme que os grãos entram de fato na bazuca. Repita com funcionário e jogador. Depois teste duas colheitadeiras, tanque cheio, descarga no caminhão, carreta cheia durante a transferência e novo ciclo. Teste também desligar e desacoplar. O volume deve mudar somente pelo sistema de descarga do próprio jogo.

Confira mensagens de erro em `Documentos/My Games/FarmingSimulator2025/log.txt`. Um teste Lua simulado não confirma física ou integração do mod no jogo.

## Arquivos e desenvolvimento

- `TransbordoInteligente.lua`: especialização principal corrigida, também disponível separadamente. Sozinho, depende do registro da especialização, do evento de atualização e da ação `TOGGLE_TRANSBORDO` no mod que o carrega.
- `Bootstrap.lua` e `modDesc.xml`: registro nos tipos de veículos e atalho para o ZIP independente fornecido.
- `tests/`: 30 testes de regressão com objetos simulados. Exercitam limiar de chamada, vários alvos, prioridade, reserva, fazenda/talhão, cultura, compartimentos, acionamento da direção nativa, sequência de estados, descarga autorizada pela engine, capacidade, perda de alvo, watchdogs, cliente/servidor e registro da especialização. Não incluem simulação física do veículo nem movimentação real de grãos.
- `package.py`: gera o ZIP do mod e o pacote de fontes sem alterar o arquivo original enviado nem os ZIPs de TG GPS no repositório.

Reprodução dos testes com Python 3 e `lupa==2.6`:

```bash
python -m unittest discover -s tests -v
python package.py
```

No ambiente preparado nesta conversa, use `/workspace/.onboarding/o-o-/.venv/bin/python` como interpretador.

As chamadas `AIVehicleUtil.driveToPoint`, `getDischargeTargetObject`, `getCanDischargeToObject`, `setPipeState` e `aiPrepareLoading` foram confrontadas com exemplos públicos de uso no [Courseplay para FS25](https://github.com/Courseplay/Courseplay_FS25), referência consultada no commit `5cdd86f1c5bae0ded4af3845f067cd1535f9bbb8`. O controlador e os testes deste pacote são uma implementação própria; não contêm o Courseplay.
