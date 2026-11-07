# TOP GAMERS — Criador de Cercas FS25 v0.2 (teste)

**Status:** protótipo experimental. Branch separada da principal. Ainda NÃO validado no FS25 com mods reais.

## Download
Baixe o arquivo `TG_Cerca_Editor_GE10_v0.2_I3D_TESTE.zip` nesta pasta e extraia no Windows.

## Novidade
- Lê uma spline exportada como `.i3d` pelo GIANTS Editor 10.0.14 e seu arquivo correspondente `.i3d.shapes` da mesma pasta.
- Aceita **qualquer nome** terminado em `.i3d`, desde que a referência do arquivo shapes esteja correta.
- Continua aceitando CSV, mas **não exige mais o script Lua** para exportar.
- Botão **Analisar spline** para conferir pontos/trechos antes de gerar.
- Pode gerar XML `newFence` para cercas compatíveis, com prévia e backup.

## Como testar
1. Exporte a spline no GIANTS Editor: **File > Export Selection**.
2. Mantenha juntos o I3D e o arquivo de shapes referido nele.
3. Extraia o ZIP e execute **INICIAR.cmd** (requer Python 3.10+ com Tkinter).
4. Na janela, selecione a spline I3D e clique **Analisar spline**.
5. Selecione pasta mods, mod da cerca, XML da cerca e **placeables.xml de um save de teste**.
6. Mantenha **Só conferir / prévia** habilitado e execute **Conferir / Gerar XML**.
7. Se não houver erro, faça o teste de gravação apenas numa cópia e examine o `log.txt` do jogo.

## Limitações
- Testado com o I3D de exemplo enviado: 26 pontos de controle, cerca de 393 m e 210 segmentos em simulação.
- Splines cúbicas são aproximadas por linhas entre pontos de controle; traçado pode diferir da curva exata.
- Venda por trechos **não está comprovada** no jogo; depende da estrutura nativa `newFence` do mod.
- A porteira é tratada como placeable separado e só mantém animação se já for funcional no XML/I3D do mod.
- `animatedObjects.xml` e `storeItems.xml` **são apenas validados**: o programa **não** injeta códigos nesses arquivos na v0.2.
- O leitor de alguns arquivos shapes pode precisar de internet para obter a tabela pública de chaves do formato (licença MIT).
- Não utilize no mapa principal sem backup.

O ZIP contém `LEIA-ME.txt`, `TESTAR.py`, código-fonte Python, `INICIAR.cmd`, dados de exemplo e créditos MIT.
