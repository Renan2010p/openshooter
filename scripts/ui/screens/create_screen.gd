extends MenuScreen
## Criar servidor (Normal, Privado ou Duelo).

const DURATIONS := [3, 5, 10, 15]

var mode := "normal"
var _code := ""


func _ready() -> void:
	for m in DURATIONS:
		%Duration.add_item("%d minutos" % m, m)
	bind_button(%Create, _create)
	bind_button(%Back, func(): menu.show_screen("Private" if mode == "private" else "Browser", null if mode == "private" else mode))


func enter(arg: Variant) -> void:
	mode = str(arg) if arg != null else "normal"
	var duel := mode == "duel"
	%ServerName.text = "Servidor de %s" % Config.player_name
	%Bots.max_value = 1 if duel else 8
	%Bots.value = 1 if duel else 3
	%Duration.select(1)
	%MaxPlayers.value = 2 if duel else 10
	%MaxPlayers.editable = not duel
	_code = "%05d" % (randi() % 100000)
	%CodeLabel.text = "Código Privado: %s" % _code
	%CodeLabel.visible = mode == "private"
	%DuelHint.visible = duel


func _create() -> void:
	menu.request_host({
		"name": (%ServerName.text as String).substr(0, 32),
		"mode": mode,
		"private": mode == "private",
		"code": _code if mode == "private" else "",
		"bots": int(%Bots.value),
		"minutes": %Duration.get_selected_id(),
		"max": int(%MaxPlayers.value),
	})
