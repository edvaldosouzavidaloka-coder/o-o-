# John Deere 8R BR v2 — FS25 1.0.0.2

[Baixar o ZIP completo](../FS25_JohnDeere8R_BR_V2.zip) · [Relatório da correção do log](RELATORIO.md)

Atualização baseada no log enviado: corrigidos os templates de som ausentes, a versão dos shaders do painel, CPU mesh da câmera, referência de abastecimento e engates. Os arquivos de motor originais foram mantidos; buzina, ar e comandos receberam efeitos mono locais de compatibilidade. Pressão, cores, 56 opções de rodas e 25 opções de motor foram preservados.

## Instalação

Use **FS25_JohnDeere8R_BR_V2.zip** diretamente na pasta `mods`, **sem descompactar**. Afaste a pasta antiga do mesmo mod de `mods` e guarde a cópia fora dessa pasta. Servidor e jogadores devem usar o mesmo ZIP.

O erro `symbol_tractor/getHasShaderParameter` é do TG GPS. Atualize também [FS25_TG_GPS.zip](../FS25_TG_GPS.zip) para a versão **0.9.2.1**, que corrige a consulta de shader nos ícones agrupados.

## Validação

**25 testes simulados do trator e 89 do TG GPS passaram.** Referências locais e integridade dos ZIPs foram conferidas. O teste no FS25 e o `log.txt` da nova sessão ainda são necessários; não houve execução da engine neste ambiente.

Os avisos de desempenho de imagens PNG/JPEG sem mipmaps e das malhas textuais do GPS permanecem. Recursos de outros mods não foram alterados.

## Pressão

Escolha `Yes` em `Tire pressure system`. `Ctrl+Page Up/Down` muda o alvo e `Ctrl+P` inicia ou para o ajuste. O script simula pressão, interface e som, sem alterar a física dos pneus.

O controle interativo opcional depende de um mod externo compatível, não incluído. A pasta `FS22` no ZIP contém recursos legados locais, não exige instalar o FS22.

Esta pasta contém fontes textuais para revisão. Os binários, texturas e sons completos estão no ZIP; extraia-o para editar a árvore inteira. Não instale somente esta pasta.
