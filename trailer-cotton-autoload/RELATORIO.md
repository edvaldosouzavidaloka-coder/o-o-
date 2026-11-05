# Bitrem Lizard Cotton Autoload — correção FS25 1.0.0.1

O problema informado era a falta de carregamento de fardos **redondos** de algodão. Também foi solicitado que as rodas e a carreta pudessem mudar de cor. Foram preparados os dois veículos e um ZIP completo; a validação realizada é offline e não certifica execução sem erros dentro do jogo.

## Autoload

- Os dois detectores `baleTrigger` estavam com grupo e máscara de colisão zerados. Uma especialização local inclui os flags `TRIGGER` e `DYNAMIC_OBJECT` do FS25 nos respectivos campos, preservando os demais bits. A alteração afeta apenas os tipos de veículo deste mod. Coleta, montagem, permissões, descarga, salvamento e sincronização continuam a cargo do `BaleLoader` nativo.
- O XML aceitava somente diâmetro e largura exatamente iguais a 2,38 m. Agora aceita fardos redondos entre 2,30 e 2,50 m nas duas dimensões. A validação da cultura exige o conteúdo real `COTTON`, recusando outras culturas e módulos retangulares.
- Na traseira, `dropBaleReverseSpeed="unloadX"` colocava o nome de uma animação em um campo numérico. Corrigidos os atributos de animação, com velocidade numérica e referência apropriada a `dropToWork`.
- Adicionada uma animação curta e estacionária para os passos nativos sem mecanismo físico de garra. Foram explicitados os nomes das animações de coleta, transferência e descarga que antes dependiam de nomes padrão ausentes. As animações reais de descarga foram mantidas.
- O contêiner inicial já inclui os 9/11 lugares físicos. Foi corrigido o agrupamento `balePlaces` para tratar a carga completa como uma plataforma, evitando reaplicar o deslocamento de um lugar individual ao conjunto carregado.
- Mantidas as capacidades 9 + 11, o tipo nativo do contador `ROUNDBALE_COTTON`, os nós físicos e a opção de uso manual. Desativado o consumo de PTO, desnecessário para esta carreta sem mecanismo de coleta acionado por eixo.

## Cores

- Migrados os blocos obsoletos de `baseMaterialConfigurations` e `designMaterial2/3Configurations` para `baseColorConfigurations` e `designColor2/3Configurations`. Retirado `baseMaterial` de parâmetros `colorMat` obsoletos.
- Corrigidos seletores que tratavam uma string RGB como nome de template. Todas as opções manuais existentes foram mantidas, com RGB de três componentes; aliases de cores antigas foram convertidos para valores RGB explícitos. Os IDs antigos de acabamento foram substituídos por parâmetros PBR de metalness, smoothness e clear coat nas escolhas manuais, sem usar números como nomes de materiais.
- A especialização `CottonTrailerColors` atribui slots às superfícies pintadas reais do modelo convertido antes da aplicação dos seletores nativos. Há 19 vínculos por carreta: 5 de carroceria, 6 de chassis, 2 de suportes, 2 de laterais e 4 de rodas antigas. Pneus, lâmpadas, vidros e adesivos não entram nesses grupos.
- Habilitado `useRimColor` para os aros carregados pelo sistema de rodas. Os aros antigos embutidos na cena também passam a responder ao seletor de rodas.
- O tipo manual herda `trailer` e inclui somente a especialização de cores. O tipo autoload herda `baleLoader` e inclui os dois ajustes. Assim as cores também funcionam com Autoload Não, sem callbacks de coleta no tipo manual.
- Normalizadas as listas de IDs de materiais que usavam vírgulas para o formato com espaços. A topologia, os materiais, as posições e a geometria binária das cenas foram preservados.

## Verificação

**18 testes simulados aprovados, sem testes pulados.** Foram executados métodos da referência pública do FS25, incluindo `BaleLoader`, `VehicleConfigurationItemColor` e `VehicleMaterial`, com as chamadas de engine simuladas.

Os testes reproduzem os filtros zerados e a rejeição da medida 2,40 m no original; verificam detecção, faixa de tamanho, cultura, forma, propriedade dos fardos, alcance, objetos já montados, posição de trabalho, lotação e o ciclo nativo de coleta/posicionamento/descarga nas capacidades 9 e 11. Também confirmam que todas as referências de animação usadas pelo carregador resolvem.

Para cores, foram verificados a preservação do número de escolhas manuais, RGB válido, aplicação independente aos cinco grupos nas duas carretas, manutenção dos slots não selecionados e recoloração dos dois modelos de aro locais pelo `VehicleMaterial` nativo. O tipo manual foi conferido separadamente.

As referências locais de arquivos foram conferidas recursivamente, sem arquivos faltando. O ZIP foi verificado por CRC e comparação com a árvore preparada. Todos os arquivos originais não envolvidos na correção permaneceram idênticos; os arquivos `.i3d.shapes`, texturas e definições de rodas foram preservados byte a byte.

Referência pública utilizada: https://github.com/MyGameSteamOfficial/fs25-lua-api, commit `9478ee9245f7f95fdff98a887ad3b2f713340f8a`. As assinaturas de filtros e slots de material foram conferidas em `scriptBinding.xml`.

## Validação no jogo

Não houve execução do FS25, compilação gráfica ou sessão multiplayer real. Recursos `$data` e templates do próprio jogo ainda dependem da instalação do usuário. O próximo teste deve comprar ou reconfigurar as duas carretas com Autoload Sim, ativar posição de trabalho pelo menu F1, coletar algodão redondo, lotar/descarregar e conferir cores na loja/oficina. O `log.txt` dessa sessão permite diagnosticar qualquer falha que só apareça na engine.
