# John Deere 8R BR v2 — correção do log, versão 1.0.0.2

O log enviado confirmou incompatibilidades que não podiam ser verificadas apenas com o teste offline do primeiro pacote. Esta atualização trata os erros concretos de áudio e shader e os avisos de configuração do trator. O log completo não é publicado: contém caminhos e informações locais do usuário.

## Correções do trator

- **Som do motor:** removidos os templates `LARGE_TRACTOR_MOTOR_*`, ausentes no jogo usado pelo usuário. Os cinco arquivos de motor enviados continuam no mod. Partida, parada, marcha lenta e aceleração/carga usam esses arquivos diretamente. Curvas locais `JD8R_RPM` e `JD8R_LOAD` são registradas pelo mod e obtêm RPM/carga pelas funções nativas `Motorized`, com valores finitos limitados a 0–1.
- **Buzina, ar e comandos:** removidas as dependências dos templates ausentes `HONK_NEW_HOLLAND_TRACTOR`, `DEFAULT_SOWING_AIR_BLOWER`, `SWITCH_01`, `SWITCH_TURNLIGHT`, `ATTACH_01`, `defaultHydraulicSound` e `WATER_SPLASH_01`. Incluídos sete efeitos mono locais: buzina, ar, hidráulico, interruptor, pisca, engate e água. São sinais procedurais de compatibilidade, não gravações originais de uma marca de trator. Templates que o log mostrou como resolvidos foram preservados.
- **Painel:** corrigido o cabeçalho dos dois shaders para `CustomShader version="5"`, versão exigida explicitamente pela engine no log. Injeções, parâmetros, variações e código dos shaders foram preservados. Isso corrige a declaração incompatível que impedia a disponibilização de `lightControl`; os avisos de emissores identificados no log apontavam para o shader recusado.
- **Câmera:** habilitado `cpuMesh` no Shape existente que o mapeamento `shadowFocusBox` realmente referencia. Não foi apagada a câmera nem substituída sua geometria.
- **Reabastecimento:** as duas configurações diesel agora declaram `exactFillRootNode` no componente físico principal existente. O callback local inclui o flag `FILLABLE` antes de a especialização FillUnit registrar esse nó, preservando os demais flags. Não foi inventada uma nova malha de abastecimento.
- **Engates:** referências dos braços superiores migradas para XML, incluindo o nome `walterscheidHO_110_700` indicado pela engine; removidos nomes vazios de templates do braço dianteiro. Declarada a faixa `categoryRange="1 4"`, que corresponde ao padrão nativo já usado quando o atributo faltava.
- Mantidos controle de pressão, cores, 56 opções de rodas, 25 opções de motor e a geometria binária do pacote anterior.

## Erro separado do TG GPS

A exceção `symbol_tractor` em `getHasShaderParameter` vinha de `CurveGPSMonitorScreen.lua`, no mod TG GPS, e não do script de pressão do trator. `symbol_tractor` é um TransformGroup. A rotina de brilho agora consulta shaders somente em Shapes, mas continua percorrendo os filhos e atualizando o cache. Um teste reproduz a restrição real da API e verifica a atualização dos filhos do ícone. Essa correção está no **TG GPS 0.9.2.1**, que precisa ser atualizado separadamente.

## Validação e limites

- **25 testes simulados do trator aprovados**, incluindo as regressões da versão anterior e casos novos para callbacks de som, templates ausentes, áudio mono, cabeçalhos de shader, câmera, combustível e engates.
- **89 testes simulados do TG GPS aprovados**, incluindo a consulta estrita de shaders somente em Shapes.
- Todos os 12 arquivos OGG locais do trator foram decodificados e conferidos como mono. Referências locais e ZIPs conferidos por presença, CRC e conteúdo.
- Não houve execução da engine FS25 neste ambiente. A nova carga no jogo precisa confirmar a compilação gráfica dos shaders, os efeitos de áudio e o comportamento físico. Não se afirma que um novo log já está sem erros.

Os avisos de desempenho das imagens PNG/JPEG sem compressão/mipmaps e os avisos de malhas textuais do TG GPS permanecem. Os recursos visuais foram preservados nesta atualização; isso não foi tratado como erro de template ou falha de script. Avisos de outros mods, inclusive manifestos de outros tratores e mapas, não foram atribuídos ao John Deere 8R deste pacote.

## Instalação para o novo teste

Use **FS25_JohnDeere8R_BR_V2.zip** e **FS25_TG_GPS.zip** diretamente na pasta `mods`, **sem descompactar**. O log mostrou o John Deere carregado como pasta; afaste a pasta antiga da pasta `mods` para não carregar duas cópias. Guarde a cópia antiga fora de `mods` e teste a nova versão. O `log.txt` da nova sessão é a evidência necessária para confirmar o resultado na engine.
