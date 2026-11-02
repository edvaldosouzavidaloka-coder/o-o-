# Transbordo Inteligente — versão de teste 0.3.0.2

Adaptação do `TransbordoInteligente.lua` enviado pelo usuário para Farming Simulator 25, single-player. A lógica foi testada com contratos simulados da engine em Lua 5.1; ainda não foi executada no FS25. O pacote não depende do TG GPS nem do Courseplay.

## Correção da leitura de cultura na 0.3.0.2

O aviso `Leitura de cultura indisponivel` na 0.3.0.1 podia ser causado pelo próprio sensor: ele exigia `g_currentMission.fruits`, uma estrutura antiga que não é necessária para a leitura no FS25. O controlador freava por não conseguir verificar a plantação.

O sensor agora consulta `FruitTypeDesc:getDataPlaneInfo()` (id do layer, primeiro canal e quantidade de canais), com suporte aos campos equivalentes do descritor do FS25. A tabela antiga fica apenas como compatibilidade opcional. Estados de área colhida são consultados por `getIsCut`/`cutStates`, usando a numeração do FS25. Estados iniciais e maduros continuam protegidos. Cada leitor usa modificadores próprios para não alterar filtros compartilhados do jogo.

Foram incluídos testes sem `g_currentMission.fruits`, cobrindo accessor nativo, campos do descritor, múltiplos estados colhidos, cultura não carregada no mapa e falha de leitura. Se faltar uma API ou metadado, a mensagem passa a indicar o item/cultura que falhou; o mod não desativa a proteção para continuar andando. A confirmação em um mapa real do FS25 ainda é necessária.

Referência da interface: [FruitTypeDesc — getDataPlaneInfo](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Fruits/FruitTypeDesc.md#getdataplaneinfo).

## Correção do carregamento na 0.3.0.1

A versão anterior podia mostrar `Especializacao nao encontrada: FS25_TransbordoInteligente.transbordoInteligente` mesmo com a declaração presente no manifesto: o Bootstrap tentava acessar os requisitos da classe pelo retorno do registro de especializações. A correção usa diretamente `TransbordoInteligente`, carregada pelo `modDesc.xml`, e passa o nome registrado apenas para `typeManager:addSpecialization`. Isso remove o bloqueio antes de registrar o atalho nos veículos. Se o script da classe realmente faltar, o diagnóstico agora informa o arquivo a conferir.

Os testes foram corrigidos para não fabricar um campo `classObject` e incluem o ciclo manifesto → classe → tipo de veículo → eventos → callback do atalho. São testes simulados, não uma confirmação de carregamento no FS25.

## Atalho que não aparece ou não responde

Nesta versão a ação tem um nome próprio, `TI_TOGGLE_TRANSBORDO`, para evitar colisão com o script anterior. Também foi corrigida a condição que registra o comando no veículo selecionado. O registro da especialização deixa de tentar sobrescrever uma função herdada que pode não estar registrada no tipo do veículo.

1. Feche o FS25, substitua `FS25_TransbordoInteligente.zip` pelo ZIP **0.3.0.2** e remova outra cópia antiga deste mesmo mod. Não basta substituir o ZIP com uma partida aberta: o script só é recarregado ao iniciar o jogo/partida.
2. Ative o mod na seleção da partida e entre no **trator**, com a bazuca acoplada.
3. Em **Opções > Controles**, procure **Ligar/desligar Transbordo Inteligente**. O padrão é **Ctrl esquerdo + Alt esquerdo + T**. Se aparecer sem tecla, ou se houver conflito, atribua a combinação nessa linha. Não é necessário apagar todas as configurações de controles.
4. Ao entrar em um veículo elegível, o mod informa que carregou. No menu de ajuda **F1**, a ação deve mostrar a tecla efetivamente cadastrada. Use essa tecla para ligar/desligar.
5. Se a ação nem aparecer em Controles/F1, o problema pode ser o carregamento do mod ou a compatibilidade do tipo de veículo. Confira `log.txt`: procure `[Transbordo Inteligente]`, a versão `0.3.0.2`, o registro nos tipos de veículos e eventuais erros. A versão do jogo e o modelo do trator precisam ser conferidos nesse caso; os testes locais não confirmam o carregamento no FS25.

## Instalar e usar

1. Copie **FS25_TransbordoInteligente.zip**, sem descompactar, para `Documentos/My Games/FarmingSimulator2025/mods` no computador do jogo. Remova a versão anterior deste mesmo mod e evite carregar outra cópia do script ao mesmo tempo.
2. Ative o mod ao abrir uma partida single-player. Acople **uma bazuca** ao trator. Este arquivo controla o trator e identifica o compartimento de grãos da bazuca; não usa o tanque de combustível como carga.
3. Estacione o caminhão com uma carreta de grãos na borda do talhão, com espaço para aproximação por trás e pelo lado do cano. A carreta deve pertencer à mesma fazenda, aceitar a cultura e ter capacidade livre. Deixe a combinação parada e, para o primeiro teste, paralela ao sentido de aproximação do trator. Comece sobre área colhida ou livre de cultura.
4. Posicione o trator com a bazuca no talhão ou junto à borda. Desative o funcionário ou outro piloto **desse trator**. Pressione **Ctrl+Alt+T** para ligar; a mesma tecla desliga. O atalho pode ser alterado em Opções > Controles.
5. As colheitadeiras podem estar com funcionário nativo ou com jogador. O controlador atende a partir de **60%** de grãos, prioriza a mais cheia e, em empate, a mais próxima. O mesmo alvo não é reservado simultaneamente por duas bazucas deste mod.
6. A bazuca busca uma rota por área sem cultura em pé até uma posição atrás do cano. O cano recebe comando de abertura e o trator espera que termine de abrir antes de usar sua posição. O lado é calculado pelo cano real, seja esquerdo ou direito; o controlador não escolhe o lado contrário para contornar um bloqueio durante o recebimento. O fluxo de grãos continua sendo o do jogo.
7. Ao atingir **99,9%**, a bazuca tenta sair da lateral da colheitadeira, procura a carreta receptora compatível mais próxima da borda e alinha seu cano com o receptor dela. A descarga só é acionada se a engine confirmar **aquele veículo e aquele compartimento** sob o cano. Não há descarga programada no chão nem criação/transferência artificial de grãos.
8. Se a carreta encher antes de a bazuca esvaziar, o controlador interrompe a descarga e procura outra. Ao esvaziar, volta a procurar colheitadeiras a partir de 60%. Se a colheitadeira esvaziar antes da bazuca encher, a carga parcial é mantida para atender outra colheitadeira compatível; isso não força uma viagem ao caminhão.

Sem colheitadeira elegível, o trator para onde está; não há retorno automático ao ponto inicial. Sem carreta compatível, a bazuca espera parada. Se um alvo for removido, se a bazuca for desacoplada ou se outra IA assumir o trator, o controlador libera os alvos e interrompe seu controle.

## Limites desta implementação

- **Rotas com desvio e direção direta.** O planejador próprio procura trajetórias somente para frente, com raio mínimo de curva. Consulta volumes de colisão do trator e dos implementos, inclui uma aproximação do arrasto da bazuca nas curvas, amostra os trechos entre os pontos e protege os estados de cultura desde o crescimento inicial. Área colhida é permitida; capim/prado não são tratados como cultura a proteger. Não altera a plantação nem o estado das colisões do mapa.
- Postes, construções, veículos e árvores são evitados quando o mapa fornece suas colisões. Árvores recebem margem adicional para afastar a rota da mata. **Vegetação decorativa sem colisão não é identificada como floresta por esses sensores.** Não há interpretação visual de imagens do mapa, leitor de ruas, planejamento de ré ou navegador completo equivalente ao Courseplay/AutoDrive.
- A direção é enviada diretamente ao controlador nativo `AIVehicleUtil.driveToPoint`; não escreve `rotatedTime`, não teleporta o veículo e não usa cruise control para forçar o movimento. A rota permanece estável enquanto válida, reduz a velocidade nas curvas e reavalia a frente usando uma distância de frenagem estimada. Se aparecer obstáculo, freia e recalcula. Durante recebimento, não troca de lado para escapar de cultura; aguarda faixa livre.
- O cálculo de rota é dividido entre quadros e tem limite de busca. Se não houver uma passagem suficiente para **todo o conjunto**, ou faltar leitura confiável de cultura/colisão, o trator permanece parado com uma mensagem. Não existe fallback que atravesse a cultura quando a rota falha. Começar já dentro da cultura também pode bloquear o movimento.
- Alinhamento, frenagem real, desempenho, inclinação do terreno, curvas, orientação dos nós e alcance/altura dos canos precisam de teste no FS25 com os modelos escolhidos. O arrasto usa um modelo cinemático simplificado, não a física GIANTS. Dimensões são lidas dos veículos; se o modelo não as informar, são usados valores conservadores configuráveis. Canos ajustáveis não têm ajuste automático de altura nesta versão. Tratores articulados, esteiras e configurações especiais não foram validados.
- Use apenas uma bazuca por trator. A seleção automática da carreta é limitada a implementos com especialização de trailer, sem cano próprio. Outros transbordos, tanques, colheitadeiras, o próprio conjunto e implementos de outra fazenda são excluídos.
- O contorno é o campo original informado pelo mapa. Campos unidos ou alterados com arado não são reconhecidos como novo contorno. Ao ativar fora do campo, usa o campo da colheitadeira da mesma fazenda mais próxima, até 600 m. Reative ao mudar de talhão.
- Se o mapa não fornecer contorno, usa busca de colheitadeiras até 600 m do trator e carretas até 200 m do ponto em que foi ativado. Esse fallback não garante que todos os veículos estejam no mesmo talhão.
- Sem progresso no recebimento/descarga por 30 s, ou manobra de aproximação/saída por mais de 120 s, a versão pausa e mostra o motivo. Desligue, reposicione e reative. Não tenta resolver uma manobra impossível rodando indefinidamente.
- Single-player. Não há eventos de rede, sincronização multiplayer, contratação de funcionário visual, cobrança de salário ou persistência do estado ativo entre partidas. A versão original alterava flags internas da IA sem criar um job; esta não faz isso.

Os parâmetros de atendimento ficam em `TransbordoInteligente.CONFIG`: chamada 60%, cheio 99,9%, viagem 15 km/h, manobra 5 km/h, colheitadeira até 15 km/h e carreta até 60 m da borda original do campo. `TransbordoNavegacao.CONFIG`, em `TINavegacao.lua`, configura raio mínimo de 10 m, margem de 0,6 m no conjunto, faixa adicional de 2,5 m nas árvores, amostragem a cada 1 m e orçamento de consultas por quadro. São valores iniciais para ajuste durante os testes no jogo.

## Validar no jogo

Comece com uma colheitadeira, uma bazuca e uma carreta, num campo plano. Confirme primeiro o comando em Controles/F1. Confira que 59% não chama e 60% chama, que o lado coincide com o cano aberto e que os grãos entram de fato na bazuca. Repita com funcionário e jogador e, se disponível, com cano para o outro lado. Teste uma faixa de cultura entre o trator e a máquina, um poste, árvores e um veículo entrando na frente. Confira que desvia por passagem livre e que para quando não houver passagem. Depois teste duas colheitadeiras, tanque cheio, descarga no caminhão, carreta cheia durante a transferência e novo ciclo. Teste desligar e desacoplar. O volume deve mudar somente pelo sistema de descarga do próprio jogo.

Confira mensagens de erro em `Documentos/My Games/FarmingSimulator2025/log.txt`. Um teste Lua simulado não confirma física ou integração do mod no jogo.

## Arquivos e desenvolvimento

- `TransbordoInteligente.lua`: especialização principal. Depende de `TINavegacao.lua`, do registro da especialização, dos eventos e da ação `TI_TOGGLE_TRANSBORDO`. Use o ZIP completo, não apenas a substituição deste Lua em uma versão antiga.
- `TINavegacao.lua`: planejador incremental, verificação de cultura/colisão e direção direta.
- `Bootstrap.lua` e `modDesc.xml`: registro nos tipos de veículos e atalho para o ZIP independente fornecido.
- `tests/`: testes de regressão com objetos simulados, incluindo rota ao redor de postes e árvores, cultura inicial/madura/colhida, arrasto da bazuca, percurso cinemático completo com desvio, obstáculos novos, leitura ausente, lado do cano e acionamento do atalho. Preservam os testes de atendimento, carga, descarga e reservas. Não incluem física GIANTS, pressão real de teclas ou movimentação real de grãos.
- `package.py`: gera o ZIP do mod e o pacote de fontes sem alterar o arquivo original enviado nem os ZIPs de TG GPS no repositório.

Reprodução dos testes com Python 3 e `lupa==2.6`:

```bash
python -m unittest discover -s tests -v
python package.py
```

No ambiente preparado nesta conversa, use `/workspace/.onboarding/o-o-/.venv/bin/python` como interpretador.

As chamadas `AIVehicleUtil.driveToPoint`, `getDischargeTargetObject`, `getCanDischargeToObject`, `setPipeState` e `aiPrepareLoading` foram confrontadas com exemplos públicos de uso no [Courseplay para FS25](https://github.com/Courseplay/Courseplay_FS25), referência consultada no commit `5cdd86f1c5bae0ded4af3845f067cd1535f9bbb8`. O controlador e os testes deste pacote são uma implementação própria; não contêm o Courseplay.
