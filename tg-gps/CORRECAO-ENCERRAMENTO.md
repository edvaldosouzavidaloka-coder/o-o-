# Correção ao sair da partida — TG GPS 0.9.4.0

O log enviado identifica **TG GPS 0.9.2.1**, tanto no manifesto encontrado quanto na mensagem de carregamento. Ele não registra execução da versão 0.9.3.0 com o novo monitor GreenStar. A foto posterior mostra o novo modelo, mas não informa a versão. O mesmo código de limpeza ainda era usado pela versão nova, por isso a correção foi aplicada ao pacote atual, preservando o modelo, caracteres, animações, sons e reconhecimento.

Quatro mensagens `Script error in delete: Unknown entity id` aparecem após sair da partida. As chamadas passam por `CurveGPSMonitorScreen:detach`, `CurveGPSMonitorManager:removeMonitor` e `TGGPS:deleteMap`. O jogo já havia removido o veículo e seus filhos; o GPS mantinha os identificadores desses objetos e tentava apagá-los novamente. Verificar apenas se o identificador era diferente de zero não detectava a remoção anterior.

A limpeza agora consulta `entityExists` antes de acessar ou remover objetos da cena. O evento `onDelete` do veículo também solta o monitor antes da remoção dos componentes, quando essa ordem está disponível. Excluir outro veículo preserva o monitor ativo e cancela somente uma instalação pendente que pertença ao veículo excluído. A tela deixa de atualizar nós inexistentes. A limpeza continua segura quando chamada mais de uma vez e libera também referências, caches e sons.

O simulador de testes anteriormente permitia apagar objetos já destruídos, o que escondia esse caso. Ele agora rejeita essa operação, como o contrato real da engine. Antes da correção, cinco dos seis novos casos falharam; depois, **118 testes simulados passaram**. Os novos casos cobrem remoção prévia do veículo pela engine, remoção parcial da tela, evento de exclusão do veículo, exclusão de outro veículo, limpeza repetida e atualização após remoção do pai. A geometria e as texturas originais não foram modificadas nesta revisão.

## Outros registros do log

- Há 56 avisos do GPS sobre malhas I3D em texto: oito cargas de cada modelo antigo e 32 do fundo PDA dinâmico. São avisos de formato/desempenho, distintos dos quatro erros de exclusão. Não foram ocultados nem foi feita conversão binária sem GIANTS Editor.
- `FS25_JohnDeere_C0stas_8r` tem um manifesto XML com tags incompatíveis; `FS25_Mepel_15500` e `FS25_Valmet_SeriesV2` estão sem título; `FS25_silobolsapack` declara uma versão de manifesto não aceita. Esses pacotes não foram enviados nesta etapa e não foram alterados.
- `FS25_JohnDeere8R_BR_V2` versão 1.0.0.2 aparece na lista de mods disponíveis, com aviso de instalação como pasta. Não há carga do modelo desse trator no log, portanto esta sessão não comprova seu funcionamento no jogo. Para usar o pacote corrigido, mantenha o ZIP direto em `mods` e guarde a pasta extraída fora dela.

## Instalar e confirmar

Feche o FS25 e substitua o **FS25_TG_GPS.zip** antigo na pasta de mods configurada no jogo. Não descompacte e guarde outras cópias fora dessa pasta. Na próxima sessão, confira a mensagem **`[TG GPS PRO] v0.9.4.0 carregado`**. O arquivo `GPS.zip` enviado como modelo não substitui o mod instalável completo.

Entre em um veículo, confira o monitor e saia da partida. O log dessa nova sessão deve confirmar a ausência de `Unknown entity id` no encerramento e permitirá avaliar o novo monitor. A engine e o GIANTS Editor não foram executados neste ambiente; alinhamento, shaders, áudio e comportamento visual ainda dependem desse teste. O log original não foi publicado porque contém caminhos e dados locais do usuário.
