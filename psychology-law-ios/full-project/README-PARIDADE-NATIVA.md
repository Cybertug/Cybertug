# SimulaPro para iPhone: atualização nativa

## Base

Projeto iOS local `psychology-law-ios/full-project`, confirmado nesta tarefa. O ZIP enviado contém somente arquivos web, sem código iOS nem bancos de questões dos demais exames. Esta entrega preserva o login, o registro de uso e os quatro simuladores nativos já presentes na cópia local.

## Comparação e implementação

| Recurso web | Antes no iOS | Nesta entrega |
|---|---|---|
| Overview | Apenas catálogo | Tela SwiftUI com questões respondidas, sessões, provas completas e média das últimas dez tentativas |
| Filtro e tendência | Ausentes | Filtro por exame praticado e gráfico nativo de pontuação |
| Plano de estudos | Ausente | Barras calculadas pelo histórico e tamanho do banco informado pela API |
| Biblioteca | Quatro módulos fixos | Lista da API `/api/customer/dashboard`, busca e abertura dos módulos iOS compatíveis |
| Loja | Assinaturas nativas | Aba Store em SwiftUI com os quatro simuladores; preços vêm da Apple |
| Exames | Quatro simuladores nativos | Os quatro continuam com interface nativa; a área de conta não abre páginas web |
| Questões GC | Download de uma página que agora redireciona para a conta | As 242 questões GC existentes foram empacotadas no app e podem ser carregadas sem rede |
| Visual | Gradiente azul/roxo | Azul marinho, fundo claro e nome SimulaPro |

O painel carrega `/api/customer/dashboard` e `/api/perf/summary` usando a sessão nativa existente. Se falhar, mostra uma mensagem e permite recarregar puxando a tela para baixo.

**Limite de paridade:** o site lista mais exames do que o projeto iOS contém. A biblioteca exibe os exames da conta, mas só abre os quatro módulos existentes: Florida Psychology Laws & Rules, PMI-CP, GC Business & Finance e FE Mechanical. Outros exames ficam marcados como indisponíveis no iPhone. O ZIP não contém a implementação nativa nem as questões necessárias para criá-los. A biblioteca web e as assinaturas StoreKit usam fontes de acesso distintas; a posse de um exame no site ainda não desbloqueia sua versão nativa automaticamente. Os preços web diferem dos produtos StoreKit e não foram copiados para o app.

## Verificações

- Os oito arquivos JavaScript de referência passaram em `node --check`.
- Todos os arquivos Swift referenciados em `project.pbxproj` existem, inclusive `AccountDashboardView.swift`.
- A nova área de conta não usa WebView. O código anterior de GC/FE ainda usa um WKWebView sem interação para desenhar diagramas SVG dentro da tela nativa.
- O banco GC incluído foi validado com 242 questões e 242 IDs únicos; o teste de simulador confirma seu carregamento no cache do app.
- Esta máquina Windows não tem Xcode. O app **não foi compilado nem executado** no simulador aqui. A pasta `Tests` original não integra um target de testes Xcode.

## Build e teste no Mac

1. Abra `PsychologyLawNative.xcodeproj` no Xcode, selecione o esquema **PsychologyLawNative** e um simulador de iPhone.
2. Faça uma verificação de build sem assinatura no Terminal, dentro desta pasta:

   ```sh
   xcodebuild -project PsychologyLawNative.xcodeproj -scheme PsychologyLawNative -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
   ```

3. Use **Product > Run**. Entre com uma conta de teste e confira Overview, filtros, métricas, progresso, busca na biblioteca, Store e recarregamento por gesto.
4. Em **My exams**, abra cada módulo nativo com uma assinatura de teste. Confira também retorno ao painel e logout.
5. Para testar no iPhone físico, selecione sua equipe em **Signing & Capabilities** e confirme o bundle ID `com.simulapro.psychologylaw`.

## Apple e publicação

Existe uma configuração antiga de navegador chamada “Apple App Store Connect - Psychology Law”, mas nenhum login Apple ativo foi confirmado nesta tarefa. O desenvolvimento e o build local não exigem esse login. Para consultar o registro do app ou enviar um build, use sua sessão em [App Store Connect](https://appstoreconnect.apple.com/). Uma chave da API do App Store Connect pode automatizar acesso conforme a permissão escolhida; ela deve ficar fora do projeto e do chat.

Nenhum build foi enviado ao TestFlight ou à App Store. Antes de submeter, confira a diferença entre os preços do site e os produtos StoreKit, o acesso aos exames e a experiência em um iPhone real.
