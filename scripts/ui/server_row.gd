class_name ServerRow
extends PanelContainer
## Uma linha da lista de servidores (scenes/ui/server_row.tscn).

signal join_pressed(ip: String)

var _ip := ""


func _ready() -> void:
	%Join.pressed.connect(func(): join_pressed.emit(_ip))


func setup(ip: String, info: Dictionary) -> void:
	_ip = ip
	%ServerName.text = str(info.get("name", "Servidor"))
	%Details.text = "%s  •  %d/%d jogadores  •  %d bots" % [ip, int(info.get("players", 0)), int(info.get("max", 0)), int(info.get("bots", 0))]
