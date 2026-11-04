# Online do Combate Tático

Adaptação do transporte do Raid Alien: lista HTTP de salas, WebSocket binário,
relay sem simulação e dono como autoridade do combate. As salas usam o identificador
`combate-tatico`, em um servidor separado. O Raid Alien não foi alterado.

## Jogar localmente

Instale Node.js e, nesta pasta, execute:

```powershell
npm ci
npm start
```

Abra duas instâncias do jogo e escolha **Online**. A conexão é automática.
Você também pode executar `iniciar-local.ps1` para instalar as dependências ausentes
e iniciar o relay. Mantenha o terminal aberto enquanto joga.
Informe seu nome; crie uma sala numa instância e toque em **ENTRAR** na lista da outra.
Com pelo menos dois jogadores, o dono pode iniciar. Até quatro pessoas dividem os
cinco heróis contra a IA. Na sala, cada um toca nos heróis que quer controlar (toque de novo libera);
heróis livres vão para quem tem menos. A dica informa quem joga a cada turno.

Para testes em outro computador na mesma rede, configure a variável de ambiente
`COMBATE_RELAY=ws://IP-DO-COMPUTADOR:8787` antes de iniciar o jogo.
Pode ser necessário permitir a porta TCP 8787 no firewall do computador servidor.

## Publicar para jogar pela internet

Publicado no Fly.io (mesma conta do Raid Alien) como `combate-tatico-relay`, região `gru`:
`wss://combate-tatico-relay.fly.dev`, já configurado em `net/net_tuning.gd`.
Para atualizar o servidor, rode `fly deploy --ha=false` nesta pasta.
Para testar contra ele, defina `COMBATE_RELAY=wss://combate-tatico-relay.fly.dev` antes de
`tests/test_online.gd` ou `tests/test_online_pair.gd`. A tela dos jogadores mostra
apenas a lista de salas: não exibe endereço de servidor nem códigos de sala.
O endereço é configuração do projeto em `net/net_tuning.gd`; em desenvolvimento,
a variável de ambiente `COMBATE_RELAY` permite substituí-lo.

Há Dockerfile e modelo `fly.toml`, seguindo o Raid Alien, com região `gru` (São Paulo).
Para Fly.io: instale o CLI, entre na sua conta, escolha um nome disponível para o app,
ajuste `app` no fly.toml e rode `fly apps create NOME` e `fly deploy --ha=false`.
Depois configure o endereço publicado em `net/net_tuning.gd`, com TLS ativado,
e gere a distribuição do jogo. Em desenvolvimento, use `COMBATE_RELAY=wss://NOME.fly.dev`.
A hospedagem pode gerar cobrança.
Use uma única máquina: as salas ficam em memória e somem ao reiniciar o relay.

Não é necessário abrir porta no roteador dos jogadores ao usar um relay público.
O servidor fica hospedado; o dono precisa manter o jogo aberto durante o combate.

## Escopo desta versão

- Cooperativo, 2–4 pessoas; cada um escolhe seus heróis na sala, inimigos pela IA.
- O dono valida as escolhas: ninguém toma herói de outro e só inicia quando todos têm pelo menos um.
- Criar, listar, atualizar, entrar pela lista, cancelar, sair e iniciar juntos.
- Dono valida a posse do herói, turno, destino e habilidade; convidados recebem estado e animações.
- Durante o combate novas entradas ficam bloqueadas. Convidado saindo transfere seus heróis ao dono.
- Se o dono sair ou a conexão cair, volta à lista. Não há reconexão, migração de dono,
  contas, voz, versus ou salvamento da partida online nesta versão.

## Verificação

Com `PORT=18787` no ambiente do relay, execute na raiz do jogo:

```powershell
godot --headless --path . --script tests/test_online.gd
```

O teste conecta dois clientes reais, verifica descoberta, nomes, início, autoridade,
ação do convidado, snapshots, bloqueio de entrada e saída. Os testes existentes
`tests/test_battle.gd` e `tests/test_audio.gd` continuam disponíveis.

Para verificar também as duas apresentações completas do combate, execute
`tests/test_online_pair.gd` em dois processos Godot simultâneos, um com `-- host`
e outro com `-- guest` após os argumentos do script. Esse teste usa a porta 18787
e verifica movimento, animações e igualdade do estado ao final.

Referência do transporte Godot: https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html
