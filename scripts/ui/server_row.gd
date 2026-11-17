class_name ServerRow
extends PanelContainer
## One row of the server list (scenes/ui/server_row.tscn).

signal join_pressed(ip: String)

var _ip := ""


func _ready() -> void:
	UiMotion.attach(%Join)
	%Join.pressed.connect(func(): join_pressed.emit(_ip))


func setup(ip: String, info: Dictionary) -> void:
	_ip = ip
	%ServerName.text = str(info.get("name", "Server"))
	%Details.text = "%s  •  %s  •  %s  •  %d/%d players  •  %d bots" % [ip, info.get("mode_name", "Normal"), info.get("map", "?"), int(info.get("players", 0)), int(info.get("max", 0)), int(info.get("bots", 0))]
