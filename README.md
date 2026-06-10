# Voz MCP

Voz MCP e um prototipo iOS local-first para transformar comandos falados em mensagens prontas dentro de qualquer campo de texto, especialmente WhatsApp.

O objetivo original do projeto e bem especifico: o usuario nao quer abrir um app separado, gerar uma resposta, copiar e voltar para o WhatsApp. A experiencia desejada e usar um teclado/atalho enquanto a conversa ja esta aberta, falar ou ditar um pedido, gerar a mensagem com IA local no iPhone e inserir o texto final no proprio campo de mensagem.

## Estado atual

Este repositorio contem:

- App iOS SwiftUI principal.
- Extensao de teclado iOS (`VozMCPKeyboard`).
- Gerador compartilhado com tentativa de usar `FoundationModels` / Apple Intelligence local.
- Fallback local estruturado em portugues do Brasil, com analise de intencao, tamanho, checklist obrigatorio e controle de qualidade.
- Interface principal SwiftUI refeita com NavigationStack, materiais nativos, ScrollView e botao de voz animado.
- Teclado compacto com acao principal `Transformar`, seletor Auto/Curta/Completa e indicador de energia animado.
- Icones e imagem de orbe no estilo Siri/Liquid Glass.
- Projeto gerado por XcodeGen.

O build atual compila e foi instalado em um iPhone 16 Pro Max conectado usando assinatura de desenvolvimento local.

## Fluxo atual do teclado

Por causa das restricoes praticas do iOS em extensoes de teclado, a versao atual evita usar microfone diretamente dentro da extensao. A tentativa anterior fazia o teclado fechar no WhatsApp.

Fluxo atual:

1. No WhatsApp, toque no campo de mensagem.
2. Dite ou digite algo como:

```text
voz mcp responda dizendo que eu vou falar com ele pela manha, de boa noite, e diga que eu preciso do codigo do produto amanha cedo
```

3. Troque para o teclado `Voz MCP`.
4. Toque em `Transformar`.
5. O teclado apaga o comando e insere a mensagem final no mesmo campo.

Tambem ha um botao `voz mcp`, que coloca `voz mcp ` no campo para facilitar o inicio.

## O que o usuario quer de verdade

O usuario quer uma experiencia parecida com apps como `Typeless: teclado de voz AI`, mas usando IA local:

- Interface extremamente limpa, com cara de iOS, nao Android.
- Teclado bonito, direto, sem abas, sem muitos botoes, sem poluicao.
- Um botao/orbe vivo no estilo nova Siri/Liquid Glass.
- Geracao dentro do WhatsApp sem sair da conversa.
- Interpretacao inteligente de comandos falados.
- Respostas curtas, medias ou longas de acordo com o pedido.
- Exemplo: `escreva uma receita completa de bolo de fuba` deve gerar ingredientes, modo de preparo, rendimento e dicas, nao tres linhas.
- Exemplo: `responda dizendo que vou falar com ele pela manha, de boa noite, e diga que preciso do codigo do produto amanha cedo` deve virar uma mensagem natural e completa.
- Selecionar entre Apple Foundation Models e Gemma 4 local, se tecnicamente viavel.

## Limitacoes importantes do iOS

- Um teclado de terceiros nao consegue ler a conversa inteira do WhatsApp.
- Um teclado so consegue interagir com o texto no campo ativo via `textDocumentProxy`.
- Usar microfone diretamente em extensao de teclado pode ser instavel ou bloqueado pelo sistema. Nesta maquina, o codigo compilou, mas no iPhone o teclado fechava em runtime.
- Outro app no iPhone nao pode compartilhar automaticamente o modelo Gemma ja baixado, por sandbox.
- Para usar Gemma 4 de verdade neste app, o modelo `.litertlm` precisa ser empacotado/importado pelo proprio Voz MCP e o app precisa linkar o runtime LiteRT-LM para iOS.

## IA local

### Apple Foundation Models

`VozMCPApp/DraftGenerator.swift` tenta usar:

- `SystemLanguageModel.default`
- `LanguageModelSession`
- `GenerationOptions`

Se o modelo estiver indisponivel, desligado, baixando, responder vazio ou responder abaixo do pedido, o app cai no compositor local.

### Gemma 4

O usuario quer usar Gemma 4 porque ja usa um modelo local desse tipo. Neste Mac foi encontrado:

```text
/Users/adrianoalmeida/.litert-lm/models/gemma4-e4b-litert/model.litertlm
```

Esse arquivo tem cerca de 3.4 GB e nao esta incluido no repositorio.

O proximo caminho tecnico para Gemma e:

1. Adicionar LiteRT-LM Swift ao app iOS.
2. Criar tela/importador para selecionar um `.litertlm` local.
3. Copiar o modelo para o container do app.
4. Expor um `ModelProvider` com opcoes `Apple Foundation Models`, `Gemma 4 LiteRT` e `Fallback local`.
5. Fazer o teclado chamar o mesmo provider de forma segura para extensoes.

## Build

Instale o XcodeGen:

```sh
brew install xcodegen
```

Gere o projeto:

```sh
xcodegen generate
```

Build para dispositivo fisico assinado:

```sh
rm -rf /tmp/VozMCPSignedObj /tmp/VozMCPSignedBuild
xcodebuild -project VozMCP.xcodeproj \
  -target VozMCP \
  -sdk iphoneos \
  OBJROOT=/tmp/VozMCPSignedObj \
  SYMROOT=/tmp/VozMCPSignedBuild \
  DEVELOPMENT_TEAM=73HPGSC9QX \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build
```

Instale em um iPhone conectado:

```sh
xcrun devicectl list devices
xcrun devicectl device install app \
  --device <DEVICE_ID> \
  "/tmp/VozMCPSignedBuild/Debug-iphoneos/Voz MCP.app"
```

Abrir no iPhone:

```sh
xcrun devicectl device process launch \
  --device <DEVICE_ID> \
  com.adrianoalmeida.VozMCP
```

## Arquitetura

- `VozMCPApp/ContentView.swift`: app principal SwiftUI.
- `VozMCPApp/ComposerViewModel.swift`: estado da tela principal, gravacao e geracao.
- `VozMCPApp/DraftGenerator.swift`: motor de escrita, Foundation Models e fallback.
- `VozMCPApp/SpeechCommandRecognizer.swift`: ditado on-device no app principal.
- `KeyboardExtension/KeyboardViewController.swift`: UI e fluxo do teclado.
- `KeyboardExtension/KeyboardSpeechRecognizer.swift`: experimento de speech no teclado; atualmente nao e usado pelo fluxo principal.
- `project.yml`: fonte do projeto XcodeGen.

## Prioridades para o proximo modelo

1. Validar visualmente a nova UI no aparelho e no WhatsApp real.
2. Garantir que o teclado nunca feche ao tocar no botao principal.
3. Ampliar o parser de comandos compostos para mais dominios alem dos exemplos atuais.
4. Implementar provider real para Gemma 4 LiteRT-LM.
5. Adicionar selecao de modelo no app principal.
6. Testar resposta longa, curta e media com casos reais do usuario.

## Referencias usadas

- Apple Custom Keyboard Programming Guide.
- Apple Foundation Models framework.
- Apple Siri AI / Liquid Glass announcements.
- Google LiteRT-LM Swift.
- Google Gemma 4 LiteRT-LM.
