# Atualizações do Combate Tático

O jogo exportado verifica `https://github.com/rocksted21/rpgbolivia/releases/latest/download/version.json` a cada abertura. O editor permanece local. O formato é o mesmo do Raid Alien: `patch_id`, `version`, `size`, `download`, `sha256`, `gz` e `parts`.

O PCK completo é dividido em blocos gzip. Após baixar todas as partes, o jogo confere tamanho e SHA-256, salva em `user://combate_update/` e reinicia. O próximo processo monta o PCK antes dos autoloads. Se a plataforma não conseguir reiniciar automaticamente, a atualização entra na próxima abertura. Sem internet ou com download inválido, o jogo continua com o conteúdo local. Duas tentativas de inicialização sem chegar ao menu desativam o pacote problemático e restauram o jogo instalado.

## Gerar uma atualização

Na raiz do projeto, execute:

```powershell
.\tools\build_update.ps1 -Version '0.1.1'
```

Use `-Godot 'C:\caminho\godot.exe'` para outra instalação. O script cria `build/update-<patch_id>/patch.pck`, as partes compactadas e `version.json`, sem alterar permanentemente a versão do projeto. Cada release deve ter um `patch_id` crescente. O PCK contém os JSON dos assets também.

Crie uma release **publicada**, sem marcar como prerelease, com a tag `combate-<patch_id>` e anexe **version.json e todas as partes**. Marque essa release como a mais recente. O PCK inteiro fica disponível localmente para conferência; o atualizador usa apenas as partes. Não troque arquivos de uma release existente; gere outra atualização para manter URLs e conteúdo consistentes.

O destino precisa permitir downloads públicos sem login: releases de um repositório privado não funcionam no aparelho dos jogadores. Não coloque tokens do GitHub no jogo. Se o código precisar continuar privado, use um repositório público separado para distribuição e ajuste `BASE_URL`, a validação de `base_url` no atualizador e o endereço gerado pelo script de build.

## Instaladores mínimos

Gere um projeto separado, sem os assets ou autoloads do jogo:

```powershell
node tools/release/prepare_launcher.mjs
```

Exporte os presets do projeto `build/launcher-project`. Windows incorpora o carregador no EXE; Android inclui somente ARM64; macOS usa app universal e DMG compactado. Os executáveis ainda contêm o motor Godot. O Windows também pode ser distribuído em ZIP para reduzir o download sem modificar o executável.

Na primeira abertura o carregador baixa e valida o PCK. Antes de abrir o menu, restaura as configurações de `update/runtime.cfg` e instancia os serviços de áudio e rede. Os scripts resolvem esses serviços pela árvore de nodes, permitindo carregar o conteúdo dinamicamente. Em aberturas seguintes, verifica o JSON novamente e permite jogar offline com o pacote já salvo. O menu confirma o início bem-sucedido para evitar repetir uma atualização defeituosa.

`tools/release/macos.yml` contém o job para gerar e verificar o DMG em um runner macOS. Ele usa `launcher.zip` e `release-tag.txt` na raiz do repositório de distribuição. O app recebe assinatura ad hoc; não há certificado de distribuição nem notarização Apple configurados.

## Exportação completa (opcional)

Exporte o preset Windows ou Android no Godot. A primeira instalação contém o jogo completo e o atualizador. No Windows, distribua o `.exe` e seu `.pck` juntos; depois basta publicar as releases de conteúdo. Android já tem permissão de internet no preset. Mudanças no executável, plugins nativos, autoloads e configurações do projeto exigem uma nova instalação; o PCK atualiza scripts, cenas e assets.

O projeto é versionado nesta pasta (`combate/`), no repositório `https://github.com/rocksted21/rpgbolivia`. Consulte o [README principal](../README.md) para começar a desenvolver.
