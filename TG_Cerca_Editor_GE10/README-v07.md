# TG + EDVALDO — Criador de Cercas FS25 v0.7 (BETA I3D)

## Mudanças

- **Foto do trator fixa no fundo escuro:** é a foto já incorporada na v0.6. A opção **"Escolher foto em alta resolução"** e o texto abaixo dela foram **removidos**.
- **Espaçamento corrigido nas retas:** em vez de cortar cada 25 metros, a versão 0.7 agrupa até 80 metros (padrão) e posiciona as emendas no final de grupos inteiros de painéis. Isso reduz postes extras e a variação de distância entre vãos nos trechos retos.
- **Curvas e relevo:** preserva pontos onde a spline muda direção ou altitude, respeitando as tolerâncias horizontal e vertical. Trechos curtos em curvas acentuadas podem continuar apresentando espaçamento diferente; o programa avisa no log.
- **Compatibilidade:** reconhece os cinco tipos nativos de cerca do mod brasileiro (painéis de 4 m, 6,7 m, 4 m, 4 m e 3,8 m), sem editar os arquivos do mod.
- **Entrada somente I3D:** selecione seu arquivo \`.i3d\` exportado no GIANTS Editor 10.0.14, com o correspondente \`.i3d.shapes\` ao lado; não usa CSV.
- **Loja e demolição:** continua conferindo o XML da cerca, registro no modDesc e canBeSold. A venda por trechos não é garantida sem teste dentro do FS25, com o terreno comprado pela fazenda.

## Instalação e teste

1. Baixe o \`TG_EDVALDO_Cercas_FS25_v07_I3D.exe\` no GitHub Releases.
2. Inicie o programa fora da pasta \`mods\`; não precisa instalar Python.
3. Selecione sua pasta de mods, o mod \`FS25_Brazilian_fences\`, e o XML do modelo desejado.
4. Exporte **somente a spline** como \`.i3d\` no GE 10.0.14. Guarde o \`.i3d.shapes\` na mesma pasta.
5. Selecione um **placeables.xml de uma cópia de savegame**; nunca sobrescreva o único save original.
6. **Mantenha "Só conferir / prévia" ligado** e clique **Conferir / Gerar XML**. Leia os avisos de trechos curtos e compare a contagem.
7. Se estiver correto, desmarque prévia para gerar. O programa salva backup do XML.
8. Teste no FS25 com o mod selecionado, verificando arames, postes, animação e demolição por trechos no terreno da fazenda.

## Ajustes

- **Trecho máximo no XML:** padrão **80 m**. Não é a distância entre postes. Em linhas retas, poucos segmentos XML permitem o jogo repetir os postes com intervalos mais regulares; não coloque valores enormes antes de testar.
- **Tolerância de curva:** 0,35 m padrão. Diminuir para 0,20 m mantém mais detalhes das curvas e aumenta segmentos XML.
- **Tolerância de relevo:** 0,18 m padrão. Diminuir para 0,10 m mantém mais detalhes da altura e aumenta segmentos.
- **Porteira nativa:** selecionada pelo id no XML do mesmo mod. Testar abertura/animação no jogo.
- **Propriedade/demolição:** mudar farmId sozinho não garante remoção. Testar em savegame de teste, com terreno da fazenda.

### Limitações

- O FS25 tem seu próprio cálculo interno de postes e painéis. A v0.7 **reduz emendas e estabiliza estimativas de comprimento em retas**, mas não pode prometer espaçamento perfeitamente uniforme em todos os modelos e curvas sem teste no jogo.
- O leitor I3D experimental aproxima splines cúbicas como polilinhas; formas muito curvas precisam de teste visual.
- O programa **não modifica** o ZIP do mod, \`storeItems.xml\` ou animações do mod.
- **EXE beta**, compilado e testado em Windows pelo GitHub Actions. Antes de usar no mapa principal, verifique os resultados no FS25 e revise \`log.txt\` em caso de falha.
