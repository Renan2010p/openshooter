extends MenuScreen
## Tela inicial: Jogar, Armário, Configurações, Estatísticas e Sair.


func _ready() -> void:
	bind_button(%Play, func(): menu.show_screen("Modes"))
	bind_button(%Locker, func(): menu.show_screen("Locker"))
	bind_button(%Settings, func(): menu.show_screen("Settings"))
	bind_button(%Stats, func(): menu.show_screen("Stats"))
	bind_button(%Quit, func(): menu.request_quit())


func enter(_arg: Variant) -> void:
	%PlayerName.text = Config.player_name
