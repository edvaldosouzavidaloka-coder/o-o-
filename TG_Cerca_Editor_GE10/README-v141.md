# TG + EDVALDO FS25 v1.4.1 — Correção das janelas (Windows)

## Problema corrigido

Ao abrir **ADICIONAR PC OBJECTS**, o Windows podia trazer o programa principal à frente depois de escolher um I3D, XML ou pasta. A janela do PC Objects ficava escondida, exigindo trocas constantes na barra de tarefas.

## Nova operação

- Quando abre **PC Objects**, a janela principal é **minimizada**.
- A janela PC Objects fica **visível e em primeiro plano**.
- Os seletores **I3D do objeto**, **I3D do mapa**, **XML do objeto**, **pasta do mapa**, **placeables.xml** e **StoreItems.xml** usam PC Objects como janela-pai do diálogo. Quando o diálogo fecha, o foco volta para PC Objects.
- Ao clicar no **X** de PC Objects, o programa **restaura a janela principal**. Também restaura quando o popup é fechado de outra forma.
- Se clicar no botão PC Objects novamente, reutiliza a janela aberta.

## Sem alterações nos recursos

O resto continua como na versão 1.4: I3D exportado do GIANTS Editor, posição X/Y/Z e rotação, registro independente e confirmado em placeables.xml / StoreItems.xml, XML decorativo opcional, backups, e criador de cercas/porteiras baseado na v0.9.1.

## Teste

1. Abra o EXE v1.4.1 e clique **ADICIONAR PC OBJECTS**.
2. Verifique que a janela principal minimiza e que PC Objects permanece visível.
3. Selecione o I3D ou XML, feche o diálogo de seleção e veja que PC Objects continua à frente.
4. Feche PC Objects no **X**; a janela principal deve reaparecer.

É uma correção de interface; recomendamos continuar testando os registros XML numa **cópia do mapa FS25**.
