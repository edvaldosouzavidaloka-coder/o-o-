# Log recebido e revisão 0.9.6.0

O novo log confirma o carregamento do TG GPS 0.9.4.0, a geração de passadas e o acionamento do piloto. Não há erro de compilação do novo monitor nesse trecho. Há 14 mensagens do TG de uma única causa: `stopSample` recebeu um argumento, mas a engine exige três. A chamada do mod estava incorreta. Foram corrigidas as duas rotinas, de reprodução e descarte, para informar amostra, atraso zero e término imediato. O simulador agora rejeita chamadas com aridade incorreta, reproduzindo a restrição do jogo.

Os outros erros pertencem a pacotes diferentes: manifesto inválido de FS25_JohnDeere_C0stas_8r, título ausente em FS25_Mepel_15500 e FS25_Valmet_SeriesV2, versão de manifesto não aceita em FS25_silobolsapack e nome inválido da pasta Nova pasta. Esses arquivos não foram enviados nesta etapa e não foram modificados. Os avisos de I3D em texto são de formato/desempenho; não foram ocultados.

A foto mostrou letras pequenas e a interface anterior simplificada. A revisão usa moldura de interface própria em 2K com mipmaps completos, fontes proporcionais e contraste reforçado. A pintura usa contornos contínuos e triângulos, com largura verificada contra a geometria do equipamento. Conforme a solicitação posterior, o fundo sem pintura fica claro, o trabalhado fica azul forte e a cabeceira automática dá lugar à linha de bordadura.

Foram aprovados 135 testes simulados. O log e as fotos recebidos não validam a revisão 0.9.6.0 ainda: o teste dentro do FS25 e o log da nova sessão são necessários. O log original não foi incluído no Git porque contém caminhos e dados locais do usuário.
