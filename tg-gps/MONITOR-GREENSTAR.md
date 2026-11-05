# TG GPS 0.9.6.0 — Orientação, pintura contínua e bordadura

A interface foi redesenhada seguindo a última referência enviada: barra superior verde, painel de orientação escuro, dados nas colunas laterais, botões em relevo e barra inferior com ícones. O fundo estático usa DDS de 2048 × 2048 com a cadeia completa de mipmaps BC3. Os valores usam fonte proporcional com acentos e números em negrito; pontos decimais mantêm o tamanho correto. A janela central continua totalmente dinâmica, sem PDA na cabine. Os sete recursos originais enviados permanecem intactos, com hashes em models/greenstar/source-hashes.json.

A camada refletiva e a imagem antiga sob a nova interface ficam ocultas durante a operação. Isso evita que o reflexo ou a arte anterior concorram com letras e guias. Modelo físico, inicialização e sons são preservados. O resultado visual desta revisão ainda precisa de confirmação na engine FS25.

## Pintura

Azul **forte** identifica a área já trabalhada. O azul **claro** é o fundo ainda sem pintura; uma repassagem real usa azul mais escuro. A projeção usa os contornos contínuos do trabalho, incluindo larguras fracionadas, sem ampliar as bordas para células grandes. A grade de medição não foi alterada.

As faixas de projeção são unidas em polígonos inclinados e preenchidas com triângulos, de modo que uma passagem reta vira um trapézio com bordas contínuas. Os materiais são opacos, sem acumular transparência a cada quadro. A rasterização intermediária é limitada e serve ao cálculo dos contornos, não a desenhar quadrados grandes na tela. Curvas complexas, amostragem e histórico de geometria já removida da memória ainda têm limites de precisão; a tela não promete recuperar detalhes que o histórico antigo não guardou.

## Bordadura

Os controles de manobra automática de cabeceira foram retirados da interface padrão. Abra **Ctrl+Alt+M → BORDADURA → GERAR LINHA DE BORDADURA**. O GPS lê o contorno nativo e cria uma referência fechada a meia largura real do equipamento para dentro do talhão. Pode inverter o sentido, salvar a linha ou voltar a gerar passadas internas.

A geração não altera a pintura. Contornos sem espaço, com interseções ou complexidade excessiva são recusados preservando o trajeto atual. Funciona quando o mapa fornece um polígono válido; não inventa o limite do campo. A linha pode ser usada com o piloto TG, mas velocidade, entrada nas curvas e levantamento continuam com o jogador. A biblioteca e o salvamento rápido guardam a bordadura e reconstroem a referência com a largura do equipamento em uso. Registros antigos não reativam a manobra automática na configuração padrão.

## Log e controles

O log da versão 0.9.4.0 mostrou 14 repetições de uma chamada incorreta de som. A engine exige `stopSample(sampleId, delay, fadeTime)`; reprodução e limpeza agora fornecem os três argumentos. O teste nativo simulado também exige essa assinatura. [Diagnóstico completo e outros mods](CORRECAO-LOG-096.md).

Os comandos continuam nos atalhos e no terminal TG. A arte dos botões físicos reproduz o formato da referência; o monitor 3D não ganhou interação por toque. **Ctrl+Alt+W** redetecta a largura, **Ctrl+Alt+P** alterna o piloto e **Shift direito+M**, parado, ajusta a posição física do monitor. O PDA geográfico permanece no terminal 2D.

## Instalação e evidência

Substitua **FS25_TG_GPS.zip** em `mods`, sem descompactar nem manter outra cópia do mod nessa pasta. Confirme **v0.9.6.0 carregado** no próximo log.

**135 testes simulados aprovados**, incluindo assinatura real do som, largura 2,40/6,40/12,80 m em diferentes orientações, limites da sobreposição, triângulos de área correta, fonte, DDS, saída da partida e bordadura em campos retangulares e côncavos. O empacotador valida recursos locais e integridade integral do ZIP.

A [prévia da interface](validacao/previa-orientacao.png) é gerada a partir da geometria e dos comandos reais do renderer com dados demonstrativos; não é uma captura do FS25. O FS25 e o GIANTS Editor não foram executados neste ambiente. Nitidez final, cores e alinhamento ainda dependem da resolução, distância e renderização da cabine no jogo. Permanecem os avisos de malhas I3D em texto carregadas uma vez; o PDA físico não é recriado a cada movimento.
