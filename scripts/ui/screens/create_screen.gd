extends MenuScreen
## Create a server for a game mode: name, mode, map, bots, duration and slots.
## The mode and map start from the lobby's choice (Config.selected_*);
## changing the mode here changes the lobby's choice too. Opened with the
## argument "private" (from the Private screen) it creates a private server.

const DURATIONS := [3, 5, 10, 15]
## ID used by the "Random" item in the map dropdown.
const RANDOM_ID := 1000

var _private := false
var _code := ""


func _ready() -> void:
	for m in DURATIONS:
		%Duration.add_item("%d minutes" % m, m)
	for i in ModeDB.count():
		%Mode.add_item(ModeDB.get_mode(i).display_name, i)
	%Mode.item_selected.connect(func(_i): _on_mode_changed())
	%Map.add_item("Random", RANDOM_ID)
	for i in MapDB.count():
		%Map.add_item(MapDB.display_name(i), i)
	%Map.item_selected.connect(func(_i): _update_description())
	bind_button(%Create, _create)
	bind_button(%Back, func(): menu.show_screen("Private" if _private else "Browser"))


func enter(arg: Variant) -> void:
	_private = str(arg) == "private"
	%ServerName.text = "%s's server" % Config.player_name
	%Duration.select(1)
	%Mode.select(%Mode.get_item_index(Config.selected_mode))
	var map_id := Config.selected_map if Config.selected_map >= 0 else RANDOM_ID
	%Map.select(%Map.get_item_index(map_id))
	_code = "%05d" % (randi() % 100000)
	%CodeLabel.text = "Private code: %s" % _code
	%CodeLabel.visible = _private
	_apply_mode_rules()
	_update_description()


func _mode_index() -> int:
	return %Mode.get_selected_id()


func _is_duel() -> bool:
	return ModeDB.get_mode(_mode_index()).id == "duel"


func _on_mode_changed() -> void:
	Config.selected_mode = _mode_index()
	Config.save_cfg()
	_apply_mode_rules()


## Title and slot limits follow the mode: a Duel is one versus one.
func _apply_mode_rules() -> void:
	var mode := ModeDB.get_mode(_mode_index())
	var duel := _is_duel()
	%Title.text = "CREATE %sSERVER — %s" % ["PRIVATE " if _private else "", mode.display_name.to_upper()]
	%Bots.max_value = 1 if duel else 8
	%Bots.value = 1 if duel else 3
	%MaxPlayers.value = 2 if duel else 10
	%MaxPlayers.editable = not duel
	%DuelHint.visible = duel


func _update_description() -> void:
	var id: int = %Map.get_selected_id()
	%MapDescription.text = "A different map every time." if id == RANDOM_ID else MapDB.info(id).description


func _create() -> void:
	var map: int = %Map.get_selected_id()
	if map == RANDOM_ID:
		map = MapDB.random_index()
	menu.request_host({
		"name": (%ServerName.text as String).substr(0, 32),
		# Server type: Duel servers end at 5 kills (MatchManager.is_duel_lobby).
		"mode": "duel" if _is_duel() else ("private" if _private else "normal"),
		"mode_idx": _mode_index(),
		"map": map,
		"private": _private,
		"code": _code if _private else "",
		"bots": int(%Bots.value),
		"minutes": %Duration.get_selected_id(),
		"max": int(%MaxPlayers.value),
		"aim_assist": %AllowAimAssist.button_pressed,
	})
