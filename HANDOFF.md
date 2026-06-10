# Handoff para continuar o Voz MCP

Este arquivo existe para outro modelo/engenheiro entender rapidamente o que foi pedido, o que foi tentado e onde o projeto falhou.

## Pedido original

O usuario quer um app iOS/teclado que funcione dentro do WhatsApp sem sair da conversa. A ideia e:

- Abrir uma conversa.
- Tocar no campo de mensagem.
- Acionar o teclado/app.
- Falar um comando.
- A IA local do iPhone gerar a mensagem.
- Inserir automaticamente o texto final no campo.
- O usuario so revisa e envia.

Ele citou como inspiracao o app `Typeless: teclado de voz AI` e pediu algo com acabamento Apple, estilo Siri/Liquid Glass.

## Feedback critico do usuario

O usuario rejeitou fortemente as versoes anteriores por:

- Interface parecendo Android e nao iOS.
- Tela cortada, nao responsiva, fontes ruins e conteudo inacessivel.
- Teclado poluido, com botoes demais.
- Botao de microfone/orbe ruim e estatico.
- Botao do teclado fechando o WhatsApp/teclado.
- Campo interno no teclado inutil, porque exigia copiar/colar.
- Geracao de IA fraca, sem entender pedidos compostos.
- Receita de bolo de fuba vindo curta/rasa quando deveria ser completa.
- Falta de Gemma 4 local real.
- Icone anterior feio/inadequado.

## Estado atual apos a ultima revisao

### App principal

Foi refeito novamente em `VozMCPApp/ContentView.swift` com:

- `NavigationStack` nativo.
- Fundo claro/escuro usando `systemGroupedBackground` e materiais do sistema.
- Botao de voz animado menor e mais iOS.
- Atalhos horizontais discretos para exemplos criticos: boa noite, codigo, receita, saudade e desculpa.
- Seletor de modelo `Auto`, `Apple` e `Local` no painel do pedido.
- ScrollView para evitar tela cortada.
- Campo principal e resultado.
- Menos texto tecnico visivel e controles com raio menor.

Ainda precisa de validacao visual real no aparelho.

### Teclado

Foi refeito em `KeyboardExtension/KeyboardViewController.swift`.

Mudanca importante: o microfone direto dentro do teclado foi removido do fluxo principal, porque a tentativa anterior fechava o teclado no WhatsApp. Agora o fluxo estavel e:

1. Usuario dita/escreve o comando no campo do app host.
2. Teclado le `documentContextBeforeInput`.
3. Teclado apaga o comando.
4. Teclado insere a resposta.

Isso imita o comportamento que a primeira versao fazia melhor, mas ainda precisa ficar mais bonito e mais poderoso.

Na revisao mais recente o teclado ficou mais compacto:

- Topo com `Voz MCP`, apagar e trocar teclado.
- Status curto.
- Indicador de energia pequeno e animado.
- Botao principal `Transformar`.
- Segmented control `Auto`, `Curta`, `Completa`.
- Botao discreto `voz mcp`.

### IA

`DraftGenerator.swift` tenta usar `FoundationModels` quando disponivel.

O app principal passa `ModelPreference` no `DraftRequest`:

- `automatic`: tenta Apple Foundation Models e cai no compositor local.
- `apple`: prefere Foundation Models e explica quando caiu para o local.
- `local`: usa apenas `SmartLocalComposer`.

Tambem ha fallback local estruturado com:

- `DraftIntentAnalyzer` para detectar tipo, tamanho, assunto e termos obrigatorios.
- `DraftQualityGate` para descartar respostas rasas ou incompletas do modelo.
- `SmartLocalComposer` para construir respostas locais melhores quando o modelo nao atende.

Hoje ele cobre melhor:

- Receita de bolo de fuba curta/completa.
- Boa noite + amor.
- Pedido envolvendo codigo do produto pela manha.
- Normalizacao de "ele" para "voce" em respostas direcionadas.
- Comandos compostos com tamanho curto/medio/completo.
- Tom inferido a partir do comando: carinhoso, elegante, direto ou natural.
- Mensagem de saudade sem inverter o sujeito do sentimento.
- Mensagem de desculpa por atraso com fechamento polido.

Foi adicionado `Scripts/ValidateDrafts.swift` para validar exemplos criticos e o parser do teclado:

```sh
swiftc VozMCPApp/DraftGenerator.swift KeyboardExtension/KeyboardCommandParser.swift Scripts/ValidateDrafts.swift -o /tmp/ValidateDrafts
/tmp/ValidateDrafts
```

`KeyboardExtension/KeyboardCommandParser.swift` separa a extracao de comandos da UI do teclado. Ele valida `voz mcp ...`, comandos implicitos que comecam com verbos como `escreva` ou `responda`, e evita tratar texto normal como comando.

Foi adicionada validacao para descartar respostas ruins do modelo quando:

- Receita nao contem ingredientes/modo de preparo.
- Pedido completo recebe texto muito curto.
- Pedido sobre codigo do produto perde essa informacao.
- Pedido de boa noite perde "boa noite".
- Pedido de manha perde "manha/amanha".

## Onde precisa melhorar

### 1. UX do teclado

O teclado precisa ser redesenhado com extremo cuidado:

- Altura adequada.
- Sem submenus.
- Um botao principal vivo.
- Controles secundarios discretos.
- Nada que pareca app Android.
- Tipografia iOS padrao.
- Liquid Glass/materials com bom contraste.
- Acessivel no WhatsApp.

### 2. Voz dentro do teclado

Investigar corretamente como apps como Typeless fazem voz no teclado.

Hipoteses:

- Podem usar extensao com Open Access e APIs de audio de forma que exige configuracao especifica.
- Podem abrir app/overlay proprio.
- Podem usar dictation do sistema e so transformar o texto.
- Podem ter entitlement/arquitetura diferente.

Nao assumir. Testar no aparelho.

### 3. Gemma 4 LiteRT-LM

Existe um modelo no Mac:

```text
/Users/adrianoalmeida/.litert-lm/models/gemma4-e4b-litert/model.litertlm
```

Ele nao esta no repo.

Para usar no iPhone:

- Integrar LiteRT-LM Swift.
- Decidir se o modelo sera bundled ou importado.
- Se bundled, o app ficara enorme.
- Se importado, criar UI de importacao e persistencia no app container.
- Verificar se app extension consegue chamar esse runtime diretamente.

### 4. Prompt e parsing

O usuario fala comandos naturais e longos. O sistema precisa:

- Extrair intencoes.
- Preservar todos os requisitos.
- Entender tamanho pedido.
- Entender tom pedido.
- Construir resposta final pronta para enviar.
- Nunca responder com explicacao do processo.

Exemplo obrigatorio:

```text
responda dizendo que eu vou falar com ele pela manha, deu um boa noite, e diga que eu preciso do codigo do produto amanha cedo
```

Resposta esperada:

```text
Boa noite. Amanha de manha eu falo com voce com calma. Tambem preciso que voce me mande o codigo do produto cedo, para eu conseguir verificar direitinho.
```

### 5. Testes reais

Validar em:

- WhatsApp.
- Notas.
- iMessage.
- Campo vazio.
- Campo com `voz mcp ...`.
- Campo com texto sem trigger.
- Pedido curto.
- Pedido completo.
- Pedido com varias obrigacoes.

## Comandos uteis

Build:

```sh
xcodegen generate
rm -rf /tmp/VozMCPSignedObj /tmp/VozMCPSignedBuild
xcodebuild -project VozMCP.xcodeproj -target VozMCP -sdk iphoneos OBJROOT=/tmp/VozMCPSignedObj SYMROOT=/tmp/VozMCPSignedBuild DEVELOPMENT_TEAM=73HPGSC9QX CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

Instalar:

```sh
xcrun devicectl device install app --device A2894021-74E1-5E6A-A5D3-49F47F856D04 "/tmp/VozMCPSignedBuild/Debug-iphoneos/Voz MCP.app"
```

Abrir:

```sh
xcrun devicectl device process launch --device A2894021-74E1-5E6A-A5D3-49F47F856D04 com.adrianoalmeida.VozMCP
```

## Observacao honesta

Este projeto ainda nao atingiu a experiencia que o usuario quer. Ele deve ser tratado como uma base experimental, nao como produto polido.
