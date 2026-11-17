extends MenuScreen
## Create a server (Normal, Private or Duel): name, map, bots, duration and slots.
## The game mode and the default map come from the lobby (Config.selected_*).

const DURATIONS := [3, 5, 10, 15]
## ID used by the "Random" item in the map dropdown.
const RANDOM_ID := 1000

var mode := "normal"
var _code := ""


func _ready() -> void:
	for m in DURATIONS:
		%Duration.add_item("%d minutes" % m, m)
	%Map.add_item("Random", RANDOM_ID)
	for i in MapDB.count():
		%Map.add_item(MapDB.display_name(i), i)
	%Map.item_selected.connect(func(_i): _update_description())
	bind_button(%Create, _create)
	bind_button(%Back, func(): menu.show_screen("Private" if mode == "private" else "Browser", null if mode == "private" else mode))


func enter(arg: Variant) -> void:
	mode = str(arg) if arg != null else "normal"
	var duel := mode == "duel"
	%ServerName.text = "%s's server" % Config.player_name
	%Bots.max_value = 1 if duel else 8
	%Bots.value = 1 if duel else 3
	%Duration.select(1)
	var map_id := Config.selected_map if Config.selected_map >= 0 else RANDOM_ID
	%Map.select(%Map.get_item_index(map_id))
	%ModeLabel.text = "Mode: %s" % ModeDB.get_mode(_mode_index()).display_name
	%MaxPlayers.value = 2 if duel else 10
	%MaxPlayers.editable = not duel
	_code = "%05d" % (randi() % 100000)
	%CodeLabel.text = "Private code: %s" % _code
	%CodeLabel.visible = mode == "private"
	%DuelHint.visible = duel
	_update_description()


## The lobby's mode, except on Duel servers, which always play Duel.
func _mode_index() -> int:
	if mode == "duel":
		for i in ModeDB.count():
			if ModeDB.get_mode(i).id == "duel":
				return i
	return Config.selected_mode


func _update_description() -> void:
	var id: int = %Map.get_selected_id()
	%MapDescription.text = "A different map every time." if id == RANDOM_ID else MapDB.info(id).description


func _create() -> void:
	var map: int = %Map.get_selected_id()
	if map == RANDOM_ID:
		map = MapDB.random_index()
	menu.request_host({
		"name": (%ServerName.text as String).substr(0, 32),
		"mode": mode,
		"map": map,
		"mode_idx": _mode_index(),
		"private": mode == "private",
		"code": _code if mode == "private" else "",
		"bots": int(%Bots.value),
		"minutes": %Duration.get_selected_id(),
		"max": int(%MaxPlayers.value),
		"aim_assist": %AllowAimAssist.button_pressed,
	})
