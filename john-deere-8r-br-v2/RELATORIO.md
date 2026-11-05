# John Deere 8R BR v2 — FS25, versão 1.0.0.1

O pacote completo foi reconstruído a partir dos arquivos enviados. A validação foi offline: não houve execução do FS25, sessão multiplayer real, compilação dos shaders na engine ou ensaio de física. A publicação de um ZIP completo não equivale a certificar funcionamento 100% dentro do jogo.

## Correções

- **TirePressure.lua:** substituídas as chamadas legadas MathUtil.clamp/sign; registrados os campos XML de configuração; respeitada a escolha Sim/Não da loja; valores não finitos recusados; pressão limitada; salvamento e recarga com bomba desligada. Só o servidor avança a pressão. Alterações do alvo são enviadas ao servidor e os streams replicam pressão atual, alvo e estado, inclusive a parada de áudio nos clientes. O script continua simulando estado/interface/áudio: não modifica a física dos pneus.
- **Cores:** habilitado useRimColor no material dos aros e nos quatro cubos, que antes podiam ignorar a seleção. Corrigido o amarelo numérico de RGBA para RGB e retirado o atributo legado material dos seletores. Acrescentadas seis cores nativas de carroceria. Uma especialização local atribui slots estáveis a 72 superfícies pintadas antes de a configuração nativa aplicar a cor; preserva os demais slots. Retirado o bloco baseMaterial obsoleto de colorMat do XML.
- **Luzes:** eliminadas cinco referências a filhos inexistentes e a referência/mapeamento sideLight01, ausente na cena. Uma bandeira deixou de ser cadastrada como lâmpada. Mantidos os faróis e demais indicadores existentes, sem inventar uma luz substituta para os nós ausentes.
- **Colisões:** os campos de grupo e máscara estavam zerados no componente principal, peça frontal e trigger. JD8RCompatibility os restaura no callback de carregamento desta instância, antes da verificação de componentes, com CollisionFlag do próprio FS25. Preserva filtros que já estejam configurados e não altera a classe Vehicle global. Isso foi verificado por contratos simulados; as malhas ainda precisam do teste físico dentro do jogo.
- **Rodas:** corrigida a configuração MICHELIN_BROAD_W, cujo pai MICHELIN_BROAD não existia. Ela agora herda as representações e direção de MICHELIN_DEFAULT3, mantendo seus quatro pneus e ajustes físicos próprios. Quatro XMLs Michelin que buscavam modelos locais ausentes passaram a indicar os modelos compartilhados machXBib/cereXBib2 em $data. Os caminhos e índices desses recursos do jogo ainda precisam de confirmação na instalação FS25 do usuário.
- **Som:** mantidas as cinco gravações de motor enviadas e convertidas as cópias entregues de estéreo para mono Vorbis, adequadas à fonte de áudio 3D. O sounds/mf.xml e a buzina por template foram preservados. Removidos os modificadores VALVE_LOAD do som de pressão que o script não registrava. Templates e a transmissão de $data continuam sujeitos à verificação no jogo.
- **Recursos:** referências de imagens alinhadas aos DDS recebidos, inclusive um acessório que indicava PNG enquanto o arquivo era DDS. Os dois shaders do painel foram incluídos em shaders/ com caminhos explícitos. Seu código não foi reescrito sem a engine para compilá-lo. Corrigida a codificação declarada do I3D principal para UTF-8 e retirado um mapeamento steeringSensorLeftPart duplicado.
- **Interface:** acrescentadas traduções brasileiras para os controles e a indicação de pressão. A versão do mod passou para 1.0.0.1. Mantido descVersion 94: já é um manifesto FS25 e não foi inventado um requisito de versão mais alto.

## Evidências

- **20 testes de regressão simulados aprovados**, sem testes pulados. Incluem um controle negativo que reproduz a dependência matemática do script original; inflação/esvaziamento e parada exata; opção desativada; valores inválidos; salvamento; eventos e streams; áudio; falhas de carregamento; filtros existentes; herança de rodas acíclica e representação de todas as quatro rodas em cada opção.
- O teste de cores executou VehicleConfigurationItemColor e VehicleMaterial da referência pública FS25, simulando apenas as chamadas da engine, sobre a árvore real do I3D enviado. As seis cores atingiram as 72 superfícies esperadas e preservaram os outros slots. Não foi alegada validação visual.
- **23 XML/I3D analisados recursivamente**, sem recursos locais referenciados faltando. Foram distinguidos caminhos de recursos do mod, arquivos relativos a cada I3D, sentinelas de configuração e caminhos compartilhados do jogo.
- **1.530 referências de nós do XML principal resolvidas** na cena fornecida; nenhuma duplicata nas categorias auditadas; nenhum fileId/materialId inválido; todas as animações referenciadas existem; todas as luzes reais cadastradas apontam para Light. Os quatro conectores locais também resolvem nos nós do I3D de rodas.
- **132 imagens decodificadas:** 107 DDS, 19 PNG e 6 JPEG. Cadeias de mipmaps DXT verificadas quando aplicável; nenhum payload truncado encontrado. As 72 texturas da pasta Textures foram preservadas byte a byte.
- **Cinco sons Vorbis mono decodificados integralmente** por FFmpeg. As gravações estéreo originais foram preservadas fora do pacote corrigido.
- Preservadas as **56 configurações de rodas**, **25 configurações de motor**, calibrações de suspensão e animações. A única mudança de herança de rodas é a correção documentada acima. A topologia da cena e JohnDeere8R.i3d.shapes permaneceram idênticos aos recebidos.
- ZIP verificado por CRC, presença de modDesc.xml na raiz e comparação de conteúdo de todas as entradas com os arquivos preparados.

Os contratos públicos consultados são do repositório https://github.com/MyGameSteamOfficial/fs25-lua-api, commit 9478ee9245f7f95fdff98a887ad3b2f713340f8a, incluindo Vehicle, Wheels, BaseMaterial, VehicleMaterial, VehicleConfigurationItemColor, WheelXMLObject, SoundManager e as assinaturas de engine em scriptBinding.xml. Isso é uma referência de API; não constitui uma instalação ou certificação oficial do jogo.

## Validação pendente dentro do FS25

Há **107 referências únicas a recursos compartilhados $data** nos arquivos analisados, além de templates de som do jogo. Não houve acesso a esses arquivos instalados para confirmar sua existência ou os índices internos dos modelos. Os shaders, transparências, reflexos, o funcionamento real das luzes, som de motor/buzina, aderência, deformação, colisões e suspensão precisam de ensaio na engine.

As definições interactiveControl originais foram preservadas. O mod externo compatível que fornece essa interface não foi fornecido ou incluído; não se deve afirmar que os controles interativos funcionam sem ele. A alteração dos streams de pressão exige que servidor e clientes usem o mesmo ZIP corrigido.

Teste a compra do veículo, suas combinações de rodas e cores, motor e buzina, condução e colisões, faróis e indicadores, salvar/reabrir a partida. O próximo insumo para diagnosticar qualquer erro real é o log.txt dessa sessão. Não foram inventados recursos ausentes ou removidas opções da loja para ocultar falhas.
