# addons/rl_projects

Logo animada da RL PROJECTS para jogos Godot 4.

- `rl_intro.tscn` — cena de boot: toca a logo e abre `rl_projects/next_scene`.
- `rl_splash.gd` — `RLProjectsSplash`, o nó da logo (sinal `finished`, pulável).
- `rl_intro*.ogg` — as 8 trilhas (nebula, aurora, cathedral, odyssey, lullaby, abyss, dawn, horizon); cada vez que o jogo abre sorteia uma diferente da última (ou fixe uma em `soundtrack`).
- `galaxy_data.gd` — estrelas da galáxia (gerado por `brand/tools/rl_brand.py`).

Instalar/atualizar num jogo: `python3 brand/tools/install_godot.py <pasta-do-jogo>`.
Rodar o jogo com argumentos (`godot --path . -- --qualquer`) pula a intro.

Fontes: Poppins (SIL OFL 1.1, ver `fonts/OFL.txt`).
