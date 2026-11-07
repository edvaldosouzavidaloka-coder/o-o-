# TOP GAMERS — Criador de Cercas FS25 (protótipo v0.2)

**Experimento — não validado em um mod real nem dentro do FS25.** Faça backup da pasta do mapa/savegame. A ferramenta gera `placeables.xml` a partir de CSV de spline previamente exportado. Não gera geometria/I3D, fios ou colisões sozinha.

## Instalação no Windows

1. Instale Python 3.10 ou mais recente.
2. Extraia esta pasta e execute `py TG_Cerca_Editor.py` em um CMD aberto nela.
3. Selecione a sua pasta `mods`, o ZIP da cerca e o XML da cerca (não o `modDesc.xml`).
4. Selecione o CSV da spline (`x,y,z`), que deve ter sido obtido anteriormente do Editor.
5. Escolha o `placeables.xml` do mapa ou, para um save existente, o `placeables.xml` desse save.
6. **Mantenha “Só conferir/prévia” marcado**. Clique `Conferir/Gerar XML` e veja os avisos.
7. Só desmarque a prévia após conferir. O programa cria `placeables.xml.tg_backup` uma vez ao lado do XML destino, porém é recomendado backup manual separado.
8. Teste o resultado em uma cópia do save, nunca no arquivo original.

## Novidades da v0.2

- **Trecho máximo no XML (m)**: padrão 18 m. Em retas longas, reduz centenas de pequenos `<segment>`; não representa o espaçamento dos postes.
- **Tolerância da curva (m)**: padrão 0,35 m. Preserva mais pontos nas curvas fortes.
- **Tolerância do relevo (m)**: padrão 0,18 m. Mantém pontos necessários quando o terreno sobe/desce.
- **Diagnóstico da cerca**: verifica a presença dos elementos `<fence><poles node=...>` e `<fence><panels node=...>` no XML e informa o comprimento original dos painéis quando declarado.
- **Farm ID da porteira**: ajustável (padrão 1), apenas para porteira independente. A propriedade da cerca `newFence` é determinada principalmente pelo terreno no FS25, não por esse campo.

## Por que só aparecem postes e não os fios?

Os `<segment>` definem **o caminho**. A geometria dos postes e dos fios/painéis vem do **XML e I3D do mod**. Se não houver `<panels>` configurado, ou o nó referenciado estiver incorreto, a ferramenta não consegue inventar os fios. Uma imagem de postes sem fios não prova isoladamente qual parte do modelo está errada. Envie o ZIP do mod e o `log.txt` para verificar.

O **espaçamento real dos postes** geralmente depende de `<fence><panels length="...">` e da modelagem original, não do campo "Trecho máximo" do programa. Não alteramos o ZIP original, para não quebrar o mod.

## Por que não consigo demolir no paisagismo?

O FS25 permite que cercas **nativas `newFence`** sejam demolidas por painéis, quando a cerca foi registrada corretamente e o jogo pode selecionar seus nós de colisão. No sistema nativo, a propriedade da cerca depende da titularidade do **terreno**, portanto teste numa área comprada pela sua fazenda. Também dependem da configuração do mod: `newFence`, colisões/picking do painel e comportamento de destruição. Mudar simplesmente `farmId="0"` para `farmId="1"` no XML da cerca **não garante** a demolição. Consulte `log.txt`.

**Atenção:** não gere outra cerca em cima da antiga sem remover antes a entrada de teste anterior do `placeables.xml`. Caso contrário, podem aparecer cercas duplicadas. Como esta versão não tem limpeza/identificação segura dos registros antigos, remova apenas o bloco de teste que você adicionou, depois de fazer backup e verificar o `uniqueId`.

## Recursos ainda não implementados

- Não edita `storeItems.xml`, animações ou I3D; apenas valida XMLs fornecidos.
- Não ajusta automaticamente a distância real entre os postes; isso depende da configuração de painéis da cerca.
- Não reconstrói fios ausentes, nem cria colisões; depende do mod.
- Não otimiza diretamente cercas já gravadas; gere um arquivo de teste novo e remova a entrada de teste antiga apenas quando seguro.
- A exportação Lua por `io.open` pode falhar no GIANTS Editor, que não disponibiliza essa função. Se isso acontecer, use um CSV já extraído por um método compatível com o Editor ou envie o I3D + shapes para adaptar o importador.

## Fontes técnicas

- Documentação oficial GIANTS Software, `PlaceableNewFence`: https://gdn.giants-software.com/documentation_scripting_fs25.php?category=78&class=749&version=script
- Documentação oficial GIANTS Software, `Fence`: https://gdn.giants-software.com/documentation_scripting_fs25.php?category=90&class=865&version=script
