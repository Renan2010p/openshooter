class_name MenuScreen
extends Control
## Base das telas do menu. O [MainMenu] preenche `menu` e chama enter()/leave().

var menu: MainMenu


## Chamado ao abrir a tela. `arg` vem de MainMenu.show_screen().
func enter(_arg: Variant) -> void:
	pass


## Chamado ao sair da tela.
func leave() -> void:
	pass


## Liga o botão ao Callable e toca o clique.
func bind_button(button: BaseButton, action: Callable) -> void:
	button.pressed.connect(func():
		Sfx.play("switch", -8.0)
		action.call())
