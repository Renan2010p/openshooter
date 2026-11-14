extends MenuScreen
## Seleção do modo de jogo.


func _ready() -> void:
	bind_button(%Normal, func(): menu.show_screen("Browser", "normal"))
	bind_button(%Private, func(): menu.show_screen("Private"))
	bind_button(%Duel, func(): menu.show_screen("Browser", "duel"))
	bind_button(%Back, func(): menu.show_screen("Home"))
