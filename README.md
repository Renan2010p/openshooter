# Linha de Fogo

FPS em 3D com multiplayer em rede local (LAN), feito em Godot 4.7 (renderizador
Compatibility, roda em placa de vídeo fraca).

## Jogar

```sh
godot-fedora --path ~/Projetos/Jogos/linha-de-fogo
godot-fedora -e --path ~/Projetos/Jogos/linha-de-fogo   # abrir no editor
```

**Jogar → modo:**
- **Normal**: lista os servidores da rede automaticamente. Também dá para criar um servidor ou conectar por IP.
- **Privado**: quem cria recebe um **código de 5 números**. Os outros digitam o código e o jogo acha o servidor na rede.
- **Apenas Duelos**: 1 contra 1, vence quem fizer 5 abates primeiro.

Ao criar um servidor, dá para colocar **bots** (até 8) para jogar sozinho ou completar a partida.

Rede: porta **24540/UDP** (jogo) e **24541/UDP** (descoberta). Se o firewall
bloquear o broadcast, use "IP direto".

## Controles

| Tecla | Ação |
|---|---|
| WASD | andar |
| Mouse | mirar |
| Botão esquerdo | atirar / colocar mina |
| Botão direito | luneta do Fuzil |
| ESPAÇO | pular |
| SHIFT | correr |
| CTRL ou C | agachar (mais precisão) |
| R | recarregar |
| 1–6 ou rodinha | trocar arma |
| TAB | placar |
| ESC | pausa / sair da partida |

## Armas

| # | Arma | Dano | Observação |
|---|---|---|---|
| 1 | Faca | 55 | corpo a corpo |
| 2 | Pistola | 26 | 12 balas, precisa |
| 3 | AK-47 | 22 | automática, 30 balas |
| 4 | Escopeta | 9×13 | forte de perto, fraca de longe |
| 5 | Fuzil | 80 | luneta, tiro na cabeça mata |
| 6 | Mina | até 150 | arma em 1,5 s, explode quando um inimigo pisa perto |

Tiro na cabeça multiplica o dano (×2 a ×2,2).

## Desempenho

Em **Configurações → Qualidade gráfica**:

| Qualidade | Resolução 3D | Sombras | Névoa | Antisserrilhado |
|---|---|---|---|---|
| Baixa | 60% | não | não | não |
| Média (padrão) | 80% | sim, curtas | sim | não |
| Alta | 100% | sim | sim | MSAA 2× |

"Mostrar FPS" liga um contador no canto da tela.

Otimizações internas:
- **Mapa:** todo o desenho de cor sólida vira um único mesh, com cores por vértice, e toda a colisão fica num único StaticBody.
- **Bonecos e armas:** um mesh por parte móvel.
- **Luzes de clarão:** ficam desligadas de verdade fora do tiro. No renderizador Compatibility, cada luz visível redesenha os objetos que toca.
- **Sombras:** mapa de 1024 e sem filtro suave.
- **HUD:** ranking, relógio e placar são atualizados 10× por segundo.

Benchmark com 8 bots em Intel HD 4400: `--host=normal --bots=8 --autoplay --bench=15 --quality=1`.

## Como a rede funciona

- Quem cria a partida é o **servidor**: ele confere os tiros (raio contra as hitboxes de corpo e cabeça), o dano, as mortes, as minas, os bots e o relógio.
- Cada jogador manda a própria posição 30 vezes por segundo.
- O servidor anuncia a partida por broadcast UDP a cada segundo. Partidas privadas só mostram um hash do código.

## Testes

```sh
# duas janelas que se enfrentam sozinhas pela rede
godot-fedora --path . -- --host=duel --bots=0 --autoplay &
godot-fedora --path . -- --join=127.0.0.1 --autoplay
```

Outras opções: `--host=normal|private|duel --bots=N`, `--join=IP --code=12345`,
`--name=Nome`, `--browse=normal|duel|locker`, `--shot=arquivo.png --wait=segundos`.
