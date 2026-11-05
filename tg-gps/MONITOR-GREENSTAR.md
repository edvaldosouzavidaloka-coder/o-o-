# GreenStar 3 — TG GPS 0.9.4.0

A tela da cabine usa o modelo e os DDS enviados. O GPS3000.dds reenviado é idêntico ao incluído: o modelo, a moldura e os arquivos originais foram preservados. O painel foi reorganizado conforme a referência Orientação enviada depois: dados da máquina à esquerda, visão azul central, ajustes de pista à direita e barra inferior de ícones. Os desenhos dos ícones originais são reaproveitados nessa barra. O PDA foi retirado da tela física. A janela central agora mostra guias azuis em perspectiva e a passada selecionada clara, calculadas a partir dos trajetos reais e da posição/orientação da máquina. A imagem do terreno continua disponível no terminal 2D (Ctrl+Alt+M).

A pintura do trabalho é **azul**, com azul mais escuro para uma segunda passagem real. A tela usa células únicas do histórico e materiais opacos, redesenhados com objetos reutilizados em cada quadro. Atualizações consecutivas não acumulam transparência ou hectares. A projeção da grade é aproximada por faixas limitadas ao visor; não é uma captura 3D do terreno e não simula relevo.

Os desenhos dos ícones de Mapping, Guidance, Resources, Equipment, Water, Document e Totals continuam recortes da própria textura. Recebem pulsos de brilho conforme trabalho, piloto, campo reconhecido, implemento, pulverização, gravação e área medida. O símbolo central muda entre trator/colheitadeira e reage ao comando de direção. Os botões impressos continuam arte; os comandos reais usam o terminal TG e os atalhos existentes.

Ao ligar o motor há inicialização com a arte original, barra progressiva e indicador giratório. Após 1,8 segundo aparece a orientação em perspectiva. Há sons próprios de conexão/desconexão e animação do indicador de trabalho; Ctrl+Alt+C permite silenciar. A cabine usa posição inicial conforme câmera interna e tipo de máquina. Shift direito+M, parado, permite ajustar; Home restaura o padrão e Enter salva por modelo.

O reconhecimento continua lendo tipo de máquina, largura do implemento/plataforma, posição e polígono nativo do talhão. Distâncias até a borda usam o centro da máquina; mapas sem polígono indicam indisponibilidade. Gerar trajetos e ativar manobra de cabeceira continuam ações explícitas do jogador.

Também foi corrigido Unknown entity id ao encerrar: consulta entityExists e libera o monitor no evento de exclusão do veículo. [Relatório do log](CORRECAO-ENCERRAMENTO.md). O log recebido é da 0.9.2.1; a foto posterior confirma a exibição do novo modelo, mas não informa a versão.

Instale FS25_TG_GPS.zip em mods, sem descompactar nem manter cópias anteriores nessa pasta. O pacote contém todos os arquivos locais. Não exige o FS22. Uso single-player.

**118 testes simulados passaram**, incluindo oito casos da perspectiva, ausência de PDA na cabine, pintura estável, cores azuis, animação dos ícones e seis casos de encerramento. As regressões do renderer anterior continuam testadas explicitamente; a perspectiva é o padrão de produção. ZIP e referências locais são conferidos pelo empacotador. Os binários e imagens originais mantêm os hashes de models/greenstar/source-hashes.json.

Não houve execução local do FS25 ou GIANTS Editor. A foto enviada ajudou a identificar a mistura da imagem estática com o PDA. O resultado desta revisão, alinhamento fino, cores e animações ainda precisam de confirmação no jogo. Permanecem avisos de primitivas I3D em texto; o PDA físico deixa de ser criado no modo padrão.
