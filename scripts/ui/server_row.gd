class_name ServerRow
extends PanelContainer
## One row of the server list (scenes/ui/server_row.tscn): map picture,
## server name, map and address, players and bots, and the Join button.

signal join_pressed(ip: String)

var _ip := ""


func _ready() -> void:
	UiMotion.attach(%Join)
	%Join.pressed.connect(func(): join_pressed.emit(_ip))


func setup(ip: String, info: Dictionary) -> void:
	_ip = ip
	%ServerName.text = str(info.get("name", "Server"))
	%Details.text = "%s · %s" % [info.get("map", "?"), ip]
	%Count.text = "%d / %d" % [int(info.get("players", 0)), int(info.get("max", 0))]
	var bots := int(info.get("bots", 0))
	%Bots.text = "+%d BOT%s" % [bots, "" if bots == 1 else "S"] if bots > 0 else "NO BOTS"
	var picture := "res://assets/ui/maps/%s.png" % str(info.get("map_id", ""))
	%Thumb.texture = load(picture) if ResourceLoader.exists(picture) else null
