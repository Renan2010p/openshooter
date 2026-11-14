# Arquitetura do Linha de Fogo

O jogo é dividido em **cenas** (o que aparece e onde fica) e **scripts** (como se
comporta). Quase tudo pode ser ajustado no editor do Godot sem tocar em código.

```
linha-de-fogo/
├── scenes/
│   ├── main.tscn              raiz: troca entre menu e partida
│   ├── game/world.tscn        a partida (mapa + jogadores + sistemas + HUD)
│   ├── maps/bairro.tscn       o mapa
│   ├── props/                 casas, galpão, árvore, carro, poste, banco, cerca...
│   ├── player/
│   │   ├── player.tscn        jogador (corpo, hitbox, câmera, armas, IA)
│   │   ├── avatar.tscn        boneco em blocos
│   │   └── view_arms.tscn     braços em primeira pessoa
│   ├── weapons/               modelo 3D de cada arma
│   ├── fx/                    rastro de bala, impacto, explosão, mina no chão
│   └── ui/
│       ├── hud.tscn           interface da partida
│       ├── main_menu.tscn     menu (mapa girando + telas)
│       ├── screens/           uma cena por tela do menu
│       └── hotbar_slot / server_row / pause_menu
├── resources/
│   ├── weapons/*.tres         ficha de cada arma (WeaponData)
│   ├── ui/theme.tres          visual de botões, painéis e textos
│   ├── environments/day.tres  céu, luz ambiente e névoa
│   └── materials/, textures/
├── scripts/
│   ├── autoload/              Config (opções), Net (rede LAN), Sfx (sons)
│   ├── core/                  Block, BlockBaker, BakedModel
│   ├── game/                  World, Combat, MineManager, MatchManager, GameMap
│   ├── player/                Player, WeaponHolder, BotBrain, Avatar
│   ├── weapons/               WeaponData, WeaponDB
│   ├── fx/                    scripts dos efeitos
│   └── ui/                    Hud, Crosshair, Scoreboard, MainMenu, telas...
├── shaders/scope.gdshader     luneta do Fuzil
└── audio/                     efeitos sonoros (.wav)
```

## O bloco `Block`

Tudo o que é geometria (mapa, props, armas, boneco) é feito de nós **Block**:
uma caixa, cilindro ou esfera com **tamanho, cor, metal, aspereza, brilho e
colisão** editáveis no Inspetor.

- **No editor**, cada bloco se desenha sozinho.
- **No jogo**, o mapa (`GameMap`), as armas (`BakedModel`) e o boneco (`Avatar`)
  juntam os blocos com o `BlockBaker`. Isso dá **um mesh e uma colisão só**,
  com poucos draw calls e FPS alto mesmo com centenas de blocos.
- Um bloco solto, fora desses lugares, se desenha e cria a própria colisão
  sozinho.

Para criar um bloco no editor: *Adicionar Nó → Block*.

## Receitas

**Mexer no mapa.** Abra `scenes/maps/bairro.tscn`.
- Para adicionar algo, coloque Blocks ou arraste cenas de `scenes/props/` para
  dentro de `Geometry` (qualquer subpasta).
- `Spawns`: cada Marker3D é um ponto de nascimento.
- `Waypoints`: pontos por onde os bots andam.
- `Sun` e `WorldEnvironment` controlam a luz e o céu.

**Criar um prop novo.** Crie uma cena com raiz `Node3D`, monte com Blocks, salve
em `scenes/props/` e arraste para o mapa.

**Mudar uma arma.** Abra `resources/weapons/<arma>.tres` no Inspetor: dano,
cadência, pente, imprecisão, recuo, luneta, som, modelo e posição em primeira
pessoa. Para mudar o visual, edite `scenes/weapons/<arma>.tscn`. O `Muzzle`
marca a ponta do cano.

**Adicionar uma arma.**
1. Crie o modelo em `scenes/weapons/`, com raiz `BakedModel` e um Marker3D chamado `Muzzle`.
2. Crie a ficha `.tres` (Novo Recurso → `WeaponData`).
3. Coloque-a no fim da lista `ALL` em `scripts/weapons/weapon_db.gd`.

A barra de armas e as teclas se ajustam sozinhas (até 6 teclas, depois use a
rodinha do mouse).

**Mudar o boneco.** Edite `scenes/player/avatar.tscn`. Blocos com `tint` =
Shirt, Pants ou Skin recebem as cores do Armário. A arma fica presa em
`ArmR/HandSocket`.

**Mudar o HUD ou o menu.** Abra `scenes/ui/hud.tscn` ou as telas em
`scenes/ui/screens/`. Os nós usados pelos scripts têm nome único (o `%` no
editor), então podem ser movidos para qualquer lugar da árvore, desde que o
nome continue o mesmo. Cores, fontes e estilos ficam em
`resources/ui/theme.tres` (variações: TitleLabel, HudBig, Card, MenuBtn,
BigButton, HotbarSlot...).

**Ajustar jogabilidade.** Os valores aparecem no Inspetor de cada nó:
- `Player`: velocidades, pulo e gravidade
- `BotBrain`: reação, erro de mira e alcance de visão
- `Combat`: tempo para renascer
- `MineManager`: raio e dano das minas
- `MatchManager`: abates para vencer o duelo

## Rede

- Quem cria a partida é o **servidor** (ENet, porta 24540/UDP).
- A partida fica sempre em `/root/Main/World` e tem o mesmo caminho em todos os
  computadores. Os RPCs dependem disso.
- **Movimento:** cada jogador manda a própria posição (`Player.sync_state`, 30×/s).
- **Tiros e dano:** o servidor confere em `Combat._server_fire` (raio contra as
  hitboxes `Body` e `Head`) e espalha o resultado com `fx_shot`, `on_hit`,
  `on_kill` e `on_respawn`.
- **Bots:** rodam só no servidor.
- **Descoberta:** o servidor anuncia a partida por broadcast UDP na porta 24541
  (`Net`). Partidas privadas mandam só um hash do código.

**Camadas de física:**

| Camada | Uso |
|---|---|
| 1 | mundo |
| 2 | corpo dos jogadores (só colide com o mundo) |
| 3 | hitboxes (só raios de tiro) |

**Camadas visuais:**

| Camada | Uso |
|---|---|
| 1 | normal |
| 2 | corpo do próprio jogador (escondido da câmera dele) |
| 3 | arma em primeira pessoa |
