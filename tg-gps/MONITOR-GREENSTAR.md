# Monitor GreenStar 3 — TG GPS 0.9.3.0

O monitor físico foi substituído pelo modelo de `GPS.zip` enviado pelo usuário. `GPS3000.dds` avulso é idêntico ao arquivo do ZIP. A geometria binária e as sete imagens/recursos originais foram copiados sem recodificação; os hashes estão em [source-hashes.json](models/greenstar/source-hashes.json). As letras dos menus, A–J, rótulos e ícones continuam na textura original. A autoria do modelo não foi informada; não se atribui sua criação ao TG GPS.

Ao ligar o motor, a tela mostra a imagem original de inicialização, com barra de progresso e o indicador giratório da imagem enviada. Após 1,8 segundo, aparece o mapa local do TG GPS na janela central, com passadas, posição, pintura, sobreposição e o símbolo adequado para trator, colheitadeira ou colheitadeira com plataforma. O indicador de trabalho gira enquanto a área está ativa e a máquina se move. Desligar o motor apaga a tela; religar reinicia a sequência.

A moldura e os botões impressos são preservados. Setas, zoom e câmera da arte são restaurados por recortes UV sobre o mapa dinâmico. O consumo por hectare é calculado a partir do consumo nativo, velocidade e largura, aparecendo `--` quando não há trabalho mensurável. O indicador de desvio usa a distância lateral até a passada, convertido em polegadas conforme o rótulo original. A indicação `Steer ON` aparece com o piloto ligado. Fazenda, proprietário, biblioteca e demais controles completos continuam no terminal TG, aberto com **Ctrl+Alt+M**; os botões desenhados na textura 3D não são novos controles clicáveis.

As três formas de reconhecimento pedidas estão presentes:

- **Cabine:** usa a referência da câmera interna para escolher o canto inicial. Trator e colheitadeira recebem posições iniciais diferentes; a fixação acompanha a cabine e preserva a posição salva por modelo. **Shift direito+M**, com a máquina parada, permite ajuste. **Home** restaura a posição automática e **Enter** salva. Cabines personalizadas sem uma referência interna adequada podem precisar desse ajuste.
- **Borda/cabeceira:** lê o polígono nativo do talhão a cada segundo. Mostra distância até a borda e a faixa de cabeceira configurada; mantém também a distância à frente nos dados de reconhecimento. As distâncias usam a posição central da máquina. O contorno aparece mesmo antes de gerar uma linha. Mapas que não fornecem o polígono mostram a informação como indisponível. A leitura não aciona direção ou implementos; a manobra automática continua exigindo geração do talhão e ativação da cabeceira pelos controles TG.
- **Máquina/largura:** identifica trator ou colheitadeira pelas especializações nativas e usa a largura do implemento/plataforma selecionado. Posição e pintura usam as áreas de trabalho existentes. Larguras salvas por implemento e referências de trajeto são preservadas.

Dois sinais mono próprios indicam conexão e desconexão. Eles acompanham a conclusão da inicialização, o desligamento do motor e as transições reais do piloto. Não são gravações originais John Deere. **Ctrl+Alt+C → SONS DO MONITOR** permite silenciar; a preferência fica salva com brilho e zoom. As amostras são liberadas ao sair da partida.

## Instalação e validação

Substitua **FS25_TG_GPS.zip** na pasta `mods`, sem descompactar e sem manter outra cópia do mod nessa pasta. O pacote inclui modelo, `.shapes`, imagens, scripts, shaders e sons. A pasta interna `FS22` contém somente recursos legados locais e não exige instalar outro jogo. Uso single-player, como nas versões anteriores.

**104 testes simulados aprovados:** os 89 anteriores e 15 novos cobrem preservação dos arquivos, normalização do modelo, ciclo de energia, progresso, animação ligada ao trabalho, tons, silêncio, troca de cabine, plataforma, leitura do contorno e liberação de recursos. O empacotador confere dependências locais, arquivos binários externos e integridade completa do ZIP. Os dois OGG foram decodificados e conferidos como mono de 44,1 kHz.

O FS25 e o GIANTS Editor não estão instalados neste ambiente. A compilação gráfica, a orientação UV da malha binária, o alinhamento fino dos recortes com a tela e a posição em cada cabine precisam de confirmação no jogo. O adaptador usa a esfera da geometria fornecida pela engine e a proporção 4:3 do monitor para dimensionar o conteúdo. Não houve renderização real do modelo durante esses testes. Permanecem avisos de malhas textuais das primitivas dinâmicas; os binários e texturas enviados foram preservados.

Para reproduzir a importação, execute `python tools/import_greenstar.py /caminho/GPS-extraido`. Os sinais podem ser gerados com `python tools/generate_monitor_sounds.py` (FFmpeg). Rode os testes com `python tools/test.py` (lupa 2.6) e crie o pacote com `python tools/package.py`.
